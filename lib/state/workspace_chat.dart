// 一个工作区里“正在聊”的状态：每段对话的条目和忙不忙、等用户点的确认卡 / 提问卡、输入框上方排队的消息。
//
// 三个 Notifier 都是同一个写法：
// - 状态不可变，改动都是换一份新的；
// - `current` 是最近一份状态，工作区关掉、应用退出以后也能读——跑到一半的那一轮收尾时还要读写它；
// - 工作区关掉并收完尾（`session.released`）以后不再通知任何人。
// Agent 怎么跑（发请求、调工具、派子代理）不在这里，在 ProjectSession 里；这里只管“状态长什么样、怎么改”。
import 'package:lopicode/agent/agent_runner.dart';
import 'package:lopicode/agent/usage.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/state/workspace_conversations.dart';
import 'package:riverpod/riverpod.dart';

/// 三个 Notifier 共用的“存一份、能通知就通知”。
mixin _Snapshot<T> on Notifier<T> {
  ProjectSession get session;
  late T _snap = initial();
  bool _attached = false;

  T initial();

  /// 最近一份状态（不依赖状态容器还在不在）。
  T get current => _snap;

  @override
  T build() {
    _attached = true;
    return _snap = initial();
  }

  void _set(T next) {
    _snap = next;
    // 没接到状态容器上（应用已经退出时临时建的）、工作区已经收完尾：只记不通知
    if (_attached && ref.mounted && !session.released) state = next;
  }
}

// ── 一段对话的运行 ─────────────────────────────────────

class ChatRunState {
  const ChatRunState({this.items = const [], this.busy = false, this.loaded = false, this.turn, this.rev = 0});

  /// 这段对话显示的条目（列表不可改）。
  final List<ChatItem> items;

  /// 是不是正在生成。
  final bool busy;

  /// 消息记录从盘上读过了没有。
  final bool loaded;

  /// 正在跑的这一轮的用量；跑完后留着最近一轮的。它是边跑边记的本子，内容变了看 [rev]。
  final TurnUsage? turn;

  /// 条目之外的东西（这一轮的用量步骤）变了的次数。
  final int rev;

  ChatRunState copyWith({List<ChatItem>? items, bool? busy, bool? loaded, TurnUsage? turn, int? rev}) =>
      ChatRunState(items: items == null ? this.items : List.unmodifiable(items), busy: busy ?? this.busy, loaded: loaded ?? this.loaded, turn: turn ?? this.turn, rev: rev ?? this.rev);
}

/// 一段对话的运行状态。主对话、子代理、自动化任务各有一份，互不干扰。
class ChatRunNotifier extends Notifier<ChatRunState> with _Snapshot<ChatRunState> {
  ChatRunNotifier(this.key);
  final (ProjectSession, String) key;

  @override
  ProjectSession get session => key.$1;
  String get convId => key.$2;

  @override
  ChatRunState initial() => const ChatRunState();

  @override
  ChatRunState build() {
    // 这段对话被删掉后同一个 id 又建了新的：干活用的东西也要从头来
    messages = [];
    runner = null;
    unattended = false;
    _last = null;
    return super.build();
  }

  /// 这段对话在目录里的最新一份（被删掉以后是删之前的那份）。
  Conversation get conv => _last = session.conversationById(convId) ?? _last ?? Conversation(convId, '', DateTime.fromMillisecondsSinceEpoch(0));
  Conversation? _last;

  /// 刚建出来的对话：先记住它，免得目录里还没有时查不到。
  void seed(Conversation conv) => _last ??= conv;

  // 干活用的东西（不进状态）：接口格式的消息记录、正在跑的那个执行器、是不是没人在场。
  List<Map<String, dynamic>> messages = [];
  AgentRunner? runner;

  /// 没人在场（自动化任务）：需要确认的操作一律按拒绝处理，也不提问。
  bool unattended = false;

  List<ChatItem> get items => _snap.items;
  bool get busy => _snap.busy;
  bool get loaded => _snap.loaded;
  TurnUsage? get turn => _snap.turn;

  void setBusy(bool value) => _set(_snap.copyWith(busy: value));
  void markLoaded() => _set(_snap.copyWith(loaded: true));
  void setTurn(TurnUsage turn) => _set(_snap.copyWith(turn: turn));

  /// 这一轮的用量本子里记了新东西。
  void bumpRev() => _set(_snap.copyWith(rev: _snap.rev + 1));

  void add(ChatItem item) => _set(_snap.copyWith(items: [..._snap.items, item]));
  void setItems(List<ChatItem> items) => _set(_snap.copyWith(items: items));

  /// 把 [old]（按“是不是同一个对象”找）换成 [next]。找不到就不动，返回 [old]。
  T replace<T extends ChatItem>(T old, T next) {
    final i = _snap.items.indexWhere((x) => identical(x, old));
    if (i < 0) return old;
    _set(_snap.copyWith(items: [..._snap.items]..[i] = next));
    return next;
  }

