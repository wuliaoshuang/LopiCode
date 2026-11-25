// 多口积木在编辑器里的界面测试（390×844，浅色 + 深色）：点“＋ / −”增减段、拖进拖出各个口、让位和落点阴影、
// 长按 0.28 秒拿起、单指滑动只平移、校验标记、撤销重做。宿主是测试专用的假宿主。
//   LOPI_SHOTS=1 flutter test --no-pub test/blocks_arms_ui_test.dart   # 同时把截图写到 docs/screenshots/bk6-*.png
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/blocks/block_dock.dart';
import 'package:lopicode/blocks/block_geometry.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:material_ui/material_ui.dart';

import 'screens_test.dart' show fontsLoaded, shot;
import 'support/blocks_fake_host.dart';
import 'support/blocks_fake_rig.dart';
import 'support/harness.dart';

Finder k(String key) => find.byKey(ValueKey(key));

void main() {
  setUpAll(() async => fontsLoaded = await loadRealFonts());
  tearDown(BkDockMemory.clear);

  testWidgets('点“＋”：先加一段“否则如果”，再点能选加一段还是加上“否则”；每次一条撤销记录，撤销重做原样回来', (tester) async {
    final rig = FakeRig([rigIf()]);
    await rig.pump(tester);
    final start = rig.host.encode();
    expect(rig.first.arms, isEmpty);
    expect(rig.first.noElse, isTrue);
    expect(rig.block([lcStep(0)]).mouths, hasLength(1));

    // 段没有、否则也没有：点“＋”弹出两项。
    await tester.tapAt(rig.control([lcStep(0)], BkControlKind.add));
    await tester.pumpAndSettle();
    expect(k('bk-arm-menu-arm'), findsOneWidget);
    expect(k('bk-arm-menu-tail'), findsOneWidget);
    expect(find.text('加一段“否则如果”'), findsOneWidget);
    expect(find.text('加上“否则”'), findsOneWidget);
    await tester.tap(k('bk-arm-menu-arm'));
    await tester.pumpAndSettle();
    expect(rig.first.arms, hasLength(1));
    expect((rig.first.arms[0].args['cond'] as Map)['e'], 'bool', reason: '新的一段带着默认条件');
    expect(rig.host.edits, 1);
    expect(rig.s.selection!.path, [lcStep(0)], reason: '点小按钮顺手选中这块');

    await tester.tapAt(rig.control([lcStep(0)], BkControlKind.add));
    await tester.pumpAndSettle();
    await tester.tap(k('bk-arm-menu-tail'));
    await tester.pumpAndSettle();
    expect(rig.first.noElse, isFalse);
    expect(rig.block([lcStep(0)]).mouths, hasLength(3));
    expect(rig.host.edits, 2);

    // 否则已经在了：再点“＋”不弹菜单，直接加一段。
    await tester.tapAt(rig.control([lcStep(0)], BkControlKind.add));
    await tester.pumpAndSettle();
    expect(k('bk-arm-menu-arm'), findsNothing);
    expect(rig.first.arms, hasLength(2));
    expect(rig.host.edits, 3);

    final after = rig.host.encode();
    for (var i = 0; i < 3; i++) {
      rig.host.undo();
    }
    await tester.pumpAndSettle();
    expect(rig.host.encode(), start);
    for (var i = 0; i < 3; i++) {
      rig.host.redo();
    }
    await tester.pumpAndSettle();
    expect(rig.host.encode(), after);
    expect(tester.takeException(), isNull);
  });

  testWidgets('点“−”：空的段直接删；里面有积木先问；到了最少段数没有“−”；收起有积木的“否则”也先问', (tester) async {
    final rig = FakeRig([fxSampleIf()]);
    await rig.pump(tester);
    // 第 2 段是空的：直接删。
    await tester.tapAt(rig.control([lcStep(0)], BkControlKind.removeArm, arm: 1));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(rig.first.arms, hasLength(1));
    expect(rig.host.edits, 1);
    // 第 1 段里有一块：先问，取消＝不动。
    await tester.tapAt(rig.control([lcStep(0)], BkControlKind.removeArm, arm: 0));
    await tester.pumpAndSettle();
    expect(find.text('删掉这一段？'), findsOneWidget);
    expect(find.textContaining('还有 1 块积木'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(rig.first.arms, hasLength(1));
    expect(rig.host.edits, 1);
    await tester.tapAt(rig.control([lcStep(0)], BkControlKind.removeArm, arm: 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(rig.first.arms, isEmpty);
    expect(rig.host.edits, 2);
    // 收起“否则”：里面有一块，先问。
    await tester.tapAt(rig.control([lcStep(0)], BkControlKind.removeTail));
    await tester.pumpAndSettle();
    expect(find.text('去掉“否则”？'), findsOneWidget);
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(rig.first.orElse, isEmpty);
    expect(rig.first.noElse, isTrue);
    expect(rig.block([lcStep(0)]).mouths, hasLength(1));
    // 一路撤销回到最开始。
    while (rig.host.canUndo) {
      rig.host.undo();
    }
    await tester.pumpAndSettle();
    expect(jsonEncode(rig.first.toJson()), jsonEncode(fxSampleIf().toJson()));
    expect(tester.takeException(), isNull);
  });

  testWidgets('分情况：最少一段——只剩一段时那一段没有“−”，画不出来也点不到', (tester) async {
    final rig = FakeRig([rig1Switch()]);
    await rig.pump(tester);
    final blk = rig.block([lcStep(0)]);
    expect(blk.controls.where((c) => c.kind == BkControlKind.removeArm), isEmpty);
    await tester.tapAt(rig.control([lcStep(0)], BkControlKind.add));
    await tester.pumpAndSettle();
    expect(rig.first.arms, hasLength(2), reason: '“都不是”已经在：直接加一段');
    expect(rig.block([lcStep(0)]).controls.where((c) => c.kind == BkControlKind.removeArm), hasLength(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('长按 0.28 秒拿起段里的积木，拖进另一段：别的积木让位、落点有阴影；放下一条撤销记录；撤销重做', (tester) async {
    final rig = FakeRig([fxSampleIf()]);
    await rig.pump(tester);
    final before = rig.host.encode();
    final from = rig.grip([lcStep(0), lcStep(0, arm: 0)]);
    // 按住不到 0.28 秒：还没拿起来。
    final g = await tester.startGesture(from);
    await tester.pump(const Duration(milliseconds: 200));
    expect(rig.s.drag, isNull);
    await tester.pump(const Duration(milliseconds: 100));
    expect(rig.s.drag, isNotNull);
    expect(rig.s.drag!.blocks.single.op, 'say');
    final to = rig.snap([lcStep(0)], 0, arm: 1);
    await rig.glide(tester, g, from, to);
    await tester.pump(const Duration(milliseconds: 200));
    final ghost = rig.s.drag!.ghost!;
    expect(ghost.arm, 1);
    expect(ghost.parent, [lcStep(0)]);
    await rig.drop(tester, g);
    expect(rig.host.edits, 1);
    expect(rig.first.arms[0].body, isEmpty);
    expect((rig.first.arms[1].body.single.args['text'] as Map)['v'], '及格');
    rig.host.undo();
    await tester.pumpAndSettle();
    expect(rig.host.encode(), before);
    rig.host.redo();
    await tester.pumpAndSettle();
    expect(rig.first.arms[1].body, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('从“否则”拖到最外层、从最外层拖进第 1 段的中间；拖回原处不产生改动', (tester) async {
    final rig = FakeRig([fxSampleIf(), fxSay('后面')]);
    await rig.pump(tester);
    var from = rig.grip([lcStep(0), lcStep(0, inElse: true)]);
    var g = await rig.lift(tester, from);
    await rig.glide(tester, g, from, rig.snap(const [], 1));
    await rig.drop(tester, g);
    expect([for (final b in rig.tree.body) b.op], ['if', 'say', 'say']);
    expect(rig.first.orElse, isEmpty);
    expect(rig.host.edits, 1);

    from = rig.grip([lcStep(2)]);
    g = await rig.lift(tester, from);
    await rig.glide(tester, g, from, rig.snap([lcStep(0)], 0, arm: 0));
    await rig.drop(tester, g);
    expect([for (final b in rig.first.arms[0].body) (b.args['text'] as Map)['v']], ['后面', '及格']);
    expect(rig.host.edits, 2);

    from = rig.grip([lcStep(0), lcStep(1, arm: 0)]);
    g = await rig.lift(tester, from);
    await rig.glide(tester, g, from, rig.snap([lcStep(0)], 1, arm: 0));
    await rig.drop(tester, g);
    expect(rig.host.edits, 2, reason: '放回原处不算改动');
    expect(tester.takeException(), isNull);
  });

  testWidgets('从积木盒拖一块新的进“分情况”的第 2 段', (tester) async {
    final rig = FakeRig([fxSampleSwitch()]);
    await rig.pump(tester);
    await rig.openTab(tester, 'text');
    final item = rig.item('block-say');
    final from = tester.getTopLeft(item) + const Offset(10, 20);
    final g = await tester.startGesture(from);
    await tester.pump(const Duration(milliseconds: 220));
    expect(rig.s.drag, isNotNull);
    await rig.glide(tester, g, from, rig.snap([lcStep(0)], 1, arm: 1));
    await rig.drop(tester, g);
    expect(rig.first.arms[1].body, hasLength(2));
    expect(rig.host.edits, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('单指在多口积木上滑动只平移画布：不拿起、不改模型；点段上的槽能就地改', (tester) async {
    final rig = FakeRig([fxSampleIf()]);
    await rig.pump(tester);
    final before = rig.host.encode();
    final at = rig.grip([lcStep(0), lcStep(0, arm: 0)]);
    final pan0 = rig.s.pan;
    await tester.dragFrom(at, const Offset(-60, 40));
    await tester.pumpAndSettle();
    expect(rig.s.drag, isNull);
    expect(rig.s.pan, isNot(pan0));
    expect(rig.host.encode(), before);
    expect(rig.host.edits, 0);
    // 在小按钮上滑也只是平移，不触发增减。
    await tester.dragFrom(rig.control([lcStep(0)], BkControlKind.removeArm, arm: 1), const Offset(40, 30));
    await tester.pumpAndSettle();
    expect(rig.host.encode(), before);
    expect(tester.takeException(), isNull);
  });

  testWidgets('校验标记：宿主把问题标到段的参数上（@段号:名字），那一格画上标记；选中这块能看到那句话', (tester) async {
    final bad = fxSampleIf();
    bad.arms[1].args['cond'] = fxBool(false);
    final rig = FakeRig([bad]);
    await rig.pump(tester);
    final issue = rig.host.issues.single;
    expect(issue.arg, '@1:cond');
    expect(rig.s.issues, hasLength(1));
    final marks = rig.s.issueMarks['s1']!;
    final blk = rig.block([lcStep(0)]);
    final slot1 = blk.slots.firstWhere((x) => x.arg == '@1:cond' && x.exprPath.isEmpty);
    final slot0 = blk.slots.firstWhere((x) => x.arg == '@0:cond' && x.exprPath.isEmpty);
    expect(marks.slotLevel(blk.path, slot1), isNotNull);
    expect(marks.slotLevel(blk.path, slot0), isNull);
    await tester.tapAt(rig.grip([lcStep(0)]));
    await tester.pumpAndSettle();
    expect(find.textContaining('第 2 段“否则如果”的条件永远不成立'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    final suffix = mode == ThemeMode.light ? 'light' : 'dark';
    testWidgets('截图：多口“如果”（3 段 + 否则）、“分情况”、拖进一段的落点（$suffix）', (tester) async {
      final big = fxSampleIf()
        ..arms.add(LcArm(args: {'cond': fxCmp(fxVar('分数'), '>', fxNum(10))}, body: [fxSay('再想想')]))
        ..arms[1].body.add(fxSay('差一点'));
      var rig = FakeRig([big]);
      await rig.pump(tester, mode: mode);
      await pullDockDown(tester);
      await shot(tester, 'bk6-if-arms-$suffix');

      final from = rig.grip([lcStep(0), lcStep(0)]);
      final g = await rig.lift(tester, from);
      await rig.glide(tester, g, from, rig.snap([lcStep(0)], 1, arm: 1));
      await tester.pump(const Duration(milliseconds: 300));
      await shot(tester, 'bk6-if-drag-$suffix');
      await rig.drop(tester, g);

      rig = FakeRig([fxSampleSwitch()]);
      await rig.pump(tester, mode: mode);
      await pullDockDown(tester);
      await shot(tester, 'bk6-switch-$suffix');

      rig = FakeRig([
        LcBlock(
          op: 'try',
          body: [fxSay('试试看')],
          arms: [
            LcArm(
              body: [
                LcBlock(op: 'throw', args: {'message': fxText('没成功')}),
              ],
            ),
          ],
          orElse: [fxSay('收尾')],
        ),
        rigIf(),
      ]);
      await rig.pump(tester, mode: mode);
      await pullDockDown(tester);
      // 测试环境默认把投影画成一圈实心黑边（debugDisableShadows）：小菜单外面那圈粗黑边就是这么来的，真机上是柔和的投影。
      // 这一张按真机的画法截；截完改回去。
      debugDisableShadows = false;
      try {
        await tester.tapAt(rig.control([lcStep(1)], BkControlKind.add));
        await tester.pumpAndSettle();
        await shot(tester, 'bk6-add-menu-$suffix');
        await tester.tapAt(const Offset(300, 700));
        await tester.pumpAndSettle();
      } finally {
        debugDisableShadows = true;
      }
    });
  }
}

/// 新拿出来的“如果”（没有段、没有否则），里面放一块。
LcBlock rigIf() => LcBlock(op: 'if', args: {'cond': fxCmp(fxVar('分数'), '>', fxNum(60))}, body: [fxSay('及格')], noElse: true);

LcBlock rig1Switch() => LcBlock(
  op: 'switch',
  args: {'x': fxVar('次数')},
  arms: [
    LcArm(args: {'value': fxNum(1)}),
  ],
);

/// 把积木盒收到只剩手柄条（截图时画布露得多一点）。
Future<void> pullDockDown(WidgetTester tester) async {
  await tester.tap(k('bk-palette-handle'), warnIfMissed: false);
  await tester.pumpAndSettle();
}
