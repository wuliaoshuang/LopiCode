part of 'typecheck.dart';

/// 类与接口（核心 2·第 2 段）：类本身的成员、内部的字段、参数默认值、“创建时”的规矩、继承绕圈、成员重名，
/// 以及“重写 / 实现的方法样子要一模一样”。规则 T22–T28（表在 type_issue.dart）。
mixin _Classes on _Core {
  /// [of] 写的是不是一个类的名字（没有被同名的变量、函数挡住）：是＝在说“这个类本身”。
  @override
  LClassInfo? classRef(_Scope sc, LExpr of) => of is LName && of.kind == LNameKind.variable && find(sc, of.name) == null && !w.funcs.containsKey(of.name) ? w.classes[of.name] : null;

  /// 现在这段代码写在哪个类里（方法、创建时、字段初值、类本身的方法，连它们里面的匿名函数）；不在类里＝null。
  String? _ownerOf(_Scope sc) {
    for (_Scope? s = sc; s != null; s = s.parent) {
      final o = s.f?.owner;
      if (o != null) return o;
    }
    return sc.thisType?.name;
  }

  @override
  void privateCheck(_Scope sc, LClassInfo owner, String name, LNode node) {
    final me = _ownerOf(sc);
    if (me != null && w.supers(me).contains(owner.name)) return;
    err('T22', sc, '「${owner.name}」的「$name」是内部的，只有「${owner.name}」自己和它的子类里面能用', node: node);
  }

  (LFieldDecl, LClassInfo)? _staticField(LClassInfo? c, String name) {
    var guard = 0;
    while (c != null && guard++ < 64) {
      for (final f in c.decl.fields) {
        if (f.isStatic && f.name == name) return (f, c);
      }
      c = w.classes[c.decl.parent];
    }
    return null;
  }

  @override
  LTypedFunc? staticMethod(LClassInfo? c, String name) {
    var guard = 0;
    while (c != null && guard++ < 64) {
      final f = w.funcs[lStaticName(c.name, name)];
      if (f != null && f.owner == c.name) return f;
      c = w.classes[c.decl.parent];
    }
    return null;
  }

  @override
  LType staticField(_Scope sc, LClassInfo c, String name, LNode node) {
    final got = _staticField(c, name);
    if (got == null) {
      if (w.classField(c, name) != null) {
        err('T25', sc, '「$name」是每个对象自己的字段，不是「${c.name}」这个类本身的：要先有一个对象', node: node);
      } else {
        err('T08', sc, '「${c.name}」这个类本身没有「$name」这一项', node: node);
      }
      return _never;
    }
    final (f, owner) = got;
    if (f.isPrivate) privateCheck(sc, owner, name, node);
    final key = lStaticName(owner.name, name);
    op(node, 'static:$key');
    return w.res(f.type != null ? w.resolve(f.type) : (vt[vkey(_mainKey, key)]?.t ?? _never));
  }

  @override
  LType staticSend(_Scope sc, LClassInfo c, LSend e) {
    final f = staticMethod(c, e.method);
    if (f == null) {
      for (final x in e.args) {
        ex(sc, x);
      }
      if (w.classMethod(c, e.method) != null) {
        err('T25', sc, '「${e.method}」是每个对象自己的方法，不是「${c.name}」这个类本身的：要先新建一个对象，再让它做', node: e);
      } else {
        err('T08', sc, '「${c.name}」这个类本身没有「${e.method}」这个方法', node: e);
      }
      return _never;
    }
    op(e, 'static:${f.key}');
    if (fnWaits(f.key)) waited(sc, e, '调了要等的「${c.name} 的 ${e.method}」');
    return apply(sc, f.name, [for (var i = 0; i < f.params.length; i++) ptype(f, i)], rtype(f), f.typeVars, f.bounds, e.args, f: f, node: e);
  }

  static LType _litType(Object? v) => switch (v) {
    null => _nul,
    bool() => _bool,
    int() => _int,
    double() => _flt,
    _ => _txt,
  };

  /// 参数的默认值（T26）：有默认值的排在后面；标了类型的，默认值要放得进去；没标的，默认值也算一次“给过的值”。
  @override
  void paramDefaults(LTypedFunc f, _Scope sc) {
    var seen = false;
    for (var i = 0; i < f.params.length; i++) {
      final p = f.params[i];
      final d = p.defaultValue;
      if (d == null) {
        if (seen && !p.rest) err('T26', sc, '参数「${p.name}」没有默认值，要排在有默认值的参数前面', node: f.decl, where: f.key);
        continue;
      }
      seen = true;
      final dt = _litType(d.value);
      if (p.type != null) {
        final wt = w.resolve(p.type, f.typeVars);
        if (!w.ok(dt, wt)) err('T26', sc, '参数「${p.name}」是${wt.show()}，默认值却是${dt.show()}', node: f.decl, where: f.key);
      } else {
        _widen(pt, '${f.key}#$i', dt);
      }
    }
  }

  void _widen(Map<String, LType> table, String key, LType t) {
    final old = table[key] ?? _never;
    final now = w.join(old, t);
    if (now != old) {
      table[key] = now;
      w.changed = true;
    }
  }

  /// 没标类型的参数 / 返回值跟着“上面”的（父类的方法、接口里说的）走：能并到一起就用上面的类型。
  void _follow(LTypedFunc f, List<LType> params, LType ret) {
    for (var i = 0; i < f.params.length && i < params.length; i++) {
      if (f.params[i].type == null && !params[i].isNever) _widen(pt, '${f.key}#$i', params[i]);
    }
    if (f.ret == null && !ret.isNever && w.join(rt[f.key] ?? _never, ret) == ret) _widen(rt, f.key, ret);
  }

  /// [f] 和上面说的样子（[params]、[ret]、[defaults]）对不对得上：参数、返回值的类型要一模一样（Go、Java 里它们是同一个方法），
  /// 默认值也要一样（调用的地方按变量的类型补默认值，不一样的话同一个对象会得到两种结果）。对不上＝原因。
  String? _shapeDiff(LTypedFunc f, List<LType> params, LType ret, List<LLit?> defaults, String up) {
    if (f.params.length != params.length) return '$up的收 ${params.length} 个参数，这里收 ${f.params.length} 个';
    for (var i = 0; i < params.length; i++) {
      final a = w.res(ptype(f, i)), b = w.res(params[i]);
      if (!a.isNever && !b.isNever && a != b) return '第 ${i + 1} 个参数$up的是${b.show()}，这里是${a.show()}';
      final da = f.params[i].defaultValue, db = defaults[i];
      if ((da == null) != (db == null) || (da != null && da.value != db!.value)) return '第 ${i + 1} 个参数的默认值和$up的不一样';
    }
    final a = w.res(rtype(f)), b = w.res(ret);
    if (!a.isNever && !b.isNever && a != b) return '$up的返回${b.show()}，这里返回${a.show()}';
    return null;
  }

  /// 说自己实现了接口 [i] 的类 [c]：方法齐不齐、样子对不对（T11）。
  @override
  void implementsRules(LClassInfo c, String i, _Scope at) {
    final d = c.decl;
    final iface = w.interfaces[i];
    if (iface == null) {
      err(w.classes.containsKey(i) ? 'T23' : 'T08', at, w.classes.containsKey(i) ? '「$i」是类，不是接口，不能写在“实现了”里' : '没有叫「$i」的接口', node: d);
      return;
    }
    for (final m in iface.methods) {
      final got = w.classMethod(c, m.name);
      if (got == null) {
        err('T11', at, '「${c.name}」说自己是「$i」，但是没有「${m.name}」这个方法', node: d);
        continue;
      }
      final f = got.$1;
      final wantRet = w.resolve(m.returns ?? LType.nul);
      final params = [for (final p in m.params) w.resolve(p.type)];
      if (f.params.length != m.params.length) {
        err('T11', at, '「${c.name}」的「${m.name}」要收 ${m.params.length} 个参数，现在收 ${f.params.length} 个', node: f.decl ?? d);
        continue;
      }
      _follow(f, params, wantRet);
      if (!w.ok(rtype(f), wantRet)) {
        err('T11', at, '「${c.name}」的「${m.name}」要返回${wantRet.show()}，现在返回的是${show(rtype(f))}', node: f.decl ?? d);
        continue;
      }
      final why = _shapeDiff(f, params, wantRet, [for (final p in m.params) p.defaultValue], '接口「$i」');
      if (why != null) err('T11', at, '「${c.name}」的「${m.name}」和接口「$i」说的对不上：$why', node: f.decl ?? d);
    }
  }

  /// 子类 [c] 重写父类的方法：样子要一模一样（T18）。
  @override
  void overrideRules(LClassInfo c, LClassInfo parent, _Scope at) {
    for (final m in c.methods.values) {
      final up = w.classMethod(parent, m.name);
      if (up == null) continue;
      final p = up.$1;
      String? why;
      if (p.params.length != m.params.length) {
        why = '父类的收 ${p.params.length} 个参数，这里收 ${m.params.length} 个';
      } else {
        _follow(m, [for (var i = 0; i < p.params.length; i++) ptype(p, i)], rtype(p));
        _follow(p, [for (var i = 0; i < m.params.length; i++) ptype(m, i)], _never);
        why = _shapeDiff(m, [for (var i = 0; i < p.params.length; i++) ptype(p, i)], rtype(p), [for (final x in p.params) x.defaultValue], '父类');
      }
      if (why != null) err('T18', at, '「${c.name}」的「${m.name}」和「${up.$2.name}」的对不上：$why', node: m.decl ?? c.decl);
    }
  }

  /// 类上别的规矩：继承绕圈（T24）、成员重名（T28）、“创建时”和父类“创建时”的关系（T27）。绕圈了＝true（后面的不用查了）。
  @override
  bool classRules(LClassInfo c, _Scope at) {
    final d = c.decl;
    final chain = [c.name];
    for (var p = w.classes[d.parent]; p != null && chain.length < 64; p = w.classes[p.decl.parent]) {
      chain.add(p.name);
      if (p.name == c.name) {
        err('T24', at, '继承绕圈了：${chain.join(' → ')}。一个类不能是自己的上一辈', node: d);
        return true;
      }
    }
    final seen = <String>{};
    for (final n in [for (final f in d.fields) f.name, for (final m in d.methods) m.fn.name]) {
      if (!seen.add(n)) err('T28', at, '「${c.name}」里有两个东西都叫「$n」（字段、方法、类本身的成员不能重名）', node: d);
    }
    final parent = w.classes[d.parent];
    for (final f in d.fields) {
      final up = f.isStatic ? null : w.classField(parent, f.name);
      if (up != null) err('T28', at, '「${c.name}」的字段「${f.name}」和「${up.$2.name}」里的重名了：父类的字段子类直接就能用，不用再写一遍', node: d);
    }
    // “调父类的创建时”只能是“创建时”的第一句。
    final ctor = d.ctor;
    var calls = 0;
    void count(List<LStmt> body) => lWalk(body, (s) {
      void go(LExpr e) {
        if (e is LSuperSend && e.isCtor) calls++;
        if (e is LLambda) {
          count(e.stmts);
        } else {
          lExprChildren(e).forEach(go);
        }
      }

      lStmtExprs(s).forEach(go);
    });
    for (final m in d.methods) {
      count(m.fn.body);
    }
    if (calls > 0) err('T27', at, '“调父类的创建时”只能写在「${c.name}」的“创建时”里', node: d);
    if (ctor == null) return false;
    calls = 0;
    count(ctor.body);
    final first = ctor.body.isNotEmpty && ctor.body.first is LExprStmt && ((ctor.body.first as LExprStmt).expr is LSuperSend) && ((ctor.body.first as LExprStmt).expr as LSuperSend).isCtor;
    if (calls > 1 || (calls == 1 && !first)) {
      err('T27', at, '“调父类的创建时”要放在「${c.name}」的“创建时”的第一句，而且只能调一次', node: ctor);
    } else if (calls == 0 && parent != null) {
      final up = w.classCtor(parent);
      if (up != null && up.params.isNotEmpty) err('T27', at, '「${parent.name}」的“创建时”要参数，「${c.name}」的“创建时”第一句要先“调父类的创建时”', node: ctor);
    }
    return false;
  }
}
