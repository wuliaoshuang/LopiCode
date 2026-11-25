/// 规矩版本 2 的类型检查和推断（积木第 5 版·核心 1）。
///
/// 规则：docs/blocks-v5-parts/B-type-system.md 第 4 节；算法是推断原型 docs/blocks-v5-prototypes/types/infer.py 的移植
/// （`test/lang_typecheck_proto_test.dart` 拿原型的 16 个程序、4 组错例逐行对照）。接口怎么用见 docs/blocks-v5-parts/B-impl-notes.md。
///
/// 规矩版本 1 的文档不走这里（它用 analyze.dart，行为不变）。
///
/// 注意：结果按“节点对象”记（不是按内容）。同一个节点对象不要在一棵树里出现两次（`const` 写的两处一模一样的节点是同一个对象）。
library;

import 'dart:collection';

import 'package:lopicode/lang/ast.dart';
import 'package:lopicode/lang/ast_util.dart';
import 'package:lopicode/lang/rt_v2.dart';
import 'package:lopicode/lang/type_issue.dart';
import 'package:lopicode/lang/type_world.dart';
import 'package:lopicode/lang/types.dart';

part 'typecheck_call.dart';
part 'typecheck_decl.dart';
part 'typecheck_expr.dart';
part 'typecheck_result.dart';
part 'typecheck_rt.dart';
part 'typecheck_stmt.dart';

/// 检查一个模块：声明＋“启动时”的语句（记在“主”名下）。
LTypeResult checkModuleTypes(LModule module) => checkTypes(decls: module.decls, main: module.body);

/// 一段单独的脚本（比如后端的一个接口、前端的一个事件）：有自己的一层变量，看得见 [checkTypes] 的 `decls` 里的东西。
class LTypeScript {
  const LTypeScript(this.name, this.body, {this.vars = const {}});

  /// 记在谁名下（提示语里的“在哪”）。不能和函数重名。
  final String name;
  final List<LStmt> body;

  /// 宿主给这段脚本的变量（名字 → 类型）。
  final Map<String, LType> vars;
}

/// 检查一批声明＋主程序＋若干段脚本。[outer] 是宿主给的、到处看得见的变量。
LTypeResult checkTypes({List<LDecl> decls = const [], List<LStmt> main = const [], List<LTypeScript> scripts = const [], Map<String, LType> outer = const {}}) {
  final c = _Checker(decls, main, scripts, outer);
  return c.run();
}

const LType _int = LType.integer;
const LType _flt = LType.number;
const LType _txt = LType.text;
const LType _bool = LType.boolean;
const LType _nul = LType.nul;
const LType _any = LType.any;
const LType _never = LType.never;

const String _mainKey = '主';

class _Var {
  _Var(this.t, {this.fixed = false, this.hidden = false, this.kind = LVarKind.local});
  LType t;
  bool fixed;
  bool hidden;
  LVarKind kind;

  /// 标成“任意”的变量里放过带类型的列表 / 字典（T14 用）。
  bool holdsSnapshot = false;
}

class _Scope {
  _Scope(this.key, this.fn, {this.parent, this.lam = false, List<String>? tv, LType? thisType})
    : tv = tv != null && tv.isNotEmpty ? tv : (parent?.tv ?? const []),
      thisType = thisType ?? parent?.thisType,
      bounds = parent?.bounds ?? const {},
      reassigned = parent?.reassigned ?? const {};
  final String key;
  final String fn;
  final _Scope? parent;
  final bool lam;
  final Set<String> names = {};

  /// 现在肯定不是空的变量。
  Set<String> nn = {};
  final List<String> tv;
  final LType? thisType;
  final List<LType> rets = [];
  Map<String, String> bounds;
  Set<String> reassigned;
  LTypedFunc? f;
}

abstract class _Core {
  _Core(this.decls, this.main, this.scripts, this.outer);
  final List<LDecl> decls;
  final List<LStmt> main;
  final List<LTypeScript> scripts;
  final Map<String, LType> outer;

  final LTypeWorld w = LTypeWorld();
  final Map<String, LNativeDecl> natives = {};
  final List<LVarDecl> globals = [];
  final List<String> sigOrder = [];

  /// 变量表（“作用域记号 名字” → 变量），整个推断过程里一直留着、只会变宽。
  final Map<String, _Var> vt = {};
  final List<(String, String)> order = [];

