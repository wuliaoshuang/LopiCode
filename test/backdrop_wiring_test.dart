// 背景图片接到各个页面上了没有（合并主题 + 背景图片后补的接入点）：
// - “范围 › 其它页面”开 → 这一页后面画着背景；关 → 没有。
// - “透出背景”四个开关（终端 / 代码区 / 积木画布 / 低代码画布）开 → 那一块的底色变半透明；关 → 实底。
//   flutter test --no-pub test/backdrop_wiring_test.dart
//   LOPI_SHOTS=1 LOPI_SHOT_DIR=../preview flutter test --no-pub test/backdrop_wiring_test.dart   # 同时出 merged-*.png
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/appearance/theme_builtin.dart';
import 'package:lopicode/backdrop/backdrop_model.dart';
import 'package:lopicode/blocks/block_canvas_view.dart';
import 'package:lopicode/build/build_screen.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/lowcode/builder_screen.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/runtime/runtime_screen.dart';
import 'package:lopicode/templates/project_templates.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/backdrop_images.dart';
import 'package:lopicode/ui/backdrop_settings_screen.dart';
import 'package:lopicode/ui/backend_screen.dart';
import 'package:lopicode/ui/chrome.dart';
import 'package:lopicode/ui/favorites_screen.dart';
import 'package:lopicode/ui/project_list_screen.dart';
import 'package:lopicode/ui/project_shell.dart';
import 'package:lopicode/ui/settings_pages.dart';
import 'package:lopicode/ui/settings_screen.dart';
import 'package:lopicode/ui/shell.dart';
import 'package:lopicode/ui/theme_editor_screen.dart';
import 'package:lopicode/ui/theme_import_screen.dart';
import 'package:lopicode/ui/themes_screen.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:re_editor/re_editor.dart';
import 'package:xterm/xterm.dart';

import 'support/backdrop_ui_support.dart';
import 'support/harness.dart';
import 'support/runtime_fakes.dart';

const paintKey = ValueKey('app-backdrop-paint');
final bool writeShots = Platform.environment['LOPI_SHOTS'] == '1';
final String shotDir = Platform.environment['LOPI_SHOT_DIR'] ?? '.tmp/merged-shots';
bool fontsLoaded = false;

const String _js = '''// 待办清单
export class Todo {
  constructor(title, done = false) {
    this.title = title;
    this.done = done;
  }
}
const items = [new Todo('写周报'), new Todo('买牛奶', true)];
console.log(items.length, true, null);
''';

