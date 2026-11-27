// 第 4 期·多页面的界面（390×844）：顶栏的“页面”按钮、页面面板（换页、新建、改名、复制、设为首页、排序、删除）、
// 导航项的“点了去”和“改成各页共用”（原来是“同步到其它页面”）、事件页的“点击时去页面”、跨页撤销。
// 模型和导出在 lowcode_pages_test.dart / lowcode_pages_export_test.dart。
//   LOPI_SHOTS=1 LOPI_SHOT_DIR=<目录> flutter test --no-pub test/lowcode_pages_ui_test.dart   # 同时出截图
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/model_v3_components.dart';
import 'package:lopicode/lowcode/nav_sync.dart';
import 'package:lopicode/lowcode/quick_actions.dart';
import 'package:material_ui/material_ui.dart';

import 'support/harness.dart';
import 'support/lowcode_builder.dart';
import 'support/pages_sample.dart';

final String shotDir = Platform.environment['LOPI_SHOT_DIR'] ?? '.tmp/editor-b1-shots';

Future<void> shot(WidgetTester tester, String name) => lbShot(tester, shotDir, name);

Future<void> tap(WidgetTester tester, Finder f) async {
  expect(f, findsWidgets, reason: '要点的东西不在界面上');
  await tester.tap(f.first, warnIfMissed: false);
  await tester.pumpAndSettle();
  await settle(tester, rounds: 2);
}

Future<void> openPages(WidgetTester tester) async {
  await tap(tester, lbKey('lc-pages-open'));
  expect(lbKey('lc-pages-sheet'), findsOneWidget);
}

/// 页面面板里某一页的 ⋮ 菜单点一项。
Future<void> pageMenu(WidgetTester tester, String pageId, String item) async {
  await tap(tester, lbKey('lc-page-menu-$pageId'));
  await tap(tester, find.widgetWithText(PopupMenuItem<String>, item));
}

bool menuEnabled(WidgetTester tester, String item) => tester.widget<PopupMenuItem<String>>(find.widgetWithText(PopupMenuItem<String>, item)).enabled;

Future<void> closeSheet(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
  await settle(tester, rounds: 2);
}

