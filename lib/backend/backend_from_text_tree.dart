part of 'backend_from_text.dart';

/// 写“对照用的文字”的写法器：局部名字照 [rename] 换、类型里的别名照 [aliases] 摊开。两边（原来的模块、积木翻回去的语法树）
/// 都用它写，写出来一样＝这一句翻对了。“文字原样”块里存的也是它写的字（名字已经换好）。
class BeCanonWriter extends LcWriter {
  factory BeCanonWriter({Map<String, String> rename = const {}, Map<String, LType> aliases = const {}}) {
    late final BeCanonWriter w;
    return w = BeCanonWriter._(rename, aliases, (e) => w._expr(e), (s) => w._stmt(s));
  }
  BeCanonWriter._(this.rename, this.aliases, String? Function(LExpr) e, String? Function(LStmt) s) : super(exprHook: e, stmtHook: s);

  final Map<String, String> rename;
  final Map<String, LType> aliases;

  /// 自带的库里有用 `_` 当“不要的参数”的名字的：读得进来，平常的写法器却不肯写；这里照原样写。
  @override
  String name(String n) => n == '_' ? n : super.name(n);

  /// 被匿名函数的参数挡住的名字（挡住的不换）。
  final List<Set<String>> _shadow = [];

  String local(String n) => _shadow.any((s) => s.contains(n)) ? n : (rename[n] ?? n);

  LType expand(LType t, [int depth = 0]) {
    if (depth > 16) return t;
    final target = t.kind == LKind.object && t.args.isEmpty ? aliases[t.name] : null;
    if (target != null) {
      final x = expand(target, depth + 1);
      return t.nullable && !x.nullable && x.kind != LKind.any && x.kind != LKind.nul ? LType(x.kind, of: x.of, args: x.args, name: x.name, nullable: true, waits: x.waits) : x;
    }
    return LType(t.kind, of: t.of == null ? null : expand(t.of!, depth + 1), args: [for (final a in t.args) expand(a, depth + 1)], name: t.name, nullable: t.nullable, waits: t.waits);
  }

  @override
  String type(LType t) => super.type(aliases.isEmpty ? t : expand(t));

  String? _expr(LExpr e) {
    if (e is LName && e.kind == LNameKind.variable) return name(local(e.name));
    if (e is LLambda && rename.isNotEmpty) {
      _shadow.add({for (final p in e.params) p.name});
      try {
        final head = e.waits ? '要等λ' : 'λ';
        return e.expr != null ? '($head ${params(e.params)} ${expr(e.expr!)})' : '($head块 ${params(e.params)}${block(e.body, '    ')})';
      } finally {
        _shadow.removeLast();
      }
    }
    return null;
  }

  String _part(String? x) => x == null ? '_' : name(x);

  String? _stmt(LStmt s) {
    const inner = '  ';
    switch (s) {
      case LLet() when s.kind == LNameKind.variable:
        final t = s.type;
        return '(${s.isConst ? '常' : '设'} ${name(local(s.name))}${t == null ? '' : ' ${type(t)}'} ${expr(s.value)})';
      case LAssign(target: LTName(name: final n), :final value):
        return '(改 ${name(local(n))} ${expr(value)})';
      case LForCount():
        return '(从数 ${name(local(s.name))} ${expr(s.from)} ${expr(s.to)} ${expr(s.step)}${block(s.body, inner)})';
      case LForEach():
        if (s.reuse) return '(每个旧 ${name(local(s.item))} ${expr(s.list)}${block(s.body, inner)})';
        if (s.index != null) return '(每个带号 ${name(local(s.item))} ${name(local(s.index!))} ${expr(s.list)}${block(s.body, inner)})';
        return '(每个 ${name(local(s.item))} ${expr(s.list)}${block(s.body, inner)})';
      case LForPairs():
        return '(每对 ${name(local(s.key))} ${name(local(s.value))} ${expr(s.dict)}${block(s.body, inner)})';
      case LTry():
        final catches = s.catches;
        return '(试\n$inner(做${block(s.body, '$inner  ')})'
            '${catches.isEmpty ? '\n$inner(不接)' : [for (final c in catches) '\n$inner(出错时 ${_part(c.kind)} ${_part(c.name == null ? null : local(c.name!))}${block(c.body, '$inner  ')})'].join()}'
            '${s.finallyBody.isEmpty ? '' : '\n$inner(最后${block(s.finallyBody, '$inner  ')})'})';
      default:
        return null;
    }
  }
}

