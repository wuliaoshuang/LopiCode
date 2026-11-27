/// 给顶层的名字改名（核心 2·模块）：几个模块合成一个程序时，不同模块里重名的顶层东西要换成不撞的名字（link.dart 用）。
///
/// 一个“这个名字现在叫什么”的函数管两种位置：
/// - 值的位置（变量、函数的名字）：被这一层的参数、局部变量挡住的不改。局部变量从它出现的那一句开始挡（和类型检查一样，
///   按先后来、一直挡到这个函数完）；
/// - 类型的位置（标注、新建、是不是、继承、实现、只接哪种错误…）：被类型参数挡住的不改。
/// 字段、方法、变体里“情况”的名字不是顶层名字，不动。整棵树重建，位置信息（src）原样带着。
library;

import 'package:lopicode/lang/ast.dart';
import 'package:lopicode/lang/types.dart';

class LRenamer {
  LRenamer(this.resolve);

  /// 一个没被挡住的顶层名字 → 它在合并以后的程序里叫什么（不改就原样返回）。
  final String Function(String name) resolve;

  /// 现在被挡住的名字：值的、类型的。
  Set<String> _locals = {};
  Set<String> _tvars = const {};

  String _val(String n) => _locals.contains(n) ? n : resolve(n);
  String _typ(String n) => _tvars.contains(n) ? n : resolve(n);
  String? _typQ(String? n) => n == null ? null : _typ(n);

  T _scoped<T>(Iterable<String> locals, Iterable<String> tvars, T Function() run) {
    final l = _locals, t = _tvars;
    _locals = {...l, ...locals};
    _tvars = {...t, ...tvars};
    try {
      return run();
    } finally {
      _locals = l;
      _tvars = t;
    }
  }

  LType type(LType t) {
    final named = t.name != null && t.kind != LKind.typeVar;
    return LType(t.kind, of: t.of == null ? null : type(t.of!), args: [for (final a in t.args) type(a)], name: named ? _typ(t.name!) : t.name, nullable: t.nullable, waits: t.waits);
  }

  LType? typeQ(LType? t) => t == null ? null : type(t);

  List<LParam> params(List<LParam> ps) => [for (final p in ps) LParam(p.name, defaultValue: p.defaultValue, type: typeQ(p.type), rest: p.rest)];
  List<LTypeParam> _tps(List<LTypeParam> ps) => [for (final p in ps) LTypeParam(p.name, bound: p.bound == null || p.bound == kBoundComparable || p.bound == kBoundKey ? p.bound : _typ(p.bound!))];
  List<LTypedField> _fields(List<LTypedField> fs) => [for (final f in fs) LTypedField(f.name, type(f.type))];

  /// 一个模块的顶层声明、启动语句。
  List<LDecl> decls(List<LDecl> ds) => [for (final d in ds) decl(d)];
  List<LStmt> mainBody(List<LStmt> body) => _scoped(const [], const [], () => block(body));

  LFuncDecl func(LFuncDecl d) {
    final tv = [for (final p in d.typeParams) p.name];
    return _scoped([for (final p in d.params) p.name], tv, () {
      return LFuncDecl(
        d.name,
        params(d.params),
        block(d.body),
        isPublic: d.isPublic,
        typeParams: _tps(d.typeParams),
        codeName: d.codeName,
        waits: d.waits,
        noWait: d.noWait,
        src: d.src,
        type: typeQ(d.type),
      );
    });
  }

