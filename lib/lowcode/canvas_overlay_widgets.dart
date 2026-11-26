// 设计约束（低代码 · 画布上叠的选中层）
// - 选中框、盒模型示意（外边距橙色、内边距绿色，都半透明）只是画上去的，不挡手指。
// - 拖柄：画出来是 9px 的小方块，能按住的范围是 44px（都按屏幕上的大小算，不随缩放变大变小）。
//   能按的范围往组件外侧偏 14px：伸进组件里面的只有 8px，尽量不盖住组件本身（还要能点它、长按拖它）。
// - 组件太小时只留四个角的拖柄：边上的要这条边够长（屏幕上 ≥ 60px：两个角各伸进来 8，中间还放得下 44）才放。
// - 尺寸标签（“160 × 48”）放在选中框里面的右下角，不挡框外面别的组件；框不够宽裕（不到两个标签宽、三个标签高）就放到框的上方（上方没地方放下方）。
//   放到框外面时要避开旁边的组件：上方靠右 → 下方靠右 → 上方靠左 → 下方靠左 → 右边 → 左边，挨个试，第一个不盖住别的组件的就用；
//   都会盖住（周围挤满了）：框够宽就收进框里面的右头（字一般靠左），不够宽用盖得最少的那个。不管放哪都收在屏幕看得见的那一块里面，不会被屏幕边切掉。
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:lopicode/lowcode/canvas_css.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/style_resolve.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// 选中的那个组件在页面里的位置和间距（都是页面坐标，没乘缩放）。
@immutable
class CanvasSelection {
  const CanvasSelection({required this.nodeId, required this.rect, required this.margin, required this.border, required this.padding, required this.isRoot, this.avoid = const []});

  /// 量好位置以后算出选中层要的东西。[base]＝百分比间距按多宽算（父容器的宽），[page]＝页面多大。
  factory CanvasSelection.of(LcNode node, LcNode? parent, Rect rect, {required double base, required Size page, List<Rect> avoid = const []}) {
    final style = resolvedStyle(node, parent);
    final scale = CssScale(pageWidth: page.width, pageHeight: page.height);
    final font = scale.withFont(cssSizePx(style['font-size'], scale) ?? 16);
    return CanvasSelection(
      nodeId: node.id,
      rect: rect,
      margin: cssEdges(style, 'margin', font, percentOf: base),
      border: cssBorderWidths(style, font),
      padding: cssEdges(style, 'padding', font, percentOf: base),
      isRoot: parent == null || node.locked,
      avoid: avoid,
    );
  }
  final String nodeId;

  /// 旁边别的组件占的地方（页面坐标）：尺寸标签放到框外面时避开它们。
  final List<Rect> avoid;

  /// 边框盒。
  final Rect rect;
  final CssEdges margin;
  final CssEdges border;
  final CssEdges padding;

  /// 不出拖柄、不画外边距那一圈：页面本身，和锁定了的组件。
  final bool isRoot;

  @override
  bool operator ==(Object other) =>
      other is CanvasSelection &&
      other.nodeId == nodeId &&
      other.rect == rect &&
      other.margin == margin &&
      other.border == border &&
      other.padding == padding &&
      other.isRoot == isRoot &&
      listEquals(other.avoid, avoid);

  @override
  int get hashCode => Object.hash(nodeId, rect, margin, border, padding, isRoot, Object.hashAll(avoid));
}

/// 八个拖柄：名字 → 在哪一侧（-1 左 / 上，0 中，1 右 / 下）。角上的排在后面，叠在边上的上面。
const Map<String, (int, int)> kCanvasHandles = {'n': (0, -1), 's': (0, 1), 'w': (-1, 0), 'e': (1, 0), 'nw': (-1, -1), 'ne': (1, -1), 'sw': (-1, 1), 'se': (1, 1)};

/// 拖柄能按住的范围（屏幕像素）。
const double kCanvasHandleHit = 44;
const double _hit = kCanvasHandleHit;
const double _outward = 14;

/// 边上的拖柄要这条边在屏幕上至少这么长才放。
const double _edgeHandleMin = 60;

// 尺寸标签：11 号字，左右各留 6。按字数估宽度（数字、空格、乘号都差不多宽），估大一点没关系。
const double _labelHeight = 19;
double _labelWidth(String text) => text.length * 7.0 + 12;

class CanvasSelectionOverlay extends StatelessWidget {
  const CanvasSelectionOverlay({
    super.key,
    required this.selection,
    required this.scale,
    required this.visible,
    required this.showBoxModel,
    required this.onResizeStart,
    required this.onResizeUpdate,
    required this.onResizeEnd,
    required this.onTapThrough,
  });

  final CanvasSelection selection;

