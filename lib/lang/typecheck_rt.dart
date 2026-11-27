part of 'typecheck.dart';

/// 小库函数的类型；列表 / 字典上“看被操作的是什么再定”的那几样。
mixin _Rt on _Core {
  void _each(_Scope sc, List<LExpr> args) {
    for (final x in args) {
      ex(sc, x);
    }
  }

  @override
  LType runtimeCall(_Scope sc, LRt e, LType? wantT) {
    final a = e.args;
    switch (e.fn) {
      case 'join' || 'toText':
        _each(sc, a); // “连起来”收任何类型（设计 5.2 第 4 条）
        return _txt;
      case 'size':
        _each(sc, a);
        return _int;
      case 'log':
        _each(sc, a);
        return _nul;
      case 'isNull':
        _each(sc, a);
        return _bool;
      case 'orElse' when a.length == 2:
        final t = w.res(ex(sc, a[0]));
        final d = ex(sc, a[1]);
        if (t.isNever) return _never;
        if (!w.ok(d, t.nonNull) && !w.ok(t.nonNull, d)) err('T01', sc, '“如果是空就用”后面要${t.nonNull.show()}，放进来的是${show(d)}', node: a[1]);
        return w.join(t.nonNull, d);
      case 'must' when a.length == 1:
        final t = w.res(ex(sc, a[0]));
        if (t.nullable || t.isAny) check(LCheckKind.must, e, sc);
        return t.nonNull;
      case 'listPush' when a.length == 2:
        push(sc, a[0], a[1], e);
        return _nul;
      case 'listPop' when a.length == 1:
        final t = w.res(ex(sc, a[0]));
        _snapshotWarn(sc, a[0], e);
        return WL.isList(t) ? WL.elem(t).orNull : (t.isNever ? _never : _any);
      case 'listGet' || 'dictGet' || 'item' when a.length == 2:
        return index(sc, a[0], a[1], e);
      case 'listSet' || 'dictSet' || 'setItem' when a.length == 3:
        store(sc, a[0], a[1], a[2], e);
        return _nul;
      case 'dictRemove':
        _each(sc, a);
        if (a.isNotEmpty) _snapshotWarn(sc, a[0], e);
        return _nul;
    }
    final sig = kLangRtV2[e.fn];
    if (sig == null) {
      _each(sc, a); // 表里还没写类型的小库函数：参数随便，结果按任意。
      return _any;
    }
    if (const {'toInt', 'floor', 'ceil', 'round'}.contains(e.fn)) check(LCheckKind.floatToInt, e, sc);
    if (kLangRtV2Waits.contains(e.fn)) waited(sc, e, '用了“${sig.label}”');
    return apply(sc, sig.label, sig.params, sig.ret, sig.typeVars, sig.bounds, a, node: e, slots: sig.slots);
  }

  static String _container(LType t) => t.kind == LKind.dict ? '字典' : '列表';

  /// 取一项：列表按位置（越界在运行时报错）、字典按键（没有就是空）。
  @override
  LType index(_Scope sc, LExpr of, LExpr key, LNode node) {
    final t = nonnull(sc, of, _container);
    if (WL.isList(t)) {
      arg(sc, key, _int, '位置');
      check(LCheckKind.listIndex, node, sc);
      op(node, 'listAt');
      return WL.elem(t);
    }
    if (WL.isDict(t)) {
      arg(sc, key, _txt, '字典的键');
      op(node, 'dictGet');
      return WL.elem(t).orNull;
    }
    ex(sc, key);
    if (t.isAny) {
      op(node, 'dynGet');
      return _any;
    }
    if (!t.isNever && !WL.isHole(t)) err('T01', sc, '这里要列表或者字典，放进来的是${t.show()}', node: of);
    return _never;
  }

  /// 改一项 / 存一项。
  @override
  void store(_Scope sc, LExpr of, LExpr key, LExpr value, LNode node) {
    final t = nonnull(sc, of, _container);
    if (WL.isList(t)) {
      arg(sc, key, _int, '位置');
      arg(sc, value, WL.elem(t), '往列表里放的东西');
      check(LCheckKind.listIndex, node, sc);
      op(node, 'listSetAt');
    } else if (WL.isDict(t)) {
      arg(sc, key, _txt, '字典的键');
      arg(sc, value, WL.elem(t), '往字典里存的东西');
      op(node, 'dictSet');
    } else {
      ex(sc, key);
      ex(sc, value);
      if (t.isAny) {
        op(node, 'dynSet');
        _snapshotWarn(sc, of, node);
      } else if (!t.isNever && !WL.isHole(t)) {
        err('T01', sc, '这里要列表或者字典，放进来的是${t.show()}', node: of);
      }
    }
  }

  /// 往列表里加一项。
  @override
  void push(_Scope sc, LExpr of, LExpr value, LNode node) {
    final t = nonnull(sc, of, (_) => '列表');
    if (WL.isList(t)) {
      arg(sc, value, WL.elem(t), '往列表里加的东西');
      op(node, 'listPush');
      return;
    }
    ex(sc, value);
    if (t.isAny) {
      op(node, 'dynPush');
      _snapshotWarn(sc, of, node);
    } else if (!t.isNever && !WL.isHole(t)) {
      err('T01', sc, '这里要列表，放进来的是${t.show()}', node: of);
    }
  }

  /// T14：[of] 是一个标成“任意”的变量，里面放的其实是带类型的列表 / 字典的快照——往里加东西改不到原来那份。
  void _snapshotWarn(_Scope sc, LExpr of, LNode node) {
    if (of is! LName) return;
    final k = find(sc, of.name);
    if (k == null || !vt[k]!.holdsSnapshot) return;
    err('T14', sc, '「${of.name}」是“任意”，里面是原来那个列表（或字典）的一份快照，往里加东西改不到原来那份', node: node);
  }
}
