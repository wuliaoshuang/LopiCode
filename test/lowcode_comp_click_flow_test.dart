// 第四轮 B3：整条界面流程，一下一下点出来（B2 的组件是用数据写的）——
// 项目甲：组件盒里点出卡片、文字、按钮 → 存成组件“商品卡片”→ 编辑组件：加属性并接到文字上、加事件并让按钮发出、
// 加变体并在变体模式里改按钮 → 回页面给实例填属性、接事件、选变体 → 存成库 → 导出成文件；
// 项目乙：从文件导入（先看预览）→ 组件盒“我的”里点一下用上 → 实例上属性 / 事件 / 变体都在 → 四种导出都导得出、带着它的内容。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/core/safe_file.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/lowcode/builder_screen.dart';
import 'package:lopicode/lowcode/comp_lib.dart';
import 'package:lopicode/lowcode/comp_lib_store.dart';
import 'package:lopicode/lowcode/component_extras.dart';
import 'package:lopicode/lowcode/export_dart.dart';
import 'package:lopicode/lowcode/export_html.dart';
import 'package:lopicode/lowcode/export_react.dart';
import 'package:lopicode/lowcode/export_vue.dart';
import 'package:lopicode/lowcode/palette_widgets.dart';
import 'package:lopicode/project_session.dart';
import 'package:material_ui/material_ui.dart';

import 'support/comp_samples.dart';
import 'support/harness.dart';
import 'support/lowcode_builder.dart';
import 'support/node_find.dart';

/// 等到 [f] 出现（读写文件要真等）；有上限。
Future<void> _until(WidgetTester tester, Finder f, String what) async {
  for (var i = 0; i < 40 && f.evaluate().isEmpty; i++) {
    await settle(tester, rounds: 1);
  }
  expect(f, findsWidgets, reason: '等不到 $what');
}

/// 点一下；不用“等动画全停”（组件库面板读文件的时候转着圈）。
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

/// 组件盒里点一个（没开就先点“添加”）。
Future<void> _add(WidgetTester tester, String group, String itemKey) async {
  final panel = find.byType(PalettePanel);
  if (panel.evaluate().isEmpty || tester.state<PalettePanelState>(panel).collapsed) await _tap(tester, lbKey('lc-tool-add').last);
  // 分类条是横着滚的：靠后的（“我的”）要先滚出来。
  for (var i = 0; i < 6 && lbKey('palette-group-$group').evaluate().isEmpty; i++) {
    await tester.drag(lbKey('palette-group-recent').evaluate().isEmpty ? find.byType(PalettePanel) : lbKey('palette-group-recent'), const Offset(-200, 0), warnIfMissed: false);
    await settle(tester, rounds: 2);
  }
  await _tap(tester, lbKey('palette-group-$group'));
  await _tap(tester, lbKey('palette-item-$itemKey'));
}

Future<void> _open(WidgetTester tester, TestEnv env, ProjectSession session) async {
  await tester.pumpWidget(
    appFor(
      env,
      BuilderScreen(key: UniqueKey(), session: session),
      font: lbFontsLoaded ? kTestFont : null,
    ),
  );
  await settle(tester, rounds: 6);
}

