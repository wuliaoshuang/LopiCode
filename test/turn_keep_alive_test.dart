// 后台保活接到真实会话上的测试（不带界面、假模型、假通知宿主）：
// 一轮开始 → 开；跑的过程里通知上的字跟着步骤走；卡在确认卡上 → “在等你确认”；结束 → 关 + 提醒；
// 通知上点停止 = 聊天页的停止；排队的下一条接着跑时服务不关；自动化任务也算。
//   flutter test test/turn_keep_alive_test.dart
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/agent/agent_tools.dart';
import 'package:lopicode/agent/automation.dart';
import 'package:lopicode/agent/chat_client.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/stores.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/session/turn_keep_alive.dart';

import 'agent_test.dart' show RecordingRunner;
import 'session_system_test.dart' show RoutingClient, Turn, reply, use, waitFor;
import 'support/harness.dart';
import 'support/keep_alive_fakes.dart';

void main() {
  group('通知上那句“正在做什么”', () {
    ToolItem tool(String name, Map<String, dynamic> args, {bool done = false}) => ToolItem('c${args.hashCode}', name, _json(args), result: done ? 'ok' : null);

    test('按这一轮最新的状态说；步数只数这一轮', () {
      expect(turnStatusText(const []), '正在等模型回应');
      expect(turnStatusText(const [UserItem('你好')]), '正在等模型回应');
      expect(turnStatusText(const [UserItem('你好'), ThinkingItem('嗯', streaming: true)]), '正在思考');
      expect(turnStatusText(const [UserItem('你好'), AssistantItem('好的', streaming: true)]), '正在写回复');
      final old = [
        const UserItem('上一轮'),
        tool('read_file', {'path': 'a.dart'}, done: true),
        const AssistantItem('读完了'),
      ];
      expect(
        turnStatusText([
          ...old,
          const UserItem('这一轮'),
          tool('write_file', {'path': 'lib/a.dart', 'content': 'x'}),
        ]),
        '第 1 步 · 正在改 lib/a.dart',
      );
      expect(
        turnStatusText([
          ...old,
          const UserItem('这一轮'),
          tool('write_file', {'path': 'lib/a.dart'}, done: true),
          tool('run_command', {'command': 'npm test'}),
        ]),
        '第 2 步 · 正在跑命令：npm test',
      );
      expect(
        turnStatusText([
          const UserItem('这一轮'),
          tool('read_file', {'path': 'b.dart'}, done: true),
        ]),
        '第 1 步 · 正在想下一步',
      );
    });

    test('各种工具都有一句人话；参数坏了、没见过的工具也不崩', () {
      String one(String name, [Map<String, dynamic> args = const {}]) => turnStatusText([const UserItem('x'), tool(name, args)]).replaceFirst('第 1 步 · ', '');
      expect(one('read_file', {'path': 'a.txt'}), '正在读 a.txt');
      expect(one('delete_file', {'path': 'a.txt'}), '正在删 a.txt');
      expect(one('list_files'), '正在看文件列表');
      expect(one('run_command'), '正在跑命令');
      expect(one('web_search', {'query': '私人问题'}), '正在联网搜索', reason: '搜索词不上通知');
      expect(one('spawn_agent', {'name': '小助手', 'task': '很长的任务'}), '正在派子代理');
      expect(one('ask_user', {'question': '用哪个？'}), '在等你回答');
      expect(one('update_todos'), '正在更新待办清单');
      expect(one('some_new_tool'), '正在调用 some_new_tool');
      expect(turnStatusText(const [UserItem('x'), ToolItem('c1', 'write_file', '{"path": "半截')]), '第 1 步 · 正在改');
      expect(turnStatusText(const [UserItem('x'), ToolItem('c1', 'write_file', '{"path": 42}')]), '第 1 步 · 正在改');
    });
  });

  group('接到会话上', () {
    late TestEnv env;
    late Project project;
    late ProjectSession session;
    late FakeKeepAliveHost host;
    late List<({List<Map<String, dynamic>> messages, List<String> tools})> log;
    Turn turn = (_, _) => reply('好的。');

    const linger = Duration(milliseconds: 80);

    setUp(() async {
      log = [];
      turn = (_, _) => reply('好的。');
      env = await TestEnv.create(chatClient: () => RoutingClient((m, t) => turn(m, t), log));
      host = FakeKeepAliveHost();
      env.services.keepAlive
        ..attach(host)
        ..minGap = const Duration(milliseconds: 10)
        ..linger = linger;
      project = await env.services.projects.create('测试工作区', ProjectTemplate.web);
      session = ProjectSession(env.services, project, headless: true);
      session.commandRunnerFactory = RecordingRunner.new;
      await session.loadChat();
    });
    tearDown(() async {
      session.dispose();
      await env.dispose();
    });

    Future<void> idle() => waitFor(() => host.of('stop').isNotEmpty, what: '服务关掉');

    test('一轮开始就开，结束后关；应用看得见时不提醒', () async {
      final gate = Completer<void>();
      turn = (m, t) async {
        await gate.future;
        return reply('好');
      };
      final sending = session.sendToAgent('你好');
      await waitFor(() => host.of('start').isNotEmpty, what: '服务开起来');
      expect(env.services.keepAlive.running, 1);
      gate.complete();
      await sending;
      await idle();
      expect(env.services.keepAlive.running, 0);
      expect(host.of('start').length, 1);
      expect(host.of('alert'), isEmpty);
    });

    test('通知上的字跟着步骤走；命令里的密钥被抹掉', () async {
      await session.setPermission(PermissionLevel.full);
      final gate = Completer<void>();
      var n = 0;
      turn = (m, t) async {
        switch (n++) {
          case 0:
            return use('write_file', {'path': 'lib/a.dart', 'content': 'void main() {}'});
          case 1:
            return use('run_command', {'command': 'curl -H "Authorization: Bearer abcdefgh12345678" https://example.com'});
          default:
            await gate.future;
            return reply('做完了');
        }
      };
      final sending = session.sendToAgent('写个文件再跑一下');
      await waitFor(() => n == 3, what: '两步都跑完');
      await waitFor(() => host.shown?.text == '第 2 步 · 正在想下一步', what: '通知上的字换到最新');
      final texts = [for (final c in host.calls.where((c) => c.startsWith('update:') || c.startsWith('start:'))) c];
      expect(texts.join('\n'), isNot(contains('abcdefgh12345678')), reason: '密钥不上通知');
      gate.complete();
      await sending;
      await idle();
    });

    test('看不见时卡在确认卡上：发“在等你确认”；点了允许后收掉；做完再发“做完了”', () async {
      var n = 0;
      turn = (m, t) => n++ == 0 ? use('run_command', {'command': 'npm install'}) : reply('装好了');
      host.setVisible!(false);
      final sending = session.sendToAgent('装一下依赖');
      await waitFor(() => session.pendingApproval != null, what: '确认卡');
      await waitFor(() => host.of('alert').isNotEmpty, what: '等确认的提醒');
      expect(host.of('alert').single, startsWith('alert:waiting:Agent 在等你确认|'));
      expect(host.of('alert').single, isNot(contains('npm install')), reason: '提醒里不带命令');
      await waitFor(() => host.shown?.title == 'Agent 在等你确认', what: '常驻通知也换成等确认');
      session.resolveApproval(true);
      await sending;
      expect(host.of('cancel'), contains('cancel:waiting'));
      await waitFor(() => host.of('alert').length == 2, what: '做完的提醒');
      expect(host.of('alert').last, startsWith('alert:done:Agent 做完了|装一下依赖'));
    });

    test('模型接口报错、应用看不见：发“出错了”，不带错误内容', () async {
      turn = (m, t) => throw ChatApiException('接口 401：api_key=sk-abcdefghijklmnop 无效');
      host.setVisible!(false);
      await session.sendToAgent('你好');
      await waitFor(() => host.of('alert').isNotEmpty, what: '出错的提醒');
      expect(host.of('alert').single, startsWith('alert:failed:Agent 出错了，没做完|'));
      expect(host.of('alert').single, isNot(contains('401')));
      expect(host.of('alert').single, isNot(contains('sk-')));
    });

    test('通知上点停止 = 聊天页点停止：这一轮停下，排着的消息不自动发，也不提醒', () async {
      final gate = Completer<void>();
      var n = 0;
      turn = (m, t) async {
        if (n++ == 0) await gate.future;
        return reply('好');
      };
      final first = session.sendToAgent('第一条');
      await waitFor(() => log.isNotEmpty);
      await session.sendToAgent('排着的');
      host.setVisible!(false);
      host.pressStop!();
      await waitFor(() => host.shown?.text == '正在停止…', what: '通知换成正在停止');
      gate.complete();
      await first;
      await idle();
      expect(session.agentBusy, isFalse);
      expect(session.queue.single.text, '排着的');
      expect(log, hasLength(1));
      expect(session.chat.whereType<NoticeItem>().any((x) => x.text.startsWith('已停止')), isTrue);
      expect(host.of('alert'), isEmpty);
    });

    test('排队的下一条接着跑：中间服务不关不重开，最后只提醒一次', () async {
      final gate = Completer<void>();
      var n = 0;
      turn = (m, t) async {
        if (n++ == 0) await gate.future;
        return reply('好');
      };
      // 两轮之间要存盘、读技能，机器忙的时候不止几十毫秒：这里按真机的思路留足余量（真机上是 3 秒）
      env.services.keepAlive.linger = const Duration(seconds: 1);
      host.setVisible!(false);
      final first = session.sendToAgent('第一条');
      await waitFor(() => log.isNotEmpty);
      await session.sendToAgent('第二条');
      gate.complete();
      await first;
      await waitFor(() => !session.agentBusy && log.length == 2, what: '第二条也跑完');
      await idle();
      expect(host.of('start').length, 1);
      expect(host.of('stop').length, 1);
      await waitFor(() => host.of('alert').isNotEmpty, what: '做完的提醒');
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      expect(host.of('alert').length, 1);
    });

    test('设置里把保活关了：不开服务，提醒照发；把提醒也关了：都不发', () async {
      await env.services.settings.set(SettingKeys.agentKeepAlive, false);
      host.setVisible!(false);
      await session.sendToAgent('你好');
      await waitFor(() => host.of('alert').isNotEmpty, what: '做完的提醒');
      expect(host.of('start'), isEmpty);
      await env.services.settings.set(SettingKeys.agentNotifyDone, false);
      await session.sendToAgent('再来');
      await Future<void>.delayed(linger * 3);
      expect(host.of('alert').length, 1);
      expect(host.of('start'), isEmpty);
    });

    test('自动化任务在跑也保活；做完的提醒写明是自动化任务', () async {
      host.setVisible!(false);
      final gate = Completer<void>();
      turn = (m, t) async {
        await gate.future;
        return reply('检查完了');
      };
      final a = Automation(
        id: 'a1',
        title: '每日检查',
        instruction: '看看有没有问题',
        workspaceId: project.id,
        rule: TimeRule(kind: RuleKind.daily, tzOffsetMinutes: 480),
      );
      final running = session.runAutomation(a);
      await waitFor(() => host.of('start').isNotEmpty, what: '服务开起来');
      gate.complete();
      await running;
      await waitFor(() => host.of('alert').isNotEmpty, what: '做完的提醒');
      expect(host.of('alert').single, startsWith('alert:done:自动化任务做完了|'));
    });

    test('通道每次都抛错：对话照常跑完', () async {
      host.broken = true;
      host.setVisible!(false);
      var n = 0;
      turn = (m, t) => n++ == 0 ? use('read_file', {'path': 'index.html'}) : reply('读完了');
      await session.sendToAgent('读一下');
      expect(session.agentBusy, isFalse);
      expect(session.chat.whereType<AssistantItem>().last.text, '读完了');
      await Future<void>.delayed(linger * 2);
    });

    test('应用销毁后还在收尾的那一轮：不再调用原生', () async {
      final gate = Completer<void>();
      turn = (m, t) async {
        await gate.future;
        return reply('好');
      };
      final sending = session.sendToAgent('你好');
      await waitFor(() => host.of('start').isNotEmpty);
      env.services.dispose();
      final before = host.calls.length;
      expect(host.calls.last, 'stop');
      gate.complete();
      await sending;
      await Future<void>.delayed(linger * 2);
      expect(host.calls.length, before);
    });
  });
}

String _json(Map<String, dynamic> args) => '{${args.entries.map((e) => '"${e.key}": ${e.value is String ? '"${e.value}"' : e.value}').join(', ')}}';
