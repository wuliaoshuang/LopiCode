import 'dart:async';
import 'dart:convert';

import 'package:lopicode/agent/agent_tools.dart';
import 'package:lopicode/agent/auto_compact.dart';
import 'package:lopicode/agent/chat_client.dart';
import 'package:lopicode/agent/loop_guard.dart';
import 'package:lopicode/agent/tool_images.dart';
import 'package:lopicode/agent/usage.dart';

export 'package:lopicode/agent/auto_compact.dart' show compactHistory;

sealed class AgentEvent {}

/// 模型正在输出的文字（增量）。
class AssistantDelta extends AgentEvent {
  AssistantDelta(this.text);
  final String text;
}

/// 模型正在思考（增量）。只用来显示，不算回复。
class ReasoningDelta extends AgentEvent {
  ReasoningDelta(this.text);
  final String text;
}

/// 这一段思考结束了（开始说话 / 调工具，或者这次回复结束）。[ms] 是想了多久。
class ReasoningDone extends AgentEvent {
  ReasoningDone(this.ms);
  final int ms;
}

/// 上下文快满，较早的对话已经压成摘要（这一轮接着跑）。
class ContextCompacted extends AgentEvent {
  ContextCompacted(this.summary, this.replaced);
  final String summary;

  /// 被摘要顶替的消息条数。
  final int replaced;
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
  ToolFinished(this.callId, this.name, this.outcome, {this.ms});
  final String callId;
  final String name;
  final ToolOutcome outcome;

  /// 这一步用了多久（毫秒，含等用户点确认的时间）；没真正执行的是 null。
  final int? ms;
}

/// 生成过程中用户插的话，已经交给模型（从这一步起它能看到）。
class UserInjected extends AgentEvent {
  UserInjected(this.text);
  final String text;
}

/// 应用自己告诉模型的一件事（不是用户说的话）。[text] 给模型看；[label] 是聊天页上那一行短提示。
class AppNotice {
  const AppNotice(this.text, this.label);
  final String text;
  final String label;
}

/// 一条应用通知已经交给模型。
class NoticeInjected extends AgentEvent {
  NoticeInjected(this.notice);
  final AppNotice notice;
}

/// 消息记录里“应用通知”的标记（值是聊天页上显示的那行短提示）：聊天页据此显示成一行提示而不是用户消息。
const String kAppNoticeMark = '_notice';

/// 应用自己的提示（例如达到轮次上限）。
class AgentNotice extends AgentEvent {
  AgentNotice(this.text);
  final String text;
}

/// 一次模型请求结束（成功、被打断、或者中途断了）。[usage] 是接口给的用量，没给是 null。
class RequestFinished extends AgentEvent {
  RequestFinished(this.usage, this.ms, {this.firstMs, this.startedAt, this.compaction = false});
  final TokenUsage? usage;

  /// 这次请求是“自动压缩对话”那一次（照样算进这一轮的用量）。
  final bool compaction;
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
/// 一“轮”＝调用一次模型。模型每轮可以要求调用若干工具（每次工具调用算一“步”），结果回填后进入下一轮。
/// 连着执行满 [maxSteps] 步就由代码停下来：有人在场（给了 [confirmContinue]）就问要不要继续，
/// 没人在场（自动化任务）直接停下并留一句说明——不管模型还想不想继续。
class AgentRunner {
  AgentRunner({
    required this.client,
    required this.toolbox,
    this.maxSteps = defaultMaxSteps,
    this.confirmContinue,
    this.autoCompact = false,
    String? systemPrompt,
    List<Map<String, dynamic>>? history,
    this.vision = false,
    this.loadImage,
    this.parallelTools = const {'spawn_agent'},
    this.maxParallel = 1,
    this.contextLimit,
    this.maxRetries = 2,
    this.retryDelayOf = retryDelay,
    this.takeNotices,
    this.returnNotices,
  }) : systemPrompt = systemPrompt ?? defaultSystemPrompt,
       messages = history ?? [] {
    // 用户点停止时，正在跑的命令要跟着中途结束（见 AgentToolbox.stopSignal）。
    toolbox.stopSignal = () => _stopped.future;
  }

  /// 应用自己要告诉模型的事（例如“后台命令结束了”）：每次调用模型之前取一次，取到的当成一条说明交给模型。
  /// 没有新的返回空。只在本来就要调用模型的时候带上，不会为了它多调用一次。
  final List<AppNotice> Function()? takeNotices;

  /// 通知交出去了但那次请求一个字没回（消息被撤回）：把通知还回去，下次再带。
  final void Function(List<AppNotice> notices)? returnNotices;

