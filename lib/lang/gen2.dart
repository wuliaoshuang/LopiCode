/// 规矩版本 2 的生成器（积木第 5 版·核心 1）：吃“一整个模块的语法树＋类型检查的结果”，吐一种语言的完整程序。
///
/// 和版本 1 的生成器（gen.dart）是两条路，互不影响：版本 1 所有运算走小库、值一律是“任意”；这里每个式子按检查器推出来的类型
/// 写代码（Go / Java 用原生类型，Node / Python / PHP 用严格的小函数），在“用到的地方”按要的类型转换
/// （整数→小数、装进任意、任意取回时检查、可空的包和拆）。设计：docs/blocks-v5-parts/B-type-system.md 第 7、8、11 节；
/// 实际落成什么见 docs/blocks-v5-parts/B-gen-notes.md。
///
/// 这个文件是和语言无关的骨架：作用域、哪些变量被里层函数用到、语句。式子在 gen2_expr.dart。
/// “这种语言里怎么写”是一批钩子，各语言在 gen2_*.dart 里答。碰到还不支持的东西抛 [LangUnsupported]。
library;

import 'package:lopicode/lang/ast.dart';
import 'package:lopicode/lang/ast_util.dart';
import 'package:lopicode/lang/gen_support.dart';
import 'package:lopicode/lang/type_world.dart';
import 'package:lopicode/lang/typecheck.dart';
import 'package:lopicode/lang/types.dart';

export 'package:lopicode/lang/gen_support.dart' show LangUnsupported;

final RegExp _identChar = RegExp(r'^[\p{L}\p{Nd}_]$', unicode: true);

/// 把用户起的名字收拾成五种语言都认的标识符的一截：字母（含中文）、数字、下划线原样，别的写成 `_u码点_`。
String v2Ident(String s) {
  final out = StringBuffer();
  for (final r in s.runes) {
    final ch = String.fromCharCode(r);
    out.write(_identChar.hasMatch(ch) ? ch : '_u${r.toRadixString(16)}_');
  }
  return out.toString();
}

/// 找到的一个变量：它的类型、是哪一层函数的（[depth]＝套了几层匿名函数）、是不是模块级的。
class V2Var {
  const V2Var(this.info, this.depth, {this.global = false});
  final LVarInfo info;
  final int depth;
  final bool global;
  String get name => info.name;
  LType get type => info.type;
}

/// 正在生成的那个函数（有名字的函数、方法、“创建时”、匿名函数、主程序）。
class V2Fn {
  V2Fn(this.scope, this.ret, {this.parent, this.lambda, this.cls, this.isCtor = false, this.isMain = false});
  final String scope;

  /// 返回类型；空＝不返回东西。
  final LType ret;
  final V2Fn? parent;
  final LLambda? lambda;
  final LClassInfo? cls;
  final bool isCtor;
  final bool isMain;

  int get depth => parent == null ? 0 : parent!.depth + 1;
  V2Fn get root => parent?.root ?? this;
  bool get isVoid => ret.isNul;

  /// 所在的类（匿名函数看外面的）。
  LClassInfo? get owner => cls ?? parent?.owner;

  /// 要放到“当前这一句”前面的代码（Python 带语句的匿名函数先在前面定义）。
  List<String> pre = [];
  int _n = 0;
  int next() => ++root._n;

  /// 这个函数里有没有“试着做”（Go 要多声明两个变量）。
  bool hasTry = false;
}

abstract class Gen2Base {
  Gen2Base(this.module, this.r) {
    for (final v in r.vars) {
      (_vars[v.scope] ??= {})[v.name] = v;
    }
    _scanAll();
  }

  final LModule module;
  final LTypeResult r;
  LTypeWorld get w => r.world;

  static const String mainScope = '主';

  final Map<String, Map<String, LVarInfo>> _vars = {};

  /// 被里层匿名函数用到的变量：属于哪一层 → 名字。
  final Map<String, Set<String>> captured = {};

