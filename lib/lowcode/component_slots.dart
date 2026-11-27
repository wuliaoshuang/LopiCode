/// 自定义组件的插槽——定义那一头的纯逻辑（不带界面）。实例那一头（往插槽里放东西、分拣、落点）在 slots.dart，展开在 component_expand.dart。
///
/// 怎么存（格式见 docs/lowcode-page-format-v3.md，没有新字段）：
/// - 组件定义里，一个容器的内容“设成插槽”＝在这个容器里放一个 `type: slot` 的占位节点，容器原来的子节点挪进占位里，成了“没填时显示的默认内容”。
///   容器自己（底色、内边距、怎么排）不变：外面填进来的东西就排在这个容器里。
/// - 插槽名（`props.name`，不写＝默认插槽 `default`）是给代码用的：她起的名字是英文字母 / 数字 / 下划线就直接用，不是就自动发 `s1`、`s2`…。
///   给人看的名字是占位节点的 `name`（就是图层面板里那个名字），存盘时一并写进定义的 `slots: [{name, label}]`。
/// - 页面上用它的实例：子节点各自的 `slot` 写着放进哪个插槽。
///
/// 改定义时已有实例里填的东西怎么办（**不许悄悄丢**）：
/// - 插槽改名（代码用的名字变了）：所有实例里填在这个插槽的子节点跟着改 `slot`（[renameSlotsInInstances]，写回定义时自动做）。
/// - 取消插槽：先数有几个实例在里面填了东西（[slotFillCount]）给她看；确认后这些内容**挪到各自那个实例的后面**（同一个容器里、紧挨着、先后不变），
///   不删（[evictSlotContent]）。实例是另一个组件的最外层、后面没地方放时，外面包一层容器。
/// - 别的路子把占位节点弄没了（删掉它或它外面的容器、撤销）：只要有实例在那个插槽里填着东西就不让，说明原因（[slotLossBlock]）。
/// - 删整个组件：“拆成普通控件留着”时填的内容接在原来插槽的位置上；“连用到的地方一起删”会连填的内容一起删（确认框里写明有几处填了东西）。
library;

import 'package:lopicode/lowcode/component_model.dart';
import 'package:lopicode/lowcode/component_ops.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/model_v3_components.dart';
import 'package:lopicode/lowcode/slots.dart';

/// 一个组件最多几个插槽。
const int kComponentSlotMax = 8;

/// 能“设成插槽”的容器。
const Set<String> kSlotHostTypes = {'container', 'row', 'column', 'card'};

void _walk(LcNode n, void Function(LcNode n, LcNode? parent) visit, [LcNode? parent]) {
  visit(n, parent);
  for (final c in [...n.children]) {
    _walk(c, visit, n);
  }
}

/// 一棵树里的插槽占位节点（按先后）。
List<LcNode> slotNodesIn(LcNode root) {
  final out = <LcNode>[];
  _walk(root, (n, _) {
    if (n.type == 'slot') out.add(n);
  });
  return out;
}

Set<String> slotNamesIn(LcNode root) => {for (final s in slotNodesIn(root)) lcSlotNameOf(s)};

/// 占位节点给人看的名字。
String slotNodeLabel(LcNode slotNode) => slotNode.name.isNotEmpty ? slotNode.name : lcDefaultSlotLabel(lcSlotNameOf(slotNode));

/// 这个节点里面直接放着的那个插槽占位（它的内容已经“设成插槽”了）；没有返回 null。
LcNode? slotInside(LcNode host) => host.children.where((c) => c.type == 'slot').firstOrNull;

/// 起的名字 → 代码里用的插槽名：是字母开头的英文 / 数字 / 下划线（最长 24）而且没人用，就用它；不然发 `s数字`。
String slotNameFor(String label, Set<String> used, {required bool asDefault}) {
  if (asDefault) return kLcDefaultSlot;
  final t = label.trim();
  if (RegExp(r'^[A-Za-z][A-Za-z0-9_]{0,23}$').hasMatch(t) && t != kLcDefaultSlot && !used.contains(t)) return t;
  for (var i = 1; ; i++) {
    if (!used.contains('s$i')) return 's$i';
  }
}

