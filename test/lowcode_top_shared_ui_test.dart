// 顶部导航栏跨页共用的界面（第四轮 B3；390×844）：改成共用、在一页上改样子别的页跟着变、每页自己的标题 / 返回箭头 / 左右按钮、
// 这一页不显示 / 再显示、取消共用、四种导出按共用的一份出。
//   LOPI_SHOTS=1 LOPI_SHOT_DIR=<目录> flutter test --no-pub test/lowcode_top_shared_ui_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/lowcode/export_dart.dart';
import 'package:lopicode/lowcode/export_pages.dart';
import 'package:lopicode/lowcode/export_react.dart';
import 'package:lopicode/lowcode/export_vue.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/top_shared.dart';
import 'package:material_ui/material_ui.dart';

import 'support/harness.dart';
import 'support/lowcode_builder.dart';
import 'support/pages_sample.dart';

final String shotDir = Platform.environment['LOPI_SHOT_DIR'] ?? '.tmp/editor-r4b3-shots';

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

LcNode topOf(LcDocument d, String id) => lcTopsIn(d.pageById(id)!.root).first;

void main() {
  setUpAll(() async => lbFontsLoaded = await loadRealFonts());

  testWidgets('改成共用（确认框写明哪页留着自己的什么）→ 第二页改成居中，首页跟着变；标题各是各的；存盘只有一份', (tester) async {
    final session = await lbOpen(tester, doc: pagesSample());
    await tap(tester, lbNode('bar'));
    await lbOpenCommon(tester);
    await lbTapShown(tester, lbKey('lc-top-share'));
    expect(find.textContaining('「商品列表」的顶栏会换成共用的'), findsOneWidget);
    expect(find.textContaining('「商品列表」留着自己的标题、返回箭头'), findsOneWidget);
    await shot(tester, 'topshare-01-confirm');
    await tap(tester, find.widgetWithText(TextButton, '改成共用'));
    expect(find.text('已改成共用：2 个页面在显示这一条。'), findsOneWidget);
    lbHintAbove(tester, '已改成共用：2 个页面'); // 第四轮 B8：这句提示看得见、没被挡、在工具条上面
    await lbShow(tester, lbKey('lc-top-shared'));
    expect(find.textContaining('各页共用 · 2 个页面在显示'), findsOneWidget);
    expect(tester.widget<Switch>(lbKey('lc-top-own-title')).value, isFalse);
    await shot(tester, 'topshare-02-shared-block');
    await back(tester);

    await goPage(tester, 'p2');
    await tap(tester, lbNode('bar'));
    await lbOpenCommon(tester);
    await lbShow(tester, lbKey('lc-top-own-title'));
    expect(tester.widget<Switch>(lbKey('lc-top-own-title')).value, isTrue);
    expect(tester.widget<Switch>(lbKey('lc-top-own-back')).value, isTrue);
    expect(tester.widget<Switch>(lbKey('lc-top-own-slots')).value, isFalse);
    await lbTapShown(tester, lbKey('lc-common-variant-center'));
    await back(tester);
    final saved = await lbSaved(tester, session);
    expect(topOf(saved, 'p1').props['variant'], 'center');
    expect(topOf(saved, 'p2').props['variant'], 'center');
    expect(topOf(saved, 'p1').props['title'], '首页');
    expect(topOf(saved, 'p2').props['title'], '商品');
    expect(topOf(saved, 'p1').props['back'] == true, isFalse);
    late String text;
    await tester.runAsync(() async => text = File(session.guard.resolve(kLowcodePageFile)).readAsStringSync());
    expect('"center"'.allMatches(text).length, 1, reason: '样子只写在最外层那一份里');

    // 第二页的返回箭头换回共用的（共用的是没有箭头）
    await tap(tester, lbNode('bar'));
    await lbOpenCommon(tester);
    await lbTapShown(tester, lbKey('lc-top-own-back'));
    await back(tester);
    final again = await lbSaved(tester, session);
    expect(topOf(again, 'p2').props['back'] == true, isFalse);
    expect(lcTopOwn(topOf(again, 'p2')), {'title'});
    await goPage(tester, 'p1');
    await shot(tester, 'topshare-03-other-page-follows');
    expect(tester.takeException(), isNull);
  });

  testWidgets('B5：手机上点“改成各页共用”以后，存下来的文件导出 Vue / React 多一个 components/LcTopBar，两页都引用它', (tester) async {
    final session = await lbOpen(tester, doc: pagesSample());
    await tap(tester, lbNode('bar'));
    await lbOpenCommon(tester);
    await lbTapShown(tester, lbKey('lc-top-share'));
    await tap(tester, find.widgetWithText(TextButton, '改成共用'));
    await back(tester);
    final saved = await lbSaved(tester, session);
    for (final (ex, ext, title) in [(exportVue(saved), 'vue', 'title="商品" back'), (exportReact(saved), 'jsx', 'title={"商品"} back')]) {
      final files = {for (final f in ex.files) f.path: f.content};
      expect(files.keys, contains('components/LcTopBar.$ext'));
      expect(files['Home.$ext'], contains('<LcTopBar '));
      expect(files['LcPage.$ext'], contains(title), reason: '“商品”页自己的标题和返回箭头当属性传进去');
      expect(files['Home.$ext'], isNot(contains('<header')));
    }
  });

  testWidgets('这一页不显示 → 页面面板里写着、能再显示；取消共用后各改各的', (tester) async {
    final doc = pagesSample();
    lcShareTop(doc, 'p1');
    final session = await lbOpen(tester, doc: doc);
    await tap(tester, lbNode('bar'));
    await lbOpenCommon(tester);
    await lbTapShown(tester, lbKey('lc-top-hide-here'));
    expect(find.textContaining('不显示顶部导航了'), findsOneWidget);
    lbHintAbove(tester, '不显示顶部导航了'); // 第四轮 B8：这句提示看得见、没被挡、在工具条上面
    expect(lbNode('bar'), findsNothing);
    var saved = await lbSaved(tester, session);
    expect(lcPageShowsSharedTop(saved.pageById('p1')!), isFalse);
    expect(lcPageShowsSharedTop(saved.pageById('p2')!), isTrue);
    await back(tester);

    await tap(tester, lbKey('lc-pages-open'));
    expect(find.textContaining('· 不显示顶部导航'), findsNWidgets(2), reason: '首页刚关掉、第三页本来就没有');
    await shot(tester, 'topshare-04-pages-sheet');
    await tap(tester, lbKey('lc-page-menu-p1'));
    await shot(tester, 'topshare-05-page-menu');
    await tap(tester, find.widgetWithText(PopupMenuItem<String>, '这一页显示顶部导航'));
    await back(tester);
    saved = await lbSaved(tester, session);
    expect(lcPageShowsSharedTop(saved.pageById('p1')!), isTrue);
    expect(saved.pageById('p1')!.root.children.first.type, 'appBar');
    expect(topOf(saved, 'p1').props['title'], 'Home', reason: '再显示时标题先用页面的名字');

    final id = topOf(saved, 'p1').id;
    await tap(tester, lbNode(id));
    await lbOpenCommon(tester);
    await lbTapShown(tester, lbKey('lc-top-unshare'));
    await shot(tester, 'topshare-06-unshare-confirm');
    await tap(tester, find.widgetWithText(TextButton, '取消共用'));
    lbHintAbove(tester, '已取消共用。'); // 第四轮 B8：这句提示看得见、没被挡、在工具条上面
    await lbShow(tester, lbKey('lc-top-share'));
    await lbTapShown(tester, lbKey('lc-common-variant-center'));
    await back(tester);
    saved = await lbSaved(tester, session);
    expect(saved.sharedTop, isNull);
    expect(topOf(saved, 'p1').props['variant'], 'center');
    expect(topOf(saved, 'p2').props['variant'] == 'center', isFalse);
    expect(tester.takeException(), isNull);
  });

  test('四种导出按共用的一份出：样子每页一样，标题各页是各页的', () {
    final doc = pagesSample();
    lcShareTop(doc, 'p1');
    lcSetPageShowsSharedTop(doc, 'p3', true);
    topOf(doc, 'p1').props['bg'] = '#123456';
    final htmls = [for (final f in exportHtmlPages(doc)) f.files];
    expect(htmls.length, 3);
    for (final (i, title) in ['首页', '商品', 'Me'].indexed) {
      expect(htmls[i].html.contains('>$title<'), isTrue, reason: title);
      expect(htmls[i].css.toLowerCase().contains('#123456'), isTrue, reason: title);
    }
    for (final ex in [exportVue(doc), exportReact(doc)]) {
      final all = ex.files.map((f) => f.content).join('\n').toLowerCase();
      expect('#123456'.allMatches(all).length, greaterThanOrEqualTo(3));
    }
    final dart = exportDart(doc);
    expect(RegExp('0xFF123456', caseSensitive: false).allMatches(dart).length, greaterThanOrEqualTo(3));
  });
}
