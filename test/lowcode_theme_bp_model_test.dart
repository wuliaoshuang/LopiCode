// 第 4 期 B2：主题变量和断点的模型、四种导出（不碰界面）。
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/lowcode/export_dart.dart';
import 'package:lopicode/lowcode/export_html.dart';
import 'package:lopicode/lowcode/export_pages.dart';
import 'package:lopicode/lowcode/export_react.dart';
import 'package:lopicode/lowcode/export_vue.dart';
import 'package:lopicode/lowcode/inspector_write.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/nav_sync.dart';
import 'package:lopicode/lowcode/responsive.dart';
import 'package:lopicode/lowcode/style_resolve.dart';
import 'package:lopicode/lowcode/theme_vars.dart';

LcDocument _doc() {
  final doc = LcDocument.parse('''
{"version":3,"title":"小站","nextId":20,
 "root":{"id":"n1","type":"page","props":{"padding":16,"gap":12},"children":[
   {"id":"n2","type":"text","props":{"text":"你好","fontSize":16}},
   {"id":"n3","type":"button","props":{"text":"点我","bg":"#058654"}},
   {"id":"n4","type":"container","props":{"direction":"column","padding":8},"children":[]}
 ]}}''');
  return doc;
}

void main() {
  group('主题变量', () {
    test('读写：加、改名字、读不懂的原样留着、空了去掉字段', () {
      final doc = _doc();
      expect(doc.more.containsKey('theme'), isFalse);
      expect(lcThemeOf(doc).isEmpty, isTrue);
      expect(lcSetVar(doc, 'color-brand', '#112233', label: '品牌色'), isTrue);
      expect(lcSetVar(doc, 'Bad Name', '#fff'), isFalse);
      expect(lcSetVar(doc, 'color-x', 'red; } body {'), isFalse);
      final t = lcThemeOf(doc);
      expect(t.values, {'color-brand': '#112233'});
      expect(t.labelOf('color-brand'), '品牌色');
      // 存盘再读回来一样
      final again = LcDocument.parse(doc.encode());
      expect(lcThemeOf(again).values, {'color-brand': '#112233'});
      expect(lcThemeOf(again).labels, {'color-brand': '品牌色'});
      // 读不懂的项、别的键留着
      final odd = LcDocument.parse(
        '{"version":3,"title":"t","nextId":2,"theme":{"vars":{"color-a":"#000","Odd Key":"1","n":5},"future":{"x":1}},"root":{"id":"n1","type":"page","props":{},"children":[]}}',
      );
      expect(lcThemeOf(odd).values, {'color-a': '#000'});
      lcSetVar(odd, 'color-b', '#fff');
      final theme = odd.more['theme'] as Map;
      expect((theme['vars'] as Map).keys, ['color-a', 'color-b', 'Odd Key', 'n']);
      expect(theme['future'], {'x': 1});
      lcRemoveVar(doc, 'color-brand');
      expect(doc.more.containsKey('theme'), isFalse);
    });

    test('没动过主题的文档存盘一个字节不变', () {
      final doc = _doc();
      final before = doc.encode();
      lcThemeOf(doc);
      LcViewEnv.of(doc);
      expect(doc.encode(), before);
    });

    test('替换：嵌套、后备值、没有的变量原样、绕圈不死', () {
      const vars = {'a': 'var(--b)', 'b': '8px', 'loop': 'var(--loop)'};
      expect(lcSubstVars('var(--a)', vars), '8px');
      expect(lcSubstVars('0 var(--b) var( --b )', vars), '0 8px 8px');
      expect(lcSubstVars('var(--nope, 4px)', vars), '4px');
      expect(lcSubstVars('var(--nope, rgba(0, 0, 0, 0.2))', vars), 'rgba(0, 0, 0, 0.2)');
      expect(lcSubstVars('var(--nope)', vars), 'var(--nope)');
      expect(lcSubstVars('var(--loop)', vars), 'var(--loop)');
      expect(lcVarNameIn(' var(--color-primary) '), 'color-primary');
      expect(lcVarNameIn('1px solid var(--x)'), isNull);
    });

    test('改名、删除扫所有页面和自定义组件（样式、状态样式、断点样式）', () {
      final doc = LcDocument.parse('''
{"version":3,"title":"t","nextId":30,
 "theme":{"vars":{"color-a":"#ff0000","color-b":"var(--color-a)","space-m":"16px"},"labels":{"color-a":"甲"}},
 "components":[{"id":"c1","name":"卡","props":[],"root":{"id":"k1","type":"container","props":{},"style":{"background-color":"var(--color-a)"},"children":[]}}],
 "root":{"id":"n1","type":"page","props":{},"children":[
    {"id":"n2","type":"button","props":{"text":"a"},"style":{"color":"var(--color-a)","padding-top":"var(--space-m)"},
     "states":{"pressed":{"background-color":"var(--color-a)"}},
     "responsive":{"tablet":{"style":{"border-top-color":"var( --color-a )"},"props":{"x":1}}}}]},
 "pages":[
  {"id":"p2","title":"二","root":{"id":"m1","type":"page","props":{},"style":{"background-color":"var(--color-a, #fff)"},"children":[]}}
 ]}''');
      expect(lcVarUseCount(doc, 'color-a'), 6); // 组件 1 + 按钮 3 + 第二页 1 + 变量 color-b 1
      expect(lcRenameVar(doc, 'color-a', 'space-m'), isFalse, reason: '重名');
      expect(lcRenameVar(doc, 'color-a', 'color-main'), isTrue);
      final text = doc.encode();
      expect(text.contains('--color-a'), isFalse);
      expect(RegExp('--color-main').allMatches(text).length, 6);
      expect(lcThemeOf(doc).labels, {'color-main': '甲'});
      expect(lcThemeOf(doc).values.keys.toList(), ['color-main', 'color-b', 'space-m'], reason: '位置不变');
      expect(lcThemeOf(doc).resolved('color-b'), '#ff0000');
      // 删：用到的地方换成现在的值
      expect(lcRemoveVar(doc, 'color-main'), 6);
      final after = doc.encode();
      expect(after.contains('color-main'), isFalse);
      expect(doc.components.single.root.style['background-color'], '#ff0000');
      expect(doc.pages[1].root.style['background-color'], '#ff0000');
      expect(lcThemeOf(doc).values['color-b'], '#ff0000');
      final btn = doc.pages.first.root.children.single;
      expect(lcBpStyle(btn, 'tablet'), {'border-top-color': '#ff0000'});
      expect(((btn.more['responsive'] as Map)['tablet'] as Map)['props'], {'x': 1}, reason: '不解释的键留着');
      expect(btn.style['padding-top'], 'var(--space-m)');
    });

    test('起步的一套：只加没有的', () {
      final doc = _doc();
      lcSetVar(doc, 'color-primary', '#000000');
      expect(lcAddStarterVars(doc), kLcStarterVars.length - 1);
      expect(lcThemeOf(doc).values['color-primary'], '#000000');
      expect(lcAddStarterVars(doc), 0);
      expect(lcThemeOf(doc).labelOf('space-md'), '中间距');
      expect(lcFreshVarName(lcThemeOf(doc), LcVarKind.color), 'color-1');
    });

    test('“常用”页写变量：进 style；换回普通值回到简写属性', () {
      final doc = _doc();
      final btn = doc.find('n3')!;
      expect(writeCommon(btn, 'bg', 'var(--color-primary)'), 'style');
      expect(btn.style, {'background-color': 'var(--color-primary)'});
      expect(btn.props['bg'], '#058654', reason: '简写属性留着');
      expect(writeCommon(btn, 'bg', '#112233'), 'props');
      expect(btn.style, isEmpty);
      expect(btn.props['bg'], '#112233');
      expect(writeCommon(btn, 'padding', 'var(--space-md)'), 'style');
      expect(btn.style.keys.toSet(), {'padding-top', 'padding-right', 'padding-bottom', 'padding-left'});
      expect(writeCommon(btn, 'padding', 24), 'props');
      expect(btn.style, isEmpty);
    });
  });

  group('断点', () {
    test('读、叠加、只记差别、清掉', () {
      final doc = _doc();
      final n = doc.find('n2')!;
      final before = doc.encode();
      expect(lcBpMerged(n, 'desktop'), isEmpty);
      lcEditAtBp(n, 'tablet', (s) => s['font-size'] = '20px');
      expect(lcBpStyle(n, 'tablet'), {'font-size': '20px'});
      lcEditAtBp(n, 'desktop', (s) {
        expect(s['font-size'], '20px', reason: '桌面看得到平板改的');
        s['font-size'] = '28px';
        s['color'] = '#111111';
      });
      expect(lcBpMerged(n, 'tablet'), {'font-size': '20px'});
      expect(lcBpMerged(n, 'desktop'), {'font-size': '28px', 'color': '#111111'});
      // 改回和下面一样＝这一档不再记它
      lcEditAtBp(n, 'desktop', (s) => s['font-size'] = '20px');
      expect(lcBpStyle(n, 'desktop'), {'color': '#111111'});
      final again = LcDocument.parse(doc.encode()).find('n2')!;
      expect(lcBpStyle(again, 'tablet'), {'font-size': '20px'});
      lcReplaceBp(n, 'tablet', const {});
      lcReplaceBp(n, 'desktop', const {});
      expect(n.more.containsKey('responsive'), isFalse);
      expect(doc.encode(), before);
    });

    test('画布看到的样子：变量换成值、断点并进来；没什么可换时是同一个对象', () {
      final doc = _doc();
      final n = doc.find('n2')!;
      expect(identical(lcViewNode(n, LcViewEnv.of(doc)), n), isTrue);
      expect(identical(lcViewNode(n, LcViewEnv.of(doc, 'desktop')), n), isTrue);
      lcSetVar(doc, 'font-lg', '20px');
      expect(identical(lcViewNode(n, LcViewEnv.of(doc)), n), isTrue, reason: '有变量但这个节点没用');
      n.style['font-size'] = 'var(--font-lg)';
      lcEditAtBp(n, 'tablet', (s) => s['color'] = '#ff0000');
      final phone = lcViewNode(n, LcViewEnv.of(doc));
      expect(resolvedStyle(phone, doc.root)['font-size'], '20px');
      expect(resolvedStyle(phone, doc.root).containsKey('color'), isFalse);
      final desk = lcViewNode(n, LcViewEnv.of(doc, 'desktop'));
      expect(resolvedStyle(desk, doc.root)['color'], '#ff0000');
      expect(n.style['font-size'], 'var(--font-lg)', reason: '原节点不动');
    });

    test('同步底部导航：断点样式也抄过去', () {
      final doc = LcDocument.parse('''
{"version":3,"title":"首页","nextId":30,"id":"home",
 "root":{"id":"n1","type":"page","props":{},"children":[
   {"id":"n2","type":"bottomNav","props":{"items":[{"label":"首页","icon":"home","page":"home"},{"label":"我的","icon":"person","page":"me"}]},
    "responsive":{"desktop":{"style":{"height":"72px"}}}}]},
 "pages":[
 {"id":"me","title":"我的","root":{"id":"m1","type":"page","props":{},"children":[]}}]}''');
      expect(lcSyncBottomNav(doc, 'n2'), 1);
      final there = doc.pages[1].root.children.single;
      expect(lcBpStyle(there, 'desktop'), {'height': '72px'});
      lcReplaceBp(doc.find('n2')!, 'desktop', const {});
      lcSyncBottomNav(doc, 'n2');
      expect(there.more.containsKey('responsive'), isFalse);
    });
  });

  group('导出', () {
    LcDocument sample() {
      final doc = _doc();
      lcAddStarterVars(doc);
      writeCommon(doc.find('n3')!, 'bg', 'var(--color-primary)');
      writeCommon(doc.find('n1')!, 'padding', 'var(--space-md)');
      lcEditAtBp(doc.find('n2')!, 'tablet', (s) => s['font-size'] = 'var(--font-xl)');
      lcEditAtBp(doc.find('n4')!, 'desktop', (s) {
        s['flex-direction'] = 'row';
        s['width'] = '600px';
      });
      return doc;
    }

    test('没用变量、没用断点：四种导出逐字节不变（就算项目里有变量）', () {
      final plain = _doc();
      final withVars = _doc();
      lcAddStarterVars(withVars);
      expect(exportHtml(withVars).css, exportHtml(plain).css);
      expect(exportHtml(withVars).html, exportHtml(plain).html);
      expect(exportDart(withVars), exportDart(plain));
      String all(LcFrameworkExport e) => [for (final f in e.files) '${f.path}\n${f.content}'].join('\n=====\n');
      expect(all(exportVue(withVars)), all(exportVue(plain)));
      expect(all(exportReact(withVars)), all(exportReact(plain)));
    });

    test('普通网页：:root 一段 + 最后的媒体查询', () {
      final css = exportHtml(sample()).css;
      expect(css, contains(':root {\n  --color-primary: #058654;'));
      expect(css, contains('background-color: var(--color-primary)'));
      expect(css, contains('@media (min-width: 768px) {\n  .n-n2 { font-size: var(--font-xl); }\n}'));
      final desk = RegExp(r'@media \(min-width: 1024px\) \{\n  \.n-n4 \{ ([^}]*) \}').firstMatch(css)![1]!;
      expect(desk, contains('flex-direction: row'));
      expect(desk, contains('width: 600px'));
      expect(css.indexOf('@media (min-width: 768px)') < css.indexOf('@media (min-width: 1024px)'), isTrue);
      expect(css.indexOf(':root') < css.indexOf('.n-n1'), isTrue);
    });

    test('Vue：单页面变量放页面里不带 scoped 的一段；React：放共用基础样式', () {
      final vue = exportVue(sample()).files.first.content;
      expect(vue, contains('<style>\n/* 主题变量'));
      expect(vue.indexOf('<style scoped>') < vue.indexOf('<style>\n'), isTrue);
      expect(vue, contains('@media (min-width: 768px)'));
      final react = exportReact(sample());
      final base = react.files.firstWhere((f) => f.path == 'lc-base.css').content;
      expect(base, contains('--color-primary: #058654;'));
      expect(react.files.firstWhere((f) => f.path.endsWith('.css') && f.path != 'lc-base.css').content, contains('@media (min-width: 1024px)'));
    });

    test('多页面：Vue 的变量放外壳，各页不重复', () {
      final doc = sample();
      doc.addPage('第二页');
      final vue = exportVue(doc);
      final shell = vue.files.firstWhere((f) => f.path == 'LcApp.vue').content;
      expect(shell, contains('--space-md: 16px;'));
      for (final f in vue.files.where((f) => f.path != 'LcApp.vue')) {
        expect(f.content.contains(':root'), isFalse, reason: f.path);
      }
      final pages = exportHtmlPages(doc);
      expect(pages.first.files.css, contains(':root'));
      expect(pages[1].files.css.contains(':root'), isFalse, reason: '第二页没用变量');
    });

    test('Flutter：变量换成现在的值，开头写明局限；断点不导出', () {
      final code = exportDart(sample());
      expect(code, contains('// 主题变量：这里写的是导出那一刻的值'));
      expect(code, contains('// 断点：屏幕更宽时'));
      expect(code, contains('backgroundColor: const Color(0xFF058654)'));
      expect(code, contains('EdgeInsets.all(16)'));
      expect(code.contains('var('), isFalse);
      final doc = sample();
      lcSetVar(doc, 'color-primary', '#aa0000');
      expect(exportDart(doc), contains('Color(0xFFAA0000)'));
    });
  });
}
