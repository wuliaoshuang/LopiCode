import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:lopicode/agent/agent_runner.dart';
import 'package:lopicode/agent/agent_tools.dart';
import 'package:lopicode/agent/automation.dart';
import 'package:lopicode/agent/command_runner.dart';
import 'package:lopicode/agent/model_config.dart';
import 'package:lopicode/agent/presets.dart';
import 'package:lopicode/agent/quota.dart';
import 'package:lopicode/agent/skills.dart';
import 'package:lopicode/agent/team.dart';
import 'package:lopicode/agent/usage.dart';
import 'package:lopicode/agent/web_search.dart';
import 'package:lopicode/app_services.dart';
import 'package:lopicode/core/path_guard.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/safe_file.dart';
import 'package:lopicode/core/stores.dart';
import 'package:lopicode/preview/preview_server.dart';
import 'package:lopicode/runtime/linux_command_runner.dart';
import 'package:lopicode/runtime/linux_shell_backend.dart';
import 'package:lopicode/session/automation_tools.dart';
import 'package:lopicode/session/chat_models.dart';
import 'package:lopicode/session/conversation.dart';
import 'package:lopicode/ssh/ssh_config.dart';
import 'package:lopicode/ssh/ssh_connector.dart';
import 'package:lopicode/state/workspace_chat.dart';
import 'package:lopicode/state/workspace_conversations.dart';
import 'package:lopicode/state/workspace_files.dart';
import 'package:lopicode/state/workspace_preview.dart';
import 'package:lopicode/state/workspace_terminals.dart';
import 'package:lopicode/terminal/terminal_session.dart';
import 'package:path/path.dart' as p;

export 'package:lopicode/session/chat_models.dart';
export 'package:lopicode/session/conversation.dart';

/// 一段对话的运行状态（条目、忙不忙、这一轮的用量）：就是 [ChatRunNotifier]，沿用老名字。
typedef ConvRun = ChatRunNotifier;

class _Semaphore {
  _Semaphore(this.max);
  int max;
  int _held = 0;
  final List<Completer<void>> _waiters = [];

  Future<void> acquire() async {
    if (_held < max) {
      _held++;
      return;
    }
    final c = Completer<void>();
    _waiters.add(c);
    await c.future;
  }

  void release() {
    if (_waiters.isNotEmpty) {
      _waiters.removeAt(0).complete(); // 名额直接转给下一个
    } else {
      _held--;
    }
  }
}

/// 打开一个项目期间的全部运行状态：终端会话、预览服务器、Agent 对话。
/// 各个页面共用这一个对象，切页面不丢状态。
class ProjectSession {
  ProjectSession(this.app, this.project, {this.headless = false}) : guard = project.guard {
    if (!headless && !app.disposed) app.container.read(terminalsProvider(this));
  }

  /// 不带界面（自动化任务在别的工作区里跑时用）：不开终端。
  final bool headless;

  final AppServices app;
  final Project project;
  final PathGuard guard;

  /// 预览用的本机小服务器：归 [previewProvider] 管，这里只是转一手。
  PreviewServer get preview => app.container.read(previewProvider(this).notifier).server;

  // ── 文件改动 ──────────────────────────────────────────
  /// 项目文件有变化：文件树、预览订阅 [filesRevProvider] 跟着刷新。
  void filesChanged() {
    if (_disposed || app.disposed) return;
    app.container.read(filesRevProvider(this).notifier).bump();
  }

  // ── 终端 ─────────────────────────────────────────────
  TerminalsState get _terminals => _disposed || app.disposed ? const TerminalsState() : app.container.read(terminalsProvider(this));
  TerminalsNotifier get _terminalsCtl => app.container.read(terminalsProvider(this).notifier);
  List<TerminalSession> get terminals => _terminals.sessions;
  int get activeTerminal => _terminals.active;

  /// 测试用：换掉伪终端的创建方式。
  PtySpawner? ptySpawner;

  /// 测试用：换掉“带参数的伪终端”（进 Ubuntu 用的那种）。
  PtyArgsSpawner? linuxPtySpawner;

  /// 新开一个本机会话。Ubuntu 环境能用就进 Ubuntu，否则是手机自带的 sh。
  /// [forceLocal] 为 true 时不管环境装没装，都开手机自带的 sh。
  TerminalSession addTerminal({bool forceLocal = false}) => _terminalsCtl.addLocal(forceLocal: forceLocal);

  /// 新开一个 SSH 会话。[onUnknownHost] 在第一次连这台主机时弹指纹确认。
  TerminalSession addSshTerminal(SshConfig config, {HostKeyPrompt? onUnknownHost}) => _terminalsCtl.addSsh(config, onUnknownHost: onUnknownHost);

  void closeTerminal(int index) => _terminalsCtl.close(index);

  void selectTerminal(int index) => _terminalsCtl.select(index);

  // ── Agent ────────────────────────────────────────────
  /// 这个工作区已经关掉了：之后不许再往状态里写。
  bool get disposed => _disposed;
  bool _disposed = false;

  /// 每段对话的运行状态（用到才建）。
  final Map<String, ConvRun> _runs = {};