  LDecl decl(LDecl d) {
    switch (d) {
      case LVarDecl():
        return LVarDecl(resolve(d.name), expr(d.init), isConst: d.isConst, isPublic: d.isPublic, src: d.src, type: typeQ(d.type));
      case LFuncDecl():
        final name = resolve(d.name); // 函数自己的名字不会被自己的参数挡住
        final f = func(d);
        return LFuncDecl(name, f.params, f.body, isPublic: f.isPublic, typeParams: f.typeParams, codeName: f.codeName, waits: f.waits, noWait: f.noWait, src: f.src, type: f.type);
      case LClassDecl():
        final name = resolve(d.name);
        return _scoped(const [], [for (final p in d.typeParams) p.name], () {
          return LClassDecl(
            name,
            parent: _typQ(d.parent),
            interfaces: [for (final i in d.interfaces) _typ(i)],
            fields: [for (final f in d.fields) LFieldDecl(f.name, f.init == null ? null : expr(f.init!), isPrivate: f.isPrivate, isStatic: f.isStatic, type: typeQ(f.type))],
            ctor: d.ctor == null ? null : func(d.ctor!),
            methods: [for (final m in d.methods) LMethodDecl(func(m.fn), isStatic: m.isStatic, isAbstract: m.isAbstract)],
            typeParams: _tps(d.typeParams),
            isOpen: d.isOpen,
            isPublic: d.isPublic,
            codeName: d.codeName,
            src: d.src,
          );
        });
      case LInterfaceDecl():
        return LInterfaceDecl(
          resolve(d.name),
          [for (final m in d.methods) LSignature(m.name, params(m.params), returns: typeQ(m.returns), waits: m.waits, noWait: m.noWait)],
          isPublic: d.isPublic,
          codeName: d.codeName,
          src: d.src,
        );
      case LNativeDecl():
        return LNativeDecl(d.name, params(d.params), src: d.src, type: typeQ(d.type));
      case LRecordDecl():
        final name = resolve(d.name);
        return _scoped(const [], [for (final p in d.typeParams) p.name], () {
          return LRecordDecl(name, _fields(d.fields), typeParams: _tps(d.typeParams), isPublic: d.isPublic, codeName: d.codeName, src: d.src);
        });
      case LEnumDecl():
        return LEnumDecl(resolve(d.name), d.cases, isPublic: d.isPublic, codeName: d.codeName, src: d.src);
      case LVariantDecl():
        return LVariantDecl(resolve(d.name), [for (final c in d.cases) LVariantCase(c.name, _fields(c.fields))], isPublic: d.isPublic, codeName: d.codeName, src: d.src);
      case LAliasDecl():
        return LAliasDecl(resolve(d.name), type(d.target), isPublic: d.isPublic, codeName: d.codeName, src: d.src);
    }
  }

  List<LStmt> block(List<LStmt> xs) => [for (final s in xs) stmt(s)];
  List<LExpr> exprs(List<LExpr> xs) => [for (final e in xs) expr(e)];

  LTarget _target(LTarget t) => switch (t) {
    LTName() => LTName(_val(t.name), src: t.src),
    LTIndex() => LTIndex(expr(t.of), expr(t.key), src: t.src),
    LTField() => LTField(expr(t.of), t.name, src: t.src),
  };

  LStmt stmt(LStmt s) {
    switch (s) {
      case LLet():
        final value = expr(s.value);
        _locals.add(s.name);
        return LLet(s.name, value, isConst: s.isConst, kind: s.kind, src: s.src, type: typeQ(s.type));
      case LAssign():
        return LAssign(_target(s.target), expr(s.value), src: s.src);
      case LExprStmt():
        return LExprStmt(expr(s.expr), src: s.src);
      case LIf():
        return LIf([for (final a in s.arms) LIfArm(expr(a.cond), block(a.body))], orElse: block(s.orElse), src: s.src);
      case LWhile():
        return LWhile(s.cond == null ? null : expr(s.cond!), block(s.body), src: s.src);
      case LForCount():
        final from = expr(s.from), to = expr(s.to), step = expr(s.step);
        _locals.add(s.name);
        return LForCount(s.name, from, to, step, block(s.body), src: s.src);
      case LForEach():
        final list = expr(s.list);
        if (!s.reuse) _locals.add(s.item);
        if (s.index != null) _locals.add(s.index!);
        return LForEach(list, s.reuse ? _val(s.item) : s.item, block(s.body), index: s.index, reuse: s.reuse, src: s.src);
      case LForPairs():
        final dict = expr(s.dict);
        _locals.addAll([s.key, s.value]);
        return LForPairs(dict, s.key, s.value, block(s.body), src: s.src);
      case LRepeat():
        return LRepeat(expr(s.times), block(s.body), src: s.src);
      case LReturn():
        return LReturn(s.value == null ? null : expr(s.value!), src: s.src);
      case LThrow():
        return LThrow(expr(s.message), src: s.src);
      case LTry():
        final hs = s.handlers;
        List<LStmt> caught(String? name, List<LStmt> body) {
          if (name != null) _locals.add(name);
          return block(body);
        }

        final body = block(s.body);
        final onError = hs == null ? caught(s.errorName, s.onError) : block(s.onError);
        final handlers = hs == null ? null : [for (final c in hs) LCatch(caught(c.name, c.body), kind: _typQ(c.kind), name: c.name)];
        return LTry(body, errorName: s.errorName, errorClass: _typQ(s.errorClass), onError: onError, handlers: handlers, finallyBody: block(s.finallyBody), src: s.src);
      case LMatch():
        final subject = expr(s.subject);
        final arms = [
          for (final a in s.arms)
            () {
              _locals.addAll(a.binds);
              return LMatchArm(a.caseName, a.binds, block(a.body));
            }(),
        ];
        return LMatch(subject, arms, orElse: s.orElse == null ? null : block(s.orElse!), src: s.src);
      case LBreak() || LContinue() || LHost() || LNote():
        return s;
    }
  }

