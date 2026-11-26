part of 'typecheck.dart';

/// 声明：收集、一遍一遍地过、类上的几条规则（T11、T13、T17、T18）。
mixin _Decls on _Core {
  LTypedFunc _info(LFuncDecl d, String key, List<LTypeParam> classTv, {String? owner}) {
    final all = [...classTv, ...d.typeParams];
    sigOrder.add(key);
    return LTypedFunc(
      key: key,
      name: d.name,
      typeVars: [for (final p in all) p.name],
      own: [for (final p in d.typeParams) p.name],
      bounds: {
        for (final p in all)
          if (p.bound != null) p.name: p.bound!,
      },
      params: d.params,
      ret: d.type,
      body: d.body,
      decl: d,
      owner: owner,
    );
  }

  void collect() {
    for (final d in [...prelude, ...decls]) {
      if (langIsBuiltinError(d.name) && !prelude.contains(d)) {
        clashes.add(d);
        continue;
      }
      switch (d) {
        case LRecordDecl():
          w.records[d.name] = d;
        case LEnumDecl():
          w.enums[d.name] = d;
        case LVariantDecl():
          w.variants[d.name] = d;
        case LAliasDecl():
          w.aliases[d.name] = d;
        case LInterfaceDecl():
          w.interfaces[d.name] = d;
        case LNativeDecl():
          natives[d.name] = d;
        case LVarDecl():
          globals.add(d);
        case LFuncDecl():
          w.funcs[d.name] = _info(d, d.name, const []);
        case LClassDecl():
          final c = LClassInfo(d);
          for (final m in d.ownMethods) {
            c.methods[m.fn.name] = _info(m.fn, '${d.name}.${m.fn.name}', d.typeParams, owner: d.name);
          }
          // 类本身的成员：字段当模块级的变量，方法当模块级的函数（名字是“类名.成员名”）。
          for (final s in lStaticDecls(d)) {
            if (s is LVarDecl) globals.add(s);
            if (s is LFuncDecl) w.funcs[s.name] = _info(s, s.name, const [], owner: d.name);
          }
          final ctor = d.ctor;
          if (ctor != null) {
            c.ctor = LTypedFunc(
              key: '${d.name}.创建',
              name: '创建',
              typeVars: c.typeVars,
              own: const [],
              bounds: {
                for (final p in d.typeParams)
                  if (p.bound != null) p.name: p.bound!,
              },
              params: ctor.params,
              ret: null,
              body: ctor.body,
              decl: ctor,
              owner: d.name,
            );
          }
          w.classes[d.name] = c;
      }
    }
  }

  @override
  void runFn(LTypedFunc f, {LType? thisType, _Scope? parent}) {
    final sc = _Scope(f.key, f.key, parent: parent, tv: f.typeVars, thisType: thisType);
    sc.f = f;
    sc.bounds = f.bounds;
    sc.reassigned = _targets(f.body);
    paramDefaults(f, sc);
    for (var i = 0; i < f.params.length; i++) {
      final p = f.params[i];
      sc.names.add(p.name);
      vt[vkey(f.key, p.name)] = _Var(p.rest ? LType(LKind.list, of: ptype(f, i)) : ptype(f, i), fixed: true, hidden: true, kind: LVarKind.param, slot: p.rest ? null : '${f.key}#$i');
    }
    block(sc, f.body);
    if (f.ret != null) return;
    var r = sc.rets.isEmpty ? _nul : _never;
    for (final x in sc.rets) {
      r = w.join(r, x);
    }
    if (sc.rets.isNotEmpty && !_Stmts._exits(f.body, jumps: false) && !_Stmts._allReturn(f.body)) r = w.join(r, _nul);
    final old = rt[f.key] ?? _never;
    final now = w.join(old, r);
    if (now != old) {
      rt[f.key] = now;
      w.changed = true;
    }
  }

  /// 这段程序里所有被“改”过的变量名（连匿名函数里的）。
  Set<String> _targets(List<LStmt> body) {
    final out = <String>{};
    late final void Function(List<LStmt>) stmts;
    void expr(LExpr e) {
      if (e is LLambda) stmts(e.stmts);
      lExprChildren(e).forEach(expr);
    }

    stmts = (List<LStmt> list) {
      lWalk(list, (s) {
        if (s case LAssign(target: LTName(:final name))) out.add(name);
        if (s case LForEach(:final item, reuse: true)) out.add(item);
        lStmtExprs(s).forEach(expr);
      });
    };

    stmts(body);
    return out;
  }

  void onePass() {
    final top = _Scope(_mainKey, _mainKey);
    top.reassigned = _targets(main);
    for (final MapEntry(key: name, value: t) in outer.entries) {
      top.names.add(name);
      vt[vkey(_mainKey, name)] = _Var(w.resolve(t), fixed: true, hidden: true, kind: LVarKind.host);
    }
    for (final g in globals) {
      final keep = curSrc;
      curSrc = g.src;
      if (g.type != null) {
        final wt = w.resolve(g.type);
        final t = ex(top, g.init, wt);
        want(g.init, wt);
        declare(top, g.name, t, declared: wt, node: g.init, kind: LVarKind.global);
      } else {
        declare(top, g.name, ex(top, g.init), node: g.init, kind: LVarKind.global);
      }
      if (finalPass) _assigned.add((g.init, vkey(_mainKey, g.name)));
      curSrc = keep;
    }
    for (final d in clashes) {
      curSrc = d.src;
      err('T20', top, '「${d.name}」是内置的错误种类，自己的东西换一个名字', node: d, where: d.name);
    }
    for (final c in w.classes.values) {
      curSrc = c.decl.src;
      _class(c, top);
    }
    for (final f in w.funcs.values) {
      curSrc = f.decl?.src;
      runFn(f, parent: top);
      _exported(f, top);
    }
    curSrc = null;
    block(top, main);
    for (final s in scripts) {
      final sc = _Scope(s.name, s.name, parent: top);
      sc.reassigned = _targets(s.body);
      for (final MapEntry(key: name, value: t) in s.vars.entries) {
        sc.names.add(name);
        vt[vkey(s.name, name)] = _Var(w.resolve(t), fixed: true, hidden: true, kind: LVarKind.host);
      }
      block(sc, s.body);
    }
  }

  void _class(LClassInfo c, _Scope top) {
    final d = c.decl;
    final tv = c.typeVars;
    final self = LType(
      LKind.object,
      name: c.name,
      args: [for (final v in tv) LType(LKind.typeVar, name: v)],
    );
    final at = _Scope('${c.name}.字段', c.name, parent: top, tv: tv, thisType: self);
    for (final f in d.ownFields) {
      final init = f.init;
      if (init != null) arg(at, init, w.resolve(f.type, tv), '「${f.name}」的初始值');
    }
    final ctor = c.ctor;
    if (ctor != null) runFn(ctor, thisType: self, parent: top);
    for (final m in c.methods.values) {
      curSrc = m.decl?.src ?? d.src;
      runFn(m, thisType: self, parent: top);
    }
    curSrc = d.src;
    if (classRules(c, at)) return;
    for (final i in d.interfaces) {
      implementsRules(c, i, at);
    }
    final parent = w.classes[d.parent];
    if (d.parent != null && parent == null) {
      err(w.interfaces.containsKey(d.parent) ? 'T23' : 'T08', at, w.interfaces.containsKey(d.parent) ? '「${d.parent}」是接口，不能当父类：写在“实现了”里' : '没有叫「${d.parent}」的类', node: d);
    }
    if (parent == null) return;
    if (!parent.decl.isOpen) err('T17', at, '「${c.name}」继承了「${parent.name}」，但「${parent.name}」没有勾“可以被继承”', node: d);
    overrideRules(c, parent, at);
  }

  /// T13：给别人用的函数没标全。
  void _exported(LTypedFunc f, _Scope top) {
    final d = f.decl;
    if (d == null || !d.isPublic) return;
    final miss = [
      for (final p in d.params)
        if (p.type == null) '参数「${p.name}」',
      if (d.type == null) '返回值',
    ];
    if (miss.isNotEmpty) err('T13', top, '「${d.name}」是给别人用的，${miss.join('、')}还没有标类型', node: d, where: d.name);
  }
}
