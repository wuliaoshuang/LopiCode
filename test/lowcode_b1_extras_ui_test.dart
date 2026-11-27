// 第四轮 B1 的几处零碎（390×844）：
// “编辑组件”页切到平板后，“常用”页改的样子只记平板那一档；重复设置里名字和右边的药丸隔开了；
// 面板页签下面那段淡出不占高度、不挡点按；“状态”页上不再有“变量”这个叫法。
//   LOPI_SHOTS=1 LOPI_SHOT_DIR=<目录> flutter test --no-pub test/lowcode_b1_extras_ui_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/lowcode/component_model.dart';
import 'package:lopicode/lowcode/inspector_header_widgets.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/responsive.dart';
import 'package:material_ui/material_ui.dart';

import 'support/bind_sample.dart';
import 'support/harness.dart';
import 'support/lowcode_builder.dart';

final String shotDir = Platform.environment['LOPI_SHOT_DIR'] ?? '.tmp/editor-r4b1-shots';

Future<void> shot(WidgetTester tester, String name) => lbShot(tester, shotDir, name);

Future<void> tap(WidgetTester tester, Finder f) async {
  expect(f, findsWidgets, reason: '要点的东西不在界面上');
  await tester.tap(f.first, warnIfMissed: false);
  await tester.pumpAndSettle();
  await settle(tester, rounds: 2);
}

LcDocument compDoc() {
  final doc = LcDocument.starter('我的小站');
  doc.components.add(
    LcComponentDef(
      id: 'c1',
      name: '问候卡',
      root: LcNode(
        id: 'cr',
        type: 'column',
        children: [
          LcNode(id: 'cb', type: 'button', props: {'text': '买'}),
        ],
      ),
    ),
  );
  doc.root.children.add(LcNode(id: 'inst', type: 'component', props: {'ref': 'c1'}));
  return doc;
}

void main() {
  setUpAll(() async => lbFontsLoaded = await loadRealFonts());

  testWidgets('“编辑组件”页切到平板：“常用”页改大小只记平板那一档，手机那份没动；文字那一行标着“不分屏宽”', (tester) async {
    final session = await lbOpen(tester, doc: compDoc(), selected: 'inst');
    await tap(tester, find.byTooltip('更多操作'));
    await tap(tester, find.text('编辑组件'));
    expect(find.text('完成'), findsOneWidget);
    await tap(tester, lbKey('lc-bp-open'));
    await tap(tester, lbKey('lc-bp-tablet'));
    await tap(tester, lbNode('cb'));
    await lbOpenCommon(tester);
    expect(lbKey('lc-bp-note'), findsOneWidget);
    expect(find.text('不分屏宽'), findsWidgets);
    await lbTapShown(tester, lbKey('lc-common-size-l'));
    await shot(tester, 'bpcommon-04-component-editor-tablet');
    final cb = (await lbSaved(tester, session)).component('c1')!.root.children.single;
    expect(cb.props, {'text': '买'}, reason: '手机那份简写属性没动');
    expect(cb.style, isEmpty);
    expect(lcBpStyle(cb, 'tablet')['font-size'], '18px');
    expect(lcBpStyle(cb, 'desktop'), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('重复设置：名字和右边的内容至少隔开 8；各行的内容左边对齐', (tester) async {
    await lbOpen(tester, doc: bindSample());
    await tap(tester, lbNode('rowItem').first);
    await lbOpenCommon(tester);
    await lbTapShown(tester, lbKey('lc-bound-repeat'));
    final label = tester.getRect(find.text('每项的标识').first);
    final pill = tester.getRect(lbKey('lc-repeat-key'));
    expect(pill.left - label.right, greaterThanOrEqualTo(8), reason: '名字右边 ${label.right} / 药丸左边 ${pill.left}');
    expect(tester.getRect(lbKey('lc-repeat-list')).left, pill.left);
    expect(tester.getRect(lbKey('lc-repeat-item')).left, pill.left);
    await shot(tester, 'repeat-01-label-gap');
    expect(tester.takeException(), isNull);
  });

  testWidgets('面板页签下面那段淡出：不占高度；面板滚过一截以后头一行照样点得到', (tester) async {
    await lbOpen(tester, doc: bindSample(), selected: 'submit');
    await lbOpenCommon(tester);
    final header = tester.getRect(find.byType(InspectorHeader));
    final fade = find.descendant(of: find.byType(InspectorHeader), matching: find.byType(OverflowBox));
    expect(fade, findsOneWidget);
    expect(tester.getRect(fade).height, 0, reason: '不占高度');
    final painted = tester.getRect(find.descendant(of: fade, matching: find.byType(DecoratedBox)));
    expect(painted.height, kInspectorHeaderFade);
    expect(painted.top, header.bottom, reason: '画在页签那一栏的下面');
    await lbShow(tester, lbKey('lc-data-add-style'));
    await shot(tester, 'panel-01-scrolled-fade');
    // 滚过以后点得到刚好在淡出下面的东西
    await lbTapShown(tester, lbKey('lc-data-add-style'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('“状态”页：说明里不再叫“变量”', (tester) async {
    await lbOpen(tester, doc: bindSample());
    await tap(tester, find.byTooltip('更多'));
    await tap(tester, find.widgetWithText(PopupMenuItem<String>, '状态'));
    expect(find.textContaining('状态是页面记着的值'), findsOneWidget);
    expect(find.textContaining('积木编辑器里看到的也是这一份'), findsOneWidget);
    expect(find.textContaining('变量'), findsNothing);
    await shot(tester, 'state-01-wording');
  });
}
