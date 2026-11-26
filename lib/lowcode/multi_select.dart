/// 多选（一次选中同一层的几个组件）要用的纯计算：能不能加进来、一起复制 / 删除 / 包成容器 / 挪动。
///
/// 规矩（设计见 docs/blocks-v5-parts/E-editor-components.md §3.3）：
/// - 只能一起选**同一个容器里的兄弟**；页面本身不能选。
/// - 一起做的每件事都按它们在页面上的先后来（不按点选的先后）。
/// - 这里只改文档，不记撤销、不存盘：调用的人把它包在一次统一修改里，所以每件事一条撤销。
library;

import 'package:lopicode/lowcode/editor_clipboard.dart';
import 'package:lopicode/lowcode/logic_edit.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/slots.dart';

/// 跨层选的时候说的那句话。
const String kLcMultiSameLevelOnly = '只能一起选同一层的';

/// 点了一个组件：已经选中就移出，没选中就加进来。
/// 返回 null＝照办了（[ids] 已经改好）；返回一句话＝没办成，原因就是这句话。
String? lcMultiToggle(LcDocument doc, Set<String> ids, String id) {
  if (ids.remove(id)) return null;
  final parent = doc.parentOf(id);
  if (parent == null) return doc.find(id) == null ? '找不到这个组件' : '页面本身不能和别的一起选';
  if (ids.isNotEmpty && !identical(doc.parentOf(ids.first), parent)) return kLcMultiSameLevelOnly;
  ids.add(id);
  return null;
}

/// 文档变了（撤销、被别处删了）以后：去掉已经不在的、不再是同一层的。
void lcMultiPrune(LcDocument doc, Set<String> ids) {
  ids.removeWhere((id) => doc.parentOf(id) == null);
  if (ids.isEmpty) return;
  final parent = doc.parentOf(ids.first);
  ids.removeWhere((id) => !identical(doc.parentOf(id), parent));
}

/// 选中的这几个，按页面上的先后排好。
List<LcNode> lcMultiOrdered(LcDocument doc, Set<String> ids) {
  if (ids.isEmpty) return const [];
  final parent = doc.parentOf(ids.first);
  if (parent == null) return const [];
  return [
    for (final c in parent.children)
      if (ids.contains(c.id)) c,
  ];
}

/// 一起复制到搭建页的剪贴板。
bool lcMultiCopy(LcDocument doc, Set<String> ids) {
  final nodes = lcMultiOrdered(doc, ids);
  return nodes.isNotEmpty && lcClipboardCopyMany(doc, [for (final n in nodes) n.id]);
}

/// 这几个（连同它们里面的）在积木逻辑里被用到几处。
int lcMultiLogicRefs(LcDocument doc, Set<String> ids) {
  var refs = 0;
  void walk(LcNode n) {
    refs += doc.logic.nodeRefCount(n.id);
    n.children.forEach(walk);
  }

  lcMultiOrdered(doc, ids).forEach(walk);
  return refs;
}

/// 一起删掉（用到它们的积木逻辑一并清掉）。返回删了几个。
int lcMultiDelete(LcDocument doc, Set<String> ids) {
  final nodes = lcMultiOrdered(doc, ids);
  void walk(LcNode n) {
    doc.logic.removeNodeRefs(n.id);
    n.children.forEach(walk);
  }

  for (final n in nodes) {
    walk(n);
    doc.remove(n.id);
  }
  return nodes.length;
}

/// 把这几个一起包进一个新容器（容器放在第一个原来的位置，里面的先后不变）。返回新容器的编号；包不了返回 null。
String? lcMultiWrap(LcDocument doc, Set<String> ids) {
  final nodes = lcMultiOrdered(doc, ids);
  if (nodes.isEmpty) return null;
  final parent = doc.parentOf(nodes.first.id)!;
  final box = doc.newNode('container');
  // 和包一个时一样：新容器不带自己的内边距和间距，包上以后页面看起来尽量不变。
  box.props
    ..remove('padding')
    ..remove('gap');
  box.slot = nodes.first.slot; // 包的是插槽里的组件：容器顶替它们留在那个插槽里
  if (!doc.insert(parent.id, box, parent.children.indexOf(nodes.first))) return null;
  for (var i = 0; i < nodes.length; i++) {
    doc.move(nodes[i].id, box.id, i);
  }
  return box.id;
}

/// 一起上移 / 下移一位（[delta] 是 -1 / 1）。已经顶到头的不动；一个都没动返回 false。
bool lcMultiShift(LcDocument doc, Set<String> ids, int delta) {
  final nodes = lcMultiOrdered(doc, ids);
  if (nodes.isEmpty) return false;
  final list = doc.parentOf(nodes.first.id)!.children;
  var moved = false;
  // 往下挪从最后一个开始，往上挪从第一个开始：前面的让出位置，后面的才有地方去。
  for (final n in delta > 0 ? nodes.reversed : nodes) {
    final i = list.indexOf(n), j = i + delta;
    if (j < 0 || j >= list.length || ids.contains(list[j].id)) continue;
    list
      ..removeAt(i)
      ..insert(j, n);
    moved = true;
  }
  return moved;
}

bool _contains(LcNode n, String id) => n.id == id || n.children.any((c) => _contains(c, id));

/// 这几个能不能一起放进 [parentId]（不能放进它们自己或自己里面）。
bool lcMultiCanDropInto(LcDocument doc, Set<String> ids, String parentId) {
  final (hostId, slot) = lcSplitSlotId(parentId);
  final target = doc.find(hostId);
  if (target == null || !target.isContainer || lcMultiOrdered(doc, ids).any((n) => _contains(n, hostId))) return false;
  return slot == null || lcSlotsOf(target).any((s) => s.name == slot);
}

/// 一起挪到 [parentId] 的第 [index] 个位置（按挪走之前的顺序数，和 LcDocument.move 一样）；挪过去以后它们挨在一起、先后不变。
bool lcMultiMoveTo(LcDocument doc, Set<String> ids, String parentId, int index) {
  final nodes = lcMultiOrdered(doc, ids);
  // [parentId] 可以是插槽（`组件id#插槽名`，见 slots.dart）：位置按插槽里的第几个算，挪进去以后写上 slot。
  final (hostId, slot) = lcSplitSlotId(parentId);
  final target = doc.find(hostId);
  if (nodes.isEmpty || target == null || !lcMultiCanDropInto(doc, ids, parentId)) return false;
  // 落点后面第一个“不在这次挪动里的”：挪完以后它们排在它前面。
  final at = slot == null ? index.clamp(0, target.children.length) : lcFlatIndex(target, slot, index);
  LcNode? anchor;
  for (var i = at; i < target.children.length; i++) {
    if (!ids.contains(target.children[i].id)) {
      anchor = target.children[i];
      break;
    }
  }
  final from = doc.parentOf(nodes.first.id)!;
  from.children.removeWhere((c) => ids.contains(c.id));
  final to = anchor == null ? target.children.length : target.children.indexOf(anchor);
  target.children.insertAll(to, nodes);
  for (final n in nodes) {
    if (slot != null) {
      n.slot = slot;
    } else if (!target.hasSlots) {
      n.slot = null;
    }
  }
  return true;
}

/// 这几个都有的简写属性（“改公共样式”里只放大家都有的那几项），按第一个组件的字段顺序。
List<String> lcMultiCommonFields(LcDocument doc, Set<String> ids) {
  final nodes = lcMultiOrdered(doc, ids);
  if (nodes.isEmpty) return const [];
  return [
    for (final f in nodes.first.spec.fields)
      if (nodes.every((n) => n.spec.fields.contains(f))) f,
  ];
}
