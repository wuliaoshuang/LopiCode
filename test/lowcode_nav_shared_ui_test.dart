// 底部导航跨页真共用的界面（第四轮 B1；390×844）：改成共用、在一页上改别的页跟着变、这一页不显示 / 再显示、
// 当前项只读、取消共用、新放的导航栏、四种导出按共用的一份出。
//   LOPI_SHOTS=1 LOPI_SHOT_DIR=<目录> flutter test --no-pub test/lowcode_nav_shared_ui_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/lowcode/export_dart.dart';
import 'package:lopicode/lowcode/export_pages.dart';
import 'package:lopicode/lowcode/export_react.dart';
import 'package:lopicode/lowcode/export_vue.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/model_v3_components.dart';
import 'package:lopicode/lowcode/nav_shared.dart';
import 'package:material_ui/material_ui.dart';

import 'support/harness.dart';
import 'support/lowcode_builder.dart';
import 'support/pages_sample.dart';

final String shotDir = Platform.environment['LOPI_SHOT_DIR'] ?? '.tmp/editor-r4b1-shots';

Future<void> shot(WidgetTester tester, String name) => lbShot(tester, shotDir, name);

Future<void> tap(WidgetTester tester, Finder f) async {
  expect(f, findsWidgets, reason: '要点的东西不在界面上');
  await tester.tap(f.first, warnIfMissed: false);
  await tester.pumpAndSettle();
  await settle(tester, rounds: 2);
}

Future<void> back(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
  await settle(tester, rounds: 2);
}

Future<void> goPage(WidgetTester tester, String id) async {
  await tap(tester, lbKey('lc-pages-open'));
  await tap(tester, lbKey('lc-page-row-$id'));
}

LcNode navOf(LcDocument d, String id) => lcNavsIn(d.pageById(id)!.root).first;

