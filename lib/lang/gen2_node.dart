/// 规矩版本 2 的生成器·Node.js。小库：`lc2.js`（rt2_node.dart）。
library;

import 'package:lopicode/lang/ast.dart';
import 'package:lopicode/lang/gen2.dart';
import 'package:lopicode/lang/gen2_dyn.dart';
import 'package:lopicode/lang/gen2_split.dart';
import 'package:lopicode/lang/gen_support.dart';
import 'package:lopicode/lang/rt2_node.dart';
import 'package:lopicode/lang/types.dart';

class NodeGen2 extends Gen2Dyn {
  NodeGen2(super.module, super.r);

  @override
  String get mainFile => 'main.js';
  @override
  Map<String, String> get runtimeFiles => const {'lc2.js': kRt2NodeSource};

  @override
  String textLit(String v) => super.textLit(v).replaceAll('</', r'<\/').replaceAll('<!--', r'<\!--');
  @override
  String floatLit(double v) => v < 0 ? '(${langNumber(v)})' : langNumber(v);
  @override
  String listLit(LType elem, List<String> items) => '[${items.join(', ')}]';
  @override
  String dictLit(LType value, List<(String, String)> entries) => 'new Map([${[for (final e in entries) '[${e.$1}, ${e.$2}]'].join(', ')}])';
  @override
  String lam1(String Function(String v) body) => '(lcV) => ${body('lcV')}';
  @override
  String changes(Map<String, String> byField) => '{ ${[for (final e in byField.entries) '${e.key}: ${e.value}'].join(', ')} }';
  @override
  String selfCode() => 'this';
  @override
  String superCall(String method, List<String> args) => 'super.${member(method)}(${args.join(', ')})';
  @override
  String superCtor(List<String> args) => 'super(${args.join(', ')})';
  @override
  String nativeLen(String arr) => '$arr.length';
  @override
  String dictAt(String dict, String key, LType value) => '$dict.get($key)';
  @override
  String countHead(String k, String n) => 'for (let $k = 0; $k < $n; $k++)';
  @override
  String tmpDecl(String name, LType type, String code) => 'const $name = $code;';
  @override
  List<String> throwLines(String message) => ['throw new lc.LcError($message);'];

  @override
  List<String> throwObjLines(String obj, String message) => ['throw new lc.LcError($message, $obj);'];
  @override
  String errObjCode(String e) => 'lc.errObj($e)';
  @override
  List<String> rethrowLines(String e) => ['throw $e;'];
  @override
  String errKindCode(String obj, LType type) => 'lc.kindOf($obj)';
  @override
  String errNarrow(String code, LType from, LType to) => code;
  @override
  List<String> errSupport() => [
    'lc.errSetup((lcK, lcM) => {',
    ...indent([
      'switch (lcK) {',
      ...indent([for (final (k, make) in errMakers('lcM').skip(1)) 'case ${textLit(k)}: return $make;', 'default: return ${errMakers('lcM').first.$2};']),
      '}',
    ]),
    '});',
  ];

  @override
  List<String> tryFrame(LTry s, List<String> Function(List<LStmt>) gen, List<String> Function(String e)? handler) {
    final e = tmpName('E');
    return [
      'try {',
      ...indent(gen(s.body)),
      if (handler != null) ...[
        '} catch ($e) {',
        ...indent(['if (!($e instanceof lc.LcError)) throw $e;', ...handler(e)]),
      ],
      if (s.finallyBody.isNotEmpty) ...['} finally {', ...indent(gen(s.finallyBody))],
      '}',
    ];
  }

  @override
  List<String> declareLocals(V2Fn f) {
    final names = localNames(f);
    return names.isEmpty ? const [] : ['let ${names.map((n) => '$n = null').join(', ')};'];
  }

  @override
  String lambdaCode(LLambda e, LType ft, V2Fn inner) {
    final params = paramCodes(inner, e.params).join(', ');
    final head = inner.waits ? 'async ' : '';
    if (e.expr != null && !inner.isVoid && localsOf(inner.scope).isEmpty) return '($head($params) => ${inFn(inner, () => x(e.expr!, inner.ret))})';
    return '($head($params) => {\n${indent(funcBody(inner, e.stmts)).join('\n')}\n})';
  }

  @override
  List<String> funcDecl(String name, List<String> params, List<String> body) => ['${waitDecls.contains(name) ? 'async ' : ''}function $name(${params.join(', ')}) {', ...indent(body), '}'];

