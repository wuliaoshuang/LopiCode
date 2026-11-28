// 第四轮 B8 的界面测试共用的点法（等到出现再点；长按拿起；读项目里导出的网页文件）。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/lowcode/lift_gesture_widgets.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/palette_widgets.dart';
import 'package:lopicode/project_session.dart';
import 'package:material_ui/material_ui.dart';

import 'harness.dart';
import 'lowcode_builder.dart';

final String b8ShotDir = Platform.environment['LOPI_SHOT_DIR'] ?? '.tmp/b8-shots';

/// 等到 [f] 出现（有上限）。
Future<void> b8Until(WidgetTester tester, Finder f, String what) async {
  for (var i = 0; i < 40 && f.evaluate().isEmpty; i++) {
    await settle(tester, rounds: 1);
  }
  expect(f, findsWidgets, reason: '等不到 $what');
}

Future<void> b8Tap(WidgetTester tester, Finder f, [String what = '要点的东西']) async {
  await b8Until(tester, f, what);
  await tester.tap(f.first, warnIfMissed: false);
  await tester.pump();
  await settle(tester, rounds: 4);
}

Future<void> b8TapText(WidgetTester tester, String label) async {
  await b8Until(tester, find.text(label), '“$label”');
  await tester.tap(find.text(label).last, warnIfMissed: false);
  await tester.pumpAndSettle();
}

/// 右上角 ⋮ 里点一项。
Future<void> b8Menu(WidgetTester tester, String label) async {
  await b8Tap(tester, find.byTooltip('更多').last);
  await b8Tap(tester, find.widgetWithText(PopupMenuItem<String>, label));
}

/// 组件盒里点一个（先点开那一类）。
Future<void> b8Add(WidgetTester tester, String group, String itemKey) async {
  final panel = find.byType(PalettePanel);
  if (panel.evaluate().isEmpty || tester.state<PalettePanelState>(panel).collapsed) await b8Tap(tester, lbKey('lc-tool-add').last);
  await b8Tap(tester, lbKey('palette-group-$group'));
  await b8Until(tester, lbKey('palette-item-$itemKey'), '组件盒里的 $itemKey');
  await lbShow(tester, lbKey('palette-item-$itemKey'));
  await settle(tester, rounds: 2);
  await b8Tap(tester, lbKey('palette-item-$itemKey'), '组件盒里的 $itemKey');
}

/// 在画布上长按一个组件（出长按菜单）。
Future<void> b8LongPress(WidgetTester tester, Finder f) async {
  final g = await tester.startGesture(tester.getCenter(f));
  await tester.pump(kLcLiftAfter + const Duration(milliseconds: 40));
  await tester.pump();
  await g.up();
  await tester.pumpAndSettle();
}

/// 提示条自己消失（3 秒）。
Future<void> b8HintGone(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 4));
  await tester.pumpAndSettle();
}

/// 项目里现在存着的导出网页（应用里“预览”读的就是这几个文件）：文件名 → 内容。
Future<Map<String, String>> b8PreviewFiles(WidgetTester tester, ProjectSession session) async {
  await waitLowcodeSaved(tester);
  final out = <String, String>{};
  await tester.runAsync(() async {
    final dir = Directory(session.guard.resolve('.'));
    for (final f in dir.listSync()) {
      if (f is File && (f.path.endsWith('.html') || f.path.endsWith('.css') || f.path.endsWith('.js'))) {
        out[f.uri.pathSegments.last] = f.readAsStringSync();
      }
    }
  });
  return out;
}

LcDocument b8Page(List<Object?> children, {List<Object?> variables = const [], List<Object?> components = const [], String title = 'B8'}) => LcDocument.parse(
  jsonEncode({
    'version': 3,
    'title': title,
    'logic': {'variables': variables},
    'components': components,
    'root': {
      'id': 'root',
      'type': 'page',
      'props': <String, Object?>{'padding': 16, 'gap': 12},
      'children': children,
    },
  }),
);

Map<String, Object?> b8Node(String id, String type, Map<String, Object?> props, [List<Object?> children = const [], Map<String, Object?> more = const {}]) => {
  'id': id,
  'type': type,
  'props': props,
  'children': children,
  ...more,
};
