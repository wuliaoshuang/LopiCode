// CSS 声明编解码（lib/lowcode/css_codec.dart 和它用到的 css_scan / css_expand / css_color）。
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/lowcode/css_codec.dart';
import 'package:lopicode/lowcode/css_color.dart';
import 'package:lopicode/lowcode/css_expand.dart';
import 'package:lopicode/lowcode/css_scan.dart';
import 'package:lopicode/lowcode/model.dart';

Map<String, String> p(String css) => parseDeclarations(css);
String w(Map<String, String> d) => declarationsToCss(d, multiline: false);
Map<String, String> four(String prefix, List<String> v, [String suffix = '']) => {for (var i = 0; i < 4; i++) '$prefix${cssSides[i]}$suffix': v[i]};

/// 往返稳定性用的声明：各种简写、单项、认不出的属性、!important、函数值。
const roundTripCases = <String>[
  'margin: 8px',
  'margin: 8px 4px',
  'margin: 1px 2px 3px',
  'margin: 1px 2px 3px 4px',
  'margin: auto',
  'margin: 0 auto',
  'margin: inherit',
  'margin: var(--m)',
  'margin: calc(1px + 2px) 3px',
  'margin-top: 8px',
  'margin-top: 8px; margin-bottom: 8px',
  'margin: 8px !important',
  'margin-top: 1px !important; margin-right: 1px; margin-bottom: 1px; margin-left: 1px',
  'padding: 12px',
  'padding: 12px 16px',
  'padding: 0 0 0 20px',
  'padding-left: 2em',
  'inset: 0',
  'inset: 0 auto auto 0',
  'top: 0; left: 0',
  'border: 1px solid red',
  'border: 1px solid',
  'border: 0',
  'border: none',
  'border: solid',
  'border: 2px dashed rgb(0, 0, 0)',
  'border: thick double #ff0000',
  'border: inherit',
  'border: var(--b)',
  'border: 1px solid red !important',
  'border-top: 1px solid #eee',
  'border-bottom: 2px dotted',
  'border: 1px solid red; border-top-color: blue',
  'border: 1px solid red; border-left: 0',
  'border-width: 1px',
  'border-width: 1px 2px',
  'border-width: 1px; border-style: solid',
  'border-color: red green blue black',
  'border-top-width: 3px',
  'border-top: var(--line); border-top-color: red',
  'border-radius: 8px',
  'border-radius: 8px 4px',
  'border-radius: 1px 2px 3px 4px',
  'border-radius: 50%',
  'border-radius: 8px / 4px',
  'border-radius: 10px 20px / 5px',
  'border-top-left-radius: 6px',
  'gap: 8px',
  'gap: 8px 16px',
  'row-gap: 4px',
  'flex: 1',
  'flex: 2',
  'flex: none',
  'flex: auto',
  'flex: 0 0 16px',
  'flex: 1 1 0',
  'flex: 1 30px',
  'flex: 2 3',
  'flex: 100px',
  'flex: initial',
  'flex: var(--f)',
  'flex-grow: 1',
  'flex-grow: 1; flex-shrink: 0',
  'flex-grow: calc(1); flex-shrink: 1; flex-basis: 0%',
  'overflow: hidden',
  'overflow: hidden auto',
  'overflow-x: scroll',
  'background: #fff',
  'background: red',
  'background: rgba(0, 0, 0, .5)',
  'background: transparent !important',
  'background: url(a.png) no-repeat',
  'background: linear-gradient(to right, red, blue)',
  'background: url(a.png); background-color: red',
  'background-color: red; background-image: url(a.png)',
  'background-color: var(--bg)',
  'font: 12px/1.5 serif',
  'font: bold 14px Arial; font-size: 16px',
  'color: #222435; font-size: 16px; font-weight: 600; text-align: center',
  'box-shadow: 0 1px 3px rgba(0, 0, 0, .2)',
  'box-shadow: 0 1px 2px red, 0 2px 4px blue',
  'transform: rotate(3deg) scale(1.1)',
  '-webkit-line-clamp: 2; --my-var: 3px',
  'transition: all .2s ease-in-out; cursor: pointer',
  'grid-template-columns: repeat(3, 1fr)',
  'content: "a: b"',
  "font-family: 'PingFang SC', sans-serif",
  'width: 100%; height: calc(100vh - 40px); min-width: 0; max-width: 480px',
  'position: absolute; top: 0; right: 0; bottom: 0; left: 0; z-index: 3',
  'display: flex; flex-direction: column; flex-wrap: wrap; align-items: center; justify-content: space-between; align-self: stretch',
  'opacity: .5; letter-spacing: 1px; line-height: 1.5; text-decoration: underline; font-style: italic',
  'zoom: 1; margin: 4px; aaa: 1; padding: 2px; bbb: 2',
];

