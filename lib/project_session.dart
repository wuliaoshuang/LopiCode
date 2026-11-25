// 一个工作区对外的门面：界面和别的模块通过它的方法办事（发消息、开终端、切对话……）。
//
// 它自己不存状态、不通知任何人：状态都在 lib/state 的 provider 里；Agent 引擎拆在 lib/session 里——
// session_core.dart（共用的存取）、turn_runner.dart（跑一轮）、toolbox_builder.dart（组装工具）、
// subagents.dart（派子代理）、send_flow.dart（发送与排队）、system_prompt.dart、chat_export.dart、attachments.dart。
// 这里只负责把它们接起来，再把方法转过去。新功能不要往这里写逻辑。
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:lopicode/agent/agent_runner.dart';
import 'package:lopicode/agent/agent_tools.dart';
import 'package:lopicode/agent/automation.dart';
import 'package:lopicode/agent/command_output_store.dart';
import 'package:lopicode/agent/command_runner.dart';
import 'package:lopicode/agent/context_segments.dart';
import 'package:lopicode/agent/model_config.dart';
import 'package:lopicode/agent/presets.dart';
import 'package:lopicode/agent/team.dart';
import 'package:lopicode/agent/usage.dart';
import 'package:lopicode/agent/web_search.dart';
import 'package:lopicode/app_services.dart';
import 'package:lopicode/core/path_guard.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/preview/preview_server.dart';
import 'package:lopicode/runtime/linux_shell_backend.dart';
import 'package:lopicode/session/attachments.dart' as attachments;
import 'package:lopicode/session/background_flow.dart';
import 'package:lopicode/session/chat_export.dart';
import 'package:lopicode/session/chat_models.dart';
import 'package:lopicode/session/compact_flow.dart';
import 'package:lopicode/session/conversation.dart';
import 'package:lopicode/session/send_flow.dart';
import 'package:lopicode/session/session_core.dart';
import 'package:lopicode/session/subagents.dart';
import 'package:lopicode/session/system_prompt.dart';
import 'package:lopicode/session/toolbox_builder.dart';
import 'package:lopicode/session/turn_journal.dart';
import 'package:lopicode/session/turn_runner.dart';
import 'package:lopicode/ssh/ssh_config.dart';
import 'package:lopicode/ssh/ssh_connector.dart';
import 'package:lopicode/state/backend_run.dart';
import 'package:lopicode/state/workspace_background.dart';
import 'package:lopicode/state/workspace_chat.dart';
import 'package:lopicode/state/workspace_files.dart';
import 'package:lopicode/state/workspace_preview.dart';
import 'package:lopicode/state/workspace_terminals.dart';
import 'package:lopicode/terminal/terminal_session.dart';

export 'package:lopicode/session/chat_models.dart';
export 'package:lopicode/session/conversation.dart';

/// 一段对话的运行状态（条目、忙不忙、这一轮的用量）：就是 [ChatRunNotifier]，沿用老名字。
typedef ConvRun = ChatRunNotifier;

/// 打开一个工作区期间，各个页面共用这一个对象，切页面不丢状态。
class ProjectSession {
  ProjectSession(this.app, this.project, {this.headless = false}) : guard = project.guard {
    if (!headless && !app.disposed) app.container.read(terminalsProvider(this));
  }

  /// 不带界面（自动化任务在别的工作区里跑时用）：不开终端。
  final bool headless;

  final AppServices app;
  final Project project;
  final PathGuard guard;

  // ── 引擎的几块（用到才建；互相要用的地方用函数接，免得谁拿着谁）────────
  late final SessionCore _core = SessionCore(this);
  late final BackgroundFlow _background = BackgroundFlow(_core);
  late final ToolboxBuilder _toolbox = ToolboxBuilder(_core, spawnTool: (parent, root, skills) => _subagents.tool(parent, root, skills), background: _background);
  late final TurnRunner _turns = TurnRunner(_core, toolbox: _toolbox);
  late final Subagents _subagents = Subagents(_core, execute: _turns.execute);
  late final SendFlow _sending = SendFlow(_core, execute: _turns.execute, loadChat: loadChat);

