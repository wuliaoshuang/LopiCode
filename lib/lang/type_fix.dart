/// “一键修”真的去改语法树：拿检查器给的 [LFix]（lib/lang/type_issue.dart），得到改好的一份新模块。纯数据，不碰界面、不碰积木文档。
///
/// 设计：docs/blocks-v5-parts/B-type-system.md 6.2。十一种都能做；积木文档上怎么改（现在只有前六种有对应的积木）在
/// lib/backend/backend_type_fix.dart。语法树不可变，所以是“沿着到目标节点的那条路重新建一遍”，别的节点还是原来的对象。
library;

import 'package:lopicode/lang/ast.dart';
import 'package:lopicode/lang/type_issue.dart';
import 'package:lopicode/lang/typecheck.dart';
import 'package:lopicode/lang/types.dart';

/// “是空就用 ▢”“补上的字段”里先放什么：照类型给一个最平常的值；说不出来（有名字的类型、函数…）返回 null。
LExpr? lFixDefaultFor(LType? t) {
  if (t == null) return null;
  return switch (t.kind) {
    LKind.integer => const LLit(0),
    LKind.number => const LLit(0.0),
    LKind.text => const LLit(''),
    LKind.bool => const LLit(false),
    LKind.list => const LListLit([]),
    LKind.dict => const LDictLit([]),
    _ => null,
  };
}

/// 把 [fix] 用到 [module] 上，返回改好的新模块；做不了（目标不在这个模块里、种类和目标对不上）返回 null，什么都不改。
///
/// [types]＝这个模块的检查结果（“是空就用”后面先放什么、补的字段先放什么要看类型）；不给就放“空”。
/// [fill]＝“是空就用 ▢”的 ▢ 里放什么（给了就用它，不看类型）。
LModule? lApplyFix(LModule module, LFix fix, {LTypeResult? types, LExpr? fill}) {
  final target = fix.target;
  if (target == null) return null;
  final swap = _swapFor(fix, target, types, fill);
  if (swap == null) return null;
  final rw = _Rewriter(target, swap);
  final next = rw.module(module);
  return rw.hit ? next : null;
}

List<String> _names(Object? raw) => [
  if (raw is List)
    for (final x in raw)
      if (x is String) x,
];

/// 目标节点换成什么（式子换式子、语句换语句）；对不上返回 null。
LNode? _swapFor(LFix fix, LNode target, LTypeResult? types, LExpr? fill) {
  switch (fix.kind) {
    case LFixKind.wrapToText:
      return target is LExpr ? LRt('toText', [target], src: target.src) : null;
    case LFixKind.wrapToInt:
      return target is LExpr ? LRt('toInt', [target], src: target.src) : null;
    case LFixKind.wrapParseInt:
      return target is LExpr ? LRt('parseInt', [target], src: target.src) : null;
    case LFixKind.wrapOrElse:
      if (target is! LExpr) return null;
      return LRt('orElse', [target, fill ?? lFixDefaultFor(types?.typeOf(target)?.nonNull) ?? const LLit(null)], src: target.src);
    case LFixKind.wrapMust:
      return target is LExpr ? LRt('must', [target], src: target.src) : null;
    case LFixKind.compareNotZero:
      return target is LExpr ? LBinary('!=', target, const LLit(0), src: target.src) : null;
    case LFixKind.addMatchCases:
      if (target is! LMatch) return null;
      final have = {for (final a in target.arms) a.caseName};
      final add = [
        for (final c in _names(fix.params['cases']))
          if (!have.contains(c)) c,
      ];
      if (add.isEmpty) return null;
      return LMatch(target.subject, [...target.arms, for (final c in add) LMatchArm(c, const [], const [])], orElse: target.orElse, src: target.src);
    case LFixKind.addMatchElse:
      if (target is! LMatch || target.orElse != null) return null;
      return LMatch(target.subject, target.arms, orElse: const [], src: target.src);
    case LFixKind.addRecordFields:
      if (target is! LRecordNew) return null;
      final have = {for (final f in target.fields) f.name};
      final decl = types?.world.records[target.record];
      final add = [
        for (final n in _names(fix.params['fields']))
          if (!have.contains(n)) n,
      ];
      if (add.isEmpty) return null;
      LExpr first(String name) {
        final t = decl?.fields.where((f) => f.name == name).firstOrNull?.type;
        return lFixDefaultFor(t == null ? null : types!.world.resolve(t)) ?? const LLit(null);
      }
      return LRecordNew(target.record, [...target.fields, for (final n in add) LFieldInit(n, first(n))], src: target.src);
    case LFixKind.removeRecordField:
      final field = fix.params['field'];
      if (target is LRecordNew && target.fields.any((f) => f.name == field)) {
        return LRecordNew(
          target.record,
          [
            for (final f in target.fields)
              if (f.name != field) f,
          ],
          src: target.src,
        );
      }
      if (target is LRecordCopy && target.fields.any((f) => f.name == field)) {
        return LRecordCopy(
          target.of,
          [
            for (final f in target.fields)
              if (f.name != field) f,
          ],
          src: target.src,
        );
      }
      return null;
    case LFixKind.useRecordCopy:
      // “把 p 的 x 改成 5” → “把 p 设为（复制 p 并改 x＝5）”。p 得是能重新放东西的位置（变量、列表 / 字典里的一项、另一个字段）。
      if (target is! LAssign) return null;
      final at = target.target;
      if (at is! LTField) return null;
      final of = at.of;
      final LTarget? home = switch (of) {
        LName(:final name) => LTName(name, src: at.src),
        LIndex(of: final a, :final key) => LTIndex(a, key, src: at.src),
        LField(of: final a, :final name) => LTField(a, name, src: at.src),
        _ => null,
      };
      if (home == null) return null;
      return LAssign(home, LRecordCopy(of, [LFieldInit(at.name, target.value)]), src: target.src);
  }
}

