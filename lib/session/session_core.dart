// 一个工作区的 Agent 引擎里大家共用的那部分：每段对话的运行状态放哪、对话记录怎么读写、
// 对话目录怎么查、子代理和团队的设置、任务板。跑一轮（turn_runner.dart）、组装工具（toolbox_builder.dart）、
// 派子代理（subagents.dart）、发送与排队（send_flow.dart）都拿着同一个 SessionCore 干活。
//
// 这里不发请求、不调工具，只管“东西在哪、怎么存”。界面不直接用它，界面走 ProjectSession 的方法和 lib/state 的 provider。
import 'dart:async';
import 'dart:io';

import 'package:lopicode/agent/agent_runner.dart';
import 'package:lopicode/agent/agent_tools.dart';
import 'package:lopicode/agent/auto_compact.dart';
import 'package:lopicode/agent/memory_store.dart';
import 'package:lopicode/agent/message_ids.dart';
import 'package:lopicode/agent/model_config.dart';
import 'package:lopicode/agent/presets.dart';
import 'package:lopicode/agent/team.dart';
import 'package:lopicode/app_services.dart';
import 'package:lopicode/core/path_guard.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/safe_file.dart';
import 'package:lopicode/core/stores.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/session/chat_items.dart';
import 'package:lopicode/session/turn_journal.dart';
import 'package:lopicode/state/message_edit.dart';
import 'package:lopicode/state/team_state.dart';
import 'package:lopicode/state/workspace_chat.dart';
import 'package:lopicode/state/workspace_conversations.dart';
import 'package:lopicode/state/workspace_favorites.dart';
import 'package:lopicode/state/workspace_files.dart';
import 'package:path/path.dart' as p;

/// 文字太长就截断，后面加省略号。
String clipText(String s, int max) => s.length > max ? '${s.substring(0, max)}…' : s;

/// 对话标题：取第一行，最多 18 个字。
String titleFromText(String text) {
  final line = text.trim().split('\n').first.trim();
  return line.length > 18 ? '${line.substring(0, 18)}…' : line;
}

class SessionCore {
  SessionCore(this.session);

  /// 所属的工作区门面：provider 都按它分身，所以这里要拿着它当“钥匙”。
  final ProjectSession session;

  AppServices get app => session.app;
  Project get project => session.project;
  PathGuard get guard => session.guard;

  // ── 生命周期 ─────────────────────────────────────────
  /// 这个工作区已经关掉了：之后不许再往状态里写。
  bool disposed = false;

  /// 关掉并且收完尾了：对话目录的状态已经放掉。
  bool released = false;

  /// 项目文件有变化：文件树、预览订阅 [filesRevProvider] 跟着刷新。
  void filesChanged() {
    if (disposed || app.disposed) return;
    app.container.read(filesRevProvider(session).notifier).bump();
  }

  /// 工作区关掉以后，等跑到一半的那几轮都收完尾（存好记录和目录）再把对话目录的状态放掉。
  void releaseWhenIdle() {
    if (!disposed || released || runs.values.any((r) => r.busy)) return;
    released = true;
    if (app.disposed) return;
    final box = app.container;
    box.invalidate(conversationsProvider(session));
    for (final id in runs.keys) {
      box.invalidate(chatRunProvider((session, id)));
    }
    box.invalidate(pendingCardsProvider(session));
    box.invalidate(sendQueueProvider(session));
    box.invalidate(favoritesProvider(session));
    box.invalidate(chatJumpProvider(session));
    box.invalidate(messageEditProvider(session));
    for (final id in boards.keys) {
      box.invalidate(teamProvider((session, id)));
    }
  }

  // ── 每段对话的运行状态 ───────────────────────────────
  /// 每段对话的运行状态（用到才建）。
  final Map<String, ChatRunNotifier> runs = {};

  ChatRunNotifier runOf(Conversation conv) => runs.putIfAbsent(
    conv.id,
    // 应用已经退出时拿不到状态容器：临时建一个不接容器的，只记不通知
    () => (app.disposed ? ChatRunNotifier((session, conv.id)) : app.container.read(chatRunProvider((session, conv.id)).notifier))..seed(conv),
  );
  late final PendingCardsNotifier cards = app.disposed ? PendingCardsNotifier(session) : app.container.read(pendingCardsProvider(session).notifier);
  late final SendQueueNotifier queue = app.disposed ? SendQueueNotifier(session) : app.container.read(sendQueueProvider(session).notifier);

