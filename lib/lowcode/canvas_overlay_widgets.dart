// 设计约束（低代码 · 画布上叠的选中层）
// - 选中框、盒模型示意（外边距橙色、内边距绿色，都半透明）只是画上去的，不挡手指。
// - 拖柄：画出来是 9px 的小方块，能按住的范围是 32px（都按屏幕上的大小算，不随缩放变大变小）。
//   能按的范围往组件外侧偏 8px，尽量不盖住组件本身（还要能点它、长按拖它）。
// - 组件太小时只留四个角的拖柄，边上的省掉。
// - 尺寸标签（“160 × 48”）贴在选中框左下角外面。
import 'package:flutter/gestures.dart';
import 'package:lopicode/lowcode/canvas_css.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// 选中的那个组件在页面里的位置和间距（都是页面坐标，没乘缩放）。
@immutable
class CanvasSelection {
  const CanvasSelection({required this.nodeId, required this.rect, required this.margin, required this.border, required this.padding, required this.isRoot});
  final String nodeId;

  /// 边框盒。
  final Rect rect;
  final CssEdges margin;
  final CssEdges border;
  final CssEdges padding;
  final bool isRoot;

  @override
  bool operator ==(Object other) =>
      other is CanvasSelection && other.nodeId == nodeId && other.rect == rect && other.margin == margin && other.border == border && other.padding == padding && other.isRoot == isRoot;

  @override
  int get hashCode => Object.hash(nodeId, rect, margin, border, padding, isRoot);
}

/// 八个拖柄：名字 → 在哪一侧（-1 左 / 上，0 中，1 右 / 下）。角上的排在后面，叠在边上的上面。
const Map<String, (int, int)> kCanvasHandles = {'n': (0, -1), 's': (0, 1), 'w': (-1, 0), 'e': (1, 0), 'nw': (-1, -1), 'ne': (1, -1), 'sw': (-1, 1), 'se': (1, 1)};

const double _hit = 32;
const double _outward = 8;

class CanvasSelectionOverlay extends StatelessWidget {
  const CanvasSelectionOverlay({
    super.key,
    required this.selection,
    required this.scale,
    required this.showBoxModel,
    required this.onResizeStart,
    required this.onResizeUpdate,
    required this.onResizeEnd,
  });

  final CanvasSelection selection;

  /// 画布当前的缩放比例：拖柄、线宽、标签按它反着缩，保证屏幕上看起来一样大。
  final double scale;
  final bool showBoxModel;
  final void Function(String handle, Offset globalPosition) onResizeStart;
  final void Function(Offset globalPosition) onResizeUpdate;

  /// [cancelled]：手势被打断，不要写入。
  final void Function({required bool cancelled}) onResizeEnd;

  @override
  Widget build(BuildContext context) {
    final rect = selection.rect;
    final k = 1 / scale;
    final screenW = rect.width * scale, screenH = rect.height * scale;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: IgnorePointer(child: CustomPaint(painter: _SelectionPainter(selection, scale, showBoxModel))),
        ),
        Positioned(
          left: rect.left,
          top: rect.bottom + 6 * k,
          child: IgnorePointer(
            child: Transform.scale(
              scale: k,
              alignment: Alignment.topLeft,
              child: Container(
                key: const ValueKey('lowcode-size-label'),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: Palette.primary500, borderRadius: BorderRadius.circular(4)),
                child: Text(
                  '${rect.width.round()} × ${rect.height.round()}',
                  style: const TextStyle(fontSize: 11, height: 1.3, color: Colors.white, fontWeight: FontWeight.w500, decoration: TextDecoration.none),
                ),
              ),
            ),
          ),
        ),
        if (!selection.isRoot)
          for (final e in kCanvasHandles.entries)
            // 边上的拖柄要给两头的角让出地方：这个方向不够长就不放。
            if ((e.value.$1 == 0 || e.value.$2 == 0) ? (e.value.$1 == 0 ? screenW : screenH) >= 56 : true) _handle(e.key, e.value.$1, e.value.$2, k),
      ],
    );
  }

  Widget _handle(String name, int hx, int hy, double k) {
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
              color: Colors.white,
              border: Border.all(color: Palette.primary500, width: 1.5 * k),
              borderRadius: BorderRadius.circular(2 * k),
            ),
          ),
        ),
      ),
    );
  }
}

class _SelectionPainter extends CustomPainter {
  const _SelectionPainter(this.sel, this.scale, this.showBoxModel);
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
      if (!sel.isRoot) _ring(canvas, _inflate(rect, sel.margin), rect, const Color(0x59FF9800));
      final inside = _deflate(rect, sel.border);
      _ring(canvas, inside, _deflate(inside, sel.padding), const Color(0x5934C759));
    }
    // 页面自己选中时的框由页面画（贴着页面边缘往里画，不会被裁掉）。
    if (!sel.isRoot) {
      canvas.drawRect(
        rect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2 / scale
          ..color = Palette.primary500,
      );
    }
  }

  @override
  bool shouldRepaint(_SelectionPainter old) => old.sel != sel || old.scale != scale || old.showBoxModel != showBoxModel;
}