  /// 每个匿名函数用到（[lambdaUses]）、改到（[lambdaWrites]）的外层变量（连它里面套着的匿名函数用到的）。
  final Map<LLambda, Set<String>> lambdaUses = Map.identity();
  final Map<LLambda, Set<String>> lambdaWrites = Map.identity();

  late V2Fn fn;

  // —— 小工具 ——

  String get indentUnit => '  ';
  List<String> indent(List<String> lines) => [
    for (final l in lines)
      for (final x in l.split('\n')) x.isEmpty ? x : '$indentUnit$x',
  ];

  /// 式子的类型。“我自己”常常是共用的一个节点（检查结果按节点对象记，会串），所以按当前所在的类现算。
  LType t(LExpr e) => e is LThis ? selfType : r.typeOf(e) ?? LType.any;

  /// 当前所在的类的类型。
  LType get selfType {
    final c = _fnOrNull?.owner;
    return c == null ? LType.any : LType(LKind.object, name: c.name, args: [for (final v in c.typeVars) LType(LKind.typeVar, name: v)]);
  }

  Never unsupported(String what, [LNode? node]) => throw LangUnsupported(what, src: node?.src);

  /// 这一层函数自己的变量（不含参数、模块级变量）。
  List<LVarInfo> localsOf(String scope) => [
    for (final v in (_vars[scope] ?? const <String, LVarInfo>{}).values)
      if (v.kind != LVarKind.param && v.kind != LVarKind.global && v.kind != LVarKind.host) v,
  ];

  List<LVarInfo> get globals => [
    for (final v in (_vars[mainScope] ?? const <String, LVarInfo>{}).values)
      if (v.kind == LVarKind.global) v,
  ];

  LVarInfo? varIn(String scope, String name) => _vars[scope]?[name];

  /// 从现在这个位置往外找一个名字。
  V2Var? lookup(String name) {
    for (V2Fn? f = fn; f != null; f = f.parent) {
      final v = _vars[f.scope]?[name];
      if (v != null) return V2Var(v, f.depth, global: v.kind == LVarKind.global);
    }
    final g = _vars[mainScope]?[name];
    return g != null && g.kind == LVarKind.global ? V2Var(g, 0, global: true) : null;
  }

  V2Var mustVar(String name, LNode node) => lookup(name) ?? unsupported('找不到变量「$name」（类型检查没有给出它）', node);

  bool isCaptured(V2Var v) => !v.global && (captured[_scopeAt(v.depth)]?.contains(v.name) ?? false);

  String _scopeAt(int depth) {
    V2Fn f = fn;
    while (f.depth > depth && f.parent != null) {
      f = f.parent!;
    }
    return f.scope;
  }

  // —— 先扫一遍：哪些变量被里层的匿名函数用到 ——

  void _scanAll() {
    for (final d in module.decls) {
      if (d is LFuncDecl) _scan(d.body, [d.name], const []);
      if (d is LClassDecl) {
        final c = d.ctor;
        if (c != null) _scan(c.body, ['${d.name}.创建'], const []);
        for (final m in d.methods) {
          _scan(m.fn.body, ['${d.name}.${m.fn.name}'], const []);
        }
      }
    }
    _scan(module.body, [mainScope], const []);
  }

  void _use(String name, List<String> chain, List<LLambda> lams, {bool write = false}) {
    for (var i = chain.length - 1; i >= 0; i--) {
      if (!(_vars[chain[i]]?.containsKey(name) ?? false)) continue;
      if (i == chain.length - 1) return;
      if (_vars[chain[i]]![name]!.kind == LVarKind.global) return;
      (captured[chain[i]] ??= {}).add(name);
      for (final l in lams.sublist(i)) {
        (lambdaUses[l] ??= {}).add(name);
        if (write) (lambdaWrites[l] ??= {}).add(name);
      }
      return;
    }
  }

