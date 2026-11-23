// 团队任务板的状态（完整版：不可变快照 + Notifier）。
//
// 任务板按“主对话”一块一块存（.lopicode/team-<对话 id>.json），读写和规则都在 lib/agent/team.dart 的 TeamBoard 里。
// 这里按（工作区会话，主对话 id）给界面一份不可变的快照：还没读出来时是 null；
// 之后不管是谁改的（界面、Agent 的任务板工具、派子代理时自动认领），任务板都会把新的样子送过来。
// 界面要改就调 [TeamNotifier] 的方法；校验不过抛 TeamException，由界面提示。
import 'dart:async';

import 'package:lopicode/agent/team.dart';
import 'package:lopicode/project_session.dart';
import 'package:riverpod/riverpod.dart';

/// 哪一块任务板：哪个工作区会话里的哪段主对话。
typedef TeamKey = (ProjectSession session, String rootId);

class TeamNotifier extends Notifier<TeamView?> {
  TeamNotifier(this.key);
  final TeamKey key;

  ProjectSession get _session => key.$1;

  @override
  TeamView? build() {
    // 任务板第一次用到时要读文件：读完再把快照放出来（已经读过的也走这里，下一拍就有）。
    if (!_session.disposed) unawaited(_load());
    return null;
  }

  Future<void> _load() async {
    final board = await _session.boardById(key.$2);
    publish(board.view);
  }

  /// 任务板来说一声：变成这样了。工作区关掉以后不再写。
  void publish(TeamView view) {
    if (ref.mounted && !_session.disposed) state = view;
  }

  Future<TeamBoard> get _board => _session.boardById(key.$2);

  Future<TeamTask> createTask({required String title, String owner = '', List<String> deps = const [], List<String> scope = const []}) async =>
      (await _board).create(title: title, owner: owner, deps: deps, scope: scope);

  Future<TeamTask> setStatus(String id, TaskStatus status) async => (await _board).update(id, status: status);

  Future<void> removeTask(String id) async => (await _board).remove(id);
}

final teamProvider = NotifierProvider.family<TeamNotifier, TeamView?, TeamKey>(TeamNotifier.new);
