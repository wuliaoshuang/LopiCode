import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
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
import 'package:lopicode/ssh/ssh_config.dart';
import 'package:lopicode/ssh/ssh_connector.dart';
import 'package:lopicode/ssh/ssh_shell_backend.dart';
import 'package:lopicode/terminal/terminal_session.dart';
import 'package:path/path.dart' as p;

/// 对话里显示的一项。
sealed class ChatItem {}

class UserItem extends ChatItem {
  UserItem(this.text, {this.images = const []});
  final String text;

  /// 图片附件在手机上的完整路径。
  final List<String> images;
}

class AssistantItem extends ChatItem {
  AssistantItem(this.text, {this.streaming = false});
  String text;
  bool streaming;
}

class ToolItem extends ChatItem {
  ToolItem(this.callId, this.name, this.arguments);
  final String callId;
  final String name;
  final String arguments;
  String? result;
  bool ok = true;
  bool denied = false;
  bool get running => result == null;

  /// 派子代理的调用：对应的子对话。
  String? childConversationId;
}

/// 上下文占用。
class ContextUsage {
  const ContextUsage(this.used, this.limit, {required this.estimated});
  final int used;
  final int limit;

  /// true＝按字数估的“预计下次请求”；false＝接口返回的“上次请求”。
  final bool estimated;
  double get fraction => (used / limit).clamp(0.0, 1.0);
}

/// 一轮结束后，回复下方那行用量。
class UsageItem extends ChatItem {
  UsageItem(this.turn);
  final TurnUsage turn;
}

class NoticeItem extends ChatItem {
  NoticeItem(this.text, {this.isError = false});
  final String text;
  final bool isError;
}

/// 工作区里的一段对话。子代理的对话也是一段对话，只是有上级（[parentId]）。
class Conversation {
  Conversation(
    this.id,
    this.title,
    this.updatedAt, {
    this.parentId,
    this.depth = 0,
    this.agentName = '',
    this.selection,
    this.permission,
    this.planMode = false,
    this.presetId,
    this.auto = false,
    UsageTotals? usage,
    this.lastInput,
  }) : usage = usage ?? UsageTotals();
  final String id;
  String title;
  DateTime updatedAt;

  /// 上级对话；主对话为 null。
  final String? parentId;

  /// 委派层数：主对话 0，它派出的子代理 1……
  final int depth;

  /// 子代理的名字。
  final String agentName;

  /// 这段对话选的模型；null 表示用新对话默认。
  ModelSelection? selection;

  /// 权限档位；null 表示用新对话默认。
  String? permission;
  bool planMode;
  String? presetId;

  /// 是不是自动化任务跑出来的。
  final bool auto;

  /// 这段对话累计的用量（含它派出去的子代理）。压缩对话不会清掉它。
  final UsageTotals usage;

  /// 最近一次请求的输入 token 数（接口给的），用来算上下文占用；还没有是 null。
  int? lastInput;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'updatedAt': updatedAt.toIso8601String(),
    'parent': parentId,
    'depth': depth,
    'agent': agentName,
    'model': selection?.toJson(),
    'permission': permission,
    'plan': planMode,
    'preset': presetId,
    'auto': auto,
    if (usage.requests > 0) 'usage': usage.toJson(),
    'lastInput': ?lastInput,
  };
}

/// 等用户点“允许 / 拒绝”的确认卡。
class PendingApproval {
  PendingApproval(this.request, {this.conversationId = '', this.agentName = ''});
  final ApprovalRequest request;
  final String conversationId;

  /// 是哪个子代理要的；主智能体为空。
  final String agentName;
  final Completer<bool> completer = Completer<bool>();
}

/// AI 向用户提的问题（选择卡）。
class PendingQuestion {
  PendingQuestion(this.question, this.options, {this.conversationId = '', this.agentName = ''});
  final String question;
  final List<String> options;
  final String conversationId;
  final String agentName;
  final Completer<String> completer = Completer<String>();
}

/// AI 生成过程中用户又发的消息：排队的，或者插话（还没交给模型的）。
class QueuedMessage {
  QueuedMessage(this.text, {this.images = const [], this.steer = false});
  final String text;
  final List<Map<String, dynamic>> images;

  /// true＝插话（下一步交给模型）；false＝排队（这一轮结束后再发）。
  bool steer;
}

/// 发送方式（AI 正在生成时）。
enum SendMode { queue, steer, interrupt }

/// 一段对话的运行状态。主对话、子代理、自动化任务各有一份，互不干扰。
class ConvRun {
  ConvRun(this.conv);
  final Conversation conv;
  final List<ChatItem> items = [];
  List<Map<String, dynamic>> messages = [];
  bool busy = false;
  bool loaded = false;
  AgentRunner? runner;

  /// 没人在场（自动化任务）：需要确认的操作一律按拒绝处理，也不提问。
  bool unattended = false;

