/// 语言核心的类型。
///
/// 两代并存（设计稿 docs/blocks-v5-parts/B-type-system.md 第 2、10.1 节）：
/// - **规矩版本 1**（旧文档）：只用老的 10 个标签，[LType.join]／[LType.clashesWith] 是老的宽松算法，生成时全部按“任意”。这部分一个字没动。
/// - **规矩版本 2**（新文档）：标签＋类型参数＋名字。新加 8 个标签（整数、记录、枚举、变体、接口、类型变量、永不、待定）；
///   合并、能不能放、代入这些算法要查声明表（类的继承、接口），在 type_world.dart 的 `LTypeWorld` 里，不在这里。
///
/// 类型参数放在哪：
/// - 列表〈T〉、稍后的结果〈T〉：[of]＝T；字典〈V〉：[of]＝V（键第一版恒为文字，不存）。
/// - 函数：[args]＝参数类型…＋返回类型（最后一个）；[args] 是空的＝老的“不知道形状的函数”。
/// - 有名字的（记录、枚举、变体、类、接口）：[name]＋[args]（泛型的类型实参）。类型变量、待定：只有 [name]。
/// - “可以是空”是任何类型上的一个记号（[nullable]），不是单独一层。
library;

enum LKind {
  any,

  /// 老的“数字”＝小数。
  number,
  text,
  bool,
  nul,
  list,
  dict,
  fn,

  /// 有名字＝类；没名字＝老的“对象”。标注里写的“还没认出是哪一种的名字”也先记成它（见 [LType.ref]）。
  object,
  future,

  // —— 第 5 版新加（只加不改）——
  integer,
  record,
  enumeration,
  variant,
  interface,

  /// 泛型里的类型变量（T）。
  typeVar,

  /// 永不：一定会抛错的式子、已经报过错的式子。只在内部用。
  never,

  /// 待定：空列表里放什么、没写〈…〉的泛型类——等后面的用法定下来。只在推断过程中出现。
  hole,
}

/// 整数的范围（JS 能精确表示的最大整数）。
const int kLangMaxInt = 9007199254740991;

class LType {
  const LType(this.kind, {this.of, this.args = const [], this.name, this.nullable = false, this.waits});

  /// 列表〈[of]〉。
  const LType.listOf(LType this.of, {this.nullable = false}) : kind = LKind.list, args = const [], name = null, waits = null;

  /// 字典〈[of]〉（键是文字）。
  const LType.dictOf(LType this.of, {this.nullable = false}) : kind = LKind.dict, args = const [], name = null, waits = null;

  /// 函数 (参数…) → 返回。[paramsAndReturn] 最后一个是返回类型。
  const LType.func(List<LType> paramsAndReturn, {this.nullable = false, this.waits}) : kind = LKind.fn, args = paramsAndReturn, of = null, name = null;

  /// 标注里按名字写的类型（记录 / 枚举 / 变体 / 类 / 接口 / 别名 / 类型变量——哪一种由检查器查声明表认出来）。
  const LType.ref(String this.name, {this.args = const [], this.nullable = false}) : kind = LKind.object, of = null, waits = null;

  /// 类型变量。
  const LType.variable(String this.name, {this.nullable = false}) : kind = LKind.typeVar, of = null, args = const [], waits = null;

  final LKind kind;

  /// 列表的元素类型 / 字典的值类型 / “稍后的结果”的类型。
  final LType? of;

  /// 函数：参数类型…＋返回类型；有名字的类型：类型实参。
  final List<LType> args;

  /// 类 / 接口 / 记录 / 枚举 / 变体的名字；类型变量的名字；待定的编号。
  final String? name;

  /// 可以是空。
  final bool nullable;

  /// 只对函数类型有意义：调它“要不要等”。null＝还没推（这一轮只留位置和存盘字段，推断与拦截在核心 3）。
  final bool? waits;

  static const any = LType(LKind.any);
  static const number = LType(LKind.number);
  static const text = LType(LKind.text);
  static const boolean = LType(LKind.bool);
  static const nul = LType(LKind.nul);
  static const list = LType(LKind.list);
  static const dict = LType(LKind.dict);
  static const integer = LType(LKind.integer);
  static const never = LType(LKind.never);

  bool get isAny => kind == LKind.any;
  bool get isNever => kind == LKind.never;
  bool get isHole => kind == LKind.hole;
  bool get isNul => kind == LKind.nul;
  bool get isFn => kind == LKind.fn;

  /// 整数或小数（不是“可以是空”的）。
  bool get isNumber => (kind == LKind.integer || kind == LKind.number) && !nullable;

  /// 有名字、按名字认的那几种。
  bool get isNamed => name != null && (kind == LKind.object || kind == LKind.record || kind == LKind.enumeration || kind == LKind.variant || kind == LKind.interface);

