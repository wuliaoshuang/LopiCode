/// 规矩版本 2 的生成器·Node / Python / PHP 共用的部分：这三种语言的值没有静态类型，严格的规矩靠小库里的小函数
/// （整数加减乘查范围、除以 0 报错、任意取回时检查…）。各语言只答语法上不一样的地方（gen2_node / gen2_python / gen2_php.dart）。
library;

import 'package:lopicode/lang/ast.dart';
import 'package:lopicode/lang/ast_util.dart';
import 'package:lopicode/lang/gen2.dart';
import 'package:lopicode/lang/gen2_expr.dart';
import 'package:lopicode/lang/gen2_split.dart';
import 'package:lopicode/lang/gen_support.dart';
import 'package:lopicode/lang/rt_v2.dart';
import 'package:lopicode/lang/type_world.dart';
import 'package:lopicode/lang/typecheck.dart';
import 'package:lopicode/lang/types.dart';

/// 一个类收拾好的样子（各语言照着排版）。
class DynClass {
  DynClass(this.info, this.name, this.parent, this.kinds, this.fields, this.ctorParams, this.ctorBody, this.methods);
  final LClassInfo info;
  final String name;
  final String? parent;

  /// 它“是”哪些东西：自己、父类们、实现的接口（给“是不是”用）。
  final List<String> kinds;

  /// 字段名 → 初始值的代码。
  final List<(String, String)> fields;

  /// “创建时”的参数；null＝没写“创建时”。
  final List<String>? ctorParams;
  final List<String> ctorBody;
  final List<(String, List<String>, List<String>)> methods;
}

abstract class Gen2Dyn extends Gen2 {
  Gen2Dyn(super.module, super.r);

  // —— 各语言答的 ——

  /// 变量名前面的符号（PHP 是 `$`）。
  String get vp => '';

  /// 取成员的符号。
  String get dot => '.';

  /// 小库函数怎么叫。
  String rtn(String name) => 'lc.$name';
  String get eqOp => '===';
  String get andOp => '&&';
  String get orOp => '||';
  String get catOp => '+';
  String newOf(String type, List<String> args) => 'new $type(${args.join(', ')})';
  String instanceOf(String code, String type) => '($code instanceof $type)';
  String enumRef(String type, String c) => '$type.$c';

  /// 一个参数的函数（小库要一个“逐项检查”的函数时用）。
  String lam1(String Function(String v) body);

  /// 小库函数当值用。
  String rtRef(String name) => rtn(name);

  /// 按字段名给的一组值（“复制并改”用）。
  String changes(Map<String, String> byField);
  List<String> funcDecl(String name, List<String> params, List<String> body);
  List<String> recordDecl(String name, String label, List<String> fields, {String? base});
  List<String> enumDecl(String name, String label, List<(String, String)> cases);
  List<String> classDecl(DynClass c);
  List<String> globalDecls(List<String> names);
  String programText(List<String> top, List<String> mainBody, {List<String> head = const []});

  // —— 分文件（gen2_split.dart）：各语言答的 ——

  /// 文件的后缀（不带点）。
  String get ext;

  /// 别的模块的模块级变量在这个文件里怎么写（PHP 的全局变量哪个文件都看得见，不用改）。
  String globalFrom(String part, String base) => base;

  /// 把 [part] 那一份引进来的几行：[names] 是它的类型、函数，[vars] 是它有没有模块级变量；[inMain]＝是不是写在主文件里。
  List<String> importLines(String part, List<String> names, {required bool vars, required bool inMain});

  /// 文件最后“交出去”的几行（只有 Node 要）。
  List<String> exportLines(List<String> names, List<String> globals) => const [];

  /// 一个不是主文件的文件：[what] 写进开头的说明。
  String moduleText(String what, List<String> head, List<String> top, List<String> tail);

  String partBase(String part) => part == Gen2Split.kinds ? 'lc_kinds' : 'm_${split!.ident[part]}';
  String modVar(String part) => '${vp}lcM_${split!.ident[part]}';

  // —— 名字 ——

  String typeName(String name) => 'T_${v2Ident(name)}';

