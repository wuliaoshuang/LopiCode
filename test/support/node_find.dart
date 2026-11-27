import 'package:lopicode/lowcode/model.dart';

/// 在一棵节点树里按 id 找（组件定义的树没有文档那样的 find）。
LcNode? nodeIn(LcNode root, String id) {
  if (root.id == id) return root;
  for (final c in root.children) {
    final hit = nodeIn(c, id);
    if (hit != null) return hit;
  }
  return null;
}
