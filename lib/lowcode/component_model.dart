import 'package:lopicode/lowcode/model.dart';

/// 自定义组件：把一棵控件子树存下来反复用。JSON 结构约定见 docs/lowcode-v2-design.md。
///
/// - 定义里的节点可以用 `bind` 把自己的某个属性接到组件的 prop 上（见 [LcNode.bind]）。
/// - 页面里用 `type: "component"` 的节点引用它：`props.ref` 是组件 id，`props.values` 是这次用的 prop 值。
class LcComponentProp {
  LcComponentProp({required this.name, this.type = 'text', Object? defaultValue}) : defaultValue = coerce(type, defaultValue);

  String name;
  String type;
  Object defaultValue;

  static const List<String> types = ['text', 'number', 'color', 'bool'];
  static final RegExp namePattern = RegExp(r'^[A-Za-z_][A-Za-z0-9_]{0,31}$');

  static Object coerce(String type, Object? v) => switch (type) {
    'number' => v is num ? v : 0,
    'bool' => v is bool && v,
    'color' => v is String && RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(v) ? v.toUpperCase() : '#000000',
    _ => v is String ? v : '',
  };

  Map<String, dynamic> toJson() => {'name': name, 'type': type, 'default': defaultValue};

  static LcComponentProp? tryParse(Object? json) {
    if (json is! Map) return null;
    final name = json['name'];
    if (name is! String || !namePattern.hasMatch(name)) return null;
    final type = json['type'];
    return LcComponentProp(name: name, type: type is String && types.contains(type) ? type : 'text', defaultValue: json['default']);
  }
}

class LcComponentDef {
  LcComponentDef({required this.id, required this.name, List<LcComponentProp>? props, required this.root}) : props = props ?? [];

  /// 组件 id：`c数字`，页面里的实例靠它引用。
  String id;
  String name;
  final List<LcComponentProp> props;

  /// 组件的内容。不能是 page。
  LcNode root;

  static final RegExp idPattern = RegExp(r'^[A-Za-z0-9_]+$');

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    if (props.isNotEmpty) 'props': [for (final p in props) p.toJson()],
    'root': root.toJson(),
  };

  LcComponentProp? prop(String name) {
    for (final p in props) {
      if (p.name == name) return p;
    }
    return null;
  }

  /// 读不出来（缺 root、root 结构不合法、root 是 page）返回 null：坏的组件定义跳过，不让整页打不开。
  static LcComponentDef? tryParse(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final rootJson = json['root'];
    if (rootJson is! Map<String, dynamic>) return null;
    final LcNode root;
    try {
      root = LcNode.fromJson(rootJson, 1);
    } on FormatException {
      return null;
    }
    if (root.type == 'page') return null;
    final id = json['id'];
    final name = json['name'];
    final rawProps = json['props'];
    final seen = <String>{};
    return LcComponentDef(
      id: id is String && idPattern.hasMatch(id) ? id : '',
      name: name is String && name.trim().isNotEmpty ? name.trim() : '未命名组件',
      props: [
        if (rawProps is List)
          for (final p in rawProps)
            if (LcComponentProp.tryParse(p) case final x? when seen.add(x.name)) x,
      ],
      root: root,
    );
  }
}
