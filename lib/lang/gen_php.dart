/// PHP 生成器。小库：`lc_runtime.php`、`lc_json.php`（值的规矩）＋ `lc_lang.php`（第 4 版新加的）。
///
/// **这份生成器和它的小库还没有实际运行过**（本机没有 PHP）：只做过文本级的检查。
/// 列表在 PHP 里是 `LcList` 对象（不是 PHP 数组）：PHP 数组传来传去是复制的，“在末尾加一项”改不到原来那个。
library;

import 'package:lopicode/lang/gen.dart';
import 'package:lopicode/lang/rt.dart';

class PhpLangGen extends LangGen {
  const PhpLangGen({super.host});

  @override
  String get id => 'php';
  @override
  String get runtimeFile => 'lc_lang.php';
  @override
  String get indentUnit => '    ';

  /// 数字都带小数点（PHP 里 `1` 是整数）；双引号里 `$` 要加反斜杠；控制字符写成 `\u{…}`。
  @override
  String literal(Object? value) => switch (value) {
    null => 'null',
    final bool b => '$b',
    final num n => langNumber(n, dotZero: true),
    final String s => langQuoted(s, escape: r'$', unicode: (c) => '\\u{${c.toRadixString(16)}}'),
    _ => 'null',
  };

  @override
  String variable(String name) => '\$v_$name';
  @override
  String temp(String name) => '\$lcT$name';
  @override
  String loopName(String letter, int n) => '\$lcv$letter$n';
  @override
  String coreCall(String fn, List<String> args) => 'lc_$fn(${args.join(', ')})';
  @override
  String langCall(String fn, List<String> args) => 'lc_$fn(${args.join(', ')})';
  @override
  String comment(String text) => '// ${langComment(text).replaceAll('?>', '? >')}';
  @override
  List<String> declare(String name) => ['${variable(name)} = null;'];
  @override
  String local(LRet type, String name, String value) => '$name = $value;';
  @override
  String countedHead(String k, String n) => 'for ($k = 0; $k < $n; $k++)';
  @override
  String nativeLen(String list) => 'count($list)';
  @override
  String nativeAt(String list, String k) => '$list[$k]';
  @override
  String intToNumber(String k) => '(float) $k';

  @override
  String scriptSource(List<List<String>> bodies) {
    final out = StringBuffer()
      ..writeln('<?php')
      ..writeln('// 由 LopiCode 积木生成（PHP）。')
      ..writeln()
      ..writeln('declare(strict_types=1);')
      ..writeln();
    for (final f in ['lc_runtime.php', 'lc_json.php', runtimeFile]) {
      out.writeln("require_once __DIR__ . '/$f';");
    }
    for (var i = 0; i < bodies.length; i++) {
      out
        ..writeln()
        ..writeln('function lc_module${i + 1}()')
        ..writeln('{');
      indented(bodies[i]).forEach(out.writeln);
      out.writeln('}');
    }
    out.writeln();
    for (var i = 0; i < bodies.length; i++) {
      out.writeln('lc_module${i + 1}();');
    }
    return out.toString();
  }
}
