// 后台命令接进会话以后（不带界面、不联网，命令用真实的 /bin/sh）：
// 工具什么时候有、启动和 run_command 同级确认、结束后怎么通知模型（忙时顺带 / 空闲不自动开一轮）、
// 停止、删对话、关工作区、应用被杀后重开。
@TestOn('linux')
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/agent/agent_tools.dart';
import 'package:lopicode/agent/background_commands.dart';
import 'package:lopicode/agent/background_tools.dart';
import 'package:lopicode/agent/chat_client.dart';
import 'package:lopicode/agent/command_runner.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/safe_file.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/state/workspace_background.dart';

import 'agent_test.dart' show RecordingRunner;
import 'command_stop_test.dart' show alive, expectGone;
import 'session_system_test.dart' show RoutingClient, Turn, reply, toolResults, use;
import 'support/harness.dart';

const _all = [kBgStartTool, kBgReadTool, kBgStopTool, kBgListTool];

Future<void> waitFor(bool Function() cond, {String what = '条件', int ms = 8000}) async {
  final end = DateTime.now().add(Duration(milliseconds: ms));
  while (!cond() && DateTime.now().isBefore(end)) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  if (!cond()) fail('等不到：$what');
}

void main() {
  late TestEnv env;
  late Project project;
  late ProjectSession session;
  late List<({List<Map<String, dynamic>> messages, List<String> tools})> log;
  Turn turn = (_, _) => reply('好的。');

  ProjectSession open({bool headless = false, CommandRunner? runner}) => ProjectSession(env.services, project, headless: headless)..commandRunnerFactory = () => runner ?? LocalShellRunner();

  setUp(() async {
    turn = (_, _) => reply('好的。');
    log = [];
    env = await TestEnv.create(chatClient: () => RoutingClient((m, t) => turn(m, t), log));
    project = await env.services.projects.create('测试工作区', ProjectTemplate.web);
    session = open();
    await session.loadChat();
  });
  tearDown(() async {
    session.dispose();
    await pendingWrites();
    await env.dispose();
  });

  BackgroundTasksState state([ProjectSession? s]) => env.services.container.read(backgroundTasksProvider(s ?? session));
  BackgroundTasksNotifier notifier() => env.services.container.read(backgroundTasksProvider(session).notifier);
  List<String> notices([ProjectSession? s]) => [...(s ?? session).chat.whereType<NoticeItem>().map((n) => n.text)];
  List<String> userMessages(int call) => [
    for (final m in log[call].messages)
      if (m['role'] == 'user') '${m['content']}',
  ];

  /// 按顺序回放；放完了就回“好的。”。
  void script(List<List<ChatDelta>> turns) {
    var n = 0;
    turn = (_, _) => n < turns.length ? turns[n++] : reply('好的。');
  }

  group('工具什么时候有', () {
    test('工作区内修改：四个都有', () async {
      await session.sendToAgent('你好');
      expect(log.single.tools, containsAll(_all));
    });

    test('仅可查看：没有启动和停止，只剩看的两个；硬调启动被拒、命令没跑、不弹卡', () async {
      await session.setPermission(PermissionLevel.view);
      script([
        use(kBgStartTool, {'command': 'echo x > hacked.txt'}),
      ]);
      await session.sendToAgent('跑一下');
      expect(log.first.tools, isNot(contains(kBgStartTool)));
      expect(log.first.tools, isNot(contains(kBgStopTool)));
      expect(log.first.tools, containsAll([kBgReadTool, kBgListTool]));
      expect(session.pendingApproval, isNull);
      expect(File('${project.dir}/hacked.txt').existsSync(), isFalse);
      expect(state().tasks, isEmpty);
    });

    test('计划模式：没有启动和停止', () async {
      await session.setPlanMode(true);
      await session.sendToAgent('你好');
      expect(log.single.tools, isNot(contains(kBgStartTool)));
      expect(log.single.tools, isNot(contains(kBgStopTool)));
      expect(log.single.tools, isNot(contains('run_command')), reason: '和 run_command 同进同退');
    });

    test('没人在场的会话（自动化任务用的那种）：四个都没有', () async {
      final quiet = open(headless: true);
      addTearDown(quiet.dispose);
      await quiet.loadChat();
      await quiet.sendToAgent('你好');
      expect(log.last.tools, contains('run_command'));
      for (final name in _all) {
        expect(log.last.tools, isNot(contains(name)));
      }
    });

    test('执行环境不支持后台启动（测试里的假环境）：四个都没有，其余工具不变', () async {
      final plain = open(runner: RecordingRunner());
      addTearDown(plain.dispose);
      await plain.loadChat();
      await plain.sendToAgent('你好');
      expect(log.last.tools, contains('run_command'));
      for (final name in _all) {
        expect(log.last.tools, isNot(contains(name)));
      }
    });
  });

  group('启动和 run_command 同级确认', () {
    test('工作区内修改：出的是 run_command 那张确认卡；拒绝 → 没有执行', () async {
      script([
        use(kBgStartTool, {'command': 'echo x > made.txt; sleep 30'}),
      ]);
      final sending = session.sendToAgent('起个服务');
      await waitFor(() => session.pendingApproval != null, what: '确认卡');
      final card = session.pendingApproval!.request;
      expect(card.tool, 'run_command', reason: '同一种确认卡：同样的危险提示、同样受“本对话都允许”管');
      expect(card.detail, 'echo x > made.txt; sleep 30');
      expect(card.title, '在后台执行命令');
      expect(state().tasks, isEmpty, reason: '没点允许之前不执行');
      session.resolveApproval(false);
      await sending;
      expect(File('${project.dir}/made.txt').existsSync(), isFalse);
      expect(state().tasks, isEmpty);
      expect(toolResults(log.last.messages), contains('用户拒绝执行这条命令'));
    });

    test('允许 → 启动，立刻返回任务号；“本对话都允许”之后 run_command 也不再问（同一个开关）', () async {
      script([
        use(kBgStartTool, {'command': 'echo started; sleep 30'}),
        use('run_command', {'command': 'echo front'}),
        use(kBgStartTool, {'command': 'sleep 30'}),
      ]);
      final sending = session.sendToAgent('起个服务');
      await waitFor(() => session.pendingApproval != null, what: '确认卡');
      session.resolveApproval(true, always: true);
      await sending;
      expect(session.pendingApproval, isNull);
      expect(state().tasks.map((t) => t.id), [1, 2]);
      expect(state().tasks.every((t) => t.running && t.convId == session.activeConversationId), isTrue);
      final results = toolResults(log.last.messages);
      expect(results, contains('后台命令 #1 已启动'));
      expect(results, contains('后台命令 #2 已启动'));
      expect(results, contains('front'));
    });

    test('完全权限：不问，直接启动（和 run_command 一样）', () async {
      await session.setPermission(PermissionLevel.full);
      script([
        use(kBgStartTool, {'command': 'sleep 30'}),
      ]);
      await session.sendToAgent('起个服务');
      expect(session.pendingApproval, isNull);
      expect(state().tasks.single.running, isTrue);
    });

    test('到上限：不出确认卡，直接告诉模型没启动', () async {
      await session.setPermission(PermissionLevel.workspace);
      final manager = notifier().manager;
      await manager.load();
      for (var i = 0; i < kMaxBackgroundRunning; i++) {
        await manager.start(session.activeConversationId, 'sleep 30', LocalShellRunner());
      }
      script([
        use(kBgStartTool, {'command': 'echo x > over.txt'}),
      ]);
      await session.sendToAgent('再起一个');
      expect(session.pendingApproval, isNull);
      expect(toolResults(log.last.messages), contains('上限'));
      expect(File('${project.dir}/over.txt').existsSync(), isFalse);
    });

    test('刚启动就退出的（命令打错）：结果直接给模型，不再另发通知', () async {
      await session.setPermission(PermissionLevel.full);
      script([
        use(kBgStartTool, {'command': 'echo boom >&2; exit 5'}),
      ]);
      await session.sendToAgent('起个服务');
      final results = toolResults(log.last.messages);
      expect(results, contains('刚启动就结束了'));
      expect(results, contains('退出码 5'));
      expect(results, contains('boom'));
      expect(notices(), isEmpty);
      await session.sendToAgent('然后呢');
      expect(userMessages(log.length - 1).where((m) => m.contains('应用通知')), isEmpty);
    });
  });

  group('读输出、停止、清单', () {
    setUp(() => session.setPermission(PermissionLevel.full));

    test('接着读 / 最后 N 行 / 清单 / 停止：模型自己停的不再通知', () async {
      script([
        use(kBgStartTool, {'command': 'echo line-1; echo line-2; echo line-3; sleep 30'}),
        use(kBgReadTool, {'id': 1, 'wait_seconds': 5}),
        use(kBgReadTool, {'id': 1}),
        use(kBgReadTool, {'id': 1, 'tail_lines': 1}),
        use(kBgListTool, {}),
        use(kBgStopTool, {'id': 1}),
        use(kBgReadTool, {'id': 9}),
      ]);
      await session.sendToAgent('起个服务看看输出');
      final results = [
        for (final m in log.last.messages)
          if (m['role'] == 'tool') '${m['content']}',
      ];
      expect(results[1], allOf(contains('在跑'), contains('line-1'), contains('line-3')));
      expect(results[2], allOf(contains('没有新输出'), isNot(contains('新输出：'))), reason: '读过的不再给');
      expect(results[3], endsWith('最后 1 行：\nline-3'));
      expect(results[4], allOf(contains('#1'), contains('echo line-1')));
      expect(results[5], contains('后台命令 #1 已停止'));
      expect(results[6], contains('没有后台命令 #9'));
      expect(state().tasks.single.status, BackgroundStatus.stopped);
      expect(notices(), isEmpty, reason: '模型自己停的：不用提示');
      await session.sendToAgent('好');
      expect(userMessages(log.length - 1).where((m) => m.contains('应用通知')), isEmpty);
    });

    test('别的对话的任务：读不到、停不了', () async {
      final manager = notifier().manager;
      await manager.load();
      final other = await manager.start('另一段对话', 'sleep 30', LocalShellRunner());
      script([
        use(kBgStopTool, {'id': other.id}),
        use(kBgReadTool, {'id': other.id}),
        use(kBgListTool, {}),
      ]);
      await session.sendToAgent('停掉');
      final results = toolResults(log.last.messages);
      expect(results, contains('这段对话里没有后台命令 #${other.id}'));
      expect(results, contains('这段对话里没有后台命令。'));
      expect(manager.byId(other.id)!.running, isTrue);
    });
  });

  group('结束后告诉模型', () {
    setUp(() => session.setPermission(PermissionLevel.full));

    test('对话正在跑：下一次调用模型之前顺带交给它，不多调用一次', () async {
      script([
        use(kBgStartTool, {'command': 'sleep 0.7; echo build-finished; exit 3'}),
        use('run_command', {'command': 'sleep 1.6; echo front-done'}),
        reply('都好了。'),
      ]);
      await session.sendToAgent('后台构建，同时做别的');
      expect(log, hasLength(3), reason: '没有为了通知多调用模型');
      final seen = userMessages(2).where((m) => m.contains('应用通知')).toList();
      expect(seen, hasLength(1));
      expect(seen.single, allOf(contains('后台命令 #1'), contains('退出码 3'), contains('build-finished'), contains('不是用户说的话'), contains('.lopicode/outputs/bg-')));
      expect(userMessages(1).where((m) => m.contains('应用通知')), isEmpty, reason: '还没结束的时候不通知');
      expect(notices(), ['后台命令 #1 已结束（退出码 3），已告诉 AI']);
      expect(state().tasks.single.notified, isTrue);
      await session.sendToAgent('好');
      expect(userMessages(3).where((m) => m.contains('应用通知')), hasLength(1), reason: '历史里那一条还在，没有重复再发');
    });

    test('对话空闲：不自动开一轮，只在聊天里提示一行；下次发消息时带给模型，只带一次', () async {
      script([
        use(kBgStartTool, {'command': 'sleep 0.8; echo late-result'}),
        reply('已在后台跑。'),
      ]);
      await session.sendToAgent('后台跑一下');
      expect(log, hasLength(2));
      expect(session.agentBusy, isFalse);
      await waitFor(() => !state().tasks.single.running, what: '后台命令结束');
      await waitFor(() => notices().isNotEmpty, what: '聊天里的提示');
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(log, hasLength(2), reason: '空闲时不自动调用模型（不花钱）');
      expect(session.agentBusy, isFalse);
      expect(notices(), ['后台命令 #1 已结束（退出码 0）。下次发消息时会告诉 AI。']);
      expect(state().tasks.single.notified, isFalse);

      await session.sendToAgent('结果怎么样');
      expect(log, hasLength(3));
      final users = userMessages(2);
      expect(users[users.length - 2], '结果怎么样', reason: '通知排在她这条消息后面');
      expect(users.last, allOf(contains('应用通知'), contains('后台命令 #1'), contains('late-result')));
      expect(state().tasks.single.notified, isTrue);
      await session.sendToAgent('好');
      expect(userMessages(3).where((m) => m.contains('应用通知')), hasLength(1), reason: '不重复带');
    });

    test('用户自己在面板里停的：照样告诉模型', () async {
      script([
        use(kBgStartTool, {'command': 'echo serving; sleep 30'}),
      ]);
      await session.sendToAgent('起个服务');
      await notifier().stop(1);
      expect(state().tasks.single.status, BackgroundStatus.stopped);
      await waitFor(() => notices().isNotEmpty, what: '提示');
      expect(notices(), ['后台命令 #1 已停止。下次发消息时会告诉 AI。']);
      final before = log.length;
      await session.sendToAgent('我把它停了');
      expect(userMessages(before).last, allOf(contains('后台命令 #1'), contains('已被用户停止'), contains('serving')));
    });

    test('通知交出去了但请求失败、一个字没回：下次再带', () async {
      script([
        use(kBgStartTool, {'command': 'sleep 1; echo once'}),
        reply('在跑了。'),
      ]);
      await session.sendToAgent('后台跑一下');
      await waitFor(() => !state().tasks.single.running, what: '结束');
      var fail = true;
      turn = (_, _) {
        if (fail) throw const SocketException('断网了');
        return reply('收到。');
      };
      expect(state().tasks.single.notified, isFalse);
      await session.sendToAgent('结果呢');
      expect(log.last.messages.where((m) => '${m['content']}'.contains('应用通知')), hasLength(1), reason: '这次请求里带了通知');
      expect(state().tasks.single.notified, isFalse, reason: '模型没收到：还回来');
      fail = false;
      await session.sendToAgent('再问一次');
      expect(userMessages(log.length - 1).where((m) => m.contains('应用通知')), hasLength(1));
      expect(state().tasks.single.notified, isTrue);
    });

    test('点“停止”只停前台这一轮，后台命令接着跑', () async {
      final gate = Completer<void>();
      var n = 0;
      turn = (_, _) async {
        if (n++ == 0) return use(kBgStartTool, {'command': 'sleep 30'});
        await gate.future;
        return reply('好。');
      };
      final sending = session.sendToAgent('起个服务');
      await waitFor(() => state().tasks.isNotEmpty && log.length == 2, what: '启动完、第二次请求在等');
      session.stopAgent();
      gate.complete();
      await sending;
      expect(state().tasks.single.running, isTrue);
    });
  });

  group('生命周期', () {
    setUp(() => session.setPermission(PermissionLevel.full));

    Future<int> startWithPid() async {
      script([
        use(kBgStartTool, {'command': r'echo pid:$$; sleep 30'}),
      ]);
      await session.sendToAgent('起个服务');
      final manager = notifier().manager;
      await waitFor(() => RegExp(r'pid:\d+').hasMatch(manager.tail(1)), what: '进程号');
      return int.parse(RegExp(r'pid:(\d+)').firstMatch(manager.tail(1))!.group(1)!);
    }

    test('关掉工作区：后台命令全部结束，进程不留', () async {
      final id = await startWithPid();
      expect(alive(id), isTrue);
      session.dispose();
      await expectGone([id], reason: '工作区关了，后台命令不该留下');
    });

    test('删掉对话：它的后台命令一起停掉', () async {
      final id = await startWithPid();
      await session.deleteConversation();
      await expectGone([id]);
      expect(state().tasks, isEmpty);
    });

    test('重开工作区：上次的任务标成“已中断”（或关闭时停掉），聊天里提示一行，不自动重跑，发消息时告诉模型', () async {
      await startWithPid();
      session.dispose();
      await pendingWrites();
      session = open();
      await session.loadChat();
      final task = state().tasks.single;
      expect(task.running, isFalse);
      expect(task.status, BackgroundStatus.stopped);
      expect(task.stoppedBy, StoppedBy.close);
      expect(notices(), ['后台命令 #1 在工作区关闭时停掉了。下次发消息时会告诉 AI。']);
      final before = log.length;
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(log, hasLength(before), reason: '不自动重跑、不自动开一轮');
      await session.sendToAgent('接着来');
      expect(userMessages(before).last, allOf(contains('后台命令 #1'), contains('工作区关闭时已停止')));
    });
  });

  group('状态（backgroundTasksProvider）', () {
    test('一开始是空的；有任务后快照跟着变，快照不可改', () async {
      expect(state().tasks, isEmpty);
      final seen = <int>[];
      final sub = env.services.container.listen(backgroundTasksProvider(session), (_, next) => seen.add(next.tasks.length));
      addTearDown(sub.close);
      final manager = notifier().manager;
      await manager.load();
      final t = await manager.start('c1', 'echo hi; sleep 30', LocalShellRunner());
      expect(state().tasks.single.id, t.id);
      expect(state().of('c1'), hasLength(1));
      expect(state().of('c2'), isEmpty);
      expect(() => state().tasks.add(t), throwsUnsupportedError);
      await waitFor(() => notifier().logTail(t.id) == 'hi', what: '日志');
      await notifier().stop(t.id);
      expect(state().tasks.single.status, BackgroundStatus.stopped);
      expect(state().tasks.single.stoppedBy, StoppedBy.user);
      expect(seen, isNotEmpty);
    });

    test('工作区已经关掉以后再读：空的，不出错', () async {
      session.dispose();
      expect(state().tasks, isEmpty);
    });
  });
}
