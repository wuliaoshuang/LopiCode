// 积木盒手柄条那一行怎么排（390×844，浅色 + 深色）：把手严格居中；左边是“积木盒”名字（点一下收起 / 展开）和问题数量
// （有问题才有，点了开问题列表）；右边撤销 / 重做 / 缩放。三档都不溢出、不互相压；从左边的东西上竖着拖还是拖面板。
//   LOPI_SHOTS=1 flutter test --no-pub test/blocks_dock_handle_test.dart   # 同时把截图写到 docs/screenshots/bk5-*.png
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/blocks/block_dock.dart';
import 'package:lopicode/blocks/block_palette_view.dart';
import 'package:material_ui/material_ui.dart';

import 'blocks_dock_test.dart' show dock, grab, k, pull;
import 'blocks_issue_ui_test.dart' show troubled;
import 'screens_test.dart' show fontsLoaded, shot;
import 'support/blocks_fixture.dart';
import 'support/blocks_rig.dart';
import 'support/harness.dart';

Rect r(WidgetTester tester, String key) => tester.getRect(k(key));

/// 这一行现在排得对不对：把手正中；左、中、右三块都在手柄条里、互不相压；左右两块离屏幕边一样“满”。
void expectRow(WidgetTester tester, {required bool issues, String? reason}) {
  final handle = r(tester, 'bk-palette-handle');
  final grip = r(tester, 'bk-palette-grip');
  final lead = r(tester, 'bk-dock-lead');
  final tools = r(tester, 'bk-tools');
  expect(handle.width, 390, reason: reason);
  expect(grip.center.dx, 195, reason: '把手严格水平居中 $reason');
  expect(grip.center.dy, handle.center.dy, reason: reason);
  expect(lead.left, 0, reason: reason);
  expect(lead.right, lessThanOrEqualTo(grip.left - BlockPaletteView.gripGap), reason: '左边不压把手 $reason');
  expect(tools.left, greaterThanOrEqualTo(grip.right + BlockPaletteView.gripGap), reason: '右边不压把手 $reason');
  expect(tools.right, 390, reason: reason);
  for (final box in [lead, tools]) {
    expect(box.top, greaterThanOrEqualTo(handle.top), reason: reason);
    expect(box.bottom, lessThanOrEqualTo(handle.bottom), reason: reason);
  }
  // 左边不再空着：名字从左边 12 起，至少占到 80 宽。
  final title = r(tester, 'bk-dock-title');
  expect(title.width, greaterThanOrEqualTo(80), reason: reason);
  expect(title.height, greaterThanOrEqualTo(44), reason: reason);
  expect(
    find.descendant(of: k('bk-dock-title'), matching: find.text('积木盒')).hitTestable(),
    findsOneWidget,
    reason: reason,
  );
  expect(k('bk-dock-issues'), issues ? findsOneWidget : findsNothing, reason: reason);
  if (issues) {
    final pill = r(tester, 'bk-dock-issues');
    expect(pill.width, greaterThanOrEqualTo(44), reason: reason);
    expect(pill.height, greaterThanOrEqualTo(44), reason: reason);
    expect(pill.left, greaterThanOrEqualTo(title.right), reason: reason);
  }
  expect(tester.takeException(), isNull, reason: reason);
}

