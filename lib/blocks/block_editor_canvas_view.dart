// 设计约束（可编辑的积木画布，390 宽，浅色 + 深色）— 2026-11-24
// - 整块区域只有画布一样东西：点阵底 + 一串串积木。主操作＝直接用手拖积木，没有“进入编辑模式”这一步。
// - 手指落在积木上一动就是拖积木（不用长按，过 8 像素就算）；落在空白处是平移画布；两根手指是缩放（50%–200%）。
// - 手指按住不动约 0.45 秒＝长按（表达式上长按＝“换成…”）。没动就抬起＝点一下。
// - 没摆过位置的脚本自动从上往下排，算出来的位置不写回模型（不进撤销、不落盘）。
// - 画的时候只画一次排版结果；拖动时画的是“拿走以后 + 让出落点”的预览排版，模型一个字不动。
import 'dart:async';
import 'dart:math' as math;

import 'package:lopicode/blocks/block_canvas_layout.dart';
import 'package:lopicode/blocks/block_canvas_view.dart';
import 'package:lopicode/blocks/block_colors.dart';
import 'package:lopicode/blocks/block_drag.dart';
import 'package:lopicode/blocks/block_editor_view.dart';
import 'package:lopicode/blocks/block_geometry.dart';
import 'package:lopicode/blocks/block_host.dart';
import 'package:lopicode/blocks/block_layout.dart';
import 'package:lopicode/blocks/block_paint_view.dart';
import 'package:lopicode/blocks/block_script_view.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:material_ui/material_ui.dart';

enum _Touch { none, pending, pan, drag, pinch, held }

