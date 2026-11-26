// GAP-E-6：属性面板和样式面板合成一张以后，“常用”页的改动写到哪儿，四种导出（网页 / Flutter / Vue / React）
// 才和原来的“属性”面板逐字一样。规矩在 lib/lowcode/inspector_write.dart。
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/lowcode/export_dart.dart';
import 'package:lopicode/lowcode/export_html.dart';
import 'package:lopicode/lowcode/export_react.dart';
import 'package:lopicode/lowcode/export_vue.dart';
import 'package:lopicode/lowcode/inspector_write.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/style_model.dart';
import 'package:lopicode/lowcode/style_resolve.dart';

/// 一页里每种组件各一个。
LcDocument _page() {
  final doc = LcDocument.starter('对比');
  for (final type in ['container', 'row', 'column', 'card', 'text', 'button', 'image', 'input', 'list']) {
    doc.insert(doc.root.id, doc.newNode(type));
  }
  final row = doc.root.children.firstWhere((n) => n.type == 'row');
  doc.insert(row.id, doc.newNode('text'));
  doc.insert(row.id, doc.newNode('container'));
  return doc;
}

/// 四种导出的全部文字拼在一起。
Map<String, String> _exports(LcDocument doc) {
  final html = exportHtml(doc);
  return {
    'html': html.html,
    'css': html.css,
    'flutter': exportDart(doc),
    for (final f in exportVue(doc).files) 'vue:${f.path}': f.content,
    for (final f in exportReact(doc).files) 'react:${f.path}': f.content,
  };
}

List<LcNode> _all(LcDocument doc) {
  final out = <LcNode>[];
  void walk(LcNode n) {
    out.add(n);
    n.children.forEach(walk);
  }

  walk(doc.root);
  return out;
}

/// 旧“属性”面板能改的每一项，各给两个值。
const Map<String, List<Object>> _values = {
  'padding': [0, 24],
  'margin': [8, 32],
  'radius': [0, 16],
  'gap': [0, 24],
  'fontSize': [12, 30],
  'height': [48, 200],
  'width': ['fill', 120],
  'bg': ['#FFFFFF', '#3B6FE0'],
  'color': ['#DC3545', '#222435'],
  'bold': [true],
  'textAlign': ['center', 'right'],
  'align': ['center', 'stretch'],
  'justify': ['between', 'end'],
};

