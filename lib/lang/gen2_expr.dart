/// 规矩版本 2 的生成器·式子那一半（和语言无关的部分）：每个式子按它的类型写，在用到的地方按要的类型转换。
/// 骨架和语句在 gen2.dart。
library;

import 'package:lopicode/lang/ast.dart';
import 'package:lopicode/lang/gen2.dart';
import 'package:lopicode/lang/rt_v2.dart';
import 'package:lopicode/lang/type_world.dart';
import 'package:lopicode/lang/typecheck.dart';
import 'package:lopicode/lang/types.dart';

const LType _int = LType.integer;
const LType _flt = LType.number;
const LType _txt = LType.text;
const LType _bool = LType.boolean;
const LType _any = LType.any;

mixin Gen2Expr on Gen2Base {
  // —— 这种语言里怎么写 ——

  String nullLit();
  String boolLit(bool v);
  String intLit(int v);
  String floatLit(double v);
  String textLit(String v);
  String listLit(LType elem, List<String> items);
  String dictLit(LType value, List<(String, String)> entries);

  /// 把 [from] 类型的值变成 [to] 类型的（两个不一样；已经排除了“不用变”的情况）。
  String convert(String code, LType from, LType to);

  /// 有名字的函数当值用。
  String funcValue(LTypedSig f);
  String selfCode();

  /// [op]：ineg / fneg。
  String neg(String op, String a);

  /// 比大小。[kind]：i 整数、f 小数、t 文字、d 任意、g 泛型里“能比较”的 T；[cmp]：lt le gt ge。
  String compare(String kind, String cmp, String a, String b);

  /// 两个同一种类型的值相不相等（记录、变体按内容）。
  String eqSame(LType type, String a, String b);
  String isNullCode(String code, LType type);
  String notCode(String a);
  String logic(String op, String a, String b);
  String ternary(String cond, String a, String b, LType type);

  String listAt(String list, String index, LType elem);
  String dictGet(String dict, String key, LType value);
  String dynGet(String of, String key);
  /// 改一项 / 存一项（写成一个式子，不带句尾）。
  String listSetCode(String list, String index, String value, LType elem);
  String dictSetCode(String dict, String key, String value, LType valueType);
  String dynSetCode(String of, String key, String value);

  String callNamed(LTypedSig f, List<String> args, List<LType> typeArgs);
  String callValue(String f, List<String> args, LType ft);
  String dynCall(String f, List<String> args);

  /// 表里的小库函数（[kLangRtV2]）。[types] 是参数的类型（类型变量已经代进去），[ret] 是结果的类型。
  String rtCall(String fn, List<String> args, List<LType> types, LType ret, LRt e);

  /// 写成文字、连起来。
  String text(String code, LType type);
  String concat(List<String> parts);
  String logCode(String text);
  String sizeCode(String code, LType type);
  String orElseCode(String code, LType type, String def);
  String mustCode(String code, LType type);
  String pushCode(String list, String value, LType listType);
  String popCode(String list, LType listType);
  String dictRemoveCode(String dict, String key, LType dictType);
  String dynRt(String fn, List<String> args);

  String lambdaCode(LLambda e, LType ft, V2Fn inner);

  String recordNew(LRecordDecl d, LType type, List<String> values);
  String recordCopy(LRecordDecl d, LType type, String of, Map<String, String> changes);
  String fieldGet(String of, LType ofType, String name, LField e);
  String variantNew(LVariantDecl d, LVariantCase c, List<String> args);
  String newObject(LClassInfo c, LType type, List<String> args);
  String send(String obj, LType objType, String method, List<String> args, LSend e);
  String superCall(String method, List<String> args);
  String superCtor(List<String> args);
  String isA(String code, LType type, String cls);

  /// 向下转型（父类 → 子类 / 接口 → 类），不对就抛错。
  String downcast(String code, LType from, LType to);

  // —— 和语言无关的 ——

  static bool _isNull(LExpr e) => e is LLit && e.value == null;

  String lit(Object? v) => switch (v) {
    null => nullLit(),
    final bool b => boolLit(b),
    final int n => intLit(n),
    final double d => floatLit(d),
    final String s => textLit(s),
    _ => nullLit(),
  };

  @override
  String conv(String code, LType from, LType to) {
    if (from == to || to.isNever || to.isHole || from.isNever || from.isHole || to.isNul) return code;
    return convert(code, from, to);
  }

  @override
  String x(LExpr e, [LType? to]) {
    if (to != null) {
      if (e is LLit && e.value is int && to.kind == LKind.number) return conv(floatLit((e.value! as int).toDouble()), _flt, to);
      if (_isNull(e) && (to.nullable || to.isAny)) return nulOf(to);
      final tn = to.nonNull;
      if (e is LListLit && e.items.isEmpty && tn.kind == LKind.list) return conv(listLit(tn.of ?? _any, const []), tn, to);
      if (e is LDictLit && e.entries.isEmpty && tn.kind == LKind.dict) return conv(dictLit(tn.of ?? _any, const []), tn, to);
    }
    final code = raw(e);
    return to == null ? code : conv(code, t(e), to);
  }

  String raw(LExpr e) {
    switch (e) {
      case LLit(:final value):
        return lit(value);
      case LListLit(:final items):
        final lt = t(e).nonNull;
        final elem = lt.kind == LKind.list ? lt.of ?? _any : _any;
        final code = listLit(elem, [for (final i in items) x(i, elem)]);
        return lt.kind == LKind.list ? conv(code, lt, t(e)) : conv(code, LType.listOf(elem), t(e));
      case LDictLit(:final entries):
        final dt = t(e).nonNull;
        final vt = dt.kind == LKind.dict ? dt.of ?? _any : _any;
        final code = dictLit(vt, [for (final p in entries) (x(p.key, _txt), x(p.value, vt))]);
        return dt.kind == LKind.dict ? conv(code, dt, t(e)) : conv(code, LType.dictOf(vt), t(e));
      case LName(:final name, :final kind):
        if (kind == LNameKind.host) unsupported('宿主给的名字「$name」', e);
        final v = lookup(name);
        if (v != null) return conv(varCode(v), v.type, t(e));
        final f = r.funcs[name];
        if (f != null && w.funcs.containsKey(name)) return funcValue(f);
        unsupported('找不到「$name」', e);
      case LIndex(:final of, :final key):
        return _index(e, of, key);
      case LUnary(:final op, :final x):
        if (op == 'not') return notCode(this.x(x, _bool));
        if (t(x).isAny) return arith('dsub', conv(intLit(0), _int, _any), this.x(x, _any));
        final o = r.opOf(e) ?? 'fneg';
        return neg(o, this.x(x, o == 'ineg' ? _int : _flt));
      case LBinary():
        return _binary(e);
      case LLogic(:final op, :final l, :final r):
        return logic(op, x(l, _bool), x(r, _bool));
      case LCond(:final cond, :final then, :final orElse):
        return ternary(x(cond, _bool), x(then, t(e)), x(orElse, t(e)), t(e));
      case LCall():
        return _call(e);
      case LLambda():
        final ft = t(e).nonNull;
        final key = r.lambdaScope(e) ?? unsupported('这个匿名函数没有经过类型检查', e);
        return lambdaCode(e, ft, V2Fn(key, ft.hasShape ? ft.returns : _any, parent: fn, lambda: e));
      case LRt():
        return _rt(e);
      case LField(:final of, :final name):
        final ot = t(of).nonNull;
        if (!ot.isNamed) unsupported('取字段「$name」：前面的值是${ot.show()}，不是记录也不是对象', e);
        return conv(fieldGet(x(of, ot), ot, name, e), fieldType(ot, name, e), t(e));
      case LSend():
        return _send(e);
      case LSuperSend(:final method, :final args):
        final parent = w.classes[fn.owner?.decl.parent];
        if (parent == null) unsupported('这里没有父类', e);
        if (e.isCtor) {
          final sig = r.funcs[w.classCtor(parent)?.key];
          return superCtor([for (var i = 0; i < args.length; i++) x(args[i], sig != null && i < sig.params.length ? sig.params[i] : null)]);
        }
        final got = w.classMethod(parent, method) ?? unsupported('父类没有「$method」这个方法', e);
        final sig = r.funcs[got.$1.key]!;
        return conv(superCall(method, [for (var i = 0; i < args.length; i++) x(args[i], i < sig.params.length ? sig.params[i] : null)]), sig.returns, t(e));
      case LNew(:final cls, :final args):
        final c = w.classes[cls] ?? unsupported('没有叫「$cls」的类', e);
        final ot = t(e).nonNull;
        final sig = r.funcs[w.classCtor(c)?.key];
        final b = typeArgsOfType(ot);
        return newObject(c, ot, [for (var i = 0; i < args.length; i++) x(args[i], sig != null && i < sig.params.length ? w.subst(sig.params[i], b) : null)]);
      case LIsA(x: final v, :final cls):
        return isA(x(v), t(v), cls);
      case LThis():
        return selfCode();
      case LRecordNew(:final record, :final fields):
        final d = w.records[record] ?? unsupported('没有叫「$record」的记录', e);
        final rt = t(e).nonNull;
        return recordNew(d, rt, [
          for (final f in d.fields)
            () {
              final ft = fieldType(rt, f.name, e);
              final init = fields.where((i) => i.name == f.name).firstOrNull;
              return init == null ? nulOf(ft) : x(init.value, ft);
            }(),
        ]);
      case LRecordCopy(:final of, :final fields):
        final ot = t(of).nonNull;
        final d = w.records[ot.name] ?? unsupported('“复制并改”只能用在记录上', e);
        return recordCopy(d, ot, x(of, ot), {for (final f in fields) f.name: x(f.value, fieldType(ot, f.name, e))});
      case LEnumValue(:final enumName, :final caseName):
        return enumCode(w.enums[enumName] ?? unsupported('没有叫「$enumName」的枚举', e), caseName);
      case LVariantNew(:final variant, :final caseName, :final args):
        final d = w.variants[variant] ?? unsupported('没有叫「$variant」的变体', e);
        final c = d.cases.where((c) => c.name == caseName).firstOrNull ?? unsupported('「$variant」没有「$caseName」这种情况', e);
        return variantNew(d, c, [for (var i = 0; i < args.length && i < c.fields.length; i++) x(args[i], w.resolve(c.fields[i].type))]);
      case LCast(x: final v):
        final from = t(v), to = t(e);
        if (from == to) return x(v);
        if (from.nullable && from.nonNull == to) return mustCode(x(v), from);
        if (!from.isAny && from.isNamed && to.isNamed && from.name != to.name) return downcast(x(v), from, to);
        return x(v, to);
      case LAscribe(x: final v):
        return x(v, t(e));
      case LNative(:final name):
        unsupported('宿主函数「$name」：带类型的独立模块里还不能调宿主函数', e);
      case LAwait() || LSpawn():
        unsupported('异步（核心 3 才有）', e);
    }
  }

  String _index(LNode node, LExpr of, LExpr key) {
    final ot = t(of).nonNull;
    final want = node is LExpr ? t(node) : _any;
    switch (r.opOf(node)) {
      case 'listAt':
        final elem = ot.of ?? _any;
        return conv(listAt(x(of, ot), x(key, _int), elem), elem, want);
      case 'dictGet':
        final vt = ot.of ?? _any;
        return conv(dictGet(x(of, ot), x(key, _txt), vt), vt.orNull, want);
      case 'dynGet':
        return conv(dynGet(x(of, _any), x(key, _any)), _any, want);
    }
    unsupported('取一项：前面的值是${ot.show()}，不是列表也不是字典', node);
  }

  String _store(LNode node, LExpr of, LExpr key, LExpr value) {
    final ot = t(of).nonNull;
    switch (r.opOf(node)) {
      case 'listSetAt':
        final elem = ot.of ?? _any;
        return listSetCode(x(of, ot), x(key, _int), x(value, elem), elem);
      case 'dictSet':
        final vt = ot.of ?? _any;
        return dictSetCode(x(of, ot), x(key, _txt), x(value, vt), vt);
      case 'dynSet':
        return dynSetCode(x(of, _any), x(key, _any), x(value, _any));
    }
    unsupported('改一项：前面的值是${ot.show()}，不是列表也不是字典', node);
  }

  @override
  List<String> storeIndex(LAssign s, LTIndex target) => exprStmt(_store(r.opOf(s) != null ? s : target, target.of, target.key, s.value), isVoid: true);

  static const Map<String, LType> _arithType = {'i': _int, 'f': _flt, 'd': _any};

  String _binary(LBinary e) {
    if (e.op == '==' || e.op == '!=') {
      final res = _eq(e.l, e.r);
      return e.op == '==' ? res : notCode(res);
    }
    final op = r.opOf(e) ?? unsupported('运算「${e.op}」没有定下来怎么算', e);
    final k = op[0], rest = op.substring(1);
    if (const {'lt', 'le', 'gt', 'ge'}.contains(rest)) {
      if (k == 'd') {
        final tv = [t(e.l), t(e.r)].where((x) => x.kind == LKind.typeVar).firstOrNull;
        if (tv != null) return compare('g', rest, x(e.l, tv), x(e.r, tv));
      }
      final ot = k == 't' ? _txt : _arithType[k]!;
      return compare(k, rest, x(e.l, ot), x(e.r, ot));
    }
    final ot = _arithType[k] ?? unsupported('不认识的运算 $op', e);
    return conv(arith(op, x(e.l, ot), x(e.r, ot)), ot, t(e));
  }

  String _eq(LExpr l, LExpr r) {
    final lt = t(l), rt = t(r);
    if (_isNull(l) || _isNull(r)) {
      final other = _isNull(l) ? r : l;
      return _isNull(other) ? boolLit(true) : isNullCode(x(other), t(other));
    }
    if (lt == rt) return eqSame(lt, x(l), x(r));
    if (lt.nonNull == rt.nonNull && !lt.isAny) {
      final nt = lt.nullable ? lt : rt;
      return eqSame(nt, x(l, nt), x(r, nt));
    }
    if (lt.isNumber && rt.isNumber) return eqSame(_flt, x(l, _flt), x(r, _flt));
    return eqSame(_any, x(l, _any), x(r, _any));
  }

  String _call(LCall e) {
    final callee = e.callee;
    if (callee is LName && callee.kind == LNameKind.variable && lookup(callee.name) == null) {
      final sig = r.funcs[callee.name];
      if (sig != null && w.funcs.containsKey(callee.name)) {
        final b = r.typeArgsOf(e) ?? const <String, LType>{};
        final ps = sig.info.params;
        if (ps.any((p) => p.rest)) unsupported('“剩下的全收”的参数（带类型的生成路径里还没有）', e);
        final args = <String>[];
        for (var i = 0; i < ps.length; i++) {
          final pt = w.subst(sig.params[i], b);
          if (i < e.args.length) {
            args.add(x(e.args[i], pt));
          } else {
            final d = ps[i].defaultValue;
            args.add(d is LLit ? x(d, pt) : nulOf(pt));
          }
        }
        final code = callNamed(sig, args, [for (final v in sig.info.own) b[v] ?? _any]);
        return conv(code, w.subst(sig.returns, b), t(e));
      }
    }
    final ft = t(callee).nonNull;
    if (ft.kind == LKind.fn && ft.hasShape) {
      final ps = ft.params;
      return conv(callValue(x(callee, ft), [for (var i = 0; i < e.args.length; i++) x(e.args[i], i < ps.length ? ps[i] : null)], ft), ft.returns, t(e));
    }
    return conv(dynCall(x(callee, _any), [for (final a in e.args) x(a, _any)]), _any, t(e));
  }

  String _send(LSend e) {
    final ot = t(e.obj).nonNull;
    var params = const <LType>[];
    var ret = _any;
    if (ot.kind == LKind.interface) {
      final m = w.interfaces[ot.name]?.methods.where((m) => m.name == e.method).firstOrNull ?? unsupported('「${ot.name}」没有「${e.method}」这个方法', e);
      params = [for (final p in m.params) w.resolve(p.type)];
      ret = w.resolve(m.returns ?? LType.nul);
    } else if (ot.kind == LKind.object && w.classes.containsKey(ot.name)) {
      final got = w.classMethod(w.classes[ot.name], e.method) ?? unsupported('「${ot.name}」没有「${e.method}」这个方法', e);
      final sig = r.funcs[got.$1.key]!;
      final b = {...typeArgsOfType(ot), ...?r.typeArgsOf(e)};
      params = [for (final p in sig.params) w.subst(p, b)];
      ret = w.subst(sig.returns, b);
    } else {
      unsupported('调方法「${e.method}」：前面的值是${ot.show()}，不是对象', e);
    }
    final args = [for (var i = 0; i < e.args.length; i++) x(e.args[i], i < params.length ? params[i] : null)];
    return conv(send(x(e.obj, ot), ot, e.method, args, e), ret, t(e));
  }

  String _rt(LRt e) {
    final a = e.args;
    LType at(int i) => t(a[i]);
    switch (e.fn) {
      case 'join':
        return a.isEmpty ? textLit('') : concat([for (final v in a) text(x(v), t(v))]);
      case 'toText' when a.length == 1:
        return text(x(a[0]), at(0));
      case 'size' when a.length == 1:
        return sizeCode(x(a[0], at(0).nonNull), at(0).nonNull);
      case 'log':
        return logCode(a.isEmpty ? textLit('') : concat([for (final v in a) text(x(v), t(v))]));
      case 'isNull' when a.length == 1:
        return isNullCode(x(a[0]), at(0));
      case 'orElse' when a.length == 2:
        final want = t(e);
        if (!at(0).nullable && !at(0).isAny) return x(a[0], want);
        if (at(0).isAny) return conv(dynRt('orElse', [x(a[0]), x(a[1], _any)]), _any, want);
        return orElseCode(x(a[0], want.orNull), want.orNull, x(a[1], want));
      case 'must' when a.length == 1:
        if (!at(0).nullable && !at(0).isAny) return x(a[0]);
        return conv(mustCode(x(a[0]), at(0)), at(0).nonNull, t(e));
      case 'listPush' when a.length == 2:
        if (r.opOf(e) == 'dynPush' || at(0).nonNull.kind != LKind.list) return dynRt('push', [x(a[0], _any), x(a[1], _any)]);
        final lt = at(0).nonNull;
        return pushCode(x(a[0], lt), x(a[1], lt.of ?? _any), lt);
      case 'listPop' when a.length == 1:
        final lt = at(0).nonNull;
        if (lt.kind != LKind.list) return conv(dynRt('pop', [x(a[0], _any)]), _any, t(e));
        return conv(popCode(x(a[0], lt), lt), (lt.of ?? _any).orNull, t(e));
      case 'listGet' || 'dictGet' || 'item' when a.length == 2:
        return _index(e, a[0], a[1]);
      case 'listSet' || 'dictSet' || 'setItem' when a.length == 3:
        return _store(e, a[0], a[1], a[2]);
      case 'dictRemove' when a.length == 2:
        final dt = at(0).nonNull;
        if (dt.kind != LKind.dict) return dynRt('remove', [x(a[0], _any), x(a[1], _any)]);
        return dictRemoveCode(x(a[0], dt), x(a[1], _txt), dt);
    }
    final sig = kLangRtV2[e.fn] ?? unsupported('小库函数「${e.fn}」在带类型的生成路径里还没有', e);
    final b = r.typeArgsOf(e) ?? const <String, LType>{};
    final types = [for (final p in sig.params) w.subst(p, b)];
    if (a.length != types.length) unsupported('「${sig.label}」要 ${types.length} 个参数，给了 ${a.length} 个', e);
    final ret = w.subst(sig.ret, b);
    return conv(rtCall(e.fn, [for (var i = 0; i < a.length; i++) x(a[i], types[i])], types, ret, e), ret, t(e));
  }
}

/// 一种语言的版本 2 生成器＝骨架＋式子。
abstract class Gen2 extends Gen2Base with Gen2Expr {
  Gen2(super.module, super.r);

  /// 这种语言的小库文件（相对路径 → 内容），和 [program] 生成的主文件放在一起就能跑。
  Map<String, String> get runtimeFiles;

  /// 主文件叫什么。
  String get mainFile;
}