/// 沿路重建：碰到 [from]（按“是不是同一个对象”认）就换成 [to]。没变的子树原样返回（还是同一个对象）。
class _Rewriter {
  _Rewriter(this.from, this.to);
  final LNode from;
  final LNode to;
  bool hit = false;

  List<T> _list<T>(List<T> xs, T Function(T) f) {
    List<T>? out;
    for (var i = 0; i < xs.length; i++) {
      final y = f(xs[i]);
      if (!identical(y, xs[i])) (out ??= [...xs])[i] = y;
    }
    return out ?? xs;
  }

  LModule module(LModule m) {
    final decls = _list(m.decls, decl), body = block(m.body);
    return identical(decls, m.decls) && identical(body, m.body) ? m : LModule(name: m.name, uses: m.uses, decls: decls, body: body, src: m.src);
  }

  List<LStmt> block(List<LStmt> xs) => _list(xs, stmt);
  List<LExpr> exprs(List<LExpr> xs) => _list(xs, expr);

  LFuncDecl func(LFuncDecl d) {
    final body = block(d.body);
    return identical(body, d.body) ? d : LFuncDecl(d.name, d.params, body, isPublic: d.isPublic, typeParams: d.typeParams, codeName: d.codeName, src: d.src, type: d.type);
  }

  LDecl decl(LDecl d) {
    switch (d) {
      case LVarDecl():
        final init = expr(d.init);
        return identical(init, d.init) ? d : LVarDecl(d.name, init, isConst: d.isConst, isPublic: d.isPublic, src: d.src, type: d.type);
      case LFuncDecl():
        return func(d);
      case LClassDecl():
        final fields = _list(d.fields, (LFieldDecl f) {
          final init = f.init == null ? null : expr(f.init!);
          return identical(init, f.init) ? f : LFieldDecl(f.name, init, isPrivate: f.isPrivate, isStatic: f.isStatic, type: f.type);
        });
        final ctor = d.ctor == null ? null : func(d.ctor!);
        final methods = _list(d.methods, (LMethodDecl m) {
          final fn = func(m.fn);
          return identical(fn, m.fn) ? m : LMethodDecl(fn, isStatic: m.isStatic, isAbstract: m.isAbstract);
        });
        if (identical(fields, d.fields) && identical(ctor, d.ctor) && identical(methods, d.methods)) return d;
        return LClassDecl(
          d.name,
          parent: d.parent,
          interfaces: d.interfaces,
          fields: fields,
          ctor: ctor,
          methods: methods,
          typeParams: d.typeParams,
          isOpen: d.isOpen,
          isPublic: d.isPublic,
          codeName: d.codeName,
          src: d.src,
        );
      case LInterfaceDecl() || LNativeDecl() || LTypeDecl():
        return d;
    }
  }

