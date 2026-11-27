// 第四轮 B7：搭建台里的提示条，一步步点出来量位置——都得浮在工具条（和选中条 / 多选条）上面，不盖撤销、重做。
// 点到的：多选里“只能选同一层的”、多选“上移”到头、“加一条样式”起了不能用的名字（类名开关走的是同一段代码）、
// “Flutter 代码”面板里的“复制全部”（面板是盖在页面上的，页面上的提示条会被面板挡住——改成按钮自己变成“已复制”）。
// 别的提示条（底部导航 / 顶栏共用、换页、保存失败、组件库几句）各自的测试里点过、看的是字出没出来；它们和这里走的是同一个函数。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/lowcode/lift_gesture_widgets.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/multi_select.dart';

import 'support/bind_sample.dart';
import 'support/comp_samples.dart';
import 'support/harness.dart';
import 'support/lowcode_builder.dart';

final String _shotDir = Platform.environment['LOPI_SHOT_DIR'] ?? '.tmp/b7-shots';

LcDocument _doc() => LcDocument.parse(
  jsonEncode({
    'version': 3,
    'title': '提示',
    'logic': {
      'variables': [
        {'name': 'on', 'type': 'bool', 'initial': false},
      ],
    },
    'root': cn(
      'root',
      'page',
      {'padding': 16, 'gap': 12},
      [
        cn('a', 'text', {'text': '甲'}),
        cn('b', 'button', {'text': '乙'}),
        cn('c', 'text', {'text': '丙'}),
        cn(
          'box',
          'container',
          {'padding': 8},
          [
            cn('d', 'text', {'text': '丁'}),
          ],
        ),
      ],
    ),
  }),
);

Future<void> _longPress(WidgetTester tester, Finder f) async {
  final g = await tester.startGesture(tester.getCenter(f));
  await tester.pump(kLcLiftAfter + const Duration(milliseconds: 40));
  await tester.pump();
  await g.up();
  await tester.pumpAndSettle();
}

Future<void> _tapText(WidgetTester tester, String label) async {
  expect(find.text(label), findsWidgets, reason: '界面上没有“$label”');
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

/// 这句提示在界面上、点得到，而且整条在工具条上面。
void _above(WidgetTester tester, Finder hint, String what) {
  expect(hint, findsOneWidget, reason: '$what：提示没出来');
  expect(hint.hitTestable(), findsOneWidget, reason: '$what：提示被别的东西挡住了');
  final r = tester.getRect(hint);
  expect(r.bottom, lessThanOrEqualTo(tester.getRect(lbKey('lc-toolbar')).top), reason: '$what：提示盖到工具条上了');
  for (final tip in ['撤销', '重做']) {
    expect(find.byTooltip(tip).hitTestable(), findsOneWidget, reason: '$what：$tip 被挡住了');
  }
}

Future<void> _gone(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 4));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async => lbFontsLoaded = await loadRealFonts());

  testWidgets('多选：点了别的层的说一句、上移到头说一句——两句都在工具条上面', (tester) async {
    await lbOpen(tester, doc: _doc());
    await _longPress(tester, lbNode('a'));
    await _tapText(tester, '多选');
    expect(find.text('已选 1 个'), findsOneWidget);
    await lbTap(tester, lbNode('d'));
    _above(tester, find.text(kLcMultiSameLevelOnly), '只能选同一层');
    await lbShot(tester, _shotDir, 'b7-hint-multi-level');
    await _gone(tester);
    await lbTap(tester, lbKey('lc-multi-more'));
    await tester.pumpAndSettle();
    await _tapText(tester, '上移');
    _above(tester, find.text('已经在最前面了'), '上移到头');
    expect(tester.takeException(), isNull);
  });

  testWidgets('“加一条样式”起了个不能用的名字：那句提示在工具条上面（以前贴在最底下、盖住工具条）', (tester) async {
    await lbOpen(tester, doc: bindSample(), selected: 'submit');
    await lbOpenCommon(tester);
    await lbTapShown(tester, lbKey('lc-data-add-style'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText).last, 'Bad Name');
    await _tapText(tester, '确定');
    _above(tester, find.textContaining('不能用：'), '名字不能用');
    await lbShot(tester, _shotDir, 'b7-hint-class-name');
    expect(tester.takeException(), isNull);
  });

  testWidgets('“Flutter 代码”面板 ›“复制全部”：按钮自己变成“已复制”（面板盖着页面，页面上的提示条看不到）', (tester) async {
    await lbOpen(tester, doc: _doc());
    await lbTap(tester, find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await _tapText(tester, '导出 Flutter 代码');
    await settle(tester, rounds: 4);
    await tester.pumpAndSettle();
    expect(find.text('Flutter 代码'), findsOneWidget);
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String?;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await _tapText(tester, '复制全部');
    await settle(tester, rounds: 3);
    expect(copied, contains('class '), reason: '真的进了剪贴板');
    expect(find.text('已复制').hitTestable(), findsOneWidget, reason: '点完看得到“已复制”');
    expect(find.text('复制全部'), findsNothing);
    await lbShot(tester, _shotDir, 'b7-hint-code-copied');
    expect(tester.takeException(), isNull);
  });
}