  /// 测试用：换掉执行命令的环境、联网搜索的客户端。
  CommandRunner Function()? commandRunnerFactory;
  WebSearchClient Function(WebSearchConfig config)? webSearchFactory;

  /// 预览用的本机小服务器：归 [previewProvider] 管，这里只是转一手。
  PreviewServer get preview => app.container.read(previewProvider(this).notifier).server;

  /// 项目文件有变化：文件树、预览订阅 [filesRevProvider] 跟着刷新。
  void filesChanged() => _core.filesChanged();

  // ── 终端 ─────────────────────────────────────────────
  TerminalsState get _terminals => disposed || app.disposed ? const TerminalsState() : app.container.read(terminalsProvider(this));
  TerminalsNotifier get _terminalsCtl => app.container.read(terminalsProvider(this).notifier);
  List<TerminalSession> get terminals => _terminals.sessions;
  int get activeTerminal => _terminals.active;

  /// 测试用：换掉伪终端的创建方式。
  PtySpawner? ptySpawner;

  /// 测试用：换掉“带参数的伪终端”（进 Ubuntu 用的那种）。
  PtyArgsSpawner? linuxPtySpawner;

  /// 新开一个会话。Ubuntu 环境能用就进 Ubuntu，否则在允许本机 shell 的平台（桌面调试、测试）开本机 shell；
  /// 安卓上环境没装好时不开，返回 null（终端页是安装引导）。[forceLocal] 只在允许本机 shell 的平台有效。
  TerminalSession? addTerminal({bool forceLocal = false}) => _terminalsCtl.addLocal(forceLocal: forceLocal);

  /// 新开一个 SSH 会话。[onUnknownHost] 在第一次连这台主机时弹指纹确认。
  TerminalSession addSshTerminal(SshConfig config, {HostKeyPrompt? onUnknownHost}) => _terminalsCtl.addSsh(config, onUnknownHost: onUnknownHost);

  void closeTerminal(int index) => _terminalsCtl.close(index);

  void selectTerminal(int index) => _terminalsCtl.select(index);

  // ── 对话目录 ─────────────────────────────────────────
  /// 这个工作区已经关掉了：之后不许再往状态里写。
  bool get disposed => _core.disposed;

  /// 关掉并且收完尾了：对话目录的状态已经放掉。
  bool get released => _core.released;

  ConvRun get _active => _core.active;

  /// 当前对话显示的条目。
  List<ChatItem> get chat => _active.items;
  List<Map<String, dynamic>> get _messages => _active.messages;

  /// 当前对话是不是正在生成。
  bool get agentBusy => _active.busy;
  bool _chatLoaded = false;

  List<Conversation> get conversations => _core.dir.all;
  String get activeConversationId => _core.dir.activeId;
  Conversation get activeConversation => _core.dir.active;
  Conversation? conversationById(String? id) => _core.dir.byId(id);

  /// 侧边栏里列的对话：不含子代理的。
  List<Conversation> get topConversations => _core.dir.top;

  /// 顶栏标题：还没说话的对话叫“新对话”。
  String get conversationTitle => activeConversation.title.isEmpty ? '新对话' : activeConversation.title;

  /// 项目规则：她写给 Agent 的长期要求，拼在系统提示词后面。
  String get projectRules => _core.dir.projectRules;

  Future<void> setProjectRules(String text) async {
    await _core.convs?.setProjectRules(text);
  }

  // ── 模型 / 权限 / 计划模式 / 预设（每段对话各自一份）──────────
  /// 这段对话的“根”：子代理的权限、计划模式、预设都跟着最上面那段主对话走。
  Conversation rootOf(Conversation conv) => _core.dir.rootOf(conv);

  ResolvedModel? modelOf(Conversation conv) => _core.modelOf(conv);
  ResolvedModel? get currentModel => modelOf(activeConversation);