  LTarget target(LTarget t) {
    switch (t) {
      case LTName():
        return t;
      case LTIndex():
        final of = expr(t.of), key = expr(t.key);
        return identical(of, t.of) && identical(key, t.key) ? t : LTIndex(of, key, src: t.src);
      case LTField():
        final of = expr(t.of);
        return identical(of, t.of) ? t : LTField(of, t.name, src: t.src);
    }
  }

  LStmt stmt(LStmt s) {
    if (identical(s, from)) {
      hit = true;
      return to as LStmt;
    }
    switch (s) {
      case LLet():
        final v = expr(s.value);
        return identical(v, s.value) ? s : LLet(s.name, v, isConst: s.isConst, kind: s.kind, src: s.src, type: s.type);
      case LAssign():
        final t = target(s.target), v = expr(s.value);
        return identical(t, s.target) && identical(v, s.value) ? s : LAssign(t, v, src: s.src);
      case LExprStmt():
        final e = expr(s.expr);
        return identical(e, s.expr) ? s : LExprStmt(e, src: s.src);
      case LIf():
        final arms = _list(s.arms, (LIfArm a) {
          final c = expr(a.cond), b = block(a.body);
          return identical(c, a.cond) && identical(b, a.body) ? a : LIfArm(c, b);
        });
        final orElse = block(s.orElse);
        return identical(arms, s.arms) && identical(orElse, s.orElse) ? s : LIf(arms, orElse: orElse, src: s.src);
      case LWhile():
        final c = s.cond == null ? null : expr(s.cond!), b = block(s.body);
        return identical(c, s.cond) && identical(b, s.body) ? s : LWhile(c, b, src: s.src);
      case LForCount():
        final a = expr(s.from), z = expr(s.to), st = expr(s.step), b = block(s.body);
        return identical(a, s.from) && identical(z, s.to) && identical(st, s.step) && identical(b, s.body) ? s : LForCount(s.name, a, z, st, b, src: s.src);
      case LForEach():
        final l = expr(s.list), b = block(s.body);
        return identical(l, s.list) && identical(b, s.body) ? s : LForEach(l, s.item, b, index: s.index, reuse: s.reuse, src: s.src);
      case LForPairs():
        final d = expr(s.dict), b = block(s.body);
        return identical(d, s.dict) && identical(b, s.body) ? s : LForPairs(d, s.key, s.value, b, src: s.src);
      case LRepeat():
        final t = expr(s.times), b = block(s.body);
        return identical(t, s.times) && identical(b, s.body) ? s : LRepeat(t, b, src: s.src);
      case LReturn():
        final v = s.value == null ? null : expr(s.value!);
        return identical(v, s.value) ? s : LReturn(v, src: s.src);
      case LThrow():
        final m = expr(s.message);
        return identical(m, s.message) ? s : LThrow(m, src: s.src);
      case LTry():
        final b = block(s.body), e = block(s.onError), f = block(s.finallyBody);
        if (identical(b, s.body) && identical(e, s.onError) && identical(f, s.finallyBody)) return s;
        return LTry(b, errorName: s.errorName, errorClass: s.errorClass, onError: e, finallyBody: f, src: s.src);
      case LMatch():
        final subject = expr(s.subject);
        final arms = _list(s.arms, (LMatchArm a) {
          final b = block(a.body);
          return identical(b, a.body) ? a : LMatchArm(a.caseName, a.binds, b);
        });
        final orElse = s.orElse == null ? null : block(s.orElse!);
        return identical(subject, s.subject) && identical(arms, s.arms) && identical(orElse, s.orElse) ? s : LMatch(subject, arms, orElse: orElse, src: s.src);
      case LBreak() || LContinue() || LHost() || LNote():
        return s;
    }
  }

  List<LFieldInit> _inits(List<LFieldInit> xs) => _list(xs, (LFieldInit f) {
    final v = expr(f.value);
    return identical(v, f.value) ? f : LFieldInit(f.name, v);
  });

