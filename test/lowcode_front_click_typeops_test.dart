// 页面逻辑页里一步步点出来的路（积木第 5 版·第四轮·A3b 第 2 件）：三块类型积木从积木盒里拖出来、选类型、用上。
// 每一步都是手指的动作（点、填、按住拖），不是把数据塞进文档；最后把存盘的那一页导出成三种网页真编译、在 jsdom 里真跑。
//   LOPI_SHOTS=1 flutter test --no-pub test/lowcode_front_click_typeops_test.dart   # 截图写到 ../preview/front/a3b/
@Tags(['needs-webdev'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/backend/backend_blocks_typeops.dart';
import 'package:lopicode/lang/types.dart';
import 'package:lopicode/lowcode/logic_model.dart';

import 'support/front_ui.dart';
import 'support/harness.dart';
import 'support/lowcode_builder.dart';
import 'support/page_front_samples.dart';

void main() {
  setUpAll(() async => lbFontsLoaded = await loadRealFonts());

  testWidgets('“类型”页拖出“当成某类型用”“标上类型”，“运算”页拖出“是不是某种类型”→ 选类型 → 三种网页真编译真跑', (tester) async {
    final session = await fuOpen(tester, frontPage([btn('b1', '试'), btn('b2', '看'), txt('t1'), txt('t2')], [], frontDoc()));
    const onClick = 'hat-libhat:lib:lopi/page#onClick';

    // 1 第一顶帽子：把 t1 的文字改成 把（“好” 标成 任意）当成 文字
    await fuDropHat(tester, 'lib:lopi/page:事件', onClick, const Offset(40, 120));
    final h1 = fuHost(tester).doc.hats.single.id;
    await fuShow(tester, h1);
    await fuPick(tester, fuHatSlot(tester, h1, 'node'), 'b1');
    await fuDropStmt(tester, 'lib:lopi/page:控件', 'block-lib:lopi/page#propSet', h1, const [], 0);
    await fuPick(tester, fuArg(tester, h1, [lcStep(0)], 'node'), 't1');
    await fuPick(tester, fuArg(tester, h1, [lcStep(0)], 'prop'), 'text');
    await fuDropValue(tester, '类型', 'expr-$kBeCast', h1, [lcStep(0)], 'value');
    await fuShot(tester, 'typeops-1-palette');
    await fuDropValue(tester, '类型', 'expr-$kBeAscribe', h1, [lcStep(0)], 'value', via: const ['x']);
    await fuPick(tester, fuArg(tester, h1, [lcStep(0)], 'value', via: const ['x', 'to']), beTypeKey(LType.any));
    await fuDropValue(tester, '直接填', 'expr-text', h1, [lcStep(0)], 'value', via: const ['x', 'x']);
    await fuInline(tester, fuArg(tester, h1, [lcStep(0)], 'value', via: const ['x', 'x']), '好');
    final v = fuHost(tester).doc.hats.single.body.single.args['value'] as Map;
    expect(v['e'], kBeCast);
    expect(v['to'], beTypeKey(LType.text), reason: '拖出来默认是文字');
    expect((v['x'] as Map)['to'], beTypeKey(LType.any));
    expect(fuErrors(tester), isEmpty);

    // 2 当成一个永远成不了的类型：当场标红；改回来就好
    await fuPick(tester, fuArg(tester, h1, [lcStep(0)], 'value', via: const ['to']), beTypeKey(const LType.listOf(LType.integer)));
    expect(fuErrors(tester), isEmpty, reason: '任意 → 列表：运行时才知道，搭的时候不报');
    await fuPick(tester, fuArg(tester, h1, [lcStep(0)], 'value', via: const ['x', 'to']), beTypeKey(LType.integer));
    expect(fuErrors(tester).join('\n'), contains('这里标的是'), reason: '文字标成整数放不进去');
    await fuShot(tester, 'typeops-2-wrong');
    await fuPick(tester, fuArg(tester, h1, [lcStep(0)], 'value', via: const ['x', 'to']), beTypeKey(LType.any));
    await fuPick(tester, fuArg(tester, h1, [lcStep(0)], 'value', via: const ['to']), beTypeKey(LType.text));
    expect(fuErrors(tester), isEmpty);

    // 3 第二顶帽子：把 t2 的文字改成 （“好” 是 文字）
    await fuDropHat(tester, 'lib:lopi/page:事件', onClick, const Offset(40, 330));
    final h2 = fuHost(tester).doc.hats.last.id;
    await fuShow(tester, h2);
    await fuPick(tester, fuHatSlot(tester, h2, 'node'), 'b2');
    await fuDropStmt(tester, 'lib:lopi/page:控件', 'block-lib:lopi/page#propSet', h2, const [], 0);
    await fuPick(tester, fuArg(tester, h2, [lcStep(0)], 'node'), 't2');
    await fuPick(tester, fuArg(tester, h2, [lcStep(0)], 'prop'), 'text');
    await fuDropValue(tester, '运算', 'expr-isType', h2, [lcStep(0)], 'value');
    await fuDropValue(tester, '直接填', 'expr-text', h2, [lcStep(0)], 'value', via: const ['x']);
    await fuPick(tester, fuArg(tester, h2, [lcStep(0)], 'value', via: const ['type']), 'text');
    await fuShot(tester, 'typeops-3-used');
    expect(fuErrors(tester), isEmpty);

    // 4 存盘 → 三种网页真编译 → 真点
    await fuSavedAndRun(tester, session, [
      {'op': 'click', 'sel': '.n-b1'},
      {'op': 'text', 'sel': '.n-t1', 'is': '好'},
      {'op': 'click', 'sel': '.n-b2'},
      {'op': 'text', 'sel': '.n-t2', 'is': 'true'},
    ]);
  });
}
