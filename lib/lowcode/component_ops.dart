/// 自定义组件的纯逻辑：存成组件、改 props 和绑定、展开实例（给画布和导出用）、拆开、删除。
///
/// 约定（数据结构见 docs/lowcode-v2-design.md）：
/// - 改文档的函数都直接改传进来的 [LcDocument]（放在 `onEdit((d) => …)` 里调），失败时**什么都不改**，
///   返回带人话原因的 [LcOpResult]，不抛异常。
/// - 展开实例不改文档：返回一棵新的子树。展开后最外层节点的 id 就是实例自己的 id（这样选中框、拖柄、
///   挂在实例上的积木逻辑都还认得它），里面的节点是 `<实例 id>__<定义里的 id>`，全页唯一。
/// - 实例自己的 `width` / `margin` 属性和 `style` 盖在定义最外层节点之上。
library;

import 'package:lopicode/lowcode/component_model.dart';
import 'package:lopicode/lowcode/logic_edit.dart';
import 'package:lopicode/lowcode/model.dart';

/// 上限：组件名的字数、组件套组件的层数（再深不展开）、一个组件的属性个数、
/// 一次展开最多造多少个节点（超了的那部分实例不展开，画成占位，免得一不小心画出几万个节点）。
const int kComponentNameMax = 30;
const int kComponentNestMax = 8;
const int kComponentPropMax = 30;
const int kComponentExpandBudget = 4000;

final RegExp _hex = RegExp(r'^#[0-9a-fA-F]{6}$');

/// 一次操作的结果。[error] 为 null＝成功。
class LcOpResult {
  const LcOpResult.ok({this.nodeId, this.componentId}) : error = null, uses = 0;
  const LcOpResult.fail(String this.error, {this.uses = 0}) : nodeId = null, componentId = null;

  /// 失败的原因（给人看的）；成功是 null。
  final String? error;

  /// 这次操作新建 / 换掉的那个页面节点的 id（存成组件、插入实例、拆开时有）。
  final String? nodeId;

  /// 这次操作涉及的组件定义的 id（存成组件时是新定义的 id）。
  final String? componentId;

  /// 删除被拒绝时：还有多少个实例在用。
  final int uses;

  bool get ok => error == null;
}

/// 删除组件定义时，还在用它的实例怎么办：
/// refuse＝不删，返回使用次数；remove＝连实例一起删；detach＝先把实例拆开成普通控件再删。
enum LcDeleteInstances { refuse, remove, detach }

Object? _cloneValue(Object? v) => switch (v) {
  Map() => <String, dynamic>{
    for (final MapEntry(:key, :value) in v.entries)
      if (key is String) key: _cloneValue(value),
  },
  List() => [for (final x in v) _cloneValue(x)],
  _ => v,
};

Map<String, dynamic> _cloneProps(Map<String, dynamic> props) => {for (final e in props.entries) e.key: _cloneValue(e.value)};

/// 深拷贝一棵子树（不走 JSON 解析：解析有嵌套层数上限，这里的树是合法的，没必要再查一遍）。
LcNode copyLcTree(LcNode n, {bool keepBind = true}) => n.shell(
  props: _cloneProps(n.props),
  keepBind: keepBind,
  children: [for (final c in n.children) copyLcTree(c, keepBind: keepBind)],
);

void _walk(LcNode n, void Function(LcNode n) visit) {
  visit(n);
  for (final c in n.children) {
    _walk(c, visit);
  }
}

String? _refOf(LcNode n) {
  final ref = n.props['ref'];
  return n.type == 'component' && ref is String ? ref : null;
}

/// 数字 / 开关 / 文字 → 显示成文字（和导出的 JavaScript 里 `String(v)` 一样：3 不写成 3.0）。
String componentValueText(Object? v) => switch (v) {
  final num n => n == n.roundToDouble() && n.abs() < 1e15 ? '${n.round()}' : '$n',
  final bool b => b ? 'true' : 'false',
  final String s => s,
  _ => '',
};

