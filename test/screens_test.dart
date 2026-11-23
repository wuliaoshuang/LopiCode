// 主要界面在 390×844 上的渲染检查：每个界面在浅色和深色下各渲染一次，
// 不能有异常或溢出。设置环境变量 LOPI_SHOTS=1 时，同时把截图写到 docs/screenshots/。
//   LOPI_SHOTS=1 flutter test test/screens_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/build/build_controller.dart';
import 'package:lopicode/build/build_screen.dart';
import 'package:lopicode/build/github_client.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/ui/preview_tab.dart';
import 'package:lopicode/ui/project_list_screen.dart';
import 'package:lopicode/ui/project_shell.dart';
import 'package:lopicode/ui/settings_screen.dart';
import 'package:lopicode/ui/shell.dart';
import 'package:material_ui/material_ui.dart';

import 'support/harness.dart';

final bool writeShots = Platform.environment['LOPI_SHOTS'] == '1';
bool fontsLoaded = false;

Future<void> shot(WidgetTester tester, String name) async {
  expect(tester.takeException(), isNull, reason: '$name 渲染时出了异常');
  if (!writeShots || !fontsLoaded) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(shotKey));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('docs/screenshots/$name.png');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(data!.buffer.asUint8List());
  });
}

/// 预览页里用来代替 WebView 的假网页（测试环境里 WebView 渲染不了）。
Widget fakeWebPage(Uri uri) => ColoredBox(
  color: const Color(0xFFF6FBFD),
  child: Padding(
    padding: const EdgeInsets.all(20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('你好，LopiCode', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Color(0xFF12202B))),
        const SizedBox(height: 8),
        Text('（截图里的占位网页，真机上这里是 WebView：$uri）', style: const TextStyle(fontSize: 13, color: Color(0xFF51606C))),
      ],
    ),
  ),
);

