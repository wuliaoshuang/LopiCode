// 积木编辑器（BlockEditorView）的拖拽测试：390×844。手势都是真的按下 → 分步移动 → 抬起，中途推帧。
//   LOPI_SHOTS=1 flutter test --no-pub test/blocks_editor_test.dart   # 同时把截图写到 docs/screenshots/bk2-*.png
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/blocks/block_drag.dart';
import 'package:lopicode/lowcode/logic_blocks.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:material_ui/material_ui.dart';

import 'screens_test.dart' show fontsLoaded, shot;
import 'support/blocks_fixture.dart';
import 'support/blocks_rig.dart';
import 'support/harness.dart';

const click = 'HapticFeedbackType.selectionClick', light = 'HapticFeedbackType.lightImpact', medium = 'HapticFeedbackType.mediumImpact', heavy = 'HapticFeedbackType.heavyImpact';

void main() {
  setUpAll(() async => fontsLoaded = await loadRealFonts());

  testWidgets('自动排布不产生改动：打开、平移、缩放都不写文档、不进撤销', (tester) async {
    final rig = Rig(sampleDoc());
    final before = rig.doc.encode();
    await rig.pump(tester);
    expect(rig.s.layout.scripts, hasLength(3));
    expect(rig.s.layout.scripts.every((p) => p.auto), isTrue);
    final rev = rig.host.revision;

    // 单指拖空白处＝平移。
    final blank = tester.getTopLeft(find.byKey(const ValueKey('bk-canvas'))) + const Offset(360, 300);
    final g = await tester.startGesture(blank);
    await g.moveBy(const Offset(-30, -40));
    await tester.pump();
    await g.moveBy(const Offset(-30, -40));
    await tester.pump();
    await g.up();
    await tester.pumpAndSettle();
    expect(rig.s.pan.dy, lessThan(-50));
    expect(rig.s.drag, isNull);

    // 两指缩放。
    final a = await tester.startGesture(blank, pointer: 11);
    final b = await tester.startGesture(blank + const Offset(0, 100), pointer: 12);
    await tester.pump();
    await b.moveBy(const Offset(0, 60));
    await tester.pump();
    await b.moveBy(const Offset(0, 60));
    await tester.pump();
    await a.up();
    await b.up();
    await tester.pumpAndSettle();
    expect(rig.s.zoom, greaterThan(1.5));
    expect(rig.s.zoom, lessThanOrEqualTo(2.0));

    expect(rig.edits, 0);
    expect(rig.host.revision, rev);
    expect(rig.history.canUndo, isFalse);
    expect(rig.doc.encode(), before);
    expect(rig.handlers.every((h) => h.x == null && h.y == null), isTrue);
  });

  testWidgets('从积木盒拖出来，吸到一串的末尾：落点阴影、触感、一条撤销记录', (tester) async {
    final rig = Rig(sampleDoc());
    final haptics = captureHaptics(tester);
    await rig.pump(tester);
    final id = rig.h(1).id;
    await rig.show(tester, 1);
    final g = await rig.liftFromPalette(tester, '交互', 'block-alert');
    expect(rig.s.drag!.isNew, isTrue);
    await rig.glide(tester, g, rig.stackSnap(id, const [], 2));
    // 吸附中：有落点，画的排布里那一串多让出了一块。
    expect(rig.s.drag!.target, isNotNull);
    expect(rig.s.drag!.ghost!.scriptId, id);
    expect(rig.s.drag!.display.placed(id)!.layout.blockAt([lcStep(2)]), isNotNull);
    expect(haptics, contains(click));
    expect(rig.edits, 0, reason: '还没松手，模型不能动');
    await rig.drop(tester, g);
    expect(rig.ops(1), ['setVar', 'setProp', 'alert']);
    expect(rig.edits, 1);
    expect(haptics, contains(light));
    expect(rig.s.drag, isNull);
    // 落下的那块被选中。
    expect(rig.s.selection!.scriptId, id);
  });

  testWidgets('拖到两块之间、拖进 C 形口、拖进“否则”口', (tester) async {
    final rig = Rig(sampleDoc());
    await rig.pump(tester);
    final id = rig.h(0).id;

    var g = await rig.liftFromPalette(tester, '交互', 'block-alert');
    await rig.glide(tester, g, rig.stackSnap(id, const [], 1));
    expect(rig.s.drag!.target, isNotNull);
    await rig.drop(tester, g);
    expect(rig.ops(0), ['changeVar', 'alert', 'if', 'repeat']);

    // “重复”是个空的 C 形块（现在在第 4 块）。
    await rig.show(tester, 0, [lcStep(3)]);
    g = await rig.liftFromPalette(tester, '交互', 'block-log');
    await rig.glide(tester, g, rig.stackSnap(id, [lcStep(3)], 0));
    expect(rig.s.drag!.target, isNotNull);
    await rig.drop(tester, g);
    expect([for (final b in rig.h(0).body[3].body) b.op], ['log']);

    // “如果”的否则口里原来有一块，放到它后面。
    await rig.show(tester, 0, [lcStep(2), lcStep(0, inElse: true)]);
    g = await rig.liftFromPalette(tester, '交互', 'block-navigate');
    await rig.glide(tester, g, rig.stackSnap(id, [lcStep(2)], 1, inElse: true));
    expect(rig.s.drag!.target!.snap.inElse, isTrue);
    await rig.drop(tester, g);
    expect([for (final b in rig.h(0).body[2].orElse) b.op], ['setProp', 'navigate']);
    expect(rig.edits, 3);
  });

  testWidgets('拖一块带走它下面的整串；跨脚本；原位立即合拢', (tester) async {
    final rig = Rig(sampleDoc());
    await rig.pump(tester);
    final g = await rig.lift(tester, rig.grip(0, [lcStep(1)]));
    // 手上是“如果”和它下面的“重复”；原来那一串只剩一块。
    expect([for (final b in rig.s.drag!.blocks) b.op], ['if', 'repeat']);
    expect(rig.s.drag!.base.placed(rig.h(0).id)!.layout.blocks.where((b) => !b.isHat), hasLength(1));
    expect(find.byKey(const ValueKey('bk-trash')), findsOneWidget);
    // 另一串在下面：拖到画布下沿停一会儿，画布自己滚上来。
    final canvas = tester.getRect(find.byKey(const ValueKey('bk-canvas')));
    await rig.glide(tester, g, Offset(300, canvas.bottom - rig.s.dockHeight - 20));
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(rig.s.pan.dy, lessThan(-100));
    await rig.glide(tester, g, rig.stackSnap(rig.h(1).id, const [], 1));
    expect(rig.s.drag!.target!.scriptId, rig.h(1).id);
    await rig.drop(tester, g);
    expect(rig.ops(0), ['changeVar']);
    expect(rig.ops(1), ['setVar', 'if', 'repeat', 'setProp']);
    expect(rig.h(1).body[1].body, hasLength(2), reason: 'C 形块里面的跟着走');
    expect(rig.edits, 1);
  });

  testWidgets('同一串里换位置；放回原处等于没动；不能拖进自己里面', (tester) async {
    final rig = Rig(sampleDoc());
    await rig.pump(tester);
    final id = rig.h(0).id;
    var g = await rig.lift(tester, rig.grip(0, [lcStep(2)]));
    await rig.glide(tester, g, rig.stackSnap(id, const [], 0));
    await rig.drop(tester, g);
    expect(rig.ops(0), ['repeat', 'changeVar', 'if']);
    expect(rig.edits, 1);

    // 拿起来又放回原处。
    final from = rig.grip(0, [lcStep(2)]);
    g = await rig.lift(tester, from);
    await rig.glide(tester, g, rig.stackSnap(id, const [], 2));
    expect(rig.s.drag!.target!.noop, isTrue);
    await rig.drop(tester, g);
    expect(rig.ops(0), ['repeat', 'changeVar', 'if']);
    expect(rig.edits, 1, reason: '放回去不算改动');

    // 拖着“如果”：能拼的位置里没有它自己肚子里的；手指挪到它原来的口里也放不进去。
    final mouth = rig.grip(0, [lcStep(2), lcStep(0)]);
    g = await rig.lift(tester, from);
    final snaps = rig.s.drag!.base.placed(id)!.layout.snaps;
    expect(snaps.where((x) => x.parent.isNotEmpty && x.parent.first.index == 2), isEmpty);
    await rig.glide(tester, g, mouth);
    await rig.drop(tester, g);
    expect(rig.ops(0), ['repeat', 'changeVar', 'if']);
    expect(rig.h(0).body[2].body, hasLength(2));
    expect(rig.edits, 1);
  });

  testWidgets('放在空白处：弹回原位并提示，模型不变', (tester) async {
    final rig = Rig(sampleDoc());
    final haptics = captureHaptics(tester);
    await rig.pump(tester);
    await rig.show(tester, 1);
    final g = await rig.lift(tester, rig.grip(1, [lcStep(1)]));
    final canvas = tester.getTopLeft(find.byKey(const ValueKey('bk-canvas')));
    await rig.glide(tester, g, canvas + const Offset(350, 60));
    expect(rig.s.drag!.target, isNull);
    await g.up();
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.byKey(const ValueKey('bk-toast')), findsOneWidget);
    expect(find.textContaining('积木要接在事件下面'), findsOneWidget);
    await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));
    expect(rig.ops(1), ['setVar', 'setProp']);
    expect(rig.edits, 0);
    expect(haptics, contains(heavy));
    expect(rig.s.drag, isNull);
  });

  testWidgets('表达式：从积木盒拖进槽、从槽里拖出来放进另一个槽、类型不对只提醒', (tester) async {
    final rig = Rig(sampleDoc());
    await rig.pump(tester);
    final id = rig.h(0).id;
    // 变量 → “把 count 加上 [1]” 的那个槽。
    var g = await rig.liftFromPalette(tester, '状态', 'expr-var');
    expect(rig.s.drag!.kind, BkDragKind.expr);
    await rig.glide(tester, g, rig.exprSnap(id, [lcStep(0)], 'by'));
    expect(rig.s.drag!.target, isNotNull);
    await rig.drop(tester, g);
    expect(exprKind(rig.h(0).body[0].args['by']), 'var');
    expect(rig.edits, 1);

    // 把“如果”条件里右边的“不是 ok”拖出来，放到“弹出提示”的槽里。
    final p = rig.placed(0);
    final not = p.layout.allSlots.map((e) => e.$2).firstWhere((sl) => sl.expr?.kind == 'not').expr!;
    g = await rig.lift(tester, rig.s.globalOf(rig.s.toView(p.origin + not.rect.centerLeft + const Offset(9, 0))));
    expect(rig.s.drag!.kind, BkDragKind.expr);
    expect(exprKind(rig.s.drag!.expr), 'not');
    await rig.glide(tester, g, rig.exprSnap(id, [lcStep(1), lcStep(0)], 'message'));
    expect(rig.s.drag!.target, isNotNull);
    await rig.drop(tester, g);
    final cond = rig.h(0).body[1].args['cond'] as Map<String, dynamic>;
    expect(exprKind(rig.h(0).body[1].body[0].args['message']), 'not');
    expect(exprKind(cond['r']), isNot('not'));
    expect(cond['r'], exText('点太多次啦'), reason: '交换：被换下来的文字回到被拖走的那个槽里，不丢');
    expect(rig.edits, 2);

    // 数字拖到“如果”的条件（要是 / 否）：照样能放，只是提醒色。
    g = await rig.liftFromPalette(tester, '直接填', 'expr-num');
    await rig.glide(tester, g, rig.exprSnap(id, [lcStep(1)], 'cond'));
    expect(rig.s.drag!.target!.mismatch, isTrue);
    await rig.drop(tester, g);
    expect(exprKind(rig.h(0).body[1].args['cond']), 'num');
    expect(rig.edits, 3);
  });

  testWidgets('表达式放在空白处弹回；拖进垃圾桶＝槽恢复默认', (tester) async {
    final rig = Rig(sampleDoc());
    await rig.pump(tester);
    Offset notAt() {
      final p = rig.placed(0);
      final not = p.layout.allSlots.map((e) => e.$2).firstWhere((sl) => sl.expr?.kind == 'not').expr!;
      return rig.s.globalOf(rig.s.toView(p.origin + not.rect.centerLeft + const Offset(9, 0)));
    }

    var g = await rig.lift(tester, notAt());
    await rig.glide(tester, g, tester.getTopLeft(find.byKey(const ValueKey('bk-canvas'))) + const Offset(350, 30));
    await rig.drop(tester, g);
    expect(rig.edits, 0);
    expect(find.textContaining('槽'), findsOneWidget);

    g = await rig.lift(tester, notAt());
    await rig.glide(tester, g, tester.getCenter(find.byKey(const ValueKey('bk-trash'))));
    expect(rig.s.overTrash, isTrue);
    await rig.drop(tester, g);
    expect(rig.edits, 1);
    expect(exprKind((rig.h(0).body[1].args['cond'] as Map<String, dynamic>)['r']), isNot('not'));
  });

  testWidgets('拖到垃圾桶删除：高亮、触感；删帽子里面有积木先确认', (tester) async {
    final rig = Rig(sampleDoc());
    final haptics = captureHaptics(tester);
    await rig.pump(tester);
    var g = await rig.lift(tester, rig.grip(0, [lcStep(2)]));
    await rig.glide(tester, g, tester.getCenter(find.byKey(const ValueKey('bk-trash'))));
    expect(rig.s.overTrash, isTrue);
    expect(find.text('松手删除'), findsOneWidget);
    await rig.drop(tester, g);
    expect(rig.ops(0), ['changeVar', 'if']);
    expect(rig.edits, 1);
    expect(haptics, contains(medium));
    await rig.show(tester, 1);

    // 帽子：先问。取消＝弹回去。
    g = await rig.lift(tester, rig.grip(1, const []));
    await rig.glide(tester, g, tester.getCenter(find.byKey(const ValueKey('bk-trash'))));
    await g.up();
    await tester.pumpAndSettle();
    expect(find.text('删掉这一整串？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(rig.handlers, hasLength(3));
    expect(rig.edits, 1);
    expect(rig.s.drag, isNull);

    g = await rig.lift(tester, rig.grip(1, const []));
    await rig.glide(tester, g, tester.getCenter(find.byKey(const ValueKey('bk-trash'))));
    await g.up();
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(rig.handlers, hasLength(2));
    expect(rig.edits, 2);

    // 从积木盒拿出来又放回积木盒：什么都不发生。
    g = await rig.liftFromPalette(tester, '交互', 'block-alert');
    await g.moveBy(const Offset(20, 10));
    await tester.pump();
    await rig.drop(tester, g);
    expect(rig.edits, 2);
  });

  testWidgets('拖帽子＝移动整串：位置写回，别的串的位置一起固定；撤销后恢复', (tester) async {
    final rig = Rig(sampleDoc());
    await rig.pump(tester);
    final autos = [for (final p in rig.s.layout.scripts) p.origin];
    await rig.show(tester, 1);
    final from = rig.grip(1, const []);
    final g = await rig.lift(tester, from);
    expect(rig.s.drag!.kind, BkDragKind.hat);
    await rig.glide(tester, g, from + const Offset(52, 42));
    await rig.drop(tester, g);
    expect(rig.edits, 1);
    expect(rig.h(1).x, autos[1].dx + 52);
    expect(rig.h(1).y, autos[1].dy + 42);
    // 另外两串没动，但位置也写下来了（免得以后自动排的时候叠上去）。
    expect([rig.h(0).x, rig.h(0).y], [autos[0].dx, autos[0].dy]);
    expect([rig.h(2).x, rig.h(2).y], [autos[2].dx, autos[2].dy]);
    expect(rig.s.layout.scripts.every((p) => !p.auto), isTrue);

    await tester.tap(find.byKey(const ValueKey('bk-undo')));
    await tester.pumpAndSettle();
    expect(rig.handlers.every((h) => h.x == null && h.y == null), isTrue);
    expect(rig.s.layout.scripts[1].origin, autos[1]);
    await tester.tap(find.byKey(const ValueKey('bk-redo')));
    await tester.pumpAndSettle();
    expect(rig.h(1).x, autos[1].dx + 52);
  });

  testWidgets('从积木盒拖出帽子＝在放下的地方新建一串', (tester) async {
    final rig = Rig(sampleDoc());
    await rig.pump(tester);
    final g = await rig.liftFromPalette(tester, 'event', 'hat-click');
    final canvas = tester.getTopLeft(find.byKey(const ValueKey('bk-canvas')));
    await rig.glide(tester, g, canvas + const Offset(200, 120));
    await rig.drop(tester, g);
    expect(rig.handlers, hasLength(4));
    expect(rig.handlers.last.event, 'click');
    final at = rig.s.toCanvas(const Offset(200, 120)) - rig.s.grabOffset;
    expect(rig.handlers.last.x, closeTo(at.dx, 1));
    expect(rig.handlers.last.y, closeTo(at.dy, 1));
    expect(rig.edits, 1);
  });

  testWidgets('缩放以后拖拽，落点仍然对', (tester) async {
    final rig = Rig(sampleDoc());
    await rig.pump(tester);
    final blank = tester.getTopLeft(find.byKey(const ValueKey('bk-canvas'))) + const Offset(360, 200);
    final a = await tester.startGesture(blank, pointer: 21);
    final b = await tester.startGesture(blank + const Offset(0, 200), pointer: 22);
    await tester.pump();
    await b.moveBy(const Offset(0, -40));
    await tester.pump();
    await b.moveBy(const Offset(0, -40));
    await tester.pump();
    await a.up();
    await b.up();
    await tester.pumpAndSettle();
    expect(rig.s.zoom, closeTo(0.6, 0.01));

    await rig.show(tester, 2, [lcStep(0), lcStep(0)]);
    var g = await rig.liftFromPalette(tester, '交互', 'block-alert');
    await rig.glide(tester, g, rig.stackSnap(rig.h(2).id, [lcStep(0)], 1));
    expect(rig.s.drag!.target, isNotNull);
    await rig.drop(tester, g);
    expect([for (final x in rig.h(2).body[0].body) x.op], ['fetch', 'alert']);

    await rig.show(tester, 0, [lcStep(2)]);
    g = await rig.lift(tester, rig.grip(0, [lcStep(2)]));
    await rig.glide(tester, g, rig.stackSnap(rig.h(1).id, const [], 0));
    expect(rig.s.drag!.target, isNotNull);
    await rig.drop(tester, g);
    expect(rig.ops(1), ['repeat', 'setVar', 'setProp']);
  });

  testWidgets('拖到画布边上停一会儿，画布自己滚', (tester) async {
    final rig = Rig(sampleDoc());
    await rig.pump(tester);
    final g = await rig.lift(tester, rig.grip(0, [lcStep(2)]));
    final canvas = tester.getTopLeft(find.byKey(const ValueKey('bk-canvas')));
    await rig.glide(tester, g, canvas + const Offset(200, 10));
    expect(rig.s.pan.dy, 0);
    for (var i = 0; i < 50; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(rig.s.pan.dy, greaterThan(40));
    await rig.drop(tester, g);
    expect(rig.edits, 0);
  });

  testWidgets('点一下积木盒里的积木＝加到选中积木后面 / 当前脚本末尾；积木盒可收起', (tester) async {
    final rig = Rig(sampleDoc());
    await rig.pump(tester);
    await tester.tapAt(rig.grip(0, [lcStep(0)]));
    await tester.pumpAndSettle();
    expect(rig.s.selection, isNotNull);
    await tester.drag(find.byKey(const ValueKey('bk-palette-tabs')), const Offset(-150, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('bk-palette-tab-交互')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('bk-palette-item-block-alert')));
    await tester.pumpAndSettle();
    expect(rig.ops(0), ['changeVar', 'alert', 'if', 'repeat']);

    final full = tester.getSize(find.byKey(const ValueKey('bk-palette-handle')).first);
    expect(full.width, greaterThan(0));
    await tester.tap(find.byKey(const ValueKey('bk-palette-handle')));
    await tester.pumpAndSettle();
    expect(rig.s.paletteCollapsed, isTrue);
    expect(find.byKey(const ValueKey('bk-palette-item-block-alert')).hitTestable(), findsNothing);
    // 收起以后只剩手柄条，分类那一行也看不到了；再点一下手柄条回到默认档。
    expect(find.byKey(const ValueKey('bk-palette-tab-流程')).hitTestable(), findsNothing);
    await tester.tap(find.byKey(const ValueKey('bk-palette-handle')));
    await tester.pumpAndSettle();
    expect(rig.s.paletteCollapsed, isFalse);
    await tester.tap(find.byKey(const ValueKey('bk-palette-tab-流程')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('bk-palette-item-block-repeat')), findsOneWidget);
  });

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    final suffix = mode == ThemeMode.light ? 'light' : 'dark';
    testWidgets('截图与冒烟：整体、拖动吸附中、垃圾桶高亮、积木盒收起（$suffix）', (tester) async {
      final rig = Rig(sampleDoc());
      await rig.pump(tester, mode: mode);
      expect(tester.takeException(), isNull);
      await shot(tester, 'bk2-editor-$suffix');

      var g = await rig.liftFromPalette(tester, '交互', 'block-alert');
      await rig.glide(tester, g, rig.stackSnap(rig.h(0).id, [lcStep(1)], 1) + const Offset(10, 12));
      expect(rig.s.drag!.target, isNotNull);
      await shot(tester, 'bk2-drag-snap-$suffix');
      await rig.drop(tester, g);
      expect([for (final b in rig.h(0).body[1].body) b.op], ['alert', 'alert', 'setVar']);

      g = await rig.lift(tester, rig.grip(0, [lcStep(2)]));
      await rig.glide(tester, g, tester.getCenter(find.byKey(const ValueKey('bk-trash'))) + const Offset(-60, -20));
      await tester.pump(const Duration(milliseconds: 200));
      await shot(tester, 'bk2-trash-$suffix');
      await rig.glide(tester, g, rig.grip(0, [lcStep(1)]) + const Offset(200, 0));
      await rig.drop(tester, g);

      await tester.tap(find.byKey(const ValueKey('bk-palette-handle')));
      await tester.pumpAndSettle();
      await shot(tester, 'bk2-palette-collapsed-$suffix');
      expect(tester.takeException(), isNull);
    });
  }
}