  /// 正在跑的这一轮的用量；跑完后留着最近一轮的。
  TurnUsage? turn;
}

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
class ProjectSession extends ChangeNotifier {
  ProjectSession(this.app, this.project, {this.headless = false}) : guard = project.guard {
    preview = PreviewServer(project.dir);
    if (!headless) addTerminal();
  }

  /// 不带界面（自动化任务在别的工作区里跑时用）：不开终端。
  final bool headless;

  final AppServices app;
  final Project project;
  final PathGuard guard;
  late final PreviewServer preview;

  // ── 文件改动 ──────────────────────────────────────────
  /// 每次项目文件有变化就 +1；文件树、预览监听它来刷新。
  final ValueNotifier<int> fileRevision = ValueNotifier(0);
  void filesChanged() => fileRevision.value++;

  // ── 终端 ─────────────────────────────────────────────
  final List<TerminalSession> terminals = [];
  int activeTerminal = 0;
  int _terminalCounter = 0;

  /// 测试用：换掉伪终端的创建方式。
  PtySpawner? ptySpawner;

  /// 测试用：换掉“带参数的伪终端”（进 Ubuntu 用的那种）。
  PtyArgsSpawner? linuxPtySpawner;

  /// 新开一个本机会话。Ubuntu 环境能用就进 Ubuntu，否则是手机自带的 sh。
  /// [forceLocal] 为 true 时不管环境装没装，都开手机自带的 sh。
  TerminalSession addTerminal({bool forceLocal = false}) {
    final runtime = app.runtime;
    if (!forceLocal && runtime.shouldUseLinux) {
      final session = TerminalSession(
        title: 'Ubuntu ${++_linuxCounter}',
        backend: LinuxShellBackend(
          runtime: runtime,
          projectDir: project.dir,
          guestCwd: project.linuxPath,
          spawner: linuxPtySpawner,
          fallbackSpawner: ptySpawner,
        ),
      );
      session.append(
        '\x1b[2mLopiCode 终端 · Ubuntu 24.04\n'
        '${project.isLinux ? '工作区目录是 ${project.linuxPath}' : '项目目录挂在 /workspace'}。装软件用 apt，常用运行时可以在侧边栏“运行环境”里一键安装。\x1b[0m\n\n',
      );
      return _addSession(session);
    }
    final String hint;
    if (runtime.usable) {
      hint = 'Ubuntu 环境连续启动失败，这里先用手机自带的 sh。到侧边栏“运行环境”看日志、重新尝试。';
    } else if (runtime.installed) {
      hint = 'Ubuntu 环境已下载，但这个安装包缺少进入 Ubuntu 要用的文件，进不去。';
    } else {
      hint = '想跑 node、python：到侧边栏“运行环境”安装 Ubuntu 环境；或者点右上角 ＋ 连一台 SSH 主机。';
    }
    final session = TerminalSession(
      title: '本机 ${++_terminalCounter}',
      backend: LocalShellBackend(project.dir, spawner: ptySpawner),
    );
    session.append(
      '\x1b[2mLopiCode 终端 · 项目目录\n'
      '手机自带的 sh：有 ls、cat、cp、mkdir 这类基础命令，没有 git、node、python 和编译器。\n'
      '$hint\x1b[0m\n\n',
    );
    return _addSession(session);
  }

  int _sshCounter = 0;
  int _linuxCounter = 0;

  /// 新开一个 SSH 会话。[onUnknownHost] 在第一次连这台主机时弹指纹确认。
  TerminalSession addSshTerminal(SshConfig config, {HostKeyPrompt? onUnknownHost}) {
    final session = TerminalSession(
      title: 'SSH ${++_sshCounter}',
      backend: SshShellBackend(
        hostLabel: config.display,
        connect: () => connectSsh(
          config: config,
          secrets: app.secrets,
          knownHosts: KnownHosts(app.settings),
          onUnknownHost: onUnknownHost,
        ),
      ),
    );
    return _addSession(session);
  }

  TerminalSession _addSession(TerminalSession session) {
    terminals.add(session);
    activeTerminal = terminals.length - 1;
    notifyListeners();
    return session;
  }

  void closeTerminal(int index) {
    if (terminals.length <= 1) return;
    terminals.removeAt(index).dispose();
    activeTerminal = activeTerminal.clamp(0, terminals.length - 1);
    notifyListeners();
  }

  void selectTerminal(int index) {
    activeTerminal = index;
    notifyListeners();
  }

  // ── Agent ────────────────────────────────────────────
  bool _disposed = false;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  /// 每段对话的运行状态（用到才建）。
  final Map<String, ConvRun> _runs = {};

  ConvRun _runOf(Conversation conv) => _runs.putIfAbsent(conv.id, () => ConvRun(conv));
  ConvRun get _active => _runOf(activeConversation);

  /// 当前对话显示的条目。
  List<ChatItem> get chat => _active.items;
  List<Map<String, dynamic>> get _messages => _active.messages;