  /// 连着执行多少步后停下来问（设置里可调，范围 [minMaxSteps]–[maxMaxSteps]）。
  static const int defaultMaxSteps = 30;
  static const int minMaxSteps = 10;
  static const int maxMaxSteps = 100;

  /// 没人在场、到步数上限停下时那句提示的开头（收尾的地方据此把这一轮记成“没做完”）。
  static const String stepLimitStopPrefix = '已达到步数上限';

  static const String defaultSystemPrompt =
      '你是 LopiCode 里的编程助手，在用户手机上帮他完成一个代码项目。\n'
      '- 用提供的工具查看和修改项目文件；所有路径都是项目内的相对路径。\n'
      '- 改文件前先读一下相关文件。改已有文件优先用 edit_file（只换要改的那一段）；新建文件或整份重写才用 write_file，这时给出完整内容。\n'
      '- 执行命令和删除文件需要用户确认，被拒绝后不要重复请求，换个办法或说明情况。\n'
      '- 命令在什么环境里跑、装了哪些工具，以下面“命令执行环境”那一段为准，不要凭印象假设。\n'
      '- 用户消息里的 @路径 指项目里的那个文件，回答前先读它。\n'
      '- 要分 3 步以上的任务，先用 update_todos 列出待办，每做完一项就更新；一两步的小事不用。\n'
      '- 工具报错时先看清报错原因再改，不要用同样的参数重复同一个失败的调用。\n'
      '- 用简体中文回答，说明你做了什么、结果如何。';

  final ChatClient client;
  final AgentToolbox toolbox;
  final int maxSteps;

  /// 到步数上限时问用户要不要继续（参数是这一轮已经执行的步数）。null＝没人在场，直接停。
  final Future<bool> Function(int steps)? confirmContinue;

  /// 裁掉较早的工具结果以后还是快满：自动把较早的对话压成摘要再继续（会多调用一次模型）。
  final bool autoCompact;
  bool _compactGaveUp = false;
  final String systemPrompt;

  /// 当前模型能不能看图。不能看时，图片附件只把文件路径告诉它。
  final bool vision;

  /// 读图片附件的字节（[path] 是工作区内的相对路径）；读不到返回 null。
  final Future<List<int>?> Function(String path)? loadImage;

  /// 可以同时跑的工具（派子代理）。同一轮里连着出现时并行执行，最多 [maxParallel] 个同时跑。
  final Set<String> parallelTools;
  final int maxParallel;

  /// 同一轮里连着的只读工具（读文件、列目录、搜索……）最多几个同时跑。
  static const int maxReadParallel = 4;

  /// 模型的上下文长度（token）。给了的话，快占满时自动省掉较早的工具结果。
  final int? contextLimit;

  /// 对话估算占到上下文的这个比例就开始省。
  static const double pruneAt = 0.85;

  /// 接口临时出错（限流、服务端 5xx、连不上）而且一个字都还没回时，最多自动重试几次。
  final int maxRetries;

  /// 第几次重试前等多久（测试里换成 0）。
  final Duration Function(int attempt) retryDelayOf;

  /// 对话历史（不含 system），格式就是发给接口的 messages，可直接存盘。
  /// 以 `_` 开头的键是我们自己的（`_images` 图片附件、`_raw` 原协议内容），发出去前会处理掉。
  final List<Map<String, dynamic>> messages;

  bool _cancelled = false;
  bool get isCancelled => _cancelled;

  Completer<void> _stopped = Completer<void>();

  /// 让当前这次 [send] 尽快停下（在下一个检查点生效）；正在跑的命令立刻中途结束。
  void cancel() {
    _cancelled = true;
    if (!_stopped.isCompleted) _stopped.complete();
  }

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
      if (isArchived(m)) continue; // 已经被摘要顶替：不再发给模型

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
    // 工具结果带的图片（view_image）：攒着，等这一批 tool 消息过去后，作为紧跟其后的一条 user 消息发（规矩见 tool_images.dart）。
    final sendToolImages = toolImageMessagesToSend(messages);
    final toolImages = <Object?>[];
    for (var i = 0; i < messages.length; i++) {
      final m = messages[i];
      if (isArchived(m)) continue; // 已经被摘要顶替，只留着给聊天页看
      if (m['role'] != 'tool' && toolImages.isNotEmpty) {
        out.add(await toolImagesMessage(toolImages, vision: vision, loadImage: loadImage));
        toolImages.clear();
      }
      final images = m['_images'];
      if (m['role'] == 'tool' && sendToolImages.contains(i)) toolImages.addAll(images as List);
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
    if (toolImages.isNotEmpty) out.add(await toolImagesMessage(toolImages, vision: vision, loadImage: loadImage));
    return out;
  }