  // “等”：Node 里一件要等的事交回来的是 Promise，前面写 await；“稍后的结果”本身就是 Promise。
  @override
  String nativeCall(String ident, List<String> args) => 'require("./$ident.js")(${args.join(', ')})';
  @override
  String awaited(String code) => '(await $code)';
  @override
  String waitCode(String task, LType of) => 'lc.wait($task)';

  @override
  List<String> globalDecls(List<String> names) => names.isEmpty ? const [] : ['let ${names.map((n) => '$n = null').join(', ')};'];

  @override
  List<String> recordDecl(String name, String label, List<String> fields, {String? base}) => [
    'class $name extends ${base == null ? 'lc.Rec' : (base.isEmpty ? 'lc.Variant' : base)} {',
    if (base == null || base.isNotEmpty)
      ...indent([
        'constructor(${fields.join(', ')}) {',
        ...indent(['super();', for (final f in fields) 'this.$f = $f;', 'Object.freeze(this);']),
        '}',
      ]),
    '}',
    '$name.lcName = ${textLit(label)};',
  ];

  @override
  List<String> enumDecl(String name, String label, List<(String, String)> cases) => [
    'class $name extends lc.Enum {}',
    '$name.lcName = ${textLit(label)};',
    for (var i = 0; i < cases.length; i++) '$name.${cases[i].$1} = new $name(${textLit(cases[i].$2)}, $i);',
  ];

  @override
  List<String> classDecl(DynClass c) {
    final needSuper = c.parent != null && c.ctorParams != null && !callsSuperCtor(c.info);
    return [
      'class ${c.name}${c.parent == null ? ' extends lc.Obj' : ' extends ${c.parent}'} {',
      ...indent([
        for (final f in c.fields) '${f.$1} = ${f.$2};',
        if (c.ctorParams != null) ...[
          'constructor(${c.ctorParams!.join(', ')}) {',
          ...indent([if (needSuper || c.parent == null) 'super();', ...c.ctorBody]),
          '}',
        ],
        for (final m in c.methods) ...['${waitDecls.contains('${c.name}.${m.$1}') ? 'async ' : ''}${m.$1}(${m.$2.join(', ')}) {', ...indent(m.$3), '}'],
      ]),
      '}',
      '${c.name}.lcName = ${textLit(c.info.name)};',
      '${c.name}.lcKinds = [${c.kinds.map(textLit).join(', ')}];',
    ];
  }

  @override
  String programText(List<String> top, List<String> mainBody, {List<String> head = const []}) {
    final out = StringBuffer()
      ..writeln('// 由 LopiCode 积木生成（Node.js，严格规矩）。')
      ..writeln('"use strict";')
      ..writeln('const lc = require("./lc2.js");');
    head.forEach(out.writeln);
    if (top.isNotEmpty) out.writeln();
    top.forEach(out.writeln);
    out
      ..writeln()
      ..writeln('lc.run(${mainWaits ? 'async ' : ''}() => {');
    for (final l in indent(mainBody)) {
      out.writeln(l);
    }
    out.writeln('});');
    return out.toString();
  }

  // —— 分文件：每个模块是一个 CommonJS 文件，最后把类型、函数、变量交出去（module.exports）。
  // 变量交出去的是“读 / 写”一对（get / set），所以别的文件里 `lcM_模块.g_变量` 读到、改到的就是这个文件里的那个变量。

  @override
  String get ext => 'js';
  @override
  String globalFrom(String part, String base) => '${modVar(part)}.$base';

  @override
  List<String> importLines(String part, List<String> names, {required bool vars, required bool inMain}) {
    final file = 'require("./${partBase(part)}.js")';
    if (part == Gen2Split.kinds) return [names.isEmpty ? '$file;' : 'const { ${names.join(', ')} } = $file;'];
    return ['const ${modVar(part)} = $file;', if (names.isNotEmpty) 'const { ${names.join(', ')} } = ${modVar(part)};'];
  }

  @override
  List<String> exportLines(List<String> names, List<String> globals) => [
    'module.exports = {',
    ...indent([
      for (final n in names) '$n,',
      for (final g in globals) ...['get $g() { return $g; },', 'set $g(lcV) { $g = lcV; },'],
    ]),
    '};',
  ];

  @override
  String moduleText(String what, List<String> head, List<String> top, List<String> tail) =>
      ['// 由 LopiCode 积木生成（Node.js，严格规矩）：$what。', '"use strict";', 'const lc = require("./lc2.js");', ...head, if (top.isNotEmpty) '', ...top, '', ...tail, ''].join('\n');
}
