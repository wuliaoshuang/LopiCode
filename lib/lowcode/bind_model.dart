/// 数据绑定的数据模型（第 5 期；设计见 docs/blocks-v5-parts/E-editor-components.md §10.8、D 分册第 4 节）。
///
/// 绑定是**控件上的设置**，不是积木。8 种，都存在节点上（这一版的模型不解释这些字段，它们原样待在 `LcNode.more` 里）：
///
/// | 绑定 | 字段 | 写法 |
/// | --- | --- | --- |
/// | 文字、属性 | `data` | `{属性名: 来源}` |
/// | 显示条件 | `showIf` | 来源（不成立时看不见，东西还在） |
/// | 存在条件 | `renderIf` | 来源（不成立时真的没有） |
/// | 重复 | `repeat` | `{list: 来源, item: 名字, index: 名字, key: 来源, empty: 文字, preview: 画布画几份}` |
/// | 类名开关 | `classIf` | `[{name: 类名, when: 来源}]` |
/// | 样式 | `styles` | `{CSS 属性名: 来源}` |
/// | 双向 | `model` | `{state: 状态名}` |
///
/// **来源**三种写法：`{"from": "const", …}`（写死，等于没绑）、`{"from": "var", "name": 名字, "path": [格子…]}`
/// （用一个值；`path` 可省，取记录里的一格）、`{"from": "expr", "expr": 值式子}`（值式子就是积木的值的存法：
/// text / num / bool / var / bin / not / join，另加一个 `len`＝列表有几项）。
/// 名字先找“重复”带出来的这一项 / 序号，再找这一页的状态，最后找项目级状态。
///
/// 这里只管读写；算值在 bind_eval.dart，翻成 JS 在 bind_js.dart，检查在 bind_check.dart。
library;

import 'package:lopicode/lowcode/logic_expr.dart';
import 'package:lopicode/lowcode/model.dart';

const String kLcData = 'data';
const String kLcShowIf = 'showIf';
const String kLcRenderIf = 'renderIf';
const String kLcRepeat = 'repeat';
const String kLcClassIf = 'classIf';
const String kLcStyles = 'styles';
const String kLcModel = 'model';

/// 节点上所有和绑定有关的字段。
const List<String> kLcBindFields = [kLcData, kLcShowIf, kLcRenderIf, kLcRepeat, kLcClassIf, kLcStyles, kLcModel];

/// 类名开关的类名、“这一项 / 序号”的名字要合的规矩。
final RegExp kLcClassName = RegExp(r'^[A-Za-z_][A-Za-z0-9_-]{0,47}$');
final RegExp kLcLocalName = RegExp(r'^[A-Za-z_][A-Za-z0-9_]{0,31}$');

/// 能绑样式的 CSS 属性名（小写连字符）。
final RegExp kLcCssProp = RegExp(r'^[a-z][a-z-]{0,47}$');

// —— 来源 ——

Map<String, dynamic> lcSrcVar(String name, [List<String> path = const []]) => {'from': 'var', 'name': name, if (path.isNotEmpty) 'path': path};
Map<String, dynamic> lcSrcExpr(Map<String, dynamic> expr) => {'from': 'expr', 'expr': expr};

/// 读一个值（可带路径）的值式子。
Map<String, dynamic> exRead(String name, [List<String> path = const []]) => {'e': 'var', 'name': name, if (path.isNotEmpty) 'path': path};

/// 列表有几项。
Map<String, dynamic> exLen(Map<String, dynamic> x) => {'e': 'len', 'x': x};

/// 路径（记录里一格一格往下）；坏的当没有。
List<String> lcPathOf(Object? raw) => [
  if (raw is List)
    for (final p in raw)
      if (p is String && p.isNotEmpty) p,
];

/// 把来源化成一个值式子；写死的、读不懂的返回 null（＝没绑）。
Map<String, dynamic>? lcSrcExprOf(Object? src) {
  if (src is! Map) return null;
  switch (src['from']) {
    case 'var':
      final name = src['name'];
      return name is String && name.isNotEmpty ? exRead(name, lcPathOf(src['path'])) : null;
    case 'expr':
      final e = src['expr'];
      return isExpr(e) ? Map<String, dynamic>.from(e as Map) : null;
  }
  return null;
}

/// 是不是“绑着”（不是写死、也读得懂）。
bool lcIsBoundSrc(Object? src) => lcSrcExprOf(src) != null;

// —— 文字 / 属性 ——

/// 这个属性绑的来源（原样）；没绑返回 null。
Object? lcDataSrc(LcNode n, String prop) {
  final data = n.more[kLcData];
  final src = data is Map ? data[prop] : null;
  return lcIsBoundSrc(src) ? src : null;
}

Map<String, dynamic>? lcDataExpr(LcNode n, String prop) => lcSrcExprOf(lcDataSrc(n, prop));

