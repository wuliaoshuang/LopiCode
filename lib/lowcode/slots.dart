/// 内置组件的插槽：一个带插槽的组件（列表行、顶部导航栏、标签页、弹窗）的子节点是**一串平铺的**，
/// 每个子节点用 `slot` 写明自己在哪个插槽里（格式见 docs/lowcode-page-format-v3.md）。这里是读法和改法，不带界面。
///
/// 规矩：
/// - 有哪些插槽：列表行 `left` / `right`，顶部导航栏 `left` / `right`，弹窗 `content` / `footer`，
///   标签页是每个页签一个（插槽名＝页签 id）。
/// - 子节点没写 `slot`、或者写的插槽不存在：**算在“兜底插槽”里**（列表行、导航栏是 `right`，弹窗是 `content`，
///   标签页是第一个页签）。只是这么画、这么导出，文件里不替它改。这样图层面板、粘贴、“点一下添加”
///   这些不知道插槽的老路子往带插槽的组件里放东西，放进去就看得见。
/// - 画布上拖进某个插槽：落点的“容器 id”写成 `组件id#插槽名`（[lcSlotBoxId]）；组件 id 里不会有 `#`。
///   [lcInsertAt] / [lcMoveTo] 认这种 id：放进去以后把子节点的 `slot` 写对；放进普通容器的把 `slot` 去掉。
/// - 一个插槽里子节点的先后＝它们在那串平铺的子节点里的先后。
///
/// 自定义组件的插槽（B3）也用这一套：实例的插槽就是它的定义里有的那些（[LcNode.instSlots]，由 [lcLinkInstances] 对上），
/// 兜底插槽是 `default`（定义里没有默认插槽就是第一个）。定义那一头的操作在 component_slots.dart。
library;

import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/model_v3_components.dart';

class LcSlot {
  const LcSlot(this.name, this.label, {this.row = false});
  final String name;

  /// 给人看的名字（“左侧”“内容”“页签一”）。
  final String label;

  /// 自定义组件的插槽：占位节点所在的容器是不是横着排（画布算落点用）。
  final bool row;
}

/// 自定义组件的默认插槽的名字（同 Vue 的默认插槽）。
const String kLcDefaultSlot = 'default';

/// 插槽占位节点（`type: slot`）的插槽名：`props.name`，没写＝默认插槽。
String lcSlotNameOf(LcNode slotNode) => slotNode.strProp('name') ?? kLcDefaultSlot;

String lcDefaultSlotLabel(String name) => name == kLcDefaultSlot ? '默认插槽' : name;

/// 给页面里、各组件定义里的每个组件实例对上“它的定义现在有哪些插槽”（[LcNode.instSlots]）。
/// 文档每次建好、插入 / 移动 / 复制之前、编辑器每次改完都调一遍；[extra] 是一棵还没放进文档的子树。
void lcLinkInstances(LcDocument doc, {LcNode? extra}) {
  final cache = <String, List<LcSlot>>{};
  void walk(LcNode n) {
    if (n.type == 'component') {
      final ref = n.props['ref'];
      n.instSlots = ref is String ? cache[ref] ??= doc.component(ref)?.slots ?? const [] : const [];
    }
    n.children.forEach(walk);
  }

  walk(doc.root);
  for (final c in doc.components) {
    walk(c.root);
  }
  if (extra != null) walk(extra);
}

const Map<String, String> _labels = {'left': '左侧', 'right': '右侧', 'content': '内容', 'footer': '底部按钮'};

/// 这个组件有哪些插槽（按顺序）；不带插槽的返回空表。
List<LcSlot> lcSlotsOf(LcNode host) {
  if (host.type == 'component') return host.instSlots;
  final fixed = host.spec.slots;
  if (fixed == null) return const [];
  if (host.type == 'tabs') return [for (final t in lcObjects(host, 'tabs')) LcSlot(t['id'] as String, lcItemLabel(t, 'id'))];
  return [for (final s in fixed) LcSlot(s, _labels[s] ?? s)];
}

/// 兜底插槽：没写 `slot` 或写错了的子节点算在这儿。一个插槽都没有（页签删光了）返回 null。
String? lcFallbackSlot(LcNode host) {
  final slots = lcSlotsOf(host);
  if (slots.isEmpty) return null;
  return switch (host.type) {
    'listItem' || 'appBar' => 'right',
    'dialog' => 'content',
    'component' => slots.any((s) => s.name == kLcDefaultSlot) ? kLcDefaultSlot : slots.first.name,
    _ => slots.first.name,
  };
}

/// 这个子节点算在 [host] 的哪个插槽里。
String? lcSlotOfChild(LcNode host, LcNode child) {
  final slots = lcSlotsOf(host);
  final s = child.slot;
  return s != null && slots.any((x) => x.name == s) ? s : lcFallbackSlot(host);
}

/// [node] 刚放进 [parent] 的第 [at] 个位置：把它的 `slot` 收拾对（LcDocument.insert / move 每次都调）。
/// - 普通容器：去掉 `slot`（从插槽里拖出来的不带着旧插槽名走）。
/// - 带插槽的组件：`slot` 本来就是它的某个插槽＝不动；不是——跟前一个兄弟放一起；没有前一个，标签页放进当前页签，别的按兜底算（不写）。
void lcSettleSlot(LcNode parent, LcNode node, int at) {
  if (!parent.hasSlots) {
    node.slot = null;
    return;
  }
  final names = {for (final s in lcSlotsOf(parent)) s.name};
  if (names.contains(node.slot)) return;
  final prev = at > 0 && at <= parent.children.length ? parent.children[at - 1] : null;
  if (prev != null && !identical(prev, node) && names.contains(prev.slot)) {
    node.slot = prev.slot;
  } else {
    node.slot = parent.type == 'tabs' ? lcCurrentTab(parent) : null;
  }
}

