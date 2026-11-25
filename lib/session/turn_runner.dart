// 跑一轮：把一句话交给模型，边收事件边改这段对话的状态，收尾时存盘、记用量。
// 主对话、子代理、自动化任务共用这一个。
import 'dart:io';

import 'package:lopicode/agent/agent_runner.dart';
import 'package:lopicode/agent/line_diff.dart';
import 'package:lopicode/agent/quota.dart';
import 'package:lopicode/agent/skills.dart';
import 'package:lopicode/agent/usage.dart';
import 'package:lopicode/session/chat_models.dart';
import 'package:lopicode/session/conversation.dart';
import 'package:lopicode/session/memory_consolidation.dart';
import 'package:lopicode/session/session_core.dart';
import 'package:lopicode/session/system_prompt.dart';
import 'package:lopicode/session/toolbox_builder.dart';
import 'package:lopicode/session/turn_changes.dart';
import 'package:lopicode/session/turn_journal.dart';
import 'package:lopicode/session/turn_keep_alive.dart';
import 'package:lopicode/state/workspace_chat.dart';

/// “要继续吗？”那张卡的两个回答。
const String kContinueAnswer = '继续';
const String kStopAnswer = '停止';

/// 一轮跑完的结果：最后一段回答（出错时是错误文字）、是不是没做成。
typedef TurnOutcome = ({String text, bool failed});

/// [TurnRunner.execute] 的样子（派子代理那边拿着它）。
typedef ExecuteTurn = Future<TurnOutcome> Function(
  ChatRunNotifier run,
  String text, {
  required Conversation root,
  required List<Skill> skills,
  List<Map<String, dynamic>> images,
  List<String>? writeScope,
  String? taskNote,
});

class TurnRunner {
  TurnRunner(this.core, {required this.toolbox});

  final SessionCore core;
  final ToolboxBuilder toolbox;

  /// 一轮结束后的记忆整理（设置里开了才做）。
  late final MemoryConsolidator memory = MemoryConsolidator(core);

  /// 每段正在跑的对话这一轮改过哪些文件（子代理改的也记进上级那一轮）。
  final TurnChangeBook changes = TurnChangeBook();

