part of 'typecheck.dart';

/// 式子的类型（原型的 `ex0`）。
mixin _Exprs on _Core {
  @override
  LType ex(_Scope sc, LExpr e, [LType? wantT]) {
    final t = _ex0(sc, e, wantT);
    if (finalPass) types[e] = t;
    return t;
  }

  void _all(_Scope sc, List<LExpr> list) {
    for (final x in list) {
      ex(sc, x);
    }
  }

  LType _ex0(_Scope sc, LExpr e, LType? wantT) {
    switch (e) {
      case LLit(:final value):
        return switch (value) {
          null => _nul,
          bool() => _bool,
          int() => _intLit(sc, e, value),
          double() => _flt,
          _ => _txt,
        };
      case LName(:final name, :final kind):
        if (kind != LNameKind.variable) return _any;
        final k = find(sc, name);
        if (k != null) {
          final t = w.res(vt[k]!.t);
          final n = narrowed(sc, name);
          if (n != null && n != t) {
            op(e, 'narrow');
            return n;
          }
          return sc.nn.contains(name) ? t.nonNull : t;
        }
        final f = w.funcs[name];
        if (f != null) return fnType(f);
        err('T08', sc, '没有叫「$name」的变量', node: e);
        return _never;
      case LListLit(:final items):
        return _listLit(sc, e, items, wantT);
      case LDictLit(:final entries):
        return _dictLit(sc, e, entries, wantT);
      case LField(:final of, :final name):
        return field(sc, of, name, e);
      case LIndex(:final of, :final key):
        return index(sc, of, key, e);
      case LUnary(:final op, :final x):
        if (op == 'not') {
          cond(sc, x);
          return _bool;
        }
        final t = w.res(ex(sc, x));
        final r = _num(sc, '取负', [t], [x], e);
        if (r != null) return r;
        if (t == _int) check(LCheckKind.intOverflow, e, sc);
        this.op(e, t == _int ? 'ineg' : 'fneg');
        return t;
      case LBinary():
        return _binary(sc, e);
      case LLogic(:final op, :final l, :final r):
        final keep = {...sc.nn};
        cond(sc, l);
        if (op == 'and') sc.nn.addAll(facts(l, true));
        if (op == 'or') sc.nn.addAll(facts(l, false));
        cond(sc, r);
        sc.nn = keep;
        return _bool;
      case LCond(:final cond, :final then, :final orElse):
        this.cond(sc, cond);
        final keep = {...sc.nn};
        sc.nn = {...keep, ...facts(cond, true)};
        final a = ex(sc, then, wantT);
        sc.nn = {...keep, ...facts(cond, false)};
        final b = ex(sc, orElse, wantT);
        sc.nn = keep;
        return w.join(a, b);
      case LCall():
        return call(sc, e);
      case LSend():
        return send(sc, e);
      case LSuperSend():
        return superSend(sc, e);
      case LNew():
        return newObject(sc, e);
      case LIsA(:final x, :final cls):
        ex(sc, x);
        if (!w.classes.containsKey(cls) && !w.interfaces.containsKey(cls)) err('T08', sc, '没有叫「$cls」的类或接口', node: e);
        return _bool;
      case LLambda():
        return lam(sc, e, wantT);
      case LThis():
        if (sc.thisType == null) err('T25', sc, '“我自己”只能用在类的方法和“创建时”里（类本身的方法里没有“我自己”）', node: e);
        return sc.thisType ?? _any;
      case LAwait(:final x):
        final t = w.res(ex(sc, x));
        return t.kind == LKind.future && !t.nullable ? WL.elem(t) : t;
      case LSpawn():
        return _any; // 异步在核心 3。
      case LRt():
        return runtimeCall(sc, e, wantT);
      case LNative(:final name, :final args):
        final d = natives[name];
        if (d == null) {
          _all(sc, args);
          return _any;
        }
        return apply(sc, name, [for (final p in d.params) w.resolve(p.type)], w.resolve(d.type), const [], const {}, args, node: e);
      case LRecordNew():
        return _recordNew(sc, e);
      case LRecordCopy(:final of, :final fields):
        final t = w.res(ex(sc, of));
        final d = w.isRecord(t) ? w.records[t.name] : null;
        if (d == null) {
          for (final f in fields) {
            ex(sc, f.value);
          }
          if (!t.isAny && !t.isNever) err('T01', sc, '“复制并改”要一个记录，放进来的是${t.show()}', node: of);
          return t;
        }
        final b = _recordArgs(d, t);
        for (final f in fields) {
          final ft = d.fields.where((x) => x.name == f.name).firstOrNull;
          if (ft == null) {
            ex(sc, f.value);
            err(
              'T04',
              sc,
              '「${d.name}」没有「${f.name}」这一项',
              node: e,
              fixes: [
                LFix(LFixKind.removeRecordField, '删掉「${f.name}」', target: e, params: {'field': f.name}),
              ],
            );
          } else {
            arg(sc, f.value, w.subst(w.resolve(ft.type, _tvOf(d)), b), '「${d.name}」的「${f.name}」');
          }
        }
        return t;
      case LEnumValue(:final enumName, :final caseName):
        final d = w.enums[enumName];
        if (d == null) {
          err('T08', sc, '没有叫「$enumName」的枚举', node: e);
          return _never;
        }
        if (!d.cases.contains(caseName)) err('T08', sc, '「$enumName」里没有「$caseName」', node: e);
        return LType(LKind.enumeration, name: enumName);
      case LVariantNew(:final variant, :final caseName, :final args):
        final c = w.variants[variant]?.cases.where((c) => c.name == caseName).firstOrNull;
        if (c == null) {
          _all(sc, args);
          err('T08', sc, w.variants.containsKey(variant) ? '「$variant」里没有「$caseName」' : '没有叫「$variant」的变体', node: e);
          return _never;
        }
        if (c.fields.length != args.length) err('T07', sc, '「$caseName」要 ${c.fields.length} 个值，给了 ${args.length} 个', node: e);
        for (var i = 0; i < c.fields.length && i < args.length; i++) {
          arg(sc, args[i], w.resolve(c.fields[i].type), '「$caseName」的「${c.fields[i].name}」', argIndex: i);
        }
        return LType(LKind.variant, name: variant);
      case LCast(:final x, :final to):
        final t = w.res(ex(sc, x));
        final target = w.resolve(to, sc.tv);
        _castCheck(sc, e, t, target);
        return target;
      case LAscribe(:final x, :final to):
        final target = w.resolve(to, sc.tv);
        final t = ex(sc, x, target);
        if (!w.ok(t, target)) mismatch(sc, x, w.res(t), target, '这里标的是${target.show()}');
        want(x, target);
        return target;
    }
  }

  LType _intLit(_Scope sc, LLit e, int value) {
    if (value.abs() > kLangMaxInt || value.abs() < 0) err('T16', sc, '$value 太大了，整数最大只能到 $kLangMaxInt', node: e);
    return _int;
  }

  /// “当成〈类型〉”：永远成不了的报 T15；别的记一处运行时检查。
  void _castCheck(_Scope sc, LCast e, LType t, LType target) {
    if (t.isNever || WL.isHole(t)) return;
    if (!t.isAny && !target.isAny && !w.ok(t, target) && !w.ok(target, t) && !w.hasOpen(target)) {
      final loose = (w.isInterface(target) && w.isClass(t)) || (w.isInterface(t) && w.isClass(target)) || (w.isInterface(t) && w.isInterface(target));
      if (!loose) {
        err('T15', sc, '这个值是${t.show()}，永远当不成${target.show()}', node: e);
        return;
      }
    }
    if (t == target) return;
    if (target.isNamed && (target.kind == LKind.object || target.kind == LKind.interface)) {
      check(LCheckKind.downcast, e, sc, type: target);
    } else if (t.isAny) {
      final each = (target.kind == LKind.list || target.kind == LKind.dict) && !WL.elem(target).isAny;
      check(each ? LCheckKind.anyToContainer : LCheckKind.anyToType, e, sc, type: target);
    }
  }

  LType _listLit(_Scope sc, LListLit e, List<LExpr> items, LType? wantT) {
    final wl = wantT == null ? null : w.res(wantT);
    if (wl != null && WL.isList(wl)) {
      for (final x in items) {
        arg(sc, x, WL.elem(wl), '列表里的一项');
      }
      return wl;
    }
    var el = _never;
    final lams = <LExpr>[];
    for (final x in items) {
      if (x is LLambda) {
        lams.add(x);
      } else {
        el = w.join(el, ex(sc, x));
      }
    }
    for (final x in lams) {
      // 匿名函数放到最后看，拿别的项的类型当线索。
      el = w.join(el, ex(sc, x, el.isNever ? null : el));
    }
    return LType(LKind.list, of: items.isNotEmpty && !el.isNever ? el : LType(LKind.hole, name: holeKey(e, sc)));
  }

  LType _dictLit(_Scope sc, LDictLit e, List<LDictEntry> entries, LType? wantT) {
    final wd = wantT == null ? null : w.res(wantT);
    for (final x in entries) {
      if (x.key is! LLit) arg(sc, x.key, _txt, '字典的键');
    }
    if (wd != null && WL.isDict(wd)) {
      for (final x in entries) {
        arg(sc, x.value, WL.elem(wd), '字典里的一项');
      }
      return wd;
    }
    var el = _never;
    for (final x in entries) {
      el = w.join(el, ex(sc, x.value));
    }
    return LType(LKind.dict, of: entries.isNotEmpty && !el.isNever ? el : LType(LKind.hole, name: holeKey(e, sc)));
  }

  /// 算术的两边：有问题就说一句、返回“永不”；有一边是任意返回“任意”；都是数字返回 null（由调用的地方定是整数还是小数）。
  LType? _num(_Scope sc, String opName, List<LType> ts, List<LExpr> xs, LExpr e) {
    for (var i = 0; i < ts.length; i++) {
      if (ts[i].nullable) {
        err('T02', sc, '$opName的一边可能是空，要先判断“不是空”才能算', node: e, fixes: fixesFor(xs[i], ts[i], ts[i].nonNull));
        return _never;
      }
    }
    if (ts.any((t) => t.isNever || WL.isHole(t))) return _never;
    if (ts.any((t) => t.isAny)) {
      check(LCheckKind.dynamicArith, e, sc);
      return _any;
    }
    for (final t in ts) {
      if (t != _int && t != _flt) {
        err('T06', sc, '$opName的两边要数字，这里有一边是${t.show()}', node: e);
        return _never;
      }
    }
    return null;
  }

  static const Map<String, (String, String)> _arith = {'+': ('加法', 'add'), '-': ('减法', 'sub'), '*': ('乘法', 'mul'), '/': ('除法', 'div'), '**': ('乘方', 'pow'), '//': ('整除', 'idiv'), '%': ('余', 'mod')};
  static const Map<String, String> _compare = {'<': 'lt', '<=': 'le', '>': 'gt', '>=': 'ge'};

  LType _binary(_Scope sc, LBinary e) {
    final o = e.op;
    final xs = [e.l, e.r];
    if (o == '==' || o == '!=') {
      _all(sc, xs);
      op(e, o == '==' ? 'eq' : 'ne');
      return _bool;
    }
    final ts = [for (final x in xs) w.res(ex(sc, x))];
    final cmp = _compare[o];
    if (cmp != null) {
      for (final t in ts) {
        if (t.nullable) {
          err('T02', sc, '比大小的一边可能是空，要先判断“不是空”才能比', node: e);
        } else if (WL.isVar(t) && sc.bounds[t.name] != kBoundComparable) {
          err('T05', sc, '${t.name} 没有说明“能比大小”，不能比', node: e);
        } else if (t != _int && t != _flt && t != _txt && !t.isAny && !t.isNever && !WL.isVar(t) && !WL.isHole(t)) {
          err('T06', sc, '只有数字和文字能比大小，这里有一边是${t.show()}', node: e);
        }
      }
      if (ts.contains(_txt) && (ts.contains(_int) || ts.contains(_flt))) err('T06', sc, '数字和文字不能互相比大小', node: e);
      if (ts.any((t) => t.isAny)) check(LCheckKind.dynamicArith, e, sc);
      op(e, '${ts.any((t) => t.isAny || WL.isVar(t)) ? 'd' : (ts.contains(_txt) ? 't' : (ts.every((t) => t == _int) ? 'i' : 'f'))}$cmp');
      if (ts.contains(_flt) && ts.contains(_int)) {
        for (final x in xs) {
          want(x, _flt);
        }
      }
      return _bool;
    }
    final a = _arith[o];
    if (a == null) {
      err('T06', sc, '不认识的运算「$o」', node: e);
      return _never;
    }
    final (label, fn) = a;
    final whole = o == '//' || o == '%';
    final r = _num(sc, whole ? label : label, ts, xs, e);
    if (r != null) {
      if (r.isAny) op(e, 'd$fn');
      return r;
    }
    final ints = ts.every((t) => t == _int);
    if (!ints && o != '//' && o != '%') {
      for (final x in xs) {
        want(x, _flt); // 整数和小数混着算：整数那边先变成小数
      }
    }
    switch (o) {
      case '+' || '-' || '*':
        if (ints) check(LCheckKind.intOverflow, e, sc);
        op(e, '${ints ? 'i' : 'f'}$fn');
        return ints ? _int : _flt;
      case '/':
        check(LCheckKind.divideByZero, e, sc);
        op(e, 'fdiv');
        return _flt;
      case '**':
        op(e, 'fpow');
        return _flt;
      default:
        if (!ints) {
          err(
            'T06',
            sc,
            '“$label”的两边要整数，这里有一边是小数',
            node: e,
            fixes: [
              for (var i = 0; i < 2; i++)
                if (ts[i] == _flt) LFix(LFixKind.wrapToInt, '取整', target: xs[i]),
            ],
          );
        }
        check(LCheckKind.divideByZero, e, sc);
        op(e, o == '//' ? 'idiv' : 'imod');
        return _int;
    }
  }

  @override
  LType nonnull(_Scope sc, LExpr e, String Function(LType t) what) {
    final t = w.res(ex(sc, e));
    if (!t.nullable) return t;
    final nm = e is LName ? e.name : '这个值';
    err('T02', sc, '「$nm」可能是空，要先判断“不是空”才能当${what(t.nonNull)}用', node: e, fixes: fixesFor(e, t, t.nonNull));
    return t.nonNull;
  }

  @override
  LType arg(_Scope sc, LExpr e, LType wantT, String where, {int? argIndex}) {
    final t = w.res(ex(sc, e, wantT));
    final wt = w.res(wantT);
    if (!w.ok(t, wt)) mismatch(sc, e, t, wt, '$where要${wt.show()}', argIndex: argIndex);
    w.unify(wantT, t, {});
    want(e, wantT);
    return t;
  }

  @override
  void cond(_Scope sc, LExpr e) {
    final t = w.res(ex(sc, e));
    want(e, _bool);
    if (t == _bool || t.isAny || t.isNever) return;
    err(
      'T09',
      sc,
      '这里要“是/否”，放进来的是${t.show()}',
      node: e,
      fixes: [if (t == _int || t == _flt) LFix(LFixKind.compareNotZero, '换成“… ≠ 0”', target: e)],
    );
  }

  /// 条件成立（或不成立）时，哪些变量肯定不是空。
  @override
  Set<String> facts(LExpr e, bool truth) {
    switch (e) {
      case LBinary(op: '!=', l: LName(:final name), r: LLit(value: null)) || LBinary(op: '!=', l: LLit(value: null), r: LName(:final name)):
        return truth ? {name} : {};
      case LBinary(op: '==', l: LName(:final name), r: LLit(value: null)) || LBinary(op: '==', l: LLit(value: null), r: LName(:final name)):
        return truth ? {} : {name};
      case LRt(fn: 'isNull', args: [LName(:final name)]):
        return truth ? {} : {name};
      case LUnary(op: 'not', :final x):
        return facts(x, !truth);
      case LLogic(:final op, :final l, :final r) when (op == 'and' && truth) || (op == 'or' && !truth):
        return {...facts(l, truth), ...facts(r, truth)};
      default:
        return {};
    }
  }

  List<String> _tvOf(LRecordDecl d) => [for (final p in d.typeParams) p.name];

  Map<String, LType> _recordArgs(LRecordDecl d, LType t) => {for (var i = 0; i < d.typeParams.length && i < t.args.length; i++) d.typeParams[i].name: t.args[i]};

  LType _recordNew(_Scope sc, LRecordNew e) {
    final d = w.records[e.record];
    if (d == null) {
      for (final f in e.fields) {
        ex(sc, f.value);
      }
      err('T08', sc, '没有叫「${e.record}」的记录', node: e);
      return _never;
    }
    final t = LType(
      LKind.record,
      name: d.name,
      args: [for (final p in d.typeParams) LType(LKind.hole, name: holeKey(e, sc, ':${p.name}'))],
    );
    final b = _recordArgs(d, t);
    final given = {for (final f in e.fields) f.name};
    final miss = [
      for (final f in d.fields)
        if (!given.contains(f.name)) f.name,
    ];
    if (miss.isNotEmpty) {
      err(
        'T04',
        sc,
        '新建「${d.name}」还缺：${miss.join('、')}',
        node: e,
        fixes: [
          LFix(LFixKind.addRecordFields, '补上缺的', target: e, params: {'fields': miss}),
        ],
      );
    }
    for (final f in e.fields) {
      final ft = d.fields.where((x) => x.name == f.name).firstOrNull;
      if (ft == null) {
        ex(sc, f.value);
        err(
          'T04',
          sc,
          '「${d.name}」没有「${f.name}」这一项',
          node: e,
          fixes: [
            LFix(LFixKind.removeRecordField, '删掉「${f.name}」', target: e, params: {'field': f.name}),
          ],
        );
      } else {
        arg(sc, f.value, w.subst(w.resolve(ft.type, _tvOf(d)), b), '「${d.name}」的「${f.name}」');
      }
    }
    return w.res(t);
  }

  @override
  LType field(_Scope sc, LExpr of, String name, LNode node) {
    final cls = classRef(sc, of);
    if (cls != null) return staticField(sc, cls, name, node);
    final t = nonnull(sc, of, (_) => '有字段的东西');
    if (w.isRecord(t) && w.records.containsKey(t.name)) {
      final d = w.records[t.name]!;
      final f = d.fields.where((x) => x.name == name).firstOrNull;
      if (f != null) return w.res(w.subst(w.resolve(f.type, _tvOf(d)), _recordArgs(d, t)));
    } else if (w.isClass(t)) {
      if (name == kErrKindField && isErr(t)) {
        op(node, 'errKind');
        return _txt;
      }
      final got = w.classField(w.classes[t.name], name);
      if (got != null) {
        final (ft, c) = got;
        if (c.decl.fields.any((f) => f.name == name && f.isPrivate)) privateCheck(sc, c, name, node);
        final tv = c.typeVars;
        return w.res(w.subst(ft, {for (var i = 0; i < tv.length && i < t.args.length; i++) tv[i]: t.args[i]}));
      }
    } else if (t.isAny || t.isNever) {
      return t;
    }
    err('T08', sc, '${t.show()}没有「$name」这一项', node: node);
    return _never;
  }
}
