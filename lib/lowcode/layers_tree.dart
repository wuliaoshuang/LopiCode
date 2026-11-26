/// 图层面板的两样纯计算：现在该显示哪些行（折起来的不显示里面的），和拖一行时落在哪儿。
library;

import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/slots.dart';

/// 图层面板里的一行。
class LayerRow {
  const LayerRow(this.node, this.depth, {required this.collapsed});
  final LcNode node;
  final int depth;

  /// 这一行折着（里面的不显示）。没有子组件的永远是 false。
  final bool collapsed;
  bool get hasChildren => node.children.isNotEmpty;
}

/// 从 [root] 起按层排出要显示的行；[collapsed] 里的组件只显示自己。
List<LayerRow> layerRows(LcNode root, Set<String> collapsed) {
  final rows = <LayerRow>[];
  void walk(LcNode n, int depth) {
    final folded = n.children.isNotEmpty && collapsed.contains(n.id);
    rows.add(LayerRow(n, depth, collapsed: folded));
    if (folded) return;
    for (final c in n.children) {
      walk(c, depth + 1);
    }
  }

  walk(root, 0);
  return rows;
}

/// 图层面板里一行的名字：她起了名字就是名字，没起就是类型名。
String layerTitle(LcNode n) => n.name.isNotEmpty ? n.name : n.spec.label;

/// 名字后面那句灰字：上面的字 / 提示文字；起了名字的再带上类型名（不然看不出它是个什么）。
String layerHint(LcNode n) {
  final text = n.strProp('text') ?? n.strProp('placeholder') ?? '';
  if (n.name.isEmpty) return text;
  return text.isEmpty ? n.spec.label : '${n.spec.label} · $text';
}

/// 这一行放在带插槽的组件里时，说它在哪个插槽：“在「底部按钮」里”。它上一层不带插槽就是空的。
/// 自定义组件已经没有插槽了、它还留在里面：说“没地方放（这个组件没有插槽了）”——画布上看不到它，只有这里找得到。
String layerSlotNote(LcDocument doc, LcNode n) {
  final parent = doc.parentOf(n.id);
  if (parent == null) return '';
  final slots = lcSlotsOf(parent);
  if (slots.isEmpty) return parent.type == 'component' ? '没地方放（这个组件没有插槽了）' : '';
  final name = n.slot ?? lcFallbackSlot(parent);
  final slot = slots.where((s) => s.name == name).firstOrNull;
  return slot == null ? '没地方放（没有这个插槽了）' : '在「${slot.label}」里';
}

/// 搜索：名字、类型名、上面的字里有 [query]（不分大小写）的行，顺序不变。
List<LayerRow> layerSearch(List<LayerRow> all, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return all;
  bool hit(LcNode n) => n.name.toLowerCase().contains(q) || n.spec.label.toLowerCase().contains(q) || (n.strProp('text') ?? n.strProp('placeholder') ?? '').toLowerCase().contains(q);
  return [
    for (final r in all)
      if (hit(r.node)) LayerRow(r.node, r.depth, collapsed: false),
  ];
}

/// 拖着的那一行会落在哪儿。
class LayerDrop {
  const LayerDrop(this.parentId, this.index, {required this.line, required this.depth, required this.into});

  /// 放进哪个容器、第几个（按“挪走之前”的顺序数，和 LcDocument.move 的算法一致）。
  final String parentId;
  final int index;

  /// 提示线画在第几行的上沿（＝行数时画在最后一行的下沿）。[into] 为 true 时是“整行高亮第 line 行”。
  final int line;

  /// 提示线从第几层缩进开始画。
  final int depth;

  /// 是不是“放进这一行里面”（拖到某行右半边）。
  final bool into;

  @override
  bool operator ==(Object other) => other is LayerDrop && other.parentId == parentId && other.index == index && other.line == line && other.into == into;

  @override
  int get hashCode => Object.hash(parentId, index, line, into);
}

bool _contains(LcNode n, String id) => n.id == id || n.children.any((c) => _contains(c, id));

LcNode? _parentOf(LcNode root, String id) {
  for (final c in root.children) {
    if (c.id == id) return root;
    final r = _parentOf(c, id);
    if (r != null) return r;
  }
  return null;
}

/// 手指在面板里的位置（[dy] 从第一行的上沿量，[dx] 从面板左边量）→ 落点。
///
/// - 手指在某一行的**右半边**、那一行是容器：放进它里面（排最后）。
/// - 否则看上半行 / 下半行：放在它前面 / 后面（它是展开着的、有内容的容器时，“后面”＝它里面的第一个）。
/// - 不能放进自己或自己里面；最顶上那一行（页面 / 组件的最外层）前后都不能放，只能放进去。
/// - 放下去位置不变的（原地）返回 null。
LayerDrop? layerDropTarget(LcNode root, List<LayerRow> rows, String dragId, double dy, double dx, {required double rowHeight, required double width}) {
  if (rows.isEmpty) return null;
  final i = (dy / rowHeight).floor().clamp(0, rows.length - 1);
  final row = rows[i], target = row.node;
  final dragged = rows.where((r) => r.node.id == dragId).firstOrNull?.node;
  if (dragged == null || _contains(dragged, target.id)) return null;
  final oldParent = _parentOf(root, dragId);
  if (oldParent == null) return null;
  final oldIndex = oldParent.children.indexOf(dragged);
  LayerDrop? at(LcNode parent, int index, {required int line, required int depth, bool into = false}) {
    // 原地：还在同一个容器里，而且是紧挨着自己的前面或后面。
    if (identical(parent, oldParent) && (index == oldIndex || index == oldIndex + 1)) return null;
    return LayerDrop(parent.id, index, line: line, depth: depth, into: into);
  }

  final isRoot = identical(target, root);
  if (target.isContainer && (dx > width / 2 || isRoot)) return at(target, target.children.length, line: i, depth: row.depth + 1, into: true);
  if (isRoot) return null;
  final parent = _parentOf(root, target.id)!;
  final index = parent.children.indexOf(target);
  final lower = dy - i * rowHeight > rowHeight / 2;
  if (!lower) return at(parent, index, line: i, depth: row.depth);
  if (target.isContainer && target.children.isNotEmpty && !row.collapsed) return at(target, 0, line: i + 1, depth: row.depth + 1);
  return at(parent, index + 1, line: i + 1, depth: row.depth);
}
