// 小应用乙组·第 2 种形状的逐步点击界面测试（390×844）：照着霜霜在手机上会点的顺序走一遍——
// 项目甲的页面逻辑 › 更多 › 积木库 › 新建库（给谁用＝前端）→ 库的画布里把“本地保存”用上、写“会话”库的关键一段
// （“记住令牌”把令牌存到本地、“记着的令牌”取回来）、给参数标类型 → 更多 › 这个库：两块都公开 → 回页面逻辑 › 积木库 › 这个库 › 导出成一个文件；
// 项目乙（另一份页面文档）› 更多 › 积木库 › 从文件导入（先看预览）→ 把“本地保存”和这个库都用上 → 拖它的两块积木 → 存盘 → 三种网页真编译真跑。
// 两个安全开关都是默认的关着。
//   LOPI_SHOTS=1 flutter test --no-pub test/lowcode_front_app_b_click_test.dart   # 截图写到 ../preview/front/a5c/
@Tags(['needs-webdev'])
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart' show SizedBox;
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/backend/backend_lib_build.dart';
import 'package:lopicode/lang/rules.dart';
import 'package:lopicode/lang/types.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:path/path.dart' as p;

import 'support/front_libs_samples.dart';
import 'support/front_ui.dart';
import 'support/harness.dart';
import 'support/lowcode_builder.dart';
import 'support/page_front_samples.dart';

const String _lib = 'shuang/session';
Future<void> _shot(WidgetTester tester, String name) => lbShot(tester, '../preview/front/a5c', name);

/// 库的画布（或页面逻辑）› 更多 › 积木库 › 自带的“本地保存”› 在这份文档里用它。
Future<void> _useStorage(WidgetTester tester, {required String button}) async {
  final host = fuHost(tester);
  await fuMore(tester, 'libs', button: button);
  await fuUntil(tester, () => fk('be-lib-new').evaluate().isNotEmpty, '积木库面板读完项目里的库');
  await fuTap(tester, 'be-lib-builtin-storage');
  await fuTap(tester, 'be-lib-use');
  await fuUntil(tester, () => host.doc.use('lopi/storage') != null, '用上“本地保存”');
  await fuCloseSheets(tester, 'be-libs');
}

/// 选中 [fnId] 这块“我的积木”的帽子 → 类型那一行的“改”→ 把参数 [param] 标成文字。
Future<void> _markText(WidgetTester tester, String fnId, String param) async {
  fuEd(tester).jumpTo(fnId, const []);
  await tester.pumpAndSettle();
  await fuTap(tester, 'bk-type-edit');
  expect(fk('be-types-sheet'), findsOneWidget);
  await fuTap(tester, 'be-type-param-$param');
  await fuTap(tester, 'be-type-text');
  await fuTap(tester, 'be-type-done');
  expect(find.descendant(of: fk('be-type-param-$param'), matching: find.text('文字')), findsOneWidget);
  await fuCloseSheets(tester, 'be-types-sheet');
}