  Future<void> _updateActive(Conversation Function(Conversation c) change) async {
    _core.convs?.update(activeConversationId, change);
    await _core.saveIndex();
  }

  Future<void> setModel(ModelSelection selection) async {
    _core.convs?.update(activeConversationId, (c) => c.copyWith(selection: selection));
    await app.models.setLastSelection(selection);
    await _core.saveIndex();
  }

  PermissionLevel get defaultPermission => _core.defaultPermission;
  PermissionLevel permissionOf(Conversation conv) => _core.permissionOf(conv);
  PermissionLevel get permission => permissionOf(activeConversation);

  Future<void> setPermission(PermissionLevel level) => _updateActive((c) => c.copyWith(permission: level.id));

  bool get planMode => activeConversation.planMode;

  Future<void> setPlanMode(bool on) => _updateActive((c) => c.copyWith(planMode: on));

  AgentPreset presetOf(Conversation conv) => _core.presetOf(conv);
  AgentPreset get preset => presetOf(activeConversation);

  Future<void> setPreset(String id) => _updateActive((c) => c.copyWith(presetId: id));

  /// 当前对话是不是点过“本对话都允许”。只在内存里：重启 App 后恢复逐次询问。
  bool get autoAllowActive => _core.cards.autoAllowed(activeConversationId);

  void clearAutoAllow() => _core.cards.clearAutoAllow(activeConversationId);

  /// 当前对话里有几个 MCP 工具点过“本对话都允许”；[clearMcpAllow] 全部收回。
  int get mcpAllowCount => _core.cards.allowedKeyCount(rootOf(activeConversation).id);
  void clearMcpAllow() => _core.cards.clearAllowKeys(rootOf(activeConversation).id);

  // ── 读对话、开新对话、切换、删除 ──────────────────────
  Future<void>? _loading;

  Future<void> loadChat() => _loading ??= _loadChat();

  Future<void> _loadChat() async {
    if (_chatLoaded) return;
    await app.ready();
    await _core.convs?.load();
    await _core.ensureLoaded(_active);
    await _background.load(); // 上次留下的后台命令：标成“已中断”，在聊天里提示一行
    // 老版本只有一个 chat.json、没有标题：从第一句话补一个。
    if (activeConversation.title.isEmpty) {
      final first = _messages.where((m) => m['role'] == 'user').firstOrNull;
      if (first != null) _core.convs?.update(activeConversationId, (c) => c.copyWith(title: titleFromText('${first['content'] ?? ''}')));
    }
    _chatLoaded = true;
  }

  /// 开一段新对话。当前这段还是空的就直接留在这里，不堆空对话。
  Future<void> newConversation() async {
    if (agentBusy) return;
    await loadChat();
    if (_messages.isEmpty && chat.isEmpty) return;
    final conv = Conversation(_core.newConvId(), '', DateTime.now(), selection: app.models.defaultForNewChat()?.selection, presetId: app.presets.defaultId);
    _core.convs?.add(conv, front: true, activate: true);
    _core.runOf(conv).markLoaded();
    _core.queue.clear();
    await _core.saveIndex();
  }

  Future<void> selectConversation(String id) async {
    if (agentBusy || id == activeConversationId || !conversations.any((c) => c.id == id)) return;
    await loadChat();
    _core.convs?.activate(id);
    _core.queue.clear();
    await _core.ensureLoaded(_active);
    _background.announce(_active);
  }

  /// 子代理谱系：[rootId] 这段对话派出的全部子代理（含子代理再派出的），按派出顺序。
  List<Conversation> descendantsOf(String rootId) => _core.dir.descendantsOf(rootId);

  /// 当前对话派出的子代理。
  List<Conversation> get subAgents => descendantsOf(activeConversationId);
  bool isRunning(String conversationId) => _core.runs[conversationId]?.busy ?? false;

