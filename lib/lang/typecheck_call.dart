part of 'typecheck.dart';

/// 匿名函数、调用、发消息、新建对象。
mixin _Calls on _Core {
  @override
  LType lam(_Scope sc, LLambda e, LType? wantT0) {
    final wantT = wantT0 == null ? null : w.res(wantT0);
    final shaped = wantT != null && WL.isFn(wantT) && wantT.hasShape;
    final key = 'λ#${id(e)}';
    if (finalPass) lambdaKeys[e] = key;
    final ls = _Scope(key, sc.fn, parent: sc, lam: true);
    // 外面“判断过不是空”的变量带进匿名函数：只带那些在整个函数里从没被“改”过的（被改过的，等匿名函数真跑的时候可能又是空了）。
    ls.nn = {
      for (final n in sc.nn)
        if (!sc.reassigned.contains(n)) n,
    };
    final pts = <LType>[];
    for (var i = 0; i < e.params.length; i++) {
      final p = e.params[i];
      final LType t;
      if (p.type != null) {
        t = w.resolve(p.type, sc.tv);
      } else if (shaped && i < wantT.params.length) {
        t = wantT.params[i]; // 没标的参数：看上下文
      } else {
        t = _any; // 没有上下文：任意
      }
      pts.add(t);
      ls.names.add(p.name);
      vt[vkey(key, p.name)] = _Var(t, fixed: true, hidden: true, kind: LVarKind.param);
    }
    if (shaped && wantT.params.length != e.params.length) {
      err('T07', sc, '这里要一个收 ${wantT.params.length} 个参数的函数，给的收 ${e.params.length} 个', node: e);
    }
    LType ret;
    final short = e.expr;
    if (short != null) {
      ret = ex(ls, short, shaped ? wantT.returns : null);
    } else {
      block(ls, e.body);
      ret = _nul;
      for (final r in ls.rets) {
        ret = ret.isNul ? r : w.join(ret, r);
      }
    }
    return LType(LKind.fn, args: [...pts, ret]);
  }

  static bool _sameMap(Map<String, LType> a, Map<String, LType> b) {
    if (a.length != b.length) return false;
    for (final k in a.keys) {
      if (a[k] != b[k]) return false;
    }
    return true;
  }

  @override
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
    int? least,
  }) {
    least ??= f?.minArgs ?? pts.length;
    final rest = f?.hasRest ?? false;
    if (args.length < least || (!rest && args.length > pts.length)) {
      err('T07', sc, '「$name」要 ${pts.length} 个参数，给了 ${args.length} 个', node: node);
      return _never;
    }
    final n = args.length < pts.length ? args.length : pts.length;
    for (var i = n; i < args.length; i++) {
      ex(sc, args[i]); // “剩下的全收”收走的
    }
    final b = <String, LType>{for (final v in tvs) v: _never, ...?pre};
    final got = List<LType>.filled(n, _never);
    // 第一步：先看不是匿名函数的参数。
    for (var i = 0; i < n; i++) {
      if (args[i] is LLambda) continue;
      final s = w.subst(pts[i], b);
      got[i] = w.res(ex(sc, args[i], w.hasOpen(s) ? null : s));
      w.unify(pts[i], got[i], b);
    }
    // 第二步：带着已经定下来的类型去看匿名函数。看完以后类型变量要是变宽了（整数 → 小数），带着变宽后的类型再看一遍。
    for (var again = 0; again < 2; again++) {
      final before = {...b};
      for (var i = 0; i < n; i++) {
        if (args[i] is! LLambda) continue;
        got[i] = w.res(ex(sc, args[i], w.subst(pts[i], b)));
        w.unify(pts[i], got[i], b);
      }
      if (_sameMap(b, before)) break;
    }
    for (var i = 0; i < n; i++) {
      final wantT = w.res(w.subst(pts[i], b));
      if (f != null && f.params[i].type == null) {
        // 没标类型的参数：把这次调用的实参类型记下来。
        final k = '${f.key}#$i';
        final old = pt[k] ?? _never;
        final now = w.join(old, got[i]);
        if (now != old) {
          pt[k] = now;
          w.changed = true;
        }
        want(args[i], ptype(f, i));
        continue;
      }
      want(args[i], wantT);
      if (w.ok(got[i], wantT)) continue;
      if (WL.isFn(got[i]) && WL.isFn(wantT) && got[i].args.length != wantT.args.length) continue; // 参数个数不对已经报过 T07（一处错只说一句）
      final slot = i < slots.length ? slots[i] : '';
      mismatch(sc, args[i], got[i], wantT, '${slot.isEmpty ? '「$name」的第 ${i + 1} 个参数' : slot}要${wantT.show()}', argIndex: i);
    }
    for (final MapEntry(key: v, value: c) in bounds.entries) {
      final t = w.res(b[v] ?? _never);
      if (t.isNever || t.isAny || WL.isVar(t) || WL.isHole(t)) continue;
      if (c == kBoundComparable) {
        if (t != _int && t != _flt && t != _txt) err('T05', sc, '「$name」要的是能比大小的东西（数字或文字），${t.show()}不能比大小', node: node);
      } else if (c == kBoundKey) {
        if (t != _txt) err('T05', sc, '「$name」要的是能当字典的键的东西（文字），${t.show()}不行', node: node);
      } else if (!(t.isNamed && !t.nullable && (t.name == c || w.supers(t.name).contains(c)))) {
        err('T05', sc, '「$name」要的是实现了「$c」的东西，${t.show()}没有', node: node);
      }
    }
    if (finalPass && node != null && tvs.isNotEmpty) typeArgs[node] = {for (final v in tvs) v: b[v] ?? _never};
    return w.res(w.subst(ret, b));
  }

  @override
  LType call(_Scope sc, LCall e) {
    final callee = e.callee;
    if (callee is LName && callee.kind == LNameKind.variable && find(sc, callee.name) == null) {
      final f = w.funcs[callee.name];
      if (f != null) {
        if (finalPass) types[callee] = fnType(f);
        return apply(sc, f.name, [for (var i = 0; i < f.params.length; i++) ptype(f, i)], rtype(f), f.typeVars, f.bounds, e.args, f: f, node: e);
      }
    }
    final t = w.res(ex(sc, callee));
    if (WL.isFn(t) && t.hasShape) return apply(sc, callee is LName ? callee.name : '这个函数', t.params, t.returns, const [], const {}, e.args, node: e);
    for (final x in e.args) {
      ex(sc, x);
    }
    if (WL.isFn(t)) return _any;
    if (!t.isAny && !t.isNever) err('T01', sc, '${callee is LName ? '「${callee.name}」' : '这个值'}是${t.show()}，不是函数，不能调用', node: e);
    return t;
  }

  /// 类 [c] 上叫 [name] 的方法（参数、返回已经把类的类型变量换成 [targs]）。
  (List<LType>, LType, LTypedFunc)? _method(LClassInfo? c, String name, List<LType> targs) {
    final got = w.classMethod(c, name);
    if (got == null) return null;
    final (f, owner) = got;
    final tv = owner.typeVars;
    final b = {for (var i = 0; i < tv.length && i < targs.length; i++) tv[i]: targs[i]};
    return ([for (var i = 0; i < f.params.length; i++) w.subst(ptype(f, i), b)], w.subst(rtype(f), b), f);
  }

  @override
  LType send(_Scope sc, LSend e) {
    final cls = classRef(sc, e.obj);
    if (cls != null) return staticSend(sc, cls, e);
    final t = nonnull(sc, e.obj, (_) => '对象');
    if (w.isClass(t)) {
      final m = _method(w.classes[t.name], e.method, t.args);
      if (m != null) return apply(sc, e.method, m.$1, m.$2, const [], const {}, e.args, f: m.$3, node: e);
    } else if (w.isInterface(t)) {
      final m = w.interfaces[t.name]?.methods.where((m) => m.name == e.method).firstOrNull;
      if (m != null) {
        return apply(sc, e.method, [for (final p in m.params) w.resolve(p.type)], w.resolve(m.returns ?? LType.nul), const [], const {}, e.args, node: e, least: lMinArgs(m.params));
      }
    } else if (t.isAny || t.isNever) {
      for (final x in e.args) {
        ex(sc, x);
      }
      return t;
    }
    for (final x in e.args) {
      ex(sc, x);
    }
    if (w.isClass(t) && staticMethod(w.classes[t.name], e.method) != null) {
      err('T25', sc, '「${e.method}」是「${t.name}」这个类本身的方法，不是每个对象自己的：要写成“${t.name} 的 ${e.method}”', node: e);
    } else {
      err('T08', sc, '${t.show()}没有「${e.method}」这个方法', node: e);
    }
    return _never;
  }

  @override
  LType superSend(_Scope sc, LSuperSend e) {
    final self = sc.thisType;
    final parent = self == null ? null : w.classes[w.classes[self.name]?.decl.parent];
    if (parent == null) {
      for (final x in e.args) {
        ex(sc, x);
      }
      err('T08', sc, '这里没有父类', node: e);
      return _never;
    }
    if (e.isCtor) {
      final ctor = w.classCtor(parent);
      if (ctor == null) {
        for (final x in e.args) {
          ex(sc, x);
        }
        if (e.args.isNotEmpty) err('T07', sc, '「新建${parent.name}」要 0 个参数，给了 ${e.args.length} 个', node: e);
        return _nul;
      }
      apply(sc, '新建${parent.name}', [for (var i = 0; i < ctor.params.length; i++) ptype(ctor, i)], _nul, const [], const {}, e.args, f: ctor, node: e);
      return _nul;
    }
    final m = _method(parent, e.method, const []);
    if (m == null) {
      for (final x in e.args) {
        ex(sc, x);
      }
      err('T08', sc, '${parent.name}没有「${e.method}」这个方法', node: e);
      return _never;
    }
    return apply(sc, e.method, m.$1, m.$2, const [], const {}, e.args, f: m.$3, node: e);
  }

  @override
  LType newObject(_Scope sc, LNew e) {
    final c = w.classes[e.cls];
    if (c == null) {
      for (final x in e.args) {
        ex(sc, x);
      }
      if (w.interfaces.containsKey(e.cls)) {
        err('T23', sc, '「${e.cls}」是接口，不能新建：要新建一个实现了它的类', node: e);
      } else {
        err('T08', sc, '没有叫「${e.cls}」的类', node: e);
      }
      return _never;
    }
    final tv = c.typeVars;
    final targs = e.typeArgs.isNotEmpty ? [for (final a in e.typeArgs) w.resolve(a, sc.tv)] : [for (final v in tv) LType(LKind.hole, name: holeKey(e, sc, ':$v'))]; // 没写〈…〉：先留着，看后面怎么用
    final b = {for (var i = 0; i < tv.length && i < targs.length; i++) tv[i]: targs[i]};
    final ctor = w.classCtor(c);
    if (ctor == null) {
      for (final x in e.args) {
        ex(sc, x);
      }
      if (e.args.isNotEmpty) err('T07', sc, '「新建${e.cls}」要 0 个参数，给了 ${e.args.length} 个', node: e);
    } else {
      apply(sc, '新建${e.cls}', [for (var i = 0; i < ctor.params.length; i++) w.subst(ptype(ctor, i), b)], _nul, const [], const {}, e.args, f: ctor, node: e);
    }
    return w.res(LType(LKind.object, name: e.cls, args: targs));
  }
}
