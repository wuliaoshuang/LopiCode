// “我的积木”的界面测试（390×844）：新建积木页的完整流程（新建 → 出现在积木盒 → 拖出来用 → 编辑改参数 → 各处跟着变 → 删除提示）、
// 就地校验、长按菜单、看它的定义、包成积木、三种调用外观在画布和积木盒里、撤销重做、不支持的宿主没有这一页。
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/blocks/block_dock.dart';
import 'package:lopicode/blocks/block_geometry.dart';
import 'package:lopicode/blocks/block_host.dart';
import 'package:lopicode/blocks/block_palette_model.dart';
import 'package:lopicode/lowcode/logic_expr.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:material_ui/material_ui.dart';

import 'screens_test.dart' show fontsLoaded;
import 'support/blocks_fake_host.dart';
import 'support/blocks_fake_rig.dart';
import 'support/blocks_fn_rig.dart';
import 'support/harness.dart';

Future<void> longPress(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  final g = await tester.startGesture(tester.getTopLeft(f) + const Offset(10, 16));
  await tester.pump(const Duration(milliseconds: 700));
  await g.up();
  await tester.pumpAndSettle();
}

/// 表单是懒加载的长列表：要找的那一行可能还没造出来，先滚回最上面，再一点点往下找。
Future<void> reveal(WidgetTester tester, String key) async {
  final form = k('bk-look-form');
  if (k(key).evaluate().isEmpty && form.evaluate().isNotEmpty) {
    await tester.drag(form, const Offset(0, 3000));
    await tester.pumpAndSettle();
    for (var i = 0; i < 30 && k(key).evaluate().isEmpty; i++) {
      await tester.drag(form, const Offset(0, -160));
      await tester.pumpAndSettle();
    }
  }
  expect(k(key), findsOneWidget, reason: '表单里找不到 $key');
  await tester.ensureVisible(k(key));
  await tester.pumpAndSettle();
}

Future<String> fieldText(WidgetTester tester, String key) async {
  await reveal(tester, key);
  return tester.widget<TextField>(k(key)).controller!.text;
}

Future<void> type(WidgetTester tester, String key, String text) async {
  await reveal(tester, key);
  await tester.enterText(k(key), text);
  await tester.pumpAndSettle();
}

Future<void> press(WidgetTester tester, String key) async {
  await reveal(tester, key);
  await tester.tap(k(key));
  await tester.pumpAndSettle();
}

List<String> errorsOf(WidgetTester tester, String id) => [
  // 没有问题时这一行不占地方（找不到也算没有）。
  for (final e in find.descendant(of: k('bk-look-error-$id'), matching: find.byType(Text)).evaluate()) (e.widget as Text).data ?? '',
];