/// 画布这一层：排版缓存、平移缩放、选中、把手指的动作分成“点 / 长按 / 拖积木 / 平移 / 缩放”。
mixin BkEditorCanvas on State<BlockEditorView>, BkKitHolder<BlockEditorView>, TickerProvider {
  static const double minZoom = 0.5, maxZoom = 2.0;

  /// 手指移动多远算“拖”而不是“点”。
  static const double dragSlop = 8;
  static const Duration longPressAfter = Duration(milliseconds: 450);

  BlockHost get host => widget.host;

  final GlobalKey viewKey = GlobalKey(debugLabel: 'bk-editor-view');

  /// 画布上的点 × [zoom] + [pan] ＝ 编辑区里的点。
  Offset pan = Offset.zero;
  double zoom = 1;
  Size viewSize = Size.zero;

  BlockLayoutEngine? _engine;
  BkCanvasLayout? _layout;
  int _layoutRev = -1;
  List<BlockIssue> issues = const [];
  BlockSelection? selection;

  late final AnimationController flashAnim = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  final Map<int, Offset> _pointers = {};
  _Touch _touch = _Touch.none;
  int _primary = -1;
  Offset _downAt = Offset.zero;
  ({BkPlaced script, BkHit hit})? _downHit;
  Timer? _longPress;
  double _pinchDist = 1, _pinchZoom = 1;

  /// 手指按下的地方（画布坐标）。
  Offset get downCanvas => toCanvas(_downAt);

  // —— 别的几层提供的 ——

  BkDragSession? get drag;
  bool get busy;
  void dragStartFromCanvas(BkPlaced script, BkHit hit, Offset viewAt);
  void dragMove(Offset viewAt);
  void dragEnd();
  void dragCancel();
  void onTapHit(BkPlaced script, BkHit hit);
  void onLongPressHit(BkPlaced script, BkHit hit);

  BlockLayoutEngine get engine => _engine ??= kit.engine(host);

  @override
  void kitChanged() {
    _engine = null;
    _layout = null;
  }

  /// 现在的排布（没在拖的时候的样子）。
  BkCanvasLayout get layout {
    if (_layout == null || _layoutRev != host.revision) {
      _layout = layoutBlockCanvas(host, engine);
      _layoutRev = host.revision;
      issues = host.issues;
      final sel = selection;
      if (sel != null && _layout!.placed(sel.scriptId)?.layout.blockAt(sel.path) == null) selection = null;
    }
    return _layout!;
  }

  void dropLayout() {
    _engine = null;
    _layout = null;
  }

  Offset toCanvas(Offset view) => (view - pan) / zoom;
  Offset toView(Offset canvas) => canvas * zoom + pan;
  Rect rectToView(Rect canvas) => Rect.fromPoints(toView(canvas.topLeft), toView(canvas.bottomRight));

  /// 屏幕上的点换成编辑区里的点。
  Offset viewOf(Offset global) {
    final box = viewKey.currentContext?.findRenderObject();
    return box is RenderBox ? box.globalToLocal(global) : global;
  }

  Offset globalOf(Offset view) {
    final box = viewKey.currentContext?.findRenderObject();
    return box is RenderBox ? box.localToGlobal(view) : view;
  }

  /// 底下被积木盒盖住多高（画布露出来的部分＝上面这一段）。
  double get coveredBottom;

  void setPan(Offset next) {
    final ext = (drag?.display ?? layout).extent * zoom;
    const keep = 72.0;
    final w = viewSize.width, h = math.max(keep * 2, viewSize.height - coveredBottom);
    pan = Offset(next.dx.clamp(math.min(keep - ext.width, 0), math.max(w - keep, 0)).toDouble(), next.dy.clamp(math.min(keep - ext.height, 0), math.max(h - keep, 0)).toDouble());
  }

  void setZoom(double next, Offset focalView) {
    final z = next.clamp(minZoom, maxZoom).toDouble();
    final at = toCanvas(focalView);
    zoom = z;
    setPan(focalView - at * z);
  }

  void select(BlockSelection? s) {
    if (s == null ? selection == null : s.same(selection)) return;
    setState(() => selection = s);
  }

  /// 跳到某块积木：选中、挪到看得见的地方、闪一下。
  void jumpTo(String scriptId, LcBlockPath path) {
    final placed = layout.placed(scriptId);
    final block = placed?.layout.blockAt(path) ?? placed?.layout.hat;
    if (placed == null || block == null) return;
    final rect = rectToView(block.rect.shift(placed.origin));
    final h = viewSize.height - coveredBottom;
    setState(() {
      selection = BlockSelection(scriptId, block.isHat ? const [] : block.path);
      if (rect.top < 56 || rect.bottom > h - 16 || rect.left < 0 || rect.left > viewSize.width - 80) {
        setPan(pan + Offset(16 - rect.left, math.max(64, h * 0.3) - rect.top));
      }
    });
    unawaited(flashAnim.forward(from: 0));
  }

  // —— 手指 ——

  void _clearLongPress() {
    _longPress?.cancel();
    _longPress = null;
  }

  void pointerDown(PointerDownEvent e) {
    if (busy) return;
    final at = viewOf(e.position);
    _pointers[e.pointer] = at;
    if (_pointers.length >= 2) {
      _clearLongPress();
      if (_touch == _Touch.drag) return; // 拖着积木时第二根手指不管。
      final ps = _pointers.values.toList();
      _pinchDist = math.max(1, (ps[0] - ps[1]).distance);
      _pinchZoom = zoom;
      _touch = _Touch.pinch;
      return;
    }
    _primary = e.pointer;
    _downAt = at;
    _downHit = layout.hitTest(toCanvas(at));
    _touch = _Touch.pending;
    _clearLongPress();
    if (_downHit != null) {
      _longPress = Timer(longPressAfter, () {
        final hit = _downHit;
        if (!mounted || _touch != _Touch.pending || hit == null) return;
        _touch = _Touch.held;
        onLongPressHit(hit.script, hit.hit);
      });
    }
  }

  void pointerMove(PointerMoveEvent e) {
    final before = _pointers[e.pointer];
    if (before == null) return;
    final at = viewOf(e.position);
    _pointers[e.pointer] = at;
    switch (_touch) {
      case _Touch.pending:
        if (e.pointer != _primary || (at - _downAt).distance < dragSlop) return;
        _clearLongPress();
        final hit = _downHit;
        if (hit != null) {
          _touch = _Touch.drag;
          dragStartFromCanvas(hit.script, hit.hit, _downAt);
          if (drag == null) {
            _touch = _Touch.pan;
          } else {
            dragMove(at);
          }
        } else {
          _touch = _Touch.pan;
          setState(() => setPan(pan + (at - _downAt)));
        }
      case _Touch.pan:
        if (e.pointer == _primary) setState(() => setPan(pan + (at - before)));
      case _Touch.drag:
        if (e.pointer == _primary) dragMove(at);
      case _Touch.pinch:
        final ps = _pointers.values.toList();
        if (ps.length < 2) return;
        final focal = (ps[0] + ps[1]) / 2;
        final moved = at - before;
        setState(() {
          setPan(pan + moved / 2);
          setZoom(_pinchZoom * (ps[0] - ps[1]).distance / _pinchDist, focal);
        });
      case _Touch.none || _Touch.held:
        break;
    }
  }

  void pointerUp(PointerEvent e) {
    if (_pointers.remove(e.pointer) == null) return;
    _clearLongPress();
    final cancelled = e is PointerCancelEvent;
    switch (_touch) {
      case _Touch.pending:
        final hit = _downHit;
        _touch = _Touch.none;
        if (cancelled) return;
        if (hit == null) {
          select(null);
        } else {
          onTapHit(hit.script, hit.hit);
        }
      case _Touch.drag:
        if (e.pointer != _primary) return;
        _touch = _Touch.none;
        cancelled ? dragCancel() : dragEnd();
      case _Touch.pinch:
        // 松开一根：剩下那根接着平移。
        if (_pointers.length == 1) {
          _primary = _pointers.keys.first;
          _touch = _Touch.pan;
        } else if (_pointers.isEmpty) {
          _touch = _Touch.none;
        }
      case _Touch.pan || _Touch.held || _Touch.none:
        if (_pointers.isEmpty) _touch = _Touch.none;
    }
  }

  void disposeCanvas() {
    _clearLongPress();
    flashAnim.dispose();
  }

  /// 画布本体。`shown`＝现在该画的排布（拖动时是预览）。
  Widget buildCanvas(BuildContext context) {
    final d = drag;
    final shown = d?.display ?? layout;
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: pointerDown,
      onPointerMove: pointerMove,
      onPointerUp: pointerUp,
      onPointerCancel: pointerUp,
      child: AnimatedBuilder(
        animation: flashAnim,
        builder: (context, _) => CustomPaint(
          key: const ValueKey('bk-canvas'),
          size: Size.infinite,
          painter: BkWorkspacePainter(
            layout: shown,
            kit: kit,
            pan: pan,
            zoom: zoom,
            selection: d == null ? selection : null,
            issues: d == null ? issues : const [],
            flash: flashAnim.isAnimating ? 1 - Curves.easeOut.transform(flashAnim.value) : 0,
            ghost: d?.ghost,
            slot: d == null || d.kind != BkDragKind.expr || d.target == null
                ? null
                : (scriptId: d.target!.scriptId, block: d.target!.snap.parent, arg: d.target!.snap.arg ?? '', path: d.target!.snap.exprPath, warn: d.target!.mismatch),
          ),
        ),
      ),
    );
  }
}

