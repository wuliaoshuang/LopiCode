// 跑一轮：把一句话交给模型，边收事件边改这段对话的状态，收尾时存盘、记用量。
// 主对话、子代理、自动化任务共用这一个。
import 'dart:io';

import 'package:lopicode/agent/agent_runner.dart';
import 'package:lopicode/agent/quota.dart';
import 'package:lopicode/agent/skills.dart';
import 'package:lopicode/agent/usage.dart';
import 'package:lopicode/session/chat_models.dart';
import 'package:lopicode/session/conversation.dart';
import 'package:lopicode/session/session_core.dart';
import 'package:lopicode/session/system_prompt.dart';
import 'package:lopicode/session/toolbox_builder.dart';
import 'package:lopicode/state/workspace_chat.dart';

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
    run.add(UserItem(text, images: [for (final i in images) core.hostPathOfAttachment('${i['path']}')]));
    convs?.update(run.convId, (c) => c.copyWith(updatedAt: DateTime.now()));

    final resolved = core.modelOf(run.conv);
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
    );
    run.runner = runner;
    final turn = TurnUsage();
    run.setTurn(turn);
    final price = resolved == null ? null : ModelPrice.of(resolved.model);
    final clock = Stopwatch()..start();
    final toolClocks = <String, Stopwatch>{};
    AssistantItem? streaming;
    var last = '';
    var failed = false;
    try {
      await for (final event in runner.send(text, images: images)) {
        switch (event) {
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
          case UserInjected(:final text):
            run.add(UserItem(text));
            if (identical(run, core.active)) queue.dropSteered(text);
          case ToolStarted(:final callId, :final name, :final arguments):
            run.add(ToolItem(callId, name, arguments));
            turn.steps.add(ToolStep(callId, name));
            toolClocks[callId] = Stopwatch()..start();
          case ToolFinished(:final callId, :final outcome):
            final item = run.items.whereType<ToolItem>().lastWhere((t) => t.callId == callId);
            run.replace(item, item.copyWith(result: outcome.text, ok: outcome.ok, denied: outcome.denied));
            if (outcome.changedFiles) core.filesChanged();
            turn.steps.whereType<ToolStep>().where((t) => t.callId == callId).lastOrNull
              ?..ms = toolClocks.remove(callId)?.elapsedMilliseconds
              ..ok = outcome.ok;
          case RequestFinished(:final usage, :final ms, :final firstMs, :final startedAt):
            turn.steps.add(RequestStep(RequestUsage(usage: usage, ms: ms, firstMs: firstMs, startedAt: startedAt, cost: usage == null ? null : price?.cost(usage))));
            if (usage != null) convs?.update(run.convId, (c) => c.copyWith(lastInput: usage.input));
          case AgentNotice(:final text):
            run.add(NoticeItem(text));
            if (text.startsWith('已停止')) failed = true;
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
      // 兜底：流意外结束时不能留着没人能点的确认卡、提问卡。
      core.cards.dropOf({run.conv.id});
      run.setBusy(false);
      run.runner = null;
      turn.ms = clock.elapsedMilliseconds;
      _recordTurn(run, turn);
      await core.saveRun(run);
      core.releaseWhenIdle();
    }
    // 额度：对话结束后查一次余额（有节流）；到提醒线或到顶时说一声。
    if (resolved != null) {
      final note = await app.quota.afterRun(resolved.channel);
      if (note != null && run.conv.parentId == null && !run.unattended) {
        run.add(NoticeItem(note, isError: note.startsWith(kQuotaBlockedPrefix)));
      }
    }
    // 提醒：对话快把上下文占满了。
    final limit = resolved?.model.contextLength;
    if (limit != null && run.conv.parentId == null && !run.unattended && AgentRunner.estimateTokens(run.messages) > limit * 0.8) {
      run.add(NoticeItem('这段对话快把模型的上下文（${limit ~/ 1000}K）占满了。发 /compact 可以把前面的内容压缩成摘要再继续。'));
    }
    return (text: last, failed: failed);
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
