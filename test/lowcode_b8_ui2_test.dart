// 第四轮 B8（中）：一步步点出来看——
// 7. “重复”的设置单里点“换成一块内容（能放图、按钮）”：它后面多一个只在列表为空时出现的容器（画布上淡着、带角标），
//    原来那句话搬进去；再开设置单，那一行变成说明；“不重复了”那一块一起走；撤销一步全回来。
// 8. 数字框：长按住再左右拖＝加减（往右加、往左减，8 像素一步），框上面浮着现在的数；点一下照旧进去打字；
//    按下就上下划（没到长按）不会改数。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/lowcode/bind_model.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/number_drag_widgets.dart';
import 'package:lopicode/lowcode/repeat_empty.dart';
import 'package:material_ui/material_ui.dart';

import 'support/b8_ui.dart';
import 'support/harness.dart';
import 'support/lowcode_builder.dart';

LcDocument _listPage() => b8Page(
  [
    b8Node(
      'row',
      'text',
      {'text': '一项'},
      const [],
      {
        'repeat': {
          'list': {'from': 'var', 'name': 'xs'},
          'item': 'it',
          'index': 'i',
          'empty': '还没有订单',
        },
      },
    ),
    b8Node('after', 'button', {'text': '下面的按钮'}),
  ],
  variables: [
    {
      'name': 'xs',
      'type': 'list',
      'initial': ['甲', '乙'],
    },
  ],
);

Future<void> _openRepeat(WidgetTester tester) async {
  await b8Tap(tester, lbNode('row').first);
  await lbOpenCommon(tester);
  await lbTapShown(tester, lbKey('lc-bound-repeat'));
  await b8Until(tester, lbKey('lc-repeat-save'), '“重复”的设置单');
}

