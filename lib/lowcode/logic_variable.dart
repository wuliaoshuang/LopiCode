/// 页面变量——第 5 期起也叫“状态”（“现在的变量自动就是状态”，见 docs/blocks-v5-parts/E-editor-components.md §10.8）。
///
/// - 基础三种类型：text / number / bool（积木编辑器、后端积木只认这三种，见 [types]）。
/// - 第 5 期给页面加的两种：list（一串东西）/ record（一条记录），初值是 JSON（见 [stateTypes]）。
/// - “派生”：不存值，带一个式子（[derived]），读的时候现算。存盘时多 `"kind": "derived"` 和 `"expr"` 两个字段；
///   普通的状态不写 `kind`，所以旧页面存出来一个字都不变。
library;

import 'dart:convert';

class LcVariable {
  LcVariable({required this.name, this.type = 'text', Object? initial, this.derived}) : initial = _coerce(type, initial);

  String name;
  String type;
  Object initial;

  /// 派生值的式子（值积木的存法）；null＝普通的状态。
  Object? derived;

  bool get isDerived => derived != null;

  static const List<String> types = ['text', 'number', 'bool'];

  /// 页面 / 项目的状态能用的类型（比 [types] 多 list、record）。
  static const List<String> stateTypes = ['text', 'number', 'bool', 'list', 'record'];
  static final RegExp namePattern = RegExp(r'^[A-Za-z_][A-Za-z0-9_]{0,31}$');

  static Object _coerce(String type, Object? v) => switch (type) {
    'number' => v is num ? v : 0,
    'bool' => v is bool && v,
    'list' => v is List ? v : const <Object?>[],
    'record' => v is Map ? v : const <String, Object?>{},
    _ => v is String ? v : '',
  };

  Map<String, dynamic> toJson() => {'name': name, 'type': type, 'initial': initial, if (derived != null) 'kind': 'derived', if (derived != null) 'expr': derived};

  LcVariable clone() => LcVariable(name: name, type: type, initial: _copy(initial), derived: _copy(derived));

  static Object? _copy(Object? v) => v is Map || v is List ? jsonDecode(jsonEncode(v)) : v;

  /// 字段不对就返回 null（调用方跳过这一条）。[wide]：认不认 list / record 和派生（页面逻辑、项目状态认；后端积木不认）。
  static LcVariable? tryParse(Object? json, {bool wide = false}) {
    if (json is! Map) return null;
    final name = json['name'];
    if (name is! String || !namePattern.hasMatch(name)) return null;
    final type = json['type'];
    final expr = json['expr'];
    return LcVariable(
      name: name,
      type: type is String && (wide ? stateTypes : types).contains(type) ? type : 'text',
      initial: json['initial'],
      derived: wide && json['kind'] == 'derived' && expr is Map ? expr : null,
    );
  }
}