  void _scanExpr(LExpr e, List<String> chain, List<LLambda> lams) {
    if (e is LName && e.kind == LNameKind.variable) _use(e.name, chain, lams);
    if (e is LLambda) {
      final key = r.lambdaScope(e);
      if (key == null) return;
      final c = [...chain, key], l = [...lams, e];
      if (e.expr != null) {
        _scanExpr(e.expr!, c, l);
      } else {
        _scan(e.body, c, l);
      }
      return;
    }
    for (final x in lExprChildren(e)) {
      _scanExpr(x, chain, lams);
    }
  }

  void _scan(List<LStmt> body, List<String> chain, List<LLambda> lams) {
    void w(String? n) {
      if (n != null) _use(n, chain, lams, write: true);
    }

    lWalk(body, (s) {
      switch (s) {
        case LLet(:final name):
          w(name);
        case LAssign(target: LTName(:final name)):
          w(name);
        case LAssign(target: LTIndex(:final of, :final key)):
          _scanExpr(of, chain, lams);
          _scanExpr(key, chain, lams);
        case LAssign(target: LTField(:final of)):
          _scanExpr(of, chain, lams);
        case LForEach(:final item, :final index):
          w(item);
          w(index);
        case LForCount(:final name):
          w(name);
        case LForPairs(:final key, :final value):
          w(key);
          w(value);
        case LTry(:final errorName):
          w(errorName);
        case LMatch(:final arms):
          for (final a in arms) {
            a.binds.forEach(w);
          }
        default:
          break;
      }
      for (final e in lStmtExprs(s)) {
        _scanExpr(e, chain, lams);
      }
    });
  }

  // —— 类型上的小工具 ——

  Map<String, LType> _argMap(List<String> names, List<LType> args) => {for (var i = 0; i < names.length && i < args.length; i++) names[i]: args[i]};

  /// 记录 / 类的类型实参表。
  Map<String, LType> typeArgsOfType(LType recv) {
    final rec = w.records[recv.name];
    if (rec != null && recv.kind == LKind.record) return _argMap([for (final p in rec.typeParams) p.name], recv.args);
    final c = w.classes[recv.name];
    return c == null ? const {} : _argMap(c.typeVars, recv.args);
  }

  /// 字段的类型（已经把接收者的类型实参代进去）。
  LType fieldType(LType recv, String name, LNode node) {
    final b = typeArgsOfType(recv);
    final rec = w.records[recv.name];
    if (recv.kind == LKind.record && rec != null) {
      for (final f in rec.fields) {
        if (f.name == name) return w.subst(w.resolve(f.type, [for (final p in rec.typeParams) p.name]), b);
      }
    }
    final got = w.classField(w.classes[recv.name], name);
    if (got != null) return w.subst(got.$1, b);
    unsupported('${recv.show()} 没有「$name」这个字段', node);
  }

  /// 字段是哪个类声明的。
  LClassInfo? fieldOwner(LType recv, String name) => w.classField(w.classes[recv.name], name)?.$2;

  // —— 语句（和语言无关的部分）——

  /// 这种语言的钩子（语句）。
  String get end => ';';
  bool get braces => true;
  String ifHead(String cond) => 'if ($cond)';
  String elseIfHead(String cond) => 'else if ($cond)';
  String whileHead(String? cond) => 'while (${cond ?? trueLit})';
  String get trueLit => 'true';
  String comment(String text) => '// ${langComment(text)}';

  /// 从 0 数到 n − 1；[k] 是这种语言自己的整数。
  String countHead(String k, String n);

  /// 就地存一个不会再改的临时值。
  String tmpDecl(String name, LType type, String code);
  String tmpName(String letter) => 'lc$letter${fn.next()}';
  String assignLine(String target, String value) => '$target = $value$end';

  /// [isVoid]：这个式子本来就不给结果（调一个不返回东西的函数）。
  List<String> exprStmt(String code, {required bool isVoid}) => ['$code$end'];
  String returnLine(String? value) => value == null ? 'return$end' : 'return $value$end';
  List<String> breakLines() => ['break$end'];
  List<String> continueLines() => ['continue$end'];
  List<String> throwLines(String message);

