// 第四轮 B4：事件带数据，从头到尾一步步点——
// 画布上点出卡片和按钮 → 存成组件 → 编辑组件：加属性 step（数字）、加事件、让按钮发出它、发出时带上 step
// → 回到页面：实例上给这个事件接“把一个状态设成事件带来的值”、选状态 cart → 存盘里的样子对、四种导出都导得出。
// 不带数据的事件：单子里没有“把一个状态设成事件带来的值”这一行。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/core/safe_file.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/lowcode/builder_screen.dart';
import 'package:lopicode/lowcode/component_extras.dart';
import 'package:lopicode/lowcode/component_instance_widgets.dart';
import 'package:lopicode/lowcode/export_comp_files.dart';
import 'package:lopicode/lowcode/export_dart.dart';
import 'package:lopicode/lowcode/export_html.dart';
import 'package:lopicode/lowcode/export_react.dart';
import 'package:lopicode/lowcode/export_vue.dart';
import 'package:lopicode/lowcode/palette_widgets.dart';
import 'package:lopicode/lowcode/quick_actions.dart';
import 'package:lopicode/project_session.dart';
import 'package:material_ui/material_ui.dart';

import 'support/comp_samples.dart';
import 'support/harness.dart';
import 'support/lowcode_builder.dart';
import 'support/node_find.dart';

/// 等到 [f] 出现；有上限。
Future<void> _until(WidgetTester tester, Finder f, String what) async {
  for (var i = 0; i < 40 && f.evaluate().isEmpty; i++) {
    await settle(tester, rounds: 1);
  }
  expect(f, findsWidgets, reason: '等不到 $what');
}

Future<void> _tap(WidgetTester tester, Finder f, [String what = '要点的东西']) async {
  await _until(tester, f, what);
  await tester.tap(f.first, warnIfMissed: false);
  await tester.pump();
  await settle(tester, rounds: 4);
}

Future<void> _back(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pump();
  await settle(tester, rounds: 4);
}

Future<void> _menu(WidgetTester tester, String label) async {
  await _tap(tester, find.byTooltip('更多').last);
  await _tap(tester, find.widgetWithText(PopupMenuItem<String>, label));
}

Future<void> _more(WidgetTester tester, String label) async {
  await _tap(tester, find.byTooltip('更多操作'));
  await _tap(tester, find.widgetWithText(PopupMenuItem<String>, label));
}

Future<void> _answer(WidgetTester tester, String text, String confirm) async {
  await tester.enterText(lbKey('comp-ask-text'), text);
  await _tap(tester, find.widgetWithText(TextButton, confirm));
}

Future<void> _add(WidgetTester tester, String group, String itemKey) async {
  final panel = find.byType(PalettePanel);
  if (panel.evaluate().isEmpty || tester.state<PalettePanelState>(panel).collapsed) await _tap(tester, lbKey('lc-tool-add').last);
  await _tap(tester, lbKey('palette-group-$group'));
  await _tap(tester, lbKey('palette-item-$itemKey'));
}

