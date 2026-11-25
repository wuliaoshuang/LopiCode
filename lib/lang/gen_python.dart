/// Python 生成器。小库：`lc_runtime.py`（值的规矩）＋ `lc_lang.py`（第 4 版新加的；它把前者的函数也带上，所以代码里都写 `lc.xxx`）。
library;

import 'package:lopicode/lang/ast.dart';
import 'package:lopicode/lang/ast_util.dart';
import 'package:lopicode/lang/gen.dart';
import 'package:lopicode/lang/rt.dart';

class PythonLangGen extends LangGen {
  const PythonLangGen({super.host});

  @override
  String get id => 'python';
  @override
  String get runtimeFile => 'lc_lang.py';
  @override
  String get indentUnit => '    ';

  @override
  String literal(Object? value) => switch (value) {
    null => 'None',
    final bool b => b ? 'True' : 'False',
    final num n => langNumber(n),
    final String s => langQuoted(s),
    _ => 'None',
  };

  /// 小库的函数在 Python 里是下划线写法：`listGet` → `list_get`。
  static String snake(String fn) => fn.replaceAllMapped(RegExp('[A-Z]'), (m) => '_${m[0]!.toLowerCase()}');

  @override
  String coreCall(String fn, List<String> args) => 'lc.${snake(fn)}(${args.join(', ')})';
  @override
  String langCall(String fn, List<String> args) => 'lc.${snake(fn)}(${args.join(', ')})';
  @override
  String comment(String text) => '# ${langComment(text)}';
  @override
  List<String> declare(String name) => ['${variable(name)} = None'];
  @override
  String get end => '';
  @override
  String local(LRet type, String name, String value) => '$name = $value';
  @override
  bool get braces => false;
  @override
  String ifHead(String cond) => 'if $cond';
  @override
  String elseIfHead(String cond) => 'elif $cond';
  @override
  String whileHead(String? cond) => 'while ${cond ?? 'True'}';
  @override
  String countedHead(String k, String n) => 'for $k in range($n)';
  @override
  String get andOp => 'and';
  @override
  String get orOp => 'or';
  @override
  String ternary(String cond, String then, String orElse) => '($then if $cond else $orElse)';
  @override
  String nativeLen(String list) => 'len($list)';
  @override
  String nativeAt(String list, String k) => '$list[$k]';
  @override
  String intToNumber(String k) => 'float($k)';

  // —— 函数 ——

  @override
  Map<String, LCap> get caps => {...kLangBaseCaps, 'closures': LCap.lowered};
  @override
  List<String> globalDecl(String code) => ['$code = None'];
  @override
  String fnWrap(String name, int min, int max, String impl) => 'lc.fn(${literal(name)}, $min, $max, $impl)';
  @override
  String fnCall(String f, List<String> args) => 'lc.call(${[f, ...args].join(', ')})';
  @override
  bool get shortRest => false;
  @override
  List<String> get finalReturn => const [];

  String _params(List<LParam> params, LangScope scope) =>
      [for (final p in params) '${p.rest ? '*' : ''}${localCode(scope, p.name)}${p.defaultValue == null ? '' : '=${literal(p.defaultValue!.value)}'}'].join(', ');

  @override
  List<String> funcDecl(String fname, List<LParam> params, LangScope scope, List<String> body) => ['def $fname(${_params(params, scope)}):', ...suite(body)];

  /// Python 的 lambda 只能写一个式子：带函数体的一律生成成一个嵌套的 `def`，再包成函数值存回同一个名字。
  @override
  List<String> lambdaDef(String tmp, List<LParam> params, LangScope scope, List<String> body, List<String> uses, String args) => [
    'def $tmp(${_params(params, scope)}):',
    ...suite(body),
    '$tmp = lc.fn("", ${lMinArgs(params)}, ${lMaxArgs(params)}, $tmp)',
  ];
  @override
  String lambdaShort(List<LParam> params, LangScope scope, String code, List<String> uses, String args) => params.isEmpty ? 'lambda: $code' : 'lambda ${_params(params, scope)}: $code';

  /// `*xs` 拿到的是元组：转成列表。
  @override
  List<String> paramPreamble(List<LParam> params, LangScope scope, String? args) => [
    for (final p in params)
      if (p.rest) '${localCode(scope, p.name)} = list(${localCode(scope, p.name)})',
  ];

  /// 里层要**改**外层函数的变量：`nonlocal`；改模块级变量：`global`。只读的不用声明。
  @override
  List<String> closurePreamble(List<String> outerWritten, List<String> globalsWritten, List<String> globalsUsed) => [
    if (outerWritten.isNotEmpty) 'nonlocal ${outerWritten.join(', ')}',
    if (globalsWritten.isNotEmpty) 'global ${globalsWritten.join(', ')}',
  ];

  @override
  String scriptSource(List<List<String>> bodies, {List<String> top = const []}) {
    final out = StringBuffer()
      ..writeln('# 由 LopiCode 积木生成（Python）。')
      ..writeln('import lc_lang as lc');
    if (top.isNotEmpty) out.writeln();
    top.forEach(out.writeln);
    for (var i = 0; i < bodies.length; i++) {
      out
        ..writeln()
        ..writeln()
        ..writeln('def lc_module${i + 1}():');
      suite(bodies[i]).forEach(out.writeln);
    }
    out
      ..writeln()
      ..writeln();
    for (var i = 0; i < bodies.length; i++) {
      out.writeln('lc_module${i + 1}()');
    }
    return out.toString();
  }
}
