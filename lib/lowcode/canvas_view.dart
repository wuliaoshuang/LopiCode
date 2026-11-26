// 设计约束（低代码 · 画布 · 390×844）
// - 整块都是画布（沉浸式）：灰底从屏幕最顶铺起，上面放一块“页面”；页面的顶边起始时正好在悬浮顶栏的下沿（topInset），
//   往上滚时页面从顶栏按钮下面滑过去。画布上不再浮着任何小工具条（第 5 版第 1 期）：屏宽档、间距示意、缩放都由外面的搭建台（editor_workbench_widgets.dart）放进顶栏小字和“⋮”菜单，这里只提供方法。
// - 手势分工——
//     点一下＝选中（点空白处＝取消选中）；单指拖＝平移 / 上下滚动；双指＝缩放（25%–300%）；
//     长按组件 280 毫秒＝拿起来拖（和积木画布一个手感，见 lift_gesture_widgets.dart）；按住选中框上的拖柄拖＝改宽高。
// - 页面比可视区小的方向不许拖走（横向居中、纵向贴顶），大的方向拖到边就停：不会把页面拖丢。
// - 选中框、拖柄、间距示意、拖动时的蓝线都叠在页面上面画，不改页面本身的排版——拖动时页面一个像素都不动。
// - 性能：平移 / 缩放只换最外面那层变换（_view），不重搭页面；每次重搭只扫一遍组件树清测量表。
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';
import 'package:lopicode/backdrop/backdrop_model.dart';
import 'package:lopicode/lowcode/canvas_css.dart';
import 'package:lopicode/lowcode/canvas_drag_widgets.dart';
import 'package:lopicode/lowcode/canvas_overlay_widgets.dart';
import 'package:lopicode/lowcode/canvas_render_widgets.dart';
import 'package:lopicode/lowcode/canvas_viewport.dart';
import 'package:lopicode/lowcode/component_ops.dart';
import 'package:lopicode/lowcode/editor_drag.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/palette_widgets.dart';
import 'package:lopicode/lowcode/style_resolve.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/app_backdrop.dart';
import 'package:material_ui/material_ui.dart';

export 'package:lopicode/lowcode/canvas_viewport.dart';

class CanvasView extends StatefulWidget {
  const CanvasView({
    super.key,
    required this.doc,
    required this.selected,
    required this.onSelect,
    required this.canDrop,
    required this.onResize,
    required this.onLift,
    required this.onLiftMove,
    required this.onLiftDrop,
    required this.onLiftCancel,
    this.presetWidth = 0,
    this.showBoxModel = true,
    this.topInset = 0,
    this.bottomInset = 0,
  });

  final LcDocument doc;
  final String? selected;
  final void Function(String? id) onSelect;

  /// 拖着的东西能不能放进这个容器。
  final bool Function(LcDrag drag, String parentId) canDrop;

  /// 拖柄松手：把新的宽 / 高（像素，取整）写进组件。哪一项是 null 就是那个方向没动。只在松手时调一次。
  final void Function(String id, int? width, int? height) onResize;

  /// 长按画布上的一个组件拿起来了 / 手指在动 / 松手 / 被打断。位置是屏幕坐标。
  /// 拖动本身由外面的搭建台管（它还要管组件盒里拖出来的、底部的删除区），画布只负责算落点（[CanvasViewState.dragMove]）。
  final void Function(LcDrag drag, Offset global) onLift;
  final void Function(Offset global) onLiftMove;
  final VoidCallback onLiftDrop;
  final VoidCallback onLiftCancel;

  /// 屏宽档：0＝自适应，其余是页面宽度（像素）。
  final int presetWidth;

  /// 选中时画不画间距示意（外边距橙色、内边距绿色）。
  final bool showBoxModel;

  /// 画布最上面被悬浮顶栏（连同状态栏）盖住多高：页面的顶边从这下面开始，定位和缩放中心也让开它。
  final double topInset;

  /// 画布最下面被别的东西（收起来的组件盒手柄）盖住多高：页面滚到底时底边停在它上面。
  final double bottomInset;

  @override
  State<CanvasView> createState() => CanvasViewState();
}

class CanvasViewState extends State<CanvasView> with SingleTickerProviderStateMixin {
  /// 缩放和位置：平移 / 缩放只改它，只有最外面那层变换跟着重画（页面不重搭）。
  final ValueNotifier<CanvasViewport> _view = ValueNotifier(const CanvasViewport(1, Offset.zero));
  Size _viewport = Size.zero;
  Size _pageSize = Size.zero;