  /// 画布当前的缩放比例：拖柄、线宽、标签按它反着缩，保证屏幕上看起来一样大。
  final double scale;

  /// 屏幕上看得见的那一块（页面坐标）：尺寸标签收在它里面。
  final Rect visible;
  final bool showBoxModel;
  final void Function(String handle, Offset globalPosition) onResizeStart;
  final void Function(Offset globalPosition) onResizeUpdate;

  /// [cancelled]：手势被打断，不要写入。
  final void Function({required bool cancelled}) onResizeEnd;

  /// 在拖柄上只是点了一下（没拖）：交给画布当成点在下面的组件上。
  final void Function(Offset globalPosition) onTapThrough;

  @override
  Widget build(BuildContext context) {
    final rect = selection.rect;
    final ui = context.themeSpec;
    final k = 1 / scale;
    final screenW = rect.width * scale, screenH = rect.height * scale;
    final text = '${rect.width.round()} × ${rect.height.round()}';
    final at = sizeLabelOrigin(rect, visible, scale, text, avoid: selection.avoid);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: IgnorePointer(child: CustomPaint(painter: _SelectionPainter(selection, scale, showBoxModel, ui))),
        ),
        Positioned(
          left: at.dx,
          top: at.dy,
          child: IgnorePointer(
            child: Transform.scale(
              scale: k,
              alignment: Alignment.topLeft,
              child: Container(
                key: const ValueKey('lowcode-size-label'),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: ui.lowcodeColor(LowcodeKey.selection), borderRadius: BorderRadius.circular(4)),
                child: Text(
                  text,
                  style: TextStyle(fontSize: 11, height: 1.3, color: ui.lowcodeColor(LowcodeKey.selectionText), fontWeight: FontWeight.w500, decoration: TextDecoration.none),
                ),
              ),
            ),
          ),
        ),
        if (!selection.isRoot)
          for (final e in kCanvasHandles.entries)
            // 边上的拖柄要给两头的角让出地方：这个方向不够长就不放。
            if ((e.value.$1 == 0 || e.value.$2 == 0) ? (e.value.$1 == 0 ? screenW : screenH) >= _edgeHandleMin : true) _handle(e.key, e.value.$1, e.value.$2, k, ui),
      ],
    );
  }

  Widget _handle(String name, int hx, int hy, double k, ThemeSpec ui) {
    final rect = selection.rect;
    final cx = rect.center.dx + hx * rect.width / 2, cy = rect.center.dy + hy * rect.height / 2;
    final size = _hit * k;
    return Positioned(
      // 按名字认：拖大以后边上会多出拖柄，不认名字的话正在拖的那个会被当成别的拖柄换掉，拖到一半就断了。
      key: ValueKey('lc-handle-slot-$name'),
      left: cx - size / 2 + hx * _outward * k,
      top: cy - size / 2 + hy * _outward * k,
      width: size,
      height: size,
      child: GestureDetector(
        key: ValueKey('lowcode-handle-$name'),
        behavior: HitTestBehavior.opaque,
        // 从按下的那一点算起：不然开始拖之前“试探”的那一小段位移会丢，组件的边跟不上手指
        dragStartBehavior: DragStartBehavior.down,
        onTapUp: (d) => onTapThrough(d.globalPosition),
        onPanStart: (d) => onResizeStart(name, d.globalPosition),
        onPanUpdate: (d) => onResizeUpdate(d.globalPosition),
        onPanEnd: (_) => onResizeEnd(cancelled: false),
        onPanCancel: () => onResizeEnd(cancelled: true),
        child: Align(
          // 小方块画在组件的角 / 边上，不跟着能按的范围往外偏
          alignment: Alignment(-hx * _outward * 2 / (_hit - 9), -hy * _outward * 2 / (_hit - 9)),
          child: Container(
            width: 9 * k,
            height: 9 * k,
            decoration: BoxDecoration(
              color: ui.lowcodeColor(LowcodeKey.handleFill),
              border: Border.all(color: ui.lowcodeColor(LowcodeKey.selection), width: 1.5 * k),
              borderRadius: BorderRadius.circular(2 * k),
            ),
          ),
        ),
      ),
    );
  }
}

/// 尺寸标签要不要避开 [id] 这个组件占的那一块（[box]，页面坐标）：选中的自己、包着选中框的（它的各层容器）、
/// 里面还有东西的容器（让它里面的各自算）不用避；别的都避。
bool sizeLabelAvoids(LcDocument doc, String selectedId, Rect selected, String id, Rect box) {
  if (id == selectedId || id.contains('#')) return false;
  if (doc.find(id)?.children.isNotEmpty ?? false) return false;
  final both = box.expandToInclude(selected);
  return both != box && both != selected; // 谁也不包着谁
}

