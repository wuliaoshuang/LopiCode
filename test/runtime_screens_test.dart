// “运行环境”页和 Ubuntu 终端在 390×844 上的渲染与交互检查（浅色 + 深色）。
// LOPI_SHOTS=1 时把截图写到 docs/screenshots/。
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/app.dart';
import 'package:lopicode/app_services.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/stores.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/runtime/linux_runtime.dart';
import 'package:lopicode/runtime/runtime_screen.dart';
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

class Env {
  Env(this.tmp, this.services, this.host);
  final Directory tmp;
  final AppServices services;
  final FakeRuntimeHost host;
  LinuxRuntime get runtime => services.runtime;

  static Future<Env> create({bool proot = true, bool installed = false}) async {
    final tmp = Directory.systemTemp.createTempSync('lopi_rtui_');
    final settings = SettingsStore(File(p.join(tmp.path, 'settings.json')));
    final host = FakeRuntimeHost(nativeDir: proot ? makeFakeNativeDir(tmp) : tmp.path, free: 23 * 1024 * 1024 * 1024);
    final runtime = LinuxRuntime(settings: settings, baseDir: p.join(tmp.path, 'runtime'), host: host);
    if (installed) markInstalled(runtime);
    await runtime.init();
    return Env(
      tmp,
      AppServices(settings: settings, secrets: MemorySecretStore(), projects: ProjectStore(p.join(tmp.path, 'projects')), runtime: runtime),
      host,
    );
  }

  Widget app(Widget home, ThemeMode mode) => RepaintBoundary(
    key: shotKey,
    child: LopiCodeApp(services: services, home: home, fontFamily: kTestFont, forceThemeMode: mode),
  );
}

Widget inShell(Widget child) => ShellScope(openDrawer: () {}, go: (_) {}, projectName: '我的小站', child: child);