  ConvRun _runOf(Conversation conv) => _runs.putIfAbsent(
    conv.id,
    // 应用已经退出时拿不到状态容器：临时建一个不接容器的，只记不通知
    () => (app.disposed ? ChatRunNotifier((this, conv.id)) : app.container.read(chatRunProvider((this, conv.id)).notifier))..seed(conv),
  );
  late final PendingCardsNotifier _cards = app.disposed ? PendingCardsNotifier(this) : app.container.read(pendingCardsProvider(this).notifier);
  late final SendQueueNotifier _queue = app.disposed ? SendQueueNotifier(this) : app.container.read(sendQueueProvider(this).notifier);
  ConvRun get _active => _runOf(activeConversation);

  /// 当前对话显示的条目。
  List<ChatItem> get chat => _active.items;
  List<Map<String, dynamic>> get _messages => _active.messages;

  /// 当前对话是不是正在生成。
  bool get agentBusy => _active.busy;
  bool _chatLoaded = false;

  /// 请求失败、用户消息被撤回时，要交还给输入框的文字。
  String? get restoredDraft => _queue.current.restoredDraft;

  /// 输入框把草稿拿走（拿走就清掉）。
  String? takeRestoredDraft() => _queue.takeDraft();

  // 对话：一个工作区可以有多段对话。目录（有哪些、当前哪段、项目规则）在 [conversationsProvider]；
  // 每段对话的消息各存一个文件（第一段沿用 chat.json，其余是 chat-<id>.json）。子代理的对话也在目录里，带着上级的 id。
  // 应用已经退出时拿不到（null）：这时候什么都不读、不写
  late final ConversationsNotifier? _convs = app.disposed ? null : app.container.read(conversationsProvider(this).notifier);
  final ConversationsState _noDir = ConversationsState();
  ConversationsState get _dir => _convs?.current ?? _noDir;
  List<Conversation> get conversations => _dir.all;
  String get activeConversationId => _dir.activeId;
  Conversation get activeConversation => _dir.active;
  Conversation? conversationById(String? id) => _dir.byId(id);

  /// 侧边栏里列的对话：不含子代理的。
  List<Conversation> get topConversations => _dir.top;

  /// 顶栏标题：还没说话的对话叫“新对话”。
  String get conversationTitle => activeConversation.title.isEmpty ? '新对话' : activeConversation.title;

  File _reserved(String name) => File(guard.resolve('${PathGuard.reservedDir}/$name', allowReserved: true));
  File _chatFileOf(String id) => _reserved(id == 'main' ? 'chat.json' : 'chat-$id.json');

  /// 项目规则：她写给 Agent 的长期要求，拼在系统提示词后面。
  String get projectRules => _dir.projectRules;

  Future<void> setProjectRules(String text) async {
    await _convs?.setProjectRules(text);
  }

  /// 目录里这段对话的最新一份（闭包里拿着的可能是旧的）。
  Conversation _live(Conversation c) => conversationById(c.id) ?? c;

  // ── 模型 / 权限 / 计划模式 / 预设（每段对话各自一份）──────────
  /// 这段对话的“根”：子代理的权限、计划模式、预设都跟着最上面那段主对话走。
  Conversation rootOf(Conversation conv) => _dir.rootOf(conv);

  ResolvedModel? modelOf(Conversation conv) => app.models.resolve(conv.selection) ?? app.models.defaultForNewChat();
  ResolvedModel? get currentModel => modelOf(activeConversation);

  Future<void> setModel(ModelSelection selection) async {
    _convs?.update(activeConversationId, (c) => c.copyWith(selection: selection));
    await app.models.setLastSelection(selection);
    await _saveIndex();
  }

  PermissionLevel get defaultPermission => PermissionLevel.byId(app.settings.getString(SettingKeys.defaultPermission, 'workspace'));
  PermissionLevel permissionOf(Conversation conv) => conv.permission == null ? defaultPermission : PermissionLevel.byId(conv.permission);
  PermissionLevel get permission => permissionOf(activeConversation);

  Future<void> setPermission(PermissionLevel level) async {
    _convs?.update(activeConversationId, (c) => c.copyWith(permission: level.id));
    await _saveIndex();
  }

  bool get planMode => activeConversation.planMode;

  Future<void> setPlanMode(bool on) async {
    _convs?.update(activeConversationId, (c) => c.copyWith(planMode: on));
    await _saveIndex();
  }

  AgentPreset presetOf(Conversation conv) => app.presets.byId(conv.presetId ?? app.presets.defaultId);
  AgentPreset get preset => presetOf(activeConversation);

  Future<void> setPreset(String id) async {
    _convs?.update(activeConversationId, (c) => c.copyWith(presetId: id));
    await _saveIndex();
  }

  /// 当前对话是不是点过“本对话都允许”。只在内存里：重启 App 后恢复逐次询问。
  bool get autoAllowActive => _cards.autoAllowed(activeConversationId);

  void clearAutoAllow() => _cards.clearAutoAllow(activeConversationId);

  // ── 读写对话记录 ─────────────────────────────────────
  Future<List<Map<String, dynamic>>> _readMessages(String id) async {
    // 文件坏了：备份后当空对话
    final decoded = await readJsonFile(_chatFileOf(id), accept: (j) => j is List, label: '对话记录');
    if (decoded is! List) return [];
    return [
      for (final m in decoded)
        if (m is Map<String, dynamic>) m,
    ];
  }

  Future<void> _ensureLoaded(ConvRun run) async {
    if (run.loaded) return;
    run.markLoaded();
    run.messages = await _readMessages(run.convId);
    _rebuildItems(run);
  }

  Future<void>? _loading;

  Future<void> loadChat() => _loading ??= _loadChat();

