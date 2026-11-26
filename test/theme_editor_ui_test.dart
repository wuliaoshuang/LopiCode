// 主题编辑器、取色面板、快捷生成（手机尺寸 390×844）。外观页 / 管理页在 theme_manage_ui_test.dart，导出 / 导入在 theme_share_ui_test.dart。
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

import 'support/theme_ui_support.dart';

void main() {
  setUpAll(() async => fontsLoaded = await loadRealFonts());
  useFakeClipboard();

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
}
