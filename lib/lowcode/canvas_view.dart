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
import 'package:lopicode/lowcode/canvas_dropbox.dart';
import 'package:lopicode/lowcode/canvas_overlay_widgets.dart';
import 'package:lopicode/lowcode/canvas_render_widgets.dart';
import 'package:lopicode/lowcode/canvas_viewport.dart';
import 'package:lopicode/lowcode/editor_drag.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/palette_widgets.dart';
import 'package:lopicode/lowcode/slots.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/app_backdrop.dart';
import 'package:material_ui/material_ui.dart';

export 'package:lopicode/lowcode/canvas_viewport.dart';

part 'canvas_drag_view.dart';

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
    this.overlayId,
    this.statePreview,
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

  /// “只看这个弹层”的那个弹窗；正在预览的状态样式（见 CanvasPage 同名的两项）。
  final String? overlayId;
  final ({String nodeId, String state})? statePreview;

  @override
  State<CanvasView> createState() => CanvasViewState();
}

class CanvasViewState extends State<CanvasView> with SingleTickerProviderStateMixin, _CanvasDragging {
  /// 缩放和位置：平移 / 缩放只改它，只有最外面那层变换跟着重画（页面不重搭）。
  final ValueNotifier<CanvasViewport> _view = ValueNotifier(const CanvasViewport(1, Offset.zero));
  @override
  Size _viewport = Size.zero;
  Size _pageSize = Size.zero;

  /// 此刻的缩放和位置。平常和 [_view] 里的一样；正在搭界面时改的（[_place] 的 quiet）先只记在这里，这一帧画完再补通知。
  CanvasViewport _vp = const CanvasViewport(1, Offset.zero);
  bool _syncQueued = false;

  @override
  double get _scale => _vp.scale;
  @override
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
  @override
  double get _room => (_viewport.height - widget.topInset - widget.bottomInset).clamp(0.0, double.infinity).toDouble();

  /// 页面此刻在可视区里占的那一块（屏幕像素；测试用）。
  Rect get pageRect => _offset & (_pageSize * _scale);

  final Map<String, GlobalKey> _keys = {};
  final ValueNotifier<CanvasSelection?> _selection = ValueNotifier(null);

  // 缩放 / 平移手势开始时的状态
  double _gestureScale = 1;
  Offset _gesturePagePoint = Offset.zero;

  // 松手后的惯性滑动
  @override
  late final Ticker _ticker = createTicker(_onFlingTick);
  FrictionSimulation? _flingX, _flingY;

  // 拖柄改尺寸
  CanvasResizePreview? _preview;
  ({String id, int hx, int hy, Offset start, double width, double height})? _resize;

  /// 当前缩放比例（1＝100%）。
  double get scale => _scale;

  /// 缩放 / 位置变了会通知（外面要显示比例时订阅它）。
  ValueListenable<CanvasViewport> get view => _view;

  /// 当前页面宽度（屏幕像素 ÷ 缩放之前的）。
  double get pageWidth => widget.presetWidth == 0 ? _viewport.width : widget.presetWidth.toDouble();

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
  @override
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

  @override
  RenderBox? get _pageBox {
    final box = _keys[widget.doc.root.id]?.currentContext?.findRenderObject();
    return box is RenderBox && box.hasSize ? box : null;
  }

  /// 一个组件的边框盒在页面上的位置（页面坐标）；还没排出来就是 null。
  @override
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
    // 旁边别的组件占的地方：尺寸标签放到框外面时避开它们
    final avoid = [
      for (final id in _keys.keys)
        if (_rectOf(id, pageBox) case final box? when sizeLabelAvoids(doc, node.id, rect, id, box)) box,
    ];
    _selection.value = CanvasSelection.of(node, parent, rect, base: base, page: _pageSize, avoid: avoid);
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
      _keys.removeWhere((id, _) => !alive.contains(lcSplitSlotId(id).$1));
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
              overlayId: widget.overlayId,
              statePreview: widget.statePreview,
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
