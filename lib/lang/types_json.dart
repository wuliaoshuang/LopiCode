/// 类型的存盘写法（设计 B 10.1）。只加不改：老的标签名字不变；读的时候坏的、不认识的一律当“任意”，绝不抛异常。
///
/// 写法：`{"k": 标签, "args": [类型参数…], "name": 名字, "nullable": true, "waits": true/false}`，没有的字段不写。
/// - 列表、稍后的结果：`args` 一个；字典：两个（键、值；键第一版恒为文字）；函数：参数…＋返回；有名字的类型：类型实参。
/// - 老写法里的 `of`（只有一个的类型参数）照样能读。
library;

import 'package:lopicode/lang/types.dart';

const Map<LKind, String> _names = {
  LKind.any: 'any',
  LKind.number: 'number',
  LKind.text: 'text',
  LKind.bool: 'bool',
  LKind.nul: 'null',
  LKind.list: 'list',
  LKind.dict: 'dict',
  LKind.fn: 'fn',
  LKind.object: 'object',
  LKind.future: 'future',
  LKind.integer: 'int',
  LKind.record: 'record',
  LKind.enumeration: 'enum',
  LKind.variant: 'variant',
  LKind.interface: 'interface',
  LKind.typeVar: 'var',
  LKind.never: 'never',
};

/// “待定”只在推断过程中有，不存盘（存成“任意”）。
Map<String, dynamic> lTypeToJson(LType t) {
  final args = switch (t.kind) {
    LKind.list || LKind.future => [if (t.of != null) t.of!],
    LKind.dict => [if (t.of != null) ...[LType.text, t.of!]],
    _ => t.args,
  };
  return {
    'k': _names[t.kind] ?? 'any',
    if (args.isNotEmpty) 'args': [for (final a in args) lTypeToJson(a)],
    if (t.name != null && t.kind != LKind.hole) 'name': t.name,
    if (t.nullable) 'nullable': true,
    if (t.waits != null) 'waits': t.waits,
  };
}

LType lTypeFromJson(Object? json, [int depth = 0]) {
  if (json is! Map || depth > 32) return LType.any;
  final kind = _names.entries.where((e) => e.value == json['k']).firstOrNull?.key;
  if (kind == null) return LType.any;
  final raw = json['args'];
  final args = [
    if (raw is List)
      for (final a in raw) lTypeFromJson(a, depth + 1)
    else if (json['of'] != null)
      lTypeFromJson(json['of'], depth + 1),
  ];
  final name = json['name'];
  final nullable = json['nullable'] == true && kind != LKind.any && kind != LKind.nul && kind != LKind.never;
  final waits = json['waits'];
  return switch (kind) {
    LKind.list || LKind.future => LType(kind, of: args.isEmpty ? null : args.first, nullable: nullable),
    LKind.dict => LType(kind, of: args.isEmpty ? null : args.last, nullable: nullable),
    LKind.fn => LType(kind, args: args, nullable: nullable, waits: waits is bool ? waits : null),
    _ => LType(kind, args: args, name: name is String ? name : null, nullable: nullable),
  };
}