  /// 函数类型的参数们 / 返回类型（不知道形状的函数：没有参数、返回任意）。
  List<LType> get params => args.isEmpty ? const [] : args.sublist(0, args.length - 1);
  LType get returns => args.isEmpty ? any : args.last;
  bool get hasShape => args.isNotEmpty;

  /// 加上“可以是空”。任意、永不、空本身不变。
  LType get orNull => nullable || kind == LKind.any || kind == LKind.never || kind == LKind.nul ? this : _with(nullable: true);

  /// 去掉“可以是空”。
  LType get nonNull => nullable ? _with(nullable: false) : this;

  LType _with({required bool nullable}) => LType(kind, of: of, args: args, name: name, nullable: nullable, waits: waits);

  /// 把每个类型参数过一遍 [f]（自己不过）。
  LType mapParts(LType Function(LType) f) {
    if (of == null && args.isEmpty) return this;
    return LType(kind, of: of == null ? null : f(of!), args: [for (final a in args) f(a)], name: name, nullable: nullable, waits: waits);
  }

  /// 自己或里面任何一层满足 [test] 吗。
  bool anyPart(bool Function(LType) test) => test(this) || (of?.anyPart(test) ?? false) || args.any((a) => a.anyPart(test));

  /// **规矩版本 1 的合并**（老算法，原样保留）：一样就是它；一边是空＝另一边加上“可以是空”；说不清的一律是“任意”。
  /// 版本 2 的合并在 `LTypeWorld.join`。
  LType join(LType other) {
    if (isAny || other.isAny) return any;
    if (kind == LKind.nul) return other.kind == LKind.nul ? nul : LType(other.kind, of: other.of, name: other.name, nullable: true);
    if (other.kind == LKind.nul) return LType(kind, of: of, name: name, nullable: true);
    if (kind != other.kind || name != other.name) return any;
    final inner = of == null || other.of == null ? null : of!.join(other.of!);
    return LType(kind, of: inner, name: name, nullable: nullable || other.nullable);
  }

  /// 确定对不上吗（给 G10 这类校验用，老算法）：只要有一边是“任意”就不算。
  bool clashesWith(LType other) => !isAny && !other.isAny && kind != LKind.nul && other.kind != LKind.nul && kind != other.kind;

  @override
  bool operator ==(Object other) => other is LType && other.kind == kind && other.of == of && other.name == name && other.nullable == nullable && other.waits == waits && _sameArgs(args, other.args);

  static bool _sameArgs(List<LType> a, List<LType> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(kind, of, name, nullable, waits, Object.hashAll(args));

  /// 给人看的写法（**版本 2 的**，提示语、说明条都用它）：整数、小数、列表〈文字〉、整数?、(整数, 文字) → 是否。
  /// 不出现 int64、`List<String>` 这类写法（设计 6.3）。
  String show() {
    final base = switch (kind) {
      LKind.any => '任意',
      LKind.number => '小数',
      LKind.integer => '整数',
      LKind.text => '文字',
      LKind.bool => '是否',
      LKind.nul => '空',
      LKind.never => '永不',
      LKind.hole => '待定',
      LKind.list => '列表〈${(of ?? any).show()}〉',
      LKind.dict => '字典〈${(of ?? any).show()}〉',
      LKind.future => '稍后的结果〈${(of ?? any).show()}〉',
      LKind.fn => hasShape ? '(${params.map((p) => p.show()).join(', ')}) → ${returns.show()}' : '函数',
      LKind.typeVar => name ?? 'T',
      LKind.object || LKind.record || LKind.enumeration || LKind.variant || LKind.interface => name == null ? '对象' : (args.isEmpty ? name! : '$name〈${args.map((a) => a.show()).join(', ')}〉'),
    };
    if (!nullable) return base;
    return kind == LKind.fn && hasShape ? '($base)?' : '$base?';
  }

  /// 老的写法（版本 1 的检查结果、老测试在用，原样保留；新标签借 [show]）。
  @override
  String toString() {
    final base = switch (kind) {
      LKind.any => '任意',
      LKind.number => '数字',
      LKind.text => '文字',
      LKind.bool => '是否',
      LKind.nul => '空',
      LKind.list => of == null || of!.isAny ? '列表' : '列表〈$of〉',
      LKind.dict => of == null || of!.isAny ? '字典' : '字典〈$of〉',
      LKind.fn => hasShape ? nonNull.show() : '函数',
      LKind.object => name ?? '对象',
      LKind.future => '稍后的结果',
      _ => nonNull.show(),
    };
    return nullable ? '$base（可以是空）' : base;
  }
}
