// 第 1 条真机反馈：安卓上不再用手机自带的命令行。没装运行环境时终端页是安装引导，
// 装了但起不来时显示原因和出路，Agent 的 run_command 不悄悄退回本机 shell。
//
// 测试都跑在宿主机上，不假装自己是安卓：用 `LinuxRuntime(localShellAllowed: false)` 直接走安卓那条路。
// 不联网、不下载：安装走“空间不够”这条在联网之前就失败的路，或者用 markInstalled 摆出“已安装”。
// LOPI_SHOTS=1 时把截图写到 docs/screenshots/。
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lopicode/agent/agent_tools.dart';
import 'package:lopicode/agent/command_runner.dart';
import 'package:lopicode/app.dart';
import 'package:lopicode/app_services.dart';
import 'package:lopicode/backend/backend_launch.dart';
import 'package:lopicode/core/path_guard.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/stores.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/runtime/linux_command_runner.dart';
import 'package:lopicode/runtime/linux_runtime.dart';
import 'package:lopicode/runtime/linux_shell_backend.dart';
import 'package:lopicode/runtime/runtime_diagnostics.dart';
import 'package:lopicode/runtime/runtime_screen.dart';
import 'package:lopicode/ssh/ssh_config.dart';
import 'package:lopicode/ssh/ssh_connect_screen.dart';
import 'package:lopicode/ui/project_shell.dart';
import 'package:lopicode/ui/shell.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import 'support/harness.dart';
import 'support/runtime_fakes.dart';

final bool writeShots = Platform.environment['LOPI_SHOTS'] == '1';
bool fontsLoaded = false;

Future<void> shot(WidgetTester tester, String name) async {
  expect(tester.takeException(), isNull, reason: '$name 渲染时出了异常');
  if (!writeShots || !fontsLoaded) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(shotKey));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    File('docs/screenshots/$name.png')
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(data!.buffer.asUint8List());
  });
}

/// 一联网就让测试失败的客户端：保证这里的用例绝不真下载。
class _NoNetwork extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) => throw StateError('测试里不许联网：${request.url}');
}

class Env {
  Env(this.tmp, this.services, this.host);
  final Directory tmp;
  final AppServices services;
  final FakeRuntimeHost host;
  LinuxRuntime get runtime => services.runtime;

  /// [android] 为 true：按安卓的规矩来（不许用本机 shell）。
  static Future<Env> create({bool android = true, bool installed = false, bool proot = true, int free = 23 * 1024 * 1024 * 1024}) async {
    final tmp = Directory.systemTemp.createTempSync('lopi_tsetup_');
    final settings = SettingsStore(File(p.join(tmp.path, 'settings.json')));
    final host = FakeRuntimeHost(nativeDir: proot ? makeFakeNativeDir(tmp) : tmp.path, free: free);
    final runtime = LinuxRuntime(settings: settings, baseDir: p.join(tmp.path, 'runtime'), host: host, httpClient: _NoNetwork.new, localShellAllowed: android ? false : null);
    if (installed) markInstalled(runtime);
    await runtime.init();
    return Env(tmp, AppServices(settings: settings, secrets: MemorySecretStore(), projects: ProjectStore(p.join(tmp.path, 'projects')), runtime: runtime), host);
  }

  Widget app(Widget home, ThemeMode mode) => RepaintBoundary(
    key: shotKey,
    child: LopiCodeApp(services: services, home: home, fontFamily: kTestFont, forceThemeMode: mode),
  );

  void dispose() {
    services.dispose();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  }
}

/// 一启动就报错退出的假伪终端（模拟 PRoot 起不来）。
FakePty failingPty() => FakePty()
  ..emit('proot error: execve("/usr/bin/env"): Permission denied\r\n')
  ..exit(255);