  /// 走不到的地方（“看是哪种情况”每种都写了以后的那个“否则”）。
  List<String> unreachable();

  /// 试着做 / 出错了 / 最后。[errTarget]＝接错误文字的变量（没起名字是 null）。
  List<String> tryLines(LTry s, List<String> Function(List<LStmt>) gen, String? errTarget);

  /// 列表拍一份这种语言自己的数组（遍历时用）；它有几项、第 k 项。
  String snapshot(String list, LType elem);
  String nativeLen(String arr);
  String nativeAt(String arr, String k, LType elem);

  /// 字典的键（按码点排好）拍成这种语言自己的数组；按键直接取（一定有）。
  String dictKeysNative(String dict, LType value);
  String dictAt(String dict, String key, LType value);

  /// 语言自己的整数 → 整数。
  String nativeInt(String k) => k;

  /// 从 a 数到 b、每次加 s，要数几遍（语言自己的整数）。
  String stepsCode(String a, String b, String s, {required bool ints});

  /// 进出循环（Go 的“试着做”要知道“跳出”是不是跨了闭包）。
  void loopIn() {}
  void loopOut() {}

  List<String> block(String head, List<String> body) => braces ? ['$head {', ...indent(body), '}'] : ['$head:', ...suite(body)];
  List<String> suite(List<String> body) => indent([...body, if (body.every((l) => l.trimLeft().startsWith('#'))) 'pass']);

  List<String> ifChain(List<(String, List<String>)> arms, List<String>? orElse) {
    final out = <String>[];
    for (var i = 0; i < arms.length; i++) {
      final head = i == 0 ? ifHead(arms[i].$1) : elseIfHead(arms[i].$1);
      if (braces) {
        out
          ..add(i == 0 ? '$head {' : '} $head {')
          ..addAll(indent(arms[i].$2));
      } else {
        out
          ..add('$head:')
          ..addAll(suite(arms[i].$2));
      }
    }
    if (orElse != null && orElse.isNotEmpty) {
      out.add(braces ? '} else {' : 'else:');
      out.addAll(braces ? indent(orElse) : suite(orElse));
    }
    if (braces) out.add('}');
    return out;
  }

  // 式子那一半（gen2_expr.dart）给的。
  String x(LExpr e, [LType? to]);
  String conv(String code, LType from, LType to);
  String varCode(V2Var v);
  String arith(String op, String a, String b);
  List<String> storeIndex(LAssign s, LTIndex target);
  String setFieldLine(String obj, LType objType, String name, String value, LTField target);

  List<String> stmts(List<LStmt> list) {
    final out = <String>[];
    final outer = fn.pre;
    try {
      for (final s in list) {
        fn.pre = [];
        final lines = stmt(s);
        out
          ..addAll(fn.pre)
          ..addAll(lines);
        if (lExits(s)) break;
      }
    } finally {
      fn.pre = outer;
    }
    return out;
  }

  List<String> _loop(List<String> Function() body) {
    loopIn();
    try {
      return body();
    } finally {
      loopOut();
    }
  }