  Future<void> _loadChat() async {
    if (_chatLoaded) return;
    await app.ready();
    await _convs?.load();
    await _ensureLoaded(_active);
    // 老版本只有一个 chat.json、没有标题：从第一句话补一个。
    if (activeConversation.title.isEmpty) _retitle();
    _chatLoaded = true;
  }

  void _retitle() {
    final first = _messages.where((m) => m['role'] == 'user').firstOrNull;
    if (first == null) return;
    _convs?.update(activeConversationId, (c) => c.copyWith(title: _titleFrom('${first['content'] ?? ''}')));
  }

  static String _titleFrom(String text) {
    final line = text.trim().split('\n').first.trim();
    return line.length > 18 ? '${line.substring(0, 18)}…' : line;
  }

  Future<void> _saveIndex() async => _convs?.save();

  String _newConvId() => _convs?.newId() ?? DateTime.now().microsecondsSinceEpoch.toRadixString(36);

  Future<void> _saveRun(ConvRun run) async {
    try {
      final file = _chatFileOf(run.conv.id);
      await writeJsonAtomic(file, run.messages);
    } on FileSystemException {
      // 存不了就算了：不影响当前对话
    }
    await _saveIndex();
  }

  /// 开一段新对话。当前这段还是空的就直接留在这里，不堆空对话。
  Future<void> newConversation() async {
    if (agentBusy) return;
    await loadChat();
    if (_messages.isEmpty && chat.isEmpty) return;
    final conv = Conversation(_newConvId(), '', DateTime.now(), selection: app.models.defaultForNewChat()?.selection, presetId: app.presets.defaultId);
    _convs?.add(conv, front: true, activate: true);
    _runOf(conv).markLoaded();
    _queue.clear();
    await _saveIndex();
  }

  Future<void> selectConversation(String id) async {
    if (agentBusy || id == activeConversationId || !conversations.any((c) => c.id == id)) return;
    await loadChat();
    _convs?.activate(id);
    _queue.clear();
    await _ensureLoaded(_active);
  }

  /// 子代理谱系：[rootId] 这段对话派出的全部子代理（含子代理再派出的），按派出顺序。
  List<Conversation> descendantsOf(String rootId) => _dir.descendantsOf(rootId);

  /// 当前对话派出的子代理。
  List<Conversation> get subAgents => descendantsOf(activeConversationId);
  bool isRunning(String conversationId) => _runs[conversationId]?.busy ?? false;

  /// 进子代理对话时用：拿到它的条目（没读过就先读盘）。
  Future<ConvRun?> openRun(String conversationId) async {
    final conv = conversationById(conversationId);
    if (conv == null) return null;
    final run = _runOf(conv);
    await _ensureLoaded(run);
    return run;
  }

  /// 删除当前对话（文件不受影响），它派出的子代理对话一起删。删到一段不剩时留一段空的。
  Future<void> deleteConversation() async {
    if (agentBusy) return;
    final id = activeConversationId;
    final doomed = [id, for (final c in descendantsOf(id)) c.id];
    for (final d in doomed) {
      _runs.remove(d)?.runner?.cancel();
      for (final file in [_chatFileOf(d), _reserved('team-$d.json')]) {
        try {
          if (await file.exists()) await file.delete();
        } on FileSystemException {
          // 删不掉：索引里照样移除
        }
      }
      _boards.remove(d);
      _cards.clearAutoAllow(d);
      if (!app.disposed) app.container.invalidate(chatRunProvider((this, d)));
    }
    _convs?.removeAll(doomed.toSet());
    _queue.clear();
    await _ensureLoaded(_active);
    await _saveIndex();
  }

  String _hostPathOfAttachment(String rel) => p.join(project.dir, rel);

  /// 从接口格式的消息记录重建界面条目（记录是唯一的事实来源）。
  void _rebuildItems(ConvRun run) {
    final items = <ChatItem>[];
    final toolAt = <String, int>{};
    final kids = conversations.where((c) => c.parentId == run.convId).toList()..sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
    var kid = 0;
    for (final m in run.messages) {
      switch (m['role']) {
        case 'user':
          items.add(
            UserItem(
              '${m['content'] ?? ''}',
              images: [
                for (final i in (m['_images'] as List?) ?? const [])
                  if (i is Map) _hostPathOfAttachment('${i['path']}'),
              ],
            ),
          );
        case 'assistant':
          final text = m['content'];
          if (text is String && text.isNotEmpty) items.add(AssistantItem(text));
          for (final c in (m['tool_calls'] as List?) ?? const []) {
            if (c is! Map) continue;
            final fn = c['function'];
            final name = fn is Map ? '${fn['name']}' : '';
            final item = ToolItem(
              '${c['id']}',
              name,
              fn is Map ? '${fn['arguments']}' : '',
              result: '（没有记录到结果）',
              childConversationId: name == 'spawn_agent' && kid < kids.length ? kids[kid++].id : null,
            );
            toolAt[item.callId] = items.length;
            items.add(item);
          }
        case 'tool':
          final at = toolAt['${m['tool_call_id']}'];
          if (at != null) {
            final result = '${m['content'] ?? ''}';
            items[at] = (items[at] as ToolItem).copyWith(result: result, ok: !result.startsWith('错误') && !result.startsWith('用户拒绝'), denied: result.startsWith('用户拒绝'));
          }
      }
      final turn = TurnUsage.fromJson(m['_usage']);
      if (turn != null) items.add(UsageItem(turn));
    }
    run.setItems(items);
  }

