/// 积木槽的类型（[LcType]，存盘用的四个字符串）和语言核心的类型（`LType`）之间的桥（设计 B 10.3）。
///
/// [LcType] 的四个字符串是存盘格式，不动；判断“对不对得上”一律换成 `LType` 来做，G10 和 T 开头的规则用同一套类型。
library;

import 'package:lopicode/lang/types.dart';
import 'package:lopicode/lowcode/logic_expr.dart';

/// 槽的类型 → 语言核心的类型。老的“数字”＝小数；不认识的＝任意。
LType lcToLType(String type) => switch (type) {
  LcType.number => LType.number,
  LcType.text => LType.text,
  LcType.boolean => LType.boolean,
  _ => LType.any,
};

/// 语言核心的类型 → 槽的类型：整数、小数都是“数字”；四种以外的（列表、记录…）和“可以是空”的都按“任意”（槽上说不准）。
String lTypeToLc(LType t) {
  if (t.nullable) return LcType.any;
  return switch (t.kind) {
    LKind.number || LKind.integer => LcType.number,
    LKind.text => LcType.text,
    LKind.bool => LcType.boolean,
    _ => LcType.any,
  };
}
