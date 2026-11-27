part of 'backend_lower_lang.dart';

/// 函数那一组积木怎么翻（调用、匿名函数、函数引用、“返回”）：从 backend_lower_lang.dart 原样挪出来的，那边放不下了。
extension _BeLangLowerFunc on BeLangLower {
  // —— 函数（第 2 阶段）——

  List<LParam> _lambdaParams(Object? e) {
    final raw = exprField(e, 'params');
    final names = <String>[];
    if (raw is List) {
      for (final p in raw) {
        if (p is String && p.trim().isNotEmpty && !names.contains(beIdent(p))) names.add(beIdent(p));
      }
    }
    return [for (final n in names) LParam(n)];
  }

  /// 调用的实参表：按定义的参数顺序一个个取（实参按参数名存）。“剩下的全收”的槽里放的是“列表”积木就把每一项各当一个实参，放别的就当一个。
  /// [holder]＝这次调用本身（值积木是那个式子，语句积木是那块积木）。
  List<LExpr> _callArgs(BeFunction f, Object? Function(String name) read, int depth, Object holder) {
    final arg = _arg;
    final out = <LExpr>[];
    LExpr one(String name, Object? value, [Object? inList, int? i]) {
      _arg = name;
      return inList == null ? _lx(value, depth + 1, holder, name) : _lx(value, depth + 1, inList, i);
    }

    for (final p in f.params) {
      final value = read(p.name);
      if (!p.rest) {
        out.add(value == null ? LLit(p.defaultValue) : one(p.name, value));
      } else if (exprKind(value) == 'listLit') {
        final items = exprField(value, 'items');
        if (items is List) out.addAll([for (final (i, item) in items.indexed) one(p.name, item, items, i)]);
      } else if (value != null) {
        out.add(one(p.name, value));
      }
    }
    _arg = arg;
    return out;
  }

  List<LExpr> _listArgs(Object? list, int depth) => [
    if (list is List)
      for (final (i, item) in list.indexed) _lx(item, depth + 1, list, i),
  ];

  /// 第 2 阶段的式子；不是的返回 null。
  LExpr? _funcExpr(String kind, Object e, int depth, LExpr Function(String key) sub) {
    LExpr gone() {
      host.addNote('这块自定义积木的定义已经不在了，当成空的');
      return const LLit(null);
    }

    final callee = beCallId(kind);
    if (callee != null) {
      final f = host.function(callee);
      return f == null ? gone() : LCall(LName(f.ident), _callArgs(f, (n) => exprField(e, n), depth, e), src: _src());
    }
    final lib = kind.startsWith('lib:') ? bridge?.libExpr(kind, sub, (n) => exprField(e, n)) : null;
    if (lib != null) return lib;
    switch (kind) {
      case 'param':
        final name = exprString(e, 'name');
        if (name == null || name.isEmpty) {
          host.addNote('参数没选好，当成空的');
          return const LLit(null);
        }
        return LName(beIdent(name), src: _src());
      case 'funcRef':
        final f = host.function(exprString(e, 'fn') ?? '');
        return f == null ? gone() : LName(f.ident, src: _src());
      case 'callValue':
        return LCall(sub('fn'), _listArgs(exprField(e, 'args'), depth), src: _src());
      case 'lambdaExpr':
        return LLambda.short(_lambdaParams(e), sub('body'), src: _src());
      case 'lambda':
        final body = lcExprBody(e) ?? const <LcBlock>[];
        final owner = _owner, path = _path, arg = _arg, at = _depth;
        final src = _src();
        // 这个口是这块积木上的第几个（按内容认，不按位置存：见 logic_model.dart 的 lcExprMouthArm）。
        final k = owner == null ? -1 : owner.exprMouths.indexWhere((m) => identical(m, body));
        final inner = k < 0 ? const <LStmt>[] : stmts(body, path, at + 1, arm: lcExprMouthArm(k));
        _owner = owner;
        _path = path;
        _arg = arg;
        _depth = at;
        return LLambda(_lambdaParams(e), inner, src: src);
      case 'listMap' || 'listFilter' || 'listFind' || 'listEvery' || 'listSome' || 'listSortBy':
        return LRt(kind, [sub('xs'), sub('fn')], src: _src());
      case 'listReduce':
        return LRt(kind, [sub('xs'), sub('fn'), sub('init')], src: _src());
    }
    return null;
  }

  /// 第 2 阶段的语句；不是的返回 null。
  List<LStmt>? _funcBlock(LcBlock b, LExpr Function(String name) arg, LSrc Function([String? name]) src) {
    final callee = beCallId(b.op);
    if (callee != null) {
      final f = host.function(callee);
      if (f == null) return _skip('这块自定义积木的定义已经不在了');
      return [LExprStmt(LCall(LName(f.ident), _callArgs(f, (n) => b.args[n], 0, b), src: src()), src: src())];
    }
    switch (b.op) {
      case 'return':
        return [LReturn(arg('value'), src: src())];
      case 'returnNothing':
        return [LReturn(null, src: src())];
      case 'callValueStmt':
        final fn = arg('fn');
        _arg = 'args';
        final args = _listArgs(b.args['args'], 0);
        _arg = null;
        return [LExprStmt(LCall(fn, args, src: src()), src: src())];
      case 'listEach':
        return [
          LExprStmt(LRt('listEach', [arg('xs'), arg('fn')], src: src()), src: src()),
        ];
    }
    return null;
  }
}