void main() {
  setUpAll(() async => fontsLoaded = await loadRealFonts());

  group('平台判断', () {
    test('默认按平台定：宿主机（不是安卓）允许本机 shell；显式传 false 就是安卓的规矩', () async {
      final tmp = Directory.systemTemp.createTempSync('lopi_plat_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final settings = SettingsStore(File(p.join(tmp.path, 's.json')));
      final byPlatform = LinuxRuntime(settings: settings, baseDir: p.join(tmp.path, 'a'));
      expect(byPlatform.localShellAllowed, !Platform.isAndroid);
      expect(byPlatform.localShellAllowed, isTrue, reason: '测试跑在宿主机上');
      expect(byPlatform.needsSetup, isFalse, reason: '允许本机 shell 的平台从不强制安装');
      expect(byPlatform.view.needsSetup, isFalse);
      final android = LinuxRuntime(settings: settings, baseDir: p.join(tmp.path, 'b'), localShellAllowed: false);
      expect(android.needsSetup, isTrue);
      expect(android.view.needsSetup, isTrue);
      expect(android.view.localShellAllowed, isFalse);
    });
  });

  group('终端列表（安卓的规矩）', () {
    late Env env;
    late Project project;
    late ProjectSession session;

    Future<void> open({bool installed = false, bool proot = true}) async {
      env = await Env.create(installed: installed, proot: proot);
      project = await env.services.projects.create('我的小站', ProjectTemplate.web);
      session = ProjectSession(env.services, project);
      session.linuxPtySpawner = (exe, args, {required workingDirectory, required environment, required rows, required columns}) => FakePty();
    }

    tearDown(() {
      session.dispose();
      env.dispose();
    });

    test('没装运行环境：一个会话都不开，也开不出本机 shell（强制也不行）', () async {
      await open();
      expect(session.terminals, isEmpty);
      expect(session.addTerminal(), isNull);
      expect(session.addTerminal(forceLocal: true), isNull);
      expect(session.terminals, isEmpty);
    });

    test('没装运行环境：SSH 会话照样能开，而且可以关到一个不剩（回到安装引导）', () async {
      await open();
      final ssh = session.addSshTerminal(const SshConfig(host: '10.0.0.2', port: 22, user: 'me'));
      expect(session.terminals.single, same(ssh));
      session.closeTerminal(0);
      expect(session.terminals, isEmpty);
      expect(session.activeTerminal, 0);
    });

    test('装好的那一下：自动开一个 Ubuntu 会话并切过去；之后环境再有动静不会重复开', () async {
      await open();
      final ssh = session.addSshTerminal(const SshConfig(host: '10.0.0.2', port: 22, user: 'me'));
      markInstalled(env.runtime);
      await env.runtime.init(); // 安装完成时运行环境就是这样通知出来的
      expect(session.terminals.map((t) => t.title), ['SSH 1', 'Ubuntu 1']);
      expect(session.terminals.first, same(ssh));
      expect(session.activeTerminal, 1);
      expect(session.terminals.last.backend, isA<LinuxShellBackend>());
      env.runtime.log('随便记一行');
      env.runtime.resetLaunchFailures();
      expect(session.terminals.length, 2);
      // 用户自己把 Ubuntu 会话关了：不会因为环境记了一行日志又被开回来
      session.closeTerminal(1);
      env.runtime.log('再记一行');
      expect(session.terminals.single, same(ssh));
    });

    test('已装环境：一打开就是 Ubuntu 会话，没有本机会话；强制本机也还是 Ubuntu', () async {
      await open(installed: true);
      expect(session.terminals.single.title, 'Ubuntu 1');
      final more = session.addTerminal(forceLocal: true)!;
      expect(more.title, 'Ubuntu 2');
      expect(more.backend, isA<LinuxShellBackend>());
      expect(session.terminals.where((t) => t.title.startsWith('本机')), isEmpty);
    });

    test('连续启动失败以后新开的会话仍然是 Ubuntu，不是本机 shell', () async {
      await open(installed: true);
      env.runtime
        ..recordLaunchFailure('a')
        ..recordLaunchFailure('b');
      expect(env.runtime.shouldUseLinux, isFalse);
      expect(session.addTerminal()!.backend, isA<LinuxShellBackend>());
    });

    test('环境被卸掉：Ubuntu 会话收掉（已经进不去了），SSH 会话留着', () async {
      await open(installed: true);
      session.addSshTerminal(const SshConfig(host: '10.0.0.2', port: 22, user: 'me'));
      expect(session.terminals.length, 2);
      await env.runtime.uninstall();
      expect(session.terminals.single.title, 'SSH 1');
      expect(session.activeTerminal, 0);
      expect(env.runtime.needsSetup, isTrue);
    });

    test('安装包里缺 PRoot：下载了也算不能用，不开会话', () async {
      await open(installed: true, proot: false);
      expect(env.runtime.needsSetup, isTrue);
      expect(session.terminals, isEmpty);
    });

    test('后端积木“在终端启动”：没装环境时不开本机终端、什么都不敲，返回 null；装好后正常', () async {
      await open();
      expect(launchBackendInTerminal(session, 'node server.js'), isNull);
      expect(session.terminals, isEmpty);
      markInstalled(env.runtime);
      await env.runtime.init();
      final t = launchBackendInTerminal(session, 'node server.js')!;
      expect(t.title, kBackendTerminalTitle);
      expect(t.backend, isA<LinuxShellBackend>());
    });
  });

  group('Ubuntu 启动失败（安卓的规矩）', () {
    late Env env;
    setUp(() async => env = await Env.create(installed: true));
    tearDown(() => env.dispose());

    test('失败不退回本机 shell：进“启动失败”状态，带真实原因；重试、兼容模式重试都还是进 Ubuntu', () async {
      final envs = <Map<String, String>>[];
      final local = <FakePty>[];
      var fail = true;
      FakePty? good;
      final backend = LinuxShellBackend(
        runtime: env.runtime,
        projectDir: env.tmp.path,
        quickExit: const Duration(milliseconds: 60),
        spawner: (exe, args, {required workingDirectory, required environment, required rows, required columns}) {
          envs.add(environment);
          return fail ? failingPty() : good = FakePty();
        },
        fallbackSpawner: (exe, {required workingDirectory, required environment, required rows, required columns}) {
          final pty = FakePty();
          local.add(pty);
          return pty;
        },
      );
      var notified = 0;
      backend.onStalledChanged = () => notified++;
      final seen = StringBuffer();
      backend.output.listen(seen.write);
      await backend.start(columns: 80, rows: 24);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(backend.failure, contains('退出码 255'));
      expect(notified, greaterThan(0), reason: '要通知终端页换成失败页');
      expect(backend.usingFallback, isFalse);
      expect(backend.label, 'Ubuntu');
      expect(seen.toString(), contains('Ubuntu 环境没能启动'));
      expect(seen.toString(), isNot(contains('已退回')));
      expect(env.runtime.logLines.join('\n'), contains('Permission denied'), reason: 'PRoot 的输出要进日志');

      // 再失败一次（到了“连续失败”的上限）：还是不退回本机
      await backend.retryCompat();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(envs.last['PROOT_NO_SECCOMP'], '1');
      expect(env.runtime.launchFailures, 2);
      expect(env.runtime.shouldUseLinux, isFalse);
      expect(backend.failure, isNotNull);
      expect(backend.usingFallback, isFalse);
      await backend.switchToLocal();
      expect(backend.usingFallback, isFalse, reason: '安卓上没有“先用本机 shell”这条路');
      expect(local, isEmpty, reason: '从头到尾没开过本机 shell');
      expect(env.runtime.logLines.join('\n'), isNot(contains('退回本机 shell')));

      // 重试成功：失败状态清掉，键盘输入进 Ubuntu
      fail = false;
      final before = envs.length;
      await backend.retry();
      expect(envs.length, before + 1);
      expect(backend.failure, isNull);
      good!.emit('root@localhost:/workspace# ');
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(env.runtime.launchFailures, 0);
      backend.write('ls\r');
      expect(String.fromCharCodes(good!.written), 'ls\r');
      await backend.close();
    });

    test('“重试”清掉失败计数、按默认模式再进；没点过兼容模式时不带 PROOT_NO_SECCOMP', () async {
      final envs = <Map<String, String>>[];
      final backend = LinuxShellBackend(
        runtime: env.runtime,
        projectDir: env.tmp.path,
        spawner: (exe, args, {required workingDirectory, required environment, required rows, required columns}) {
          envs.add(environment);
          return failingPty();
        },
      );
      backend.output.listen((_) {});
      await backend.start(columns: 80, rows: 24);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(env.runtime.compatPinned, isFalse);
      await backend.retry();
      expect(envs.last.containsKey('PROOT_NO_SECCOMP'), isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(env.runtime.launchFailures, 1, reason: '重试前清过零');
      await backend.close();
    });
  });

  group('Agent 的 run_command（安卓的规矩）', () {
    test('没装运行环境：命令没有执行，返回一条说清原因的结果；不退回本机 shell', () async {
      final env = await Env.create();
      addTearDown(env.dispose);
      final echoed = StringBuffer();
      final runner = LinuxCommandRunner(env.runtime, onOutput: echoed.write);
      final marker = File(p.join(env.tmp.path, 'ran.txt'));
      expect(runner.unavailableReason, contains('还没有安装'));
      expect(runner.description, contains('执行不了任何命令'));
      final result = await runner.run('echo hi > ran.txt', workingDirectory: env.tmp.path);
      expect(result.exitCode, kCommandNotRun);
      expect(result.output, contains('运行环境还没有安装'));
      expect(result.output, contains('命令没有执行'));
      expect(result.output, contains('安装运行环境'));
      expect(marker.existsSync(), isFalse, reason: '命令不能被本机 shell 偷偷执行');
      expect(echoed.toString(), contains('echo hi > ran.txt'));
      expect(echoed.toString(), contains('没有执行'));
    });

    test('正在安装 / 安装包缺文件：原因各说各的', () async {
      final env = await Env.create();
      addTearDown(env.dispose);
      env.runtime.phase = RuntimePhase.downloading;
      expect(LinuxCommandRunner(env.runtime).unavailableReason, contains('正在安装'));
      env.runtime.phase = RuntimePhase.notInstalled;
      final broken = await Env.create(installed: true, proot: false);
      addTearDown(broken.dispose);
      expect(LinuxCommandRunner(broken.runtime).unavailableReason, contains('缺少进入它要用的文件'));
    });

    test('工具层：环境不能用时不弹确认卡、不执行，把原因回给模型（算失败，不算用户拒绝）', () async {
      final env = await Env.create();
      addTearDown(env.dispose);
      final proj = Directory(p.join(env.tmp.path, 'proj'))..createSync();
      final asked = <ApprovalRequest>[];
      final toolbox = AgentToolbox(
        guard: PathGuard(proj.path),
        runner: LinuxCommandRunner(env.runtime),
        requestApproval: (r) async {
          asked.add(r);
          return true;
        },
        autoApprove: () => false,
      );
      final outcome = await toolbox.execute('run_command', {'command': 'echo hi > ran.txt'});
      expect(outcome.ok, isFalse);
      expect(outcome.denied, isFalse);
      expect(outcome.text, startsWith('命令没有执行：'));
      expect(outcome.text, contains('运行环境还没有安装'));
      expect(asked, isEmpty, reason: '反正执行不了，不让用户白点一次“允许”');
      expect(File(p.join(proj.path, 'ran.txt')).existsSync(), isFalse);
    });

    test('装了环境：进 Ubuntu 执行；连续启动失败以后也还是进 Ubuntu，不退回本机 sh', () async {
      final env = await Env.create(installed: true);
      addTearDown(env.dispose);
      final runner = LinuxCommandRunner(env.runtime);
      expect(runner.unavailableReason, isNull);
      env.runtime
        ..recordLaunchFailure('a')
        ..recordLaunchFailure('b');
      expect(runner.unavailableReason, isNull);
      expect(runner.description, contains('Ubuntu 24.04'));
      expect(runner.commandTimeout, const Duration(minutes: 5));
      if (Platform.isWindows) return; // 假的 libproot.so 是 POSIX 脚本
      final result = await runner.run('echo fallback', workingDirectory: env.tmp.path);
      // 假 PRoot 把收到的参数打印出来：能看到它，说明命令交给了 PRoot，而不是本机 sh 直接执行
      expect(result.output, contains('/bin/bash -lc echo fallback'));
      expect(result.output.trim(), isNot('fallback'));
    });

    test('装了但 PRoot 根本起不来：返回真实的启动错误，不退回本机 sh', () async {
      final env = await Env.create(installed: true);
      addTearDown(env.dispose);
      if (Platform.isWindows) return;
      File(p.join(env.host.nativeDir!, 'libproot.so')).deleteSync();
      Directory(p.join(env.host.nativeDir!, 'libproot.so')).createSync(); // 是个目录：启动必然失败
      final result = await LinuxCommandRunner(env.runtime).run('echo hi > ran.txt', workingDirectory: env.tmp.path);
      expect(result.exitCode, isNot(0));
      expect(result.output, contains('无法启动 Ubuntu 环境'));
      expect(File(p.join(env.tmp.path, 'ran.txt')).existsSync(), isFalse);
      expect(env.runtime.launchFailures, 1);
    });
  });

  group('非安卓平台：行为不变', () {
    late Env env;
    late ProjectSession session;
    setUp(() async {
      env = await Env.create(android: false);
      session = ProjectSession(env.services, await env.services.projects.create('我的小站', ProjectTemplate.web));
    });
    tearDown(() {
      session.dispose();
      env.dispose();
    });

    test('没装环境也一打开就有本机会话，可以再开本机 shell，只剩一个时关不掉', () {
      expect(session.terminals.single.title, '本机 1');
      expect(session.addTerminal(forceLocal: true)!.title, '本机 2');
      session.closeTerminal(1);
      session.closeTerminal(0);
      expect(session.terminals.single.title, '本机 1');
    });

    test('run_command 没装环境时照旧用本机 shell 执行', () async {
      final runner = LinuxCommandRunner(env.runtime);
      expect(runner.unavailableReason, isNull);
      if (Platform.isWindows) return;
      final result = await runner.run('echo desktop', workingDirectory: env.tmp.path);
      expect(result.exitCode, 0);
      expect(result.output.trim(), 'desktop');
    });

    test('装好环境不会被自动多开一个会话（那是安卓上安装引导的事）', () async {
      markInstalled(env.runtime);
      await env.runtime.init();
      expect(session.terminals.single.title, '本机 1');
    });
  });

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    final suffix = mode == ThemeMode.light ? 'light' : 'dark';

    Future<(Env, Project, ProjectSession, List<FakePty>, List<Map<String, String>>)> boot(
      WidgetTester tester, {
      bool android = true,
      bool installed = false,
      bool proot = true,
      int? free,
      FakePty Function()? pty,
    }) async {
      usePhoneViewport(tester);
      final env = (await tester.runAsync(
        () => free == null ? Env.create(android: android, installed: installed, proot: proot) : Env.create(android: android, installed: installed, proot: proot, free: free),
      ))!;
      addTearDown(() => env.tmp.deleteSync(recursive: true));
      final project = (await tester.runAsync(() => env.services.projects.create('我的小站', ProjectTemplate.web)))!;
      final ptys = <FakePty>[];
      final envs = <Map<String, String>>[];
      late ProjectSession session;
      await tester.runAsync(() async {
        session = ProjectSession(env.services, project);
        await session.loadChat();
        session.linuxPtySpawner = (exe, args, {required workingDirectory, required environment, required rows, required columns}) {
          final made = (pty ?? FakePty.new)();
          ptys.add(made);
          envs.add(environment);
          return made;
        };
      });
      // 已装环境时第一个会话在注入假伪终端之前就建好了：换一个用假伪终端的（标题因此是 Ubuntu 2）
      if (installed && android) {
        session.addTerminal();
        session.closeTerminal(0);
      }
      return (env, project, session, ptys, envs);
    }

    Future<void> close(WidgetTester tester, ProjectSession session) async {
      await tester.runAsync(() async => session.dispose());
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('终端 · 没装运行环境：整页是安装引导，没有本机终端、没有按键行 ($suffix)', (tester) async {
      final (env, project, session, _, _) = await boot(tester);
      await tester.pumpWidget(env.app(ProjectShell(project: project, session: session, initial: ShellDest.terminal), mode));
      await settle(tester);
      expect(find.byKey(const Key('terminal-setup')), findsOneWidget);
      expect(find.text('先装运行环境，终端才能用'), findsOneWidget);
      expect(find.textContaining('没有 git、node、python'), findsOneWidget);
      expect(find.textContaining('需要下载 28.5 MB'), findsOneWidget, reason: '大小用现有数据');
      expect(find.textContaining('手机现在剩余 23.0 GB'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '安装运行环境'), findsOneWidget);
      expect(find.byKey(const Key('terminal-setup-ssh')), findsOneWidget);
      expect(find.textContaining('本机'), findsNothing);
      expect(find.byKey(const Key('terminal-keys')), findsNothing);
      expect(find.byTooltip('新建会话'), findsNothing);
      expect(session.terminals, isEmpty);
      await shot(tester, '60-terminal-setup-$suffix');

      // 次要出路：连 SSH
      await tester.tap(find.byKey(const Key('terminal-setup-ssh')));
      await tester.pumpAndSettle();
      expect(find.byType(SshConnectScreen), findsOneWidget);
      await close(tester, session);
    });

    testWidgets('终端 · 安装中：本页显示进度，能取消 ($suffix)', (tester) async {
      final (env, project, session, _, _) = await boot(tester);
      env.runtime
        ..phase = RuntimePhase.downloading
        ..progressDone = 12 * 1024 * 1024
        ..progressTotal = env.runtime.image.size;
      await tester.pumpWidget(env.app(ProjectShell(project: project, session: session, initial: ShellDest.terminal), mode));
      await settle(tester);
      expect(find.text('正在安装运行环境'), findsOneWidget);
      expect(find.text('已下载 12.0 MB / 28.5 MB'), findsOneWidget);
      expect(find.byKey(const Key('terminal-setup-cancel')), findsOneWidget);
      expect(find.byKey(const Key('terminal-setup-install')), findsNothing);
      expect(find.byKey(const Key('terminal-setup-ssh')), findsOneWidget, reason: '等的时候也能先连 SSH');
      await shot(tester, '61-terminal-setup-installing-$suffix');

      env.runtime
        ..phase = RuntimePhase.extracting
        ..log('解压');
      await tester.pump();
      expect(find.textContaining('解压中，不要退出应用'), findsOneWidget);
      env.runtime.phase = RuntimePhase.notInstalled;
      await close(tester, session);
    });

    testWidgets('终端 · 点安装失败：真实原因显示在本页，可以再点；下到一半的写“继续下载” ($suffix)', (tester) async {
      // 剩余空间不够：安装在联网之前就失败（这里的客户端一联网就报错）
      final (env, project, session, _, _) = await boot(tester, free: 50 * 1024 * 1024);
      await tester.pumpWidget(env.app(ProjectShell(project: project, session: session, initial: ShellDest.terminal), mode));
      await settle(tester);
      expect(find.byKey(const Key('terminal-setup-error')), findsNothing);
      await tester.tap(find.byKey(const Key('terminal-setup-install')));
      await settle(tester);
      expect(find.byKey(const Key('terminal-setup-error')), findsOneWidget);
      expect(find.textContaining('手机剩余空间不够'), findsOneWidget);
      expect(find.textContaining('现在只剩 50.0 MB'), findsWidgets);
      expect(find.byKey(const Key('terminal-setup-install')), findsOneWidget, reason: '失败后还能再点');
      expect(find.byKey(const Key('terminal-setup-sources')), findsOneWidget);
      expect(session.terminals, isEmpty);

      // 下载中断留下了半个文件：按钮如实写能接着下
      await tester.runAsync(() async {
        Directory(p.join(env.runtime.baseDir, 'download')).createSync(recursive: true);
        File(p.join(env.runtime.baseDir, 'download', '${env.runtime.image.fileName}.part')).writeAsBytesSync(List.filled(5 * 1024 * 1024, 0));
      });
      env.runtime
        ..installError = '下载中断：Connection reset by peer。已下载的部分留着，重试会接着下'
        ..log('中断');
      await tester.pump();
      expect(find.text('继续下载（已有 5.0 MB）'), findsOneWidget);
      await shot(tester, '62-terminal-setup-failed-$suffix');

      await tester.tap(find.byKey(const Key('terminal-setup-sources')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('rootfs-source')), findsOneWidget, reason: '换下载源在“运行环境”页');
      await close(tester, session);
    });

    testWidgets('终端 · 装好的那一下：引导消失，自动进 Ubuntu 终端 ($suffix)', (tester) async {
      final (env, project, session, ptys, _) = await boot(tester);
      await tester.pumpWidget(env.app(ProjectShell(project: project, session: session, initial: ShellDest.terminal), mode));
      await settle(tester);
      expect(find.byKey(const Key('terminal-setup')), findsOneWidget);
      await tester.runAsync(() async {
        markInstalled(env.runtime);
        await env.runtime.init();
      });
      await settle(tester);
      expect(find.byKey(const Key('terminal-setup')), findsNothing);
      expect(find.text('Ubuntu 1'), findsOneWidget);
      expect(find.byKey(const Key('terminal-keys')), findsOneWidget);
      expect(ptys, hasLength(1), reason: 'Ubuntu 的 shell 已经自动启动');
      ptys.single.emit('root@localhost:/workspace# ');
      await settle(tester);
      expect(session.terminals.single.text, contains('root@localhost:/workspace#'));

      // 新建会话里没有“本机 shell”
      await tester.tap(find.byTooltip('新建会话'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('new-linux-session')), findsOneWidget);
      expect(find.byKey(const Key('new-ssh-session')), findsOneWidget);
      expect(find.byKey(const Key('new-local-session')), findsNothing);
      expect(find.text('本机 shell'), findsNothing);
      await close(tester, session);
    });

    testWidgets('终端 · 安装包缺 PRoot：说明进不去，不给安装按钮，SSH 还在 ($suffix)', (tester) async {
      final (env, project, session, _, _) = await boot(tester, proot: false);
      await tester.pumpWidget(env.app(ProjectShell(project: project, session: session, initial: ShellDest.terminal), mode));
      await settle(tester);
      expect(find.byKey(const Key('terminal-setup-no-proot')), findsOneWidget);
      expect(find.byKey(const Key('terminal-setup-install')), findsNothing);
      expect(find.byKey(const Key('terminal-setup-ssh')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await close(tester, session);
    });

    testWidgets('终端 · 没装环境但连着 SSH：会话能关到一个不剩；新建里有“安装运行环境”，没有本机 shell ($suffix)', (tester) async {
      final (env, project, session, _, _) = await boot(tester);
      session.addSshTerminal(const SshConfig(host: '127.0.0.1', port: 1, user: 'me'));
      await tester.pumpWidget(env.app(ProjectShell(project: project, session: session, initial: ShellDest.terminal), mode));
      await tester.pump();
      expect(find.byKey(const Key('terminal-setup')), findsNothing);
      expect(find.text('SSH 1'), findsOneWidget);
      await tester.tap(find.byTooltip('新建会话'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('new-session-install-runtime')), findsOneWidget);
      expect(find.byKey(const Key('new-local-session')), findsNothing);
      expect(find.byKey(const Key('new-linux-session')), findsNothing);
      await tester.tapAt(const Offset(195, 80));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('关闭会话'));
      await tester.pump();
      expect(find.byKey(const Key('terminal-setup')), findsOneWidget);
      await close(tester, session);
    });

    testWidgets('终端 · Ubuntu 启动失败：显示原因和四条出路，不退回本机 shell；重试成功后回到终端 ($suffix)', (tester) async {
      var fail = true;
      final (env, project, session, ptys, envs) = await boot(tester, installed: true, pty: () => fail ? failingPty() : FakePty());
      expect(session.terminals.single.title, 'Ubuntu 2');
      await tester.pumpWidget(env.app(ProjectShell(project: project, session: session, initial: ShellDest.terminal), mode));
      await settle(tester);
      await tester.pump(const Duration(milliseconds: 300));
      await settle(tester, rounds: 2);
      expect(find.byKey(const Key('terminal-failure')), findsOneWidget);
      expect(find.text('Ubuntu 没能启动'), findsOneWidget);
      expect(find.textContaining('退出码 255'), findsOneWidget, reason: '真实原因');
      expect(find.widgetWithText(FilledButton, '重试'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, '用兼容模式重试'), findsOneWidget);
      expect(find.widgetWithText(TextButton, '一键诊断'), findsOneWidget);
      expect(find.widgetWithText(TextButton, '连接 SSH'), findsOneWidget);
      expect(find.text('Ubuntu 2'), findsOneWidget, reason: '会话标签还在');
      expect(find.textContaining('本机'), findsNothing);
      expect(find.byKey(const Key('terminal-keys')), findsNothing);
      expect(session.terminals.single.backend.label, 'Ubuntu');
      await shot(tester, '63-terminal-launch-failed-$suffix');

      // 兼容模式重试：还是失败，仍然留在失败页；这时“重试”就是兼容模式，不再单独给按钮
      await tester.tap(find.byKey(const Key('terminal-failure-compat')));
      await tester.pump(const Duration(milliseconds: 300));
      await settle(tester, rounds: 2);
      expect(envs.last['PROOT_NO_SECCOMP'], '1');
      expect(find.byKey(const Key('terminal-failure')), findsOneWidget);
      expect(find.byKey(const Key('terminal-failure-compat')), findsNothing);
      expect(find.textContaining('已经是兼容模式'), findsOneWidget);
      expect((session.terminals.single.backend as LinuxShellBackend).usingFallback, isFalse);

      // 连接 SSH
      await tester.tap(find.byKey(const Key('terminal-failure-ssh')));
      await tester.pumpAndSettle();
      expect(find.byType(SshConnectScreen), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      // 重试成功
      fail = false;
      final before = ptys.length;
      await tester.tap(find.byKey(const Key('terminal-failure-retry')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(ptys.length, before + 1);
      expect(find.byKey(const Key('terminal-failure')), findsNothing);
      expect(find.byKey(const Key('terminal-keys')), findsOneWidget);
      ptys.last.emit('root@localhost:/workspace# ');
      await settle(tester);
      expect(session.terminals.single.text, contains('root@localhost:/workspace#'));
      await tester.pump(const Duration(seconds: 4));
      await close(tester, session);
    });

    testWidgets('终端 · 启动失败后一键诊断：就在本页跑，跑完列出结论，完整报告去“运行环境”页 ($suffix)', (tester) async {
      final (env, project, session, _, _) = await boot(tester, installed: true, pty: failingPty);
      final runtime = env.runtime;
      File(p.join(runtime.rootfsDir, 'usr/bin/env')).writeAsStringSync('x');
      File(p.join(runtime.rootfsDir, 'usr/bin/bash')).writeAsStringSync('x');
      runtime.diagnostics = RuntimeDiagnostics(
        runtime,
        commandTimeout: const Duration(milliseconds: 200),
        ptyTimeout: const Duration(milliseconds: 400),
        localShell: '/bin/sh',
        runProcess: (exe, args, {environment, required timeout}) async {
          if (!exe.endsWith('libproot.so')) return const DiagRun(exitCode: 0, stdout: 'Linux localhost 6.6.30-android15 aarch64', stderr: '', elapsed: Duration(milliseconds: 3));
          if (args.contains('--version')) return const DiagRun(exitCode: 0, stdout: 'proot 5.1.107', stderr: '', elapsed: Duration(milliseconds: 12));
          if (!(environment ?? const {}).containsKey('PROOT_NO_SECCOMP')) return DiagRun(exitCode: null, stdout: '', stderr: '', elapsed: timeout, timedOut: true);
          return const DiagRun(exitCode: 0, stdout: 'ok', stderr: '', elapsed: Duration(milliseconds: 180));
        },
        ptySpawner: (exe, {required workingDirectory, required environment, required rows, required columns}) => FakePty()..exit(0),
        ptyArgsSpawner: (exe, args, {required workingDirectory, required environment, required rows, required columns}) => FakePty()
          ..emit('lopi-pty-ok\r\n')
          ..exit(0),
      );
      await tester.pumpWidget(env.app(ProjectShell(project: project, session: session, initial: ShellDest.terminal), mode));
      await settle(tester);
      await tester.pump(const Duration(milliseconds: 300));
      await settle(tester, rounds: 2);
      expect(find.byKey(const Key('terminal-failure-diagnose')), findsOneWidget);
      // 诊断里是真实的等待（超时、伪终端），放到真实时间里跑；按钮点下去走的是同一个入口
      final running = tester.runAsync(() => runtime.diagnostics.run(projectDir: project.dir));
      await tester.pump();
      await running;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('诊断结论'), findsOneWidget);
      expect(find.text('重新诊断'), findsOneWidget);
      expect(find.byKey(const Key('terminal-failure-report')), findsOneWidget);
      await shot(tester, '64-terminal-launch-failed-diagnosed-$suffix');
      await tester.ensureVisible(find.byKey(const Key('terminal-failure-report')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('terminal-failure-report')));
      await tester.pumpAndSettle();
      expect(find.byType(RuntimeScreen), findsOneWidget, reason: '跳到了“运行环境”页');
      expect(find.byKey(const Key('diag-report')), findsOneWidget);
      await close(tester, session);
    });

    testWidgets('终端 · Ubuntu 没有响应：第二条出路是“连接 SSH”，没有“先用本机 shell” ($suffix)', (tester) async {
      final (env, project, session, _, _) = await boot(tester, installed: true);
      await tester.pumpWidget(env.app(ProjectShell(project: project, session: session, initial: ShellDest.terminal), mode));
      await settle(tester);
      await tester.pump(const Duration(seconds: 9));
      await tester.pump();
      expect(find.byKey(const Key('terminal-stalled')), findsOneWidget);
      expect(find.byKey(const Key('stalled-use-ssh')), findsOneWidget);
      expect(find.byKey(const Key('stalled-use-local')), findsNothing);
      expect(find.text('先用本机 shell'), findsNothing);
      expect(session.terminals.single.text, contains('改连 SSH 远程主机'));
      await tester.tap(find.byKey(const Key('stalled-use-ssh')));
      await tester.pumpAndSettle();
      expect(find.byType(SshConnectScreen), findsOneWidget);
      await close(tester, session);
    });

    testWidgets('非安卓平台：终端页照旧是本机终端，新建里还有“本机 shell” ($suffix)', (tester) async {
      final (env, project, session, _, _) = await boot(tester, android: false);
      // 不真的起本机 shell 进程
      session.ptySpawner = (exe, {required workingDirectory, required environment, required rows, required columns}) => FakePty();
      final fresh = session.addTerminal()!;
      expect(fresh.title, '本机 2');
      await tester.pumpWidget(env.app(ProjectShell(project: project, session: session, initial: ShellDest.terminal), mode));
      await settle(tester);
      expect(find.byKey(const Key('terminal-setup')), findsNothing);
      expect(find.text('本机 2'), findsOneWidget);
      expect(find.byKey(const Key('terminal-keys')), findsOneWidget);
      await tester.tap(find.byTooltip('新建会话'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('new-local-session')), findsOneWidget);
      expect(find.byKey(const Key('new-session-install-runtime')), findsNothing);
      await tester.tap(find.byKey(const Key('new-local-session')));
      await tester.pumpAndSettle();
      expect(session.terminals.last.title, '本机 3');
      await close(tester, session);
    });
  }
}
