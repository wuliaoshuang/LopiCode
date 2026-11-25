// 积木第 4 版·第 2 阶段：在真的后端积木页里用函数和“我的积木”（390×844）。
//
// 整个应用外壳真的搭起来（同 backend_screen_test.dart）：在“我的积木”页签新建一块 → 拖出来用 → 往定义里放“返回”、把参数小块拖进去
// → 改参数（各处调用跟着变，丢了内容要说）→ 删除先说有几处在用；长按一块“包成积木”；匿名函数的口里拖进拖出；撤销重做。
// 存盘和生成的代码都是真实文件。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/blocks/block_dock.dart';
import 'package:lopicode/blocks/block_geometry.dart';
import 'package:lopicode/blocks/block_palette_model.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/lowcode/logic_expr.dart';
import 'package:lopicode/lowcode/logic_model.dart';

import 'backend_lang_ui_test.dart' show dropStatement, dropValue, rules;
import 'backend_screen_test.dart' show at, be, boot, doc, ed, flushed, k, liftFromPalette, paletteTab, text, until;
import 'blocks_custom_ui_test.dart' show longPress, press, type;
import 'screens_test.dart' show fontsLoaded;
import 'support/backend_func_blocks.dart';
import 'support/backend_lang_blocks.dart' hide text;
import 'support/harness.dart';

/// 打开之前往样本项目里加几个接口 / 几块自定义积木。
void Function() seed({List<J> routes = const [], List<J> functions = const []}) => () {
  final json = jsonDecode(text(kBackendFileName)) as Map<String, dynamic>;
  (json['routes'] as List).addAll(routes);
  if (functions.isNotEmpty) json['functions'] = functions;
  at(kBackendFileName).writeAsStringSync(jsonEncode(json));
};

/// 屏幕上：某一串里某块积木头上的把手。
Offset grip(WidgetTester tester, String id, LcBlockPath path) {
  final s = ed(tester);
  final placed = s.layout.placed(id)!;
  return s.globalOf(s.toView(placed.origin + placed.layout.blockAt(path)!.head.centerLeft + const Offset(7, 0)));
}

/// 屏幕上：帽子（`owner == null`）或某块积木上的第几个参数小块。
Offset chip(WidgetTester tester, String id, int index, {LcBlockPath? owner}) {
  final s = ed(tester);
  final placed = s.layout.placed(id)!;
  final chips = [
    for (final (b, x) in placed.layout.allSlots)
      if (x.look == BkSlotLook.param && x.param != null && (owner == null ? b.isHat : (!b.isHat && bkSameBlockPath(b.path, owner)))) x,
  ];
  return s.globalOf(s.toView(placed.origin + chips[index].rect.center));
}

/// 把某一串挪到屏幕上看得见的地方（帽子在顶栏下面一点）。
Future<void> show(WidgetTester tester, String id) async {
  final s = ed(tester);
  final origin = s.layout.placed(id)!.origin;
  s.setPan(Offset(16 - origin.dx * s.zoom, 12 - origin.dy * s.zoom));
  // ignore: invalid_use_of_protected_member 测试里摆好画布位置，只为重画一下
  s.setState(() {});
  await tester.pumpAndSettle();
}

/// 长按一块积木、没挪就松手（弹出这块积木的菜单）。
Future<void> holdBlock(WidgetTester tester, String id, LcBlockPath path) async {
  final g = await tester.startGesture(grip(tester, id, path));
  await tester.pump(const Duration(milliseconds: 300));
  await g.up();
  await tester.pumpAndSettle();
}

Future<TestGesture> pick(WidgetTester tester, Offset from) async {
  final g = await tester.startGesture(from);
  await tester.pump(const Duration(milliseconds: 300));
  expect(ed(tester).drag, isNotNull, reason: '长按应该已经拿起来了');
  return g;
}

