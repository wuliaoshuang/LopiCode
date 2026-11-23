// “运行环境”页和 Ubuntu 终端在 390×844 上的渲染与交互检查（浅色 + 深色）。
// LOPI_SHOTS=1 时把截图写到 docs/screenshots/。
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/app.dart';
import 'package:lopicode/app_services.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/stores.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/runtime/linux_runtime.dart';
import 'package:lopicode/runtime/runtime_diagnostics.dart';
import 'package:lopicode/runtime/runtime_screen.dart';
import 'package:lopicode/ui/project_shell.dart';
import 'package:lopicode/ui/settings_screen.dart';
import 'package:lopicode/ui/third_party_screen.dart';
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
      await tester.ensureVisible(find.byKey(const Key('runtime-uninstall')));
      await tester.pump();
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
      expect(find.byKey(const Key('runtime-diagnose')), findsOneWidget, reason: '启动失败时一键诊断要在第一屏');
      await shot(tester, '26a-runtime-launch-failed-top-$suffix');
      await tester.scrollUntilVisible(find.byKey(const Key('runtime-log')), 200, scrollable: find.byType(Scrollable).first);
      await tester.pump();
      expect(find.byKey(const Key('runtime-log')), findsOneWidget);
      expect(find.textContaining('Permission denied'), findsOneWidget);
      await shot(tester, '26-runtime-launch-failed-$suffix');
      tester.state<ScrollableState>(find.byType(Scrollable).first).position.jumpTo(0); // 回到顶上
      await tester.pump();
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

    testWidgets('设置 › 第三方声明：三个组件、许可证全文、来源和校验值 ($suffix)', (tester) async {
      usePhoneViewport(tester);
      final env = await tester.runAsync(Env.create);
      addTearDown(() => env!.tmp.deleteSync(recursive: true));
      await tester.pumpWidget(env!.app(const SettingsScreen(), mode));
      await tester.pump();
      await tester.scrollUntilVisible(find.byKey(const Key('settings-third-party')), 200, scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      await shot(tester, '30-settings-third-party-entry-$suffix');
      await tester.tap(find.byKey(const Key('settings-third-party')));
      await tester.pumpAndSettle();
      expect(find.text('第三方声明'), findsOneWidget);
      expect(find.text('PRoot（Termux 版） 5.1.107.102'), findsOneWidget);
      expect(find.text('许可证：GPL-2.0-or-later'), findsOneWidget);
      await shot(tester, '31-third-party-$suffix');

      // 展开 PRoot 的来源：能看到包地址、校验值、源码地址
      await tester.tap(find.byKey(const Key('source-PRoot（Termux 版）')));
      await tester.pumpAndSettle();
      expect(find.textContaining('packages.termux.dev/apt/termux-main/pool/main/p/proot/proot_5.1.107.102_aarch64.deb'), findsOneWidget);
      expect(find.text('10a394b585c2fc2b2c8502544f4e5f1be581dc8bfff79e8ba62f16207423e030'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('https://github.com/termux/proot/archive/v5.1.107.102.zip'), 200, scrollable: find.descendant(of: find.byKey(const Key('third-party-list')), matching: find.byType(Scrollable)).first);
      await tester.pumpAndSettle();
      await shot(tester, '31b-third-party-source-$suffix');

      // 另外两个组件和“怎么拿到源码”都在
      final list = find.descendant(of: find.byKey(const Key('third-party-list')), matching: find.byType(Scrollable)).first;
      await tester.scrollUntilVisible(find.text('talloc 2.5.0'), 200, scrollable: list);
      expect(find.text('许可证：LGPL-3.0-or-later'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('libandroid-shmem 0.7'), 200, scrollable: list);
      await tester.scrollUntilVisible(find.byKey(const Key('third-party-source-offer')), 200, scrollable: list);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('许可证全文页：GPL-2.0 原文能读出来 ($suffix)', (tester) async {
      usePhoneViewport(tester);
      final env = await tester.runAsync(Env.create);
      addTearDown(() => env!.tmp.deleteSync(recursive: true));
      final text = File('assets/licenses/GPL-2.0.txt').readAsStringSync();
      await tester.pumpWidget(env!.app(LicenseTextScreen(asset: 'assets/licenses/GPL-2.0.txt', bundle: _FixedBundle(text)), mode));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('license-text')), findsOneWidget);
      expect(find.textContaining('GNU GENERAL PUBLIC LICENSE'), findsOneWidget);
      expect(find.textContaining('END OF TERMS AND CONDITIONS'), findsOneWidget);
      await shot(tester, '32-license-text-$suffix');
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

    testWidgets('终端 · Ubuntu 没有响应：出提示条，三个出路；兼容模式重试后能用 ($suffix)', (tester) async {
      usePhoneViewport(tester);
      final env = await tester.runAsync(() => Env.create(installed: true));
      addTearDown(() => env!.tmp.deleteSync(recursive: true));
      final project = await tester.runAsync(() => env!.services.projects.create('我的小站', ProjectTemplate.web));
      final ptys = <FakePty>[];
      final envs = <Map<String, String>>[];
      late ProjectSession session;
      await tester.runAsync(() async {
        session = ProjectSession(env!.services, project!);
        session.linuxPtySpawner = (exe, args, {required workingDirectory, required environment, required rows, required columns}) {
          final pty = FakePty();
          ptys.add(pty);
          envs.add(environment);
          return pty;
        };
      });
      final fresh = session.addTerminal();
      await tester.pumpWidget(env!.app(ProjectShell(project: project!, session: session, initial: ShellDest.terminal), mode));
      await settle(tester);
      expect(find.byKey(const Key('terminal-stalled')), findsNothing);
      // 假伪终端一个字都不输出，等过 8 秒
      await tester.pump(const Duration(seconds: 9));
      await tester.pump();
      expect(find.byKey(const Key('terminal-stalled')), findsOneWidget);
      expect(find.text('Ubuntu 没有响应'), findsOneWidget);
      expect(find.text('改用兼容模式重试'), findsOneWidget);
      expect(find.text('先用本机 shell'), findsOneWidget);
      expect(find.text('去做一键诊断'), findsOneWidget);
      expect(fresh.text, contains('还没有任何响应'));
      await shot(tester, '33-terminal-stalled-$suffix');

      await tester.tap(find.byKey(const Key('stalled-retry-compat')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const Key('terminal-stalled')), findsNothing);
      expect(ptys.length, greaterThanOrEqualTo(2));
      expect(envs.last['PROOT_NO_SECCOMP'], '1');
      ptys.last.emit('root@localhost:/workspace# ');
      await tester.pump(const Duration(seconds: 4));
      expect(env.services.settings.getBool(SettingKeys.runtimeCompat), isTrue);

      // 点屏幕弹键盘，打的字进这个会话
      await tester.tapAt(const Offset(195, 300));
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.testTextInput.isVisible, isTrue);
      tester.testTextInput.updateEditingValue(const TextEditingValue(text: '  ls', selection: TextSelection.collapsed(offset: 4)));
      await tester.pump();
      expect(utf8.decode(ptys.last.written), 'ls');
      // 键盘行的按键也写进同一个会话
      await tester.tap(find.text('Tab'));
      await tester.pump();
      expect(utf8.decode(ptys.last.written), 'ls\t');
      ptys.last.emit('ls');
      await tester.pump();
      await shot(tester, '34-terminal-typing-$suffix');

      // “中文”点亮后：拼音画在光标后面
      await tester.dragUntilVisible(find.text('中文'), find.byType(ListView).last, const Offset(-120, 0));
      await tester.tap(find.text('中文'));
      await tester.pump(const Duration(milliseconds: 400));
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(text: '  nihao', selection: TextSelection.collapsed(offset: 7), composing: TextRange(start: 2, end: 7)),
      );
      await tester.pump();
      expect(find.byKey(const Key('terminal-composing')), findsOneWidget);
      expect(utf8.decode(ptys.last.written), 'ls\t', reason: '拼音没选字前不写入');
      await shot(tester, '35-terminal-composing-$suffix');
      await tester.runAsync(() async => session.dispose());
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('终端 · 没有响应时去诊断：跳到“运行环境”页 ($suffix)', (tester) async {
      usePhoneViewport(tester);
      final env = await tester.runAsync(() => Env.create(installed: true));
      addTearDown(() => env!.tmp.deleteSync(recursive: true));
      final project = await tester.runAsync(() => env!.services.projects.create('我的小站', ProjectTemplate.web));
      late ProjectSession session;
      await tester.runAsync(() async {
        session = ProjectSession(env!.services, project!);
        session.linuxPtySpawner = (exe, args, {required workingDirectory, required environment, required rows, required columns}) => FakePty();
      });
      session.addTerminal();
      await tester.pumpWidget(env!.app(ProjectShell(project: project!, session: session, initial: ShellDest.terminal), mode));
      await settle(tester);
      await tester.pump(const Duration(seconds: 9));
      await tester.pump();
      await tester.tap(find.byKey(const Key('stalled-diagnose')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('runtime-diagnose')), findsOneWidget);
      await tester.runAsync(() async => session.dispose());
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('运行环境 · 一键诊断：跑完有结论、完整报告、能复制 ($suffix)', (tester) async {
      usePhoneViewport(tester);
      final env = await tester.runAsync(() => Env.create(installed: true));
      addTearDown(() => env!.tmp.deleteSync(recursive: true));
      final runtime = env!.runtime;
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
          if (!(environment ?? const {}).containsKey('PROOT_NO_SECCOMP')) {
            return DiagRun(exitCode: null, stdout: '', stderr: '', elapsed: timeout, timedOut: true);
          }
          return const DiagRun(exitCode: 0, stdout: 'ok', stderr: '', elapsed: Duration(milliseconds: 180));
        },
        ptySpawner: (exe, {required workingDirectory, required environment, required rows, required columns}) => _EchoPty(),
        ptyArgsSpawner: (exe, args, {required workingDirectory, required environment, required rows, required columns}) => FakePty()
          ..emit('lopi-pty-ok\r\n')
          ..exit(0),
      );
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
        return null;
      });
      await tester.pumpWidget(env.app(inShell(RuntimeScreen(projectDir: env.tmp.path)), mode));
      await tester.pump();
      await tester.scrollUntilVisible(find.byKey(const Key('runtime-diagnose')), 200, scrollable: find.byType(Scrollable).first);
      expect(find.text('开始诊断'), findsOneWidget);
      // 诊断里是真实的等待（超时、伪终端），放到真实时间里跑
      final running = tester.runAsync(() => runtime.diagnostics.run(projectDir: env.tmp.path));
      await tester.pump();
      await running;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('重新诊断'), findsOneWidget);
      expect(find.textContaining('默认模式进不去，兼容模式可以'), findsWidgets);
      expect(find.byKey(const Key('diag-report')), findsOneWidget);
      expect(env.services.settings.getBool(SettingKeys.runtimeCompat), isTrue);
      await tester.scrollUntilVisible(find.byKey(const Key('diag-copy')), 200, scrollable: find.byType(Scrollable).first);
      await tester.pump(const Duration(milliseconds: 300));
      await shot(tester, '36-runtime-diagnostics-$suffix');
      await tester.tap(find.byKey(const Key('diag-copy')));
      await tester.pump();
      expect(copied, contains('LopiCode 运行环境诊断'));
      expect(copied, contains('== 伪终端自检'));
      await tester.pump(const Duration(seconds: 5));
    });
  }
}

/// 测试里直接给出文件内容的资源包。
class _FixedBundle extends CachingAssetBundle {
  _FixedBundle(this.text);
  final String text;

  @override
  Future<ByteData> load(String key) async => ByteData.sublistView(Uint8List.fromList(utf8.encode(text)));

  @override
  Future<String> loadString(String key, {bool cache = true}) async => text;
}

class _EchoPty extends FakePty {
  @override
  void write(List<int> data) {
    super.write(data);
    final text = utf8.decode(data);
    emit(text.replaceAll('\r', '\r\n'));
    if (text.contains(r'$((40+2))')) emit('lopi-42\r\n');
  }
}