  Future<TurnOutcome> execute(
    ChatRunNotifier run,
    String text, {
    required Conversation root,
    required List<Skill> skills,
    List<Map<String, dynamic>> images = const [],
    List<String>? writeScope,
    String? taskNote,
  }) async {
    final app = core.app;
    final convs = core.convs;
    final queue = core.queue;
    run.setBusy(true);
    // 又开始新的一轮了：上一轮“没正常结束”的提示不用再挂着。
    core.clearInterrupted(run);
    final journal = core.journalOf(run.convId)..begin(text);
    changes.begin(run.convId, parentId: run.conv.parentId);
    run.add(UserItem(text, images: [for (final i in images) core.hostPathOfAttachment('${i['path']}')]));
    convs?.update(run.convId, (c) => c.copyWith(updatedAt: DateTime.now()));

    final resolved = core.modelOf(run.conv);
    // 记忆文件可能被她手改过：这一轮开始前重新读一遍，系统提示词里带的是最新的。
    if (app.memory.enabled) await app.memory.refresh(core.project);
    // 额度到顶的拦截在 createChatClient 里（主对话、子代理、自动化都走这一个口子）
    final client = await app.createChatClient(resolved);
    final runner = AgentRunner(
      client: client,
      history: run.messages,
      systemPrompt: systemPromptFor(core, run.conv, root, skills, taskNote: taskNote),
      toolbox: await toolbox.build(run, root, skills, writeScope: writeScope),
      vision: resolved?.model.vision ?? false,
      loadImage: (path) async {
        try {
          return await File(core.guard.resolve(path)).readAsBytes();
        } on Exception {
          return null;
        }
      },
      maxParallel: core.subagentMaxConcurrent,
      contextLimit: resolved?.model.contextLength,
      autoCompact: core.autoCompact,
      maxSteps: core.maxSteps,
      // 到步数上限：有人在场就问要不要继续；没人在场（自动化任务和它派的子代理）直接停。
      confirmContinue: run.unattended ? null : (steps) => _askContinue(run, journal, steps),
      // 后台命令结束了：只在本来就要调用模型的时候顺带告诉它（见 background_flow.dart）。
      takeNotices: () => toolbox.background?.takeNotices(run, root) ?? const [],
      returnNotices: (notices) => toolbox.background?.returnNotices(notices),
    );
    run.runner = runner;
    final turn = TurnUsage();
    run.setTurn(turn);
    final price = resolved == null ? null : ModelPrice.of(resolved.model);
    final clock = Stopwatch()..start();
    final toolClocks = <String, Stopwatch>{};
    AssistantItem? streaming;
    ThinkingItem? thinking;
    var last = '';
    var failed = false;
    final keepAlive = TurnKeepAlive.start(core, run); // 后台保活 + 通知栏进度
    try {
      await for (final event in runner.send(text, images: images)) {
        switch (event) {
          case ReasoningDelta(:final text):
            final soFar = thinking;
            if (soFar == null) {
              run.add(thinking = ThinkingItem(text, streaming: true, startedAt: DateTime.now()));
            } else {
              thinking = run.replace(soFar, soFar.copyWith(text: soFar.text + text));
            }
          case ReasoningDone(:final ms):
            final done = thinking;
            if (done != null) run.replace(done, done.copyWith(streaming: false, ms: ms));
            thinking = null;
          case ContextCompacted(:final summary):
            run.add(CompactionItem(summary));
            core.saveMessagesLater(run);
          case AssistantDelta(:final text):
            final soFar = streaming;
            if (soFar == null) {
              run.add(streaming = AssistantItem(text, streaming: true));
            } else {
              streaming = run.replace(soFar, soFar.copyWith(text: soFar.text + text));
            }
          case AssistantMessage(:final text):
            final done = streaming;
            if (done != null) run.replace(done, done.copyWith(streaming: false));
            streaming = null;
            if (text.trim().isNotEmpty) last = text;
          case NoticeInjected(:final notice):
            run.add(NoticeItem(notice.label));
          case UserInjected(:final text):
            run.add(UserItem(text));
            if (identical(run, core.active)) queue.dropSteered(text);
          case ToolStarted(:final callId, :final name, :final arguments):
            run.add(ToolItem(callId, name, arguments, startedAt: DateTime.now()));
            turn.steps.add(ToolStep(callId, name));
            toolClocks[callId] = Stopwatch()..start();
            journal.stepStarted(callId, name, arguments);
            // 这时候记录里已经有“模型要调这些工具”那条消息：先存一次，被关掉也知道做到哪了。
            core.saveMessagesLater(run);
          case ToolFinished(:final callId, :final outcome, :final ms):
            final item = run.items.whereType<ToolItem>().lastWhere((t) => t.callId == callId);
            run.replace(item, item.copyWith(result: outcome.text, ok: outcome.ok, denied: outcome.denied, change: outcome.change?.slim, ms: ms));
            changes.record(run.convId, outcome.change);
            if (outcome.changedFiles) core.filesChanged();
            turn.steps.whereType<ToolStep>().where((t) => t.callId == callId).lastOrNull
              ?..ms = toolClocks.remove(callId)?.elapsedMilliseconds
              ..ok = outcome.ok;
            journal.stepFinished(callId, ok: outcome.ok, denied: outcome.denied);
            core.saveMessagesLater(run);
          case RequestFinished(:final usage, :final ms, :final firstMs, :final startedAt, :final compaction):
            // 自动压缩那一次请求也如实记进这一轮的用量。
            turn.steps.add(RequestStep(RequestUsage(usage: usage, ms: ms, firstMs: firstMs, startedAt: startedAt, cost: usage == null ? null : price?.cost(usage), compaction: compaction)));
            if (usage != null && !compaction) convs?.update(run.convId, (c) => c.copyWith(lastInput: usage.input));
          case AgentNotice(:final text):
            run.add(NoticeItem(text));
            if (text.startsWith('已停止')) failed = true;
            // 没人在场、到步数上限停下：这一轮算没做完，并把原因记进交回去的结果里（自动化的运行记录、子代理的汇报）。
            if (text.startsWith(AgentRunner.stepLimitStopPrefix)) {
              failed = true;
              last = last.isEmpty ? text : '$last\n\n（$text）';
            }
          case AgentError(:final text):
            failed = true;
            last = text;
            final cut = streaming;
            if (cut != null) streaming = run.replace(cut, cut.copyWith(streaming: false));
            run.add(NoticeItem(text, isError: true));
            // 模型一个字没回时，runner 已把用户消息撤回；界面同步撤回并还原草稿。
            if (run.messages.isEmpty || run.messages.last['role'] != 'user') {
              final lastUser = run.items.lastIndexWhere((c) => c is UserItem);
              if (lastUser >= 0 && run.items.skip(lastUser + 1).every((c) => c is NoticeItem)) {
                if (identical(run, core.active)) queue.setDraft((run.items[lastUser] as UserItem).text);
                run.removeAt(lastUser);
              }
            }
        }
        run.bumpRev(); // 这一轮的用量本子里可能记了新步骤
      }
    } finally {
      final open = streaming;
      if (open != null) run.replace(open, open.copyWith(streaming: false));
      // 想到一半就断了 / 停了：思考那一行不能一直转。
      final thought = thinking;
      if (thought != null) run.replace(thought, thought.copyWith(streaming: false, ms: thought.startedAt == null ? null : DateTime.now().difference(thought.startedAt!).inMilliseconds));
      // 兜底：流意外结束时不能留着没人能点的确认卡、提问卡。
      core.cards.dropOf({run.conv.id});
      run.setBusy(false);
      run.runner = null;
      keepAlive.finish(failed: failed);
      turn.ms = clock.elapsedMilliseconds;
      _recordFiles(run, changes.end(run.convId));
      _recordTurn(run, turn);
      // 存对话记录，同时把进行中记录标成“已结束”（做完 / 出错 / 点了停止都算正常收尾：下次打开不提示）。
      await Future.wait([core.saveRun(run), journal.finish()]);
      // 这一轮里结束、却没赶上交给模型的后台命令：在聊天里提示一行，下次发消息时带上。
      toolbox.background?.announce(run);
      core.releaseWhenIdle();
    }
    // 记忆整理（默认关）：不等它，在后台另发一次请求；做不做、成不成都不影响这一轮。
    memory.afterTurn(run, failed: failed, turn: turn, resolved: resolved);
    // 额度：对话结束后查一次余额（有节流）；到提醒线或到顶时说一声。
    if (resolved != null) {
      final note = await app.quota.afterRun(resolved.channel);
      if (note != null && run.conv.parentId == null && !run.unattended) {
        run.add(NoticeItem(note, isError: note.startsWith(kQuotaBlockedPrefix)));
      }
    }
    // 提醒：对话快把上下文占满了。
    final limit = resolved?.model.contextLength;
    // （开着自动压缩就不用提醒：快满时会自己压。）
    if (limit != null && !core.autoCompact && run.conv.parentId == null && !run.unattended && AgentRunner.estimateTokens(run.messages) > limit * 0.8) {
      run.add(NoticeItem('这段对话快把模型的上下文（${limit ~/ 1000}K）占满了。发 /compact 可以把前面的内容压缩成摘要再继续。'));
    }
    return (text: last, failed: failed);
  }

