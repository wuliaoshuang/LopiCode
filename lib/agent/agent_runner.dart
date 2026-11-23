import 'dart:async';
import 'dart:convert';

import 'package:lopicode/agent/agent_tools.dart';
import 'package:lopicode/agent/chat_client.dart';
import 'package:lopicode/agent/usage.dart';

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

/// 生成过程中用户插的话，已经交给模型（从这一步起它能看到）。
class UserInjected extends AgentEvent {
  UserInjected(this.text);
  final String text;
}

/// 应用自己的提示（例如达到轮次上限）。
class AgentNotice extends AgentEvent {
  AgentNotice(this.text);
  final String text;
}

/// 一次模型请求结束（成功、被打断、或者中途断了）。[usage] 是接口给的用量，没给是 null。
class RequestFinished extends AgentEvent {
  RequestFinished(this.usage, this.ms, {this.firstMs, this.startedAt});
  final TokenUsage? usage;
  final int ms;

  /// 从发出到收到第一块内容（文字或工具调用）的用时；一块都没收到是 null。
  final int? firstMs;
  final DateTime? startedAt;
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
    this.vision = false,
    this.loadImage,
    this.parallelTools = const {'spawn_agent'},
    this.maxParallel = 1,
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

  /// 当前模型能不能看图。不能看时，图片附件只把文件路径告诉它。
  final bool vision;

  /// 读图片附件的字节（[path] 是工作区内的相对路径）；读不到返回 null。
  final Future<List<int>?> Function(String path)? loadImage;

  /// 可以同时跑的工具（派子代理）。同一轮里连着出现时并行执行，最多 [maxParallel] 个同时跑。
  final Set<String> parallelTools;
  final int maxParallel;

  /// 对话历史（不含 system），格式就是发给接口的 messages，可直接存盘。
  /// 以 `_` 开头的键是我们自己的（`_images` 图片附件、`_raw` 原协议内容），发出去前会处理掉。
  final List<Map<String, dynamic>> messages;

  bool _cancelled = false;
  bool get isCancelled => _cancelled;

  /// 让当前这次 [send] 尽快停下（在下一个检查点生效）。
  void cancel() => _cancelled = true;

  final List<String> _steer = [];

  /// 生成过程中插话：下一步（下一次调用模型之前）交给模型。
  void steer(String text) {
    if (text.trim().isNotEmpty) _steer.add(text);
  }

  /// 还没交给模型的插话。
  List<String> get pendingSteer => List.unmodifiable(_steer);

  /// 撤回一条还没交出去的插话。
  bool withdrawSteer(String text) => _steer.remove(text);

  /// 粗略估算对话占了多少上下文（按 3 个字符 1 个 token，偏保守）。
  static int estimateTokens(List<Map<String, dynamic>> messages) {
    var chars = 0;
    for (final m in messages) {
      chars += '${m['content'] ?? ''}'.length;
      for (final c in (m['tool_calls'] as List?) ?? const []) {
        chars += '$c'.length;
      }
      chars += ((m['_images'] as List?)?.length ?? 0) * 3000;
    }
    return chars ~/ 3;
  }

  /// 把存盘格式的消息变成这一次请求要发的样子：图片附件按模型能力展开。
  Future<List<Map<String, dynamic>>> buildRequest() async {
    final out = <Map<String, dynamic>>[
      {'role': 'system', 'content': systemPrompt},
    ];
    for (final m in messages) {
      final images = m['_images'];
      if (m['role'] != 'user' || images is! List || images.isEmpty) {
        out.add(m);
        continue;
      }
      final text = '${m['content'] ?? ''}';
      final parts = <Map<String, dynamic>>[];
      final asFiles = <String>[];
      for (final img in images) {
        if (img is! Map) continue;
        final path = '${img['path']}';
        final bytes = vision ? await loadImage?.call(path) : null;
        if (bytes == null) {
          asFiles.add(path);
        } else {
          parts.add({
            'type': 'image_url',
            'image_url': {'url': 'data:${img['mime'] ?? 'image/png'};base64,${base64Encode(bytes)}'},
          });
        }
      }
      final note = asFiles.isEmpty ? '' : '\n\n（用户附了 ${asFiles.length} 个文件，${vision ? '读取失败，' : '当前模型不能看图，'}已存在工作区里：${asFiles.join('、')}）';
      if (parts.isEmpty) {
        out.add({'role': 'user', 'content': '$text$note'});
      } else {
        out.add({
          'role': 'user',
          'content': [
            {'type': 'text', 'text': '$text$note'},
            ...parts,
          ],
        });
      }
    }
    return out;
  }