void main() {
  testWidgets('事件带数据：编辑组件里配“带上 step”，页面上接“把一个状态设成事件带来的值”', (tester) async {
    usePhoneViewport(tester);
    late TestEnv env;
    late ProjectSession a;
    await tester.runAsync(() async {
      env = await TestEnv.create();
      a = ProjectSession(env.services, await env.services.projects.create('项目甲', ProjectTemplate.lowcode));
      // 页面：只有一行“购物车 N 件”和几个状态（cart 数字、apple 文字…），没有任何组件。
      File(a.guard.resolve(kLowcodePageFile)).writeAsStringSync(compUserDoc(const []).encode());
    });
    addTearDown(() async {
      await pendingWrites();
      a.dispose();
      await env.dispose();
    });
    await tester.pumpWidget(
      appFor(
        env,
        BuilderScreen(key: UniqueKey(), session: a),
        font: lbFontsLoaded ? kTestFont : null,
      ),
    );
    await settle(tester, rounds: 6);

    // 点出卡片，里面放一个按钮；存成组件
    final ids0 = (await lbSaved(tester, a)).root.children.map((n) => n.id).toSet();
    await _add(tester, 'recent', 'card');
    var doc = await lbSaved(tester, a);
    final cardId = doc.root.children.firstWhere((n) => !ids0.contains(n.id)).id;
    await _add(tester, 'recent', 'button');
    await _back(tester);
    await _tap(tester, lbNode(cardId));
    await _more(tester, '存成组件');
    await _answer(tester, '加量按钮', '完成');
    doc = await lbSaved(tester, a);
    final buttonId = doc.components.single.root.children.firstWhere((n) => n.type == 'button').id;

    // 编辑组件：属性 step（数字）
    await _tap(tester, lbNode(cardId));
    await _more(tester, '编辑组件');
    await _menu(tester, '可配置的属性');
    await _tap(tester, lbKey('comp-prop-add'));
    await _answer(tester, 'step', '下一步');
    await _tap(tester, find.text('数字').last);
    await _back(tester);

    // 事件 add，由按钮的点击发出
    await _tap(tester, lbNode(buttonId));
    await _menu(tester, '事件');
    await _tap(tester, lbKey('comp-event-add'));
    await _answer(tester, '要加', '下一步');
    await _answer(tester, 'add', '确定');
    // 还没有控件发出它：单子里没有“带上一项数据”
    await _tap(tester, lbKey('comp-event-row-add'));
    expect(lbKey('comp-event-data'), findsNothing);
    await _tap(tester, lbKey('comp-event-emit-click'));

    // 这时回页面看一眼：不带数据的事件，动作单子里没有“把一个状态设成事件带来的值”
    await _back(tester);
    await _tap(tester, lbKey('comp-editor-done'));
    await _tap(tester, lbNode(cardId));
    await lbOpenCommon(tester);
    await lbTapShown(tester, lbKey('comp-event-add'));
    expect(lbKey('comp-event-act-changeVar'), findsOneWidget);
    expect(lbKey('comp-event-act-${kLcTakeQuick.id}'), findsNothing);
    await _back(tester); // 关掉单子
    await _back(tester); // 关掉面板

    // 再进编辑组件：发出时带上 step
    await _tap(tester, lbNode(cardId));
    await _more(tester, '编辑组件');
    await _menu(tester, '事件');
    await _tap(tester, lbKey('comp-event-row-add'));
    await _tap(tester, lbKey('comp-event-data'));
    expect(find.text('step · 属性'), findsOneWidget);
    await _tap(tester, lbKey('comp-event-data-step'));
    expect(find.textContaining('带：step'), findsOneWidget);
    await _back(tester);
    await _tap(tester, lbKey('comp-editor-done'));
    doc = await lbSaved(tester, a);
    var def = doc.components.single;
    expect(lcCompEvents(def).single.params.single.name, 'step');
    expect(lcCompEvents(def).single.params.single.type, 'number');
    expect(lcEmitsOf(nodeIn(def.root, buttonId)!)['click']!.args.keys, ['step']);

    // 页面上：把状态 cart 设成事件带来的值
    await _tap(tester, lbNode(cardId));
    await lbOpenCommon(tester);
    await lbTapShown(tester, lbKey('comp-event-add'));
    await _tap(tester, lbKey('comp-event-act-${kLcTakeQuick.id}'));
    await _tap(tester, lbKey('comp-event-val-cart'));
    expect(find.textContaining('把一个状态设成事件带来的值：cart'), findsOneWidget);
    await _back(tester);
    doc = await lbSaved(tester, a);
    def = doc.components.single;
    final inst = doc.find(cardId)!;
    final body = lcOnOf(inst)['add']!;
    expect(lcEventQuickOf(body)?.$1, same(kLcTakeQuick));
    expect(body.single.args['name'], 'cart');
    expect(body.single.args['value'], {'e': 'event'});

    // 四种导出都导得出；Vue / React 是组件文件，页面上接着事件
    expect(lcLiveFilesOk(doc), isTrue);
    final vue = {for (final f in exportVue(doc).files) f.path: f.content};
    final react = {for (final f in exportReact(doc).files) f.path: f.content};
    expect(vue.keys.where((k) => k.startsWith('components/')), hasLength(1));
    expect(vue.values.join(), contains('@add='));
    expect(vue.values.join(), contains('lcEvt("add", {'));
    expect(react.keys.where((k) => k.endsWith('.jsx') && k.startsWith('components/')), hasLength(1));
    expect(react.values.join(), contains('onAdd={'));
    expect(exportHtml(doc).html, contains('<button'));
    expect(exportDart(doc), contains('class '));

    // 再点一次能换回“不带数据”
    await _tap(tester, lbNode(cardId));
    await _more(tester, '编辑组件');
    await _menu(tester, '事件');
    await _tap(tester, lbKey('comp-event-row-add'));
    await _tap(tester, lbKey('comp-event-data'));
    await _tap(tester, lbKey('comp-event-data-none'));
    await _back(tester);
    await _tap(tester, lbKey('comp-editor-done'));
    doc = await lbSaved(tester, a);
    expect(lcCompEvents(doc.components.single).single.params, isEmpty);
    expect(lcEmitsOf(nodeIn(doc.components.single.root, buttonId)!)['click']!.args, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
