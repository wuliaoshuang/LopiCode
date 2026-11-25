// 积木编辑器（BlockEditorView）的就地编辑测试：数字 / 文字 / 下拉 / 是否 / “换成…” / 一串值加减 / 选中后的工具条 / 问题 / 看代码。
//   LOPI_SHOTS=1 flutter test --no-pub test/blocks_editor_edit_test.dart   # 同时把截图写到 docs/screenshots/bk2-*.png
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/blocks/block_geometry.dart';
import 'package:lopicode/lowcode/logic_blocks.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:material_ui/material_ui.dart';

import 'screens_test.dart' show fontsLoaded, shot;
import 'support/blocks_fixture.dart';
import 'support/blocks_rig.dart';
import 'support/harness.dart';

Future<void> longPress(WidgetTester tester, Offset at) async {
  final g = await tester.startGesture(at);
  await tester.pump(const Duration(milliseconds: 520));
  await g.up();
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async => fontsLoaded = await loadRealFonts());

  testWidgets('就地改数字：贴着槽出现输入框、数字键盘、回车提交；填错了不关，点别处放弃', (tester) async {
    final rig = Rig(sampleDoc());
    await rig.pump(tester);
    final at = rig.slot(0, [lcStep(0)], (s) => s.look == BkSlotLook.field);
    await tester.tapAt(at);
    await tester.pumpAndSettle();
    final input = find.byKey(const ValueKey('bk-inline-input'));
    expect(input, findsOneWidget);
    expect(tester.widget<TextField>(input).keyboardType.index, TextInputType.number.index);
    expect(tester.widget<TextField>(input).controller!.text, '1');
    // 输入框贴着那个槽。
    expect((tester.getCenter(input) - at).distance, lessThan(48));
    // 改的时候积木盒让开（键盘要占地方）。
    expect(find.byKey(const ValueKey('bk-palette-handle')), findsNothing);

    await tester.enterText(input, '25');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(input, findsNothing);
    expect(rig.h(0).body[0].args['by'], {'e': 'num', 'v': 25});
    expect(rig.edits, 1);

    await tester.tapAt(rig.slot(0, [lcStep(0)], (s) => s.look == BkSlotLook.field));
    await tester.pumpAndSettle();
    await tester.enterText(input, '二十');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(input, findsOneWidget, reason: '填错了不能完成');
    expect(find.byKey(const ValueKey('bk-inline-error')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('bk-inline-barrier')), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.textContaining('不是数字'), findsOneWidget);
    await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));
    expect(input, findsNothing);
    expect(rig.h(0).body[0].args['by'], {'e': 'num', 'v': 25});
    expect(rig.edits, 1);

    // 没改就关：不算改动。
    await tester.tapAt(rig.slot(0, [lcStep(0)], (s) => s.look == BkSlotLook.field));
    await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(rig.edits, 1);
  });

  testWidgets('就地改文字：点别处就算填好', (tester) async {
    final rig = Rig(sampleDoc());
    await rig.pump(tester);
    await tester.tapAt(rig.slot(0, [lcStep(1), lcStep(0)], (s) => s.look == BkSlotLook.field));
    await tester.pumpAndSettle();
    final input = find.byKey(const ValueKey('bk-inline-input'));
    expect(tester.widget<TextField>(input).keyboardType, TextInputType.text);
    await tester.enterText(input, '别点啦 "真的"');
    await tester.tap(find.byKey(const ValueKey('bk-inline-barrier')), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(input, findsNothing);
    expect(rig.h(0).body[1].body[0].args['message'], {'e': 'text', 'v': '别点啦 "真的"'});
    expect(rig.edits, 1);
  });

  testWidgets('键盘弹出时，正在改的槽不被挡住', (tester) async {
    final rig = Rig(sampleDoc());
    await rig.pump(tester);
    // “重复 [3] 次”在画布靠下的地方。
    final at = rig.slot(0, [lcStep(2)], (s) => s.look == BkSlotLook.field);
    expect(at.dy, greaterThan(500));
    await tester.tapAt(at);
    await tester.pump();
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    final input = find.byKey(const ValueKey('bk-inline-input'));
    expect(input, findsOneWidget);
    expect(tester.getRect(input).bottom, lessThanOrEqualTo(844 - 320));
    final slotNow = rig.slot(0, [lcStep(2)], (s) => s.look == BkSlotLook.field);
    expect(slotNow.dy, lessThan(844 - 320), reason: '画布跟着往上挪了');
    expect((tester.getCenter(input) - slotNow).distance, lessThan(48));
    expect(rig.edits, 0, reason: '挪画布不算改动');
  });

  testWidgets('下拉类的槽：贴着槽弹小菜单，直接选（变量、运算符、帽子上的控件）', (tester) async {
    final rig = Rig(sampleDoc());
    await rig.pump(tester);
    final at = rig.slot(0, [lcStep(0)], (s) => s.look == BkSlotLook.dropdown && s.arg == 'name');
    await tester.tapAt(at);
    await tester.pumpAndSettle();
    final item = find.byKey(const ValueKey('bk-menu-msg'));
    expect(item, findsOneWidget);
    expect((tester.getTopLeft(item).dy - at.dy).abs(), lessThan(120), reason: '菜单贴着槽');
    await tester.tap(item);
    await tester.pumpAndSettle();
    expect(rig.h(0).body[0].args['name'], 'msg');
    expect(rig.edits, 1);

    // 条件里的运算符（嵌在表达式里的下拉）。
    await tester.tapAt(rig.slot(0, [lcStep(1)], (s) => s.look == BkSlotLook.dropdown && s.text == '并且'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('bk-menu-or')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('bk-menu-or')));
    await tester.pumpAndSettle();
    expect((rig.h(0).body[1].args['cond'] as Map<String, dynamic>)['op'], 'or');

    // 选回同一个：不算改动。
    await tester.tapAt(rig.slot(0, [lcStep(1)], (s) => s.look == BkSlotLook.dropdown && s.text == '或者'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('bk-menu-or')));
    await tester.pumpAndSettle();
    expect(rig.edits, 2);

    // 帽子上的“哪个控件”。
    final input = nodeIdOf(rig.doc, 'input');
    await tester.tapAt(rig.slot(0, const [], (s) => s.hatSlotId == 'target'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('bk-menu-$input')));
    await tester.pumpAndSettle();
    expect(rig.h(0).target, input);
    expect(rig.edits, 3);
  });

  testWidgets('“是 / 否”点一下就翻；空槽点一下弹“换成…”', (tester) async {
    final rig = Rig(shapesDoc());
    await rig.pump(tester);
    await rig.show(tester, 0, [lcStep(4)]);
    await tester.tapAt(rig.slot(0, [lcStep(4)], (s) => s.look == BkSlotLook.toggle));
    await tester.pumpAndSettle();
    expect(rig.h(0).body[4].args['message'], {'e': 'bool', 'v': false});

    await tester.tapAt(rig.slot(0, [lcStep(3)], (s) => s.look == BkSlotLook.empty));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('bk-replace')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('bk-replace-tab-运算')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('bk-replace-not')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('bk-replace')), findsNothing);
    expect(exprKind(rig.h(0).body[3].args['cond']), 'not');
    expect(rig.edits, 2);

    // 点卡片外面＝关掉，不改。
    await tester.tapAt(rig.slot(0, [lcStep(4)], (s) => s.look == BkSlotLook.toggle) + const Offset(0, 0));
    await tester.pumpAndSettle();
    expect(rig.edits, 3);
  });

  testWidgets('长按一个值弹“换成…”：换一种（原来拼好的包进去）、清空改回直接填', (tester) async {
    final rig = Rig(sampleDoc());
    await rig.pump(tester);
    Offset notAt() {
      final p = rig.placed(0);
      final not = p.layout.allSlots.map((e) => e.$2).firstWhere((sl) => sl.expr?.kind == 'not').expr!;
      return rig.s.globalOf(rig.s.toView(p.origin + not.rect.centerLeft + const Offset(9, 0)));
    }

    await longPress(tester, notAt());
    expect(find.byKey(const ValueKey('bk-replace')), findsOneWidget);
    expect(rig.s.drag, isNull, reason: '长按不是拖');
    // 点外面关掉。
    await tester.tapAt(const Offset(380, 80));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('bk-replace')), findsNothing);
    expect(rig.edits, 0);

    await longPress(tester, notAt());
    await tester.tap(find.byKey(const ValueKey('bk-replace-tab-运算')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('bk-replace-bin')));
    await tester.pumpAndSettle();
    final r = (rig.h(0).body[1].args['cond'] as Map<String, dynamic>)['r'] as Map<String, dynamic>;
    expect(exprKind(r), 'bin');
    expect(exprKind(r['l']), 'not', reason: '原来的“不是 ok”包进新的一块里');
    expect(rig.edits, 1);

    // 长按直接填的框也可以（把数字换成变量）。
    await longPress(tester, rig.slot(0, [lcStep(0)], (s) => s.look == BkSlotLook.field));
    await tester.tap(find.byKey(const ValueKey('bk-replace-tab-变量')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('bk-replace-var')));
    await tester.pumpAndSettle();
    expect(exprKind(rig.h(0).body[0].args['by']), 'var');

    // 清空：改回直接填。
    final p = rig.placed(0);
    final v = p.layout.allSlots.where((e) => bkSameBlockPath(e.$1.path, [lcStep(0)]) && e.$2.arg == 'by' && e.$2.expr != null).first.$2.expr!;
    await longPress(tester, rig.s.globalOf(rig.s.toView(p.origin + v.rect.centerLeft + const Offset(4, 0))));
    await tester.tap(find.byKey(const ValueKey('bk-replace-reset')));
    await tester.pumpAndSettle();
    expect(exprKind(rig.h(0).body[0].args['by']), 'num');
    expect(rig.edits, 3);
  });

  testWidgets('一串值（拼接）：点末尾的“＋”加一项，长按某一项可以去掉', (tester) async {
    final rig = Rig(sampleDoc());
    await rig.pump(tester);
    final path = [lcStep(1), lcStep(0, inElse: true)];
    await rig.show(tester, 0, path);
    List<dynamic> items() => ((rig.h(0).body[1].orElse[0].args['value'] as Map<String, dynamic>)['items'] as List);
    expect(items(), hasLength(3));
    await tester.tapAt(rig.slot(0, path, (s) => s.look == BkSlotLook.add));
    await tester.pumpAndSettle();
    expect(items(), hasLength(4));
    expect(exprKind(items().last), 'text');
    expect(rig.edits, 1);

    // 长按第一项（“点了”）。
    await longPress(tester, rig.slot(0, path, (s) => s.look == BkSlotLook.field && s.text.trim() == '点了'));
    expect(find.byKey(const ValueKey('bk-replace-remove')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('bk-replace-remove')));
    await tester.pumpAndSettle();
    expect(items(), hasLength(3));
    expect(exprKind(items().first), 'var');
    expect(rig.edits, 2);
  });

  testWidgets('选中积木：工具条上复制 / 删除；带子积木的删除要确认；删帽子＝删整串', (tester) async {
    final rig = Rig(sampleDoc());
    final haptics = captureHaptics(tester);
    await rig.pump(tester);
    expect(find.byKey(const ValueKey('bk-action-delete')), findsNothing);
    await tester.tapAt(rig.grip(0, [lcStep(0)]));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('bk-action-duplicate')));
    await tester.pumpAndSettle();
    expect(rig.ops(0), ['changeVar', 'changeVar', 'if', 'repeat']);
    expect(rig.s.selection!.path.last.index, 1, reason: '选中新复制出来的那块');
    await tester.tap(find.byKey(const ValueKey('bk-action-delete')));
    await tester.pumpAndSettle();
    expect(rig.ops(0), ['changeVar', 'if', 'repeat']);
    expect(haptics, contains('HapticFeedbackType.mediumImpact'));
    expect(rig.s.selection, isNull);

    await tester.tapAt(rig.grip(0, [lcStep(1)]));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('bk-action-delete')));
    await tester.pumpAndSettle();
    expect(find.text('连里面的一起删？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(rig.ops(0), ['changeVar', 'if', 'repeat']);
    await tester.tap(find.byKey(const ValueKey('bk-action-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(rig.ops(0), ['changeVar', 'repeat']);

    // 帽子：没有“复制”，删除＝删整串（里面有积木先问）。
    await tester.tapAt(rig.grip(0, const []));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('bk-action-duplicate')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('bk-action-delete')));
    await tester.pumpAndSettle();
    expect(find.text('删掉这一整串？'), findsOneWidget);
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(rig.handlers, hasLength(2));

    // 撤销两次：整串回来、“如果”回来。
    await tester.tap(find.byKey(const ValueKey('bk-undo')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('bk-undo')));
    await tester.pumpAndSettle();
    expect(rig.handlers, hasLength(3));
    expect(rig.ops(0), ['changeVar', 'if', 'repeat']);
  });

  testWidgets('问题列表：点一条跳到那块积木并选中、闪一下；看代码', (tester) async {
    final rig = Rig(shapesDoc());
    await rig.pump(tester);
    final issues = rig.host.issues;
    expect(issues, isNotEmpty);
    // 问题数现在有两处：顶栏的入口和积木盒手柄条左边；这里只看顶栏那一个。
    expect(
      find.descendant(of: find.byKey(const ValueKey('bk-issues')), matching: find.text('${issues.length}')),
      findsOneWidget,
      reason: '顶栏的问题数',
    );
    expect(find.text('${issues.length}'), findsNWidgets(2), reason: '顶栏和手柄条各一个');
    await tester.tap(find.byKey(const ValueKey('bk-issues')));
    await tester.pumpAndSettle();
    expect(find.text('${issues.length} 个问题'), findsOneWidget);
    final i = issues.lastIndexWhere((x) => x.scriptId != null && x.path.isNotEmpty);
    final row = find.byKey(ValueKey('bk-issue-$i'));
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tester.tap(row);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(rig.s.flashAnim.isAnimating, isTrue);
    await tester.pumpAndSettle();
    expect(rig.s.selection!.scriptId, issues[i].scriptId);
    expect(bkSameBlockPath(rig.s.selection!.path, issues[i].path), isTrue);
    // 那块积木挪到了看得见的地方，工具条上写着它的问题。
    final at = rig.grip(0, issues[i].path);
    expect(at.dy, inInclusiveRange(64, 844 - rig.s.dockHeight));
    expect(find.byKey(const ValueKey('bk-selection-issue')), findsOneWidget);
    expect(rig.edits, 0);

    await tester.tap(find.byKey(const ValueKey('bk-code')));
    await tester.pumpAndSettle();
    expect(find.textContaining('JavaScript'), findsWidgets);
    expect(find.textContaining('addEventListener', findRichText: true), findsWidgets);
  });

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    final suffix = mode == ThemeMode.light ? 'light' : 'dark';
    testWidgets('截图：就地改数字、下拉小菜单、“换成…”（$suffix）', (tester) async {
      final rig = Rig(sampleDoc());
      await rig.pump(tester, mode: mode);
      await tester.tapAt(rig.slot(0, [lcStep(1)], (s) => s.look == BkSlotLook.field && s.text == '10'));
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('bk-inline-input')), '12');
      await tester.pump();
      await shot(tester, 'bk2-inline-number-$suffix');
      tester.view.resetViewInsets();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      await tester.tapAt(rig.slot(0, [lcStep(0)], (s) => s.look == BkSlotLook.dropdown && s.arg == 'name'));
      await tester.pumpAndSettle();
      await shot(tester, 'bk2-menu-$suffix');
      await tester.tap(find.byKey(const ValueKey('bk-menu-count')));
      await tester.pumpAndSettle();

      await longPress(tester, rig.slot(0, [lcStep(0)], (s) => s.look == BkSlotLook.field));
      await tester.tap(find.byKey(const ValueKey('bk-replace-tab-运算')));
      await tester.pumpAndSettle();
      await shot(tester, 'bk2-replace-$suffix');
      expect(tester.takeException(), isNull);
    });
  }
}