  /// 类型当值传给小库（PHP 要写 `T::class`）。
  String typeRef(String name) => typeName(name);
  String caseType(String variant, String c) => 'T_${v2Ident(variant)}_${v2Ident(c)}';
  String member(String name) => 'm_${v2Ident(name)}';
  String funcName(String name) => 'f_${v2Ident(name)}';

  String call(String name, List<String> args) => '${rtn(name)}(${args.join(', ')})';

  @override
  String varCode(V2Var v) {
    if (v.global) {
      final base = '${vp}g_${v2Ident(v.name)}', part = split?.of(v.name);
      return part == null || part == curModule ? base : globalFrom(part, base);
    }
    if (v.info.kind == LVarKind.temp) return '${vp}lcT${v2Ident(v.name)}';
    return v.depth == 0 ? '${vp}v_${v2Ident(v.name)}' : '${vp}v${v.depth}_${v2Ident(v.name)}';
  }

  @override
  String tmpName(String letter) => '$vp${super.tmpName(letter)}';

  /// 参数在代码里的名字（在 [f] 这个函数里）。
  List<String> paramCodes(V2Fn f, List<LParam> params) => inFn(f, () => [for (final p in params) varCode(mustVar(p.name, module))]);

  // —— 式子 ——

  @override
  String nulOf(LType type) => nullLit();
  @override
  String nullLit() => 'null';
  @override
  String boolLit(bool v) => '$v';
  @override
  String intLit(int v) => v < 0 ? '($v)' : '$v';
  @override
  String floatLit(double v) => v < 0 ? '(${langNumber(v, dotZero: true)})' : langNumber(v, dotZero: true);
  @override
  String textLit(String v) => langQuoted(v);

  /// 这种类型的值装进“任意”要不要过一遍小库（列表、字典拍快照；整数和小数分开的语言里整数要变成小数）。
  bool needsDyn(LType from) => from.kind == LKind.list || from.kind == LKind.dict;

  /// 整数变小数（JS 里是同一种数字，不用变）。
  String widen(String code) => code;

  String _checker(LType to) {
    final n = to.nonNull;
    final simple = switch (n.kind) {
      LKind.integer => 'asInt',
      LKind.number => 'asNum',
      LKind.text => 'asText',
      LKind.bool => 'asBool',
      LKind.fn => 'asFn',
      _ => null,
    };
    if (simple != null && !to.nullable) return rtRef(simple);
    return lam1((v) => convert(v, LType.any, to));
  }

  @override
  String convert(String code, LType from, LType to) {
    if (to.isAny) return needsDyn(from.nonNull) ? call('toDyn', [code]) : code;
    if (from.isAny) {
      if (to.nullable) return call('asOpt', [code, _checker(to.nonNull)]);
      switch (to.kind) {
        case LKind.integer:
          return call('asInt', [code]);
        case LKind.number:
          return call('asNum', [code]);
        case LKind.text:
          return call('asText', [code]);
        case LKind.bool:
          return call('asBool', [code]);
        case LKind.fn:
          return call('asFn', [code]);
        case LKind.list:
          return (to.of ?? LType.any).isAny ? call('asList', [code]) : call('asListOf', [code, _checker(to.of!)]);
        case LKind.dict:
          return (to.of ?? LType.any).isAny ? call('asDict', [code]) : call('asDictOf', [code, _checker(to.of!)]);
        case LKind.record || LKind.object || LKind.enumeration || LKind.variant:
          return call('asA', [code, typeRef(to.name ?? ''), textLit(to.name ?? '')]);
        case LKind.interface:
          return call('asKind', [code, textLit(to.name ?? '')]);
        default:
          return code;
      }
    }
    if (from.nonNull.kind == LKind.integer && to.nonNull.kind == LKind.number) return from.nullable ? call('widenOpt', [code]) : widen(code);
    return code;
  }

  @override
  String funcValue(LTypedSig f) => funcName(f.info.name);

  @override
  String neg(String op, String a) => '(0 - $a)';

  @override
  String arith(String op, String a, String b) => switch (op) {
    'fadd' => '($a + $b)',
    'fsub' => '($a - $b)',
    'fmul' => '($a * $b)',
    _ => call(op, [a, b]),
  };

  static const Map<String, String> _cmpOps = {'lt': '<', 'le': '<=', 'gt': '>', 'ge': '>='};