  /// 到步数上限：出一张只能选“继续 / 停止”的卡。卡被收掉（这一轮停了）按停止算。
  Future<bool> _askContinue(ChatRunNotifier run, TurnJournalStore journal, int steps) async {
    journal.setAwaitingContinue(true);
    try {
      final answer = await core.cards.ask(
        PendingQuestion('这一轮已经连着执行了 $steps 步，还没做完。要继续吗？', const [kContinueAnswer, kStopAnswer], conversationId: run.convId, agentName: run.conv.agentName, title: '要继续吗？', choiceOnly: true),
      );
      return answer == kContinueAnswer;
    } finally {
      journal.setAwaitingContinue(false);
    }
  }

  /// 这一轮改过的文件：挂在这一轮最后一条消息上（跟着对话存盘），并在回复下方加一行。
  void _recordFiles(ChatRunNotifier run, List<FileChange> files) {
    if (files.isEmpty || run.messages.isEmpty || run.messages.last.containsKey('_files')) return;
    run.messages.last['_files'] = [for (final f in files) f.toJson()];
    run.add(ChangedFilesItem(files));
  }

  /// 把这一轮的用量记到对话上：累计进对话合计，并挂在这一轮最后一条消息上（跟着对话存盘）。
  void _recordTurn(ChatRunNotifier run, TurnUsage turn) {
    final totals = turn.totals;
    if (totals.requests == 0) return; // 一次请求都没发出去（没配模型、被额度拦下）：不显示
    // 子代理的用量由上级那一轮统一算进主对话；这里只累计到它自己这段对话上。
    core.convs?.update(run.convId, (c) => c.withTurn(totals));
    // 用户消息被撤回时（模型一个字没回），最后一条是上一轮的，别盖掉上一轮的记录。
    if (run.messages.isNotEmpty && !run.messages.last.containsKey('_usage')) {
      run.messages.last['_usage'] = turn.toJson();
    }
    run.add(UsageItem(turn));
  }
}