void main() {
  setUpAll(() async => lbFontsLoaded = await loadRealFonts());

  testWidgets('“重复”为空时显示一块内容：设置单里点一下就加在它后面；再开是说明；不重复了一起走；撤销一步回来', (tester) async {
    final s = await lbOpen(tester, doc: _listPage());
    await _openRepeat(tester);
    expect(lbKey('lc-repeat-empty'), findsOneWidget, reason: '还没有那一块：是一句话的输入框');
    await lbShow(tester, lbKey('lc-repeat-empty-block'));
    expect(find.text('换成一块内容（能放图、按钮）'), findsOneWidget);
    await lbShot(tester, b8ShotDir, 'b8-repeat-sheet');
    await b8Tap(tester, lbKey('lc-repeat-empty-block'));
    lbHintAbove(tester, '已在它后面加了一块');

    var doc = await lbSaved(tester, s);
    final box = lcRepeatEmptyBlock(doc, 'row');
    expect(box, isNotNull);
    expect(doc.root.children.map((n) => n.id).toList(), ['row', box!.id, 'after']);
    expect(box.children.single.props['text'], '还没有订单', reason: '原来那句话搬进去了');
    expect(lcRepeatOf(doc.find('row')!)!.empty, isNull);
    expect(lcRenderIfExpr(box), isNotNull);
    // 画布上看得到、点得中（列表现在有两项，条件不成立：淡着占位）
    await b8HintGone(tester);
    await b8Until(tester, lbNode(box.id), '画布上的那一块');
    expect(find.text('还没有订单'), findsOneWidget);
    await b8Tap(tester, lbNode(box.id));
    await lbShot(tester, b8ShotDir, 'b8-repeat-empty-block-canvas');
    // 导出的网页里：那一块带着条件，原来“一句话”的写法没有了
    final files = await b8PreviewFiles(tester, s);
    expect(files['index.html'], contains('n-${box.id}'));

    // 再开设置单：那一行是说明，按钮换成“保存，并去改那一块”
    await _openRepeat(tester);
    expect(lbKey('lc-repeat-empty'), findsNothing);
    expect(lbKey('lc-repeat-empty-has-block'), findsOneWidget);
    expect(find.text('保存，并去改那一块'), findsOneWidget);
    await lbShot(tester, b8ShotDir, 'b8-repeat-sheet-has-block');
    await b8Tap(tester, lbKey('lc-repeat-empty-block'));
    lbHintAbove(tester, '那一块就在它后面');
    doc = await lbSaved(tester, s);
    expect(doc.root.children.length, 3, reason: '没有加第二块');
    await b8HintGone(tester);

    // 不重复了：那一块一起走
    await _openRepeat(tester);
    await b8Tap(tester, lbKey('lc-repeat-remove'));
    doc = await lbSaved(tester, s);
    expect(lcRepeatOf(doc.find('row')!), isNull);
    expect(doc.root.children.map((n) => n.id).toList(), ['row', 'after']);
    // 撤销一步：重复和那一块都回来
    await b8Tap(tester, find.byTooltip('撤销'));
    doc = await lbSaved(tester, s);
    expect(lcRepeatOf(doc.find('row')!), isNotNull);
    expect(lcRepeatEmptyBlock(doc, 'row')?.id, box.id);
    expect(tester.takeException(), isNull);
  });

  testWidgets('数字框：长按住再左右拖＝加减，上面浮着现在的数；点一下照旧打字；没到长按就划走不改数', (tester) async {
    final s = await lbOpen(
      tester,
      doc: b8Page([
        b8Node(
          'box',
          'card',
          {'padding': 12},
          [
            b8Node('t', 'text', {'text': '里面'}),
          ],
        ),
      ]),
    );
    // 点卡片的留白（正中间是里面那行字）。
    await tester.tapAt(tester.getTopLeft(lbNode('box').first) + const Offset(5, 5));
    await settle(tester, rounds: 4);
    await lbOpenCommon(tester);
    await lbTapShown(tester, lbKey('lc-preset-padding-more'));
    await lbShow(tester, lbKey('lc-num-padding'));
    await settle(tester, rounds: 2);
    final at = tester.getCenter(lbKey('lc-num-padding'));
    String shown() => tester.widget<TextField>(lbKey('lc-num-padding')).controller!.text;
    expect(shown(), '12');

    // 没到长按就往上划：不改数、没有气泡（面板照常滚）
    var g = await tester.startGesture(at);
    await tester.pump(const Duration(milliseconds: 60));
    await g.moveBy(const Offset(0, -30));
    await tester.pump();
    await g.up();
    await tester.pumpAndSettle();
    expect(lbKey('lc-num-padding-drag'), findsNothing);
    expect((await lbSaved(tester, s)).find('box')!.props['padding'], 12);
    await lbShow(tester, lbKey('lc-num-padding'));
    await settle(tester, rounds: 2);

    // 长按住：气泡出来；往右拖 40 像素＝加 5
    g = await tester.startGesture(tester.getCenter(lbKey('lc-num-padding')));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    expect(lbKey('lc-num-padding-drag'), findsOneWidget, reason: '长按成立：气泡出来');
    for (var i = 0; i < 5; i++) {
      await g.moveBy(const Offset(kNumberDragPx, 0));
      await tester.pump();
    }
    expect(find.descendant(of: lbKey('lc-num-padding-drag'), matching: find.textContaining('17')), findsOneWidget);
    expect(shown(), '17');
    final bubble = tester.getRect(lbKey('lc-num-padding-drag')), box = tester.getRect(lbKey('lc-num-padding'));
    expect(bubble.bottom, lessThanOrEqualTo(box.top), reason: '气泡在数字框上面，不被手指挡住');
    await lbShot(tester, b8ShotDir, 'b8-number-drag');
    // 再往左拖回去 9 步＝从 12 减 4
    for (var i = 0; i < 9; i++) {
      await g.moveBy(const Offset(-kNumberDragPx, 0));
      await tester.pump();
    }
    expect(shown(), '8');
    // 一直往左：到 0 为止（内边距不许负）
    await g.moveBy(const Offset(-200, 0));
    await tester.pump();
    expect(shown(), '0');
    await g.moveBy(const Offset(200 + 3 * kNumberDragPx, 0));
    await tester.pump();
    expect(shown(), '11');
    await g.up();
    await tester.pump(const Duration(milliseconds: 450));
    await settle(tester, rounds: 3);
    expect(lbKey('lc-num-padding-drag'), findsNothing, reason: '松手：气泡收起');
    expect((await lbSaved(tester, s)).find('box')!.props['padding'], 11);
    // 整个拖动只算一步：撤销一下回到 12
    await b8Tap(tester, find.byTooltip('撤销'));
    expect((await lbSaved(tester, s)).find('box')!.props['padding'], 12);

    // 点一下：照旧进去打字
    await lbShow(tester, lbKey('lc-num-padding'));
    await b8Tap(tester, lbKey('lc-num-padding-touch'));
    expect(tester.widget<TextField>(lbKey('lc-num-padding')).focusNode!.hasFocus, isTrue);
    expect(lbKey('lc-num-padding-touch'), findsNothing, reason: '打字的时候那一层拿掉，光标归输入框管');
    await tester.enterText(lbKey('lc-num-padding'), '30');
    await tester.pump(const Duration(milliseconds: 450));
    await settle(tester, rounds: 3);
    expect((await lbSaved(tester, s)).find('box')!.props['padding'], 30);

    // “样式”页里的数字框（另一种框）也一样：布局 › 占剩余空间，长按往右拖 3 步
    await lbTap(tester, find.text('样式').last);
    await lbTapShown(tester, lbKey('lc-tab-layout'));
    await lbShow(tester, lbKey('lc-num-flex-grow'));
    await settle(tester, rounds: 2);
    expect(lbKey('lc-num-flex-grow-touch'), findsOneWidget);
    g = await tester.startGesture(tester.getCenter(lbKey('lc-num-flex-grow')));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    expect(lbKey('lc-num-flex-grow-drag'), findsOneWidget);
    for (var i = 0; i < 3; i++) {
      await g.moveBy(const Offset(kNumberDragPx, 0));
      await tester.pump();
    }
    await g.up();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect((await lbSaved(tester, s)).find('box')!.style['flex-grow'], '3');
    expect(tester.takeException(), isNull);
  });
}
