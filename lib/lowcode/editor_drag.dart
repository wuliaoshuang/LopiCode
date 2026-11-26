/// 拖组件时“手指在这里，该放到哪”的纯计算（不带界面，位置都是页面坐标）。
///
/// 规矩（设计文档 E 第 3.2 节）：
/// - 拖动时页面排版不动，只算出一个落点：放进哪个容器、排第几个、蓝线画在哪。
/// - 手指在一个嵌在里面的容器上：先当成“放在它前面 / 后面”（落点在它的上一层）；停在它上面满 [kDropDwell]，
///   或者它是空的，才算“放进它里面”。页面本身不用等。
/// - 不能放的地方（自己里面、自定义组件的实例里面、调用方说不行的）往上一层找；一层都不行就是没有落点。
/// - 放下去位置不会变（原地、或紧挨着自己前后）：算“原地不动”，不画线，松手什么都不改。
library;

import 'dart:ui';

/// 停在一个容器上多久算“要放进它里面”。
const Duration kDropDwell = Duration(milliseconds: 400);

/// 蓝线多粗。
const double kDropLineWidth = 3;

/// 量好的一个组件：在页面上占哪一块、是不是能放东西的容器、里面怎么排。
class DropBox {
  const DropBox({required this.id, required this.label, required this.rect, this.container = false, this.row = false, this.reverse = false, this.children = const []});
  final String id;

  /// 显示用的名字（“卡片”“页面”）。
  final String label;

  /// 边框盒（页面坐标）。
  final Rect rect;

  /// 能不能往里放（容器，且不是自定义组件的实例）。
  final bool container;

  /// 里面是不是横着排。
  final bool row;

  /// 里面是不是倒着排（row-reverse / column-reverse）。
  final bool reverse;
  final List<DropBox> children;
}

/// 算出来的落点。
class DropTarget {
  const DropTarget({required this.parentId, required this.index, required this.parentLabel, required this.parentRect, required this.ordinal, this.line, this.noop = false, this.inside = false});
  final String parentId;

  /// 插到第几个前面（按拖动开始时的子项顺序算，和 LcDocument.insert / move 用的一样）。
  final int index;
  final String parentLabel;
  final Rect parentRect;

  /// 放下以后它是第几个（从 1 数）。
  final int ordinal;

  /// 蓝线（页面坐标）。空容器没有线，整块高亮。
  final Rect? line;

  /// 放下去等于没动。
  final bool noop;

  /// 要不要把容器描出来：停够了才进去的容器、空容器。
  final bool inside;

  String get label => '放到 $parentLabel 里 · 第 $ordinal 个';

  bool sameSpot(DropTarget? other) => other != null && other.parentId == parentId && other.index == index && other.noop == noop;
}

/// 手指下面一层层的容器：从页面到最里面那个。手指在页面外面时按最近的页面内的点算。
List<DropBox> dropChain(DropBox root, Offset point) {
  final r = root.rect;
  final p = Offset(point.dx.clamp(r.left, r.right).toDouble(), point.dy.clamp(r.top, r.bottom).toDouble());
  final chain = <DropBox>[root];
  var at = root;
  while (true) {
    DropBox? next;
    // 后画的在上面：从后往前找
    for (final c in at.children.reversed) {
      if (c.rect.contains(p)) {
        next = c;
        break;
      }
    }
    if (next == null) break;
    chain.add(next);
    at = next;
  }
  return chain;
}

/// 算落点。
///
/// [armed]：停够了的容器（id）。[movingId]：正在挪的是画布上已有的哪个组件（从组件盒拖新的是 null）。
/// [canDrop]：调用方说这个容器能不能放。
DropTarget? pickDropTarget(DropBox root, Offset point, {required Set<String> armed, required bool Function(String parentId) canDrop, String? movingId}) {
  final chain = dropChain(root, point);
  // 正在挪的那个组件自己和它里面的都不算（不能放进自己里面）。
  final cut = movingId == null ? -1 : chain.indexWhere((b) => b.id == movingId);
  final usable = cut < 0 ? chain : chain.sublist(0, cut);
  for (var i = usable.length - 1; i >= 0; i--) {
    final box = usable[i];
    if (!box.container || !canDrop(box.id)) continue;
    final entered = i == 0 || box.children.isEmpty || armed.contains(box.id);
    if (!entered) continue;
    return _targetIn(box, point, movingId: movingId, inside: i > 0);
  }
  return null;
}

