/// PHP 生成器。小库：`lc_runtime.php`、`lc_json.php`（值的规矩）＋ `lc_lang.php`（第 4 版新加的）。
///
/// 2026-11-26 起在开发机上用 PHP 8.3 真跑（语言核心一致性测试，和别的四种语言逐字节对比）。
/// 列表在 PHP 里是 `LcList` 对象（不是 PHP 数组）：PHP 数组传来传去是复制的，“在末尾加一项”改不到原来那个。
library;

import 'package:lopicode/lang/ast.dart';
import 'package:lopicode/lang/ast_util.dart';
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

  // —— 函数 ——

  @override
  Map<String, LCap> get caps => {...kLangBaseCaps, 'closures': LCap.lowered};
  @override
  String globalVar(String prefix, String name) => '\$g${prefix}_$name';
  @override
  String fnTemp(int n) => '\$lcF$n';
  @override
  List<String> globalDecl(String code) => ['$code = null;'];
  @override
  String fnWrap(String name, int min, int max, String impl) => 'lc_fn(${literal(name)}, $min, $max, $impl)';
  @override
  String fnCall(String f, List<String> args) => 'lc_call(${[f, ...args].join(', ')})';
  @override
  bool get shortRest => false;
  @override
  List<String> get finalReturn => const [];

  String _params(List<LParam> params, LangScope scope) =>
      [for (final p in params) '${p.rest ? '...' : ''}${localCode(scope, p.name)}${p.defaultValue == null ? '' : ' = ${literal(p.defaultValue!.value)}'}'].join(', ');

  /// 匿名函数要写明用了外面哪些变量；一律按引用（`&`），里层改了外层也看得见。
  static String _use(List<String> uses) => uses.isEmpty ? '' : ' use (${[for (final u in uses) '&$u'].join(', ')})';

  @override
  List<String> funcDecl(String fname, List<LParam> params, LangScope scope, List<String> body) => ['function $fname(${_params(params, scope)})', '{', ...indented(body), '}'];
  @override
  List<String> lambdaDef(String tmp, List<LParam> params, LangScope scope, List<String> body, List<String> uses, String args) => [
    '$tmp = lc_fn("", ${lMinArgs(params)}, ${lMaxArgs(params)}, function (${_params(params, scope)})${_use(uses)} {',
    ...indented(body),
    '});',
  ];

  /// 不用 `fn() =>`：它抓的是当时的值，外层后来改了里层看不见。
  @override
  String lambdaShort(List<LParam> params, LangScope scope, String code, List<String> uses, String args) => 'function (${_params(params, scope)})${_use(uses)} { return $code; }';

  /// 短写法里用到模块级变量也要先 `global`（2026-11-26 第一次真跑 PHP 时发现：漏了这句，读到的是没定义的局部变量）。
  @override
  String lambdaShortWithGlobals(List<LParam> params, LangScope scope, String code, List<String> uses, String args, List<String> globalsUsed) =>
      globalsUsed.isEmpty ? lambdaShort(params, scope, code, uses, args) : 'function (${_params(params, scope)})${_use(uses)} { global ${globalsUsed.join(', ')}; return $code; }';
  @override
  String namedImpl(LFuncDecl f, String fname) => "'$fname'";

  /// `...$xs` 拿到的是 PHP 数组：转成列表。
  @override
  List<String> paramPreamble(List<LParam> params, LangScope scope, String? args) => [
    for (final p in params)
      if (p.rest) '${localCode(scope, p.name)} = lc_listOf(...${localCode(scope, p.name)});',
  ];

  /// 函数里用模块级变量（读也算）要先 `global`。
  @override
  List<String> closurePreamble(List<String> outerWritten, List<String> globalsWritten, List<String> globalsUsed) => [if (globalsUsed.isNotEmpty) 'global ${globalsUsed.join(', ')};'];

  @override
  String scriptSource(List<List<String>> bodies, {List<String> top = const []}) {
    final out = StringBuffer()
      ..writeln('<?php')
      ..writeln('// 由 LopiCode 积木生成（PHP）。')
      ..writeln()
      ..writeln('declare(strict_types=1);')
      ..writeln()
      // 命令行下 PHP 默认把报错写到标准输出，和程序自己的输出混在一起；改到标准错误（别的语言都是这样）。
      ..writeln("ini_set('display_errors', 'stderr');")
      ..writeln();
    for (final f in ['lc_runtime.php', 'lc_json.php', runtimeFile]) {
      out.writeln("require_once __DIR__ . '/$f';");
    }
    if (top.isNotEmpty) out.writeln();
    top.forEach(out.writeln);
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