void main() {
  setUpAll(() async => lbFontsLoaded = await loadRealFonts());

  testWidgets('只有一页的项目：顶栏写着“1 页”；改东西存出来还是单页面的样子；新建一页就换过去，文件里多出 pages，网页多出 page-p2.*；撤销回到一页', (tester) async {
    final session = await lbOpen(tester);
    expect(find.descendant(of: lbKey('lc-pages-open'), matching: find.text('1 页')), findsOneWidget);
    expect(find.textContaining('第 1/'), findsNothing, reason: '只有一页时副标题不写第几页');
    await shot(tester, 'pages-01-single-topbar');

    await openPages(tester);
    expect(lbKey('lc-page-row-p1'), findsOneWidget);
    expect(find.textContaining('正在编辑 · 首页'), findsOneWidget);
    await tap(tester, lbKey('lc-page-menu-p1'));
    expect(menuEnabled(tester, '删除'), isFalse, reason: '只剩一页不能删');
    expect(find.widgetWithText(PopupMenuItem<String>, '设为首页'), findsNothing);
    await shot(tester, 'pages-02-single-sheet-menu');
    await closeSheet(tester); // 关菜单
    await tap(tester, lbKey('lc-page-add'));
    expect(find.widgetWithText(TextField, '页面 2'), findsOneWidget, reason: '名字预填“页面 2”');
    await tester.enterText(find.byType(TextField).last, '关于我们');
    await tap(tester, find.widgetWithText(TextButton, '新建'));

    // 建好就换过去了：面板关了，标题是新页的名字，画布是空的。
    expect(lbKey('lc-pages-sheet'), findsNothing);
    expect(find.text('关于我们'), findsOneWidget);
    expect(find.textContaining('第 2/2 页'), findsOneWidget);
    expect(find.descendant(of: lbKey('lc-pages-open'), matching: find.text('2 页')), findsOneWidget);
    expect(lbNode('n5'), findsNothing, reason: '首页的“提交”按钮不在这一页');
    await shot(tester, 'pages-03-new-page-empty');

    final saved = await lbSaved(tester, session);
    expect([for (final p in saved.pages) '${p.id}:${p.title}'], ['p1:我的小站', 'p2:关于我们']);
    late Set<String> names;
    await tester.runAsync(() async => names = {for (final f in Directory(session.guard.root).listSync()) f.uri.pathSegments.last});
    expect(names, containsAll(['index.html', 'style.css', 'page-p2.html', 'page-p2.css']));

    // 撤销“新建页面”：回到首页，文件又是单页面的样子。
    await tap(tester, find.byTooltip('撤销'));
    expect(find.textContaining('第 2/2 页'), findsNothing);
    expect(lbNode('n5'), findsOneWidget);
    final back = await lbSaved(tester, session);
    expect(back.pages.length, 1);
    await tester.runAsync(() async => names = {for (final f in Directory(session.guard.root).listSync()) f.uri.pathSegments.last});
    expect(names.where((n) => n.startsWith('page-')), isEmpty, reason: '没人要的 page-p2.* 清掉了');
  });

  testWidgets('旧的单页面文件：打开不写；改一下再存，没有多出 id / pages，别的字段一个不少', (tester) async {
    final source = File('test/fixtures/lowcode/page-v2.saved-v3.lc.json').readAsStringSync();
    final session = await lbOpen(tester, text: source);
    late String now;
    Future<void> read() => tester.runAsync(() async => now = File(session.guard.resolve(kLowcodePageFile)).readAsStringSync());
    await waitLowcodeSaved(tester);
    await read();
    expect(now, source, reason: '只是打开，不该写文件');
    // 开一下页面面板再关：还是不写。
    await openPages(tester);
    await closeSheet(tester);
    await waitLowcodeSaved(tester);
    await read();
    expect(now, source);
    // 真改一下（⋮ › 修改页面标题）。
    await tap(tester, find.byTooltip('更多'));
    await tap(tester, find.text('修改页面标题'));
    await tester.enterText(find.byType(TextField).last, '改过的标题');
    await tap(tester, find.widgetWithText(TextButton, '保存'));
    final saved = await lbSaved(tester, session);
    await read();
    final expected = LcDocument.parse(source)..title = '改过的标题';
    expect(now, expected.encode());
    expect(now, isNot(contains('"pages"')));
    expect(saved.pages.single.id, kLcFirstPageId);
  });

  testWidgets('三页的项目：面板里三行，正在编辑的那行标着；点一行换页，画布、标题、选中都换；在第二页改的只进第二页', (tester) async {
    final session = await lbOpen(tester, doc: pagesSample());
    expect(find.textContaining('第 1/3 页'), findsOneWidget);
    await shot(tester, 'pages-04-multi-home');
    await tap(tester, lbNode('toList'));
    await openPages(tester);
    for (final id in ['p1', 'p2', 'p3']) {
      expect(lbKey('lc-page-row-$id'), findsOneWidget);
    }
    expect(find.textContaining('正在编辑 · 首页 · '), findsOneWidget);
    expect(find.textContaining('3 串逻辑'), findsOneWidget);
    await shot(tester, 'pages-05-sheet');

    await tap(tester, lbKey('lc-page-row-p2'));
    expect(lbKey('lc-pages-sheet'), findsNothing);
    expect(find.textContaining('第 2/3 页'), findsOneWidget);
    expect(lbNode('item'), findsOneWidget);
    expect(lbNode('toList'), findsNothing);
    expect(find.widgetWithText(FilledButton, '常用'), findsNothing, reason: '换页以后没有选中的组件');
    await shot(tester, 'pages-06-second-page');

    // 只换页：不存盘、不多一步撤销。
    await waitLowcodeSaved(tester);
    late String text;
    await tester.runAsync(() async => text = File(session.guard.resolve(kLowcodePageFile)).readAsStringSync());
    expect(text, pagesSample().encode());

    // 在第二页加一个按钮。
    await lbOpenPalette(tester);
    await tap(tester, lbPaletteItem('button'));
    final saved = await lbSaved(tester, session);
    final was = pagesSample();
    expect(saved.pageById('p1')!.root.toJson(), was.pageById('p1')!.root.toJson());
    expect(saved.pageById('p3')!.root.toJson(), was.pageById('p3')!.root.toJson());
    int count(LcNode n) => n.children.fold(1, (s, c) => s + count(c));
    expect(count(saved.pageById('p2')!.root), count(was.pageById('p2')!.root) + 1);
  });

  testWidgets('一页的 ⋮ 菜单：改名、复制、设为首页、上移下移（只在不是首页的几页之间）、删除（先问，说清楚里面有什么、谁还指着它）', (tester) async {
    final session = await lbOpen(tester, doc: pagesSample());
    await openPages(tester);

    // 上移 / 下移哪些能点。
    await tap(tester, lbKey('lc-page-menu-p1'));
    expect((menuEnabled(tester, '上移'), menuEnabled(tester, '下移')), (false, false), reason: '首页不参加排序');
    await closeSheet(tester);
    await tap(tester, lbKey('lc-page-menu-p2'));
    expect((menuEnabled(tester, '上移'), menuEnabled(tester, '下移')), (false, true), reason: '第 2 页再上移就等于换首页，不让');
    await shot(tester, 'pages-07-row-menu');
    await tap(tester, find.widgetWithText(PopupMenuItem<String>, '下移'));
    expect([for (final p in (await lbSaved(tester, session)).pages) p.id], ['p1', 'p3', 'p2']);

    // 改名。
    await pageMenu(tester, 'p2', '改名');
    await tester.enterText(find.byType(TextField).last, '全部商品');
    await tap(tester, find.widgetWithText(TextButton, '保存'));
    expect(find.descendant(of: lbKey('lc-page-row-p2'), matching: find.text('全部商品')), findsOneWidget);

    // 复制：紧跟在后面，名字加“副本”，人还在原来那页。
    await pageMenu(tester, 'p3', '复制一页');
    expect(find.text('Me 副本'), findsOneWidget);
    var saved = await lbSaved(tester, session);
    expect([for (final p in saved.pages) '${p.id}:${p.title}'], ['p1:Home', 'p3:Me', 'p4:Me 副本', 'p2:全部商品']);
    expect(find.textContaining('正在编辑 · 首页'), findsOneWidget);

    // 设为首页。
    await pageMenu(tester, 'p2', '设为首页');
    saved = await lbSaved(tester, session);
    expect(saved.pages.first.id, 'p2');
    expect(find.descendant(of: lbKey('lc-page-row-p2'), matching: find.textContaining('首页 · ')), findsOneWidget);
    expect(
      find.descendant(of: lbKey('lc-page-row-p1'), matching: find.textContaining('正在编辑 · ')),
      findsOneWidget,
      reason: '换首页不换“正在编辑哪页”',
    );
    await shot(tester, 'pages-08-after-rename-dup-home');

    // 删除“我的”：别的页还有 4 处指着它。
    await pageMenu(tester, 'p3', '删除');
    expect(find.text('删除「Me」'), findsOneWidget);
    expect(find.textContaining('里面的 3 个组件、1 串逻辑会一起删掉'), findsOneWidget);
    expect(find.textContaining('还有 5 处'), findsOneWidget, reason: '首页两块积木 + 首页、商品、副本三条导航栏各一项');
    await shot(tester, 'pages-09-delete-confirm');
    await tap(tester, find.widgetWithText(TextButton, '取消'));
    expect((await lbSaved(tester, session)).pageById('p3'), isNotNull);
    await pageMenu(tester, 'p3', '删除');
    await tap(tester, find.widgetWithText(TextButton, '删除'));
    saved = await lbSaved(tester, session);
    expect([for (final p in saved.pages) p.id], ['p2', 'p1', 'p4']);

    // 删正在编辑的这一页：落到别的页上，画布跟着换。
    await pageMenu(tester, 'p1', '删除');
    await tap(tester, find.widgetWithText(TextButton, '删除'));
    await closeSheet(tester);
    expect(lbNode('toList'), findsNothing);
    expect(find.textContaining('/2 页'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('导航项：每项下面一行“点了去”，能改；指着已经删掉的页面标红；“改成各页共用”各页不一样时先挑以哪一页为准', (tester) async {
    final doc = pagesSample();
    // 第三页的导航栏先弄得不一样，再加一页没有导航栏的。
    final nav3 = doc.pageById('p3')!.root.children.last;
    nav3.props['items'] = [
      {'icon': 'star', 'label': '旧的'},
    ];
    final p4 = doc.addPage('购物车')!;
    final session = await lbOpen(tester, doc: doc);
    await tap(tester, lbNode('nav'));
    await lbOpenCommon(tester);
    await lbShow(tester, lbKey('lc-items-page-2'));
    expect(find.descendant(of: lbKey('lc-items-page-1'), matching: find.text('商品列表')), findsOneWidget);
    await shot(tester, 'pages-10-nav-items');

    // 第 2 项改成去“购物车”。
    await lbTapShown(tester, lbKey('lc-items-page-1'));
    expect(lbKey('lc-items-page-pick-p1'), findsOneWidget);
    expect(find.textContaining('（就是这一页）'), findsOneWidget);
    await shot(tester, 'pages-11-nav-pick-page');
    await tap(tester, lbKey('lc-items-page-pick-$p4'));
    expect(find.descendant(of: lbKey('lc-items-page-1'), matching: find.text('购物车')), findsOneWidget);

    // 改成各页共用（第四轮 B1 起代替“同步到其它页面”）：各页不一样，先挑以哪一页为准。
    expect(lbKey('lc-items-sync-nav'), findsNothing);
    await lbTapShown(tester, lbKey('lc-nav-share'));
    expect(lbKey('lc-nav-share-pick'), findsOneWidget);
    expect(find.textContaining('别的页的导航栏会被换成它'), findsOneWidget);
    await shot(tester, 'pages-12-nav-share-pick');
    await tap(tester, lbKey('lc-nav-share-base-p1'));
    expect(find.text('已改成共用：4 个页面在显示这一条。'), findsOneWidget);
    await shot(tester, 'pages-12b-after-share');
    final saved = await lbSaved(tester, session);
    LcNode navOf(String id) => saved.pageById(id)!.root.children.lastWhere((n) => n.type == 'bottomNav');
    final home = navOf('p1');
    for (final (id, current) in [(p4, 1), ('p3', 2), ('p2', 0)]) {
      expect(saved.pageById(id)!.root.children.map((n) => n.type), contains('bottomNav'), reason: '$id：${saved.encode()}');
      final n = navOf(id);
      expect([for (final m in lcObjects(n, 'items')) '${m['label']}→${lcNavItemPage(m)}'], ['首页→p1', '商品→$p4', '我的→p3'], reason: id);
      expect(n.props['current'], current, reason: '$id 的当前项是指向它自己的那一项（没有哪一项指着它就是第一项）');
      expect(n.props['width'], home.props['width']);
    }
    expect(saved.sharedNav, isNotNull);
    // 改成共用是一条撤销。
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byTooltip('撤销').hitTestable(), findsOneWidget, reason: '那句“已改成共用”的提示不能盖住撤销');
    await tap(tester, find.byTooltip('撤销'));
    final undone = await lbSaved(tester, session);
    expect(lcObjects(undone.pageById('p3')!.root.children.last, 'items').single['label'], '旧的');
    expect(undone.sharedNav, isNull);

    // 指着的页面删掉了：红字。
    await openPages(tester);
    await pageMenu(tester, 'p3', '删除');
    await tap(tester, find.widgetWithText(TextButton, '删除'));
    await closeSheet(tester);
    await tap(tester, lbNode('nav'));
    await lbOpenCommon(tester);
    await lbShow(tester, lbKey('lc-items-page-2'));
    expect(find.descendant(of: lbKey('lc-items-page-2'), matching: find.text('已经删掉的页面')), findsOneWidget);
    await shot(tester, 'pages-13-nav-deleted-page');
  });

  testWidgets('只有一页时：导航项下面没有“点了去”，只有一句灰字说以后可以选；事件页“点击时去页面”写着先加一个页面', (tester) async {
    final doc = pagesSample()
      ..removePage('p2')
      ..removePage('p3');
    for (final m in (doc.root.children.last.props['items'] as List).cast<Map<String, dynamic>>()) {
      m.remove('page');
    }
    doc.logic.handlers.clear();
    await lbOpen(tester, doc: doc);
    await tap(tester, lbNode('nav'));
    await lbOpenCommon(tester);
    await lbShow(tester, lbKey('lc-items-page-hint'));
    expect(lbKey('lc-items-page-0'), findsNothing);
    expect(lbKey('lc-items-sync-nav'), findsNothing);
    await shot(tester, 'pages-14-nav-single-page');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tap(tester, lbNode('toList'));
    await tap(tester, find.widgetWithText(TextButton, '逻辑'));
    await lbShow(tester, lbKey('lc-quick-goPage'));
    expect(find.descendant(of: lbKey('lc-quick-goPage'), matching: find.text('先加一个页面')), findsOneWidget);
    await shot(tester, 'pages-15-quick-single-page');
  });

  testWidgets('事件页“点击时去页面”：选一页，存下来是一块 goPage 积木；再点能换、能不要', (tester) async {
    final session = await lbOpen(tester, doc: pagesSample());
    await tap(tester, lbNode('hello'));
    await tap(tester, find.widgetWithText(TextButton, '逻辑'));
    await lbTapShown(tester, lbKey('lc-quick-goPage'));
    expect(lbKey('lc-quick-page-p1'), findsNothing, reason: '不列自己这一页');
    await shot(tester, 'pages-16-quick-pick');
    await tap(tester, lbKey('lc-quick-page-p3'));
    expect(find.descendant(of: lbKey('lc-quick-goPage'), matching: find.text('Me')), findsOneWidget);
    await shot(tester, 'pages-17-quick-set');
    var saved = await lbSaved(tester, session);
    expect(lcQuickValue(saved, 'hello', kLcGoPageQuick), 'p3');
    expect(saved.logic.handlersFor('hello').single.body.single.op, kLcGoPageOp);
    await lbTapShown(tester, lbKey('lc-quick-goPage'));
    await tap(tester, lbKey('lc-quick-page-none'));
    saved = await lbSaved(tester, session);
    expect(saved.logic.handlersFor('hello'), isEmpty);
  });

  testWidgets('跨页撤销：在第二页改了东西、回到首页点撤销——跟到第二页去，并说一声', (tester) async {
    await lbOpen(tester, doc: pagesSample());
    await openPages(tester);
    await tap(tester, lbKey('lc-page-row-p2'));
    await lbOpenPalette(tester);
    await tap(tester, lbPaletteItem('button'));
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await openPages(tester);
    await tap(tester, lbKey('lc-page-row-p1'));
    expect(find.textContaining('第 1/3 页'), findsOneWidget);
    await tap(tester, find.byTooltip('撤销'));
    expect(find.textContaining('第 2/3 页'), findsOneWidget);
    expect(find.textContaining('已换到「商品列表」'), findsOneWidget);
    await shot(tester, 'pages-18-undo-jumps');
    await tap(tester, find.byTooltip('重做'));
    expect(find.textContaining('第 2/3 页'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
