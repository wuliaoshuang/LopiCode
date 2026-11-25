// 函数生成出来的代码长什么样（文本级检查）：五种语言各自的闭包写法、默认参数、剩下的全收、函数值。
// Node / Python / Go / Java 另有真跑的测试（lang_conformance_func_test.dart）；PHP 本机没有，只有这里的文本检查，**未实测**。
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/lang/lang.dart';

import 'support/lang_cases_func.dart';
import 'support/lang_cases_hof.dart';
import 'support/lang_conformance.dart';

String _script(String language) => langGenFor(language)!.script(casesProgram([...kLangFuncCases, ...kLangHofCases]));

void _has(String text, List<String> pieces, String language) {
  for (final piece in pieces) {
    expect(text, contains(piece), reason: '$language 里应该有：$piece');
  }
}

void main() {
  test('五种语言都能生成整份函数用例，没有“还不支持”', () {
    for (final language in kLangTargets) {
      expect(() => _script(language), returnsNormally, reason: language);
    }
  });

  test('node：原生闭包、默认参数、剩下的全收；函数当值才包一层', () {
    _has(_script('node'), [
      'function f7_greet(v_name, v_greeting = "你好", v_mark = "！") {',
      'function f8_sum(v_first, ...v_more) {',
      'const lcF1 = lc.fn("", 0, 0, () => {',
      'return lc.fn("", 1, 1, (v_x) => lc.call(v_f, lc.call(v_g, v_x)));',
    ], 'node');
  });

  test('python：里层改外层变量加 nonlocal，改模块级变量加 global；带函数体的匿名函数是嵌套的 def', () {
    final s = _script('python');
    _has(s, ['nonlocal v_count', 'nonlocal v_hits', 'global g4_total', 'def lcF1(', 'def f8_sum(v_first, *v_more):'], 'python');
    expect(RegExp(r'^\s*nonlocal g\d', multiLine: true).hasMatch(s), isFalse, reason: '模块级变量不用 nonlocal');
  });

  test('go：函数值用小库的 lc.NewFn / lc.Call；默认值在调用处补齐；剩下的全收在调用处包成列表', () {
    _has(_script('go'), [
      'lcF1 := lc.NewFn("", 0, 0, func(lcA1 []any) any {',
      'lc.Call(v_inner)',
      'func f7_greet(v_name any, v_greeting any, v_mark any) any {',
      'f7_greet("丙", "你好", "！")',
      'func f8_sum(v_first any, v_more any) any {',
      'f8_sum(1.0, lc.ListOf())',
    ], 'go');
  });

  test('java：被里层改写的外层变量装盒子，参数装盒子时换名；函数值用 LcLang.fn / LcLang.call', () {
    _has(_script('java'), [
      'final Object[] v_count = {null};',
      'static Object f3_makeAdder(Object lcP_total) {',
      'final Object[] v_total = {lcP_total};',
      'final Lc.Fn lcF1 = LcLang.fn("", 0, 0, (lcA1) -> {',
      'LcLang.call(v_inner);',
      'f7_greet("丙", "你好", "！")',
      'f8_sum(1.0, LcLang.listOf())',
      'LcLang.fn("greet", 1, 3, (lcA) -> f7_greet(LcLang.arg(lcA, 0), LcLang.argOr(lcA, 1, "你好"), LcLang.argOr(lcA, 2, "！")))',
    ], 'java');
  });

  group('php（未实测，只查文本）', () {
    final s = _script('php');

    test('闭包：用到的外层变量按引用写进 use；模块级变量用 global', () {
      _has(s, [r'function () use (&$v_hits) {', r'global $g4_total;', r'global $g4_total, $g4_label;', r'function ($v_x) use (&$v_g, &$v_f) { return lc_call($v_f, lc_call($v_g, $v_x)); }'], 'php');
      expect(s, isNot(contains('=>')), reason: '不用箭头函数：它按值抓变量，改不了外面的');
    });

    test('默认参数原生写；剩下的全收进来先转成列表', () {
      _has(s, [
        r'function f7_greet($v_name, $v_greeting = "你好", $v_mark = "！")',
        r'function f7_kinds($v_a = 1.5, $v_b = true, $v_c = null, $v_d = "引\"号\\")',
        r'function f8_sum($v_first, ...$v_more)',
        r'$v_more = lc_listOf(...$v_more);',
        r'function f8_mix($v_a, $v_b = "B", ...$v_tail)',
      ], 'php');
    });

    test('函数值：lc_fn 包一层、lc_call 调；有名字的函数直接调', () {
      _has(s, [r'$lcF1 = lc_fn("", 0, 0, function ()', r'lc_call($v_inner);', 'lc_log(f1_fact(5.0));', "lc_fn(\"double\", 1, 1, 'f5_double')"], 'php');
    });

    test('没有返回值的函数不补 return；提前返回写 return null', () {
      expect(s, contains('function f9_shout(\$v_x)\n{\n    lc_log(lc_join(\$v_x, "!"));\n}\n'));
      expect(s, contains('        lc_log("负数，不干了");\n        return null;\n'));
    });

    test('括号成对；字符串里没有会被 PHP 当成变量的 \$', () {
      for (final (open, close) in [('{', '}'), ('(', ')')]) {
        expect(open.allMatches(s).length, close.allMatches(s).length, reason: '$open$close');
      }
      // 双引号字符串里的 $ 都得带反斜杠（不然 PHP 当成变量）：一个字一个字走，认出字符串再看
      int bare(String text) {
        var count = 0;
        String? quote;
        for (var i = 0; i < text.length; i++) {
          final ch = text[i];
          if (quote != null && ch == r'\') {
            i++;
          } else if (quote == null && (ch == '"' || ch == "'")) {
            quote = ch;
          } else if (ch == quote) {
            quote = null;
          } else if (quote == '"' && ch == r'$') {
            count++;
          }
        }
        return count;
      }

      expect(bare(r'lc_log("a$b");'), 1, reason: '这个查法认得出没转义的');
      expect(bare(s), 0);
      final tricky = langGenFor('php')!.script([
        LModule(
          decls: [
            fn(
              'price',
              [p('unit', or: r'$5 "x"')],
              [
                ret(rt('join', [t(r'共 $'), v('unit')])),
              ],
            ),
          ],
          body: [log(callN('price'))],
        ),
      ]);
      expect(tricky, contains(r'$v_unit = "\$5 \"x\""'));
      expect(tricky, contains(r'"共 \$"'));
      expect(bare(tricky), 0);
    });
  });
}