  Stream<AgentEvent> send(String userText, {List<Map<String, dynamic>> images = const []}) async* {
    _cancelled = false;
    if (_stopped.isCompleted) _stopped = Completer<void>();
    messages.add({'role': 'user', 'content': userText, if (images.isNotEmpty) '_images': images});

    var steps = 0; // 这一轮一共执行了几步
    var sinceAsk = 0; // 上次问过“要不要继续”之后又执行了几步
    for (var round = 1; ; round++) {
      if (_cancelled) {
        yield AgentNotice('已停止。');
        return;
      }
      if (sinceAsk >= maxSteps) {
        final ask = confirmContinue;
        if (ask == null) {
          yield AgentNotice('$stepLimitStopPrefix：这一轮已执行 $steps 步（上限 $maxSteps 步），没有人在场确认要不要继续，已自动停下。');
          return;
        }
        final go = await ask(steps);
        if (_cancelled) {
          yield AgentNotice('已停止。');
          return;
        }
        if (!go) {
          yield AgentNotice('已执行 $steps 步，按你的选择停在这里。发“继续”可以让它接着做。');
          return;
        }
        sinceAsk = 0;
      }
      // 插话在这里交给模型：这一步起它就能看到。
      while (_steer.isNotEmpty) {
        final text = _steer.removeAt(0);
        messages.add({'role': 'user', 'content': text});
        yield UserInjected(text);
      }
      // 应用的通知（后台命令结束了……）也在这里交给模型。
      for (final note in takeNotices?.call() ?? const <AppNotice>[]) {
        messages.add({'role': 'user', 'content': note.text, kAppNoticeMark: note.label});
        yield NoticeInjected(note);
      }

      // 上下文快满了：先把较早的工具结果换成一句占位（不删消息，接口要求的配对不受影响）。
      final limit = contextLimit;
      if (limit != null && estimateTokens(messages) > limit * pruneAt) {
        final pruned = pruneOldToolResults(messages);
        if (pruned > 0) yield AgentNotice('对话快把模型的上下文占满了，已省略 $pruned 条较早的工具结果（需要时 Agent 会重新读取）。');
        // 第二道：裁完还是超过这条线，就把较早的对话压成摘要（多调用一次模型），这一轮不中断。
        if (autoCompact && !_compactGaveUp && estimateTokens(messages) > limit * pruneAt) {
          final r = await compactOlder(client, messages, keepRecent: kCompactKeepRecent, archive: true, keepLastRequest: true, contextLimit: limit);
          if (r.requested) yield RequestFinished(r.usage, r.ms, startedAt: r.startedAt, compaction: true);
          if (r.ok) {
            yield ContextCompacted(r.summary, r.replaced);
          } else if (!r.skipped) {
            // 失败：记录一个字没动。这一轮里不再试（免得每一步都白花一次请求）。
            _compactGaveUp = true;
            yield AgentNotice('想把较早的对话自动压缩成摘要，但没成功（${r.error}）。对话记录没有丢，先只省略较早的工具结果继续。');
          }
          if (_cancelled) {
            yield AgentNotice('已停止。');
            return;
          }
        }
      }

      final text = StringBuffer();
      final reasoning = StringBuffer();
      final calls = <int, _PendingCall>{};
      Map<String, dynamic>? raw;
      TokenUsage? usage;
      var started = false;
      int? firstMs;
      DateTime? startedAt;
      String? finishReason;
      final clock = Stopwatch();
      int? thinkFrom; // 这一段思考从第几毫秒开始；null＝现在没在思考
      var thinkMs = 0;
      for (var attempt = 0; ; attempt++) {
        try {
          final request = await buildRequest();
          startedAt = DateTime.now();
          clock
            ..reset()
            ..start();
          // 工具列表每一轮现取：权限、计划模式中途改了，下一轮就生效。
          await for (final delta in client.streamChat(messages: request, tools: toolbox.specs)) {
            started = true;
            if (delta.usage != null) usage = delta.usage;
            if (delta.finishReason != null) finishReason = delta.finishReason;
            if (firstMs == null && ((delta.content?.isNotEmpty ?? false) || delta.toolCalls.isNotEmpty)) firstMs = clock.elapsedMilliseconds;
            if (_cancelled) break;
            if (delta.reasoning != null && delta.reasoning!.isNotEmpty) {
              thinkFrom ??= clock.elapsedMilliseconds;
              reasoning.write(delta.reasoning);
              yield ReasoningDelta(delta.reasoning!);
            }
            // 开始说话 / 调工具：这一段思考结束。
            if (thinkFrom != null && ((delta.content?.isNotEmpty ?? false) || delta.toolCalls.isNotEmpty)) {
              thinkMs += clock.elapsedMilliseconds - thinkFrom;
              thinkFrom = null;
              yield ReasoningDone(thinkMs);
            }
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
          if (thinkFrom != null) {
            thinkMs += clock.elapsedMilliseconds - thinkFrom;
            thinkFrom = null;
            yield ReasoningDone(thinkMs);
          }
          break;
        } on ChatApiException catch (e) {
          // 临时性的错误、而且接口一个字都还没回：等一下自动再试，不让整轮白跑。
          if (!started && !_cancelled && attempt < maxRetries && (e.transient || isRetryableStatus(e.statusCode))) {
            final wait = retryDelayOf(attempt + 1);
            yield AgentNotice('${e.message}。${wait.inMilliseconds >= 1000 ? '${(wait.inMilliseconds / 1000).round()} 秒后' : '马上'}自动重试（第 ${attempt + 1} 次，最多 $maxRetries 次）。');
            await _pause(wait);
            if (!_cancelled) continue;
            // 等的时候用户点了停止：按出错收尾（一个字没回，把用户消息还给输入框）。
          }
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
      }
      yield RequestFinished(usage, clock.elapsedMilliseconds, firstMs: firstMs, startedAt: startedAt);

      if (_cancelled) {
        // 被打断的这一轮不留工具调用（没执行，留下会让下一次请求对不上）。
        if (text.isNotEmpty) {
          messages.add({'role': 'assistant', 'content': text.toString(), if (reasoning.isNotEmpty) '_reasoning': reasoning.toString(), if (reasoning.isNotEmpty) '_reasoningMs': thinkMs});
        }
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
        // 思考内容（DeepSeek 的 reasoning_content）：带工具的对话里之后每次请求都要原样带回，见 docs/api-notes.md。
        // 聊天页也拿它显示“思考了 N 秒”（`_reasoningMs` 是想了多久）。
        if (reasoning.isNotEmpty) '_reasoning': reasoning.toString(),
        if (reasoning.isNotEmpty) '_reasoningMs': thinkMs,
      });
      yield AssistantMessage(text.toString());

      if (ordered.isEmpty) {
        if (_steer.isEmpty) return;
        continue; // 它说完了，但用户刚插了话：接着处理
      }

      // 输出被长度上限截断时，最后一个工具调用的参数多半没写完。
      final cutOff = finishReason == 'length';
      var i = 0;
      while (i < ordered.length) {
        // 连着的“可并行”工具凑成一批同时跑：派子代理按设置的并发数，只读工具最多 [maxReadParallel] 个；其余一个一个来。
        var j = i + 1;
        if (maxParallel > 1 && parallelTools.contains(ordered[i].name)) {
          while (j < ordered.length && j - i < maxParallel && parallelTools.contains(ordered[j].name)) {
            j++;
          }
        } else if (_readOnly(ordered[i].name)) {
          while (j < ordered.length && j - i < maxReadParallel && _readOnly(ordered[j].name)) {
            j++;
          }
        }
        final batch = ordered.sublist(i, j);
        // 重复失败的检测按顺序先过一遍，再一起跑。
        final verdicts = <LoopVerdict>[];
        for (final call in batch) {
          final v = _loop.check(call.name, call.arguments.toString());
          verdicts.add(v);
          if (v != LoopVerdict.run) _loop.record(call.name, call.arguments.toString(), ok: false);
        }
        for (final call in batch) {
          yield ToolStarted(call.id, call.name, call.arguments.toString());
        }
        steps += batch.length;
        sinceAsk += batch.length;
        // 每一步各自计时（同一批并行的互不影响）；存进记录里，重新打开对话还能看到用了多久。
        final spent = List<int?>.filled(batch.length, null);
        final outcomes = await Future.wait([
          for (var k = 0; k < batch.length; k++)
            verdicts[k] == LoopVerdict.run
                ? () async {
                    final clock = Stopwatch()..start();
                    try {
                      return await _runCall(batch[k], truncated: cutOff && identical(batch[k], ordered.last));
                    } finally {
                      spent[k] = clock.elapsedMilliseconds;
                    }
                  }()
                : Future.value(ToolOutcome(LoopGuard.refusal(batch[k].name), ok: false)),
        ]);
        for (var k = 0; k < batch.length; k++) {
          var outcome = outcomes[k];
          if (verdicts[k] == LoopVerdict.run) {
            final nudge = _loop.record(batch[k].name, batch[k].arguments.toString(), ok: outcome.ok);
            if (nudge != null) outcome = outcome.withText('${outcome.text}$nudge');
          }
          // 每个 tool_call 都必须有对应的 tool 消息，否则下一次请求会被接口拒绝。
          messages.add({
            'role': 'tool',
            'tool_call_id': batch[k].id,
            'content': outcome.text,
            '_diff': ?outcome.change?.slim.toJson(),
            if (outcome.images.isNotEmpty) '_images': outcome.images,
            '_ms': ?spent[k],
          });
          yield ToolFinished(batch[k].id, batch[k].name, outcome, ms: spent[k]);
        }
        if (verdicts.contains(LoopVerdict.stop)) {
          // 剩下没跑的调用也要有对应的 tool 消息。
          for (final rest in ordered.sublist(j)) {
            const skipped = '这一轮已经停下，本次调用没有执行。';
            yield ToolStarted(rest.id, rest.name, rest.arguments.toString());
            messages.add({'role': 'tool', 'tool_call_id': rest.id, 'content': skipped});
            yield ToolFinished(rest.id, rest.name, ToolOutcome(skipped, ok: false, denied: true));
          }
          yield AgentNotice('Agent 连续 $kRepeatFailStop 次用同样的参数重复同一个失败的操作，已自动停下，免得白白消耗。可以换个说法，或者告诉它哪里不对。');
          return;
        }
        i = j;
      }
    }
  }

  final LoopGuard _loop = LoopGuard();

  bool _readOnly(String name) => toolbox.kindOf(name) == ToolKind.read;

  /// 等一会儿；中途被 [cancel] 就提前结束。
  Future<void> _pause(Duration d) async {
    final end = DateTime.now().add(d);
    while (!_cancelled && DateTime.now().isBefore(end)) {
      final left = end.difference(DateTime.now());
      await Future<void>.delayed(left > const Duration(milliseconds: 100) ? const Duration(milliseconds: 100) : left);
    }
  }

  Future<ToolOutcome> _runCall(_PendingCall call, {bool truncated = false}) async {
    if (_cancelled) return ToolOutcome('用户已停止，本次调用没有执行。', ok: false, denied: true);
    final rawArgs = call.arguments.toString();
    // 输出被长度上限截断时，最后一个调用即使看起来完整也不执行（内容可能只写了一半）。
    if (truncated) return ToolOutcome(badArgumentsMessage(call.name, rawArgs, truncated: true), ok: false);
    Object? args;
    FormatException? error;
    try {
      args = rawArgs.trim().isEmpty ? <String, dynamic>{} : jsonDecode(rawArgs);
    } on FormatException catch (e) {
      error = e;
    }
    // 参数解析不了：把错在哪、该怎么改说清楚回给模型，让它自己重来，不让整轮失败。
    if (args is! Map<String, dynamic>) return ToolOutcome(badArgumentsMessage(call.name, rawArgs, error: error), ok: false);
    final outcome = await toolbox.execute(call.name, args);
    // 兜底：任何工具的结果都不许无限长（各工具自己还有更小的上限）。
    final clipped = clipToolResult(outcome.text);
    return identical(clipped, outcome.text) ? outcome : outcome.withText(clipped);
  }

  /// 请求失败时：模型已经说了一些就留下这半截；一个字都没回且上一条是用户消息，
  /// 就把那条用户消息撤回（界面会把文字放回输入框，重发不会重复）。
  void _rollbackIfEmpty(StringBuffer text) {
    if (text.isEmpty) {
      // 末尾还没被模型看到的应用通知：先拿下来还回去（下次请求再带），再按原来的规矩处理用户消息。
      final back = <AppNotice>[];
      while (messages.isNotEmpty && messages.last[kAppNoticeMark] is String) {
        final m = messages.removeLast();
        back.insert(0, AppNotice('${m['content']}', m[kAppNoticeMark] as String));
      }
      if (back.isNotEmpty) returnNotices?.call(back);
    }
    if (text.isNotEmpty) {
      messages.add({'role': 'assistant', 'content': text.toString()});
    } else if (messages.isNotEmpty && messages.last['role'] == 'user') {
      messages.removeLast();
    }
  }
}