/// 这个值能不能当这个 prop 的值（类型对不对）。
bool valueFitsProp(LcComponentProp p, Object? v) => _fit(p, v) != null;

Object? _fit(LcComponentProp p, Object? v) => switch (p.type) {
  'number' => v is num && v.isFinite ? v : null,
  'bool' => v is bool ? v : null,
  'color' => v is String && _hex.hasMatch(v) ? v.toUpperCase() : null,
  _ => v is String ? v : null,
};

/// 实例实际用的每个 prop 的值：传了而且类型对就用传的，否则用默认值。
Map<String, Object> instanceValues(LcComponentDef def, LcNode instance) {
  final raw = instance.props['values'];
  return {for (final p in def.props) p.name: _fit(p, raw is Map ? raw[p.name] : null) ?? p.defaultValue};
}

/// 实例有没有自己传这个 prop（传了而且类型对）。
bool instanceOverrides(LcComponentDef def, LcNode instance, String propName) {
  final raw = instance.props['values'];
  final p = def.prop(propName);
  return p != null && raw is Map && _fit(p, raw[propName]) != null;
}

/// 实例指向的组件名；找不到定义就叫“组件”。
String componentLabel(LcDocument doc, LcNode instance) {
  final ref = _refOf(instance);
  return (ref == null ? null : doc.component(ref)?.name) ?? '组件';
}

/// 某类型的控件有哪些属性可以接到组件的 prop 上（按这类控件属性面板里实际有的来）。
List<String> bindablePropsFor(String type) {
  if (type == 'component' || type == 'page') return const [];
  final fields = lcSpecs[type]?.fields ?? const <String>[];
  return [
    for (final p in LcNode.bindableProps)
      if (fields.contains(p)) p,
  ];
}

/// 这种类型的 prop 能不能接到这个属性上：颜色属性只能接颜色；文字类的属性什么都能接（数字、开关会显示成文字）。
bool propTypeFitsAttr(String propType, String attr) => attr == 'bg' || attr == 'color' ? propType == 'color' : true;

/// 展开时认不认这条绑定。比 [bindablePropsFor] 松：和 Vue / React 导出认的范围一样
/// （文字只有文本和按钮有，提示文字只有输入框有，图片地址只有图片有，颜色谁都行），免得两边导出的结果不一样。
bool _attrFitsType(String attr, String type) => switch (attr) {
  'text' => type == 'text' || type == 'button',
  'placeholder' => type == 'input',
  'src' => type == 'image',
  _ => type != 'component' && type != 'page',
};

class _Expander {
  _Expander(this.doc, {this.deep = true}) {
    // 页面里本来就长得像“展开后的 id”的节点（带 __ 的）要避开。绝大多数页面一个都没有。
    _walk(doc.root, (n) {
      if (n.id.contains('__')) taken.add(n.id);
    });
  }

  final LcDocument doc;

  /// false＝只展开一层：里面套的别的组件实例原样留着（拆开实例时用）。
  final bool deep;
  final Set<String> taken = {};
  final Set<String> visiting = {};
  int budget = kComponentExpandBudget;

