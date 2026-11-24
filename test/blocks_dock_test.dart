// 积木盒面板上下拖（390×844）：最矮只剩手柄条、最高顶到状态栏下沿；松手停在哪；任何高度下拖出 / 放下 / 删除都做得到；
// 撤销 / 重做 / 缩放在手柄条上。
//   LOPI_SHOTS=1 flutter test --no-pub test/blocks_dock_test.dart   # 同时把截图写到 docs/screenshots/bk4-*.png
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/blocks/block_dock.dart';
import 'package:lopicode/blocks/block_editor_dock_view.dart';
import 'package:lopicode/blocks/block_palette_view.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:material_ui/material_ui.dart';

import 'screens_test.dart' show fontsLoaded, shot;
import 'support/blocks_fixture.dart';
import 'support/blocks_rig.dart';
import 'support/harness.dart';

Finder k(String key) => find.byKey(ValueKey(key));
Rect dock(WidgetTester tester) => tester.getRect(k('bk-dock'));
Rect canvas(WidgetTester tester) => tester.getRect(k('bk-canvas'));

/// 按住手柄，分几步竖着拖 `dy`（往下为正），不松手。测试里的手指没有时间戳，松手时速度是 0（＝慢慢放下）。
Future<TestGesture> grab(WidgetTester tester, double dy, {int steps = 8, String on = 'bk-palette-grip'}) async {
  final g = await tester.startGesture(tester.getCenter(k(on)));
  for (var i = 0; i < steps; i++) {
    await g.moveBy(Offset(0, dy / steps));
    await tester.pump(const Duration(milliseconds: 16));
  }
  return g;
}

