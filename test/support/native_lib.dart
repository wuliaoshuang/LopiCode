// 带手写代码的库的验收样例（积木第 5 版·第四轮）：一个文字写法的库，两个手写函数（一个不用等、一个声明“要等”），
// 五种语言各一份；外加用它的文档。lib_native_test.dart（规矩、放行、真跑）和界面测试共用。
import 'dart:convert';

import 'backend_core_samples.dart';
import 'backend_lang_blocks.dart';
import 'user_libs.dart';

const String kLibHand = 'shuang/hand';

const Map<String, String> _join = {
  'node': 'module.exports = function (s, n) {\n  return Array.from({ length: Number(n) }, () => s).join("!");\n};\n',
  'python': 'def run(s, n):\n    return "!".join([s] * n)\n',
  'php': '<?php\nreturn function (string \$s, int \$n): string {\n    return implode("!", array_fill(0, \$n, \$s));\n};\n',
  'go': 'package main\n\nimport "strings"\n\nfunc __NAME__(s string, n int64) string {\n\tparts := make([]string, 0, n)\n\tfor i := int64(0); i < n; i++ {\n\t\tparts = append(parts, s)\n\t}\n\treturn strings.Join(parts, "!")\n}\n',
  'java': 'final class __NAME__ {\n  static String run(String s, long n) {\n    StringBuilder b = new StringBuilder();\n    for (long i = 0; i < n; i++) {\n      if (i > 0) b.append("!");\n      b.append(s);\n    }\n    return b.toString();\n  }\n}\n',
};

const Map<String, String> _twice = {
  'node': 'module.exports = function (n) {\n  return BigInt(n) * 2n;\n};\n',
  'python': 'def run(n):\n    return n * 2\n',
  'php': '<?php\nreturn function (int \$n): int {\n    return \$n * 2;\n};\n',
  'go': 'package main\n\nfunc __NAME__(n int64) int64 {\n\treturn n * 2\n}\n',
  'java': 'final class __NAME__ {\n  static long run(long n) {\n    return n * 2;\n  }\n}\n',
};

const Map<String, String> _ext = {'node': 'js', 'python': 'py', 'php': 'php', 'go': 'go', 'java': 'java'};

/// 库的文件。`only`＝只带这几种语言的手写文件；`manifest`＝往清单上盖的键（做“写错了”的样例用）。
Map<String, String> handLibFiles({Iterable<String>? only, Map<String, Object?> manifest = const {}, String? nodeJoin}) {
  final langs = [...(only ?? _ext.keys)];
  final lib = <String, Object?>{
    'kind': 'lopicode-lib',
    'format': 1,
    'id': kLibHand,
    'name': '手写示例',
    'version': '1.0.0',
    'author': '霜霜',
    'rules': 2,
    'modules': [
      {'file': 'modules/hand.lc', 'name': '手写示例'},
    ],
    'blocks': ['blocks.json'],
    'native': {
      'allowed': true,
      'functions': [
        {
          'name': 'join',
          'params': ['文字', '整数'],
          'returns': '文字',
          'waits': false,
          'files': {for (final l in langs) l: 'native/join.${_ext[l]}'},
        },
        {
          'name': 'twice',
          'params': ['整数'],
          'returns': '整数',
          'waits': true,
          'files': {for (final l in langs) l: 'native/twice.${_ext[l]}'},
        },
      ],
    },
    ...manifest,
  };
  return {
    'lib.json': '${const JsonEncoder.withIndent('  ').convert(lib)}\n',
    'modules/hand.lc':
        '(模块 手写示例\n'
        '  (宿主 手写.$kLibHand.join ((s 文字) (n 整数)) -> 文字)\n'
        '  (宿主 手写.$kLibHand.twice ((n 整数)) -> 整数)\n'
        '  (公开 (函数 连起来 ((s 文字) (n 整数)) -> 文字 (返回 (宿 手写.$kLibHand.join s n))))\n'
        '  (公开 (函数 两倍 ((n 整数)) -> 整数 (返回 (宿 手写.$kLibHand.twice n)))))\n',
    'blocks.json': jsonEncode({
      'blocks': [
        {
          'id': 'join',
          'how': 'call',
          'of': '连起来',
          'args': ['s', 'n'],
          'look': {'name': '连起来', 'shape': 'value', 'template': '把 {s} 连 {n} 遍'},
        },
        {
          'id': 'twice',
          'how': 'call',
          'of': '两倍',
          'args': ['n'],
          'look': {'name': '两倍', 'shape': 'value', 'template': '{n} 的两倍（手写的）'},
        },
      ],
    }),
    for (final l in langs) 'native/join.${_ext[l]}': l == 'node' && nodeJoin != null ? nodeJoin : _join[l]!,
    for (final l in langs) 'native/twice.${_ext[l]}': _twice[l]!,
  };
}

/// 用它的文档。
J handUserDoc() => {
  ...coreDoc(
    '用手写示例',
    main: [
      log(lx(kLibHand, 'join', {'s': tx('嗨'), 'n': nm(3)})),
      say([
        tx('两倍 '),
        lx(kLibHand, 'twice', {'n': nm(21)}),
      ]),
    ],
  ),
  'version': 5,
  'uses': [use(kLibHand)],
};
const String kHandWant = '嗨!嗨!嗨\n两倍 42\n';
