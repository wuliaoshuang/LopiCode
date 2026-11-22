import 'dart:convert';

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
class LcNode {
  LcNode({
    required this.id,
    required this.type,
    Map<String, dynamic>? props,
    List<LcNode>? children,
  }) : props = props ?? {},
       children = children ?? [];

  String id;
  final String type;
  final Map<String, dynamic> props;
  final List<LcNode> children;

  LcSpec get spec => lcSpecs[type]!;
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

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    if (props.isNotEmpty) 'props': props,
    if (children.isNotEmpty) 'children': [for (final c in children) c.toJson()],
  };

  LcNode clone() => LcNode.fromJson(
    jsonDecode(jsonEncode(toJson())) as Map<String, dynamic>,
    0,
  );

  static const int maxDepth = 24;

  factory LcNode.fromJson(Map<String, dynamic> json, int depth) {
    if (depth > maxDepth) {
      throw const FormatException('组件嵌套太深（最多 $maxDepth 层）');
    }
    final type = json['type'];
    if (type is! String || !lcSpecs.containsKey(type)) {
      throw FormatException('未知的组件类型：$type');
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
      children.add(LcNode.fromJson(c, depth + 1));
    }
    if (children.isNotEmpty && !lcSpecs[type]!.isContainer) {
      throw FormatException('${lcSpecs[type]!.label}（$type）不能包含子组件');
    }
    if (children.any((c) => c.type == 'page')) {
      throw const FormatException('page 只能作为根组件');
    }
    return LcNode(
      id: json['id'] is String ? json['id'] as String : '',
      type: type,
      props: _cleanProps(type, (rawProps as Map?)?.cast<String, dynamic>() ?? {}),
      children: children,
    );
  }

  static Map<String, dynamic> _cleanProps(String type, Map<String, dynamic> raw) {
    final out = <String, dynamic>{};
    raw.forEach((key, value) {
      if (value == null) return;
      switch (key) {
        case 'width':
          if (value == 'fill' || (value is num && value >= 0)) out[key] = value;
        case 'height' || 'padding' || 'margin' || 'radius' || 'gap' || 'fontSize' || 'size':
          if (value is num && value >= 0) out[key] = value;
        case 'bg' || 'color':
          if (value is String && RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(value)) {
            out[key] = value.toUpperCase();
          }
        case 'align':
          if (const ['start', 'center', 'end', 'stretch'].contains(value)) out[key] = value;
        case 'justify':
          if (const ['start', 'center', 'end', 'between'].contains(value)) out[key] = value;
        case 'textAlign':
          if (const ['left', 'center', 'right'].contains(value)) out[key] = value;
        case 'text' || 'src' || 'placeholder':
          if (value is String) out[key] = value;
        case 'bold':
          if (value is bool) out[key] = value;
        case 'items':
          if (value is List) out[key] = [for (final v in value) '$v'];
      }
    });
    return out;
  }
}

class LcSpec {
  const LcSpec(this.type, this.label, {this.isContainer = false, this.defaults = const {}, this.fields = const []});
  final String type;
  final String label;
  final bool isContainer;
  final Map<String, dynamic> defaults;

  /// 属性面板里显示哪些字段、按什么顺序。
  final List<String> fields;
}

const _boxFields = ['width', 'height', 'padding', 'margin', 'bg', 'radius'];
const _layoutFields = ['gap', 'align', 'justify'];

const Map<String, LcSpec> lcSpecs = {
  'page': LcSpec('page', '页面', isContainer: true,
      defaults: {'padding': 16, 'gap': 12, 'bg': '#F6FBFD'},
      fields: ['padding', 'bg', ..._layoutFields]),
  'container': LcSpec('container', '容器', isContainer: true,
      defaults: {'padding': 12, 'gap': 8, 'width': 'fill'},
      fields: [..._boxFields, ..._layoutFields]),
  'row': LcSpec('row', '行', isContainer: true,
      defaults: {'gap': 8, 'align': 'center', 'width': 'fill'},
      fields: [..._boxFields, ..._layoutFields]),
  'column': LcSpec('column', '列', isContainer: true,
      defaults: {'gap': 8},
      fields: [..._boxFields, ..._layoutFields]),
  'card': LcSpec('card', '卡片', isContainer: true,
      defaults: {'padding': 16, 'gap': 8, 'bg': '#FFFFFF', 'radius': 12, 'width': 'fill'},
      fields: [..._boxFields, ..._layoutFields]),
  'text': LcSpec('text', '文本',
      defaults: {'text': '一段文本', 'fontSize': 16, 'color': '#222435'},
      fields: ['text', 'fontSize', 'bold', 'color', 'textAlign', 'width', 'padding', 'margin', 'bg', 'radius']),
  'button': LcSpec('button', '按钮',
      defaults: {'text': '按钮', 'bg': '#058654', 'color': '#FFFFFF', 'radius': 8, 'padding': 12, 'fontSize': 16},
      fields: ['text', 'fontSize', 'bg', 'color', 'radius', 'padding', 'width', 'margin']),
  'image': LcSpec('image', '图片',
      defaults: {'src': '', 'height': 160, 'radius': 8, 'width': 'fill'},
      fields: ['src', 'width', 'height', 'radius', 'margin']),
  'input': LcSpec('input', '输入框',
      defaults: {'placeholder': '请输入', 'radius': 8, 'width': 'fill'},
      fields: ['placeholder', 'width', 'radius', 'margin']),
  'list': LcSpec('list', '列表',
      defaults: {'items': ['第一项', '第二项', '第三项'], 'fontSize': 16, 'color': '#222435'},
      fields: ['items', 'fontSize', 'color', 'width', 'padding', 'margin', 'bg', 'radius']),
  'divider': LcSpec('divider', '分割线', defaults: {}, fields: ['margin']),
  'spacer': LcSpec('spacer', '间隔', defaults: {'size': 16}, fields: ['size']),
};

