/// Vue / React 两种导出共用的部分：导出结果的数据类、起名（组件名、变量名）、基础 CSS、
/// “哪些控件属性被逻辑用到了”的登记、自定义组件的展开计划、事件处理的归类。
///
/// 两种导出各自只管“标签和绑定怎么写”（export_vue.dart / export_react.dart），其余都从这里拿，
/// 保证同一页导出来的两份代码结构、命名、简化项一致。
library;

import 'dart:convert';

import 'package:lopicode/format/format.dart';
import 'package:lopicode/lowcode/component_model.dart';
import 'package:lopicode/lowcode/export_theme_bp.dart';
import 'package:lopicode/lowcode/export_v3_fields.dart';
import 'package:lopicode/lowcode/export_web_v3.dart';
import 'package:lopicode/lowcode/export_web_v3_css.dart';
import 'package:lopicode/lowcode/logic_blocks.dart';
import 'package:lopicode/lowcode/logic_js_core.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:lopicode/lowcode/logic_text.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/slots.dart';
import 'package:lopicode/lowcode/style_resolve.dart';

/// 导出的一个文件。[path] 相对导出目录（`LcPage.vue`、`components/TitleCard.vue`），一律用 `/`。
class LcExportFile {
  const LcExportFile({required this.path, required this.content, this.formatProblem});
  final String path;
  final String content;

  /// 这个文件没能排版时的原因（这时 [content] 是没排版的原文）；排好了是 null。
  final String? formatProblem;

  int get lineCount => content.isEmpty ? 0 : '\n'.allMatches(content).length + (content.endsWith('\n') ? 0 : 1);
}

/// 一次导出的全部文件，和导出时跳过 / 简化了什么（人话，给面板显示）。
class LcFrameworkExport {
  const LcFrameworkExport({required this.files, required this.notes});
  final List<LcExportFile> files;
  final List<String> notes;

  LcExportFile? file(String path) {
    for (final f in files) {
      if (f.path == path) return f;
    }
    return null;
  }
}

/// 把生成的代码过一遍格式化；排不了就用原文并带上原因。
LcExportFile lcFormatted(String path, String source, String language) {
  final r = formatCode(source, language);
  return LcExportFile(path: path, content: r.text, formatProblem: r.problem);
}

/// 走节点树时的保险：正常数据最多 24 层，内存里被改坏的也不许把栈撑爆。
const int kExportMaxDepth = 64;

const String kExportHeader = '由 LopiCode 低代码搭建器生成，重新导出会覆盖本文件。';

/// 基础样式：和 export_html.dart 的那套 `.lc-*` 规则等价，两处不同——
/// 1. 不写 `*` 和 `body`：导出的是放进别人工程里的组件，不该改到组件以外的元素。
///    `box-sizing` 改成点名给我们自己的类；字体和文字颜色挪到最外层的 `.lc-page` 上。
/// 2. 多一个 `.lc-component`（自定义组件实例的类）。
const String kFrameworkBaseCss =
    '''.lc-page, .lc-container, .lc-row, .lc-column, .lc-card, .lc-text, .lc-button, .lc-image, .lc-input, .lc-list, .lc-divider, .lc-spacer, .lc-component { box-sizing: border-box; }
.lc-page {
  font-family: system-ui, -apple-system, "PingFang SC", "Noto Sans SC", sans-serif;
  color: #222435;
}
.lc-page, .lc-container, .lc-column, .lc-card { display: flex; flex-direction: column; }
.lc-row { display: flex; flex-direction: row; }
.lc-page { min-height: 100vh; }
.lc-card { box-shadow: 0 1px 3px rgba(0, 0, 0, .2); }
.lc-text { margin: 0; line-height: 1.5; }
.lc-button { border: 0; cursor: pointer; font: inherit; }
.lc-input { border: 1px solid #b1c0c8; font: inherit; padding: 10px 12px; min-width: 0; }
.lc-image { display: block; max-width: 100%; object-fit: cover; background: #d3dee4; }
.lc-list { margin: 0; padding-left: 20px; line-height: 1.75; }
.lc-divider { border: 0; border-top: 1px solid #d3dee4; margin: 0; align-self: stretch; }
''';

