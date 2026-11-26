// 主题界面测试（管理页、编辑器、导出 / 导入）共用的小工具：假剪贴板、起一页、等存盘、新建一套自己的主题、截图。
// 原来都在 test/theme_editor_ui_test.dart 里；2026-11-26 那个文件按功能拆成三个以后挪到这里，内容没变。
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

/// 假剪贴板里现在的内容（每个用例开始时清空）。
String clipboard = '';

/// 在 main() 里调一次：每个用例装上假剪贴板，结束时拆掉。
void useFakeClipboard() {
  setUp(() {
    clipboard = '';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') clipboard = (call.arguments as Map)['text'] as String;
      if (call.method == 'Clipboard.getData') return {'text': clipboard};
      return null;
    });
  });
  tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
}

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
