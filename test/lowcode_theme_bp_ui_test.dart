// 第 4 期·主题变量＋断点的界面（390×844）：顶栏“看哪种屏宽”、样式页只写这一档的差别和一键清掉、
// 取色面板的“主题色”、数值格的“用变量…”、“主题变量”页（改值、改名、删除、起步的一套）。
// 模型和导出在 lowcode_theme_bp_model_test.dart / lowcode_theme_bp_export_test.dart。
//   LOPI_SHOTS=1 LOPI_SHOT_DIR=<目录> flutter test --no-pub test/lowcode_theme_bp_ui_test.dart   # 同时出截图
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/lowcode/canvas_view.dart';
import 'package:lopicode/lowcode/responsive.dart';
import 'package:lopicode/lowcode/theme_vars.dart';
import 'package:lopicode/project_session.dart';
import 'package:material_ui/material_ui.dart';

import 'support/harness.dart';
import 'support/lowcode_builder.dart';
import 'support/pages_sample.dart';
import 'support/theme_bp_sample.dart';

final String shotDir = Platform.environment['LOPI_SHOT_DIR'] ?? '.tmp/editor-b2p4-shots';

Future<void> shot(WidgetTester tester, String name) => lbShot(tester, shotDir, name);

Future<void> tap(WidgetTester tester, Finder f) async {
  expect(f, findsWidgets, reason: '要点的东西不在界面上');
  await tester.tap(f.first, warnIfMissed: false);
  await tester.pumpAndSettle();
  await settle(tester, rounds: 2);
}

Future<void> back(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
  await settle(tester, rounds: 2);
}

Future<void> pickBp(WidgetTester tester, String which) async {
  await tap(tester, lbKey('lc-bp-open'));
  await tap(tester, lbKey('lc-bp-$which'));
}

Future<void> openStyle(WidgetTester tester) async {
  await lbOpenCommon(tester);
  await lbTap(tester, find.text('样式').last);
}

Future<void> openThemePage(WidgetTester tester) async {
  await tap(tester, find.byTooltip('更多'));
  await tap(tester, find.widgetWithText(PopupMenuItem<String>, '主题变量'));
  expect(find.text('主题变量'), findsWidgets);
}

Future<String> fileText(WidgetTester tester, ProjectSession session) async {
  await waitLowcodeSaved(tester);
  late String text;
  await tester.runAsync(() async => text = File(session.guard.resolve(kLowcodePageFile)).readAsStringSync());
  return text;
}

CanvasView canvasOf(WidgetTester tester) => tester.widget<CanvasView>(find.byType(CanvasView));

