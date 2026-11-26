// 主题管理页、主题编辑器、取色面板、快捷生成、导出 / 导入界面（手机尺寸 390×844）。
//
//   flutter test test/theme_editor_ui_test.dart
//   LOPI_SHOTS=1 flutter test test/theme_editor_ui_test.dart   # 同时写截图到 docs/screenshots/editor-*.png
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/appearance/theme_builtin.dart';
import 'package:lopicode/appearance/theme_contrast.dart';
import 'package:lopicode/appearance/theme_edit_model.dart';
import 'package:lopicode/appearance/theme_export_file.dart';
import 'package:lopicode/appearance/theme_fields.dart';
import 'package:lopicode/appearance/theme_generate.dart';
import 'package:lopicode/appearance/theme_json.dart';
import 'package:lopicode/appearance/theme_spec.dart';
import 'package:lopicode/core/stores.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/state/theme_hooks.dart';
import 'package:lopicode/state/themes_state.dart';
import 'package:lopicode/theme/tokens.dart' hide ThemeSpec;
import 'package:lopicode/ui/settings_code_font.dart';
import 'package:lopicode/ui/settings_pages.dart';
import 'package:lopicode/ui/theme_editor_screen.dart';
import 'package:lopicode/ui/theme_export_sheet.dart';
import 'package:lopicode/ui/theme_import_screen.dart';
import 'package:lopicode/ui/themes_screen.dart';
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
    File('docs/screenshots/editor-$name.png')
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(data!.buffer.asUint8List());
  });
}

Finder k(String key) => find.byKey(Key(key));

