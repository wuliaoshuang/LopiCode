/// “只看这个弹层”：画布现在是不是只在编辑某一个弹窗（不带界面，搭建台拿它记着）。
///
/// 规矩（E 分册 GAP-E-13 细化后的）：
/// - **进**：选中一个弹窗、或者弹窗里面的组件（画布上点页面里那个“弹窗”小标签、图层里点它、刚加进来一个弹窗），就进这个弹窗的编辑状态。
/// - **留**：点画布空白（取消选中）不退——不然在弹窗外面点一下就丢了正在编辑的东西。
/// - **出**：点顶上横条里的“退出”；或者在图层里选中了弹窗外面的组件；或者这个弹窗被删了、撤销没了。
/// - 换到另一个弹窗（图层里点另一个）＝直接换过去。
library;

import 'package:lopicode/lowcode/model.dart';

/// [id] 这个组件所在的弹窗（它自己是弹窗就是它自己）；不在任何弹窗里返回 null。
LcNode? lcEnclosingDialog(LcDocument doc, String id) {
  LcNode? n = doc.find(id);
  for (var guard = 0; n != null && guard <= LcNode.maxDepth * 4; guard++) {
    if (n.type == 'dialog') return n;
    n = doc.parentOf(n.id);
  }
  return null;
}

class LcOverlayFocus {
  String? _id;
  String? _seen;

  /// 每次重搭时调一下：按现在选中的是谁更新，返回正在编辑的弹窗（没有是 null）。
  LcNode? sync(LcDocument doc, String? selected) {
    if (selected != _seen) {
      _seen = selected;
      if (selected != null) _id = lcEnclosingDialog(doc, selected)?.id;
    }
    final node = _id == null ? null : doc.find(_id!);
    if (node == null || node.type != 'dialog') {
      _id = null;
      return null;
    }
    return node;
  }

  /// 点了“退出”。调用方同时要取消选中（不然选中的还是看不见的弹窗）。
  void exit() {
    _id = null;
    _seen = null;
  }
}
