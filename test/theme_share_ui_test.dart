// 主题导出面板、导入页和导入预览（手机尺寸 390×844）。原在 test/theme_editor_ui_test.dart，2026-11-26 按功能拆出来，断言没变。
//
//   flutter test test/theme_share_ui_test.dart
//   LOPI_SHOTS=1 flutter test test/theme_share_ui_test.dart   # 同时写截图到 docs/screenshots/editor-*.png
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/appearance/theme_builtin.dart';
import 'package:lopicode/appearance/theme_contrast.dart';
import 'package:lopicode/appearance/theme_export_file.dart';
import 'package:lopicode/appearance/theme_fields.dart';
import 'package:lopicode/appearance/theme_generate.dart';
import 'package:lopicode/appearance/theme_json.dart';
import 'package:lopicode/appearance/theme_spec.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/state/theme_hooks.dart';
import 'package:lopicode/theme/tokens.dart' hide ThemeSpec;
import 'package:lopicode/ui/theme_export_sheet.dart';
import 'package:lopicode/ui/theme_import_screen.dart';
import 'package:lopicode/ui/themes_screen.dart';
import 'package:material_ui/material_ui.dart';

import 'support/harness.dart';

import 'support/theme_ui_support.dart';

void main() {
  setUpAll(() async => fontsLoaded = await loadRealFonts());
  useFakeClipboard();

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
