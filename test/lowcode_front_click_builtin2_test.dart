// 页面逻辑页里一步步点出来的路（积木第 5 版·第四轮·A5a）：自带前端库第二批——路由、表单校验、国际化、动画。
// 每个库一条：搭建页“更多 › 积木逻辑”›“更多 › 积木库…”› 应用自带里点开这个库 › 在画布上看（只读）›“在这份文档里用它”›
// 积木盒多出这个库的一页 › 拖它的积木、填好 › 存盘 › 存盘的那一页导出成三种网页真编译真跑。两个安全开关都是默认的关着。
//   LOPI_SHOTS=1 flutter test --no-pub test/lowcode_front_click_builtin2_test.dart   # 截图写到 ../preview/front/a5a/
@Tags(['needs-webdev'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/blocks/block_canvas_view.dart';
import 'package:lopicode/lang/rules.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/project_session.dart';
import 'package:material_ui/material_ui.dart';

import 'support/front_libs_more_samples.dart';
import 'support/front_libs_samples.dart';
import 'support/front_ui.dart';
import 'support/harness.dart';
import 'support/lowcode_builder.dart';
import 'support/page_front_samples.dart';

Future<void> _shot(WidgetTester tester, String name) => lbShot(tester, '../preview/front/a5a', name);

const _page = 'lib:lopi/page';

/// 打开页面逻辑 › 积木库… › 点开 [short] 这个库 › 只读地看 › 用上它。回来时面板都收起了、积木盒里有它的一页。
Future<ProjectSession> _openAndUse(WidgetTester tester, LcDocument doc, String short, String label) async {
  expect((kLibNativeCodeEnabled, kUserLibHostEnabled), (false, false), reason: '这条路考的是默认状态');
  final session = await fuOpen(tester, doc);
  final page = fuHost(tester);
  expect(page.categories.where((c) => c.id == 'lib:lopi/$short'), isEmpty, reason: '没用上以前积木盒里没有这一页');

  await fuMore(tester, 'libs');
  await fuUntil(tester, () => fk('be-lib-new').evaluate().isNotEmpty, '积木库面板读完项目里的库');
  for (final s in const ['router', 'form', 'i18n', 'anim']) {
    await fuSee(tester, 'be-lib-builtin-$s');
  }
  await fuSee(tester, 'be-lib-builtin-$short');
  await _shot(tester, '$short-1-libs');

  await fuTap(tester, 'be-lib-builtin-$short');
  expect(fk('be-lib-front-$short-sheet'), findsOneWidget);
  expect(find.descendant(of: fk('be-lib-front-$short-sheet'), matching: find.text(label)), findsWidgets);
  expect(tester.widget<SwitchListTile>(fk('be-lib-use')).value, isFalse);
  await _shot(tester, '$short-2-sheet');

  await fuTap(tester, 'be-lib-front-view');
  expect(fk('be-lib-view'), findsOneWidget);
  expect(find.byType(BlockCanvasView), findsOneWidget);
  expect(tester.takeException(), isNull);
  await settle(tester, rounds: 8);
  await _shot(tester, '$short-3-canvas');
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
  expect(fk('be-lib-view'), findsNothing);

  if (fk('be-libs').evaluate().isEmpty) {
    await fuMore(tester, 'libs');
    await fuUntil(tester, () => fk('be-lib-new').evaluate().isNotEmpty, '积木库面板读完项目里的库');
  }
  await fuTap(tester, 'be-lib-builtin-$short');
  await fuTap(tester, 'be-lib-use');
  await fuUntil(tester, () => page.doc.use('lopi/$short') != null, '用上这个库');
  expect(tester.widget<SwitchListTile>(fk('be-lib-use')).value, isTrue);
  await fuCloseSheets(tester, 'be-libs');
  final cat = page.categories.firstWhere((c) => c.id == 'lib:lopi/$short');
  expect(cat.label, label);
  return session;
}

/// 拖一个“当点了 b1”出来，回它的号。
Future<String> _onClickB1(WidgetTester tester, Offset at) async {
  await fuDropHat(tester, '$_page:事件', 'hat-libhat:$_page#onClick', at);
  final id = fuHost(tester).doc.hats.last.id;
  await fuShow(tester, id);
  await fuPick(tester, fuHatSlot(tester, id, 'node'), 'b1');
  return id;
}

/// 在 [hat] 的第 [index] 句放“把 t1 的文字改成 …”（值还空着）。
Future<void> _setT1(WidgetTester tester, String hat, int index) async {
  await fuDropStmt(tester, '$_page:控件', 'block-$_page#propSet', hat, const [], index);
  await fuPick(tester, fuArg(tester, hat, [lcStep(index)], 'node'), 't1');
  await fuPick(tester, fuArg(tester, hat, [lcStep(index)], 'prop'), 'text');
}

void main() {
  setUpAll(() async => lbFontsLoaded = await loadRealFonts());

  testWidgets('路由：用它 › 点了就“去 /detail/7”› 把“现在的路径”写出来 › 三种网页真编译真跑', (tester) async {
    const lib = 'lib:lopi/router';
    final session = await _openAndUse(tester, frontPage([btn('b1', '去'), txt('t1')], [], frontDoc()), 'router', '路由');
    final h1 = await _onClickB1(tester, const Offset(40, 40));
    await fuDropStmt(tester, lib, 'block-$lib#go', h1, const [], 0);
    await fuInline(tester, fuArg(tester, h1, [lcStep(0)], 'path'), '/detail/7');
    await _setT1(tester, h1, 1);
    await fuDropValue(tester, lib, 'expr-$lib#path', h1, [lcStep(1)], 'value');
    expect(fuErrors(tester), isEmpty);
    await _shot(tester, 'router-4-canvas');
    final saved = await fuSavedAndRun(tester, session, [click('b1'), hashIs('#/detail/7'), textIs('t1', '/detail/7')]);
    expect(saved.logic.uses.map((u) => u['id']), contains('lopi/router'));
  });

  testWidgets('表单校验：用它 ›“自己的规则”里说“这一格不对”› 点了就查一格 › 三种网页真编译真跑', (tester) async {
    const lib = 'lib:lopi/form';
    final session = await _openAndUse(tester, frontPage([btn('b1', '查'), txt('t1')], [], frontDoc()), 'form', '表单校验');
    await fuDropHat(tester, lib, 'hat-libhat:$lib#custom', const Offset(40, 40));
    final h0 = fuHost(tester).doc.hats.last.id;
    await fuShow(tester, h0);
    await fuInline(tester, fuHatSlot(tester, h0, 'form'), '改密码');
    await fuInline(tester, fuHatSlot(tester, h0, 'field'), '新密码');
    await fuDropStmt(tester, lib, 'block-$lib#fail', h0, const [], 0);
    await fuInline(tester, fuArg(tester, h0, [lcStep(0)], 'msg'), '太简单了');
    final h1 = await _onClickB1(tester, const Offset(40, 300));
    await _setT1(tester, h1, 0);
    await fuDropValue(tester, lib, 'expr-$lib#check', h1, [lcStep(0)], 'value');
    await fuInline(tester, fuArg(tester, h1, [lcStep(0)], 'value', via: const ['form']), '改密码');
    await fuInline(tester, fuArg(tester, h1, [lcStep(0)], 'value', via: const ['field']), '新密码');
    await fuInline(tester, fuArg(tester, h1, [lcStep(0)], 'value', via: const ['value']), 'abc');
    expect(fuErrors(tester), isEmpty);
    await _shot(tester, 'form-4-canvas');
    final saved = await fuSavedAndRun(tester, session, [click('b1'), textIs('t1', '太简单了')]);
    expect(saved.logic.uses.map((u) => u['id']), contains('lopi/form'));
  });

  testWidgets('国际化：用它 › 点了就把数写成带千位分隔的样子 › 三种网页真编译真跑', (tester) async {
    const lib = 'lib:lopi/i18n';
    final session = await _openAndUse(tester, frontPage([btn('b1', '算'), txt('t1')], [], frontDoc()), 'i18n', '国际化');
    final h1 = await _onClickB1(tester, const Offset(40, 40));
    await _setT1(tester, h1, 0);
    await fuDropValue(tester, lib, 'expr-$lib#group', h1, [lcStep(0)], 'value');
    // 要数的槽：先从“直接填”拖一块“数字”进去，再填（槽里直接打的字算文字，检查会说“要小数，放进来的是文字”）
    await fuDropValue(tester, '直接填', 'expr-num', h1, [lcStep(0)], 'value', via: const ['value']);
    await fuInline(tester, fuArg(tester, h1, [lcStep(0)], 'value', via: const ['value', 'v']), '1234567');
    await fuDropValue(tester, '直接填', 'expr-num', h1, [lcStep(0)], 'value', via: const ['digits']);
    await fuInline(tester, fuArg(tester, h1, [lcStep(0)], 'value', via: const ['digits', 'v']), '2');
    expect(fuErrors(tester), isEmpty);
    await _shot(tester, 'i18n-4-canvas');
    final saved = await fuSavedAndRun(tester, session, [click('b1'), textIs('t1', '1,234,567.00')]);
    expect(saved.logic.uses.map((u) => u['id']), contains('lopi/i18n'));
  });

  testWidgets('动画：用它 › 点了就在 60 毫秒里把状态 x 变到 100 › 绑着 x 的文字跟着变 › 三种网页真编译真跑', (tester) async {
    const lib = 'lib:lopi/anim';
    final session = await _openAndUse(tester, frontPage([btn('b1', '动'), bound('v', 'x')], [numVar('x')], frontDoc()), 'anim', '动画');
    final h1 = await _onClickB1(tester, const Offset(40, 40));
    await fuDropStmt(tester, lib, 'block-$lib#tween', h1, const [], 0);
    await fuDropValue(tester, '直接填', 'expr-num', h1, [lcStep(0)], 'ms');
    await fuInline(tester, fuArg(tester, h1, [lcStep(0)], 'ms', via: const ['v']), '60');
    await fuInline(tester, fuArg(tester, h1, [lcStep(0)], 'state'), 'x');
    await fuDropValue(tester, '直接填', 'expr-num', h1, [lcStep(0)], 'to');
    await fuInline(tester, fuArg(tester, h1, [lcStep(0)], 'to', via: const ['v']), '100');
    expect(fuErrors(tester), isEmpty);
    await _shot(tester, 'anim-4-canvas');
    final saved = await fuSavedAndRun(tester, session, [textIs('v', '0'), click('b1'), untilText('v', '100')]);
    expect(saved.logic.uses.map((u) => u['id']), contains('lopi/anim'));
  });
}
