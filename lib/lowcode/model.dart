import 'dart:convert';

import 'package:lopicode/lowcode/component_model.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:lopicode/lowcode/model_props.dart';
import 'package:lopicode/lowcode/model_v3_components.dart';
import 'package:lopicode/lowcode/slots.dart';

export 'package:lopicode/lowcode/model_history.dart';

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
  bool get isContainer => spec.isContainer;

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

  /// 是不是带插槽的组件（列表行、顶部导航栏、标签页、弹窗）；插槽怎么读见 slots.dart。
  bool get hasSlots => spec.slots != null;

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
  );

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
    if (children.isNotEmpty && !lcSpecs[type]!.isContainer) {
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

class LcSpec {
  const LcSpec(this.type, this.label, {this.isContainer = false, this.defaults = const {}, this.fields = const [], this.slots});
  final String type;
  final String label;
  final bool isContainer;
  final Map<String, dynamic> defaults;

  /// 带插槽的组件：固定的插槽名（标签页的插槽跟着页签走，这里是空表）。null＝没有插槽。读法见 slots.dart。
  final List<String>? slots;

  /// 属性面板里显示哪些字段、按什么顺序。
  final List<String> fields;
}

const _boxFields = ['width', 'height', 'padding', 'margin', 'bg', 'radius'];
const _layoutFields = ['gap', 'align', 'justify'];

/// 这一版不认识的组件类型用的说明（不在 [lcSpecs] 里：组件盒、各处“每种组件”的清单都不该有它）。
const LcSpec lcUnknownSpec = LcSpec('unknown', '新版组件', defaults: {}, fields: []);

const Map<String, LcSpec> lcSpecs = {
  'page': LcSpec('page', '页面', isContainer: true, defaults: {'padding': 16, 'gap': 12, 'bg': '#F6FBFD'}, fields: ['padding', 'bg', ..._layoutFields]),
  'container': LcSpec('container', '容器', isContainer: true, defaults: {'padding': 12, 'gap': 8, 'width': 'fill'}, fields: [..._boxFields, ..._layoutFields]),
  'row': LcSpec('row', '行', isContainer: true, defaults: {'gap': 8, 'align': 'center', 'width': 'fill'}, fields: [..._boxFields, ..._layoutFields]),
  'column': LcSpec('column', '列', isContainer: true, defaults: {'gap': 8}, fields: [..._boxFields, ..._layoutFields]),
  'card': LcSpec('card', '卡片', isContainer: true, defaults: {'padding': 16, 'gap': 8, 'bg': '#FFFFFF', 'radius': 12, 'width': 'fill'}, fields: [..._boxFields, ..._layoutFields]),
  'text': LcSpec(
    'text',
    '文本',
    defaults: {'text': '一段文本', 'fontSize': 16, 'color': '#222435'},
    fields: ['text', 'fontSize', 'bold', 'color', 'textAlign', 'width', 'padding', 'margin', 'bg', 'radius'],
  ),
  'button': LcSpec(
    'button',
    '按钮',
    defaults: {'text': '按钮', 'bg': '#058654', 'color': '#FFFFFF', 'radius': 8, 'padding': 12, 'fontSize': 16},
    fields: ['text', 'fontSize', 'bg', 'color', 'radius', 'padding', 'width', 'margin'],
  ),
  'image': LcSpec('image', '图片', defaults: {'src': '', 'height': 160, 'radius': 8, 'width': 'fill'}, fields: ['src', 'width', 'height', 'radius', 'margin']),
  'input': LcSpec('input', '输入框', defaults: {'placeholder': '请输入', 'radius': 8, 'width': 'fill'}, fields: ['placeholder', 'width', 'radius', 'margin']),
  'list': LcSpec(
    'list',
    '列表',
    defaults: {
      'items': ['第一项', '第二项', '第三项'],
      'fontSize': 16,
      'color': '#222435',
    },
    fields: ['items', 'fontSize', 'color', 'width', 'padding', 'margin', 'bg', 'radius'],
  ),
  'divider': LcSpec('divider', '分割线', defaults: {}, fields: ['margin']),
  'spacer': LcSpec('spacer', '间隔', defaults: {'size': 16}, fields: ['size']),
  // 这一版不认识的类型（LcNode.raw）：不能放子组件、不在组件盒里、没有可改的属性。
  // 自定义组件的实例：props.ref 指向 LcDocument.components 里的定义。不在组件栏的固定清单里。
  'component': LcSpec('component', '组件', defaults: {}, fields: ['width', 'margin']),
  // 第 3 版的 11 个新组件（model_v3_components.dart）。
  ...lcV3Specs,
};

/// 组件面板里可拖出来的类型（page 只能是根）。
const List<String> lcPaletteTypes = ['container', 'row', 'column', 'card', 'text', 'button', 'image', 'input', 'list', 'divider', 'spacer', ...lcV3PaletteTypes];

class LcDocument {
  LcDocument({required this.title, required this.root, LcLogic? logic, List<LcComponentDef>? components, this.fileVersion = currentVersion, Map<String, dynamic>? more, List<Object?>? keptComponents})
    : logic = logic ?? LcLogic(),
      components = components ?? [],
      more = more ?? {},
      keptComponents = keptComponents ?? [] {
    _normalizeIds();
    _normalizeComponents();
  }

  /// 1＝只有组件树；2＝加了 style / logic / components（都可省略，所以第 1 版的文件照样能读）。
  /// 3＝节点多了名字 / 锁定 / 编辑器内隐藏和一批新属性，并且给后面几期留好了字段；看不懂的东西一律原样留着。
  /// 整份说明见 docs/lowcode-page-format-v3.md。
  static const int currentVersion = 3;

  /// 最外层这一版会读的字段；别的（给后面几期留的 pages / theme，以及任何不认识的）都进 [more]。
  static const Set<String> knownKeys = {'version', 'title', 'root', 'logic', 'components'};

  /// 打开的那个文件写的是第几版（没写＝1）。只用来判断“是不是比这一版新”，以及存盘时版本号不往回写。
  final int fileVersion;

  /// 这个页面是比这一版应用更新的版本做的：有些东西这里显示不了、改不了，但存盘时会原样留着。
  bool get isFromNewer => fileVersion > currentVersion;

  /// 最外层别的字段：不解释，原样留着。
  final Map<String, dynamic> more;

  /// 读不出来的组件定义：不解释，原样留着（排在读得出来的后面）。
  final List<Object?> keptComponents;

  String title;
  LcNode root;

  /// 页面逻辑：变量和事件处理。
  final LcLogic logic;

  /// 自定义组件的定义。
  final List<LcComponentDef> components;
  int _nextId = 1;

  factory LcDocument.starter(String title) => LcDocument(
    title: title,
    root: LcNode(
      id: 'root',
      type: 'page',
      props: Map.of(lcSpecs['page']!.defaults),
      children: [
        LcNode(id: '', type: 'text', props: {'text': title, 'fontSize': 24, 'bold': true, 'color': '#222435'}),
        LcNode(id: '', type: 'text', props: {'text': '点左下角的“添加”选一个组件放进来；长按组件可以拖动。', 'fontSize': 16, 'color': '#5C6479'}),
        LcNode(
          id: '',
          type: 'card',
          props: Map.of(lcSpecs['card']!.defaults),
          children: [
            LcNode(id: '', type: 'input', props: Map.of(lcSpecs['input']!.defaults)),
            LcNode(id: '', type: 'button', props: {...lcSpecs['button']!.defaults, 'text': '提交'}),
          ],
        ),
      ],
    ),
  );

  factory LcDocument.fromJson(Map<String, dynamic> json) {
    final rootJson = json['root'];
    if (rootJson is! Map<String, dynamic>) {
      throw const FormatException('缺少 root');
    }
    final v = json['version'];
    final version = v is int && v >= 1 ? v : 1;
    final root = LcNode.fromJson(rootJson, 0, version: version);
    if (root.type != 'page') {
      throw const FormatException('根组件必须是 page');
    }
    final rawComponents = json['components'];
    return LcDocument(
      title: json['title'] is String ? json['title'] as String : '未命名页面',
      root: root,
      logic: LcLogic.fromJson(json['logic']),
      fileVersion: version,
      components: [
        if (rawComponents is List)
          for (final c in rawComponents) ?LcComponentDef.tryParse(c, version: version),
      ],
      keptComponents: [
        if (rawComponents is List)
          for (final c in rawComponents)
            if (LcComponentDef.tryParse(c, version: version) == null) c,
      ],
      more: {
        for (final e in json.entries)
          if (!knownKeys.contains(e.key) && e.value != null) e.key: e.value,
      },
    );
  }

  static LcDocument parse(String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (e) {
      throw FormatException('页面文件不是合法 JSON：${e.message}');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('页面文件必须是一个 JSON 对象');
    }
    return LcDocument.fromJson(decoded);
  }

  Map<String, dynamic> toJson() => {
    'version': fileVersion > currentVersion ? fileVersion : currentVersion,
    'title': title,
    'root': root.toJson(),
    if (!logic.isEmpty) 'logic': logic.toJson(),
    if (components.isNotEmpty || keptComponents.isNotEmpty) 'components': [for (final c in components) c.toJson(), ...keptComponents],
    ...more,
  };

  LcComponentDef? component(String id) {
    for (final c in components) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// 组件定义：id 缺了 / 重了补成 `c数字`；定义内部的节点 id 各自保证唯一（和页面的节点 id 互不相干）。
  void _normalizeComponents() {
    final ids = <String>{};
    var next = 1;
    for (final c in components) {
      if (c.id.isEmpty || !ids.add(c.id)) {
        while (ids.contains('c$next')) {
          next++;
        }
        c.id = 'c$next';
        ids.add(c.id);
      }
      final seen = <String>{};
      var n = 1;
      void fix(LcNode node) {
        if (node.id.isEmpty || !RegExp(r'^[A-Za-z0-9]+$').hasMatch(node.id) || !seen.add(node.id)) {
          while (seen.contains('k$n')) {
            n++;
          }
          node.id = 'k$n';
          seen.add(node.id);
        }
        node.children.forEach(fix);
      }

      fix(c.root);
    }
  }

  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());

  /// 保证每个节点都有唯一 id（外部 JSON、Agent 写入的可能缺或重复）。
  void _normalizeIds() {
    final seen = <String>{};
    var maxN = 0;
    void scan(LcNode n) {
      final m = RegExp(r'^n(\d+)$').firstMatch(n.id);
      if (m != null) maxN = maxN < int.parse(m[1]!) ? int.parse(m[1]!) : maxN;
      n.children.forEach(scan);
    }

    scan(root);
    _nextId = maxN + 1;
    void fix(LcNode n) {
      if (n.id.isEmpty || !RegExp(r'^[A-Za-z0-9_]+$').hasMatch(n.id) || !seen.add(n.id)) {
        n.id = 'n${_nextId++}';
        seen.add(n.id);
      }
      n.children.forEach(fix);
    }

    fix(root);
  }

  LcNode newNode(String type) => LcNode(id: 'n${_nextId++}', type: type, props: jsonDecode(jsonEncode(lcSpecs[type]!.defaults)) as Map<String, dynamic>);

  LcNode? find(String id) {
    LcNode? walk(LcNode n) {
      if (n.id == id) return n;
      for (final c in n.children) {
        final r = walk(c);
        if (r != null) return r;
      }
      return null;
    }

    return walk(root);
  }

  LcNode? parentOf(String id) {
    LcNode? walk(LcNode n) {
      for (final c in n.children) {
        if (c.id == id) return n;
        final r = walk(c);
        if (r != null) return r;
      }
      return null;
    }

    return walk(root);
  }

  bool _contains(LcNode ancestor, String id) => ancestor.id == id || ancestor.children.any((c) => _contains(c, id));

  /// 把节点插到某个容器的指定位置；返回是否成功。
  bool insert(String parentId, LcNode node, [int? index]) {
    final parent = find(parentId);
    if (parent == null || !parent.isContainer || node.type == 'page') return false;
    final i = (index ?? parent.children.length).clamp(0, parent.children.length);
    parent.children.insert(i, node);
    lcSettleSlot(parent, node, i);
    _normalizeIds();
    return true;
  }

  bool remove(String id) {
    final parent = parentOf(id);
    if (parent == null) return false; // 根不能删
    parent.children.removeWhere((c) => c.id == id);
    return true;
  }

  /// 移动 / 重排。不能移进自己或自己的后代里。
  bool move(String id, String newParentId, int index) {
    final node = find(id);
    final oldParent = parentOf(id);
    final newParent = find(newParentId);
    if (node == null || oldParent == null || newParent == null) return false;
    if (!newParent.isContainer || _contains(node, newParentId)) return false;
    final oldIndex = oldParent.children.indexOf(node);
    oldParent.children.removeAt(oldIndex);
    var i = index;
    if (identical(oldParent, newParent) && oldIndex < index) i -= 1;
    final at = i.clamp(0, newParent.children.length);
    newParent.children.insert(at, node);
    lcSettleSlot(newParent, node, at);
    return true;
  }

  /// 在同级里上移 / 下移一位。
  bool shift(String id, int delta) {
    final parent = parentOf(id);
    if (parent == null) return false;
    final i = parent.children.indexWhere((c) => c.id == id);
    final j = i + delta;
    if (j < 0 || j >= parent.children.length) return false;
    final node = parent.children.removeAt(i);
    parent.children.insert(j, node);
    return true;
  }

  String? duplicate(String id) {
    final parent = parentOf(id);
    final node = find(id);
    if (parent == null || node == null) return null;
    final copy = node.clone();
    void clear(LcNode n) {
      n.id = '';
      n.children.forEach(clear);
    }

    clear(copy);
    parent.children.insert(parent.children.indexOf(node) + 1, copy);
    _normalizeIds();
    return copy.id;
  }
}
