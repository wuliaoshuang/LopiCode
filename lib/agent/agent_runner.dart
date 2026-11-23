import 'dart:async';
import 'dart:convert';

import 'package:lopicode/agent/agent_tools.dart';
import 'package:lopicode/agent/chat_client.dart';

sealed class AgentEvent {}

/// 模型正在输出的文字（增量）。
class AssistantDelta extends AgentEvent {
  AssistantDelta(this.text);
  final String text;
}

/// 一轮模型回复结束（[text] 是这一轮的完整文字，可能为空）。
class AssistantMessage extends AgentEvent {
  AssistantMessage(this.text);
  final String text;
}

class ToolStarted extends AgentEvent {
  ToolStarted(this.callId, this.name, this.arguments);
  final String callId;
  final String name;
  final String arguments;
}

class ToolFinished extends AgentEvent {
  ToolFinished(this.callId, this.name, this.outcome);
  final String callId;
  final String name;
  final ToolOutcome outcome;
}

/// 应用自己的提示（例如达到轮次上限）。
class AgentNotice extends AgentEvent {
  AgentNotice(this.text);
  final String text;
}

class AgentError extends AgentEvent {
  AgentError(this.text);
  final String text;
}

class _PendingCall {
  String id = '';
  String name = '';
  final StringBuffer arguments = StringBuffer();
}

/// 对话 + 工具调用循环。
///
/// 一“轮”＝调用一次模型。模型每轮可以要求调用若干工具，结果回填后进入下一轮；
/// 最多 [maxRounds] 轮，到了上限由代码强行停下，不管模型还想不想继续。
class AgentRunner {
  AgentRunner({
    required this.client,
    required this.toolbox,
    this.maxRounds = defaultMaxRounds,
    String? systemPrompt,
    List<Map<String, dynamic>>? history,
  }) : systemPrompt = systemPrompt ?? defaultSystemPrompt,
       messages = history ?? [];

  static const int defaultMaxRounds = 12;

  static const String defaultSystemPrompt =
      '你是 LopiCode 里的编程助手，在用户手机上帮他完成一个代码项目。\n'
      '- 用提供的工具查看和修改项目文件；所有路径都是项目内的相对路径。\n'
      '- 改文件前先读一下相关文件；写文件时给出完整内容。\n'
      '- 执行命令和删除文件需要用户确认，被拒绝后不要重复请求，换个办法或说明情况。\n'
      '- 手机自带的 shell 没有编译器和包管理器，不要假设能运行 npm、flutter、gradle。\n'
      '- 用户消息里的 @路径 指项目里的那个文件，回答前先读它。\n'
      '- 用简体中文回答，说明你做了什么、结果如何。';

  final ChatClient client;
  final AgentToolbox toolbox;
  final int maxRounds;
  final String systemPrompt;

  /// 对话历史（不含 system），格式就是发给接口的 messages，可直接存盘。
  final List<Map<String, dynamic>> messages;

  bool _cancelled = false;
  bool get isCancelled => _cancelled;

  /// 让当前这次 [send] 尽快停下（在下一个检查点生效）。
  void cancel() => _cancelled = true;

  Stream<AgentEvent> send(String userText) async* {
    _cancelled = false;
    messages.add({'role': 'user', 'content': userText});

    for (var round = 1; ; round++) {
      if (_cancelled) {
        yield AgentNotice('已停止。');
        return;
      }
      if (round > maxRounds) {
        yield AgentNotice('已连续调用工具 $maxRounds 轮，达到上限，已自动停下。可以发“继续”让它接着做。');
        return;
      }

      final text = StringBuffer();
      final calls = <int, _PendingCall>{};
      try {
        final request = [
          {'role': 'system', 'content': systemPrompt},
          ...messages,
        ];
        await for (final delta in client.streamChat(messages: request, tools: AgentToolbox.specs)) {
          if (_cancelled) break;
          if (delta.content != null && delta.content!.isNotEmpty) {
            text.write(delta.content);
            yield AssistantDelta(delta.content!);
          }
          for (final c in delta.toolCalls) {
            final call = calls.putIfAbsent(c.index, _PendingCall.new);
            if (c.id != null && c.id!.isNotEmpty) call.id = c.id!;
            if (c.name != null && c.name!.isNotEmpty) call.name = c.name!;
            if (c.arguments != null) call.arguments.write(c.arguments);
          }
        }
      } on ChatApiException catch (e) {
        _rollbackIfEmpty(text);
        yield AgentError(e.message);
        return;
      } on Exception catch (e) {
        _rollbackIfEmpty(text);
        yield AgentError('和模型的连接中断了：${_short(e)}');
        return;
      }

      if (_cancelled) {
        if (text.isNotEmpty) messages.add({'role': 'assistant', 'content': text.toString()});
        yield AssistantMessage(text.toString());
        yield AgentNotice('已停止。');
        return;
      }

      final ordered = (calls.keys.toList()..sort()).map((k) => calls[k]!).where((c) => c.name.isNotEmpty).toList();
      for (var i = 0; i < ordered.length; i++) {
        // 有些兼容接口不给 id；补一个，保证 tool 消息能对上。
        if (ordered[i].id.isEmpty) ordered[i].id = 'call_${round}_$i';
      }

      messages.add({
        'role': 'assistant',
        'content': text.isEmpty ? null : text.toString(),
        if (ordered.isNotEmpty)
          'tool_calls': [
            for (final c in ordered)
              {
                'id': c.id,
                'type': 'function',
                'function': {'name': c.name, 'arguments': c.arguments.toString()},
              },
          ],
      });
      yield AssistantMessage(text.toString());

      if (ordered.isEmpty) return;

      for (final call in ordered) {
        final rawArgs = call.arguments.toString();
        yield ToolStarted(call.id, call.name, rawArgs);
        ToolOutcome outcome;
        if (_cancelled) {
          outcome = ToolOutcome('用户已停止，本次调用没有执行。', ok: false, denied: true);
        } else {
          Object? args;
          try {
            args = rawArgs.trim().isEmpty ? <String, dynamic>{} : jsonDecode(rawArgs);
          } on FormatException {
            args = null;
          }
          outcome = args is Map<String, dynamic>
              ? await toolbox.execute(call.name, args)
              : ToolOutcome('错误：工具参数不是合法的 JSON 对象', ok: false);
        }
        // 每个 tool_call 都必须有对应的 tool 消息，否则下一次请求会被接口拒绝。
        messages.add({'role': 'tool', 'tool_call_id': call.id, 'content': outcome.text});
        yield ToolFinished(call.id, call.name, outcome);
      }
    }
  }

  /// 请求失败时：模型已经说了一些就留下这半截；一个字都没回且上一条是用户消息，
  /// 就把那条用户消息撤回（界面会把文字放回输入框，重发不会重复）。
  void _rollbackIfEmpty(StringBuffer text) {
    if (text.isNotEmpty) {
      messages.add({'role': 'assistant', 'content': text.toString()});
    } else if (messages.isNotEmpty && messages.last['role'] == 'user') {
      messages.removeLast();
    }
  }

  static String _short(Object e) {
    final s = e.toString();
    return s.length > 160 ? '${s.substring(0, 160)}…' : s;
  }
}
