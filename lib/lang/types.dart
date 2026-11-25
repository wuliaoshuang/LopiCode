/// 语言核心的类型（设计稿 4.3）。第 1 阶段：生成时全部按“任意”（建议 A / 建议 C 的第一步，可改），类型只用于校验。
library;

enum LKind { any, number, text, bool, nul, list, dict, fn, object, future }

class LType {
  const LType(this.kind, {this.of, this.name, this.nullable = false});

  final LKind kind;

  /// 列表的元素类型 / 字典的值类型 / “稍后的结果”的类型。
  final LType? of;

  /// 类名 / 接口名（[LKind.object]）。
  final String? name;

  /// 可以是空。
  final bool nullable;

  static const any = LType(LKind.any);
  static const number = LType(LKind.number);
  static const text = LType(LKind.text);
  static const boolean = LType(LKind.bool);
  static const nul = LType(LKind.nul);
  static const list = LType(LKind.list);
  static const dict = LType(LKind.dict);

  bool get isAny => kind == LKind.any;

  /// 两个类型“合起来”：一样就是它；一边是空＝另一边加上“可以是空”；说不清的一律是“任意”。
  LType join(LType other) {
    if (isAny || other.isAny) return any;
    if (kind == LKind.nul) return other.kind == LKind.nul ? nul : LType(other.kind, of: other.of, name: other.name, nullable: true);
    if (other.kind == LKind.nul) return LType(kind, of: of, name: name, nullable: true);
    if (kind != other.kind || name != other.name) return any;
    final inner = of == null || other.of == null ? null : of!.join(other.of!);
    return LType(kind, of: inner, name: name, nullable: nullable || other.nullable);
  }

  /// 确定对不上吗（给 G10 这类校验用）：只要有一边是“任意”就不算。
  bool clashesWith(LType other) => !isAny && !other.isAny && kind != LKind.nul && other.kind != LKind.nul && kind != other.kind;

  @override
  bool operator ==(Object other) => other is LType && other.kind == kind && other.of == of && other.name == name && other.nullable == nullable;

  @override
  int get hashCode => Object.hash(kind, of, name, nullable);

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
      LKind.fn => '函数',
      LKind.object => name ?? '对象',
      LKind.future => '稍后的结果',
    };
    return nullable ? '$base（可以是空）' : base;
  }
}