void main() {
  setUpAll(() async {
    fontsLoaded = await loadRealFonts();
    PreviewTab.debugViewBuilder = fakeWebPage;
  });
  tearDownAll(() => PreviewTab.debugViewBuilder = null);

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    final suffix = mode == ThemeMode.light ? 'light' : 'dark';
    final font = kTestFont;

    Future<(TestEnv, Project, ProjectSession)> open(WidgetTester tester, ProjectTemplate template, {TestEnv? env}) async {
      usePhoneViewport(tester);
      late TestEnv e;
      late Project project;
      late ProjectSession session;
      await tester.runAsync(() async {
        e = env ?? await TestEnv.create();
        project = await e.services.projects.create('我的小站', template);
        session = ProjectSession(e.services, project);
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      addTearDown(() async {
        session.dispose();
        e.dispose();
      });
      return (e, project, session);
    }

    testWidgets('项目列表：空状态 → 新建面板 → 有项目 ($suffix)', (tester) async {
      usePhoneViewport(tester);
      late TestEnv env;
      await tester.runAsync(() async => env = await TestEnv.create());
      addTearDown(env.dispose);
      await tester.pumpWidget(appFor(env, ProjectListScreen(onOpen: (_) {}), mode: mode, font: font));
      await settle(tester);
      expect(find.text('还没有项目'), findsOneWidget);
      await shot(tester, '01-projects-empty-$suffix');

      await tester.tap(find.widgetWithText(FilledButton, '新建项目').first);
      await settle(tester, rounds: 3);
      expect(find.text('前端网页'), findsOneWidget);
      expect(find.text('低代码页面'), findsOneWidget);
      await shot(tester, '02-new-project-$suffix');

      await tester.tapAt(const Offset(195, 60));
      await settle(tester, rounds: 2);
      await tester.runAsync(() async {
        await env.services.projects.create('个人主页', ProjectTemplate.web);
        await env.services.projects.create('活动报名页', ProjectTemplate.lowcode);
        await env.services.projects.create('脚本练习', ProjectTemplate.empty);
      });
      await tester.pumpWidget(appFor(env, ProjectListScreen(key: UniqueKey(), onOpen: (_) {}), mode: mode, font: font));
      // 列表要读每个项目的元数据：一连串真实 IO，每一步都要让出一轮
      await settle(tester, rounds: 40, ms: 5);
      expect(find.text('个人主页'), findsOneWidget);
      expect(find.text('活动报名页'), findsOneWidget);
      await shot(tester, '03-projects-$suffix');
    });

    testWidgets('文件与编辑器 ($suffix)', (tester) async {
      final (env, project, session) = await open(tester, ProjectTemplate.web);
      await tester.pumpWidget(appFor(env, ProjectShell(project: project, session: session, initial: ShellDest.files), mode: mode, font: font));
      await settle(tester, rounds: 20, ms: 5);
      expect(find.text('index.html'), findsWidgets);
      await shot(tester, '08-files-$suffix');
      await tester.tap(find.text('style.css').first);
      await settle(tester, rounds: 20, ms: 5);
      expect(find.textContaining('box-sizing'), findsWidgets);
      await shot(tester, '09-editor-$suffix');
    });

    testWidgets('Agent：工具卡片、确认卡 ($suffix)', (tester) async {
      usePhoneViewport(tester);
      late TestEnv env;
      await tester.runAsync(() async {
        env = await TestEnv.create(
          chatClient: () => ScriptedChatClient([
            [say('好的，我先看看项目里有什么。'), call(0, 'list_files', '{}')],
            [
              say('我来加一个深色主题的样式，然后看一下目录。'),
              call(0, 'write_file', '{"path":"dark.css","content":"body { background: #111; color: #eee; }\\n"}'),
              call(1, 'run_command', '{"command":"ls -la"}'),
            ],
            [say('已经加好 dark.css。在 index.html 里引入它就能生效。')],
          ]),
        );
      });
      final (_, project, session) = await open(tester, ProjectTemplate.web, env: env);
      await tester.pumpWidget(appFor(env, ProjectShell(project: project, session: session, initial: ShellDest.chat), mode: mode, font: font));
      await settle(tester);
      expect(find.text('新对话'), findsOneWidget);
      expect(find.textContaining('我的小站 / '), findsOneWidget);
      expect(find.text('项目规则'), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing, reason: '不应该再有底部导航');
      await shot(tester, '04-chat-empty-$suffix');

      await tester.tap(find.byTooltip('打开侧边栏'));
      await settle(tester, rounds: 3);
      expect(find.text('低代码搭建'), findsOneWidget);
      await shot(tester, '05-drawer-$suffix');
      await tester.tapAt(const Offset(370, 400));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.byType(Drawer), findsNothing);

      late Future<void> sending;
      await tester.runAsync(() async {
        sending = session.sendToAgent('帮我加一个深色主题');
        for (var i = 0; i < 40 && session.pendingApproval == null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      });
      await settle(tester, rounds: 3);
      expect(session.pendingApproval, isNotNull, reason: '执行命令前必须停下来等确认');
      expect(File('${project.dir}/dark.css').existsSync(), isTrue);
      expect(find.text('允许这一次'), findsOneWidget);
      await shot(tester, '06-chat-approval-$suffix');

      await tester.tap(find.text('允许这一次'));
      await tester.runAsync(() => sending.timeout(const Duration(seconds: 20)));
      await settle(tester, rounds: 3);
      expect(session.agentBusy, isFalse);
      expect(find.textContaining('已经加好 dark.css'), findsOneWidget);
      await shot(tester, '07-chat-done-$suffix');
    });

    testWidgets('终端：真的跑一条命令 ($suffix)', (tester) async {
      final (env, project, session) = await open(tester, ProjectTemplate.web);
      await tester.pumpWidget(appFor(env, ProjectShell(project: project, session: session, initial: ShellDest.terminal), mode: mode, font: font));
      await settle(tester);
      await tester.runAsync(() async {
        session.terminals[session.activeTerminal].run('ls');
        await Future<void>.delayed(const Duration(milliseconds: 600));
      });
      await settle(tester, rounds: 2);
      expect(session.terminals[session.activeTerminal].text, contains('index.html'));
      await shot(tester, '10-terminal-$suffix');
    });

    testWidgets('预览 ($suffix)', (tester) async {
      final (env, project, session) = await open(tester, ProjectTemplate.web);
      await tester.pumpWidget(appFor(env, ProjectShell(project: project, session: session, initial: ShellDest.preview), mode: mode, font: font));
      await settle(tester, rounds: 6);
      expect(session.preview.port, isNotNull);
      await shot(tester, '11-preview-$suffix');
    });

    testWidgets('低代码搭建器 ($suffix)', (tester) async {
      final (env, project, session) = await open(tester, ProjectTemplate.lowcode);
      await tester.pumpWidget(appFor(env, ProjectShell(project: project, session: session, initial: ShellDest.builder), mode: mode, font: font));
      await settle(tester, rounds: 8);
      expect(find.byTooltip('打开侧边栏'), findsOneWidget);
      await shot(tester, '12-builder-$suffix');

      // 点画布上的按钮选中它 → 打开属性面板
      await tester.tap(find.text('提交').first);
      await settle(tester, rounds: 2);
      expect(find.text('属性'), findsOneWidget);
      await shot(tester, '13-builder-selected-$suffix');
      await tester.tap(find.text('属性'));
      await settle(tester, rounds: 3);
      expect(find.text('按钮属性'), findsOneWidget);
      await shot(tester, '14-builder-props-$suffix');
      await tester.tapAt(const Offset(195, 60));
      await settle(tester, rounds: 2);
      await tester.tap(find.byTooltip('图层'));
      await settle(tester, rounds: 3);
      await shot(tester, '15-builder-layers-$suffix');
    });

    testWidgets('APK 打包 ($suffix)', (tester) async {
      final (env, _, session) = await open(tester, ProjectTemplate.web);
      await tester.pumpWidget(appFor(env, BuildScreen(session: session), mode: mode, font: font));
      await settle(tester);
      expect(find.textContaining('手机上跑不了 Android SDK 和 Gradle'), findsOneWidget);
      await shot(tester, '16-apk-$suffix');

      final job =
          ApkBuildController(
              client: GitHubClient(token: 'x', owner: 'shuang', repo: 'demo'),
              workflowFile: 'android.yml',
              ref: 'main',
              outputDir: '/storage/emulated/0/Android/data/com.lopicode.app/files/apk/demo',
            )
            ..phase = BuildPhase.done
            ..log.addAll(['推送 4 个文件到 shuang/demo 的 main 分支…', '已提交 a1b2c3d', '触发工作流 android.yml…', '运行 #777 已开始', '构建中…（一般要几分钟）', '构建结束：成功', 'APK 已保存（18.4 MB）'])
            ..runUrl = 'https://github.com/shuang/demo/actions/runs/777'
            ..apkPath = '/storage/emulated/0/Android/data/com.lopicode.app/files/apk/demo/app-debug.apk';
      await tester.pumpWidget(appFor(env, BuildScreen(key: UniqueKey(), session: session, debugController: job), mode: mode, font: font));
      await settle(tester);
      await tester.drag(find.byType(ListView), const Offset(0, -520));
      await settle(tester, rounds: 2);
      expect(find.text('打包完成'), findsOneWidget);
      await shot(tester, '17-apk-done-$suffix');
    });

    testWidgets('设置 ($suffix)', (tester) async {
      usePhoneViewport(tester);
      late TestEnv env;
      await tester.runAsync(() async => env = await TestEnv.create());
      addTearDown(env.dispose);
      await tester.pumpWidget(appFor(env, const SettingsScreen(), mode: mode, font: font));
      await settle(tester);
      expect(find.text('设置'), findsWidgets);
      await shot(tester, '18-settings-$suffix');
    });
  }
}