/// 起的名字合不合适（对话框里边填边查）；合适返回 null。[slotNodeId]：改名时是哪个插槽（它自己现在的名字不算重名）。
String? slotLabelProblem(LcDocument editing, String label, {required bool asDefault, String? slotNodeId}) {
  final self = slotNodeId == null ? null : editing.find(slotNodeId);
  final error = _labelError(editing.root, label, except: self);
  if (error != null) return error;
  final taken = slotNodesIn(editing.root).any((s) => !identical(s, self) && lcSlotNameOf(s) == kLcDefaultSlot);
  return asDefault && taken ? '这个组件已经有默认插槽了' : null;
}

String? _labelError(LcNode root, String label, {LcNode? except}) {
  final t = LcNode.cleanName(label);
  if (t.isEmpty) return '给插槽起个名字';
  if (label.trim().runes.length > LcNode.maxNameLength) return '名字最多 ${LcNode.maxNameLength} 个字';
  if (slotNodesIn(root).any((s) => !identical(s, except) && slotNodeLabel(s) == t)) return '已经有一个叫「$t」的插槽了';
  return null;
}

/// 这个节点现在能不能“设成插槽”；能返回 null，不能返回原因。[editing] 是组件编辑页的临时文档。
String? canMakeSlot(LcDocument editing, String nodeId) {
  final node = editing.find(nodeId);
  if (node == null) return '找不到这个控件';
  if (node.type == 'slot') return '它已经是插槽了';
  if (!kSlotHostTypes.contains(node.type)) return '只有容器、行、列、卡片的内容能设成插槽';
  if (slotInside(node) != null) return '这个${node.spec.label}的内容已经是插槽了';
  if (slotNodesIn(editing.root).length >= kComponentSlotMax) return '一个组件最多 $kComponentSlotMax 个插槽';
  return null;
}

/// 把 [nodeId]（一个容器）的内容设成插槽：容器里放一个占位节点，原来的子节点成了默认内容。
/// 成功时 [LcOpResult.nodeId] 是占位节点的 id。
LcOpResult makeSlot(LcDocument editing, String nodeId, {required String label, required bool asDefault}) {
  final blocked = canMakeSlot(editing, nodeId);
  if (blocked != null) return LcOpResult.fail(blocked);
  final error = _labelError(editing.root, label);
  if (error != null) return LcOpResult.fail(error);
  final used = slotNamesIn(editing.root);
  if (asDefault && used.contains(kLcDefaultSlot)) return const LcOpResult.fail('这个组件已经有默认插槽了');
  final host = editing.find(nodeId)!;
  final name = slotNameFor(label, used, asDefault: asDefault);
  final slot = editing.newNode('slot')..name = LcNode.cleanName(label);
  if (name != kLcDefaultSlot) slot.props['name'] = name;
  slot.children.addAll(host.children);
  host.children
    ..clear()
    ..add(slot);
  return LcOpResult.ok(nodeId: slot.id);
}

/// 给插槽改名 / 改成（或不再是）默认插槽。成功时 [LcOpResult.componentId] 里放的是**改之后**代码里用的插槽名
/// （和原来不一样时，写回定义那一步会去改已有实例，见 [renameSlotsInInstances]）。
LcOpResult renameSlot(LcDocument editing, String slotNodeId, {required String label, required bool asDefault}) {
  final slot = editing.find(slotNodeId);
  if (slot == null || slot.type != 'slot') return const LcOpResult.fail('找不到这个插槽');
  final error = _labelError(editing.root, label, except: slot);
  if (error != null) return LcOpResult.fail(error);
  final old = lcSlotNameOf(slot);
  final used = {
    for (final s in slotNodesIn(editing.root))
      if (!identical(s, slot)) lcSlotNameOf(s),
  };
  if (asDefault && used.contains(kLcDefaultSlot)) return const LcOpResult.fail('这个组件已经有默认插槽了');
  // 名字没动、默认不默认也没动：代码里的名字不变（不让实例白白跟着改）。
  final keep = LcNode.cleanName(label) == slot.name && asDefault == (old == kLcDefaultSlot);
  final name = keep ? old : slotNameFor(label, used, asDefault: asDefault);
  slot.name = LcNode.cleanName(label);
  name == kLcDefaultSlot ? slot.props.remove('name') : slot.props['name'] = name;
  return LcOpResult.ok(nodeId: slotNodeId, componentId: name);
}