/// 组件面板里可拖出来的类型（page 只能是根）。
const List<String> lcPaletteTypes = [
  'container', 'row', 'column', 'card', 'text', 'button', 'image', 'input', 'list', 'divider', 'spacer',
];

class LcDocument {
  LcDocument({required this.title, required this.root}) {
    _normalizeIds();
  }

  static const int currentVersion = 1;

  String title;
  LcNode root;
  int _nextId = 1;

  factory LcDocument.starter(String title) => LcDocument(
    title: title,
    root: LcNode(id: 'root', type: 'page', props: Map.of(lcSpecs['page']!.defaults), children: [
      LcNode(id: '', type: 'text', props: {'text': title, 'fontSize': 24, 'bold': true, 'color': '#222435'}),
      LcNode(id: '', type: 'text', props: {'text': '从下方组件栏拖一个组件上来，或点一下直接添加。', 'fontSize': 16, 'color': '#5C6479'}),
      LcNode(id: '', type: 'card', props: Map.of(lcSpecs['card']!.defaults), children: [
        LcNode(id: '', type: 'input', props: Map.of(lcSpecs['input']!.defaults)),
        LcNode(id: '', type: 'button', props: {...lcSpecs['button']!.defaults, 'text': '提交'}),
      ]),
    ]),
  );

  factory LcDocument.fromJson(Map<String, dynamic> json) {
    final rootJson = json['root'];
    if (rootJson is! Map<String, dynamic>) {
      throw const FormatException('缺少 root');
    }
    final root = LcNode.fromJson(rootJson, 0);
    if (root.type != 'page') {
      throw const FormatException('根组件必须是 page');
    }
    return LcDocument(
      title: json['title'] is String ? json['title'] as String : '未命名页面',
      root: root,
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
    'version': currentVersion,
    'title': title,
    'root': root.toJson(),
  };

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

  LcNode newNode(String type) => LcNode(
    id: 'n${_nextId++}',
    type: type,
    props: jsonDecode(jsonEncode(lcSpecs[type]!.defaults)) as Map<String, dynamic>,
  );

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

  bool _contains(LcNode ancestor, String id) =>
      ancestor.id == id || ancestor.children.any((c) => _contains(c, id));

  /// 把节点插到某个容器的指定位置；返回是否成功。
  bool insert(String parentId, LcNode node, [int? index]) {
    final parent = find(parentId);
    if (parent == null || !parent.isContainer || node.type == 'page') return false;
    final i = (index ?? parent.children.length).clamp(0, parent.children.length);
    parent.children.insert(i, node);
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
    newParent.children.insert(i.clamp(0, newParent.children.length), node);
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

/// 撤销 / 重做：存整份 JSON 快照，简单可靠。
class LcHistory {
  LcHistory(LcDocument initial) : _undo = [initial.encode()];
  final List<String> _undo;
  final List<String> _redo = [];
  static const int limit = 100;

  bool get canUndo => _undo.length > 1;
  bool get canRedo => _redo.isNotEmpty;

  /// 每次修改之后调用。
  void record(LcDocument doc) {
    final snap = doc.encode();
    if (snap == _undo.last) return;
    _undo.add(snap);
    if (_undo.length > limit) _undo.removeAt(0);
    _redo.clear();
  }

  LcDocument? undo() {
    if (!canUndo) return null;
    _redo.add(_undo.removeLast());
    return LcDocument.parse(_undo.last);
  }

  LcDocument? redo() {
    if (!canRedo) return null;
    final snap = _redo.removeLast();
    _undo.add(snap);
    return LcDocument.parse(snap);
  }
}