/// 绑上 / 解除（[src] 给 null）。别的属性、读不懂的条目原样留着；空了字段去掉。
void lcSetData(LcNode n, String prop, Map<String, dynamic>? src) => _setIn(n, kLcData, prop, src);

/// 这个节点上绑着的属性名。
List<String> lcBoundProps(LcNode n) {
  final data = n.more[kLcData];
  return [
    if (data is Map)
      for (final e in data.entries)
        if (e.key is String && lcIsBoundSrc(e.value)) e.key as String,
  ];
}

void _setIn(LcNode n, String field, String key, Object? value) {
  final old = n.more[field];
  final map = <String, dynamic>{
    if (old is Map)
      for (final e in old.entries) '${e.key}': e.value,
  };
  if (value == null) {
    map.remove(key);
  } else {
    map[key] = value;
  }
  if (map.isEmpty) {
    n.more.remove(field);
  } else {
    n.more[field] = map;
  }
}

// —— 显示条件 / 存在条件 ——

Map<String, dynamic>? lcShowIfExpr(LcNode n) => lcSrcExprOf(n.more[kLcShowIf]);
Map<String, dynamic>? lcRenderIfExpr(LcNode n) => lcSrcExprOf(n.more[kLcRenderIf]);

/// [field]：[kLcShowIf] 或 [kLcRenderIf]。
void lcSetCond(LcNode n, String field, Map<String, dynamic>? src) {
  if (src == null) {
    n.more.remove(field);
  } else {
    n.more[field] = src;
  }
}

// —— 重复 ——

/// 画布上一个“重复”最多画几份。
const int kLcRepeatPreviewMax = 5;

class LcRepeat {
  const LcRepeat({required this.list, this.item = 'item', this.index = 'i', this.key, this.empty, this.preview = 3});

  /// 列表从哪儿来（值式子）。
  final Map<String, dynamic> list;

  /// “这一项”“序号”在里面叫什么。
  final String item;
  final String index;

  /// 每项的标识（值式子，里面能用这一项和序号）；null＝没给。
  final Map<String, dynamic>? key;

  /// 列表是空的时候显示的一句话；null＝什么都不显示。
  final String? empty;

  /// 画布上先画几份（1–[kLcRepeatPreviewMax]）。
  final int preview;

  /// 标识是不是就用的序号（React / Vue 都不建议：增删挪动时会认错项）。
  bool get keyIsIndex => key != null && key!['e'] == 'var' && key!['name'] == index && lcPathOf(key!['path']).isEmpty;
}

LcRepeat? lcRepeatOf(LcNode n) {
  final r = n.more[kLcRepeat];
  if (r is! Map) return null;
  final list = lcSrcExprOf(r['list']);
  if (list == null) return null;
  final item = r['item'], index = r['index'], empty = r['empty'], preview = r['preview'];
  final itemName = item is String && kLcLocalName.hasMatch(item) ? item : 'item';
  var indexName = index is String && kLcLocalName.hasMatch(index) ? index : 'i';
  if (indexName == itemName) indexName = '${itemName}_i';
  return LcRepeat(
    list: list,
    item: itemName,
    index: indexName,
    key: lcSrcExprOf(r['key']),
    empty: empty is String && empty.isNotEmpty ? empty : null,
    preview: preview is int ? preview.clamp(1, kLcRepeatPreviewMax) : 3,
  );
}

/// 设 / 改“重复”（[listSrc] 给 null＝去掉）。字段里别的键原样留着。
void lcSetRepeat(LcNode n, {required Map<String, dynamic>? listSrc, String? item, String? index, Map<String, dynamic>? keySrc, String? empty, int? preview}) {
  if (listSrc == null) {
    n.more.remove(kLcRepeat);
    return;
  }
  final old = n.more[kLcRepeat];
  final map = <String, dynamic>{
    if (old is Map)
      for (final e in old.entries) '${e.key}': e.value,
    'list': listSrc,
    'item': item ?? 'item',
    'index': index ?? 'i',
  };
  void put(String k, Object? v) => v == null ? map.remove(k) : map[k] = v;
  put('key', keySrc);
  put('empty', empty == null || empty.isEmpty ? null : empty);
  put('preview', preview);
  n.more[kLcRepeat] = map;
}

// —— 类名开关 / 样式 ——

class LcClassIf {
  const LcClassIf(this.name, this.when);
  final String name;
  final Map<String, dynamic> when;
}

List<LcClassIf> lcClassIfOf(LcNode n) {
  final raw = n.more[kLcClassIf];
  final seen = <String>{};
  return [
    if (raw is List)
      for (final item in raw)
        if (item is Map && item['name'] is String && kLcClassName.hasMatch(item['name'] as String) && seen.add(item['name'] as String))
          if (lcSrcExprOf(item['when']) case final cond?) LcClassIf(item['name'] as String, cond),
  ];
}