typedef _J = Map<String, dynamic>;

/// 一个函数里的翻译：语法树 → 积木的 JSON。翻不了的地方落成“文字原样”，并记一笔。
class _Tree {
  _Tree(this.m, this.w, this.params);
  final BeFromText m;
  final BeCanonWriter w;

  /// 现在看得见的参数（函数的、外面套着的匿名函数的）。
  final Set<String> params;
  final List<String> raws = [];
  int stmtCount = 0;
  int rawStmts = 0;

  _J _x(String kind, [_J args = const {}]) => {'e': kind, ...args};
  _J _b(String op, [_J args = const {}, List<_J> body = const [], List<_J> orElse = const [], List<_J> arms = const [], bool noElse = false]) => {
    'op': op,
    if (args.isNotEmpty) 'args': args,
    if (body.isNotEmpty) 'body': body,
    if (arms.isNotEmpty) 'arms': arms,
    if (orElse.isNotEmpty) 'else': orElse,
    if (noElse) 'noElse': true,
  };

  _J rawExpr(LExpr e) {
    final text = w.expr(e);
    raws.add(text);
    return _x(kBeRawExpr, {'src': text});
  }

  _J rawStmt(LStmt s) {
    rawStmts++;
    final text = w.stmt(s, '') ?? '';
    raws.add(text);
    return _b(kBeRawStmt, {'src': text});
  }

  String? _typeKey(LType t) => lcTypeText(w.expand(t));

  List<_J> exprs(List<LExpr> list) => [for (final e in list) expr(e)];

  _J expr(LExpr e) => _expr(e) ?? rawExpr(e);

  _J? _expr(LExpr e) {
    switch (e) {
      case LLit(:final value):
        return switch (value) {
          null => _x('null'),
          final bool v => _x('bool', {'v': v}),
          final num v => _x('num', {'v': v}),
          final String v => _x('text', {'v': v}),
          _ => null,
        };
      case LName(name: final n, :final kind):
        if (kind != LNameKind.variable) return null;
        if (params.contains(n)) return _x('param', {'name': n});
        final to = w.local(n);
        if (m.localOk(to) && (w.rename.containsKey(n) || m.isLocalName(n))) return _x('var', {'name': to});
        final f = m.funcs[n];
        return f == null ? null : _x('funcRef', {'fn': f.id});
      case LListLit(:final items):
        return _x('listLit', {'items': exprs(items)});
      case LDictLit(:final entries):
        if (entries.any((x) => x.key is! LLit || (x.key as LLit).value is! String || ((x.key as LLit).value as String).isEmpty)) return null;
        return _x('obj', {
          'fields': [
            for (final x in entries) _x('pair', {'key': (x.key as LLit).value, 'value': expr(x.value)}),
          ],
        });
      case LIndex(:final of, :final key):
        return _x('index', {'of': expr(of), 'key': expr(key)});
      case LField(:final of, name: final n):
        return _x('getField', {'of': expr(of), 'name': n});
      case LUnary(:final op, :final x):
        return op == 'not' ? _x('not', {'x': expr(x)}) : (op == 'neg' ? _x('neg', {'x': expr(x)}) : null);
      case LBinary(:final op, :final l, :final r):
        if (op == '**') return _x('pow', {'a': expr(l), 'b': expr(r)});
        if (op == '//') return _x(kBeIntDiv, {'l': expr(l), 'r': expr(r)});
        return kArithmeticOps.contains(op) || kCompareOps.contains(op) ? _x('bin', {'op': op, 'l': expr(l), 'r': expr(r)}) : null;
      case LLogic(:final op, :final l, :final r):
        return _x('logic', {'op': op, 'l': expr(l), 'r': expr(r)});
      case LCond(:final cond, :final then, :final orElse):
        return _x('cond', {'cond': expr(cond), 'then': expr(then), 'orElse': expr(orElse)});
      case LCall(:final callee, :final args):
        final f = callee is LName && !params.contains(callee.name) && !w.rename.containsKey(callee.name) ? m.funcs[callee.name] : null;
        if (f != null) return f.params.length == args.length ? _x(beCallOp(f.id), {for (final (i, p) in f.params.indexed) p: expr(args[i])}) : null;
        return _x('callValue', {'fn': expr(callee), 'args': exprs(args)});
      case LSend(:final obj, :final method, :final args):
        return _x('callMethod', {'of': expr(obj), 'name': method, 'args': exprs(args)});
      case LNew(:final cls, :final args, :final typeArgs):
        return typeArgs.isEmpty && m.classes.contains(cls) ? _x('classNew', {'type': cls, 'args': exprs(args)}) : null;
      case LThis():
        return _x('this');
      case LRecordNew(:final record, :final fields):
        return _x('recNew', {
          'type': record,
          'fields': [
            for (final f in fields) _x('pair', {'key': f.name, 'value': expr(f.value)}),
          ],
        });
      case LCast(:final x, :final to):
        final key = _typeKey(to);
        return key == null ? null : _x(kBeCast, {'x': expr(x), 'to': key});
      case LAscribe(:final x, :final to):
        final key = _typeKey(to);
        return key == null ? null : _x(kBeAscribe, {'x': expr(x), 'to': key});
      case LNative(name: final n, :final args):
        return _x(kBeHostCall, {'name': n, 'args': exprs(args)});
      case LLambda():
        if (e.waits || e.params.any((p) => p.defaultValue != null || p.rest || beIdent(p.name) != p.name)) return null;
        final names = [for (final p in e.params) p.name];
        // 参数标了类型的：类型写得出来就标在参数小块上（一格一个，没标的是空字）。
        final types = [for (final p in e.params) p.type == null ? '' : _typeKey(p.type!)];
        if (types.contains(null)) return null;
        final typed = types.any((t) => t != '') ? {kExprParamTypes: types} : const <String, dynamic>{};
        if (names.toSet().length != names.length || names.any(w.rename.containsKey)) return null;
        final added = names.where(params.add).toList();
        try {
          return e.expr != null ? _x('lambdaExpr', {'params': names, ...typed, 'body': expr(e.expr!)}) : _x('lambda', {'params': names, ...typed, kLcExprBody: stmts(e.body)});
        } finally {
          params.removeAll(added);
        }
      case LRt(:final fn, :final args):
        return _rt(fn, args);
      default:
        return null;
    }
  }

