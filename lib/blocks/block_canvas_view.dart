// 设计约束（积木画布 · 只读版，390×844，浅色 + 深色）— 2026-11-24
// - 整块区域就是一张可以平移、双指缩放的画布，底上是淡淡的点阵；每串脚本摆在自己的 x / y 上，没有位置的自动排成一列。
// - 画布上只有积木，没有别的控件；一个脚本都没有时，正中一句话告诉人下一步做什么。
// - 点积木＝选中（亮黄描边），再点一下或点空白＝取消。这一版不能拖。
// - 内容跟着宿主的 revision 走：外面在宿主变了以后重建这个控件就行，这里不占宿主的 onChanged。
import 'dart:math' as math;

import 'package:lopicode/blocks/block_canvas_layout.dart';
import 'package:lopicode/blocks/block_colors.dart';
import 'package:lopicode/blocks/block_geometry.dart';
import 'package:lopicode/blocks/block_host.dart';
import 'package:lopicode/blocks/block_paint_view.dart';
import 'package:lopicode/blocks/block_script_view.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:material_ui/material_ui.dart';

/// 选中了哪一串的哪块积木。`path` 为空＝帽子（这一串本身）。
class BlockSelection {
  const BlockSelection(this.scriptId, this.path);
  final String scriptId;
  final LcBlockPath path;

  bool same(BlockSelection? o) => o != null && o.scriptId == scriptId && bkSameBlockPath(o.path, path);
}

class BlockCanvasView extends StatefulWidget {
  const BlockCanvasView({super.key, required this.host, this.initialSelection, this.onSelectionChanged, this.onTapHit, this.transformation});

  final BlockHost host;
  final BlockSelection? initialSelection;
  final void Function(BlockSelection? selection)? onSelectionChanged;

  /// 点到积木时顺带告诉外面点的是哪个槽位（接就地编辑用）。
  final void Function(BkPlaced script, BkHit hit)? onTapHit;

  /// 平移 / 缩放的控制器；不给就自己建一个。
  final TransformationController? transformation;

  @override
  State<BlockCanvasView> createState() => BlockCanvasViewState();
}

class BlockCanvasViewState extends State<BlockCanvasView> with BkKitHolder {
  BkCanvasLayout? _layout;
  int _rev = -1;
  List<BlockIssue> _issues = const [];
  late BlockSelection? _selection = widget.initialSelection;
  TransformationController? _own;

  TransformationController get _transform => widget.transformation ?? (_own ??= TransformationController());

  /// 现在的排布（下一步做拖拽的人从这里拿几何信息）。
  BkCanvasLayout get layout => _ensure();
  BlockSelection? get selection => _selection;

  @override
  void kitChanged() => _layout = null;

  @override
  void didUpdateWidget(BlockCanvasView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.host, widget.host)) _layout = null;
  }

  @override
  void dispose() {
    _own?.dispose();
    super.dispose();
  }

  BkCanvasLayout _ensure() {
    if (_layout == null || _rev != widget.host.revision) {
      _layout = layoutBlockCanvas(widget.host, kit.engine(widget.host));
      _rev = widget.host.revision;
      _issues = widget.host.issues;
      // 选中的那块不在了（被删、撤销）就取消选中。
      final sel = _selection;
      if (sel != null && _layout!.placed(sel.scriptId)?.layout.blockAt(sel.path) == null) _selection = null;
    }
    return _layout!;
  }

  void select(BlockSelection? s) {
    if (s == null ? _selection == null : s.same(_selection)) return;
    setState(() => _selection = s);
    widget.onSelectionChanged?.call(s);
  }

  void _tap(Offset p) {
    final found = _ensure().hitTest(p);
    if (found == null) {
      select(null);
      return;
    }
    final s = BlockSelection(found.script.id, found.hit.block.path);
    select(s.same(_selection) ? null : s);
    widget.onTapHit?.call(found.script, found.hit);
  }

  @override
  Widget build(BuildContext context) {
    final layout = _ensure();
    final palette = kit.palette;
    if (layout.scripts.isEmpty) {
      return ColoredBox(
        color: palette.canvas,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              '还没有积木。\n从下面的积木盒里拿一块“事件”出来，再往它下面拼积木。',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).hintColor),
            ),
          ),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, box) {
        final size = Size(math.max(layout.extent.width + 120, box.maxWidth), math.max(layout.extent.height + 160, box.maxHeight));
        return ColoredBox(
          color: palette.canvas,
          child: InteractiveViewer(
            transformationController: _transform,
            constrained: false,
            minScale: 0.4,
            maxScale: 2.5,
            boundaryMargin: const EdgeInsets.all(240),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (d) => _tap(d.localPosition),
              child: CustomPaint(
                size: size,
                painter: _CanvasPainter(layout: layout, kit: kit, selection: _selection, issues: _issues, revision: _rev),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CanvasPainter extends CustomPainter {
  _CanvasPainter({required this.layout, required this.kit, required this.selection, required this.issues, required this.revision});

  final BkCanvasLayout layout;
  final BkKit kit;
  final BlockSelection? selection;
  final List<BlockIssue> issues;
  final int revision;

  @override
  void paint(Canvas canvas, Size size) {
    _dots(canvas, size, kit.palette);
    for (final s in layout.scripts) {
      final sel = selection != null && selection!.scriptId == s.id ? selection : null;
      final state = BkPaintState(
        selected: sel != null && sel.path.isNotEmpty ? sel.path : null,
        selectedHat: sel != null && sel.path.isEmpty,
        errors: [
          for (final i in issues)
            if (i.scriptId == s.id && i.isError) i.path,
        ],
        warnings: [
          for (final i in issues)
            if (i.scriptId == s.id && !i.isError) i.path,
        ],
      );
      canvas.save();
      canvas.translate(s.origin.dx, s.origin.dy);
      kit.painter.paint(canvas, s.layout, state);
      canvas.restore();
    }
  }

  static void _dots(Canvas canvas, Size size, BkPalette palette) {
    const step = 24.0;
    final paint = Paint()..color = palette.canvasDot;
    for (var y = step / 2; y < size.height; y += step) {
      for (var x = step / 2; x < size.width; x += step) {
        canvas.drawCircle(Offset(x, y), 1.1, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_CanvasPainter old) =>
      !identical(old.layout, layout) || old.revision != revision || !identical(old.kit, kit) || !(selection == null ? old.selection == null : selection!.same(old.selection));
}