void main() {
  setUpAll(() async => lbFontsLoaded = await loadRealFonts());

  testWidgets('断点：顶栏切到平板，画布按 768 宽画；样式页改的只记进 responsive.tablet；一键清掉；回到手机提示就没了', (tester) async {
    final session = await lbOpen(tester, doc: themeBpSample(), selected: 'buy');
    expect(canvasOf(tester).bp, isNull);
    await shot(tester, 'bp-01-phone');

    await tap(tester, lbKey('lc-bp-open'));
    expect(find.text('手机（默认）'), findsOneWidget);
    expect(find.text('平板（≥768）'), findsOneWidget);
    expect(find.text('桌面（≥1024）'), findsOneWidget);
    await shot(tester, 'bp-02-menu');
    await tap(tester, lbKey('lc-bp-tablet'));
    expect(canvasOf(tester).bp, 'tablet');
    expect(canvasOf(tester).presetWidth, 768);
    expect(find.textContaining('平板 768'), findsOneWidget, reason: '副标题写着现在看的是哪一档');
    expect(lbCanvas(tester).scale, lessThan(0.6), reason: '768 宽的页面缩小了整页放进 390 的屏里');
    await shot(tester, 'bp-03-tablet-canvas');

    await openStyle(tester);
    expect(lbKey('lc-bp-note'), findsOneWidget);
    expect(lbKey('lc-bp-clear'), findsNothing, reason: '这一档还没改过东西，没有“清掉”');
    await lbTapShown(tester, lbKey('lc-tab-layout'));
    await lbTapShown(tester, lbKey('lc-num-flex-grow-plus'));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    var buy = (await lbSaved(tester, session)).find('buy')!;
    expect(lcBpStyle(buy, 'tablet'), {'flex-grow': '1'});
    expect(buy.style, {'background-color': 'var(--color-primary)'}, reason: '手机的样子没动');
    expect(lcBpStyle(buy, 'desktop'), isEmpty);
    await lbShow(tester, lbKey('lc-bp-note'));
    expect(lbKey('lc-bp-clear'), findsOneWidget);
    await shot(tester, 'bp-04-tablet-style');

    await lbTapShown(tester, lbKey('lc-bp-clear'));
    buy = (await lbSaved(tester, session)).find('buy')!;
    expect(buy.more.containsKey('responsive'), isFalse, reason: '清空了整个字段都不留');

    // “常用”页在平板档：提示说这里改的是所有屏宽，给一个去“样式”页的入口。
    await lbTap(tester, find.text('常用').last);
    expect(lbKey('lc-bp-note'), findsOneWidget);
    expect(lbKey('lc-bp-go-style'), findsOneWidget);
    await shot(tester, 'bp-05-tablet-common');

    await pickBp(tester, 'desktop');
    expect(canvasOf(tester).presetWidth, 1024);
    await shot(tester, 'bp-06-desktop');
    await pickBp(tester, 'phone');
    expect(canvasOf(tester).bp, isNull);
    expect(lbKey('lc-bp-note'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('断点下的画布：平板把竖排改成横排，标题用平板的字号变量', (tester) async {
    await lbOpen(tester, doc: themeBpSample());
    final a0 = tester.getTopLeft(lbNode('cardA')), b0 = tester.getTopLeft(lbNode('cardB'));
    expect(b0.dy, greaterThan(a0.dy), reason: '手机：两张卡片上下排');
    final h0 = tester.getSize(find.descendant(of: lbNode('title'), matching: find.text('欢迎来到小站'))).height / lbCanvas(tester).scale;
    await pickBp(tester, 'tablet');
    final a1 = tester.getTopLeft(lbNode('cardA')), b1 = tester.getTopLeft(lbNode('cardB'));
    expect(b1.dy, closeTo(a1.dy, 0.5), reason: '平板：横排');
    expect(b1.dx, greaterThan(a1.dx));
    final h1 = tester.getSize(find.descendant(of: lbNode('title'), matching: find.text('欢迎来到小站'))).height / lbCanvas(tester).scale;
    expect(h1, greaterThan(h0 * 1.3), reason: '字号从 20 变成 30');
    expect(tester.takeException(), isNull);
  });

  testWidgets('用变量：取色面板里点主题色、数值格选“用变量…”，写进去的是 var(--名)；面板上看得出来自变量', (tester) async {
    final session = await lbOpen(tester, doc: themeBpSample(), selected: 'cardBText');
    await openStyle(tester);
    await lbTapShown(tester, lbKey('lc-tab-text'));
    await lbTapShown(tester, lbKey('lc-color-color'));
    expect(find.textContaining('主题色'), findsOneWidget);
    expect(lbKey('lc-color-var-color-primary'), findsOneWidget);
    await shot(tester, 'var-01-color-sheet');
    await tap(tester, lbKey('lc-color-var-color-primary'));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    var n = (await lbSaved(tester, session)).find('cardBText')!;
    expect(n.style['color'], 'var(--color-primary)');
    expect(lbKey('lc-color-color-var'), findsOneWidget, reason: '颜色按钮上有“来自变量”的链环');
    expect(
      find.descendant(of: lbKey('lc-color-color'), matching: find.text('品牌绿')),
      findsOneWidget,
      reason: '写的是变量给人看的名字',
    );

    await lbShow(tester, lbKey('lc-len-font-size-unit'));
    await tap(tester, lbKey('lc-len-font-size-unit'));
    await tap(tester, find.text('用变量…').last);
    expect(lbKey('lc-len-font-size-var-font-lg'), findsOneWidget);
    expect(lbKey('lc-len-font-size-var-color-primary'), findsNothing, reason: '字号只列字号变量');
    await shot(tester, 'var-02-length-menu');
    await tap(tester, lbKey('lc-len-font-size-var-font-lg'));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    n = (await lbSaved(tester, session)).find('cardBText')!;
    expect(n.style['font-size'], 'var(--font-lg)');
    await lbShow(tester, lbKey('lc-len-font-size-var'));
    expect(lbKey('lc-len-font-size-var'), findsOneWidget, reason: '整格换成变量的小牌子');
    await shot(tester, 'var-03-style-with-vars');
    expect(tester.takeException(), isNull);
  });

  testWidgets('“常用”页的预设档：展开后最下面一排变量牌，点了就用上；再点普通的一档就回到普通值', (tester) async {
    final session = await lbOpen(tester, doc: themeBpSample(), selected: 'cardB');
    await lbOpenCommon(tester);
    await lbTapShown(tester, lbKey('lc-preset-radius-more'));
    await lbShow(tester, lbKey('lc-var-radius-radius-md'));
    expect(lbKey('lc-var-radius-color-primary'), findsNothing, reason: '圆角只列圆角变量');
    await shot(tester, 'var-04-preset-open');
    await lbTap(tester, lbKey('lc-var-radius-radius-md'));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    var n = (await lbSaved(tester, session)).find('cardB')!;
    expect(n.style['border-top-left-radius'], 'var(--radius-md)');
    expect(n.style['border-bottom-right-radius'], 'var(--radius-md)');
    // 展开着的时候行首只写现在是什么；收起来以后行首是变量牌。
    expect(find.descendant(of: lbKey('lc-preset-radius-now'), matching: find.text('中圆角')), findsOneWidget);
    await lbTapShown(tester, lbKey('lc-preset-radius-more'));
    await lbShow(tester, lbKey('lc-preset-radius-var'));
    expect(lbKey('lc-preset-radius-var'), findsOneWidget, reason: '行首是变量牌');
    await shot(tester, 'var-05-preset-used');

    await lbTapShown(tester, lbKey('lc-preset-radius-6'));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    n = (await lbSaved(tester, session)).find('cardB')!;
    expect(n.style.keys.where((k) => k.contains('radius')), isEmpty, reason: '变量那几条去掉了');
    expect(n.props['radius'], 6, reason: '回到简写属性');
    expect(lbKey('lc-preset-radius-var'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('主题变量页：改值所有用到的地方跟着变；改代码里的名字扫所有页面和组件；删除换成现在的值；都能撤销', (tester) async {
    final session = await lbOpen(tester, doc: themeBpSample());
    expect(lbCanvas(tester).env.vars['color-primary'], '#058654');
    await openThemePage(tester);
    expect(lbKey('lc-var-row-color-primary'), findsOneWidget);
    expect(find.text('品牌绿'), findsOneWidget);
    expect(tester.widgetList<Text>(find.textContaining('--color-primary')).map((t) => t.data), ['--color-primary · 用了 2 处'], reason: '按钮的底色、组件“标签”里的字');
    await shot(tester, 'theme-01-list');

    // 改值
    await tap(tester, lbKey('lc-var-row-color-primary'));
    await shot(tester, 'theme-02-edit');
    await tester.enterText(lbKey('lc-var-value'), 'red!');
    await tester.pump();
    expect(tester.widget<FilledButton>(lbKey('lc-var-save')).onPressed, isNull, reason: '不是颜色：不让存');
    await shot(tester, 'theme-03-edit-bad');
    await tester.enterText(lbKey('lc-var-value'), '#aa3300');
    await tester.pump();
    await tap(tester, lbKey('lc-var-save'));
    var d = await lbSaved(tester, session);
    expect(lcThemeOf(d).values['color-primary'], '#aa3300');
    expect(d.find('buy')!.style['background-color'], 'var(--color-primary)', reason: '用到的地方写的还是变量');

    // 改代码里的名字
    await tap(tester, lbKey('lc-var-row-color-primary'));
    await tester.enterText(lbKey('lc-var-code'), 'color-brand');
    await tester.pump();
    await tap(tester, lbKey('lc-var-save'));
    d = await lbSaved(tester, session);
    expect(lcThemeOf(d).values.containsKey('color-primary'), isFalse);
    expect(lcThemeOf(d).values['color-brand'], '#aa3300');
    expect(lcThemeOf(d).labelOf('color-brand'), '品牌绿');
    expect(d.find('buy')!.style['background-color'], 'var(--color-brand)');
    expect(d.components.single.root.style['color'], 'var(--color-brand)', reason: '自定义组件里的也改了');
    expect(d.encode(), isNot(contains('--color-primary')));

    // 删除：先问
    await tap(tester, lbKey('lc-var-row-color-text-muted'));
    await tap(tester, lbKey('lc-var-delete'));
    expect(find.textContaining('有 1 处在用它'), findsOneWidget);
    await shot(tester, 'theme-04-delete-confirm');
    await tester.tap(find.text('删除').last);
    await tester.pumpAndSettle();
    await settle(tester, rounds: 2);
    d = await lbSaved(tester, session);
    expect(lcThemeOf(d).values.containsKey('color-text-muted'), isFalse);
    d.openPageAt(1);
    expect(d.find('about')!.style['color'], '#5c6479', reason: '另一页里用到的换成了它当时的值');

    // 回到搭建页：画布用的是新值；撤销三次回到最初
    await back(tester);
    expect(lbCanvas(tester).env.vars['color-brand'], '#aa3300');
    for (var i = 0; i < 3; i++) {
      await tap(tester, find.byTooltip('撤销'));
    }
    expect(await fileText(tester, session), themeBpSample().encode());
    expect(tester.takeException(), isNull);
  });

  testWidgets('主题变量页：空的时候加一套起步的；加一个变量；名字撞了、种类不对不让存', (tester) async {
    final session = await lbOpen(tester, doc: pagesSample());
    await openThemePage(tester);
    expect(find.text('还没有主题变量'), findsOneWidget);
    await shot(tester, 'theme-05-empty');
    await tap(tester, lbKey('lc-var-starter'));
    var d = await lbSaved(tester, session);
    expect(lcThemeOf(d).values.length, kLcStarterVars.length);
    expect(find.text('颜色'), findsOneWidget);
    expect(find.text('字号'), findsOneWidget);
    await shot(tester, 'theme-06-starter');

    await tester.scrollUntilVisible(
      lbKey('lc-var-add'),
      300,
      scrollable: find.descendant(of: lbKey('lc-var-list'), matching: find.byType(Scrollable)).first,
    );
    await tap(tester, lbKey('lc-var-add'));
    await tap(tester, lbKey('lc-var-kind-space'));
    expect(find.text('加一个间距变量'), findsOneWidget);
    await tester.enterText(lbKey('lc-var-code'), 'space-md');
    await tester.pump();
    expect(find.textContaining('已经有一个叫 --space-md'), findsOneWidget);
    await tester.enterText(lbKey('lc-var-code'), 'gap-big');
    await tester.pump();
    expect(find.textContaining('要以 space- 开头'), findsOneWidget);
    expect(tester.widget<FilledButton>(lbKey('lc-var-save')).onPressed, isNull);
    await tester.enterText(lbKey('lc-var-code'), 'space-xl');
    await tester.enterText(lbKey('lc-var-label'), '特大间距');
    await tester.enterText(lbKey('lc-var-value'), '40px');
    await tester.pump();
    await tap(tester, lbKey('lc-var-save'));
    d = await lbSaved(tester, session);
    expect(lcThemeOf(d).values['space-xl'], '40px');
    expect(lcThemeOf(d).labelOf('space-xl'), '特大间距');
    expect(tester.takeException(), isNull);
  });

  testWidgets('没用变量、没用断点的页面：切屏宽、进出主题变量页、开关面板，文件一个字不变', (tester) async {
    final before = pagesSample().encode();
    final session = await lbOpen(tester, doc: pagesSample(), selected: 'hello');
    await pickBp(tester, 'tablet');
    await openStyle(tester);
    await lbTapShown(tester, lbKey('lc-tab-text'));
    await pickBp(tester, 'desktop');
    await pickBp(tester, 'phone');
    await openThemePage(tester);
    await back(tester);
    expect(await fileText(tester, session), before);
    // 在手机档改一下再改回去（走撤销）：还是一个字不变，也没有多出 theme / responsive。
    await lbTapShown(tester, lbKey('lc-tab-layout'));
    await lbTapShown(tester, lbKey('lc-num-flex-grow-plus'));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    final mid = await fileText(tester, session);
    expect(mid, isNot(contains('"theme"')));
    expect(mid, isNot(contains('"responsive"')));
    expect(tester.takeException(), isNull);
  });
}
