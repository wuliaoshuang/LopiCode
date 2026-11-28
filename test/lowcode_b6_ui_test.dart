// 第四轮 B6：上一段留下的界面小项，一步步点出来看——
// 1. 组件盒“表单”：九个条目一眼看全（面板自己高一点，三行整个露出来），换回两行以内的分类面板回到原来的高度；
// 2. “自定义组件”清单：自己做的排前面；从库来的（内置组件库）单独收成一组；
// 3. 面板“样式”页在平板档上选了一个状态：屏宽、状态两条提示并成一条，“清掉”清的是这个状态；
// 4. 选中标题居中的顶栏（左右都放着按钮）：尺寸标签不压在标题上，也不压在两边的按钮上。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/lowcode/canvas_overlay_widgets.dart';
import 'package:lopicode/lowcode/comp_lib_builtin.dart';
import 'package:lopicode/lowcode/logic_text.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/palette_widgets.dart';
import 'package:lopicode/lowcode/states_bp.dart';
import 'package:material_ui/material_ui.dart';

import 'support/comp_samples.dart';
import 'support/harness.dart';
import 'support/lowcode_builder.dart';

final String _shotDir = Platform.environment['LOPI_SHOT_DIR'] ?? '.tmp/b6-shots';

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

LcDocument _page(List<Object?> children, {List<Object?> components = const []}) =>
    LcDocument.parse(jsonEncode({'version': 3, 'title': 'B6', 'components': components, 'root': cn('root', 'page', {}, children)}));