  LcNode? expand(LcNode inst, [int depth = 0]) {
    final ref = _refOf(inst);
    final def = ref == null ? null : doc.component(ref);
    // 定义没了、套得太深、绕回自己：这一层不展开。
    if (def == null || depth >= kComponentNestMax || visiting.contains(def.id) || budget <= 0) return null;
    visiting.add(def.id);
    final values = instanceValues(def, inst);
    final rootId = inst.id;

    LcNode build(LcNode src, bool isRoot) {
      budget--;
      var id = isRoot ? rootId : '${rootId}__${src.id}';
      while (!isRoot && taken.contains(id)) {
        id = '${id}_';
      }
      if (src.type == 'component') {
        final placed = LcNode(id: id, type: 'component', props: _cloneProps(src.props), style: Map.of(src.style));
        return (deep ? expand(placed, depth + 1) : null) ?? placed;
      }
      final props = _cloneProps(src.props);
      src.bind.forEach((attr, name) {
        final p = def.prop(name);
        if (p == null || !_attrFitsType(attr, src.type)) return;
        final v = values[name];
        if (attr == 'bg' || attr == 'color') {
          // 颜色必须是 #RRGGBB；不是就留着控件自己原来的颜色。
          if (v is String && _hex.hasMatch(v)) props[attr] = v.toUpperCase();
        } else {
          props[attr] = componentValueText(v);
        }
      });
      return LcNode(
        id: id,
        type: src.type,
        props: props,
        style: Map.of(src.style),
        children: [
          for (final c in src.children)
            if (budget > 0) build(c, false),
        ],
      );
    }

    final root = build(def.root, true);
    visiting.remove(def.id);
    // 实例自己的摆放（宽度、外边距、样式）盖在最外层。
    for (final key in const ['width', 'margin']) {
      if (inst.props.containsKey(key)) root.props[key] = inst.props[key];
    }
    root.style.addAll(inst.style);
    return root;
  }
}

/// 把一个实例展开成普通控件的子树（不改文档）。bind 的属性换成实际的值（传了用传的，没传 / 类型不对用默认值）；
/// 里面套的实例一起展开。定义不存在、或这个实例会绕回自己（循环）返回 null；
/// 里面某一层出了这种问题，那一层原样留成 `component` 节点（调用方画占位 / 输出注释）。
LcNode? expandInstance(LcDocument doc, LcNode instance) {
  if (instance.type != 'component') return null;
  final out = _Expander(doc).expand(instance);
  return out == null || out.type == 'component' ? null : out;
}

/// 整个页面的树，实例都展开好（给导出用，不改文档）。展开不了的实例原样留着。
/// 页面里一个实例都没有时直接返回原来的根（不拷贝），所以没有组件的页面导出结果和以前一个字都不差。
LcNode expandedTree(LcDocument doc) {
  var any = false;
  _walk(doc.root, (n) => any = any || n.type == 'component');
  if (!any) return doc.root;
  final ex = _Expander(doc);
  LcNode walk(LcNode n) {
    if (n.type == 'component') return ex.expand(n) ?? n;
    if (n.children.isEmpty) return n;
    return LcNode(id: n.id, type: n.type, props: n.props, style: n.style, bind: n.bind, children: [for (final c in n.children) walk(c)], raw: n.raw);
  }

  return walk(doc.root);
}

/// 这个组件被用了几次（页面里的实例 + 别的组件定义里的实例）。
int componentUseCount(LcDocument doc, String componentId) {
  var n = 0;
  void count(LcNode x) {
    if (_refOf(x) == componentId) n++;
  }

  _walk(doc.root, count);
  for (final c in doc.components) {
    if (c.id != componentId) _walk(c.root, count);
  }
  return n;
}

/// 把 [childId] 的实例放进 [hostId] 的定义里会不会造成循环（自己套自己，或绕一圈回到自己）。
bool wouldCycle(LcDocument doc, String hostId, String childId) {
  final seen = <String>{};
  bool reaches(String id) {
    if (id == hostId) return true;
    if (!seen.add(id)) return false;
    final def = doc.component(id);
    if (def == null) return false;
    var hit = false;
    _walk(def.root, (n) {
      final ref = _refOf(n);
      if (!hit && ref != null && reaches(ref)) hit = true;
    });
    return hit;
  }

  return reaches(childId);
}

/// 组件名合不合规矩；合规矩返回 null，否则返回原因。
String? validateComponentName(String name) {
  final t = name.trim();
  if (t.isEmpty) return '组件名不能为空';
  if (t.runes.length > kComponentNameMax) return '组件名最多 $kComponentNameMax 个字';
  return null;
}

