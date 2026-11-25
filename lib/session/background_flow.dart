// 后台命令和对话之间的接线：给一段对话装上后台命令的工具；命令结束后怎么让模型和用户知道。
//
// 通知的规矩（和 RikkaHub 有意不同）：
// - 这段对话**正在跑**：下一次调用模型之前，把“后台命令 #N 已结束…”当成一条应用通知交给模型（AgentRunner.takeNotices）；
// - 这段对话**空闲**：**不自动开一轮**（开一轮要花钱）。只在聊天里加一行安静的提示；等她下次发消息时，通知跟着那条消息一起交给模型。
// - 模型自己停掉的、已经用读输出工具看到结束的：不再通知。用户在面板里手动停的：照样告诉模型。
// 任务归属主对话：子代理起的后台命令记在它的主对话名下，通知也交给主对话。
import 'package:lopicode/agent/agent_runner.dart';
import 'package:lopicode/agent/agent_tools.dart';
import 'package:lopicode/agent/background_commands.dart';
import 'package:lopicode/agent/background_tools.dart';
import 'package:lopicode/agent/command_runner.dart';
import 'package:lopicode/session/chat_models.dart';
import 'package:lopicode/session/conversation.dart';
import 'package:lopicode/session/session_core.dart';
import 'package:lopicode/state/workspace_background.dart';
import 'package:lopicode/state/workspace_chat.dart';

class BackgroundFlow {
  BackgroundFlow(this.core);
  final SessionCore core;

  BackgroundCommands? _manager;

  /// 已经在聊天里提示过“结束了”的任务（只在内存里：重开后会再提示一次，因为那行提示不存盘）。
  final Set<int> _announced = {};

  /// 这个工作区的后台命令。工作区已经关掉、应用已经退出时是 null。
  BackgroundCommands? get manager {
    // 不带界面的工作区（自动化任务临时开的）不碰后台命令：同一个目录可能正被带界面的那个管着。
    if (core.disposed || core.app.disposed || core.session.headless) return null;
    final m = _manager ??= core.app.container.read(backgroundTasksProvider(core.session).notifier).manager;
    m.onEnded ??= _ended;
    return m.disposed ? null : m;
  }

  /// 把上次的任务清单读出来，并把当前对话里“结束了还没说”的提示出来。
  Future<void> load() async {
    await manager?.load();
    announce(core.active);
  }

  /// 给一段对话的工具箱加上后台命令的工具。没人在场（自动化任务）不给：没人看着的后台进程不该留着。
  List<ExtraTool> tools(ChatRunNotifier run, Conversation root, CommandRunner runner, {required Future<bool> Function(ApprovalRequest request) approve, Future<void>? Function()? stopSignal}) {
    final m = manager;
    if (m == null || run.unattended) return const [];
    return backgroundCommandTools(manager: m, convId: root.id, runner: runner, approve: approve, stopSignal: stopSignal);
  }

  /// 要交给模型的通知（取走就算“模型知道了”）。只有主对话自己那一轮取；子代理、自动化任务不取。
  List<AppNotice> takeNotices(ChatRunNotifier run, Conversation root) {
    final m = manager;
    if (m == null || run.convId != root.id || run.unattended) return const [];
    final ended = m.unnotified(root.id);
    if (ended.isEmpty) return const [];
    final notices = [for (final t in ended) backgroundNotice(m, t)];
    m.setNotified(ended.map((t) => t.id));
    _announced.addAll(ended.map((t) => t.id));
    return notices;
  }

  /// 通知交出去了但那次请求一个字没回：还回来，下次再带。
  void returnNotices(List<AppNotice> notices) {
    final ids = [
      for (final n in notices)
        if (RegExp(r'后台命令 #(\d+)').firstMatch(n.label)?.group(1) case final String id) int.parse(id),
    ];
    manager?.setNotified(ids, value: false);
  }

  /// 对话空闲时：把“结束了、模型还不知道”的任务在聊天里各提示一行（安静的提示，不开新一轮）。
  void announce(ChatRunNotifier run) {
    final m = manager;
    if (m == null || run.busy || !run.loaded || run.unattended) return;
    for (final t in m.unnotified(run.convId)) {
      if (_announced.add(t.id)) run.add(NoticeItem('${backgroundNoticeLabel(t)}。下次发消息时会告诉 AI。'));
    }
  }

  void _ended(BackgroundTask task) {
    final run = core.runs[task.convId];
    if (run != null) announce(run);
  }

  /// 这段对话删掉了：它的后台命令一起停掉、删掉。
  Future<void> dropConversation(String convId) async {
    await manager?.dropConversation(convId);
  }
}