/// 尺寸标签的左上角放哪（页面坐标）。[rect]＝选中框，[visible]＝屏幕上看得见的那一块，都是页面坐标。
/// [avoid]＝旁边别的组件占的地方：标签放到框外面时尽量不盖住它们。
Offset sizeLabelOrigin(Rect rect, Rect visible, double scale, String text, {List<Rect> avoid = const []}) {
  final k = 1 / scale;
  final w = _labelWidth(text) * k, h = _labelHeight * k, gap = 6 * k;
  Offset clamp(double left, double top) => Offset(math.max(visible.left, math.min(left, visible.right - w)), math.max(visible.top, math.min(top, visible.bottom - h)));
  // “放得下”要宽裕：框至少有两个标签宽、三个标签高。刚好塞得进的小组件（一个按钮、一行标题）放进去会把它的字盖住
  // （第 2 期出截图时看到 88×48 的按钮上的字被标签挡了）。
  if (rect.width >= w * 2 + gap * 2 && rect.height >= h * 3 + gap * 2) return clamp(rect.right - gap - w, rect.bottom - gap - h); // 框里面的右下角
  // 放不下：框外面。挨个试，第一个整个露得出来、又不盖住别的组件的就用。
  final above = rect.top - gap - h, below = rect.bottom + gap, mid = rect.center.dy - h / 2;
  final spots = [Offset(rect.right - w, above), Offset(rect.right - w, below), Offset(rect.left, above), Offset(rect.left, below), Offset(rect.right + gap, mid), Offset(rect.left - gap - w, mid)];
  double covered(Offset at) {
    final box = (at & Size(w, h)).deflate(0.5 * k);
    var area = 0.0;
    for (final r in [...avoid, rect]) {
      final hit = box.intersect(r);
      if (hit.width > 0 && hit.height > 0) area += hit.width * hit.height;
    }
    return area;
  }

  if (avoid.isNotEmpty) {
    Offset? best;
    var least = double.infinity;
    for (final spot in spots) {
      if (clamp(spot.dx, spot.dy) != spot) continue; // 露不全的不算
      final c = covered(spot);
      if (c == 0) return spot;
      if (c < least) (best, least) = (spot, c);
    }
    // 四周都有东西：框够宽（放得下两个标签）就收进框里面的右头——字一般靠左，右头多半是空的；不够宽才用盖得最少的那个。
    if (rect.width >= w * 2 + gap * 2) return clamp(rect.right - gap - w, rect.center.dy - h / 2);
    if (best != null) return best;
  }
  // 旁边没东西要避（或者哪儿都露不全）：框的上方靠右；上方露不出来就放下方
  return clamp(rect.right - w, above < visible.top ? below : above);
}

class _SelectionPainter extends CustomPainter {
  const _SelectionPainter(this.sel, this.scale, this.showBoxModel, this.ui);
  final ThemeSpec ui;
  final CanvasSelection sel;
  final double scale;
  final bool showBoxModel;

  static Rect _inflate(Rect r, CssEdges e) => Rect.fromLTRB(r.left - e.left, r.top - e.top, r.right + e.right, r.bottom + e.bottom);

  /// 往里收；收过头（间距比盒子还大）就停在中间，不画反了的矩形。
  static Rect _deflate(Rect r, CssEdges e) {
    final left = (r.left + e.left).clamp(r.left, r.center.dx).toDouble(), right = (r.right - e.right).clamp(r.center.dx, r.right).toDouble();
    final top = (r.top + e.top).clamp(r.top, r.center.dy).toDouble(), bottom = (r.bottom - e.bottom).clamp(r.center.dy, r.bottom).toDouble();
    return Rect.fromLTRB(left, top, right, bottom);
  }

  static void _ring(Canvas canvas, Rect outer, Rect inner, Color color) {
    if (outer == inner) return;
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(outer)
      ..addRect(inner);
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rect = sel.rect;
    if (showBoxModel) {
      if (!sel.isRoot) _ring(canvas, _inflate(rect, sel.margin), rect, ui.lowcodeColor(LowcodeKey.marginRing));
      final inside = _deflate(rect, sel.border);
      _ring(canvas, inside, _deflate(inside, sel.padding), ui.lowcodeColor(LowcodeKey.paddingRing));
    }
    // 页面自己选中时的框由页面画（贴着页面边缘往里画，不会被裁掉）。
    if (!sel.isRoot) {
      canvas.drawRect(
        rect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2 / scale
          ..color = ui.lowcodeColor(LowcodeKey.selection),
      );
    }
  }

  @override
  bool shouldRepaint(_SelectionPainter old) => old.sel != sel || old.scale != scale || old.showBoxModel != showBoxModel;
}