void main() {
  setUpAll(() async => fontsLoaded = await loadRealFonts());
  tearDown(BackdropImages.instance.clear);

  Future<void> shot(WidgetTester tester, String name) async {
    expect(tester.takeException(), isNull, reason: '$name 渲染时出了异常（溢出也算）');
    if (!writeShots || !fontsLoaded) return;
    final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(shotKey));
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      File('$shotDir/merged-$name.png')
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync(data!.buffer.asUint8List());
    });
  }

  Future<TestEnv> newEnv(WidgetTester tester) async {
    usePhoneViewport(tester);
    late TestEnv env;
    await tester.runAsync(() async => env = await TestEnv.create());
    return env;
  }

  /// 放一张像风景的背景；[pages]＝“其它页面”开不开；[areas]＝要打开的“透出”。
  Future<void> seed(WidgetTester tester, TestEnv env, {bool pages = true, Set<BackdropArea> areas = const {}}) => seedBackdrop(
    tester,
    env,
    scene: true,
    settings: (s) {
      var next = s.copyWith(onPages: pages);
      for (final a in areas) {
        next = next.withArea(a, true);
      }
      return next;
    },
  );

  Future<(TestEnv, Project, ProjectSession)> open(WidgetTester tester, ProjectTemplate template, {String? language, void Function(Project)? before, bool fakePty = false}) async {
    final env = await newEnv(tester);
    late Project project;
    late ProjectSession session;
    await tester.runAsync(() async {
      project = await createProjectFromTemplate(env.services.projects, '我的小站', template, language: language);
      before?.call(project);
      session = ProjectSession(env.services, project);
      if (fakePty) {
        session.ptySpawner = (exe, {required workingDirectory, required environment, required rows, required columns}) => FakePty();
      }
      await session.loadChat();
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    addTearDown(() async {
      await tester.runAsync(() async {
        session.dispose();
        await env.dispose();
      });
    });
    return (env, project, session);
  }

  Future<void> show(WidgetTester tester, TestEnv env, Widget home, {ThemeMode mode = ThemeMode.light, int rounds = 8}) async {
    await tester.pumpWidget(appFor(env, home, mode: mode, font: kTestFont));
    await settle(tester, rounds: rounds);
  }

  /// 开关拨一下再看：开 → 画着背景；关 → 没有。
  Future<void> flip(WidgetTester tester, TestEnv env, {required String what}) async {
    expect(find.byKey(paintKey), findsWidgets, reason: '$what：“其它页面”开着，应该画着背景');
    backdropOf(env).update((s) => s.copyWith(onPages: false), persist: false);
    await settle(tester, rounds: 2);
    expect(find.byKey(paintKey), findsNothing, reason: '$what：“其它页面”关了，不该有背景');
    backdropOf(env).update((s) => s.copyWith(onPages: true), persist: false);
    await settle(tester, rounds: 2);
    expect(find.byKey(paintKey), findsWidgets, reason: '$what：再打开又有了');
  }

  group('“其它页面”开关', () {
    testWidgets('没设背景图：这些页面一个都不画背景（和原来一样）', (tester) async {
      final env = await newEnv(tester);
      addTearDown(() => tester.runAsync(env.dispose));
      for (final page in <Widget>[ProjectListScreen(onOpen: (_) {}), const SettingsScreen(), const AppearanceScreen(), const ThemesScreen(), const RuntimeScreen()]) {
        await show(tester, env, page, rounds: 4);
        expect(find.byKey(paintKey), findsNothing, reason: '${page.runtimeType}');
      }
    });

    testWidgets('项目列表', (tester) async {
      final env = await newEnv(tester);
      addTearDown(() => tester.runAsync(env.dispose));
      await tester.runAsync(() async {
        await env.services.projects.create('个人主页', ProjectTemplate.web);
        await env.services.projects.create('活动报名页', ProjectTemplate.lowcode);
        await env.services.projects.create('脚本练习', ProjectTemplate.empty);
      });
      await seed(tester, env);
      await show(tester, env, ProjectListScreen(onOpen: (_) {}), rounds: 40);
      expect(find.text('个人主页'), findsOneWidget);
      await flip(tester, env, what: '项目列表');
      // 卡片按“表面不透明度”变透（没动过滑杆：用主题的 0.88），字还是实的
      final card = tester.widget<Card>(find.ancestor(of: find.text('个人主页'), matching: find.byType(Card)).first);
      expect(card.color!.a, closeTo(0.88, 0.01));
      await shot(tester, 'projects-light');
      await show(tester, env, ProjectListScreen(onOpen: (_) {}), mode: ThemeMode.dark, rounds: 40);
      expect(find.byKey(paintKey), findsWidgets);
      await shot(tester, 'projects-dark');
    });

    testWidgets('设置各页（公共外壳）：设置首页、外观、背景图片设置页；卡片变透', (tester) async {
      final env = await newEnv(tester);
      addTearDown(() => tester.runAsync(env.dispose));
      await seed(tester, env);
      await show(tester, env, const SettingsScreen(), rounds: 4);
      await flip(tester, env, what: '设置首页');
      final cardBox = tester.widget<Container>(find.descendant(of: find.byType(GroupCard).first, matching: find.byType(Container)).first);
      expect((cardBox.decoration! as BoxDecoration).color!.a, closeTo(0.88, 0.01));
      await shot(tester, 'settings-light');
      await show(tester, env, const SettingsScreen(), mode: ThemeMode.dark, rounds: 4);
      await shot(tester, 'settings-dark');

      await show(tester, env, const AppearanceScreen(), rounds: 4);
      await flip(tester, env, what: '外观页');
      expect(find.descendant(of: find.byKey(const Key('appearance-background')), matching: find.text('已启用')), findsOneWidget);
      await shot(tester, 'appearance-light');
      await tester.ensureVisible(find.byKey(const Key('appearance-background')));
      await tester.tap(find.byKey(const Key('appearance-background')));
      await tester.pumpAndSettle();
      expect(find.byType(BackdropSettingsScreen), findsOneWidget, reason: '点“背景图片”进它的设置页');
      await pumpUntil(tester, find.byKey(const Key('bg-enabled')));
      await flip(tester, env, what: '背景图片设置页');
      await shot(tester, 'backdrop-settings-light');
    });

    testWidgets('外观页那一行的状态文字跟着变：未设置 → 已启用 → 已关闭', (tester) async {
      final env = await newEnv(tester);
      addTearDown(() => tester.runAsync(env.dispose));
      await show(tester, env, const AppearanceScreen(), rounds: 4);
      Finder said(String s) => find.descendant(of: find.byKey(const Key('appearance-background')), matching: find.text(s));
      expect(said('未设置'), findsOneWidget);
      await seed(tester, env, pages: false);
      await settle(tester, rounds: 2);
      expect(said('已启用'), findsOneWidget);
      backdropOf(env).update((s) => s.copyWith(enabled: false), persist: false);
      await settle(tester, rounds: 2);
      expect(said('已关闭'), findsOneWidget);
    });

    testWidgets('主题管理页、主题编辑器、导入主题页', (tester) async {
      final env = await newEnv(tester);
      addTearDown(() => tester.runAsync(env.dispose));
      await seed(tester, env);
      await show(tester, env, const ThemesScreen(), rounds: 4);
      await flip(tester, env, what: '主题管理页');
      await shot(tester, 'themes-light');
      await show(tester, env, const ThemeEditorScreen(theme: kDefaultLightTheme), rounds: 4);
      await flip(tester, env, what: '主题编辑器');
      await shot(tester, 'theme-editor-light');
      await show(tester, env, const ThemeImportScreen(), rounds: 4);
      await flip(tester, env, what: '导入主题页');
    });

    testWidgets('工作区里的页面：文件、终端、打包、运行环境、收藏', (tester) async {
      final (env, project, session) = await open(tester, ProjectTemplate.web);
      await seed(tester, env);
      await show(tester, env, ProjectShell(project: project, session: session, initial: ShellDest.files), rounds: 20);
      await flip(tester, env, what: '文件页');
      await shot(tester, 'files-light');
      await show(tester, env, ProjectShell(project: project, session: session, initial: ShellDest.terminal));
      await flip(tester, env, what: '终端页');
      await show(tester, env, ProjectShell(project: project, session: session, initial: ShellDest.apk));
      expect(find.byType(BuildScreen), findsOneWidget);
      await flip(tester, env, what: '打包页');
      await shot(tester, 'apk-light');
      await show(tester, env, ProjectShell(project: project, session: session, initial: ShellDest.runtime));
      expect(find.byType(RuntimeScreen), findsOneWidget);
      await flip(tester, env, what: '运行环境页');
      await shot(tester, 'runtime-light');
      await show(tester, env, FavoritesScreen(session: session), rounds: 6);
      await flip(tester, env, what: '收藏页');
    });

    testWidgets('搭建页：低代码、后端积木（画布默认还是实底，只是页面后面有背景）', (tester) async {
      final (env, project, session) = await open(tester, ProjectTemplate.lowcode);
      await seed(tester, env);
      await show(tester, env, ProjectShell(project: project, session: session, initial: ShellDest.builder));
      expect(find.byType(BuilderScreen), findsOneWidget);
      await flip(tester, env, what: '低代码搭建页');
      final canvas = tester.widget<ColoredBox>(find.ancestor(of: find.byKey(const ValueKey('lowcode-canvas')), matching: find.byType(ColoredBox)).first);
      expect(canvas.color.a, 1, reason: '“透出 › 低代码画布”没开：画布四周还是实底');
    });
  });

  group('“透出背景”开关', () {
    testWidgets('终端：关＝实底；开＝底色按表面不透明度变透，xterm 自己不再铺底', (tester) async {
      final (env, project, session) = await open(tester, ProjectTemplate.web);
      await seed(tester, env);
      await show(tester, env, ProjectShell(project: project, session: session, initial: ShellDest.terminal));
      await tester.runAsync(() async {
        session.terminals[session.activeTerminal].run('ls');
        await Future<void>.delayed(const Duration(milliseconds: 600));
      });
      session.terminals[session.activeTerminal].terminal.write('\r\n\x1b[32m绿色 ok\x1b[0m \x1b[31m红色 error\x1b[0m\r\n\x1b[1m粗体\x1b[0m 普通文字 README.md index.html\r\n');
      await settle(tester, rounds: 2);
      ColoredBox box() => tester.widget<ColoredBox>(find.ancestor(of: find.byType(TerminalView), matching: find.byType(ColoredBox)).first);
      final solid = tester.element(find.byType(TerminalView)).themeSpec.terminalColor('bg');
      expect(box().color, solid);
      expect(tester.widget<TerminalView>(find.byType(TerminalView)).theme.background, solid);
      await shot(tester, 'terminal-off-light');

      backdropOf(env).update((s) => s.withArea(BackdropArea.terminal, true), persist: false);
      await settle(tester, rounds: 2);
      expect(box().color.a, closeTo(solid.a * 0.88, 0.01));
      expect(tester.widget<TerminalView>(find.byType(TerminalView)).theme.background.a, 0, reason: '只铺一层半透明的底，不叠两层');
      await shot(tester, 'terminal-on-light');

      // “其它页面”关了：这一页没背景，透出开关开着也还是实底
      backdropOf(env).update((s) => s.copyWith(onPages: false), persist: false);
      await settle(tester, rounds: 2);
      expect(box().color, solid);
      backdropOf(env).update((s) => s.copyWith(onPages: true), persist: false);
      await settle(tester, rounds: 2);

      await show(
        tester,
        env,
        ProjectShell(project: project, session: session, initial: ShellDest.terminal),
        mode: ThemeMode.dark,
      );
      session.terminals[session.activeTerminal].terminal.write('\x1b[33m黄色 warn\x1b[0m\r\n');
      await settle(tester, rounds: 2);
      await shot(tester, 'terminal-on-dark');
      backdropOf(env).update((s) => s.withArea(BackdropArea.terminal, false), persist: false);
      await settle(tester, rounds: 2);
      await shot(tester, 'terminal-off-dark');
    });

    testWidgets('代码区：编辑器底色', (tester) async {
      final (env, project, session) = await open(tester, ProjectTemplate.web, before: (project) => File(p.join(project.dir, 'todo.js')).writeAsStringSync(_js));
      await seed(tester, env);
      await show(tester, env, ProjectShell(project: project, session: session, initial: ShellDest.files), rounds: 20);
      await tester.tap(find.text('todo.js').first);
      await settle(tester, rounds: 20, ms: 5);
      Color bg() => tester.widget<CodeEditor>(find.byType(CodeEditor)).style!.backgroundColor!;
      final solid = tester.element(find.byType(CodeEditor)).themeSpec.codeColor(CodeKey.bg);
      expect(bg(), solid);
      backdropOf(env).update((s) => s.withArea(BackdropArea.code, true), persist: false);
      await settle(tester, rounds: 2);
      expect(bg().a, closeTo(solid.a * 0.88, 0.01));
      await shot(tester, 'code-on-light');
      backdropOf(env).update((s) => s.withArea(BackdropArea.code, false), persist: false);
      await settle(tester, rounds: 2);
      expect(bg(), solid);

      await show(
        tester,
        env,
        ProjectShell(project: project, session: session, initial: ShellDest.files),
        mode: ThemeMode.dark,
        rounds: 20,
      );
      backdropOf(env).update((s) => s.withArea(BackdropArea.code, true), persist: false);
      await settle(tester, rounds: 4);
      await shot(tester, 'code-on-dark');
    });

    testWidgets('积木画布', (tester) async {
      final (env, project, session) = await open(tester, ProjectTemplate.backendBlocks, language: 'node', fakePty: true);
      await seed(tester, env);
      await show(tester, env, ProjectShell(project: project, session: session, initial: ShellDest.builder));
      expect(find.byType(BackendScreen), findsOneWidget);
      expect(find.byKey(paintKey), findsWidgets, reason: '后端积木页后面有背景');
      ColoredBox box() => tester.widget<ColoredBox>(find.descendant(of: find.byType(BlockCanvasView), matching: find.byType(ColoredBox)).first);
      expect(box().color.a, 1, reason: '默认不透出');
      final solid = box().color;
      backdropOf(env).update((s) => s.withArea(BackdropArea.blocks, true), persist: false);
      await settle(tester, rounds: 2);
      expect(box().color.a, closeTo(0.88, 0.01));
      expect(box().color.withValues(alpha: 1), solid);
      // 整页的底让开了：不然两层叠起来比设定的更不透
      final scaffold = tester.widget<Scaffold>(find.ancestor(of: find.byType(BlockCanvasView), matching: find.byType(Scaffold)).first);
      expect(scaffold.backgroundColor!.a, 0);
      await shot(tester, 'blocks-on-light');
      await show(
        tester,
        env,
        ProjectShell(project: project, session: session, initial: ShellDest.builder),
        mode: ThemeMode.dark,
      );
      await shot(tester, 'blocks-on-dark');
      backdropOf(env).update((s) => s.withArea(BackdropArea.blocks, false), persist: false);
      await settle(tester, rounds: 2);
      expect(box().color.a, 1);
    });

    testWidgets('低代码画布：四周变透，页面本身不变', (tester) async {
      final (env, project, session) = await open(tester, ProjectTemplate.lowcode);
      await seed(tester, env);
      await show(tester, env, ProjectShell(project: project, session: session, initial: ShellDest.builder));
      ColoredBox box() => tester.widget<ColoredBox>(find.ancestor(of: find.byKey(const ValueKey('lowcode-canvas')), matching: find.byType(ColoredBox)).first);
      final solid = box().color;
      expect(solid.a, 1);
      backdropOf(env).update((s) => s.withArea(BackdropArea.lowcode, true), persist: false);
      await settle(tester, rounds: 2);
      expect(box().color.a, closeTo(0.88, 0.01));
      await shot(tester, 'lowcode-on-light');
      await show(
        tester,
        env,
        ProjectShell(project: project, session: session, initial: ShellDest.builder),
        mode: ThemeMode.dark,
      );
      await shot(tester, 'lowcode-on-dark');
      backdropOf(env).update((s) => s.withArea(BackdropArea.lowcode, false), persist: false);
      await settle(tester, rounds: 2);
      expect(box().color.a, 1);
    });
  });

  group('表面不透明度', () {
    testWidgets('没动过滑杆：用当前主题的数；动过以后滑杆说了算；“恢复默认效果”回到跟随主题', (tester) async {
      final env = await newEnv(tester);
      addTearDown(() => tester.runAsync(env.dispose));
      await seed(tester, env);
      await show(tester, env, const SettingsScreen(), rounds: 4);
      double cardAlpha() => ((tester.widget<Container>(find.descendant(of: find.byType(GroupCard).first, matching: find.byType(Container)).first).decoration! as BoxDecoration).color!).a;
      expect(cardAlpha(), closeTo(0.88, 0.01), reason: '默认浅色主题的 metrics.surfaceOpacity 是 0.88');
      backdropOf(env).update((s) => s.copyWith(surfaceOpacity: 60), persist: false);
      await settle(tester, rounds: 2);
      expect(cardAlpha(), closeTo(0.6, 0.01));
      backdropOf(env).update((s) => s.copyWith(surfaceFromTheme: true), persist: false);
      await settle(tester, rounds: 2);
      expect(cardAlpha(), closeTo(0.88, 0.01));
    });
  });
}
