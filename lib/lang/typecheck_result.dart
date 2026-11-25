part of 'typecheck.dart';

enum LVarKind {
  /// “设”出来的变量。
  local,

  /// 生成器 / 降级用的临时值。
  temp,

  /// 参数（函数的、匿名函数的）。
  param,

  /// 循环变量。
  loop,

  /// “看是哪种情况”接出来的。
  matchBind,

  /// “出错了”接到的错误。
  error,

  /// 模块顶上的变量。
  global,

  /// 宿主给的。
  host,
}

class LVarInfo {
  const LVarInfo(this.scope, this.name, this.type, this.kind);

  /// 在哪一层：“主”、函数的记号、脚本的名字，或匿名函数的记号（[LTypeResult.lambdaScope]）。
  final String scope;
  final String name;
  final LType type;
  final LVarKind kind;
}

class LTypedSig {
  const LTypedSig(this.key, this.info, this.params, this.returns);
  final String key;
  final LTypedFunc info;
  final List<LType> params;
  final LType returns;

  LType get type => LType(LKind.fn, args: [...params, returns]);
}

/// 检查的结果。所有类型都是收尾以后的：不含“待定”“永不”（没定下来的按“任意”）。
class LTypeResult {
  LTypeResult._(this.world, this.issues, this._types, this._wants, this._ops, this._typeArgs, this.checks, this.funcs, this.vars, this._lambdaKeys, this._lines, this.passes, this.shared);

  /// 声明表（记录、枚举、变体、接口、类、函数、别名），生成器要查字段顺序、情况列表时用。
  final LTypeWorld world;

  /// 问题，按发现的顺序（T12 在最后）。
  final List<LTypeIssue> issues;
  final Map<LExpr, LType> _types;
  final Map<LExpr, LType> _wants;
  final Map<LNode, String> _ops;
  final Map<LNode, Map<String, LType>> _typeArgs;

  /// 要在运行时检查的地方（设计第 8 节的 9 种）。
  final List<LRuntimeCheck> checks;

  /// 每个函数 / 方法 /“创建时”的签名（记号 → 签名），按声明的顺序。
  final Map<String, LTypedSig> funcs;

  /// 所有变量（含参数、循环变量、匿名函数里的）。
  final List<LVarInfo> vars;
  final Map<LLambda, String> _lambdaKeys;
  final List<String> _lines;

  /// 反复算了几遍才不变。
  final int passes;

  /// 在树里出现了不止一次的同一个节点对象（多半是 `const` 写的）。结果是按节点对象记的，这样的节点 [typeOf]、[coercionOf]、[opOf]
  /// 只能记住一处——生成器用结果之前要保证它是空的（不会出错的那几种不算：空、是 / 否、文字的字面量）。
  final List<LNode> shared;

  bool get hasErrors => issues.any((i) => i.isError);
  List<LTypeIssue> get errors => [
    for (final i in issues)
      if (i.isError) i,
  ];

  /// 这个式子的类型；没检查到的（比如它所在的地方前面已经报错跳过了）＝null。
  LType? typeOf(LExpr e) => _types[e];

  /// 这个式子要放进什么类型的地方（参数、带类型的变量、条件…）；没有要求＝null。
  LType? wantOf(LExpr e) => _wants[e];

  /// 这个式子放进它要去的地方时要做的转换（整数 → 小数、任意 → 确定类型要查…）；不用做＝null。
  LCoercion? coercionOf(LExpr e) {
    final from = _types[e], to = _wants[e];
    return from == null || to == null ? null : LCoercion.between(from, to);
  }

  /// 这个运算 / 取项 / 改项该用哪个小函数：`iadd fadd dadd`（整数 / 小数 / 任意）`isub imul fdiv idiv imod fpow ineg`、
  /// `ilt flt tlt dlt`（比大小：整数 / 小数 / 文字 / 任意）`eq ne`、`listAt dictGet dynGet listSetAt dictSet dynSet listPush dynPush`。
  String? opOf(LNode node) => _ops[node];

  /// 泛型调用（[LCall]、[LRt]、[LSend]、[LNew]…）这一次把类型变量定成了什么。
  Map<String, LType>? typeArgsOf(LNode call) => _typeArgs[call];

  /// 匿名函数里的变量记在哪一层（配合 [vars] 用）。
  String? lambdaScope(LLambda e) => _lambdaKeys[e];

  LVarInfo? variable(String scope, String name) => vars.where((v) => v.scope == scope && v.name == name).firstOrNull;

  /// 和推断原型一样的打印：每个函数一行签名、每个变量一行类型（不含参数、匿名函数里的、“看是哪种情况”接出来的）。
  List<String> describe() => _lines;
}

