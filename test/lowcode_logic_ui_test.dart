// 积木逻辑页（LogicScreen：薄壳 + 通用积木编辑器 BlockEditorView）的界面测试（390×844，浅色 + 深色）。
//   LOPI_SHOTS=1 flutter test --no-pub test/lowcode_logic_ui_test.dart   # 同时把截图写到 docs/screenshots/bk2-logic-*.png
//
// 台子（test/support/blocks_rig.dart 的 Rig）模仿搭建页：手里一份文档 + 撤销历史，onEdit 每调一次算一条撤销记录、一次落盘；
// 而且**每次都先换一份新对象再改**，界面要是偷偷留着旧对象改，测试马上就能发现。
// 拖拽手感本身（吸附、阴影、垃圾桶、缩放）在 test/blocks_editor_test.dart，就地编辑在 test/blocks_editor_edit_test.dart；
// 这里测的是“前端逻辑页整条线走得通”：旧列表式界面测过的功能点，这里每一条都有对应。
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/blocks/block_geometry.dart';
import 'package:lopicode/lowcode/logic_blocks.dart';
import 'package:lopicode/lowcode/logic_js.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:material_ui/material_ui.dart';

import 'screens_test.dart' show fontsLoaded, shot;
import 'support/blocks_fixture.dart' show nodeIdOf;
import 'support/blocks_rig.dart';
import 'support/harness.dart';

/// 起始页：标题、说明、卡片里一个输入框和一个“提交”按钮。
LcDocument starter() => LcDocument.starter('测试页');

LcBlock say(String words) => LcBlock(op: 'alert', args: {'message': exText(words)});

Finder k(String key) => find.byKey(ValueKey(key));

Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> tapKey(WidgetTester tester, String key) => tap(tester, k(key));

Future<void> tapAt(WidgetTester tester, Offset at) async {
  await tester.tapAt(at);
  await tester.pumpAndSettle();
}

Future<void> longPress(WidgetTester tester, Offset at) async {
  final g = await tester.startGesture(at);
  await tester.pump(const Duration(milliseconds: 520));
  await g.up();
  await tester.pumpAndSettle();
}

/// 点积木盒里的一样东西（先切到它那一页）。
Future<void> pick(WidgetTester tester, String category, String itemKey) async {
  final tab = k('bk-palette-tab-$category');
  final tabs = k('bk-palette-tabs');
  await tester.drag(tabs, const Offset(600, 0));
  await tester.pumpAndSettle();
  for (var i = 0; i < 8 && tab.hitTestable().evaluate().isEmpty; i++) {
    await tester.drag(tabs, const Offset(-120, 0));
    await tester.pumpAndSettle();
  }
  await tester.tap(tab);
  await tester.pumpAndSettle();
  await tapKey(tester, 'bk-palette-item-$itemKey');
}

/// “换成…”浮层里挑一种。
Future<void> replaceWith(WidgetTester tester, String category, String kind) async {
  expect(k('bk-replace'), findsOneWidget);
  await tester.tap(k('bk-replace-tab-$category'));
  await tester.pumpAndSettle();
  await tester.tap(k('bk-replace-$kind'));
  await tester.pumpAndSettle();
}

Future<void> menuPick(WidgetTester tester, String value) async {
  final item = k('bk-menu-$value');
  await tester.ensureVisible(item);
  await tester.pumpAndSettle();
  await tester.tap(item);
  await tester.pumpAndSettle();
}