  /// 当前这段对话的运行状态。
  ChatRunNotifier get active => runOf(dir.active);

  // ── 对话目录 ─────────────────────────────────────────
  // 目录（有哪些、当前哪段、项目规则）在 [conversationsProvider]；每段对话的消息各存一个文件
  // （第一段沿用 chat.json，其余是 chat-<id>.json）。子代理的对话也在目录里，带着上级的 id。
  // 应用已经退出时拿不到（null）：这时候什么都不读、不写
  late final ConversationsNotifier? convs = app.disposed ? null : app.container.read(conversationsProvider(session).notifier);
  final ConversationsState _noDir = ConversationsState();
  ConversationsState get dir => convs?.current ?? _noDir;

  /// 目录里这段对话的最新一份（闭包里拿着的可能是旧的）。
  Conversation live(Conversation c) => dir.byId(c.id) ?? c;

  Future<void> saveIndex() async => convs?.save();

  String newConvId() => convs?.newId() ?? DateTime.now().microsecondsSinceEpoch.toRadixString(36);

  // ── 每段对话各自的模型 / 权限 / 预设 ──────────────────
  ResolvedModel? modelOf(Conversation conv) => app.models.resolve(conv.selection) ?? app.models.defaultForNewChat();

  PermissionLevel get defaultPermission => PermissionLevel.byId(app.settings.getString(SettingKeys.defaultPermission, 'workspace'));
  PermissionLevel permissionOf(Conversation conv) => conv.permission == null ? defaultPermission : PermissionLevel.byId(conv.permission);

  AgentPreset presetOf(Conversation conv) => app.presets.byId(conv.presetId ?? app.presets.defaultId);

  // ── 读写对话记录 ─────────────────────────────────────
  File reserved(String name) => File(guard.resolve('${PathGuard.reservedDir}/$name', allowReserved: true));
  File chatFileOf(String id) => reserved(id == 'main' ? 'chat.json' : 'chat-$id.json');

  Future<List<Map<String, dynamic>>> _readMessages(String id) async {
    // 文件坏了：备份后当空对话
    final decoded = await readJsonFile(chatFileOf(id), accept: (j) => j is List, label: '对话记录');
    if (decoded is! List) return [];
    return [
      for (final m in decoded)
        if (m is Map<String, dynamic>) m,
    ];
  }

  Future<void> ensureLoaded(ChatRunNotifier run) async {
    if (run.loaded) return;
    run.markLoaded();
    run.messages = await _readMessages(run.convId);
    // 上一轮要是没正常收尾，记录里可能有“调了工具却没有结果”的消息：补上说明，免得下一次请求被接口拒绝。
    repairDanglingCalls(run.messages);
    // 旧对话文件里的消息没有稳定标识：补上并马上写回（收藏、删除认的是它，重开应用不能变）。写不了就算了，下次再补。
    if (ensureMessageIds(run.messages) > 0) {
      try {
        await writeJsonAtomic(chatFileOf(run.convId), run.messages);
      } on FileSystemException {
        // 盘写不了：这次打开期间内存里的标识照样能用
      }
    }
    rebuildItems(run);
    // 上一轮进行中 App 被关掉 / 被回收：在对话末尾说清楚停在哪，等用户选“继续 / 不用了”。绝不自动重跑。
    final cut = await journalOf(run.convId).interrupted();
    if (cut != null && !run.busy) run.add(cut.describe());
  }

  // ── 进行中记录（App 被关掉后的恢复提示）─────────────────
  final Map<String, TurnJournalStore> _journals = {};

  TurnJournalStore journalOf(String convId) => _journals.putIfAbsent(convId, () => TurnJournalStore(reserved(convId == 'main' ? 'turn.json' : 'turn-$convId.json')));

  /// 对话删掉了：交出它的进行中记录文件（调用方一起删）。
  File dropJournal(String convId) => (_journals.remove(convId) ?? journalOf(convId)).file;

  /// 把对话末尾的“上一轮没正常结束”提示收掉（用户选过了，或者又发了新消息）。
  void clearInterrupted(ChatRunNotifier run) {
    if (run.items.any((i) => i is InterruptedItem)) run.setItems([...run.items.where((i) => i is! InterruptedItem)]);
  }