  @override
  String compare(String kind, String cmp, String a, String b) {
    final o = _cmpOps[cmp]!;
    return switch (kind) {
      'i' || 'f' => '($a $o $b)',
      't' => '(${call('cmpText', [a, b])} $o 0)',
      'd' => '(${call('dcmp', [a, b])} $o 0)',
      _ => '(${call('cmp', [a, b])} $o 0)',
    };
  }

  static bool _plain(LType type) => !type.nullable && const {LKind.integer, LKind.number, LKind.text, LKind.bool, LKind.enumeration}.contains(type.kind);

  @override
  String eqSame(LType type, String a, String b) => _plain(type) ? '($a $eqOp $b)' : call('eq', [a, b]);
  @override
  String sameEnum(String a, String b) => '($a $eqOp $b)';
  @override
  String isNullCode(String code, LType type) => '($code $eqOp ${nullLit()})';
  @override
  String notCode(String a) => '(!$a)';
  @override
  String logic(String op, String a, String b) => '($a ${op == 'and' ? andOp : orOp} $b)';
  @override
  String ternary(String cond, String a, String b, LType type) => '($cond ? $a : $b)';

  @override
  String listAt(String list, String index, LType elem) => call('at', [list, index]);
  @override
  String dictGet(String dict, String key, LType value) => call('get', [dict, key]);
  @override
  String dynGet(String of, String key) => call('dynGet', [of, key]);
  @override
  String listSetCode(String list, String index, String value, LType elem) => call('setAt', [list, index, value]);
  @override
  String dictSetCode(String dict, String key, String value, LType valueType) => call('dictSet', [dict, key, value]);
  @override
  String dynSetCode(String of, String key, String value) => call('dynSet', [of, key, value]);

  @override
  String callNamed(LTypedSig f, List<String> args, List<LType> typeArgs) => '${funcName(f.info.name)}(${args.join(', ')})';
  @override
  String callValue(String f, List<String> args, LType ft) => '$f(${args.join(', ')})';
  @override
  String dynCall(String f, List<String> args) => '${call('asFn', [f])}(${args.join(', ')})';
  @override
  String rtCall(String fn, List<String> args, List<LType> types, LType ret, LRt e) => kLangRtV2Tasks.contains(fn) ? hostCall(fn, args) : call(fn, args);
  @override
  String hostCall(String fn, List<String> args) => call(fn, args);
  @override
  String spawnCode(String f, LType ft) => hostCall('spawn', [f]);
  @override
  String waitCode(String task, LType of) => hostCall('wait', [task]);

  /// 标了“要等”的函数 / 方法在代码里的名字（方法是“类名.方法名”）；主程序里有没有要等的事。只有 Node 用得着。
  final Set<String> waitDecls = {};
  bool mainWaits = false;

  @override
  String text(String code, LType type) {
    if (type.nullable) return call('dtext', [code]);
    return switch (type.kind) {
      LKind.text => code,
      LKind.integer => call('itext', [code]),
      LKind.number => call('fmtNum', [code]),
      LKind.bool => call('boolText', [code]),
      _ => call('dtext', [code]),
    };
  }

  @override
  String concat(List<String> parts) => parts.length == 1 ? parts.first : '(${parts.join(' $catOp ')})';
  @override
  String logCode(String text) => call('log', [text]);
  @override
  String sizeCode(String code, LType type) => call(
    switch (type.kind) {
      LKind.text => 'textLen',
      LKind.list || LKind.dict => 'len',
      _ => 'dynSize',
    },
    [code],
  );
  @override
  String orElseCode(String code, LType type, String def, LType want) => '($code ?? $def)';
  @override
  String mustCode(String code, LType type) => call('must', [code]);
  @override
  String pushCode(String list, String value, LType listType) => call('push', [list, value]);
  @override
  String popCode(String list, LType listType) => call('pop', [list]);
  @override
  String dictRemoveCode(String dict, String key, LType dictType) => call('dictRemove', [dict, key]);
  @override
  String dynRt(String fn, List<String> args) => call('dyn${fn[0].toUpperCase()}${fn.substring(1)}', args);