void main() {
  group('解析', () {
    test('基本写法：小写属性名、去空格、最后一条可以没有分号、同名后写的生效', () {
      expect(p('Color: Red ;FONT-SIZE:16px'), {'color': 'Red', 'font-size': '16px'});
      expect(p('color: red; color: blue'), {'color': 'blue'});
      expect(p('  color : red ;;; '), {'color': 'red'});
    });

    test('接受包着选择器的一条规则和注释', () {
      expect(p('.a > b { color: red; /* 注释; 里的: 不算 */ width: 1px }'), {'color': 'red', 'width': '1px'});
      expect(p('/* 开头 */color:/* 中间 */red'), {'color': 'red'});
      expect(p('content: "/* 不是注释 */"'), {'content': '"/* 不是注释 */"'});
      final r = parseCss('.a { color: red } .b { color: blue }');
      expect(r.declarations, {'color': 'red'});
      expect(r.dropped.single, contains('只读第一条规则'));
    });

    test('四边简写的 1 / 2 / 3 / 4 个值', () {
      for (final name in ['margin', 'padding']) {
        expect(p('$name: 1px'), four('$name-', ['1px', '1px', '1px', '1px']));
        expect(p('$name: 1px 2px'), four('$name-', ['1px', '2px', '1px', '2px']));
        expect(p('$name: 1px 2px 3px'), four('$name-', ['1px', '2px', '3px', '2px']));
        expect(p('$name: 1px 2px 3px 4px'), four('$name-', ['1px', '2px', '3px', '4px']));
      }
      expect(p('inset: 0 auto'), {'top': '0', 'right': 'auto', 'bottom': '0', 'left': 'auto'});
      expect(p('border-width: 1px 2px 3px'), four('border-', ['1px', '2px', '3px', '2px'], '-width'));
      expect(p('border-style: solid dashed'), four('border-', ['solid', 'dashed', 'solid', 'dashed'], '-style'));
      expect(p('border-color: red'), four('border-', ['red', 'red', 'red', 'red'], '-color'));
      expect(p('margin: calc(1px + 2px) 3px')['margin-top'], 'calc(1px + 2px)');
      // 拆不了的原样保留
      expect(p('margin: 1px 2px 3px 4px 5px'), {'margin': '1px 2px 3px 4px 5px'});
      expect(p('padding: var(--p)'), {'padding': 'var(--p)'});
    });

    test('圆角：四个角，带斜杠的椭圆写法', () {
      Map<String, String> corners(List<String> v) => {for (var i = 0; i < 4; i++) 'border-${cssCorners[i]}-radius': v[i]};
      expect(p('border-radius: 8px'), corners(['8px', '8px', '8px', '8px']));
      expect(p('border-radius: 1px 2px'), corners(['1px', '2px', '1px', '2px']));
      expect(p('border-radius: 1px 2px 3px'), corners(['1px', '2px', '3px', '2px']));
      expect(p('border-radius: 1px 2px 3px 4px'), corners(['1px', '2px', '3px', '4px']));
      expect(p('border-radius: 10px 20px / 5px'), corners(['10px 5px', '20px 5px', '10px 5px', '20px 5px']));
      expect(p('border-radius: 8px / 8px'), corners(['8px', '8px', '8px', '8px']));
      expect(p('border-radius: 1px / 2px / 3px'), {'border-radius': '1px / 2px / 3px'});
    });

    test('gap、overflow、flex', () {
      expect(p('gap: 8px'), {'row-gap': '8px', 'column-gap': '8px'});
      expect(p('gap: 8px 16px'), {'row-gap': '8px', 'column-gap': '16px'});
      expect(p('overflow: hidden'), {'overflow-x': 'hidden', 'overflow-y': 'hidden'});
      expect(p('overflow: hidden auto'), {'overflow-x': 'hidden', 'overflow-y': 'auto'});
      Map<String, String> flex(String g, String s, String b) => {'flex-grow': g, 'flex-shrink': s, 'flex-basis': b};
      expect(p('flex: 1'), flex('1', '1', '0%'));
      expect(p('flex: none'), flex('0', '0', 'auto'));
      expect(p('flex: auto'), flex('1', '1', 'auto'));
      expect(p('flex: 30px'), flex('1', '1', '30px'));
      expect(p('flex: 2 3'), flex('2', '3', '0%'));
      expect(p('flex: 2 30px'), flex('2', '1', '30px'));
      expect(p('flex: 0 0 16px'), flex('0', '0', '16px'));
      expect(p('flex: inherit'), flex('inherit', 'inherit', 'inherit'));
      expect(p('flex: 1 2 3 4'), {'flex': '1 2 3 4'});
      expect(p('flex: 10px 1'), {'flex': '10px 1'});
    });

    test('border 简写：三个部分顺序任意，省略的补初始值', () {
      final full = {
        for (final s in cssSides) ...{'border-$s-width': '1px', 'border-$s-style': 'solid', 'border-$s-color': 'red'},
      };
      for (final css in ['1px solid red', '1px red solid', 'solid 1px red', 'solid red 1px', 'red 1px solid', 'red solid 1px']) {
        expect(p('border: $css'), full, reason: css);
      }
      expect(p('border-top: dashed #EEE'), {'border-top-width': 'medium', 'border-top-style': 'dashed', 'border-top-color': '#EEE'});
      expect(p('border-left: 0'), {'border-left-width': '0', 'border-left-style': 'none', 'border-left-color': 'currentcolor'});
      expect(p('border: 2px dashed rgb(0, 0, 0)')['border-right-color'], 'rgb(0, 0, 0)');
      expect(p('border: thin papayawhip')['border-top-color'], 'papayawhip', reason: '没收录的颜色名也认');
      expect(p('border: none').length, 12);
      // 拆不了的原样保留
      expect(p('border: 1px 2px solid'), {'border': '1px 2px solid'});
      expect(p('border: 1px solid red blue'), {'border': '1px solid red blue'});
      expect(p('border: var(--b)'), {'border': 'var(--b)'});
    });

    test('background 只在单个颜色时翻成 background-color；font 不拆', () {
      for (final c in ['#fff', '#FFFFFF80', 'red', 'rgb(1, 2, 3)', 'rgba(0,0,0,.5)', 'hsl(120 50% 50%)', 'transparent', 'currentColor']) {
        expect(p('background: $c'), {'background-color': c}, reason: c);
      }
      for (final v in ['url(a.png)', 'red url(a.png)', 'linear-gradient(red, blue)', 'none', 'var(--bg)', 'rgb(0,0,0) no-repeat']) {
        expect(p('background: $v'), {'background': v}, reason: v);
      }
      expect(p('font: italic bold 12px/1.5 serif; font-size: 20px'), {'font': 'italic bold 12px/1.5 serif', 'font-size': '20px'});
    });

    test('后写的盖住先写的（和 CSS 的规矩一样）', () {
      expect(p('margin-top: 1px; margin: 2px')['margin-top'], '2px');
      expect(p('margin: 2px; margin-top: 1px')['margin-top'], '1px');
      expect(p('margin-top: 1px; margin: var(--m)'), {'margin': 'var(--m)'}, reason: '拆不了的简写把之前的单项盖掉');
      expect(p('margin: var(--m); margin: 3px').containsKey('margin'), isFalse);
      expect(p('margin: var(--m); margin-top: 3px'), {'margin': 'var(--m)', 'margin-top': '3px'});
      expect(p('border-top: var(--t); border: 1px solid red').containsKey('border-top'), isFalse);
      expect(p('border: 1px solid red; border-width: var(--w)').keys.where((k) => k.endsWith('-width')), ['border-width']);
      expect(p('background-color: red; background-image: url(a); background: url(b)'), {'background': 'url(b)'});
      expect(p('background: url(b); background: blue'), {'background-color': 'blue'});
    });

    test('!important：保留，写法统一，拆简写时带到每个单项', () {
      expect(p('color: red !important'), {'color': 'red !important'});
      expect(p('color: red!IMPORTANT'), {'color': 'red !important'});
      expect(p('margin: 1px 2px ! important'), four('margin-', ['1px !important', '2px !important', '1px !important', '2px !important']));
      expect(p('background: red !important'), {'background-color': 'red !important'});
      expect(p('border: 1px solid !important')['border-left-color'], 'currentcolor !important');
      expect(p('weird-prop: x !important'), {'weird-prop': 'x !important'});
    });

    test('认不出的属性一条都不丢', () {
      const css = '-webkit-line-clamp: 2; --brand: #f00; transform: rotate(3deg); aspect-ratio: 16 / 9; made-up: whatever(1, 2)';
      expect(p(css), {'-webkit-line-clamp': '2', '--brand': '#f00', 'transform': 'rotate(3deg)', 'aspect-ratio': '16 / 9', 'made-up': 'whatever(1, 2)'});
    });

    test('括号、引号里的分号和冒号不会把一条声明切成几条', () {
      final r = parseCss('color: red; background-image: url(data:image/png;base64,AAAA); width: calc(1px + 2px); content: "a; b: c"; height: 2px');
      // 带分号的值按页面文件的规矩不能存，整条丢掉并告诉调用方；前后的声明不受影响。
      expect(r.declarations, {'color': 'red', 'width': 'calc(1px + 2px)', 'height': '2px'});
      expect(r.dropped, hasLength(2));
      expect(r.dropped[0], startsWith('background-image: url(data:image/png;base64,AAAA)'));
      expect(r.dropped[1], startsWith('content: "a; b: c"'));
      expect(p('background-image: url(http://a.b/c.png)'), {'background-image': 'url(http://a.b/c.png)'});
      expect(p("content: ':'; quotes: '\\'' ':'"), {'content': "':'", 'quotes': "'\\'' ':'"});
    });

    test('丢掉的条目都有记录', () {
      final r = parseCss('color: red; oops; 中文: 1; width: ; x: a<b; y: a>b; z: !important; UP: 1; bad name: 2; long: ${'a' * 501}');
      expect(r.declarations, {'color': 'red', 'up': '1'});
      expect(r.dropped, hasLength(8));
      expect(r.dropped[0], 'oops（没有冒号，不是一条声明）');
      expect(r.dropped[1], contains('属性名不合法'));
      expect(r.dropped[2], contains('没有值'));
      expect(r.dropped[3], contains('不能有'));
      expect(r.dropped[5], contains('没有值'));
      expect(r.dropped[7], contains('值太长'));
      expect(r.dropped[7].length, lessThan(120), reason: '提示里的原文要截短');
    });

    test('换行：引号外面的收成空格，引号里面的整条丢掉', () {
      expect(p('box-shadow: 0 1px 2px red,\n\t  0 2px 4px blue;\ncolor:\nred'), {'box-shadow': '0 1px 2px red, 0 2px 4px blue', 'color': 'red'});
      final r = parseCss('content: "a\nb"; color: red');
      expect(r.declarations, {'color': 'red'});
      expect(r.dropped.single, contains('换行'));
    });

    test('坏输入不抛异常', () {
      final bad = <String>[
        '', ' ', ';', ';;;;', ':', '::', ': red', 'color', 'color:', 'color: red; garbage', '{', '}', '{}', '}{', 'a { b { c: d } }', 'a { color: red', //
        'color: red }', 'width: calc(1px', 'width: calc(1px; height: 2px', 'width: 1px); height: 2px', 'content: "abc', "content: 'abc; x: y", '/* 没收尾', '/*', '*/', //
        'a: b\\', '\\', '"', "'", '(', ')', '((((', '!important', 'margin:', 'margin: !important', 'border: / / /', 'border-radius: /', 'flex: ', '\u0000: \u0000', '💥: 💥', //
        'margin: ${'1px ' * 5000}', 'x: ${'(' * 3000}', 'a: b;' * 20000, '${'{' * 2000}${'}' * 2000}', 'color: red\r\n;\r\nwidth: 1px',
      ];
      for (final css in bad) {
        final r = parseCss(css);
        expect(LcNode.cleanStyle(r.declarations), r.declarations, reason: css.length > 40 ? css.substring(0, 40) : css);
        expect(declarationsToCss(r.declarations), isA<String>());
      }
      expect(p('width: 1px); height: 2px'), {'width': '1px)', 'height': '2px'}, reason: '多出来的右括号不吞掉后面的声明');
      expect(parseCss('width: calc(1px; height: 2px').declarations, isEmpty, reason: '没配平的左括号：后面的都算进这一条，带分号所以丢掉');
      expect(p('a: b;' * 20000), {'a': 'b'});
    });
  });

  group('生成', () {
    test('四边能合并就合并成最短的写法，缺边就保持单项', () {
      expect(w(four('margin-', ['1px', '1px', '1px', '1px'])), 'margin: 1px;');
      expect(w(four('margin-', ['1px', '2px', '1px', '2px'])), 'margin: 1px 2px;');
      expect(w(four('margin-', ['1px', '2px', '3px', '2px'])), 'margin: 1px 2px 3px;');
      expect(w(four('margin-', ['1px', '2px', '3px', '4px'])), 'margin: 1px 2px 3px 4px;');
      expect(w(four('margin-', ['1px', '2px', '1px', '4px'])), 'margin: 1px 2px 1px 4px;');
      expect(w({'padding-top': '1px', 'padding-left': '2px'}), 'padding-top: 1px; padding-left: 2px;');
      expect(w({'top': '0', 'right': '0', 'bottom': '0', 'left': '0'}), 'inset: 0;');
      expect(w({'row-gap': '8px', 'column-gap': '8px'}), 'gap: 8px;');
      expect(w({'row-gap': '8px', 'column-gap': '4px'}), 'gap: 8px 4px;');
      expect(w({'overflow-x': 'hidden', 'overflow-y': 'auto'}), 'overflow: hidden auto;');
      expect(w({'overflow-y': 'auto'}), 'overflow-y: auto;');
      expect(w(p('border-radius: 4px 8px')), 'border-radius: 4px 8px;');
      expect(w(p('border-radius: 4px / 8px')), contains('border-top-left-radius: 4px 8px;'));
    });

    test('合并不了的情况：!important 不一致、带 var()、值不是单个词', () {
      expect(
        w({
          ...four('margin-', ['1px', '1px', '1px', '1px']),
          'margin-top': '1px !important',
        }),
        'margin-top: 1px !important; margin-right: 1px; margin-bottom: 1px; margin-left: 1px;',
      );
      expect(w(four('margin-', ['1px !important', '1px !important', '1px !important', '1px !important'])), 'margin: 1px !important;');
      expect(w(four('margin-', ['var(--a)', '1px', '1px', '1px'])), startsWith('margin-top: var(--a);'));
      expect(w(four('margin-', ['inherit', '1px', '1px', '1px'])), startsWith('margin-top: inherit;'));
      expect(w(four('margin-', ['inherit', 'inherit', 'inherit', 'inherit'])), 'margin: inherit;');
    });

    test('flex', () {
      expect(w({'flex-grow': '1', 'flex-shrink': '1', 'flex-basis': '0%'}), 'flex: 1;');
      expect(w({'flex-grow': '0', 'flex-shrink': '0', 'flex-basis': '16px'}), 'flex: 0 0 16px;');
      expect(w({'flex-grow': '1', 'flex-shrink': '1', 'flex-basis': 'auto'}), 'flex: 1 1 auto;');
      expect(w({'flex-grow': '1', 'flex-shrink': '0'}), 'flex-grow: 1; flex-shrink: 0;');
      expect(w({'flex-grow': 'calc(1)', 'flex-shrink': '1', 'flex-basis': '0%'}), 'flex-grow: calc(1); flex-shrink: 1; flex-basis: 0%;');
    });

    test('border：四边一样合成一条；不一样时按边、再按宽度 / 样式 / 颜色合并', () {
      expect(w(p('border: 1px solid red')), 'border: 1px solid red;');
      expect(w(p('border: solid 1px')), 'border: 1px solid;');
      expect(w(p('border: 0')), 'border: 0;');
      expect(w(p('border: none')), 'border: none;');
      expect(w(p('border-bottom: 1px solid #eee')), 'border-bottom: 1px solid #eee;');
      expect(w(p('border: 1px solid red; border-top-color: blue')), 'border-top: 1px solid blue; border-right: 1px solid red; border-bottom: 1px solid red; border-left: 1px solid red;');
      expect(w(p('border-width: 1px 2px; border-style: solid')), 'border-width: 1px 2px; border-style: solid;');
      expect(w(p('border-top-width: 1px; border-top-style: solid')), 'border-top-width: 1px; border-top-style: solid;');
      expect(w(p('border-top: 1px solid red; border-width: 2px')), 'border-top: 2px solid red; border-right-width: 2px; border-bottom-width: 2px; border-left-width: 2px;');
      expect(w(p('border: var(--b); border-top-width: 2px')), 'border: var(--b); border-top-width: 2px;', reason: '拆不了的简写排在单项前面');
    });

    test('背景色单独出现写成 background；有别的 background-* 就不合并', () {
      expect(w({'background-color': '#fff'}), 'background: #fff;');
      expect(w({'background-color': 'var(--c)'}), 'background-color: var(--c);');
      expect(w({'background-color': '#fff', 'background-image': 'url(a)'}), 'background-color: #fff; background-image: url(a);');
      expect(w(p('background: url(a); background-color: red')), 'background: url(a); background-color: red;');
    });

    test('顺序固定，和表里的先后无关；认不出的排最后并保持原来顺序', () {
      final a = p('zoom: 1; justify-content: center; color: red; aaa: 1; width: 1px; margin: 2px; position: relative; bbb: 2; flex: 1');
      const expected = 'position: relative; flex: 1; width: 1px; margin: 2px; color: red; justify-content: center; zoom: 1; aaa: 1; bbb: 2;';
      expect(w(a), expected);
      final reversed = Map.fromEntries(a.entries.toList().reversed);
      expect(w(reversed), expected.replaceFirst('zoom: 1; aaa: 1; bbb: 2', 'bbb: 2; aaa: 1; zoom: 1'));
      // 第 1 版导出的次序不能变
      expect(
        w(
          p(
            'justify-content: center; align-items: center; gap: 1px; text-align: left; font-weight: 600; font-size: 1px; border-radius: 1px; color: red; background: blue; margin: 1px; padding: 1px; height: 1px; min-width: 0; flex: 1',
          ),
        ),
        'flex: 1; min-width: 0; height: 1px; padding: 1px; margin: 1px; background: blue; color: red; border-radius: 1px; font-size: 1px; font-weight: 600; text-align: left; gap: 1px; align-items: center; justify-content: center;',
      );
    });

    test('多行 / 单行、缩进、空表', () {
      expect(declarationsToCss({}), '');
      expect(declarationsToCss({'color': 'red', 'width': '1px'}), 'width: 1px;\ncolor: red;');
      expect(declarationsToCss({'color': 'red', 'width': '1px'}, indent: '  '), '  width: 1px;\n  color: red;');
      expect(mergedDeclarations(p('margin: 1px; color: red')).map((e) => '${e.key}=${e.value}'), ['margin=1px', 'color=red']);
    });
  });

  group('往返稳定', () {
    void check(String css) {
      final x = p(css);
      final text = declarationsToCss(x);
      expect(p(text), x, reason: '$css → $text');
      expect(declarationsToCss(p(text)), text, reason: '再生成一次文字也不变：$css');
      expect(parseCss(text).dropped, isEmpty, reason: css);
      expect(LcNode.cleanStyle(x), x, reason: '每一条都存得进页面文件：$css');
      expect(p(w(x)), x, reason: '单行写法：$css');
    }

    test('${roundTripCases.length} 组手写的声明', () {
      expect(roundTripCases.length, greaterThanOrEqualTo(60));
      roundTripCases.forEach(check);
      check(roundTripCases.join('; '));
    });

    test('随机拼出来的 2000 组', () {
      final rnd = Random(20261124);
      const lengths = ['0', '1px', '8px', '-4px', '50%', '1.5em', 'auto', 'calc(100% - 8px)', 'var(--x)', 'inherit', '2rem !important'];
      const colors = ['red', '#fff', 'rgb(1, 2, 3)', 'currentcolor', 'transparent', 'var(--c)', 'papayawhip', 'initial'];
      const styles = ['none', 'solid', 'dashed', 'inset', 'unset'];
      String pick(List<String> l) => l[rnd.nextInt(l.length)];
      String some(List<String> l, int max) => [for (var i = 0; i <= rnd.nextInt(max); i++) pick(l)].join(' ');
      String one() {
        switch (rnd.nextInt(16)) {
          case 0:
            return '${pick(['margin', 'padding', 'inset', 'border-width', 'border-radius'])}: ${some(lengths, 5)}';
          case 1:
            return '${pick(['margin', 'padding', 'border'])}-${pick(cssSides)}${pick(['', '-width'])}: ${pick(lengths)}';
          case 2:
            return '${pick(['border', 'border-top', 'border-left'])}: ${([pick(lengths), pick(styles), pick(colors)]..shuffle(rnd)).take(1 + rnd.nextInt(3)).join(' ')}';
          case 3:
            return 'border-${pick(cssSides)}-${pick(['style: ${pick(styles)}', 'color: ${pick(colors)}'])}';
          case 4:
            return 'border-${pick(['style: ${some(styles, 4)}', 'color: ${some(colors, 4)}'])}';
          case 5:
            return 'flex: ${some(['0', '1', '2', 'auto', 'none', '10px', '0%', 'initial'], 3)}';
          case 6:
            return '${pick(['flex-grow', 'flex-shrink', 'flex-basis'])}: ${pick(['0', '1', 'auto', '0%', '10px'])}';
          case 7:
            return '${pick(['gap', 'overflow'])}: ${some(['4px', '8px', 'hidden', 'auto', 'inherit'], 2)}';
          case 8:
            return 'background: ${pick([...colors, 'url(a.png)', 'none'])}';
          case 9:
            return 'background-${pick(['color: ${pick(colors)}', 'image: url(b.png)', 'size: cover'])}';
          case 10:
            return 'border-${pick(cssCorners)}-radius: ${some(lengths, 2)}';
          case 11:
            return '${pick(['row-gap', 'column-gap', 'overflow-x', 'top', 'left', 'width'])}: ${pick(lengths)}';
          case 12:
            return '${pick(['x-custom', '--v', 'transform', 'font'])}: ${some(['a', 'b(1, 2)', '"q r"', '12px/1.5'], 3)}';
          case 13:
            return 'border-radius: ${some(lengths, 4)} / ${some(lengths, 4)}';
          default:
            return '${pick(['color', 'opacity', 'display', 'font-size'])}: ${pick([...colors, ...lengths])}${pick(['', '', ' !important'])}';
        }
      }

      for (var i = 0; i < 2000; i++) {
        check([for (var k = 0; k <= rnd.nextInt(8); k++) one()].join('; '));
      }
    });

    test('mergeDeclarations / canonicalDeclarations：结果是规范写法，不改传进来的表', () {
      final base = p('margin: 1px; color: red; background: #fff');
      final over = {'margin': '2px 3px', 'background': 'url(a.png)', 'x': ' y '};
      final copy = Map.of(base);
      final merged = mergeDeclarations(base, over);
      expect(base, copy);
      expect(merged, {
        ...four('margin-', ['2px', '3px', '2px', '3px']),
        'color': 'red',
        'background': 'url(a.png)',
        'x': 'y',
      });
      expect(canonicalDeclarations({'border': '1px solid #ff0000', 'margin-top': '8px'}), {...p('border: 1px solid #ff0000'), 'margin-top': '8px'});
      for (final css in roundTripCases) {
        expect(canonicalDeclarations(p(css)), p(css), reason: '已经是规范写法的再整理一次不变：$css');
      }
    });
  });

  group('底层扫描和颜色', () {
    test('切词、切分隔符、去注释、取规则体', () {
      expect(cssTokens('  1px  solid\trgb(0, 0, 0) "a b" '), ['1px', 'solid', 'rgb(0, 0, 0)', '"a b"']);
      expect(cssTokens(''), isEmpty);
      expect(cssTokens('a(b c'), ['a(b c']);
      expect(splitTopLevel('a;b(c;d);"e;f";g', ';'), ['a', 'b(c;d)', '"e;f"', 'g']);
      expect(splitTopLevel('', ';'), ['']);
      expect(stripCssComments('a/*x*/b/*y'), 'a b ');
      expect(cssRuleBody('x { a: b } y { c: d }'), (body: ' a: b ', rest: ' y { c: d }'));
      expect(cssRuleBody('a: b'), (body: 'a: b', rest: ''));
      expect(collapseCssSpace('  a \n b  "c  d"  '), 'a b "c  d"');
      expect(splitImportant('red ! IMPORTANT '), (value: 'red', important: true));
      expect(splitImportant(' red '), (value: 'red', important: false));
      expect(withImportant('red', true), 'red !important');
      expect(isCssNumber('1.5') && isCssNumber('-2') && isCssNumber('.5') && !isCssNumber('1px') && !isCssNumber(''), isTrue);
      expect(isCssWideKeyword('INHERIT') && !isCssWideKeyword('auto'), isTrue);
    });

    test('简写登记：拆成哪些单项、边框的词怎么归类', () {
      expect(cssLonghands('margin'), ['margin-top', 'margin-right', 'margin-bottom', 'margin-left']);
      expect(cssLonghands('border'), hasLength(12));
      expect(cssLonghands('color'), isEmpty);
      expect(cssLonghands('font'), isEmpty);
      expect(cssCovered('border'), hasLength(19));
      expect(expandShorthand('color', 'red'), isNull);
      expect(expandShorthand('gap', '1px 2px 3px'), isNull);
      expect(
        [
          for (final t in ['2px', '.5em', 'thin', 'calc(1px)', 'SOLID', 'red', '#fff', 'rgb(0,0,0)', 'inherit', '"x"']) cssBorderPartKind(t),
        ],
        ['width', 'width', 'width', 'width', 'style', 'color', 'color', 'color', null, null],
      );
    });

    test('颜色：认不认得出、转 0xAARRGGBB、转回文字', () {
      expect(cssColorToArgb('#f00'), 0xFFFF0000);
      expect(cssColorToArgb('#F008'), 0x88FF0000);
      expect(cssColorToArgb('#058654'), 0xFF058654);
      expect(cssColorToArgb('#05865480'), 0x80058654);
      expect(cssColorToArgb('rgb(255, 0, 128)'), 0xFFFF0080);
      expect(cssColorToArgb('rgba(0, 0, 0, .2)'), 0x33000000);
      expect(cssColorToArgb('rgb(0 0 255 / 50%)'), 0x800000FF);
      expect(cssColorToArgb('rgb(100%, 0%, 0%)'), 0xFFFF0000);
      expect(cssColorToArgb('RGB(300, -5, 0)'), 0xFFFF0000);
      expect(cssColorToArgb('hsl(120, 100%, 50%)'), 0xFF00FF00);
      expect(cssColorToArgb('hsla(240deg 100% 50% / 0.5)'), 0x800000FF);
      expect(cssColorToArgb('transparent'), 0x00000000);
      expect(cssColorToArgb(' White '), 0xFFFFFFFF);
      for (final bad in [null, '', 'currentcolor', 'var(--c)', 'papayawhip', '#ff', '#gggggg', 'rgb(1, 2)', 'rgb(a, b, c)', 'rgb(1, 2, 3, 4, 5)', 'hsl(1, 2, 3)', 'rgb(']) {
        expect(cssColorToArgb(bad), isNull, reason: '$bad');
      }
      expect(argbToCss(0xFF058654), '#058654');
      expect(argbToCss(0x80058654), '#05865480');
      expect(argbToCss(0x00000000), '#00000000');
      for (final c in ['#fff', 'red', 'RGB(1,2,3)', 'hsl(1 2% 3%)', 'transparent', 'CurrentColor', 'oklch(0.5 0.2 30)']) {
        expect(isCssColor(c), isTrue, reason: c);
      }
      for (final c in ['', 'url(a)', 'red blue', 'rgb(0,0,0) x', 'rgb(0,0,0', 'var(--c)', 'none', 'papayawhip', '#12345']) {
        expect(isCssColor(c), isFalse, reason: c);
      }
    });
  });
}