  /// 没标类型的参数从调用处反推出来的类型、没标的返回类型。
  final Map<String, LType> pt = {};
  final Map<String, LType> rt = {};

  bool finalPass = false;
  int passes = 0;
  final List<LTypeIssue> issues = [];
  final Set<String> _said = {};
  final Map<Object, int> _ids = HashMap.identity();

  // —— 最后一遍记下来、交给生成器的东西 ——
  final Map<LExpr, LType> types = HashMap.identity();
  final Map<LExpr, LType> wants = HashMap.identity();
  final Map<LNode, String> ops = HashMap.identity();
  final Map<LNode, Map<String, LType>> typeArgs = HashMap.identity();
  final List<LRuntimeCheck> checks = [];
  final Set<String> _checked = {};
  final Map<LLambda, String> lambdaKeys = HashMap.identity();

  /// （放进变量的式子, 变量的记号）、（没标返回类型的函数里“返回”的式子, 函数）：收尾时算它们要放进什么类型的地方。
  final List<(LExpr, String)> _assigned = [];
  final List<(LExpr, LTypedFunc)> _returned = [];

  /// 现在在检查哪一句（式子自己没带位置时用它的）。
  LSrc? curSrc;
  LStmt? curStmt;

  /// 一个“待定”的记号：哪个节点、在哪一句、哪一层里（`const` 写的两个一模一样的空列表是同一个对象，光按节点分不开）。
  String holeKey(LNode e, _Scope sc, [String tail = '']) => '${id(e)}@${curStmt == null ? 0 : id(curStmt!)}@${sc.key}$tail';

  int id(Object node) => _ids.putIfAbsent(node, () => _ids.length + 1);
  String vkey(String scope, String name) => '$scope\u0001$name';
  String show(LType t) => w.res(t).show();

  void err(String code, _Scope sc, String message, {LNode? node, int? argIndex, List<LFix> fixes = const [], String? where}) {
    if (!finalPass) return;
    final at = where ?? sc.fn;
    if (!_said.add('$code $at：$message#${node == null ? 0 : id(node)}')) return;
    issues.add(LTypeIssue(code, at, message, level: kTypeRules[code]!.level, node: node, src: node?.src ?? curSrc, argIndex: argIndex, fixes: fixes));
  }

  void check(LCheckKind kind, LNode node, _Scope sc, {LType? type}) {
    if (!finalPass || !_checked.add('${kind.name}#${id(node)}')) return;
    checks.add(LRuntimeCheck(kind, node, type: type, where: sc.fn));
  }

  void op(LNode node, String name) {
    if (finalPass) ops[node] = name;
  }

  void want(LExpr e, LType t) {
    if (finalPass) wants[e] = t;
  }

  // —— 变量表 ——
  String? find(_Scope? sc, String name) {
    while (sc != null) {
      if (sc.names.contains(name) && vt.containsKey(vkey(sc.key, name))) return vkey(sc.key, name);
      sc = sc.parent;
    }
    return null;
  }

  /// 只在这个函数自己里面找（匿名函数往外找到包着它的函数为止）：新建变量时用，函数里的变量可以和外面的同名。
  String? findLocal(_Scope? sc, String name) {
    while (sc != null) {
      if (sc.names.contains(name) && vt.containsKey(vkey(sc.key, name))) return vkey(sc.key, name);
      if (!sc.lam) return null;
      sc = sc.parent;
    }
    return null;
  }

  void note(_Scope sc, String name, LType t, {LType? declared, LNode? node, LVarKind kind = LVarKind.local, bool local = false}) {
    final found = declared == null ? (local ? findLocal(sc, name) : find(sc, name)) : null;
    final key = found ?? vkey(sc.key, name);
    var v = vt[key];
    if (v == null) {
      v = vt[key] = _Var(_never, kind: kind);
      if (!sc.lam) order.add((sc.key, name));
    }
    if (declared != null) {
      v.t = declared;
      v.fixed = true;
    }
    if (v.fixed) {
      if (!w.ok(t, v.t)) {
        final have = w.res(v.t), got = w.res(t);
        err('T01', sc, '「$name」是${have.show()}，放进来的是${got.show()}', node: node, fixes: node is LExpr ? fixesFor(node, got, have) : const []);
      }
      w.unify(v.t, t, {});
      if (v.t.isAny && node != null) {
        final got = w.res(t);
        if ((WL.isList(got) || WL.isDict(got)) && !WL.elem(got).isAny) v.holdsSnapshot = true;
      }
      return;
    }
    final now = w.join(v.t, t);
    if (now != v.t) {
      v.t = now;
      w.changed = true;
    }
  }