  /// 一轮进行中途存一次消息记录（不等写完、不动对话目录）：App 这时候被关掉，已经做完的步骤不会丢。
  /// 上一次还没写完就只记“有新内容”，写完后补写一次最新的；一轮收尾时 [saveRun] 会写最终的，那之后不再补。
  void saveMessagesLater(ChatRunNotifier run) {
    final id = run.conv.id;
    if (_savingLater.contains(id)) {
      _dirtyLater.add(id);
      return;
    }
    _savingLater.add(id);
    unawaited(
      writeJsonAtomic(chatFileOf(id), run.messages).catchError((Object _) {}).whenComplete(() {
        _savingLater.remove(id);
        if (_dirtyLater.remove(id) && run.busy) saveMessagesLater(run);
      }),
    );
  }

  final Set<String> _savingLater = {};
  final Set<String> _dirtyLater = {};

  /// 附件在手机上的真实路径。
  String hostPathOfAttachment(String rel) => p.join(project.dir, rel);

  /// 从接口格式的消息记录重建界面条目（记录是唯一的事实来源）。
  void rebuildItems(ChatRunNotifier run) {
    final kids = dir.all.where((c) => c.parentId == run.convId).toList()..sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
    run.setItems(chatItemsFromMessages(run.messages, childConversationIds: [for (final k in kids) k.id], hostPathOf: hostPathOfAttachment, conversationExists: (id) => dir.byId(id) != null));
  }

  Future<void> saveRun(ChatRunNotifier run) async {
    ensureMessageIds(run.messages); // 摘要、承接语这类不经界面的消息在这里补上标识
    try {
      await writeJsonAtomic(chatFileOf(run.conv.id), run.messages);
    } on FileSystemException {
      // 存不了就算了：不影响当前对话
    }
    await saveIndex();
  }

  // ── 记忆 ─────────────────────────────────────────────
  /// 这个工作区的项目记忆；.lopicode/memory 被换成指到外面的符号链接时是 null（不读不写）。
  MemoryStore? get projectMemory {
    try {
      return app.memory.project(project);
    } on PathGuardException {
      return null;
    }
  }

  // ── Agent 的几项设置 ─────────────────────────────────
  /// 上下文快满时自动把较早的对话压成摘要（默认开）。
  bool get autoCompact => app.settings.getBool(SettingKeys.agentAutoCompact, true);

  /// 连着执行多少步后停下来问（默认 30，范围 10–100）。
  int get maxSteps => (app.settings.get<int>(SettingKeys.agentMaxSteps) ?? AgentRunner.defaultMaxSteps).clamp(AgentRunner.minMaxSteps, AgentRunner.maxMaxSteps);

  // ── 子代理、团队的设置 ───────────────────────────────
  bool get teamEnabled => app.settings.getBool(SettingKeys.teamEnabled);
  bool get subagentsEnabled => app.settings.getBool(SettingKeys.subagentEnabled, true);
  int get subagentMaxDepth => (app.settings.get<int>(SettingKeys.subagentMaxDepth) ?? 1).clamp(0, 3);
  int get subagentMaxConcurrent => (app.settings.get<int>(SettingKeys.subagentMaxConcurrent) ?? 2).clamp(1, 4);
  List<String> get subagentAllowedModels => [
    for (final m in app.settings.get<List<dynamic>>(SettingKeys.subagentAllowedModels) ?? const [])
      if (m is String) m,
  ];

  // ── 团队任务板 ───────────────────────────────────────
  final Map<String, TeamBoard> boards = {};

  Future<TeamBoard> boardOf(Conversation root) => boardById(root.id);

  /// 主对话 [rootId] 的任务板（第一次用到时读文件）。
  Future<TeamBoard> boardById(String rootId) {
    final loading = _boardLoads[rootId];
    if (loading != null) return loading;
    final board = TeamBoard(file: reserved('team-$rootId.json'))..onChanged = (view) => _teamChanged(rootId, view);
    boards[rootId] = board;
    return _boardLoads[rootId] = board.load().then((_) => board);
  }

  final Map<String, Future<TeamBoard>> _boardLoads = {};

  /// 对话删掉了：它的任务板也不要了。
  void dropBoard(String rootId) {
    boards.remove(rootId);
    _boardLoads.remove(rootId);
    if (!app.disposed) app.container.invalidate(teamProvider((session, rootId)));
  }

  /// 任务板变了：把新的样子送给状态层。
  void _teamChanged(String rootId, TeamView view) {
    if (!disposed && !app.disposed) app.container.read(teamProvider((session, rootId)).notifier).publish(view);
  }
}
