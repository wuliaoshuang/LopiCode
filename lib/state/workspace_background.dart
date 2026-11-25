// 一个工作区的后台命令：有哪些、各自什么状态、输出到多少字节了。
//
// 干活的是 [BackgroundCommands]（起进程、写日志、停止，在 lib/agent/background_commands.dart），由这里持有；
// 它每次有变化，这里拍一张不可变快照。界面只读快照；要停止、读日志调 Notifier 的方法（或 ProjectSession 上转的那几个）。
// 工作区关掉、应用退出时这里被释放：所有后台命令立刻结束。
import 'dart:async';

import 'package:lopicode/agent/background_commands.dart';
import 'package:lopicode/project_session.dart';
import 'package:riverpod/riverpod.dart';

class BackgroundTasksState {
  const BackgroundTasksState({this.tasks = const []});

  /// 全部任务（不可改），按任务号从小到大。
  final List<BackgroundTask> tasks;

  /// 某段主对话的任务。
  List<BackgroundTask> of(String convId) => [...tasks.where((t) => t.convId == convId)];
}

class BackgroundTasksNotifier extends Notifier<BackgroundTasksState> {
  BackgroundTasksNotifier(this.session);
  final ProjectSession session;

  /// 干活的对象。逻辑层（工具、通知）直接用它；界面不要直接用。
  late final BackgroundCommands manager = BackgroundCommands(session.guard);

  @override
  BackgroundTasksState build() {
    ref.onDispose(manager.dispose);
    if (session.disposed) {
      manager.dispose();
      return const BackgroundTasksState();
    }
    manager.onChanged = _publish;
    return BackgroundTasksState(tasks: manager.tasks);
  }

  void _publish() {
    if (ref.mounted && !session.disposed) state = BackgroundTasksState(tasks: manager.tasks);
  }

  /// 用户在面板里点“停止”。
  Future<void> stop(int id) async {
    await manager.stop(id, by: StoppedBy.user);
  }

  /// 日志的最后一段（界面看实时日志用）。
  String logTail(int id, {int lines = 2000, int maxBytes = 256 * 1024}) => manager.tail(id, lines: lines, maxBytes: maxBytes);
}

/// 某个工作区的后台命令（按工作区分身）。
final backgroundTasksProvider = NotifierProvider.family<BackgroundTasksNotifier, BackgroundTasksState, ProjectSession>(BackgroundTasksNotifier.new);
