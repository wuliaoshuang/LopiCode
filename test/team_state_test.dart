// 团队任务板的状态（lib/state/team_state.dart）和任务板本身的不可变快照（lib/agent/team.dart）。
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/agent/team.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/state/team_state.dart';
import 'package:riverpod/riverpod.dart';

import 'support/harness.dart';

void main() {
  late TestEnv env;
  late Project project;
  late ProjectSession session;
  late ProviderContainer box;
  late TeamKey key;
  TeamView? state() => box.read(teamProvider(key));
  TeamNotifier ctl() => box.read(teamProvider(key).notifier);

  /// 等任务板第一次读出来。
  Future<TeamView> loaded() async {
    box.listen(teamProvider(key), (_, _) {});
    for (var i = 0; i < 200 && state() == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    return state()!;
  }

  setUp(() async {
    env = await TestEnv.create();
    project = await env.services.projects.create('demo', ProjectTemplate.web);
    session = ProjectSession(env.services, project, headless: true);
    box = env.services.container;
    key = (session, session.activeConversationId);
  });
  tearDown(() async {
    session.dispose();
    await env.dispose();
  });

  test('一开始还没读出来是 null；读出来后只有主智能体、没有任务', () async {
    expect(state(), isNull);
    final v = await loaded();
    expect(v.members.single.name, TeamBoard.lead);
    expect(v.tasks, isEmpty);
    expect(v.messages, isEmpty);
  });

  test('新建、改状态、删除：快照每次换新的；旧快照和手里那份任务不变', () async {
    final first = await loaded();
    final t1 = await ctl().createTask(title: ' 搭框架 ', owner: '前端', scope: ['src/', '../etc', '/abs']);
    expect(first.tasks, isEmpty);
    expect((t1.title, t1.owner, t1.status), ('搭框架', '前端', TaskStatus.todo));
    expect(t1.scope, ['src'], reason: '越出工作区的范围被丢掉');
    final second = state()!;
    expect(second.tasks.single.id, t1.id);
    expect(second.members.map((m) => m.name), [TeamBoard.lead, '前端'], reason: '负责人自动进成员');

    final doing = await ctl().setStatus(t1.id, TaskStatus.doing);
    expect(doing.status, TaskStatus.doing);
    expect(t1.status, TaskStatus.todo, reason: '手里那份是旧的');
    expect(second.tasks.single.status, TaskStatus.todo);
    expect(state()!.tasks.single.status, TaskStatus.doing);

    final t2 = await ctl().createTask(title: '写页面', deps: [t1.id]);
    await ctl().removeTask(t1.id);
    expect(state()!.tasks.single.id, t2.id);
    expect(state()!.tasks.single.deps, isEmpty, reason: '删掉的任务从别人的依赖里去掉');
    expect(t2.deps, [t1.id]);
  });

  test('规则不过就抛错，任务板一点不变（依赖没完成不能开始；不能依赖自己；依赖不存在）', () async {
    await loaded();
    final t1 = await ctl().createTask(title: '搭框架');
    final t2 = await ctl().createTask(title: '写页面', deps: [t1.id]);
    final before = state()!;
    await expectLater(ctl().setStatus(t2.id, TaskStatus.doing), throwsA(isA<TeamException>()));
    await expectLater(ctl().createTask(title: '  '), throwsA(isA<TeamException>()));
    await expectLater(ctl().createTask(title: 'x', deps: ['nope']), throwsA(isA<TeamException>()));
    final board = await session.boardById(key.$2);
    await expectLater(board.update(t1.id, deps: [t1.id]), throwsA(isA<TeamException>()));
    // 一次调用里既改依赖又开工、开工被挡：依赖也不能被悄悄改掉
    final t3 = await ctl().createTask(title: '写文档');
    await expectLater(board.update(t3.id, deps: [t1.id], status: TaskStatus.doing), throwsA(isA<TeamException>()));
    expect(state()!.task(t3.id)!.deps, isEmpty);
    expect(state()!.task(t2.id)!.status, TaskStatus.todo);
    expect(before.tasks, hasLength(2));
  });

  test('拿到手的清单和任务改不了', () async {
    await loaded();
    final t = await ctl().createTask(title: '搭框架', scope: ['src/']);
    final v = state()!;
    expect(() => v.tasks.add(t), throwsUnsupportedError);
    expect(v.members.clear, throwsUnsupportedError);
    expect(v.messages.clear, throwsUnsupportedError);
    expect(() => v.tasks.single.scope.add('x'), throwsUnsupportedError);
    expect(() => v.tasks.single.deps.add('x'), throwsUnsupportedError);
  });

  test('不经过 Notifier 的改动（Agent 的任务板工具、留言、加成员）也进快照；重叠提示和阻塞算得和任务板一致', () async {
    await loaded();
    final board = await session.boardById(key.$2);
    final tools = {for (final t in board.tools('前端')) (t.spec['function'] as Map)['name']: t};
    final made = await tools['team_task']!.run({
      'title': '做登录页',
      'status': 'doing',
      'write_scope': ['src/'],
    });
    expect(made.text, allOf(contains('进行中'), contains('负责人 前端')), reason: '新建时直接开工：回话里是开工后的状态');
    await board.create(title: '整理样式', owner: '样式', scope: ['src/css']);
    await board.update(state()!.tasks.last.id, status: TaskStatus.doing);
    await board.post('前端', '', '开工了');
    await board.addMember('测试', '子代理');
    await board.addMember('测试');
    final v = state()!;
    expect(v.tasks.map((t) => t.title), ['做登录页', '整理样式']);
    expect(v.messages.single.to, '全体');
    expect(v.members.where((m) => m.name == '测试').single.role, '子代理', reason: '再加一次不重复、不清掉角色');
    expect(v.overlapWarnings(), hasLength(1));
    expect(v.overlapWarnings(), board.overlapWarnings());
    expect(identical(v, board.view), isTrue);
  });

  test('存盘再读：另一个会话打开同一段对话看到同样的任务板', () async {
    await loaded();
    final t = await ctl().createTask(title: '搭框架', owner: '前端');
    await ctl().setStatus(t.id, TaskStatus.done);
    final other = ProjectSession(env.services, project, headless: true);
    addTearDown(other.dispose);
    final again = await other.boardById(key.$2);
    expect(again.tasks.single.status, TaskStatus.done);
    expect(again.members.map((m) => m.name), contains('前端'));
    expect((await again.create(title: '新的')).id, isNot(t.id), reason: '编号不重复');
  });

  test('同一块任务板同时要两次：只读一次文件，拿到同一个对象', () async {
    final a = session.boardById('same'), b = session.boardById('same');
    expect(identical(await a, await b), isTrue);
  });

  test('工作区关掉以后：通知不再写状态，也不报错', () async {
    await loaded();
    final board = await session.boardById(key.$2);
    final n = ctl();
    var count = 0;
    box.listen(teamProvider(key), (_, _) => count++);
    session.dispose();
    expect(state(), isNull, reason: '关掉后状态放掉');
    final after = count;
    await board.create(title: '关掉以后');
    n.publish(board.view);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(count, after);
    expect(state(), isNull);
  });
}