void main() {
  setUpAll(() async => fontsLoaded = await loadRealFonts());
  tearDown(BkDockMemory.clear);

  testWidgets('新建积木 → 出现在“我的积木”页签 → 往定义里放“返回”、参数小块拖进去 → 拖出调用放进接口 → 存盘是版本 3、代码里函数在接口前、看代码看得到', (tester) async {
    await boot(
      tester,
      ProjectTemplate.backendBlocks,
      language: 'node',
      before: seed(
        routes: [
          route('use', 'GET', '/use', [json(tx('占位'))]),
        ],
      ),
    );
    final host = be(tester).host!;
    final start = host.doc.encode();
    await paletteTab(tester, bkCustomCategoryId);
    expect(k('bk-palette-custom-empty'), findsOneWidget);
    await tester.tap(k('bk-palette-custom-new'));
    await tester.pumpAndSettle();
    expect(k('bk-look-form'), findsOneWidget);
    await type(tester, 'bk-look-name', '加倍');
    await press(tester, 'bk-look-param-add');
    await type(tester, 'bk-look-param-name-0', '数');
    await press(tester, 'bk-look-done');
    expect(k('bk-look-form'), findsNothing);

    // 文档里多了一个函数、画布上多了一串定义、“我的积木”页签里多了一块。
    final f = doc(tester).functions.single;
    expect((f.id, f.name, f.paramNames.join(',')), ('f1', '加倍', '数'));
    expect(ed(tester).layout.placed('f1'), isNotNull);
    expect(k('bk-palette-custom-empty'), findsNothing);
    expect(k('bk-palette-item-block-call:f1'), findsOneWidget, reason: '定义里还没有“返回”：是一块语句');
    expect(rules(tester), contains('L14'), reason: '还没人用：黄色提醒');
    expect(be(tester).host!.issues.where((i) => i.isError), isEmpty);

    // 往定义里放“返回 (值)”；帽子上的参数小块“数”拖进去。
    await show(tester, 'f1');
    var (g, from) = await liftFromPalette(tester, '函数', 'block-return');
    await dropStatement(tester, g, from, 'f1', const [], 0);
    expect([for (final b in doc(tester).function('f1')!.body) b.op], ['return']);
    final c = chip(tester, 'f1', 0);
    g = await pick(tester, c);
    await dropValue(tester, g, c, 'f1', [lcStep(0)], 'value');
    expect(doc(tester).function('f1')!.body.single.args['value'], {'e': 'param', 'name': '数'});

    // 有“返回”了：积木盒里它变成一个值（胶囊），拖进接口“返回响应”的数据槽。
    await paletteTab(tester, bkCustomCategoryId);
    expect(k('bk-palette-item-expr-call:f1'), findsOneWidget);
    expect(k('bk-palette-item-block-call:f1'), findsNothing);
    await show(tester, 'use');
    (g, from) = await liftFromPalette(tester, bkCustomCategoryId, 'expr-call:f1');
    await dropValue(tester, g, from, 'use', [lcStep(0)], 'value');
    final call = doc(tester).route('use')!.body.single.args['value'] as Map;
    expect((call['e'], (call['数'] as Map)['e']), ('call:f1', 'text'));
    expect(be(tester).host!.issues.where((i) => i.scriptId == 'f1' || i.scriptId == 'use'), isEmpty, reason: '用上了：提醒也没了');

    // 存盘：版本 3；代码里函数排在接口前面；看代码就是这一份。
    await flushed(tester);
    await until(tester, () => text('server.js').contains('f_'), '函数进了代码');
    final saved = jsonDecode(text(kBackendFileName)) as Map<String, dynamic>;
    expect(saved['version'], 3);
    expect(((saved['functions'] as List).single as Map)['id'], 'f1');
    final code = text('server.js');
    expect(code.indexOf('f_'), lessThan(code.indexOf('/hello')));
    await tester.tap(k('bk-code'));
    await tester.pumpAndSettle();
    expect(be(tester).host!.codeText, code);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    // 撤销到底回到一开始（函数没了、文件回到版本 1），再重做回来。
    final end = host.doc.encode();
    var steps = 0;
    while (host.canUndo) {
      host.undo();
      steps++;
    }
    await tester.pumpAndSettle();
    expect(steps, 4, reason: '新建、放返回、放参数、放调用：一步一条');
    expect(host.doc.encode(), start);
    expect(ed(tester).layout.placed('f1'), isNull);
    for (var i = 0; i < steps; i++) {
      host.redo();
    }
    await tester.pumpAndSettle();
    expect(host.doc.encode(), end);
    expect(ed(tester).layout.placed('f1'), isNotNull);
    await flushed(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('改参数联动：在“编辑积木”里删掉一个参数 → 先问有几处在用 → 各处调用少一格，丢了内容有提示；删除积木先说有几处在用，调用一起拿掉', (tester) async {
    await boot(
      tester,
      ProjectTemplate.backendBlocks,
      language: 'node',
      before: seed(
        routes: [
          route('use', 'GET', '/use', [
            callS('f1', {'话': tx('你好'), '次数': nm(3)}),
            json(tx('好')),
          ]),
        ],
        functions: [
          fnDef(
            'f1',
            '记一笔',
            [par('话'), par('次数', def: 1)],
            [
              blk('log', {
                'value': cat([pm('话'), pm('次数')]),
              }),
            ],
          ),
        ],
      ),
    );
    final host = be(tester).host!;
    expect(host.issues.where((i) => i.isError), isEmpty);
    await paletteTab(tester, bkCustomCategoryId);
    await longPress(tester, k('bk-palette-item-block-call:f1'));
    await tester.tap(k('bk-palette-custom-edit'));
    await tester.pumpAndSettle();
    expect(find.text('编辑积木'), findsOneWidget);
    await press(tester, 'bk-look-param-delete-1');
    expect(find.text('删掉参数“次数”？'), findsOneWidget);
    expect(find.text('有 1 处在用，槽里的东西会丢掉。'), findsOneWidget);
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    await press(tester, 'bk-look-done');
    expect(k('bk-look-form'), findsNothing);
    expect(find.textContaining('1 格内容一起丢掉了'), findsOneWidget, reason: '丢掉的实参要说一声');
    expect(doc(tester).function('f1')!.paramNames, ['话']);
    expect(doc(tester).route('use')!.body.first.args.keys, ['话']);
    // 定义里还读着“次数”：校验指到那一块上（红点），代码不更新。
    final g03 = host.issues.firstWhere((i) => i.rule == 'G03');
    expect((g03.scriptId, g03.isError, g03.path.single.index), ('f1', true, 0));
    // 提示条上的“撤销”：参数和各处的内容都回来。
    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();
    expect(doc(tester).function('f1')!.paramNames, ['话', '次数']);
    expect(exprNum(doc(tester).route('use')!.body.first.args['次数'], 'v'), 3);

    // 删除：先说有几处在用；取消不删；确认以后定义没了、接口里那一块也拿掉。
    await paletteTab(tester, bkCustomCategoryId);
    await longPress(tester, k('bk-palette-item-block-call:f1'));
    await tester.tap(k('bk-palette-custom-remove'));
    await tester.pumpAndSettle();
    expect(find.text('删掉“记一笔”？'), findsOneWidget);
    expect(find.textContaining('有 1 处在用'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(doc(tester).functions, hasLength(1));
    await longPress(tester, k('bk-palette-item-block-call:f1'));
    await tester.tap(k('bk-palette-custom-remove'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(doc(tester).functions, isEmpty);
    expect([for (final b in doc(tester).route('use')!.body) b.op], ['respondJson']);
    expect(k('bk-palette-custom-empty'), findsOneWidget);
    await flushed(tester);
    expect((jsonDecode(text(kBackendFileName)) as Map).containsKey('functions'), isFalse);
    expect((jsonDecode(text(kBackendFileName)) as Map)['version'], 1);
    host.undo();
    await tester.pumpAndSettle();
    expect(doc(tester).functions, hasLength(1));
    expect([for (final b in doc(tester).route('use')!.body) b.op], ['call:f1', 'respondJson']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('包成积木：带着“返回响应”的包不了，说原因；包得了的 → 起名字 → 这块和下面的搬进新定义、原处换成调用、用到的外面的变量成了参数；一步撤销', (tester) async {
    await boot(
      tester,
      ProjectTemplate.backendBlocks,
      language: 'node',
      before: seed(
        routes: [
          route('wrap', 'POST', '/wrap', [
            let('n', nm(2)),
            let('xs', ls([])),
            push('xs', vr('n')),
            blk('log', {'value': vr('xs')}),
          ]),
        ],
      ),
    );
    final host = be(tester).host!;
    // 样本里的 /hello：整串都以“返回响应”收尾，包不了。
    final hello = doc(tester).routes.firstWhere((r) => r.path == '/hello').id;
    await show(tester, hello);
    await holdBlock(tester, hello, [lcStep(0)]);
    expect(k('bk-block-menu-wrap'), findsOneWidget);
    await tester.tap(k('bk-block-menu-wrap'));
    await tester.pumpAndSettle();
    expect(k('bk-look-form'), findsNothing);
    expect(find.textContaining('返回响应'), findsOneWidget);
    expect(doc(tester).functions, isEmpty);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    await show(tester, 'wrap');
    final start = host.doc.encode();
    await holdBlock(tester, 'wrap', [lcStep(2)]);
    await tester.tap(k('bk-block-menu-wrap'));
    await tester.pumpAndSettle();
    expect(find.text('包成积木'), findsOneWidget);
    await type(tester, 'bk-look-name', '记下来');
    await press(tester, 'bk-look-done');
    expect(k('bk-look-form'), findsNothing);
    final f = doc(tester).functions.single;
    expect((f.name, f.paramNames.join(','), [for (final b in f.body) b.op].join(',')), ('记下来', 'xs,n', 'listPush,log'));
    final body = doc(tester).route('wrap')!.body;
    expect([for (final b in body) b.op], ['let', 'let', 'call:f1']);
    expect([for (final v in body.last.args.values) exprString(v, 'name')], ['xs', 'n']);
    expect(host.issues.where((i) => i.isError), isEmpty);
    expect(find.textContaining('包成了“记下来”'), findsOneWidget);
    await flushed(tester);
    await until(tester, () => text('server.js').contains('f_'), '包出来的函数进了代码');
    host.undo();
    await tester.pumpAndSettle();
    expect(host.doc.encode(), start);
    expect(tester.takeException(), isNull);
  });

  testWidgets('带口的值：把语句拖进匿名函数的口、再拖出来；匿名函数的参数小块拖进口里的槽；每步能撤销重做', (tester) async {
    await boot(
      tester,
      ProjectTemplate.backendBlocks,
      language: 'node',
      before: seed(
        routes: [
          route('mouth', 'GET', '/mouth', [
            let('f', lam(['x'], [ret(nm(1))])),
            json(callV(vr('f'), [nm(5)])),
          ]),
        ],
      ),
    );
    final host = be(tester).host!;
    expect(host.issues.where((i) => i.scriptId == 'mouth' && i.isError), isEmpty);
    await show(tester, 'mouth');
    final start = host.doc.encode();
    List<LcBlock> mouth() => doc(tester).route('mouth')!.body.first.exprMouths.single;
    final arm = lcExprMouthArm(0);

    // 从积木盒拖“写到日志”进口里（排在“返回”前面）。
    var (g, from) = await liftFromPalette(tester, '调试', 'block-log');
    await dropStatement(tester, g, from, 'mouth', [lcStep(0)], 0, arm: arm);
    expect([for (final b in mouth()) b.op], ['log', 'return']);
    // 匿名函数的参数小块 x 拖进“写到日志”的槽。
    final c = chip(tester, 'mouth', 0, owner: [lcStep(0)]);
    g = await pick(tester, c);
    await dropValue(tester, g, c, 'mouth', [lcStep(0), lcStep(0, arm: arm)], 'value');
    expect(mouth().first.args['value'], {'e': 'param', 'name': 'x'});
    expect(host.issues.where((i) => i.scriptId == 'mouth' && i.isError), isEmpty);
    final inside = host.doc.encode();

    // 从口里把“返回”拖出来，接到接口里：口里只剩“写到日志”；“返回 (值)”直接放在接口里不行 → 校验指出来。
    final from2 = grip(tester, 'mouth', [lcStep(0), lcStep(1, arm: arm)]);
    g = await pick(tester, from2);
    await dropStatement(tester, g, from2, 'mouth', const [], 1);
    expect([for (final b in mouth()) b.op], ['log']);
    expect([for (final b in doc(tester).route('mouth')!.body) b.op], ['let', 'return', 'respondJson']);
    final issue = host.issues.firstWhere((i) => i.scriptId == 'mouth' && i.isError);
    expect((issue.rule, issue.path.single.index), ('L03', 1));

    host.undo();
    await tester.pumpAndSettle();
    expect(host.doc.encode(), inside);
    host
      ..undo()
      ..undo();
    await tester.pumpAndSettle();
    expect(host.doc.encode(), start);
    host
      ..redo()
      ..redo();
    await tester.pumpAndSettle();
    expect(host.doc.encode(), inside);
    await flushed(tester);
    await until(tester, () => text('server.js').contains('/mouth'), '带匿名函数的接口进了代码');
    expect(tester.takeException(), isNull);
  });
}