void main() {
  setUpAll(() async => lbFontsLoaded = await loadRealFonts());

  testWidgets('改成共用（各页一样：一个确认框）→ 在第二页改名字、加一项，三页都变；当前项不能点；存盘只有一份', (tester) async {
    final session = await lbOpen(tester, doc: pagesSample());
    await tap(tester, lbNode('nav'));
    await lbOpenCommon(tester);
    await lbTapShown(tester, lbKey('lc-nav-share'));
    expect(find.textContaining('不用再同步'), findsOneWidget);
    expect(find.textContaining('会换成共用的'), findsOneWidget);
    await shot(tester, 'navshare-01-confirm');
    await tap(tester, find.widgetWithText(TextButton, '改成共用'));
    expect(find.text('已改成共用：3 个页面在显示这一条。'), findsOneWidget);
    lbHintAbove(tester, '已改成共用：3 个页面'); // 第四轮 B8：这句提示看得见、没被挡、在工具条上面
    await lbShow(tester, lbKey('lc-nav-shared'));
    expect(find.textContaining('各页共用 · 3 个页面在显示'), findsOneWidget);
    await shot(tester, 'navshare-02-shared-block');
    // 当前项只是给看
    expect(tester.widget<IconButton>(lbKey('lc-items-current-1')).onPressed, isNull);
    await back(tester);

    await goPage(tester, 'p2');
    await tap(tester, lbNode('nav'));
    await lbOpenCommon(tester);
    await lbShow(tester, lbKey('lc-items-label-0'));
    await tester.enterText(lbKey('lc-items-label-0'), '主页');
    await tester.pumpAndSettle();
    await lbTapShown(tester, lbKey('lc-items-add'));
    await back(tester);
    final saved = await lbSaved(tester, session);
    for (final id in ['p1', 'p2', 'p3']) {
      final n = navOf(saved, id);
      expect(lcObjects(n, 'items').first['label'], '主页', reason: id);
      expect(lcObjects(n, 'items').length, 4, reason: id);
    }
    expect(
      [
        for (final id in ['p1', 'p2', 'p3']) navOf(saved, id).props['current'],
      ],
      [0, 1, 2],
    );
    late String text;
    await tester.runAsync(() async => text = File(session.guard.resolve(kLowcodePageFile)).readAsStringSync());
    expect('主页'.allMatches(text).length, 1, reason: '文件里导航项只写在最外层那一份里');

    // 换回首页：画布上的导航已经是新名字（没点过同步）
    await goPage(tester, 'p1');
    expect(find.descendant(of: lbNode('nav'), matching: find.text('主页')), findsOneWidget);
    await shot(tester, 'navshare-03-other-page-follows');
    expect(tester.takeException(), isNull);
  });

  testWidgets('这一页不显示 → 页面面板里写着、能再显示；取消共用后各改各的', (tester) async {
    final doc = pagesSample();
    lcShareNav(doc, 'p1');
    final session = await lbOpen(tester, doc: doc);
    await tap(tester, lbNode('nav'));
    await lbOpenCommon(tester);
    await lbTapShown(tester, lbKey('lc-nav-hide-here'));
    expect(find.textContaining('不显示底部导航了'), findsOneWidget);
    lbHintAbove(tester, '不显示底部导航了'); // 第四轮 B8：这句提示看得见、没被挡、在工具条上面
    expect(lbNode('nav'), findsNothing);
    var saved = await lbSaved(tester, session);
    expect(lcPageShowsSharedNav(saved.pageById('p1')!), isFalse);
    expect(lcPageShowsSharedNav(saved.pageById('p2')!), isTrue);
    await back(tester);

    await tap(tester, lbKey('lc-pages-open'));
    expect(find.textContaining('· 不显示底部导航'), findsOneWidget);
    await shot(tester, 'navshare-04-pages-sheet');
    await tap(tester, lbKey('lc-page-menu-p1'));
    await shot(tester, 'navshare-05-page-menu');
    await tap(tester, find.widgetWithText(PopupMenuItem<String>, '这一页显示底部导航'));
    await back(tester);
    saved = await lbSaved(tester, session);
    expect(lcPageShowsSharedNav(saved.pageById('p1')!), isTrue);
    expect(navOf(saved, 'p1').props['current'], 0);

    // 取消共用
    final navId = navOf(saved, 'p1').id;
    await tap(tester, lbNode(navId));
    await lbOpenCommon(tester);
    await lbTapShown(tester, lbKey('lc-nav-unshare'));
    await shot(tester, 'navshare-06-unshare-confirm');
    await tap(tester, find.widgetWithText(TextButton, '取消共用'));
    lbHintAbove(tester, '已取消共用。'); // 第四轮 B8：这句提示看得见、没被挡、在工具条上面
    await lbShow(tester, lbKey('lc-nav-share'));
    expect(tester.widget<IconButton>(lbKey('lc-items-current-1')).onPressed, isNotNull);
    await lbShow(tester, lbKey('lc-items-label-0'));
    await tester.enterText(lbKey('lc-items-label-0'), '只有首页改了');
    await tester.pumpAndSettle();
    await back(tester);
    saved = await lbSaved(tester, session);
    expect(saved.sharedNav, isNull);
    expect(lcObjects(navOf(saved, 'p1'), 'items').first['label'], '只有首页改了');
    expect(lcObjects(navOf(saved, 'p2'), 'items').first['label'], '首页');
    expect(tester.takeException(), isNull);
  });

  testWidgets('共用的导航：把一项指到还没显示它的页，那一页顺手加上；撤销一次都回去', (tester) async {
    final doc = pagesSample();
    lcShareNav(doc, 'p1');
    final p4 = doc.addPage('购物车')!;
    final session = await lbOpen(tester, doc: doc);
    await tap(tester, lbNode('nav'));
    await lbOpenCommon(tester);
    await lbTapShown(tester, lbKey('lc-items-page-1'));
    await tap(tester, lbKey('lc-items-page-pick-$p4'));
    expect(find.text('「购物车」也显示这条导航了。'), findsOneWidget);
    lbHintAbove(tester, '也显示这条导航了'); // 第四轮 B8：这句提示看得见、没被挡、在工具条上面
    var saved = await lbSaved(tester, session);
    expect(navOf(saved, p4).props['current'], 1);
    await back(tester);
    await tap(tester, find.byTooltip('撤销'));
    saved = await lbSaved(tester, session);
    expect(lcPageShowsSharedNav(saved.pageById(p4)!), isFalse);
    expect(lcNavItemPageOf(navOf(saved, 'p1'), 1), 'p2');
  });

  test('四种导出按共用的一份出：改完以后每一页导出的导航项都一样、各页亮各自那一项', () {
    final doc = pagesSample();
    lcShareNav(doc, 'p1');
    final nav = navOf(doc, 'p1');
    final items = [for (final m in lcObjects(nav, 'items')) Map<String, dynamic>.of(m)]..[1]['label'] = '共用改的名';
    nav.props['items'] = items;
    final htmls = [for (final f in exportHtmlPages(doc)) f.files.html];
    expect(htmls.length, 3);
    for (final h in htmls) {
      expect(h.contains('共用改的名'), isTrue);
      expect('aria-current="page"'.allMatches(h).length, 1);
    }
    for (final ex in [exportVue(doc), exportReact(doc)]) {
      final pages = [
        for (final f in ex.files)
          if (f.content.contains('共用改的名')) f,
      ];
      // 第四轮 B3 起：Vue / React 里共用的导航抽成一个公共部件文件，改过的名字只写在那一个文件里；三页都引用它、各亮各的。
      expect([for (final f in pages) f.path.replaceAll(RegExp(r'\.(vue|jsx)$'), '')], ['components/LcBottomNav'], reason: '改过的名字只该在公共部件里');
      final refs = [
        for (final f in ex.files)
          if (f.content.contains('<LcBottomNav ')) RegExp(r'current[=:{"]+(\d)').firstMatch(f.content.substring(f.content.indexOf('<LcBottomNav ')))?[1],
      ];
      expect(refs, ['0', '1', '2'], reason: '三页各引用一次、各亮各自那一项');
    }
    final dart = exportDart(doc);
    expect('共用改的名'.allMatches(dart).length, 3);
    expect(RegExp(r'selectedIndex: (\d)').allMatches(dart).map((m) => m[1]).toList(), ['0', '1', '2']);
  });
}

String? lcNavItemPageOf(LcNode nav, int i) => lcObjects(nav, 'items')[i]['page'] as String?;
