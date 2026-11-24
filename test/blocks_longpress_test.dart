// 积木编辑器的手势分工（真机反馈第二轮第 3 条）：390×844。
// 单指滑动一律平移画布（起点在积木上也一样）；长按 0.28 秒才拿起积木；长按期间动了＝平移。
//   LOPI_SHOTS=1 flutter test --no-pub test/blocks_longpress_test.dart   # 同时把截图写到 docs/screenshots/bk4-*.png
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/blocks/block_drag.dart';
import 'package:lopicode/blocks/block_editor_canvas_view.dart';
import 'package:lopicode/blocks/block_geometry.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:material_ui/material_ui.dart';

import 'backend_screen_test.dart' as be;
import 'screens_test.dart' show fontsLoaded, shot;
import 'support/blocks_fixture.dart';
import 'support/blocks_rig.dart';
import 'support/harness.dart';

const click = 'HapticFeedbackType.selectionClick', medium = 'HapticFeedbackType.mediumImpact';

Finder k(String key) => find.byKey(ValueKey(key));

/// 一根手指从 `from` 滑 `by` 这么远（分几步，中途推帧），不松手。
Future<TestGesture> swipe(WidgetTester tester, Offset from, Offset by, {int steps = 5}) async {
  final g = await tester.startGesture(from);
  await tester.pump(const Duration(milliseconds: 16));
  for (var i = 0; i < steps; i++) {
    await g.moveBy(by / steps.toDouble());
    await tester.pump(const Duration(milliseconds: 16));
  }
  return g;
}

/// 第 0 串“如果”条件里那块“不是”（一个拼在槽里的值积木）在屏幕的哪里。
Offset notAt(Rig rig) {
  final p = rig.placed(0);
  final not = p.layout.allSlots.map((e) => e.$2).firstWhere((sl) => sl.expr?.kind == 'not').expr!;
  return rig.s.globalOf(rig.s.toView(p.origin + not.rect.centerLeft + const Offset(9, 0)));
}