class BkWorkspacePainter extends CustomPainter {
  BkWorkspacePainter({required this.layout, required this.kit, required this.pan, required this.zoom, this.selection, this.issues = const [], this.flash = 0, this.ghost, this.slot});

  final BkCanvasLayout layout;
  final BkKit kit;
  final Offset pan;
  final double zoom;
  final BlockSelection? selection;
  final List<BlockIssue> issues;
  final double flash;
  final ({String scriptId, LcBlockPath parent, bool inElse, int start, int count})? ghost;
  final ({String scriptId, LcBlockPath block, String arg, BkExprPath path, bool warn})? slot;

  @override
  void paint(Canvas canvas, Size size) {
    final palette = kit.palette;
    canvas.drawRect(Offset.zero & size, Paint()..color = palette.canvas);
    _dots(canvas, size, palette);
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.translate(pan.dx, pan.dy);
    canvas.scale(zoom);
    final visible = Rect.fromLTWH(-pan.dx / zoom, -pan.dy / zoom, size.width / zoom, size.height / zoom).inflate(24);
    for (final s in layout.scripts) {
      if (!s.bounds.overlaps(visible)) continue;
      final sel = selection != null && selection!.scriptId == s.id ? selection : null;
      final g = ghost != null && ghost!.scriptId == s.id ? ghost : null;
      final sl = slot != null && slot!.scriptId == s.id ? slot : null;
      final state = BkPaintState(
        selected: sel != null && sel.path.isNotEmpty ? sel.path : null,
        selectedHat: sel != null && sel.path.isEmpty,
        flash: sel == null ? 0 : flash,
        ghostRange: g == null ? null : (parent: g.parent, inElse: g.inElse, start: g.start, count: g.count),
        selectedSlot: sl == null ? null : (block: sl.block, arg: sl.arg, path: sl.path),
        slotColor: sl != null && sl.warn ? palette.warning : null,
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
    canvas.restore();
  }

  void _dots(Canvas canvas, Size size, BkPalette palette) {
    final step = 24.0 * zoom;
    if (step < 8) return;
    final paint = Paint()..color = palette.canvasDot;
    final r = math.max(0.8, 1.1 * zoom);
    for (var y = pan.dy % step; y < size.height; y += step) {
      for (var x = pan.dx % step; x < size.width; x += step) {
        canvas.drawCircle(Offset(x, y), r, paint);
      }
    }
  }

  @override
  bool shouldRepaint(BkWorkspacePainter old) => true;
}
