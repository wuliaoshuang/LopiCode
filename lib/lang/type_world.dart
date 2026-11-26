/// 规矩版本 2 的类型运算：声明表（记录、枚举、变体、接口、类、函数、别名）＋合并、能不能放、代入、定“待定”。
///
/// 设计：docs/blocks-v5-parts/B-type-system.md 第 2、3、4 节。算法照推断原型 docs/blocks-v5-prototypes/types/infer.py，
/// 一处有意的不同：两个同名的泛型类型合并时保留类型实参（原型会丢掉）。
library;

import 'package:lopicode/lang/ast.dart';
import 'package:lopicode/lang/types.dart';

/// 一个函数 / 方法 /“创建时”在检查器眼里的样子。
class LTypedFunc {
  LTypedFunc({
    required this.key,
    required this.name,
    required this.typeVars,
    required this.own,
    required this.bounds,
    required this.params,
    required this.ret,
    required this.body,
    this.decl,
    this.owner,
  });

  /// 记号：函数是名字，方法是“类.方法”，创建时是“类.创建”。
  final String key;
  final String name;

  /// 看得见的类型变量（类的＋自己的）。
  final List<String> typeVars;

  /// 自己带的类型变量。
  final List<String> own;

  /// 类型变量的约束（见 [LTypeParam.bound]）。
  final Map<String, String> bounds;
  final List<LParam> params;

  /// 标的返回类型；null＝没标。
  final LType? ret;
  final List<LStmt> body;
  final LFuncDecl? decl;

  /// 方法、创建时属于哪个类。
  final String? owner;

  int get minArgs => params.where((p) => !p.rest && p.defaultValue == null).length;
  bool get hasRest => params.any((p) => p.rest);
}

class LClassInfo {
  LClassInfo(this.decl);
  final LClassDecl decl;
  String get name => decl.name;
  List<String> get typeVars => [for (final p in decl.typeParams) p.name];
  final Map<String, LTypedFunc> methods = {};
  LTypedFunc? ctor;
}

class LTypeWorld {
  final Map<String, LRecordDecl> records = {};
  final Map<String, LEnumDecl> enums = {};
  final Map<String, LVariantDecl> variants = {};
  final Map<String, LInterfaceDecl> interfaces = {};
  final Map<String, LClassInfo> classes = {};
  final Map<String, LTypedFunc> funcs = {};
  final Map<String, LAliasDecl> aliases = {};

  /// “待定”的洞现在定成了什么（没有＝还没定）。
  final Map<String, LType> holes = {};

  /// 这一遍里有没有东西变了（推断反复算到不变）。
  bool changed = false;

  static bool isOpt(LType t) => t.nullable;
  static bool isHole(LType t) => t.kind == LKind.hole && !t.nullable;
  static bool isVar(LType t) => t.kind == LKind.typeVar && !t.nullable;
  static bool isList(LType t) => t.kind == LKind.list && !t.nullable;
  static bool isDict(LType t) => t.kind == LKind.dict && !t.nullable;
  static bool isFn(LType t) => t.kind == LKind.fn && !t.nullable;
  static bool isName(LType t) => t.isNamed && !t.nullable;
  static bool isAny(LType t) => t.kind == LKind.any;
  static bool isNever(LType t) => t.kind == LKind.never;
  static LType elem(LType t) => t.of ?? LType.any;

  bool isRecord(LType t) => isName(t) && t.kind == LKind.record;
  bool isClass(LType t) => isName(t) && t.kind == LKind.object && classes.containsKey(t.name);
  bool isInterface(LType t) => isName(t) && t.kind == LKind.interface;

