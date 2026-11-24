// 积木编辑器的“手感”测试：让位滑动、落下的咔哒、动画可打断、减弱动态、表达式交换、就地输入不压邻槽、提示条位置、空画布引导。
// 390×844，手势都是真的按下 → 分步移动 → 抬起，中途推帧，断言中间态和终态。
//   LOPI_SHOTS=1 flutter test --no-pub test/blocks_feel_test.dart   # 同时把截图写到 docs/screenshots/bk3-*.png
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/blocks/block_editor_canvas_view.dart';
import 'package:lopicode/blocks/block_editor_drag_view.dart';
import 'package:lopicode/blocks/block_geometry.dart';
import 'package:lopicode/lowcode/logic_blocks.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:material_ui/material_ui.dart';

import 'blocks_motion_test.dart' show bigDoc;
import 'screens_test.dart' show fontsLoaded, shot;
import 'support/blocks_fixture.dart';
import 'support/blocks_rig.dart';
import 'support/harness.dart';

LcDocument emptyDoc() => sampleDoc()..logic.handlers.clear();

Offset canvasAt(WidgetTester tester, Offset d) => tester.getTopLeft(find.byKey(const ValueKey('bk-canvas'))) + d;

BkWorkspacePainter painterOf(WidgetTester tester) => tester.widget<CustomPaint>(find.byKey(const ValueKey('bk-canvas'))).painter! as BkWorkspacePainter;

/// 画布上某块积木在“让位前 / 让位后”的位置（画布坐标）。
Rect rectIn(dynamic layout, String id, LcBlockPath path) {
  final p = layout.placed(id)!;
  return (p.layout.blockAt(path)!.rect as Rect).shift(p.origin as Offset);
}

