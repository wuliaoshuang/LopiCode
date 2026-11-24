// 真机反馈第三轮第 3 条的界面：终端页上“正在替你配工具”的那一条、安装引导里的那句话、运行面板的说明。
// 390×844，浅色 + 深色。Ubuntu 里的进程是假的（不进 PRoot、不联网）。LOPI_SHOTS=1 时把截图写到 docs/screenshots/。
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/app.dart';
import 'package:lopicode/backend/backend_launch.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/state/backend_run.dart';
import 'package:lopicode/ui/backend_run_sheet.dart';
import 'package:lopicode/ui/project_shell.dart';
import 'package:lopicode/ui/shell.dart';
import 'package:material_ui/material_ui.dart';

import 'support/harness.dart';
import 'support/run_fakes.dart';

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

const goCmd = 'go build -o server . && ./server';
Finder k(String key) => find.byKey(Key(key));

void main() {
  setUpAll(() async => fontsLoaded = await loadRealFonts());

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    final suffix = mode == ThemeMode.light ? 'light' : 'dark';

    Future<(RunEnv, ProjectSession)> boot(WidgetTester tester, {bool installed = true, int? free}) async {
      usePhoneViewport(tester);
      final env = (await tester.runAsync(() => RunEnv.create(installed: installed, free: free ?? 23 * 1024 * 1024 * 1024)))!;
      final project = (await tester.runAsync(() => env.services.projects.create('小后端', ProjectTemplate.web)))!;
      late ProjectSession session;
      await tester.runAsync(() async {
        session = ProjectSession(env.services, project);
        await session.loadChat();
        env.wire(session);
      });
      addTearDown(() async {
        await tester.runAsync(() async {
          session.dispose();
          await env.dispose();
        });
      });
      await tester.pumpWidget(
        RepaintBoundary(
          key: shotKey,
          child: LopiCodeApp(
            services: env.services,
            home: ProjectShell(project: project, session: session, initial: ShellDest.terminal),
            fontFamily: kTestFont,
            forceThemeMode: mode,
          ),
        ),
      );
      await settle(tester);
      return (env, session);
    }

    /// 让真实的异步走到 [done] 成立，再把界面刷出来。
    Future<void> reach(WidgetTester tester, bool Function() done, String what) async {
      // 点按钮触发的那部分跑在测试的假时钟里、假进程跑在真时钟里：两边轮着推。
      for (var i = 0; i < 200 && !done(); i++) {
        await tester.runAsync(() => tick(10));
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(done(), isTrue, reason: '等不到：$what');
      await settle(tester);
    }

    testWidgets('Go 没装：终端页多一条“正在安装”，输出在下面的终端里；没装成显示真正原因和“重试”；重试装好后这条消失、后端启动 ($suffix)', (tester) async {
      final (env, session) = await boot(tester);
      expect(k('backend-run-bar'), findsNothing, reason: '没事的时候不占地方');
      env.ctl(session).start(language: 'go', command: goCmd);
      await reach(tester, () => env.guest.installs.isNotEmpty, '开始装');
      env.guest.installs.single
        ..say('Get:1 http://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports noble InRelease [256 kB]\n')
        ..say('Setting up curl (8.5.0-2ubuntu10.6) ...\n')
        ..say('下载 go1.26.11.linux-arm64.tar.gz（约 61 MB）\n')
        ..complain('######################                         48.3%\n');
      await reach(tester, () => session.terminals.last.text.contains('48.3%'), '输出进终端');
      expect(tester.widget<Text>(k('backend-run-title')).data, '正在安装 Go 1.26.11');
      expect(find.textContaining('进度看下面的终端'), findsOneWidget);
      expect(k('backend-run-progress'), findsOneWidget);
      expect(k('backend-run-cancel'), findsOneWidget);
      expect(k('backend-run-retry'), findsNothing);
      expect(session.terminals.last.title, kBackendTerminalTitle);
      await shot(tester, '70-backend-run-installing-$suffix');

      env.guest.installs.single
        ..complain('curl: (6) Could not resolve host: golang.google.cn\n')
        ..finish(6);
      await reach(tester, () => env.run(session).phase == BackendRunPhase.failed, '失败');
      expect(find.text('Go 1.26.11 没装成，后端没有启动'), findsOneWidget);
      expect(tester.widget<Text>(k('backend-run-body')).data, contains('连不上下载源（现在用的是“清华大学镜像”）'));
      expect(k('backend-run-progress'), findsNothing);
      expect(k('backend-run-cancel'), findsNothing);
      expect(k('backend-run-retry'), findsOneWidget);
      expect(k('backend-run-dismiss'), findsOneWidget);
      await shot(tester, '71-backend-run-failed-$suffix');

      await tester.tap(k('backend-run-retry'));
      await reach(tester, () => env.guest.installs.length == 2, '重新装');
      expect(find.text('正在安装 Go 1.26.11'), findsOneWidget);
      env.guest.installs.last.finish(0);
      await reach(tester, () => env.typed.any((t) => t.contains(goCmd)), '启动');
      expect(k('backend-run-bar'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('JDK 比较大：先问一次，写明多大、装在哪；“先不装”就收起；点“安装并启动”才装；装的时候点“取消”就停 ($suffix)', (tester) async {
      final (env, session) = await boot(tester);
      env.ctl(session).start(language: 'java', command: 'javac Main.java && java Main');
      await reach(tester, () => env.run(session).phase == BackendRunPhase.confirming, '等她点头');
      expect(find.text('要先装 Java（JDK 21）'), findsOneWidget);
      expect(find.textContaining('下载约 130 MB，装好后占约 300 MB，装在 Ubuntu 环境里'), findsOneWidget);
      expect(k('backend-run-confirm'), findsOneWidget);
      expect(k('backend-run-decline'), findsOneWidget);
      expect(k('backend-run-cancel'), findsNothing, reason: '一种状态只给一组出路');
      await shot(tester, '72-backend-run-confirm-$suffix');

      await tester.tap(k('backend-run-decline'));
      await reach(tester, () => env.run(session).phase == BackendRunPhase.idle, '收起');
      expect(k('backend-run-bar'), findsNothing);
      expect(env.guest.installs, isEmpty);

      env.ctl(session).start(language: 'java', command: 'javac Main.java && java Main');
      await reach(tester, () => env.run(session).phase == BackendRunPhase.confirming, '再问');
      await tester.tap(k('backend-run-confirm'));
      await reach(tester, () => env.guest.installs.isNotEmpty, '开始装');
      expect(find.text('正在安装 Java（JDK 21）'), findsOneWidget);
      await tester.tap(k('backend-run-cancel'));
      await reach(tester, () => env.run(session).phase == BackendRunPhase.idle, '停下');
      expect(env.guest.installs.single.killed, isTrue);
      expect(k('backend-run-bar'), findsNothing);
      expect(env.typed.where((t) => t.contains('javac')), isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Ubuntu 环境没装时点运行：终端页是安装引导，多一句“装好后会接着启动后端”；没在等的时候没有这句 ($suffix)', (tester) async {
      // 空间不够：安装在联网之前就失败，不下载任何东西；这一次“运行”还等着她在引导里再点一次。
      final (env, session) = await boot(tester, installed: false, free: 20 * 1024 * 1024);
      expect(k('terminal-setup'), findsOneWidget);
      expect(k('terminal-setup-notice'), findsNothing);
      env.ctl(session).start(language: 'go', command: goCmd);
      await reach(tester, () => env.runtime.installError != null, '装环境失败');
      expect(env.run(session).phase, BackendRunPhase.waitingRuntime);
      expect(find.descendant(of: k('terminal-setup-notice'), matching: find.textContaining('装好后会接着准备好工具并启动后端')), findsOneWidget);
      expect(find.textContaining('剩余空间不够'), findsWidgets, reason: '真正的原因在引导里');
      expect(k('backend-run-bar'), findsNothing, reason: '引导就是整页，不再叠一条');
      await shot(tester, '73-backend-run-setup-$suffix');
      expect(tester.takeException(), isNull);
    });
  }

  test('运行面板的说明：五种语言都写“没装会自动装好再启动”，Go 写明多大，JDK 写明会先问一次（面板本身的截图在 backend_screen_test.dart）', () {
    expect(beToolchainNote('go').text, '要用到 Go（1.18 或更新）。没装也不用管：点“在终端启动”会先自动装好 Go 1.26.11（下载约 61 MB，装好后占约 240 MB）再启动。第一次启动要先编译，会慢一些。');
    expect(beToolchainNote('java').text, allOf(contains('要带 javac'), contains('Java（JDK 21）（下载约 130 MB，装好后占约 300 MB）'), contains('装之前会先问你一次')));
    expect(beToolchainNote('php').text, '要用到 PHP 的命令行版。没装也不用管：点“在终端启动”会先自动装好 PHP 8.3 再启动。');
    for (final language in ['node', 'python', 'go', 'java', 'php']) {
      expect(beToolchainNote(language).oneTap, isTrue, reason: language);
      expect(beToolchainNote(language).text, isNot(contains('自己')), reason: language);
    }
    expect(beToolchainNote('cobol'), (text: '这种语言的工具要你自己在终端里装好。', oneTap: false));
  });
}
