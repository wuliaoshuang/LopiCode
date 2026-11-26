/// 规矩版本 2 的生成器·PHP（8.1 起）。小库：`lc2.php`（rt2_php.dart）。
library;

import 'package:lopicode/lang/ast.dart';
import 'package:lopicode/lang/gen2.dart';
import 'package:lopicode/lang/gen2_dyn.dart';
import 'package:lopicode/lang/gen_support.dart';
import 'package:lopicode/lang/rt2_php.dart';
import 'package:lopicode/lang/typecheck.dart';
import 'package:lopicode/lang/types.dart';

class PhpGen2 extends Gen2Dyn {
  PhpGen2(super.module, super.r);

  @override
  String get mainFile => 'main.php';
  @override
  Map<String, String> get runtimeFiles => const {'lc2.php': kRt2PhpSource};

  @override
  String get vp => r'$';
  @override
  String get dot => '->';
  @override
  String rtn(String name) => 'Lc::$name';
  @override
  String rtRef(String name) => 'Lc::$name(...)';
  @override
  String get catOp => '.';
  @override
  String typeRef(String name) => '${typeName(name)}::class';
  @override
  String newOf(String type, List<String> args) => '(new $type(${args.join(', ')}))';
  @override
  String enumRef(String type, String c) => '$type::\$$c';

  @override
  String textLit(String v) => langQuoted(v, escape: r'$', unicode: (c) => '\\u{${c.toRadixString(16)}}');
  @override
  String listLit(LType elem, List<String> items) => 'Lc::list([${items.join(', ')}])';
  @override
  String dictLit(LType value, List<(String, String)> entries) => 'Lc::dict([${[for (final e in entries) '[${e.$1}, ${e.$2}]'].join(', ')}])';
  @override
  String lam1(String Function(String v) body) => '(fn(\$lcV) => ${body(r'$lcV')})';
  @override
  String changes(Map<String, String> byField) => '[${[for (final e in byField.entries) "'${e.key}' => ${e.value}"].join(', ')}]';
  @override
  bool needsDyn(LType from) => super.needsDyn(from) || from.kind == LKind.integer || from.kind == LKind.typeVar;
  @override
  String widen(String code) => '((float)$code)';
  @override
  String funcValue(LTypedSig f) => '${funcName(f.info.name)}(...)';
  @override
  String callValue(String f, List<String> args, LType ft) => '($f)(${args.join(', ')})';
  @override
  String selfCode() => r'$this';
  @override
  String superCall(String method, List<String> args) => 'parent::${member(method)}(${args.join(', ')})';
  @override
  String superCtor(List<String> args) => '[parent::__construct(${args.join(', ')}), \$this->${_fieldsOf(fn.owner!.name)}()]';
  @override
  String nativeLen(String arr) => 'count($arr)';
  @override
  String dictAt(String dict, String key, LType value) => '$dict->a[$key]';
  @override
  String countHead(String k, String n) => 'for ($k = 0; $k < $n; $k++)';
  @override
  String tmpDecl(String name, LType type, String code) => '$name = $code;';
  @override
  List<String> throwLines(String message) => ['throw new LcError($message);'];

  String _fieldsOf(String cls) => 'lcf_${v2Ident(cls)}';

