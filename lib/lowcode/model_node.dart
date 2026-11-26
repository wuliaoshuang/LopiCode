part of 'model.dart';

/// 低代码页面的数据模型：一棵组件树，整份存成项目里的 JSON 文件。
///
/// 属性约定（都可省略）：
/// - `width`：数字（像素）或 `"fill"`（撑满）；省略＝自适应
/// - `height`：数字
/// - `padding` / `margin` / `radius` / `gap` / `fontSize` / `size`：数字
/// - `bg` / `color`：`#RRGGBB`
/// - `align`：start / center / end / stretch（交叉轴）
/// - `justify`：start / center / end / between（主轴）
/// - `textAlign`：left / center / right
/// - `text` / `src` / `placeholder`：字符串；`bold`：布尔；`items`：字符串数组
/// - `ref` / `values`：只有 `component`（自定义组件的实例）用，见 component_model.dart
///
/// 第 2 版加的（都可省略，旧文件没有也能打开；约定见 docs/lowcode-v2-design.md）：
/// - [style]：这个组件自己的 CSS 声明（规范写法：小写连字符的属性名 → 值），盖在上面那些简写属性之上。
/// - [bind]：只在自定义组件的定义里用，把属性接到组件的 prop 上（属性名 → prop 名）。
///
/// 第 3 版加的（都可省略；整份说明见 docs/lowcode-page-format-v3.md）：
/// - [name]：用户起的名字（图层面板里显示）。[locked]：锁定。[hidden]：只在编辑器里不画，**不影响导出**。
/// - [keptProps]：`props` 里这一版看不懂的，不解释、原样留着。
/// - [more]：节点上别的字段（给后面几期留的 states / responsive / data / repeat / showIf / slot，
///   老文件里挪出来的 oldProps，以及任何不认识的字段），不解释、原样留着。
/// - [raw]：这一版不认识的组件类型（[type] 是 `unknown`）：整个节点原样留着，画布上画一个占位，导出时跳过。
class LcNode {
  LcNode({
    required this.id,
    required this.type,
    Map<String, dynamic>? props,
    List<LcNode>? children,
    Map<String, String>? style,
    Map<String, String>? bind,
    this.name = '',
    this.locked = false,
    this.hidden = false,
    Map<String, dynamic>? keptProps,
    Map<String, dynamic>? more,
    this.raw,
  }) : props = props ?? {},
       children = children ?? [],
       style = style ?? {},
       bind = bind ?? {},
       keptProps = keptProps ?? {},
       more = more ?? {};

  /// 不认识的组件类型在内存里的类型名（文件里写的还是它原来的名字，见 [raw]）。
  static const String unknownType = 'unknown';

  /// 节点上这一版会读的字段；别的都进 [more]。
  static const Set<String> knownKeys = {'id', 'type', 'name', 'locked', 'hidden', 'props', 'style', 'bind', 'children'};

  /// 名字最长多少个字。
  static const int maxNameLength = 40;

  String name;
  bool locked;
  bool hidden;
  final Map<String, dynamic> keptProps;
  final Map<String, dynamic> more;
  final Map<String, dynamic>? raw;

  bool get isUnknown => raw != null;

  /// 文件里写的类型名（不认识的类型也给得出来）。
  String get fileType => raw?['type'] is String ? raw!['type'] as String : type;

  String id;
  final String type;
  final Map<String, dynamic> props;
  final List<LcNode> children;
  final Map<String, String> style;
  final Map<String, String> bind;

  LcSpec get spec => lcSpecs[type] ?? lcUnknownSpec;

  /// 自定义组件的实例：它的定义里有哪些插槽（不进文件；文档每次改完重新对一遍，见 slots.dart 的 lcLinkInstances）。
  List<LcSlot> instSlots = const [];
  bool get isContainer => spec.isContainer || instSlots.isNotEmpty;

  num? numProp(String key) {
    final v = props[key];
    return v is num ? v : null;
  }

  String? strProp(String key) {
    final v = props[key];
    return v is String && v.isNotEmpty ? v : null;
  }

  bool get fillWidth => props['width'] == 'fill';

  /// 这个节点放在父节点的哪个插槽里（文件里的 `slot`）；没写是 null。
  String? get slot => more['slot'] is String ? more['slot'] as String : null;
  set slot(String? v) => v == null ? more.remove('slot') : more['slot'] = v;

  /// 是不是带插槽的组件（列表行、顶部导航栏、标签页、弹窗，定义里有插槽的自定义组件实例）；插槽怎么读见 slots.dart。
  bool get hasSlots => spec.slots != null || instSlots.isNotEmpty;

  /// 字段顺序固定：id、type、name、locked、hidden、props、style、bind、（别的字段）、children；空的不写。
  Map<String, dynamic> toJson() {
    if (raw != null) return {...raw!, 'id': id};
    final allProps = {
      ...props,
      for (final e in keptProps.entries)
        if (!props.containsKey(e.key)) e.key: e.value,
    };
    return {
      'id': id,
      'type': type,
      if (name.isNotEmpty) 'name': name,
      if (locked) 'locked': true,
      if (hidden) 'hidden': true,
      if (allProps.isNotEmpty) 'props': allProps,
      if (style.isNotEmpty) 'style': style,
      if (bind.isNotEmpty) 'bind': bind,
      ...more,
      if (children.isNotEmpty) 'children': [for (final c in children) c.toJson()],
    };
  }

