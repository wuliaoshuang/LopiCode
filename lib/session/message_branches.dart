// 重试、编辑、分支：对当前对话里一条消息的三个“改走向”的动作。算法在 branch_ops.dart，这里负责另存、截断、存盘、重发、切对话。
// 界面通过 ProjectSession.branches 用它。
//
// 数据怎么存（详见 docs/chat-branches.md）：
// - 分支＝复制出一段新对话：新的对话 id、自己的记录文件（chat-<id>.json），目录里那一条带 `from`（出处：原对话 id、消息 id、当时的名字）。
//   不在一个文件里做消息树；旧的对话文件、旧的目录文件照常能开。
// - 重试 / 编辑＝“从这条消息重新来”：被移走的内容先整段另存成一段带“旧版本”记号的对话（同样是复制），
//   然后当前对话截到这条消息之前，再走**原有的发送流程**（SendFlow.send）把消息发出去——
//   权限档、确认卡、计划模式、额度拦截、步数上限、排队都照常。
// - 随对话走的东西：模型 / 权限档 / 计划模式 / 预设抄过去；待办清单、改过的文件清单、每轮用量脚注都在消息上，跟着消息走；
//   累计用量从 0 重新计；“本对话都允许”不带过去（新对话重新问）；子代理对话不复制，卡片仍点开原来那段；
//   团队任务板、后台命令、记忆、收藏都不动（收藏指向被移走的消息时，改指到旧版本里的同一条）。
// - Agent 已经对文件做过的修改不撤销。
import 'dart:io';

import 'package:lopicode/agent/message_ids.dart';
import 'package:lopicode/core/safe_file.dart';
import 'package:lopicode/session/branch_ops.dart';
import 'package:lopicode/session/chat_models.dart';
import 'package:lopicode/session/conversation.dart';
import 'package:lopicode/session/session_core.dart';
import 'package:lopicode/state/message_edit.dart';
import 'package:lopicode/state/workspace_chat.dart';
import 'package:lopicode/state/workspace_favorites.dart';

/// Agent 正在回复时不能重试 / 编辑：说明原因的那句话。
const String kRewindWhileBusy = 'Agent 正在回复，等它停下再重试或编辑。';

/// 正在跑的这一轮不能当分支点。
const String kBranchRunningTurn = '这一轮还没跑完，等它停下再从这里分支。';

const String kSwitchWhileBusy = 'Agent 正在回复，停下后才能切到别的对话。';
const String kMessageGone = '这条消息已经不在记录里了。';

/// “从这条消息重新来”开始以后的情况。
class RewindStart {
  const RewindStart({this.error, this.oldVersionId, this.turn});

  /// 没开始成的原因（给用户看）；开始了是 null。
  final String? error;

  /// 旧内容另存成的那段对话；没什么可存的是 null。
  final String? oldVersionId;

  /// 重新发出去的那一轮（跑完才结束）。界面不用等它。
  final Future<void>? turn;
}

class BranchResult {
  const BranchResult({this.error, this.convId, this.opened = false, this.wholeTurn = false, this.draftHeld = false});
  final String? error;
  final String? convId;

  /// 已经切到新分支（Agent 正在回复时切不过去，只建好）。
  final bool opened;

  /// 分支点落在一轮中间、抄到了这一轮结束。
  final bool wholeTurn;

  /// 从我的消息分支时，这条的文字已经交给输入框。
  final bool draftHeld;
}

class MessageBranches {
  MessageBranches(this.core, {required this.send, required this.loadChat, required this.open});

  final SessionCore core;

  /// 原有的发送入口（SendFlow.send）。
  final Future<void> Function(String text, {List<Map<String, dynamic>> images}) send;
  final Future<void> Function() loadChat;

  /// 切到另一段对话（ProjectSession.selectConversation）。
  final Future<void> Function(String id) open;

  ChatRunNotifier get _run => core.active;
  bool _working = false;

  String _titleOf(Conversation c) => c.title.isEmpty ? '新对话' : c.title;

  /// 这段对话里每次 spawn_agent 调用对应的子对话。
  Map<String, String> _childLinks(ChatRunNotifier run) => {
    for (final item in run.items)
      if (item is ToolItem && item.childConversationId != null) item.callId: item.childConversationId!,
  };

  /// 把 [messages] 存成一段新对话（不切过去）。存不了返回 null。
  Future<Conversation?> _saveCopy(ChatRunNotifier from, List<Map<String, dynamic>> messages, BranchOrigin origin, {required bool front}) async {
    final convs = core.convs;
    if (convs == null) return null;
    final src = from.conv;
    final conv = Conversation(
      core.newConvId(),
      src.title,
      // 旧版本紧跟在原对话后面（重开应用后目录按时间排，早 1 毫秒就排在它后面）
      front ? DateTime.now() : src.updatedAt.subtract(const Duration(milliseconds: 1)),
      selection: src.selection,
      permission: src.permission,
      planMode: src.planMode,
      presetId: src.presetId,
      origin: origin,
    );
    try {
      await writeJsonAtomic(core.chatFileOf(conv.id), messages);
    } on FileSystemException {
      return null;
    }
    convs.add(conv, front: front, after: front ? null : src.id);
    await core.saveIndex();
    return conv;
  }

  // ── 重试 / 编辑 ──────────────────────────────────────
  /// 从 [id] 所在那一轮重新来之前先算：会移走什么。不在记录里返回 null。
  RewindPlan? previewRewind(String id) => planRewind(_run.messages, id);

  /// 重试：用这一轮“我的那条消息”原样再发一遍（图片附件还在）。
  Future<RewindStart> retry(String id) => _rewind(id, null, null);

