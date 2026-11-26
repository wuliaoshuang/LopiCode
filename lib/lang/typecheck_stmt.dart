part of 'typecheck.dart';

/// 语句。
mixin _Stmts on _Core {
  @override
  void block(_Scope sc, List<LStmt> body) {
    for (final s in body) {
      final keep = curSrc, keepStmt = curStmt;
      curSrc = s.src ?? curSrc;
      curStmt = s;
      _st(sc, s);
      curSrc = keep;
      curStmt = keepStmt;
    }
  }

  static LStmt? _last(List<LStmt> body) {
    for (final s in body.reversed) {
      if (s is! LNote) return s;
    }
    return null;
  }

  /// 这一串的最后一句是“返回 / 抛出”（[jumps]：跳出、跳过也算）。
  static bool _exits(List<LStmt> body, {bool jumps = true}) {
    final s = _last(body);
    return s is LReturn || s is LThrow || (jumps && (s is LBreak || s is LContinue));
  }

  /// 最后一句是“看是哪种情况 / 试着做 / 带否则的如果”，而且每一段都以返回结束：也算一定会返回。
  static bool _allReturn(List<LStmt> body) {
    bool ends(List<LStmt> b) => _exits(b, jumps: false) || _allReturn(b);
    return switch (_last(body)) {
      LMatch(:final arms, :final orElse) => arms.every((a) => ends(a.body)) && (orElse == null || ends(orElse)),
      LTry(:final body, :final handlers, :final onError, :final errorName) =>
        ends(body) && (handlers == null ? errorName == null && onError.isEmpty || ends(onError) : handlers.every((c) => ends(c.body))),
      LIf(:final arms, :final orElse) => orElse.isNotEmpty && ends(orElse) && arms.every((a) => ends(a.body)),
      _ => false,
    };
  }

  void _loop(_Scope sc, List<LStmt> body) {
    final keep = {...sc.nn};
    block(sc, body);
    sc.nn = keep.intersection(sc.nn);
  }

  /// “如果 / 否则如果 / 否则”：从第 [i] 段起。返回“从这一段起是不是每条路都出去了”。
  bool _ifFrom(_Scope sc, LIf s, int i) {
    final arm = s.arms[i];
    cond(sc, arm.cond);
    final keep = {...sc.nn};
    sc.nn = {...keep, ...facts(arm.cond, true)};
    block(sc, arm.body);
    final n1 = {...sc.nn};
    sc.nn = {...keep, ...facts(arm.cond, false)};
    final bool elseExits;
    if (i + 1 < s.arms.length) {
      elseExits = _ifFrom(sc, s, i + 1);
    } else {
      block(sc, s.orElse);
      elseExits = _exits(s.orElse);
    }
    final n2 = {...sc.nn};
    final thenExits = _exits(arm.body);
    if (thenExits && elseExits) {
      sc.nn = keep;
    } else if (thenExits) {
      sc.nn = n2;
    } else if (elseExits) {
      sc.nn = n1;
    } else {
      sc.nn = n1.intersection(n2);
    }
    return thenExits && elseExits;
  }

  void _st(_Scope sc, LStmt s) {
    switch (s) {
      case LNote() || LBreak() || LContinue() || LHost():
        return;
      case LLet(:final name, :final value, :final kind):
        final vk = kind == LNameKind.variable ? LVarKind.local : LVarKind.temp;
        if (s.type != null) {
          final wt = w.resolve(s.type, sc.tv);
          final t = ex(sc, value, wt);
          want(value, wt);
          declare(sc, name, t, declared: wt, node: value, kind: vk);
        } else {
          declare(sc, name, ex(sc, value), node: value, kind: vk);
        }
        if (finalPass) _assigned.add((value, find(sc, name)!));
      case LAssign(:final target, :final value):
        switch (target) {
          case LTName(:final name):
            _assign(sc, name, value, s);
          case LTIndex(:final of, :final key):
            store(sc, of, key, value, s);
          case LTField(:final of, :final name):
            if (classRef(sc, of) != null) {
              arg(sc, value, field(sc, of, name, target), '「$name」');
              return;
            }
            final t = w.res(ex(sc, of));
            if (name == kErrKindField && isErr(t)) {
              ex(sc, value);
              err('T19', sc, '错误的“种类”只能读，不能改', node: s);
              return;
            }
            if (w.isRecord(t)) {
              ex(sc, value);
              err(
                'T10',
                sc,
                '记录「${t.name}」建好以后不能改，用“复制并改”',
                node: s,
                fixes: [
                  LFix(LFixKind.useRecordCopy, '换成“复制并改”', target: s, params: {'field': name}),
                ],
              );
              return;
            }
            arg(sc, value, field(sc, of, name, target), '「$name」');
        }
      case LExprStmt(:final expr):
        noteAlone(expr);
        ex(sc, expr);
      case LIf():
        if (s.arms.isEmpty) {
          block(sc, s.orElse);
        } else {
          _ifFrom(sc, s, 0);
        }
      case LWhile(:final cond, :final body):
        if (cond != null) this.cond(sc, cond);
        _loop(sc, body);
      case LRepeat(:final times, :final body):
        arg(sc, times, _int, '“重复”的次数');
        _loop(sc, body);
      case LForCount(:final name, :final from, :final to, :final step, :final body):
        // 三个数都是整数：数出来的是整数；有小数：数出来的是小数。
        final parts = [(from, '“数数”的起点'), (to, '“数数”的终点'), (step, '“数数”的步长')];
        final ts = [for (final (x, _) in parts) w.res(ex(sc, x))];
        final wt = ts.contains(_flt) ? _flt : _int;
        for (var i = 0; i < parts.length; i++) {
          if (!w.ok(ts[i], wt)) mismatch(sc, parts[i].$1, ts[i], wt, '${parts[i].$2}要${wt.show()}');
          want(parts[i].$1, wt);
        }
        declare(sc, name, wt, kind: LVarKind.loop);
        _loop(sc, body);
      case LForEach(:final list, :final item, :final index, :final reuse, :final body):
        final t = nonnull(sc, list, (_) => '列表');
        final el = WL.isList(t) ? WL.elem(t) : (t.isAny ? _any : _never);
        if (reuse) {
          _assignType(sc, item, el, s);
        } else {
          declare(sc, item, el, kind: LVarKind.loop);
        }
        if (!WL.isList(t) && !t.isAny && !t.isNever) err('T01', sc, '“每个”后面要列表，放进来的是${t.show()}', node: list);
        if (index != null) declare(sc, index, _int, kind: LVarKind.loop);
        _loop(sc, body);
      case LForPairs(:final dict, :final key, :final value, :final body):
        final t = nonnull(sc, dict, (_) => '字典');
        declare(sc, key, _txt, kind: LVarKind.loop);
        declare(sc, value, WL.isDict(t) ? WL.elem(t) : _any, kind: LVarKind.loop);
        if (!WL.isDict(t) && !t.isAny && !t.isNever) err('T01', sc, '“每一对”后面要字典，放进来的是${t.show()}', node: dict);
        _loop(sc, body);
      case LReturn(:final value):
        final f = sc.f;
        final wt = f?.ret == null ? null : w.resolve(f!.ret, f.typeVars);
        var t = value == null ? _nul : ex(sc, value, wt);
        if (wt != null && value != null) want(value, wt);
        if (wt != null && !w.ok(t, wt)) {
          t = w.res(t);
          if (t.nullable && w.ok(t.nonNull, wt)) {
            err('T02', sc, '「${sc.fn}」说好返回${wt.show()}，这里返回的可能是空', node: value ?? s, fixes: value == null ? const [] : fixesFor(value, t, wt));
          } else {
            err('T01', sc, '「${sc.fn}」说好返回${wt.show()}，这里返回的是${t.show()}', node: value ?? s, fixes: value == null ? const [] : fixesFor(value, t, wt));
          }
        }
        if (wt != null && value != null && w.ok(t, wt)) waitFit(sc, value, t, wt, '「${sc.fn}」返回的东西');
        sc.rets.add(t);
        if (finalPass && value != null && wt == null && f != null) _returned.add((value, f));
      case LThrow():
        throwStmt(sc, s);
      case LTry():
        tryStmt(sc, s);
      case LMatch():
        _match(sc, s);
    }
  }

  void _assign(_Scope sc, String name, LExpr value, LNode node) {
    final k = find(sc, name);
    if (k == null) {
      ex(sc, value);
      err('T08', sc, '没有叫「$name」的变量', node: node);
      return;
    }
    final v = vt[k]!;
    final t = ex(sc, value, v.fixed ? v.t : null);
    for (_Scope? x = sc; x != null; x = x.parent) {
      x.narrow.remove(name); // 重新放了东西：不再按“出错时”那一节的种类看
      if (x.names.contains(name)) break;
    }
    if (finalPass) _assigned.add((value, k));
    _assignType(sc, name, t, value);
  }

  void _assignType(_Scope sc, String name, LType t, LNode node) {
    final k = find(sc, name);
    if (k == null) {
      err('T08', sc, '没有叫「$name」的变量', node: node);
      return;
    }
    var owner = sc;
    while (!owner.names.contains(name)) {
      owner = owner.parent!;
    }
    note(owner, name, t, node: node);
    final r = w.res(t);
    if (r.nullable || r.isNul) {
      sc.nn.remove(name);
    } else if (identical(owner, sc) && w.res(vt[k]!.t).nullable) {
      sc.nn.add(name); // 刚放进去一个肯定不是空的值
    }
  }

  void _match(_Scope sc, LMatch s) {
    final t = w.res(ex(sc, s.subject));
    final names = [for (final a in s.arms) a.caseName];
    List<String>? all;
    LVariantDecl? variant;
    if (t.kind == LKind.enumeration && !t.nullable && w.enums.containsKey(t.name)) {
      all = w.enums[t.name]!.cases;
    } else if (t.kind == LKind.variant && !t.nullable && w.variants.containsKey(t.name)) {
      variant = w.variants[t.name];
      all = [for (final c in variant!.cases) c.name];
    } else if (!t.isAny && !t.isNever) {
      err('T01', sc, '“分情况”要枚举或者变体，放进来的是${t.show()}', node: s.subject);
    }
    if (all != null && s.orElse == null) {
      final miss = [
        for (final c in all)
          if (!names.contains(c)) c,
      ];
      if (miss.isNotEmpty) {
        err(
          'T03',
          sc,
          '“分情况”还少了：${miss.join('、')}（或者加一个“其余”）',
          node: s,
          fixes: [
            LFix(LFixKind.addMatchCases, '补上少的情况', target: s, params: {'cases': miss}),
            LFix(LFixKind.addMatchElse, '加一个“其余”', target: s),
          ],
        );
      }
    }
    final keep = {...sc.nn};
    for (final a in s.arms) {
      sc.nn = {...keep};
      if (all != null && !all.contains(a.caseName)) {
        err('T08', sc, '「${t.name}」里没有「${a.caseName}」', node: s);
        continue;
      }
      final fields = variant?.cases.firstWhere((c) => c.name == a.caseName).fields ?? const <LTypedField>[];
      if (a.binds.length > fields.length && all != null) err('T07', sc, '「${a.caseName}」带 ${fields.length} 个值，这里接了 ${a.binds.length} 个', node: s);
      for (var i = 0; i < a.binds.length; i++) {
        final name = a.binds[i];
        sc.names.add(name);
        vt.putIfAbsent(vkey(sc.key, name), () => _Var(i < fields.length ? w.resolve(fields[i].type) : _any, hidden: true, kind: LVarKind.matchBind));
      }
      block(sc, a.body);
    }
    if (s.orElse != null) {
      sc.nn = {...keep};
      block(sc, s.orElse!);
    }
    sc.nn = keep;
  }
}