/// [host] 的某个插槽里的子节点（按先后）。
List<LcNode> lcSlotChildren(LcNode host, String slot) => [
  for (final c in host.children)
    if (lcSlotOfChild(host, c) == slot) c,
];

/// 标签页现在显示的是哪个页签（`current` 没写或写错了＝第一个）；一个页签都没有返回 null。
String? lcCurrentTab(LcNode tabs) {
  final all = lcObjects(tabs, 'tabs');
  if (all.isEmpty) return null;
  final cur = tabs.props['current'];
  return all.any((t) => t['id'] == cur) ? cur as String : all.first['id'] as String;
}

/// 这个插槽里面是不是横着排（列表行、导航栏的左右，弹窗的底部按钮）；标签页的一页、弹窗的内容是竖着排。
bool lcSlotIsRow(LcNode host, String slot) =>
    host.type == 'component' ? host.instSlots.any((s) => s.name == slot && s.row) : host.type == 'listItem' || host.type == 'appBar' || (host.type == 'dialog' && slot == 'footer');

// —— 画布落点用的“插槽 id” ——

String lcSlotBoxId(String hostId, String slot) => '$hostId#$slot';

/// 拆开落点的容器 id：普通容器返回 (id, null)；插槽返回 (组件 id, 插槽名)。
(String hostId, String? slot) lcSplitSlotId(String id) {
  final i = id.indexOf('#');
  return i < 0 ? (id, null) : (id.substring(0, i), id.substring(i + 1));
}

/// 插槽里的第 [index] 个位置，对应那串平铺的子节点里的第几个（都按动之前的顺序算）。
int lcFlatIndex(LcNode host, String slot, int index) {
  final inSlot = lcSlotChildren(host, slot);
  if (index >= 0 && index < inSlot.length) return host.children.indexOf(inSlot[index]);
  return inSlot.isEmpty ? host.children.length : host.children.indexOf(inSlot.last) + 1;
}

/// 放进普通容器的：去掉 `slot`；放进带插槽的组件但没指明插槽的：留着原来的（不认识就按兜底算）。
void _settle(LcDocument doc, LcNode node, String? slot) {
  if (slot != null) {
    node.slot = slot;
  } else if (!(doc.parentOf(node.id)?.hasSlots ?? false)) {
    node.slot = null;
  }
}

/// 把新节点放到 [target]（普通容器 id，或 [lcSlotBoxId]）的第 [index] 个位置。
bool lcInsertAt(LcDocument doc, String target, LcNode node, [int? index]) {
  final (hostId, slot) = lcSplitSlotId(target);
  final host = doc.find(hostId);
  if (host == null) return false;
  if (slot != null && !lcSlotsOf(host).any((s) => s.name == slot)) return false;
  final at = slot == null ? index : lcFlatIndex(host, slot, index ?? 1 << 30);
  if (slot != null) node.slot = slot;
  if (!doc.insert(hostId, node, at)) return false;
  // insert 会给新节点发 id，这时再按“在哪个容器里”收拾 slot
  if (slot == null && !host.hasSlots) node.slot = null;
  return true;
}

/// 把已有的节点挪到 [target] 的第 [index] 个位置（[index] 按挪之前的顺序算，和 LcDocument.move 一样）。
bool lcMoveTo(LcDocument doc, String id, String target, int index) {
  final (hostId, slot) = lcSplitSlotId(target);
  final node = doc.find(id), host = doc.find(hostId);
  if (node == null || host == null) return false;
  if (slot == null) {
    if (!doc.move(id, hostId, index)) return false;
    _settle(doc, node, null);
    return true;
  }
  if (!lcSlotsOf(host).any((s) => s.name == slot)) return false;
  final at = lcFlatIndex(host, slot, index);
  if (!doc.move(id, hostId, at)) return false;
  node.slot = slot;
  return true;
}

/// 删掉一个页签：它里面的子节点一起删。返回删了几个子节点；页签不存在、或者只剩这一个页签返回 -1（不删）。
int lcRemoveTab(LcNode tabs, String tabId) {
  final all = lcObjects(tabs, 'tabs');
  if (all.length <= 1 || !all.any((t) => t['id'] == tabId)) return -1;
  final gone = lcSlotChildren(tabs, tabId);
  tabs.children.removeWhere(gone.contains);
  tabs.props['tabs'] = [
    for (final t in all)
      if (t['id'] != tabId) t,
  ];
  if (tabs.props['current'] == tabId) tabs.props['current'] = lcObjects(tabs, 'tabs').first['id'];
  return gone.length;
}

/// 给标签页发一个没用过的页签 id（`t1`、`t2`…）。
String lcNewTabId(LcNode tabs) {
  final used = {for (final t in lcObjects(tabs, 'tabs')) t['id']};
  for (var i = 1; ; i++) {
    if (!used.contains('t$i')) return 't$i';
  }
}
