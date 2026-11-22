import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:lopicode/agent/agent_runner.dart';
import 'package:lopicode/agent/agent_tools.dart';
import 'package:lopicode/agent/command_runner.dart';
import 'package:lopicode/app_services.dart';
import 'package:lopicode/core/path_guard.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/stores.dart';
import 'package:lopicode/preview/preview_server.dart';
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

/// 等用户点“允许 / 拒绝”的确认卡。
class PendingApproval {
  PendingApproval(this.request);
  final ApprovalRequest request;
  final Completer<bool> completer = Completer<bool>();
}

/// 打开一个项目期间的全部运行状态：终端会话、预览服务器、Agent 对话。
/// 五个页签共用这一个对象，切页签不丢状态。
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

  TerminalSession addTerminal() {
    final session = TerminalSession(
      title: '本机 ${++_terminalCounter}',
      backend: PipeShellBackend(project.dir),
    );
    session.append(
      'LopiCode 基础终端 · 项目目录\n'
      '这里跑的是手机自带的 sh：有 ls、cat、cp、mkdir 这类基础命令，没有 git、node、python 和编译器。\n'
      '一次一条命令；不支持 vim、top 这类全屏程序。\n\n',
    );
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

  File get _chatFile => File(guard.resolve('${PathGuard.reservedDir}/chat.json', allowReserved: true));

  Future<void> loadChat() async {
    if (_chatLoaded) return;
    _chatLoaded = true;
    try {
      if (await _chatFile.exists()) {
        final decoded = jsonDecode(await _chatFile.readAsString());
        if (decoded is List) {
          _messages = [
            for (final m in decoded)
              if (m is Map<String, dynamic>) m,
          ];
        }
      }
    } on Exception {
      _messages = [];
    }
    _rebuildItems();
    notifyListeners();
  }

  Future<void> _saveChat() async {
    try {
      await _chatFile.parent.create(recursive: true);
      await _chatFile.writeAsString(jsonEncode(_messages));
    } on FileSystemException {
      // 存不了就算了：不影响当前对话
    }
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
    notifyListeners();

    final client = await app.createChatClient();
    final runner = AgentRunner(
      client: client,
      history: _messages,
      toolbox: AgentToolbox(
        guard: guard,
        runner: LocalShellRunner(onOutput: (t) => terminals.first.append(t)),
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

  Future<void> clearChat() async {
    if (agentBusy) return;
    _messages.clear();
    chat.clear();
    await _saveChat();
    notifyListeners();
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