void main() {
  setUpAll(() async => fontsLoaded = await loadRealFonts());

  test('长按时长在 250–300 毫秒之间', () {
    expect(BkEditorCanvas.longPressAfter.inMilliseconds, inInclusiveRange(250, 300));
  });

  testWidgets('起点落在积木上的单指滑动只平移画布：语句块、帽子、值积木、槽都一样；模型不变、不震动', (tester) async {
    final rig = Rig(sampleDoc());
    final haptics = captureHaptics(tester);
    final before = rig.doc.encode();
    await rig.pump(tester);
    final rev = rig.host.revision;
    final starts = <String, Offset Function()>{
      '语句块': () => rig.grip(0, [lcStep(1)]),
      '帽子': () => rig.grip(0, const []),
      '值积木': () => notAt(rig),
      '直接填的槽': () => rig.slot(0, [lcStep(0)], (s) => s.look == BkSlotLook.field),
    };
    for (final MapEntry(key: name, value: at) in starts.entries) {
      final pan0 = rig.s.pan;
      final origins = [for (final p in rig.s.layout.scripts) p.origin];
      final g = await swipe(tester, at(), const Offset(-20, -60));
      expect(rig.s.drag, isNull, reason: '$name：滑动不能把积木拖起来');
      expect(find.byKey(const ValueKey('bk-trash')), findsNothing, reason: name);
      // 滑完停住不动再等一会儿：也不会补一个长按。
      await tester.pump(const Duration(milliseconds: 600));
      expect(rig.s.drag, isNull, reason: '$name：已经判成平移了，停住也不拿起');
      await g.up();
      await tester.pumpAndSettle();
      expect(rig.s.pan - pan0, const Offset(-20, -60), reason: '$name：画布跟着手指走了这么多');
      expect([for (final p in rig.s.layout.scripts) p.origin], origins, reason: '$name：积木在画布上的位置没变');
      expect(rig.s.selection, isNull, reason: '$name：滑动不算点');
      expect(find.byKey(const ValueKey('bk-replace')), findsNothing, reason: name);
      expect(find.byKey(const ValueKey('bk-inline-input')), findsNothing, reason: name);
      // 滑回去，下一轮从同一个地方开始。
      final back = await swipe(tester, tester.getTopLeft(k('bk-canvas')) + const Offset(370, 300), const Offset(20, 60));
      await back.up();
      await tester.pumpAndSettle();
      expect(rig.s.pan, pan0);
    }
    expect(rig.edits, 0);
    expect(rig.host.revision, rev);
    expect(rig.history.canUndo, isFalse);
    expect(rig.doc.encode(), before);
    expect(rig.handlers.every((h) => h.x == null && h.y == null), isTrue);
    expect(haptics, isEmpty);
  });

  testWidgets('长按 0.28 秒才拿起：到点之前没动静，到点震一次、被“拿起”放大，之后跟手、能吸附、松手改模型', (tester) async {
    final rig = Rig(sampleDoc());
    final haptics = captureHaptics(tester);
    await rig.pump(tester);
    final id = rig.h(0).id;
    final from = rig.grip(0, [lcStep(2)]);
    final g = await tester.startGesture(from);
    await tester.pump(const Duration(milliseconds: 250));
    expect(rig.s.drag, isNull, reason: '还没按够');
    expect(haptics, isEmpty);
    await tester.pump(const Duration(milliseconds: 40));
    expect(rig.s.drag, isNotNull, reason: '按够了：拿起来了');
    expect(rig.s.drag!.kind, BkDragKind.statement);
    expect([for (final b in rig.s.drag!.blocks) b.op], ['repeat']);
    expect(haptics, [medium], reason: '拿起的一瞬间震一次，只一次');
    expect(find.byKey(const ValueKey('bk-drag-piece')), findsOneWidget);
    expect(find.byKey(const ValueKey('bk-trash')), findsOneWidget);
    // “抬起”：从原大放大到 104%。
    expect(rig.s.pieceLook.scale, lessThan(1.04));
    await tester.pump(const Duration(milliseconds: 200));
    expect(rig.s.pieceLook.scale, closeTo(1.04, 0.001));
    // 手指没动：手上那块就在原处。
    expect(rig.s.pieceShownAt, rig.s.toView(rig.s.drag!.pieceOrigin!));
    expect(rig.edits, 0);

    // 之后跟手：挪到第 1 块前面，吸住。
    final pan0 = rig.s.pan;
    await rig.glide(tester, g, rig.stackSnap(id, const [], 1), steps: 8);
    expect(rig.s.pan, pan0, reason: '拿起以后手指动的是积木，不是画布');
    expect(rig.s.drag!.target, isNotNull);
    expect(rig.s.drag!.ghost!.start, 1);
    expect(haptics, contains(click), reason: '吸附的触感还在');
    expect(rig.edits, 0, reason: '还没松手');
    await rig.drop(tester, g);
    expect(rig.ops(0), ['changeVar', 'repeat', 'if']);
    expect(rig.edits, 1);
    expect(haptics.where((h) => h == medium), hasLength(1));
  });

  testWidgets('长按期间手指动了就变成平移：之后再怎么停也不会拿起；动得不到 8 像素不算动', (tester) async {
    final rig = Rig(sampleDoc());
    final haptics = captureHaptics(tester);
    final before = rig.doc.encode();
    await rig.pump(tester);
    final pan0 = rig.s.pan;
    var g = await tester.startGesture(rig.grip(0, [lcStep(1)]));
    await tester.pump(const Duration(milliseconds: 150));
    await g.moveBy(const Offset(0, -30));
    await tester.pump(const Duration(milliseconds: 16));
    expect(rig.s.pan - pan0, const Offset(0, -30));
    await tester.pump(const Duration(milliseconds: 500));
    expect(rig.s.drag, isNull);
    await g.moveBy(const Offset(0, -30));
    await tester.pump(const Duration(milliseconds: 16));
    expect(rig.s.pan - pan0, const Offset(0, -60));
    await g.up();
    await tester.pumpAndSettle();
    expect(rig.s.drag, isNull);
    expect(haptics, isEmpty);
    expect(rig.doc.encode(), before);

    // 手抖一点点（5 像素）不算动：照样拿得起来。
    g = await tester.startGesture(rig.grip(0, [lcStep(1)]));
    await tester.pump(const Duration(milliseconds: 100));
    await g.moveBy(const Offset(3, 4));
    await tester.pump(const Duration(milliseconds: 200));
    expect(rig.s.drag, isNotNull);
    expect(haptics, [medium]);
    // 没挪就松手：原样放回去，什么都不改。
    await rig.drop(tester, g);
    expect(rig.s.drag, isNull);
    expect(rig.edits, 0);
    expect(rig.doc.encode(), before);
  });

  testWidgets('按住期间落下第二根手指＝缩放，不拿起；两指都落在积木上也是缩放', (tester) async {
    final rig = Rig(sampleDoc());
    final haptics = captureHaptics(tester);
    await rig.pump(tester);
    final a = await tester.startGesture(rig.grip(0, [lcStep(1)]), pointer: 41);
    await tester.pump(const Duration(milliseconds: 120));
    final b = await tester.startGesture(rig.grip(0, [lcStep(2)]), pointer: 42);
    await tester.pump(const Duration(milliseconds: 400));
    expect(rig.s.drag, isNull);
    await b.moveBy(const Offset(0, 60));
    await tester.pump();
    await b.moveBy(const Offset(0, 60));
    await tester.pump();
    expect(rig.s.zoom, greaterThan(1.2));
    await a.up();
    await b.up();
    await tester.pumpAndSettle();
    expect(rig.s.drag, isNull);
    expect(rig.edits, 0);
    expect(haptics, isEmpty);
  });

  testWidgets('帽子：长按拿起整串，拖到别处放下（只改位置）', (tester) async {
    final rig = Rig(sampleDoc());
    await rig.pump(tester);
    final from = rig.grip(0, const []);
    final g = await rig.lift(tester, from);
    expect(rig.s.drag!.kind, BkDragKind.hat);
    await rig.glide(tester, g, from + const Offset(60, 90));
    await rig.drop(tester, g);
    expect(rig.h(0).x, isNotNull);
    expect(rig.ops(0), ['changeVar', 'if', 'repeat']);
    expect(rig.edits, 1);
  });

  testWidgets('槽里的值积木：长按拿起后拖走＝拖出来；拿起后没挪就松手＝弹“换成…”；直接填的槽长按＝直接弹“换成…”、不拿起', (tester) async {
    final rig = Rig(sampleDoc());
    final haptics = captureHaptics(tester);
    await rig.pump(tester);

    // 拿起后没挪就松手。
    var g = await tester.startGesture(notAt(rig));
    await tester.pump(const Duration(milliseconds: 300));
    expect(rig.s.drag!.kind, BkDragKind.expr, reason: '先被拿起来');
    expect(haptics, [medium]);
    expect(find.byKey(const ValueKey('bk-replace')), findsNothing, reason: '手还按着，不弹');
    await g.up();
    await tester.pumpAndSettle();
    expect(rig.s.drag, isNull, reason: '放回原处');
    expect(find.byKey(const ValueKey('bk-replace')), findsOneWidget);
    expect(rig.edits, 0);
    await tester.tapAt(const Offset(380, 80));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('bk-replace')), findsNothing);

    // 直接填的槽（数字框）：按够了直接弹，不拿起它所在的积木。
    haptics.clear();
    g = await tester.startGesture(rig.slot(0, [lcStep(0)], (s) => s.look == BkSlotLook.field));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(rig.s.drag, isNull);
    expect(find.byKey(const ValueKey('bk-replace')), findsOneWidget);
    expect(haptics, [click]);
    await g.up();
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(380, 80));
    await tester.pumpAndSettle();
    expect(rig.edits, 0);

    // 拿起后拖走：从槽里拖出来，放到另一块的条件槽里…这里拖到垃圾桶删掉最直接。
    g = await rig.lift(tester, notAt(rig));
    expect(rig.s.drag!.kind, BkDragKind.expr);
    await rig.glide(tester, g, tester.getCenter(find.byKey(const ValueKey('bk-trash'))));
    await rig.drop(tester, g);
    expect(find.byKey(const ValueKey('bk-replace')), findsNothing, reason: '挪过了：不弹“换成…”');
    final cond = rig.h(0).body[1].args['cond'] as Map<String, dynamic>;
    expect(cond['r'], isNot(isA<Map<String, dynamic>>().having((m) => m['e'], 'e', 'not')), reason: '“不是”被拖走了');
    expect(rig.edits, 1);
  });

  testWidgets('点一下还是选中、点槽还是就地编辑、点下拉还是弹菜单；按得慢一点（0.2 秒）也算点', (tester) async {
    final rig = Rig(sampleDoc());
    final haptics = captureHaptics(tester);
    await rig.pump(tester);
    await tester.tapAt(rig.grip(0, [lcStep(1)]));
    await tester.pumpAndSettle();
    expect(rig.s.selection!.path, [lcStep(1)]);
    expect(find.byKey(const ValueKey('bk-selection-bar')), findsOneWidget);

    // 慢一点的点。
    final g = await tester.startGesture(rig.grip(0, [lcStep(2)]));
    await tester.pump(const Duration(milliseconds: 200));
    await g.up();
    await tester.pumpAndSettle();
    expect(rig.s.drag, isNull);
    expect(rig.s.selection!.path, [lcStep(2)]);

    await tester.tapAt(rig.slot(0, [lcStep(0)], (s) => s.look == BkSlotLook.field));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('bk-inline-input')), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('bk-inline-input')), '7');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect((rig.h(0).body[0].args['by'] as Map<String, dynamic>)['v'], 7);

    await tester.tapAt(rig.slot(0, [lcStep(0)], (s) => s.look == BkSlotLook.dropdown && s.arg == 'name'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('bk-menu-msg')), findsOneWidget);
    await tester.tapAt(const Offset(380, 80));
    await tester.pumpAndSettle();
    expect(haptics.where((h) => h == medium), isEmpty, reason: '点不会触发“拿起”的震动');
  });

  testWidgets('积木盒：按住 0.18 秒或横着拖＝拿出来（震一次），拖到画布吸上去；竖着滑＝翻积木盒、不拿', (tester) async {
    final rig = Rig(sampleDoc());
    final haptics = captureHaptics(tester);
    await rig.pump(tester);
    final id = rig.h(0).id;

    // 按住拿出来。
    var g = await rig.liftFromPalette(tester, '交互', 'block-alert');
    expect(rig.s.drag!.isNew, isTrue);
    expect(haptics, [medium]);
    await rig.glide(tester, g, rig.stackSnap(id, const [], 1));
    await rig.drop(tester, g);
    expect(rig.ops(0), ['changeVar', 'alert', 'if', 'repeat']);

    // 横着拖：不用等。
    haptics.clear();
    final item = find.byKey(const ValueKey('bk-palette-item-block-alert'));
    final from = tester.getTopLeft(item) + const Offset(10, 20);
    g = await tester.startGesture(from);
    await tester.pump(const Duration(milliseconds: 16));
    await g.moveBy(const Offset(12, 0));
    await tester.pump(const Duration(milliseconds: 16));
    await g.moveBy(const Offset(12, 0));
    await tester.pump(const Duration(milliseconds: 16));
    expect(rig.s.drag, isNotNull, reason: '横着拖直接拿出来');
    expect(haptics, [medium]);
    await g.up();
    await tester.pumpAndSettle();
    expect(rig.edits, 1, reason: '在积木盒上方松手＝不要了');

    // 竖着滑：翻这一页，不拿。
    haptics.clear();
    final page = tester.state<ScrollableState>(find.descendant(of: find.byKey(const ValueKey('bk-palette-page-交互')), matching: find.byType(Scrollable)));
    final pos0 = page.position.pixels;
    g = await tester.startGesture(from);
    await tester.pump(const Duration(milliseconds: 16));
    for (var i = 0; i < 4; i++) {
      await g.moveBy(const Offset(0, -12));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(rig.s.drag, isNull);
    await tester.pump(const Duration(milliseconds: 400));
    expect(rig.s.drag, isNull, reason: '已经在滚了，停住也不拿');
    await g.up();
    await tester.pumpAndSettle();
    // 这一页积木少、没满（翻不动）时也一样不拿——以前这种情况下竖着滑会把积木误拿出来。
    if (page.position.maxScrollExtent > 0) expect(page.position.pixels, greaterThan(pos0));
    expect(haptics, isEmpty);
    expect(rig.edits, 1);
  });

  testWidgets('系统开了“减弱动态效果”：长按照样拿起、照样震，只是没有放大的过程', (tester) async {
    final rig = Rig(sampleDoc());
    final haptics = captureHaptics(tester);
    await rig.pump(tester, reduceMotion: true);
    final g = await tester.startGesture(rig.grip(0, [lcStep(2)]));
    await tester.pump(const Duration(milliseconds: 290));
    expect(rig.s.drag, isNotNull);
    expect(haptics, [medium]);
    expect(rig.s.pieceLook.scale, 1.04, reason: '直接是拿起的样子');
    await rig.drop(tester, g);
    expect(rig.edits, 0);
  });

  testWidgets('后端积木页也一样：在积木上滑＝平移，长按才拿起', (tester) async {
    await be.boot(tester, ProjectTemplate.backendBlocks, language: 'node');
    final haptics = captureHaptics(tester);
    final s = be.ed(tester);
    final route = be.doc(tester).routes.first;
    final before = be.doc(tester).encode();
    Offset grip() {
      final p = s.layout.placed(route.id)!;
      return s.globalOf(s.toView(p.origin + p.layout.blockAt([lcStep(0)])!.head.centerLeft + const Offset(7, 0)));
    }

    final pan0 = s.pan;
    var g = await swipe(tester, grip(), const Offset(0, -80));
    expect(s.drag, isNull);
    await g.up();
    await tester.pumpAndSettle();
    expect(s.pan - pan0, const Offset(0, -80));
    expect(be.doc(tester).encode(), before);
    expect(haptics, isEmpty);

    g = await tester.startGesture(grip());
    await tester.pump(const Duration(milliseconds: 300));
    expect(s.drag, isNotNull);
    expect(s.drag!.kind, BkDragKind.statement);
    expect(haptics, [medium]);
    await g.up();
    await tester.pumpAndSettle();
    expect(s.drag, isNull);
    expect(be.doc(tester).encode(), before, reason: '没挪就松手：原样放回');
  });

  for (final (mode, suffix) in [(ThemeMode.light, 'light'), (ThemeMode.dark, 'dark')]) {
    testWidgets('截图：长按抬起中（$suffix）', (tester) async {
      // 截图时投影按真机的画法来（测试环境默认画成一圈实心黑边）；结束前改回去。
      debugDisableShadows = false;
      try {
        final rig = Rig(sampleDoc());
        await rig.pump(tester, mode: mode);
        final g = await tester.startGesture(rig.grip(0, [lcStep(1)]));
        await tester.pump(const Duration(milliseconds: 290));
        expect(rig.s.drag, isNotNull);
        await tester.pump(const Duration(milliseconds: 200));
        await shot(tester, 'bk4-longpress-lift-$suffix');
        await rig.drop(tester, g);
      } finally {
        debugDisableShadows = true;
      }
    });
  }
}