  _J? _rt(String fn, List<LExpr> args) {
    _J? named(String kind, List<String> names, [_J more = const {}]) => names.length == args.length ? _x(kind, {...more, for (final (i, n) in names.indexed) n: expr(args[i])}) : null;
    final strict = kBeStrictRtArgs[fn];
    if (strict != null) return named(fn, strict);
    if (fn == 'isType') {
      final t = args.length == 2 && args[1] is LLit ? (args[1] as LLit).value : null;
      if (kBeTypeNames.contains(t)) return _x('isType', {'x': expr(args[0]), 'type': t});
      return named(kBeIsTypeNamed, const ['x', 'name']);
    }
    if (fn == 'size') return named(kBeSizeOf, const ['x']);
    if (fn == 'join') return _x(kBeJoinText, {'items': exprs(args)});
    for (final f in kBeRtFamilies.entries) {
      if (f.value.$1.contains(fn)) return named(f.key, f.value.$2, {'fn': fn});
    }
    const withFn = {'listMap', 'listFilter', 'listFind', 'listEvery', 'listSome', 'listSortBy'};
    if (withFn.contains(fn)) return named(fn, const ['xs', 'fn']);
    if (fn == 'listReduce') return named(fn, const ['xs', 'fn', 'init']);
    final plain = kBeRtArgs[fn];
    if (plain != null && beLangExprSpecs.containsKey(fn)) return named(fn, plain);
    return null;
  }

  List<_J> stmts(List<LStmt> list) => [
    for (final s in list)
      if (s is! LNote) stmt(s),
  ];

  _J stmt(LStmt s) {
    stmtCount++;
    final mark = raws.length, markRaw = rawStmts;
    final got = _stmt(s);
    if (got != null) return got;
    // 整句翻不了：里面先前记下的那些小处不再单算，按整句记一处。
    raws.length = mark;
    rawStmts = markRaw;
    return rawStmt(s);
  }