void main() {
  setUpAll(() async => fontsLoaded = await loadRealFonts());

  testWidgets('让位是滑过去的：中间态在起止之间，越来越近，到头正好；落点阴影同形；手上的积木被吸过去一半', (tester) async {
    final rig = Rig(sampleDoc());
    await rig.pump(tester);
    final id = rig.h(0).id;
    final g = await rig.liftFromPalette(tester, '交互', 'block-alert');
    // 拿起：从原大放大到 104%（中途略微过冲）。
    expect(rig.s.pieceLook.scale, 1.0);
    await tester.pump(const Duration(milliseconds: 40));
    expect(rig.s.pieceLook.scale, greaterThan(1.0));
    await tester.pump(const Duration(milliseconds: 200));
    expect(rig.s.pieceLook.scale, closeTo(1.04, 1e-6));

    final to = rig.stackSnap(id, const [], 1);
    await rig.glide(tester, g, to + const Offset(14, 10), steps: 3);
    final d = rig.s.drag!;
    expect(d.target, isNotNull);
    expect((d.ghost!.start, d.ghost!.count), (1, 1));
    final from = rectIn(d.base, id, [lcStep(1)]), end = rectIn(d.display, id, [lcStep(2)]);
    expect(end.top - from.top, greaterThan(30), reason: '“如果”要往下让出一块的高度');

    // 让位到一半。
    expect(rig.s.roomT, inExclusiveRange(0, 1));
    final mid1 = rig.s.shownRect(id, [lcStep(2)])!;
    expect(mid1.top, inExclusiveRange(from.top, end.top));
    expect(painterOf(tester).motion, isNotNull);
    expect(painterOf(tester).ghostAlpha, inExclusiveRange(0, 1), reason: '落点阴影跟着淡入');
    // 落点阴影那一块和手上的同形（同一种积木、同样的宽高）。
    final ghost = d.display.placed(id)!.layout.blockAt([lcStep(1)])!;
    expect(ghost.block!.op, 'alert');
    expect(ghost.rect.size, d.piece.blocks.single.rect.size);
    expect(rig.s.shownRect(id, [lcStep(1)]), ghost.rect.shift(d.display.placed(id)!.origin), reason: '阴影不滑，直接在落点');

    await tester.pump(const Duration(milliseconds: 32));
    final mid2 = rig.s.shownRect(id, [lcStep(2)])!;
    expect(mid2.top, greaterThan(mid1.top));
    expect(mid2.top, lessThan(end.top));
    // 上面那块不动。
    expect(rig.s.shownRect(id, [lcStep(0)]), rectIn(d.display, id, [lcStep(0)]));

    await tester.pump(const Duration(milliseconds: 200));
    expect(rig.s.roomT, 1);
    expect(rig.s.shownRect(id, [lcStep(2)]), end);
    expect(painterOf(tester).motion, isNull);
    expect(tester.binding.hasScheduledFrame, isFalse, reason: '让完位就不再刷帧');

    // 手上的积木被吸向落点：画的位置在“跟手的位置”和落点正中间。
    final hand = rig.s.viewOf(to + const Offset(14, 10)) - rig.s.grabOffset * rig.s.zoom;
    final anchor = rig.s.toView(d.target!.anchor);
    expect(rig.s.pieceShownAt.dx, closeTo((hand.dx + anchor.dx) / 2, 0.01));
    expect(rig.s.pieceShownAt.dy, closeTo((hand.dy + anchor.dy) / 2, 0.01));
    expect(tester.getTopLeft(find.byKey(const ValueKey('bk-drag-piece'))).dy, lessThan(rig.s.globalOf(hand).dy + 1));

    // 挪开：合拢也是滑的。
    await rig.glide(tester, g, canvasAt(tester, const Offset(330, 40)), steps: 2);
    expect(rig.s.drag!.target, isNull);
    final back = rig.s.shownRect(id, [lcStep(1)])!;
    expect(back.top, inExclusiveRange(from.top, end.top));
    await tester.pump(const Duration(milliseconds: 200));
    expect(rig.s.shownRect(id, [lcStep(1)]), from);
    await rig.drop(tester, g);
    expect(rig.edits, 0);
  });

  testWidgets('放下：飞向落点 → 到位改模型 → 轻弹；总共不超过 220 毫秒', (tester) async {
    final rig = Rig(sampleDoc());
    await rig.pump(tester);
    final id = rig.h(0).id;
    final g = await rig.liftFromPalette(tester, '交互', 'block-alert');
    await rig.glide(tester, g, rig.stackSnap(id, const [], 1) + const Offset(14, 10));
    await tester.pump(const Duration(milliseconds: 200));
    final anchor = rig.s.toView(rig.s.drag!.target!.anchor);
    final start = rig.s.pieceShownAt;

    await g.up();
    await tester.pump();
    expect(rig.s.busy, isTrue);
    expect(rig.edits, 0, reason: '还在飞，没改模型');
    await tester.pump(const Duration(milliseconds: 60));
    final flying = rig.s.pieceLook;
    expect(flying.scale, 1.04);
    expect((flying.at - anchor).distance, lessThan((start - anchor).distance * 0.5), reason: '缓出：一半时间已经飞过大半');
    expect((flying.at - anchor).distance, greaterThan(0));

    await tester.pump(const Duration(milliseconds: 61));
    expect(rig.edits, 1, reason: '120 毫秒到位，模型改好');
    expect(rig.s.drag, isNull);
    expect(rig.s.busy, isFalse);
    expect(rig.ops(0), ['changeVar', 'alert', 'if', 'repeat']);
    expect(rig.s.selection!.path, [lcStep(1)]);
    // 轻弹进行中：只弹落下的那一块。
    final pulse = painterOf(tester).pulse!;
    expect((pulse.scriptId, pulse.range!.start, pulse.range!.count), (id, 1, 1));
    await tester.pump(const Duration(milliseconds: 16)); // 轻弹的第一帧
    await tester.pump(const Duration(milliseconds: 50));
    expect(painterOf(tester).pulse!.t, inExclusiveRange(0, 1));
    await tester.pump(const Duration(milliseconds: 51));
    expect(painterOf(tester).pulse, isNull, reason: '120 + 100 = 220 毫秒全部结束');
    expect(BkEditorDrag.dropTime + BkEditorCanvas.pulseTime, lessThanOrEqualTo(const Duration(milliseconds: 220)));
    await tester.pumpAndSettle();
    expect(rig.edits, 1);
  });

  testWidgets('动画不挡手：飞到一半又按下去，模型当场改好，新的手势照常接', (tester) async {
    final rig = Rig(sampleDoc());
    await rig.pump(tester);
    final id = rig.h(0).id;
    var g = await rig.liftFromPalette(tester, '交互', 'block-alert');
    await rig.glide(tester, g, rig.stackSnap(id, const [], 1));
    await g.up();
    await tester.pump(const Duration(milliseconds: 30));
    expect(rig.s.busy, isTrue);
    expect(rig.edits, 0);

    // 立刻在空白处按下去拖：上一个动作当场落定，这一下照常平移。
    final pan = rig.s.pan;
    g = await tester.startGesture(canvasAt(tester, const Offset(350, 300)));
    expect(rig.edits, 1);
    expect(rig.s.busy, isFalse);
    expect(rig.s.drag, isNull);
    expect(rig.ops(0), ['changeVar', 'alert', 'if', 'repeat']);
    await g.moveBy(const Offset(-20, -30));
    await tester.pump(const Duration(milliseconds: 16));
    await g.moveBy(const Offset(-20, -30));
    await tester.pump(const Duration(milliseconds: 16));
    expect(rig.s.pan.dy, lessThan(pan.dy - 20));
    await g.up();
    await tester.pumpAndSettle();

    // 弹回去的动画中途，又把同一块抓起来：也接得住，这次放到最前面。
    await rig.show(tester, 0, [lcStep(3)]);
    g = await rig.lift(tester, rig.grip(0, [lcStep(3)]));
    await rig.glide(tester, g, canvasAt(tester, const Offset(340, 60)));
    await g.up();
    await tester.pump(const Duration(milliseconds: 40));
    expect(rig.s.busy, isTrue);
    final first = rig.s.drag;
    g = await rig.lift(tester, rig.grip(0, [lcStep(3)]));
    expect(rig.s.busy, isFalse);
    expect(identical(rig.s.drag, first), isFalse, reason: '是一次新的拖动');
    expect(rig.edits, 1);
    await rig.glide(tester, g, rig.stackSnap(id, const [], 0));
    await rig.drop(tester, g);
    expect(rig.ops(0), ['repeat', 'changeVar', 'alert', 'if']);
    expect(rig.edits, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('减弱动态效果：让位、放下、弹回、删除都直接到终态', (tester) async {
    final rig = Rig(sampleDoc());
    await rig.pump(tester, reduceMotion: true);
    expect(rig.s.reduceMotion, isTrue);
    final id = rig.h(0).id;
    var g = await rig.liftFromPalette(tester, '交互', 'block-alert');
    expect(rig.s.pieceLook.scale, 1.04);
    await rig.glide(tester, g, rig.stackSnap(id, const [], 1) + const Offset(14, 10), steps: 2);
    final d = rig.s.drag!;
    expect(rig.s.roomT, 1);
    expect(rig.s.shownRect(id, [lcStep(2)]), rectIn(d.display, id, [lcStep(2)]));
    expect(painterOf(tester).motion, isNull);
    expect(rig.s.roomAnim.isAnimating, isFalse);
    // 不吸：手上的积木老老实实跟手。
    expect(rig.s.pieceShownAt, rig.s.viewOf(rig.stackSnap(id, const [], 1) + const Offset(14, 10)) - rig.s.grabOffset);

    await g.up();
    await tester.pump();
    expect(rig.edits, 1, reason: '松手当场落定');
    expect(rig.s.drag, isNull);
    expect(rig.s.busy, isFalse);
    expect(painterOf(tester).pulse, isNull);
    expect(rig.s.pulseAnim.isAnimating, isFalse);
    expect(rig.s.settleAnim.isAnimating, isFalse);

    // 弹回。
    g = await rig.lift(tester, rig.grip(0, [lcStep(3)]));
    await rig.glide(tester, g, canvasAt(tester, const Offset(340, 60)), steps: 2);
    await g.up();
    await tester.pump();
    expect(rig.s.drag, isNull);
    expect(rig.s.busy, isFalse);
    expect(rig.edits, 1);

    // 删除。
    g = await rig.lift(tester, rig.grip(0, [lcStep(3)]));
    await rig.glide(tester, g, tester.getCenter(find.byKey(const ValueKey('bk-trash'))), steps: 2);
    await g.up();
    await tester.pump();
    expect(rig.s.drag, isNull);
    expect(rig.ops(0), ['changeVar', 'alert', 'if']);
    expect(rig.edits, 2);
    await tester.pump(const Duration(milliseconds: 20));
    expect(rig.s.roomAnim.isAnimating || rig.s.settleAnim.isAnimating || rig.s.liftAnim.isAnimating, isFalse);
    await tester.pumpAndSettle(const Duration(seconds: 5));
  });

  testWidgets('拖动中：能接的地方给淡提示；删除是缩小淡出；积木盒里按住有按下态', (tester) async {
    final rig = Rig(sampleDoc());
    await rig.pump(tester);
    expect(painterOf(tester).hints, isNull);

    // 按下态。
    await tester.tap(find.byKey(const ValueKey('bk-palette-tab-交互')));
    await tester.pumpAndSettle();
    final item = find.byKey(const ValueKey('bk-palette-item-block-alert'));
    AnimatedScale feel() => tester.widget<AnimatedScale>(find.descendant(of: item, matching: find.byType(AnimatedScale)));
    expect(feel().scale, 1);
    var g = await tester.startGesture(tester.getTopLeft(item) + const Offset(10, 20));
    await tester.pump(const Duration(milliseconds: 60));
    expect(feel().scale, 0.96);
    await tester.pump(const Duration(milliseconds: 160));
    expect(rig.s.drag, isNotNull, reason: '按住就拿出来了');
    expect(painterOf(tester).hints, BkSnapKind.statement);
    await g.up();
    await tester.pumpAndSettle();
    expect(feel().scale, 1);
    expect(rig.edits, 0);

    g = await rig.liftFromPalette(tester, '变量', 'expr-var');
    expect(painterOf(tester).hints, BkSnapKind.expr);
    await g.up();
    await tester.pumpAndSettle();
    expect(painterOf(tester).hints, isNull);

    // 删除：缩小 + 淡出，160 毫秒后才真的删。
    g = await rig.lift(tester, rig.grip(0, [lcStep(2)]));
    await rig.glide(tester, g, tester.getCenter(find.byKey(const ValueKey('bk-trash'))));
    await g.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    final look = rig.s.pieceLook;
    expect(look.scale, inExclusiveRange(0, 1.04));
    expect(look.opacity, inExclusiveRange(0, 1));
    expect(rig.edits, 0);
    await tester.pumpAndSettle();
    expect(rig.ops(0), ['changeVar', 'if']);
    expect(rig.edits, 1);
  });

  testWidgets('表达式拖进有值的槽：从槽里拖来的＝交换；积木盒来的盖掉旧值，给一条带“撤销”的提示', (tester) async {
    final rig = Rig(sampleDoc());
    await rig.pump(tester);
    final id = rig.h(0).id;
    final p = rig.placed(0);
    final not = p.layout.allSlots.map((e) => e.$2).firstWhere((sl) => sl.expr?.kind == 'not').expr!;
    var g = await rig.lift(tester, rig.s.globalOf(rig.s.toView(p.origin + not.rect.centerLeft + const Offset(9, 0))));
    await rig.glide(tester, g, rig.exprSnap(id, [lcStep(1), lcStep(0)], 'message'));
    expect(rig.s.drag!.target, isNotNull);
    await tester.pump(const Duration(milliseconds: 200));
    await rig.drop(tester, g);
    final cond = rig.h(0).body[1].args['cond'] as Map<String, dynamic>;
    expect(rig.h(0).body[1].body[0].args['message'], exNot(exVar('ok')));
    expect(cond['r'], exText('点太多次啦'), reason: '换下来的文字回到“不是 ok”原来的槽里');
    expect(rig.edits, 1);
    expect(find.byKey(const ValueKey('bk-toast')), findsNothing, reason: '谁也没丢，不用提示');

    // 积木盒里的新变量盖住“不是 ok”：旧值没处去 → 提示 + 撤销。
    g = await rig.liftFromPalette(tester, '变量', 'expr-var');
    await rig.glide(tester, g, rig.exprSnap(id, [lcStep(1), lcStep(0)], 'message'));
    await rig.drop(tester, g);
    expect(exprKind(rig.h(0).body[1].body[0].args['message']), 'var');
    expect(rig.edits, 2);
    expect(find.text('原来的值被换掉了。'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('bk-toast-action')));
    await tester.pumpAndSettle();
    expect(rig.h(0).body[1].body[0].args['message'], exNot(exVar('ok')), reason: '撤销把旧值找回来');
    expect(find.byKey(const ValueKey('bk-toast')), findsNothing);

    // 盖住的是默认值（数字 0 这种没内容的）不啰嗦。
    g = await rig.liftFromPalette(tester, '变量', 'expr-var');
    await rig.glide(tester, g, rig.exprSnap(id, [lcStep(2)], 'times'));
    await rig.drop(tester, g);
    expect(exprKind(rig.h(0).body[2].args['times']), 'var');
    await tester.pumpAndSettle(const Duration(seconds: 5));
  });

  testWidgets('就地输入框正好盖在槽上，不压旁边的槽；打字时积木跟着变宽；提示条在积木盒上面、键盘弹出也看得见', (tester) async {
    final rig = Rig(sampleDoc());
    await rig.pump(tester);
    final box = find.byKey(const ValueKey('bk-inline-box'));

    /// 同一块积木上别的叶子槽（屏幕坐标）。
    List<Rect> others(String editingText) {
      final pl = (rig.s.previewLayout ?? rig.s.layout).placed(rig.h(0).id)!;
      return [
        for (final (b, sl) in pl.layout.allSlots)
          if (!b.isHat && bkSameBlockPath(b.path, [lcStep(1)]) && sl.expr == null && sl.text != editingText)
            Rect.fromPoints(rig.s.globalOf(rig.s.toView(pl.origin + sl.rect.topLeft)), rig.s.globalOf(rig.s.toView(pl.origin + sl.rect.bottomRight))),
      ];
    }

    await tester.tapAt(rig.slot(0, [lcStep(1)], (sl) => sl.text == '10'));
    await tester.pumpAndSettle();
    expect(box, findsOneWidget);
    var r = tester.getRect(box);
    expect(others('10'), isNotEmpty);
    for (final o in others('10')) {
      expect(r.overlaps(o), isFalse, reason: '输入框 $r 压住了旁边的槽 $o');
    }
    expect(find.byType(Material).evaluate().where((e) => (e.widget as Material).elevation == 6), isEmpty, reason: '输入框不带投影');
    final w0 = r.width;
    final blockW = rig.s.shownRect(rig.h(0).id, [lcStep(1)])!.width;

    await tester.enterText(find.byKey(const ValueKey('bk-inline-input')), '1234567890');
    await tester.pump();
    r = tester.getRect(box);
    expect(r.width, greaterThan(w0 + 20), reason: '框跟着字变宽');
    expect(rig.s.shownRect(rig.h(0).id, [lcStep(1)])!.width, greaterThan(blockW + 20), reason: '积木跟着变宽，把右边的推开');
    for (final o in others('1234567890')) {
      expect(r.overlaps(o), isFalse, reason: '输入框 $r 压住了旁边的槽 $o');
    }
    expect(rig.edits, 0);

    // 键盘弹出（底下 300 被占）、填错了点别处：提示条还在看得见的地方。
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await tester.enterText(find.byKey(const ValueKey('bk-inline-input')), '12a');
    await tester.pump();
    await tester.tapAt(canvasAt(tester, const Offset(360, 12)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final toast = find.byKey(const ValueKey('bk-toast'));
    expect(find.textContaining('不是数字'), findsOneWidget);
    expect(tester.getRect(toast).bottom, lessThan(844 - 300));
    expect(tester.getRect(toast).top, greaterThan(tester.getRect(find.byKey(const ValueKey('bk-canvas'))).top));
    expect(rig.edits, 0);
    tester.view.resetViewInsets();
    await tester.pumpAndSettle(const Duration(seconds: 3));

    // 平时：提示条在积木盒上沿之上，不盖最上面那串的帽子。
    final g = await rig.lift(tester, rig.grip(0, [lcStep(2)]));
    await rig.glide(tester, g, canvasAt(tester, const Offset(340, 40)));
    await rig.drop(tester, g);
    final t = tester.getRect(find.byKey(const ValueKey('bk-toast')));
    final dock = tester.getRect(find.byKey(const ValueKey('bk-dock')));
    final hat = rig.placed(0).layout.hat!.rect.shift(rig.placed(0).origin);
    final hatOnScreen = Rect.fromPoints(rig.s.globalOf(rig.s.toView(hat.topLeft)), rig.s.globalOf(rig.s.toView(hat.bottomRight)));
    expect(t.bottom, lessThanOrEqualTo(dock.top));
    expect(t.top, greaterThan(dock.top - 130));
    expect(t.overlaps(hatOnScreen), isFalse);
    expect(t.overlaps(tester.getRect(find.byKey(const ValueKey('bk-undo')))), isFalse, reason: '也不盖右下角的撤销');
    await tester.pumpAndSettle(const Duration(seconds: 3));
  });

  testWidgets('空画布引导：一句话 + 往上走的箭头（动两下就停）；拖出第一块后消失；双击空白回到 100%', (tester) async {
    final rig = Rig(emptyDoc());
    await rig.pump(tester);
    final arrow = find.byKey(const ValueKey('bk-empty-arrow'));
    expect(find.byKey(const ValueKey('bk-empty')), findsOneWidget);
    expect(arrow, findsOneWidget);
    final rest = tester.getCenter(arrow);
    expect(tester.binding.hasScheduledFrame, isFalse, reason: '箭头动两下就停，不一直耗着');
    expect(tester.getRect(arrow).bottom, lessThan(tester.getRect(find.byKey(const ValueKey('bk-dock'))).top));

    // 没有事件时点语句积木：提示 + 箭头再动两下。
    await tester.tap(find.byKey(const ValueKey('bk-palette-tab-交互')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('bk-palette-item-block-alert')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.textContaining('先从“事件”里拿一块出来'), findsOneWidget);
    expect((tester.getCenter(arrow) - rest).dy.abs(), greaterThan(2), reason: '箭头在动');
    await tester.pumpAndSettle(const Duration(seconds: 3));
    expect(tester.getCenter(arrow), rest);

    // 拖一块事件上来：拖的时候引导就让开，放下以后没有了。
    final g = await rig.liftFromPalette(tester, 'event', 'hat-click');
    expect(find.byKey(const ValueKey('bk-empty')), findsNothing);
    await rig.glide(tester, g, canvasAt(tester, const Offset(60, 120)));
    await g.up();
    await tester.pump();
    expect(rig.handlers, hasLength(1), reason: '帽子不用飞，松手就在');
    expect(painterOf(tester).pulse!.range, isNull, reason: '新的一串整串轻弹');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('bk-empty')), findsNothing);
    expect(arrow, findsNothing);

    // 双击空白：回到 100%、回到起始位置；隔久了的两下不算。
    final blank = canvasAt(tester, const Offset(330, 180));
    final a = await tester.startGesture(blank, pointer: 31);
    final b = await tester.startGesture(blank + const Offset(0, 200), pointer: 32);
    await tester.pump();
    await b.moveBy(const Offset(0, -40));
    await tester.pump();
    await b.moveBy(const Offset(0, -40));
    await tester.pump();
    await a.up();
    await b.up();
    await tester.pumpAndSettle();
    final zoomed = rig.s.zoom;
    expect(zoomed, lessThan(0.9));
    await tester.tapAt(blank);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tapAt(blank);
    await tester.pump(const Duration(milliseconds: 500));
    expect(rig.s.zoom, zoomed);
    await tester.tapAt(blank);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tapAt(blank);
    await tester.pumpAndSettle();
    expect(rig.s.zoom, 1);
    expect(rig.s.pan, Offset.zero);
    expect(rig.edits, 1);
  });

  testWidgets('空画布引导：减弱动态效果时箭头不动', (tester) async {
    final rig = Rig(emptyDoc());
    usePhoneViewport(tester);
    await rig.pump(tester, reduceMotion: true);
    final arrow = find.byKey(const ValueKey('bk-empty-arrow'));
    final rest = tester.getCenter(arrow);
    await tester.tap(find.byKey(const ValueKey('bk-palette-tab-交互')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('bk-palette-item-block-alert')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(tester.getCenter(arrow), rest);
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pumpAndSettle(const Duration(seconds: 3));
  });

  testWidgets('性能冒烟（界面）：200 块的一串，让位动画的每一帧都不重新排版；整段拖动的排版次数有上限', (tester) async {
    final rig = Rig(bigDoc(200));
    await rig.pump(tester);
    final id = rig.h(0).id;
    final g = await rig.liftFromPalette(tester, '交互', 'block-alert');
    final lifted = rig.s.engine.scriptLayouts;
    final watch = Stopwatch()..start();
    var targets = 0;
    for (var i = 1; i <= 3; i++) {
      await rig.glide(tester, g, rig.stackSnap(id, const [], i), steps: 4);
      expect(rig.s.drag!.target, isNotNull);
      targets++;
      final settled = rig.s.engine.scriptLayouts;
      expect(painterOf(tester).motion, isNotNull);
      printOnFailure('i=$i moves=${rig.s.motion.moveCount} target=${rig.s.drag!.target!.snap.index} ghost=${rig.s.drag!.ghost}');
      if (i == 1) expect(rig.s.motion.moveCount, greaterThan(150), reason: '后面一百多块都在滑');
      for (var f = 0; f < 12; f++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(rig.s.engine.scriptLayouts, settled, reason: '动画帧只插值，不排版');
    }
    watch.stop();
    // 每挪一步最多换两次落点（离开旧的、对上新的），每次最多重排一串。
    expect(rig.s.engine.scriptLayouts - lifted, lessThanOrEqualTo(targets * 4 * 2));
    expect(watch.elapsedMilliseconds, lessThan(8000), reason: '48 帧；阈值放得很宽，只防明显退化');
    await rig.drop(tester, g);
    expect(rig.h(0).body, hasLength(201));
    expect(tester.takeException(), isNull);
  });

  for (final (mode, suffix) in [(ThemeMode.light, 'light'), (ThemeMode.dark, 'dark')]) {
    testWidgets('截图：让位到一半 / 完成、放下瞬间、空画布引导、就地编辑、表达式交换前后（$suffix）', (tester) async {
      // 测试环境默认把投影画成一圈实心黑边（debugDisableShadows），截出来的浮层会多一圈真机上没有的粗边。
      // 截图时按真机的画法来；测试结束前必须改回去。
      debugDisableShadows = false;
      try {
        var rig = Rig(sampleDoc());
        await rig.pump(tester, mode: mode);
        final id = rig.h(0).id;
        var g = await rig.liftFromPalette(tester, '交互', 'block-alert');
        await tester.pump(const Duration(milliseconds: 200));
        await rig.glide(tester, g, rig.stackSnap(id, [lcStep(1)], 1) + const Offset(10, 12), steps: 3);
        await tester.pump(const Duration(milliseconds: 40));
        expect(rig.s.roomT, inExclusiveRange(0, 1));
        await shot(tester, 'bk3-drag-half-$suffix');
        await tester.pump(const Duration(milliseconds: 300));
        await shot(tester, 'bk3-drag-snap-$suffix');
        await g.up();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 120));
        await tester.pump(const Duration(milliseconds: 30));
        expect(painterOf(tester).pulse, isNotNull);
        await shot(tester, 'bk3-drop-$suffix');
        await tester.pumpAndSettle();
        expect([for (final b in rig.h(0).body[1].body) b.op], ['alert', 'alert', 'setVar']);

        // 表达式交换前后。
        await tester.tapAt(canvasAt(tester, const Offset(378, 220)));
        await tester.pumpAndSettle(const Duration(milliseconds: 400));
        final p = rig.placed(0);
        final not = p.layout.allSlots.map((e) => e.$2).firstWhere((sl) => sl.expr?.kind == 'not').expr!;
        g = await rig.lift(tester, rig.s.globalOf(rig.s.toView(p.origin + not.rect.centerLeft + const Offset(9, 0))));
        await rig.glide(tester, g, rig.exprSnap(id, [lcStep(1), lcStep(0)], 'message') + const Offset(8, 10));
        await tester.pump(const Duration(milliseconds: 300));
        await shot(tester, 'bk3-swap-before-$suffix');
        await rig.drop(tester, g);
        await shot(tester, 'bk3-swap-after-$suffix');

        // 就地编辑。
        await tester.tapAt(rig.slot(0, [lcStep(1)], (sl) => sl.text == '10'));
        await tester.pumpAndSettle();
        await shot(tester, 'bk3-inline-number-$suffix');
        await tester.enterText(find.byKey(const ValueKey('bk-inline-input')), '12345');
        await tester.pump();
        await shot(tester, 'bk3-inline-typed-$suffix');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();

        // 提示条。
        g = await rig.lift(tester, rig.grip(0, [lcStep(2)]));
        await rig.glide(tester, g, canvasAt(tester, const Offset(340, 40)));
        await rig.drop(tester, g);
        await shot(tester, 'bk3-toast-$suffix');
        await tester.pumpAndSettle(const Duration(seconds: 3));

        // 空画布引导。
        rig = Rig(emptyDoc());
        await rig.pump(tester, mode: mode);
        await shot(tester, 'bk3-empty-$suffix');
        expect(tester.takeException(), isNull);
      } finally {
        debugDisableShadows = true;
      }
    });
  }
}