  // ── 确认卡 / 提问卡（可能同时来自主智能体和几个子代理，排队一张一张出）────
  PendingApproval? get pendingApproval => _cards.current.approval;
  PendingQuestion? get pendingQuestion => _cards.current.question;

  Future<bool> _requestApproval(ConvRun run, ApprovalRequest request) {
    if (run.unattended) return Future.value(false); // 没人在场：一律按拒绝
    return _cards.requestApproval(PendingApproval(request, conversationId: run.convId, agentName: run.conv.agentName));
  }

  /// 回答最前面那张确认卡。[always]＝“本对话都允许”（这类卡允许的话）。
  void resolveApproval(bool allow, {bool always = false}) => _cards.resolveApproval(
    allow,
    always: always,
    rootOf: (id) {
      final conv = conversationById(id);
      return conv == null ? null : rootOf(conv).id;
    },
    fallbackRoot: activeConversationId,
  );

  Future<String> _askUser(ConvRun run, String question, List<String> options) {
    if (run.unattended) return Future.value('（这是无人值守的自动化任务，没有人能回答。请按最稳妥的做法继续，或者说明卡在哪里。）');
    return _cards.ask(PendingQuestion(question, options, conversationId: run.convId, agentName: run.conv.agentName));
  }

  void answerQuestion(String answer) => _cards.answerQuestion(answer);

  void _dropPendingOf(Set<String> convIds) => _cards.dropOf(convIds);

  // ── 团队任务板 ───────────────────────────────────────
  bool get teamEnabled => app.settings.getBool(SettingKeys.teamEnabled);
  final Map<String, TeamBoard> _boards = {};

  Future<TeamBoard> boardOf(Conversation root) async {
    final existing = _boards[root.id];
    if (existing != null) return existing;
    final board = TeamBoard(file: _reserved('team-${root.id}.json'))..onChanged = _teamChanged;
    _boards[root.id] = board;
    await board.load();
    return board;
  }

  /// 当前对话的任务板（团队没开时也能看，只是 Agent 没有任务板工具）。
  Future<TeamBoard> get teamBoard => boardOf(rootOf(activeConversation));

  void _teamChanged() {
    if (!_disposed && !app.disposed) app.container.read(teamRevProvider(this).notifier).bump();
  }

  // ── 子代理设置 ───────────────────────────────────────
  bool get subagentsEnabled => app.settings.getBool(SettingKeys.subagentEnabled, true);
  int get subagentMaxDepth => (app.settings.get<int>(SettingKeys.subagentMaxDepth) ?? 1).clamp(0, 3);
  int get subagentMaxConcurrent => (app.settings.get<int>(SettingKeys.subagentMaxConcurrent) ?? 2).clamp(1, 4);
  List<String> get subagentAllowedModels => [
    for (final m in app.settings.get<List<dynamic>>(SettingKeys.subagentAllowedModels) ?? const [])
      if (m is String) m,
  ];
  late final _Semaphore _subSlots = _Semaphore(2);

  // ── 系统提示词 ───────────────────────────────────────
  String _systemPromptFor(Conversation conv, Conversation root, List<Skill> skills, {String? taskNote}) {
    root = _live(root);
    final parts = <String>[AgentRunner.defaultSystemPrompt];
    final presetPrompt = presetOf(root).prompt.trim();
    if (presetPrompt.isNotEmpty) parts.add('当前 Agent 预设的要求：\n$presetPrompt');
    final prefs = app.presets.preferences;
    if (prefs.isNotEmpty) parts.add('用户的个人偏好（尽量照做）：\n$prefs');
    if (projectRules.isNotEmpty) parts.add('用户给这个项目定的规则（必须遵守）：\n$projectRules');
    final skillText = SkillStore.promptSection(skills);
    if (skillText.isNotEmpty) parts.add(skillText);
    parts.add(switch (permissionOf(root)) {
      PermissionLevel.view => '当前权限：仅可查看。你只能看，不能改文件、删文件、执行命令（这些工具已经被关掉）。',
      PermissionLevel.workspace => '当前权限：工作区内修改。可以改工作区里的文件；删除文件、执行命令每次要用户确认。',
      PermissionLevel.full => '当前权限：完全权限。删除文件、执行命令不再逐次确认，动手前自己多想一步。',
    });
    if (root.planMode) parts.add('现在是计划模式：只调查、只出计划，不要改任何东西（写文件、删文件、执行命令的工具已经被关掉）。把打算怎么做分步骤写清楚，等用户确认。');
    if (conv.parentId != null) {
      parts.add('你是被上级智能体派出来的子代理“${conv.agentName}”，只负责交给你的这一件事。做完后用一段话汇报结果（做了什么、改了哪些文件、有什么没做成），这段话会原样交回上级。${taskNote ?? ''}');
    } else if (teamEnabled) {
      parts.add('这段对话开了智能体团队：你是“${TeamBoard.lead}”。复杂的事先用 team_task 在任务板上拆成任务（写清负责人、依赖、写入范围），再用 spawn_agent 把任务派给子代理（带上 task_id），最后汇总。');
    }
    return parts.join('\n\n');
  }

  String get systemPrompt => _systemPromptFor(activeConversation, rootOf(activeConversation), const []);

