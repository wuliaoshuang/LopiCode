// “常用”页分屏宽的界面（第四轮 B1；390×844）：平板档改内边距只记平板、手机不动；内容类的行标“不分屏宽”；
// 画布跟着变；“编辑组件”页也能切屏宽。
//   LOPI_SHOTS=1 LOPI_SHOT_DIR=<目录> flutter test --no-pub test/lowcode_bp_common_ui_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/lowcode/canvas_view.dart';
import 'package:lopicode/lowcode/inspector_presets_widgets.dart';
import 'package:lopicode/lowcode/responsive.dart';

import 'support/harness.dart';
import 'support/lowcode_builder.dart';
import 'support/theme_bp_sample.dart';

final String shotDir = Platform.environment['LOPI_SHOT_DIR'] ?? '.tmp/editor-r4b1-shots';

Future<void> shot(WidgetTester tester, String name) => lbShot(tester, shotDir, name);

Future<void> tap(WidgetTester tester, Finder f) async {
  expect(f, findsWidgets, reason: '要点的东西不在界面上');
  await tester.tap(f.first, warnIfMissed: false);
  await tester.pumpAndSettle();
  await settle(tester, rounds: 2);
}

Future<void> pickBp(WidgetTester tester, String which) async {
  await tap(tester, lbKey('lc-bp-open'));
  await tap(tester, lbKey('lc-bp-$which'));
}

void main() {
  setUpAll(() async => lbFontsLoaded = await loadRealFonts());

  testWidgets('平板档的“常用”页：改内边距只记进平板；文字那一行标着“不分屏宽”、改了哪儿都变；回到手机还是原来的', (tester) async {
    final session = await lbOpen(tester, doc: themeBpSample(), selected: 'buy');
    final before = (await lbSaved(tester, session)).find('buy')!;
    await pickBp(tester, 'tablet');
    await lbOpenCommon(tester);
    expect(lbKey('lc-bp-note'), findsOneWidget);
    expect(find.textContaining('只在平板及更宽的屏上生效'), findsOneWidget);
    expect(lbKey('lc-bp-go-style'), findsNothing);
    expect(find.text('不分屏宽'), findsWidgets);
    // “文字”那一行有标，“大小”那一行没有
    expect(
      find.descendant(
        of: find.ancestor(of: lbKey('lc-common-text'), matching: find.byType(InspectorRow)).first,
        matching: find.text('不分屏宽'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.ancestor(of: lbKey('lc-common-size-l'), matching: find.byType(InspectorRow)).first,
        matching: find.text('不分屏宽'),
      ),
      findsNothing,
    );
    await shot(tester, 'bpcommon-01-tablet-common');

    await lbTapShown(tester, lbKey('lc-common-size-l'));
    var buy = (await lbSaved(tester, session)).find('buy')!;
    expect(buy.props, before.props, reason: '手机那份简写属性没动');
    expect(buy.style, before.style);
    expect(lcBpStyle(buy, 'tablet')['padding-top'], '16px');
    expect(lcBpStyle(buy, 'tablet')['font-size'], '18px');
    await lbShow(tester, lbKey('lc-bp-note'));
    expect(lbKey('lc-bp-clear'), findsOneWidget);
    await shot(tester, 'bpcommon-02-after-size');

    // 文字不分屏宽
    await lbShow(tester, lbKey('lc-common-text'));
    await tester.enterText(lbKey('lc-common-text'), '马上买');
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    buy = (await lbSaved(tester, session)).find('buy')!;
    expect(buy.props['text'], '马上买');

    // 画布：平板上按钮变高了，回手机还是原来那么高
    final hTablet = tester.getSize(lbNode('buy')).height / lbCanvas(tester).scale;
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await pickBp(tester, 'phone');
    final hPhone = tester.getSize(lbNode('buy')).height / lbCanvas(tester).scale;
    expect(hTablet, greaterThan(hPhone + 6), reason: '平板 $hTablet / 手机 $hPhone');
    await lbOpenCommon(tester);
    expect(find.text('不分屏宽'), findsNothing, reason: '手机档不标');
    expect(tester.takeException(), isNull);
  });

  testWidgets('桌面档：容器的对齐、间距按这一档显示和记；清掉回到和手机一样', (tester) async {
    final session = await lbOpen(tester, doc: themeBpSample(), selected: 'cards');
    await pickBp(tester, 'desktop');
    await lbOpenCommon(tester);
    await lbTapShown(tester, lbKey('lc-common-spread-between'));
    var cards = (await lbSaved(tester, session)).find('cards')!;
    expect(lcBpStyle(cards, 'desktop')['justify-content'], 'space-between');
    expect(cards.props.containsKey('justify'), isFalse);
    await shot(tester, 'bpcommon-03-desktop-container');
    await lbTapShown(tester, lbKey('lc-common-spread-start'));
    cards = (await lbSaved(tester, session)).find('cards')!;
    expect(lcBpStyle(cards, 'desktop')['justify-content'], anyOf(isNull, 'flex-start'));
    await lbTapShown(tester, lbKey('lc-bp-clear'));
    cards = (await lbSaved(tester, session)).find('cards')!;
    expect(lcBpStyle(cards, 'desktop'), isEmpty);
    expect(lcBpStyle(cards, 'tablet'), {'flex-direction': 'row'}, reason: '别的档没动');
    expect(tester.widget<CanvasView>(find.byType(CanvasView)).bp, 'desktop');
    expect(tester.takeException(), isNull);
  });
}
