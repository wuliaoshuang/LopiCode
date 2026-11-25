// 主题预览的“搭建”（低代码编辑器）那一种：21 项都画出来了；在编辑器里改低代码的颜色时预览自动切过来并跟着变。
//
//   flutter test test/theme_preview_lowcode_test.dart
//   LOPI_SHOTS=1 flutter test test/theme_preview_lowcode_test.dart   # 同时写截图到 docs/screenshots/editor-*.png
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/appearance/theme_fields.dart';
import 'package:lopicode/appearance/theme_spec.dart';
import 'package:lopicode/state/themes_state.dart';
import 'package:lopicode/ui/theme_editor_screen.dart';
import 'package:lopicode/ui/theme_preview.dart';
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

/// 预览里所有“画出来的颜色”：容器的底色、边框色、文字色、图标色。
Set<int> paintedColors(WidgetTester tester) {
  final out = <int>{};
  final root = k('theme-preview-lowcode');
  for (final w in tester.widgetList<Container>(find.descendant(of: root, matching: find.byType(Container)))) {
    if (w.color != null) out.add(w.color!.toARGB32());
    final d = w.decoration;
    if (d is BoxDecoration) {
      if (d.color != null) out.add(d.color!.toARGB32());
      final b = d.border;
      if (b is Border) out.add(b.top.color.toARGB32());
    }
  }
  for (final w in tester.widgetList<DecoratedBox>(find.descendant(of: root, matching: find.byType(DecoratedBox)))) {
    final d = w.decoration;
    if (d is BoxDecoration) {
      if (d.color != null) out.add(d.color!.toARGB32());
      final b = d.border;
      if (b is Border) out.add(b.top.color.toARGB32());
    }
  }
  for (final w in tester.widgetList<Text>(find.descendant(of: root, matching: find.byType(Text)))) {
    final c = w.style?.color;
    if (c != null) out.add(c.toARGB32());
  }
  for (final w in tester.widgetList<Icon>(find.descendant(of: root, matching: find.byType(Icon)))) {
    if (w.color != null) out.add(w.color!.toARGB32());
  }
  return out;
}

void main() {
  setUpAll(() async => fontsLoaded = await loadRealFonts());

  Future<(TestEnv, ThemeSpec)> boot(WidgetTester tester, {required bool dark}) async {
    usePhoneViewport(tester);
    late TestEnv env;
    late ThemeSpec t;
    await tester.runAsync(() async {
      env = await TestEnv.create();
      t = (await env.services.container.read(themesProvider.notifier).create(dark: dark, name: '搭建用')).theme!;
    });
    addTearDown(() => tester.runAsync(env.dispose));
    await tester.pumpWidget(
      appFor(
        env,
        ThemeEditorScreen(theme: t),
        mode: dark ? ThemeMode.dark : ThemeMode.light,
        font: kTestFont,
      ),
    );
    await settle(tester, rounds: 2);
    return (env, t);
  }

  testWidgets('低代码编辑器的 21 项，每一项换成一个独一无二的颜色后都能在“搭建”预览里找到（浅色）', (tester) async {
    usePhoneViewport(tester);
    late TestEnv env;
    late ThemeSpec t;
    // 21 个互不相同、别处也不会出现的颜色。
    final marks = {for (final (i, f) in kLowcodeFields.indexed) f.key: 0xFF100000 + (i + 1) * 0x000B07};
    await tester.runAsync(() async {
      env = await TestEnv.create();
      final themes = env.services.container.read(themesProvider.notifier);
      final made = (await themes.create(dark: false, name: '记号')).theme!;
      expect(await themes.save(made.withColors('lowcode', marks)), isNull);
      t = env.services.container.read(themesProvider).byId(made.id)!;
    });
    addTearDown(() => tester.runAsync(env.dispose));
    await tester.pumpWidget(
      appFor(
        env,
        Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ThemePreview(spec: t, kind: ThemePreviewKind.lowcode),
            ),
          ),
        ),
        font: kTestFont,
      ),
    );
    await settle(tester, rounds: 2);
    expect(tester.takeException(), isNull);
    final painted = paintedColors(tester);
    final missing = [
      for (final f in kLowcodeFields)
        if (!painted.contains(marks[f.key])) '${f.key}（${f.label}）',
    ];
    expect(missing, isEmpty, reason: '这些项在预览里看不到');
    expect(kLowcodeFields.length, 21);
  });

  testWidgets('编辑器：能切到“搭建”；改“选中框”时预览自动切到搭建、颜色跟着变（浅色截图）', (tester) async {
    await boot(tester, dark: false);
    await tester.tap(find.descendant(of: k('theme-preview-kind'), matching: find.text('搭建')));
    await tester.pumpAndSettle();
    expect(k('theme-preview-lowcode'), findsOneWidget);
    await shot(tester, 'editor-lowcode-light');
    // 回到界面，再去改低代码的一项。
    await tester.tap(find.descendant(of: k('theme-preview-kind'), matching: find.text('界面')));
    await tester.pumpAndSettle();
    await tester.tap(k('theme-section-ui'));
    await tester.pumpAndSettle();
    final list = find.descendant(of: k('theme-editor-list'), matching: find.byType(Scrollable)).first;
    await tester.scrollUntilVisible(k('theme-section-lowcode'), 200, scrollable: list);
    await tester.ensureVisible(k('theme-section-lowcode'));
    await tester.pumpAndSettle();
    await tester.tap(k('theme-section-lowcode'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(k('theme-item-lowcode.selection'), 100, scrollable: list);
    await Scrollable.ensureVisible(tester.element(k('theme-item-lowcode.selection')), alignment: 0.5);
    await tester.pumpAndSettle();
    await tester.tap(k('theme-item-lowcode.selection'));
    await tester.pumpAndSettle();
    expect(k('theme-preview-lowcode'), findsOneWidget, reason: '改低代码的颜色时预览自动切到搭建');
    await tester.ensureVisible(k('color-hex'));
    await tester.enterText(k('color-hex'), '#E0457B');
    await tester.pump();
    final box = tester.widget<DecoratedBox>(k('lc-preview-selection')).decoration as BoxDecoration;
    expect((box.border! as Border).top.color.toARGB32(), 0xFFE0457B);
    expect(tester.widget<Container>(k('lc-preview-name-tag')).color!.toARGB32(), 0xFFE0457B);
    await shot(tester, 'editor-lowcode-color-sheet');
  });

  testWidgets('深色主题下的“搭建”预览（截图）', (tester) async {
    await boot(tester, dark: true);
    await tester.tap(find.descendant(of: k('theme-preview-kind'), matching: find.text('搭建')));
    await tester.pumpAndSettle();
    expect(k('theme-preview-lowcode'), findsOneWidget);
    await shot(tester, 'editor-lowcode-dark');
  });
}