const String kNoteBody = '字体和文字颜色写在页面最外层的元素上，没有去动 body；想去掉浏览器默认的页边距，在你工程的全局样式里加一条 body { margin: 0 }。';
const String kNoteStraySlot = '页面里有插槽占位（它只在自定义组件里有用），导出时只留了它里面的内容。';
const String kNoteHomeless = '有组件实例带着填好的内容，可它的组件定义里已经没有插槽了，这些内容没有导出（页面文件里还留着）。';
const String kNoteUnknownNode = '页面里有新版应用加的组件，这一版不认识，没有导出。';
const String kNoteNoBinding = '变量改了以后界面不会自己跟着变（页面里没有“把变量显示出来”的写法，和导出的网页一样）；要让界面变，用“改控件”积木。';

// —— 起名 ——

/// 不能拿来当组件名的：会盖住生成的代码里要用的全局对象，或是框架自己的内置组件，或是 Windows 上不能当文件名的。
const Set<String> _reservedComponentNames = {
  'String', 'Number', 'Boolean', 'Object', 'Array', 'Math', 'JSON', 'Error', 'Promise', 'Date', 'Map', 'Set', 'Symbol', 'RegExp', 'Function', 'React', 'Infinity', 'NaN', //
  'Transition', 'TransitionGroup', 'KeepAlive', 'Teleport', 'Suspense', 'Component', 'Slot', 'Template', 'Fragment', 'Con', 'Prn', 'Aux', 'Nul',
};

/// 一段文字 → 合法的大驼峰英文名（当组件名和文件名用）。非英文数字的字符都丢掉，丢光了就用 [fallback]。
String lcPascalName(String raw, {required String fallback}) {
  final parts = raw.split(RegExp('[^A-Za-z0-9]+')).where((s) => s.isNotEmpty);
  var name = parts.map((s) => s[0].toUpperCase() + s.substring(1)).join();
  if (name.length > 40) name = name.substring(0, 40);
  if (name.isEmpty) return fallback;
  if (RegExp('^[0-9]').hasMatch(name)) name = 'Lc$name';
  if (_reservedComponentNames.contains(name)) name = '${name}View';
  return name;
}

/// 页面导出的组件名 / 文件名：标题转出来的，转不出来叫 `LcPage`。
String lcPageName(LcDocument doc) => lcPascalName(doc.title, fallback: 'LcPage');

/// 生成的脚本里已经有主的名字：浏览器全局对象、框架的函数、处理函数的参数。页面变量不许叫这些。
const Set<String> kJsNamesInUse = {
  'event', 'alert', 'location', 'console', 'fetch', 'setTimeout', 'Math', 'Number', 'String', 'Error', 'JSON', 'Object', 'Promise', 'window', 'document', 'globalThis', //
  'ref', 'onMounted', 'defineProps', 'props', 'React', 'useState', 'useRef', 'useEffect', 'className', 'style',
};

/// 发名字的：保证每个名字都能当独立的 JS 变量名、不以 `lc` 开头（那是我们小工具的地盘）、互不重复。
class LcNames {
  LcNames([Iterable<String> reserved = const []]) : _used = {...reserved};
  final Set<String> _used;

  void reserve(String name) => _used.add(name);

  bool _free(String s) => isJsBindingName(s) && !s.startsWith('lc') && !_used.contains(s);

  /// 尽量用 [preferred]；不能用（保留字、撞名）就在后面加 `_tag`、`_tag2`…
  String take(String preferred, {String tag = 'x'}) {
    var base = preferred.replaceAll(RegExp('[^A-Za-z0-9_]'), '_');
    if (base.isEmpty || RegExp('^[0-9]').hasMatch(base)) base = '_$base';
    if (base.startsWith('lc')) base = 'v_$base';
    if (base == '__proto__') base = 'proto';
    var name = base;
    for (var n = 1; !_free(name); n++) {
      name = n == 1 ? '${base}_$tag' : '${base}_$tag$n';
    }
    _used.add(name);
    return name;
  }
}