  @override
  String recordNew(LRecordDecl d, LType type, List<String> values) => newOf(typeName(d.name), values);
  @override
  String recordCopy(LRecordDecl d, LType type, String of, Map<String, String> changes) => call('recCopy', [
    of,
    this.changes({for (final e in changes.entries) member(e.key): e.value}),
  ]);
  @override
  String fieldGet(String of, LType ofType, String name, LField e) => '$of$dot${member(name)}';
  @override
  String setFieldLine(String obj, LType objType, String name, String value, LTField target) => assignLine('$obj$dot${member(name)}', value);
  @override
  String enumCode(LEnumDecl d, String caseName) => enumRef(typeName(d.name), 'c_${v2Ident(caseName)}');
  @override
  String variantNew(LVariantDecl d, LVariantCase c, List<String> args) => newOf(caseType(d.name, c.name), args);
  @override
  String isCase(String v, LVariantDecl d, LVariantCase c) => instanceOf(v, caseType(d.name, c.name));
  @override
  String caseField(String v, LVariantDecl d, LVariantCase c, int i) => '$v$dot${member(c.fields[i].name)}';
  @override
  String newObject(LClassInfo c, LType type, List<String> args) => newOf(typeName(c.name), args);
  @override
  String send(String obj, LType objType, String method, List<String> args, LSend e) => '$obj$dot${member(method)}(${args.join(', ')})';
  @override
  String isA(String code, LType type, String cls) => w.interfaces.containsKey(cls) ? call('isKind', [code, textLit(cls)]) : instanceOf(code, typeName(cls));
  @override
  String downcast(String code, LType from, LType to) =>
      to.kind == LKind.interface ? call('asKind', [code, textLit(to.name ?? '')]) : call('asA', [code, typeRef(to.name ?? ''), textLit(to.name ?? '')]);

  // —— 语句 ——

  @override
  List<String> unreachable() => [
    '${call('fail', [textLit('到不了这里')])}$end',
  ];
  @override
  String snapshot(String list, LType elem) => call('items', [list]);
  @override
  String nativeAt(String arr, String k, LType elem) => '$arr[$k]';
  @override
  String dictKeysNative(String dict, LType value) => call('keys', [dict]);
  @override
  String stepsCode(String a, String b, String s, {required bool ints}) => call(ints ? 'steps' : 'fsteps', [a, b, s]);

  /// 这一层函数开头要先放成“空”的名字（代码里的名字）。
  List<String> localNames(V2Fn f) => inFn(f, () => [for (final v in localsOf(f.scope)) varCode(V2Var(v, f.depth))]);

  // —— 整个程序 ——

  List<String> _function(LFuncDecl d) {
    final sig = r.funcs[d.name]!;
    final f = V2Fn(d.name, sig.returns, waits: sig.waits);
    if (sig.waits) waitDecls.add(funcName(d.name));
    return funcDecl(funcName(d.name), paramCodes(f, d.params), funcBody(f, d.body));
  }

  DynClass _class(LClassInfo c) {
    final d = c.decl;
    final init = V2Fn('${c.name}.字段', LType.nul, cls: c);
    final fields = inFn(
      init,
      () => [
        for (final f in d.ownFields)
          () {
            final ft = w.resolve(f.type, c.typeVars);
            return (member(f.name), f.init == null ? nullLit() : x(f.init!, ft));
          }(),
      ],
    );
    List<String>? ctorParams;
    var ctorBody = const <String>[];
    final ctor = d.ctor;
    if (ctor != null) {
      final f = V2Fn('${c.name}.创建', LType.nul, cls: c, isCtor: true);
      ctorParams = paramCodes(f, ctor.params);
      ctorBody = funcBody(f, ctor.body);
    }
    final methods = <(String, List<String>, List<String>)>[];
    for (final m in d.ownMethods) {
      final sig = r.funcs['${c.name}.${m.fn.name}']!;
      final f = V2Fn(sig.key, sig.returns, cls: c, waits: sig.waits);
      if (sig.waits) waitDecls.add('${typeName(c.name)}.${member(m.fn.name)}');
      methods.add((member(m.fn.name), paramCodes(f, m.fn.params), funcBody(f, m.fn.body)));
    }
    return DynClass(c, typeName(c.name), d.parent == null ? null : typeName(d.parent!), w.supers(c.name), fields, ctorParams, ctorBody, methods);
  }

