// 第四轮 B3：B2 只在主题冒烟里“打开看过”的几张面板，这里一下一下点、最后核对存盘结果。
// - 定义这边（编辑组件页）：让选中的控件把点击往外发；加一个变体；在“正在改变体”里改样式（只记成这个变体的差别）。
// - 用的这边（选中实例 ›“常用”）：选变体、“属性跟着状态变”挑状态、给事件接动作；再把它们一个个去掉。
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/lowcode/bind_model.dart';
import 'package:lopicode/lowcode/component_extras.dart';
import 'package:material_ui/material_ui.dart';

import 'support/comp_samples.dart';
import 'support/lowcode_builder.dart';
import 'support/node_find.dart';

Future<void> _menu(WidgetTester tester, String label) async {
  await lbTap(tester, find.byTooltip('更多').last);
  await lbTap(tester, find.widgetWithText(PopupMenuItem<String>, label));
}

Future<void> _answer(WidgetTester tester, String text, String confirm) async {
  await tester.enterText(lbKey('comp-ask-text'), text);
  await lbTap(tester, find.widgetWithText(TextButton, confirm));
}

Future<void> _back(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('编辑组件页：让选中的文字把点击往外发；加变体、在变体模式里改按钮大小——只记成变体的差别', (tester) async {
    final session = await lbOpen(tester, doc: compUserDoc([productCardDef()]));
    final before = (await lbSaved(tester, session)).component('c1')!;
    final buyBefore = nodeIn(before.root, 'buy')!;
    await lbTap(tester, lbNode('p1'));
    await lbTap(tester, find.byTooltip('更多操作'));
    await lbTap(tester, find.widgetWithText(PopupMenuItem<String>, '编辑组件'));
    expect(lbKey('comp-editor-done'), findsOneWidget);

    // 一、没选中控件时点事件那一行：只有一句“先去选中”的提示，没有“发出它”的选项。
    await _menu(tester, '事件');
    await lbTap(tester, lbKey('comp-event-row-addCart'));
    expect(find.textContaining('先关掉这张面板'), findsOneWidget);
    expect(lbKey('comp-event-emit-click'), findsNothing);
    await _back(tester);
    await _back(tester);

    // 二、选中“商品名”那行文字 → 事件 → 加一个事件 → 点它 →“选中的文字被点击时发出它”。
    await lbTap(tester, lbNode('name'));
    await _menu(tester, '事件');
    await lbTap(tester, lbKey('comp-event-add'));
    await _answer(tester, '点了名字', '下一步');
    await _answer(tester, 'tapName', '确定');
    expect(find.textContaining('tapName · 还没有控件发出它'), findsOneWidget);
    await lbTap(tester, lbKey('comp-event-row-tapName'));
    await lbTap(tester, lbKey('comp-event-emit-click'));
    expect(find.textContaining('tapName · 文本被点击时发出'), findsOneWidget);
    await _back(tester);

    // 三、变体 → 添加（放进“样子”那一组）→ 点它进变体模式 → 选中按钮 → 常用 › 大小“大”→ 改完变体。
    await _menu(tester, '变体');
    await lbTap(tester, lbKey('comp-variant-add'));
    await lbTap(tester, lbKey('comp-variant-group-kind'));
    await _answer(tester, '促销', '确定');
    expect(lbKey('comp-variant-row-kind-v1'), findsOneWidget);
    expect(find.textContaining('还没改样子'), findsOneWidget);
    await lbTap(tester, lbKey('comp-variant-row-kind-v1'));
    expect(lbKey('comp-editor-variant-done'), findsOneWidget);
    expect(find.textContaining('正在改变体：促销'), findsOneWidget);
    await lbTap(tester, lbNode('buy'));
    await lbOpenCommon(tester);
    await lbTapShown(tester, lbKey('lc-common-size-l'));
    await _back(tester);
    await lbTap(tester, lbKey('comp-editor-variant-done'));
    expect(lbKey('comp-editor-done'), findsOneWidget);

    // 变体表里写着改了 1 个控件。
    await _menu(tester, '变体');
    expect(find.descendant(of: lbKey('comp-variant-row-kind-v1'), matching: find.textContaining('改了 1 个控件的样子')), findsOneWidget);
    await _back(tester);
    await lbTap(tester, lbKey('comp-editor-done'));

    final def = (await lbSaved(tester, session)).component('c1')!;
    // 事件：新事件在，发出它的是 name 的点击；原来 buy 发 addCart 的没动。
    expect(lcCompEvents(def).map((e) => e.name), ['addCart', 'tapName']);
    expect(lcEmitsOf(nodeIn(def.root, 'name')!)['click']?.event, 'tapName');
    expect(lcEmitsOf(nodeIn(def.root, 'buy')!)['click']?.event, 'addCart');
    // 变体：新变体只记了 buy 的样式差别；按钮平时的样子一个字没动。
    final v = lcVariants(def).firstWhere((x) => x.key == 'kind/v1');
    expect(v.label, '促销');
    expect(v.styles.keys, ['buy']);
    expect(v.styles['buy'], containsPair('font-size', '18px'));
    expect(v.styles['buy']!.keys, contains('padding-top'));
    final buy = nodeIn(def.root, 'buy')!;
    expect(buy.props, buyBefore.props);
    expect(buy.style, buyBefore.style);
    expect(lcVariants(def).length, 3);
    expect(tester.takeException(), isNull);
  });

  testWidgets('选中实例 ›“常用”：选变体、属性跟着状态变、事件接“让一个数字加 1”；再一个个去掉', (tester) async {
    final session = await lbOpen(tester, doc: compUserDoc([productCardDef()]));
    await lbTap(tester, lbNode('p2'));
    await lbOpenCommon(tester);

    // 选变体：样子 → 热卖
    await lbTapShown(tester, lbKey('comp-variant-kind'));
    await lbTap(tester, lbKey('comp-variant-pick-hot'));
    // 属性跟着状态变：title → apple（文字状态）
    await lbTapShown(tester, lbKey('comp-bind-title'));
    expect(lbKey('comp-bind-pick-none'), findsNothing, reason: '还没绑的时候没有“不跟状态”这一行');
    await lbTap(tester, lbKey('comp-bind-pick-apple'));
    expect(find.text('跟着 apple'), findsOneWidget);
    // price 是数字：能挑的只有数字状态
    await lbTapShown(tester, lbKey('comp-bind-price'));
    expect(lbKey('comp-bind-pick-cart'), findsOneWidget);
    expect(lbKey('comp-bind-pick-apple'), findsNothing, reason: '文字状态不能给数字属性');
    await _back(tester);
    // 事件：原来接的是“加 10”的积木（不是快捷动作）→ 换成“让一个数字加 1：cart”
    await lbShow(tester, lbKey('comp-event-addCart'));
    expect(find.text('1 块积木'), findsOneWidget);
    await lbTap(tester, lbKey('comp-event-addCart'));
    await lbTap(tester, lbKey('comp-event-act-changeVar'));
    await lbTap(tester, lbKey('comp-event-val-cart'));
    expect(find.text('让一个数字加 1：cart'), findsOneWidget);

    var doc = await lbSaved(tester, session);
    var p2 = doc.find('p2')!;
    final def = doc.component('c1')!;
    expect(lcInstanceVariants(def, p2), {'kind': 'hot'});
    expect(lcDataExpr(p2, 'title'), {'e': 'var', 'name': 'apple'});
    expect(lcDataExpr(p2, 'price'), isNull);
    final body = lcOnOf(p2)['addCart']!;
    expect(body.single.op, 'changeVar');
    expect(body.single.args['name'], 'cart');
    expect((body.single.args['by'] as Map)['v'], 1);
    expect((p2.props['values'] as Map)['title'], '香蕉', reason: '填的固定值留着，只是不起作用');

    // 一个个去掉
    await lbTapShown(tester, lbKey('comp-variant-kind'));
    await lbTap(tester, lbKey('comp-variant-pick-none'));
    await lbTapShown(tester, lbKey('comp-bind-title'));
    await lbTap(tester, lbKey('comp-bind-pick-none'));
    await lbTapShown(tester, lbKey('comp-event-addCart'));
    await lbTap(tester, lbKey('comp-event-act-none'));
    doc = await lbSaved(tester, session);
    p2 = doc.find('p2')!;
    expect(lcInstanceVariants(def, p2), isEmpty);
    expect(lcDataExpr(p2, 'title'), isNull);
    expect(lcOnOf(p2), isEmpty);
    expect(lcInstanceIsLive(p2), isFalse, reason: '都去掉以后，这个实例又是“没用新东西”的了');
    expect(tester.takeException(), isNull);
  });
}
