// 第 2 阶段的截图（390×844，浅色 + 深色）：定义帽子、参数小块拖出中、带口的值、三种调用外观、新建积木页、我的积木页、菜单、包成积木。
//   LOPI_SHOTS=1 flutter test --no-pub test/blocks_fn_shots_test.dart   # 写到 docs/screenshots/bk7-*.png
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/blocks/block_dock.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:material_ui/material_ui.dart';

import 'screens_test.dart' show fontsLoaded, shot;
import 'support/blocks_fake_host.dart';
import 'support/blocks_fake_rig.dart';
import 'support/blocks_fn_rig.dart';
import 'support/harness.dart';

Future<void> dockDown(WidgetTester tester) async {
  await tester.tap(k('bk-palette-handle'), warnIfMissed: false);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async => fontsLoaded = await loadRealFonts());
  tearDown(BkDockMemory.clear);

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    final suffix = mode == ThemeMode.light ? 'light' : 'dark';
    testWidgets('截图：定义帽子、带口的值、参数小块拖出中（$suffix）', (tester) async {
      final def = fxGreetDef();
      def.def!['params'] = [
        {'name': '名字'},
        {'name': '次数', 'default': 1},
        {'name': '其余', 'rest': true},
      ];
      final rig = FnRig([
        def,
        FakeScript('s2', body: [fxMapBlock(), fxSay('好了')], x: 0, y: 200),
      ]);
      await rig.pump(tester, mode: mode);
      await dockDown(tester);
      await shot(tester, 'bk7-hat-lambda-$suffix');

      // 参数小块拖出中：从帽子上拿出“名字”，对着“说”的槽。
      final from = rig.chip('s1', 0);
      final g = await rig.lift(tester, from);
      // 半路上（还没吸到槽上）：看得见帽子上那块还在、手上是一份副本、这一串里能放的槽都描了一圈。
      await rig.glide(tester, g, from, const Offset(250, 150));
      await tester.pump(const Duration(milliseconds: 300));
      await shot(tester, 'bk7-chip-drag-$suffix');
      await rig.glide(tester, g, from, rig.exprSnap('s1', [lcStep(0), lcStep(0)], 'text'));
      await tester.pump(const Duration(milliseconds: 300));
      await shot(tester, 'bk7-chip-snap-$suffix');
      await rig.drop(tester, g);

      // 把语句拖进匿名函数的口：让位 + 剪影。
      final from2 = rig.gripIn('s2', [lcStep(1)]);
      final g2 = await rig.lift(tester, from2);
      await rig.glide(tester, g2, from2, rig.snapIn('s2', [lcStep(0)], 1, arm: -2));
      await tester.pump(const Duration(milliseconds: 300));
      await shot(tester, 'bk7-mouth-drag-$suffix');
      await rig.drop(tester, g2);
      await tester.tapAt(const Offset(340, 700));
      await tester.pumpAndSettle();

      // 参数小卡（真实阴影）。先等前面的提示条消失。
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      debugDisableShadows = false;
      try {
        await tester.tapAt(rig.chip('s1', 1));
        await tester.pumpAndSettle();
        await shot(tester, 'bk7-param-card-$suffix');
        await tester.tapAt(const Offset(195, 780));
        await tester.pumpAndSettle();
      } finally {
        debugDisableShadows = true;
      }
    });

    testWidgets('截图：三种调用外观、“我的积木”页、长按菜单（$suffix）', (tester) async {
      final rig = FnRig(fxThreeLooks());
      await rig.pump(tester, mode: mode);
      await dockDown(tester);
      await shot(tester, 'bk7-three-looks-$suffix');
      await dockDown(tester);
      await rig.openTab(tester, '@custom');
      await shot(tester, 'bk7-custom-tab-$suffix');
      debugDisableShadows = false;
      try {
        final g = await tester.startGesture(tester.getTopLeft(rig.item('block-del')) + const Offset(10, 16));
        await tester.pump(const Duration(milliseconds: 700));
        await g.up();
        await tester.pumpAndSettle();
        await shot(tester, 'bk7-custom-menu-$suffix');
        await tester.tapAt(const Offset(350, 120));
        await tester.pumpAndSettle();
      } finally {
        debugDisableShadows = true;
      }
      // 空的“我的积木”页。
      final empty = FnRig([
        FakeScript('s1', body: [fxSay('开始')], x: 0, y: 0),
      ]);
      await empty.pump(tester, mode: mode);
      await empty.openTab(tester, '@custom');
      await shot(tester, 'bk7-custom-empty-$suffix');
    });

    testWidgets('截图：新建积木页——空的、填好的、有错误、键盘弹起（$suffix）', (tester) async {
      final rig = FnRig([fxGreetDef()]);
      await rig.pump(tester, mode: mode);
      await rig.openTab(tester, '@custom');
      await tester.tap(k('bk-palette-custom-new'));
      await tester.pumpAndSettle();
      await shot(tester, 'bk7-new-empty-$suffix');

      await tester.enterText(k('bk-look-name'), '删一条');
      await tester.enterText(k('bk-look-template'), '把 {集合} 里编号是 {id} 的那条删掉');
      await tester.pumpAndSettle();
      await tester.tap(k('bk-look-param-add'));
      await tester.pumpAndSettle();
      await tester.tap(k('bk-look-param-add'));
      await tester.pumpAndSettle();
      await tester.drag(k('bk-look-form'), const Offset(0, 3000));
      await tester.pumpAndSettle();
      await shot(tester, 'bk7-new-filled-$suffix');
      await tester.drag(k('bk-look-form'), const Offset(0, -420));
      await tester.pumpAndSettle();
      await shot(tester, 'bk7-new-filled-2-$suffix');
      await tester.drag(k('bk-look-form'), const Offset(0, 3000));
      await tester.pumpAndSettle();

      // 有错误：和已有的重名、文案里写了没有的槽。
      await tester.enterText(k('bk-look-name'), '问好');
      await tester.enterText(k('bk-look-template'), '把 {集合} 里编号是 {编号} 的那条删掉');
      await tester.pumpAndSettle();
      await shot(tester, 'bk7-new-error-$suffix');

      // 键盘弹起：预览还在。
      await tester.enterText(k('bk-look-name'), '删一条');
      await tester.enterText(k('bk-look-template'), '把 {集合} 里编号是 {id} 的那条删掉');
      await tester.showKeyboard(k('bk-look-template'));
      tester.view.viewInsets = const FakeViewPadding(bottom: 336);
      await tester.pumpAndSettle();
      await shot(tester, 'bk7-new-keyboard-$suffix');
      tester.view.resetViewInsets();
    });

    testWidgets('截图：包成积木前后、长按语句的菜单（$suffix）', (tester) async {
      final rig = FnRig([
        FakeScript(
          's1',
          body: [
            fxSay('前面'),
            LcBlock(
              op: 'set',
              args: {
                'name': '分数',
                'value': fxExpr('arith', {'l': fxVar('次数'), 'op': '+', 'r': fxNum(1)}),
              },
            ),
            LcBlock(op: 'say', args: {'text': fxVar('分数')}),
          ],
          x: 0,
          y: 0,
        ),
      ]);
      await rig.pump(tester, mode: mode);
      await dockDown(tester);
      debugDisableShadows = false;
      try {
        final g = await tester.startGesture(rig.grip([lcStep(1)]));
        await tester.pump(const Duration(milliseconds: 300));
        await g.up();
        await tester.pumpAndSettle();
        await shot(tester, 'bk7-wrap-before-$suffix');
        await tester.tap(k('bk-block-menu-wrap'));
        await tester.pumpAndSettle();
        await tester.enterText(k('bk-look-name'), '算分数');
        await tester.pumpAndSettle();
        await shot(tester, 'bk7-wrap-page-$suffix');
        await tester.tap(k('bk-look-done'));
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
        await shot(tester, 'bk7-wrap-after-$suffix');
      } finally {
        debugDisableShadows = true;
      }
    });
  }
}
