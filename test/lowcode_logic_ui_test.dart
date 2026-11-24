// 积木逻辑编辑页的界面测试（390×844，浅色 + 深色）。
//   LOPI_SHOTS=1 flutter test --no-pub test/lowcode_logic_ui_test.dart   # 同时把截图写到 docs/screenshots/lc-logic-*.png
//
// 宿主模仿搭建页：手里一份文档，onEdit 每调一次算一条撤销记录；而且**每次都先换一份新对象再改**
// （搭建页撤销重做后就是这样），这样界面要是偷偷留着旧对象改，测试马上就能发现。
import 'dart:convert';

import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/lowcode/logic_block_widgets.dart';
import 'package:lopicode/lowcode/logic_blocks.dart';
import 'package:lopicode/lowcode/logic_edit.dart';
import 'package:lopicode/lowcode/logic_js.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:lopicode/lowcode/logic_screen.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/theme/app_theme.dart';
import 'package:material_ui/material_ui.dart';

import 'screens_test.dart' show fontsLoaded, shot;
import 'support/harness.dart';

class Host {
  Host(this.doc);
  LcDocument doc;

  /// 撤销记录条数。
  int edits = 0;

  void apply(void Function(LcDocument d) change) {
    final json = jsonDecode(jsonEncode(doc.toJson()));
    doc = LcDocument.fromJson(json is Map<String, dynamic> ? json : {});
    change(doc);
    edits++;
  }

  LcHandler get h1 => doc.logic.handlers.first;
  List<String> get ops => [for (final b in h1.body) b.op];
}

/// 起始页：标题、说明、卡片里一个输入框和一个“提交”按钮。
LcDocument starter() => LcDocument.starter('测试页');

String idOf(LcDocument doc, String type) {
  String? walk(LcNode n) {
    if (n.type == type) return n.id;
    for (final c in n.children) {
      final r = walk(c);
      if (r != null) return r;
    }
    return null;
  }

  return walk(doc.root)!;
}

LcBlock say(String words) => LcBlock(op: 'alert', args: {'message': exText(words)});

Future<Host> pumpLogic(WidgetTester tester, LcDocument doc, {String? initialNodeId, ThemeMode mode = ThemeMode.light}) async {
  usePhoneViewport(tester);
  final host = Host(doc);
  final nav = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    RepaintBoundary(
      key: shotKey,
      child: MaterialApp(
        navigatorKey: nav,
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(Brightness.light, fontFamily: kTestFont),
        darkTheme: buildAppTheme(Brightness.dark, fontFamily: kTestFont),
        themeMode: mode,
        home: const Scaffold(),
      ),
    ),
  );
  // 和搭建页一样用 push 打开（这样顶栏有返回按钮）。
  nav.currentState!.push(
    MaterialPageRoute<void>(
      builder: (_) => LogicScreen(doc: host.doc, onEdit: host.apply, initialNodeId: initialNodeId),
    ),
  );
  await tester.pumpAndSettle();
  return host;
}

Finder k(String key) => find.byKey(ValueKey(key));

Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> tapKey(WidgetTester tester, String key) => tap(tester, k(key));

/// 点积木的空白处（左上角往里一点：那里是句子开头的字，不是胶囊）。
Future<void> tapBlock(WidgetTester tester, String key) async {
  await tester.ensureVisible(k(key));
  await tester.pumpAndSettle();
  await tester.tapAt(tester.getTopLeft(k(key)) + const Offset(16, 20));
  await tester.pumpAndSettle();
}

/// 长按一块积木，拖到 [to]，松手。
Future<void> dragBlock(WidgetTester tester, String key, Offset to, {void Function()? whileHolding}) async {
  final from = tester.getTopLeft(k(key)) + const Offset(16, 20);
  final gesture = await tester.startGesture(from);
  await tester.pump(kLongPressTimeout + const Duration(milliseconds: 150));
  for (var i = 1; i <= 4; i++) {
    await gesture.moveTo(Offset.lerp(from, to, i / 4)!);
    await tester.pump(const Duration(milliseconds: 20));
  }
  whileHolding?.call();
  await gesture.up();
  await tester.pumpAndSettle();
}

Future<void> addBlock(WidgetTester tester, String slotKey, String category, String op) async {
  await tapKey(tester, slotKey);
  await tapKey(tester, 'lc-palette-cat-$category');
  await tapKey(tester, 'lc-palette-$op');
}