  /// 此刻的缩放和位置。平常和 [_view] 里的一样；正在搭界面时改的（[_place] 的 quiet）先只记在这里，这一帧画完再补通知。
  CanvasViewport _vp = const CanvasViewport(1, Offset.zero);
  bool _syncQueued = false;

  double get _scale => _vp.scale;
  Offset get _offset => _vp.offset;

  /// 换位置。[quiet]：现在正在搭界面 / 排版（不许通知），画布自己马上会按新位置重画，通知留到这一帧结束。
  void _place(CanvasViewport v, {bool quiet = false}) {
    _vp = v;
    if (!quiet) {
      _view.value = v;
    } else if (!_syncQueued && _view.value != v) {
      _syncQueued = true;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _syncQueued = false;
        if (mounted) _view.value = _vp;
      });
    }
  }

  /// 露出来的那一段（悬浮顶栏下沿到底部遮挡的上沿）多高。
  double get _room => (_viewport.height - widget.topInset - widget.bottomInset).clamp(0.0, double.infinity).toDouble();

  /// 页面此刻在可视区里占的那一块（屏幕像素；测试用）。
  Rect get pageRect => _offset & (_pageSize * _scale);

  final Map<String, GlobalKey> _keys = {};
  final ValueNotifier<CanvasSelection?> _selection = ValueNotifier(null);

  // 缩放 / 平移手势开始时的状态
  double _gestureScale = 1;
  Offset _gesturePagePoint = Offset.zero;

  // 松手后的惯性滑动
  late final Ticker _ticker = createTicker(_onFlingTick);
  FrictionSimulation? _flingX, _flingY;

  // 拖柄改尺寸
  CanvasResizePreview? _preview;
  ({String id, int hx, int hy, Offset start, double width, double height})? _resize;

  // 拖组件：量好的盒子、手指位置、停够了的容器、落点
  ({LcDrag drag, DropBox root})? _drag;
  Offset? _dragAt;
  final Map<String, Timer> _dwell = {};
  final Set<String> _armed = {};
  final ValueNotifier<DropTarget?> _target = ValueNotifier(null);

  /// 手指在页面里的横向位置：落点标签要躲着它（见 canvas_drag_widgets.dart）。
  final ValueNotifier<double?> _fingerX = ValueNotifier(null);
  Timer? _autoScroll;

  /// 当前缩放比例（1＝100%）。
  double get scale => _scale;

  /// 缩放 / 位置变了会通知（外面要显示比例时订阅它）。
  ValueListenable<CanvasViewport> get view => _view;

  /// 当前页面宽度（屏幕像素 ÷ 缩放之前的）。
  double get pageWidth => widget.presetWidth == 0 ? _viewport.width : widget.presetWidth.toDouble();

  /// 拖动中算出来的落点（测试用）。
  DropTarget? get dropTarget => _target.value;

  @override
  void didUpdateWidget(CanvasView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 顶栏那一段变高 / 变矮了（比如状态栏高度变了）：页面跟着挪，不被盖住。
    if (oldWidget.topInset != widget.topInset) {
      _place(CanvasViewport(_scale, _clamp(_offset + Offset(0, widget.topInset - oldWidget.topInset), _scale)), quiet: true);
    } else if (oldWidget.bottomInset != widget.bottomInset) {
      _place(CanvasViewport(_scale, _clamp(_offset, _scale)), quiet: true);
    }
    // 换了屏宽档：回到“适应屏幕”。
    if (oldWidget.presetWidth != widget.presetWidth) fitToScreen(quiet: true);
  }

  @override
  void dispose() {
    _stopDrag();
    _ticker.dispose();
    _selection.dispose();
    _target.dispose();
    _fingerX.dispose();
    _view.dispose();
    super.dispose();
  }

  GlobalKey _keyFor(String id) => _keys.putIfAbsent(id, () => GlobalKey(debugLabel: 'lc-box-$id'));

  // ───────────── 缩放与平移 ─────────────

  /// 把位置收回允许的范围：页面比露出来的那一段小的方向固定（横向居中、纵向贴着悬浮顶栏的下沿），大的方向不许露出页面外面。
  Offset _clamp(Offset o, double scale) {
    // 宽度直接用设定的页面宽度（刚换预设、还没量到新尺寸时也是准的）；高度没量到之前按“正好一屏”算。
    final top = widget.topInset, room = _room;
    final w = pageWidth * scale, h = (_pageSize.height > 0 ? _pageSize.height : room) * scale;
    final x = w <= _viewport.width ? (_viewport.width - w) / 2 : o.dx.clamp(_viewport.width - w, 0.0).toDouble();
    final y = h <= room ? top : o.dy.clamp(top + room - h, top).toDouble();
    return Offset(x, y);
  }

  /// 只改 [_view]：不 setState，页面不重搭。
  void _moveTo(double scale, Offset offset, {bool quiet = false}) {
    final s = scale.clamp(kCanvasMinScale, kCanvasMaxScale).toDouble();
    _place(CanvasViewport(s, _clamp(offset, s)), quiet: quiet);
  }

  /// 缩放到指定比例；[focal] 是可视区里保持不动的那个点（不给就是正中间）。
  void zoomTo(double scale, {Offset? focal}) {
    _ticker.stop();
    final f = focal ?? Offset(_viewport.width / 2, widget.topInset + _room / 2);
    final s = scale.clamp(kCanvasMinScale, kCanvasMaxScale).toDouble();
    final pagePoint = (f - _offset) / _scale;
    _moveTo(s, f - pagePoint * s);
  }

  /// 适应屏幕：整块页面的宽度正好放进可视区（页面不比可视区宽就是 100%），回到顶部。
  void fitToScreen({bool quiet = false}) {
    _ticker.stop();
    final w = pageWidth;
    _moveTo(w > _viewport.width && w > 0 ? _viewport.width / w : 1, Offset(0, widget.topInset), quiet: quiet);
  }

  /// 放大（1）/ 缩小（-1）一档。
  void zoomStep(int dir) {
    final next = dir > 0 ? kCanvasZoomSteps.firstWhere((s) => s > _scale + 0.001, orElse: () => kCanvasMaxScale) : kCanvasZoomSteps.lastWhere((s) => s < _scale - 0.001, orElse: () => kCanvasMinScale);
    zoomTo(next);
  }

  void _onScaleStart(ScaleStartDetails d) {
    _ticker.stop();
    _gestureScale = _scale;
    _gesturePagePoint = (d.localFocalPoint - _offset) / _scale;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    // 手指按住的那个页面上的点始终跟着手指：单指时就是平移，双指时同时缩放。
    final s = (_gestureScale * d.scale).clamp(kCanvasMinScale, kCanvasMaxScale).toDouble();
    _moveTo(s, d.localFocalPoint - _gesturePagePoint * s);
  }

  void _onScaleEnd(ScaleEndDetails d) {
    final v = d.velocity.pixelsPerSecond;
    if (v.distance < 80) return;
    _flingX = FrictionSimulation(0.02, _offset.dx, v.dx);
    _flingY = FrictionSimulation(0.02, _offset.dy, v.dy);
    _ticker
      ..stop()
      ..start();
  }

  void _onFlingTick(Duration elapsed) {
    final t = elapsed.inMicroseconds / 1e6;
    final fx = _flingX, fy = _flingY;
    if (fx == null || fy == null) {
      _ticker.stop();
      return;
    }
    final target = Offset(fx.x(t), fy.x(t));
    final before = _offset;
    _moveTo(_scale, target);
    // 滑到头了，或者速度降下来了，就停。
    if ((fx.isDone(t) && fy.isDone(t)) || (_offset == before && t > 0.05)) _ticker.stop();
  }

  // ───────────── 量：页面多大、组件在哪 ─────────────

  RenderBox? get _pageBox {
    final box = _keys[widget.doc.root.id]?.currentContext?.findRenderObject();
    return box is RenderBox && box.hasSize ? box : null;
  }

  /// 一个组件的边框盒在页面上的位置（页面坐标）；还没排出来就是 null。
  Rect? _rectOf(String id, RenderBox pageBox) {
    final box = _keys[id]?.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !box.attached) return null;
    return MatrixUtils.transformRect(box.getTransformTo(pageBox), Offset.zero & box.size);
  }

  /// 每次重搭排完版以后量一次：页面多大、选中的组件在哪。量到的结果变了才通知选中层重画。
  void _measure() {
    if (!mounted) return;
    final doc = widget.doc;
    final pageBox = _pageBox;
    if (pageBox == null) return;
    if (pageBox.size != _pageSize) {
      _pageSize = pageBox.size;
      _place(CanvasViewport(_scale, _clamp(_offset, _scale)));
    }
    final id = widget.selected;
    final node = id == null ? null : doc.find(id);
    final rect = node == null || _drag != null ? null : _rectOf(node.id, pageBox);
    if (node == null || rect == null) {
      _selection.value = null;
      return;
    }
    final parent = doc.parentOf(node.id);
    final parentBox = parent == null ? null : _keys[parent.id]?.currentContext?.findRenderObject();
    final base = parentBox is RenderBox && parentBox.hasSize ? parentBox.size.width : _pageSize.width;
    final style = resolvedStyle(node, parent);
    final scale = CssScale(pageWidth: _pageSize.width, pageHeight: _pageSize.height);
    final font = scale.withFont(cssSizePx(style['font-size'], scale) ?? 16);
    _selection.value = CanvasSelection(
      nodeId: node.id,
      rect: rect,
      margin: cssEdges(style, 'margin', font, percentOf: base),
      border: cssBorderWidths(style, font),
      padding: cssEdges(style, 'padding', font, percentOf: base),
      isRoot: parent == null || node.locked,
    );
  }

  /// 一个组件此刻在屏幕上占的那一块（屏幕坐标）；量不到是 null。
  Rect? nodeScreenRect(String id) {
    final pageBox = _pageBox, self = context.findRenderObject();
    if (pageBox == null || self is! RenderBox) return null;
    final r = _rectOf(id, pageBox);
    if (r == null) return null;
    final origin = self.localToGlobal(Offset.zero);
    return Rect.fromLTWH(origin.dx + _offset.dx + r.left * _scale, origin.dy + _offset.dy + r.top * _scale, r.width * _scale, r.height * _scale);
  }

  /// 把一个组件滚到看得见的地方（刚点一下加进来的那个）。已经整个露着就不动。要在排完版以后调。
  void revealNode(String id) {
    if (!mounted) return;
    _ticker.stop();
    _measure();
    final pageBox = _pageBox;
    final r = pageBox == null ? null : _rectOf(id, pageBox);
    if (r == null) return;
    const gap = 12.0;
    final top = widget.topInset + gap, bottom = widget.topInset + _room - gap;
    final y0 = _offset.dy + r.top * _scale, y1 = _offset.dy + r.bottom * _scale;
    var dy = 0.0;
    if (y1 - y0 > bottom - top || y0 < top) {
      dy = top - y0; // 比露出来的那段还高：让它的顶边露出来
    } else if (y1 > bottom) {
      dy = bottom - y1;
    }
    final x0 = _offset.dx + r.left * _scale, x1 = _offset.dx + r.right * _scale;
    var dx = 0.0;
    if (x1 - x0 > _viewport.width - gap * 2 || x0 < gap) {
      dx = gap - x0;
    } else if (x1 > _viewport.width - gap) {
      dx = _viewport.width - gap - x1;
    }
    if (dx != 0 || dy != 0) _moveTo(_scale, _offset + Offset(dx, dy));
  }

  // ───────────── 拖柄 ─────────────

  void _resizeStart(String handle, Offset global) {
    final sel = _selection.value;
    final dir = kCanvasHandles[handle];
    if (sel == null || dir == null) return;
    _resize = (id: sel.nodeId, hx: dir.$1, hy: dir.$2, start: global, width: sel.rect.width, height: sel.rect.height);
  }

  void _resizeUpdate(Offset global) {
    final r = _resize;
    if (r == null) return;
    // 手指在屏幕上移了多少，换算回页面上的像素。
    final d = (global - r.start) / _scale;
    final next = resizeByHandle(startWidth: r.width, startHeight: r.height, dx: d.dx, dy: d.dy, hx: r.hx, hy: r.hy);
    setState(() => _preview = CanvasResizePreview(r.id, next.width, next.height));
  }

  void _resizeEnd({required bool cancelled}) {
    final r = _resize, p = _preview;
    _resize = null;
    if (p == null) return;
    setState(() => _preview = null);
    if (cancelled || r == null) return;
    // 没真的变（只是碰了一下）就不写，免得平白多一条撤销记录。
    final width = p.width == r.width.round() ? null : p.width, height = p.height == r.height.round() ? null : p.height;
    if (width != null || height != null) widget.onResize(r.id, width, height);
  }

  // ───────────── 拖组件：算落点、边缘自动滚 ─────────────

  DropBox? _boxOf(LcNode node, LcNode? parent, RenderBox pageBox) {
    final rect = _rectOf(node.id, pageBox);
    if (rect == null) return null;
    final instance = node.type == 'component';
    final container = node.isContainer && !instance;
    final flow = container ? cssFlow(resolvedStyle(node, parent), rowByDefault: node.type == 'row') : null;
    return DropBox(
      id: node.id,
      label: instance ? componentLabel(widget.doc, node) : node.spec.label,
      rect: rect,
      container: container,
      row: flow?.row ?? false,
      reverse: flow?.reverse ?? false,
      children: container ? [for (final c in node.children) ?_boxOf(c, node, pageBox)] : const [],
    );
  }

  /// 在拖柄上点了一下（没拖）：当成点在它下面的组件上——拖柄能按的范围比看到的大，不能把旁边的小组件挡得点不着。
  void _tapThrough(Offset global) {
    final self = context.findRenderObject(), pageBox = _pageBox;
    final root = pageBox == null ? null : _boxOf(widget.doc.root, null, pageBox);
    if (root == null || self is! RenderBox) return;
    final point = (self.globalToLocal(global) - _offset) / _scale;
    widget.onSelect(root.rect.contains(point) ? dropChain(root, point).last.id : null);
  }

  /// 开始拖：把所有组件的位置量下来（拖动中排版不变，量一次就够）。量不到（页面还没排出来）返回 false。
  bool beginDrag(LcDrag drag) {
    _stopDrag();
    _ticker.stop();
    final pageBox = _pageBox;
    final root = pageBox == null ? null : _boxOf(widget.doc.root, null, pageBox);
    if (root == null) return false;
    setState(() => _drag = (drag: drag, root: root));
    _autoScroll = Timer.periodic(const Duration(milliseconds: 16), (_) => _autoScrollTick());
    return true;
  }

  /// 手指到了 [global]（屏幕坐标）：重新算落点。返回现在的落点。
  DropTarget? dragMove(Offset global) {
    final self = context.findRenderObject();
    if (_drag == null || self is! RenderBox) return null;
    _dragAt = self.globalToLocal(global);
    _fingerX.value = (_dragAt!.dx - _offset.dx) / _scale;
    return _retarget();
  }

  /// 手指离开画布了（比如移到底部的删除区上）：不要落点了。
  void dragAway() {
    _dragAt = null;
    _retarget();
  }

  DropTarget? _retarget() {
    final drag = _drag, at = _dragAt;
    if (drag == null) return null;
    if (at == null || at.dy < 0 || at.dy > _viewport.height) {
      _setHover(const []);
      return _target.value = null;
    }
    final point = (at - _offset) / _scale;
    final moving = drag.drag.nodeId;
    bool can(String id) => widget.canDrop(drag.drag, id);
    // 手指下面除了页面以外的容器：各自开始计时，停够了才算“要放进去”。
    final chain = dropChain(drag.root, point);
    final cut = moving == null ? -1 : chain.indexWhere((b) => b.id == moving);
    _setHover([
      for (final b in (cut < 0 ? chain : chain.sublist(0, cut)).skip(1))
        if (b.container && b.children.isNotEmpty && can(b.id)) b.id,
    ]);
    return _target.value = pickDropTarget(drag.root, point, armed: _armed, canDrop: can, movingId: moving);
  }

  void _setHover(List<String> ids) {
    for (final id in _dwell.keys.toList()) {
      if (!ids.contains(id)) _dwell.remove(id)?.cancel();
    }
    _armed.removeWhere((id) => !ids.contains(id));
    for (final id in ids) {
      if (_armed.contains(id) || _dwell.containsKey(id)) continue;
      _dwell[id] = Timer(kDropDwell, () {
        _dwell.remove(id);
        _armed.add(id);
        if (mounted) _retarget();
      });
    }
  }

  void _autoScrollTick() {
    final at = _dragAt;
    if (!mounted || _drag == null || at == null) return;
    final vy = autoScrollSpeed(at.dy, widget.topInset, widget.topInset + _room);
    final vx = autoScrollSpeed(at.dx, 0, _viewport.width);
    if (vx == 0 && vy == 0) return;
    final before = _offset;
    // 往下滚＝页面往上走。
    _moveTo(_scale, _offset - Offset(vx, vy) * 0.016);
    if (_offset != before) _retarget();
  }

  void _stopDrag() {
    _autoScroll?.cancel();
    _autoScroll = null;
    for (final t in _dwell.values) {
      t.cancel();
    }
    _dwell.clear();
    _armed.clear();
    _dragAt = null;
  }

  /// 拖动结束（松手 / 取消）：返回最后的落点，并把拖动时的东西都收起来。
  DropTarget? finishDrag() {
    final target = _target.value;
    _stopDrag();
    _target.value = null;
    if (_drag != null && mounted) setState(() => _drag = null);
    return target;
  }

  // ───────────── 界面 ─────────────

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // 清掉已经不在的组件的测量 key：先把现有的 id 收成一个集合（一遍扫完），不要每个 key 都去树里找一次。
    if (_keys.isNotEmpty) {
      final alive = <String>{};
      void walk(LcNode n) {
        alive.add(n.id);
        n.children.forEach(walk);
      }

      walk(widget.doc.root);
      _keys.removeWhere((id, _) => !alive.contains(id));
    }
    SchedulerBinding.instance.addPostFrameCallback((_) => _measure());
    return LayoutBuilder(
      builder: (context, box) {
        final viewport = box.biggest;
        if (viewport != _viewport) {
          // 第一次量到大小：页面的顶边放在悬浮顶栏的下沿。
          final first = _viewport == Size.zero;
          _viewport = viewport;
          _place(CanvasViewport(_scale, _clamp(first ? Offset(0, widget.topInset) : _offset, _scale)), quiet: true);
        }
        // 页面和叠在上面的几层：平移 / 缩放时这一整块原样复用，不重搭。
        final content = Stack(
          clipBehavior: Clip.none,
          children: [
            CanvasPage(
              doc: widget.doc,
              pageWidth: pageWidth,
              minHeight: _room,
              selected: widget.selected,
              movingId: _drag?.drag.nodeId,
              onSelect: widget.onSelect,
              onLift: widget.onLift,
              onLiftMove: widget.onLiftMove,
              onLiftDrop: widget.onLiftDrop,
              onLiftCancel: widget.onLiftCancel,
              boxKey: _keyFor,
              preview: _preview,
            ),
            Positioned.fill(
              child: ListenableBuilder(
                listenable: Listenable.merge([_selection, _view]),
                builder: (context, _) {
                  final sel = _selection.value;
                  return sel == null
                      ? const SizedBox.shrink()
                      : CanvasSelectionOverlay(
                          selection: sel,
                          scale: _scale,
                          // 屏幕上看得见的那一块（页面坐标）：尺寸标签不许跑到它外面
                          visible: Rect.fromLTWH(-_offset.dx / _scale, (widget.topInset - _offset.dy) / _scale, _viewport.width / _scale, _room / _scale),
                          showBoxModel: widget.showBoxModel,
                          onResizeStart: _resizeStart,
                          onResizeUpdate: _resizeUpdate,
                          onResizeEnd: _resizeEnd,
                          onTapThrough: _tapThrough,
                        );
                },
              ),
            ),
            Positioned.fill(
              child: ListenableBuilder(
                listenable: Listenable.merge([_target, _view, _fingerX]),
                builder: (context, _) {
                  final target = _target.value;
                  return target == null ? const SizedBox.shrink() : CanvasDropOverlay(target: target, scale: _scale, fingerX: _fingerX.value);
                },
              ),
            ),
          ],
        );
        return ClipRect(
          child: ColoredBox(
            color: BackdropScope.surface(context, c.surfaceMuted, seeThrough: BackdropArea.lowcode),
            child: GestureDetector(
              key: const ValueKey('lowcode-canvas'),
              behavior: HitTestBehavior.opaque,
              onTap: () => widget.onSelect(null),
              onScaleStart: _onScaleStart,
              onScaleUpdate: _onScaleUpdate,
              onScaleEnd: _onScaleEnd,
              child: OverflowBox(
                alignment: Alignment.topLeft,
                minWidth: 0,
                maxWidth: double.infinity,
                minHeight: 0,
                maxHeight: double.infinity,
                child: ListenableBuilder(
                  listenable: _view,
                  child: content,
                  builder: (context, child) => Transform(
                    transform: Matrix4.identity()
                      ..translateByDouble(_offset.dx, _offset.dy, 0, 1)
                      ..scaleByDouble(_scale, _scale, 1, 1),
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