/// 不和已有组件重名的名字：重了就在后面加 2、3…
String uniqueComponentName(LcDocument doc, String name, {String? exceptId}) {
  final base = name.trim();
  bool used(String s) => doc.components.any((c) => c.id != exceptId && c.name == s);
  if (!used(base)) return base;
  for (var i = 2; ; i++) {
    final suffix = ' $i';
    // 加了后缀也不能超长：超了就把前面截短一点。
    final keep = base.runes.take(kComponentNameMax - suffix.length);
    final candidate = '${String.fromCharCodes(keep)}$suffix';
    if (!used(candidate)) return candidate;
  }
}

int _subtreeLogicRefs(LcDocument doc, LcNode node) {
  var refs = 0;
  _walk(node, (n) => refs += doc.logic.nodeRefCount(n.id));
  return refs;
}

/// 这个节点能不能存成组件；能返回 null，不能返回原因。
String? canSaveAsComponent(LcDocument doc, String nodeId) {
  final node = doc.find(nodeId);
  if (node == null) return '找不到这个控件';
  if (node.type == 'page' || doc.parentOf(nodeId) == null) return '整个页面不能存成组件，选页面里面的控件';
  if (node.type == 'component') return '它已经是一个组件了';
  // 组件定义里的控件不支持积木逻辑（定义里的 id 和页面互不相干，逻辑找不到它们）。
  final refs = _subtreeLogicRefs(doc, node);
  if (refs > 0) return '这几个控件有积木逻辑在用（$refs 处），先去掉逻辑再存成组件';
  return null;
}

String _newComponentId(LcDocument doc) {
  for (var i = 1; ; i++) {
    if (doc.component('c$i') == null) return 'c$i';
  }
}

/// 把定义里的节点 id 重新编成 k1、k2…（只在一个定义内部唯一就行）。
void _renumber(LcNode root) {
  var i = 1;
  _walk(root, (n) => n.id = 'k${i++}');
}

/// 把页面里 [nodeId] 那棵子树存成一个新组件，原位置换成指向它的实例（实例沿用原来的 id，所以选中不会丢）。
/// 子树里有积木逻辑在用的控件时拒绝（见 [canSaveAsComponent]）。名字重了自动加序号。
LcOpResult saveAsComponent(LcDocument doc, String nodeId, String name) {
  final nameError = validateComponentName(name);
  if (nameError != null) return LcOpResult.fail(nameError);
  final blocked = canSaveAsComponent(doc, nodeId);
  if (blocked != null) return LcOpResult.fail(blocked);
  final node = doc.find(nodeId)!;
  final parent = doc.parentOf(nodeId)!;
  // 页面里的节点不该有 bind（那是定义里才用的）；有也不带过去，新组件还没有任何 prop。
  final root = copyLcTree(node, keepBind: false);
  _renumber(root);
  final def = LcComponentDef(id: _newComponentId(doc), name: uniqueComponentName(doc, name), root: root);
  doc.components.add(def);
  final instance = LcNode(id: node.id, type: 'component', props: {'ref': def.id});
  parent.children[parent.children.indexOf(node)] = instance;
  return LcOpResult.ok(nodeId: instance.id, componentId: def.id);
}

/// 往页面里加一个实例。位置和点组件栏一样：[nearId] 是容器就加进去；不是容器就加在它后面；没给加到页面末尾。
LcOpResult insertInstance(LcDocument doc, String componentId, {String? nearId}) {
  if (doc.component(componentId) == null) return const LcOpResult.fail('这个组件已经不存在了');
  final node = doc.newNode('component')..props['ref'] = componentId;
  final near = nearId == null ? null : doc.find(nearId);
  final parent = near == null ? null : doc.parentOf(near.id);
  final bool ok;
  if (near != null && near.isContainer) {
    ok = doc.insert(near.id, node);
  } else if (near != null && parent != null) {
    ok = doc.insert(parent.id, node, parent.children.indexOf(near) + 1);
  } else {
    ok = doc.insert(doc.root.id, node);
  }
  return ok ? LcOpResult.ok(nodeId: node.id, componentId: componentId) : const LcOpResult.fail('这里放不了组件');
}