  List<String> stmt(LStmt s) {
    switch (s) {
      case LNote(:final text):
        return [comment(text)];
      case LLet(:final name, :final value):
        final v = mustVar(name, s);
        return [assignLine(varCode(v), x(value, v.type))];
      case LAssign(:final target, :final value):
        switch (target) {
          case LTName(:final name):
            final v = mustVar(name, s);
            return [assignLine(varCode(v), x(value, v.type))];
          case LTIndex():
            return storeIndex(s, target);
          case LTField(:final of, :final name):
            final ot = t(of).nonNull;
            return [setFieldLine(x(of, ot), ot, name, x(value, fieldType(ot, name, s)), target)];
        }
      case LExprStmt(expr: final e):
        return exprStmt(x(e), isVoid: t(e).isNul);
      case LIf(:final arms, :final orElse):
        if (arms.isEmpty) return stmts(orElse);
        return ifChain([for (final a in arms) (x(a.cond, LType.boolean), stmts(a.body))], stmts(orElse));
      case LWhile(:final cond, :final body):
        final c = cond == null ? null : x(cond, LType.boolean);
        return block(whileHead(c), _loop(() => stmts(body)));
      case LRepeat(:final times, :final body):
        final n = tmpName('N'), k = tmpName('K');
        return [tmpDecl(n, LType.integer, x(times, LType.integer)), ...block(countHead(k, n), _loop(() => stmts(body)))];
      case LForCount(:final name, :final from, :final to, :final step, :final body):
        final v = mustVar(name, s);
        final ints = [from, to, step].every((e) => t(e) == LType.integer);
        final nt = ints ? LType.integer : LType.number;
        final a = tmpName('A'), b = tmpName('B'), st = tmpName('S'), n = tmpName('N'), k = tmpName('K');
        final kv = conv(nativeInt(k), LType.integer, nt);
        final value = ints ? arith('iadd', a, arith('imul', kv, st)) : arith('fadd', a, arith('fmul', kv, st));
        return [
          tmpDecl(a, nt, x(from, nt)),
          tmpDecl(b, nt, x(to, nt)),
          tmpDecl(st, nt, x(step, nt)),
          tmpDecl(n, LType.integer, stepsCode(a, b, st, ints: ints)),
          ...block(countHead(k, n), [assignLine(varCode(v), conv(value, nt, v.type)), ..._loop(() => stmts(body))]),
        ];
      case LForEach(:final list, :final item, :final index, :final body):
        final lt0 = t(list).nonNull;
        final lt = lt0.kind == LKind.list ? lt0 : const LType.listOf(LType.any);
        final elem = lt.of ?? LType.any;
        final v = mustVar(item, s);
        final l = tmpName('L'), k = tmpName('K');
        final iv = index == null ? null : mustVar(index, s);
        return [
          tmpDecl(l, LType.nul, snapshot(x(list, lt), elem)),
          ...block(countHead(k, nativeLen(l)), [
            assignLine(varCode(v), conv(nativeAt(l, k, elem), elem, v.type)),
            if (iv != null) assignLine(varCode(iv), conv(nativeInt(k), LType.integer, iv.type)),
            ..._loop(() => stmts(body)),
          ]),
        ];
      case LForPairs(:final dict, :final key, :final value, :final body):
        final dt0 = t(dict).nonNull;
        final dt = dt0.kind == LKind.dict ? dt0 : const LType.dictOf(LType.any);
        final vt = dt.of ?? LType.any;
        final kv = mustVar(key, s), vv = mustVar(value, s);
        final d = tmpName('D'), l = tmpName('L'), k = tmpName('K');
        return [
          tmpDecl(d, dt, x(dict, dt)),
          tmpDecl(l, LType.nul, dictKeysNative(d, vt)),
          ...block(countHead(k, nativeLen(l)), [
            assignLine(varCode(kv), conv(nativeAt(l, k, LType.text), LType.text, kv.type)),
            assignLine(varCode(vv), conv(dictAt(d, nativeAt(l, k, LType.text), vt), vt, vv.type)),
            ..._loop(() => stmts(body)),
          ]),
        ];
      case LBreak():
        return breakLines();
      case LContinue():
        return continueLines();
      case LReturn(:final value):
        return returnLines(value == null ? (fn.isVoid ? null : nulOf(fn.ret)) : (fn.isVoid ? null : x(value, fn.ret)), value: value);
      case LThrow(:final message):
        return throwLines(x(message, LType.text));
      case LTry(:final errorName):
        fn.hasTry = true;
        return tryLines(s, stmts, errorName == null ? null : varCode(mustVar(errorName, s)));
      case LMatch():
        return _match(s);
      case LHost():
        unsupported('这里有一句宿主的语句（后端的旧积木）：带类型的独立模块里还不能夹宿主语句', s);
    }
  }