  /// 进子代理对话时用：拿到它的条目（没读过就先读盘）。
  Future<ConvRun?> openRun(String conversationId) async {
    final conv = conversationById(conversationId);
    if (conv == null) return null;
    final run = _core.runOf(conv);
    await _core.ensureLoaded(run);
    return run;
  }

  /// 删除当前对话（文件不受影响），它派出的子代理对话一起删。删到一段不剩时留一段空的。
  Future<void> deleteConversation() async {
    if (agentBusy) return;
    final id = activeConversationId;
    final doomed = [id, for (final c in descendantsOf(id)) c.id];
    for (final d in doomed) {
      _core.runs.remove(d)?.runner?.cancel();
      for (final file in [_core.chatFileOf(d), _core.reserved('team-$d.json'), _core.dropJournal(d)]) {
        try {
          if (await file.exists()) await file.delete();
        } on FileSystemException {
          // 删不掉：索引里照样移除
        }
      }
      _core.dropBoard(d);
      await _background.dropConversation(d);
      _core.cards.clearAutoAllow(d);
      _core.cards.clearAllowKeys(d);
      if (!app.disposed) app.container.invalidate(chatRunProvider((this, d)));
    }
    _core.convs?.removeAll(doomed.toSet());
    _core.queue.clear();
    await _core.ensureLoaded(_active);
    await _core.saveIndex();
  }

  // ── 确认卡 / 提问卡（可能同时来自主智能体和几个子代理，排队一张一张出）────
  PendingApproval? get pendingApproval => _core.cards.current.approval;
  PendingQuestion? get pendingQuestion => _core.cards.current.question;

  /// 回答最前面那张确认卡。[always]＝“本对话都允许”（这类卡允许的话）。
  void resolveApproval(bool allow, {bool always = false}) => _core.cards.resolveApproval(
    allow,
    always: always,
    rootOf: (id) {
      final conv = conversationById(id);
      return conv == null ? null : rootOf(conv).id;
    },
    fallbackRoot: activeConversationId,
  );

  /// 拒绝最前面那张确认卡，并带一句原因（原因会跟在“用户拒绝……”后面告诉模型）。和点“拒绝”一样：不执行。
  void rejectApproval(String reason) {
    pendingApproval?.request.denyReason = reason;
    resolveApproval(false);
  }

  void answerQuestion(String answer) => _core.cards.answerQuestion(answer);

  // ── 团队、子代理的设置 ───────────────────────────────
  bool get teamEnabled => _core.teamEnabled;

  Future<TeamBoard> boardOf(Conversation root) => _core.boardOf(root);
  Future<TeamBoard> boardById(String rootId) => _core.boardById(rootId);

  bool get subagentsEnabled => _core.subagentsEnabled;
  int get subagentMaxDepth => _core.subagentMaxDepth;
  int get subagentMaxConcurrent => _core.subagentMaxConcurrent;
  List<String> get subagentAllowedModels => _core.subagentAllowedModels;

  /// 当前对话的系统提示词（不含技能那一段）。
  String get systemPrompt => systemPromptFor(_core, activeConversation, rootOf(activeConversation), const []);

  // ── 自动化任务（Agent 侧的两个工具在 lib/session/automation_tools.dart）──
  /// 到点了：在这个工作区里新开一段对话，无人值守地执行 [a] 的指令。不切换当前对话。
  Future<AutomationRun> runAutomation(Automation a) async {
    await loadChat();
    final startedAt = DateTime.now().toUtc();
    final conv = Conversation(
      _core.newConvId(),
      titleFromText('[自动] ${a.title}'),
      DateTime.now(),
      selection: app.models.defaultForNewChat()?.selection,
      permission: PermissionLevel.byId(a.permission).id,
      presetId: app.presets.defaultId,
      auto: true,
    );
    _core.convs?.add(conv, front: true);
    final run = _core.runOf(conv)
      ..markLoaded()
      ..unattended = true;
    await _core.saveIndex();
    final skills = await app.skills.enabled(workspaceDir: project.dir);
    final outcome = await _turns.execute(run, a.instruction, root: conv, skills: skills);
    return AutomationRun(startedAt, outcome.failed ? 'failed' : 'ok', clipText(outcome.text.trim().isEmpty ? '（没有输出）' : outcome.text.trim(), 300));
  }