  /// 当前对话是不是正在生成。
  bool get agentBusy => _active.busy;
  bool _chatLoaded = false;

  /// 请求失败、用户消息被撤回时，把文字交还给输入框。
  String? restoredDraft;

  // 对话：一个工作区可以有多段对话。索引在 chats.json，每段对话的消息各存一个文件
  // （第一段沿用 chat.json，其余是 chat-<id>.json）。子代理的对话也在里面，带着上级的 id。
  final List<Conversation> conversations = [];
  String activeConversationId = 'main';
  final Conversation _fallbackConv = Conversation('main', '', DateTime.now());

  Conversation get activeConversation => conversations.firstWhere((c) => c.id == activeConversationId, orElse: () => _fallbackConv);

  Conversation? conversationById(String? id) => conversations.where((c) => c.id == id).firstOrNull;

  /// 侧边栏里列的对话：不含子代理的。
  List<Conversation> get topConversations => conversations.where((c) => c.parentId == null).toList();

  /// 顶栏标题：还没说话的对话叫“新对话”。
  String get conversationTitle => activeConversation.title.isEmpty ? '新对话' : activeConversation.title;

  File _reserved(String name) => File(guard.resolve('${PathGuard.reservedDir}/$name', allowReserved: true));
  File get _indexFile => _reserved('chats.json');
  File _chatFileOf(String id) => _reserved(id == 'main' ? 'chat.json' : 'chat-$id.json');
  File get _rulesFile => _reserved('rules.md');

  /// 项目规则：她写给 Agent 的长期要求，拼在系统提示词后面。
  String projectRules = '';

  Future<void> setProjectRules(String text) async {
    projectRules = text.trim();
    try {
      await _rulesFile.parent.create(recursive: true);
      await _rulesFile.writeAsString(projectRules);
    } on FileSystemException {
      // 存不了：这次打开期间仍然生效
    }
    notifyListeners();
  }

  // ── 模型 / 权限 / 计划模式 / 预设（每段对话各自一份）──────────
  /// 这段对话的“根”：子代理的权限、计划模式、预设都跟着最上面那段主对话走。
  Conversation rootOf(Conversation conv) {
    var c = conv;
    for (var i = 0; i < 8 && c.parentId != null; i++) {
      final parent = conversationById(c.parentId);
      if (parent == null) break;
      c = parent;
    }
    return c;
  }

  ResolvedModel? modelOf(Conversation conv) => app.models.resolve(conv.selection) ?? app.models.defaultForNewChat();
  ResolvedModel? get currentModel => modelOf(activeConversation);

  Future<void> setModel(ModelSelection selection) async {
    activeConversation.selection = selection;
    await app.models.setLastSelection(selection);
    await _saveIndex();
    notifyListeners();
  }

  PermissionLevel get defaultPermission => PermissionLevel.byId(app.settings.getString(SettingKeys.defaultPermission, 'workspace'));
  PermissionLevel permissionOf(Conversation conv) => conv.permission == null ? defaultPermission : PermissionLevel.byId(conv.permission);
  PermissionLevel get permission => permissionOf(activeConversation);

  Future<void> setPermission(PermissionLevel level) async {
    activeConversation.permission = level.id;
    await _saveIndex();
    notifyListeners();
  }

  bool get planMode => activeConversation.planMode;

  Future<void> setPlanMode(bool on) async {
    activeConversation.planMode = on;
    await _saveIndex();
    notifyListeners();
  }

  AgentPreset presetOf(Conversation conv) => app.presets.byId(conv.presetId ?? app.presets.defaultId);
  AgentPreset get preset => presetOf(activeConversation);

  Future<void> setPreset(String id) async {
    activeConversation.presetId = id;
    await _saveIndex();
    notifyListeners();
  }

  /// 点过“本对话都允许”的对话。只在内存里：重启 App 后恢复逐次询问。
  final Set<String> _autoAllow = {};
  bool get autoAllowActive => _autoAllow.contains(activeConversationId);