DropTarget _targetIn(DropBox box, Offset point, {required String? movingId, required bool inside}) {
  final kids = box.children;
  if (kids.isEmpty) {
    return DropTarget(parentId: box.id, index: 0, parentLabel: box.label, parentRect: box.rect, ordinal: 1, inside: true);
  }
  double main(Offset o) => box.row ? o.dx : o.dy;
  // 手指越过了几个子项的中点（倒着排的容器里反过来数）。
  var passed = 0;
  for (final k in kids) {
    final before = main(k.rect.center) < main(point);
    if (box.reverse ? !before : before) passed++;
  }
  final index = passed;
  final self = movingId == null ? -1 : kids.indexWhere((k) => k.id == movingId);
  final noop = self >= 0 && (index == self || index == self + 1);
  final ordinal = index + 1 - (self >= 0 && self < index ? 1 : 0);

  // 蓝线：夹在前后两个子项中间；在最前 / 最后就贴着第一个 / 最后一个的外沿。
  final prev = index > 0 ? kids[index - 1].rect : null;
  final next = index < kids.length ? kids[index].rect : null;
  double edge(Rect r, {required bool far}) {
    final start = box.row ? r.left : r.top, end = box.row ? r.right : r.bottom;
    // far＝这个子项排在后面的那一侧；倒着排时“后面”在左 / 上。
    return (far != box.reverse) ? end : start;
  }

  final double at;
  if (prev != null && next != null) {
    at = (edge(prev, far: true) + edge(next, far: false)) / 2;
  } else if (prev != null) {
    at = edge(prev, far: true) + (box.reverse ? -kDropLineWidth : kDropLineWidth);
  } else {
    at = edge(next!, far: false) + (box.reverse ? kDropLineWidth : -kDropLineWidth);
  }
  // 线的长度：跟相邻的子项一样长（两个都有就取宽的那个），不超出容器。
  final ref = prev == null ? next! : (next == null ? prev : prev.expandToInclude(next));
  const half = kDropLineWidth / 2;
  final outer = box.rect;
  final Rect line;
  if (box.row) {
    final x = at.clamp(outer.left + half, outer.right - half).toDouble();
    line = Rect.fromLTRB(x - half, ref.top.clamp(outer.top, outer.bottom).toDouble(), x + half, ref.bottom.clamp(outer.top, outer.bottom).toDouble());
  } else {
    final y = at.clamp(outer.top + half, outer.bottom - half).toDouble();
    line = Rect.fromLTRB(ref.left.clamp(outer.left, outer.right).toDouble(), y - half, ref.right.clamp(outer.left, outer.right).toDouble(), y + half);
  }
  return DropTarget(parentId: box.id, index: index, parentLabel: box.label, parentRect: box.rect, ordinal: ordinal, line: line, noop: noop, inside: inside);
}

/// 手指离上下（或左右）边缘多近开始自动滚。
const double kAutoScrollEdge = 64;

/// 自动滚最快每秒多少像素。
const double kAutoScrollMax = 900;

/// 手指在 [pos]、可滚的那一段是 [start]..[end] 时，这个方向每秒该滚多少（负＝往回滚，正＝往后滚，0＝不滚）。
/// 越靠边越快；到边缘外面按最快算。
double autoScrollSpeed(double pos, double start, double end) {
  if (end - start < kAutoScrollEdge * 2) return 0;
  if (pos < start + kAutoScrollEdge) return -kAutoScrollMax * ((start + kAutoScrollEdge - pos) / kAutoScrollEdge).clamp(0.0, 1.0);
  if (pos > end - kAutoScrollEdge) return kAutoScrollMax * ((pos - (end - kAutoScrollEdge)) / kAutoScrollEdge).clamp(0.0, 1.0);
  return 0;
}
