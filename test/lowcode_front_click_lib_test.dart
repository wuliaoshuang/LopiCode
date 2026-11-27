// 页面逻辑页里一步步点出来的路（积木第 5 版·第四轮·A3b 第 1 件）之三：积木库。
// “更多 › 积木库…”：自带的两个库怎么列（“接口服务”在页面逻辑里是灰的、带原因）→ 新建一个“都行”的库 → 进库的画布写两块积木 →
// 公开（一块是值，一块多一个“放进变量”的槽）→ 回页面逻辑启用 → 在帽子里用上 → 存盘的那一页导出成三种网页真编译真跑。
// 两个安全开关都是默认的关着。
//   LOPI_SHOTS=1 flutter test --no-pub test/lowcode_front_click_lib_test.dart   # 截图写到 ../preview/front/a3b/
@Tags(['needs-webdev'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/backend/backend_lib_build.dart';
import 'package:lopicode/lang/rules.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:material_ui/material_ui.dart';

import 'support/front_ui.dart';
import 'support/harness.dart';
import 'support/lowcode_builder.dart';
import 'support/page_front_samples.dart';

void main() {
  setUpAll(() async => lbFontsLoaded = await loadRealFonts());

  testWidgets('自带库怎么列 → 新建“都行”的库 → 库画布写两块积木并公开 → 页面逻辑里启用、用上（值、放进变量）→ 三种网页真编译真跑', (tester) async {
    expect((kLibNativeCodeEnabled, kUserLibHostEnabled), (false, false), reason: '这条路考的是默认状态');
    final session = await fuOpen(tester, frontPage([btn('b1', '问'), txt('t1'), btn('b2', '再问'), txt('t2')], [], frontDoc()));
    final page = fuHost(tester);

    // 1 更多 › 积木库：自带的两个库。“页面”用着；“接口服务”是灰的，下面一行写原因，点开也说。
    await fuMore(tester, 'libs');
    await fuUntil(tester, () => fk('be-lib-new').evaluate().isNotEmpty, '积木库面板读完项目里的库');
    await fuSee(tester, 'be-lib-builtin-why');
    expect(find.descendant(of: fk('be-lib-builtin-page'), matching: find.textContaining('用着')), findsOneWidget);
    expect(find.descendant(of: fk('be-lib-builtin'), matching: find.text('这里用不了')), findsOneWidget);
    expect(find.descendant(of: fk('be-lib-builtin-why'), matching: find.text('只在后端的积木里用得上')), findsOneWidget);
    await fuShot(tester, 'lib-1-builtin');
    await fuTap(tester, 'be-lib-builtin');
    expect(fk('be-lib-builtin-sheet'), findsOneWidget);
    expect(fk('be-sheet-problem'), findsWidgets, reason: '面板顶上说为什么用不了');
    expect(find.descendant(of: fk('be-lib-builtin-sheet'), matching: find.textContaining('只给后端用的库')), findsWidgets);
    expect(fk('be-lib-builtin-fork'), findsNothing);
    await fuShot(tester, 'lib-2-service-why');
    await fuCloseSheets(tester, 'be-lib-builtin-sheet');

    // 2 新建库：名字、标识、给谁用＝都行 → 直接进库的画布
    await fuTap(tester, 'be-lib-new');
    await fuType(tester, '问好');
    await fuType(tester, 'shuang/hello');
    expect(fk('be-lib-side'), findsOneWidget);
    await fuShot(tester, 'lib-3-side');
    await fuTap(tester, 'be-lib-side-both');
    await fuUntil(tester, () => find.textContaining('库 · 公开了').evaluate().isNotEmpty, '新建完进库的画布');
    final lib = fuHost(tester);
    expect(lib.doc.library?.id, 'shuang/hello');

    // 3 库的画布上：两块积木，都是“把给的东西原样交回”
    for (final (i, name) in ['回声', '回声到变量'].indexed) {
      await fuNewBlock(tester, name, '谁');
      final id = lib.doc.functions[i].id;
      await fuDropStmt(tester, '函数', 'block-return', id, const [], 0);
      await fuMoveValue(tester, fuChip(tester, id, 0), id, [lcStep(0)], 'value');
    }
    await fuShot(tester, 'lib-4-canvas');

    // 4 更多 › 这个库：两块都公开；第二块多一个“放进变量”的槽
    await fuMore(tester, 'lib-info', button: 'be-more');
    final ids = [for (final f in lib.doc.functions) f.id];
    await fuTap(tester, 'be-lib-def-${ids[0]}');
    await fuTap(tester, 'be-lib-def-public');
    await fuTap(tester, 'be-lib-def-look');
    await fuType(tester, '{谁} 的回声');
    await fuTap(tester, 'be-sheet-done');
    await fuTap(tester, 'be-lib-def-${ids[1]}');
    await fuTap(tester, 'be-lib-def-public');
    await fuTap(tester, 'be-lib-def-look');
    await fuType(tester, '喊一声 {谁}');
    await fuTap(tester, 'be-lib-def-into');
    await fuShot(tester, 'lib-5-public');
    await fuTap(tester, 'be-sheet-done');
    await fuTap(tester, 'be-sheet-done');
    expect(beLibFiles(lib.doc).problems, isEmpty);
    final libJson = File(session.guard.resolve('blocks/shuang/hello/lib.json'));
    await fuUntil(tester, libJson.existsSync, '库存盘就出库文件');

    final blocksJson = File(session.guard.resolve('blocks/shuang/hello/blocks.json'));
    // 5 回页面逻辑 → 积木库 → 这个库 → 在这份文档里用它
    await tester.binding.handlePopRoute();
    await settle(tester, rounds: 4);
    expect(identical(fuHost(tester), page), isTrue, reason: '回到页面逻辑页');
    // 离开库画布时最后那次改动才落盘（“放进变量”那个槽）：等它写完再往下点，手上就是等这一下。
    await fuUntil(tester, () => blocksJson.existsSync() && blocksJson.readAsStringSync().contains('"into"'), '离开库画布时把最后的改动写进库文件');
    await fuMore(tester, 'libs');
    await fuUntil(tester, () => fk('be-lib-shuang/hello').evaluate().isNotEmpty, '积木库面板里有新建的库');
    await fuTap(tester, 'be-lib-shuang/hello');
    final use = tester.widget<SwitchListTile>(fk('be-lib-use'));
    expect(use.onChanged, isNotNull, reason: '“都行”的库在页面逻辑里点得动');
    await fuShot(tester, 'lib-6-use');
    await fuTap(tester, 'be-lib-use');
    await fuUntil(tester, () => page.doc.use('shuang/hello') != null, '用上这个库');
    await fuCloseSheets(tester, 'be-libs');
    final cat = page.categories.firstWhere((c) => c.id == 'lib:shuang/hello');
    final exprs = [...cat.exprs, for (final g in cat.groups) ...g.exprs];
    final blocks = [...cat.blocks, for (final g in cat.groups) ...g.blocks];
    expect((exprs.length, blocks.length), (1, 1), reason: '一块是值，一块是带“放进变量”的语句');

    // 6 点“问”：把 t1 的文字改成 〔你好〕的回声
    await fuDropHat(tester, 'lib:lopi/page:事件', 'hat-libhat:lib:lopi/page#onClick', const Offset(40, 40));
    final h1 = page.doc.hats.last.id;
    await fuShow(tester, h1);
    await fuPick(tester, fuHatSlot(tester, h1, 'node'), 'b1');
    await fuDropStmt(tester, 'lib:lopi/page:控件', 'block-lib:lopi/page#propSet', h1, const [], 0);
    await fuPick(tester, fuArg(tester, h1, [lcStep(0)], 'node'), 't1');
    await fuPick(tester, fuArg(tester, h1, [lcStep(0)], 'prop'), 'text');
    await fuDropValue(tester, 'lib:shuang/hello', 'expr-${exprs.single}', h1, [lcStep(0)], 'value');
    await fuInline(tester, fuArg(tester, h1, [lcStep(0)], 'value', via: const ['谁']), '你好');

    // 7 点“再问”：新建变量 x → 喊一声〔在吗〕放进 x → 把 t2 的文字改成 x
    await fuDropHat(tester, 'lib:lopi/page:事件', 'hat-libhat:lib:lopi/page#onClick', const Offset(40, 300));
    final h2 = page.doc.hats.last.id;
    await fuShow(tester, h2);
    await fuPick(tester, fuHatSlot(tester, h2, 'node'), 'b2');
    await fuDropStmt(tester, '变量', 'block-let', h2, const [], 0);
    await fuDropValue(tester, '直接填', 'expr-text', h2, [lcStep(0)], 'value');
    await fuDropStmt(tester, 'lib:shuang/hello', 'block-${blocks.single}', h2, const [], 1);
    await fuInline(tester, fuArg(tester, h2, [lcStep(1)], '谁'), '在吗');
    await fuPick(tester, fuArg(tester, h2, [lcStep(1)], '结果'), 'x');
    await fuDropStmt(tester, 'lib:lopi/page:控件', 'block-lib:lopi/page#propSet', h2, const [], 2);
    await fuPick(tester, fuArg(tester, h2, [lcStep(2)], 'node'), 't2');
    await fuPick(tester, fuArg(tester, h2, [lcStep(2)], 'prop'), 'text');
    await fuDropValue(tester, '变量', 'expr-var', h2, [lcStep(2)], 'value');
    await fuPick(tester, fuArg(tester, h2, [lcStep(2)], 'value', via: const ['name']), 'x');
    await fuPick(tester, fuArg(tester, h2, [lcStep(2)], 'value', via: const ['name']), 'x');
    await fuShot(tester, 'lib-7-used');
    expect(fuErrors(tester), isEmpty);

    // 8 存盘 → 三种网页真编译 → 真点
    await fuSavedAndRun(tester, session, [
      {'op': 'click', 'sel': '.n-b1'},
      {'op': 'text', 'sel': '.n-t1', 'is': '你好'},
      {'op': 'click', 'sel': '.n-b2'},
      {'op': 'text', 'sel': '.n-t2', 'is': '在吗'},
    ]);
  });
}