  // ── 用量 ─────────────────────────────────────────────
  /// 按调用 id 在已加载的对话里找那次工具调用（轨迹的步骤详情用）。
  ToolItem? findToolItem(String callId) {
    for (final run in _core.runs.values) {
      for (final item in run.items) {
        if (item is ToolItem && item.callId == callId) return item;
      }
    }
    return null;
  }

  /// 当前对话的累计用量。
  UsageTotals get usageTotals => activeConversation.usage;

  /// 当前对话的上下文占用。接口返回过用量就用“上次请求的输入 token 数”；
  /// 还没有就按字数估一个“预计下次请求”（[ContextUsage.estimated] 为 true）。没配模型是 null。
  ContextUsage? get contextUsage {
    final limit = modelOf(activeConversation)?.model.contextLength;
    if (limit == null || limit <= 0) return null;
    final last = activeConversation.lastInput;
    if (last != null) return ContextUsage(last, limit, estimated: false);
    return ContextUsage(estimateTextTokens(systemPrompt) + AgentRunner.estimateTokens(_messages), limit, estimated: true);
  }

  /// 上下文分项（系统提示词 / 工具定义 / 消息）。都是按字数估的，不是接口给的。
  Future<({int system, int tools, int messages})> contextBreakdown() async {
    final conv = activeConversation;
    final root = rootOf(conv);
    final skills = await app.skills.enabled(workspaceDir: project.dir);
    final box = await _toolbox.build(_core.runOf(conv), root, skills);
    return (system: estimateTextTokens(systemPromptFor(_core, conv, root, skills)), tools: estimateTextTokens(jsonEncode(box.specs)), messages: AgentRunner.estimateTokens(_messages));
  }

  /// 上下文占用分段（估算）：系统提示词 / 工具定义 / 对话消息 / 工具结果 / 剩余。没选模型（不知道上下文多长）是 null。
  Future<ContextSegments?> contextSegments() async {
    final limit = contextUsage?.limit;
    if (limit == null) return null;
    final b = await contextBreakdown();
    return ContextSegments.of(system: b.system, tools: b.tools, messages: _messages, limit: limit);
  }

  // ── 发送、插话、排队 ─────────────────────────────────
  /// AI 生成时又发的消息（显示在输入框上方）。
  List<QueuedMessage> get queue => _core.queue.current.queue;

  /// 请求失败、用户消息被撤回时，要交还给输入框的文字。
  String? get restoredDraft => _core.queue.current.restoredDraft;

  /// 输入框把草稿拿走（拿走就清掉）。
  String? takeRestoredDraft() => _core.queue.takeDraft();

  /// 发一条消息。AI 正在生成时按 [mode] 处理：排队（默认）、插话、中断并发送。
  Future<void> sendToAgent(String text, {List<Map<String, dynamic>> images = const [], SendMode mode = SendMode.queue}) => _sending.send(text, images: images, mode: mode);

  /// 排队里的一条：立即发送（中断当前这一轮，马上发它）。
  void sendQueuedNow(QueuedMessage msg) => _sending.sendQueuedNow(msg);

  /// 排队里的一条：改为插话（下一步就让模型看到）。带图片的不能插话。
  void steerQueued(QueuedMessage msg) => _sending.steerQueued(msg);

  /// 排队里的一条：撤回（文字交还输入框）。
  void withdrawQueued(QueuedMessage msg) => _sending.withdrawQueued(msg);

  /// 上一轮出错或被停止后，排着的消息先不自动发（等她点“继续发送”）。
  bool get queuePaused => _core.queue.current.paused;

