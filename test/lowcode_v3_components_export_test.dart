// 第 3 期第 2 段的 11 个新组件：四种导出都写出来了、写得对；导出的 Flutter 代码能编译、在 390 宽上能渲染、弹窗打得开。
// Vue / React 的真编译在 test/dev_webdev_compile_test.dart（样本同一份：test/support/v3_components_sample.dart）。
import 'dart:io';

// 导出的代码用的是 package:flutter/material.dart，这里必须用同一套。
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/lowcode/component_ops.dart';
import 'package:lopicode/lowcode/export_dart.dart';
import 'package:lopicode/lowcode/export_html.dart';
import 'package:lopicode/lowcode/export_react.dart';
import 'package:lopicode/lowcode/export_vue.dart';
import 'package:lopicode/lowcode/model.dart';

import 'generated/v3_all_page.dart';
import 'generated/v3_home_page.dart';
import 'generated/v3_login_page.dart';
import 'generated/v3_settings_page.dart';
import 'support/html_check.dart';
import 'support/sample_doc.dart';
import 'support/v3_components_sample.dart';

String _all(LcFrameworkExport e) => e.files.map((f) => f.content).join('\n');

void main() {
  group('网页导出', () {
    final all = exportHtml(v3AllPage());
    final html = all.html, css = all.css;

    test('四个样例页：标签都配对、没有重复的 id / class 冲突，文字里的尖括号引号都转义了', () {
      for (final s in v3ComponentSamples().entries) {
        final e = exportHtml(s.value());
        expect(htmlProblems(e.html), isEmpty, reason: s.key);
        expect(e.css, isNot(contains('undefined')), reason: s.key);
      }
      expect(html, contains('全部 &lt;组件&gt; &amp; "引号"'));
      expect(html, contains('第二行 &lt;/textarea&gt; {{ x }}</textarea>'));
      expect(html, contains('香蕉 &lt;b&gt;'));
    });

    test('图标：外面一层 lc-glyph（不和按钮里的小图标抢 lc-icon），大小写在 svg 上', () {
      expect(html, contains('<span class="lc-glyph n-ic">'));
      expect(html, contains('<svg viewBox="0 0 24 24" width="32" height="32" aria-hidden="true">'));
      expect(html, isNot(contains('class="lc-icon n-ic"')));
      expect(css, contains(':where(.lc-glyph) {'));
    });

    test('多行输入：行数、字数上限、自动长高、必填、禁用；带标签的外面包一层 label', () {
      expect(html, contains('<textarea class="lc-textarea n-ta" rows="2" placeholder="写点什么" data-autogrow="">'));
      expect(html, contains('<label class="lc-field n-taOff-field">'));
      expect(html, contains('<textarea class="lc-textarea n-taOff" rows="3" placeholder="" maxlength="50" required disabled></textarea>'));
      expect(css, contains('.n-taOff-field {'));
      expect(css, contains('field-sizing: content'));
    });

    test('开关、勾选框：都是原生的 checkbox，勾没勾、禁没禁用写在属性上', () {
      expect(html, contains('<input class="lc-switch n-sw" type="checkbox" role="switch" checked>'));
      expect(html, contains('<input class="lc-switch n-swOff" type="checkbox" role="switch" disabled>'));
      expect(html, contains('<label class="lc-checkbox n-cb">'));
      expect(html, contains('<input type="checkbox" checked>'));
    });

    test('单选组：同一组一个 name，选中的那个 checked；没写名字的选项显示它的值', () {
      expect(RegExp(r'name="lc-rd"').allMatches(html).length, 3);
      expect(html, contains('<input type="radio" name="lc-rd" value="b" checked>'));
      expect(html, contains('<span>c</span>'));
      expect(html, contains('data-variant="button" data-direction="column"'));
      expect(RegExp(r'name="lc-rdBtn"[^>]*disabled').allMatches(html).length, 2);
    });

    test('下拉选择：选中的那项 selected；没选时显示占位那一项', () {
      expect(html, contains('<option value="b" selected>'));
      expect(html, contains('<option value="" disabled hidden selected>请选择</option>'));
      expect(html, contains('<select class="lc-select n-selEmpty" disabled>'));
    });

    test('列表行：左右插槽各一层；没写插槽的子组件算在右边；一行的样子不出副标题', () {
      final li = html.substring(html.indexOf('n-li"'), html.indexOf('n-li1"'));
      expect(li.indexOf('lc-slot-left'), lessThan(li.indexOf('lc-item-main')));
      expect(li.indexOf('lc-item-main'), lessThan(li.indexOf('lc-slot-right')));
      expect(li.indexOf('n-liL'), lessThan(li.indexOf('lc-item-main')));
      expect(li.indexOf('n-liR'), greaterThan(li.indexOf('lc-slot-right')));
      expect(li.indexOf('n-liLost'), greaterThan(li.indexOf('lc-slot-right')));
      expect(li, contains('lc-item-sub'));
      expect(li, contains('lc-item-chevron'));
      final one = html.substring(html.indexOf('n-li1"'), html.indexOf('n-tb"'));
      expect(one, isNot(contains('lc-item-sub')));
      expect(one, isNot(contains('lc-slot')));
      expect(one, isNot(contains('lc-item-chevron')));
    });

    test('顶部导航栏：排在页面第一个的贴边（抵掉页面内边距）；不在最上面的不贴', () {
      expect(html, contains('<header class="lc-appBar n-bar" data-variant="center" data-page="">'));
      expect(html, contains('<header class="lc-appBar n-bar2" data-variant="left">'));
      expect(css, contains('.n-bar { margin-left: -12px; margin-right: -12px; margin-top: -12px; }'));
      expect(css, isNot(contains('.n-bar2 { margin-left')));
      expect(html, contains('aria-label="返回"'));
    });

    test('底部导航栏：排在页面最后的贴边、钉在底下；当前项 aria-current；只有图标的样子不出文字', () {
      expect(html, contains('<nav class="lc-bottomNav n-nav" data-variant="iconOnly" data-page="">'));
      expect(css, contains('.n-nav { margin-left: -12px; margin-right: -12px; margin-bottom: -12px; }'));
      expect(RegExp(r'aria-current="page"').allMatches(html).length, 1);
      expect(html, contains('class="lc-nav-item" aria-label="首页"'));
      final home = exportHtml(v3HomePage()).html;
      expect(home, contains('<span>首页</span>'));
      expect(home, contains('<button type="button" class="lc-nav-item" aria-current="page">'));
    });

    test('标签页：每个页签一个按钮一块内容，不是当前的那几块 hidden；子组件进了各自的页签', () {
      expect(RegExp(r'role="tab" ').allMatches(html).length, 3);
      expect(html, contains('role="tab" aria-selected="true" data-tab="b"'));
      expect(html, contains('<div class="lc-tabs-panel" role="tabpanel" data-tab="a" hidden>'));
      expect(html, contains('<div class="lc-tabs-panel" role="tabpanel" data-tab="b">'));
      final b = html.substring(html.indexOf('role="tabpanel" data-tab="b"'), html.indexOf('role="tabpanel" data-tab="c"'));
      expect(b, contains('n-tbB'));
      expect(b, contains('n-tbB2'));
      expect(b, isNot(contains('n-tbA')));
    });

    test('弹窗：一开始不开的先藏着；自带的按钮和点遮罩会关；不许点遮罩关的遮罩上没有动作；自己放了底部按钮就不出自带的', () {
      expect(html, contains('<div class="lc-dialog n-dlg" role="dialog" aria-modal="true" data-variant="alert" style="display: none">'));
      expect(html, contains('<div class="lc-dialog n-dlg2" role="dialog" aria-modal="true" data-variant="confirm">'));
      final dlg = html.substring(html.indexOf('n-dlg"'), html.indexOf('n-dlg2"'));
      expect(dlg, contains('<div class="lc-dialog-scrim"></div>'));
      expect(dlg, isNot(contains('lc-dialog-btn')));
      expect(dlg.indexOf('n-dlgNote'), lessThan(dlg.indexOf('lc-dialog-footer')), reason: '没写插槽的算内容');
      expect(dlg.indexOf('n-dlgOk'), greaterThan(dlg.indexOf('lc-dialog-footer')));
      final dlg2 = html.substring(html.indexOf('n-dlg2"'), html.indexOf('n-nav"'));
      expect(RegExp(r'class="lc-dialog-btn"').allMatches(dlg2).length, 2);
      expect(dlg2, contains('>取消</button>'));
      expect(RegExp(r"style\.display = 'none'").allMatches(dlg2).length, 3);
    });

    test('公共样式：用到哪个组件才写哪个的；一律包在 :where() 里，盖不过节点自己的样式', () {
      final login = exportHtml(v3LoginPage()).css;
      expect(login, contains(':where(.lc-checkbox)'));
      expect(login, contains(':where(.lc-appBar)'));
      expect(login, isNot(contains('.lc-dialog')));
      expect(login, isNot(contains('.lc-tabs')));
      expect(login, isNot(contains('.lc-switch')));
      // 节点规则后面补的公共规则：新组件的都以 :where( 开头；不是的只有第 3 版第 1 段就有的那几条和“标签里的多行输入”一条。
      final extra = css.substring(css.lastIndexOf('\n.n-', css.indexOf(':where('))).split('\n').skip(2).where((l) => l.isNotEmpty && !l.startsWith('.n-'));
      expect(extra, isNotEmpty);
      for (final line in extra) {
        expect(
          line.startsWith(':where(') ||
              RegExp(r'^\.lc-(icon|icon-solo|button:disabled|field|field > \.lc-input|field > \.lc-textarea|label|required) ').hasMatch(line) ||
              line.startsWith('.lc-button:disabled,'),
          isTrue,
          reason: line,
        );
      }
    });

    test('状态样式：按下 / 聚焦写成 :active / :focus，跟在节点自己的规则后面', () {
      final login = exportHtml(v3LoginPage()).css;
      expect(login, contains('.n-go:active { background: #046b43; }'));
      expect(login, contains('.n-go:focus { outline: 2px solid #7fd1ae; }'));
      expect(login.indexOf('.n-go {'), lessThan(login.indexOf('.n-go:active')));
    });

    test('没用新组件的旧页面：导出里一个新东西都没有', () {
      final old = exportHtml(sample());
      expect(old.css, isNot(contains(':where')));
      expect(old.html, isNot(contains('data-variant')));
    });
  });

  group('Vue / React 导出', () {
    test('结构和网页导出一样；React 用 className / defaultChecked / defaultValue / maxLength', () {
      final vue = _all(exportVue(v3AllPage())), react = _all(exportReact(v3AllPage()));
      for (final cls in ['lc-glyph', 'lc-textarea', 'lc-switch', 'lc-checkbox', 'lc-radio', 'lc-select', 'lc-listItem', 'lc-appBar', 'lc-bottomNav', 'lc-tabs', 'lc-dialog']) {
        expect(vue, contains('class="$cls n-'), reason: cls);
        expect(react, contains('className="$cls n-'), reason: cls);
      }
      expect(react, contains('type={"checkbox"} role={"switch"} defaultChecked'));
      expect(react, contains('maxLength={"50"}'));
      expect(react, contains('<select className="lc-select n-sel" defaultValue={"b"}>'));
      expect(react, isNot(contains(' selected')));
      expect(react, isNot(contains(' class="')));
      expect(vue, contains('<option value="b" selected>'));
      expect(vue, contains(r'@click="$event.view.history.back()"'));
      expect(react, contains('onClick={(event) => event.view.history.back()}'));
    });

    test('弹窗被逻辑管着显示：一开始显不显示看 open；关的时候改的是那份状态', () {
      final vue = _all(exportVue(v3AllPage())), react = _all(exportReact(v3AllPage()));
      expect(vue, contains('const dlg_visible = ref(false);'));
      expect(vue, contains('v-show="dlg_visible"'));
      expect(react, contains('dlg_visible: false,'));
      // 设置页的确认弹窗用的是自带按钮：关＝把状态改回去
      final vueSet = _all(exportVue(v3SettingsPage())), reactSet = _all(exportReact(v3SettingsPage()));
      expect(RegExp(r'@click="sure_visible = false"').allMatches(vueSet).length, 3);
      expect(RegExp(r'onClick=\{\(event\) => \{ lcUi\.sure_visible = false; lcRefresh\(\); \}\}').allMatches(reactSet).length, 3);
      // 没被逻辑管着的：直接改网页元素
      expect(vue, contains(r"$event.currentTarget.closest('.lc-dialog').hidden = true"));
    });

    test('单选组：页面上用 name 分组；自定义组件的定义里不写 name（会被用多次），改成点一个取消别的', () {
      final doc = LcDocument.parse(v3AllPage().encode());
      expect(saveAsComponent(doc, 'rd', 'Pick').ok, isTrue);
      final vue = exportVue(doc), react = exportReact(doc);
      final vueDef = vue.files.firstWhere((f) => f.path.startsWith('components/')).content;
      final reactDef = react.files.firstWhere((f) => f.path.startsWith('components/') && f.path.endsWith('.jsx')).content;
      expect(vueDef, isNot(contains('name="lc-')));
      expect(vueDef, contains("@change=\"\$event.currentTarget.closest('.lc-radio')"));
      expect(reactDef, isNot(contains('name={')));
      expect(reactDef, contains('onChange={(event) =>'));
    });
  });

  group('Flutter 导出', () {
    test('检入的样本和导出器当前的输出一致', () {
      for (final (file, doc, name) in [
        ('v3_login_page.dart', v3LoginPage(), 'V3LoginPage'),
        ('v3_settings_page.dart', v3SettingsPage(), 'V3SettingsPage'),
        ('v3_home_page.dart', v3HomePage(), 'V3HomePage'),
        ('v3_all_page.dart', v3AllPage(), 'V3AllPage'),
      ]) {
        expect(File('test/generated/$file').readAsStringSync(), exportDart(doc, className: name), reason: '导出器改了：运行 dart run tool/gen_sample_export.dart 重新生成（$file）');
      }
    });

    Future<void> show(WidgetTester tester, Widget page) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: page));
      await tester.pump();
      expect(tester.takeException(), isNull);
    }

    testWidgets('登录页：能在 390 宽上渲染；导航栏在 Scaffold 的 appBar 里', (tester) async {
      await show(tester, const V3LoginPage());
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.byType(BackButton), findsOneWidget);
      expect(find.text('登录'), findsNWidgets(2));
      expect(find.byType(Checkbox), findsNWidgets(2));
      expect(tester.widget<Checkbox>(find.byType(Checkbox).first).value, isTrue);
      expect(find.byIcon(Icons.person), findsOneWidget);
    });

    testWidgets('设置页：列表行、开关、按钮式单选、下拉、多行输入都在；确认弹窗打得开、点按钮能关', (tester) async {
      await show(tester, const V3SettingsPage());
      expect(find.byType(Switch), findsNWidgets(2));
      expect(find.text('简体中文'), findsOneWidget);
      expect(find.byType(SegmentedButton<String>), findsOneWidget);
      expect(find.byType(DropdownMenu<String>), findsOneWidget);
      expect(find.text('退出登录'), findsOneWidget);
      // ignore: unawaited_futures 弹窗关了这个 Future 才完成
      V3SettingsPage.showDialog_sure(tester.element(find.byType(Scaffold)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('确定要退出吗？'), findsOneWidget);
      await tester.tap(find.text('再想想'));
      await tester.pumpAndSettle();
      expect(find.text('确定要退出吗？'), findsNothing);
    });

    testWidgets('首页：底部导航在 Scaffold 的 bottomNavigationBar 里；点页签真的会切', (tester) async {
      await show(tester, const V3HomePage());
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(tester.getBottomLeft(find.byType(NavigationBar)).dy, 844);
      expect(find.text('第一条热门').hitTestable(), findsOneWidget);
      expect(find.text('最新的内容在这里').hitTestable(), findsNothing);
      await tester.tap(find.text('最新'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('最新的内容在这里').hitTestable(), findsOneWidget);
      expect(find.text('第一条热门').hitTestable(), findsNothing);
    });

    testWidgets('11 个组件都用上的页：能渲染、往下滚不报错；两个弹窗都打得开', (tester) async {
      await show(tester, const V3AllPage());
      expect(find.byType(AppBar), findsNWidgets(2));
      expect(find.byType(TabBar), findsOneWidget);
      expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
      await tester.drag(find.byType(SingleChildScrollView).first, const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final context = tester.element(find.byType(Scaffold));
      // ignore: unawaited_futures 弹窗关了这个 Future 才完成
      V3AllPage.showDialog_dlg(context);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('没写插槽的算内容'), findsOneWidget);
      expect(find.text('知道了'), findsOneWidget);
      Navigator.of(tester.element(find.text('知道了'))).pop();
      await tester.pumpAndSettle();
      // ignore: unawaited_futures 弹窗关了这个 Future 才完成
      V3AllPage.showDialog_dlg2(context);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(find.text('点确定关掉'), findsNothing);
    });

    test('没用新组件的旧页面：导出里没有弹窗方法、没有多出来的东西', () {
      final old = exportDart(sample());
      expect(old, isNot(contains('showDialog')));
      expect(old, isNot(contains('appBar:')));
    });
  });
}
