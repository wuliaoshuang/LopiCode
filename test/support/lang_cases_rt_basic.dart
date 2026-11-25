// 语言核心一致性用例（二之一）：第 4 版新加的小库函数——类型、转换、数学、随机数、文字。每个至少一例，带边界。
import 'package:lopicode/lang/lang.dart';

import 'lang_conformance.dart';

LExpr ls(List<Object?> xs) => list([for (final x in xs) lx(x)]);
LExpr lx(Object? x) => switch (x) {
  final LExpr e => e,
  final num v => n(v),
  final String s => t(s),
  final List<Object?> xs => ls(xs),
  final Map<String, Object?> m => dict({for (final e in m.entries) e.key: lx(e.value)}),
  _ => LLit(x),
};

/// 调小库：参数可以直接写 Dart 的数字、文字、列表、字典。
LExpr f(String fn, [List<Object?> args = const []]) => rt(fn, [for (final a in args) lx(a)]);

final List<LangCase> kLangRtBasicCases = [
  vals('类型判断 isType', [
    (
      ls([
        f('isType', [1, 'number']),
        f('isType', ['1', 'number']),
        f('isType', ['1', 'text']),
        f('isType', [true, 'bool']),
        f('isType', [null, 'null']),
      ]),
      '[true,false,true,true,true]',
    ),
    (
      ls([
        f('isType', [[], 'list']),
        f('isType', [<String, Object?>{}, 'dict']),
        f('isType', [[], 'dict']),
        f('isType', [0, 'bool']),
        f('isType', [1, '别的']),
      ]),
      '[true,true,false,false,false]',
    ),
    (
      ls([
        f('isType', [
          f('fromJson', ['[1]']),
          'list',
        ]),
        f('isType', [
          f('fromJson', ['{}']),
          'dict',
        ]),
        f('isType', [
          f('fromJson', ['1.5']),
          'number',
        ]),
      ]),
      '[true,true,true]',
    ),
  ]),
  vals('转换 toNumber / toText / toBool / copy', [
    (
      ls([
        f('toNumber', ['12']),
        f('toNumber', [' 1.5 ']),
        f('toNumber', ['abc']),
        f('toNumber', [true]),
        f('toNumber', [null]),
        f('toNumber', [[]]),
        f('toNumber', ['1e3']),
        f('toNumber', ['0x10']),
      ]),
      '[12,1.5,0,1,0,0,1000,0]',
    ),
    (
      ls([
        f('toText', [1.5]),
        f('toText', [null]),
        f('toText', [true]),
        f('toText', [
          [1, '二'],
        ]),
        f('toText', [
          {'a': 1},
        ]),
        f('toText', [10]),
      ]),
      '["1.5","","true","[1,\\"二\\"]","{\\"a\\":1}","10"]',
    ),
    (
      ls([
        f('toBool', [0]),
        f('toBool', ['']),
        f('toBool', ['0']),
        f('toBool', [[]]),
        f('toBool', [null]),
        f('toBool', [-1]),
      ]),
      '[false,false,true,true,false,true]',
    ),
    (
      f('copy', [
        [
          1,
          {
            'a': [2],
          },
        ],
      ]),
      '[1,{"a":[2]}]',
    ),
  ]),
  vals('数学：乘方、取整、绝对值、平方根、最大最小', [
    (
      ls([
        f('pow', [2, 8]),
        f('pow', [2, -1]),
        f('pow', [0, 0]),
        f('pow', [-2, 3]),
        f('pow', ['3', '2']),
        f('pow', [-1, 0.5]),
      ]),
      '[256,0.5,1,-8,9,0]',
    ),
    (
      ls([
        f('round', [2.5]),
        f('round', [-2.5]),
        f('round', [2.4]),
        f('round', [-2.6]),
        f('round', [0.5]),
        f('round', [-0.5]),
        f('round', [1e20]),
        f('round', ['3.5']),
        f('round', [0.49999999999999994]),
      ]),
      '[3,-3,2,-3,1,-1,1e20,4,0]',
    ),
    (
      ls([
        f('floor', [2.7]),
        f('floor', [-2.1]),
        f('ceil', [2.1]),
        f('ceil', [-2.7]),
        f('floor', [3]),
        f('ceil', [-0.5]),
        f('floor', ['x']),
      ]),
      '[2,-3,3,-2,3,0,0]',
    ),
    (
      ls([
        f('abs', [-3.5]),
        f('abs', [3]),
        f('abs', ['-2']),
        f('abs', [0]),
      ]),
      '[3.5,3,2,0]',
    ),
    (
      ls([
        f('sqrt', [16]),
        f('sqrt', [2]),
        f('sqrt', [-4]),
        f('sqrt', [0]),
      ]),
      '[4,1.41421356237,0,0]',
    ),
    (
      ls([
        f('max', [1, 2]),
        f('max', ['10', 9]),
        f('min', [1, 2]),
        f('min', [-1, 'x']),
        f('max', [2, 2]),
      ]),
      '[2,10,1,-1,2]',
    ),
  ]),
  LangCase(
    '随机数：含两头、两边可以反着给、小数去掉',
    [
      let('ok', yes),
      let('seen', dict()),
      LRepeat(n(300), [
        let('r', f('random', [3, 1])),
        iff(LLogic('or', bin('<', v('r'), n(1)), bin('>', v('r'), n(3))), [set('ok', no)]),
        iff(bin('!=', v('r'), f('floor', [v('r')])), [set('ok', no)]),
        run(f('dictSet', [v('seen'), v('r'), yes])),
      ]),
      log(v('ok')),
      logJson(f('dictKeys', [v('seen')])),
      logJson(
        ls([
          f('random', [5, 5]),
          f('random', [2.9, 2.1]),
          f('random', ['x', 0]),
          f('random', [-1.5, -1.2]),
        ]),
      ),
    ],
    ['true', '["1","2","3"]', '[5,2,0,-1]'],
  ),
  vals('文字：按码点数', [
    (
      ls([
        f('charAt', ['héllo😀', 1]),
        f('charAt', ['héllo😀', 5]),
        f('charAt', ['abc', 3]),
        f('charAt', ['abc', -1]),
        f('charAt', [123, 0]),
        f('charAt', ['abc', 1.9]),
        f('charAt', ['abc', '2']),
      ]),
      '["é","😀",null,null,"1","b","c"]',
    ),
    (
      ls([
        f('substring', ['a😀b中c', 1, 3]),
        f('substring', ['hello', 2, 99]),
        f('substring', ['hello', -5, 2]),
        f('substring', ['hello', 3, 1]),
        f('substring', ['hello', 0, 0]),
        f('substring', ['', 0, 5]),
        f('substring', [12345, 1, 3]),
      ]),
      '["😀b","llo","he","","","","23"]',
    ),
    (
      ls([
        f('contains', ['hello', 'ell']),
        f('contains', ['hello', '']),
        f('contains', ['hello', 'x']),
        f('contains', [12345, 34]),
        f('contains', ['中文😀', '😀']),
      ]),
      '[true,true,false,true,true]',
    ),
    (
      ls([
        f('startsWith', ['hello', 'he']),
        f('startsWith', ['hello', '']),
        f('startsWith', ['he', 'hello']),
        f('endsWith', ['hello', 'lo']),
        f('endsWith', ['hello', '']),
        f('endsWith', ['😀中', '中']),
        f('endsWith', ['a', 'ba']),
      ]),
      '[true,true,false,true,true,true,false]',
    ),
    (
      ls([
        f('indexOf', ['a😀b😀c', 'b']),
        f('indexOf', ['hello', 'l']),
        f('indexOf', ['hello', 'x']),
        f('indexOf', ['hello', '']),
        f('indexOf', ['', 'a']),
        f('indexOf', ['😀😀中', '中']),
      ]),
      '[2,2,-1,0,-1,2]',
    ),
    (
      ls([
        f('replace', ['aaa', 'aa', 'b']),
        f('replace', ['a.b.c', '.', '-']),
        f('replace', ['abc', '', 'x']),
        f('replace', ['abc', 'x', 'y']),
        f('replace', [r'a$1b', 'a', r'$0\1']),
        f('replace', ['😀中😀', '😀', '']),
        f('replace', [1212, 1, 'x']),
      ]),
      r'''["ba","a-b-c","abc","abc","$0\\1$1b","中","x2x2"]''',
    ),
    (
      ls([
        f('split', ['a,b,,c', ',']),
        f('split', [',a,', ',']),
        f('split', ['a😀中', '']),
        f('split', ['', ',']),
        f('split', ['', '']),
        f('split', ['abc', 'x']),
        f('split', ['a--b', '--']),
        f('split', ['a.b', '.']),
      ]),
      '[["a","b","","c"],["","a",""],["a","😀","中"],[""],[],["abc"],["a","b"],["a","b"]]',
    ),
    (
      ls([
        f('trim', ['  a b \t\r\n']),
        f('trim', ['\u3000全角空格不去\u00a0']),
        f('trim', ['   ']),
        f('trim', ['']),
        f('trim', [5]),
      ]),
      '["a b","\u3000全角空格不去\u00a0","","","5"]',
    ),
    (
      ls([
        f('upper', ['abc Xyz é ß ı 中']),
        f('lower', ['ABC Xyz É İ Σ 中']),
        f('upper', [true]),
        f('lower', ['{[@`']),
      ]),
      '["ABC XYZ é ß ı 中","abc xyz É İ Σ 中","TRUE","{[@`"]',
    ),
    (
      ls([
        f('repeatText', ['ab', 3]),
        f('repeatText', ['ab', 0]),
        f('repeatText', ['ab', -1]),
        f('repeatText', ['😀', 2.9]),
        f('repeatText', ['', 100]),
        f('size', [
          f('repeatText', ['ab', 99999]),
        ]),
      ]),
      '["ababab","","","😀😀","",20000]',
    ),
    (
      ls([
        f('template', [
          '你好 {name}，{n} 岁',
          {'name': '霜', 'n': 3},
        ]),
        f('template', [
          '{没有} {a',
          {'a': 1},
        ]),
        f('template', [
          '{a}{a}}{',
          {
            'a': [1],
          },
        ]),
        f('template', ['{a}', 5]),
        f('template', [
          '{}',
          {'': '空键'},
        ]),
        f('template', [
          '{a}',
          {'a': '{b}', 'b': '不会再换'},
        ]),
        f('template', [
          '{{a}}',
          {'a': 1},
        ]),
        f('template', [
          '{a}',
          {'a': null},
        ]),
      ]),
      '["你好 霜，3 岁","{没有} {a","[1][1]}{","{a}","空键","{b}","{1}",""]',
    ),
  ]),
];