  /// 排队消息的编辑 / 删除 / 继续发送 / 清空（规矩在 lib/session/send_flow.dart）。
  void editQueued(QueuedMessage msg, String text) => _sending.editQueued(msg, text);
  void deleteQueued(QueuedMessage msg) => _sending.deleteQueued(msg);
  void resumeQueue() => _sending.resumeQueue();
  void clearQueue() => _sending.clearQueue();

  void stopAgent() => _sending.stop();

  // ── 图片附件（规矩在 lib/session/attachments.dart）──────
  static const int maxAttachments = attachments.kMaxAttachments;
  static const int maxAttachmentBytes = attachments.kMaxAttachmentBytes;
  static const String attachmentsDir = attachments.kAttachmentsDir;

  static String? imageMimeOf(String name) => attachments.imageMimeOf(name);

  /// 把选中的图片存进工作区的附件目录，返回消息里要带的 `{path, mime}`。
  Future<Map<String, dynamic>> saveAttachment(List<int> bytes, String name) => attachments.saveAttachment(guard, bytes, name);

  /// 引用工作区里已有的图片文件当附件。
  Map<String, dynamic> attachWorkspaceFile(String rel) => attachments.attachWorkspaceFile(guard, rel);

  // ── 上一轮没正常结束（App 被关掉）之后 ─────────────────
  /// 点“继续”：让 Agent 从中断的地方接着做。不会自动重跑任何一步——做什么由模型看着记录重新决定，该确认的照样确认。
  Future<void> resumeInterrupted() async {
    if (agentBusy) return;
    _core.clearInterrupted(_active);
    await _core.journalOf(_active.convId).dismiss();
    await sendToAgent(kResumeText);
  }

  /// 点“不用了”：收掉提示，停在这里。
  Future<void> dismissInterrupted() async {
    _core.clearInterrupted(_active);
    await _core.journalOf(_active.convId).dismiss();
  }

  /// 读一份转存的命令输出（“查看完整输出”用）；被清理掉了返回 null。
  Future<String?> readCommandOutput(String rel) => CommandOutputStore(guard).read(rel);

  // ── / 指令背后的动作 ─────────────────────────────────
  /// /compact：把当前对话压缩成摘要。返回给用户看的一句话。
  Future<String> compactConversation() async {
    if (agentBusy) return 'AI 正在生成，等它停下再压缩';
    await loadChat();
    final run = _active;
    if (run.messages.length < 2) return '对话还很短，不需要压缩';
    run.setBusy(true);
    String? error;
    try {
      final before = AgentRunner.estimateTokens(run.messages);
      error = await compactRun(_core, _toolbox, run);
      if (error == null) {
        _core.rebuildItems(run); // 摘要那条会显示成“已压缩较早的对话”，点开能看
        run.add(NoticeItem('已把之前的对话压缩成摘要（估算从 ${before ~/ 1000}K 降到 ${AgentRunner.estimateTokens(run.messages) ~/ 1000}K）。原来的逐条记录不再保留。'));
      }
    } finally {
      run.setBusy(false);
      await _core.saveRun(run);
    }
    return error ?? '已压缩';
  }

  /// /export：把当前对话导出成工作区里的一个 Markdown 文件，返回相对路径。
  Future<String?> exportConversation() async {
    await loadChat();
    if (_messages.isEmpty) return null;
    final rel = await writeConversationExport(guard, conversationMarkdown(conversationTitle, _messages));
    filesChanged();
    return rel;
  }

  void dispose() {
    stopAgent();
    for (final r in _core.runs.values) {
      r.runner?.cancel();
    }
    _core.disposed = true;
    _core.releaseWhenIdle();
    if (!app.disposed) {
      app.container.invalidate(filesRevProvider(this));
      app.container.invalidate(terminalsProvider(this)); // 会话的进程在这里收掉
      app.container.invalidate(previewProvider(this)); // 预览服务器在这里停掉
      app.container.invalidate(backendRunProvider(this)); // 还在等的后端“运行”作废
      app.container.invalidate(backgroundTasksProvider(this)); // 后台命令在这里全部停掉
    }
  }
}
