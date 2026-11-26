// 带类型的样式视图（style_model.dart）、最终样式（style_resolve.dart）、HTML 导出改用最终样式后的结果。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/lowcode/css_codec.dart';
import 'package:lopicode/lowcode/export_html.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/style_model.dart';
import 'package:lopicode/lowcode/style_resolve.dart' as resolve;

import 'support/sample_doc.dart';

// —— 基准：第 1 版 export_html.dart 里的 _rules，原样留一份（2026-11-24 改用最终样式之前的写法）。 ——
String _n(num v) => v == v.roundToDouble() ? '${v.round()}' : '$v';

List<String> oldRules(LcNode n, LcNode? parent) {
  final r = <String>[];
  if (n.type == 'spacer') {
    final size = _n(n.numProp('size') ?? 16);
    return ['flex: 0 0 ${size}px;', if (parent?.type == 'row') 'width: ${size}px;' else 'height: ${size}px;'];
  }
  final width = n.props['width'];
  if (width == 'fill' || (parent?.type == 'row' && n.isContainer && width is! num)) {
    r.add(parent?.type == 'row' ? 'flex: 1; min-width: 0;' : 'align-self: stretch;');
  } else if (width is num) {
    r.add('width: ${_n(width)}px;');
  }
  final height = n.numProp('height');
  if (height != null) r.add('height: ${_n(height)}px;');
  final padding = n.numProp('padding');
  if (padding != null) r.add('padding: ${_n(padding)}px;');
  final margin = n.numProp('margin');
  if (margin != null) r.add('margin: ${_n(margin)}px;');
  final bg = n.strProp('bg');
  if (bg != null) r.add('background: ${bg.toLowerCase()};');
  final color = n.strProp('color');
  if (color != null) r.add('color: ${color.toLowerCase()};');
  final radius = n.numProp('radius');
  if (radius != null) r.add('border-radius: ${_n(radius)}px;');
  final fontSize = n.numProp('fontSize');
  if (fontSize != null) r.add('font-size: ${_n(fontSize)}px;');
  if (n.props['bold'] == true) r.add('font-weight: 600;');
  final textAlign = n.strProp('textAlign');
  if (textAlign != null) r.add('text-align: $textAlign;');
  if (n.isContainer) {
    final gap = n.numProp('gap');
    if (gap != null) r.add('gap: ${_n(gap)}px;');
    const align = {'start': 'flex-start', 'center': 'center', 'end': 'flex-end', 'stretch': 'stretch'};
    const justify = {'start': 'flex-start', 'center': 'center', 'end': 'flex-end', 'between': 'space-between'};
    final a = n.strProp('align');
    if (a != null) r.add('align-items: ${align[a]};');
    final j = n.strProp('justify');
    if (j != null) r.add('justify-content: ${justify[j]};');
  }
  return r;
}

/// 第 1 版会给这份文档输出的每个节点的 CSS 规则（按原来的遍历顺序）。
String oldNodeCss(LcDocument doc) {
  final css = StringBuffer();
  void walk(LcNode n, LcNode? parent) {
    final rules = oldRules(n, parent);
    if (rules.isNotEmpty) css.writeln('.n-${n.id} { ${rules.join(' ')} }');
    for (final c in n.children) {
      walk(c, n);
    }
  }

  walk(doc.root, null);
  return css.toString();
}

LcNode node(String type, [Map<String, dynamic>? props, Map<String, String>? style]) => LcNode(id: 'x', type: type, props: props, style: style);
final row = node('row');
final column = node('column');
String css(LcNode n, [LcNode? parent]) => resolve.nodeCssDeclarations(n, parent);