/// 变量的初始值写成 JS 字面量。按声明的类型再收一遍（内存里的对象可能被改得类型对不上）。
String lcInitialLiteral(LcVariable v) => lcValueLiteral(v.type, v.initial);

String lcValueLiteral(String type, Object? value) => switch (type) {
  'number' => value is num && value.isFinite ? (value is int || value == value.roundToDouble() && value.abs() < 1e15 ? '${value.round()}' : '$value') : '0',
  'bool' => value == true ? 'true' : 'false',
  'list' => lcJsonLiteral(value is List ? value : const <Object?>[]),
  'record' => lcJsonLiteral(value is Map ? value : const <String, Object?>{}),
  _ => jsString(value is String ? value : ''),
};

/// 列表 / 记录的初值写成 JS 字面量（就是 JSON；`<` 和行分隔符转义掉，放进网页、Vue 文件里都不会把文件截断）。
String lcJsonLiteral(Object? value) {
  String text;
  try {
    text = jsonEncode(value);
  } on Object {
    text = value is List ? '[]' : '{}';
  }
  return text.replaceAll('<', r'\u003c').replaceAll('\u2028', r'\u2028').replaceAll('\u2029', r'\u2029');
}

// —— 类名和 CSS ——

String _safeId(String id) => isSafeNodeId(id) ? id : id.replaceAll(RegExp('[^A-Za-z0-9_]'), '_');

/// 节点在模板里的 class。[prefix]：页面节点是空串；组件定义里的节点是 `<组件 id>-`，免得和页面节点撞名。
String lcNodeClass(LcNode n, String prefix) => '${lcTypeClass(n.type)} n-$prefix${_safeId(n.id)}';

/// 组件定义里的节点用的前缀。
String lcComponentPrefix(LcComponentDef def) => '${_safeId(def.id)}-';

/// 把一棵节点树的 CSS 规则（每个节点一条）收集起来。样式值里要是有会把 CSS / Vue 文件截断的字符
/// （模型读文件时已经挡掉，这里防的是内存里被改坏的），这条规则不写并记一笔。
///
/// 插槽（[plans] 给了才认）：占位节点自己没有规则，它里面的默认内容、实例里填进来的内容，
/// “父容器”都按占位节点所在的那个容器算（撑满、对齐这些规则跟着它走）。
String lcCollectCss(LcNode root, String prefix, List<String> notes, {LcComponentPlans? plans}) {
  final out = StringBuffer();
  final bp = LcBpCss();
  void walk(LcNode n, LcNode? parent, int depth) {
    if (depth > kExportMaxDepth) return;
    if (n.type == 'slot') {
      for (final c in n.children) {
        walk(c, parent, depth + 1);
      }
      return;
    }
    final body = nodeCssDeclarations(n, parent);
    if (RegExp(r'[{}<>\n\r\\]|\*/|/\*').hasMatch(body)) {
      notes.add('${lcSpecs[n.type]?.label ?? n.type}（${_safeId(n.id)}）的样式里有不能写进 CSS 的字符，这个控件的样式没有导出。');
    } else if (body.isNotEmpty) {
      out.writeln('.n-$prefix${_safeId(n.id)} { $body }');
    }
    lcStateRules(n, '.n-$prefix${_safeId(n.id)}').forEach(out.writeln);
    bp.add(n, parent, '.n-$prefix${_safeId(n.id)}');
    final fieldRule = lcFieldRule(n, parent, '.n-$prefix${_safeId(n.id)}');
    if (fieldRule.isNotEmpty) out.writeln(fieldRule);
    for (final c in n.children) {
      walk(c, n.type == 'component' ? plans?.slotContainer(n, c) ?? n : n, depth + 1);
    }
  }

  walk(root, null, 0);
  // 第 3 版加的属性要的公共样式：用到了才写。
  out.write(lcV3ExtraCss(root));
  // 断点的规则放最后（同样的选择器，后写的赢）。
  out.write(bp.css());
  return out.toString();
}

/// 带标签的输入框外面那一层的 class（见 export_v3_fields.dart）。
String lcFieldClassOf(LcNode n, String prefix) => lcFieldClass('n-$prefix${_safeId(n.id)}');

// —— 被逻辑用到的控件属性 ——