/// 取消插槽：占位节点拿掉，它里面的默认内容留在原来的位置上。
LcOpResult unwrapSlot(LcDocument editing, String slotNodeId) {
  final slot = editing.find(slotNodeId), parent = editing.parentOf(slotNodeId);
  if (slot == null || parent == null || slot.type != 'slot') return const LcOpResult.fail('找不到这个插槽');
  final at = parent.children.indexOf(slot);
  parent.children
    ..removeAt(at)
    ..insertAll(at, slot.children);
  for (final c in slot.children) {
    c.slot = slot.slot;
  }
  return LcOpResult.ok(nodeId: parent.id);
}

/// 同名的占位节点只许有一个：后面重了的（复制、粘贴出来的）换一个新名字，给人看的名字后面加序号。返回改了几个。
int dedupeSlots(LcNode root) {
  final all = slotNodesIn(root);
  final names = <String>{}, labels = <String>{};
  var changed = 0;
  for (final s in all) {
    final name = lcSlotNameOf(s);
    if (names.add(name)) {
      labels.add(slotNodeLabel(s));
      continue;
    }
    final used = {...names, for (final x in all) lcSlotNameOf(x)};
    final base = slotNodeLabel(s);
    var label = base;
    for (var i = 2; labels.contains(label); i++) {
      label = LcNode.cleanName('$base $i');
    }
    final fresh = slotNameFor('', used, asDefault: false);
    s
      ..name = label
      ..props['name'] = fresh;
    names.add(fresh);
    labels.add(label);
    changed++;
  }
  return changed;
}

/// 页面上不该有插槽占位（它只在组件定义里有意义）：把一棵要贴进页面的子树里的占位节点都拿掉，默认内容留在原位。返回拿掉了几个。
/// 最外层就是占位节点的，调用方自己处理（用 [slotNodesIn] 看）。
int stripSlots(LcNode root) {
  var n = 0;
  void fix(LcNode node) {
    for (var i = 0; i < node.children.length; i++) {
      final c = node.children[i];
      if (c.type != 'slot') continue;
      node.children
        ..removeAt(i)
        ..insertAll(i, c.children);
      n++;
      i--; // 默认内容里可能还有占位：原地再看一遍
    }
    node.children.forEach(fix);
  }

  fix(root);
  return n;
}

// —— 已有的实例 ——

String? _refOf(LcNode n) => n.type == 'component' && n.props['ref'] is String ? n.props['ref'] as String : null;

/// 走一遍这个组件的所有实例（**所有页面**里的、别的组件定义里的），连同它所在的那棵树的根。
void _eachInstance(LcDocument doc, String componentId, void Function(LcNode inst, LcNode? parent, LcComponentDef? owner) visit) {
  for (final p in doc.pages) {
    _walk(p.root, (n, parent) {
      if (_refOf(n) == componentId) visit(n, parent, null);
    });
  }
  for (final c in doc.components) {
    _walk(c.root, (n, parent) {
      if (_refOf(n) == componentId) visit(n, parent, c);
    });
  }
}

/// 现在有几个实例在 [slot] 这个插槽里填了东西、一共填了几个组件。按**改之前**的定义算（没写 `slot` 的算在兜底插槽里）。
({int instances, int nodes}) slotFillCount(LcDocument doc, String componentId, String slot) {
  lcLinkInstances(doc);
  var instances = 0, nodes = 0;
  _eachInstance(doc, componentId, (inst, _, _) {
    final n = lcSlotChildren(inst, slot).length;
    if (n > 0) instances++;
    nodes += n;
  });
  return (instances: instances, nodes: nodes);
}

