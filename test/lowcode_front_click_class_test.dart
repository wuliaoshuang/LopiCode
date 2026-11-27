// 页面逻辑页里一步步点出来的路（积木第 5 版·第四轮·A3b 第 1 件）之二：类型与类、模块。
// “更多 › 类型与类…”：建一个记录、一个类（字段、“创建时”、带交回值的方法）→ 进类的画布把方法写出来 → 回页面逻辑在帽子里用它们；
// “更多 › 模块…”：加一个模块顶上的变量，在两顶帽子里共用。存盘的那一页导出成三种网页真编译真跑。
//   LOPI_SHOTS=1 flutter test --no-pub test/lowcode_front_click_class_test.dart   # 截图写到 ../preview/front/a3b/
@Tags(['needs-webdev'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/lowcode/logic_model.dart';

import 'support/front_ui.dart';
import 'support/harness.dart';
import 'support/lowcode_builder.dart';
import 'support/page_front_samples.dart';

void main() {
  setUpAll(() async => lbFontsLoaded = await loadRealFonts());

  testWidgets('类型与类：建记录、建类（字段、创建时、方法）→ 类的画布里写方法 → 帽子里新建对象调方法、读记录的字段 → 三种网页真编译真跑', (tester) async {
    final session = await fuOpen(tester, frontPage([btn('b1', '数'), txt('t1'), btn('b2', '看'), txt('t2')], [], frontDoc()));
    final host = fuHost(tester);
    Future<void> rename(String key, String to) async {
      await fuTap(tester, key);
      await fuType(tester, to);
    }

    // 1 更多 › 类型与类 › 新建记录“名片”，一个文字字段“名字”
    await fuMore(tester, 'types');
    await fuTap(tester, 'be-core-add');
    await fuTap(tester, 'be-core-add-record');
    await rename('be-core-name', '名片');
    expect([for (final f in host.doc.core.typeNamed('名片')!.fields) f.name], ['名字'], reason: '新建的记录自带一个文字字段“名字”');
    await fuShot(tester, 'class-1-record');
    await fuTap(tester, 'be-sheet-done');

    // 2 新建类“计数器”：整数字段“次数”、“创建时”、方法“加一”交回整数
    await fuTap(tester, 'be-core-add');
    await fuTap(tester, 'be-core-add-class');
    await rename('be-core-name', '计数器');
    await fuTap(tester, 'be-core-add-field');
    await rename('be-core-field-${host.doc.core.typeNamed('计数器')!.fields.last.name}', '次数');
    await fuTap(tester, 'be-core-field-type-次数');
    await fuTap(tester, 'be-type-integer');
    await fuTap(tester, 'be-type-done');
    await fuTap(tester, 'be-core-add-ctor');
    await fuTap(tester, 'be-core-add-method');
    await fuTap(tester, 'be-core-method-${host.doc.core.typeNamed('计数器')!.methods.single.name}');
    await rename('be-core-method-name', '加一');
    await fuTap(tester, 'be-core-returns');
    await fuTap(tester, 'be-type-integer');
    await fuTap(tester, 'be-type-done');
    await fuShot(tester, 'class-2-method');
    await fuTap(tester, 'be-sheet-done');
    await fuShot(tester, 'class-3-class');
    final cls = host.doc.core.typeNamed('计数器')!;
    final ctor = cls.ctor!.id;
    final m = cls.methods.single.id;

    // 3 进类的画布：创建时把“次数”设成 0；“加一”把次数加 1 再交回
    await fuTap(tester, 'be-core-open-canvas');
    expect(host.canvasType?.name, '计数器');
    expect(fk('be-canvas-back'), findsOneWidget);
    await fuDropStmt(tester, '类型', 'block-setField', ctor, const [], 0);
    await fuDropValue(tester, '类型', 'expr-this', ctor, [lcStep(0)], 'of');
    await fuPick(tester, fuArg(tester, ctor, [lcStep(0)], 'name'), '次数');
    await fuDropValue(tester, '直接填', 'expr-num', ctor, [lcStep(0)], 'value');

    await fuDropStmt(tester, '类型', 'block-setField', m, const [], 0);
    await fuDropValue(tester, '类型', 'expr-this', m, [lcStep(0)], 'of');
    await fuPick(tester, fuArg(tester, m, [lcStep(0)], 'name'), '次数');
    await fuDropValue(tester, '运算', 'expr-bin', m, [lcStep(0)], 'value');
    await fuDropValue(tester, '类型', 'expr-getField', m, [lcStep(0)], 'value', via: const ['l']);
    await fuDropValue(tester, '类型', 'expr-this', m, [lcStep(0)], 'value', via: const ['l', 'of']);
    await fuPick(tester, fuArg(tester, m, [lcStep(0)], 'value', via: const ['l', 'name']), '次数');
    await fuInline(tester, fuArg(tester, m, [lcStep(0)], 'value', via: const ['r']), '1');
    await fuDropStmt(tester, '函数', 'block-return', m, const [], 1);
    await fuDropValue(tester, '类型', 'expr-getField', m, [lcStep(1)], 'value');
    await fuDropValue(tester, '类型', 'expr-this', m, [lcStep(1)], 'value', via: const ['of']);
    await fuPick(tester, fuArg(tester, m, [lcStep(1)], 'value', via: const ['name']), '次数');
    await fuShot(tester, 'class-4-canvas');
    await fuTap(tester, 'be-canvas-back');
    expect(host.canvasType, isNull);

    // 4 页面逻辑里用：点“数”→ 把 t1 的文字改成〔新建 计数器〕的 加一
    await fuDropHat(tester, 'lib:lopi/page:事件', 'hat-libhat:lib:lopi/page#onClick', const Offset(40, 40));
    final h1 = host.doc.hats.last.id;
    await fuShow(tester, h1);
    await fuPick(tester, fuHatSlot(tester, h1, 'node'), 'b1');
    await fuDropStmt(tester, 'lib:lopi/page:控件', 'block-lib:lopi/page#propSet', h1, const [], 0);
    await fuPick(tester, fuArg(tester, h1, [lcStep(0)], 'node'), 't1');
    await fuPick(tester, fuArg(tester, h1, [lcStep(0)], 'prop'), 'text');
    await fuDropValue(tester, '类型', 'expr-callMethod', h1, [lcStep(0)], 'value');
    await fuDropValue(tester, '类型', 'expr-classNew', h1, [lcStep(0)], 'value', via: const ['of']);
    // ignore: avoid_print
    await fuPick(tester, fuArg(tester, h1, [lcStep(0)], 'value', via: const ['name']), '加一');

    // 5 点“看”→ 把 t2 的文字改成〔新建记录 名片〕的 名字
    await fuDropHat(tester, 'lib:lopi/page:事件', 'hat-libhat:lib:lopi/page#onClick', const Offset(40, 300));
    final h2 = host.doc.hats.last.id;
    await fuShow(tester, h2);
    await fuPick(tester, fuHatSlot(tester, h2, 'node'), 'b2');
    await fuDropStmt(tester, 'lib:lopi/page:控件', 'block-lib:lopi/page#propSet', h2, const [], 0);
    await fuPick(tester, fuArg(tester, h2, [lcStep(0)], 'node'), 't2');
    await fuPick(tester, fuArg(tester, h2, [lcStep(0)], 'prop'), 'text');
    await fuDropValue(tester, '类型', 'expr-getField', h2, [lcStep(0)], 'value');
    await fuDropValue(tester, '类型', 'expr-recNew', h2, [lcStep(0)], 'value', via: const ['of']);
    await fuPick(tester, fuArg(tester, h2, [lcStep(0)], 'value', via: const ['name']), '名字');
    await fuInline(tester, fuArg(tester, h2, [lcStep(0)], 'value', via: const ['of', 'fields', 0, 'value']), '霜霜');
    await fuShot(tester, 'class-5-used');
    // ignore: avoid_print
    expect(fuErrors(tester), isEmpty);

    await fuSavedAndRun(tester, session, [
      {'op': 'click', 'sel': '.n-b1'},
      {'op': 'text', 'sel': '.n-t1', 'is': '1'},
      {'op': 'click', 'sel': '.n-b2'},
      {'op': 'text', 'sel': '.n-t2', 'is': '霜霜'},
    ]);
  });

  testWidgets('模块：加一个模块顶上的变量 → 两顶帽子共用它 → 三种网页真编译真跑', (tester) async {
    final session = await fuOpen(tester, frontPage([btn('b1', '加'), btn('b2', '看'), txt('t1')], [], frontDoc()));
    final host = fuHost(tester);
    // 1 更多 › 模块：新建一个模块；加一个顶上的变量
    await fuMore(tester, 'modules');
    expect(fk('be-modules'), findsOneWidget);
    await fuTap(tester, 'be-module-add');
    await fuTap(tester, 'be-global-add');
    final g = host.doc.core.globals.single.name;
    await fuShot(tester, 'module-1');
    await fuCloseSheets(tester, 'be-modules');

    // 2 点“加”：把变量加上 1
    await fuDropHat(tester, 'lib:lopi/page:事件', 'hat-libhat:lib:lopi/page#onClick', const Offset(40, 40));
    final h1 = host.doc.hats.last.id;
    await fuShow(tester, h1);
    await fuPick(tester, fuHatSlot(tester, h1, 'node'), 'b1');
    await fuDropStmt(tester, '变量', 'block-changeVar', h1, const [], 0);
    await fuPick(tester, fuArg(tester, h1, [lcStep(0)], 'name'), g);

    // 3 点“看”：把 t1 的文字改成这个变量
    await fuDropHat(tester, 'lib:lopi/page:事件', 'hat-libhat:lib:lopi/page#onClick', const Offset(40, 300));
    final h2 = host.doc.hats.last.id;
    await fuShow(tester, h2);
    await fuPick(tester, fuHatSlot(tester, h2, 'node'), 'b2');
    await fuDropStmt(tester, 'lib:lopi/page:控件', 'block-lib:lopi/page#propSet', h2, const [], 0);
    await fuPick(tester, fuArg(tester, h2, [lcStep(0)], 'node'), 't1');
    await fuPick(tester, fuArg(tester, h2, [lcStep(0)], 'prop'), 'text');
    await fuDropValue(tester, '变量', 'expr-var', h2, [lcStep(0)], 'value');
    await fuPick(tester, fuArg(tester, h2, [lcStep(0)], 'value', via: const ['name']), g);
    await fuShot(tester, 'module-2-used');
    // ignore: avoid_print
    expect(fuErrors(tester), isEmpty);

    await fuSavedAndRun(tester, session, [
      {'op': 'click', 'sel': '.n-b1'},
      {'op': 'click', 'sel': '.n-b1'},
      {'op': 'click', 'sel': '.n-b2'},
      {'op': 'text', 'sel': '.n-t1', 'is': '2'},
    ]);
  });
}