  void clearAutoAllow() {
    _autoAllow.remove(activeConversationId);
    notifyListeners();
  }

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
    run.loaded = true;
    run.messages = await _readMessages(run.conv.id);
    _rebuildItems(run);
  }

  Future<void>? _loading;

  Future<void> loadChat() => _loading ??= _loadChat();

  Future<void> _loadChat() async {
    if (_chatLoaded) return;
    await app.ready();
    try {
      if (await _rulesFile.exists()) projectRules = (await _rulesFile.readAsString()).trim();
    } on FileSystemException {
      projectRules = '';
    }
    conversations.clear();
    try {
      {
        // 目录文件坏了：备份后当只有一段“主对话”（各段对话的记录文件还在盘上）
        final decoded = await readJsonFile(_indexFile, accept: (j) => j is List, label: '对话目录');
        if (decoded is List) {
          for (final m in decoded) {
            if (m is! Map) continue;
            final id = '${m['id'] ?? ''}';
            if (!RegExp(r'^[a-z0-9]{1,24}$').hasMatch(id)) continue;
            conversations.add(
              Conversation(
                id,
                '${m['title'] ?? ''}',
                DateTime.tryParse('${m['updatedAt']}') ?? DateTime.fromMillisecondsSinceEpoch(0),
                parentId: m['parent'] is String ? m['parent'] as String : null,
                depth: m['depth'] is int ? m['depth'] as int : 0,
                agentName: '${m['agent'] ?? ''}',
                selection: ModelSelection.fromJson(m['model']),
                permission: m['permission'] is String ? m['permission'] as String : null,
                planMode: m['plan'] == true,
                presetId: m['preset'] is String ? m['preset'] as String : null,
                auto: m['auto'] == true,
                usage: UsageTotals.fromJson(m['usage']),
                lastInput: m['lastInput'] is int ? m['lastInput'] as int : null,
              ),
            );
          }
        }
      }
    } catch (_) {
      // 某一条的形状不对（老版本）：读到哪算哪
    }
    if (topConversations.isEmpty) conversations.add(Conversation('main', '', DateTime.now()));
    conversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    activeConversationId = topConversations.first.id;
    await _ensureLoaded(_active);
    // 老版本只有一个 chat.json、没有标题：从第一句话补一个。
    if (activeConversation.title.isEmpty) _retitle();
    _chatLoaded = true;
    notifyListeners();
  }

  void _retitle() {
    final first = _messages.where((m) => m['role'] == 'user').firstOrNull;
    if (first == null) return;
    activeConversation.title = _titleFrom('${first['content'] ?? ''}');
  }

  static String _titleFrom(String text) {
    final line = text.trim().split('\n').first.trim();
    return line.length > 18 ? '${line.substring(0, 18)}…' : line;
  }

  Future<void> _saveIndex() async {
    try {
      await writeJsonAtomic(_indexFile, [for (final c in conversations) c.toJson()]);
    } on FileSystemException {
      // 存不了就算了
    }
  }

  Future<void> _saveRun(ConvRun run) async {
    try {
      final file = _chatFileOf(run.conv.id);
      await writeJsonAtomic(file, run.messages);
    } on FileSystemException {
      // 存不了就算了：不影响当前对话
    }
    await _saveIndex();
  }

  String _newConvId() {
    var id = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    while (conversations.any((c) => c.id == id)) {
      id = '${id}x';
    }
    return id;
  }

  /// 开一段新对话。当前这段还是空的就直接留在这里，不堆空对话。
  Future<void> newConversation() async {
    if (agentBusy) return;
    await loadChat();
    if (_messages.isEmpty && chat.isEmpty) return;
    final conv = Conversation(
      _newConvId(),
      '',
      DateTime.now(),
      selection: app.models.defaultForNewChat()?.selection,
      presetId: app.presets.defaultId,
    );
    conversations.insert(0, conv);
    activeConversationId = conv.id;
    _runOf(conv).loaded = true;
    queue.clear();
    await _saveIndex();
    notifyListeners();
  }

  Future<void> selectConversation(String id) async {
    if (agentBusy || id == activeConversationId || !conversations.any((c) => c.id == id)) return;
    await loadChat();
    activeConversationId = id;
    queue.clear();
    await _ensureLoaded(_active);
    notifyListeners();
  }

  /// 子代理谱系：[rootId] 这段对话派出的全部子代理（含子代理再派出的），按派出顺序。
  List<Conversation> descendantsOf(String rootId) {
    final out = <Conversation>[];
    void walk(String id) {
      final kids = conversations.where((c) => c.parentId == id).toList()..sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
      for (final k in kids) {
        out.add(k);
        walk(k.id);
      }
    }

    walk(rootId);
    return out;
  }

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
      _autoAllow.remove(d);
    }
    conversations.removeWhere((c) => doomed.contains(c.id));
    if (topConversations.isEmpty) conversations.add(Conversation('main', '', DateTime.now()));
    activeConversationId = topConversations.first.id;
    queue.clear();
    await _ensureLoaded(_active);
    await _saveIndex();
    notifyListeners();
  }

  String _hostPathOfAttachment(String rel) => p.join(project.dir, rel);

  /// 从接口格式的消息记录重建界面条目（记录是唯一的事实来源）。
  void _rebuildItems(ConvRun run) {
    run.items.clear();
    final tools = <String, ToolItem>{};
    final kids = conversations.where((c) => c.parentId == run.conv.id).toList()..sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
    var kid = 0;
    for (final m in run.messages) {
      switch (m['role']) {
        case 'user':
          run.items.add(
            UserItem('${m['content'] ?? ''}', images: [
              for (final i in (m['_images'] as List?) ?? const [])
                if (i is Map) _hostPathOfAttachment('${i['path']}'),
            ]),
          );
        case 'assistant':
          final text = m['content'];
          if (text is String && text.isNotEmpty) run.items.add(AssistantItem(text));
          for (final c in (m['tool_calls'] as List?) ?? const []) {
            if (c is! Map) continue;
            final fn = c['function'];
            final item = ToolItem('${c['id']}', fn is Map ? '${fn['name']}' : '', fn is Map ? '${fn['arguments']}' : '');
            item.result = '（没有记录到结果）';
            if (item.name == 'spawn_agent' && kid < kids.length) item.childConversationId = kids[kid++].id;
            tools[item.callId] = item;
            run.items.add(item);
          }
        case 'tool':
          final item = tools['${m['tool_call_id']}'];
          if (item != null) {
            item.result = '${m['content'] ?? ''}';
            item.ok = !item.result!.startsWith('错误') && !item.result!.startsWith('用户拒绝');
            item.denied = item.result!.startsWith('用户拒绝');
          }
      }
      final turn = TurnUsage.fromJson(m['_usage']);
      if (turn != null) run.items.add(UsageItem(turn));
    }
  }

  // ── 确认卡 / 提问卡（可能同时来自主智能体和几个子代理，排队一张一张出）────
  final List<PendingApproval> _approvals = [];
  final List<PendingQuestion> _questions = [];

  PendingApproval? get pendingApproval => _approvals.firstOrNull;
  PendingQuestion? get pendingQuestion => _questions.firstOrNull;

  Future<bool> _requestApproval(ConvRun run, ApprovalRequest request) {
    if (run.unattended) return Future.value(false); // 没人在场：一律按拒绝
    final pending = PendingApproval(request, conversationId: run.conv.id, agentName: run.conv.agentName);
    _approvals.add(pending);
    notifyListeners();
    return pending.completer.future;
  }

  /// 回答最前面那张确认卡。[always]＝“本对话都允许”（这类卡允许的话）。
  void resolveApproval(bool allow, {bool always = false}) {
    if (_approvals.isEmpty) return;
    final pending = _approvals.removeAt(0);
    if (allow && always && pending.request.allowAlways) {
      final conv = conversationById(pending.conversationId);
      _autoAllow.add(conv == null ? activeConversationId : rootOf(conv).id);
      // 同一段对话里已经在排队的同类确认卡一并放行。
      for (final other in _approvals.where((a) => a.request.allowAlways).toList()) {
        final oc = conversationById(other.conversationId);
        if (oc != null && _autoAllow.contains(rootOf(oc).id)) {
          _approvals.remove(other);
          other.completer.complete(true);
        }
      }
    }
    pending.completer.complete(allow);
    notifyListeners();
  }

  Future<String> _askUser(ConvRun run, String question, List<String> options) {
    if (run.unattended) return Future.value('（这是无人值守的自动化任务，没有人能回答。请按最稳妥的做法继续，或者说明卡在哪里。）');
    final q = PendingQuestion(question, options, conversationId: run.conv.id, agentName: run.conv.agentName);
    _questions.add(q);
    notifyListeners();
    return q.completer.future;
  }

  void answerQuestion(String answer) {
    if (_questions.isEmpty) return;
    _questions.removeAt(0).completer.complete(answer.trim().isEmpty ? '（用户没有回答）' : answer.trim());
    notifyListeners();
  }

  void _dropPendingOf(Set<String> convIds) {
    for (final a in _approvals.where((a) => convIds.contains(a.conversationId)).toList()) {
      _approvals.remove(a);
      a.completer.complete(false);
    }
    for (final q in _questions.where((q) => convIds.contains(q.conversationId)).toList()) {
      _questions.remove(q);
      q.completer.complete('（用户没有回答，已停止）');
    }
  }

  // ── 团队任务板 ───────────────────────────────────────
  bool get teamEnabled => app.settings.getBool(SettingKeys.teamEnabled);
  final Map<String, TeamBoard> _boards = {};

  Future<TeamBoard> boardOf(Conversation root) async {
    final existing = _boards[root.id];
    if (existing != null) return existing;
    final board = TeamBoard(file: _reserved('team-${root.id}.json'))..onChanged = notifyListeners;
    _boards[root.id] = board;
    await board.load();
    return board;
  }

  /// 当前对话的任务板（团队没开时也能看，只是 Agent 没有任务板工具）。
  Future<TeamBoard> get teamBoard => boardOf(rootOf(activeConversation));

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
          spec: toolSpec('ask_user', '需要用户拿主意时，向用户提一个问题并等他回答。给出 2 到 4 个选项，用户也可以自己写别的回答。', {
            'question': {'type': 'string', 'description': '要问的问题'},
            'options': {'type': 'array', 'items': {'type': 'string'}, 'description': '可选的回答'},
          }, ['question']),
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
    if (!run.unattended) extras.addAll(_automationTools(run));
    return AgentToolbox(
      guard: guard,
      runner: commandRunnerFactory?.call() ??
          LinuxCommandRunner(app.runtime, guestCwd: project.linuxPath, onOutput: (t) => terminals.firstOrNull?.append(t)),
      requestApproval: (r) => _requestApproval(run, r),
      autoApprove: () => _autoAllow.contains(root.id),
      permission: () => permissionOf(root),
      planMode: () => root.planMode,
      allowedTools: presetOf(root).tools,
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
    conversations.add(child);
    final run = _runOf(child)
      ..loaded = true
      ..unattended = parent.unattended;
    // 让界面上那张工具卡能点进这段子对话。
    final card = parent.items.whereType<ToolItem>().where((t) => t.name == 'spawn_agent' && t.running && t.childConversationId == null).firstOrNull;
    card?.childConversationId = child.id;
    await _saveIndex();
    notifyListeners();

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

  // ── 自动化任务（Agent 侧）────────────────────────────
  static int get deviceTzOffset => DateTime.now().timeZoneOffset.inMinutes;

  List<ExtraTool> _automationTools(ConvRun run) => [
    ExtraTool(
      spec: toolSpec('list_scheduled_tasks', '列出已有的自动化任务（定时 / 周期）。', {}),
      kind: ToolKind.read,
      run: (_) async {
        final items = app.automations.items;
        if (items.isEmpty) return ToolOutcome('还没有自动化任务。');
        return ToolOutcome([
          for (final a in items) '- ${a.id}｜${a.title}｜${a.rule.describe()}｜${a.enabled ? '开着' : '已停用'}｜指令：${_clip(a.instruction, 120)}',
        ].join('\n'));
      },
    ),
    ExtraTool(
      spec: toolSpec(
        'schedule_task',
        '新建（不给 id）或修改（给 id）一个自动化任务：到时间后在这个工作区里自动开一段对话执行指令。'
            '每次都会弹出单独的确认卡让用户核对完整指令和触发时间，用户点了确认才生效。'
            '注意：只有 App 正在运行时才会触发。',
        {
          'id': {'type': 'string', 'description': '要修改的任务 id；新建时省略'},
          'title': {'type': 'string', 'description': '任务名'},
          'instruction': {'type': 'string', 'description': '到时间后要执行的完整指令（那时没有这段对话的上下文，要写全）'},
          'kind': {'type': 'string', 'enum': ['once', 'daily', 'weekly', 'interval'], 'description': '只运行一次 / 每天 / 每周 / 每隔一段时间'},
          'time': {'type': 'string', 'description': '几点几分，24 小时制，如 08:30（interval 不需要）'},
          'date': {'type': 'string', 'description': 'once 用：日期，如 2026-12-31'},
          'weekdays': {'type': 'array', 'items': {'type': 'integer'}, 'description': 'weekly 用：1＝周一 … 7＝周日'},
          'every_minutes': {'type': 'integer', 'description': 'interval 用：间隔分钟数，最短 ${TimeRule.minInterval}'},
          'tz_offset_minutes': {'type': 'integer', 'description': '时区相对 UTC 的分钟数，省略用手机当前时区（北京时间是 480）'},
        },
        ['title', 'instruction', 'kind'],
      ),
      kind: ToolKind.other,
      run: (args) async {
        final rule = TimeRule.fromJson(args, defaultTz: deviceTzOffset);
        if (rule == null) return ToolOutcome('错误：kind 要是 once / daily / weekly / interval 之一', ok: false);
        final existing = args['id'] is String ? app.automations.byId((args['id'] as String).trim()) : null;
        if (args['id'] is String && (args['id'] as String).trim().isNotEmpty && existing == null) {
          return ToolOutcome('错误：没有 id 为 ${args['id']} 的自动化任务', ok: false);
        }
        final title = '${args['title'] ?? ''}', instruction = '${args['instruction'] ?? ''}';
        try {
          AutomationStore.validate(title: title, instruction: instruction, rule: rule);
        } on AutomationException catch (e) {
          return ToolOutcome('错误：${e.message}', ok: false);
        }
        final next = rule.next(DateTime.now());
        if (next == null) return ToolOutcome('错误：这个时间已经过去了，不会再触发', ok: false);
        // 单独的确认卡：不走权限档位，也不吃“本对话都允许”——完全权限也代替不了。
        final ok = await _requestApproval(
          run,
          ApprovalRequest(
            tool: 'schedule_task',
            title: existing == null ? '新建自动化任务' : '修改自动化任务',
            detail: automationCardText(title: title, instruction: instruction, rule: rule, next: next, workspace: project.name, permission: PermissionLevel.workspace),
            allowAlways: false,
          ),
        );
        if (!ok) return ToolOutcome('用户拒绝了这个自动化任务，没有保存。', ok: false, denied: true);
        final saved = await app.automations.upsert(id: existing?.id, title: title, instruction: instruction, workspaceId: project.id, rule: rule);
        return ToolOutcome('已${existing == null ? '新建' : '修改'}自动化任务 ${saved.id}「${saved.title}」：${rule.describe()}。下一次触发：${formatLocal(next, rule.tzOffsetMinutes)}。只有 App 正在运行时才会触发。');
      },
    ),
  ];

  /// 确认卡上的文字：完整指令 + 实际触发时间（界面新建 / 修改时也用它）。
  static String automationCardText({
    required String title,
    required String instruction,
    required TimeRule rule,
    required DateTime next,
    required String workspace,
    required PermissionLevel permission,
  }) =>
      '任务名：$title\n工作区：$workspace\n时间规则：${rule.describe()}\n下一次触发：${formatLocal(next, rule.tzOffsetMinutes)}\n'
      '运行时的权限：${permission.label}（没人在场，需要你确认的操作会被自动拒绝）\n'
      '只有 App 正在运行时才会触发；错过的不会补跑。\n\n完整指令：\n$instruction';

  static String formatLocal(DateTime utc, int tzOffsetMinutes) {
    final t = utc.toUtc().add(Duration(minutes: tzOffsetMinutes));
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}（${TimeRule.tzLabel(tzOffsetMinutes)}）';
  }

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
    conversations.insert(0, conv);
    final run = _runOf(conv)
      ..loaded = true
      ..unattended = true;
    await _saveIndex();
    notifyListeners();
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
    run.busy = true;
    run.items.add(UserItem(text, images: [for (final i in images) _hostPathOfAttachment('${i['path']}')]));
    run.conv.updatedAt = DateTime.now();
    notifyListeners();

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
    run.turn = turn;
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
            if (streaming == null) {
              streaming = AssistantItem('', streaming: true);
              run.items.add(streaming);
            }
            streaming.text += text;
          case AssistantMessage(:final text):
            streaming?.streaming = false;
            streaming = null;
            if (text.trim().isNotEmpty) last = text;
          case UserInjected(:final text):
            run.items.add(UserItem(text));
            if (identical(run, _active)) queue.removeWhere((q) => q.steer && q.text == text);
          case ToolStarted(:final callId, :final name, :final arguments):
            run.items.add(ToolItem(callId, name, arguments));
            turn.steps.add(ToolStep(callId, name));
            toolClocks[callId] = Stopwatch()..start();
          case ToolFinished(:final callId, :final outcome):
            final item = run.items.whereType<ToolItem>().lastWhere((t) => t.callId == callId);
            item
              ..result = outcome.text
              ..ok = outcome.ok
              ..denied = outcome.denied;
            if (outcome.changedFiles) filesChanged();
            turn.steps.whereType<ToolStep>().where((t) => t.callId == callId).lastOrNull
              ?..ms = toolClocks.remove(callId)?.elapsedMilliseconds
              ..ok = outcome.ok;
          case RequestFinished(:final usage, :final ms, :final firstMs, :final startedAt):
            turn.steps.add(RequestStep(RequestUsage(usage: usage, ms: ms, firstMs: firstMs, startedAt: startedAt, cost: usage == null ? null : price?.cost(usage))));
            if (usage != null) run.conv.lastInput = usage.input;
          case AgentNotice(:final text):
            run.items.add(NoticeItem(text));
            if (text.startsWith('已停止')) failed = true;
          case AgentError(:final text):
            failed = true;
            last = text;
            streaming?.streaming = false;
            run.items.add(NoticeItem(text, isError: true));
            // 模型一个字没回时，runner 已把用户消息撤回；界面同步撤回并还原草稿。
            if (run.messages.isEmpty || run.messages.last['role'] != 'user') {
              final lastUser = run.items.lastIndexWhere((c) => c is UserItem);
              if (lastUser >= 0 && run.items.skip(lastUser + 1).every((c) => c is NoticeItem)) {
                if (identical(run, _active)) restoredDraft = (run.items[lastUser] as UserItem).text;
                run.items.removeAt(lastUser);
              }
            }
        }
        notifyListeners();
      }
    } finally {
      streaming?.streaming = false;
      // 兜底：流意外结束时不能留着没人能点的确认卡、提问卡。
      _dropPendingOf({run.conv.id});
      run.busy = false;
      run.runner = null;
      turn.ms = clock.elapsedMilliseconds;
      _recordTurn(run, turn);
      await _saveRun(run);
      notifyListeners();
    }
    // 额度：对话结束后查一次余额（有节流）；到提醒线或到顶时说一声。
    if (resolved != null) {
      final note = await app.quota.afterRun(resolved.channel);
      if (note != null && run.conv.parentId == null && !run.unattended) {
        run.items.add(NoticeItem(note, isError: note.startsWith(kQuotaBlockedPrefix)));
        notifyListeners();
      }
    }
    // 提醒：对话快把上下文占满了。
    final limit = resolved?.model.contextLength;
    if (limit != null && run.conv.parentId == null && !run.unattended && AgentRunner.estimateTokens(run.messages) > limit * 0.8) {
      run.items.add(NoticeItem('这段对话快把模型的上下文（${limit ~/ 1000}K）占满了。发 /compact 可以把前面的内容压缩成摘要再继续。'));
      notifyListeners();
    }
    return (text: last, failed: failed);
  }

  /// 把这一轮的用量记到对话上：累计进对话合计，并挂在这一轮最后一条消息上（跟着对话存盘）。
  void _recordTurn(ConvRun run, TurnUsage turn) {
    final totals = turn.totals;
    if (totals.requests == 0) return; // 一次请求都没发出去（没配模型、被额度拦下）：不显示
    // 子代理的用量由上级那一轮统一算进主对话；这里只累计到它自己这段对话上。
    run.conv.usage
      ..add(totals)
      ..turns += 1;
    // 用户消息被撤回时（模型一个字没回），最后一条是上一轮的，别盖掉上一轮的记录。
    if (run.messages.isNotEmpty && !run.messages.last.containsKey('_usage')) {
      run.messages.last['_usage'] = turn.toJson();
    }
    run.items.add(UsageItem(turn));
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
    return (
      system: estimateTextTokens(_systemPromptFor(conv, root, skills)),
      tools: estimateTextTokens(jsonEncode(box.specs)),
      messages: AgentRunner.estimateTokens(_messages),
    );
  }

  // ── 发送、插话、排队 ─────────────────────────────────
  /// AI 生成时又发的消息（显示在输入框上方）。
  final List<QueuedMessage> queue = [];
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
          queue.add(msg);
          run.runner?.steer(text);
        case SendMode.interrupt:
          _sendAfterStop = msg;
          stopAgent();
        default:
          queue.add(msg);
      }
      notifyListeners();
      return;
    }
    _stoppedByUser = false;
    restoredDraft = null;
    final conv = run.conv;
    if (conv.title.isEmpty) conv.title = _titleFrom(text);
    conv.selection ??= app.models.defaultForNewChat()?.selection;
    // 最近说过话的排最前
    conversations
      ..remove(conv)
      ..insert(0, conv);
    final skills = await app.skills.enabled(workspaceDir: project.dir);
    try {
      await _execute(run, text, root: conv, skills: skills, images: images);
    } finally {
      await _afterRun();
    }
  }

  Future<void> _afterRun() async {
    // 没来得及交给模型的插话：改成排队，不丢。
    for (final q in queue) {
      q.steer = false;
    }
    final interrupt = _sendAfterStop;
    _sendAfterStop = null;
    QueuedMessage? next;
    if (interrupt != null) {
      next = interrupt;
    } else if (!_stoppedByUser && queue.isNotEmpty && restoredDraft == null) {
      next = queue.removeAt(0);
    }
    notifyListeners();
    if (next != null && !_disposed) {
      // 用 unawaited：上一轮的 Future 先结束，界面状态不会卡在“生成中”。
      unawaited(sendToAgent(next.text, images: next.images));
    }
  }

  /// 排队里的一条：立即发送（中断当前这一轮，马上发它）。
  void sendQueuedNow(QueuedMessage msg) {
    if (!queue.remove(msg)) return;
    _active.runner?.withdrawSteer(msg.text);
    if (agentBusy) {
      _sendAfterStop = msg;
      stopAgent();
    } else {
      unawaited(sendToAgent(msg.text, images: msg.images));
    }
    notifyListeners();
  }

  /// 排队里的一条：改为插话（下一步就让模型看到）。带图片的不能插话。
  void steerQueued(QueuedMessage msg) {
    if (!queue.contains(msg) || msg.steer || msg.images.isNotEmpty || !agentBusy) return;
    msg.steer = true;
    _active.runner?.steer(msg.text);
    notifyListeners();
  }

  /// 排队里的一条：撤回（文字交还输入框）。
  void withdrawQueued(QueuedMessage msg) {
    if (!queue.remove(msg)) return;
    _active.runner?.withdrawSteer(msg.text);
    restoredDraft = msg.text;
    notifyListeners();
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
    run.busy = true;
    notifyListeners();
    String? error;
    try {
      final before = AgentRunner.estimateTokens(run.messages);
      error = await compactHistory(await app.createChatClient(modelOf(run.conv)), run.messages);
      if (error == null) {
        _rebuildItems(run);
        run.items.add(NoticeItem('已把之前的对话压缩成摘要（估算从 ${before ~/ 1000}K 降到 ${AgentRunner.estimateTokens(run.messages) ~/ 1000}K）。原来的逐条记录不再保留。'));
      }
    } finally {
      run.busy = false;
      await _saveRun(run);
      notifyListeners();
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

  @override
  void dispose() {
    stopAgent();
    for (final r in _runs.values) {
      r.runner?.cancel();
    }
    _disposed = true;
    for (final t in terminals) {
      t.dispose();
    }
    unawaited(preview.stop());
    fileRevision.dispose();
    super.dispose();
  }
}