  /// “返回”。不返回东西的函数里“返回 (式子)”：式子照算（[value]），再返回。
  List<String> returnLines(String? code, {LExpr? value}) => [
    if (code == null && value != null && fn.isVoid && value is! LLit) ...exprStmt(x(value), isVoid: t(value).isNul),
    returnLine(code),
  ];

  String nulOf(LType type);

  /// 枚举的一个值、变体是不是这种情况、取这种情况带的第 i 样东西。
  String enumCode(LEnumDecl d, String caseName);
  String isCase(String v, LVariantDecl d, LVariantCase c);
  String caseField(String v, LVariantDecl d, LVariantCase c, int i);
  String sameEnum(String a, String b);

  List<String> _match(LMatch s) {
    final st = t(s.subject).nonNull;
    final tmp = tmpName('M');
    final head = tmpDecl(tmp, st, x(s.subject, st));
    final arms = <(String, List<String>)>[];
    final en = w.enums[st.name], va = w.variants[st.name];
    for (final a in s.arms) {
      if (st.kind == LKind.enumeration && en != null) {
        arms.add((sameEnum(tmp, enumCode(en, a.caseName)), stmts(a.body)));
      } else if (st.kind == LKind.variant && va != null) {
        final c = va.cases.where((c) => c.name == a.caseName).firstOrNull ?? unsupported('「${va.name}」没有「${a.caseName}」这种情况', s);
        arms.add((
          isCase(tmp, va, c),
          [
            for (var i = 0; i < a.binds.length && i < c.fields.length; i++)
              () {
                final v = mustVar(a.binds[i], s);
                final ft = w.resolve(c.fields[i].type);
                return assignLine(varCode(v), conv(caseField(tmp, va, c, i), ft, v.type));
              }(),
            ...stmts(a.body),
          ],
        ));
      } else {
        unsupported('“看是哪种情况”只能看枚举和变体，这里是${st.show()}', s);
      }
    }
    final orElse = s.orElse == null ? unreachable() : stmts(s.orElse!);
    if (arms.isEmpty) return [head, ...orElse];
    return [head, ...ifChain(arms, orElse)];
  }

  /// 一个函数体（不带缩进）：开头的变量声明、语句、走到头时补的返回。
  List<String> funcBody(V2Fn f, List<LStmt> body, {List<String> Function()? first}) {
    final saved = _fnOrNull;
    fn = f;
    _fnOrNull = f;
    try {
      final head = first?.call() ?? const <String>[];
      final lines = stmts(body);
      final tail = f.isVoid ? const <String>[] : (lAlwaysReturns(body) ? alwaysTail(f) : (f.ret.nullable || f.ret.isAny ? [returnLine(nulOf(f.ret))] : unreachable()));
      return [...declareLocals(f), ...head, ...lines, ...tail];
    } finally {
      _fnOrNull = saved;
      if (saved != null) fn = saved;
    }
  }

  /// 函数体每条路都已经返回了以后还要不要补一句（Go 的“试着做”是闭包，编译器看不出来已经返回）。
  List<String> alwaysTail(V2Fn f) => const [];

  V2Fn? _fnOrNull;

  /// 在 [f] 里做一件事（生成短写法匿名函数的式子时用）。
  T inFn<T>(V2Fn f, T Function() body) {
    final saved = _fnOrNull;
    fn = f;
    _fnOrNull = f;
    try {
      return body();
    } finally {
      _fnOrNull = saved;
      if (saved != null) fn = saved;
    }
  }

  /// 函数开头声明这一层的变量。
  List<String> declareLocals(V2Fn f);

  /// **入口**：整个模块 → 一份能直接运行的程序（文件名 → 内容；小库的文件另外由 [runtimeFiles] 给）。
  String program();
}