  /// 把标注里写的类型认出来：名字 → 类型变量 / 别名 / 记录 / 枚举 / 变体 / 接口 / 类。[typeVars] 是这里看得见的类型变量。
  LType resolve(LType? s, [List<String> typeVars = const [], int depth = 0]) {
    if (s == null) return LType.any;
    final n = s.nullable;
    LType out;
    switch (s.kind) {
      case LKind.list || LKind.dict || LKind.future:
        out = LType(s.kind, of: resolve(s.of, typeVars, depth));
      case LKind.fn:
        out = LType(LKind.fn, args: [for (final a in s.args) resolve(a, typeVars, depth)], waits: s.waits);
      case LKind.typeVar:
        out = LType(LKind.typeVar, name: s.name);
      case LKind.object || LKind.record || LKind.enumeration || LKind.variant || LKind.interface:
        final name = s.name;
        if (name == null) {
          out = LType.any; // 老的“对象”（不知道是哪个类）：按任意。
        } else if (typeVars.contains(name)) {
          out = LType(LKind.typeVar, name: name);
        } else if (aliases.containsKey(name) && depth < 20) {
          out = resolve(aliases[name]!.target, typeVars, depth + 1);
        } else {
          final kind = records.containsKey(name)
              ? LKind.record
              : enums.containsKey(name)
              ? LKind.enumeration
              : variants.containsKey(name)
              ? LKind.variant
              : interfaces.containsKey(name)
              ? LKind.interface
              : LKind.object;
          out = LType(kind, name: name, args: [for (final a in s.args) resolve(a, typeVars, depth)]);
        }
      default:
        out = LType(s.kind);
    }
    return n ? out.orNull : out;
  }

  /// 标注里用到的名字是不是都有（没有的那个名字；都有＝null）。
  String? unknownName(LType? s, List<String> typeVars) {
    if (s == null) return null;
    final r = resolve(s, typeVars);
    String? bad;
    r.anyPart((t) {
      if (t.kind == LKind.object && t.name != null && !classes.containsKey(t.name)) bad ??= t.name;
      return false;
    });
    return bad;
  }

  /// 把已经定下来的“待定”换成它的类型。
  LType res(LType t) {
    if (t.kind == LKind.hole) {
      final b = holes[t.name];
      if (b == null || isNever(b)) return t;
      final r = res(b);
      return t.nullable ? r.orNull : r;
    }
    if (t.of == null && t.args.isEmpty) return t;
    final r = t.nonNull.mapParts(res);
    return t.nullable ? r.orNull : r;
  }

  /// 把类型变量换成 [b] 里的类型。
  LType subst(LType t, Map<String, LType> b) {
    if (t.kind == LKind.typeVar) {
      final r = b[t.name];
      if (r == null) return t;
      return t.nullable ? r.orNull : r;
    }
    if (t.of == null && t.args.isEmpty) return t;
    final r = t.nonNull.mapParts((x) => subst(x, b));
    return t.nullable ? r.orNull : r;
  }

  /// 一个类所有的“上面”：自己、父类链，以及它们实现的接口。
  List<String> supers(String? name) {
    final out = <String>[];
    var c = classes[name];
    var guard = 0;
    while (c != null && guard++ < 64) {
      out.add(c.name);
      out.addAll(c.decl.interfaces);
      c = classes[c.decl.parent];
    }
    return out;
  }

  /// 合并两个类型（一个变量被放过两种东西时它是什么）。
  LType join(LType a0, LType b0) {
    final a = res(a0), b = res(b0);
    if (a == b) return a;
    if (isNever(a) || isHole(a)) return b;
    if (isNever(b) || isHole(b)) return a;
    if (isAny(a) || isAny(b)) return LType.any;
    if ((a == LType.integer && b == LType.number) || (a == LType.number && b == LType.integer)) return LType.number;
    if (a.isNul) return b.orNull;
    if (b.isNul) return a.orNull;
    if (a.nullable || b.nullable) return join(a.nonNull, b.nonNull).orNull;
    if (a.kind == LKind.fn && b.kind == LKind.fn && a.hasShape && a.args.length == b.args.length) {
      // 要不要等：有一边要等＝要等；都规定了不等＝不等；别的＝没说。
      final waits = a.waits == true || b.waits == true ? true : (a.waits == false && b.waits == false ? false : null);
      return LType(LKind.fn, args: [for (var i = 0; i < a.args.length; i++) join(a.args[i], b.args[i])], waits: waits);
    }
    if (a.kind == b.kind && (a.kind == LKind.list || a.kind == LKind.dict)) {
      final ia = elem(a), ib = elem(b);
      if (isHole(ia) || isNever(ia)) return b;
      if (isHole(ib) || isNever(ib)) return a;
      return LType.any; // 两个都已经定下来、又不一样的列表：合不到一起。
    }
    if (a.isNamed && b.isNamed) {
      if (a.name == b.name && a.kind == b.kind && a.args.length == b.args.length) {
        // 同一个泛型类型：类型实参一个个合（有一边还待定就用另一边；都定了又不一样就合不到一起）。
        final args = <LType>[];
        for (var i = 0; i < a.args.length; i++) {
          final x = a.args[i], y = b.args[i];
          if (x == y || isHole(y) || isNever(y)) {
            args.add(x);
          } else if (isHole(x) || isNever(x)) {
            args.add(y);
          } else {
            return LType.any;
          }
        }
        return LType(a.kind, name: a.name, args: args);
      }
      final sa = supers(a.name), sb = supers(b.name);
      for (final s in sa) {
        if (sb.contains(s) && classes.containsKey(s)) return LType(LKind.object, name: s); // 最近的公共父类
      }
      final both = {
        for (final s in sa)
          if (sb.contains(s) && interfaces.containsKey(s)) s,
      };
      if (both.length == 1) return LType(LKind.interface, name: both.first); // 正好共同实现一个接口
    }
    return LType.any;
  }

