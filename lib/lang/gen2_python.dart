/// 规矩版本 2 的生成器·Python。小库：`lc2.py`（rt2_python.dart）。
library;

import 'package:lopicode/lang/ast.dart';
import 'package:lopicode/lang/gen2.dart';
import 'package:lopicode/lang/gen2_dyn.dart';
import 'package:lopicode/lang/gen2_split.dart';
import 'package:lopicode/lang/gen_support.dart';
import 'package:lopicode/lang/rt2_python_dyn.dart';
import 'package:lopicode/lang/typecheck.dart';
import 'package:lopicode/lang/types.dart';

class PythonGen2 extends Gen2Dyn {
  PythonGen2(super.module, super.r);

  @override
  String get mainFile => 'main.py';
  @override
  Map<String, String> get runtimeFiles => const {'lc2.py': kRt2PythonSource};

  @override
  String get end => '';
  @override
  bool get braces => false;
  @override
  String ifHead(String cond) => 'if $cond';
  @override
  String elseIfHead(String cond) => 'elif $cond';
  @override
  String whileHead(String? cond) => 'while ${cond ?? trueLit}';
  @override
  String get trueLit => 'True';
  @override
  String comment(String text) => '# ${langComment(text)}';
  @override
  String get eqOp => '==';
  @override
  String get andOp => 'and';
  @override
  String get orOp => 'or';

  @override
  String nullLit() => 'None';
  @override
  String boolLit(bool v) => v ? 'True' : 'False';
  @override
  String textLit(String v) => langQuoted(v);
  @override
  String listLit(LType elem, List<String> items) => '[${items.join(', ')}]';
  @override
  String dictLit(LType value, List<(String, String)> entries) => '{${[for (final e in entries) '${e.$1}: ${e.$2}'].join(', ')}}';
  @override
  String lam1(String Function(String v) body) => '(lambda lcV: ${body('lcV')})';
  @override
  String changes(Map<String, String> byField) => '{${[for (final e in byField.entries) '${langQuoted(e.key)}: ${e.value}'].join(', ')}}';
  @override
  bool needsDyn(LType from) => super.needsDyn(from) || from.kind == LKind.integer || from.kind == LKind.typeVar;
  @override
  String widen(String code) => 'float($code)';
  @override
  String newOf(String type, List<String> args) => '$type(${args.join(', ')})';
  @override
  String instanceOf(String code, String type) => 'isinstance($code, $type)';
  @override
  String isNullCode(String code, LType type) => '($code is None)';
  @override
  String notCode(String a) => '(not $a)';
  @override
  String ternary(String cond, String a, String b, LType type) => '($a if $cond else $b)';
  @override
  String orElseCode(String code, LType type, String def, LType want) => 'lc.orElse($code, lambda: $def)';
  @override
  String selfCode() => 'self';
  @override
  String superCall(String method, List<String> args) => 'super().${member(method)}(${args.join(', ')})';
  @override
  String superCtor(List<String> args) => '(super().__init__(${args.join(', ')}), self.${_fieldsOf(fn.owner!.name)}())';
  @override
  String nativeLen(String arr) => 'len($arr)';
  @override
  String dictAt(String dict, String key, LType value) => '$dict[$key]';
  @override
  String countHead(String k, String n) => 'for $k in range($n)';
  @override
  String tmpDecl(String name, LType type, String code) => '$name = $code';
  @override
  List<String> throwLines(String message) => ['raise lc.LcError($message)'];

  String _fieldsOf(String cls) => 'lcf_${v2Ident(cls)}';

  @override
  List<String> throwObjLines(String obj, String message) => ['raise lc.LcError($message, $obj)'];
  @override
  String errObjCode(String e) => 'lc.errObj($e)';
  @override
  List<String> rethrowLines(String e) => ['raise'];
  @override
  String errKindCode(String obj, LType type) => 'lc.kindOf($obj)';
  @override
  String errNarrow(String code, LType from, LType to) => code;
  @override
  List<String> errSupport() => [
    'def lc_err_make(lcK, lcM):',
    ...suite([
      for (final (k, make) in errMakers('lcM').skip(1)) ...[
        'if lcK == ${textLit(k)}:',
        ...suite(['return $make']),
      ],
      'return ${errMakers('lcM').first.$2}',
    ]),
    '',
    '',
    'lc.errSetup(lc_err_make)',
  ];

  @override
  List<String> tryFrame(LTry s, List<String> Function(List<LStmt>) gen, List<String> Function(String e)? handler) {
    final e = tmpName('E');
    return [
      'try:',
      ...suite(gen(s.body)),
      if (handler != null) ...['except lc.LcError as $e:', ...suite(handler(e))],
      if (s.finallyBody.isNotEmpty) ...['finally:', ...suite(gen(s.finallyBody))],
    ];
  }

  /// 这个函数里要声明成“外面的”名字：全局的（global）、外层函数的（nonlocal）。
  List<String> _outer(V2Fn f) {
    // 分了文件的时候只声明这个文件自己的模块级变量（别的模块的写成 `lcM_模块.g_变量`，不用声明）。
    final g = [
      for (final v in globals)
        if (split == null || split!.of(v.name) == curModule) varCode(V2Var(v, 0, global: true)),
    ];
    final out = <String>[if (g.isNotEmpty) 'global ${g.join(', ')}'];
    final lam = f.lambda;
    if (lam != null) {
      final names = <String>{};
      for (final n in lambdaWrites[lam] ?? const <String>{}) {
        final v = lookup(n);
        if (v != null && !v.global && v.depth < f.depth) names.add(varCode(v));
      }
      if (names.isNotEmpty) out.add('nonlocal ${names.join(', ')}');
    }
    return out;
  }

