// 页面逻辑页里一步步点出来的路（积木第 5 版·第四轮·A3b 第 1 件）之一：新建一块“我的积木”（函数）、在帽子里调用它。
// 每一步都是手指的动作（点、填、按住拖），不是把数据塞进文档；最后把存盘的那一页导出成三种网页真编译、在 jsdom 里真跑。
//   LOPI_SHOTS=1 flutter test --no-pub test/lowcode_front_click_func_test.dart   # 截图写到 ../preview/front/a3b/
@Tags(['needs-webdev'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/blocks/block_palette_model.dart';
import 'package:lopicode/lowcode/logic_model.dart';

import 'support/front_ui.dart';
import 'support/harness.dart';
import 'support/lowcode_builder.dart';
import 'support/page_front_samples.dart';

void main() {
  setUpAll(() async => lbFontsLoaded = await loadRealFonts());

  testWidgets('新建积木“加倍”→ 定义里放“返回”和算式 → 点按钮的帽子里调用它、结果写到文字上 → 三种网页真编译真跑', (tester) async {
    final session = await fuOpen(tester, frontPage([btn('b1', '算'), txt('t1')], [], frontDoc()));
    // 1 积木盒“我的积木”页 → 新建积木：名字“加倍”，一个参数“数”
    await fuTab(tester, bkCustomCategoryId);
    await fuTap(tester, 'bk-palette-custom-new');
    await tester.enterText(fk('bk-look-name'), '加倍');
    await fuTap(tester, 'bk-look-param-add');
    await tester.enterText(fk('bk-look-param-name-0'), '数');
    await tester.pumpAndSettle();
    await fuShot(tester, 'func-1-new');
    await fuTap(tester, 'bk-look-done');
    expect(fuHost(tester).doc.functions.single.name, '加倍');

    // 2 定义里：返回 (数 + 数)
    await fuDropStmt(tester, '函数', 'block-return', 'f1', const [], 0);
    await fuDropValue(tester, '运算', 'expr-bin', 'f1', [lcStep(0)], 'value');
    await fuMoveValue(tester, fuChip(tester, 'f1', 0), 'f1', [lcStep(0)], 'value', via: const ['l']);
    await fuMoveValue(tester, fuChip(tester, 'f1', 0), 'f1', [lcStep(0)], 'value', via: const ['r']);

    // 3 “当点击”帽子 → 控件挑“算”那个按钮 → 里面“把 t1 的文字改成 加倍(21)”
    await fuDropHat(tester, 'lib:lopi/page:事件', 'hat-libhat:lib:lopi/page#onClick', const Offset(40, 260));
    final hatId = fuHost(tester).doc.hats.single.id;
    await fuShow(tester, hatId);
    await fuPick(tester, fuHatSlot(tester, hatId, 'node'), 'b1');
    await fuDropStmt(tester, 'lib:lopi/page:控件', 'block-lib:lopi/page#propSet', hatId, const [], 0);
    await fuPick(tester, fuArg(tester, hatId, [lcStep(0)], 'node'), 't1');
    await fuPick(tester, fuArg(tester, hatId, [lcStep(0)], 'prop'), 'text');
    await fuDropValue(tester, bkCustomCategoryId, 'expr-call:f1', hatId, [lcStep(0)], 'value');
    await fuDropValue(tester, '直接填', 'expr-num', hatId, [lcStep(0)], 'value', via: const ['数']);
    await fuInline(tester, fuArg(tester, hatId, [lcStep(0)], 'value', via: const ['数']), '21');
    await fuShot(tester, 'func-2-used');
    expect(fuErrors(tester), isEmpty);

    // 4 存盘 → 三种网页真编译 → 真点一下
    await fuSavedAndRun(tester, session, [
      {'op': 'click', 'sel': '.n-b1'},
      {'op': 'text', 'sel': '.n-t1', 'is': '42'},
    ]);
  });
}