/// 这个组件的实例里一共填了几处内容（删组件的确认框用）。
({int instances, int nodes}) componentFillCount(LcDocument doc, String componentId) {
  var instances = 0, nodes = 0;
  _eachInstance(doc, componentId, (inst, _, _) {
    if (inst.children.isNotEmpty) instances++;
    nodes += inst.children.length;
  });
  return (instances: instances, nodes: nodes);
}

/// 插槽在代码里的名字改了（[renames]：旧名 → 新名，可以一次改几个、互相对调也行）：
/// 所有实例里填在旧名插槽里的子节点改写成新名。**要在定义改掉之前调**。返回改了几个。
int renameSlotsInInstances(LcDocument doc, String componentId, Map<String, String> renames) {
  if (renames.isEmpty) return 0;
  lcLinkInstances(doc);
  final todo = <(LcNode, String)>[];
  _eachInstance(doc, componentId, (inst, _, _) {
    for (final c in inst.children) {
      final to = renames[lcSlotOfChild(inst, c)];
      if (to != null) todo.add((c, to));
    }
  });
  for (final (c, to) in todo) {
    c.slot = to;
  }
  return todo.length;
}

/// 取消 [slot] 之前：把所有实例里填在它里面的内容挪到各自那个实例的后面（同一个容器、紧挨着、先后不变）。
/// **要在定义改掉之前调**。返回挪了几个。
int evictSlotContent(LcDocument doc, String componentId, String slot) {
  lcLinkInstances(doc);
  final jobs = <(LcNode inst, LcNode? parent, LcComponentDef? owner)>[];
  _eachInstance(doc, componentId, (inst, parent, owner) => jobs.add((inst, parent, owner)));
  var moved = 0;
  for (final (inst, parentOrNull, owner) in jobs) {
    final content = lcSlotChildren(inst, slot);
    if (content.isEmpty) continue;
    inst.children.removeWhere(content.contains);
    var parent = parentOrNull;
    if (parent == null) {
      // 实例是另一个组件的最外层：后面没地方放，外面包一层容器（容器接过最外层的位置）。
      if (owner == null) continue; // 页面的根不会是实例
      final ids = <String>{};
      _walk(owner.root, (n, _) => ids.add(n.id));
      var i = 1;
      while (ids.contains('w$i')) {
        i++;
      }
      parent = LcNode(id: 'w$i', type: 'container', props: {'width': 'fill'}, children: [inst]);
      owner.root = parent;
    }
    final at = parent.children.indexOf(inst) + 1;
    parent.children.insertAll(at, content);
    for (final c in content) {
      // 实例自己在别人的插槽里：挪出来的内容跟它待在同一个插槽。
      c.slot = parent.hasSlots ? inst.slot : null;
    }
    moved += content.length;
  }
  return moved;
}

/// 组件的内容从“有 [before] 这些插槽”改成了“只有 [after] 这些”：少掉的插槽里要是还有实例填着东西，返回一句不让改的原因；没事返回 null。
String? slotLossBlock(LcDocument doc, String componentId, Set<String> before, Set<String> after) {
  for (final name in before.difference(after)) {
    final fill = slotFillCount(doc, componentId, name);
    if (fill.nodes == 0) continue;
    final label = doc.component(componentId)?.slots.where((s) => s.name == name).firstOrNull?.label ?? name;
    return '插槽「$label」里有 ${fill.instances} 个实例填了东西（共 ${fill.nodes} 个组件），这样改会让它们没地方放。先选中这个插槽，用“取消插槽”处理（填的内容会挪到实例后面）。';
  }
  return null;
}

/// 插槽名合不合写法（给读文件 / Agent 写页面时用）。
bool isSlotName(String s) => lcSlotName.hasMatch(s);