  _J? _stmt(LStmt s) {
    switch (s) {
      case LLet() when s.kind == LNameKind.variable:
        final to = w.local(s.name);
        if (!m.localOk(to)) return null;
        final t = s.type;
        return _b(s.isConst ? 'const' : 'let', {'name': to, 'value': expr(s.value), if (t != null) kBeLetTypeArg: lTypeToJson(w.expand(t))});
      case LAssign(:final target, :final value):
        switch (target) {
          case LTName(name: final n):
            final to = w.local(n);
            return m.localOk(to) && !params.contains(n) ? _b('setVar', {'name': to, 'value': expr(value)}) : null;
          case LTIndex(:final of, :final key):
            return _b('setItem', {'of': expr(of), 'key': expr(key), 'value': expr(value)});
          case LTField(:final of, name: final n):
            return _b('setField', {'of': expr(of), 'name': n, 'value': expr(value)});
        }
      case LExprStmt(expr: final e):
        if (e is LCall) {
          final c = _expr(e);
          if (c == null) return null;
          final kind = c['e'] as String;
          final args = {...c}..remove('e');
          return kind == 'callValue' ? _b('callValueStmt', args) : _b(kind, args);
        }
        if (e is LNative) return _b(kBeHostCallStmt, {'name': e.name, 'args': exprs(e.args)});
        if (e is LSend) return _b('callMethodStmt', {'of': expr(e.obj), 'name': e.method, 'args': exprs(e.args)});
        if (e is LRt) {
          const ops = {'listPush', 'listInsert', 'listSet', 'listRemove', 'dictSet', 'dictRemove'};
          final names = kBeRtArgs[e.fn];
          if (ops.contains(e.fn) && names != null && names.length == e.args.length) return _b(e.fn, {for (final (i, n) in names.indexed) n: expr(e.args[i])});
          if (e.fn == 'listEach' && e.args.length == 2) return _b('listEach', {'xs': expr(e.args[0]), 'fn': expr(e.args[1])});
        }
        return _b('do', {'value': expr(e)});
      case LIf(:final arms, :final orElse):
        if (arms.isEmpty) return null;
        return _b(
          'if',
          {'cond': expr(arms.first.cond)},
          stmts(arms.first.body),
          stmts(orElse),
          [
            for (final a in arms.skip(1))
              {
                'args': {'cond': expr(a.cond)},
                'body': stmts(a.body),
              },
          ],
          orElse.isEmpty,
        );
      case LWhile(:final cond, :final body):
        return cond == null ? _b('forever', const {}, stmts(body)) : _b('while', {'cond': expr(cond)}, stmts(body));
      case LRepeat(:final times, :final body):
        return _b('repeat', {'times': expr(times)}, stmts(body));
      case LForCount():
        final to = w.local(s.name);
        return m.localOk(to) ? _b('forCount', {'name': to, 'from': expr(s.from), 'to': expr(s.to), 'step': expr(s.step)}, stmts(s.body)) : null;
      case LForEach():
        if (s.reuse) return null;
        final item = w.local(s.item), index = s.index == null ? null : w.local(s.index!);
        if (!m.localOk(item) || (index != null && !m.localOk(index))) return null;
        return _b(kBeForIn, {'list': expr(s.list), 'name': item, 'index': ?index}, stmts(s.body));
      case LForPairs():
        final key = w.local(s.key), value = w.local(s.value);
        return m.localOk(key) && m.localOk(value) ? _b('forPairs', {'dict': expr(s.dict), 'key': key, 'value': value}, stmts(s.body)) : null;
      case LBreak():
        return _b('break');
      case LContinue():
        return _b('continue');
      case LReturn(:final value):
        return value == null ? _b('returnNothing') : _b('return', {'value': expr(value)});
      case LThrow(:final message):
        return _b('throw', {'value': expr(message)});
      case LTry():
        if (s.handlers == null) return null;
        final arms = <_J>[];
        for (final c in s.catches) {
          final name = c.name == null ? '' : w.local(c.name!);
          if (name.isNotEmpty && !m.localOk(name)) return null;
          arms.add({
            'args': {'kind': c.kind ?? kBeCatchAny, 'name': name},
            'body': stmts(c.body),
          });
        }
        return _b('try', const {}, stmts(s.body), stmts(s.finallyBody), arms, s.finallyBody.isEmpty);
      default:
        return null;
    }
  }
}
