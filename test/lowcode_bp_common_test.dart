// “常用”页在平板 / 桌面档改的只记那一档（第四轮 B1）：写法（inspector_bp_write.dart）、四种导出里的媒体查询、
// 真编译 0 错 0 警告、jsdom 里解析出来的媒体查询规则。界面在 lowcode_bp_common_ui_test.dart。
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/lowcode/export_pages.dart';
import 'package:lopicode/lowcode/export_react.dart';
import 'package:lopicode/lowcode/export_vue.dart';
import 'package:lopicode/lowcode/inspector_bp_write.dart';
import 'package:lopicode/lowcode/inspector_write.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/responsive.dart';
import 'package:lopicode/lowcode/style_resolve.dart';

import 'support/dev_tools.dart';
import 'support/media_rules.dart';
import 'support/theme_bp_sample.dart';

/// 样例上做一遍“在平板 / 桌面档的常用页改东西”。
LcDocument edited() {
  final doc = themeBpSample();
  final buy = doc.find('buy')!, cards = doc.find('cards')!, title = doc.find('title')!, cardA = doc.find('cardA')!;
  lcApplyCommonAtBp(buy, doc.parentOf('buy'), 'tablet', (n, _) => writeCommon(n, 'padding', 24));
  lcApplyCommonAtBp(buy, doc.parentOf('buy'), 'desktop', (n, _) => writeCommon(n, 'radius', 16));
  lcApplyCommonAtBp(cards, doc.parentOf('cards'), 'tablet', (n, _) => writeCommon(n, 'gap', 32));
  lcApplyCommonAtBp(title, doc.parentOf('title'), 'tablet', (n, _) => writeCommon(n, 'textAlign', 'center'));
  lcApplyCommonAtBp(title, doc.parentOf('title'), 'desktop', (n, _) => writeCommon(n, 'bold', null));
  lcApplyCommonAtBp(cardA, doc.parentOf('cardA'), 'desktop', (n, _) => writeStyleOnly(n, 'box-shadow', kShadowScale[3]));
  return doc;
}

