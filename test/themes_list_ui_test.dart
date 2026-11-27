// 主题管理页：主题很多时列表经得起（能滚、不挤、不溢出）；从“⋯”走到导出面板（手机尺寸 390×844）。
//
//   flutter test test/themes_list_ui_test.dart
//   LOPI_SHOTS=1 flutter test test/themes_list_ui_test.dart   # 同时写截图到 docs/screenshots/editor-*.png
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/appearance/theme_builtin.dart';
import 'package:lopicode/appearance/theme_generate.dart';
import 'package:lopicode/appearance/theme_json.dart';
import 'package:lopicode/appearance/theme_spec.dart';
import 'package:lopicode/state/themes_state.dart';
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
    image.dispose();
    File('docs/screenshots/editor-$name.png')
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(data!.buffer.asUint8List());
  });
}

Finder k(String key) => find.byKey(Key(key));

/// 12 套看起来不一样的主题（强调色、底色倾向各不相同），名字有长有短。
const List<(String, int, int)> _looks = [
  ('海边', 0xFF14A3B8, 0xFFE3F2FD),
  ('樱花', 0xFFE0457B, 0xFFFCE4EC),
  ('薄荷', 0xFF058654, 0xFFE8F5E9),
  ('纸', 0xFF893300, 0xFFFFF3E0),
  ('葡萄', 0xFF7C4DFF, 0xFFEDE7F6),
  ('一个名字特别特别长长长长长长长长长长长长的主题', 0xFFC6212F, 0xFFFFFFFF),
  ('橙子', 0xFFF08A24, 0xFFFFF8E1),
  ('石头', 0xFF50525B, 0xFFECEFF1),
  ('湖', 0xFF2962CB, 0xFFE1F5FE),
  ('草地', 0xFF2E7D32, 0xFFF1F8E9),
  ('晚霞', 0xFFAD1457, 0xFFFFEBEE),
  ('沙', 0xFF8D6E63, 0xFFEFEBE9),
];

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

  Future<(TestEnv, List<ThemeSpec>)> boot(WidgetTester tester, {required bool dark, int count = 12}) async {
    usePhoneViewport(tester);
    late TestEnv env;
    final made = <ThemeSpec>[];
    await tester.runAsync(() async {
      env = await TestEnv.create();
      final themes = env.services.container.read(themesProvider.notifier);
      for (final (name, accent, tint) in _looks.take(count)) {
        final t = (await themes.create(dark: dark, name: name)).theme!;
        expect(await themes.save(generateTheme(dark: dark, tint: tint, accent: accent, shell: t).copyWith(author: () => name == '樱花' ? '霜霜' : null)), isNull);
        made.add(env.services.container.read(themesProvider).byId(t.id)!);
      }
    });
    addTearDown(() => tester.runAsync(env.dispose));
    await tester.pumpWidget(appFor(env, const ThemesScreen(), mode: dark ? ThemeMode.dark : ThemeMode.light, font: kTestFont));
    await settle(tester, rounds: 2);
    return (env, made);
  }

  final listScroll = find.descendant(of: k('themes-list'), matching: find.byType(Scrollable)).first;

  testWidgets('内置 + 12 套自己的：列表能滚到最后一套，每张卡不溢出，最后一套点了立刻选用（浅色）', (tester) async {
    final (env, made) = await boot(tester, dark: false);
    expect(k('themes-card-$kDefaultLightThemeId'), findsOneWidget);
    await shot(tester, 'themes-many-light');
    // 一屏放不下：最后一套一开始不在屏幕里。
    expect(tester.getRect(k('themes-card-${made.last.id}')).top, greaterThan(844));
    await tester.scrollUntilVisible(k('themes-card-${made.last.id}'), 300, scrollable: listScroll);
    await tester.ensureVisible(k('themes-card-${made.last.id}'));
    await tester.pumpAndSettle();
    await shot(tester, 'themes-many-light-end');
    // 每张卡同宽、同高（名字再长也只占一行，不把卡撑高，也不把“⋯”挤出去）。
    final sizes = {for (final t in made) tester.getSize(k('themes-card-${t.id}'))};
    expect(sizes.length, 1, reason: '$sizes');
    for (final t in made) {
      expect(tester.getRect(k('themes-more-${t.id}')).right, lessThanOrEqualTo(390 - 16));
    }
    await tester.tap(k('themes-card-${made.last.id}'));
    await waitUntil(tester, () => env.services.container.read(themesProvider).lightId == made.last.id, '点的那套主题被选成浅色时用的');
    await tester.pumpAndSettle();
    expect(env.services.container.read(themesProvider).lightId, made.last.id);
    expect(k('themes-inuse-${made.last.id}'), findsOneWidget);
    await shot(tester, 'themes-many-light-picked');
  });

  testWidgets('深色那一段同样经得起；“新建主题：从哪套开始”的列表也能滚到最后一套', (tester) async {
    final (_, made) = await boot(tester, dark: true);
    await shot(tester, 'themes-many-dark');
    await tester.tap(k('themes-new'));
    await tester.pumpAndSettle();
    expect(k('themes-from-$kDefaultDarkThemeId'), findsOneWidget);
    final sheetScroll = find.descendant(of: k('themes-from-list'), matching: find.byType(Scrollable)).first;
    await tester.scrollUntilVisible(k('themes-from-${made.last.id}'), 200, scrollable: sheetScroll);
    await tester.pumpAndSettle();
    expect(k('themes-from-${made.last.id}'), findsOneWidget);
    await shot(tester, 'themes-new-from-many');
  });

  testWidgets('从“⋯ › 导出”打开导出面板：复制出来的文本就是这一套（内置主题导出去是一套普通主题）', (tester) async {
    final (_, made) = await boot(tester, dark: false, count: 1);
    await tester.tap(k('themes-more-${made.first.id}'));
    await tester.pumpAndSettle();
    await tester.tap(k('themes-act-export'));
    await tester.pumpAndSettle();
    expect(k('theme-export-size'), findsOneWidget);
    await tester.tap(k('theme-export-copy'));
    await tester.pumpAndSettle();
    await shot(tester, 'export-from-themes');
    final back = decodeThemeText(clipboard);
    expect(back.ok, isTrue, reason: back.error);
    expect(back.theme!.copyWith(id: made.first.id), made.first);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    await tester.tap(k('themes-more-$kDefaultLightThemeId'));
    await tester.pumpAndSettle();
    await tester.tap(k('themes-act-export'));
    await tester.pumpAndSettle();
    await tester.tap(k('theme-export-copy'));
    await tester.pumpAndSettle();
    final builtin = decodeThemeText(clipboard);
    expect(builtin.ok, isTrue, reason: builtin.error);
    expect(builtin.theme!.builtin, isFalse);
    expect(builtin.theme!.copyWith(id: kDefaultLightThemeId, builtin: true), kDefaultLightTheme);
  });
}