/// 一个“会被逻辑读或改”的控件属性：导出时变成一份响应式状态，模板里绑定它。
class LcPropState {
  const LcPropState(this.node, this.prop, this.name, this.initialJs);
  final LcNode node;
  final String prop;

  /// 状态的名字（Vue：一个 ref 变量；React：`lcUi` 对象里的键）。
  final String name;

  /// 初值的 JS 字面量，取自模型。背景色 / 文字颜色初值是空串＝“先用样式表里的”。
  final String initialJs;
}

/// 登记簿：翻逻辑的时候用到一个登记一个；之后生成模板时来查“这个节点的这个属性要不要绑定”。
class LcPropStates {
  LcPropStates(this._names);
  final LcNames _names;
  final Map<String, LcPropState> _byKey = {};

  static String _key(LcNode n, String prop) => '${n.id}\u0000$prop';

  LcPropState require(LcNode node, String prop) => _byKey.putIfAbsent(_key(node, prop), () => LcPropState(node, prop, _names.take('${_safeId(node.id)}_$prop', tag: 'ui'), _initial(node, prop)));

  LcPropState? of(LcNode node, String prop) => _byKey[_key(node, prop)];

  Iterable<LcPropState> get all => _byKey.values;
  bool get isEmpty => _byKey.isEmpty;

  static String _initial(LcNode n, String prop) => switch (prop) {
    'text' || 'src' || 'placeholder' => jsString(n.strProp(prop) ?? ''),
    // 弹窗一开始显不显示看它的 `open`；别的组件一开始都是显示的。
    'visible' => n.type == 'dialog' && n.props['open'] != true ? 'false' : 'true',
    _ => '""',
  };
}

/// 控件不支持这个属性时的说明（和导出网页时的说法一致）。
String lcPropUnfitReason(LcNode node, String prop, {required bool write}) {
  final label = lcSpecs[node.type]?.label ?? node.type;
  if (prop == 'text') return write ? '$label的文字不能用积木改（它里面是别的内容，整段换文字会把里面的内容冲掉）' : '$label的文字读不出来，这里当成空的';
  return '$label没有“${describeProp(prop)}”';
}

// —— 事件处理 ——

class LcHandlerPlan {
  LcHandlerPlan(this.names, this.byNode, this.load);

  /// 和 `doc.logic.handlers` 一一对应的函数名。
  final List<String> names;

  /// 控件 id → 事件（click / input）→ 要调用的处理函数名（按声明顺序）。
  final Map<String, Map<String, List<String>>> byNode;

  /// “页面打开时”要调用的处理函数名。
  final List<String> load;

  List<String> of(LcNode n, String event) => byNode[n.id]?[event] ?? const [];
}

LcHandlerPlan lcPlanHandlers(LcDocument doc, List<String> notes) {
  final names = logicHandlerNames(doc);
  final byNode = <String, Map<String, List<String>>>{};
  final load = <String>[];
  for (var i = 0; i < doc.logic.handlers.length; i++) {
    final h = doc.logic.handlers[i];
    final target = h.target;
    final node = target == null ? null : doc.find(target);
    if (h.event == 'load') {
      load.add(names[i]);
    } else if ((h.event != 'click' && h.event != 'input') || node == null || !isSafeNodeId(node.id)) {
      notes.add('处理「${describeHandler(h, doc)}」没有挂到任何控件上（触发它的控件不在页面里），函数还在文件里。');
    } else {
      byNode.putIfAbsent(node.id, () => {}).putIfAbsent(h.event, () => []).add(names[i]);
    }
  }
  return LcHandlerPlan(names, byNode, load);
}

// —— 自定义组件 ——

/// 组件的 prop 不能叫这些（框架自己要用，或者我们生成的代码里已经有主了），撞了就改名。
const Set<String> _reservedPropNames = {'key', 'ref', 'class', 'style', 'className', 'children', 'is', 'slot', 'event', 'props'};

/// 一个要导出的组件定义：导出后叫什么、它的每个 prop 在代码里叫什么。
class LcComponentPlan {
  LcComponentPlan(this.def, this.name, this.attrs, this.slotAttrs);
  final LcComponentDef def;