void main() {
  setUpAll(() async => lbFontsLoaded = await loadRealFonts());

  test('默认那一档多高：两行以内不变；三行、四行整个露出来；再多露四行', () {
    expect(paletteNormalHeight(0), kPaletteNormalHeight);
    expect(paletteNormalHeight(8), kPaletteNormalHeight);
    expect(paletteNormalHeight(9), 360);
    expect(paletteNormalHeight(12), 360);
    expect(paletteNormalHeight(13), 440);
    expect(paletteNormalHeight(40), 440);
  });

  test('积木里说到一个组件：在图层里起过名字的用名字，没起的照旧用它上面的字', () {
    final doc = _page([
      cn('b1', 'button', {'text': '买'}),
      cn('b2', 'button', {'text': '买'}, [], {'name': '第二个买'}),
    ]);
    expect(describeNode(doc, 'b1'), '「按钮“买”」');
    expect(describeNode(doc, 'b2'), '「按钮“第二个买”」');
  });

  testWidgets('组件盒“表单”：九个一眼看全，不用滑；换到“基础”面板回到原来的高度', (tester) async {
    await lbOpen(
      tester,
      doc: _page([
        cn('t', 'text', {'text': '甲'}),
      ]),
    );
    await _tap(tester, lbKey('lc-tool-add').last);
    final panel = tester.state<PalettePanelState>(find.byType(PalettePanel));
    expect(panel.height, kPaletteNormalHeight, reason: '“常用”最多八个：原来的高度');
    await _tap(tester, lbKey('palette-group-form'));
    final box = tester.getRect(lbKey('palette-panel'));
    final bar = tester.getRect(lbKey('lc-tool-add').last);
    final keys = ['input', 'textarea', 'switch', 'slider', 'checkbox', 'radio', 'select', 'component:${lcBuiltinDefId('stepper')}', 'component:${lcBuiltinDefId('formItem')}'];
    for (final k in keys) {
      final r = tester.getRect(lbPaletteItem(k));
      expect(r.top >= box.top && r.bottom <= box.bottom, isTrue, reason: '$k 没整个露在面板里：$r / $box');
      expect(r.bottom <= bar.top, isTrue, reason: '$k 被底部工具条挡了：$r / $bar');
    }
    expect(panel.height, 360);
    await lbShot(tester, _shotDir, 'b6-palette-form-all');
    // 最后一个真点得着：点了页面上多一个表单项
    await _tap(tester, lbPaletteItem(keys.last));
    expect(lbCanvas(tester).widget.doc.root.children.last.props['ref'], lcBuiltinDefId('formItem'));
    await _tap(tester, lbKey('lc-tool-add').last);
    // 第四轮 B8 以后“布局”也是 9 个（多了“轻提示”），照同一条规矩露三行；“基础”6 个，回到原来的高度
    await _tap(tester, lbKey('palette-group-layout'));
    expect(tester.state<PalettePanelState>(find.byType(PalettePanel)).height, 360);
    await _tap(tester, lbKey('palette-group-basic'));
    expect(tester.state<PalettePanelState>(find.byType(PalettePanel)).height, kPaletteNormalHeight);
    expect(tester.takeException(), isNull);
  });

  testWidgets('“自定义组件”清单：自己做的在前；内置组件库装进来的单独一组', (tester) async {
    final doc = compUserDoc([productCardDef()]);
    lcEnsureBuiltin(doc, lcBuiltinDefId('stepper'));
    lcEnsureBuiltin(doc, lcBuiltinDefId('link'));
    await lbOpen(tester, doc: LcDocument.parse(doc.encode()));
    await _tap(tester, find.byTooltip('更多').last);
    await _tap(tester, find.widgetWithText(PopupMenuItem<String>, '自定义组件'));
    final group = lbKey('comp-group-$kBuiltinCompLibName');
    await _until(tester, group, '“来自库”那一行');
    expect(group, findsOneWidget);
    final head = tester.getRect(group).top;
    expect(tester.getRect(lbKey('comp-item-c1')).bottom <= head, isTrue, reason: '自己做的排在库那一组上面');
    for (final id in ['stepper', 'link']) {
      expect(tester.getRect(lbKey('comp-item-${lcBuiltinDefId(id)}')).top >= head, isTrue, reason: '$id 在库那一组里');
    }
    expect(find.textContaining('库「$kBuiltinCompLibName」· 用了'), findsNothing, reason: '每一行不再各写一遍库名');
    expect(find.text('还没有自定义组件'), findsNothing);
    await lbShot(tester, _shotDir, 'b6-comp-list-groups');
    expect(tester.takeException(), isNull);
  });

  testWidgets('“自定义组件”清单：只有库里装进来的时，照样写“还没有自定义组件”', (tester) async {
    final doc = compUserDoc(const []);
    lcEnsureBuiltin(doc, lcBuiltinDefId('stepper'));
    await lbOpen(tester, doc: LcDocument.parse(doc.encode()));
    await _tap(tester, find.byTooltip('更多').last);
    await _tap(tester, find.widgetWithText(PopupMenuItem<String>, '自定义组件'));
    await _until(tester, lbKey('comp-group-$kBuiltinCompLibName'), '“来自库”那一行');
    expect(find.text('还没有自定义组件'), findsOneWidget);
  });

  testWidgets('平板档 ＋ 选了“按下”：提示只有一条（说清屏宽和状态），“清掉”清的是这个状态', (tester) async {
    final session = await lbOpen(
      tester,
      doc: _page([
        cn('buy', 'button', {'text': '买'}),
      ]),
    );
    await lbTap(tester, lbKey('lc-bp-open'));
    await lbTap(tester, lbKey('lc-bp-tablet'));
    await lbTap(tester, lbNode('buy'));
    await lbOpenCommon(tester);
    await lbTap(tester, find.text('样式').last);
    expect(lbKey('lc-bp-note'), findsOneWidget);
    expect(lbKey('lc-state-note'), findsNothing);
    await lbTap(tester, lbKey('lc-state-pressed'));
    expect(lbKey('lc-bp-note'), findsOneWidget, reason: '并成的那一条');
    expect(lbKey('lc-state-note'), findsNothing, reason: '不再叠第二条');
    expect(find.textContaining('现在改的是“按下”时的样子，只在平板及更宽的屏上生效'), findsOneWidget);
    expect(tester.getRect(lbKey('lc-bp-note')).top >= tester.getRect(lbKey('lc-state-pressed')).bottom, isTrue, reason: '这一条在状态药丸下面');
    expect(lbKey('lc-state-clear'), findsNothing, reason: '还没写过东西');
    await lbTapShown(tester, lbKey('lc-tab-layout'));
    await lbTapShown(tester, lbKey('lc-num-flex-grow-plus'));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(lcBpStateStyle((await lbSaved(tester, session)).find('buy')!, 'tablet', 'pressed'), {'flex-grow': '1'});
    await lbShow(tester, lbKey('lc-bp-note'));
    await lbShot(tester, _shotDir, 'b6-one-note-state-at-tablet');
    await lbTapShown(tester, lbKey('lc-state-clear'));
    final buy = (await lbSaved(tester, session)).find('buy')!;
    expect(buy.more.containsKey('responsive'), isFalse, reason: '这个状态在这一档的清掉了');
    expect(tester.takeException(), isNull);
  });

  testWidgets('选中标题居中的顶栏，左右都放着按钮：尺寸标签不压标题、不压按钮', (tester) async {
    final doc = _page([
      cn(
        'bar',
        'appBar',
        {'title': '我的首页', 'variant': 'center', 'bg': '#FFFFFF', 'color': '#222435', 'width': 'fill'},
        [
          cn('l1', 'button', {'text': '返回'}, [], {'slot': 'left'}),
          cn('r1', 'button', {'text': '保存'}, [], {'slot': 'right'}),
        ],
      ),
      cn('below', 'text', {'text': '下面一行字'}),
    ]);
    await lbOpen(tester, doc: doc, selected: 'bar');
    await settle(tester, rounds: 3);
    final label = tester.getRect(lbKey('lowcode-size-label'));
    final title = tester.getRect(find.text('我的首页'));
    expect(label.overlaps(title.deflate(1)), isFalse, reason: '标签 $label 压在标题 $title 上');
    for (final id in ['l1', 'r1']) {
      expect(label.overlaps(tester.getRect(lbNode(id)).deflate(1)), isFalse, reason: '标签 $label 压在 $id 上');
    }
    // 算出来的那一块盖得住真画出来的那几个字（字在它的格子正中；格子比字宽）
    final canvas = lbCanvas(tester);
    final bar = canvas.widget.doc.find('bar')!;
    final calc = appBarTitleBox(bar, tester.getRect(lbNode('bar')))!;
    expect((calc.center.dx - title.center.dx).abs() <= 4 && (calc.center.dy - title.center.dy).abs() < 2, isTrue, reason: '算的 $calc，画的 $title');
    expect(calc.width - 16 > 40 && calc.width < title.width, isTrue, reason: '算的 $calc，画的 $title');
    await lbShot(tester, _shotDir, 'b6-size-label-center-title');
    expect(tester.takeException(), isNull);
  });
}
