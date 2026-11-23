import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:lopicode/agent/agent_runner.dart';
import 'package:lopicode/agent/agent_tools.dart';
import 'package:lopicode/app_services.dart';
import 'package:lopicode/core/path_guard.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/stores.dart';
import 'package:lopicode/preview/preview_server.dart';
import 'package:lopicode/runtime/linux_command_runner.dart';
import 'package:lopicode/runtime/linux_shell_backend.dart';
import 'package:lopicode/ssh/ssh_config.dart';
import 'package:lopicode/ssh/ssh_connector.dart';
import 'package:lopicode/ssh/ssh_shell_backend.dart';
import 'package:lopicode/terminal/terminal_session.dart';

/// 对话里显示的一项。
sealed class ChatItem {}

class UserItem extends ChatItem {
  UserItem(this.text);
  final String text;
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
}

class NoticeItem extends ChatItem {
  NoticeItem(this.text, {this.isError = false});
  final String text;
  final bool isError;
}

/// 项目里的一段对话。
class Conversation {
  Conversation(this.id, this.title, this.updatedAt);
  final String id;
  String title;
  DateTime updatedAt;

  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'updatedAt': updatedAt.toIso8601String()};
}

/// 等用户点“允许 / 拒绝”的确认卡。
class PendingApproval {
  PendingApproval(this.request);
  final ApprovalRequest request;
  final Completer<bool> completer = Completer<bool>();
}