  /// [src] 能不能放进要 [dst] 的地方。任意 → 确定类型：允许（运行时查一次）。
  bool ok(LType src0, LType dst0) {
    final src = res(src0), dst = res(dst0);
    if (!waitEscaped && isAny(dst) && src.anyPart((x) => x.kind == LKind.fn && x.waits == true)) _escape();
    if (src == dst || isAny(dst) || isNever(dst) || isNever(src) || isAny(src) || isHole(src) || isHole(dst)) return true;
    if (src == LType.integer && dst == LType.number) return true;
    if (dst.nullable) return src.isNul || ok(src.nonNull, dst.nonNull);
    if (src.nullable) return false;
    if (src.isNamed && dst.isNamed) {
      if (src.name != dst.name) return supers(src.name).contains(dst.name);
      for (var i = 0; i < src.args.length && i < dst.args.length; i++) {
        if (!same(src.args[i], dst.args[i])) return false;
      }
      return true;
    }
    if (src.kind == LKind.fn && dst.kind == LKind.fn) {
      // 要等的函数放进“没说要不要等”的地方：记下来（见 waitEscaped）。放进“规定不等”的地方由检查器另报（T30），这里不算类型不对。
      if (src.waits == true && dst.waits == null) _escape();
      if (!src.hasShape || !dst.hasShape) return true;
      if (src.args.length != dst.args.length) return false;
      for (var i = 0; i < src.params.length; i++) {
        // 参数是反着看的。里面一层没有 T30 管着：要等的（或者说不准的）函数会被放进只收不用等的函数的参数里＝对不上。
        final from = res(dst.params[i]), to = res(src.params[i]);
        if (from.kind == LKind.fn && to.kind == LKind.fn && to.waits == false && (from.waits == true || (from.waits == null && waitEscaped))) return false;
        if (!ok(from, to)) return false;
      }
      return dst.returns.isNul || ok(src.returns, dst.returns);
    }
    if (src.kind == dst.kind && (src.kind == LKind.list || src.kind == LKind.dict || src.kind == LKind.future)) return same(elem(src), elem(dst));
    return false;
  }

  bool same(LType a0, LType b0) {
    final a = res(a0), b = res(b0);
    if (a == b || isHole(a) || isHole(b) || isNever(a) || isNever(b)) return true;
    // 只差在“要不要等”上、而且有一边没说的：算一样（要等的那边混进了没说的地方，记下来）。
    if (!_sameButWaits(a, b)) return false;
    if (a.anyPart((x) => x.kind == LKind.fn && x.waits == true) || b.anyPart((x) => x.kind == LKind.fn && x.waits == true)) _escape();
    return true;
  }

  /// 有没有“要等”的函数值混进了“没说要不要等”的地方（没标的函数类型、任意）。混进去过＝凡是调“没说”的函数值都得当它可能要等；
  /// 一次都没有＝这种调用肯定不用等。只会从否变成是。核心 3，见 typecheck_wait.dart。
  bool waitEscaped = false;

  void _escape() {
    if (waitEscaped) return;
    waitEscaped = true;
    changed = true;
  }