  LExpr expr(LExpr e) {
    if (identical(e, from)) {
      hit = true;
      return to as LExpr;
    }
    switch (e) {
      case LLit() || LName() || LThis() || LEnumValue():
        return e;
      case LListLit():
        final items = exprs(e.items);
        return identical(items, e.items) ? e : LListLit(items, src: e.src);
      case LDictLit():
        final entries = _list(e.entries, (LDictEntry d) {
          final k = expr(d.key), v = expr(d.value);
          return identical(k, d.key) && identical(v, d.value) ? d : LDictEntry(k, v);
        });
        return identical(entries, e.entries) ? e : LDictLit(entries, src: e.src);
      case LField():
        final of = expr(e.of);
        return identical(of, e.of) ? e : LField(of, e.name, src: e.src);
      case LIndex():
        final of = expr(e.of), key = expr(e.key);
        return identical(of, e.of) && identical(key, e.key) ? e : LIndex(of, key, src: e.src);
      case LUnary():
        final x = expr(e.x);
        return identical(x, e.x) ? e : LUnary(e.op, x, src: e.src);
      case LBinary():
        final l = expr(e.l), r = expr(e.r);
        return identical(l, e.l) && identical(r, e.r) ? e : LBinary(e.op, l, r, src: e.src);
      case LLogic():
        final l = expr(e.l), r = expr(e.r);
        return identical(l, e.l) && identical(r, e.r) ? e : LLogic(e.op, l, r, src: e.src);
      case LCond():
        final c = expr(e.cond), t = expr(e.then), o = expr(e.orElse);
        return identical(c, e.cond) && identical(t, e.then) && identical(o, e.orElse) ? e : LCond(c, t, o, src: e.src);
      case LCall():
        final callee = expr(e.callee), args = exprs(e.args);
        return identical(callee, e.callee) && identical(args, e.args) ? e : LCall(callee, args, src: e.src);
      case LSend():
        final obj = expr(e.obj), args = exprs(e.args);
        return identical(obj, e.obj) && identical(args, e.args) ? e : LSend(obj, e.method, args, src: e.src);
      case LSuperSend():
        final args = exprs(e.args);
        return identical(args, e.args) ? e : (e.isCtor ? LSuperSend.ctor(args, src: e.src) : LSuperSend(e.method, args, src: e.src));
      case LNew():
        final args = exprs(e.args);
        return identical(args, e.args) ? e : LNew(e.cls, args, typeArgs: e.typeArgs, src: e.src);
      case LIsA():
        final x = expr(e.x);
        return identical(x, e.x) ? e : LIsA(x, e.cls, src: e.src);
      case LLambda():
        if (e.expr != null) {
          final x = expr(e.expr!);
          return identical(x, e.expr) ? e : LLambda.short(e.params, x, src: e.src);
        }
        final body = block(e.body);
        return identical(body, e.body) ? e : LLambda(e.params, body, src: e.src);
      case LAwait():
        final x = expr(e.x);
        return identical(x, e.x) ? e : LAwait(x, src: e.src);
      case LSpawn():
        final body = block(e.body);
        return identical(body, e.body) ? e : LSpawn(body, src: e.src);
      case LRt():
        final args = exprs(e.args);
        return identical(args, e.args) ? e : LRt(e.fn, args, src: e.src);
      case LNative():
        final args = exprs(e.args);
        return identical(args, e.args) ? e : LNative(e.name, args, src: e.src);
      case LRecordNew():
        final fields = _inits(e.fields);
        return identical(fields, e.fields) ? e : LRecordNew(e.record, fields, src: e.src);
      case LRecordCopy():
        final of = expr(e.of), fields = _inits(e.fields);
        return identical(of, e.of) && identical(fields, e.fields) ? e : LRecordCopy(of, fields, src: e.src);
      case LVariantNew():
        final args = exprs(e.args);
        return identical(args, e.args) ? e : LVariantNew(e.variant, e.caseName, args, src: e.src);
      case LCast():
        final x = expr(e.x);
        return identical(x, e.x) ? e : LCast(x, e.to, src: e.src);
      case LAscribe():
        final x = expr(e.x);
        return identical(x, e.x) ? e : LAscribe(x, e.to, src: e.src);
    }
  }
}