/// 打开一个项目期间的全部运行状态：终端会话、预览服务器、Agent 对话。
/// 各个页面共用这一个对象，切页面不丢状态。
class ProjectSession extends ChangeNotifier {
  ProjectSession(this.app, this.project) : guard = project.guard {
    preview = PreviewServer(project.dir);
    addTerminal();
  }

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
          spawner: linuxPtySpawner,
          fallbackSpawner: ptySpawner,
        ),
      );
      session.append(
        '\x1b[2mLopiCode 终端 · Ubuntu 24.04\n'
        '项目目录挂在 /workspace。装软件用 apt，常用运行时可以在侧边栏“运行环境”里一键安装。\x1b[0m\n\n',
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
  final List<ChatItem> chat = [];
  List<Map<String, dynamic>> _messages = [];
  PendingApproval? pendingApproval;
  bool agentBusy = false;
  bool _chatLoaded = false;
  AgentRunner? _runner;

  /// 请求失败、用户消息被撤回时，把文字交还给输入框。
  String? restoredDraft;

  bool get autoApprove => app.settings.getBool(SettingKeys.autoApprove(project.id));

  Future<void> setAutoApprove(bool value) async {
    await app.settings.set(SettingKeys.autoApprove(project.id), value);
    notifyListeners();
  }

  // 对话：一个项目可以有多段对话。索引在 chats.json，每段对话的消息各存一个文件
  // （第一段沿用 chat.json，其余是 chat-<id>.json）。
  final List<Conversation> conversations = [];
  String activeConversationId = 'main';

  Conversation get activeConversation =>
      conversations.firstWhere((c) => c.id == activeConversationId, orElse: () => Conversation('main', '', DateTime.now()));

  /// 顶栏标题：还没说话的对话叫“新对话”。
  String get conversationTitle => activeConversation.title.isEmpty ? '新对话' : activeConversation.title;

  File _reserved(String name) => File(guard.resolve('${PathGuard.reservedDir}/$name', allowReserved: true));
  File get _indexFile => _reserved('chats.json');
  File _chatFileOf(String id) => _reserved(id == 'main' ? 'chat.json' : 'chat-$id.json');
  File get _chatFile => _chatFileOf(activeConversationId);
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

  String get systemPrompt => projectRules.isEmpty
      ? AgentRunner.defaultSystemPrompt
      : '${AgentRunner.defaultSystemPrompt}\n\n用户给这个项目定的规则（必须遵守）：\n$projectRules';

  Future<List<Map<String, dynamic>>> _readMessages(String id) async {
    try {
      final file = _chatFileOf(id);
      if (await file.exists()) {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is List) {
          return [
            for (final m in decoded)
              if (m is Map<String, dynamic>) m,
          ];
        }
      }
    } on Exception {
      // 文件坏了就当空对话
    }
    return [];
  }

  Future<void> loadChat() async {
    if (_chatLoaded) return;
    _chatLoaded = true;
    try {
      if (await _rulesFile.exists()) projectRules = (await _rulesFile.readAsString()).trim();
    } on FileSystemException {
      projectRules = '';
    }
    conversations.clear();
    try {
      if (await _indexFile.exists()) {
        final decoded = jsonDecode(await _indexFile.readAsString());
        if (decoded is List) {
          for (final m in decoded) {
            if (m is! Map) continue;
            final id = '${m['id'] ?? ''}';
            if (!RegExp(r'^[a-z0-9]{1,24}$').hasMatch(id)) continue;
            conversations.add(
              Conversation(id, '${m['title'] ?? ''}', DateTime.tryParse('${m['updatedAt']}') ?? DateTime.fromMillisecondsSinceEpoch(0)),
            );
          }
        }
      }
    } on Exception {
      conversations.clear();
    }
    if (conversations.isEmpty) conversations.add(Conversation('main', '', DateTime.now()));
    conversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    activeConversationId = conversations.first.id;
    _messages = await _readMessages(activeConversationId);
    // 老版本只有一个 chat.json、没有标题：从第一句话补一个。
    if (activeConversation.title.isEmpty) _retitle();
    _rebuildItems();
    notifyListeners();
  }

  void _retitle() {
    final first = _messages.where((m) => m['role'] == 'user').firstOrNull;
    if (first == null) return;
    final line = '${first['content'] ?? ''}'.trim().split('\n').first.trim();
    if (line.isEmpty) return;
    activeConversation.title = line.length > 18 ? '${line.substring(0, 18)}…' : line;
  }

  Future<void> _saveIndex() async {
    try {
      await _indexFile.parent.create(recursive: true);
      await _indexFile.writeAsString(jsonEncode([for (final c in conversations) c.toJson()]));
    } on FileSystemException {
      // 存不了就算了
    }
  }

  Future<void> _saveChat() async {
    try {
      await _chatFile.parent.create(recursive: true);
      await _chatFile.writeAsString(jsonEncode(_messages));
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
    var id = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    while (conversations.any((c) => c.id == id)) {
      id = '${id}x';
    }
    conversations.insert(0, Conversation(id, '', DateTime.now()));
    activeConversationId = id;
    _messages = [];
    chat.clear();
    await _saveIndex();
    notifyListeners();
  }

  Future<void> selectConversation(String id) async {
    if (agentBusy || id == activeConversationId || !conversations.any((c) => c.id == id)) return;
    await loadChat();
    activeConversationId = id;
    _messages = await _readMessages(id);
    _rebuildItems();
    notifyListeners();
  }

  /// 删除当前对话（文件不受影响）。删到一段不剩时留一段空的。
  Future<void> deleteConversation() async {
    if (agentBusy) return;
    final id = activeConversationId;
    try {
      final file = _chatFileOf(id);
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // 删不掉：索引里照样移除
    }
    conversations.removeWhere((c) => c.id == id);
    if (conversations.isEmpty) conversations.add(Conversation('main', '', DateTime.now()));
    activeConversationId = conversations.first.id;
    _messages = await _readMessages(activeConversationId);
    _rebuildItems();
    await _saveIndex();
    notifyListeners();
  }

  /// 从接口格式的消息记录重建界面条目（记录是唯一的事实来源）。
  void _rebuildItems() {
    chat.clear();
    final tools = <String, ToolItem>{};
    for (final m in _messages) {
      switch (m['role']) {
        case 'user':
          chat.add(UserItem('${m['content'] ?? ''}'));
        case 'assistant':
          final text = m['content'];
          if (text is String && text.isNotEmpty) chat.add(AssistantItem(text));
          for (final c in (m['tool_calls'] as List?) ?? const []) {
            if (c is! Map) continue;
            final fn = c['function'];
            final item = ToolItem('${c['id']}', fn is Map ? '${fn['name']}' : '', fn is Map ? '${fn['arguments']}' : '');
            item.result = '（没有记录到结果）';
            tools[item.callId] = item;
            chat.add(item);
          }
        case 'tool':
          final item = tools['${m['tool_call_id']}'];
          if (item != null) {
            item.result = '${m['content'] ?? ''}';
            item.ok = !item.result!.startsWith('错误') && !item.result!.startsWith('用户拒绝');
            item.denied = item.result!.startsWith('用户拒绝');
          }
      }
    }
  }

  Future<bool> _requestApproval(ApprovalRequest request) {
    final pending = PendingApproval(request);
    pendingApproval = pending;
    notifyListeners();
    return pending.completer.future;
  }

  void resolveApproval(bool allow) {
    final pending = pendingApproval;
    if (pending == null) return;
    pendingApproval = null;
    pending.completer.complete(allow);
    notifyListeners();
  }

  Future<void> sendToAgent(String text) async {
    if (agentBusy || text.trim().isEmpty) return;
    await loadChat();
    agentBusy = true;
    restoredDraft = null;
    chat.add(UserItem(text));
    final conv = activeConversation..updatedAt = DateTime.now();
    if (conv.title.isEmpty) {
      final line = text.trim().split('\n').first.trim();
      conv.title = line.length > 18 ? '${line.substring(0, 18)}…' : line;
    }
    // 最近说过话的排最前
    conversations
      ..remove(conv)
      ..insert(0, conv);
    notifyListeners();

    final client = await app.createChatClient();
    final runner = AgentRunner(
      client: client,
      history: _messages,
      systemPrompt: systemPrompt,
      toolbox: AgentToolbox(
        guard: guard,
        runner: LinuxCommandRunner(app.runtime, onOutput: (t) => terminals.first.append(t)),
        requestApproval: _requestApproval,
        autoApprove: () => autoApprove,
      ),
    );
    _runner = runner;
    AssistantItem? streaming;
    try {
      await for (final event in runner.send(text)) {
        switch (event) {
          case AssistantDelta(:final text):
            if (streaming == null) {
              streaming = AssistantItem('', streaming: true);
              chat.add(streaming);
            }
            streaming.text += text;
          case AssistantMessage():
            streaming?.streaming = false;
            streaming = null;
          case ToolStarted(:final callId, :final name, :final arguments):
            chat.add(ToolItem(callId, name, arguments));
          case ToolFinished(:final callId, :final outcome):
            final item = chat.whereType<ToolItem>().lastWhere((t) => t.callId == callId);
            item
              ..result = outcome.text
              ..ok = outcome.ok
              ..denied = outcome.denied;
            if (outcome.changedFiles) filesChanged();
          case AgentNotice(:final text):
            chat.add(NoticeItem(text));
          case AgentError(:final text):
            streaming?.streaming = false;
            chat.add(NoticeItem(text, isError: true));
            // 模型一个字没回时，runner 已把用户消息撤回；界面同步撤回并还原草稿。
            if (_messages.isEmpty || _messages.last['role'] != 'user') {
              final last = chat.lastIndexWhere((c) => c is UserItem);
              if (last >= 0 && chat.skip(last + 1).every((c) => c is NoticeItem)) {
                restoredDraft = (chat[last] as UserItem).text;
                chat.removeAt(last);
              }
            }
        }
        notifyListeners();
      }
    } finally {
      streaming?.streaming = false;
      // 兜底：流意外结束时不能留着一张没人能点的确认卡。
      if (pendingApproval != null) resolveApproval(false);
      agentBusy = false;
      _runner = null;
      await _saveChat();
      notifyListeners();
    }
  }

  void stopAgent() {
    _runner?.cancel();
    if (pendingApproval != null) resolveApproval(false);
  }

  @override
  void dispose() {
    stopAgent();
    for (final t in terminals) {
      t.dispose();
    }
    unawaited(preview.stop());
    fileRevision.dispose();
    super.dispose();
  }
}