Future<void> pull(WidgetTester tester, double dy, {String on = 'bk-palette-grip'}) async {
  final g = await grab(tester, dy, on: on);
  await g.up();
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async => fontsLoaded = await loadRealFonts());
  tearDown(BkDockMemory.clear);

  group('三档怎么算（纯逻辑）', () {
    final stops = BkDockStops.of(handle: 44, normal: 248, area: 800);

    test('三档的高度；有系统手势条时收起、默认两档都加上它；地方不够时互相挤但不乱序', () {
      expect((stops.collapsed, stops.normal, stops.full), (44, 248, 800));
      final withBar = BkDockStops.of(handle: 44, normal: 248, area: 780, bottomInset: 20);
      expect((withBar.collapsed, withBar.normal, withBar.full), (64, 268, 780));
      final tiny = BkDockStops.of(handle: 44, normal: 248, area: 120);
      expect((tiny.collapsed, tiny.normal, tiny.full), (44, 120, 120));
      expect(tiny.isFull(120), isFalse, reason: '默认档已经顶到头了，不算“全展开”');
      final none = BkDockStops.of(handle: 44, normal: 248, area: -5);
      expect((none.collapsed, none.normal, none.full), (0, 0, 0));
    });

    test('拖动不出界；慢慢放下：离一档不到 28 吸过去，否则停在原地', () {
      expect(stops.clamp(-30), 44);
      expect(stops.clamp(9000), 800);
      expect(stops.rest(60, 0), 44);
      expect(stops.rest(230, 0), 248);
      expect(stops.rest(270, 0), 248);
      expect(stops.rest(780, 0), 800);
      expect(stops.rest(400, 0), 400);
      expect(stops.rest(120, 300), 120, reason: '不够快不算甩');
    });

    test('甩：往甩的方向去下一档，不跳档', () {
      expect(stops.rest(100, -900), 248);
      expect(stops.rest(300, -900), 800);
      expect(stops.rest(300, 900), 248);
      expect(stops.rest(200, 900), 44);
      expect(stops.rest(800, -2000), 800);
      expect(stops.rest(44, 2000), 44);
    });

    test('点一下手柄：收起 ⇄ 默认；比默认高回默认；比默认矮收起', () {
      expect(stops.toggled(44), 248);
      expect(stops.toggled(248), 44);
      expect(stops.toggled(800), 248);
      expect(stops.toggled(500), 248);
      expect(stops.toggled(150), 44);
    });
  });

  testWidgets('拖手柄：面板上沿跟着手指；往下最低只剩手柄条，往上最高顶到头，都拖不出界；从全展开还能拖回来', (tester) async {
    final rig = Rig(sampleDoc());
    await rig.pump(tester);
    expect(dock(tester).height, 248);
    expect(rig.s.dockHeight, 248);

    // 跟手：手指走多少，上沿走多少（认出“这是竖着拖”之前的那一小段也补上）。
    var g = await grab(tester, -100);
    expect(rig.s.dockResizing, isTrue);
    expect(dock(tester).height, 348);
    expect(rig.s.dockHeight, 348, reason: '画布露出来的部分跟着变');
    await g.moveBy(const Offset(0, 160));
    await tester.pump();
    expect(dock(tester).height, 188);
    // 往下拖过头：停在只剩手柄条。
    await g.moveBy(const Offset(0, 600));
    await tester.pump();
    expect(dock(tester).height, BlockPaletteView.handleHeight);
    expect(dock(tester).bottom, 844);
    // 手指回来的时候不“空走”：要先走完出界的那一段，面板才动。
    await g.moveBy(const Offset(0, -100));
    await tester.pump();
    expect(dock(tester).height, BlockPaletteView.handleHeight);
    await g.up();
    await tester.pumpAndSettle();
    expect(rig.s.paletteCollapsed, isTrue);
    expect(dock(tester).height, 44);
    expect(k('bk-palette-tabs').hitTestable(), findsNothing);
    expect(k('bk-palette-grip').hitTestable(), findsOneWidget);
    expect(tester.getSize(k('bk-palette-handle')).height, greaterThanOrEqualTo(44));
    // 画布几乎占满。
    expect(canvas(tester).bottom - rig.s.dockHeight - canvas(tester).top, greaterThan(700));

    // 往上拖过头：顶到屏幕顶（测试里没有状态栏），盖住顶栏。
    g = await grab(tester, -1200);
    expect(dock(tester).top, 0);
    expect(dock(tester).height, 844);
    await g.up();
    await tester.pumpAndSettle();
    expect(dock(tester).top, 0);
    expect(k('bk-code').hitTestable(), findsNothing, reason: '顶栏被面板盖住了');
    expect(k('bk-palette-grip').hitTestable(), findsOneWidget, reason: '手柄还在最上面，能拖回来');
    // 拖回来。
    await pull(tester, 596);
    expect(dock(tester).height, 248);
    expect(k('bk-code').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('有状态栏和系统手势条：最高只到状态栏下沿；收起时手柄条露在手势条上面', (tester) async {
    final rig = Rig(sampleDoc());
    await rig.pump(tester, safe: const EdgeInsets.only(top: 30, bottom: 20));
    expect(dock(tester).height, 268);
    await pull(tester, -1200);
    expect(dock(tester).top, 30);
    await pull(tester, 1200);
    expect(dock(tester).height, 64);
    expect(tester.getRect(k('bk-palette-handle')).bottom, 844 - 20);
    expect(k('bk-palette-tabs').hitTestable(), findsNothing);
  });

  testWidgets('按住分类那一行也能上下拖；横着滑还是翻分类；积木那一片上下滑还是翻积木，不改高度', (tester) async {
    final rig = Rig(sampleDoc());
    await rig.pump(tester);
    await pull(tester, -120, on: 'bk-palette-tabs');
    expect(dock(tester).height, 368);
    // 横着滑：分类滚走了，高度不变。
    double scrolled() => tester.state<ScrollableState>(find.descendant(of: k('bk-palette-tabs'), matching: find.byType(Scrollable))).position.pixels;
    expect(scrolled(), 0);
    await tester.drag(k('bk-palette-tabs'), const Offset(-150, 0));
    await tester.pumpAndSettle();
    expect(scrolled(), greaterThan(100));
    expect(dock(tester).height, 368);
    // 点分类还是选分类。
    await tester.tap(k('bk-palette-tab-交互'));
    await tester.pumpAndSettle();
    expect(k('bk-palette-page-交互'), findsOneWidget);
    // 积木那一片上下滑：不改高度，也没把积木拿出来。
    await tester.drag(k('bk-palette-page-交互'), const Offset(0, -60));
    await tester.pumpAndSettle();
    expect(dock(tester).height, 368);
    expect(rig.s.drag, isNull);
    expect(rig.edits, 0);
  });

  testWidgets('松手：离一档近就吸过去（带动画），否则停在放手的地方；甩一下去下一档；点手柄 收起 ⇄ 默认', (tester) async {
    final rig = Rig(sampleDoc());
    await rig.pump(tester);
    // 停在任意高度。
    await pull(tester, -152);
    expect(dock(tester).height, 400);
    // 离默认档 20：吸回去，是滑过去的。
    var g = await grab(tester, 132);
    expect(dock(tester).height, 268);
    await g.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(dock(tester).height, inExclusiveRange(240, 268));
    await tester.pumpAndSettle();
    expect(dock(tester).height, 248);

    // 往上甩：默认 → 全展开；再往下甩两次：→ 默认 → 收起。
    await tester.fling(k('bk-palette-grip'), const Offset(0, -80), 1500);
    await tester.pumpAndSettle();
    expect(dock(tester).top, 0);
    await tester.fling(k('bk-palette-grip'), const Offset(0, 80), 1500);
    await tester.pumpAndSettle();
    expect(dock(tester).height, 248);
    await tester.fling(k('bk-palette-grip'), const Offset(0, 80), 1500);
    await tester.pumpAndSettle();
    expect(dock(tester).height, 44);
    // 往上甩一下：收起 → 默认（不跳到全展开）。
    await tester.fling(k('bk-palette-grip'), const Offset(0, -60), 1500);
    await tester.pumpAndSettle();
    expect(dock(tester).height, 248);

    // 点手柄。
    await tester.tap(k('bk-palette-grip'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(dock(tester).height, inExclusiveRange(44, 248), reason: '是滑过去的');
    await tester.pumpAndSettle();
    expect(dock(tester).height, 44);
    await tester.tap(k('bk-palette-grip'));
    await tester.pumpAndSettle();
    expect(dock(tester).height, 248);
    // 比默认高时点一下回默认。
    await pull(tester, -300);
    await tester.tap(k('bk-palette-grip'));
    await tester.pumpAndSettle();
    expect(dock(tester).height, 248);
    // 滑到一半又按住：动画停下，从手按住的地方接着拖。
    await tester.tap(k('bk-palette-grip'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    final mid = dock(tester).height;
    g = await grab(tester, -40);
    expect(dock(tester).height, closeTo(mid + 40, 0.01));
    await g.up();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('减弱动态效果：点手柄、松手吸附都直接到位', (tester) async {
    final rig = Rig(sampleDoc());
    await rig.pump(tester, reduceMotion: true);
    await tester.tap(k('bk-palette-grip'));
    await tester.pump();
    expect(dock(tester).height, 44);
    await tester.tap(k('bk-palette-grip'));
    await tester.pump();
    expect(dock(tester).height, 248);
    final g = await grab(tester, -580);
    await g.up();
    await tester.pump();
    expect(dock(tester).top, 0);
    // 全展开时拿积木：面板直接回默认档。
    final lift = await rig.liftFromPalette(tester, '交互', 'block-alert');
    await tester.pump();
    expect(dock(tester).height, 248);
    await rig.drop(tester, lift);
  });

  testWidgets('面板比默认高（任意高度 / 全展开）时从积木盒拿积木：面板自己滑回默认档让出画布，照样放得上去', (tester) async {
    for (final up in [-300.0, -1200.0]) {
      final rig = Rig(sampleDoc());
      await tester.pumpWidget(const SizedBox());
      await rig.pump(tester);
      await rig.show(tester, 1);
      await pull(tester, up);
      expect(dock(tester).height, greaterThan(500));
      final g = await rig.liftFromPalette(tester, '交互', 'block-alert');
      expect(rig.s.drag!.isNew, isTrue);
      // 手上的积木一直看得见（画在面板上面那一层）。
      expect(k('bk-drag-piece'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 400));
      expect(dock(tester).height, 248, reason: '让开了');
      await rig.glide(tester, g, rig.stackSnap(rig.h(1).id, const [], 2));
      expect(rig.s.drag!.target, isNotNull);
      await rig.drop(tester, g);
      expect(rig.ops(1), ['setVar', 'setProp', 'alert']);
      expect(rig.edits, 1);
      expect(dock(tester).height, 248, reason: '放下以后留在默认档');
    }
  });

  testWidgets('面板比默认矮时从积木盒拿积木：高度不动，照样放得上去；拖回面板＝不要了', (tester) async {
    final rig = Rig(sampleDoc());
    await rig.pump(tester);
    await rig.show(tester, 1);
    await pull(tester, 60);
    expect(dock(tester).height, 188);
    var g = await rig.liftFromPalette(tester, '交互', 'block-alert');
    await rig.glide(tester, g, rig.stackSnap(rig.h(1).id, const [], 2));
    await rig.drop(tester, g);
    expect(rig.ops(1), ['setVar', 'setProp', 'alert']);
    expect(dock(tester).height, 188);
    g = await rig.liftFromPalette(tester, '交互', 'block-alert');
    await rig.glide(tester, g, const Offset(200, 500));
    await rig.glide(tester, g, dock(tester).center);
    await rig.drop(tester, g);
    expect(rig.edits, 1);
  });

  testWidgets('点积木盒快捷添加：面板比默认高就让开，看得见加在了哪；只是提示（表达式）就不动', (tester) async {
    final rig = Rig(sampleDoc());
    await rig.pump(tester);
    await pull(tester, -1200);
    await tester.tap(k('bk-palette-tab-变量'));
    await tester.pumpAndSettle();
    await tester.tap(k('bk-palette-item-expr-var'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(dock(tester).top, 0, reason: '没加东西，面板不动');
    // 全展开时画布放不下提示条：提示条在面板里、分类那一行下面，不被面板盖住，也不挡手柄和分类。
    final toast = tester.getRect(k('bk-toast'));
    expect(toast.top, greaterThanOrEqualTo(tester.getRect(k('bk-palette-tabs')).bottom));
    expect(toast.bottom, lessThan(300));
    await tester.pumpAndSettle(const Duration(seconds: 3));
    expect(k('bk-toast'), findsNothing);

    await tester.tap(k('bk-palette-item-block-setVar'));
    await tester.pumpAndSettle();
    expect(rig.edits, 1);
    expect(dock(tester).height, 248);
    // 新加的那块在画布露出来的部分里。
    final sel = rig.s.selection!;
    final at = rig.grip(rig.handlers.indexWhere((h) => h.id == sel.scriptId), sel.path);
    expect(at.dy, inInclusiveRange(canvas(tester).top, 844 - 248));
  });

  testWidgets('任何高度下都能把画布上的积木拖去删：面板收起时垃圾桶条不矮于 96；面板高时先让到默认档', (tester) async {
    for (final (dy, trash) in [(1200.0, 96.0), (100.0, 148.0), (0.0, 248.0), (-200.0, 248.0)]) {
      final rig = Rig(sampleDoc());
      await tester.pumpWidget(const SizedBox());
      await rig.pump(tester);
      if (dy != 0) await pull(tester, dy);
      final before = dock(tester).height;
      await rig.show(tester, 0, [lcStep(2)]);
      // 拿最后一块（拿前面的会带走它下面的整串）。
      final g = await rig.lift(tester, rig.grip(0, [lcStep(2)]));
      await tester.pump(const Duration(milliseconds: 400));
      expect(k('bk-trash'), findsOneWidget);
      expect(k('bk-palette-grip'), findsNothing);
      expect(tester.getRect(k('bk-trash')).height, trash);
      expect(rig.s.dockHeight, trash);
      expect(tester.getRect(k('bk-trash')).bottom, 844);
      await rig.glide(tester, g, tester.getRect(k('bk-trash')).center);
      expect(rig.s.overTrash, isTrue);
      await rig.drop(tester, g);
      expect(rig.ops(0), ['changeVar', 'if'], reason: 'dy=$dy');
      expect(rig.edits, 1);
      // 删完积木盒回来；原来比默认高的留在默认档，别的还是原来的高度。
      expect(k('bk-trash'), findsNothing);
      expect(dock(tester).height, before > 248 ? 248 : before);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('面板收起时：画布下沿自动滚的位置、提示条都跟着面板走', (tester) async {
    final rig = Rig(sampleDoc());
    await rig.pump(tester);
    await pull(tester, 1200);
    final g = await rig.lift(tester, rig.grip(0, [lcStep(1)]));
    // 垃圾桶条（96 高）上面一点：停一会儿画布自己往上滚。
    await rig.glide(tester, g, const Offset(300, 844 - 96 - 20));
    expect(rig.s.overTrash, isFalse);
    final pan = rig.s.pan.dy;
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(rig.s.pan.dy, lessThan(pan - 50));
    // 放到没法放的地方：弹回去并说一句；提示条贴在手柄条上面。
    await rig.glide(tester, g, const Offset(340, 110));
    await rig.drop(tester, g);
    if (k('bk-toast').evaluate().isNotEmpty) {
      expect(tester.getRect(k('bk-toast')).bottom, lessThanOrEqualTo(dock(tester).top));
    }
    await tester.pumpAndSettle(const Duration(seconds: 5));

    // 表达式提示：一定有提示条。面板收起时点不到积木，先回默认档拿到提示再收起。
    await tester.tap(k('bk-palette-grip'));
    await tester.pumpAndSettle();
    await tester.tap(k('bk-palette-tab-变量'));
    await tester.pumpAndSettle();
    await tester.tap(k('bk-palette-item-expr-var'));
    await tester.pump();
    await tester.tap(k('bk-palette-grip'));
    await tester.pumpAndSettle();
    final toast = tester.getRect(k('bk-toast'));
    expect(toast.bottom, lessThanOrEqualTo(dock(tester).top));
    expect(toast.bottom, greaterThan(dock(tester).top - 40));
    await tester.pumpAndSettle(const Duration(seconds: 3));
  });

  testWidgets('撤销 / 重做 / 缩放在手柄条右边：画布上不再有浮条；面板收起、全展开时都能用；点它们不算点手柄', (tester) async {
    final rig = Rig(sampleDoc());
    await rig.pump(tester);
    final tools = tester.getRect(k('bk-tools'));
    final handle = tester.getRect(k('bk-palette-handle'));
    expect(handle.contains(tools.topLeft) && handle.contains(tools.bottomRight - const Offset(1, 1)), isTrue, reason: '整条都在手柄条里');
    expect(tools.overlaps(Rect.fromLTRB(0, canvas(tester).top, 390, dock(tester).top)), isFalse, reason: '不盖画布');
    expect(tools.overlaps(tester.getRect(k('bk-palette-grip'))), isFalse);
    for (final key in ['bk-undo', 'bk-redo', 'bk-zoom']) {
      final size = tester.getSize(k(key));
      expect(size.width, greaterThanOrEqualTo(44), reason: key);
      expect(size.height, greaterThanOrEqualTo(44), reason: key);
    }
    expect(tester.widget<IconButton>(k('bk-undo')).onPressed, isNull);

    // 做一处改动，然后把面板收起来。
    final g = await rig.lift(tester, rig.grip(0, [lcStep(2)]));
    await rig.glide(tester, g, tester.getRect(k('bk-trash')).center);
    await rig.drop(tester, g);
    expect(rig.ops(0), ['changeVar', 'if']);
    await pull(tester, 1200);
    expect(dock(tester).height, 44);
    await tester.tap(k('bk-undo'));
    await tester.pumpAndSettle();
    expect(rig.ops(0), ['changeVar', 'if', 'repeat']);
    expect(dock(tester).height, 44, reason: '点按钮不算点手柄');
    await tester.tap(k('bk-redo'));
    await tester.pumpAndSettle();
    expect(rig.ops(0), ['changeVar', 'if']);
    // 按不动的按钮（没有可重做的了）也不算点手柄。
    await tester.tap(k('bk-redo'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(dock(tester).height, 44);

    // 缩放：两指放大，点比例回 100%。
    final blank = canvas(tester).topLeft + const Offset(360, 300);
    final a = await tester.startGesture(blank, pointer: 11);
    final b = await tester.startGesture(blank + const Offset(0, 100), pointer: 12);
    await tester.pump();
    await b.moveBy(const Offset(0, 80));
    await tester.pump();
    await a.up();
    await b.up();
    await tester.pumpAndSettle();
    expect(rig.s.zoom, greaterThan(1.2));
    expect(find.text('${(rig.s.zoom * 100).round()}%'), findsOneWidget);
    await tester.tap(k('bk-zoom'));
    await tester.pumpAndSettle();
    expect(rig.s.zoom, 1);
    expect(find.text('100%'), findsOneWidget);
    expect(dock(tester).height, 44);

    // 全展开时也在。
    await pull(tester, -1200);
    await tester.tap(k('bk-undo'));
    await tester.pumpAndSettle();
    expect(rig.ops(0), ['changeVar', 'if', 'repeat']);
    // 从按钮上开始竖着拖也能拖动面板。
    await pull(tester, 300, on: 'bk-undo');
    expect(dock(tester).height, 544);
  });

  testWidgets('就地改字（键盘弹出）：面板让开；改完面板回到原来的高度', (tester) async {
    final rig = Rig(sampleDoc());
    await rig.pump(tester);
    await pull(tester, 100);
    expect(dock(tester).height, 148);
    await tester.tapAt(rig.slot(0, [lcStep(0)], (s) => s.arg == 'by'));
    await tester.pumpAndSettle();
    expect(rig.s.editing, isNotNull);
    expect(k('bk-dock'), findsNothing);
    expect(rig.s.dockHeight, 0);
    await tester.enterText(k('bk-inline-input'), '5');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(rig.s.editing, isNull);
    expect(dock(tester).height, 148);
  });

  testWidgets('空画布：面板拖高到放不下引导时引导先收起来，不报溢出；拖回来又出现', (tester) async {
    final rig = Rig(sampleDoc()..logic.handlers.clear());
    await rig.pump(tester);
    expect(k('bk-empty'), findsOneWidget);
    final g = await grab(tester, -1200, steps: 40);
    expect(tester.takeException(), isNull);
    expect(k('bk-empty'), findsNothing);
    await g.moveBy(const Offset(0, 1300));
    await tester.pump();
    await g.up();
    await tester.pumpAndSettle();
    expect(k('bk-empty'), findsOneWidget);
    expect(tester.getRect(k('bk-empty-arrow')).bottom, lessThan(dock(tester).top));
  });

  testWidgets('积木逻辑页：面板停在哪，离开再回来还在那里（同一次运行里）', (tester) async {
    final rig = Rig(sampleDoc());
    await rig.pumpLogic(tester);
    expect(dock(tester).height, 248);
    await pull(tester, 1200);
    expect(dock(tester).height, 44);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(k('bk-dock'), findsNothing);
    await rig.pumpLogic(tester);
    expect(dock(tester).height, 44);
    // 全展开也记得住。
    await pull(tester, -1200);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await rig.pumpLogic(tester);
    expect(dock(tester).top, 0);
    // 没给名字的编辑器不记。
    await rig.pump(tester);
    expect(dock(tester).height, 248);
  });

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    final suffix = mode == ThemeMode.light ? 'light' : 'dark';
    testWidgets('截图：默认、拖动中、收起、收起时拖积木去删、全展开（$suffix）', (tester) async {
      final rig = Rig(sampleDoc());
      await rig.pump(tester, mode: mode);
      await shot(tester, 'bk4-dock-normal-$suffix');
      var g = await grab(tester, -170);
      await shot(tester, 'bk4-dock-dragging-$suffix');
      await g.up();
      await tester.pumpAndSettle();
      await pull(tester, 1200);
      await shot(tester, 'bk4-dock-collapsed-$suffix');
      g = await rig.lift(tester, rig.grip(0, [lcStep(2)]));
      await rig.glide(tester, g, tester.getRect(k('bk-trash')).center + const Offset(-150, 20));
      await tester.pump(const Duration(milliseconds: 200));
      await shot(tester, 'bk4-dock-collapsed-trash-$suffix');
      await rig.glide(tester, g, rig.grip(0, [lcStep(1)]) + const Offset(200, 0));
      await rig.drop(tester, g);
      await tester.pumpAndSettle(const Duration(seconds: 5));
      await pull(tester, -1200);
      await shot(tester, 'bk4-dock-full-$suffix');
      expect(BkEditorDock.trashMinHeight, 96);
    });
  }
}
