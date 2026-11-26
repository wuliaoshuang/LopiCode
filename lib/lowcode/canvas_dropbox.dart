/// 拖动开始时把画布上每个组件“在哪、能不能往里放”量成一棵 [DropBox] 树（不带界面；位置由调用方给）。
///
/// - 普通容器：能放，子项就是它的子组件。
/// - 自定义组件的实例：整块不能放。
/// - 带插槽的组件（列表行、导航栏、标签页、弹窗）：它自己不能放，能放的是它的每个插槽（id 是 `组件id#插槽名`，见 slots.dart）；
///   画布上现在没画出来的插槽（标签页别的页签、没进编辑状态的弹窗）量不到位置，就不算。
///   横排的空插槽只有 28 见方，落点往外放大 8，手指好对准。
/// - 网格容器：标上是网格，落点按“从左到右、从上到下”算（editor_drag.dart）。
/// - “只看这个弹层”时：页面本身不能放，能放的只有那个弹窗的插槽。
library;

import 'dart:ui';

import 'package:lopicode/lowcode/canvas_css.dart';
import 'package:lopicode/lowcode/component_ops.dart';
import 'package:lopicode/lowcode/editor_drag.dart';
import 'package:lopicode/lowcode/grid_css.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/slots.dart';
import 'package:lopicode/lowcode/style_resolve.dart';

/// [rectOf]：一个组件（或插槽）的边框盒在页面上的位置，没画出来返回 null。
DropBox? lcDropBoxTree(LcDocument doc, Rect? Function(String id) rectOf, {String? overlayId}) {
  final rootRect = rectOf(doc.root.id);
  if (rootRect == null) return null;
  final dialog = overlayId == null ? null : doc.find(overlayId);
  if (dialog != null && dialog.type == 'dialog') {
    final box = _boxOf(doc, dialog, doc.parentOf(dialog.id), rectOf);
    return DropBox(id: doc.root.id, label: doc.root.spec.label, rect: rootRect, children: [?box]);
  }
  return _boxOf(doc, doc.root, null, rectOf);
}

DropBox? _boxOf(LcDocument doc, LcNode node, LcNode? parent, Rect? Function(String id) rectOf) {
  final rect = rectOf(node.id);
  if (rect == null) return null;
  final instance = node.type == 'component';
  final label = instance ? componentLabel(doc, node) : node.spec.label;
  if (node.hasSlots) {
    final slots = <DropBox>[];
    for (final slot in lcSlotsOf(node)) {
      final id = lcSlotBoxId(node.id, slot.name);
      final r = rectOf(id);
      if (r == null) continue;
      final row = lcSlotIsRow(node, slot.name);
      final kids = [for (final c in lcSlotChildren(node, slot.name)) ?_boxOf(doc, c, node, rectOf)];
      slots.add(DropBox(id: id, label: '$label · ${slot.label}', rect: kids.isEmpty && row ? r.inflate(8) : r, container: true, row: row, children: kids));
    }
    return DropBox(id: node.id, label: label, rect: rect, children: slots);
  }
  final container = node.isContainer && !instance;
  final style = container ? resolvedStyle(node, parent) : const <String, String>{};
  final flow = container ? cssFlow(style, rowByDefault: node.type == 'row') : null;
  return DropBox(
    id: node.id,
    label: label,
    rect: rect,
    container: container,
    row: flow?.row ?? false,
    reverse: flow?.reverse ?? false,
    grid: container && lcIsGrid(style),
    children: container ? [for (final c in node.children) ?_boxOf(doc, c, node, rectOf)] : const [],
  );
}
