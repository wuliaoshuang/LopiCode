// 设计约束（低代码 · 画布 · 390×844）
// - 最上面一行小工具条，只管“怎么看”：页面宽度（自适应 / 360 / 390 / 768）在左；间距示意开关、缩小、比例、放大、适应屏幕在右。
// - 下面是画布：灰底上放一块“页面”。手势分工——
//     点一下＝选中（点空白处＝取消选中）；单指拖＝平移 / 上下滚动；双指＝缩放（25%–300%）；
//     长按组件＝拖动重排；按住选中框上的拖柄拖＝改宽高。
// - 页面比可视区小的方向不许拖走（横向居中、纵向贴顶），大的方向拖到边就停：不会把页面拖丢。
// - 选中框、拖柄、间距示意叠在页面上面画（canvas_overlay_widgets.dart），不改页面本身的排版。
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';
import 'package:lopicode/lowcode/canvas_css.dart';
import 'package:lopicode/lowcode/canvas_overlay_widgets.dart';
import 'package:lopicode/lowcode/canvas_render_widgets.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/palette_widgets.dart';
import 'package:lopicode/lowcode/style_resolve.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

const double kCanvasMinScale = 0.25;
const double kCanvasMaxScale = 3;
const List<double> _zoomSteps = [0.25, 0.5, 0.75, 1, 1.5, 2, 3];

/// 页面宽度的预设；0＝自适应（跟可视区一样宽）。
const List<int> kCanvasWidthPresets = [0, 360, 390, 768];

class CanvasView extends StatefulWidget {
  const CanvasView({
    super.key,
    required this.doc,
    required this.selected,
    required this.dragging,
    required this.onSelect,
    required this.onDrop,
    required this.canDrop,
    required this.onDragging,
    required this.onResize,
  });

  final LcDocument doc;
  final String? selected;

  /// 正在拖组件（从组件栏拖新的，或长按画布上的重排）：这时显示插入位、收起选中层。
  final bool dragging;
  final void Function(String? id) onSelect;
  final void Function(LcDrag drag, String parentId, int index) onDrop;
  final bool Function(LcDrag drag, String parentId) canDrop;
  final void Function(bool) onDragging;

  /// 拖柄松手：把新的宽 / 高（像素，取整）写进组件。哪一项是 null 就是那个方向没动。只在松手时调一次。
  final void Function(String id, int? width, int? height) onResize;

  @override
  State<CanvasView> createState() => CanvasViewState();
}

class CanvasViewState extends State<CanvasView> with SingleTickerProviderStateMixin {
  double _scale = 1;

  /// 页面左上角在可视区里的位置（屏幕像素）。
  Offset _offset = Offset.zero;
  int _presetWidth = 0;
  bool _showBoxModel = true;
  Size _viewport = Size.zero;
  Size _pageSize = Size.zero;

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

  /// 当前缩放比例（1＝100%）。
  double get scale => _scale;

  /// 当前页面宽度（屏幕像素 ÷ 缩放之前的）。
  double get pageWidth => _presetWidth == 0 ? _viewport.width : _presetWidth.toDouble();

  @override
  void dispose() {
    _ticker.dispose();
    _selection.dispose();
    super.dispose();
  }

  GlobalKey _keyFor(String id) => _keys.putIfAbsent(id, () => GlobalKey(debugLabel: 'lc-box-$id'));

  // ───────────── 缩放与平移 ─────────────

  /// 把位置收回允许的范围：页面比可视区小的方向固定（横向居中、纵向贴顶），大的方向不许露出页面外面。
  Offset _clamp(Offset o, double scale) {
    // 宽度直接用设定的页面宽度（刚换预设、还没量到新尺寸时也是准的）；高度没量到之前按“正好一屏”算。
    final w = pageWidth * scale, h = (_pageSize.height > 0 ? _pageSize.height : _viewport.height) * scale;
    final x = w <= _viewport.width ? (_viewport.width - w) / 2 : o.dx.clamp(_viewport.width - w, 0.0).toDouble();
    final y = h <= _viewport.height ? 0.0 : o.dy.clamp(_viewport.height - h, 0.0).toDouble();
    return Offset(x, y);
  }

  void _moveTo(double scale, Offset offset) {
    final s = scale.clamp(kCanvasMinScale, kCanvasMaxScale).toDouble();
    final o = _clamp(offset, s);
    if (s == _scale && o == _offset) return;
    setState(() {
      _scale = s;
      _offset = o;
    });
  }

  /// 缩放到指定比例；[focal] 是可视区里保持不动的那个点（不给就是正中间）。
  void zoomTo(double scale, {Offset? focal}) {
    _ticker.stop();
    final f = focal ?? _viewport.center(Offset.zero);
    final s = scale.clamp(kCanvasMinScale, kCanvasMaxScale).toDouble();
    final pagePoint = (f - _offset) / _scale;
    _moveTo(s, f - pagePoint * s);
  }

  /// 适应屏幕：整块页面的宽度正好放进可视区（页面不比可视区宽就是 100%），回到顶部。
  void fitToScreen() {
    _ticker.stop();
    final w = pageWidth;
    _moveTo(w > _viewport.width && w > 0 ? _viewport.width / w : 1, Offset.zero);
  }