  @override
  List<String> declareLocals(V2Fn f) => [..._outer(f), for (final n in localNames(f)) '$n = None'];

  @override
  String lambdaCode(LLambda e, LType ft, V2Fn inner) {
    final params = paramCodes(inner, e.params).join(', ');
    final outer = fn;
    if (e.expr != null && !inner.isVoid && localsOf(inner.scope).isEmpty) {
      // 式子里又套着带语句的匿名函数（要先在前面定义）就不能写成 lambda，改走下面有名字的写法。
      inner.pre = [];
      final body = inFn(inner, () => x(e.expr!, inner.ret));
      if (inner.pre.isEmpty) return '(lambda $params: $body)';
      inner.pre = [];
    }
    final name = 'lcF${outer.next()}';
    final body = funcBody(inner, e.stmts);
    outer.pre.addAll(['def $name($params):', ...suite(body)]);
    return name;
  }

  @override
  List<String> funcDecl(String name, List<String> params, List<String> body) => ['def $name(${params.join(', ')}):', ...suite(body), ''];

  @override
  List<String> globalDecls(List<String> names) => [for (final n in names) '$n = None'];

  @override
  List<String> recordDecl(String name, String label, List<String> fields, {String? base}) => [
    'class $name(${base == null ? 'lc.Rec' : (base.isEmpty ? 'lc.Variant' : base)}):',
    ...indent([
      'lcName = ${textLit(label)}',
      if (base == null || base.isNotEmpty) ...[
        '',
        'def __init__(${['self', ...fields].join(', ')}):',
        ...suite([for (final f in fields) 'self.$f = $f']),
      ],
    ]),
    '',
  ];

  @override
  List<String> enumDecl(String name, String label, List<(String, String)> cases) => [
    'class $name(lc.Enum):',
    ...indent(['lcName = ${textLit(label)}']),
    '',
    for (var i = 0; i < cases.length; i++) '$name.${cases[i].$1} = $name(${textLit(cases[i].$2)}, $i)',
    '',
  ];

  @override
  List<String> classDecl(DynClass c) {
    final init = _fieldsOf(c.info.name);
    final own = 'self.$init()';
    final List<String> ctor;
    if (c.ctorParams != null) {
      final explicit = callsSuperCtor(c.info);
      ctor = [
        'def __init__(${['self', ...c.ctorParams!].join(', ')}):',
        ...suite([if (!explicit && c.parent != null) 'super().__init__()', if (!explicit) own, ...c.ctorBody]),
      ];
    } else if (c.parent != null) {
      ctor = [
        'def __init__(self, *lcArgs):',
        ...suite(['super().__init__(*lcArgs)', own]),
      ];
    } else {
      ctor = [
        'def __init__(self):',
        ...suite([own]),
      ];
    }
    return [
      'class ${c.name}(${c.parent ?? 'lc.Obj'}):',
      ...indent([
        'lcName = ${textLit(c.info.name)}',
        'lcKinds = (${c.kinds.map((k) => '${textLit(k)},').join(' ')})',
        '',
        'def $init(self):',
        ...suite([for (final f in c.fields) 'self.${f.$1} = ${f.$2}']),
        '',
        ...ctor,
        for (final m in c.methods) ...[
          '',
          'def ${m.$1}(${['self', ...m.$2].join(', ')}):',
          ...suite(m.$3),
        ],
      ]),
      '',
    ];
  }

  @override
  String funcValue(LTypedSig f) => funcName(f.info.name);

  @override
  String programText(List<String> top, List<String> mainBody, {List<String> head = const []}) {
    final out = StringBuffer()
      ..writeln('# 由 LopiCode 积木生成（Python，严格规矩）。')
      ..writeln('import lc2 as lc');
    head.forEach(out.writeln);
    out.writeln();
    top.forEach(out.writeln);
    out
      ..writeln()
      ..writeln('def lc_main():');
    suite(mainBody).forEach(out.writeln);
    out
      ..writeln()
      ..writeln()
      ..writeln('lc.run(lc_main)');
    return out.toString();
  }

  // —— 分文件：每个模块是一个 .py 文件。类型、函数用 from … import 引进来；别的模块的变量写成 `lcM_模块.g_变量`
  // （模块上的属性，读到、改到的就是那个模块里的变量；from … import 拿到的只是当时的值，不能用）。

  @override
  String get ext => 'py';
  @override
  String globalFrom(String part, String base) => '${modVar(part)}.$base';

  @override
  List<String> importLines(String part, List<String> names, {required bool vars, required bool inMain}) => [
    if (part != Gen2Split.kinds) 'import ${partBase(part)} as ${modVar(part)}',
    if (names.isNotEmpty) 'from ${partBase(part)} import ${names.join(', ')}',
  ];

  @override
  String moduleText(String what, List<String> head, List<String> top, List<String> tail) => ['# 由 LopiCode 积木生成（Python，严格规矩）：$what。', 'import lc2 as lc', ...head, '', ...top, ''].join('\n');
}
