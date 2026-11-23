// 工作区一级的状态（lib/state/workspace_*.dart）：文件变动信号、终端列表、预览。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/project_session.dart';
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
  tearDown(() {
    session.dispose();
    env.dispose();
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
}