void main() {
  setUpAll(() async => fontsLoaded = await loadRealFonts());
  tearDown(BkDockMemory.clear);

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    final suffix = mode == ThemeMode.light ? 'light' : 'dark';

    testWidgets('三档都排得匀：把手正中，左边“积木盒”、右边三样，谁也不压谁、不溢出；箭头说明点了会怎样 ($suffix)', (tester) async {
      final rig = Rig(sampleDoc());
      await rig.pump(tester, mode: mode);
      // 默认档。
      expectRow(tester, issues: rig.host.issues.isNotEmpty, reason: '默认');
      expect(k('bk-dock-arrow-down'), findsOneWidget);
      expect(find.bySemanticsLabel('收起积木盒'), findsOneWidget);
      // 拖动中的任意高度。
      final g = await grab(tester, -170);
      expectRow(tester, issues: rig.host.issues.isNotEmpty, reason: '拖动中');
      await g.up();
      await tester.pumpAndSettle();
      // 收起：这一行就是全部。
      await pull(tester, 1200);
      expect(dock(tester).height, 44);
      expectRow(tester, issues: rig.host.issues.isNotEmpty, reason: '收起');
      expect(k('bk-dock-arrow-up'), findsOneWidget);
      expect(find.bySemanticsLabel('展开积木盒'), findsOneWidget);
      // 全展开。
      await pull(tester, -1200);
      expect(dock(tester).top, 0);
      expectRow(tester, issues: rig.host.issues.isNotEmpty, reason: '全展开');
      expect(k('bk-dock-arrow-down'), findsOneWidget);
    });

    testWidgets('有问题时左边多一个数量：有错误是红的、只有警告是黄的（图标也不同）；点了开问题列表，面板高度不动；修好就没了 ($suffix)', (tester) async {
      final rig = Rig(troubled());
      await rig.pump(tester, mode: mode);
      expect(rig.host.issues, hasLength(5));
      expectRow(tester, issues: true, reason: '有错误');
      expect(find.descendant(of: k('bk-dock-issues'), matching: find.text('5')), findsOneWidget);
      expect(find.descendant(of: k('bk-dock-issues'), matching: find.byIcon(Icons.error_outline_rounded)), findsOneWidget);
      await shot(tester, 'bk5-handle-issues-normal-$suffix');

      // 收起时也在，点了开问题列表；不算点手柄。
      await pull(tester, 1200);
      expectRow(tester, issues: true, reason: '收起 + 有错误');
      await shot(tester, 'bk5-handle-issues-collapsed-$suffix');
      await tester.tap(k('bk-dock-issues'));
      await tester.pumpAndSettle();
      expect(find.text('5 个问题'), findsOneWidget);
      expect(find.text('错误 · 2'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(dock(tester).height, 44);

      // 全展开时顶栏的“问题”被盖住了，这里还点得到。
      await pull(tester, -1200);
      expect(k('bk-issues').hitTestable(), findsNothing);
      expect(k('bk-dock-issues').hitTestable(), findsOneWidget);
      expectRow(tester, issues: true, reason: '全展开 + 有错误');
      await tester.tap(k('bk-palette-grip'));
      await tester.pumpAndSettle();

      // 把两处错误去掉：只剩警告 → 黄的三角。
      rig.host.edit(() => rig.host.script(rig.h(0).id)!.body.removeWhere((b) => b.op == 'changeVar' || b.op == 'setVar'));
      await tester.pumpAndSettle();
      expect(rig.host.issues.where((i) => i.isError), isEmpty);
      expect(rig.host.issues, isNotEmpty);
      expect(find.descendant(of: k('bk-dock-issues'), matching: find.byIcon(Icons.warning_amber_rounded)), findsOneWidget);
      expect(find.descendant(of: k('bk-dock-issues'), matching: find.text('${rig.host.issues.length}')), findsOneWidget);
      expectRow(tester, issues: true, reason: '只有警告');
      await shot(tester, 'bk5-handle-warnings-normal-$suffix');

      // 全清掉：数量消失。
      rig.host.edit(() {
        for (final id in [for (final h in rig.handlers) h.id]) {
          rig.host.removeScript(id);
        }
      });
      await tester.pumpAndSettle();
      expect(rig.host.issues, isEmpty);
      expectRow(tester, issues: false, reason: '没有问题');
    });
  }

  testWidgets('点“积木盒”：收起 ⇄ 默认（和点把手一样）；从它、从问题数量上竖着拖都是拖面板，不触发点按', (tester) async {
    final rig = Rig(troubled());
    await rig.pump(tester);
    expect(dock(tester).height, 248);
    await tester.tap(k('bk-dock-title'));
    await tester.pumpAndSettle();
    expect(dock(tester).height, 44);
    expect(rig.s.paletteCollapsed, isTrue);
    await tester.tap(k('bk-dock-title'));
    await tester.pumpAndSettle();
    expect(dock(tester).height, 248);

    // 从名字上拖：面板上沿跟着手指走，拖动中不算点。
    final g = await grab(tester, -100, on: 'bk-dock-title');
    expect(rig.s.dockResizing, isTrue);
    expect(dock(tester).height, 348);
    await g.up();
    await tester.pumpAndSettle();
    expect(dock(tester).height, 348, reason: '停在放手的地方，没有被当成点一下');

    // 从问题数量上拖：一样拖面板，问题列表不弹出来。
    await pull(tester, 60, on: 'bk-dock-issues');
    expect(dock(tester).height, 288);
    expect(find.text('5 个问题'), findsNothing);
    // 甩也行。
    await tester.fling(k('bk-dock-title'), const Offset(0, 30), 1500);
    await tester.pumpAndSettle();
    expect(dock(tester).height, 248);
    // 比默认高时点名字回默认。
    await pull(tester, -300);
    await tester.tap(k('bk-dock-title'));
    await tester.pumpAndSettle();
    expect(dock(tester).height, 248);
    // 滑到一半按住名字：停在那里接着拖（和把手一样）。
    await tester.tap(k('bk-dock-title'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    final mid = dock(tester).height;
    expect(mid, inExclusiveRange(44, 248));
    final h = await grab(tester, -40, on: 'bk-dock-title');
    expect(dock(tester).height, closeTo(mid + 40, 0.01));
    await h.up();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('有系统手势条、缩放比例变长（250%）、带问题数量：这一行还是不溢出、把手还在正中', (tester) async {
    final doc = troubled();
    final rig = Rig(doc);
    await rig.pump(tester, safe: const EdgeInsets.only(top: 30, bottom: 20));
    rig.s.setZoom(2.5, rig.s.canvasCenter);
    rig.s.host.onChanged?.call(); // 让编辑器重画一遍
    await tester.pumpAndSettle();
    expect(find.text('${(rig.s.zoom * 100).round()}%'), findsOneWidget);
    expectRow(tester, issues: true, reason: '放大');
    await pull(tester, 1200);
    expect(dock(tester).height, 64);
    expectRow(tester, issues: true, reason: '放大 + 收起 + 手势条');
    expect(r(tester, 'bk-palette-handle').bottom, 844 - 20);
  });

  testWidgets('积木逻辑页（真宿主）也一样：左边有名字，点了收起', (tester) async {
    final rig = Rig(sampleDoc());
    await rig.pumpLogic(tester);
    expectRow(tester, issues: rig.s.host.issues.isNotEmpty, reason: '逻辑页');
    await tester.tap(k('bk-dock-title'));
    await tester.pumpAndSettle();
    expect(dock(tester).height, 44);
    expectRow(tester, issues: rig.s.host.issues.isNotEmpty, reason: '逻辑页收起');
  });

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    final suffix = mode == ThemeMode.light ? 'light' : 'dark';
    testWidgets('截图：手柄条——默认、收起、全展开（$suffix）', (tester) async {
      final rig = Rig(sampleDoc());
      await rig.pump(tester, mode: mode);
      await shot(tester, 'bk5-handle-normal-$suffix');
      await pull(tester, 1200);
      await shot(tester, 'bk5-handle-collapsed-$suffix');
      await pull(tester, -1200);
      await shot(tester, 'bk5-handle-full-$suffix');
    });
  }
}
