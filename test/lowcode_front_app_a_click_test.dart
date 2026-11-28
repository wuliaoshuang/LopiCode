// 小应用甲组·一步步点出来的路（待办小应用里“登录并记住”那一段）：390×844 的应用界面里，
// 搭建页“更多 › 积木逻辑”› “更多 › 积木库…”把“请求”和“本地保存”两个自带库用上 ›
// 点“登录”：从假服务取令牌、存到本地、写“登录成功”› 点“看”：把本地存的令牌写出来 › 存盘 ›
// 存盘的那一页导出成三种网页真编译，对着本地假服务真跑（关掉再开令牌还在）。两个安全开关都是默认的关着。
// 页面上的控件（两个按钮、一段文字）是事先放好的，逻辑从空白一步步点出来。
//   LOPI_SHOTS=1 flutter test --no-pub test/lowcode_front_app_a_click_test.dart   # 截图写到 ../preview/front/a5b/
@Tags(['needs-webdev'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/lang/rules.dart';
import 'package:lopicode/lowcode/logic_model.dart';

import 'support/front_app_a_kit.dart';
import 'support/front_libs_samples.dart';
import 'support/front_ui.dart';
import 'support/harness.dart';
import 'support/lowcode_builder.dart';
import 'support/page_front_samples.dart';

Future<void> _shot(WidgetTester tester, String name) => lbShot(tester, '../preview/front/a5b', name);

Future<void> _useLib(WidgetTester tester, String short) async {
  if (fk('be-libs').evaluate().isEmpty) {
    await fuMore(tester, 'libs');
    await fuUntil(tester, () => fk('be-lib-new').evaluate().isNotEmpty, '积木库面板读完项目里的库');
  }
  await fuTap(tester, 'be-lib-builtin-$short');
  await fuTap(tester, 'be-lib-use');
  await fuUntil(tester, () => fuHost(tester).doc.use('lopi/$short') != null, '用上 $short');
}

void main() {
  setUpAll(() async => lbFontsLoaded = await loadRealFonts());

  testWidgets('登录并记住：用上“请求”“本地保存”› 拖积木 › 存盘 › 三种网页对着假服务真跑', (tester) async {
    expect((kLibNativeCodeEnabled, kUserLibHostEnabled), (false, false), reason: '这条路考的是默认状态');
    final api = (await tester.runAsync(() => FakeApi.start((q) => q.path == '/token' ? const FakeRes(200, 'tk-9') : const FakeRes(404, '没有'))))!;
    addTearDown(() => tester.runAsync(api.stop));

    final session = await fuOpen(tester, frontPage([btn('b1', '登录'), btn('b2', '看'), txt('t1')], [], frontDoc()));
    final page = fuHost(tester);

    // 1 更多 › 积木库…：把“请求”和“本地保存”用上
    await _useLib(tester, 'http');
    await _shot(tester, 'click-1-http-on');
    await fuCloseSheets(tester, 'be-libs');
    await _useLib(tester, 'storage');
    await fuCloseSheets(tester, 'be-libs');
    expect(page.categories.map((c) => c.id), containsAll(['lib:lopi/http', 'lib:lopi/storage']));

    // 2 点“登录”：把〔从 …/token 取到的 JSON〕存到本地，名字叫〔令牌〕；再把 t1 的文字改成〔登录成功〕
    await fuDropHat(tester, 'lib:lopi/page:事件', 'hat-libhat:lib:lopi/page#onClick', const Offset(40, 40));
    final h1 = page.doc.hats.last.id;
    await fuShow(tester, h1);
    await fuPick(tester, fuHatSlot(tester, h1, 'node'), 'b1');
    await fuDropStmt(tester, 'lib:lopi/storage', 'block-lib:lopi/storage#set', h1, const [], 0);
    await fuInline(tester, fuArg(tester, h1, [lcStep(0)], 'key'), '令牌');
    await _shot(tester, 'click-2-set');
    await fuDropValue(tester, 'lib:lopi/http', 'expr-lib:lopi/http#getJson', h1, [lcStep(0)], 'value');
    await fuInline(tester, fuArg(tester, h1, [lcStep(0)], 'value', via: const ['url']), '${api.base}/token');
    await _shot(tester, 'click-3-request-in');
    await fuDropStmt(tester, 'lib:lopi/page:控件', 'block-lib:lopi/page#propSet', h1, const [], 1);
    await fuPick(tester, fuArg(tester, h1, [lcStep(1)], 'node'), 't1');
    await fuPick(tester, fuArg(tester, h1, [lcStep(1)], 'prop'), 'text');
    await fuInline(tester, fuArg(tester, h1, [lcStep(1)], 'value'), '登录成功');

    // 3 点“看”：把 t1 的文字改成〔本地存的 令牌，没有就用 没登录〕
    await fuDropHat(tester, 'lib:lopi/page:事件', 'hat-libhat:lib:lopi/page#onClick', const Offset(40, 320));
    final h2 = page.doc.hats.last.id;
    await fuShow(tester, h2);
    await fuPick(tester, fuHatSlot(tester, h2, 'node'), 'b2');
    await fuDropStmt(tester, 'lib:lopi/page:控件', 'block-lib:lopi/page#propSet', h2, const [], 0);
    await fuPick(tester, fuArg(tester, h2, [lcStep(0)], 'node'), 't1');
    await fuPick(tester, fuArg(tester, h2, [lcStep(0)], 'prop'), 'text');
    await fuDropValue(tester, 'lib:lopi/storage', 'expr-lib:lopi/storage#get', h2, [lcStep(0)], 'value');
    await fuInline(tester, fuArg(tester, h2, [lcStep(0)], 'value', via: const ['key']), '令牌');
    await fuInline(tester, fuArg(tester, h2, [lcStep(0)], 'value', via: const ['orElse']), '没登录');
    expect(fuErrors(tester), isEmpty);
    await _shot(tester, 'click-4-canvas');

    // 4 存盘 → 三种网页真编译，对着假服务真跑：没登录先看、登录、关掉再开还在
    final saved = await fuSavedAndRun(tester, session, [
      netOn(),
      click('b2'),
      textIs('t1', '没登录'),
      click('b1'),
      untilText('t1', '登录成功'),
      storedIs('令牌', '"tk-9"'),
      ...reopen(),
      click('b2'),
      textIs('t1', 'tk-9'),
    ]);
    expect(saved.logic.uses.map((u) => u['id']), containsAll(['lopi/http', 'lopi/storage']));
    expect(api.hit('GET /token'), 3, reason: '三种网页各取了一次');
  });
}