void main() {
  setUpAll(() async => fontsLoaded = await loadRealFonts());

  testWidgets('从空开始：加点击事件 → 加“变量加上” → 新建变量 count → 选它、数值改成 2', (tester) async {
    final host = await pumpLogic(tester, starter());
    final button = idOf(host.doc, 'button');
    expect(find.text('还没有任何逻辑'), findsOneWidget);

    await tapKey(tester, 'lc-add-event');
    await tapKey(tester, 'lc-event-click');
    await tapKey(tester, 'lc-node-$button');
    expect(host.edits, 1);
    expect(find.text('点击「按钮“提交”」时'), findsOneWidget);

    await addBlock(tester, 'lc-slot-h1--b', '变量', 'changeVar');
    expect(host.edits, 2);

    // 还没有变量：胶囊写着“选变量”，校验有一条错误。
    expect(find.text('选变量'), findsOneWidget);
    expect(logicErrors(host.doc), hasLength(1));
    await tapKey(tester, 'lc-arg-h1-0-name');
    await tapKey(tester, 'lc-var-new');
    await tester.enterText(k('lc-var-name'), 'count');
    await tapKey(tester, 'lc-var-type-number');
    await tap(tester, find.text('新建'));
    expect(host.edits, 3, reason: '新建变量 + 选上它是一次动作，一条撤销记录');

    await tapKey(tester, 'lc-arg-h1-0-by');
    await tester.enterText(k('lc-expr-num'), '2');
    await tapKey(tester, 'lc-expr-done');
    expect(host.edits, 4);

    expect(host.doc.logic.toJson(), {
      'variables': [
        {'name': 'count', 'type': 'number', 'initial': 0},
      ],
      'handlers': [
        {
          'id': 'h1',
          'event': 'click',
          'target': button,
          'body': [
            {
              'op': 'changeVar',
              'args': {'name': 'count', 'by': exNum(2)},
            },
          ],
        },
      ],
    });
    expect(validateLogic(host.doc), isEmpty);
    expect(exportLogicJs(host.doc), contains('state.count'));
    expect(find.byKey(const ValueKey('lc-top-issues')), findsNothing);

    // 看代码面板里是翻出来的脚本。
    await tapKey(tester, 'lc-top-code');
    expect(find.textContaining('state.count'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('“如果”积木：那么 / 否则两个子栈各加一块；取消编辑不产生撤销记录', (tester) async {
    final doc = starter()..logic.addHandler('load');
    final host = await pumpLogic(tester, doc);
    await addBlock(tester, 'lc-slot-h1--b', '流程', 'if');
    expect(find.text('如果'), findsOneWidget);
    expect(find.text('否则'), findsOneWidget);
    await addBlock(tester, 'lc-slot-h1-0-b', '交互', 'alert');
    await addBlock(tester, 'lc-slot-h1-0-e', '交互', 'log');
    expect(host.edits, 3);
    final block = host.h1.body.single;
    expect(block.op, 'if');
    expect([for (final b in block.body) b.op], ['alert']);
    expect([for (final b in block.orElse) b.op], ['log']);

    // 打开条件的编辑面板，换了种类再点取消：什么都不改。
    await tapKey(tester, 'lc-arg-h1-0-cond');
    await tapKey(tester, 'lc-expr-kind-not');
    await tapKey(tester, 'lc-expr-cancel');
    expect(host.edits, 3);
    expect(block.args['cond'], exBool(true));

    // 空面板直接关（点遮罩）也不改。
    await tapKey(tester, 'lc-append-h1');
    await tester.tapAt(const Offset(195, 40));
    await tester.pumpAndSettle();
    expect(host.edits, 3);
  });

  testWidgets('表达式嵌套编辑：count > 10 并且 输入框的内容 等于 "ok"', (tester) async {
    final doc = starter();
    final input = idOf(doc, 'input');
    doc.logic.addVariable('count', type: 'number');
    doc.logic.addHandler('input', target: input)!.insertBlock(const [], newBlock('if', doc));
    final host = await pumpLogic(tester, doc);

    await tapKey(tester, 'lc-arg-h1-0-cond');
    // 要的是“是否”：直接填里“是 / 否”排第一，“输入的内容”在 input 处理里可选。
    expect(tester.getTopLeft(k('lc-expr-kind-bool')).dx, lessThan(tester.getTopLeft(k('lc-expr-kind-text')).dx));
    expect(k('lc-expr-kind-event'), findsOneWidget);
    await tapKey(tester, 'lc-expr-kind-bin');
    await tapKey(tester, 'lc-expr-op-and');

    await tapKey(tester, 'lc-expr-l'); // 值 › 左边
    await tapKey(tester, 'lc-expr-kind-bin');
    await tapKey(tester, 'lc-expr-op->');
    await tapKey(tester, 'lc-expr-l'); // 值 › 左边 › 左边
    expect(k('lc-expr-crumb-2'), findsOneWidget);
    await tapKey(tester, 'lc-expr-kind-var');
    await tapKey(tester, 'lc-expr-var-count');
    await tapKey(tester, 'lc-expr-up');
    await tapKey(tester, 'lc-expr-r');
    await tester.enterText(k('lc-expr-num'), '10');
    await tester.pumpAndSettle();
    await tapKey(tester, 'lc-expr-crumb-0'); // 面包屑直接回最外层

    await tapKey(tester, 'lc-expr-r'); // 值 › 右边
    await tapKey(tester, 'lc-expr-kind-bin');
    await tapKey(tester, 'lc-expr-op-==');
    await tapKey(tester, 'lc-expr-l');
    await tapKey(tester, 'lc-expr-kind-prop');
    await tapKey(tester, 'lc-expr-up');
    await tapKey(tester, 'lc-expr-r');
    await tapKey(tester, 'lc-expr-kind-text');
    await tester.enterText(k('lc-expr-text'), 'ok');
    await tester.pumpAndSettle();
    await tapKey(tester, 'lc-expr-up');
    await tapKey(tester, 'lc-expr-up');
    expect(tester.widget<Text>(k('lc-expr-reading')).data, '（count > 10） 并且 （「输入框“请输入”」的输入内容 = “ok”）');
    expect(host.edits, 0, reason: '点“完成”之前不提交');
    await tapKey(tester, 'lc-expr-done');

    expect(host.edits, 1);
    expect(host.h1.body.single.args['cond'], exBin('and', exBin('>', exVar('count'), exNum(10)), exBin('==', exProp(input, 'value'), exText('ok'))));
    expect(validateLogic(host.doc), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('拼成文字：加一项、去一项；数字填错不能完成', (tester) async {
    final doc = starter()..logic.addHandler('load')!.insertBlock(const [], say('你好'));
    final host = await pumpLogic(tester, doc);
    await tapKey(tester, 'lc-arg-h1-0-message');
    await tapKey(tester, 'lc-expr-kind-join');
    await tapKey(tester, 'lc-expr-item-add');
    await tapKey(tester, 'lc-expr-item-del-1');
    await tapKey(tester, 'lc-expr-item-1');
    await tapKey(tester, 'lc-expr-kind-num');
    await tester.enterText(k('lc-expr-num'), '3x');
    await tester.pumpAndSettle();
    expect(find.text('这里要填一个数字'), findsOneWidget);
    await tester.enterText(k('lc-expr-num'), '3.5');
    await tester.pumpAndSettle();
    await tapKey(tester, 'lc-expr-up');
    await tapKey(tester, 'lc-expr-done');
    expect(host.h1.body.single.args['message'], exJoin([exText('你好'), exNum(3.5)]));
    expect(host.edits, 1);
  });

  testWidgets('选中积木：上移 / 下移 / 复制 / 删除；带子积木的删除要确认', (tester) async {
    final doc = starter();
    final h = doc.logic.addHandler('load')!;
    h.insertBlock(const [], say('甲'));
    h.insertBlock(const [], say('乙'));
    h.insertBlock(const [], LcBlock(op: 'repeat', args: {'times': exNum(3)}, body: [say('丙')]));
    final host = await pumpLogic(tester, doc);
    List<String> words() => [for (final b in host.h1.body) b.op == 'alert' ? '${exprString(b.args['message'], 'v')}' : b.op];

    expect(find.byType(LcActionRow), findsNothing);
    await tapBlock(tester, 'lc-block-h1-0');
    expect(find.byType(LcActionRow), findsOneWidget);
    // 第一块不能再上移。
    expect(tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.arrow_upward_rounded)).onPressed, isNull);

    await tap(tester, find.byTooltip('下移'));
    expect(words(), ['乙', '甲', 'repeat']);
    // 选中跟着积木走：再点上移回到原位。
    await tap(tester, find.byTooltip('上移'));
    expect(words(), ['甲', '乙', 'repeat']);
    await tap(tester, find.byTooltip('复制'));
    expect(words(), ['甲', '甲', '乙', 'repeat']);
    await tap(tester, find.byTooltip('删除'));
    expect(words(), ['甲', '乙', 'repeat']);
    expect(find.byType(LcActionRow), findsNothing);
    expect(host.edits, 4);

    // 同一时间只有一块被选中。
    await tapBlock(tester, 'lc-block-h1-0');
    await tapBlock(tester, 'lc-block-h1-1');
    expect(find.byType(LcActionRow), findsOneWidget);

    // “重复”里面有积木：删除先问一句，取消就不删。
    await tapBlock(tester, 'lc-block-h1-2');
    await tap(tester, find.byTooltip('删除'));
    expect(find.text('删除这块积木？'), findsOneWidget);
    await tap(tester, find.text('取消'));
    expect(words(), ['甲', '乙', 'repeat']);
    await tap(tester, find.byTooltip('删除'));
    await tap(tester, find.widgetWithText(TextButton, '删除'));
    expect(words(), ['甲', '乙']);
    expect(host.edits, 5);

    // 在下面加一块：加在选中那块的正下方。
    await tapBlock(tester, 'lc-block-h1-0');
    await tap(tester, find.byTooltip('在下面加一块'));
    await tapKey(tester, 'lc-palette-cat-交互');
    await tapKey(tester, 'lc-palette-log');
    expect(host.ops, ['alert', 'log', 'alert']);
    expect(host.edits, 6);
    expect(tester.takeException(), isNull);
  });

  testWidgets('长按拖动重排：同一串里换位置、拖进子栈、不能拖进自己里面', (tester) async {
    final doc = starter();
    final h = doc.logic.addHandler('load')!;
    h.insertBlock(const [], say('甲'));
    h.insertBlock(const [], say('乙'));
    h.insertBlock(const [], LcBlock(op: 'repeat', args: {'times': exNum(3)}));
    final host = await pumpLogic(tester, doc);
    List<String> words(List<LcBlock> list) => [for (final b in list) b.op == 'alert' ? '${exprString(b.args['message'], 'v')}' : b.op];

    // 甲拖到乙的下半截：插在乙后面。拖着的时候有一条插入位横条。
    var bars = 0;
    await dragBlock(tester, 'lc-block-h1-0', tester.getCenter(k('lc-block-h1-1')) + const Offset(0, 12), whileHolding: () => bars = find.byType(LcDropBar).evaluate().length);
    expect(bars, 1);
    expect(words(host.h1.body), ['乙', '甲', 'repeat']);
    expect(host.edits, 1);
    expect(find.byType(LcDropBar), findsNothing);

    // 甲拖进“重复”的空子栈。
    await dragBlock(tester, 'lc-block-h1-1', tester.getCenter(k('lc-slot-h1-2-b')));
    expect(words(host.h1.body), ['乙', 'repeat']);
    expect(words(host.h1.body[1].body), ['甲']);
    expect(host.edits, 2);

    // “重复”拖到自己子栈里的那块上：不接，什么都不变。
    await dragBlock(tester, 'lc-block-h1-1', tester.getCenter(k('lc-block-h1-1.b0')));
    expect(words(host.h1.body), ['乙', 'repeat']);
    expect(host.edits, 2);

    // 子栈里的甲拖回最上面（乙的上半截）。
    await dragBlock(tester, 'lc-block-h1-1.b0', tester.getCenter(k('lc-block-h1-0')) - const Offset(0, 12));
    expect(words(host.h1.body), ['甲', '乙', 'repeat']);
    expect(host.h1.body[2].body, isEmpty);
    expect(host.edits, 3);

    // 原地放下（拖到自己身上）：不算改动。
    await dragBlock(tester, 'lc-block-h1-1', tester.getCenter(k('lc-block-h1-1')) + const Offset(0, 8));
    expect(host.edits, 3);
    expect(tester.takeException(), isNull);
  });

  testWidgets('拖动时手指停在底部边缘：列表自己往下滚，可以放到原来在屏幕外的位置', (tester) async {
    final doc = starter();
    final h = doc.logic.addHandler('load')!;
    for (var i = 0; i < 24; i++) {
      h.insertBlock(const [], say('第 $i 块'));
    }
    final host = await pumpLogic(tester, doc);
    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable).first);
    expect(scrollable.position.pixels, 0);
    final first = host.h1.body.first.toJson();

    final from = tester.getTopLeft(k('lc-block-h1-0')) + const Offset(16, 20);
    final gesture = await tester.startGesture(from);
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 150));
    await gesture.moveTo(const Offset(120, 400));
    await tester.pump(const Duration(milliseconds: 20));
    await gesture.moveTo(const Offset(120, 740)); // 贴着底部按钮上方
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(scrollable.position.pixels, greaterThan(300), reason: '手指不动也要继续滚');
    // 回到中间：不再滚；放下。
    await gesture.moveTo(const Offset(120, 420));
    await tester.pump(const Duration(milliseconds: 20));
    final stopped = scrollable.position.pixels;
    await tester.pump(const Duration(milliseconds: 200));
    expect(scrollable.position.pixels, stopped);
    await gesture.moveTo(const Offset(120, 424));
    await tester.pump(const Duration(milliseconds: 20));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(host.edits, 1);
    final index = host.h1.body.indexWhere((b) => jsonEncode(b.toJson()) == jsonEncode(first));
    expect(index, greaterThan(6), reason: '放到了原来在屏幕外的位置');
    expect(tester.takeException(), isNull);
  });

  testWidgets('键盘弹出时：编辑值的面板整体上移，输入框和按钮不被挡住', (tester) async {
    final doc = starter()..logic.addHandler('load')!.insertBlock(const [], say('你好'));
    await pumpLogic(tester, doc);
    await tapKey(tester, 'lc-arg-h1-0-message');
    // 先点进输入框（拿到焦点），键盘才弹出来。
    await tapKey(tester, 'lc-expr-text');
    tester.view.viewInsets = const FakeViewPadding(bottom: 320 * 2);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    await tester.enterText(k('lc-expr-text'), '很长的一段话' * 20);
    await tester.pumpAndSettle();
    expect(tester.getRect(k('lc-expr-text')).bottom, lessThanOrEqualTo(844 - 320));
    expect(tester.getRect(k('lc-expr-done')).bottom, lessThanOrEqualTo(844 - 320));
    expect(tester.takeException(), isNull);
  });

  testWidgets('变量：改名同步引用；删除在用的变量要确认；重名和不合规矩的名字就地提示', (tester) async {
    final doc = starter();
    doc.logic.addVariable('count', type: 'number');
    doc.logic.addVariable('name');
    final h = doc.logic.addHandler('load')!;
    h.insertBlock(const [], LcBlock(op: 'changeVar', args: {'name': 'count', 'by': exNum(1)}));
    h.insertBlock(const [], LcBlock(op: 'alert', args: {'message': exVar('count')}));
    final host = await pumpLogic(tester, doc);

    await tapKey(tester, 'lc-top-vars');
    expect(find.text('数字 · 初始值 0 · 2 处在用'), findsOneWidget);
    await tapKey(tester, 'lc-vars-row-count');
    await tester.enterText(k('lc-var-name'), 'name');
    await tap(tester, find.text('保存'));
    expect(find.text('已经有一个变量叫 name 了'), findsOneWidget);
    await tester.enterText(k('lc-var-name'), '1abc');
    await tap(tester, find.text('保存'));
    expect(find.textContaining('不能用数字开头'), findsOneWidget);
    expect(host.edits, 0);

    await tester.enterText(k('lc-var-name'), 'total');
    await tester.enterText(k('lc-var-initial'), '5');
    await tap(tester, find.text('保存'));
    expect(host.edits, 1, reason: '改名 + 改初始值一次保存，一条撤销记录');
    expect(host.doc.logic.variable('count'), isNull);
    expect(host.doc.logic.variable('total')!.initial, 5);
    expect(host.h1.body[0].args['name'], 'total');
    expect(host.h1.body[1].args['message'], exVar('total'));
    expect(find.text('数字 · 初始值 5 · 2 处在用'), findsOneWidget);

    // 改类型：数字 → 是 / 否。
    await tapKey(tester, 'lc-vars-row-name');
    await tapKey(tester, 'lc-var-type-bool');
    await tapKey(tester, 'lc-var-flag');
    await tap(tester, find.text('保存'));
    expect(host.doc.logic.variable('name')!.type, 'bool');
    expect(host.doc.logic.variable('name')!.initial, true);
    expect(host.edits, 2);

    // 删除在用的变量：先说有几处在用。
    await tapKey(tester, 'lc-vars-row-total');
    await tap(tester, find.widgetWithText(TextButton, '删除'));
    expect(find.textContaining('有 2 处在用它'), findsOneWidget);
    await tap(tester, find.widgetWithText(TextButton, '删除'));
    expect(host.doc.logic.variable('total'), isNull);
    expect(host.edits, 3);

    // 关掉面板：用到它的两块积木被标了问题，顶栏出现警示。
    await tester.tapAt(const Offset(195, 40));
    await tester.pumpAndSettle();
    expect(k('lc-top-issues'), findsOneWidget);
    expect(k('lc-issue-h1-0'), findsOneWidget);
    expect(k('lc-issue-h1-1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('校验问题：警示按钮带数量，点开是人话，点一条跳过去并选中那块积木', (tester) async {
    final doc = starter();
    for (var i = 0; i < 6; i++) {
      doc.logic.addHandler('load')!.insertBlock(const [], say('第 $i 个'));
    }
    // 最后一个处理里：第 2 块的“否则”里引用了没声明的变量。
    final last = doc.logic.handlers.last;
    last.insertBlock(
      const [],
      LcBlock(
        op: 'if',
        args: {'cond': exBool(true)},
        orElse: [
          LcBlock(op: 'changeVar', args: {'name': 'ghost', 'by': exNum(1)}),
        ],
      ),
    );
    final host = await pumpLogic(tester, doc);

    expect(find.descendant(of: k('lc-top-issues'), matching: find.text('1')), findsOneWidget);
    await tapKey(tester, 'lc-top-issues');
    expect(find.text('变量 ghost 还没有声明（先到“变量”里加一个）'), findsOneWidget);
    expect(find.textContaining('第 2 块 › 否则 › 第 1 块'), findsOneWidget);
    await tapKey(tester, 'lc-issue-row-0');

    // 跳到了最后一张卡片（原来在屏幕外面），那块积木被选中、露在屏幕里。
    final block = k('lc-block-h6-1.e0');
    expect(block, findsOneWidget);
    expect(find.byType(LcActionRow), findsOneWidget);
    expect(tester.getRect(block).top, greaterThan(64));
    expect(tester.getRect(block).bottom, lessThan(844 - 60));

    // 点积木上的标记也能看到问题。
    await tapKey(tester, 'lc-issue-h6-1.e0');
    expect(find.text('这块积木的问题'), findsOneWidget);
    expect(host.edits, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('从某个控件点进来：只看它的事件，添加事件默认挂在它上面，标签可以关掉', (tester) async {
    final doc = starter();
    final button = idOf(doc, 'button');
    final input = idOf(doc, 'input');
    doc.logic.addHandler('click', target: button);
    doc.logic.addHandler('load');
    doc.logic.addHandler('input', target: input);
    final host = await pumpLogic(tester, doc, initialNodeId: button);

    expect(find.text('只看：按钮“提交”'), findsOneWidget);
    expect(k('lc-card-h1'), findsOneWidget);
    expect(k('lc-card-h2'), findsNothing);
    expect(k('lc-card-h3'), findsNothing);

    // 点击事件：不再问挂在哪个控件上。
    await tapKey(tester, 'lc-add-event');
    expect(find.text('挂在「按钮“提交”」上'), findsOneWidget);
    await tapKey(tester, 'lc-event-click');
    expect(host.edits, 1);
    expect(host.doc.logic.handlers.last.target, button);
    expect(k('lc-card-h4'), findsOneWidget);

    // 输入变化：按钮不是输入框，还是要选；只有输入框能点。
    await tapKey(tester, 'lc-add-event');
    await tapKey(tester, 'lc-event-input');
    await tester.tap(k('lc-node-$button'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(host.edits, 1);
    await tapKey(tester, 'lc-node-$input');
    expect(host.doc.logic.handlers.last.event, 'input');
    expect(host.doc.logic.handlers.last.target, input);
    // 新加的不在筛选范围里：自动退出筛选，免得加完看不见。
    expect(k('lc-filter'), findsNothing);
    expect(k('lc-card-h5'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('筛选标签点叉：回到看全部', (tester) async {
    final doc = starter();
    doc.logic.addHandler('click', target: idOf(doc, 'button'));
    doc.logic.addHandler('load');
    await pumpLogic(tester, doc, initialNodeId: idOf(doc, 'button'));
    expect(k('lc-card-h2'), findsNothing);
    await tap(tester, find.descendant(of: k('lc-filter'), matching: find.byTooltip('看全部事件')));
    expect(k('lc-filter'), findsNothing);
    expect(k('lc-card-h2'), findsOneWidget);
  });

  testWidgets('目标控件不存在的处理：卡片不崩，可以改目标或删除', (tester) async {
    final doc = starter();
    final button = idOf(doc, 'button');
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
    final host = await pumpLogic(tester, doc);

    expect(tester.takeException(), isNull);
    expect(find.text('点击「已删除的控件」时'), findsOneWidget);
    expect(find.text('目标控件已不存在，这个事件不会被触发。'), findsOneWidget);
    expect(find.text('还没选是哪个控件触发的，这个事件不会被触发。'), findsOneWidget);
    // 不认识的积木：灰色、说明是什么，选中后可以删。
    expect(find.text('不认识的积木（mystery） · 里面还有 1 块'), findsOneWidget);

    await tapKey(tester, 'lc-lost-retarget-h1');
    await tapKey(tester, 'lc-node-$button');
    expect(host.doc.logic.handler('h1')!.target, button);
    expect(k('lc-lost-h1'), findsNothing);
    expect(host.edits, 1);

    // 帽子上的“更多”：改目标控件；删除先问、取消就不删。
    await tapKey(tester, 'lc-hat-menu-h1');
    await tap(tester, find.text('改目标控件'));
    await tapKey(tester, 'lc-node-${idOf(doc, 'card')}');
    expect(host.doc.logic.handler('h1')!.target, idOf(doc, 'card'));
    await tapKey(tester, 'lc-hat-menu-h1');
    await tap(tester, find.text('删除这个事件'));
    await tap(tester, find.widgetWithText(TextButton, '取消').last);
    expect(host.doc.logic.handler('h1'), isNotNull);
    expect(host.edits, 2);

    // 删除处理要确认。
    await tapKey(tester, 'lc-lost-delete-h2');
    expect(find.text('删除这个事件？'), findsOneWidget);
    await tap(tester, find.widgetWithText(TextButton, '删除').last);
    expect(host.doc.logic.handler('h2'), isNull);
    expect(host.edits, 3);
    expect(tester.takeException(), isNull);
  });

  testWidgets('改控件积木：换控件、换属性时值跟着换成对得上的', (tester) async {
    final doc = starter();
    final input = idOf(doc, 'input');
    doc.logic.addHandler('load')!.insertBlock(const [], newBlock('setProp', doc));
    final host = await pumpLogic(tester, doc);
    expect(host.h1.body.single.args['prop'], 'text');

    // 换成输入框：它没有“文字”可改，自动换成它有的第一个属性。
    await tapKey(tester, 'lc-arg-h1-0-node');
    await tapKey(tester, 'lc-node-$input');
    expect(host.h1.body.single.args['node'], input);
    expect(host.h1.body.single.args['prop'], 'value');

    // 属性换成“是否显示”：值换成“是”；可选的只有输入框有的属性。
    await tapKey(tester, 'lc-arg-h1-0-prop');
    expect(k('lc-choice-text'), findsNothing);
    expect(k('lc-choice-src'), findsNothing);
    await tapKey(tester, 'lc-choice-visible');
    expect(host.h1.body.single.args['value'], exBool(true));
    expect(find.textContaining('显示'), findsWidgets);
    expect(host.edits, 2);
    expect(validateLogic(host.doc), isEmpty);
  });

  testWidgets('很深的嵌套（6 层如果 + 长文字）在 390 宽下不溢出', (tester) async {
    final doc = starter();
    final button = idOf(doc, 'button');
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
    final host = await pumpLogic(tester, doc);
    expect(tester.takeException(), isNull);
    expect(validateLogic(host.doc), isEmpty);

    // 最里面那块：选中后操作行也放得下。
    const deepest = 'lc-block-h1-0.b0.b0.b0.b0.b0.b0';
    await tapBlock(tester, deepest);
    expect(find.byType(LcActionRow), findsOneWidget);
    expect(tester.takeException(), isNull);
    final rect = tester.getRect(k(deepest));
    expect(rect.right, lessThanOrEqualTo(390));
    expect(rect.width, greaterThan(250), reason: '嵌了 6 层以后积木还得有足够的宽度');
    await shot(tester, 'lc-logic-deep-light');
  });

  testWidgets('空逻辑时“看代码”给的是说明而不是空白', (tester) async {
    await pumpLogic(tester, starter());
    await tapKey(tester, 'lc-top-code');
    expect(find.textContaining('还没有任何变量和事件'), findsOneWidget);
  });

  // —— 截图（浅色 + 深色）——
  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    final suffix = mode == ThemeMode.light ? 'light' : 'dark';

    LcDocument full() {
      final doc = starter();
      final button = idOf(doc, 'button');
      final input = idOf(doc, 'input');
      final title = idOf(doc, 'text');
      doc.logic.addVariable('count', type: 'number');
      doc.logic.addVariable('reply');
      doc.logic.addHandler('click', target: button)!.body.addAll([
        LcBlock(op: 'changeVar', args: {'name': 'count', 'by': exNum(1)}),
        LcBlock(
          op: 'if',
          args: {'cond': exBin('and', exBin('>', exVar('count'), exNum(10)), exBin('==', exProp(input, 'value'), exText('ok')))},
          body: [
            LcBlock(
              op: 'repeat',
              args: {'times': exNum(3)},
              body: [
                LcBlock(op: 'log', args: {'value': exVar('count')}),
              ],
            ),
            LcBlock(
              op: 'setProp',
              args: {
                'node': title,
                'prop': 'text',
                'value': exJoin([exText('点了 '), exVar('count'), exText(' 次')]),
              },
            ),
          ],
          orElse: [
            LcBlock(
              op: 'fetch',
              args: {'url': exText('https://example.com/api'), 'method': 'GET', 'into': 'reply'},
              body: [
                LcBlock(op: 'setProp', args: {'node': title, 'prop': 'text', 'value': exVar('reply')}),
              ],
              orElse: [say('网络不通')],
            ),
          ],
        ),
        LcBlock(
          op: 'wait',
          args: {'ms': exNum(1000)},
          body: [
            LcBlock(op: 'setProp', args: {'node': button, 'prop': 'visible', 'value': exBool(false)}),
          ],
        ),
      ]);
      doc.logic.addHandler('load')!.body.add(LcBlock(op: 'setVar', args: {'name': 'count', 'value': exNum(0)}));
      return doc;
    }

    testWidgets('截图 · $suffix', (tester) async {
      await pumpLogic(tester, starter(), mode: mode);
      await shot(tester, 'lc-logic-empty-$suffix');

      final host = await pumpLogic(tester, full(), mode: mode);
      expect(validateLogic(host.doc), isEmpty);
      await shot(tester, 'lc-logic-full-$suffix');

      await tapBlock(tester, 'lc-block-h1-1.b0');
      await shot(tester, 'lc-logic-selected-$suffix');

      await tap(tester, find.byTooltip('在下面加一块'));
      await tapKey(tester, 'lc-palette-cat-流程');
      await shot(tester, 'lc-logic-palette-$suffix');
      await tester.tapAt(const Offset(195, 40));
      await tester.pumpAndSettle();

      await tapKey(tester, 'lc-arg-h1-1-cond');
      await shot(tester, 'lc-logic-expr-$suffix');
      await tapKey(tester, 'lc-expr-r');
      await tapKey(tester, 'lc-expr-l');
      await shot(tester, 'lc-logic-expr-nested-$suffix');
      await tapKey(tester, 'lc-expr-crumb-0');
      await tapKey(tester, 'lc-expr-cancel');

      await tapKey(tester, 'lc-top-vars');
      await shot(tester, 'lc-logic-vars-$suffix');
      await tapKey(tester, 'lc-vars-row-count');
      await shot(tester, 'lc-logic-var-edit-$suffix');
      await tap(tester, find.text('取消'));
      await tester.tapAt(const Offset(195, 40));
      await tester.pumpAndSettle();

      await tapKey(tester, 'lc-top-code');
      await shot(tester, 'lc-logic-code-$suffix');
      await tester.tapAt(const Offset(195, 20));
      await tester.pumpAndSettle();

      await tapKey(tester, 'lc-add-event');
      await tapKey(tester, 'lc-event-input');
      await shot(tester, 'lc-logic-add-event-$suffix');
      expect(host.edits, 0);

      // 问题列表：删掉一个在用的变量、把目标控件弄丢。
      final broken = full();
      broken.logic.removeVariable('reply');
      broken.logic.handlers.last.event = 'click';
      broken.logic.handlers.last.target = 'gone';
      broken.logic.handlers.first.body.insert(0, LcBlock(op: 'mystery'));
      await pumpLogic(tester, broken, mode: mode);
      await shot(tester, 'lc-logic-broken-$suffix');
      await tapKey(tester, 'lc-top-issues');
      await shot(tester, 'lc-logic-issues-$suffix');
    });
  }
}