  /// 插槽名 → React 里接它的 prop 名（默认插槽是 `children`；别的绝大多数就是插槽名，撞了保留字 / 别的 prop 的会加后缀）。
  final Map<String, String> slotAttrs;

  /// 实例里填的内容按插槽分好（按定义里插槽的先后；没填的插槽不在里面）。没写 `slot` 或写错的算在兜底插槽里。
  /// 定义里一个插槽都没有时是空的（实例带着的子节点没地方放）。
  Map<String, List<LcNode>> filled(LcNode instance) {
    final slots = def.slots;
    if (slots.isEmpty || instance.children.isEmpty) return const {};
    final names = {for (final s in slots) s.name};
    final fallback = names.contains(kLcDefaultSlot) ? kLcDefaultSlot : slots.first.name;
    final out = <String, List<LcNode>>{};
    for (final s in slots) {
      final mine = [
        for (final c in instance.children)
          if ((names.contains(c.slot) ? c.slot : fallback) == s.name) c,
      ];
      if (mine.isNotEmpty) out[s.name] = mine;
    }
    return out;
  }

  /// 组件名 / 文件名（大驼峰，互不重复，也不和页面重名）。
  final String name;

  /// prop 名 → 代码里用的名字（绝大多数时候一样；撞了保留字的会加后缀）。
  final Map<String, String> attrs;
}

class LcComponentPlans {
  LcComponentPlans._(this.all, this._byId, this._broken);

  /// 页面用到的组件（含组件里再用到的），按第一次出现的顺序。
  final List<LcComponentPlan> all;
  final Map<String, LcComponentPlan> _byId;
  final Set<String> _broken;

  static String _edge(String ownerId, LcNode instance) => '$ownerId\u0000${instance.id}';

  /// 实例指向的组件；定义不存在、或这条引用会造成“自己套自己”时返回 null（调用方生成注释占位）。
  /// [ownerId]：这个实例所在的组件定义的 id；页面里的实例传 null。
  LcComponentPlan? planFor(LcNode instance, {String? ownerId}) {
    if (ownerId != null && _broken.contains(_edge(ownerId, instance))) return null;
    final ref = instance.props['ref'];
    return ref is String ? _byId[ref] : null;
  }

  LcComponentPlan? planOf(String componentId) => _byId[componentId];

  /// 实例里填的这个子节点，实际排在定义里的哪个容器里（插槽占位节点所在的那个）；找不到返回 null。
  LcNode? slotContainer(LcNode instance, LcNode child) {
    final ref = instance.props['ref'];
    final plan = ref is String ? _byId[ref] : null;
    if (plan == null) return null;
    String? name;
    plan.filled(instance).forEach((slot, kids) {
      if (kids.contains(child)) name = slot;
    });
    if (name == null) return null;
    LcNode? found;
    void walk(LcNode n, int depth) {
      if (found != null || depth > kExportMaxDepth) return;
      for (final c in n.children) {
        if (c.type == 'slot' && lcSlotNameOf(c) == name) {
          found = n;
          return;
        }
        walk(c, depth + 1);
      }
    }

    walk(plan.def.root, 0);
    return found;
  }

