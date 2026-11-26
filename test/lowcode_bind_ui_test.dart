// 第 5 期（状态与数据绑定）的编辑器界面：画布按初值预览、面板里绑定 / 解除、从空开始新建状态、
// “状态”页（新建、改名连带改、删除、挪层、看哪里在用）、样式页的“显示”开关（含按屏宽档）、“编辑组件”页切屏宽。
// 390×844。没覆盖的：真机上的手感、键盘弹起时的遮挡。
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/lowcode/bind_model.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/responsive.dart';
import 'package:lopicode/lowcode/state_model.dart';
import 'package:material_ui/material_ui.dart';

import 'support/bind_sample.dart';
import 'support/harness.dart';
import 'support/lowcode_builder.dart';

Future<void> _back(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
  await settle(tester, rounds: 2);
}

Future<void> _menu(WidgetTester tester, String item) async {
  await lbTap(tester, find.byTooltip('更多').first);
  await tester.pumpAndSettle();
  await lbTap(tester, find.widgetWithText(PopupMenuItem<String>, item));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('画布按初值预览：绑的文字、派生值、重复的两份、条件不成立的调淡带角标', (tester) async {
    await lbOpen(tester, doc: bindSample());
    expect(find.text('你好，小塔塔'), findsOneWidget, reason: '绑到项目级状态 user 的文字');
    expect(find.text('已点 0 次'), findsOneWidget, reason: '派生值按初值算');
    expect(find.text('1. 苹果 ¥3'), findsOneWidget);
    expect(find.text('2. 香蕉 ¥2'), findsOneWidget);
    expect(find.text('重复'), findsWidgets, reason: '重复的组件有角标');
    expect(find.text('条件不成立'), findsWidgets, reason: '初值下不成立的条件：照样占位、带角标');
    expect(tester.takeException(), isNull);
  });

  testWidgets('面板：行尾的链环绑上状态→变成药丸→点 ✕ 解除；存盘里的字段跟着有、跟着没', (tester) async {
    final session = await lbOpen(tester, doc: bindSample());
    await lbTap(tester, lbNode('toCart'));
    await lbOpenCommon(tester);
    await lbTapShown(tester, lbKey('lc-bind-text'));
    await tester.pumpAndSettle();
    expect(lbKey('lc-bind-title'), findsOneWidget);
    await lbTapShown(tester, lbKey('lc-bind-value-user'));
    await tester.pumpAndSettle();
    expect(lbKey('lc-bound-text'), findsOneWidget, reason: '绑了以后这一行是药丸');
    expect(lbKey('lc-bind-text'), findsNothing);
    expect(find.text('小塔塔'), findsWidgets, reason: '画布上按钮的字换成了状态的初值');
    await _back(tester);
    var saved = await lbSaved(tester, session);
    expect(lcDataExpr(saved.find('toCart')!, 'text'), {'e': 'var', 'name': 'user'});

    await lbTap(tester, lbNode('toCart'));
    await lbOpenCommon(tester);
    await lbTapShown(tester, lbKey('lc-unbind-text'));
    await tester.pumpAndSettle();
    expect(lbKey('lc-bind-text'), findsOneWidget);
    await _back(tester);
    saved = await lbSaved(tester, session);
    expect(lcDataExpr(saved.find('toCart')!, 'text'), isNull);
    expect(saved.find('toCart')!.more.containsKey(kLcData), isFalse, reason: '解除以后不留空壳字段');
    expect(saved.find('toCart')!.strProp('text'), '去购物车', reason: '原来填的字还在');
  });

  testWidgets('从空开始：还没有状态时面板里就地新建一个，再绑上；条件、输入框同步也在“数据”一节', (tester) async {
    final session = await lbOpen(tester);
    await lbTap(tester, lbNode('n1'));
    await lbOpenCommon(tester);
    await lbTapShown(tester, lbKey('lc-bind-text'));
    await tester.pumpAndSettle();
    expect(find.text('还没有状态'), findsOneWidget);
    await lbTap(tester, lbKey('lc-bind-new-first'));
    await tester.pumpAndSettle();
    await tester.enterText(lbKey('lc-var-name'), 'headline');
    await tester.enterText(lbKey('lc-var-initial'), '今天的标题');
    await tester.pump();
    await lbTap(tester, find.widgetWithText(TextButton, '新建'));
    await tester.pumpAndSettle();
    await lbTap(tester, lbKey('lc-bind-value-headline'));
    await tester.pumpAndSettle();
    expect(lbKey('lc-bound-text'), findsOneWidget);
    expect(find.text('今天的标题'), findsWidgets);

    // 显示条件：比较 headline 不等于空
    await lbTapShown(tester, lbKey('lc-data-showIf'));
    await tester.pumpAndSettle();
    await lbTap(tester, lbKey('lc-bind-mode-compare'));
    await tester.pumpAndSettle();
    expect(lbKey('lc-bind-use'), findsOneWidget);
    await _back(tester);
    await _back(tester);

    // 输入框：跟状态同步
    await lbTap(tester, lbNode('n4'));
    await lbOpenCommon(tester);
    await lbTapShown(tester, lbKey('lc-data-model'));
    await tester.pumpAndSettle();
    await lbTap(tester, lbKey('lc-bind-value-headline'));
    await tester.pumpAndSettle();
    expect(lbKey('lc-bound-model'), findsOneWidget);
    await _back(tester);

    final saved = await lbSaved(tester, session);
    expect(saved.logic.variable('headline')?.initial, '今天的标题');
    expect(lcDataExpr(saved.find('n1')!, 'text'), {'e': 'var', 'name': 'headline'});
    expect(lcModelOf(saved.find('n4')!), 'headline');
  });

  testWidgets('“状态”页：两节都列出来；改名连带改绑定；删除先问；挪到整个项目', (tester) async {
    final session = await lbOpen(tester, doc: bindSample());
    await _menu(tester, '状态');
    expect(lbKey('lc-state-row-l-count'), findsOneWidget);
    expect(lbKey('lc-state-row-p-cart'), findsOneWidget);
    expect(find.textContaining('用了'), findsWidgets);

    // 看哪里在用
    await lbTap(tester, lbKey('lc-state-menu-l-count'));
    await tester.pumpAndSettle();
    await lbTap(tester, find.text('看哪里在用'));
    await tester.pumpAndSettle();
    expect(lbKey('lc-state-uses'), findsOneWidget);
    expect(find.textContaining('派生值 tip'), findsOneWidget);
    await _back(tester);

    // 改名：count → clicks
    await lbTap(tester, lbKey('lc-state-row-l-count'));
    await tester.pumpAndSettle();
    await tester.enterText(lbKey('lc-var-name'), 'clicks');
    await tester.pump();
    await lbTap(tester, find.widgetWithText(TextButton, '保存'));
    await tester.pumpAndSettle();
    expect(lbKey('lc-state-row-l-clicks'), findsOneWidget);
    expect(lbKey('lc-state-row-l-count'), findsNothing);

    // 挪：keyword → 整个项目
    await lbTap(tester, lbKey('lc-state-menu-l-keyword'));
    await tester.pumpAndSettle();
    await lbTap(tester, find.text('挪到整个项目'));
    await tester.pumpAndSettle();
    expect(lbKey('lc-state-row-p-keyword'), findsOneWidget);

    // 删除：先问，取消就不删；确认才删
    await tester.scrollUntilVisible(lbKey('lc-state-menu-p-visits'), 200, scrollable: find.descendant(of: lbKey('lc-state-list'), matching: find.byType(Scrollable)).first);
    await lbTap(tester, lbKey('lc-state-menu-p-visits'));
    await tester.pumpAndSettle();
    await lbTap(tester, find.text('删除').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('处在用它'), findsOneWidget);
    await lbTap(tester, find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();
    expect(lbKey('lc-state-row-p-visits'), findsOneWidget);
    await _back(tester);

    final saved = await lbSaved(tester, session);
    expect(saved.logic.variable('count'), isNull);
    expect(saved.logic.variable('clicks'), isNotNull);
    expect(saved.logic.variable('keyword'), isNull);
    expect([for (final v in lcProjectStates(saved)) v.name], contains('keyword'));
    expect(lcModelOf(saved.find('kw')!), 'keyword', reason: '挪了层，名字没变，绑定照用');
    final tip = saved.logic.variable('tip')!;
    expect('${tip.derived}', contains('clicks'));
    expect('${tip.derived}', isNot(contains('count')));
    expect('${saved.find('enough')!.more[kLcRenderIf]}', contains('clicks'));
  });

  testWidgets('样式页“显示”开关：关＝display:none；平板档关掉只记成那一档的差别，再开回来差别就没了', (tester) async {
    final session = await lbOpen(tester);
    await lbTap(tester, lbNode('n2'));
    await lbOpenCommon(tester);
    await lbTap(tester, find.text('样式').last);
    await lbTapShown(tester, lbKey('lc-tab-layout'));
    await lbTapShown(tester, lbKey('lc-style-visible'));
    expect(find.textContaining('现在是“隐藏”'), findsOneWidget);
    await lbTapShown(tester, lbKey('lc-style-visible'));
    expect(find.textContaining('现在是“隐藏”'), findsNothing);
    await _back(tester);
    var saved = await lbSaved(tester, session);
    expect(saved.find('n2')!.style.containsKey('display'), isFalse);

    // 平板档：隐藏
    await lbTap(tester, lbKey('lc-bp-open'));
    await tester.pumpAndSettle();
    await lbTap(tester, lbKey('lc-bp-tablet'));
    await tester.pumpAndSettle();
    await lbTap(tester, lbNode('n2'));
    await lbOpenCommon(tester);
    await lbTap(tester, find.text('样式').last);
    await lbTapShown(tester, lbKey('lc-tab-layout'));
    await lbTapShown(tester, lbKey('lc-style-visible'));
    await _back(tester);
    saved = await lbSaved(tester, session);
    expect(saved.find('n2')!.style.containsKey('display'), isFalse, reason: '手机那一层没动');
    expect(lcBpStyle(saved.find('n2')!, 'tablet')['display'], 'none');

    await lbTap(tester, lbNode('n2'));
    await lbOpenCommon(tester);
    await lbTap(tester, find.text('样式').last);
    await lbTapShown(tester, lbKey('lc-tab-layout'));
    await lbTapShown(tester, lbKey('lc-style-visible'));
    await _back(tester);
    saved = await lbSaved(tester, session);
    expect(lcBpStyle(saved.find('n2')!, 'tablet').containsKey('display'), isFalse);
  });

  testWidgets('样式页“显示”开关：手机隐藏、桌面显示——桌面档打开时写一个盖得过去的值', (tester) async {
    final doc = LcDocument.starter('我的小站');
    doc.find('n2')!.style['display'] = 'none';
    final session = await lbOpen(tester, doc: doc, selected: 'n2');
    await lbTap(tester, lbKey('lc-bp-open'));
    await tester.pumpAndSettle();
    await lbTap(tester, lbKey('lc-bp-desktop'));
    await tester.pumpAndSettle();
    await lbOpenCommon(tester);
    await lbTap(tester, find.text('样式').last);
    await lbTapShown(tester, lbKey('lc-tab-layout'));
    expect(find.textContaining('现在是“隐藏”'), findsOneWidget);
    await lbTapShown(tester, lbKey('lc-style-visible'));
    expect(find.textContaining('现在是“隐藏”'), findsNothing);
    await _back(tester);
    final saved = await lbSaved(tester, session);
    expect(saved.find('n2')!.style['display'], 'none', reason: '手机那一层还是隐藏');
    expect(lcBpStyle(saved.find('n2')!, 'desktop')['display'], 'block');
  });
}