void main() {
  group('LcLength', () {
    test('认得出的单位、auto、0；认不出的保留原文', () {
      expect(LcLength.parse('12px'), const LcLength.px(12));
      expect(LcLength.parse(' 1.5EM '), const LcLength(1.5, 'em'));
      expect(LcLength.parse('-4px')!.value, -4);
      expect(LcLength.parse('.5rem'), const LcLength(0.5, 'rem'));
      for (final u in LcLength.units) {
        final l = LcLength.parse('10$u')!;
        expect((l.value, l.unit, l.isNumeric, l.toCss()), (10.0, u, true, '10$u'));
      }
      expect(LcLength.parse('auto')!.isAuto, isTrue);
      expect(LcLength.parse('AUTO'), const LcLength.auto());
      expect(LcLength.parse('0'), const LcLength.px(0));
      expect(LcLength.parse(null), isNull);
      expect(LcLength.parse('  '), isNull);
      for (final raw in ['calc(100% - 8px)', 'var(--gap)', '12pt', '1.5', 'px', '12 px', 'min-content', '8px !important']) {
        final l = LcLength.parse(raw)!;
        expect((l.isNumeric, l.isAuto, l.raw, l.toCss()), (false, false, raw, raw), reason: raw);
      }
      expect(const LcLength.px(8).toCss(), '8px');
      expect(const LcLength(12.5, '%').toCss(), '12.5%');
      expect('${const LcLength.auto()}', 'auto');
      expect(const LcLength.raw('x') == const LcLength.raw('x') && const LcLength.px(1) != const LcLength(1, 'em'), isTrue);
      expect(const LcLength.px(1).hashCode, const LcLength(1, 'px').hashCode);
    });
  });

  group('LcShadow', () {
    test('单层阴影拆成各部分，inset 和颜色位置任意', () {
      final s = LcShadow.parse('0 1px 3px rgba(0, 0, 0, .2)')!;
      expect((s.x.toCss(), s.y.toCss(), s.blur.toCss(), s.spread.toCss(), s.color, s.inset), ('0px', '1px', '3px', '0px', 'rgba(0, 0, 0, .2)', false));
      expect(LcShadow.parse('inset 2px 4px #000'), const LcShadow(x: LcLength.px(2), y: LcLength.px(4), color: '#000', inset: true));
      expect(LcShadow.parse('red 1px 2px 3px 4px inset'), const LcShadow(x: LcLength.px(1), y: LcLength.px(2), blur: LcLength.px(3), spread: LcLength.px(4), color: 'red', inset: true));
      expect(LcShadow.parse('1px 2px')!.color, isNull);
      expect(const LcShadow(x: LcLength.px(1), y: LcLength.px(2), blur: LcLength.px(3), color: '#000').toCss(), '1px 2px 3px 0px #000');
      expect(const LcShadow(inset: true).toCss(), 'inset 0px 0px 0px 0px');
      expect(
        LcShadow.parse(const LcShadow(y: LcLength.px(2), blur: LcLength(1, 'em'), color: 'red', inset: true).toCss()),
        const LcShadow(y: LcLength.px(2), blur: LcLength(1, 'em'), color: 'red', inset: true),
      );
    });

    test('多层、none、认不出的返回 null', () {
      for (final bad in [null, '', 'none', '0 1px 2px red, 0 2px 4px blue', '1px', '1px 2px 3px 4px 5px', '1px 2px red blue', 'inset inset 1px 2px', 'calc(1px) 2px', '1px 2px var(--c)', 'auto 1px']) {
        expect(LcShadow.parse(bad), isNull, reason: '$bad');
      }
    });
  });

  group('登记表', () {
    test('任务要求的属性都在，名字不重复，都有中文名，枚举都有可选值', () {
      final names = lcStyleProps.map((p) => p.name).toList();
      expect(names.toSet().length, names.length);
      const required = [
        'width', 'height', 'min-width', 'max-width', 'min-height', 'max-height', 'margin-top', 'margin-right', 'margin-bottom', 'margin-left', //
        'padding-top', 'padding-right', 'padding-bottom', 'padding-left', 'border-top-width', 'border-right-style', 'border-bottom-color', 'border-left-width', //
        'border-top-left-radius', 'border-top-right-radius', 'border-bottom-right-radius', 'border-bottom-left-radius', 'background-color', 'color', 'font-size', 'font-weight', //
        'line-height', 'text-align', 'letter-spacing', 'text-decoration-line', 'font-style', 'box-shadow', 'opacity', 'display', 'flex-direction', 'flex-wrap', 'justify-content', //
        'align-items', 'align-self', 'row-gap', 'column-gap', 'flex-grow', 'flex-shrink', 'flex-basis', 'position', 'top', 'right', 'bottom', 'left', 'z-index', 'overflow-x', 'overflow-y',
      ];
      expect(names, containsAll(required));
      expect(names.where((n) => n.startsWith('border-') && !n.endsWith('radius')), hasLength(12));
      for (final p in lcStyleProps) {
        expect(p.label, isNotEmpty, reason: p.name);
        expect(p.options.isNotEmpty, p.kind == LcStyleKind.choice, reason: p.name);
        expect(cssLonghands(p.name), isEmpty, reason: '登记的都是拆开后的单项：${p.name}');
        expect(LcNode.cleanStyle({p.name: 'x'}), isNotEmpty, reason: p.name);
      }
      expect(lcStyleProp('margin-top')!.label, '上外边距');
      expect(lcStyleProp('border-top-left-radius')!.label, '左上圆角');
      expect(lcStyleProp('margin'), isNull);
      expect(lcStyleProp('align-items')!.options, contains('flex-start'));
      expect(lcStyleProp('color')!.kind, LcStyleKind.color);
      expect(lcStyleProp('opacity')!.kind, LcStyleKind.number);
      expect(lcStyleProp('line-height')!.kind, LcStyleKind.text);
      expect(lcStyleProp('box-shadow')!.kind, LcStyleKind.shadow);
      expect(lcStyleProp('width')!.kind, LcStyleKind.length);
    });

    test('每个分组都有属性、有中文名，分组加起来就是整张表', () {
      var total = 0;
      for (final g in LcStyleGroup.values) {
        expect(g.label, isNotEmpty);
        expect(lcStylePropsIn(g), isNotEmpty, reason: g.name);
        total += lcStylePropsIn(g).length;
      }
      expect(total, lcStyleProps.length);
      expect(lcStylePropsIn(LcStyleGroup.size).map((p) => p.name), ['width', 'height', 'min-width', 'max-width', 'min-height', 'max-height']);
      expect(lcStylePropsIn(LcStyleGroup.position).map((p) => p.name), ['position', 'top', 'right', 'bottom', 'left', 'z-index']);
    });
  });

  group('LcStyle 读写', () {
    test('原文、长度、数字：写 null 就是删掉', () {
      final map = <String, String>{};
      final s = LcStyle(map);
      expect(s.get('width'), isNull);
      expect(s.length('width'), isNull);
      expect(s.setLength('width', const LcLength(50, '%')), isTrue);
      expect(map, {'width': '50%'});
      expect(s.length('width'), const LcLength(50, '%'));
      expect(s.setLength('width', const LcLength.raw('calc(100% - 8px)')), isTrue);
      expect(s.length('width')!.raw, 'calc(100% - 8px)');
      expect(s.setLength('width', null), isTrue);
      expect(map, isEmpty);
      expect(s.setNumber('opacity', 0.5) && s.setNumber('z-index', 3), isTrue);
      expect(map, {'opacity': '0.5', 'z-index': '3'});
      expect((s.number('opacity'), s.number('z-index'), s.number('width')), (0.5, 3.0, null));
      map['opacity'] = 'abc';
      expect(s.number('opacity'), isNull);
      expect(s.setNumber('opacity', null), isTrue);
      expect(s.set('z-index', '  '), isTrue);
      expect(map, isEmpty);
    });

    test('不合页面文件规矩的值不写；写简写会自动拆开', () {
      final map = <String, String>{'color': 'red'};
      final s = LcStyle(map);
      for (final bad in ['a;b', 'a{b', 'a}b', 'a<b', 'a>b', 'a\nb', 'x' * 501]) {
        expect(s.set('color', bad), isFalse, reason: bad);
      }
      expect(s.set('Bad Name', '1'), isFalse);
      expect(map, {'color': 'red'});
      expect(s.set('margin', '8px 4px'), isTrue);
      expect(s.lengthSides('margin').values.map((l) => l!.toCss()), ['8px', '4px', '8px', '4px']);
      expect(map.containsKey('margin'), isFalse);
      expect(s.set('margin', null), isTrue);
      expect(map, {'color': 'red'});
      expect(LcNode.cleanStyle(map), map);
    });

    test('四边一起读写', () {
      final map = <String, String>{};
      final s = LcStyle(map);
      expect(s.lengthSides('padding').isEmpty, isTrue);
      expect(s.setAllSides('padding', const LcLength.px(8)), isTrue);
      expect(map, parseDeclarations('padding: 8px'));
      expect(s.lengthSides('padding').isUniform, isTrue);
      expect(s.setLengthSides('padding', const LcSides(LcLength.px(1), null, LcLength.auto(), LcLength(2, 'em'))), isTrue);
      expect(map, {'padding-top': '1px', 'padding-bottom': 'auto', 'padding-left': '2em'});
      final sides = s.lengthSides('padding');
      expect((sides.top!.toCss(), sides.right, sides.bottom!.isAuto, sides.left!.unit, sides.isUniform, sides.isEmpty), ('1px', null, true, 'em', false, false));
      expect(s.setAllSides('padding', null), isTrue);
      expect(map, isEmpty);
      // 边框的三样、圆角、定位的四个方向
      expect(
        s.setSides('border-style', const LcSides.all('solid')) && s.setAllSides('border-width', const LcLength.px(1)) && s.setSides('border-color', const LcSides('red', 'red', 'red', 'red')),
        isTrue,
      );
      expect(s.toCss(), 'border: 1px solid red;');
      expect(s.sides('border-color').top, 'red');
      expect(s.setAllSides('border-radius', const LcLength.px(6)) && s.setAllSides('inset', const LcLength.px(0)), isTrue);
      expect(map['border-bottom-left-radius'], '6px');
      expect(map['left'], '0px');
      expect(LcStyle.sideNames('border-radius'), ['border-top-left-radius', 'border-top-right-radius', 'border-bottom-right-radius', 'border-bottom-left-radius']);
      expect(LcStyle.sideNames('inset'), ['top', 'right', 'bottom', 'left']);
      expect(s.setSides('margin', const LcSides('1px', 'a;b', null, '2px')), isFalse, reason: '有一边不合规矩');
      expect((map['margin-top'], map['margin-right'], map['margin-left']), ('1px', null, '2px'));
      expect(() => LcStyle.sideNames('color'), throwsArgumentError);
      expect(() => s.sides('gap'), throwsArgumentError);
    });

    test('枚举、颜色、阴影', () {
      final map = <String, String>{};
      final s = LcStyle(map);
      expect(s.setChoice('text-align', 'center'), isTrue);
      expect(s.choice('text-align'), 'center');
      expect(s.setChoice('text-align', 'middle'), isFalse);
      expect(s.setChoice('made-up', 'x'), isFalse);
      expect(map, {'text-align': 'center'});
      map['text-align'] = 'CENTER';
      expect(s.choice('text-align'), 'center');
      map['text-align'] = 'start';
      expect((s.choice('text-align'), s.get('text-align')), (null, 'start'), reason: '不在可选值里的读不成枚举，但原文还在');
      expect(s.setChoice('text-align', null), isTrue);
      expect(map, isEmpty);

      expect(s.setColor('color', 'rebeccapurple') && s.setColorArgb('background-color', 0x80FF0000), isTrue);
      expect(map, {'color': 'rebeccapurple', 'background-color': '#ff000080'});
      expect((s.color('color'), s.colorArgb('color'), s.colorArgb('background-color'), s.colorArgb('width')), ('rebeccapurple', null, 0x80FF0000, null));
      expect(s.setColorArgb('color', 0xFF058654), isTrue);
      expect(s.colorArgb('color'), 0xFF058654);
      expect(s.setColor('color', null) && s.setColorArgb('background-color', null), isTrue);

      expect(s.shadow, isNull);
      expect(s.setShadow(const LcShadow(y: LcLength.px(1), blur: LcLength.px(3), color: 'rgba(0, 0, 0, .2)')), isTrue);
      expect(map, {'box-shadow': '0px 1px 3px 0px rgba(0, 0, 0, .2)'});
      expect(s.shadow!.blur, const LcLength.px(3));
      map['box-shadow'] = '0 1px 2px red, 0 2px 4px blue';
      expect((s.shadow, s.get('box-shadow')), (null, '0 1px 2px red, 0 2px 4px blue'), reason: '多层阴影保留原文');
      expect(s.setShadow(null), isTrue);
      expect(map, isEmpty);
    });

    test('哪些是自定义 CSS；整张表和文字互换', () {
      final map = parseDeclarations('transform: rotate(3deg); margin: 4px; -webkit-line-clamp: 2; color: red; background: url(a.png)');
      final s = LcStyle(map);
      expect(s.custom, {'transform': 'rotate(3deg)', '-webkit-line-clamp': '2', 'background': 'url(a.png)'});
      expect(s.custom.keys.toList(), ['transform', '-webkit-line-clamp', 'background']);
      expect(s.known.keys, containsAll(['margin-top', 'margin-left', 'color']));
      expect({...s.known, ...s.custom}, map);
      expect((s.hasAny(LcStyleGroup.margin), s.hasAny(LcStyleGroup.text), s.hasAny(LcStyleGroup.padding)), (true, true, false));
      expect(s.toCss(), 'margin: 4px;\nbackground: url(a.png);\ncolor: red;\ntransform: rotate(3deg);\n-webkit-line-clamp: 2;');
      final dropped = s.replaceWithCss('padding: 1px 2px; oops; x: a<b');
      expect(dropped, hasLength(2));
      expect(map, parseDeclarations('padding: 1px 2px'));
    });
  });

  group('legacyStyle', () {
    test('各种简写属性 × 各种父节点：和第 1 版的 _rules 逐项一致', () {
      const propSets = <Map<String, dynamic>>[
        {},
        {'width': 'fill'},
        {'width': 120},
        {'width': 33.5, 'height': 40},
        {'width': 0, 'height': 0, 'padding': 0, 'margin': 0, 'radius': 0, 'gap': 0, 'fontSize': 0, 'size': 0},
        {'padding': 12, 'margin': 4.5, 'bg': '#FFAA00', 'color': '#222435', 'radius': 8},
        {'fontSize': 18, 'bold': true, 'textAlign': 'center'},
        {'bold': false, 'textAlign': 'right', 'text': '字', 'src': 'a.png', 'placeholder': 'p'},
        {'gap': 8, 'align': 'start', 'justify': 'between'},
        {'gap': 2.5, 'align': 'stretch', 'justify': 'end', 'width': 'fill'},
        {'align': 'end', 'justify': 'center', 'width': 64, 'height': 64, 'bg': '#000000'},
        {'align': 'center', 'justify': 'start'},
        {'size': 24},
        {'size': 7.5, 'width': 'fill', 'padding': 3},
        {
          'width': 'fill', 'height': 10, 'padding': 1, 'margin': 2, 'bg': '#ABCDEF', 'color': '#FEDCBA', 'radius': 3, //
          'fontSize': 4, 'bold': true, 'textAlign': 'left', 'gap': 5, 'align': 'center', 'justify': 'between', 'size': 6,
        },
      ];
      var checked = 0;
      for (final type in lcSpecs.keys) {
        for (final parent in [null, row, column, node('page'), node('card'), node('container')]) {
          for (final props in [...propSets, lcSpecs[type]!.defaults]) {
            final n = node(type, Map.of(props));
            final expected = oldRules(n, parent).join(' ');
            final legacy = resolve.legacyStyle(n, parent);
            expect(declarationsToCss(legacy, multiline: false), expected, reason: '$type 在 ${parent?.type} 里，$props');
            expect(css(n, parent), expected);
            expect(resolve.resolvedStyle(n, parent), legacy);
            expect(canonicalDeclarations(legacy), legacy, reason: '翻出来的就是规范写法');
            // 文字意思也一样：旧规则解析出来就是这张表（背景色那条旧写法是 background 简写）。
            expect(parseDeclarations(expected), legacy);
            checked++;
          }
        }
      }
      expect(checked, 24 * 6 * 16);
    });

    test('翻出来的是拆开的单项', () {
      expect(resolve.legacyStyle(node('button', {'padding': 12, 'bg': '#058654', 'radius': 8, 'width': 'fill'}), row), {
        'flex-grow': '1', 'flex-shrink': '1', 'flex-basis': '0%', 'min-width': '0', //
        'padding-top': '12px', 'padding-right': '12px', 'padding-bottom': '12px', 'padding-left': '12px', 'background-color': '#058654', //
        'border-top-left-radius': '8px', 'border-top-right-radius': '8px', 'border-bottom-right-radius': '8px', 'border-bottom-left-radius': '8px',
      });
      expect(resolve.legacyStyle(node('button', {'width': 'fill'}), column), {'align-self': 'stretch'});
      expect(resolve.legacyStyle(node('column'), row), {'flex-grow': '1', 'flex-shrink': '1', 'flex-basis': '0%', 'min-width': '0'}, reason: '行里的容器没给宽度就平分');
      expect(resolve.legacyStyle(node('column', {'width': 80}), row), {'width': '80px'});
      expect(resolve.legacyStyle(node('spacer'), row), {'flex-grow': '0', 'flex-shrink': '0', 'flex-basis': '16px', 'width': '16px'});
      expect(resolve.legacyStyle(node('spacer', {'size': 8}), null), {'flex-grow': '0', 'flex-shrink': '0', 'flex-basis': '8px', 'height': '8px'});
      expect(resolve.legacyStyle(node('text', {'gap': 8, 'align': 'center'}), null), isEmpty, reason: '不是容器的不管 gap / align');
      expect(resolve.legacyStyle(node('component', {'width': 'fill', 'margin': 4}), null).keys, containsAll(['align-self', 'margin-top']));
    });
  });

  group('resolvedStyle', () {
    test('style 里同名的盖掉简写属性翻出来的，别的照留', () {
      final n = node('button', {'padding': 12, 'bg': '#058654', 'color': '#FFFFFF'}, {'padding-top': '4px', 'color': 'red', 'transform': 'scale(1.1)'});
      final r = resolve.resolvedStyle(n, null);
      expect((r['padding-top'], r['padding-left'], r['color'], r['background-color'], r['transform']), ('4px', '12px', 'red', '#058654', 'scale(1.1)'));
      expect(css(n), 'padding: 4px 12px 12px; background: #058654; color: red; transform: scale(1.1);');
      expect(n.style, {'padding-top': '4px', 'color': 'red', 'transform': 'scale(1.1)'}, reason: '不改节点');
      expect(n.props['padding'], 12);
    });

    test('style 里没拆开的简写（Agent 直接写进文件的）先拆再盖；拆不了的把它管的单项盖掉', () {
      expect(css(node('card', {'padding': 16, 'radius': 12}, {'padding': '0 8px', 'border': '1px solid #ff0000'})), 'padding: 0 8px; border: 1px solid #ff0000; border-radius: 12px;');
      expect(css(node('card', {'padding': 16, 'margin': 4}, {'padding': 'var(--pad)'})), 'padding: var(--pad); margin: 4px;');
      expect(css(node('card', {'bg': '#FFFFFF'}, {'background': 'linear-gradient(red, blue)'})), 'background: linear-gradient(red, blue);');
      expect(css(node('card', {'bg': '#FFFFFF'}, {'background-image': 'url(a.png)'})), 'background-color: #ffffff; background-image: url(a.png);');
      expect(css(node('card', {'gap': 8}, {'row-gap': '2px'})), 'gap: 2px 8px;');
    });

    test('style 写了宽度：不再撑满（行里去掉 flex: 1; min-width: 0，列里去掉 align-self: stretch）', () {
      expect(css(node('button', {'width': 'fill'}), row), 'flex: 1; min-width: 0;');
      expect(css(node('button', {'width': 'fill'}, {'width': '120px'}), row), 'width: 120px;');
      expect(css(node('button', {'width': 'fill'}, {'width': '50%'}), column), 'width: 50%;');
      expect(css(node('column', null, {'width': '30%'}), row), 'width: 30%;', reason: '行里靠“容器平分”撑满的也一样');
      // style 自己写的 flex / min-width / align-self 留着
      expect(css(node('button', {'width': 'fill'}, {'width': '120px', 'min-width': '80px', 'flex-shrink': '0'}), row), 'flex-shrink: 0; width: 120px; min-width: 80px;');
      expect(css(node('button', {'width': 'fill'}, {'width': '50%', 'align-self': 'center'}), column), 'align-self: center; width: 50%;');
      // 写了 flex / flex-basis 也算自己定了大小
      expect(css(node('button', {'width': 'fill'}, {'flex': '0 0 80px'}), row), 'flex: 0 0 80px;');
      expect(css(node('button', {'width': 'fill'}, {'flex-basis': '40%'}), row), 'flex-basis: 40%;');
      // 没写宽度：撑满照旧，只盖同名的
      expect(css(node('button', {'width': 'fill'}, {'flex-grow': '2', 'height': '40px'}), row), 'flex: 2; min-width: 0; height: 40px;');
      expect(css(node('button', {'width': 'fill'}, {'max-width': '300px'}), row), 'flex: 1; min-width: 0; max-width: 300px;');
      // 简写属性给的是固定宽度：就是普通的同名覆盖
      expect(css(node('button', {'width': 96}, {'width': '10em'}), row), 'width: 10em;');
    });

    test('间隔：style 写了主轴方向的尺寸就让它生效', () {
      expect(css(node('spacer', {'size': 8}, {'width': '2em'}), row), 'flex: 0 0 auto; width: 2em;');
      expect(css(node('spacer', {'size': 8}, {'height': '2em'}), column), 'flex: 0 0 auto; height: 2em;');
      expect(css(node('spacer', {'size': 8}, {'height': '2em'}), row), 'flex: 0 0 8px; width: 8px; height: 2em;', reason: '行里的高度不是主轴方向，不影响');
      expect(css(node('spacer', {'size': 8}, {'width': '2em', 'flex-basis': '10px'}), row), 'flex: 0 0 10px; width: 2em;');
    });
  });

  group('HTML 导出', () {
    void sameAsBefore(LcDocument doc) {
      final out = exportHtml(doc);
      final nodeCss = oldNodeCss(doc);
      expect(out.css, endsWith(nodeCss));
      final base = out.css.substring(0, out.css.length - nodeCss.length);
      expect(base, startsWith('/* 由 LopiCode 低代码搭建器生成'));
      expect(base, endsWith('.lc-divider { border: 0; border-top: 1px solid #d3dee4; margin: 0; align-self: stretch; }\n'));
      expect(base, isNot(contains('.n-')));
    }

    test('没有 style 的页面：每个节点的规则和改之前逐字相同（起步页面、样本页面）', () {
      sameAsBefore(LcDocument.starter('我的页面'));
      sameAsBefore(sample());
      // 钉死几行，防止基准函数和导出器一起被改坏。
      final css = exportHtml(sample()).css;
      expect(css, contains('.n-root { padding: 16px; background: #f6fbfd; gap: 12px; }\n'));
      expect(css, contains('.n-card { align-self: stretch; padding: 16px; background: #ffffff; border-radius: 12px; gap: 8px; }\n'));
      expect(css, contains('.n-b1 { flex: 1; min-width: 0; background: #058654; color: #ffffff; }\n'));
      expect(css, contains('.n-sp { flex: 0 0 8px; width: 8px; }\n'));
      expect(css, contains('.n-sp2 { flex: 0 0 24px; height: 24px; }\n'));
      expect(css, isNot(contains('.n-dv {')), reason: '没有声明的节点不输出空规则');
    });

    test('有 style 的节点：规则里是最终样式，别的节点和 HTML 结构不变', () {
      final plain = exportHtml(sample());
      final doc = sample();
      doc.find('b1')!.style.addAll({'margin-top': '8px', 'border-top-width': '1px', 'border-top-style': 'solid', 'border-top-color': '#ff0000', '-webkit-line-clamp': '2'});
      doc.find('dv')!.style['opacity'] = '.5';
      final out = exportHtml(LcDocument.parse(doc.encode()));
      expect(out.html, plain.html);
      expect(out.css, contains('.n-b1 { flex: 1; min-width: 0; margin-top: 8px; border-top: 1px solid #ff0000; background: #058654; color: #ffffff; -webkit-line-clamp: 2; }\n'));
      expect(out.css, contains('.n-dv { opacity: .5; }\n'));
      final changed = {'.n-b1 ', '.n-dv '};
      expect(out.css.split('\n').where((l) => !changed.any(l.startsWith)), plain.css.split('\n').where((l) => !changed.any(l.startsWith)));
      expect('{'.allMatches(out.css).length, '}'.allMatches(out.css).length);
    });

    test('自定义组件的实例（type: component）不崩，按空容器输出', () {
      final doc = LcDocument.parse(
        jsonEncode({
          'title': 't',
          'root': {
            'id': 'root',
            'type': 'page',
            'children': [
              {
                'id': 'n1',
                'type': 'component',
                'props': {'ref': 'c1', 'width': 'fill', 'margin': 4},
                'style': {'opacity': '0.8'},
              },
            ],
          },
        }),
      );
      final out = exportHtml(doc);
      expect(out.html, contains('<div class="lc-component n-n1">\n    </div>'));
      expect(out.css, contains('.n-n1 { align-self: stretch; margin: 4px; opacity: 0.8; }'));
    });

    test('nodeCssRule / nodeCssDeclarations / nodeCssSelector（export_html.dart 也转出了这几个）', () {
      final n = LcNode(id: 'b1', type: 'button', props: {'padding': 12}, style: {'color': 'red'});
      expect(nodeCssSelector(n), '.n-b1');
      expect(nodeCssDeclarations(n, null), 'padding: 12px; color: red;');
      expect(nodeCssRule(n, null), '.n-b1 { padding: 12px; color: red; }');
      expect(nodeCssRule(n, null, selector: '.btn'), '.btn { padding: 12px; color: red; }');
      expect(nodeCssRule(LcNode(id: 'd', type: 'divider'), null), '');
      expect(nodeCssDeclarations(LcNode(id: 'd', type: 'divider'), null), '');
    });
  });
}