  // ── 组装工具 ─────────────────────────────────────────
  Future<AgentToolbox> _toolboxFor(ConvRun run, Conversation root, List<Skill> skills, {List<String>? writeScope}) async {
    final conv = run.conv;
    final extras = <ExtraTool>[];
    if (!run.unattended) {
      extras.add(
        ExtraTool(
          spec: toolSpec(
            'ask_user',
            '需要用户拿主意时，向用户提一个问题并等他回答。给出 2 到 4 个选项，用户也可以自己写别的回答。',
            {
              'question': {'type': 'string', 'description': '要问的问题'},
              'options': {
                'type': 'array',
                'items': {'type': 'string'},
                'description': '可选的回答',
              },
            },
            ['question'],
          ),
          kind: ToolKind.other,
          run: (args) async {
            final options = [
              for (final o in args['options'] is List ? args['options'] as List : const [])
                if (o is String && o.trim().isNotEmpty) o.trim(),
            ].take(6).toList();
            final answer = await _askUser(run, AgentToolbox.argString(args, 'question'), options);
            return ToolOutcome('用户的回答：$answer');
          },
        ),
      );
    }
    final search = await WebSearchConfig.load(app.settings, app.secrets);
    if (search != null) extras.add((webSearchFactory ?? WebSearchClient.new)(search).tool);
    final skillTool = app.skills.tool(skills);
    if (skillTool != null) extras.add(skillTool);
    if (subagentsEnabled && conv.depth < subagentMaxDepth) extras.add(_spawnTool(run, root, skills));
    if (teamEnabled) extras.addAll((await boardOf(root)).tools(conv.parentId == null ? TeamBoard.lead : conv.agentName));
    if (!run.unattended) extras.addAll(automationTools(store: app.automations, project: project, approve: (request) => _requestApproval(run, request)));
    return AgentToolbox(
      guard: guard,
      runner: commandRunnerFactory?.call() ?? LinuxCommandRunner(app.runtime, guestCwd: project.linuxPath, onOutput: (t) => terminals.firstOrNull?.append(t)),
      requestApproval: (r) => _requestApproval(run, r),
      autoApprove: () => _cards.autoAllowed(root.id),
      // 权限和计划模式每次都现查目录里的最新值：跑到一半改了档位、开了计划模式，下一步就生效
      permission: () => permissionOf(_live(root)),
      planMode: () => _live(root).planMode,
      allowedTools: presetOf(_live(root)).tools,
      writeScope: writeScope,
      extras: extras,
    );
  }

  /// 测试用：换掉执行命令的环境、联网搜索的客户端。
  CommandRunner Function()? commandRunnerFactory;
  WebSearchClient Function(WebSearchConfig config)? webSearchFactory;

  // ── 子代理 ───────────────────────────────────────────
  ExtraTool _spawnTool(ConvRun parent, Conversation root, List<Skill> skills) {
    final allowed = subagentAllowedModels;
    return ExtraTool(
      spec: toolSpec(
        'spawn_agent',
        '派出一个子代理去独立完成一件事。它有自己的上下文（看不到这段对话），所以 task 里要把背景、要求、要交回什么写全。'
            '同一轮里连着派出的几个会同时进行（最多 $subagentMaxConcurrent 个）。它做完后把结果汇报给你。',
        {
          'name': {'type': 'string', 'description': '给它起个短名字，如“前端”“查资料”'},
          'task': {'type': 'string', 'description': '交给它的完整任务说明'},
          if (teamEnabled) 'task_id': {'type': 'string', 'description': '对应任务板上的任务编号（可选）：它会成为负责人，并且只能改这个任务写入范围内的文件'},
          if (allowed.isNotEmpty) 'model': {'type': 'string', 'enum': allowed, 'description': '可选：让它用别的模型（渠道ID/模型ID）；省略则和你用同一个'},
        },
        ['task'],
      ),
      kind: ToolKind.other,
      run: (args) => _spawn(parent, root, skills, args),
    );
  }

