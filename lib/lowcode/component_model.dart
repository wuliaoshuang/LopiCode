import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/model_v3_components.dart';
import 'package:lopicode/lowcode/slots.dart';

/// 自定义组件：把一棵控件子树存下来反复用。JSON 结构约定见 docs/lowcode-v2-design.md。
///
/// - 定义里的节点可以用 `bind` 把自己的某个属性接到组件的 prop 上（见 [LcNode.bind]）。
/// - 页面里用 `type: "component"` 的节点引用它：`props.ref` 是组件 id，`props.values` 是这次用的 prop 值。
class LcComponentProp {
  LcComponentProp({required this.name, this.type = 'text', Object? defaultValue}) : defaultValue = coerce(type, defaultValue);

  String name;
  String type;
  Object defaultValue;

  /// `list`（第四轮 B2 加的）：一个列表，默认是空的；多半由用它的地方绑一个列表状态进来。
  static const List<String> types = ['text', 'number', 'color', 'bool', 'list'];
  static final RegExp namePattern = RegExp(r'^[A-Za-z_][A-Za-z0-9_]{0,31}$');

  static Object coerce(String type, Object? v) => switch (type) {
    'number' => v is num ? v : 0,
    'bool' => v is bool && v,
    'list' => v is List ? v : const <Object?>[],
    'color' => v is String && RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(v) ? v.toUpperCase() : '#000000',
    _ => v is String ? v : '',
  };

  Map<String, dynamic> toJson() => {'name': name, 'type': type, 'default': defaultValue};

  static LcComponentProp? tryParse(Object? json) {
    if (json is! Map) return null;
    final name = json['name'];
    if (name is! String || !namePattern.hasMatch(name)) return null;
    final type = json['type'];
    // 类型是这一版不认识的（后面几期会加 选项 / 图片 / 列表 / 记录 / 任意）：不当成文字硬读，交给上面原样留着。
    if (type is String && !types.contains(type)) return null;
    return LcComponentProp(name: name, type: type is String ? type : 'text', defaultValue: json['default']);
  }
}

class LcComponentDef {
  LcComponentDef({
    required this.id,
    required this.name,
    List<LcComponentProp>? props,
    required this.root,
    List<Object?>? keptProps,
    Map<String, dynamic>? more,
    Map<String, String>? slotLabels,
    List<Object?>? keptSlots,
  }) : props = props ?? [],
       keptProps = keptProps ?? [],
       more = more ?? {},
       slotLabels = slotLabels ?? {},
       keptSlots = keptSlots ?? [];

  /// 定义上这一版会读的字段；别的（给第 6 期留的 events / variants / state / logic，以及任何不认识的）都进 [more]。
  static const Set<String> knownKeys = {'id', 'name', 'props', 'root', 'slots'};

  /// 文件的 `slots` 里写的“插槽名 → 给人看的名字”。有哪些插槽以 [root] 里的插槽占位节点为准（见 [slots]），这里只管名字。
  final Map<String, String> slotLabels;

  /// 文件的 `slots` 里读不懂的、或者定义里已经没有对应占位节点的项：不解释，原样留着。
  final List<Object?> keptSlots;

  /// 这个组件有哪些插槽：[root] 里的插槽占位节点（`type: slot`），按出现的先后；同名的只算第一个。
  /// 给人看的名字：占位节点自己起了名字用它的，不然用文件 `slots` 里写的，再不然默认插槽叫“默认插槽”、别的就叫插槽名。
  List<LcSlot> get slots {
    final out = <LcSlot>[];
    void walk(LcNode n, LcNode? parent) {
      if (n.type == 'slot') {
        final name = lcSlotNameOf(n);
        if (!out.any((s) => s.name == name)) {
          final flow = parent?.style['flex-direction'];
          final row = parent == null || parent.type == 'component' ? false : (flow == null ? parent.type == 'row' : flow.startsWith('row'));
          out.add(LcSlot(name, n.name.isNotEmpty ? n.name : slotLabels[name] ?? lcDefaultSlotLabel(name), row: row));
        }
      }
      for (final c in n.children) {
        walk(c, n);
      }
    }

    walk(root, null);
    return out;
  }

  /// 读不懂的属性（类型是这一版不认识的、名字不合规矩的、重名的）：不解释，原样留着。
  final List<Object?> keptProps;

  /// 定义上别的字段：不解释，原样留着。
  final Map<String, dynamic> more;

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
    if (props.isNotEmpty || keptProps.isNotEmpty) 'props': [for (final p in props) p.toJson(), ...keptProps],
    'root': root.toJson(),
    if (_slotsJson().isNotEmpty) 'slots': _slotsJson(),
    ...more,
  };

  List<Object?> _slotsJson() {
    final live = slots;
    return [
      for (final s in live) {'name': s.name, 'label': s.label},
      for (final k in keptSlots)
        if (!(k is Map && live.any((s) => s.name == k['name']))) k,
    ];
  }

  LcComponentProp? prop(String name) {
    for (final p in props) {
      if (p.name == name) return p;
    }
    return null;
  }

  /// 读不出来（缺 root、root 结构不合法、root 是 page）返回 null：坏的组件定义跳过，不让整页打不开。
  static LcComponentDef? tryParse(Object? json, {int version = LcDocument.currentVersion}) {
    if (json is! Map<String, dynamic>) return null;
    final rootJson = json['root'];
    if (rootJson is! Map<String, dynamic>) return null;
    final LcNode root;
    try {
      root = LcNode.fromJson(rootJson, 1, version: version);
    } on FormatException {
      return null;
    }
    // 最外层不能是页面、不认识的类型、插槽占位（组件得有一个真的最外层）。
    if (root.type == 'page' || root.isUnknown || root.type == 'slot') return null;
    final rawSlots = json['slots'];
    final labels = <String, String>{};
    final keptSlots = <Object?>[];
    for (final x in rawSlots is List ? rawSlots : const <Object?>[]) {
      final n = x is Map ? x['name'] : null, l = x is Map ? x['label'] : null;
      if (n is String && lcSlotName.hasMatch(n) && l is String && !labels.containsKey(n)) {
        labels[n] = LcNode.cleanName(l);
      } else {
        keptSlots.add(x);
      }
    }
    final id = json['id'];
    final name = json['name'];
    final rawProps = json['props'];
    final seen = <String>{};
    final good = <LcComponentProp>[];
    final kept = <Object?>[];
    for (final p in rawProps is List ? rawProps : const <Object?>[]) {
      final x = LcComponentProp.tryParse(p);
      if (x != null && seen.add(x.name)) {
        good.add(x);
      } else {
        kept.add(p);
      }
    }
    return LcComponentDef(
      id: id is String && idPattern.hasMatch(id) ? id : '',
      name: name is String && name.trim().isNotEmpty ? name.trim() : '未命名组件',
      props: good,
      keptProps: kept,
      slotLabels: labels,
      keptSlots: keptSlots,
      more: {
        for (final e in json.entries)
          if (!knownKeys.contains(e.key) && e.value != null) e.key: e.value,
      },
      root: root,
    );
  }
}