  Stream<AgentEvent> send(String userText, {List<Map<String, dynamic>> images = const []}) async* {
    _cancelled = false;
    messages.add({'role': 'user', 'content': userText, if (images.isNotEmpty) '_images': images});

    for (var round = 1; ; round++) {
      if (_cancelled) {
        yield AgentNotice('已停止。');
        return;
      }
      if (round > maxRounds) {
        yield AgentNotice('已连续调用工具 $maxRounds 轮，达到上限，已自动停下。可以发“继续”让它接着做。');
        return;
      }
      // 插话在这里交给模型：这一步起它就能看到。
      while (_steer.isNotEmpty) {
        final text = _steer.removeAt(0);
        messages.add({'role': 'user', 'content': text});
        yield UserInjected(text);
      }

      final text = StringBuffer();
      final calls = <int, _PendingCall>{};
      Map<String, dynamic>? raw;
      TokenUsage? usage;
      var started = false;
      int? firstMs;
      DateTime? startedAt;
      final clock = Stopwatch();
      try {
        final request = await buildRequest();
        startedAt = DateTime.now();
        clock.start();
        // 工具列表每一轮现取：权限、计划模式中途改了，下一轮就生效。
        await for (final delta in client.streamChat(messages: request, tools: toolbox.specs)) {
          started = true;
          if (delta.usage != null) usage = delta.usage;
          if (firstMs == null && ((delta.content?.isNotEmpty ?? false) || delta.toolCalls.isNotEmpty)) firstMs = clock.elapsedMilliseconds;
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
          if (delta.raw != null) raw = delta.raw;
        }
      } on ChatApiException catch (e) {
        _rollbackIfEmpty(text);
        // 接口已经开始回话才算一次请求（被额度上限拦下、连不上的不算）。
        if (started) yield RequestFinished(usage, clock.elapsedMilliseconds, firstMs: firstMs, startedAt: startedAt);
        yield AgentError(e.message);
        return;
      } on Exception catch (e) {
        _rollbackIfEmpty(text);
        if (started) yield RequestFinished(usage, clock.elapsedMilliseconds, firstMs: firstMs, startedAt: startedAt);
        yield AgentError('和模型的连接中断了：${shortError(e)}');
        return;
      }
      yield RequestFinished(usage, clock.elapsedMilliseconds, firstMs: firstMs, startedAt: startedAt);

      if (_cancelled) {
        // 被打断的这一轮不留工具调用（没执行，留下会让下一次请求对不上）。
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
        '_raw': ?raw,
      });
      yield AssistantMessage(text.toString());

      if (ordered.isEmpty) {
        if (_steer.isEmpty) return;
        continue; // 它说完了，但用户刚插了话：接着处理
      }

      var i = 0;
      while (i < ordered.length) {
        // 连着的“可并行”工具凑成一批同时跑，其余一个一个来。
        var j = i + 1;
        if (maxParallel > 1 && parallelTools.contains(ordered[i].name)) {
          while (j < ordered.length && j - i < maxParallel && parallelTools.contains(ordered[j].name)) {
            j++;
          }
        }
        final batch = ordered.sublist(i, j);
        for (final call in batch) {
          yield ToolStarted(call.id, call.name, call.arguments.toString());
        }
        final outcomes = await Future.wait([for (final call in batch) _runCall(call)]);
        for (var k = 0; k < batch.length; k++) {
          // 每个 tool_call 都必须有对应的 tool 消息，否则下一次请求会被接口拒绝。
          messages.add({'role': 'tool', 'tool_call_id': batch[k].id, 'content': outcomes[k].text});
          yield ToolFinished(batch[k].id, batch[k].name, outcomes[k]);
        }
        i = j;
      }
    }
  }

  Future<ToolOutcome> _runCall(_PendingCall call) async {
    if (_cancelled) return ToolOutcome('用户已停止，本次调用没有执行。', ok: false, denied: true);
    final rawArgs = call.arguments.toString();
    Object? args;
    try {
      args = rawArgs.trim().isEmpty ? <String, dynamic>{} : jsonDecode(rawArgs);
    } on FormatException {
      args = null;
    }
    return args is Map<String, dynamic> ? await toolbox.execute(call.name, args) : ToolOutcome('错误：工具参数不是合法的 JSON 对象', ok: false);
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
}

/// /compact：让模型把到目前为止的对话压成一段摘要，然后用摘要顶替原来的记录。
/// 成功返回 null 并就地改写 [messages]；失败返回原因，记录不动。
Future<String?> compactHistory(ChatClient client, List<Map<String, dynamic>> messages) async {
  if (messages.length < 2) return '对话还很短，不需要压缩';
  final request = <Map<String, dynamic>>[
    {'role': 'system', 'content': '你是对话记录整理员。'},
    ...messages,
    {
      'role': 'user',
      'content':
          '请把上面到目前为止的对话压缩成一份摘要，之后会用它顶替原来的记录接着干活。写清楚：用户的目标和要求、已经做完的事（改了哪些文件）、'
          '还没做完的事、要注意的约定。只输出摘要本身，用简体中文。',
    },
  ];
  final text = StringBuffer();
  try {
    await for (final d in client.streamChat(messages: request)) {
      if (d.content != null) text.write(d.content);
    }
  } on ChatApiException catch (e) {
    return e.message;
  } on Exception catch (e) {
    return '和模型的连接中断了：${shortError(e)}';
  }
  final summary = text.toString().trim();
  if (summary.isEmpty) return '模型没有给出摘要，对话记录没有动';
  messages
    ..clear()
    ..addAll([
      {'role': 'user', 'content': '（之前的对话已压缩，以下是摘要）\n$summary'},
      {'role': 'assistant', 'content': '好的，我已经了解之前的进展，可以接着做。'},
    ]);
  return null;
}