  void declare(_Scope sc, String name, LType t, {LType? declared, LNode? node, LVarKind kind = LVarKind.local}) {
    sc.names.add(name);
    note(sc, name, t, declared: declared, node: node, kind: kind, local: true);
    sc.nn.remove(name);
  }

  /// 给 [e] 包一层什么能修好（要 [want]，给的是 [got]）。
  List<LFix> fixesFor(LExpr e, LType got, LType want) {
    if (got.nullable && w.ok(got.nonNull, want)) {
      return [LFix(LFixKind.wrapOrElse, '是空就用 …', target: e), LFix(LFixKind.wrapMust, '一定不是空', target: e)];
    }
    if (want == _txt && !got.nullable && !got.isNul) return [LFix(LFixKind.wrapToText, '变成文字', target: e)];
    if (want == _int && got == _flt) return [LFix(LFixKind.wrapToInt, '取整', target: e)];
    if (want == _int && got == _txt) return [LFix(LFixKind.wrapParseInt, '变成整数（变不了就是空）', target: e)];
    return const [];
  }

  /// [e]（类型是 [t]）放不进要 [wantT] 的地方：可能是空报 T02，别的报 T01。[lead] 是“某某要整数”那半句。
  void mismatch(_Scope sc, LExpr e, LType t, LType wantT, String lead, {int? argIndex}) {
    if (t.nullable && w.ok(t.nonNull, wantT)) {
      final nm = e is LName ? '「${e.name}」' : '这个值';
      err('T02', sc, '$lead，$nm可能是空，要先判断“不是空”', node: e, argIndex: argIndex, fixes: fixesFor(e, t, wantT));
    } else {
      err('T01', sc, '$lead，放进来的是${t.show()}', node: e, argIndex: argIndex, fixes: fixesFor(e, t, wantT));
    }
  }

  LType ptype(LTypedFunc f, int i) {
    final p = f.params[i];
    if (p.type != null) return w.resolve(p.type, f.typeVars);
    return pt['${f.key}#$i'] ?? _never;
  }

  LType rtype(LTypedFunc f) => f.ret != null ? w.resolve(f.ret, f.typeVars) : (rt[f.key] ?? _never);

  LType fnType(LTypedFunc f) => LType(LKind.fn, args: [for (var i = 0; i < f.params.length; i++) ptype(f, i), rtype(f)]);

  // —— 各部分互相要用的 ——
  LType ex(_Scope sc, LExpr e, [LType? wantT]);
  LType arg(_Scope sc, LExpr e, LType wantT, String where, {int? argIndex});
  void cond(_Scope sc, LExpr e);
  LType nonnull(_Scope sc, LExpr e, String Function(LType t) what);
  Set<String> facts(LExpr e, bool truth);
  LType lam(_Scope sc, LLambda e, LType? wantT);
  LType apply(
    _Scope sc,
    String name,
    List<LType> pts,
    LType ret,
    List<String> tvs,
    Map<String, String> bounds,
    List<LExpr> args, {
    Map<String, LType>? pre,
    LTypedFunc? f,
    LNode? node,
    List<String> slots = const [],
  });
  LType call(_Scope sc, LCall e);
  LType field(_Scope sc, LExpr of, String name, LNode node);
  LType send(_Scope sc, LSend e);
  LType superSend(_Scope sc, LSuperSend e);
  LType newObject(_Scope sc, LNew e);
  LType runtimeCall(_Scope sc, LRt e, LType? wantT);
  LType index(_Scope sc, LExpr of, LExpr key, LNode node);
  void store(_Scope sc, LExpr of, LExpr key, LExpr value, LNode node);
  void push(_Scope sc, LExpr of, LExpr value, LNode node);
  void block(_Scope sc, List<LStmt> body);
  void runFn(LTypedFunc f, {LType? thisType, _Scope? parent});
}

/// 写起来短一点。
typedef WL = LTypeWorld;

class _Checker extends _Core with _Exprs, _Calls, _Rt, _Stmts, _Decls {
  _Checker(super.decls, super.main, super.scripts, super.outer);

  LTypeResult run() {
    collect();
    for (var n = 0; n < 12; n++) {
      w.changed = false;
      onePass();
      passes = n + 1;
      if (!w.changed) break;
    }
    finalPass = true;
    onePass();
    return finish();
  }
}