extension _Finish on _Checker {
  List<LNode> _sharedNodes() {
    final seen = HashSet<LNode>.identity();
    final out = <LNode>[];
    late final void Function(List<LStmt>) stmts;
    void expr(LExpr e) {
      final harmless = e is LLit && (e.value == null || e.value is bool || e.value is String);
      if (!harmless && !seen.add(e) && !out.any((x) => identical(x, e))) out.add(e);
      if (e is LLambda) stmts(e.expr == null ? e.body : const []);
      if (e is LLambda && e.expr != null) expr(e.expr!);
      lExprChildren(e).forEach(expr);
    }

    stmts = (List<LStmt> list) {
      lWalk(list, (s) {
        if (!seen.add(s) && !out.any((x) => identical(x, s))) out.add(s);
        lStmtExprs(s).forEach(expr);
      });
    };
    for (final g in globals) {
      expr(g.init);
    }
    for (final c in w.classes.values) {
      for (final f in c.decl.fields) {
        if (f.init != null) expr(f.init!);
      }
      if (c.ctor != null) stmts(c.ctor!.body);
      for (final m in c.methods.values) {
        stmts(m.body);
      }
    }
    for (final f in w.funcs.values) {
      stmts(f.body);
    }
    stmts(main);
    for (final s in scripts) {
      stmts(s.body);
    }
    return out;
  }

  static String _bound(String b) => switch (b) {
    kBoundComparable => '能比较',
    kBoundKey => '能当键',
    _ => b,
  };

  LTypeResult finish() {
    final lines = <String>[];
    final sigs = <String, LTypedSig>{};
    for (final c in w.classes.values) {
      final f = c.ctor;
      if (f != null) sigs[f.key] = LTypedSig(f.key, f, [for (var i = 0; i < f.params.length; i++) w.close(ptype(f, i))], _nul);
    }
    for (final key in sigOrder) {
      final dot = key.indexOf('.');
      final f = dot < 0 ? w.funcs[key]! : w.classes[key.substring(0, dot)]!.methods[key.substring(dot + 1)]!;
      final ps = [for (var i = 0; i < f.params.length; i++) w.close(ptype(f, i))];
      final r = w.close(rtype(f));
      sigs[key] = LTypedSig(key, f, ps, r);
      final g = f.own.isEmpty ? '' : '〈${f.own.map((v) => f.bounds.containsKey(v) ? '$v: ${_bound(f.bounds[v]!)}' : v).join(', ')}〉';
      lines.add('$key: $g(${ps.map((p) => p.show()).join(', ')}) → ${r.show()}');
    }
    final shown = <String>{};
    for (final (scope, name) in order) {
      final v = vt[vkey(scope, name)]!;
      if (v.hidden || scope.endsWith('.创建') || scope.endsWith('.字段')) continue;
      final t = w.res(v.t);
      if (w.hasHole(t)) {
        issues.add(LTypeIssue('T12', scope, '「$name」里放什么还看不出来，先当成“任意”', level: LTypeLevel.hint));
      }
      shown.add(vkey(scope, name));
      lines.add('$scope.$name: ${w.close(t).show()}');
    }
    final vars = <LVarInfo>[
      for (final MapEntry(:key, :value) in vt.entries) LVarInfo(key.substring(0, key.indexOf('\u0001')), key.substring(key.indexOf('\u0001') + 1), w.close(value.t), value.kind),
    ];
    // 放进变量的、没标返回类型的函数里返回的：它们要去的地方的类型现在才定下来。
    for (final (e, key) in _assigned) {
      wants[e] = vt[key]!.t;
    }
    for (final (e, f) in _returned) {
      wants[e] = rtype(f);
    }
    final closedTypes = HashMap<LExpr, LType>.identity()..addAll({for (final MapEntry(:key, :value) in types.entries) key: w.close(value)});
    final closedWants = HashMap<LExpr, LType>.identity()..addAll({for (final MapEntry(:key, :value) in wants.entries) key: w.close(value)});
    final closedArgs = HashMap<LNode, Map<String, LType>>.identity()
      ..addAll({
        for (final MapEntry(:key, :value) in typeArgs.entries) key: {for (final MapEntry(key: v, value: t) in value.entries) v: w.close(t)},
      });
    // 边界上的检查（第 1、2 种）：任意放进要确定类型的地方。
    final seen = {for (final c in checks) identityHashCode(c.node)};
    for (final MapEntry(key: e, value: to) in closedWants.entries) {
      final from = closedTypes[e];
      if (from == null || seen.contains(identityHashCode(e)) && e is LCast) continue;
      final c = LCoercion.between(from, to);
      if (c == null) continue;
      if (c.kind == LCoercionKind.check) checks.add(LRuntimeCheck(LCheckKind.anyToType, e, type: to));
      if (c.kind == LCoercionKind.checkEach) checks.add(LRuntimeCheck(LCheckKind.anyToContainer, e, type: to));
    }
    final outChecks = [for (final c in checks) LRuntimeCheck(c.kind, c.node, type: c.type == null ? null : w.close(c.type!), where: c.where)];
    return LTypeResult._(w, issues, closedTypes, closedWants, ops, closedArgs, outChecks, sigs, vars, lambdaKeys, lines, passes, _sharedNodes());
  }
}