Future<void> goBack(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async => fontsLoaded = await loadRealFonts());
  tearDown(BkDockMemory.clear);

  testWidgets('完整流程：新建 → 出现在积木盒 → 拖出来用 → 编辑改参数 → 各处跟着变 → 删除先说有几处在用', (tester) async {
    final rig = FnRig([FakeScript('s1', body: [fxSay('开始')], x: 0, y: 0)]);
    await rig.pump(tester);
    final start = rig.host.encode();
    await rig.openTab(tester, bkCustomCategoryId);
    expect(k('bk-palette-custom-empty'), findsOneWidget);
    await tester.tap(k('bk-palette-custom-new'));
    await tester.pumpAndSettle();
    expect(k('bk-look-form'), findsOneWidget);
    expect(k('bk-look-preview'), findsOneWidget);

    await type(tester, 'bk-look-name', '问好');
    await press(tester, 'bk-look-param-add');
    await type(tester, 'bk-look-param-name-0', '名字');
    await press(tester, 'bk-look-param-add');
    await type(tester, 'bk-look-param-name-1', '次数');
    await type(tester, 'bk-look-param-value-1', '1');
    await type(tester, 'bk-look-template', '向 {名字} 问好 {次数} 次');
    await press(tester, 'bk-look-done');
    expect(k('bk-look-form'), findsNothing);

    // 多了一串定义、积木盒里多了一块；一条撤销记录。
    final made = rig.fn.customs.single;
    expect(made.look.name, '问好');
    expect(made.params, ['名字', '次数']);
    final defId = rig.fn.definitionOf(made.id)!;
    expect(chipsOf(rig, defId), ['名字', '次数＝1']);
    expect(rig.shownItems(tester), ['block-${made.id}']);
    expect(k('bk-palette-custom-empty'), findsNothing);

    // 拖出来接在“说”后面：槽里先放着外观里说的东西。
    final from = tester.getTopLeft(rig.item('block-${made.id}')) + const Offset(10, 20);
    final g = await tester.startGesture(from);
    await tester.pump(const Duration(milliseconds: 220));
    await rig.glide(tester, g, from, from + const Offset(0, -30), steps: 3);
    await rig.glide(tester, g, from + const Offset(0, -30), rig.snap(const [], 1), steps: 8);
    await rig.drop(tester, g);
    final call = rig.tree.body[1];
    expect(call.op, made.id);
    expect(call.args, {'名字': fxText(''), '次数': fxNum(1)});
    final laid = rig.block([lcStep(1)]);
    expect(laid.labels.map((l) => l.text), ['向', '问好', '次']);
    expect(laid.slots.map((s) => s.arg), ['名字', '次数']);
    call.args['名字'] = fxText('小明');
    final used = rig.host.encode();

    // 编辑：次数删掉（先问）、加一个固定选项“语气”。各处调用跟着变。
    await longPress(tester, rig.item('block-${made.id}'));
    expect(k('bk-palette-custom-edit'), findsOneWidget);
    expect(k('bk-palette-custom-define'), findsOneWidget);
    expect(k('bk-palette-custom-remove'), findsOneWidget);
    await tester.tap(k('bk-palette-custom-edit'));
    await tester.pumpAndSettle();
    expect(find.text('编辑积木'), findsOneWidget);
    expect(await fieldText(tester, 'bk-look-name'), '问好');
    await press(tester, 'bk-look-param-delete-1');
    expect(find.text('删掉参数“次数”？'), findsOneWidget);
    expect(find.text('有 1 处在用，槽里的东西会丢掉。'), findsOneWidget);
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(await fieldText(tester, 'bk-look-template'), '向 {名字} 问好 次');
    await type(tester, 'bk-look-template', '用 {语气} 的语气向 {名字} 问好');
    expect(errorsOf(tester, 'template').join(), contains('语气'));
    await press(tester, 'bk-look-param-add');
    expect(await fieldText(tester, 'bk-look-param-name-1'), '语气');
    expect(errorsOf(tester, 'template'), isEmpty);
    await reveal(tester, 'bk-look-param-kind-1');
    await tester.tap(find.descendant(of: k('bk-look-param-kind-1'), matching: find.text('固定选项')));
    await tester.pumpAndSettle();
    expect(errorsOf(tester, 'param-1').join(), contains('选项'));
    await type(tester, 'bk-look-param-options-1', '客气、随便');
    expect(errorsOf(tester, 'param-1'), isEmpty);
    await press(tester, 'bk-look-done');
    expect(k('bk-look-form'), findsNothing);

    final after = rig.tree.body[1];
    expect(after.args.keys, ['名字', '语气']);
    expect(after.args['名字'], fxText('小明'), reason: '留着的参数，槽里的东西不动');
    expect(after.args['语气'], '客气');
    final relaid = rig.block([lcStep(1)]);
    expect(relaid.slots.map((s) => s.arg), ['语气', '名字']);
    expect(relaid.slots.first.look, BkSlotLook.dropdown);
    expect(chipsOf(rig, defId), ['名字', '语气']);
    expect(rig.s.selection, isNull, reason: '改完以后不留着旧的选中');
    rig.host.undo();
    await tester.pumpAndSettle();
    expect(rig.host.encode(), used, reason: '编辑（含各处调用跟着变）是一条撤销记录');
    rig.host.redo();
    await tester.pumpAndSettle();

    // 删除：先说有几处在用；取消不删；确认以后定义和调用都没了；撤销回来。
    final before = rig.host.encode();
    await longPress(tester, rig.item('block-${made.id}'));
    await tester.tap(k('bk-palette-custom-remove'));
    await tester.pumpAndSettle();
    expect(find.text('删掉“问好”？'), findsOneWidget);
    expect(find.textContaining('有 1 处在用'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(rig.host.encode(), before);
    await longPress(tester, rig.item('block-${made.id}'));
    await tester.tap(k('bk-palette-custom-remove'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(rig.fn.customs, isEmpty);
    expect(rig.host.encode(), start);
    expect(rig.tree.body.map((b) => b.op), ['say']);
    expect(k('bk-palette-custom-empty'), findsOneWidget);
    rig.host.undo();
    await tester.pumpAndSettle();
    expect(rig.host.encode(), before);
    expect(rig.shownItems(tester), ['block-${made.id}']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('新建积木页的校验：名字空着点“完成”才报；重名、和内置积木撞名、文案和参数对不上、参数重名，都贴在出问题的那一行下面说原因', (tester) async {
    final rig = FnRig([fxGreetDef()]);
    await rig.pump(tester);
    final start = rig.host.encode();
    await rig.openTab(tester, bkCustomCategoryId);
    await tester.tap(k('bk-palette-custom-new'));
    await tester.pumpAndSettle();
    expect(errorsOf(tester, 'name'), isEmpty, reason: '刚进来不报');
    await press(tester, 'bk-look-done');
    expect(k('bk-look-form'), findsOneWidget, reason: '没填好：留在这一页');
    expect(errorsOf(tester, 'name'), ['给这块积木起个名字']);

    await type(tester, 'bk-look-name', '问好');
    expect(errorsOf(tester, 'name').join(), contains('已经有'));
    await type(tester, 'bk-look-name', '说');
    expect(errorsOf(tester, 'name').join(), contains('内置积木'));
    await type(tester, 'bk-look-name', '打招呼');
    expect(errorsOf(tester, 'name'), isEmpty);

    await type(tester, 'bk-look-template', '向 {谁} 打招呼');
    expect(errorsOf(tester, 'template').join(), contains('谁'));
    // 文案里先写了 {谁}：加参数时直接就叫“谁”。
    await press(tester, 'bk-look-param-add');
    expect(await fieldText(tester, 'bk-look-param-name-0'), '谁');
    expect(errorsOf(tester, 'template'), isEmpty);
    await press(tester, 'bk-look-param-add');
    // 加参数：文案末尾自动接上它的槽；改名跟着改。
    expect(await fieldText(tester, 'bk-look-template'), '向 {谁} 打招呼 {参数1}');
    await type(tester, 'bk-look-param-name-1', '谁');
    expect(errorsOf(tester, 'param-1').join(), contains('已经有'));
    expect(await fieldText(tester, 'bk-look-template'), '向 {谁} 打招呼 {参数1}', reason: '名字不合适时文案不跟着乱改');
    await type(tester, 'bk-look-param-name-1', '几次');
    expect(await fieldText(tester, 'bk-look-template'), '向 {谁} 打招呼 {几次}');
    expect(errorsOf(tester, 'param-1'), isEmpty);
    // 文案里把一个参数删了：下面出现“＋{几次}”，点一下插回去。
    await type(tester, 'bk-look-template', '向 {谁} 打招呼');
    expect(errorsOf(tester, 'template').join(), contains('几次'));
    await press(tester, 'bk-look-insert-几次');
    expect(await fieldText(tester, 'bk-look-template'), '向 {谁} 打招呼 {几次}');
    expect(errorsOf(tester, 'template'), isEmpty);

    // 返回＝不建。
    await goBack(tester);
    expect(rig.host.encode(), start);
    expect(rig.host.canUndo, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('形状：选“值”→ 积木盒里是胶囊、能拖进槽；选“是否”→ 六边形；预览跟着变；键盘弹起时预览还在键盘上面', (tester) async {
    final rig = FnRig([FakeScript('s1', body: [fxSay('开始')], x: 0, y: 0)]);
    await rig.pump(tester);
    await rig.openTab(tester, bkCustomCategoryId);
    await tester.tap(k('bk-palette-custom-new'));
    await tester.pumpAndSettle();
    await type(tester, 'bk-look-name', '两倍');
    await press(tester, 'bk-look-param-add');
    await type(tester, 'bk-look-param-name-0', '数');
    await reveal(tester, 'bk-look-shape');
    await tester.tap(find.descendant(of: k('bk-look-shape'), matching: find.text('值')));
    await tester.pumpAndSettle();
    // 键盘弹起（下面 336 被占）：预览整个在键盘上面。
    tester.view.viewInsets = const FakeViewPadding(bottom: 336);
    await tester.pumpAndSettle();
    final preview = tester.getRect(k('bk-look-preview'));
    expect(preview.bottom, lessThan(844 - 336));
    expect(preview.top, greaterThanOrEqualTo(56));
    tester.view.resetViewInsets();
    await tester.pumpAndSettle();
    await press(tester, 'bk-look-done');
    final id = rig.fn.customs.single.id;
    expect(rig.fn.customs.single.isValue, isTrue);
    expect(rig.shownItems(tester), ['expr-$id']);

    final from = tester.getTopLeft(rig.item('expr-$id')) + const Offset(10, 14);
    final g = await tester.startGesture(from);
    await tester.pump(const Duration(milliseconds: 220));
    await rig.glide(tester, g, from, from + const Offset(0, -30), steps: 3);
    await rig.glide(tester, g, from + const Offset(0, -30), rig.exprSnap('s1', [lcStep(0)], 'text'), steps: 8);
    await rig.drop(tester, g);
    final e = asExpr(rig.first.args['text'])!;
    expect(exprKind(e), id);
    final laid = rig.block([lcStep(0)]).slots.single.expr!;
    expect(laid.hex, isFalse);
    expect(laid.labels.single.text, '两倍');

    // 改成“是否”：画布上那一块变成六边形。
    await longPress(tester, rig.item('expr-$id'));
    await tester.tap(k('bk-palette-custom-edit'));
    await tester.pumpAndSettle();
    await reveal(tester, 'bk-look-shape');
    await tester.tap(find.descendant(of: k('bk-look-shape'), matching: find.text('是否')));
    await tester.pumpAndSettle();
    await press(tester, 'bk-look-done');
    expect(rig.block([lcStep(0)]).slots.single.expr!.hex, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('看它的定义：画布滑到定义那一串（原来在屏幕外面）并选中它', (tester) async {
    final rig = FnRig([FakeScript('s2', body: [LcBlock(op: 'greet', args: {'名字': fxText('小明'), '次数': fxNum(2)})], x: 0, y: 0), fxGreetDef(y: 1400)]);
    await rig.pump(tester);
    Rect hatOnScreen() {
      final p = rig.s.layout.placed('s1')!;
      final r = p.layout.hat!.rect.shift(p.origin);
      return Rect.fromPoints(rig.s.globalOf(rig.s.toView(r.topLeft)), rig.s.globalOf(rig.s.toView(r.bottomRight)));
    }

    expect(hatOnScreen().top, greaterThan(844));
    await rig.openTab(tester, bkCustomCategoryId);
    await longPress(tester, rig.item('block-greet'));
    await tester.tap(k('bk-palette-custom-define'));
    await tester.pumpAndSettle();
    final r = hatOnScreen();
    expect(r.top, greaterThanOrEqualTo(0));
    expect(r.bottom, lessThan(700));
    expect(rig.s.selection?.scriptId, 's1');
    expect(rig.host.canUndo, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('包成积木：长按一块语句没挪就松手 → 菜单 → 起名字 → 这块和下面的包成新定义，原处换成一次调用；用到的外面的变量成了参数；一条撤销记录', (tester) async {
    final rig = FnRig([
      FakeScript('s1', body: [
        fxSay('前面'),
        LcBlock(op: 'set', args: {'name': '分数', 'value': fxExpr('arith', {'l': fxVar('次数'), 'op': '+', 'r': fxNum(1)})}),
        LcBlock(op: 'say', args: {'text': fxVar('分数')}),
      ], x: 0, y: 0),
    ]);
    await rig.pump(tester);
    final start = rig.host.encode();
    final g = await tester.startGesture(rig.grip([lcStep(1)]));
    await tester.pump(const Duration(milliseconds: 300));
    expect(rig.s.drag, isNotNull);
    await g.up();
    await tester.pumpAndSettle();
    expect(rig.s.drag, isNull);
    expect(rig.host.encode(), start);
    expect(k('bk-block-menu-wrap'), findsOneWidget);
    expect(find.text('从这块往下包成积木'), findsOneWidget);
    await tester.tap(k('bk-block-menu-wrap'));
    await tester.pumpAndSettle();
    expect(find.text('包成积木'), findsOneWidget);
    // 参数是算出来的：名字改不了、不能增删；形状只能是语句。
    await reveal(tester, 'bk-look-param-name-0');
    expect(tester.widget<TextField>(k('bk-look-param-name-0')).enabled, isFalse);
    expect(k('bk-look-param-delete-0'), findsNothing);
    expect(k('bk-look-param-add'), findsNothing);
    expect(find.descendant(of: k('bk-look-shape'), matching: find.text('值')), findsNothing);
    await type(tester, 'bk-look-name', '算分数');
    await press(tester, 'bk-look-done');

    final made = rig.fn.customs.single;
    expect(made.params, ['次数', '分数']);
    expect(rig.tree.body.map((b) => b.op), ['say', made.id]);
    expect(rig.tree.body[1].args.keys, made.params);
    final def = rig.script(rig.fn.definitionOf(made.id)!);
    expect(def.body.map((b) => b.op), ['set', 'say']);
    expect(rig.host.issues, isEmpty);
    expect(find.textContaining('包成了“算分数”'), findsOneWidget);
    rig.host.undo();
    await tester.pumpAndSettle();
    expect(rig.host.encode(), start);
    expect(rig.host.canUndo, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('包成积木：返回＝不包；长按后挪了＝照常拖走、不弹菜单；宿主不支持包（或没有“我的积木”）＝长按松手什么都不弹', (tester) async {
    var rig = FnRig([FakeScript('s1', body: [fxSay('一'), fxSay('二')], x: 0, y: 0)]);
    await rig.pump(tester);
    final start = rig.host.encode();
    var g = await tester.startGesture(rig.grip([lcStep(0)]));
    await tester.pump(const Duration(milliseconds: 300));
    await g.up();
    await tester.pumpAndSettle();
    await tester.tap(k('bk-block-menu-wrap'));
    await tester.pumpAndSettle();
    await goBack(tester);
    expect(rig.host.encode(), start);
    expect(rig.host.canUndo, isFalse);

    final from = rig.grip([lcStep(1)]);
    g = await rig.lift(tester, from);
    await rig.glide(tester, g, from, rig.snap(const [], 0));
    await rig.drop(tester, g);
    expect(k('bk-block-menu-wrap'), findsNothing);
    expect(rig.tree.body.map((b) => (b.args['text'] as Map)['v']), ['二', '一']);

    rig = FnRig([FakeScript('s1', body: [fxSay('一')], x: 0, y: 0)], wrappable: false);
    await rig.pump(tester);
    g = await tester.startGesture(rig.grip([lcStep(0)]));
    await tester.pump(const Duration(milliseconds: 300));
    await g.up();
    await tester.pumpAndSettle();
    expect(k('bk-block-menu-wrap'), findsNothing);

    final plain = FakeRig([fxSay('一')]);
    await plain.pump(tester);
    g = await tester.startGesture(plain.grip([lcStep(0)]));
    await tester.pump(const Duration(milliseconds: 300));
    await g.up();
    await tester.pumpAndSettle();
    expect(k('bk-block-menu-wrap'), findsNothing);
    expect(k('bk-palette-tab-$bkCustomCategoryId'), findsNothing, reason: '宿主没实现＝没有“我的积木”页签');
    expect(tester.takeException(), isNull);
  });

  testWidgets('三种调用外观摆在画布上：语句、值、是否各是各的形状，颜色照外观；积木盒“我的积木”页按顺序列出来', (tester) async {
    final rig = FnRig(fxThreeLooks());
    await rig.pump(tester);
    final layout = rig.s.layout.placed('use')!.layout;
    final st = layout.blockAt([lcStep(0)])!;
    expect(st.shape, BkShape.stack);
    expect(st.colorKey, BlockColorKey.list);
    expect(st.labels.map((l) => l.text), ['把', '里编号是', '的那条删掉']);
    final value = layout.blockAt([lcStep(1)])!.slots.single.expr!;
    expect(value.hex, isFalse);
    expect(value.colorKey, BlockColorKey.operator);
    final cond = layout.blockAt([lcStep(2)])!.slots.firstWhere((s) => s.arg == 'cond').expr!;
    expect(cond.hex, isTrue);
    await rig.openTab(tester, bkCustomCategoryId);
    expect(rig.shownItems(tester), ['block-del', 'expr-twice', 'expr-big']);
    expect(tester.takeException(), isNull);
  });
}