  /// “创建时”里有没有自己调父类的“创建时”。
  bool callsSuperCtor(LClassInfo c) {
    var found = false;
    lWalkAll(c.decl.ctor?.body ?? const [], (e) {
      if (e is LSuperSend && e.isCtor) found = true;
    });
    return found;
  }

  /// 顶层代码按“归哪一份”攒好（不分文件时只有一份），外加主程序的代码、每一份的模块级变量。
  (Gen2Parts, List<String>, Map<String, List<String>>) _collect() {
    final parts = Gen2Parts();
    String part(String name) => split?.of(name) ?? Gen2Split.kinds;
    void add(String p, List<String> lines) => parts.add(p, lines, gap: true);
    final vars = <String, List<String>>{};
    for (final g in globals) {
      curModule = part(g.name);
      (vars[curModule] ??= []).add(varCode(V2Var(g, 0, global: true)));
    }
    vars.forEach((p, names) => add(p, globalDecls(names)));
    for (final d in decls) {
      final p = curModule = part(d.name);
      switch (d) {
        case LRecordDecl():
          parts.name(p, typeName(d.name));
          add(p, recordDecl(typeName(d.name), d.name, [for (final f in d.fields) member(f.name)]));
        case LEnumDecl():
          parts.name(p, typeName(d.name));
          add(p, enumDecl(typeName(d.name), d.name, [for (final c in d.cases) ('c_${v2Ident(c)}', c)]));
        case LVariantDecl():
          parts.name(p, typeName(d.name));
          add(p, recordDecl(typeName(d.name), d.name, const [], base: ''));
          for (final c in d.cases) {
            parts.name(p, caseType(d.name, c.name));
            add(p, recordDecl(caseType(d.name, c.name), c.name, [for (final f in c.fields) member(f.name)], base: typeName(d.name)));
          }
        case LClassDecl():
          parts.name(p, typeName(d.name));
          add(p, classDecl(_class(w.classes[d.name]!)));
        case LFuncDecl():
          parts.name(p, funcName(d.name));
          add(p, _function(d));
        case LAliasDecl() || LInterfaceDecl() || LVarDecl() || LNativeDecl():
          break;
      }
    }
    final main = V2Fn(Gen2Base.mainScope, LType.nul, isMain: true, waits: true);
    curModule = Gen2Split.kinds;
    if (r.usesErrors) add(Gen2Split.kinds, errSupport());
    curModule = split?.entry ?? Gen2Split.kinds;
    final body = funcBody(main, startup);
    mainWaits = main.usedWait;
    return (parts, body, vars);
  }

  @override
  String program() {
    final (parts, body, _) = _collect();
    return programText(parts.of(Gen2Split.kinds), body);
  }

  /// 一个模块一个文件：主文件（入口模块＋主程序）、内置错误种类一份（用到了才有）、别的模块各一份。
  @override
  Map<String, String> programFiles() {
    final s = split;
    if (s == null) return super.programFiles();
    final (parts, body, vars) = _collect();
    const kinds = Gen2Split.kinds;
    final hasKinds = parts.of(kinds).isNotEmpty;
    List<String> head(String part) => [
      if (hasKinds) ...importLines(kinds, parts.namesOf(kinds), vars: false, inMain: part == s.entry),
      for (final m in s.before(part)) ...importLines(m, parts.namesOf(m), vars: vars[m]?.isNotEmpty ?? false, inMain: part == s.entry),
    ];
    return {
      mainFile: programText(parts.of(s.entry), body, head: head(s.entry)),
      if (hasKinds) '${partBase(kinds)}.$ext': moduleText('内置的错误种类', const [], parts.of(kinds), exportLines(parts.namesOf(kinds), const [])),
      for (final m in s.order)
        '${partBase(m)}.$ext': moduleText('模块「${m.replaceAll(RegExp(r'[\x00-\x1f\x7f\u0085\u2028\u2029]'), ' ')}」', head(m), parts.of(m), exportLines(parts.namesOf(m), vars[m] ?? const [])),
    };
  }
}

/// 把一串语句里所有的式子（连套着的）走一遍；不进匿名函数。
void lWalkAll(List<LStmt> body, void Function(LExpr e) visit) {
  void go(LExpr e) {
    visit(e);
    if (e is LLambda) return;
    lExprChildren(e).forEach(go);
  }

  lWalk(body, (LStmt s) => lStmtExprs(s).forEach(go));
}