/// 加 / 改 / 去掉（[when] 给 null）一条类名开关。读不懂的条目原样留着。
void lcSetClassIf(LcNode n, String name, Map<String, dynamic>? when) {
  final raw = n.more[kLcClassIf];
  final list = <dynamic>[
    if (raw is List)
      for (final item in raw)
        if (!(item is Map && item['name'] == name)) item,
    ?(when == null ? null : {'name': name, 'when': when}),
  ];
  if (list.isEmpty) {
    n.more.remove(kLcClassIf);
  } else {
    n.more[kLcClassIf] = list;
  }
}

/// 样式绑定：CSS 属性名 → 值式子。
Map<String, Map<String, dynamic>> lcStyleBinds(LcNode n) {
  final raw = n.more[kLcStyles];
  return {
    if (raw is Map)
      for (final e in raw.entries)
        if (e.key is String && kLcCssProp.hasMatch(e.key as String))
          e.key as String: ?lcSrcExprOf(e.value),
  };
}

void lcSetStyleBind(LcNode n, String cssProp, Map<String, dynamic>? src) => _setIn(n, kLcStyles, cssProp, src);

// —— 双向 ——

/// 双向绑到哪个状态；没有返回 null。
String? lcModelOf(LcNode n) {
  final m = n.more[kLcModel];
  final s = m is Map ? m['state'] : null;
  return s is String && s.isNotEmpty ? s : null;
}

void lcSetModel(LcNode n, String? state) {
  if (state == null) {
    n.more.remove(kLcModel);
  } else {
    n.more[kLcModel] = {'state': state};
  }
}

/// 双向绑的是这个控件的哪个属性；这种控件不能双向返回 null。
String? lcModelProp(String type) => switch (type) {
  'input' || 'textarea' || 'radio' || 'select' => 'value',
  'switch' || 'checkbox' => 'checked',
  _ => null,
};

/// 这个节点上有没有任何绑定。
bool lcHasBindings(LcNode n) => kLcBindFields.any(n.more.containsKey) && (lcBoundProps(n).isNotEmpty || lcShowIfExpr(n) != null || lcRenderIfExpr(n) != null || lcRepeatOf(n) != null || lcClassIfOf(n).isNotEmpty || lcStyleBinds(n).isNotEmpty || lcModelOf(n) != null);

/// 这棵树里有没有任何绑定。
bool lcTreeHasBindings(LcNode root) {
  if (lcHasBindings(root)) return true;
  for (final c in root.children) {
    if (lcTreeHasBindings(c)) return true;
  }
  return false;
}

// —— 哪些属性能绑 ——

/// 一个能绑的属性。[type]：text / number / bool / list（对不上的状态在面板里灰掉）。
class LcBindable {
  const LcBindable(this.prop, this.label, this.type);
  final String prop;
  final String label;
  final String type;
}

/// 这种控件有哪些属性能绑（不含双向的那个，双向单独算）。组件实例的属性值这一期不绑（留给第 6 期）。
List<LcBindable> lcBindablesOf(String type) => switch (type) {
  'text' => const [LcBindable('text', '文字', 'text')],
  'button' => const [LcBindable('text', '文字', 'text'), LcBindable('disabled', '禁用', 'bool')],
  'image' => const [LcBindable('src', '图片地址', 'text'), LcBindable('alt', '说明文字', 'text')],
  'input' || 'textarea' => const [LcBindable('placeholder', '提示文字', 'text'), LcBindable('disabled', '禁用', 'bool')],
  'checkbox' => const [LcBindable('text', '文字', 'text'), LcBindable('disabled', '禁用', 'bool')],
  'switch' || 'radio' || 'select' => const [LcBindable('disabled', '禁用', 'bool')],
  'list' => const [LcBindable('items', '列表内容', 'list')],
  'listItem' => const [LcBindable('title', '标题', 'text'), LcBindable('subtitle', '副标题', 'text'), LcBindable('trailing', '右侧文字', 'text')],
  'appBar' => const [LcBindable('title', '标题', 'text')],
  'dialog' => const [LcBindable('title', '标题', 'text'), LcBindable('text', '正文', 'text')],
  _ => const [],
};

LcBindable? lcBindable(String type, String prop) {
  for (final b in lcBindablesOf(type)) {
    if (b.prop == prop) return b;
  }
  return null;
}

/// 这种控件能不能带“重复”“显示条件”“存在条件”“类名开关”“样式”（页面本身、弹窗、插槽占位、不认识的不行）。
bool lcCanWrapBind(LcNode n) => !n.isUnknown && n.type != 'page' && n.type != 'slot' && n.type != 'dialog';