/// 把 [list] 里第 [index] 个（一个实例）换成定义子树的拷贝（只拆这一层，套着当前传的值）。
/// [mint] 给里面的节点发新 id。定义不在了返回 false。
bool _detachAt(LcDocument doc, List<LcNode> list, int index, String Function() mint) {
  final inst = list[index];
  final flat = _Expander(doc, deep: false).expand(inst);
  if (flat == null) return false;
  for (final c in flat.children) {
    _walk(c, (n) => n.id = mint());
  }
  list[index] = flat;
  return true;
}

/// 把页面里的一个实例拆开成普通控件（套用它当前的值）。最外层沿用实例的 id，里面的节点发新 id。
LcOpResult detachInstance(LcDocument doc, String instanceId) {
  final inst = doc.find(instanceId);
  final parent = doc.parentOf(instanceId);
  if (inst == null || parent == null || inst.type != 'component') return const LcOpResult.fail('选中的不是组件');
  // 新 id 向文档要（newNode 会发一个没人用过的 n数字），造出来的节点本身不用。
  if (!_detachAt(doc, parent.children, parent.children.indexOf(inst), () => doc.newNode('spacer').id)) {
    return const LcOpResult.fail('这个组件的定义已经不存在了，没法拆开');
  }
  return LcOpResult.ok(nodeId: instanceId);
}

String Function() _minterFor(LcNode root) {
  final used = <String>{};
  _walk(root, (n) => used.add(n.id));
  var i = 1;
  return () {
    while (!used.add('k$i')) {
      i++;
    }
    return 'k$i';
  };
}

/// 组件改名。和别的组件重名时拒绝。
LcOpResult renameComponent(LcDocument doc, String componentId, String name) {
  final def = doc.component(componentId);
  if (def == null) return const LcOpResult.fail('这个组件已经不存在了');
  final error = validateComponentName(name);
  if (error != null) return LcOpResult.fail(error);
  final t = name.trim();
  if (doc.components.any((c) => c.id != componentId && c.name == t)) return const LcOpResult.fail('已经有一个叫这个名字的组件了');
  def.name = t;
  return LcOpResult.ok(componentId: componentId);
}

String? _propNameError(LcComponentDef def, String name, {String? except}) {
  if (!LcComponentProp.namePattern.hasMatch(name)) return '属性名只能用英文字母、数字和下划线，不能用数字开头，最多 32 个字符';
  if (name != except && def.prop(name) != null) return '已经有一个叫 $name 的属性了';
  return null;
}

/// 给组件加一个可配置的属性。[defaultValue] 不给或类型不对就用这种类型的默认（空文字 / 0 / 黑色 / 关）。
LcOpResult addComponentProp(LcDocument doc, String componentId, String name, String type, [Object? defaultValue]) {
  final def = doc.component(componentId);
  if (def == null) return const LcOpResult.fail('这个组件已经不存在了');
  if (!LcComponentProp.types.contains(type)) return const LcOpResult.fail('不认识这种属性类型');
  if (def.props.length >= kComponentPropMax) return const LcOpResult.fail('一个组件最多 $kComponentPropMax 个属性');
  final error = _propNameError(def, name);
  if (error != null) return LcOpResult.fail(error);
  def.props.add(LcComponentProp(name: name, type: type, defaultValue: defaultValue));
  return LcOpResult.ok(componentId: componentId);
}

/// 走一遍这个组件的所有实例（页面里的和别的定义里的）。
void _eachInstance(LcDocument doc, String componentId, void Function(LcNode inst) visit) {
  void check(LcNode n) {
    if (_refOf(n) == componentId) visit(n);
  }

  _walk(doc.root, check);
  for (final c in doc.components) {
    _walk(c.root, check);
  }
}

