/// 类型问题的“一键修”落到积木文档上：把那一格里的东西外面包一层积木（或换成“… ≠ 0”）。纯数据，不碰界面。
///
/// 设计：docs/blocks-v5-parts/B-type-system.md 6.2。语法树上十一种修法都能做（lib/lang/type_fix.dart）；积木上现在能表达的是这六种：
///
/// | 修法 | 积木上变成什么 |
/// |---|---|
/// | 变成文字 | “转换类型”积木，选“变成文字” |
/// | 取整 | “取整”积木，选“四舍五入” |
/// | 变成整数（变不了就是空） | “把 ▢ 变成整数”（严格规矩才有的积木） |
/// | 是空就用 … | “▢ 是空就用 ▢”，后一格照类型先放一个最平常的值（0、空文字、否、空列表、空字典） |
/// | 一定不是空 | “一定不是空 ▢” |
/// | 换成“… ≠ 0” | “运算 / 比较”积木，选 ≠，右边放 0 |
///
/// 另外五种（补情况、加“其余”、补字段、删字段、换成“复制并改”）要靠“看是哪种情况”和记录的积木，这些积木还没有，[beTypeFixWrap] 返回 null。
/// 调用方（宿主）负责把这一步放进撤销栈。
library;

import 'package:lopicode/backend/backend_type_bridge.dart';
import 'package:lopicode/lang/type_issue.dart';
import 'package:lopicode/lang/types.dart';
import 'package:lopicode/lowcode/logic_expr.dart';
import 'package:lopicode/lowcode/logic_model.dart';

Object? _valueAt(LcBlock block, String arg, List<Object> path) {
  Object? v = block.argValue(arg);
  for (final step in path) {
    if (step is int) {
      if (v is! List || step < 0 || step >= v.length) return null;
      v = v[step];
    } else {
      if (v is! Map) return null;
      v = v[step];
    }
  }
  return v;
}

bool _setAt(LcBlock block, String arg, List<Object> path, Object? value) {
  if (path.isEmpty) return block.setArgValue(arg, value);
  final parent = _valueAt(block, arg, path.sublist(0, path.length - 1));
  final last = path.last;
  if (last is int) {
    if (parent is! List || last < 0 || last >= parent.length) return false;
    parent[last] = value;
    return true;
  }
  if (parent is! Map) return false;
  parent[last] = value;
  return true;
}

/// “是空就用 ▢”的 ▢ 里先放什么（积木文档里的写法）；说不出来就空着让人填。
Object? beFixDefaultValue(LType? type) => switch (type?.kind) {
  LKind.integer || LKind.number => exNum(0),
  LKind.text => exText(''),
  LKind.bool => exBool(false),
  LKind.list => <String, dynamic>{'e': 'listLit', 'items': <dynamic>[]},
  LKind.dict => <String, dynamic>{'e': 'obj', 'fields': <dynamic>[]},
  _ => null,
};

/// [inner]（那一格里原来的东西）照 [fix] 包好以后的样子；这种修法在积木上表达不了返回 null。
/// [got]＝那一格里的东西现在的类型（“是空就用”要照它先放一个值）。
Map<String, dynamic>? beTypeFixWrap(LFix fix, Object? inner, {LType? got}) => switch (fix.kind) {
  LFixKind.wrapToText => {'e': 'convert', 'x': inner, 'fn': 'toText'},
  LFixKind.wrapToInt => {'e': 'round', 'x': inner, 'fn': 'round'},
  LFixKind.wrapParseInt => {'e': 'parseInt', 's': inner},
  LFixKind.wrapOrElse => {'e': 'orElse', 'x': inner, 'd': beFixDefaultValue(got?.nonNull)},
  LFixKind.wrapMust => {'e': 'must', 'x': inner},
  LFixKind.compareNotZero => {'e': 'bin', 'op': '!=', 'l': inner, 'r': exNum(0)},
  LFixKind.addMatchCases || LFixKind.addMatchElse || LFixKind.addRecordFields || LFixKind.removeRecordField || LFixKind.useRecordCopy => null,
};

/// 把 [fix] 用到 [tree] 的 [slot] 这一格上。做了返回 true；做不了（格子不在了、这种修法积木上表达不了）返回 false，什么都不改。
bool beApplyTypeFix(LcBlockTree tree, LFix fix, BeSlotRef slot, {LType? got}) {
  final arg = slot.arg;
  final block = tree.blockAt(slot.path);
  if (arg == null || block == null) return false;
  final inner = _valueAt(block, arg, slot.exprPath);
  if (inner == null) return false;
  final wrapped = beTypeFixWrap(fix, inner, got: got);
  return wrapped != null && _setAt(block, arg, slot.exprPath, wrapped);
}
