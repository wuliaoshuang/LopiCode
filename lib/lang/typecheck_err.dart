part of 'typecheck.dart';

/// 错误是对象（核心 2）：“抛出”、“试着做 / 出错时 / 最后”。规则 T19（抛出、接住的不是错误）、T21（这一节永远轮不到）。
mixin _Errs on _Core {
  static const LType _errT = LType(LKind.object, name: kErrBase);

  /// 是不是错误对象（内置“错误”类或者它下面的类）。
  @override
  bool isErr(LType t) => w.isClass(t) && w.supers(t.name).contains(kErrBase);

  @override
  LType? narrowed(_Scope sc, String name) {
    for (_Scope? x = sc; x != null; x = x.parent) {
      final n = x.narrow[name];
      if (n != null) return n;
      if (x.names.contains(name)) return null;
    }
    return null;
  }

  @override
  void throwStmt(_Scope sc, LThrow s) {
    sawErrors = true;
    final t = w.res(ex(sc, s.value));
    if (isErr(t)) {
      op(s, 'throwObj');
      return;
    }
    if (t.nullable && isErr(t.nonNull)) {
      final nm = s.value is LName ? '「${(s.value as LName).name}」' : '这个值';
      err('T02', sc, '“抛出”后面要一个错误，$nm可能是空，要先判断“不是空”', node: s.value, fixes: [LFix(LFixKind.wrapMust, '一定不是空', target: s.value)]);
      return;
    }
    if (t == _txt || t.isAny || t.isNever) {
      want(s.value, _txt); // 一句话：自动包成内置的“错误”。任意：运行时查它是不是文字。
      return;
    }
    err('T19', sc, '“抛出”后面要一句话或者一个错误，放进来的是${t.show()}', node: s.value, fixes: t.nullable || t.isNul ? const [] : [LFix(LFixKind.wrapToText, '变成文字', target: s.value)]);
  }

  @override
  void tryStmt(_Scope sc, LTry s) {
    sawErrors = true;
    final keep = {...sc.nn};
    block(sc, s.body);
    sc.nn = keep.intersection(sc.nn);
    final before = <String?>[]; // 前面几节各接什么（null＝什么都接）
    for (final c in s.catches) {
      var kt = _errT;
      final kind = c.kind;
      if (kind != null) {
        final t = LType(LKind.object, name: kind);
        final known = w.classes.containsKey(kind) || w.records.containsKey(kind) || w.enums.containsKey(kind) || w.variants.containsKey(kind) || w.interfaces.containsKey(kind) || w.aliases.containsKey(kind);
        if (isErr(t)) {
          kt = t;
        } else if (known) {
          err('T19', sc, '“出错时”只能接错误的种类（“错误”或者父类是它的类），「$kind」不是', node: s);
        } else {
          err('T19', sc, '“出错时”要接的「$kind」不存在：没有叫这个名字的错误种类', node: s);
        }
      }
      final shadow = before.where((b) => b == null || b == kErrBase || w.supers(kt.name).contains(b)).firstOrNull;
      if (shadow != null || before.contains(null)) {
        final by = shadow == null || shadow == kErrBase ? '什么错误都接' : '接「$shadow」';
        err('T21', sc, '这一节“出错时”（接「${kt.name}」）永远轮不到：它前面有一节$by，已经把它接走了', node: s);
      }
      before.add(kind);
      final name = c.name;
      final old = name == null ? null : sc.narrow[name];
      if (name != null) {
        declare(sc, name, kt, kind: LVarKind.error);
        sc.narrow[name] = kt;
      }
      final nn = {...sc.nn};
      block(sc, c.body);
      sc.nn = nn.intersection(sc.nn);
      if (name != null) {
        if (old == null) {
          sc.narrow.remove(name);
        } else {
          sc.narrow[name] = old;
        }
      }
    }
    block(sc, s.finallyBody);
  }
}