  /// 编辑后发送：把这一轮“我的那条消息”换成 [text] / [images] 再发。
  Future<RewindStart> resendEdited(String id, String text, List<Map<String, dynamic>> images) => _rewind(id, text, images);

  Future<RewindStart> _rewind(String id, String? text, List<Map<String, dynamic>>? images) async {
    if (_working) return const RewindStart(error: '上一次操作还没处理完，稍等一下。');
    _working = true;
    final RewindPlan plan;
    Conversation? old;
    try {
      await loadChat();
      final run = _run;
      if (run.busy) return const RewindStart(error: kRewindWhileBusy);
      final p = planRewind(run.messages, id);
      if (p == null) return const RewindStart(error: kMessageGone);
      plan = p;
      if (text != null && text.trim().isEmpty && (images ?? const []).isEmpty) return const RewindStart(error: '消息是空的，没有发。');
      if (plan.worthKeeping) {
        // 先另存，存成了才动当前对话：存不了就什么都不改
        final copy = cloneMessages(run.messages);
        stampChildLinks(copy, _childLinks(run));
        old = await _saveCopy(run, copy, BranchOrigin(convId: run.convId, messageId: plan.anchorId, title: _titleOf(run.conv), old: true), front: false);
        if (old == null) return const RewindStart(error: '没能把现在的内容另存下来（存储写不了），所以没有动这段对话。');
        // 被移走的那几轮派出的子代理对话：跟着旧版本走
        for (final item in run.items) {
          final kid = item is ToolItem && plan.goneCallIds.contains(item.callId) ? item.childConversationId : null;
          if (kid != null && core.dir.byId(kid)?.parentId == run.convId) core.convs?.update(kid, (c) => c.movedUnder(old!.id));
        }
      }
      await core.journalOf(run.convId).dismiss(); // “上一轮没正常结束”的提示：要重新来了，不用再挂着
      run.messages = plan.kept;
      core.rebuildItems(run);
      // 上次请求的 token 数对不上现在的记录了：上下文占用改回估算
      core.convs?.update(run.convId, (c) => c.copyWith(clearLastInput: true));
      await core.saveRun(run);
      final favorites = core.app.disposed ? null : core.app.container.read(favoritesProvider(core.session).notifier);
      if (old != null) {
        await favorites?.moveTo(run.convId, plan.goneIds, old.id);
      } else {
        await favorites?.markGone(run.convId, plan.goneIds);
      }
    } finally {
      _working = false;
    }
    return RewindStart(
      oldVersionId: old?.id,
      turn: send(text ?? plan.text, images: images ?? plan.images),
    );
  }

  // ── 分支 ─────────────────────────────────────────────
  /// 现在能不能从 [id] 分支；不能返回原因。
  String? branchBlocked(String id) {
    final run = _run;
    final index = indexOfMessage(run.messages, id);
    if (index < 0) return kMessageGone;
    if (run.busy && index >= lastTurnStart(run.messages)) return kBranchRunningTurn;
    return null;
  }

  /// 从 [id] 这条消息另开一段对话。原对话不动。Agent 没在回复就切过去。
  Future<BranchResult> branch(String id) async {
    await loadChat();
    final run = _run;
    final blocked = branchBlocked(id);
    if (blocked != null) return BranchResult(error: blocked);
    final plan = planBranch(run.messages, id);
    if (plan == null) return const BranchResult(error: kMessageGone);
    stampChildLinks(plan.messages, _childLinks(run));
    final conv = await _saveCopy(run, plan.messages, BranchOrigin(convId: run.convId, messageId: id, title: _titleOf(run.conv)), front: true);
    if (conv == null) return const BranchResult(error: '没能建出分支（存储写不了）。');
    final opened = !run.busy;
    var held = false;
    if (opened) {
      await open(conv.id);
      // 从我的消息分支：这条的文字和图片交给输入框
      final draft = plan.draftText;
      if (draft != null && !core.app.disposed && core.dir.activeId == conv.id) {
        core.app.container.read(messageEditProvider(core.session).notifier).handOff(ComposerDraft(draft, plan.draftImages));
        held = true;
      }
    }
    return BranchResult(convId: conv.id, opened: opened, wholeTurn: plan.wholeTurn, draftHeld: held);
  }

  /// 当前对话里：哪条消息上分出去了哪些对话（分支和旧版本）。
  Map<String, List<Conversation>> get branchesByMessage {
    final out = <String, List<Conversation>>{};
    for (final c in core.dir.branchesOf(core.dir.activeId)) {
      final at = c.origin?.messageId;
      if (at != null) (out[at] ??= []).add(c);
    }
    return out;
  }

  /// 切到 [convId]（分出去的某一段）。成功返回 null。
  Future<String?> openConversation(String convId) async {
    if (convId == core.dir.activeId) return null;
    if (_run.busy) return kSwitchWhileBusy;
    if (core.dir.byId(convId) == null) return '那段对话已经被删掉了。';
    await open(convId);
    return core.dir.activeId == convId ? null : '没能打开那段对话。';
  }

  /// 回到当前对话的出处：切到原对话并滚到分出来的那条消息。成功返回 null。
  Future<String?> openOrigin() async {
    final origin = core.dir.active.origin;
    if (origin == null) return '这段对话不是从别处分出来的。';
    if (core.dir.byId(origin.convId) == null) return '原对话“${origin.title}”已经被删掉了。';
    final failed = await openConversation(origin.convId);
    if (failed != null) return failed;
    final at = origin.messageId;
    if (at != null && !core.app.disposed) core.app.container.read(chatJumpProvider(core.session).notifier).request(at);
    return null;
  }
}