void main() {
  test('没在“样式”页调过的组件：常用页写出来的页面文件和旧“属性”面板一模一样，四种导出逐字相同', () {
    var checked = 0;
    for (final e in _values.entries) {
      for (final value in e.value) {
        final oldWay = _page(), newWay = _page();
        for (final n in _all(oldWay)) {
          if (n.spec.fields.contains(e.key)) n.props[e.key] = value; // 旧面板：直接写简写属性
        }
        for (final n in _all(newWay)) {
          if (!n.spec.fields.contains(e.key)) continue;
          expect(writeCommon(n, e.key, value), 'props', reason: '${n.type}.${e.key}');
          checked++;
        }
        expect(newWay.encode(), oldWay.encode(), reason: '${e.key}=$value 页面文件');
        expect(_exports(newWay), _exports(oldWay), reason: '${e.key}=$value 导出');
      }
    }
    expect(checked, greaterThan(100));
  });

  test('清掉一项（回到默认）也和旧面板一样', () {
    for (final key in _values.keys) {
      final oldWay = _page(), newWay = _page();
      for (final n in _all(oldWay)) {
        if (n.spec.fields.contains(key)) n.props.remove(key);
      }
      for (final n in _all(newWay)) {
        if (n.spec.fields.contains(key)) writeCommon(n, key, null);
      }
      expect(newWay.encode(), oldWay.encode(), reason: key);
      expect(_exports(newWay), _exports(oldWay), reason: key);
    }
  });

  test('为什么不照原设想“一律写进样式”：网页的 CSS 倒是一样，但 Flutter 导出不跟着变', () {
    final oldWay = _page(), styleWay = _page();
    final a = oldWay.root.children.firstWhere((n) => n.type == 'button');
    final b = styleWay.root.children.firstWhere((n) => n.type == 'button');
    a.props['padding'] = 24;
    LcStyle(b.style).setAllSides('padding', const LcLength.px(24));
    // 画布和网页看到的最终样式是一样的……
    expect(resolvedStyle(b, styleWay.root), resolvedStyle(a, oldWay.root));
    expect(exportHtml(styleWay).css, exportHtml(oldWay).css);
    // ……但 Flutter 导出只看简写属性，写进样式的它看不见：
    expect(exportDart(oldWay), contains('EdgeInsets.all(24)'));
    expect(exportDart(styleWay), isNot(contains('EdgeInsets.all(24)')));
    expect(exportDart(styleWay), isNot(exportDart(oldWay)));
  });

  test('“样式”页已经调过这一项：常用页改的是样式里的那几条（不然写了也被盖着），简写属性不动', () {
    final doc = _page();
    final button = doc.root.children.firstWhere((n) => n.type == 'button');
    LcStyle(button.style).set('padding-top', '4px');
    expect(styleOverrides(button, 'padding'), isTrue);
    expect(styleOverrides(button, 'radius'), isFalse);
    expect(writeCommon(button, 'padding', 24), 'style');
    expect(button.props['padding'], 12, reason: '简写属性原样留着');
    expect(resolvedStyle(button, doc.root)['padding-top'], '24px');
    expect(resolvedStyle(button, doc.root)['padding-left'], '24px');
    expect(effectivePx(button, doc.root, 'padding-left'), 24);
    // 别的项不受影响，照旧写简写属性
    expect(writeCommon(button, 'radius', 16), 'props');
    expect(button.props['radius'], 16);
    // 颜色、加粗、对齐同理
    LcStyle(button.style).set('color', 'red');
    expect(writeCommon(button, 'color', '#3B6FE0'), 'style');
    expect(resolvedStyle(button, doc.root)['color'], '#3b6fe0');
  });

  test('样式里是没拆开的简写（Agent 或手改文件写的 padding: 4px 8px）：也算盖着，改完四边一致', () {
    final doc = _page();
    final card = doc.root.children.firstWhere((n) => n.type == 'card');
    card.style['padding'] = '4px 8px';
    expect(styleOverrides(card, 'padding'), isTrue);
    expect(writeCommon(card, 'padding', 32), 'style');
    final r = resolvedStyle(card, doc.root);
    expect([
      for (final s in ['top', 'right', 'bottom', 'left']) r['padding-$s'],
    ], everyElement('32px'));
  });

  test('宽度：样式里写过宽度时，选“撑满”要把样式里那条去掉才生效；固定宽度改样式里那条', () {
    final doc = _page();
    final button = doc.root.children.firstWhere((n) => n.type == 'button');
    LcStyle(button.style).set('width', '50%');
    expect(writeCommon(button, 'width', 200), 'style');
    expect(resolvedStyle(button, doc.root)['width'], '200px');
    expect(writeCommon(button, 'width', 'fill'), 'props');
    expect(button.style.containsKey('width'), isFalse);
    expect(resolvedStyle(button, doc.root)['align-self'], 'stretch');
    expect(resolvedStyle(button, doc.root).containsKey('width'), isFalse);
  });

  test('清掉：简写属性和样式里盖着它的两处都清', () {
    final doc = _page();
    final text = doc.root.children.firstWhere((n) => n.type == 'text');
    text.props['padding'] = 8;
    LcStyle(text.style)
      ..set('padding-top', '2px')
      ..set('color', 'red');
    writeCommon(text, 'padding', null);
    expect(text.props.containsKey('padding'), isFalse);
    expect(text.style.keys, ['color']);
    expect(resolvedStyle(text, doc.root).keys.where((k) => k.startsWith('padding')), isEmpty);
  });

  test('只有样式能表达的项（阴影、填充方式…）直接写样式；传空＝去掉', () {
    final doc = _page();
    final card = doc.root.children.firstWhere((n) => n.type == 'card');
    writeStyleOnly(card, 'box-shadow', '0 1px 3px rgba(0, 0, 0, 0.2)');
    expect(resolvedStyle(card, doc.root)['box-shadow'], '0 1px 3px rgba(0, 0, 0, 0.2)');
    expect(card.props, doc.newNode('card').props, reason: '简写属性没动');
    writeStyleOnly(card, 'box-shadow', null);
    expect(card.style, isEmpty);
  });

  test('生效值的像素数：只认像素；百分比、自动都当“不在档上”', () {
    final doc = _page();
    final button = doc.root.children.firstWhere((n) => n.type == 'button');
    expect(effectivePx(button, doc.root, 'padding-top'), 12);
    LcStyle(button.style).set('padding-top', '10%');
    expect(effectivePx(button, doc.root, 'padding-top'), isNull);
    LcStyle(button.style).set('padding-top', '0');
    expect(effectivePx(button, doc.root, 'padding-top'), 0);
    LcStyle(button.style).set('padding-top', '1.5px');
    expect(effectivePx(button, doc.root, 'padding-top'), 1.5);
  });
}