  void _zoomStep(int dir) {
    final next = dir > 0 ? _zoomSteps.firstWhere((s) => s > _scale + 0.001, orElse: () => kCanvasMaxScale) : _zoomSteps.lastWhere((s) => s < _scale - 0.001, orElse: () => kCanvasMinScale);
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

  // ───────────── 量选中的组件 ─────────────

  /// 每帧排完版以后量一次：页面多大、选中的组件在哪。量到的结果变了才通知选中层重画。
  void _measure() {
    if (!mounted) return;
    final doc = widget.doc;
    final pageBox = _keys[doc.root.id]?.currentContext?.findRenderObject();
    if (pageBox is! RenderBox || !pageBox.hasSize) return;
    if (pageBox.size != _pageSize) {
      _pageSize = pageBox.size;
      final o = _clamp(_offset, _scale);
      if (o != _offset) setState(() => _offset = o);
    }
    final id = widget.selected;
    final node = id == null ? null : doc.find(id);
    final box = id == null ? null : _keys[id]?.currentContext?.findRenderObject();
    if (node == null || widget.dragging || box is! RenderBox || !box.hasSize || !box.attached) {
      _selection.value = null;
      return;
    }
    final rect = MatrixUtils.transformRect(box.getTransformTo(pageBox), Offset.zero & box.size);
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
      isRoot: parent == null,
    );
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
    _keys.removeWhere((id, _) => widget.doc.find(id) == null);
    SchedulerBinding.instance.addPostFrameCallback((_) => _measure());
    return Column(
      children: [
        _toolbar(context),
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) {
              final viewport = box.biggest;
              if (viewport != _viewport) {
                _viewport = viewport;
                _offset = _clamp(_offset, _scale);
              }
              return ClipRect(
                child: ColoredBox(
                  color: c.surfaceMuted,
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
                      child: Transform(
                        transform: Matrix4.identity()
                          ..translateByDouble(_offset.dx, _offset.dy, 0, 1)
                          ..scaleByDouble(_scale, _scale, 1, 1),
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            CanvasPage(
                              doc: widget.doc,
                              pageWidth: pageWidth,
                              minHeight: viewport.height,
                              selected: widget.selected,
                              dragging: widget.dragging,
                              onSelect: widget.onSelect,
                              onDrop: widget.onDrop,
                              canDrop: widget.canDrop,
                              onDragging: widget.onDragging,
                              boxKey: _keyFor,
                              preview: _preview,
                            ),
                            Positioned.fill(
                              child: ValueListenableBuilder<CanvasSelection?>(
                                valueListenable: _selection,
                                builder: (context, sel, _) => sel == null
                                    ? const SizedBox.shrink()
                                    : CanvasSelectionOverlay(
                                        selection: sel,
                                        scale: _scale,
                                        showBoxModel: _showBoxModel,
                                        onResizeStart: _resizeStart,
                                        onResizeUpdate: _resizeUpdate,
                                        onResizeEnd: _resizeEnd,
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _toolbar(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    Widget icon(IconData data, String tip, VoidCallback? onTap, {bool active = false}) => IconButton(
      tooltip: tip,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      padding: EdgeInsets.zero,
      icon: Icon(data, size: 18, color: active ? c.accent : null),
      onPressed: onTap,
    );
    String label(int w) => w == 0 ? '自适应' : '$w';
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      padding: const EdgeInsets.only(left: Space.x2, right: Space.x1),
      child: Row(
        children: [
          PopupMenuButton<int>(
            tooltip: '页面宽度',
            initialValue: _presetWidth,
            onSelected: (w) {
              setState(() => _presetWidth = w);
              fitToScreen();
            },
            itemBuilder: (_) => [for (final w in kCanvasWidthPresets) PopupMenuItem(value: w, child: Text(w == 0 ? '自适应（跟屏幕一样宽）' : '$w 像素'))],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.x2, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.phone_android, size: 16, color: c.textMuted),
                  const SizedBox(width: 4),
                  Text('宽度 ${label(_presetWidth)}', style: t.labelMedium),
                  Icon(Icons.arrow_drop_down, size: 18, color: c.textMuted),
                ],
              ),
            ),
          ),
          const Spacer(),
          icon(Icons.border_outer, _showBoxModel ? '间距示意：开' : '间距示意：关', () => setState(() => _showBoxModel = !_showBoxModel), active: _showBoxModel),
          icon(Icons.remove, '缩小', _scale > kCanvasMinScale + 0.001 ? () => _zoomStep(-1) : null),
          SizedBox(
            width: 44,
            child: Text('${(_scale * 100).round()}%', key: const ValueKey('lowcode-zoom-label'), textAlign: TextAlign.center, style: t.labelMedium),
          ),
          icon(Icons.add, '放大', _scale < kCanvasMaxScale - 0.001 ? () => _zoomStep(1) : null),
          icon(Icons.fit_screen_outlined, '适应屏幕', fitToScreen),
        ],
      ),
    );
  }
}
