// 画布（canvas_view.dart）里“拖组件”的那一半：量盒子、算落点、停够了才进容器、边缘自动滚。
// 从 canvas_view.dart 拆出来的（那个文件贴着 600 行），行为一点没变。
part of 'canvas_view.dart';

mixin _CanvasDragging on State<CanvasView> {
  // 画布那一头给的：可视区、缩放和位置、量位置、挪位置。
  Size get _viewport;
  double get _scale;
  Offset get _offset;
  double get _room;
  Ticker get _ticker;
  RenderBox? get _pageBox;
  Rect? _rectOf(String id, RenderBox pageBox);
  void _moveTo(double scale, Offset offset);

  // 拖组件：量好的盒子、手指位置、停够了的容器、落点
  ({LcDrag drag, DropBox root})? _drag;
  Offset? _dragAt;
  final Map<String, Timer> _dwell = {};
  final Set<String> _armed = {};
  final ValueNotifier<DropTarget?> _target = ValueNotifier(null);

  /// 手指在页面里的横向位置：落点标签要躲着它（见 canvas_drag_widgets.dart）。
  final ValueNotifier<double?> _fingerX = ValueNotifier(null);
  Timer? _autoScroll;

  /// 拖动中算出来的落点（测试用）。
  DropTarget? get dropTarget => _target.value;

  DropBox? _boxes(RenderBox pageBox) => lcDropBoxTree(widget.doc, (id) => _rectOf(id, pageBox), overlayId: widget.overlayId);

  /// 在拖柄上点了一下（没拖）：当成点在它下面的组件上——拖柄能按的范围比看到的大，不能把旁边的小组件挡得点不着。
  void _tapThrough(Offset global) {
    final self = context.findRenderObject(), pageBox = _pageBox;
    final root = pageBox == null ? null : _boxes(pageBox);
    if (root == null || self is! RenderBox) return;
    final point = (self.globalToLocal(global) - _offset) / _scale;
    widget.onSelect(root.rect.contains(point) ? lcSplitSlotId(dropChain(root, point).last.id).$1 : null);
  }

  /// 开始拖：把所有组件的位置量下来（拖动中排版不变，量一次就够）。量不到（页面还没排出来）返回 false。
  bool beginDrag(LcDrag drag) {
    _stopDrag();
    _ticker.stop();
    final pageBox = _pageBox;
    final root = pageBox == null ? null : _boxes(pageBox);
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
}
