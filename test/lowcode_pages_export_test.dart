// 第 4 期·多页面：四种导出怎么跳页（设计见 docs/blocks-v5-parts/E-editor-components.md §10.6）。
// Vue / React 的真编译在 dev_webdev_compile_test.dart；这里看文件有哪些、跳页那几句怎么写、Flutter 真的能跳。
import 'dart:io';

// 导出的页面用的是 Flutter 自带的那套 Material（别人的工程里没有我们的 material_ui）：这里也得用它来装。
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/agent/agent_tools.dart';
import 'package:lopicode/core/path_guard.dart';
import 'package:lopicode/lowcode/export_dart.dart';
import 'package:lopicode/lowcode/export_html.dart';
import 'package:lopicode/lowcode/export_pages.dart';
import 'package:lopicode/lowcode/export_react.dart';
import 'package:lopicode/lowcode/export_vue.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:path/path.dart' as p;

import 'generated/pages_page.dart';
import 'support/html_check.dart';
import 'support/pages_sample.dart';
import 'support/v3_components_sample.dart';

void main() {
  group('只有一页的项目', () {
    test('底部导航项带着 page 也不导出点击（没有可去的地方）：和多页面之前一个字不差', () {
      // 带底部导航的首页样例里，每一项都没有 page；这里给它们填上“自己这页”和“不存在的页”。
      final json = v3HomePage().toJson();
      String patch(String s) => s.replaceFirst('"label":"首页"', '"label":"首页","page":"p1"').replaceFirst('"label":"我的"', '"label":"我的","page":"nope"');
      final before = v3HomePage();
      final after = LcDocument.parse(patch(before.encode().replaceAll(RegExp(r'\s+(?=")|(?<=:)\s+'), '')));
      expect(after.encode(), isNot(before.encode()), reason: '补丁没打上：${json.keys}');
      expect(exportHtml(after).html, exportHtml(before).html);
      expect(exportVue(after).files.map((f) => f.content).join(), exportVue(before).files.map((f) => f.content).join());
      expect(exportReact(after).files.map((f) => f.content).join(), exportReact(before).files.map((f) => f.content).join());
      expect(exportDart(after), exportDart(before));
      expect(exportVue(after).files.map((f) => f.path), isNot(contains('$kLcShellName.vue')));
    });
  });

  group('普通网页', () {
    test('每页三个文件：首页还是 index.html / style.css / logic.js，别的页是 page-<id>.*', () {
      final pages = exportHtmlPages(pagesSample());
      expect([for (final x in pages) '${x.htmlName} ${x.cssName} ${x.jsName}'], ['index.html style.css logic.js', 'page-p2.html page-p2.css page-p2.js', 'page-p3.html page-p3.css page-p3.js']);
      for (final x in pages) {
        expect(htmlProblems(x.files.html), isEmpty, reason: x.htmlName);
        expect(x.files.html, contains('<link rel="stylesheet" href="${x.cssName}">'));
        expect(x.files.html, contains('<script src="${x.jsName}" defer></script>'));
        expect(x.logicErrors, 0);
      }
      expect(pages[1].files.html, contains('<title>商品列表</title>'));
    });

    test('导出各页的过程不改文档，也不会把“当前在编辑哪页”弄丢', () {
      final doc = pagesSample()..openPage('p3');
      final before = doc.encode();
      exportHtmlPages(doc);
      exportDart(doc);
      exportVue(doc);
      exportReact(doc);
      expect(doc.page.id, 'p3');
      expect(doc.encode(), before);
    });

    test('底部导航：去别的页的项点了换地址，当前这页的那一项没有点击', () {
      final pages = exportHtmlPages(pagesSample());
      final home = pages[0].files.html, list = pages[1].files.html;
      expect("onclick=\"event.view.location.href = 'page-p2.html'\"".allMatches(home).length, 1);
      expect("onclick=\"event.view.location.href = 'page-p3.html'\"".allMatches(home).length, 1);
      expect(home, isNot(contains("location.href = 'index.html'")));
      expect(list, contains("onclick=\"event.view.location.href = 'index.html'\""));
      expect(list, isNot(contains("'page-p2.html'")));
    });

    test('“去页面”积木：翻成换地址；页面删掉了的那一块跳过、脚本照样是合法的', () {
      final pages = exportHtmlPages(pagesSample());
      expect(pages[0].files.js, contains('location.href = "page-p2.html";'));
      expect(pages[0].files.js, contains('location.href = "page-p3.html";'));
      expect(pages[1].files.js, contains('location.href = "index.html";'));
      final doc = pagesSample()..removePage('p3');
      final js = exportHtml(doc).js;
      expect(js, contains('要去的页面已经不在了'));
      expect(js, isNot(contains('page-p3')));
    });

    test('换了首页：文件名跟着换（新首页是 index，原来的首页变成 page-p1）', () {
      final doc = pagesSample()..setHomePage('p3');
      final pages = exportHtmlPages(doc);
      expect([for (final x in pages) x.htmlName], ['index.html', 'page-p1.html', 'page-p2.html']);
      expect(pages[0].files.html, contains('<title>Me</title>'));
      expect(pages[1].files.js, contains('location.href = "index.html";'), reason: '原首页里“去我的”现在去的是 index');
    });
  });

  group('Vue 3 / React', () {
    test('文件：一个外壳 + 每页一个 + 共用的组件各一份；页名不撞（中文名转不出英文的也不撞）', () {
      final vue = exportVue(pagesSample()), react = exportReact(pagesSample());
      expect(vue.files.map((f) => f.path), ['LcApp.vue', 'Home.vue', 'LcPage.vue', 'Me.vue', 'components/Card.vue']);
      expect(react.files.map((f) => f.path), ['LcApp.jsx', 'Home.jsx', 'Home.css', 'LcPage.jsx', 'LcPage.css', 'Me.jsx', 'Me.css', 'lc-base.css', 'components/Card.jsx', 'components/Card.css']);
      for (final e in [vue, react]) {
        expect(e.files.every((f) => f.formatProblem == null), isTrue, reason: [for (final f in e.files) '${f.path}: ${f.formatProblem}'].join('\n'));
        expect(e.notes, contains(kNotePages));
      }
      // 两页都叫不出英文名：第二个加数字。
      final doc = pagesSample()..renamePage('p3', '我的');
      expect(exportVue(doc).files.map((f) => f.path).take(4), ['LcApp.vue', 'Home.vue', 'LcPage.vue', 'LcPage2.vue']);
      // 页面和组件、外壳重名也不撞。
      final clash = pagesSample()
        ..renamePage('p2', 'Card')
        ..renamePage('p3', 'Lc App');
      expect(exportReact(clash).files.map((f) => f.path).where((s) => s.endsWith('.jsx')), ['LcApp.jsx', 'Home.jsx', 'Card.jsx', 'LcApp2.jsx', 'components/Card2.jsx']);
    });

    test('外壳：看地址栏里 #/ 后面那段；没有这一页就是首页；服务端渲染时不碰地址栏', () {
      final vue = exportVue(pagesSample()).file('LcApp.vue')!.content, react = exportReact(pagesSample()).file('LcApp.jsx')!.content;
      for (final s in [vue, react]) {
        expect(s, contains('p1: Home,'));
        expect(s, contains('p2: LcPage,'));
        expect(s, contains('const lcHome = "p1";'));
        expect(s, contains('typeof location === "undefined"'));
        expect(s, contains('"hashchange"'));
      }
      expect(vue, contains('<component :is="lcPages[lcCurrent]" :key="lcCurrent" />'));
      expect(react, contains('export default function LcApp()'));
    });

    test('跳页：积木和底部导航都改 location.hash；当前这页的导航项没有点击', () {
      final vue = exportVue(pagesSample()), react = exportReact(pagesSample());
      final vHome = vue.file('Home.vue')!.content, rHome = react.file('Home.jsx')!.content;
      expect(vHome, contains('location.hash = "#/p2";'));
      expect(vHome, contains("@click=\"\$event.view.location.hash = '#/p3'\""));
      expect(vHome, isNot(contains("'#/p1'")));
      expect(rHome, contains('location.hash = "#/p2";'));
      expect(rHome, contains("onClick={(event) => event.view.location.hash = '#/p3'}"));
      expect(rHome, isNot(contains("'#/p1'")));
      expect(vue.file('Me.vue')!.content, contains('location.hash = "#/p1";'));
    });
  });

  group('存盘时一起导出的网页文件', () {
    late Directory tmp;
    late PathGuard guard;
    setUp(() {
      tmp = Directory.systemTemp.createTempSync('lc_pages_');
      guard = PathGuard(p.join(tmp.path, 'proj'));
      Directory(guard.root).createSync(recursive: true);
    });
    tearDown(() => tmp.deleteSync(recursive: true));

    Set<String> names() => {for (final f in Directory(guard.root).listSync()) p.basename(f.path)};

    test('每页的文件都写出来；删了页 / 换了首页以后，没人要的 page-* 被清掉，用户自己的同名文件不碰', () async {
      final doc = pagesSample();
      await saveLowcodePage(guard, doc);
      expect(names(), {'page.lc.json', 'index.html', 'style.css', 'logic.js', 'page-p2.html', 'page-p2.css', 'page-p2.js', 'page-p3.html', 'page-p3.css', 'page-p3.js'});
      expect(LcDocument.parse(File(guard.resolve('page.lc.json')).readAsStringSync()).encode(), doc.encode());
      expect(htmlProblems(File(guard.resolve('page-p2.html')).readAsStringSync()), isEmpty);

      // 用户自己写的、名字碰巧像的文件。
      File(guard.resolve('page-mine.html')).writeAsStringSync('<html>我自己写的</html>');
      File(guard.resolve('page-mine.css')).writeAsStringSync('body { color: red }');
      File(guard.resolve('page-mine.js')).writeAsStringSync('console.log(1)');

      doc.removePage('p3');
      await saveLowcodePage(guard, doc);
      expect(names(), {'page.lc.json', 'index.html', 'style.css', 'logic.js', 'page-p2.html', 'page-p2.css', 'page-p2.js', 'page-mine.html', 'page-mine.css', 'page-mine.js'});

      // 换首页：原来的首页变成 page-p1.*，原来的 page-p2.* 没人要了。
      // 原首页里还有两块积木指着已经删掉的“我的”——逻辑有错误的页不导出脚本，所以没有 page-p1.js。
      doc.setHomePage('p2');
      await saveLowcodePage(guard, doc);
      expect(names(), {'page.lc.json', 'index.html', 'style.css', 'logic.js', 'page-p1.html', 'page-p1.css', 'page-mine.html', 'page-mine.css', 'page-mine.js'});
      expect(File(guard.resolve('index.html')).readAsStringSync(), contains('商品列表'));
      expect(File(guard.resolve('logic.js')).readAsStringSync(), allOf(contains('// 页面：p2'), contains('location.href = "page-p1.html";')));

      // 删到只剩一页：和单页面项目一样，只有那四个文件（加上用户自己的）。
      doc.removePage('p1');
      await saveLowcodePage(guard, doc);
      expect(names(), {'page.lc.json', 'index.html', 'style.css', 'logic.js', 'page-mine.html', 'page-mine.css', 'page-mine.js'});
      expect(File(guard.resolve('page-mine.html')).readAsStringSync(), '<html>我自己写的</html>');
    });

    test('某一页的逻辑有错误：只有那一页的脚本不更新，别的页照常', () async {
      final doc = pagesSample();
      await saveLowcodePage(guard, doc);
      final oldP2 = File(guard.resolve('page-p2.js')).readAsStringSync();
      final oldHome = File(guard.resolve('logic.js')).readAsStringSync();
      expect(oldHome.split('\n')[1], '// 页面：p1');
      doc.pageById('p2')!.logic.handlers.single.body.single.args['page'] = '';
      doc.pageById('p3')!.logic.handlers.clear();
      doc.pageById('p1')!.logic.handlers.first.body.single.args['page'] = '';
      await saveLowcodePage(guard, doc);
      expect(File(guard.resolve('page-p2.js')).readAsStringSync(), oldP2, reason: '有错误的那页：上一次导出的原样留着');
      expect(File(guard.resolve('logic.js')).readAsStringSync(), oldHome, reason: '首页有错误：也是留着自己上一次的');
      expect(File(guard.resolve('page-p3.js')).existsSync(), isFalse, reason: '逻辑删光的那页：脚本跟着删');
      expect(File(guard.resolve('page-p3.html')).readAsStringSync(), isNot(contains('<script')));
    });

    test('换了首页、新首页的逻辑又有错误：上一个首页留下的 logic.js 不能留给它用', () async {
      final doc = pagesSample();
      await saveLowcodePage(guard, doc);
      doc.pageById('p2')!.logic.handlers.single.body.single.args['page'] = '';
      doc.setHomePage('p2');
      await saveLowcodePage(guard, doc);
      expect(File(guard.resolve('logic.js')).existsSync(), isFalse, reason: '那份是“Home”那页的逻辑');
      expect(File(guard.resolve('page-p1.js')).readAsStringSync(), contains('location.href = "page-p3.html";'));
      // 单页面时导出的脚本没有“哪一页”那行：加了第二页、首页有错误时照旧留着。
      final one = LcDocument.parse(pagesSample().encode());
      one
        ..removePage('p2')
        ..removePage('p3')
        ..logic.handlers.removeRange(0, 2);
      one.logic.handlers.single.body.clear();
      await saveLowcodePage(guard, one);
      final single = File(guard.resolve('logic.js')).readAsStringSync();
      expect(single, isNot(contains('// 页面：')));
      one.addPage();
      one.logic.handlers.single.body.add(LcBlock(op: kLcGoPageOp, args: {'page': ''}));
      await saveLowcodePage(guard, one);
      expect(File(guard.resolve('logic.js')).readAsStringSync(), single);
    });
  });

  group('Flutter', () {
    test('检入的样本和导出器当前的输出一致；三页三个类，中文名的那页不和别的撞', () {
      final code = exportDart(pagesSample(), className: 'PagesHomePage');
      expect(File('test/generated/pages_page.dart').readAsStringSync(), code, reason: '导出器改了：运行 dart run tool/gen_sample_export.dart 重新生成');
      expect(RegExp(r'^class (\w+) extends StatelessWidget', multiLine: true).allMatches(code).map((m) => m[1]), ['PagesHomePage', 'LowcodePage', 'MePage']);
      expect(code, contains('void _lcGoTo(BuildContext context, Widget page)'));
      // 写在“如果”里面的“去页面”不是快捷操作：Flutter 这一份不导出积木逻辑，那个按钮还是空的。
      expect('onPressed: () {}'.allMatches(code).length, 1);
    });

    testWidgets('真的能跳：按钮和行里的文字是叠一页上去（能返回），底部导航是换一页', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(home: PagesHomePage()));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('欢迎'), findsOneWidget);

      await tester.tap(find.text('去看商品'));
      await tester.pumpAndSettle();
      expect(find.byType(LowcodePage), findsOneWidget);
      expect(find.text('回首页'), findsOneWidget);
      // 导航栏的返回：回到首页。
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(LowcodePage), findsNothing);
      expect(find.text('欢迎'), findsOneWidget);

      // 行里的一段文字（外面包着 Flexible）也能点。
      await tester.tap(find.text('我的资料'));
      await tester.pumpAndSettle();
      expect(find.byType(MePage), findsOneWidget);
      expect(tester.takeException(), isNull);

      // 底部导航：换成另一页，不往上叠；当前这页的那一项点了不动。
      await tester.tap(find.text('商品'));
      await tester.pumpAndSettle();
      expect(find.byType(LowcodePage), findsOneWidget);
      expect(find.byType(MePage), findsNothing);
      await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('商品')));
      await tester.pumpAndSettle();
      expect(find.byType(LowcodePage), findsOneWidget);
      // 列表项上的“去页面”。
      await tester.tap(find.text('回首页'));
      await tester.pumpAndSettle();
      expect(find.text('欢迎'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