void main() {
  setUpAll(() async => fontsLoaded = await loadRealFonts());

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    final suffix = mode == ThemeMode.light ? 'light' : 'dark';

    testWidgets('运行环境 · 未安装：说明要多大空间，有安装按钮和下载源 ($suffix)', (tester) async {
      usePhoneViewport(tester);
      final env = await tester.runAsync(Env.create);
      addTearDown(() => env!.tmp.deleteSync(recursive: true));
      await tester.pumpWidget(env!.app(inShell(const RuntimeScreen()), mode));
      await tester.pump();
      expect(find.byKey(const Key('runtime-install')), findsOneWidget);
      expect(find.textContaining('需要下载 28.5 MB'), findsOneWidget);
      expect(find.textContaining('手机现在剩余 23.0 GB'), findsOneWidget);
      expect(find.text('清华大学镜像'), findsNWidgets(2));
      expect(find.text('常用运行时'), findsNothing, reason: '没装环境时不显示运行时');
      expect(find.byKey(const Key('runtime-uninstall')), findsNothing);
      await shot(tester, '22-runtime-not-installed-$suffix');
    });

    testWidgets('运行环境 · 下载中：进度条、已下载多少、能取消 ($suffix)', (tester) async {
      usePhoneViewport(tester);
      final env = await tester.runAsync(Env.create);
      addTearDown(() => env!.tmp.deleteSync(recursive: true));
      env!.runtime
        ..phase = RuntimePhase.downloading
        ..progressDone = 12 * 1024 * 1024
        ..progressTotal = env.runtime.image.size;
      await tester.pumpWidget(env.app(inShell(const RuntimeScreen()), mode));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('已下载 12.0 MB / 28.5 MB'), findsOneWidget);
      expect(find.byKey(const Key('runtime-cancel')), findsOneWidget);
      expect(find.byKey(const Key('runtime-install')), findsNothing);
      await shot(tester, '23-runtime-downloading-$suffix');
      env.runtime.phase = RuntimePhase.notInstalled;
    });

    testWidgets('运行环境 · 安装失败：原因如实显示，可以接着下 ($suffix)', (tester) async {
      usePhoneViewport(tester);
      final env = await tester.runAsync(Env.create);
      addTearDown(() => env!.tmp.deleteSync(recursive: true));
      Directory(p.join(env!.runtime.baseDir, 'download')).createSync(recursive: true);
      File(p.join(env.runtime.baseDir, 'download', '${env.runtime.image.fileName}.part')).writeAsBytesSync(List.filled(5 * 1024 * 1024, 0));
      env.runtime.installError = '下载中断：Connection reset by peer。已下载的部分留着，重试会接着下';
      await tester.pumpWidget(env.app(inShell(const RuntimeScreen()), mode));
      await tester.pump();
      expect(find.byKey(const Key('runtime-install-error')), findsOneWidget);
      expect(find.text('继续下载（已有 5.0 MB）'), findsOneWidget);
      expect(find.text('删除没下完的文件'), findsOneWidget);
      await shot(tester, '24-runtime-install-failed-$suffix');
    });

    testWidgets('运行环境 · 已安装：常用运行时按需装，已装的标出来，有卸载 ($suffix)', (tester) async {
      usePhoneViewport(tester);
      final env = await tester.runAsync(() => Env.create(installed: true));
      addTearDown(() => env!.tmp.deleteSync(recursive: true));
      File(p.join(env!.runtime.rootfsDir, 'usr/bin/python3')).writeAsStringSync('x');
      await tester.pumpWidget(env.app(inShell(const RuntimeScreen()), mode));
      await tester.pump();
      expect(find.text('已安装，新开的终端会直接进 Ubuntu'), findsOneWidget);
      expect(find.byKey(const Key('pack-node-install')), findsOneWidget);
      expect(find.byKey(const Key('pack-python-installed')), findsOneWidget);
      expect(find.byKey(const Key('pack-git-install')), findsOneWidget);
      expect(find.byKey(const Key('runtime-install')), findsNothing);
      await shot(tester, '25-runtime-installed-$suffix');

      // 卸载要先确认
      await tester.scrollUntilVisible(find.byKey(const Key('runtime-uninstall')), 200, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.byKey(const Key('runtime-uninstall')));
      await tester.pumpAndSettle();
      expect(find.text('卸载运行环境？'), findsOneWidget);
      await shot(tester, '25b-runtime-uninstall-confirm-$suffix');
      await tester.tap(find.byKey(const Key('runtime-uninstall-confirm')));
      await tester.pumpAndSettle();
      await settle(tester); // 删目录是真实的文件操作
      expect(env.runtime.installed, isFalse);
      expect(Directory(env.runtime.baseDir).existsSync(), isFalse);
    });

    testWidgets('运行环境 · 连续启动失败：说明原因、能看日志、能重新尝试 ($suffix)', (tester) async {
      usePhoneViewport(tester);
      final env = await tester.runAsync(() => Env.create(installed: true));
      addTearDown(() => env!.tmp.deleteSync(recursive: true));
      env!.runtime
        ..recordLaunchFailure('PRoot 刚启动就退出了（退出码 255）', output: 'proot error: execve("/usr/bin/env"): Permission denied')
        ..recordLaunchFailure('PRoot 刚启动就退出了（退出码 255）', output: 'proot error: execve("/usr/bin/env"): Permission denied');
      await tester.pumpWidget(env.app(inShell(const RuntimeScreen()), mode));
      await tester.pump();
      expect(find.text('启动失败，已退回本机 shell'), findsOneWidget);
      expect(find.byKey(const Key('runtime-log')), findsOneWidget);
      expect(find.textContaining('Permission denied'), findsOneWidget);
      await shot(tester, '26-runtime-launch-failed-$suffix');
      await tester.tap(find.byKey(const Key('runtime-retry-launch')));
      await tester.pump();
      expect(env.runtime.shouldUseLinux, isTrue);
      expect(find.text('已安装，新开的终端会直接进 Ubuntu'), findsOneWidget);
    });

    testWidgets('运行环境 · 安装包没带 PRoot：如实说明，不给安装按钮 ($suffix)', (tester) async {
      usePhoneViewport(tester);
      final env = await tester.runAsync(() => Env.create(proot: false));
      addTearDown(() => env!.tmp.deleteSync(recursive: true));
      await tester.pumpWidget(env!.app(inShell(const RuntimeScreen()), mode));
      await tester.pump();
      expect(find.byKey(const Key('runtime-no-proot')), findsOneWidget);
      expect(find.byKey(const Key('runtime-install')), findsNothing);
      await shot(tester, '27-runtime-no-proot-$suffix');
    });

    testWidgets('终端：环境可用时新会话是 Ubuntu；侧边栏有“运行环境”入口 ($suffix)', (tester) async {
      usePhoneViewport(tester);
      final env = await tester.runAsync(() => Env.create(installed: true));
      addTearDown(() => env!.tmp.deleteSync(recursive: true));
      final project = await tester.runAsync(() => env!.services.projects.create('我的小站', ProjectTemplate.web));
      final ptys = <FakePty>[];
      late ProjectSession session;
      await tester.runAsync(() async {
        session = ProjectSession(env!.services, project!);
        // 构造时已经开了第一个会话：它应该是 Ubuntu
        expect(session.terminals.single.title, 'Ubuntu 1');
        session.linuxPtySpawner = (exe, args, {required workingDirectory, required environment, required rows, required columns}) {
          final pty = FakePty();
          ptys.add(pty);
          return pty;
        };
      });
      // 第一个会话在注入假伪终端之前就建好了，换一个新的来渲染
      final fresh = session.addTerminal();
      expect(fresh.title, 'Ubuntu 2');
      await tester.pumpWidget(env!.app(ProjectShell(project: project!, session: session, initial: ShellDest.terminal), mode));
      await settle(tester);
      expect(ptys, isNotEmpty);
      ptys.last.emit('root@localhost:/workspace# node -v\r\nv24.9.0\r\nroot@localhost:/workspace# ');
      await settle(tester);
      expect(fresh.text, contains('Ubuntu 24.04'));
      expect(fresh.text, contains('v24.9.0'));
      expect(env.host.keepAlive, isTrue, reason: 'Ubuntu 会话开着时要挂保活');
      await shot(tester, '28-terminal-ubuntu-$suffix');

      // 强制开本机 shell 仍然可以
      final local = session.addTerminal(forceLocal: true);
      expect(local.title, startsWith('本机'));

      await tester.tap(find.byTooltip('打开侧边栏'));
      await tester.pumpAndSettle();
      expect(find.text('运行环境'), findsOneWidget);
      await shot(tester, '29-drawer-runtime-$suffix');
      await tester.tap(find.text('运行环境'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('runtime-status')), findsOneWidget);
      await tester.runAsync(() async => session.dispose());
    });
  }
}