  Future<ToolOutcome> _spawn(ConvRun parent, Conversation root, List<Skill> skills, Map<String, dynamic> args) async {
    final task = AgentToolbox.argString(args, 'task');
    // 层数限制在代码里再查一遍：就算工具被硬调用也派不出去。
    if (!subagentsEnabled) return ToolOutcome('错误：子代理功能已在设置里关闭', ok: false);
    if (parent.conv.depth >= subagentMaxDepth) return ToolOutcome('错误：已经到了委派层数上限（$subagentMaxDepth 层），不能再往下派', ok: false);
    var name = '${args['name'] ?? ''}'.trim();
    if (name.isEmpty) name = '子代理';
    if (name.length > 12) name = name.substring(0, 12);
    final siblings = conversations.where((c) => rootOf(c).id == root.id && c.parentId != null).length;
    if (siblings >= 24) return ToolOutcome('错误：这段对话已经派出 24 个子代理，达到上限', ok: false);
    if (conversations.any((c) => c.parentId != null && rootOf(c).id == root.id && c.agentName == name)) name = '$name${siblings + 1}';

    // 模型：默认跟随上级；要换只能换成设置里允许的。
    var selection = modelOf(parent.conv)?.selection;
    final wanted = args['model'];
    if (wanted is String && wanted.trim().isNotEmpty) {
      final parts = wanted.trim().split('/');
      final ok = subagentAllowedModels.contains(wanted.trim()) && parts.length >= 2;
      final sel = ok ? ModelSelection(parts.first, parts.sublist(1).join('/')) : null;
      if (sel == null || app.models.resolve(sel) == null) {
        return ToolOutcome('错误：模型 $wanted 不在允许子代理使用的模型里。省略 model 参数就会和你用同一个模型', ok: false);
      }
      selection = sel;
    }

    // 任务板：认领任务，拿到写入范围。
    List<String>? scope;
    TeamBoard? board;
    String? taskId;
    if (teamEnabled && args['task_id'] is String && (args['task_id'] as String).trim().isNotEmpty) {
      board = await boardOf(root);
      taskId = (args['task_id'] as String).trim();
      try {
        final t = await board.update(taskId, status: TaskStatus.doing, owner: name);
        scope = t.scope.isEmpty ? null : [...t.scope];
      } on TeamException catch (e) {
        return ToolOutcome('错误：${e.message}', ok: false);
      }
    } else if (teamEnabled) {
      await (await boardOf(root)).addMember(name, '子代理');
    }

    final child = Conversation(_newConvId(), _titleFrom(task), DateTime.now(), parentId: parent.conv.id, depth: parent.conv.depth + 1, agentName: name, selection: selection);
    _convs?.add(child);
    final run = _runOf(child)
      ..markLoaded()
      ..unattended = parent.unattended;
    // 让界面上那张工具卡能点进这段子对话。
    final card = parent.items.whereType<ToolItem>().where((t) => t.name == 'spawn_agent' && t.running && t.childConversationId == null).firstOrNull;
    if (card != null) parent.replace(card, card.copyWith(childConversationId: child.id));
    await _saveIndex();

    _subSlots.max = subagentMaxConcurrent;
    await _subSlots.acquire();
    String result;
    var failed = false;
    try {
      if (parent.runner?.isCancelled ?? false) {
        result = '用户已停止，子代理没有开始。';
        failed = true;
      } else {
        final outcome = await _execute(run, task, root: root, skills: skills, writeScope: scope, taskNote: scope == null ? null : '你只能改这些位置的文件：${scope.join('、')}。');
        result = outcome.text;
        failed = outcome.failed;
        // 子代理花的用量记在上级这一轮名下（可以分开看）。
        final spent = run.turn;
        if (spent != null && spent.totals.requests > 0) parent.turn?.children.add(ChildUsage(name, spent));
      }
    } finally {
      _subSlots.release();
    }
    if (board != null && taskId != null) {
      final t = board.task(taskId);
      if (t != null && t.status == TaskStatus.doing) {
        // 子代理没自己更新任务状态：正常结束算完成，出错退回待办。
        await board.update(taskId, status: failed ? TaskStatus.todo : TaskStatus.done, note: failed ? '子代理没做完：${_clip(result, 80)}' : (t.note.isEmpty ? '子代理结束时自动标记完成' : t.note));
      }
    }
    final text = result.trim().isEmpty ? '（子代理没有给出汇报）' : _clip(result.trim(), 8000);
    return ToolOutcome('子代理“$name”的汇报：\n$text', ok: !failed, changedFiles: true);
  }

  static String _clip(String s, int max) => s.length > max ? '${s.substring(0, max)}…' : s;

  // ── 自动化任务（Agent 侧的两个工具在 lib/session/automation_tools.dart）──
  /// 到点了：在这个工作区里新开一段对话，无人值守地执行 [a] 的指令。不切换当前对话。
  Future<AutomationRun> runAutomation(Automation a) async {
    await loadChat();
    final startedAt = DateTime.now().toUtc();
    final conv = Conversation(
      _newConvId(),
      _titleFrom('[自动] ${a.title}'),
      DateTime.now(),
      selection: app.models.defaultForNewChat()?.selection,
      permission: PermissionLevel.byId(a.permission).id,
      presetId: app.presets.defaultId,
      auto: true,
    );
    _convs?.add(conv, front: true);
    final run = _runOf(conv)
      ..markLoaded()
      ..unattended = true;
    await _saveIndex();
    final skills = await app.skills.enabled(workspaceDir: project.dir);
    final outcome = await _execute(run, a.instruction, root: conv, skills: skills);
    return AutomationRun(startedAt, outcome.failed ? 'failed' : 'ok', _clip(outcome.text.trim().isEmpty ? '（没有输出）' : outcome.text.trim(), 300));
  }

