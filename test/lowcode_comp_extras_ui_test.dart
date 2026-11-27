// 第四轮 B2：编辑组件页里一下一下点出来——加一个事件、让选中的按钮把点击往外发、点一个变体进“正在改变体”再改完；
// 存盘以后这些都在。（十套主题的样子在 theme_comp_lib_smoke_test 里。）
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/lowcode/component_extras.dart';
import 'package:material_ui/material_ui.dart';

import 'support/comp_samples.dart';
import 'support/lowcode_builder.dart';

Future<void> _menu(WidgetTester tester, String label) async {
  await lbTap(tester, find.byTooltip('更多').last);
  await lbTap(tester, find.widgetWithText(PopupMenuItem<String>, label));
}

Future<void> _answer(WidgetTester tester, String text, String confirm) async {
  await tester.enterText(lbKey('comp-ask-text'), text);
  await lbTap(tester, find.widgetWithText(TextButton, confirm));
}

void main() {
  testWidgets('编辑组件页：加事件、点变体进去改再改完，存盘以后都在', (tester) async {
    final session = await lbOpen(tester, doc: compUserDoc([productCardDef()]));
    await lbTap(tester, lbNode('p1'));
    await lbTap(tester, find.byTooltip('更多操作'));
    await lbTap(tester, find.widgetWithText(PopupMenuItem<String>, '编辑组件'));
    expect(lbKey('comp-editor-done'), findsOneWidget);

    // 加一个事件：先问叫法，再问英文名。
    await _menu(tester, '事件');
    expect(lbKey('comp-event-row-addCart'), findsOneWidget);
    await lbTap(tester, lbKey('comp-event-add'));
    await _answer(tester, '点了分享', '下一步');
    await _answer(tester, 'share', '确定');
    expect(lbKey('comp-event-row-share'), findsOneWidget);
    // 名字重了会被拦住。
    await lbTap(tester, lbKey('comp-event-add'));
    await _answer(tester, '再来一个', '下一步');
    await _answer(tester, 'share', '确定');
    expect(find.textContaining('已经有一个叫 share 的事件了'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    // 点一个变体：进“正在改变体”，顶栏的“完成”换成“改完变体”；点了回到平时。
    await _menu(tester, '变体');
    await lbTap(tester, lbKey('comp-variant-row-kind-hot'));
    expect(lbKey('comp-editor-variant-done'), findsOneWidget);
    expect(lbKey('comp-editor-done'), findsNothing);
    await lbTap(tester, lbKey('comp-editor-variant-done'));
    expect(lbKey('comp-editor-done'), findsOneWidget);
    await lbTap(tester, lbKey('comp-editor-done'));

    final saved = await lbSaved(tester, session);
    final def = saved.component('c1')!;
    expect(lcCompEvents(def).map((e) => e.name), containsAll(['addCart', 'share']));
    expect(lcCompEvents(def).firstWhere((e) => e.name == 'share').label, '点了分享');
    expect(lcVariants(def).length, 2);
    expect(tester.takeException(), isNull);
  });
}