void main() {
  setUpAll(() async => fontsLoaded = await loadRealFonts());

  late String clipboard;
  setUp(() {
    clipboard = '';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') clipboard = (call.arguments as Map)['text'] as String;
      if (call.method == 'Clipboard.getData') return {'text': clipboard};
      return null;
    });
  });
  tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

  Future<TestEnv> boot(WidgetTester tester, Widget Function(TestEnv) home, {ThemeMode mode = ThemeMode.light, Future<void> Function(TestEnv)? before}) async {
    usePhoneViewport(tester);
    late TestEnv env;
    await tester.runAsync(() async {
      env = await TestEnv.create();
      await before?.call(env);
    });
    addTearDown(() => tester.runAsync(env.dispose));
    await tester.pumpWidget(appFor(env, home(env), mode: mode, font: kTestFont));
    await settle(tester, rounds: 2);
    return env;
  }

  ThemesNotifier themesOf(TestEnv env) => env.services.container.read(themesProvider.notifier);
  ThemesView viewOf(TestEnv env) => env.services.container.read(themesProvider);

  /// 等真实存盘做完再排界面。
  /// [until]：存盘后面还跟着换页面的（比如导入后退回管理页），机器忙的时候固定等几轮不够，就等到它出现为止（最多再等 30 轮）。
  Future<void> io(WidgetTester tester, {Finder? until}) async {
    await settle(tester, rounds: 4);
    await tester.pumpAndSettle();
    for (var i = 0; until != null && i < 30 && until.evaluate().isEmpty; i++) {
      await settle(tester, rounds: 1);
      await tester.pumpAndSettle();
    }
  }

  /// 新建一套自己的主题（[make] 可以再改一改）。
  Future<ThemeSpec> mine(WidgetTester tester, TestEnv env, {bool dark = false, String name = '海边', ThemeSpec Function(ThemeSpec)? make}) async {
    late ThemeSpec t;
    await tester.runAsync(() async {
      t = (await themesOf(env).create(dark: dark, name: name)).theme!;
      if (make != null) {
        expect(await themesOf(env).save(make(t)), isNull);
        t = viewOf(env).byId(t.id)!;
      }
    });
    await settle(tester, rounds: 1);
    return t;
  }

  /// 预览块里面现在用的是哪份主题。
  ThemeSpec previewSpec(WidgetTester tester, String kind) => tester.element(find.descendant(of: k('theme-preview-$kind'), matching: find.byType(SingleChildScrollView)).first).themeSpec;

  /// 在取色面板的十六进制框里写一个颜色。
  Future<void> typeHex(WidgetTester tester, String text, {String field = 'color-hex'}) async {
    await tester.ensureVisible(k(field));
    await tester.enterText(k(field), text);
    await tester.pump();
  }

  Future<void> openItem(WidgetTester tester, String id) async {
    // 先回到列表最上面：要找的那一项可能在现在位置的上面。
    tester.state<ScrollableState>(find.descendant(of: k('theme-editor-list'), matching: find.byType(Scrollable)).first).position.jumpTo(0);
    await tester.pump();
    await tester.scrollUntilVisible(
      k('theme-item-$id'),
      200,
      scrollable: find.descendant(of: k('theme-editor-list'), matching: find.byType(Scrollable)).first,
    );
    // 挪到列表中间再点（不顶到最上面：那样它那一组的标题行会被滚出去）。
    await Scrollable.ensureVisible(tester.element(k('theme-item-$id')), alignment: 0.5);
    await tester.pumpAndSettle();
    await tester.tap(k('theme-item-$id'));
    await tester.pumpAndSettle();
  }

  group('外观页', () {
    testWidgets('顺序：颜色模式 → 主题（含“管理主题”）→ 背景图片 → 代码字号；点“管理主题”进管理页', (tester) async {
      await boot(tester, (_) => const AppearanceScreen());
      expect(k('appearance-themes-manage'), findsOneWidget);
      expect(tester.getTopLeft(k('appearance-themes-manage')).dy, greaterThan(tester.getTopLeft(k('appearance-theme-dark')).dy));
      // 背景图片已经接上（2026-11-26 合并）：一行“背景图片”，排在主题和代码字号之间，右边是当前状态
      expect(k('appearance-background'), findsOneWidget);
      expect(tester.getTopLeft(k('appearance-background')).dy, greaterThan(tester.getTopLeft(k('appearance-themes-manage')).dy));
      expect(tester.getTopLeft(k('appearance-background')).dy, lessThan(tester.getTopLeft(find.byType(CodeFontGroup)).dy));
      expect(find.descendant(of: k('appearance-background'), matching: find.text('未设置')), findsOneWidget);
      await shot(tester, 'appearance-light');
      await tester.tap(k('appearance-themes-manage'));
      await tester.pumpAndSettle();
      expect(find.byType(ThemesScreen), findsOneWidget);
    });
  });

  group('主题管理页', () {
    testWidgets('按浅色 / 深色分开列；点卡片立刻选用；“正在使用”跟着走', (tester) async {
      final env = await boot(tester, (_) => const ThemesScreen());
      final a = await mine(tester, env, name: '海边');
      final d = await mine(tester, env, dark: true, name: '夜里');
      await tester.pumpAndSettle();

      expect(k('themes-card-$kDefaultLightThemeId'), findsOneWidget);
      expect(k('themes-card-${a.id}'), findsOneWidget);
      expect(k('themes-card-${d.id}'), findsNothing, reason: '深色的不在浅色这一段');
      expect(tester.widget<Text>(k('themes-source-$kDefaultLightThemeId')).data, '内置');
      expect(tester.widget<Text>(k('themes-source-${a.id}')).data, '我的');
      expect(k('themes-inuse-$kDefaultLightThemeId'), findsOneWidget);
      expect(k('theme-mini-${a.id}'), findsOneWidget);

      await tester.tap(k('themes-card-${a.id}'));
      await io(tester);
      expect(env.services.settings.getString(SettingKeys.themeLight), a.id);
      expect(k('themes-inuse-${a.id}'), findsOneWidget);
      expect(k('themes-inuse-$kDefaultLightThemeId'), findsNothing);
      await shot(tester, 'themes-light');

      await tester.tap(find.text('深色'));
      await tester.pumpAndSettle();
      expect(k('themes-card-${d.id}'), findsOneWidget);
      expect(k('themes-card-${a.id}'), findsNothing);
      expect(k('themes-inuse-$kDefaultDarkThemeId'), findsOneWidget);
      await tester.tap(k('themes-card-${d.id}'));
      await io(tester);
      expect(env.services.settings.getString(SettingKeys.themeDark), d.id);
      expect(env.services.settings.getString(SettingKeys.themeLight), a.id, reason: '浅色那边选的不受影响');
    });

    testWidgets('深色模式下进来停在深色那一段（截图）', (tester) async {
      final env = await boot(tester, (_) => const ThemesScreen(), mode: ThemeMode.dark);
      await mine(
        tester,
        env,
        dark: true,
        name: '夜里',
        make: (t) => generateTheme(dark: true, tint: 0xFF4B3A7A, accent: 0xFFB388FF, shell: t),
      );
      await tester.pumpAndSettle();
      expect(k('themes-card-$kDefaultDarkThemeId'), findsOneWidget);
      expect(k('themes-card-$kDefaultLightThemeId'), findsNothing);
      await shot(tester, 'themes-dark');
    });

    testWidgets('“⋯”：内置只有看 / 复制一份来改 / 导出；我的有编辑、改名、复制、导出、删除', (tester) async {
      final env = await boot(tester, (_) => const ThemesScreen());
      final a = await mine(tester, env);
      await tester.pumpAndSettle();

      await tester.tap(k('themes-more-$kDefaultLightThemeId'));
      await tester.pumpAndSettle();
      for (final id in ['view', 'copy-edit', 'export']) {
        expect(k('themes-act-$id'), findsOneWidget);
      }
      for (final id in ['edit', 'rename', 'delete', 'copy']) {
        expect(k('themes-act-$id'), findsNothing);
      }
      await shot(tester, 'themes-more-builtin');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      await tester.tap(k('themes-more-${a.id}'));
      await tester.pumpAndSettle();
      for (final id in ['edit', 'rename', 'copy', 'export', 'delete']) {
        expect(k('themes-act-$id'), findsOneWidget);
      }
      await shot(tester, 'themes-more-mine');

      // 改名
      await tester.tap(k('themes-act-rename'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '山里');
      await tester.tap(find.text('改名').last);
      await io(tester);
      expect(viewOf(env).byId(a.id)!.name, '山里');
      expect(find.text('山里'), findsOneWidget);

      // 复制一份
      await tester.tap(k('themes-more-${a.id}'));
      await tester.pumpAndSettle();
      await tester.tap(k('themes-act-copy'));
      await io(tester);
      expect(viewOf(env).user.length, 2);
      expect(viewOf(env).user.map((t) => t.name), contains('山里 副本'));
      expect(find.byType(ThemeEditorScreen), findsNothing, reason: '“复制一份”只复制，不进编辑器');

      // 删除：先取消，再确认；正在用的删了退回默认
      await tester.tap(k('themes-card-${a.id}'));
      await io(tester);
      expect(env.services.settings.getString(SettingKeys.themeLight), a.id);
      await tester.tap(k('themes-more-${a.id}'));
      await tester.pumpAndSettle();
      await tester.tap(k('themes-act-delete'));
      await tester.pumpAndSettle();
      expect(find.textContaining('这套正在用'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await io(tester);
      expect(viewOf(env).byId(a.id), isNotNull, reason: '点了取消不该删');
      await tester.tap(k('themes-more-${a.id}'));
      await tester.pumpAndSettle();
      await tester.tap(k('themes-act-delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除').last);
      await io(tester);
      expect(viewOf(env).byId(a.id), isNull);
      expect(k('themes-card-${a.id}'), findsNothing);
      expect(viewOf(env).light.id, kDefaultLightThemeId);
      expect(k('themes-inuse-$kDefaultLightThemeId'), findsOneWidget);
    });

    testWidgets('新建主题：先问从哪套开始，复制一份、直接进编辑器；内置的“复制一份来改”也进编辑器', (tester) async {
      final env = await boot(tester, (_) => const ThemesScreen());
      await tester.tap(k('themes-new'));
      await tester.pumpAndSettle();
      expect(k('themes-from-$kDefaultLightThemeId'), findsOneWidget);
      expect(k('themes-from-$kDefaultDarkThemeId'), findsNothing);
      await shot(tester, 'themes-new-from');
      await tester.tap(k('themes-from-$kDefaultLightThemeId'));
      await io(tester);
      expect(find.byType(ThemeEditorScreen), findsOneWidget);
      expect(viewOf(env).user.single.name, '我的浅色主题');
      expect(viewOf(env).user.single.builtin, isFalse);
      expect(k('theme-readonly-banner'), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(ThemeEditorScreen), findsNothing);
      expect(k('themes-card-${viewOf(env).user.single.id}'), findsOneWidget);

      await tester.tap(k('themes-more-$kDefaultLightThemeId'));
      await tester.pumpAndSettle();
      await tester.tap(k('themes-act-copy-edit'));
      await io(tester);
      expect(find.byType(ThemeEditorScreen), findsOneWidget);
      expect(viewOf(env).user.length, 2);
    });
  });

  group('主题编辑器', () {
    testWidgets('改一个颜色：行和预览跟着变、全应用不变；保存后才生效；撤销 / 重做', (tester) async {
      late ThemeSpec t;
      final env = await boot(
        tester,
        (env) => ThemeEditorScreen(theme: t),
        before: (env) async {
          t = (await themesOf(env).create(dark: false, name: '海边')).theme!;
          await themesOf(env).select(t.id);
        },
      );
      expect(previewSpec(tester, 'ui').ui[UiKey.bg], t.ui[UiKey.bg]);
      expect(k('theme-save'), findsNothing, reason: '没改动时没有保存按钮');
      await shot(tester, 'editor-ui-light');

      await openItem(tester, 'ui.bg');
      expect(k('color-hex'), findsOneWidget);
      await typeHex(tester, '#102030');
      expect(tester.widget<Text>(k('theme-item-ui.bg-value')).data, '#102030');
      expect(k('theme-item-ui.bg-changed'), findsOneWidget);
      expect(previewSpec(tester, 'ui').ui[UiKey.bg], 0xFF102030, reason: '预览用的是正在改的这份');
      expect(viewOf(env).light.ui[UiKey.bg], t.ui[UiKey.bg], reason: '没保存，全应用不该变');
      // 一次打开面板里改几回，只算一步撤销。
      await typeHex(tester, '#203040');
      await tester.tap(k('color-done'));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(k('theme-item-ui.bg-value')).data, '#203040');
      expect(tester.widget<Text>(k('theme-section-ui-count')).data, startsWith('改了 1 项'));

      await tester.tap(k('theme-undo'));
      await tester.pumpAndSettle();
      expect(previewSpec(tester, 'ui').ui[UiKey.bg], t.ui[UiKey.bg], reason: '撤销一下就回到打开面板之前');
      expect(k('theme-save'), findsNothing);
      await tester.tap(k('theme-redo'));
      await tester.pumpAndSettle();
      expect(previewSpec(tester, 'ui').ui[UiKey.bg], 0xFF203040);

      expect(find.text('保存（改了 1 项）'), findsOneWidget);
      await tester.tap(k('theme-save'));
      await io(tester);
      expect(viewOf(env).byId(t.id)!.ui[UiKey.bg], 0xFF203040);
      expect(viewOf(env).light.ui[UiKey.bg], 0xFF203040, reason: '正在用的这套保存后全应用换上');
      expect(k('theme-save'), findsNothing);
      expect(k('theme-item-ui.bg-changed'), findsNothing, reason: '保存以后这份成了新的起点');
      // 保存以后可以直接离开，不再问。
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('改动还没保存'), findsNothing);
    });

    testWidgets('五种预览可以切；点某一项时自动切到它所在的那种（深色截图）', (tester) async {
      late ThemeSpec t;
      await boot(
        tester,
        (env) => ThemeEditorScreen(theme: t),
        mode: ThemeMode.dark,
        before: (env) async => t = (await themesOf(env).create(dark: true, name: '夜里')).theme!,
      );
      expect(k('theme-preview-ui'), findsOneWidget);
      await shot(tester, 'editor-ui-dark');
      for (final (label, kind) in [('代码', 'code'), ('积木', 'blocks'), ('搭建', 'lowcode'), ('终端', 'terminal')]) {
        await tester.tap(find.descendant(of: k('theme-preview-kind'), matching: find.text(label)));
        await tester.pumpAndSettle();
        expect(k('theme-preview-$kind'), findsOneWidget);
        expect(previewSpec(tester, kind).id, t.id);
        await shot(tester, 'editor-$kind-dark');
      }
      expect(k('theme-preview-ansi-red'), findsOneWidget);

      await tester.tap(k('theme-section-ui'));
      await tester.pumpAndSettle();
      await tester.tap(k('theme-section-tokens'));
      await tester.pumpAndSettle();
      await openItem(tester, 'tokens.keyword');
      expect(k('theme-preview-code'), findsOneWidget, reason: '改高亮时预览自动切到代码');
      await shot(tester, 'editor-color-sheet-dark');
    });

    testWidgets('没保存就离开要问：继续编辑 / 不保存 / 保存并离开', (tester) async {
      late ThemeSpec t;
      final env = await boot(tester, (env) => const ThemesScreen(), before: (env) async => t = (await themesOf(env).create(dark: false, name: '海边')).theme!);
      Future<void> openAndChange(String hex) async {
        await tester.tap(k('themes-more-${t.id}'));
        await tester.pumpAndSettle();
        await tester.tap(k('themes-act-edit'));
        await tester.pumpAndSettle();
        await openItem(tester, 'ui.bg');
        await typeHex(tester, hex);
        await tester.tap(k('color-done'));
        await tester.pumpAndSettle();
      }

      await openAndChange('#112233');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('改动还没保存'), findsOneWidget);
      await shot(tester, 'editor-leave-confirm');
      await tester.tap(k('theme-leave-stay'));
      await tester.pumpAndSettle();
      expect(find.byType(ThemeEditorScreen), findsOneWidget);
      expect(tester.widget<Text>(k('theme-item-ui.bg-value')).data, '#112233', reason: '继续编辑：改动还在');

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(k('theme-leave-discard'));
      await io(tester);
      expect(find.byType(ThemeEditorScreen), findsNothing);
      expect(viewOf(env).byId(t.id)!.ui[UiKey.bg], t.ui[UiKey.bg], reason: '不保存：存着的那份没变');

      await openAndChange('#445566');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(k('theme-leave-save'));
      await io(tester);
      expect(find.byType(ThemeEditorScreen), findsNothing);
      expect(viewOf(env).byId(t.id)!.ui[UiKey.bg], 0xFF445566);
    });

    testWidgets('内置主题只读：有说明，点行不开取色面板，加减是灰的；“复制一份来改”换成能改的副本', (tester) async {
      final env = await boot(tester, (_) => ThemeEditorScreen(theme: kDefaultLightTheme));
      expect(k('theme-readonly-banner'), findsOneWidget);
      expect(k('theme-editor-more'), findsNothing);
      expect(k('theme-quick-accent'), findsNothing);
      await tester.tap(k('theme-item-ui.bg'));
      await tester.pumpAndSettle();
      expect(k('color-hex'), findsNothing);
      expect(find.textContaining('内置主题不能直接改'), findsOneWidget);
      await tester.tap(k('theme-section-ui'));
      await tester.pumpAndSettle();
      await tester.tap(k('theme-section-metrics'));
      await tester.pumpAndSettle();
      expect(tester.widget<IconButton>(k('theme-metric-${MetricKey.radiusScale}-plus')).onPressed, isNull);
      await shot(tester, 'editor-readonly');

      await tester.tap(k('theme-copy-to-edit'));
      await io(tester);
      expect(viewOf(env).user.single.name, '默认浅色 副本');
      expect(k('theme-readonly-banner'), findsNothing);
      expect(k('theme-editor-more'), findsOneWidget);
      await tester.tap(k('theme-item-ui.bg'));
      await tester.pumpAndSettle();
      expect(k('color-hex'), findsOneWidget);
    });

    testWidgets('数用加减改、到头变灰；高亮分类能开关粗体 / 斜体；搜索和“改过的”', (tester) async {
      late ThemeSpec t;
      await boot(tester, (env) => ThemeEditorScreen(theme: t), before: (env) async => t = (await themesOf(env).create(dark: false)).theme!);
      // 默认只展开“界面”；收起它，展开“形状与密度”。
      await tester.tap(k('theme-section-ui'));
      await tester.pumpAndSettle();
      expect(k('theme-item-ui.bg'), findsNothing);
      await tester.tap(k('theme-section-metrics'));
      await tester.pumpAndSettle();
      const key = MetricKey.radiusScale;
      final before = t.metric(key);
      await tester.tap(k('theme-metric-$key-plus'));
      await tester.pumpAndSettle();
      expect(previewSpec(tester, 'ui').metric(key), closeTo(before + 0.1, 1e-9));
      for (var i = 0; i < 40; i++) {
        final b = tester.widget<IconButton>(k('theme-metric-$key-minus'));
        if (b.onPressed == null) break;
        await tester.tap(k('theme-metric-$key-minus'));
        await tester.pump();
      }
      expect(tester.widget<IconButton>(k('theme-metric-$key-minus')).onPressed, isNull, reason: '到最小值了，减号变灰');
      expect(previewSpec(tester, 'ui').metric(key), kMetricFields.firstWhere((f) => f.key == key).min);
      await shot(tester, 'editor-metrics');
      await tester.tap(k('theme-section-metrics'));
      await tester.pumpAndSettle();

      // 搜索：所有组摊开，只剩对得上的。
      await tester.enterText(k('theme-search'), '关键字');
      await tester.pumpAndSettle();
      expect(k('theme-item-tokens.keyword'), findsOneWidget);
      expect(k('theme-item-ui.bg'), findsNothing);
      expect(k('theme-quick-accent'), findsNothing);
      final wasBold = t.tokens['keyword']?.bold ?? false;
      await tester.tap(k('theme-item-tokens.keyword-bold'));
      await tester.pumpAndSettle();
      expect(previewSpec(tester, 'ui').tokens['keyword']!.bold, !wasBold);
      await tester.tap(k('theme-item-tokens.keyword-italic'));
      await tester.pumpAndSettle();
      expect(previewSpec(tester, 'ui').tokens['keyword']!.italic, isTrue);
      await shot(tester, 'editor-search');

      await tester.enterText(k('theme-search'), '根本没有这一项');
      await tester.pumpAndSettle();
      expect(k('theme-empty'), findsOneWidget);
      await tester.tap(k('theme-search-clear'));
      await tester.pumpAndSettle();

      // 只看改过的：圆角的数 + 关键字这一类。
      await tester.tap(k('theme-only-changed'));
      await tester.pumpAndSettle();
      expect(k('theme-metric-$key'), findsOneWidget);
      expect(k('theme-item-tokens.keyword'), findsOneWidget);
      expect(k('theme-item-tokens.comment'), findsNothing);
      expect(find.text('改过的 2'), findsOneWidget);
      await shot(tester, 'editor-only-changed');
    });

    testWidgets('对比度：有偏低的项时顶上有提示，点开列表能跳到那一项；“自动调到达标”可撤销；只提示不拦保存', (tester) async {
      late ThemeSpec t;
      final env = await boot(
        tester,
        (env) => ThemeEditorScreen(theme: t),
        before: (env) async {
          final made = (await themesOf(env).create(dark: false, name: '太淡')).theme!;
          // 先把默认主题的缺口都修掉，再故意把注释调得和代码底色几乎一样。
          final clean = repairContrast(made);
          await themesOf(env).save(clean.withToken('comment', TokenStyle(color: clean.code[CodeKey.bg]! - 0x00050505)));
          t = viewOf(env).byId(made.id)!;
        },
      );
      final issues = checkThemeContrast(t);
      expect(issues.map((i) => i.id), contains('tokens.comment/code.bg'));
      expect(find.text('${issues.length} 项对比度偏低'), findsOneWidget);
      await shot(tester, 'editor-contrast-banner');

      await tester.tap(k('theme-contrast-banner'));
      await tester.pumpAndSettle();
      expect(k('theme-contrast-tokens.comment/code.bg'), findsOneWidget);
      await shot(tester, 'editor-contrast-list');
      await tester.tap(k('theme-contrast-tokens.comment/code.bg'));
      await tester.pumpAndSettle();
      expect(k('theme-item-tokens.comment'), findsOneWidget, reason: '跳到了那一项（它那一组被展开、滚到了看得见的地方）');
      expect(k('theme-item-tokens.comment-low'), findsOneWidget);

      // 取色面板里写着对比度多少、偏低。
      await tester.tap(k('theme-item-tokens.comment'));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(k('color-contrast-text')).data, allOf(contains('偏低'), contains('至少 ')));
      await shot(tester, 'editor-color-sheet-low');
      await tester.tap(k('color-done'));
      await tester.pumpAndSettle();

      // 不拦保存：改一下别的，照样能存。
      await tester.tap(k('theme-item-tokens.comment-italic'));
      await tester.pumpAndSettle();
      await tester.tap(k('theme-save'));
      await io(tester);
      expect(viewOf(env).byId(t.id)!.tokens['comment']!.italic, !(t.tokens['comment']!.italic));

      // 自动调到达标。
      await tester.tap(k('theme-contrast-banner'));
      await tester.pumpAndSettle();
      await tester.tap(k('theme-contrast-fix'));
      await tester.pumpAndSettle();
      expect(k('theme-contrast-banner'), findsNothing);
      expect(checkThemeContrast(previewSpec(tester, 'code')), isEmpty);
      await tester.tap(k('theme-undo'));
      await tester.pumpAndSettle();
      expect(k('theme-contrast-banner'), findsOneWidget, reason: '自动调的那一步可以撤销');
    });

    testWidgets('取色面板：十六进制容错、看不懂时说明、恢复默认值、最近用过、拖方块', (tester) async {
      late ThemeSpec t;
      final env = await boot(tester, (env) => ThemeEditorScreen(theme: t), before: (env) async => t = (await themesOf(env).create(dark: false)).theme!);
      int now() => previewSpec(tester, 'ui').ui[UiKey.accent]!;
      await openItem(tester, 'ui.accent');
      await shot(tester, 'editor-color-sheet-light');

      for (final (text, want) in [('00aa55', 0xFF00AA55), ('  ＃FA0 ', 0xFFFFAA00), ('0x336699', 0xFF336699), ('rgb(1, 2, 3)', 0xFF010203)]) {
        await typeHex(tester, text);
        expect(now(), want, reason: '“$text” 应该认得出来');
      }
      // 这一项不能带透明度：写了也按不透明的用，并说明。
      await typeHex(tester, '#80112233');
      expect(now(), 0xFF112233);
      expect(find.textContaining('不能带透明度'), findsOneWidget);
      expect(k('color-alpha'), findsNothing);
      // 看不懂：说明原因，颜色不动。
      await typeHex(tester, '蓝色');
      expect(find.textContaining('看不懂这个颜色'), findsOneWidget);
      expect(now(), 0xFF112233);

      // 拖饱和 × 明度的方块：颜色跟着变。
      final sv = tester.getRect(k('color-sv'));
      await tester.ensureVisible(k('color-sv'));
      await tester.tapAt(tester.getRect(k('color-sv')).center);
      await tester.pump();
      expect(now(), isNot(0xFF112233));
      expect(sv.height, 132);

      // 点一个常用色。
      await tester.ensureVisible(k('color-common-12'));
      await tester.tap(k('color-common-12'));
      await tester.pump();
      expect(now(), 0xFF058654);

      // 恢复默认值。
      await tester.tap(k('color-reset-default'));
      await tester.pump();
      expect(now(), kDefaultLightTheme.ui[UiKey.accent]);
      expect(tester.widget<TextButton>(k('color-reset-default')).onPressed, isNull, reason: '已经是默认值了');

      await typeHex(tester, '#7C4DFF');
      await tester.tap(k('color-done'));
      await io(tester);
      expect(env.services.container.read(recentColorsProvider), [0xFF7C4DFF], reason: '关面板时记下最后定的那个颜色');

      // 再开别的项：有“最近用过”，点它就用上。
      await openItem(tester, 'ui.link');
      await tester.ensureVisible(k('color-recent-0'));
      await tester.tap(k('color-recent-0'));
      await tester.pump();
      expect(previewSpec(tester, 'ui').ui[UiKey.link], 0xFF7C4DFF);
      await shot(tester, 'editor-color-sheet-recent');
    });

    testWidgets('允许透明的项有透明度条；高亮分类可以“不单独上色”', (tester) async {
      late ThemeSpec t;
      await boot(tester, (env) => ThemeEditorScreen(theme: t), before: (env) async => t = (await themesOf(env).create(dark: false)).theme!);
      final soft = kThemeItems.firstWhere((i) => i.section == 'ui' && itemAllowsAlpha(i));
      await openItem(tester, soft.id);
      expect(k('color-alpha'), findsOneWidget);
      await typeHex(tester, '#40102030');
      expect(previewSpec(tester, 'ui').ui[soft.key], 0x40102030);
      // 把透明度条拖到最右边（拖过头也算到头）：变成不透明。
      await tester.ensureVisible(k('color-alpha'));
      final bar = tester.getRect(k('color-alpha'));
      await tester.dragFrom(bar.center, const Offset(400, 0));
      await tester.pump();
      expect(previewSpec(tester, 'ui').ui[soft.key]! >> 24, 0xFF);
      // 在方块里上下拖是调明度，不是滚面板（方块在一个能上下滚的面板里，这里守着它不被抢走）。
      await tester.ensureVisible(k('color-sv'));
      final sv = tester.getRect(k('color-sv'));
      await tester.dragFrom(sv.topRight + const Offset(-10, 10), const Offset(0, 300));
      await tester.pump();
      expect(previewSpec(tester, 'ui').ui[soft.key]! & 0xFFFFFF, 0, reason: '拖到方块最下面＝明度 0＝黑');
      expect(tester.getRect(k('color-sv')), sv, reason: '面板没有跟着滚');
      await tester.tap(k('color-done'));
      await tester.pumpAndSettle();

      tester.state<ScrollableState>(find.descendant(of: k('theme-editor-list'), matching: find.byType(Scrollable)).first).position.jumpTo(0);
      await tester.pumpAndSettle();
      await tester.tap(k('theme-section-ui'));
      await tester.pumpAndSettle();
      await tester.tap(k('theme-section-tokens'));
      await tester.pumpAndSettle();
      await openItem(tester, 'tokens.keyword');
      expect(k('color-clear'), findsOneWidget);
      await tester.tap(k('color-clear'));
      await tester.pump();
      expect(previewSpec(tester, 'code').tokens['keyword']!.color, isNull);
      await tester.tap(k('color-done'));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(k('theme-item-tokens.keyword-value')).data, '跟着代码文字的颜色');
    });

    testWidgets('快捷生成：换强调色一组一起变、取消就退回；从主色生成整套；改名；全部恢复为起点', (tester) async {
      late ThemeSpec t;
      final env = await boot(
        tester,
        (env) => ThemeEditorScreen(theme: t),
        before: (env) async => t = (await themesOf(env).create(dark: false, name: '海边')).theme!,
      );
      ThemeSpec now() => previewSpec(tester, 'ui');

      await tester.tap(k('theme-quick-accent'));
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(k('gen-apply')).onPressed, isNull, reason: '没动过时“用这个”是灰的');
      await typeHex(tester, '#C2185B', field: 'gen-hex');
      expect(now().ui[UiKey.accentFill], 0xFFC2185B, reason: '边挑边看');
      expect(now(), reaccentTheme(t, 0xFFC2185B));
      await shot(tester, 'editor-reaccent');
      await tester.tap(k('gen-cancel'));
      await tester.pumpAndSettle();
      expect(now(), t, reason: '取消：退回打开之前');
      expect(k('theme-save'), findsNothing);

      await tester.tap(k('theme-quick-accent'));
      await tester.pumpAndSettle();
      await typeHex(tester, '#C2185B', field: 'gen-hex');
      await tester.tap(k('gen-apply'));
      await tester.pumpAndSettle();
      expect(now().ui[UiKey.accentFill], 0xFFC2185B);
      expect(now().ui[UiKey.accentSoft], isNot(t.ui[UiKey.accentSoft]));

      // 从主色生成整套（走“⋯”菜单）。
      await tester.tap(k('theme-editor-more'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('从主色生成整套').last);
      await tester.pumpAndSettle();
      await typeHex(tester, '#00897B', field: 'gen-hex');
      await tester.tap(find.text('底色倾向'));
      await tester.pumpAndSettle();
      await typeHex(tester, '#FFE0B2', field: 'gen-hex');
      await shot(tester, 'editor-generate');
      await tester.tap(k('gen-apply'));
      await tester.pumpAndSettle();
      final made = now();
      // 青绿配白字：按钮底是同一个色相、压深到白字够清楚为止。
      expect(made.ui[UiKey.onAccent], 0xFFFFFFFF);
      expect(made.ui[UiKey.accentFill], reaccentTheme(kDefaultLightTheme, 0xFF00897B).ui[UiKey.accentFill]);
      expect(made.ui[UiKey.accentFill], isNot(t.ui[UiKey.accentFill]));
      expect(made.ui[UiKey.canvas], isNot(t.ui[UiKey.canvas]), reason: '底色带上了倾向');
      expect(decodeThemeText(encodeThemeText(made)).ok, isTrue, reason: '生成的整套能过格式校验');
      expect(made.id, t.id);
      // 一次生成只算一步。
      await tester.tap(k('theme-undo'));
      await tester.pumpAndSettle();
      expect(now().ui[UiKey.accentFill], 0xFFC2185B);
      await tester.tap(k('theme-redo'));
      await tester.pumpAndSettle();

      // 改名：立刻存名字，不动没保存的颜色。
      await tester.tap(k('theme-editor-more'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('改名').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '青绿');
      await tester.tap(find.text('改名').last);
      await io(tester);
      expect(viewOf(env).byId(t.id)!.name, '青绿');
      expect(viewOf(env).byId(t.id)!.ui[UiKey.accentFill], t.ui[UiKey.accentFill], reason: '改名不把没保存的颜色带进去');
      expect(find.text('青绿'), findsOneWidget);
      expect(now(), made.copyWith(name: '青绿'), reason: '改名不动草稿里别的东西（按钮底是算过、压深了的青绿，不是输进去的原值）');

      // 全部恢复为起点。
      await tester.tap(k('theme-editor-more'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('全部恢复为起点').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('恢复').last);
      await tester.pumpAndSettle();
      expect(now(), t.copyWith(name: '青绿'));
      expect(k('theme-save'), findsNothing);
      await tester.tap(k('theme-undo'));
      await tester.pumpAndSettle();
      expect(now(), made.copyWith(name: '青绿'), reason: '恢复这一步也能撤销');
    });
  });

  group('导出', () {
    testWidgets('复制到剪贴板的文本能被导入还原（往返一致）；没接背景图时没有“附带背景图”', (tester) async {
      late ThemeSpec t;
      await boot(
        tester,
        (env) => Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: ThemeExportSheet(theme: t),
          ),
        ),
        before: (env) async {
          final made = (await themesOf(env).create(dark: true, name: '夜里')).theme!;
          await themesOf(env).save(generateTheme(dark: true, tint: 0xFF4B3A7A, accent: 0xFFB388FF, shell: made).withMetric(MetricKey.radiusScale, 1.4));
          t = viewOf(env).byId(made.id)!;
        },
      );
      expect(k('theme-export-with-image'), findsNothing);
      expect(tester.widget<Text>(k('theme-export-size')).data, startsWith('大小：'));
      await tester.tap(k('theme-export-copy'));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(k('theme-export-note')).data, contains('已复制'));
      final back = decodeThemeText(clipboard);
      expect(back.ok, isTrue, reason: back.error);
      expect(back.notes, isEmpty);
      expect(back.theme!.copyWith(id: t.id), t, reason: '导出再导入，每一个值都一样');
      await shot(tester, 'export-sheet');
    });

    testWidgets('存成文件：没有工作区时说明原因；有工作区时写进它的 exports/', (tester) async {
      late ThemeSpec t;
      final env = await boot(
        tester,
        (env) => Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: ThemeExportSheet(theme: t),
          ),
        ),
        before: (env) async => t = (await themesOf(env).create(dark: false, name: '海 边/1')).theme!,
      );
      await tester.tap(k('theme-export-save'));
      await io(tester);
      expect(tester.widget<Text>(k('theme-export-note')).data, contains('一个工作区都没有'));

      late String dir;
      await tester.runAsync(() async => dir = (await env.services.projects.create('demo', ProjectTemplate.empty)).dir);
      await tester.tap(k('theme-export-save'));
      await io(tester);
      final note = tester.widget<Text>(k('theme-export-note')).data!;
      expect(note, contains('已存到工作区“demo”的 exports/主题-海-边1-'));
      late List<File> files;
      late String text;
      await tester.runAsync(() async {
        files = Directory('$dir/exports').listSync().whereType<File>().toList();
        text = files.single.readAsStringSync();
      });
      expect(files.single.path, endsWith(kThemeFileSuffix));
      expect(decodeThemeText(text).theme!.copyWith(id: t.id), t);
      await shot(tester, 'export-saved');
    });

    testWidgets('背景图那部分接上并且设了图：有“附带背景图”，打开后文本里带 background；取不出来时说明原因', (tester) async {
      late ThemeSpec t;
      var fail = false;
      // 1×1 的 PNG。
      const png = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';
      final bridge = ThemeBackgroundBridge(
        hasImage: ({required dark}) => true,
        export: ({required dark}) async => fail ? const ThemeBackgroundExport(error: '图片文件不见了') : const ThemeBackgroundExport(data: {'mime': 'image/png', 'data': png, 'dim': 0.2, 'turns': 1}),
        import: (_, {required dark}) async => null,
      );
      await boot(
        tester,
        (env) => ProviderScope(
          overrides: [themeBackgroundBridgeProvider.overrideWithValue(bridge)],
          child: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: ThemeExportSheet(theme: t),
            ),
          ),
        ),
        before: (env) async => t = (await themesOf(env).create(dark: false, name: '海边')).theme!,
      );
      expect(k('theme-export-with-image'), findsOneWidget);
      await tester.tap(k('theme-export-with-image'));
      await io(tester);
      await tester.tap(k('theme-export-copy'));
      await tester.pumpAndSettle();
      expect((jsonDecode(clipboard) as Map)['background'], isA<Map<String, dynamic>>());
      final back = decodeThemeText(clipboard);
      expect(back.ok, isTrue, reason: back.error);
      expect(back.background, isNotNull);
      expect(back.background!.mime, 'image/png');
      await shot(tester, 'export-with-image');

      await tester.tap(k('theme-export-with-image'));
      await io(tester);
      fail = true;
      await tester.tap(k('theme-export-with-image'));
      await io(tester);
      expect(tester.widget<Text>(k('theme-export-note')).data, '图片文件不见了');
      expect(tester.widget<SwitchListTile>(k('theme-export-with-image')).value, isFalse);
      await tester.tap(k('theme-export-copy'));
      await tester.pumpAndSettle();
      expect((jsonDecode(clipboard) as Map).containsKey('background'), isFalse);
    });
  });

  group('导入', () {
    testWidgets('坏文本各有一句人话；没字时“检查并预览”是灰的；剪贴板是空的也说明', (tester) async {
      final env = await boot(tester, (_) => const ThemeImportScreen());
      expect(tester.widget<FilledButton>(k('theme-import-check')).onPressed, isNull);
      await tester.tap(k('theme-import-paste'));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(k('theme-import-error')).data, contains('剪贴板里现在没有文字'));

      final good = encodeTheme(kDefaultLightTheme.copyWith(name: '别人给的'));
      final bad = <String>[
        '这不是主题',
        '[1, 2, 3]',
        '{"format": "别的东西", "version": 1}',
        jsonEncode({...good, 'version': 99}),
        jsonEncode({
          ...good,
          'theme': {
            ...(good['theme']! as Map),
            'ui': {'bg': '不是颜色'},
          },
        }),
        jsonEncode({
          ...good,
          'theme': {...(good['theme']! as Map), 'name': ''},
        }),
      ];
      final seen = <String>{};
      for (final text in bad) {
        await tester.enterText(k('theme-import-text'), text);
        await tester.pump();
        await tester.tap(k('theme-import-check'));
        await tester.pumpAndSettle();
        expect(find.byType(ThemeImportPreviewScreen), findsNothing, reason: '坏文本不该进预览：$text');
        final said = tester.widget<Text>(k('theme-import-error')).data!;
        expect(said, decodeThemeText(text).error);
        expect(said, isNot(contains('Exception')));
        expect(said, isNot(contains('FormatException')));
        seen.add(said);
      }
      expect(seen.length, greaterThanOrEqualTo(4), reason: '不同的毛病说的话不一样');
      await shot(tester, 'import-error');
      expect(viewOf(env).user, isEmpty, reason: '坏文本一套都不该加进来');
      // 改了字，旧的报错就收起来。
      await tester.enterText(k('theme-import-text'), '{');
      await tester.pump();
      expect(k('theme-import-error'), findsNothing);
    });

    testWidgets('粘贴好的文本 → 导入预览：名字、作者、明暗、四种预览、对比度、提示；“加入我的主题”只加不选用，重名自动改名', (tester) async {
      final src = generateTheme(dark: true, tint: 0xFF1B3A4B, accent: 0xFF4DD0E1).copyWith(name: '深海', author: () => '闯闯');
      final json = encodeTheme(src);
      clipboard = jsonEncode({
        ...json,
        '多出来的': 1,
        'theme': {...(json['theme']! as Map), 'lowcode': <String, Object?>{}},
      });
      final env = await boot(tester, (_) => const ThemesScreen(), before: (env) async => themesOf(env).importText(encodeThemeText(src)));
      await tester.tap(k('themes-import'));
      await tester.pumpAndSettle();
      await tester.tap(k('theme-import-paste'));
      await tester.pumpAndSettle();
      await shot(tester, 'import-paste');
      await tester.tap(k('theme-import-check'));
      await tester.pumpAndSettle();

      expect(find.byType(ThemeImportPreviewScreen), findsOneWidget);
      expect(tester.widget<Text>(k('theme-import-name')).data, '深海');
      expect(tester.widget<Text>(k('theme-import-meta')).data, '作者 闯闯 · 深色主题');
      expect(k('theme-preview-ui'), findsOneWidget);
      final decoded = decodeThemeText(clipboard);
      expect(decoded.notes, isNotEmpty, reason: '这份文本多了字段、少了一节，检查时应该有提示');
      expect(tester.widget<Text>(k('theme-import-note-0')).data, decoded.notes.first);
      expect(tester.widget<Text>(k('theme-import-contrast')).data, checkThemeContrast(decoded.theme!).isEmpty ? contains('都达标') : contains('项对比度偏低'));
      expect(tester.widget<Text>(k('theme-import-image')).data, contains('没带背景图'));
      await shot(tester, 'import-preview-dark-theme');
      for (final (label, kind) in [('代码', 'code'), ('积木', 'blocks'), ('搭建', 'lowcode'), ('终端', 'terminal')]) {
        await tester.tap(find.descendant(of: k('theme-import-kind'), matching: find.text(label)));
        await tester.pumpAndSettle();
        expect(k('theme-preview-$kind'), findsOneWidget);
      }
      await shot(tester, 'import-preview-terminal');

      await tester.tap(k('theme-import-add'));
      await io(tester, until: find.byType(ThemesScreen));
      expect(find.byType(ThemesScreen), findsOneWidget);
      expect(find.byType(ThemeImportScreen), findsNothing, reason: '加进来以后直接回到管理页');
      expect(viewOf(env).user.map((t) => t.name).toSet(), hasLength(2), reason: '已经有一套“深海”，新的自动改名');
      expect(viewOf(env).dark.id, kDefaultDarkThemeId, reason: '“加入我的主题”不选用');
      expect(find.textContaining('自动改了名'), findsOneWidget);
      // 管理页切到了深色那一段，能看到刚加的。
      expect(k('themes-card-${viewOf(env).user.last.id}'), findsOneWidget);
    });

    testWidgets('“加入并立即使用”：加进来并换上；“取消”什么都不加；对比度偏低的也能加（浅色）', (tester) async {
      clipboard = encodeThemeText(kDefaultLightTheme.copyWith(name: '别人给的', author: () => null));
      final env = await boot(tester, (_) => const ThemesScreen());
      Future<void> toPreview() async {
        await tester.tap(k('themes-import'));
        await tester.pumpAndSettle();
        await tester.tap(k('theme-import-paste'));
        await tester.pumpAndSettle();
        await tester.tap(k('theme-import-check'));
        await tester.pumpAndSettle();
      }

      await toPreview();
      expect(tester.widget<Text>(k('theme-import-meta')).data, '没写作者 · 浅色主题');
      final issues = checkThemeContrast(kDefaultLightTheme);
      expect(tester.widget<Text>(k('theme-import-contrast')).data, contains('${issues.length} 项对比度偏低'));
      await tester.ensureVisible(k('theme-import-issues-more'));
      await shot(tester, 'import-preview-light');
      await tester.tap(k('theme-import-cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(ThemeImportPreviewScreen), findsNothing);
      expect(find.byType(ThemeImportScreen), findsOneWidget, reason: '取消只退一步，粘贴的文本还在');
      expect(viewOf(env).user, isEmpty);

      await tester.tap(k('theme-import-check'));
      await tester.pumpAndSettle();
      await tester.tap(k('theme-import-use'));
      await io(tester, until: find.byType(ThemesScreen));
      expect(viewOf(env).user.single.name, '别人给的');
      expect(viewOf(env).user.single.builtin, isFalse);
      expect(viewOf(env).light.id, viewOf(env).user.single.id);
      expect(find.byType(ThemesScreen), findsOneWidget);
      expect(k('themes-inuse-${viewOf(env).user.single.id}'), findsOneWidget);
    });

    testWidgets('从工作区文件里选：只列 .json、主题文件排前面；选了直接进预览；不是主题的文件说明原因', (tester) async {
      late String dir;
      final env = await boot(
        tester,
        (_) => const ThemeImportScreen(),
        before: (env) async {
          final p = await env.services.projects.create('demo', ProjectTemplate.empty);
          dir = p.dir;
          await writeThemeExport(
            p.guard,
            encodeThemeText(kDefaultDarkTheme.copyWith(name: '文件里的')),
            name: '文件里的',
            now: DateTime(2026, 11, 26, 5, 0, 0),
          );
          File('$dir/package.json').writeAsStringSync('{"name": "demo"}');
          File('$dir/notes.txt').writeAsStringSync('不是 json');
        },
      );
      await tester.tap(k('theme-import-file-pick'));
      await io(tester);
      const themeFile = 'exports/主题-文件里的-20261126-050000.lopitheme.json';
      expect(k('theme-file-$themeFile'), findsOneWidget);
      expect(k('theme-file-package.json'), findsOneWidget);
      expect(k('theme-file-notes.txt'), findsNothing);
      expect(tester.getTopLeft(k('theme-file-$themeFile')).dy, lessThan(tester.getTopLeft(k('theme-file-package.json')).dy));
      await shot(tester, 'import-file-pick');

      await tester.tap(k('theme-file-package.json'));
      await io(tester);
      expect(find.byType(ThemeImportPreviewScreen), findsNothing);
      expect(tester.widget<Text>(k('theme-import-error')).data, decodeThemeText('{"name": "demo"}').error);
      expect(k('theme-import-file'), findsOneWidget, reason: '选了的文件显示成一行，不把内容塞进输入框');

      await tester.tap(k('theme-import-file-pick'));
      await io(tester);
      await tester.tap(k('theme-file-$themeFile'));
      await io(tester);
      expect(find.byType(ThemeImportPreviewScreen), findsOneWidget);
      expect(tester.widget<Text>(k('theme-import-name')).data, '文件里的');
      expect(viewOf(env).user, isEmpty, reason: '只是预览，还没加');
    });

    testWidgets('带背景图的主题，背景图那部分没接上：只说明，照样加入颜色', (tester) async {
      const png = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';
      final text = jsonEncode({
        ...encodeTheme(kDefaultDarkTheme.copyWith(name: '带图的')),
        'background': {'mime': 'image/png', 'data': png, 'dim': 0.3},
      });
      final decoded = decodeThemeText(text);
      expect(decoded.background, isNotNull, reason: decoded.error ?? decoded.notes.join());
      final env = await boot(tester, (_) => ThemeImportPreviewScreen(text: text, result: decoded));
      await tester.scrollUntilVisible(
        k('theme-import-image'),
        200,
        scrollable: find.descendant(of: k('theme-import-preview-scroll'), matching: find.byType(Scrollable)).first,
      );
      expect(tester.widget<Text>(k('theme-import-image')).data, contains('这个版本还用不了背景图'));
      expect(k('theme-import-image-use'), findsNothing);
      await tester.tap(k('theme-import-add'));
      await io(tester, until: find.byType(ThemesScreen));
      expect(viewOf(env).user.single.name, '带图的');
    });

    testWidgets('带背景图的主题，背景图那部分接上了：有勾选，加入时把图交给背景图那边', (tester) async {
      const png = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';
      final text = jsonEncode({
        ...encodeTheme(kDefaultDarkTheme.copyWith(name: '带图的')),
        'background': {'mime': 'image/png', 'data': png, 'dim': 0.3},
      });
      final decoded = decodeThemeText(text);
      expect(decoded.background, isNotNull, reason: decoded.error ?? decoded.notes.join());
      Map<String, Object?>? got;
      final bridge = ThemeBackgroundBridge(
        hasImage: ({required dark}) => false,
        export: ({required dark}) async => const ThemeBackgroundExport(),
        import: (m, {required dark}) async {
          got = m;
          return null;
        },
      );

      await boot(
        tester,
        (_) => ProviderScope(
          overrides: [themeBackgroundBridgeProvider.overrideWithValue(bridge)],
          child: ThemeImportPreviewScreen(text: text, result: decoded),
        ),
      );
      await tester.scrollUntilVisible(
        k('theme-import-image-use'),
        200,
        scrollable: find.descendant(of: k('theme-import-preview-scroll'), matching: find.byType(Scrollable)).first,
      );
      await tester.ensureVisible(k('theme-import-image-use'));
      expect(tester.widget<CheckboxListTile>(k('theme-import-image-use')).value, isTrue);
      await shot(tester, 'import-preview-with-image');
      await tester.tap(k('theme-import-add'));
      await io(tester, until: find.byType(ThemesScreen));
      expect(got, isNotNull);
      expect(got!['mime'], 'image/png');
      expect(got!['data'], png);
      expect(got!['dim'], 0.3);
    });
  });
}