/// 属性改名：定义里接着它的绑定、所有实例传的值一起改。
LcOpResult renameComponentProp(LcDocument doc, String componentId, String oldName, String newName) {
  final def = doc.component(componentId);
  final p = def?.prop(oldName);
  if (def == null || p == null) return const LcOpResult.fail('找不到这个属性');
  if (oldName == newName) return LcOpResult.ok(componentId: componentId);
  final error = _propNameError(def, newName, except: oldName);
  if (error != null) return LcOpResult.fail(error);
  p.name = newName;
  _walk(def.root, (n) => n.bind.updateAll((_, v) => v == oldName ? newName : v));
  _eachInstance(doc, componentId, (inst) {
    final values = inst.props['values'];
    if (values is Map && values.containsKey(oldName)) values[newName] = values.remove(oldName);
  });
  return LcOpResult.ok(componentId: componentId);
}

void _dropValue(LcNode inst, String name) {
  final values = inst.props['values'];
  if (values is! Map) return;
  values.remove(name);
  if (values.isEmpty) inst.props.remove('values');
}

/// 删属性：接着它的绑定解开（控件回到自己原来的内容），所有实例传的这个值清掉。
LcOpResult removeComponentProp(LcDocument doc, String componentId, String name) {
  final def = doc.component(componentId);
  if (def == null || def.prop(name) == null) return const LcOpResult.fail('找不到这个属性');
  def.props.removeWhere((p) => p.name == name);
  _walk(def.root, (n) => n.bind.removeWhere((_, v) => v == name));
  _eachInstance(doc, componentId, (inst) => _dropValue(inst, name));
  return LcOpResult.ok(componentId: componentId);
}

/// 改属性的类型：默认值能沿用就沿用，不能就换成新类型的默认；接不上新类型的绑定解开；实例传的值类型不对了的清掉。
LcOpResult setComponentPropType(LcDocument doc, String componentId, String name, String type) {
  final def = doc.component(componentId);
  final p = def?.prop(name);
  if (def == null || p == null) return const LcOpResult.fail('找不到这个属性');
  if (!LcComponentProp.types.contains(type)) return const LcOpResult.fail('不认识这种属性类型');
  if (p.type == type) return LcOpResult.ok(componentId: componentId);
  p
    ..type = type
    ..defaultValue = LcComponentProp.coerce(type, p.defaultValue);
  _walk(def.root, (n) => n.bind.removeWhere((attr, v) => v == name && !propTypeFitsAttr(type, attr)));
  _eachInstance(doc, componentId, (inst) {
    final values = inst.props['values'];
    if (values is Map && values.containsKey(name) && _fit(p, values[name]) == null) _dropValue(inst, name);
  });
  return LcOpResult.ok(componentId: componentId);
}

/// 改属性的默认值。类型不对时拒绝。
LcOpResult setComponentPropDefault(LcDocument doc, String componentId, String name, Object? value) {
  final p = doc.component(componentId)?.prop(name);
  if (p == null) return const LcOpResult.fail('找不到这个属性');
  final v = _fit(p, value);
  if (v == null) return const LcOpResult.fail('默认值的类型和这个属性对不上');
  p.defaultValue = v;
  return LcOpResult.ok(componentId: componentId);
}

LcNode? _findIn(LcNode root, String id) {
  LcNode? hit;
  _walk(root, (n) => hit ??= n.id == id ? n : null);
  return hit;
}