  List<LFieldInit> _inits(List<LFieldInit> xs) => [for (final f in xs) LFieldInit(f.name, expr(f.value))];

  LExpr expr(LExpr e) {
    switch (e) {
      case LLit() || LThis():
        return e;
      case LName():
        return e.kind == LNameKind.host ? e : LName(_val(e.name), kind: e.kind, src: e.src);
      case LListLit():
        return LListLit(exprs(e.items), src: e.src);
      case LDictLit():
        return LDictLit([for (final d in e.entries) LDictEntry(expr(d.key), expr(d.value))], src: e.src);
      case LField():
        return LField(expr(e.of), e.name, src: e.src);
      case LIndex():
        return LIndex(expr(e.of), expr(e.key), src: e.src);
      case LUnary():
        return LUnary(e.op, expr(e.x), src: e.src);
      case LBinary():
        return LBinary(e.op, expr(e.l), expr(e.r), src: e.src);
      case LLogic():
        return LLogic(e.op, expr(e.l), expr(e.r), src: e.src);
      case LCond():
        return LCond(expr(e.cond), expr(e.then), expr(e.orElse), src: e.src);
      case LCall():
        return LCall(expr(e.callee), exprs(e.args), src: e.src);
      case LSend():
        return LSend(expr(e.obj), e.method, exprs(e.args), src: e.src);
      case LSuperSend():
        return e.isCtor ? LSuperSend.ctor(exprs(e.args), src: e.src) : LSuperSend(e.method, exprs(e.args), src: e.src);
      case LNew():
        return LNew(_typ(e.cls), exprs(e.args), typeArgs: [for (final t in e.typeArgs) type(t)], src: e.src);
      case LIsA():
        return LIsA(expr(e.x), _typ(e.cls), src: e.src);
      case LLambda():
        final ps = [for (final p in e.params) p.name];
        if (e.expr != null) return _scoped(ps, const [], () => LLambda.short(params(e.params), expr(e.expr!), waits: e.waits, src: e.src));
        return _scoped(ps, const [], () => LLambda(params(e.params), block(e.body), waits: e.waits, src: e.src));
      case LAwait():
        return LAwait(expr(e.x), src: e.src);
      case LSpawn():
        return LSpawn(block(e.body), src: e.src);
      case LRt():
        return LRt(e.fn, exprs(e.args), src: e.src);
      case LNative():
        return LNative(e.name, exprs(e.args), src: e.src);
      case LRecordNew():
        return LRecordNew(_typ(e.record), _inits(e.fields), src: e.src);
      case LRecordCopy():
        return LRecordCopy(expr(e.of), _inits(e.fields), src: e.src);
      case LEnumValue():
        return LEnumValue(_typ(e.enumName), e.caseName, src: e.src);
      case LVariantNew():
        return LVariantNew(_typ(e.variant), e.caseName, exprs(e.args), src: e.src);
      case LCast():
        return LCast(expr(e.x), type(e.to), src: e.src);
      case LAscribe():
        return LAscribe(expr(e.x), type(e.to), src: e.src);
    }
  }
}