  static Map<String, dynamic> _deep(Map<String, dynamic> m) => m.isEmpty ? {} : jsonDecode(jsonEncode(m)) as Map<String, dynamic>;

  /// 拷一份自己，不带子组件（[children] 另给）：名字、锁定、隐藏和原样留着的东西都带上。
  LcNode shell({required Map<String, dynamic> props, bool keepBind = true, List<LcNode>? children}) => LcNode(
    id: id,
    type: type,
    props: props,
    style: Map.of(style),
    bind: keepBind ? Map.of(bind) : null,
    children: children,
    name: name,
    locked: locked,
    hidden: hidden,
    keptProps: _deep(keptProps),
    more: _deep(more),
    raw: raw == null ? null : _deep(raw!),
  )..instSlots = instSlots;

  LcNode clone() => LcNode.fromJson(jsonDecode(jsonEncode(toJson())) as Map<String, dynamic>, 0);

  static const int maxDepth = 24;

  /// [version]：这个节点来自第几版的文件（内存里复制、撤销重做用的都是当前版）。
  factory LcNode.fromJson(Map<String, dynamic> json, int depth, {int version = LcDocument.currentVersion}) {
    if (depth > maxDepth) {
      throw const FormatException('组件嵌套太深（最多 $maxDepth 层）');
    }
    final type = json['type'];
    if (type is! String || type.isEmpty) {
      throw FormatException('未知的组件类型：$type');
    }
    if (!lcSpecs.containsKey(type)) {
      // 这一版不认识的类型（多半是新版应用加的组件）：整个节点原样留着，不解释。
      return LcNode(id: json['id'] is String ? json['id'] as String : '', type: unknownType, raw: Map.of(json));
    }
    final rawProps = json['props'];
    if (rawProps != null && rawProps is! Map) {
      throw FormatException('$type 的 props 必须是对象');
    }
    final rawChildren = json['children'];
    if (rawChildren != null && rawChildren is! List) {
      throw FormatException('$type 的 children 必须是数组');
    }
    final children = <LcNode>[];
    for (final c in (rawChildren as List?) ?? const []) {
      if (c is! Map<String, dynamic>) {
        throw FormatException('$type 的子组件必须是对象');
      }
      children.add(LcNode.fromJson(c, depth + 1, version: version));
    }
    // 自定义组件的实例可以有子节点（填进插槽的内容）；它的定义有没有插槽读文件时还不知道。
    if (children.isNotEmpty && !lcSpecs[type]!.isContainer && type != 'component') {
      throw FormatException('${lcSpecs[type]!.label}（$type）不能包含子组件');
    }
    if (children.any((c) => c.type == 'page')) {
      throw const FormatException('page 只能作为根组件');
    }
    final (props, kept) = lcReadProps(type, rawProps is Map ? rawProps : const {}, version);
    final more = <String, dynamic>{
      for (final e in json.entries)
        if (!knownKeys.contains(e.key) && e.value != null) e.key: e.value,
    };
    final keptProps = <String, dynamic>{};
    if (version < 3 && kept.isNotEmpty) {
      // 老文件里多出来的属性：那时候不算数，现在也不能突然算数——挪到 oldProps 里留着。
      final old = more['oldProps'];
      more['oldProps'] = {...kept, if (old is Map) ...old};
    } else {
      keptProps.addAll(kept);
    }
    final name = json['name'];
    return LcNode(
      id: json['id'] is String ? json['id'] as String : '',
      type: type,
      name: name is String ? cleanName(name) : '',
      locked: json['locked'] == true,
      hidden: json['hidden'] == true,
      props: props,
      keptProps: keptProps,
      more: more,
      children: children,
      style: cleanStyle(json['style']),
      bind: cleanBind(json['bind']),
    );
  }

  /// 名字：去掉首尾空白和换行，太长截断。
  static String cleanName(String raw) {
    final s = raw.replaceAll(RegExp(r'[\r\n\t]+'), ' ').trim();
    return s.length > maxNameLength ? s.substring(0, maxNameLength) : s;
  }

  static final RegExp _cssName = RegExp(r'^-{0,2}[a-z][a-z0-9-]{0,63}$');

  /// 属性里哪些可以接到组件的 prop 上。
  static const List<String> bindableProps = ['text', 'src', 'placeholder', 'bg', 'color'];

  /// 容错读 `style`：不是对象就当没有；属性名必须是小写连字符写法；
  /// 值必须是字符串，而且不许带 `{ } ;` 和换行（免得导出的 CSS 被截断或夹带别的规则）。
  static Map<String, String> cleanStyle(Object? raw) {
    final out = <String, String>{};
    if (raw is! Map) return out;
    raw.forEach((key, value) {
      if (key is! String || value is! String) return;
      final v = value.trim();
      if (!_cssName.hasMatch(key) || v.isEmpty || v.length > 500 || RegExp(r'[{};\n\r<>]').hasMatch(v)) return;
      out[key] = v;
    });
    return out;
  }

  static Map<String, String> cleanBind(Object? raw) {
    final out = <String, String>{};
    if (raw is! Map) return out;
    raw.forEach((key, value) {
      if (key is String && value is String && bindableProps.contains(key) && LcComponentProp.namePattern.hasMatch(value)) out[key] = value;
    });
    return out;
  }
}