  void removeAt(int index) {
    if (index < 0 || index >= _snap.items.length) return;
    _set(_snap.copyWith(items: [..._snap.items]..removeAt(index)));
  }
}

/// 某个工作区里某段对话的运行状态（键：工作区 + 对话 id）。
final chatRunProvider = NotifierProvider.family<ChatRunNotifier, ChatRunState, (ProjectSession, String)>(ChatRunNotifier.new);

/// 当前这段对话的运行状态：当前对话换了，它跟着换。聊天页订阅这个。
final activeChatProvider = Provider.family<ChatRunState, ProjectSession>((ref, session) {
  final id = ref.watch(conversationsProvider(session).select((v) => v.activeId));
  return ref.watch(chatRunProvider((session, id)));
});

// ── 确认卡 / 提问卡 ────────────────────────────────────

class PendingCardsState {
  const PendingCardsState({this.approvals = const [], this.questions = const [], this.autoAllow = const {}});

  /// 等用户点的确认卡（可能同时来自主智能体和几个子代理），排队一张一张出。
  final List<PendingApproval> approvals;
  final List<PendingQuestion> questions;

  /// 点过“本对话都允许”的主对话 id。只在内存里：重启 App 后恢复逐次询问。
  final Set<String> autoAllow;

  PendingApproval? get approval => approvals.isEmpty ? null : approvals.first;
  PendingQuestion? get question => questions.isEmpty ? null : questions.first;

  PendingCardsState copyWith({List<PendingApproval>? approvals, List<PendingQuestion>? questions, Set<String>? autoAllow}) => PendingCardsState(
    approvals: approvals == null ? this.approvals : List.unmodifiable(approvals),
    questions: questions == null ? this.questions : List.unmodifiable(questions),
    autoAllow: autoAllow == null ? this.autoAllow : Set.unmodifiable(autoAllow),
  );
}

class PendingCardsNotifier extends Notifier<PendingCardsState> with _Snapshot<PendingCardsState> {
  PendingCardsNotifier(this.session);
  @override
  final ProjectSession session;

  @override
  PendingCardsState initial() => const PendingCardsState();

  /// 出一张确认卡，等用户点。
  Future<bool> requestApproval(PendingApproval pending) {
    _set(_snap.copyWith(approvals: [..._snap.approvals, pending]));
    return pending.completer.future;
  }

  /// 回答最前面那张确认卡。[always]＝“本对话都允许”（这类卡允许的话），记在 [rootOf] 算出来的主对话上；
  /// 同一段主对话里已经在排队的同类确认卡一并放行。
  void resolveApproval(bool allow, {bool always = false, required String? Function(String conversationId) rootOf, required String fallbackRoot}) {
    if (_snap.approvals.isEmpty) return;
    final rest = [..._snap.approvals];
    final pending = rest.removeAt(0);
    var auto = _snap.autoAllow;
    final released = <PendingApproval>[];
    if (allow && always && pending.request.allowAlways) {
      auto = {...auto, rootOf(pending.conversationId) ?? fallbackRoot};
      for (final other in rest.where((a) => a.request.allowAlways).toList()) {
        final root = rootOf(other.conversationId);
        if (root != null && auto.contains(root)) {
          rest.remove(other);
          released.add(other);
        }
      }
    }
    _set(_snap.copyWith(approvals: rest, autoAllow: auto));
    for (final other in released) {
      other.completer.complete(true);
    }
    pending.completer.complete(allow);
  }

  /// 出一张提问卡，等用户回答。
  Future<String> ask(PendingQuestion q) {
    _set(_snap.copyWith(questions: [..._snap.questions, q]));
    return q.completer.future;
  }

  void answerQuestion(String answer) {
    if (_snap.questions.isEmpty) return;
    final rest = [..._snap.questions];
    final q = rest.removeAt(0);
    _set(_snap.copyWith(questions: rest));
    q.completer.complete(answer.trim().isEmpty ? '（用户没有回答）' : answer.trim());
  }

  /// 这些对话停了 / 结束了：它们名下没人能点的卡一律收掉（确认卡按拒绝，提问卡按没回答）。
  void dropOf(Set<String> convIds) {
    final gone = _snap.approvals.where((a) => convIds.contains(a.conversationId)).toList();
    final goneQ = _snap.questions.where((q) => convIds.contains(q.conversationId)).toList();
    if (gone.isEmpty && goneQ.isEmpty) return;
    _set(_snap.copyWith(approvals: [..._snap.approvals]..removeWhere(gone.contains), questions: [..._snap.questions]..removeWhere(goneQ.contains)));
    for (final a in gone) {
      a.completer.complete(false);
    }
    for (final q in goneQ) {
      q.completer.complete('（用户没有回答，已停止）');
    }
  }