  @override
  List<String> throwObjLines(String obj, String message) => ['throw Lc::errOf($message, $obj);'];
  @override
  String errObjCode(String e) => 'Lc::errObj($e)';
  @override
  List<String> rethrowLines(String e) => ['throw $e;'];
  @override
  String errKindCode(String obj, LType type) => 'Lc::kindOf($obj)';
  @override
  String errNarrow(String code, LType from, LType to) => code;
  @override
  List<String> errSupport() => [
    r'Lc::errSetup(function (string $lcK, string $lcM): object {',
    ...indent([
      r'switch ($lcK) {',
      ...indent([for (final (k, make) in errMakers(r'$lcM').skip(1)) 'case ${textLit(k)}: return $make;', 'default: return ${errMakers(r'$lcM').first.$2};']),
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
      if (handler != null) ...['} catch (LcError $e) {', ...indent(handler(e))],
      if (s.finallyBody.isNotEmpty) ...['} finally {', ...indent(gen(s.finallyBody))],
      '}',
    ];
  }

  @override
  List<String> declareLocals(V2Fn f) {
    final g = [for (final v in globals) varCode(V2Var(v, 0, global: true))];
    return [if (g.isNotEmpty) 'global ${g.join(', ')};', for (final n in localNames(f)) '$n = null;'];
  }

  @override
  String lambdaCode(LLambda e, LType ft, V2Fn inner) {
    // 外层的变量一律按引用带进来：里面改了外面看得到，外面后来改了里面也看得到。
    final uses = <String>{};
    for (final n in lambdaUses[e] ?? const <String>{}) {
      final v = lookup(n);
      if (v != null && !v.global) uses.add('&${varCode(v)}');
    }
    final params = paramCodes(inner, e.params).join(', ');
    final use = uses.isEmpty ? '' : ' use (${uses.join(', ')})';
    return '(function ($params)$use {\n${indent(funcBody(inner, e.stmts)).join('\n')}\n})';
  }

  @override
  String hostCall(String fn, List<String> args) => 'LcHost::$fn(${args.join(', ')})';

  @override
  List<String> funcDecl(String name, List<String> params, List<String> body) => ['function $name(${params.join(', ')}) {', ...indent(body), '}'];

  @override
  List<String> globalDecls(List<String> names) => [for (final n in names) '$n = null;'];

  @override
  List<String> recordDecl(String name, String label, List<String> fields, {String? base}) => [
    'class $name extends ${base == null ? 'LcRec' : (base.isEmpty ? 'LcVariant' : base)} {',
    ...indent(['const lcName = ${textLit(label)};', if (base == null || base.isNotEmpty) 'function __construct(${fields.map((f) => 'public \$$f').join(', ')}) {}']),
    '}',
  ];

  @override
  List<String> enumDecl(String name, String label, List<(String, String)> cases) => [
    'class $name extends LcEnum {',
    ...indent(['const lcName = ${textLit(label)};', for (final c in cases) 'public static \$${c.$1};']),
    '}',
    for (var i = 0; i < cases.length; i++) '$name::\$${cases[i].$1} = new $name(${textLit(cases[i].$2)}, $i);',
  ];

  @override
  List<String> classDecl(DynClass c) {
    final own = '\$this->${_fieldsOf(c.info.name)}();';
    final List<String> ctor;
    if (c.ctorParams != null) {
      final explicit = callsSuperCtor(c.info);
      ctor = [
        'function __construct(${c.ctorParams!.join(', ')}) {',
        ...indent([if (!explicit && c.parent != null) 'parent::__construct();', if (!explicit) own, ...c.ctorBody]),
        '}',
      ];
    } else if (c.parent != null) {
      ctor = [
        r'function __construct(...$lcArgs) {',
        ...indent([r'parent::__construct(...$lcArgs);', own]),
        '}',
      ];
    } else {
      ctor = [
        'function __construct() {',
        ...indent([own]),
        '}',
      ];
    }
    return [
      'class ${c.name} extends ${c.parent ?? 'LcObj'} {',
      ...indent([
        'const lcName = ${textLit(c.info.name)};',
        'const lcKinds = [${c.kinds.map(textLit).join(', ')}];',
        for (final f in c.fields) 'public \$${f.$1};',
        'function ${_fieldsOf(c.info.name)}() {',
        ...indent([for (final f in c.fields) '\$this->${f.$1} = ${f.$2};']),
        '}',
        ...ctor,
        for (final m in c.methods) ...['function ${m.$1}(${m.$2.join(', ')}) {', ...indent(m.$3), '}'],
      ]),
      '}',
    ];
  }

  @override
  String programText(List<String> top, List<String> mainBody, {List<String> head = const []}) {
    final out = StringBuffer()
      ..writeln('<?php')
      ..writeln('// 由 LopiCode 积木生成（PHP，严格规矩）。')
      ..writeln('declare(strict_types=1);')
      ..writeln("require __DIR__ . '/lc2.php';");
    head.forEach(out.writeln);
    out.writeln();
    top.forEach(out.writeln);
    out
      ..writeln()
      ..writeln('Lc::run(function () {');
    indent(mainBody).forEach(out.writeln);
    out.writeln('});');
    return out.toString();
  }

  // —— 分文件：每个模块是一个 .php 文件，主文件按启动顺序一个个 require_once 进来。
  // PHP 的函数、类、最外层的变量哪个文件都看得见，所以模块文件自己不用再引别的文件，名字也不用改。

  @override
  String get ext => 'php';

  @override
  List<String> importLines(String part, List<String> names, {required bool vars, required bool inMain}) => [if (inMain) "require_once __DIR__ . '/${partBase(part)}.php';"];

  @override
  String moduleText(String what, List<String> head, List<String> top, List<String> tail) =>
      ['<?php', '// 由 LopiCode 积木生成（PHP，严格规矩）：$what。由主文件引进来，不单独运行。', 'declare(strict_types=1);', '', ...top, ''].join('\n');
}