  static bool _sameButWaits(LType a, LType b) {
    if (a.kind != b.kind || a.name != b.name || a.nullable != b.nullable || a.args.length != b.args.length || (a.of == null) != (b.of == null)) return false;
    if (a.kind == LKind.fn && a.waits != b.waits && a.waits != null && b.waits != null) return false;
    if (a.of != null && !_sameButWaits(a.of!, b.of!)) return false;
    for (var i = 0; i < a.args.length; i++) {
      if (!_sameButWaits(a.args[i], b.args[i])) return false;
    }
    return true;
  }

  /// 用实际类型 [act] 去定 [pat] 里的类型变量（记进 [b]）和待定的洞。
  void unify(LType pat, LType act0, Map<String, LType> b) {
    final act = res(act0);
    if (isNever(act)) return;
    if (isVar(pat) && b.containsKey(pat.name)) {
      b[pat.name!] = join(b[pat.name]!, act);
    } else if (isHole(pat)) {
      bind(pat.name!, act);
    } else if (isHole(act)) {
      final p = res(subst(pat, b));
      if (!hasOpen(p)) bind(act.name!, p);
    } else if (pat.nullable) {
      unify(pat.nonNull, act.isNul ? LType.never : act.nonNull, b);
    } else if ((pat.kind == LKind.list || pat.kind == LKind.dict || pat.kind == LKind.future) && act.kind == pat.kind && !act.nullable) {
      unify(elem(pat), elem(act), b);
    } else if (pat.kind == LKind.fn && isFn(act) && pat.args.length == act.args.length) {
      final last = pat.args.length - 1;
      for (var i = 0; i < pat.args.length; i++) {
        // 参数的位置是“反着”的：函数肯收更宽的东西（比如“任意”）不该把别的参数已经定下来的类型变量撑宽——
        // 不然“映射(整数的列表, 收任意的函数)”会被说成“要任意的列表”。还没定下来的照旧从这里定。
        final p = pat.args[i];
        if (i < last && isVar(p) && b.containsKey(p.name) && !isNever(b[p.name]!)) continue;
        unify(p, act.args[i], b);
      }
    } else if (pat.isNamed && isName(act) && pat.name == act.name) {
      for (var i = 0; i < pat.args.length && i < act.args.length; i++) {
        unify(pat.args[i], act.args[i], b);
      }
    }
  }

  /// 里面还有没定的东西吗（类型变量、待定、永不）。
  bool hasOpen(LType t) => t.anyPart((x) => x.kind == LKind.typeVar || x.kind == LKind.hole || x.kind == LKind.never);

  bool hasHole(LType t) => t.anyPart((x) => x.kind == LKind.hole);

  void bind(String hole, LType t) {
    final old = holes[hole] ?? LType.never;
    final now = join(old, t);
    if (now != old) {
      holes[hole] = now;
      changed = true;
    }
  }

  /// 收尾：还待定的、永不的，一律当成“任意”。
  LType close(LType t0) {
    final t = res(t0);
    if (t.kind == LKind.hole || t.kind == LKind.never) return LType.any;
    if (t.of == null && t.args.isEmpty) return t;
    final r = t.nonNull.mapParts(close);
    return t.nullable ? r.orNull : r;
  }

  /// 类 [c]（或它的父类）里叫 [name] 的字段：类型（还带着类自己的类型变量）和它是哪个类的。
  (LType, LClassInfo)? classField(LClassInfo? c, String name) {
    var guard = 0;
    while (c != null && guard++ < 64) {
      for (final f in c.decl.fields) {
        if (f.name == name && !f.isStatic) return (resolve(f.type, c.typeVars), c);
      }
      c = classes[c.decl.parent];
    }
    return null;
  }

  /// 类 [c]（或它的父类）里叫 [name] 的方法。
  (LTypedFunc, LClassInfo)? classMethod(LClassInfo? c, String name) {
    var guard = 0;
    while (c != null && guard++ < 64) {
      final m = c.methods[name];
      if (m != null) return (m, c);
      c = classes[c.decl.parent];
    }
    return null;
  }

  /// 类 [c] 用哪个“创建时”（自己没有就用父类的）。
  LTypedFunc? classCtor(LClassInfo? c) {
    var guard = 0;
    while (c != null && guard++ < 64) {
      if (c.ctor != null) return c.ctor;
      c = classes[c.decl.parent];
    }
    return null;
  }
}