  /// 从页面出发把用到的组件都找出来。找不到定义的、循环引用的各记一条说明。
  /// [fixedNames]：多页面导出时每个组件叫什么已经全项目定好了（组件 id → 名字，见 export_pages.dart），各页照着用。
  static LcComponentPlans build(LcDocument doc, {required String pageName, required List<String> notes, Map<String, String>? fixedNames}) {
    final all = <LcComponentPlan>[];
    final byId = <String, LcComponentPlan>{};
    final broken = <String>{};
    final names = <String>{pageName};
    final stack = <String>[];

    void scan(LcNode n, String? ownerId, int depth) {
      if (depth > kExportMaxDepth) return;
      if (n.type == 'component') {
        final ref = n.props['ref'];
        final def = ref is String ? doc.component(ref) : null;
        if (def == null) {
          notes.add('有一个组件实例指向的组件定义找不到了（${ref is String ? _safeId(ref) : '没有填'}），导出的代码里那个位置只留了一行注释。');
        } else if (stack.contains(def.id)) {
          // 定义里（直接或绕一圈）又用到了自己：照着展开会没完没了，这一处不展开。
          if (ownerId != null) broken.add(_edge(ownerId, n));
          notes.add('组件「${jsComment(def.name, 30)}」里绕了一圈又用到了自己（循环引用），那个位置没有展开，只留了一行注释。');
        } else if (!byId.containsKey(def.id)) {
          var name = fixedNames?[def.id] ?? lcPascalName(def.name, fallback: 'LcComponent');
          final base = name;
          for (var i = 2; fixedNames?[def.id] == null && !names.add(name); i++) {
            name = '$base$i';
          }
          final attrNames = LcNames(_reservedPropNames);
          final propAttrs = {for (final p in def.props) p.name: RegExp('^on[A-Z]').hasMatch(p.name) ? attrNames.take('${p.name}Prop', tag: 'prop') : attrNames.take(p.name, tag: 'prop')};
          final plan = LcComponentPlan(def, name, propAttrs, {
            for (final s in def.slots) s.name: s.name == kLcDefaultSlot ? 'children' : attrNames.take(RegExp('^on[A-Z]').hasMatch(s.name) ? '${s.name}Slot' : s.name, tag: 'slot'),
          });
          byId[def.id] = plan;
          all.add(plan);
          stack.add(def.id);
          scan(def.root, def.id, depth + 1);
          stack.removeLast();
        }
      }
      for (final c in n.children) {
        scan(c, ownerId, depth + 1);
      }
    }

    scan(doc.root, null, 0);
    return LcComponentPlans._(all, byId, broken);
  }
}

/// 组件定义里的节点把 [prop] 接到了哪个 prop 上：返回代码里的名字；没接、或这种控件没有这个属性返回 null。
/// 接到了一个定义里没有的 prop 上：当作没接，记一条说明。
String? lcBoundAttr(LcComponentPlan plan, LcNode n, String prop, List<String> notes) {
  final bound = n.bind[prop];
  if (bound == null || !propFitsNode(prop, n.type)) return null;
  final attr = plan.def.prop(bound) == null ? null : plan.attrs[bound];
  if (attr == null) notes.add('组件「${jsComment(plan.def.name, 30)}」里有控件接到了一个不存在的属性（${_safeId(bound)}），那里按固定内容导出了。');
  return attr;
}

/// 接着的那个 prop 是不是文字类型（不是的话 React 里要先转成文字才能显示）。
bool lcBoundIsText(LcComponentPlan plan, LcNode n, String prop) {
  final type = plan.def.prop(n.bind[prop] ?? '')?.type;
  return type == 'text' || type == 'color';
}

/// 一个 prop 的默认值，按类型收过的 JS 字面量。
String lcPropDefaultLiteral(LcComponentProp p) => lcValueLiteral(p.type == 'color' ? 'text' : p.type, p.defaultValue);

/// 实例要传给组件的值：只传类型对得上、而且和默认值不一样的。返回（代码里的 prop 名, prop 定义, 值）。
List<(String, LcComponentProp, Object)> lcInstanceValues(LcComponentPlan plan, LcNode instance) {
  final values = instance.props['values'];
  if (values is! Map) return const [];
  final out = <(String, LcComponentProp, Object)>[];
  for (final p in plan.def.props) {
    final Object? v = values[p.name];
    final attr = plan.attrs[p.name];
    final fits = switch (p.type) {
      'number' => v is num && v.isFinite,
      'bool' => v is bool,
      'color' => v is String && RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(v),
      _ => v is String,
    };
    if (v == null || attr == null || !fits || v == p.defaultValue) continue;
    if (p.type == 'color' && v is String && v.toUpperCase() == p.defaultValue) continue;
    out.add((attr, p, v));
  }
  return out;
}

/// 注释占位里能安全出现的组件引用（只留字母数字下划线）。
String lcSafeRef(LcNode instance) {
  final ref = instance.props['ref'];
  final s = ref is String ? _safeId(ref) : '';
  return s.isEmpty ? '未填' : (s.length > 40 ? s.substring(0, 40) : s);
}