  bool autoAllowed(String rootId) => _snap.autoAllow.contains(rootId);

  /// 取消“本对话都允许”。
  void clearAutoAllow(String rootId) {
    if (!_snap.autoAllow.contains(rootId)) return;
    _set(_snap.copyWith(autoAllow: {..._snap.autoAllow}..remove(rootId)));
  }
}

/// 某个工作区里等用户点的卡（按工作区分身）。
final pendingCardsProvider = NotifierProvider.family<PendingCardsNotifier, PendingCardsState, ProjectSession>(PendingCardsNotifier.new);

// ── 排队 / 插话 ───────────────────────────────────────

class SendQueueState {
  const SendQueueState({this.queue = const [], this.restoredDraft, this.paused = false});

  /// AI 生成时又发的消息（显示在输入框上方）。
  final List<QueuedMessage> queue;

  /// 请求失败、用户消息被撤回时，要交还给输入框的文字。
  final String? restoredDraft;

  /// 上一轮出错或被点了停止：排着的消息先不自动发，等用户点“继续发送”。队列空了就不算暂停。
  final bool paused;

  SendQueueState copyWith({List<QueuedMessage>? queue, String? restoredDraft, bool clearDraft = false, bool? paused}) {
    final next = queue == null ? this.queue : List<QueuedMessage>.unmodifiable(queue);
    return SendQueueState(queue: next, restoredDraft: clearDraft ? null : restoredDraft ?? this.restoredDraft, paused: next.isNotEmpty && (paused ?? this.paused));
  }
}

class SendQueueNotifier extends Notifier<SendQueueState> with _Snapshot<SendQueueState> {
  SendQueueNotifier(this.session);
  @override
  final ProjectSession session;

  @override
  SendQueueState initial() => const SendQueueState();

  void add(QueuedMessage msg) => _set(_snap.copyWith(queue: [..._snap.queue, msg]));

  /// 拿掉 [msg]（按“是不是同一个对象”找）。不在队里返回 false。
  bool remove(QueuedMessage msg) {
    if (!_snap.queue.any((q) => identical(q, msg))) return false;
    _set(_snap.copyWith(queue: [..._snap.queue]..removeWhere((q) => identical(q, msg))));
    return true;
  }

  /// 取出最前面那条；没有返回 null。
  QueuedMessage? takeFirst() {
    if (_snap.queue.isEmpty) return null;
    final first = _snap.queue.first;
    _set(_snap.copyWith(queue: _snap.queue.sublist(1)));
    return first;
  }

  void clear() {
    if (_snap.queue.isNotEmpty) _set(_snap.copyWith(queue: const []));
  }

  /// 暂停 / 恢复自动发送（队列是空的时候暂停不起来）。
  void setPaused(bool value) {
    if (_snap.paused != (value && _snap.queue.isNotEmpty)) _set(_snap.copyWith(paused: value));
  }

  /// 把 [msg] 换成 [next]（位置不变）。不在队里返回 false。
  bool replace(QueuedMessage msg, QueuedMessage next) {
    if (!_snap.queue.any((q) => identical(q, msg))) return false;
    _set(_snap.copyWith(queue: [for (final q in _snap.queue) identical(q, msg) ? next : q]));
    return true;
  }

  /// 把 [msg] 改成插话 / 改回排队。不在队里返回 null。
  QueuedMessage? setSteer(QueuedMessage msg, bool steer) {
    if (!_snap.queue.any((q) => identical(q, msg))) return null;
    final next = msg.asSteer(steer);
    _set(_snap.copyWith(queue: [for (final q in _snap.queue) identical(q, msg) ? next : q]));
    return next;
  }

  /// 没来得及交给模型的插话：全改成排队，不丢。
  void unsteerAll() {
    if (_snap.queue.any((q) => q.steer)) _set(_snap.copyWith(queue: [for (final q in _snap.queue) q.steer ? q.asSteer(false) : q]));
  }

  /// 模型已经看到这句插话了：从队里拿掉。
  void dropSteered(String text) {
    if (_snap.queue.any((q) => q.steer && q.text == text)) _set(_snap.copyWith(queue: [..._snap.queue]..removeWhere((q) => q.steer && q.text == text)));
  }

  void setDraft(String? text) => _set(text == null ? _snap.copyWith(clearDraft: true) : _snap.copyWith(restoredDraft: text));

  /// 输入框把草稿拿走（拿走就清掉）。
  String? takeDraft() {
    final draft = _snap.restoredDraft;
    if (draft != null) _set(_snap.copyWith(clearDraft: true));
    return draft;
  }
}

/// 某个工作区里排队的消息和要还给输入框的草稿（按工作区分身）。
final sendQueueProvider = NotifierProvider.family<SendQueueNotifier, SendQueueState, ProjectSession>(SendQueueNotifier.new);
