// 工作区一级的状态（lib/state/workspace_*.dart）：文件变动信号、终端列表、预览、对话目录。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/agent/model_config.dart';
import 'package:lopicode/agent/usage.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/state/workspace_conversations.dart';
import 'package:lopicode/state/workspace_files.dart';
import 'package:lopicode/state/workspace_preview.dart';
import 'package:lopicode/state/workspace_terminals.dart';
import 'package:lopicode/terminal/terminal_session.dart';

import 'support/harness.dart';

void main() {
  late TestEnv env;
  late Project project;
  late ProjectSession session;

  setUp(() async {
    env = await TestEnv.create();
    project = await env.services.projects.create('测试工作区', ProjectTemplate.web);
    session = ProjectSession(env.services, project, headless: true);
  });
  tearDown(() async {
    session.dispose();
    await env.dispose();
  });

  group('文件变动信号', () {
    test('filesChanged 一次通知一次；两个工作区互不串', () async {
      final other = ProjectSession(env.services, await env.services.projects.create('另一个', ProjectTemplate.web), headless: true);
      addTearDown(other.dispose);
      final box = env.services.container;
      var mine = 0, theirs = 0;
      box.listen(filesRevProvider(session), (_, _) => mine++);
      box.listen(filesRevProvider(other), (_, _) => theirs++);
      session.filesChanged();
      session.filesChanged();
      expect((mine, theirs), (2, 0));
      expect(box.read(filesRevProvider(session)), 2);
      other.filesChanged();
      expect((mine, theirs), (2, 1));
    });

    test('工作区关掉以后再调：不通知、不报错；应用销毁以后也一样', () {
      final box = env.services.container;
      var n = 0;
      final closed = ProjectSession(env.services, project, headless: true);
      box.listen(filesRevProvider(closed), (_, _) => n++);
      closed.dispose();
      closed.filesChanged();
      expect(n, 0);

      final late_ = ProjectSession(env.services, project, headless: true);
      env.services.dispose();
      late_.filesChanged(); // 不抛异常就是过
      late_.dispose();
    });
  });

  group('终端列表', () {
    late ProjectSession ui;
    setUp(() => ui = ProjectSession(env.services, project));
    tearDown(() => ui.dispose());

    test('带界面的工作区一打开就有一个本机会话；不带界面的不开', () {
      final box = env.services.container;
      expect(box.read(terminalsProvider(ui)).sessions.single.title, '本机 1');
      expect(box.read(terminalsProvider(ui)).active, 0);
      expect(box.read(terminalsProvider(session)).sessions, isEmpty);
      expect(session.terminals, isEmpty);
    });

    test('新开、切换、关掉：列表和当前项跟着变；只剩一个时关不掉；越界的序号不理', () {
      final box = env.services.container;
      final ctl = box.read(terminalsProvider(ui).notifier);
      var n = 0;
      box.listen(terminalsProvider(ui), (_, _) => n++);
      final second = ctl.addLocal(forceLocal: true);
      expect(second.title, '本机 2');
      expect(box.read(terminalsProvider(ui)).active, 1);
      expect(box.read(terminalsProvider(ui)).current, same(second));
      ctl.select(0);
      expect(ui.activeTerminal, 0);
      ctl.select(9);
      ctl.select(-1);
      expect(ui.activeTerminal, 0);
      ctl.select(1);
      ctl.close(1);
      expect(ui.terminals.single.title, '本机 1');
      expect(ui.activeTerminal, 0, reason: '关掉最后一个后当前项退回前一个');
      final before = n;
      ctl.close(0);
      ctl.close(5);
      expect(ui.terminals.length, 1);
      expect(n, before, reason: '没变就不通知');
      expect(() => ui.terminals.add(second), throwsUnsupportedError, reason: '列表不能被外面直接改');
    });

    test('Ctrl 点亮 / 熄灭会通知订阅的人', () {
      final box = env.services.container;
      var n = 0;
      box.listen(terminalsProvider(ui), (_, _) => n++);
      ui.terminals.single.toggleCtrl();
      expect(n, 1);
      expect(ui.terminals.single.ctrlArmed, isTrue);
      ui.terminals.single.sendText('c'); // 用掉 Ctrl
      expect(ui.terminals.single.ctrlArmed, isFalse);
      expect(n, 2);
    });

    test('工作区关掉：会话都收掉、列表清空，之后再开也不留进程、不通知', () {
      final box = env.services.container;
      final closing = ProjectSession(env.services, project);
      final ctl = box.read(terminalsProvider(closing).notifier);
      final TerminalSession first = closing.terminals.single;
      var n = 0;
      box.listen(terminalsProvider(closing), (_, _) => n++);
      closing.dispose();
      expect(first.onChanged, isNull, reason: '会话已经被收掉');
      expect(closing.terminals, isEmpty);
      first.toggleCtrl(); // 收掉以后再动它：不通知、不报错
      final n0 = n;
      ctl.select(0);
      ctl.close(0);
      expect(n, n0);
      expect(box.read(terminalsProvider(closing)).sessions, isEmpty);
    });
  });

  group('预览', () {
    test('起服务器：起好了状态变成 ready；连着调两次只起一个；能取到项目里的文件', () async {
      final box = env.services.container;
      final ctl = box.read(previewProvider(session).notifier);
      expect(box.read(previewProvider(session)).ready, isFalse);
      final a = ctl.start(), b = ctl.start();
      await Future.wait<void>([a, b]);
      expect(box.read(previewProvider(session)).ready, isTrue);
      expect(box.read(previewProvider(session)).error, isNull);
      final port = session.preview.port;
      expect(port, greaterThan(0));
      await ctl.start();
      expect(session.preview.port, port, reason: '没有重新起');
      final client = HttpClient();
      final res = await (await client.getUrl(Uri.parse('http://127.0.0.1:$port/index.html'))).close();
      expect(res.statusCode, 200);
      await res.drain<void>();
      client.close(force: true);
    });

    test('控制台日志变了（这里用清空）会通知订阅的人', () async {
      final box = env.services.container;
      final ctl = box.read(previewProvider(session).notifier);
      var n = 0;
      box.listen(previewProvider(session), (_, _) => n++);
      ctl.clearLogs();
      await Future<void>.delayed(Duration.zero);
      expect(n, 1);
      expect(box.read(previewProvider(session)).logRev, 1);
    });

    test('工作区关掉：服务器停掉；起到一半关掉也不留端口、不往状态里写', () async {
      final box = env.services.container;
      final closing = ProjectSession(env.services, project, headless: true);
      final ctl = box.read(previewProvider(closing).notifier);
      await ctl.start();
      final server = ctl.server;
      expect(server.isRunning, isTrue);
      closing.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(server.isRunning, isFalse);

      final half = ProjectSession(env.services, project, headless: true);
      final halfCtl = box.read(previewProvider(half).notifier);
      final halfServer = halfCtl.server;
      final starting = halfCtl.start();
      half.dispose();
      await starting;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(halfServer.isRunning, isFalse);
      expect(box.read(previewProvider(half)).ready, isFalse);
    });
  });

  group('对话目录', () {
    ConversationsNotifier ctl() => env.services.container.read(conversationsProvider(session).notifier);
    ConversationsState now() => env.services.container.read(conversationsProvider(session));

    test('第一次读：盘上没有目录就补一段主对话；只读一次', () async {
      expect(now().loaded, isFalse);
      expect(now().active.id, 'main', reason: '没读出来之前有个顶替的空对话');
      await Future.wait<void>([ctl().load(), ctl().load()]);
      expect(now().loaded, isTrue);
      expect(now().all.single.id, 'main');
      expect(now().activeId, 'main');
    });

    test('没读出来之前不存盘：不会拿空目录盖掉盘上的', () async {
      final c = ctl();
      await c.load();
      c.add(Conversation('abc', '第二段', DateTime(2026, 11, 23)), front: true, activate: true);
      await c.save();
      // 另开一个工作区对象（相当于重新打开）：还没读就存，盘上的两段都还在
      final again = ProjectSession(env.services, project, headless: true);
      addTearDown(again.dispose);
      final c2 = env.services.container.read(conversationsProvider(again).notifier);
      await c2.save();
      await c2.load();
      expect(c2.current.all.map((x) => x.id), containsAll(['main', 'abc']));
    });

    test('加、改、切、删：每次都换新列表，旧的那份不变；列表不能被外面直接改', () async {
      final c = ctl();
      await c.load();
      final before = now();
      c.add(Conversation('kid', '子代理', DateTime(2026, 11, 23), parentId: 'main', depth: 1, agentName: '前端'));
      c.add(Conversation('two', '', DateTime(2026, 11, 23)), front: true, activate: true);
      expect(before.all.length, 1, reason: '旧状态没被改');
      expect(now().all.map((x) => x.id), ['two', 'main', 'kid']);
      expect(now().activeId, 'two');
      expect(now().top.map((x) => x.id), ['two', 'main']);
      expect(now().rootOf(now().byId('kid')!).id, 'main');
      expect(now().descendantsOf('main').single.id, 'kid');
      expect(() => now().all.add(Conversation('x', '', DateTime.now())), throwsUnsupportedError);

      final old = now().byId('main')!;
      c.update('main', (x) => x.copyWith(title: '改了', planMode: true, permission: 'view'), toFront: true);
      expect((old.title, old.planMode, old.permission), ('', false, null), reason: '旧对象没被改');
      expect(now().all.first.id, 'main');
      expect((now().byId('main')!.title, now().byId('main')!.planMode, now().byId('main')!.permission), ('改了', true, 'view'));
      expect(c.update('nope', (x) => x.copyWith(title: '没有这段')), isNull);

      c.activate('nope');
      expect(now().activeId, 'two', reason: '没有的对话切不过去');
      c.activate('main');
      expect(now().activeId, 'main');

      c.removeAll({'main', 'kid', 'two'});
      expect(now().all.single.id, 'main', reason: '删光了补一段空的');
      expect(now().all.single.title, '');
      expect(now().activeId, 'main');
    });

    test('用量累计：换一份新的合计，轮数加一，旧的那份不变', () async {
      final c = ctl();
      await c.load();
      final old = now().byId('main')!;
      final turn = UsageTotals()
        ..uncached = 10
        ..output = 5
        ..requests = 2;
      c.update('main', (x) => x.withTurn(turn));
      c.update('main', (x) => x.withTurn(turn));
      final u = now().byId('main')!.usage;
      expect((u.uncached, u.output, u.requests, u.turns), (20, 10, 4, 2));
      expect(old.usage.requests, 0);
    });

    test('存盘再读：标题、模型、权限、计划模式、预设、用量都在', () async {
      final c = ctl();
      await c.load();
      c.update(
        'main',
        (x) => x.copyWith(title: '标题', selection: const ModelSelection('ch', 'm'), permission: 'full', planMode: true, presetId: 'p1', lastInput: 123).withTurn(UsageTotals()..requests = 1),
      );
      await c.save();
      await c.setProjectRules('  只用中文  ');
      expect(now().projectRules, '只用中文');
      final again = ProjectSession(env.services, project, headless: true);
      addTearDown(again.dispose);
      final c2 = env.services.container.read(conversationsProvider(again).notifier);
      await c2.load();
      final m = c2.current.byId('main')!;
      expect((m.title, m.selection?.channelId, m.permission, m.planMode, m.presetId, m.lastInput, m.usage.turns), ('标题', 'ch', 'full', true, 'p1', 123, 1));
      expect(c2.current.projectRules, '只用中文');
    });

    test('工作区关掉：读到一半不往状态里写；关掉后的改动不通知订阅的人', () async {
      final closing = ProjectSession(env.services, project, headless: true);
      final box = env.services.container;
      final c = box.read(conversationsProvider(closing).notifier);
      var n = 0;
      box.listen(conversationsProvider(closing), (_, _) => n++);
      final loading = c.load();
      closing.dispose();
      await loading;
      expect(c.current.loaded, isFalse);
      expect(closing.released, isTrue);
      box.read(conversationsProvider(closing)); // 放掉时状态归零，订阅的人收到的是空目录
      final n0 = n;
      c.add(Conversation('late', '', DateTime.now()));
      expect(box.read(conversationsProvider(closing)).all, isEmpty);
      expect(n, n0);
    });
  });
}