  // ── 跑一段对话（主对话、子代理、自动化共用）────────────────
  Future<({String text, bool failed})> _execute(
    ConvRun run,
    String text, {
    required Conversation root,
    required List<Skill> skills,
    List<Map<String, dynamic>> images = const [],
    List<String>? writeScope,
    String? taskNote,
  }) async {
    run.setBusy(true);
    run.add(UserItem(text, images: [for (final i in images) _hostPathOfAttachment('${i['path']}')]));
    _convs?.update(run.convId, (c) => c.copyWith(updatedAt: DateTime.now()));

    final resolved = modelOf(run.conv);
    final client = await app.createChatClient(resolved);
    final runner = AgentRunner(
      client: client,
      history: run.messages,
      systemPrompt: _systemPromptFor(run.conv, root, skills, taskNote: taskNote),
      toolbox: await _toolboxFor(run, root, skills, writeScope: writeScope),
      vision: resolved?.model.vision ?? false,
      loadImage: (path) async {
        try {
          return await File(guard.resolve(path)).readAsBytes();
        } on Exception {
          return null;
        }
      },
      maxParallel: subagentMaxConcurrent,
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
            if (identical(run, _active)) _queue.dropSteered(text);
          case ToolStarted(:final callId, :final name, :final arguments):
            run.add(ToolItem(callId, name, arguments));
            turn.steps.add(ToolStep(callId, name));
            toolClocks[callId] = Stopwatch()..start();
          case ToolFinished(:final callId, :final outcome):
            final item = run.items.whereType<ToolItem>().lastWhere((t) => t.callId == callId);
            run.replace(item, item.copyWith(result: outcome.text, ok: outcome.ok, denied: outcome.denied));
            if (outcome.changedFiles) filesChanged();
            turn.steps.whereType<ToolStep>().where((t) => t.callId == callId).lastOrNull
              ?..ms = toolClocks.remove(callId)?.elapsedMilliseconds
              ..ok = outcome.ok;
          case RequestFinished(:final usage, :final ms, :final firstMs, :final startedAt):
            turn.steps.add(RequestStep(RequestUsage(usage: usage, ms: ms, firstMs: firstMs, startedAt: startedAt, cost: usage == null ? null : price?.cost(usage))));
            if (usage != null) _convs?.update(run.convId, (c) => c.copyWith(lastInput: usage.input));
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
                if (identical(run, _active)) _queue.setDraft((run.items[lastUser] as UserItem).text);
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
      _dropPendingOf({run.conv.id});
      run.setBusy(false);
      run.runner = null;
      turn.ms = clock.elapsedMilliseconds;
      _recordTurn(run, turn);
      await _saveRun(run);
      _releaseWhenIdle();
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
  void _recordTurn(ConvRun run, TurnUsage turn) {
    final totals = turn.totals;
    if (totals.requests == 0) return; // 一次请求都没发出去（没配模型、被额度拦下）：不显示
    // 子代理的用量由上级那一轮统一算进主对话；这里只累计到它自己这段对话上。
    _convs?.update(run.convId, (c) => c.withTurn(totals));
    // 用户消息被撤回时（模型一个字没回），最后一条是上一轮的，别盖掉上一轮的记录。
    if (run.messages.isNotEmpty && !run.messages.last.containsKey('_usage')) {
      run.messages.last['_usage'] = turn.toJson();
    }
    run.add(UsageItem(turn));
  }

  /// 按调用 id 在已加载的对话里找那次工具调用（轨迹的步骤详情用）。
  ToolItem? findToolItem(String callId) {
    for (final run in _runs.values) {
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
    final box = await _toolboxFor(_runOf(conv), root, skills);
    return (system: estimateTextTokens(_systemPromptFor(conv, root, skills)), tools: estimateTextTokens(jsonEncode(box.specs)), messages: AgentRunner.estimateTokens(_messages));
  }

  // ── 发送、插话、排队 ─────────────────────────────────
  /// AI 生成时又发的消息（显示在输入框上方）。
  List<QueuedMessage> get queue => _queue.current.queue;
  bool _stoppedByUser = false;
  QueuedMessage? _sendAfterStop;

  /// 发一条消息。AI 正在生成时按 [mode] 处理：排队（默认）、插话、中断并发送。
  Future<void> sendToAgent(String text, {List<Map<String, dynamic>> images = const [], SendMode mode = SendMode.queue}) async {
    if (text.trim().isEmpty && images.isEmpty) return;
    if (text.trim().isEmpty) text = '（见附件）';
    await loadChat();
    final run = _active;
    if (run.busy) {
      final msg = QueuedMessage(text, images: images, steer: mode == SendMode.steer && images.isEmpty);
      switch (mode) {
        case SendMode.steer when images.isEmpty:
          _queue.add(msg);
          run.runner?.steer(text);
        case SendMode.interrupt:
          _sendAfterStop = msg;
          stopAgent();
        default:
          _queue.add(msg);
      }
      return;
    }
    _stoppedByUser = false;
    _queue.setDraft(null);
    // 第一句话当标题；没选过模型就用新对话默认；最近说过话的排最前
    _convs?.update(run.convId, (c) => c.copyWith(title: c.title.isEmpty ? _titleFrom(text) : null, selection: c.selection ?? app.models.defaultForNewChat()?.selection), toFront: true);
    final conv = run.conv;
    final skills = await app.skills.enabled(workspaceDir: project.dir);
    try {
      await _execute(run, text, root: conv, skills: skills, images: images);
    } finally {
      await _afterRun();
    }
  }

  Future<void> _afterRun() async {
    // 没来得及交给模型的插话：改成排队，不丢。
    _queue.unsteerAll();
    final interrupt = _sendAfterStop;
    _sendAfterStop = null;
    QueuedMessage? next;
    if (interrupt != null) {
      next = interrupt;
    } else if (!_stoppedByUser && queue.isNotEmpty && restoredDraft == null) {
      next = _queue.takeFirst();
    }
    if (next != null && !_disposed) {
      // 用 unawaited：上一轮的 Future 先结束，界面状态不会卡在“生成中”。
      unawaited(sendToAgent(next.text, images: next.images));
    }
  }

  /// 排队里的一条：立即发送（中断当前这一轮，马上发它）。
  void sendQueuedNow(QueuedMessage msg) {
    if (!_queue.remove(msg)) return;
    _active.runner?.withdrawSteer(msg.text);
    if (agentBusy) {
      _sendAfterStop = msg;
      stopAgent();
    } else {
      unawaited(sendToAgent(msg.text, images: msg.images));
    }
  }

  /// 排队里的一条：改为插话（下一步就让模型看到）。带图片的不能插话。
  void steerQueued(QueuedMessage msg) {
    if (!queue.contains(msg) || msg.steer || msg.images.isNotEmpty || !agentBusy) return;
    _queue.setSteer(msg, true);
    _active.runner?.steer(msg.text);
  }

  /// 排队里的一条：撤回（文字交还输入框）。
  void withdrawQueued(QueuedMessage msg) {
    if (!_queue.remove(msg)) return;
    _active.runner?.withdrawSteer(msg.text);
    _queue.setDraft(msg.text);
  }

  void stopAgent() {
    _stoppedByUser = true;
    final ids = {activeConversationId, for (final c in descendantsOf(activeConversationId)) c.id};
    for (final id in ids) {
      _runs[id]?.runner?.cancel();
    }
    _dropPendingOf(ids);
  }

  // ── 图片附件 ─────────────────────────────────────────
  static const int maxAttachments = 9;
  static const int maxAttachmentBytes = 8 * 1024 * 1024;
  static const String attachmentsDir = '.lopicode-attachments';

  static String? imageMimeOf(String name) => switch (p.extension(name).toLowerCase()) {
    '.png' => 'image/png',
    '.jpg' || '.jpeg' => 'image/jpeg',
    '.gif' => 'image/gif',
    '.webp' => 'image/webp',
    _ => null,
  };

  /// 把选中的图片存进工作区的附件目录，返回消息里要带的 `{path, mime}`。
  Future<Map<String, dynamic>> saveAttachment(List<int> bytes, String name) async {
    final mime = imageMimeOf(name);
    if (mime == null) throw const FormatException('只支持 png、jpg、gif、webp 图片');
    if (bytes.length > maxAttachmentBytes) throw const FormatException('图片太大（上限 8MB）');
    final rel = '$attachmentsDir/${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${p.extension(name).toLowerCase()}';
    final file = File(guard.resolve(rel));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
    return {'path': rel, 'mime': mime};
  }

  /// 引用工作区里已有的图片文件当附件。
  Map<String, dynamic> attachWorkspaceFile(String rel) {
    final mime = imageMimeOf(rel);
    if (mime == null) throw const FormatException('只支持 png、jpg、gif、webp 图片');
    guard.resolve(rel);
    return {'path': rel, 'mime': mime};
  }

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
      error = await compactHistory(await app.createChatClient(modelOf(run.conv)), run.messages);
      if (error == null) {
        _rebuildItems(run);
        run.add(NoticeItem('已把之前的对话压缩成摘要（估算从 ${before ~/ 1000}K 降到 ${AgentRunner.estimateTokens(run.messages) ~/ 1000}K）。原来的逐条记录不再保留。'));
      }
    } finally {
      run.setBusy(false);
      await _saveRun(run);
    }
    return error ?? '已压缩';
  }

  /// /export：把当前对话导出成工作区里的一个 Markdown 文件，返回相对路径。
  Future<String?> exportConversation() async {
    await loadChat();
    if (_messages.isEmpty) return null;
    final out = StringBuffer('# $conversationTitle\n\n');
    for (final m in _messages) {
      switch (m['role']) {
        case 'user':
          out.writeln('## 我\n\n${m['content'] ?? ''}\n');
          for (final i in (m['_images'] as List?) ?? const []) {
            if (i is Map) out.writeln('（附件：${i['path']}）\n');
          }
        case 'assistant':
          if (m['content'] is String && (m['content'] as String).isNotEmpty) out.writeln('## Agent\n\n${m['content']}\n');
          for (final c in (m['tool_calls'] as List?) ?? const []) {
            if (c is Map && c['function'] is Map) out.writeln('> 调用工具 `${(c['function'] as Map)['name']}`：`${_clip('${(c['function'] as Map)['arguments']}', 300)}`\n');
          }
        case 'tool':
          out.writeln('> 工具结果：${_clip('${m['content'] ?? ''}'.replaceAll('\n', ' '), 300)}\n');
      }
    }
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final rel = 'exports/对话-${now.year}${two(now.month)}${two(now.day)}-${two(now.hour)}${two(now.minute)}${two(now.second)}.md';
    final file = File(guard.resolve(rel));
    await file.parent.create(recursive: true);
    await file.writeAsString(out.toString());
    filesChanged();
    return rel;
  }

  /// 工作区关掉以后，等跑到一半的那几轮都收完尾（存好记录和目录）再把对话目录的状态放掉。
  void _releaseWhenIdle() {
    if (!_disposed || _released || _runs.values.any((r) => r.busy)) return;
    _released = true;
    if (app.disposed) return;
    final box = app.container;
    box.invalidate(conversationsProvider(this));
    for (final id in _runs.keys) {
      box.invalidate(chatRunProvider((this, id)));
    }
    box.invalidate(pendingCardsProvider(this));
    box.invalidate(sendQueueProvider(this));
    box.invalidate(teamRevProvider(this));
  }

  /// 关掉并且收完尾了：对话目录的状态已经放掉。
  bool get released => _released;
  bool _released = false;

  void dispose() {
    stopAgent();
    for (final r in _runs.values) {
      r.runner?.cancel();
    }
    _disposed = true;
    _releaseWhenIdle();
    if (!app.disposed) {
      app.container.invalidate(filesRevProvider(this));
      app.container.invalidate(terminalsProvider(this)); // 会话的进程在这里收掉
      app.container.invalidate(previewProvider(this)); // 预览服务器在这里停掉
    }
  }
}