void main() {
  group('写法', () {
    test('样子类的改动只记进这一档；手机那份（简写属性、style）一个字不动', () {
      final doc = themeBpSample();
      final buy = doc.find('buy')!;
      final props = Map.of(buy.props), style = Map.of(buy.style);
      expect(lcApplyCommonAtBp(buy, doc.parentOf('buy'), 'tablet', (n, _) => writeCommon(n, 'padding', 24)), isTrue);
      expect(buy.props, props);
      expect(buy.style, style);
      expect(lcBpStyle(buy, 'tablet'), {'padding-top': '24px', 'padding-right': '24px', 'padding-bottom': '24px', 'padding-left': '24px'});
      expect(lcBpStyle(buy, 'desktop'), isEmpty);
      // 桌面上看到的＝平板的；在桌面再改只记桌面和平板不一样的
      lcApplyCommonAtBp(buy, doc.parentOf('buy'), 'desktop', (n, _) => writeCommon(n, 'padding', 24));
      expect(lcBpStyle(buy, 'desktop'), isEmpty, reason: '和平板一样：不记');
      lcApplyCommonAtBp(buy, doc.parentOf('buy'), 'desktop', (n, _) => writeCommon(n, 'padding', 32));
      expect(lcBpStyle(buy, 'desktop')['padding-top'], '32px');
    });

    test('内容类的改动不分屏宽：照旧写到节点上，这一档什么都不记', () {
      final doc = themeBpSample();
      final title = doc.find('title')!;
      final before = lcBpStyle(title, 'tablet');
      expect(lcApplyCommonAtBp(title, doc.parentOf('title'), 'tablet', (n, _) => n.props['text'] = '新标题'), isFalse);
      expect(title.props['text'], '新标题');
      expect(lcBpStyle(title, 'tablet'), before);
    });

    test('一次改动里又有样子又有内容：各归各的', () {
      final doc = themeBpSample();
      final title = doc.find('title')!;
      lcApplyCommonAtBp(title, doc.parentOf('title'), 'desktop', (n, _) {
        n.props['text'] = '两样都改';
        writeCommon(n, 'color', '#FF0000');
      });
      expect(title.props['text'], '两样都改');
      expect(title.props.containsKey('color'), isFalse);
      expect(title.style['color'], 'var(--color-text)', reason: '手机的颜色没动');
      expect(lcBpStyle(title, 'desktop'), {'color': '#ff0000'});
    });

    test('清掉＝这一档不再管；下面那层的值会冒出来的（手机加粗、平板不加粗）明说回去', () {
      final doc = themeBpSample();
      final buy = doc.find('buy')!, title = doc.find('title')!;
      lcApplyCommonAtBp(buy, doc.parentOf('buy'), 'tablet', (n, _) => writeCommon(n, 'padding', 24));
      // 桌面上清掉内边距：手机 / 平板的还在，所以桌面要明说回 0
      lcApplyCommonAtBp(buy, doc.parentOf('buy'), 'desktop', (n, _) => writeCommon(n, 'padding', null));
      expect(lcBpStyle(buy, 'tablet')['padding-top'], '24px');
      expect(lcBpStyle(buy, 'desktop')['padding-top'], '0px');
      // 标题手机上加粗（简写属性 bold）；平板上关掉
      expect(title.props['bold'], isTrue);
      lcApplyCommonAtBp(title, doc.parentOf('title'), 'tablet', (n, _) => writeCommon(n, 'bold', null));
      expect(title.props['bold'], isTrue, reason: '手机的没动');
      expect(lcBpStyle(title, 'tablet')['font-weight'], '400');
      expect(resolvedStyle(lcSeenAtBp(title, 'tablet'), doc.parentOf('title'))['font-weight'], '400');
    });

    test('宽度：手机固定、平板撑满；手机撑满、平板固定', () {
      final doc = themeBpSample();
      final buy = doc.find('buy')!;
      final parent = doc.parentOf('buy');
      writeCommon(buy, 'width', 160);
      lcApplyCommonAtBp(buy, parent, 'tablet', (n, _) => writeCommon(n, 'width', 'fill'));
      expect(buy.props['width'], 160);
      final seen = resolvedStyle(lcSeenAtBp(buy, 'tablet'), parent);
      expect(seen['width'], 'auto');
      expect(seen['align-self'] == 'stretch' || seen['flex-grow'] == '1', isTrue, reason: '$seen');

      final cards = doc.find('cards')!; // 手机上 width: fill
      lcApplyCommonAtBp(cards, doc.parentOf('cards'), 'desktop', (n, _) => writeCommon(n, 'width', 320));
      expect(cards.props['width'], 'fill');
      expect(lcBpStyle(cards, 'desktop')['width'], '320px');
      expect(resolvedStyle(lcSeenAtBp(cards, 'desktop'), doc.parentOf('cards')).containsKey('align-self'), isFalse, reason: '设了固定宽度就不再撑满');
    });

    test('存一遍读回来不变；没在别的档改过的旧文件一个字不变', () {
      final doc = edited();
      expect(LcDocument.parse(doc.encode()).encode(), doc.encode());
      final plain = themeBpSample();
      expect(LcDocument.parse(plain.encode()).encode(), plain.encode());
    });
  });

  group('导出', () {
    test('纯网页：分档的常用设置写成媒体查询，手机那份规则不变', () {
      final before = exportHtmlPages(themeBpSample())[0].files.css, after = exportHtmlPages(edited())[0].files.css;
      final cut = after.indexOf('@media (min-width: 768px)'), cut0 = before.indexOf('@media (min-width: 768px)');
      expect(after.substring(0, cut), before.substring(0, cut0), reason: '媒体查询前面（手机）的规则一个字不变');
      final tablet = after.substring(cut, after.indexOf('@media (min-width: 1024px)')), desktop = after.substring(after.indexOf('@media (min-width: 1024px)'));
      expect(tablet, contains('.n-buy { padding: 24px; }'));
      expect(tablet, contains('text-align: center;'));
      expect(desktop, contains('border-radius: 16px;'));
      expect(desktop, contains('font-weight: 400;'));
      expect(desktop, contains('box-shadow:'));
    });

    test('jsdom 真的解析：三种导出的媒体查询里都有这几条规则', () async {
      bool has(List<MediaRule> rules, String cond, String prop, String value) => rules.any((r) => r.cond.contains(cond) && r.style[prop] == value);
      final html = await mediaRulesOf([exportHtmlPages(edited())[0].files.css]);
      final vue = await mediaRulesOf([
        for (final f in exportVue(edited()).files)
          if (f.path == 'Home.vue') ...vueStyles(f.content),
      ]);
      final react = await mediaRulesOf([exportReact(edited()).file('Home.css')!.content]);
      for (final (name, rules) in [('纯网页', html), ('Vue 3', vue), ('React', react)]) {
        expect(has(rules, '768px', 'padding-top', '24px') || has(rules, '768px', 'padding', '24px'), isTrue, reason: '$name：平板的内边距 $rules');
        // jsdom 把 text-align 记成它的两个单项（text-align-all / text-align-last）
        expect(has(rules, '768px', 'text-align', 'center') || has(rules, '768px', 'text-align-all', 'center'), isTrue, reason: '$name：平板的对齐 $rules');
        expect(has(rules, '768px', 'row-gap', '32px') || has(rules, '768px', 'gap', '32px'), isTrue, reason: '$name：平板的间距 $rules');
        expect(has(rules, '1024px', 'font-weight', '400'), isTrue, reason: '$name：桌面不加粗');
        expect(rules.any((r) => r.cond.contains('1024px') && (r.style['border-radius'] == '16px' || r.style['border-top-left-radius'] == '16px')), isTrue, reason: '$name：桌面的圆角 $rules');
        expect(rules.any((r) => r.cond.contains('1024px') && r.style.keys.any((k) => k.startsWith('box-shadow'))), isTrue, reason: '$name：桌面的阴影');
      }
    }, skip: skipWithoutDom);

    test('真编译：纯网页 / Vue 3 / React 都是 0 错 0 警告', () async {
      final doc = edited();
      final files = <String, String>{};
      for (final p in exportHtmlPages(doc)) {
        files[p.htmlName] = p.files.html;
        files[p.cssName] = p.files.css;
        files[p.jsName] = p.files.js;
      }
      final h = await compileExport('compile_html.mjs', files, 'index.html');
      expect(h.errors, isEmpty, reason: h.raw);
      expect(h.warnings, isEmpty, reason: h.raw);
      final v = await compileExport('compile_vue.mjs', {for (final f in exportVue(doc).files) f.path: f.content}, 'LcApp.vue');
      expect(v.errors, isEmpty, reason: v.raw);
      expect(v.warnings, isEmpty, reason: v.raw);
      final r = await compileExport('compile_react.mjs', {for (final f in exportReact(doc).files) f.path: f.content}, 'LcApp.jsx');
      expect(r.errors, isEmpty, reason: r.raw);
      expect(r.warnings, isEmpty, reason: r.raw);
    }, skip: skipWithoutWebdev);
  });
}