/// 把定义里 [nodeId] 的 [attr] 属性接到 [propName] 上；[propName] 传 null＝解开。
LcOpResult bindComponentProp(LcDocument doc, String componentId, String nodeId, String attr, String? propName) {
  final def = doc.component(componentId);
  final node = def == null ? null : _findIn(def.root, nodeId);
  if (def == null || node == null) return const LcOpResult.fail('找不到这个控件');
  if (propName == null) {
    node.bind.remove(attr);
    return LcOpResult.ok(componentId: componentId);
  }
  if (!bindablePropsFor(node.type).contains(attr)) return LcOpResult.fail('${node.spec.label}没有这一项可以接');
  final p = def.prop(propName);
  if (p == null) return const LcOpResult.fail('找不到这个属性');
  if (!propTypeFitsAttr(p.type, attr)) return const LcOpResult.fail('颜色只能接颜色类型的属性');
  node.bind[attr] = propName;
  return LcOpResult.ok(componentId: componentId);
}

/// 改页面里一个实例传的值；[value] 传 null＝恢复默认。类型不对时拒绝。
LcOpResult setInstanceValue(LcDocument doc, String instanceId, String propName, Object? value) {
  final inst = doc.find(instanceId);
  final ref = inst == null ? null : _refOf(inst);
  final p = ref == null ? null : doc.component(ref)?.prop(propName);
  if (inst == null || p == null) return const LcOpResult.fail('找不到这个属性');
  if (value == null) {
    _dropValue(inst, propName);
    return LcOpResult.ok(nodeId: instanceId);
  }
  final v = _fit(p, value);
  if (v == null) return const LcOpResult.fail('填的值和这个属性的类型对不上');
  final old = inst.props['values'];
  // 不在原来的表上直接改：那张表可能是只读的（解析出来的常量），换一张新的最稳。
  inst.props['values'] = <String, dynamic>{
    if (old is Map)
      for (final MapEntry(:key, value: existing) in old.entries)
        if (key is String) key: existing,
    propName: v,
  };
  return LcOpResult.ok(nodeId: instanceId);
}

/// 删除组件定义。还有实例在用时按 [instances] 处理：
/// 默认拒绝并在 [LcOpResult.uses] 里给出使用次数；`remove` 连实例一起删（挂在实例上的积木逻辑一并清掉）；
/// `detach` 先把实例拆开成普通控件再删。
LcOpResult deleteComponent(LcDocument doc, String componentId, {LcDeleteInstances instances = LcDeleteInstances.refuse}) {
  final def = doc.component(componentId);
  if (def == null) return const LcOpResult.fail('这个组件已经不存在了');
  final uses = componentUseCount(doc, componentId);
  if (uses > 0 && instances == LcDeleteInstances.refuse) {
    return LcOpResult.fail('还有 $uses 处在用这个组件', uses: uses);
  }
  if (uses > 0) {
    final detach = instances == LcDeleteInstances.detach;
    // 一棵树里的实例：拆开或者拿掉。[mint] 给拆出来的节点发 id；[onRemove] 在拿掉之前通知一声。
    void sweep(LcNode parent, String Function() mint, void Function(LcNode inst) onRemove) {
      for (var i = parent.children.length - 1; i >= 0; i--) {
        final c = parent.children[i];
        if (_refOf(c) == componentId) {
          if (detach && _detachAt(doc, parent.children, i, mint)) continue;
          onRemove(c);
          parent.children.removeAt(i);
        } else {
          sweep(c, mint, onRemove);
        }
      }
    }

    sweep(doc.root, () => doc.newNode('spacer').id, (inst) => doc.logic.removeNodeRefs(inst.id));
    for (final other in doc.components) {
      if (other.id == componentId) continue;
      final mint = _minterFor(other.root);
      if (_refOf(other.root) == componentId) {
        // 别的组件最外层就是它：定义不能没有根，拆不开就换成一个空容器。
        final holder = [other.root];
        if (!(detach && _detachAt(doc, holder, 0, mint))) {
          holder[0] = LcNode(id: other.root.id, type: 'container', props: _cloneProps(lcSpecs['container']!.defaults));
        }
        other.root = holder[0];
      }
      sweep(other.root, mint, (_) {});
    }
  }
  doc.components.removeWhere((c) => c.id == componentId);
  return LcOpResult.ok(componentId: componentId);
}
