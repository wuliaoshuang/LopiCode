/// Node.js 生成器。小库：`lc_runtime.js`（值的规矩）＋ `lc_lang.js`（第 4 版新加的；它把前者的函数也一起导出，所以代码里都写 `lc.xxx`）。
library;

import 'package:lopicode/lang/ast.dart';
import 'package:lopicode/lang/ast_util.dart';
import 'package:lopicode/lang/gen.dart';
import 'package:lopicode/lang/rt.dart';

class NodeLangGen extends LangGen {
  const NodeLangGen({super.host});

  @override
  String get id => 'node';
  @override
  String get runtimeFile => 'lc_lang.js';

  /// 多拆开 `</` 和 `<!--`：万一有人把这段脚本贴进网页的 `<script>` 里，不会被提前截断。
  @override
  String literal(Object? value) => switch (value) {
    null => 'null',
    final bool b => '$b',
    final num n => langNumber(n),
    final String s => langQuoted(s).replaceAll('</', r'<\/').replaceAll('<!--', r'<\!--'),
    _ => 'null',
  };

  @override
  String coreCall(String fn, List<String> args) => 'lc.$fn(${args.join(', ')})';
  @override
  String langCall(String fn, List<String> args) => 'lc.$fn(${args.join(', ')})';
  @override
  String comment(String text) => '// ${langComment(text)}';
  @override
  List<String> declare(String name) => ['let ${variable(name)} = null;'];
  @override
  String local(LRet type, String name, String value) => 'const $name = $value;';
  @override
  String countedHead(String k, String n) => 'for (let $k = 0; $k < $n; $k++)';
  @override
  String nativeLen(String list) => '$list.length';
  @override
  String nativeAt(String list, String k) => '$list[$k]';

  // —— 函数 ——

  @override
  List<String> globalDecl(String code) => ['let $code = null;'];
  @override
  String fnWrap(String name, int min, int max, String impl) => 'lc.fn(${literal(name)}, $min, $max, $impl)';
  @override
  String fnCall(String f, List<String> args) => 'lc.call(${[f, ...args].join(', ')})';

  String _params(List<LParam> params, LangScope scope) =>
      [for (final p in params) '${p.rest ? '...' : ''}${localCode(scope, p.name)}${p.defaultValue == null ? '' : ' = ${literal(p.defaultValue!.value)}'}'].join(', ');

  @override
  List<String> funcDecl(String fname, List<LParam> params, LangScope scope, List<String> body) => ['function $fname(${_params(params, scope)}) {', ...indented(body), '}'];
  @override
  List<String> lambdaDef(String tmp, List<LParam> params, LangScope scope, List<String> body, List<String> uses, String args) => [
    'const $tmp = lc.fn("", ${lMinArgs(params)}, ${lMaxArgs(params)}, (${_params(params, scope)}) => {',
    ...indented(body),
    '});',
  ];
  @override
  String lambdaShort(List<LParam> params, LangScope scope, String code, List<String> uses, String args) => '(${_params(params, scope)}) => $code';

  @override
  String scriptSource(List<List<String>> bodies, {List<String> top = const []}) {
    final out = StringBuffer()
      ..writeln('// 由 LopiCode 积木生成（Node.js）。')
      ..writeln('"use strict";')
      ..writeln('const lc = require("./$runtimeFile");');
    if (top.isNotEmpty) out.writeln();
    top.forEach(out.writeln);
    for (var i = 0; i < bodies.length; i++) {
      out
        ..writeln()
        ..writeln('function lcModule${i + 1}() {');
      indented(bodies[i]).forEach(out.writeln);
      out.writeln('}');
    }
    out.writeln();
    for (var i = 0; i < bodies.length; i++) {
      out.writeln('lcModule${i + 1}();');
    }
    return out.toString();
  }
}