void main() {
  setUpAll(() async => lbFontsLoaded = await loadRealFonts());

  testWidgets('项目甲：新建前端库、写关键一段、标类型、公开、导出 → 项目乙：从文件导入、用上、拖积木 → 三种网页真编译真跑', (tester) async {
    expect((kLibNativeCodeEnabled, kUserLibHostEnabled), (false, false), reason: '这条路考的是默认状态');

    // ———— 项目甲 ————
    final a = await fuOpen(tester, frontPage([txt('t1')], [], frontDoc()));
    final pageA = fuHost(tester);

    // 1 更多 › 积木库 › 新建库：名字、标识、给谁用＝前端 → 直接进库的画布
    await fuMore(tester, 'libs');
    await fuUntil(tester, () => fk('be-lib-new').evaluate().isNotEmpty, '积木库面板读完项目里的库');
    await fuTap(tester, 'be-lib-new');
    await fuType(tester, '会话');
    await fuType(tester, _lib);
    expect(fk('be-lib-side'), findsOneWidget);
    await _shot(tester, '1-new-lib-side');
    await fuTap(tester, 'be-lib-side-frontend');
    await fuUntil(tester, () => find.textContaining('库 · 公开了').evaluate().isNotEmpty, '新建完进库的画布');
    final lib = fuHost(tester);
    expect(lib.doc.library?.id, _lib);
    expect(lib.doc.isFront, isTrue);

    // 2 库的画布 › 更多 › 积木库：把自带的“本地保存”用上（这个库要靠它）
    await _useStorage(tester, button: 'be-more');
    await _shot(tester, '2-lib-uses-storage');

    // 3 关键一段之一：“记住令牌（令牌）”＝把〔令牌〕存到本地，名字叫 tk_token；参数标成文字
    await fuNewBlock(tester, '记住令牌', '令牌');
    final f1 = lib.doc.functions[0].id;
    await fuDropStmt(tester, 'lib:lopi/storage', 'block-lib:lopi/storage#set', f1, const [], 0);
    await fuInline(tester, fuArg(tester, f1, [lcStep(0)], 'key'), 'tk_token');
    await fuMoveValue(tester, fuChip(tester, f1, 0), f1, [lcStep(0)], 'value');
    await _markText(tester, f1, '令牌');
    expect(lib.doc.function(f1)!.params.single.type, LType.text);

    // 4 关键一段之二：“记着的令牌（没有时）”＝交回 本地存着的 tk_token，没有就用〔没有时〕
    await fuNewBlock(tester, '记着的令牌', '没有时');
    final f2 = lib.doc.functions[1].id;
    await fuDropStmt(tester, '函数', 'block-return', f2, const [], 0);
    await fuDropValue(tester, 'lib:lopi/storage', 'expr-lib:lopi/storage#get', f2, [lcStep(0)], 'value');
    await fuInline(tester, fuArg(tester, f2, [lcStep(0)], 'value', via: const ['key']), 'tk_token');
    await fuMoveValue(tester, fuChip(tester, f2, 0), f2, [lcStep(0)], 'value', via: const ['orElse']);
    expect(fuErrors(tester), isEmpty);
    await _shot(tester, '3-lib-canvas');

    // 5 更多 › 这个库：两块都公开，各写一句用的时候念的话
    await fuMore(tester, 'lib-info', button: 'be-more');
    await fuTap(tester, 'be-lib-def-$f1');
    await fuTap(tester, 'be-lib-def-public');
    await fuTap(tester, 'be-lib-def-look');
    await fuType(tester, '记住令牌 {令牌}');
    await fuTap(tester, 'be-sheet-done');
    await fuTap(tester, 'be-lib-def-$f2');
    await fuTap(tester, 'be-lib-def-public');
    await fuTap(tester, 'be-lib-def-look');
    await fuType(tester, '记着的令牌，没有就用 {没有时}');
    await _shot(tester, '4-lib-public');
    await fuTap(tester, 'be-sheet-done');
    await fuTap(tester, 'be-sheet-done');
    expect(beLibFiles(lib.doc).problems, isEmpty);
    final blocksJson = File(a.guard.resolve('blocks/$_lib/blocks.json'));

    // 6 回页面逻辑 › 更多 › 积木库 › 这个库 › 导出成一个文件
    await tester.binding.handlePopRoute();
    await settle(tester, rounds: 4);
    expect(identical(fuHost(tester), pageA), isTrue, reason: '回到页面逻辑页');
    await fuUntil(tester, () => blocksJson.existsSync() && blocksJson.readAsStringSync().contains('没有时'), '离开库画布时把最后的改动写进库文件');
    await fuMore(tester, 'libs');
    await fuUntil(tester, () => fk('be-lib-$_lib').evaluate().isNotEmpty, '积木库面板里有新建的库');
    await fuTap(tester, 'be-lib-$_lib');
    await fuTap(tester, 'be-lib-export');
    await fuUntil(tester, () => fk('be-lib-note').evaluate().isNotEmpty, '导出完说一声');
    await _shot(tester, '5-lib-exported');
    final exports = Directory(a.guard.resolve('exports'));
    late Uint8List pack;
    late String packName;
    await tester.runAsync(() async {
      final packs = exports.listSync().whereType<File>().where((f) => f.path.endsWith('.lopilib')).toList();
      expect(packs, hasLength(1));
      packName = p.basename(packs.single.path);
      pack = await packs.single.readAsBytes();
    });
    await fuCloseSheets(tester, 'be-libs');

    // ———— 项目乙：另一份页面文档 ————
    // 先把项目甲的界面整个撤掉（不撤的话新页面盖不到旧的页面逻辑页上面）。
    await tester.pumpWidget(const SizedBox.shrink());
    await settle(tester, rounds: 3);
    final b = await fuOpen(
      tester,
      frontPage([inp('in1'), btn('b1', '记住'), btn('b2', '看'), txt('t1')], [], frontDoc()),
      before: (session) async {
        final f = File(session.guard.resolve('exports/$packName'));
        await f.parent.create(recursive: true);
        await f.writeAsBytes(pack);
      },
    );
    final page = fuHost(tester);
    expect(identical(page, pageA), isFalse);
    expect(File(b.guard.resolve('blocks/$_lib/lib.json')).existsSync(), isFalse, reason: '项目乙里一开始没有这个库');

    // 7 更多 › 积木库 › 从文件导入：先看预览（给谁用、要靠“本地保存”），再点导入
    await fuMore(tester, 'libs');
    await fuUntil(tester, () => fk('be-lib-import').evaluate().isNotEmpty, '积木库面板读完项目里的库');
    await fuTap(tester, 'be-lib-import');
    // 工作区里只有这一个库文件：不用挑，直接开预览（有两个以上才问“导入哪个文件”）。
    await fuUntil(tester, () => fk('be-lib-import-sheet').evaluate().isNotEmpty, '打开预览');
    expect(find.text(_lib), findsWidgets);
    expect(find.textContaining('本地保存'), findsWidgets, reason: '预览里说它要靠哪个自带库');
    await _shot(tester, '6-import-preview');
    await fuTap(tester, 'be-lib-import-go');
    await fuUntil(tester, () => fk('be-lib-$_lib').evaluate().isNotEmpty, '导入完库在清单里');
    await fuCloseSheets(tester, 'be-libs');

    // 8 先把它靠的“本地保存”用上，再把这个库用上
    await _useStorage(tester, button: 'lf-more');
    await fuMore(tester, 'libs');
    await fuUntil(tester, () => fk('be-lib-$_lib').evaluate().isNotEmpty, '积木库面板里有导入的库');
    await fuTap(tester, 'be-lib-$_lib');
    await fuTap(tester, 'be-lib-use');
    await fuUntil(tester, () => page.doc.use(_lib) != null, '用上这个库');
    await _shot(tester, '7-lib-used');
    await fuCloseSheets(tester, 'be-libs');
    final cat = page.categories.firstWhere((c) => c.id == 'lib:$_lib');
    final exprs = [...cat.exprs, for (final g in cat.groups) ...g.exprs];
    final blocks = [...cat.blocks, for (final g in cat.groups) ...g.blocks];
    expect((exprs.length, blocks.length), (1, 1), reason: '一块是值，一块是语句');

    // 9 点“记住”：记住令牌〔abc〕
    await fuDropHat(tester, 'lib:lopi/page:事件', 'hat-libhat:lib:lopi/page#onClick', const Offset(40, 40));
    final h1 = page.doc.hats.last.id;
    await fuShow(tester, h1);
    await fuPick(tester, fuHatSlot(tester, h1, 'node'), 'b1');
    await fuDropStmt(tester, 'lib:$_lib', 'block-${blocks.single}', h1, const [], 0);
    await fuInline(tester, fuArg(tester, h1, [lcStep(0)], '令牌'), 'abc');

    // 10 点“看”：把 t1 的文字改成 记着的令牌，没有就用〔无〕
    await fuDropHat(tester, 'lib:lopi/page:事件', 'hat-libhat:lib:lopi/page#onClick', const Offset(40, 300));
    final h2 = page.doc.hats.last.id;
    await fuShow(tester, h2);
    await fuPick(tester, fuHatSlot(tester, h2, 'node'), 'b2');
    await fuDropStmt(tester, 'lib:lopi/page:控件', 'block-lib:lopi/page#propSet', h2, const [], 0);
    await fuPick(tester, fuArg(tester, h2, [lcStep(0)], 'node'), 't1');
    await fuPick(tester, fuArg(tester, h2, [lcStep(0)], 'prop'), 'text');
    await fuDropValue(tester, 'lib:$_lib', 'expr-${exprs.single}', h2, [lcStep(0)], 'value');
    await fuInline(tester, fuArg(tester, h2, [lcStep(0)], 'value', via: const ['没有时']), '无');
    await _shot(tester, '8-page-canvas');
    expect(fuErrors(tester), isEmpty);

    // 11 存盘 → 三种网页真编译 → 真点：先看是“无”，记住以后再看是 abc，浏览器的本地存储里真有这一项
    final saved = await fuSavedAndRun(tester, b, [
      click('b2'),
      textIs('t1', '无'),
      click('b1'),
      click('b2'),
      textIs('t1', 'abc'),
      {'op': 'stored', 'key': 'tk_token', 'is': '"abc"'},
    ]);
    expect(saved.logic.uses.map((u) => u['id']), containsAll(['lopi/storage', _lib]));
  });
}