Future<void> typeInline(WidgetTester tester, String text) async {
  await tester.enterText(k('bk-inline-input'), text);
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async => fontsLoaded = await loadRealFonts());

  testWidgets('从空开始：加点击事件 → 加“变量加上” → 新建变量 count → 选它、数值改成 2；看代码；落盘次数；存下来的文档重新打开一样', (tester) async {
    final rig = Rig(starter());
    await rig.pumpLogic(tester);
    final button = nodeIdOf(rig.doc, 'button');
    expect(k('bk-empty'), findsOneWidget);
    expect(find.text('积木逻辑'), findsOneWidget);
    expect(find.byTooltip('返回'), findsOneWidget);

    // 还没有事件时点语句积木：说清楚要先有事件，不产生改动。
    await pick(tester, '交互', 'block-alert');
    expect(find.textContaining('先从“事件”里拿一块出来'), findsOneWidget);
    expect(rig.edits, 0);

    await pick(tester, 'event', 'hat-click');
    expect(rig.handlers.single.event, 'click');
    expect(rig.handlers.single.target, button, reason: '默认挂在第一个按钮上');
    expect(k('bk-empty'), findsNothing);
    await pick(tester, '变量', 'block-changeVar');
    expect(rig.ops(0), ['changeVar']);
    expect(rig.h(0).body.single.args['name'], '', reason: '还没有变量');
    expect(rig.s.host.issues, isNotEmpty);

    // 变量槽的小菜单里最后一项“新建变量…”：建出来并选中，一条撤销记录。
    await tapAt(tester, rig.arg(0, [lcStep(0)], 'name'));
    await tester.tap(k('bk-menu-extra'));
    await tester.pumpAndSettle();
    await tester.enterText(k('lc-var-name'), 'count');
    await tapKey(tester, 'lc-var-type-number');
    await tap(tester, find.widgetWithText(TextButton, '新建'));
    expect(rig.doc.logic.variable('count')!.type, 'number');
    expect(rig.h(0).body.single.args['name'], 'count');
    expect(rig.edits, 3, reason: '加事件、加积木、新建变量并选中 各一条');
    expect(
      find.descendant(of: k('lc-top-vars'), matching: find.text('1')),
      findsOneWidget,
      reason: '顶栏的变量数跟着变',
    );

    await tapAt(tester, rig.arg(0, [lcStep(0)], 'by'));
    await typeInline(tester, '2');
    expect(rig.h(0).body.single.args['by'], exNum(2));
    expect(rig.edits, 4);
    expect(validateLogic(rig.doc), isEmpty);
    expect(rig.s.host.issues, isEmpty);

    await tapKey(tester, 'bk-code');
    expect(find.textContaining('JavaScript'), findsWidgets);
    final js = exportLogicJs(rig.doc);
    expect(js, contains('count'));
    expect(js, contains('2'));
    expect(find.textContaining(js.trim().split('\n').first), findsWidgets, reason: '面板里就是翻出来的那份脚本');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    // 存盘的内容重新读出来还是这一份；自动排的位置没有写进去。
    final again = LcDocument.parse(rig.doc.encode());
    expect(exportLogicJs(again), exportLogicJs(rig.doc));
    expect(again.logic.handlers.single.x, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('“如果”积木：往“那么”“否则”两个口子里各拖一块；点开又关掉不产生撤销记录', (tester) async {
    final doc = starter();
    doc.logic.addHandler('load')!.insertBlock(const [], newBlock('if', doc));
    final rig = Rig(doc);
    await rig.pumpLogic(tester);
    final id = rig.h(0).id;

    var g = await rig.liftFromPalette(tester, '交互', 'block-alert');
    await rig.glide(tester, g, rig.stackSnap(id, [lcStep(0)], 0));
    expect(rig.s.drag!.ghost, isNotNull);
    await rig.drop(tester, g);
    g = await rig.liftFromPalette(tester, '交互', 'block-navigate');
    await rig.glide(tester, g, rig.stackSnap(id, [lcStep(0)], 0, inElse: true));
    await rig.drop(tester, g);
    expect([for (final b in rig.h(0).body.single.body) b.op], ['alert']);
    expect([for (final b in rig.h(0).body.single.orElse) b.op], ['navigate']);
    expect(rig.edits, 2);

    // 打开输入框不改就关、打开小菜单点外面、打开“换成…”点外面：都不算改动。
    await tapAt(tester, rig.arg(0, [lcStep(0), lcStep(0)], 'message'));
    expect(k('bk-inline-input'), findsOneWidget);
    await tester.tap(k('bk-inline-barrier'), warnIfMissed: false);
    await tester.pumpAndSettle();
    await longPress(tester, rig.arg(0, [lcStep(0)], 'cond'));
    expect(k('bk-replace'), findsOneWidget);
    await tapAt(tester, const Offset(380, 90));
    expect(k('bk-replace'), findsNothing);
    expect(rig.edits, 2);
    expect(rig.history.canUndo, isTrue);
  });

  testWidgets('表达式嵌套编辑：count > 10 并且 输入框的内容 等于 "ok"', (tester) async {
    final doc = starter();
    final input = nodeIdOf(doc, 'input');
    doc.logic.addVariable('count', type: 'number');
    doc.logic.addHandler('input', target: input)!.insertBlock(const [], newBlock('if', doc));
    final rig = Rig(doc);
    await rig.pumpLogic(tester);
    final at = [lcStep(0)];

    await longPress(tester, rig.arg(0, at, 'cond'));
    // “输入的内容”在控件那一页里可选。
    await tester.tap(k('bk-replace-tab-控件'));
    await tester.pumpAndSettle();
    expect(k('bk-replace-event'), findsOneWidget);
    await replaceWith(tester, '运算', 'bin');
    await tapAt(tester, rig.arg(0, at, 'cond', const ['op']));
    await menuPick(tester, 'and');

    await longPress(tester, rig.arg(0, at, 'cond', const ['l']));
    await replaceWith(tester, '运算', 'bin');
    await tapAt(tester, rig.arg(0, at, 'cond', const ['l', 'op']));
    await menuPick(tester, '>');
    await longPress(tester, rig.arg(0, at, 'cond', const ['l', 'l']));
    await replaceWith(tester, '变量', 'var');
    await tapAt(tester, rig.arg(0, at, 'cond', const ['l', 'r']));
    await typeInline(tester, '10');

    await longPress(tester, rig.arg(0, at, 'cond', const ['r']));
    await replaceWith(tester, '运算', 'bin');
    await tapAt(tester, rig.arg(0, at, 'cond', const ['r', 'op']));
    await menuPick(tester, '==');
    await longPress(tester, rig.arg(0, at, 'cond', const ['r', 'l']));
    await replaceWith(tester, '控件', 'prop');
    await longPress(tester, rig.arg(0, at, 'cond', const ['r', 'r']));
    await replaceWith(tester, '直接填', 'text');
    await tapAt(tester, rig.arg(0, at, 'cond', const ['r', 'r']));
    await typeInline(tester, 'ok');

    expect(rig.h(0).body.single.args['cond'], exBin('and', exBin('>', exVar('count'), exNum(10)), exBin('==', exProp(input, 'value'), exText('ok'))));
    expect(validateLogic(rig.doc), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('拼成文字：加一项、去一项；数字填错不能完成', (tester) async {
    final doc = starter();
    doc.logic.addHandler('load')!.body.addAll([
      LcBlock(
        op: 'alert',
        args: {
          'message': exJoin([exText('甲'), exText('乙')]),
        },
      ),
      LcBlock(op: 'repeat', args: {'times': exNum(3)}),
    ]);
    final rig = Rig(doc);
    await rig.pumpLogic(tester);
    List<dynamic> items() => (rig.h(0).body[0].args['message'] as Map<String, dynamic>)['items'] as List;

    await tapAt(tester, rig.slot(0, [lcStep(0)], (s) => s.look == BkSlotLook.add));
    expect(items(), hasLength(3));
    await longPress(tester, rig.arg(0, [lcStep(0)], 'message', const ['items', 0]));
    await tester.tap(k('bk-replace-remove'));
    await tester.pumpAndSettle();
    expect(items(), [exText('乙'), exText('')]);
    expect(rig.edits, 2);

    await tapAt(tester, rig.arg(0, [lcStep(1)], 'times'));
    await typeInline(tester, '三次');
    expect(k('bk-inline-input'), findsOneWidget, reason: '填错了不能完成');
    expect(k('bk-inline-error'), findsOneWidget);
    await typeInline(tester, '5');
    expect(k('bk-inline-input'), findsNothing);
    expect(rig.h(0).body[1].args['times'], exNum(5));
    expect(rig.edits, 3);
  });

  testWidgets('选中积木：在它下面加一块 / 复制 / 删除；带子积木的删除要确认；撤销重做交回搭建页', (tester) async {
    final doc = starter();
    doc.logic.addHandler('load')!.body.addAll([
      say('甲'),
      LcBlock(op: 'if', args: {'cond': exBool(true)}, body: [say('里面')]),
      say('丙'),
    ]);
    final rig = Rig(doc);
    await rig.pumpLogic(tester);
    List<String> words() => [for (final b in rig.h(0).body) b.op == 'alert' ? '${(b.args['message'] as Map)['v']}' : b.op];

    // 选中“甲”，点积木盒里的一块：加在它下面，而不是末尾。
    await tapAt(tester, rig.grip(0, [lcStep(0)]));
    expect(k('bk-action-delete'), findsOneWidget);
    await pick(tester, '交互', 'block-log');
    expect(rig.ops(0), ['alert', 'log', 'if', 'alert']);
    expect(rig.s.selection!.path.single.index, 1, reason: '选中新加的那块');

    await tapKey(tester, 'bk-action-duplicate');
    expect(rig.ops(0), ['alert', 'log', 'log', 'if', 'alert']);
    await tapKey(tester, 'bk-action-delete');
    await tapAt(tester, rig.grip(0, [lcStep(1)]));
    await tapKey(tester, 'bk-action-delete');
    expect(words(), ['甲', 'if', '丙']);

    await tapAt(tester, rig.grip(0, [lcStep(1)]));
    await tapKey(tester, 'bk-action-delete');
    expect(find.text('连里面的一起删？'), findsOneWidget);
    await tap(tester, find.text('取消'));
    expect(words(), ['甲', 'if', '丙']);
    await tapKey(tester, 'bk-action-delete');
    await tap(tester, find.text('删除'));
    expect(words(), ['甲', '丙']);
    final edits = rig.edits;

    // 撤销 / 重做：走的是搭建页那条历史，文档交回去（搭建页在那时落盘）。
    await tapKey(tester, 'bk-undo');
    expect(words(), ['甲', 'if', '丙']);
    expect(rig.restores, 1);
    await tapKey(tester, 'bk-redo');
    expect(words(), ['甲', '丙']);
    expect(rig.restores, 2);
    expect(rig.edits, edits, reason: '撤销重做不是新的改动');
    expect(tester.widget<IconButton>(k('bk-redo')).onPressed, isNull);
  });

  testWidgets('拖动重排：同一串里换位置（上移 / 下移）、拖进子栈、不能拖进自己里面、原地放下不算改动', (tester) async {
    final doc = starter();
    doc.logic.addHandler('load')!.body.addAll([
      say('甲'),
      say('乙'),
      LcBlock(op: 'if', args: {'cond': exBool(true)}),
      say('丁'),
    ]);
    final rig = Rig(doc);
    await rig.pumpLogic(tester);
    final id = rig.h(0).id;
    List<String> words(List<LcBlock> l) => [for (final b in l) b.op == 'alert' ? '${(b.args['message'] as Map)['v']}' : b.op];

    // 原地放下。
    var g = await rig.lift(tester, rig.grip(0, [lcStep(3)]));
    await rig.glide(tester, g, rig.stackSnap(id, const [], 3));
    await rig.drop(tester, g);
    expect(rig.edits, 0);

    // “丁”拖到最前面（＝上移到头）。
    g = await rig.lift(tester, rig.grip(0, [lcStep(3)]));
    await rig.glide(tester, g, rig.stackSnap(id, const [], 0));
    expect(rig.s.drag!.ghost, isNotNull);
    await rig.drop(tester, g);
    expect(words(rig.h(0).body), ['丁', '甲', '乙', 'if']);

    // “如果”拖到“甲”前面：它后面没有别的，整块上移。
    g = await rig.lift(tester, rig.grip(0, [lcStep(3)]));
    await rig.glide(tester, g, rig.stackSnap(id, const [], 1));
    await rig.drop(tester, g);
    expect(words(rig.h(0).body), ['丁', 'if', '甲', '乙']);

    // “乙”拖进“如果”的口子里。
    g = await rig.lift(tester, rig.grip(0, [lcStep(3)]));
    await rig.glide(tester, g, rig.stackSnap(id, [lcStep(1)], 0));
    await rig.drop(tester, g);
    expect(words(rig.h(0).body), ['丁', 'if', '甲']);
    expect(words(rig.h(0).body[1].body), ['乙']);

    // 拖着“如果”：它自己里面的口子不是落点（拿起来以后那里根本没有拼接点）。
    g = await rig.lift(tester, rig.grip(0, [lcStep(1)]));
    final inside = rig.s.drag!.base.placed(id)!.layout.snaps.where((x) => x.kind == BkSnapKind.statement && x.parent.isNotEmpty);
    expect(inside, isEmpty);
    await rig.glide(tester, g, const Offset(330, 300));
    await rig.drop(tester, g);
    expect(find.textContaining('积木要接在事件下面'), findsOneWidget);
    expect(words(rig.h(0).body), ['丁', 'if', '甲']);
    expect(rig.edits, 3);
  });

  testWidgets('拖动时手指停在画布下沿：画布自己往下滚，可以放到原来在屏幕外的位置', (tester) async {
    final doc = starter();
    doc.logic.addHandler('load')!.body.addAll([for (var i = 0; i < 14; i++) say('第 $i 句')]);
    final rig = Rig(doc);
    await rig.pumpLogic(tester);
    final id = rig.h(0).id;
    final canvas = tester.getRect(k('bk-canvas'));
    final edge = canvas.bottom - rig.s.dockHeight;
    expect(rig.grip(0, [lcStep(13)]).dy, greaterThan(edge), reason: '最后一块一开始在屏幕外');

    // 从积木盒拿一块，停在画布露出部分的下沿。
    final g = await rig.liftFromPalette(tester, '交互', 'block-log');
    await rig.glide(tester, g, Offset(120, edge - 16));
    final before = rig.s.pan.dy;
    for (var i = 0; i < 120; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(rig.s.pan.dy, lessThan(before - 100), reason: '画布往上走了（内容往下滚）');
    // 一直滚到末尾的拼接点进了屏幕，放下去。
    for (var i = 0; i < 400 && rig.stackSnap(id, const [], 14).dy > edge - 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await rig.glide(tester, g, rig.stackSnap(id, const [], 14));
    expect(rig.s.drag!.ghost, isNotNull);
    await rig.drop(tester, g);
    expect(rig.h(0).body, hasLength(15));
    expect(rig.h(0).body.last.op, 'log');
    expect(rig.edits, 1);
  });

  testWidgets('键盘弹出时：正在改的槽和输入框不被挡住', (tester) async {
    final doc = starter();
    doc.logic.addHandler('load')!.body.addAll([for (var i = 0; i < 10; i++) say('第 $i 句')]);
    final rig = Rig(doc);
    await rig.pumpLogic(tester);
    final at = rig.arg(0, [lcStep(9)], 'message');
    expect(at.dy + 20, greaterThan(844 - 320), reason: '这一块原本在键盘会盖住的地方');
    await tester.tapAt(at);
    await tester.pump();
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    expect(tester.getRect(k('bk-inline-input')).bottom, lessThanOrEqualTo(844 - 320));
    await typeInline(tester, '改好了');
    expect((rig.h(0).body[9].args['message'] as Map)['v'], '改好了');
  });

  testWidgets('变量：改名同步引用；删除在用的变量要确认；重名和不合规矩的名字就地提示', (tester) async {
    final doc = starter();
    doc.logic.addVariable('count', type: 'number');
    doc.logic.addVariable('name');
    final h = doc.logic.addHandler('load')!;
    h.insertBlock(const [], LcBlock(op: 'changeVar', args: {'name': 'count', 'by': exNum(1)}));
    h.insertBlock(const [], LcBlock(op: 'alert', args: {'message': exVar('count')}));
    final rig = Rig(doc);
    await rig.pumpLogic(tester);

    await tapKey(tester, 'lc-top-vars');
    expect(find.text('数字 · 初始值 0 · 2 处在用'), findsOneWidget);
    await tapKey(tester, 'lc-vars-row-count');
    await tester.enterText(k('lc-var-name'), 'name');
    await tap(tester, find.text('保存'));
    expect(find.text('已经有一个变量叫 name 了'), findsOneWidget);
    await tester.enterText(k('lc-var-name'), '1abc');
    await tap(tester, find.text('保存'));
    expect(find.textContaining('不能用数字开头'), findsOneWidget);
    expect(rig.edits, 0);

    await tester.enterText(k('lc-var-name'), 'total');
    await tester.enterText(k('lc-var-initial'), '5');
    await tap(tester, find.text('保存'));
    expect(rig.edits, 1, reason: '改名 + 改初始值一次保存，一条撤销记录');
    expect(rig.doc.logic.variable('count'), isNull);
    expect(rig.doc.logic.variable('total')!.initial, 5);
    expect(rig.h(0).body[0].args['name'], 'total');
    expect(rig.h(0).body[1].args['message'], exVar('total'));
    expect(find.text('数字 · 初始值 5 · 2 处在用'), findsOneWidget);

    // 改类型：文字 → 是 / 否。
    await tapKey(tester, 'lc-vars-row-name');
    await tapKey(tester, 'lc-var-type-bool');
    await tapKey(tester, 'lc-var-flag');
    await tap(tester, find.text('保存'));
    expect(rig.doc.logic.variable('name')!.type, 'bool');
    expect(rig.doc.logic.variable('name')!.initial, true);
    expect(rig.edits, 2);

    // 删除在用的变量：先说有几处在用。
    await tapKey(tester, 'lc-vars-row-total');
    await tap(tester, find.widgetWithText(TextButton, '删除'));
    expect(find.textContaining('有 2 处在用它'), findsOneWidget);
    await tap(tester, find.widgetWithText(TextButton, '删除'));
    expect(rig.doc.logic.variable('total'), isNull);
    expect(rig.edits, 3);

    // 关掉面板：画布跟着变了——用到它的两块积木被标了问题，顶栏的问题数是 2、变量数是 1。
    await tester.tapAt(const Offset(195, 40));
    await tester.pumpAndSettle();
    final issues = rig.s.host.issues;
    expect([for (final i in issues) i.path.single.index], unorderedEquals([0, 1]));
    expect(find.descendant(of: k('bk-issues'), matching: find.text('2')), findsOneWidget);
    expect(find.descendant(of: k('lc-top-vars'), matching: find.text('1')), findsOneWidget);
    // 画布上那两块确实带着问题标记。
    expect(rig.s.issues, hasLength(2), reason: '画布手里的问题清单（画红点用的）也刷新了');
    expect(tester.takeException(), isNull);
  });

  testWidgets('校验问题：顶栏带数量，点开是人话，点一条跳过去并选中那块积木', (tester) async {
    final doc = starter();
    final h = doc.logic.addHandler('click', target: nodeIdOf(doc, 'button'))!;
    h.body.addAll([for (var i = 0; i < 13; i++) say('第 $i 句')]);
    h.body.add(LcBlock(op: 'setVar', args: {'name': 'nope', 'value': exText('x')}));
    final rig = Rig(doc);
    await rig.pumpLogic(tester);
    final issues = rig.s.host.issues;
    expect(issues, hasLength(1));
    expect(find.descendant(of: k('bk-issues'), matching: find.text('1')), findsOneWidget);
    final canvas = tester.getRect(k('bk-canvas'));
    expect(rig.grip(0, [lcStep(13)]).dy, greaterThan(canvas.bottom - rig.s.dockHeight), reason: '有问题的那块一开始在屏幕外');

    await tapKey(tester, 'bk-issues');
    expect(find.text('1 个问题'), findsOneWidget);
    expect(find.textContaining('nope'), findsWidgets);
    await tapKey(tester, 'bk-issue-0');
    expect(rig.s.selection!.scriptId, h.id);
    expect(rig.s.selection!.path.single.index, 13);
    expect(rig.grip(0, [lcStep(13)]).dy, inInclusiveRange(canvas.top, canvas.bottom - rig.s.dockHeight));
    expect(k('bk-selection-issue'), findsOneWidget);
    expect(rig.edits, 0);

    // 没有问题时：点开说“没有问题”。
    await tapKey(tester, 'bk-action-delete');
    expect(rig.s.host.issues, isEmpty);
    await tapKey(tester, 'bk-issues');
    expect(k('bk-issues-none'), findsOneWidget);
  });

  testWidgets('从某个控件点进来：画布移到它的事件并选中；新加的事件默认挂在它上面；别的事件照样看得到、改得了', (tester) async {
    final doc = starter();
    final button = nodeIdOf(doc, 'button');
    final input = nodeIdOf(doc, 'input');
    doc.logic.addHandler('click', target: button)!.body.addAll([for (var i = 0; i < 12; i++) say('按钮 $i')]);
    doc.logic.addHandler('input', target: input)!.body.add(say('输入'));
    final rig = Rig(doc);
    await rig.pumpLogic(tester, initialNodeId: input);
    final canvas = tester.getRect(k('bk-canvas'));

    expect(rig.s.selection!.scriptId, rig.h(1).id, reason: '选中的是输入框那一串的帽子');
    expect(rig.s.selection!.path, isEmpty);
    expect(rig.grip(1, const []).dy, inInclusiveRange(canvas.top, canvas.top + 160), reason: '它在画布顶上，不用自己找');

    // 新加“内容变化”事件：挂在点进来的这个输入框上。
    await pick(tester, 'event', 'hat-input');
    expect(rig.handlers, hasLength(3));
    expect(rig.h(2).target, input);

    // 没有“只看：…”的筛选了：按钮那一串还在画布上，挪过去就能改。
    expect(find.textContaining('只看'), findsNothing);
    await rig.show(tester, 0);
    await tapAt(tester, rig.arg(0, [lcStep(0)], 'message'));
    await typeInline(tester, '改了');
    expect((rig.h(0).body[0].args['message'] as Map)['v'], '改了');
  });

  testWidgets('从一个还没有事件的控件点进来：说一句怎么加；新加的点击事件挂在它上面', (tester) async {
    final doc = starter();
    final first = nodeIdOf(doc, 'button');
    final extra = doc.newNode('button');
    expect(doc.insert(doc.root.id, extra), isTrue);
    final second = extra.id;
    doc.logic.addHandler('click', target: first);
    final rig = Rig(doc);
    await rig.pumpLogic(tester, initialNodeId: second);
    expect(find.textContaining('还没有事件'), findsOneWidget);
    expect(rig.s.selection, isNull);
    await pick(tester, 'event', 'hat-click');
    expect(rig.h(1).target, second);
    expect(rig.edits, 1);
  });

  testWidgets('目标控件不存在的事件：不崩，问题里说清楚；可以在帽子上改目标，或者整串删掉；不认识的积木画得出来、删得掉', (tester) async {
    final doc = starter();
    final button = nodeIdOf(doc, 'button');
    doc.logic.handlers.add(LcHandler(id: 'h1', event: 'click', target: 'gone', body: [say('甲')]));
    doc.logic.handlers.add(
      LcHandler(
        id: 'h2',
        event: 'click',
        body: [
          LcBlock(op: 'setProp', args: {'node': 'gone', 'prop': 'text', 'value': exText('x')}),
          LcBlock(op: 'mystery', args: {'a': 1}, body: [say('里面')]),
        ],
      ),
    );
    final rig = Rig(doc);
    await rig.pumpLogic(tester);
    expect(tester.takeException(), isNull);
    final messages = [for (final i in rig.s.host.issues) i.message];
    expect(messages.where((m) => m.contains('已不存在') || m.contains('已经不在') || m.contains('删除')), isNotEmpty, reason: '$messages');
    expect(messages.where((m) => m.contains('还没选是哪个控件触发的')), hasLength(1));
    expect(messages.where((m) => m.contains('不认识的积木 mystery')), hasLength(1));
    await tapKey(tester, 'bk-issues');
    expect(find.textContaining('还没选是哪个控件触发的'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    // 在帽子上改目标：点帽子上的控件槽，小菜单里选。
    await tapAt(tester, rig.slot(0, const [], (s) => s.hatSlotId == 'target'));
    await menuPick(tester, button);
    expect(rig.doc.logic.handler('h1')!.target, button);
    expect(rig.edits, 1);
    expect([for (final i in rig.s.host.issues) i.scriptId], isNot(contains('h1')));

    // 不认识的积木：画得出来（有它的一块），选中后可以删；里面还有积木要确认。
    await rig.show(tester, 1, [lcStep(1)]);
    final unknown = rig.placed(1).layout.blockAt([lcStep(1)])!;
    expect(unknown.rect.width, greaterThan(80));
    await tapAt(tester, rig.grip(1, [lcStep(1)]));
    await tapKey(tester, 'bk-action-delete');
    expect(find.text('连里面的一起删？'), findsOneWidget);
    await tap(tester, find.text('删除'));
    expect([for (final b in rig.doc.logic.handler('h2')!.body) b.op], ['setProp']);

    // 整串删掉：选中帽子点删除，先问；取消就不删。
    await tapAt(tester, rig.grip(1, const []));
    await tapKey(tester, 'bk-action-delete');
    expect(find.text('删掉这一整串？'), findsOneWidget);
    await tap(tester, find.text('取消'));
    expect(rig.doc.logic.handler('h2'), isNotNull);
    await tapKey(tester, 'bk-action-delete');
    await tap(tester, find.text('删除'));
    expect(rig.doc.logic.handler('h2'), isNull);
    expect(rig.edits, 3);
    expect(tester.takeException(), isNull);
  });

  testWidgets('改控件积木：换控件、换属性时值跟着换成对得上的；取值的“控件的属性”换控件也一样', (tester) async {
    final doc = starter();
    final input = nodeIdOf(doc, 'input');
    final button = nodeIdOf(doc, 'button');
    doc.logic.addHandler('load')!.body.addAll([
      newBlock('setProp', doc),
      LcBlock(op: 'alert', args: {'message': exProp(input, 'value')}),
    ]);
    final rig = Rig(doc);
    await rig.pumpLogic(tester);
    LcBlock b() => rig.h(0).body.first;
    expect(b().args['prop'], 'text');

    // 换成输入框：它没有“文字”可改，自动换成它有的第一个属性。
    await tapAt(tester, rig.arg(0, [lcStep(0)], 'node'));
    await menuPick(tester, input);
    expect(b().args['node'], input);
    expect(b().args['prop'], 'value');

    // 属性换成“是否显示”：值换成“是”；可选的只有输入框有的属性。
    await tapAt(tester, rig.arg(0, [lcStep(0)], 'prop'));
    expect(k('bk-menu-text'), findsNothing);
    expect(k('bk-menu-src'), findsNothing);
    await menuPick(tester, 'visible');
    expect(b().args['value'], exBool(true));
    // 再换回“输入内容”：值换回文字。
    await tapAt(tester, rig.arg(0, [lcStep(0)], 'prop'));
    await menuPick(tester, 'value');
    expect(b().args['value'], exText(''));
    expect(rig.edits, 3);

    // 取值：“输入框 的 输入内容”换成按钮——按钮读不到“输入内容”，换成它读得到的第一个。
    await tapAt(tester, rig.arg(0, [lcStep(1)], 'message', const ['node']));
    await menuPick(tester, button);
    expect(rig.h(0).body[1].args['message'], exProp(button, readablePropsFor('button').first));
    expect(validateLogic(rig.doc), isEmpty);
  });

  testWidgets('很深的嵌套（6 层如果 + 长文字）在 390 宽下不出错：最里面那块选得中、放得下、能缩小看全', (tester) async {
    final doc = starter();
    final button = nodeIdOf(doc, 'button');
    doc.logic.addVariable('a_very_long_variable_name_test', type: 'number');
    var inner = <LcBlock>[
      LcBlock(
        op: 'setProp',
        args: {
          'node': button,
          'prop': 'text',
          'value': exJoin([exText('这是一段特别特别长的文字用来撑宽度'), exVar('a_very_long_variable_name_test')]),
        },
      ),
      LcBlock(op: 'fetch', args: {'url': exText('https://example.com/a/very/long/path/to/some/resource?with=query'), 'method': 'POST', 'into': 'a_very_long_variable_name_test'}),
    ];
    for (var i = 0; i < 6; i++) {
      inner = [
        LcBlock(op: 'if', args: {'cond': exBin('>', exVar('a_very_long_variable_name_test'), exNum(i))}, body: inner, orElse: i.isEven ? [say('否则 $i')] : []),
      ];
    }
    doc.logic.addHandler('click', target: button)!.body.addAll(inner);
    final rig = Rig(doc);
    await rig.pumpLogic(tester);
    expect(tester.takeException(), isNull);
    expect(validateLogic(rig.doc), isEmpty);

    final deepest = [for (var i = 0; i < 6; i++) lcStep(0), lcStep(0)];
    final block = rig.placed(0).layout.blockAt(deepest)!;
    expect(block.rect.width, greaterThan(200), reason: '嵌了 6 层以后积木还得有足够的宽度');
    expect(block.rect.width, lessThanOrEqualTo(const BkMetrics().maxBlockWidth), reason: '长句子换行，不会无限变宽');
    await rig.show(tester, 0, deepest);
    await tapAt(tester, rig.grip(0, deepest));
    expect(rig.s.selection!.path, hasLength(7));
    expect(k('bk-action-delete'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // 缩到最小：整串的宽度进得了 390 的屏幕。
    rig.s.setZoom(0.5, Offset.zero);
    await tester.pumpAndSettle();
    expect(rig.placed(0).layout.size.width * rig.s.zoom, lessThan(390));
    expect(rig.edits, 0);
    await shot(tester, 'bk2-logic-deep-light');
  });

  testWidgets('空逻辑时“看代码”给的是说明而不是空白', (tester) async {
    final rig = Rig(starter());
    await rig.pumpLogic(tester);
    await tapKey(tester, 'bk-code');
    expect(find.textContaining('还没有积木，所以这里是空的'), findsOneWidget);
  });

  testWidgets('旧文档（没有位置信息）打开：自动排开、不改文档；搭建页换了文档对象（撤销）以后画布跟着换', (tester) async {
    final doc = starter();
    doc.logic.addHandler('load')!.body.add(say('一'));
    doc.logic.addHandler('click', target: nodeIdOf(doc, 'button'))!.body.add(say('二'));
    final rig = Rig(LcDocument.parse(doc.encode()));
    final before = rig.doc.encode();
    await rig.pumpLogic(tester);
    expect(rig.handlers.every((h) => h.x == null && h.y == null), isTrue);
    final a = rig.placed(0), b = rig.placed(1);
    expect(a.bounds.overlaps(b.bounds), isFalse);
    // 平移、缩放、选中、看问题：都不改文档。
    await tester.dragFrom(const Offset(340, 300), const Offset(-60, -40));
    await tester.pumpAndSettle();
    await tapKey(tester, 'bk-zoom');
    await tapAt(tester, rig.grip(0, const []));
    expect(rig.doc.encode(), before);
    expect(rig.edits, 0);
    expect(rig.restores, 0);
  });

  // —— 截图（浅色 + 深色）——
  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    final suffix = mode == ThemeMode.light ? 'light' : 'dark';
    testWidgets('截图 · $suffix', (tester) async {
      final doc = starter();
      final button = nodeIdOf(doc, 'button');
      final input = nodeIdOf(doc, 'input');
      final title = nodeIdOf(doc, 'text');
      doc.logic.addVariable('count', type: 'number');
      doc.logic.addVariable('reply');
      doc.logic.addHandler('click', target: button)!.body.addAll([
        LcBlock(op: 'changeVar', args: {'name': 'count', 'by': exNum(1)}),
        LcBlock(
          op: 'if',
          args: {'cond': exBin('>', exVar('count'), exNum(3))},
          body: [
            LcBlock(
              op: 'setProp',
              args: {
                'node': title,
                'prop': 'text',
                'value': exJoin([exText('点了 '), exVar('count'), exText(' 次')]),
              },
            ),
          ],
          orElse: [say('再点几下')],
        ),
      ]);
      doc.logic.addHandler('input', target: input)!.body.add(LcBlock(op: 'setVar', args: {'name': 'reply', 'value': exEvent()}));
      final rig = Rig(doc);
      await rig.pumpLogic(tester, mode: mode);
      await shot(tester, 'bk2-logic-$suffix');
      await tapKey(tester, 'lc-top-vars');
      await shot(tester, 'bk2-logic-vars-$suffix');
      expect(tester.takeException(), isNull);
    });
  }
}
