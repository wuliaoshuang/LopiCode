/// 规矩版本 2 的生成器·JS 公共部分：Node 目标（gen2_node.dart）和浏览器目标（gen2_browser.dart）共用的写法——
/// 字面量、匿名函数、类、记录、枚举、“试试看”、函数头。两个目标只在“模块怎么拼、宿主怎么叫、等怎么写”上不一样。
library;

import 'package:lopicode/lang/ast.dart';
import 'package:lopicode/lang/gen2.dart';
import 'package:lopicode/lang/gen2_dyn.dart';
import 'package:lopicode/lang/gen_support.dart';
import 'package:lopicode/lang/types.dart';

abstract class JsGen2 extends Gen2Dyn {
  JsGen2(super.module, super.r);

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
  String waitCode(String task, LType of) => 'lc.wait($task)';
}
