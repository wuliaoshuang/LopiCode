// “用户自己写库”界面的主题冒烟：十套内置主题，每套把和库有关的状态摆一遍（390×844）——不许抛异常、不许溢出。
// theme_smoke_test.dart 放不下了，单独一个文件。
//   flutter test --no-pub test/theme_lib_smoke_test.dart
//   LOPI_SHOTS=1 LOPI_SHOT_DIR=../preview/lang/a4 flutter test --no-pub test/theme_lib_smoke_test.dart   # 同时出 lib-<主题>-*.png
//
// 覆盖的状态：用了库的文档的画布（帽子串、带口的库积木）、积木盒里库的那一页、“更多”菜单、积木库面板、一个库的面板、
// 导入预览（带手写代码、不许导入）、看手写代码；库文档的画布、“这个库”面板、一块库积木的面板（原地展开、带口）。
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/appearance/theme_builtin.dart';
import 'package:lopicode/backend/backend_lib_build.dart';
import 'package:lopicode/backend/backend_lib_pack.dart';
import 'package:lopicode/backend/backend_lib_store.dart';
import 'package:lopicode/state/themes_state.dart';
import 'package:material_ui/material_ui.dart';

import 'support/backend_lang_blocks.dart';
import 'support/harness.dart';
import 'support/lib_ui.dart';
import 'support/user_libs.dart';

final bool writeShots = Platform.environment['LOPI_SHOTS'] == '1';
final String shotDir = Platform.environment['LOPI_SHOT_DIR'] ?? '.tmp/theme-shots';
bool fontsLoaded = false;

void main() {
  setUpAll(() async => fontsLoaded = await loadRealFonts());

  for (final theme in kBuiltinThemes) {
    final mode = theme.dark ? ThemeMode.dark : ThemeMode.light;

    Future<void> shot(WidgetTester tester, String page) async {
      expect(tester.takeException(), isNull, reason: '${theme.name} · 库 · $page 渲染时出了异常（溢出也算）');
      if (!writeShots || !fontsLoaded) return;
      final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(shotKey));
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        File('$shotDir/lib-${theme.id}-$page.png')
          ..parent.createSync(recursive: true)
          ..writeAsBytesSync(data!.buffer.asUint8List());
      });
    }

    Future<LibUi> open(WidgetTester tester, J doc, {Map<String, List<int>> files = const {}}) => openLibUi(
      tester,
      doc,
      libs: [flowLibDoc()],
      files: files,
      mode: mode,
      font: kTestFont,
      before: (env) async => expect(await env.services.container.read(themesProvider.notifier).select(theme.id), isNull),
    );

    group('${theme.name}（${theme.id}）', () {
      testWidgets('用库的文档：画布、积木盒那一页、菜单、积木库、一个库、导入预览、看代码', (tester) async {
        final built = beLibFiles(parseLangBlocksDocument(checkLibDoc()));
        final ui = await open(
          tester,
          flowUserDoc(),
          files: {
            '带手写.lopilib': beLibPack({...built.files!, 'native/hack.js': 'const cp = require("child_process");\nmodule.exports = () => cp.execSync("ls").toString();\n'}),
          },
        );
        expect(ui.screen.host!.issues.where((i) => i.isError), isEmpty);
        await shot(tester, 'user-canvas');

        final tabs = find.byKey(const ValueKey('bk-palette-tabs'));
        if (tabs.hitTestable().evaluate().isEmpty) {
          await tester.drag(find.byKey(const ValueKey('bk-palette-grip')), const Offset(0, -300), warnIfMissed: false);
          await tester.pumpAndSettle();
        }
        final tab = find.byKey(const ValueKey('bk-palette-tab-lib:$kLibFlow'));
        for (var i = 0; i < 20 && tab.hitTestable().evaluate().isEmpty; i++) {
          await tester.drag(tabs, const Offset(-120, 0));
          await tester.pumpAndSettle();
        }
        await tester.tap(tab);
        await tester.pumpAndSettle();
        await shot(tester, 'user-palette');
        await tester.drag(find.byKey(const ValueKey('bk-palette-grip')), const Offset(0, 300), warnIfMissed: false);
        await tester.pumpAndSettle();

        await libTap(tester, 'be-more');
        await shot(tester, 'user-menu');
        await libTap(tester, 'be-menu-libs');
        await shot(tester, 'libs');
        await libTap(tester, 'be-lib-$kLibFlow');
        await libTap(tester, 'be-lib-use'); // 还在用：顶上说有几处
        await shot(tester, 'lib');
        await tester.tap(lk('be-sheet-done').last);
        await libSettle(tester, rounds: 3);

        await libTap(tester, 'be-lib-import');
        await libUntil(tester, () => lk('be-lib-import-sheet').evaluate().isNotEmpty, what: '预览');
        await shot(tester, 'import-native');
        await libTap(tester, 'be-lib-native-native/hack.js');
        await shot(tester, 'import-code');
      });

      testWidgets('库文档：画布、这个库、一块库积木', (tester) async {
        final ui = await open(tester, flowUserDoc());
        await tester.runAsync(() async => expect(File(ui.session.guard.resolve(beLibSourceRel(kLibFlow))).existsSync(), isTrue));
        await libTap(tester, 'be-more');
        await libTap(tester, 'be-menu-libs');
        await libTap(tester, 'be-lib-$kLibFlow');
        await libTap(tester, 'be-lib-edit');
        await libUntil(tester, () => find.textContaining('库 · 公开了').evaluate().isNotEmpty, what: '进库的画布');
        await shot(tester, 'def-canvas');
        await libTap(tester, 'be-more');
        await libTap(tester, 'be-menu-lib-info');
        await shot(tester, 'info');
        await libTap(tester, 'be-lib-def-f4'); // 多试几次：原地展开、两个口
        await shot(tester, 'def');
        await tester.drag(find.byKey(const ValueKey('be-lib-def-into')), const Offset(0, -400), warnIfMissed: false);
        await tester.pumpAndSettle();
        await shot(tester, 'def-mouths');
      });
    });
  }
}