void main() {
  testWidgets('从零点出商品卡片 → 存库 → 导出 → 另一个项目导入 → 用上', (tester) async {
    usePhoneViewport(tester);
    late TestEnv env;
    late ProjectSession a, b;
    await tester.runAsync(() async {
      env = await TestEnv.create();
      a = ProjectSession(env.services, await env.services.projects.create('项目甲', ProjectTemplate.lowcode));
      b = ProjectSession(env.services, await env.services.projects.create('项目乙', ProjectTemplate.lowcode));
      // 两个项目的页面：只有一行“购物车 N 件”和两个状态（cart 数字、apple 文字），没有任何组件。
      for (final s in [a, b]) {
        File(s.guard.resolve(kLowcodePageFile)).writeAsStringSync(compUserDoc(const []).encode());
      }
    });
    addTearDown(() async {
      await pendingWrites();
      a.dispose();
      b.dispose();
      await env.dispose();
    });

    // ───── 项目甲：点出卡片，里面一行文字、一个按钮 ─────
    await _open(tester, env, a);
    final ids0 = (await lbSaved(tester, a)).root.children.map((n) => n.id).toSet();
    await _add(tester, 'recent', 'card');
    var doc = await lbSaved(tester, a);
    final card = doc.root.children.firstWhere((n) => !ids0.contains(n.id));
    expect(card.type, 'card');
    final cardId = card.id;
    // 新加的卡片选中着：再点文字、按钮，加进它里面。
    await _add(tester, 'recent', 'text');
    await _tap(tester, lbNode(cardId));
    await _add(tester, 'recent', 'button');
    doc = await lbSaved(tester, a);
    final inside = doc.find(cardId)!.children.where((n) => n.type != 'slot').toList();
    expect(inside.map((n) => n.type), containsAll(['text', 'button']), reason: '文字和按钮都在卡片里');

    // 存成组件
    await _back(tester); // 收起组件盒（如果开着）
    await _tap(tester, lbNode(cardId));
    await _more(tester, '存成组件');
    await _answer(tester, '商品卡片', '完成');
    doc = await lbSaved(tester, a);
    final def0 = doc.components.single;
    expect(def0.name, '商品卡片');
    expect(doc.find(cardId)!.type, 'component');
    final textId = def0.root.children.firstWhere((n) => n.type == 'text').id;
    final buttonId = def0.root.children.firstWhere((n) => n.type == 'button').id;

    // ───── 编辑组件：属性、事件、变体 ─────
    await _tap(tester, lbNode(cardId));
    await _more(tester, '编辑组件');
    expect(lbKey('comp-editor-done'), findsOneWidget);
    // 属性 title（文字），接到那行文字上
    await _menu(tester, '可配置的属性');
    await _tap(tester, lbKey('comp-prop-add'));
    await _answer(tester, 'title', '下一步');
    await _tap(tester, find.text('文字').last);
    await tester.ensureVisible(lbKey('comp-bind-$textId-text'));
    await _tap(tester, lbKey('comp-bind-$textId-text'));
    await _tap(tester, find.text('title · 文字').last);
    await _back(tester);
    // 事件 buy，由按钮的点击发出
    await _tap(tester, lbNode(buttonId));
    await _menu(tester, '事件');
    await _tap(tester, lbKey('comp-event-add'));
    await _answer(tester, '点了购买', '下一步');
    await _answer(tester, 'buy', '确定');
    await _tap(tester, lbKey('comp-event-row-buy'));
    await _tap(tester, lbKey('comp-event-emit-click'));
    expect(find.textContaining('buy · 按钮被点击时发出'), findsOneWidget);
    await _back(tester);
    // 变体“热卖”：按钮变大
    await _menu(tester, '变体');
    await _tap(tester, lbKey('comp-variant-add'));
    await _answer(tester, '热卖', '确定');
    await _tap(tester, lbKey('comp-variant-row-$kLcDefaultVariantGroup-v1'));
    expect(lbKey('comp-editor-variant-done'), findsOneWidget);
    await _tap(tester, lbNode(buttonId));
    await lbOpenCommon(tester);
    await lbTapShown(tester, lbKey('lc-common-size-l'));
    await _back(tester);
    await _tap(tester, lbKey('comp-editor-variant-done'));
    await _tap(tester, lbKey('comp-editor-done'));

    // ───── 回到页面：实例填属性、接事件、选变体 ─────
    await _tap(tester, lbNode(cardId));
    await lbOpenCommon(tester);
    await lbShow(tester, lbKey('comp-value-title'));
    await tester.enterText(find.descendant(of: lbKey('comp-value-title'), matching: find.byType(EditableText)), '苹果');
    await settle(tester, rounds: 3);
    await lbTapShown(tester, lbKey('comp-variant-$kLcDefaultVariantGroup'));
    await _tap(tester, lbKey('comp-variant-pick-v1'));
    await lbTapShown(tester, lbKey('comp-event-buy'));
    await _tap(tester, lbKey('comp-event-act-changeVar'));
    await _tap(tester, lbKey('comp-event-val-cart'));
    await _back(tester);
    doc = await lbSaved(tester, a);
    final def = doc.components.single;
    final inst = doc.find(cardId)!;
    expect(def.props.single.name, 'title');
    expect(nodeIn(def.root, textId)!.bind['text'], 'title');
    expect(lcCompEvents(def).single.name, 'buy');
    expect(lcEmitsOf(nodeIn(def.root, buttonId)!)['click']?.event, 'buy');
    expect(lcVariants(def).single.styles[buttonId], containsPair('font-size', '18px'));
    expect((inst.props['values'] as Map)['title'], '苹果');
    expect(lcInstanceVariants(def, inst), {kLcDefaultVariantGroup: 'v1'});
    expect(lcOnOf(inst)['buy']!.single.args['name'], 'cart');

    // ───── 存成库、导出成文件 ─────
    await _menu(tester, '组件库');
    await _tap(tester, lbKey('complib-new'), '“把组件存成一个库”');
    await tester.enterText(lbKey('complib-form-name'), '我的小店');
    await tester.enterText(lbKey('complib-form-id'), 'shuang/store');
    await tester.enterText(lbKey('complib-form-author'), '霜霜');
    await tester.ensureVisible(lbKey('complib-form-done'));
    await _tap(tester, lbKey('complib-form-done'));
    await _until(tester, lbKey('complib-item-shuang/store'), '存好的库');
    await _tap(tester, lbKey('complib-menu-shuang/store'));
    await _tap(tester, find.widgetWithText(PopupMenuItem<String>, '导出成文件'));
    const packRel = 'exports/组件库-我的小店-1.0.0.lopilib';
    await _until(tester, find.textContaining('已导出到项目的 $packRel'), '导出后的说明');
    await _tap(tester, find.widgetWithText(TextButton, '知道了'));
    await _back(tester); // 关掉组件库面板
    await lbSaved(tester, a);

    // 文件从甲拿到乙（相当于她把文件发给别人）
    await tester.runAsync(() async {
      final from = File(a.guard.resolve(packRel));
      expect(from.existsSync(), isTrue);
      final to = File(b.guard.resolve(packRel))..parent.createSync(recursive: true);
      to.writeAsBytesSync(from.readAsBytesSync());
    });

    // ───── 项目乙：导入（先看预览）→ 用上 ─────
    await _open(tester, env, b);
    expect((await lbSaved(tester, b)).components, isEmpty);
    await _menu(tester, '组件库');
    await _tap(tester, lbKey('complib-import-open'), '“从文件导入”');
    await _tap(tester, lbKey('complib-file-$packRel'), '选文件的单子');
    await _until(tester, lbKey('be-lib-import-sheet'), '导入前的预览');
    expect(find.text('导入组件库'), findsOneWidget);
    expect(find.text('我的小店'), findsOneWidget);
    expect(find.text('shuang/store'), findsOneWidget);
    expect(find.text('前端'), findsOneWidget, reason: '给谁用');
    expect(find.textContaining('商品卡片'), findsWidgets);
    // 预览的时候还什么都没落盘
    late List<CompStoredLib> stored;
    await tester.runAsync(() async => stored = await compLibsRead(b.guard));
    expect(stored, isEmpty);
    await tester.ensureVisible(lbKey('be-lib-import-go'));
    await _tap(tester, lbKey('be-lib-import-go'));
    await _until(tester, lbKey('complib-item-shuang/store'), '导入好的库');
    await tester.runAsync(() async => stored = await compLibsRead(b.guard));
    expect(stored.single.ok, isTrue);
    await _back(tester);

    // “已导入”的提示条浮在底下的工具栏上面：等它自己收掉再去点“添加”（有上限）。
    for (var i = 0; i < 20 && find.textContaining('已导入「我的小店」').evaluate().isNotEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(find.textContaining('已导入「我的小店」'), findsNothing);
    final refId = compLibDefId('shuang/store', def.id);
    await _add(tester, 'mine', 'component:$refId');
    await _back(tester);
    var docB = await lbSaved(tester, b);
    final used = docB.root.children.firstWhere((n) => n.type == 'component');
    expect(used.props['ref'], refId);
    final defB = docB.component(refId)!;
    expect(compLibOf(defB)?.id, 'shuang/store');
    expect(lcCompEvents(defB).single.name, 'buy');
    expect(lcVariants(defB).single.label, '热卖');

    // 在乙里也能给它接事件、选变体
    await _tap(tester, lbNode(used.id));
    await lbOpenCommon(tester);
    await lbTapShown(tester, lbKey('comp-variant-$kLcDefaultVariantGroup'));
    await _tap(tester, lbKey('comp-variant-pick-v1'));
    await lbTapShown(tester, lbKey('comp-event-buy'));
    await _tap(tester, lbKey('comp-event-act-changeVar'));
    await _tap(tester, lbKey('comp-event-val-cart'));
    docB = await lbSaved(tester, b);
    final usedB = docB.find(used.id)!;
    expect(lcInstanceVariants(docB.component(refId)!, usedB), {kLcDefaultVariantGroup: 'v1'});
    expect(lcOnOf(usedB)['buy'], isNotNull);

    // 四种导出都导得出，按钮的字都在里面
    final word = nodeIn(defB.root, buttonId)!.props['text'] as String;
    expect(exportHtml(docB).html, contains(word));
    expect(exportVue(docB).files.map((f) => f.content).join('\n'), contains(word));
    expect(exportReact(docB).files.map((f) => f.content).join('\n'), contains(word));
    expect(exportDart(docB), contains(word));
    expect(tester.takeException(), isNull);
  });
}
