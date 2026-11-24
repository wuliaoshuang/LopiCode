// 设计约束（拖积木这一层，390 宽，浅色 + 深色）— 2026-11-24
// - 手上的积木画在最上面一层（盖过积木盒），跟着手指走，略放大带投影；它原来的位置立刻合拢。
// - 靠近能拼的地方：那里的积木让开，露出一块落点阴影，手机轻轻“咔”一下；表达式则是目标槽亮起描边。
// - 拖动时底部的积木盒换成一整条“拖到这里删除”，手指进去变红；从积木盒新拿出来的积木拖回去＝不要了。
// - 松手：吸过去（约 150 毫秒，带一点回弹）；没地方放就弹回原处并说一句为什么；删除是缩小消失。
// - 动画那一小会儿不接新的手势，动画完了才真正改模型（一次改动＝一条撤销记录）。
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:lopicode/blocks/block_canvas_layout.dart';
import 'package:lopicode/blocks/block_canvas_view.dart';
import 'package:lopicode/blocks/block_drag.dart';
import 'package:lopicode/blocks/block_editor_canvas_view.dart';
import 'package:lopicode/blocks/block_editor_view.dart';
import 'package:lopicode/blocks/block_geometry.dart';
import 'package:lopicode/blocks/block_paint_view.dart';
import 'package:lopicode/blocks/block_palette_view.dart';
import 'package:lopicode/blocks/block_script_view.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';

enum _Settle { none, drop, back, vanish }

mixin BkEditorDrag on State<BlockEditorView>, BkKitHolder<BlockEditorView>, TickerProvider, BkEditorCanvas {
  static const Duration dropTime = Duration(milliseconds: 150);
  static const Duration backTime = Duration(milliseconds: 180);
  static const Duration vanishTime = Duration(milliseconds: 160);

  /// 手指离画布边缘多近开始自动滚，和要停多久才滚（免得从积木盒往外拿的时候一路带着画布跑）。
  static const double edgeBand = 48;
  static const int edgeDwellTicks = 18; // 16 毫秒一跳，约 0.3 秒

  BkDragSession? _drag;
  @override
  BkDragSession? get drag => _drag;

  /// 手指在编辑区的哪里；手指离手上那一截左上角多远（画布尺寸）。
  Offset _fingerAt = Offset.zero;
  Offset _grab = Offset.zero;
  bool overTrash = false;

  /// 手指离手上那一截左上角多远（画布尺寸；测试里算落点用）。
  Offset get grabOffset => _grab;

  late final AnimationController settleAnim = AnimationController(vsync: this);
  _Settle _settle = _Settle.none;
  Offset _settleFrom = Offset.zero, _settleTo = Offset.zero;
  void Function()? _settleDone;

  Timer? _edgeTimer;
  int _edgeTicks = 0;

  @override
  bool get busy => _settle != _Settle.none;

  /// 底部那一条（积木盒 / 垃圾桶）现在多高。
  double get dockHeight;
  void toast(String text);

  @override
  double get coveredBottom => dockHeight;

  /// 手上那一截的左上角现在在编辑区的哪里。
  Offset get _pieceView => _fingerAt - _grab * zoom;

  bool get _inDock => _fingerAt.dy >= viewSize.height - dockHeight;

  @override
  void dragStartFromCanvas(BkPlaced script, BkHit hit, Offset viewAt) {
    final session = BkDragSession.fromHit(host, engine, layout, script, hit);
    final origin = session?.pieceOrigin;
    if (session == null || origin == null) return;
    _begin(session, viewAt, toCanvas(viewAt) - origin);
  }

  /// 从积木盒里拿出来。`global`＝手指在屏幕的哪里；`grab`＝手指离样品左上角多远。
  void dragStartFromPalette(BlockPaletteItem item, Offset global, Offset grab) {
    if (busy || _drag != null) return;
    final kind = switch (item.kind) {
      BlockPaletteKind.hat => BkDragKind.hat,
      BlockPaletteKind.block => BkDragKind.statement,
      BlockPaletteKind.expr => BkDragKind.expr,
    };
    _begin(BkDragSession.fromPalette(host, engine, layout, BkPaletteSource(kind, item.id), item.layout), viewOf(global), grab);
  }

  void dragMoveGlobal(Offset global) => dragMove(viewOf(global));

  void _begin(BkDragSession session, Offset viewAt, Offset grab) {
    setState(() {
      _drag = session;
      _fingerAt = viewAt;
      _grab = grab;
      overTrash = false;
      selection = null;
    });
  }

  @override
  void dragMove(Offset viewAt) {
    final d = _drag;
    if (d == null || busy) return;
    if (d.revision != host.revision) return dragCancel();
    _fingerAt = viewAt;
    _retarget();
    _watchEdge();
    setState(() {});
  }

  void _retarget() {
    final d = _drag;
    if (d == null) return;
    final inDock = _inDock;
    overTrash = inDock && !d.isNew;
    final changed = inDock ? d.clearTarget() : d.update(toCanvas(_pieceView));
    final t = d.target;
    if (changed && t != null && !t.noop) unawaited(HapticFeedback.selectionClick());
  }

  // —— 拖到边上自动滚 ——

  Offset _edgePush() {
    final w = viewSize.width, h = viewSize.height - dockHeight;
    final p = _fingerAt;
    if (p.dy >= h) return Offset.zero;
    double pull(double d) => d < edgeBand ? (edgeBand - math.max(0, d)) / edgeBand : 0;
    return Offset(pull(p.dx) - pull(w - p.dx), pull(p.dy) - pull(h - p.dy));
  }

  void _watchEdge() {
    if (_edgePush() == Offset.zero) return _stopEdge();
    _edgeTimer ??= Timer.periodic(const Duration(milliseconds: 16), (_) {
      final push = _edgePush();
      if (!mounted || _drag == null || busy || push == Offset.zero) return _stopEdge();
      if (++_edgeTicks < edgeDwellTicks) return;
      final before = pan;
      setPan(pan + push * 10);
      if (pan == before) return;
      _retarget();
      setState(() {});
    });
  }

  void _stopEdge() {
    _edgeTimer?.cancel();
    _edgeTimer = null;
    _edgeTicks = 0;
  }

  // —— 松手 ——

  void _finish() {
    _stopEdge();
    setState(() {
      _drag = null;
      _settle = _Settle.none;
      overTrash = false;
    });
  }

  void _run(_Settle mode, Duration time, Offset to, void Function() done) {
    _stopEdge();
    setState(() {
      _settle = mode;
      _settleFrom = _pieceView;
      _settleTo = to;
      _settleDone = done;
    });
    settleAnim.duration = time;
    unawaited(
      settleAnim.forward(from: 0).whenComplete(() {
        if (!mounted || _settle != mode) return;
        final f = _settleDone;
        _settleDone = null;
        f?.call();
      }),
    );
  }

  /// 弹回原处（积木盒来的就地缩没）。
  void _bounceBack() {
    final from = _drag?.pieceOrigin;
    if (from == null) return _run(_Settle.vanish, vanishTime, _pieceView, _finish);
    _run(_Settle.back, backTime, toView(from), _finish);
  }

  @override
  void dragCancel() {
    if (_drag == null) return;
    _finish();
  }

  @override
  void dragEnd() {
    final d = _drag;
    if (d == null || busy) return;
    if (d.revision != host.revision) return dragCancel();
    if (_inDock) {
      if (d.isNew) return _run(_Settle.vanish, vanishTime, _pieceView, _finish);
      unawaited(_dropInTrash(d));
      return;
    }
    final at = toCanvas(_pieceView);
    switch (d.check(at)) {
      case BkDropResult.applied:
        unawaited(HapticFeedback.lightImpact());
        final t = d.target;
        final to = d.kind == BkDragKind.hat || t == null ? _pieceView : toView(t.anchor);
        _run(_Settle.drop, dropTime, to, () {
          final placed = d.commit(d.kind == BkDragKind.hat ? at : toCanvas(to));
          _finish();
          if (placed == null) return toast('没放成，再试一次。');
          setState(() => selection = BlockSelection(placed.scriptId, placed.path));
        });
      case BkDropResult.noop:
        _bounceBack();
      case BkDropResult.rejected:
        unawaited(HapticFeedback.heavyImpact());
        toast(d.rejectReason);
        _bounceBack();
    }
  }

  Future<void> _dropInTrash(BkDragSession d) async {
    if (d.kind == BkDragKind.hat && d.blocks.isNotEmpty) {
      // 先把手上的放稳（不再跟手），问清楚再删。
      settleAnim.value = 0;
      setState(() {
        _settleFrom = _settleTo = _pieceView;
        _settle = _Settle.back;
      });
      final ok = await confirmDialog(context, title: '删掉这一整串？', message: '这个事件下面还有 ${d.deleteCount - 1} 块积木，会一起删掉。可以用撤销找回来。', confirmLabel: '删除', danger: true);
      if (!mounted) return;
      setState(() => _settle = _Settle.none);
      if (!ok) {
        setState(() => overTrash = false);
        return _bounceBack();
      }
    }
    unawaited(HapticFeedback.mediumImpact());
    _run(_Settle.vanish, vanishTime, _pieceView, () {
      d.delete();
      _finish();
    });
  }

  void disposeDrag() {
    _stopEdge();
    settleAnim.dispose();
  }

  /// 手上那一截（画在最上面一层）。
  Widget buildDragPiece(BuildContext context) {
    final d = _drag;
    if (d == null) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: settleAnim,
      builder: (context, _) {
        var at = _pieceView;
        // 拿在手上放大一点点（4%），落下 / 弹回的过程中慢慢缩回原大。
        var scale = zoom * 1.04, opacity = 1.0;
        var lifted = true;
        final t = settleAnim.value;
        if (_settle == _Settle.drop || _settle == _Settle.back) scale = zoom * (1 + 0.04 * (1 - t));
        switch (_settle) {
          case _Settle.none:
            break;
          case _Settle.drop:
            at = Offset.lerp(_settleFrom, _settleTo, Curves.easeOutBack.transform(t))!;
            lifted = t < 0.6;
          case _Settle.back:
            // 弹回去时左右晃两下。
            at = Offset.lerp(_settleFrom, _settleTo, Curves.easeOutCubic.transform(t))! + Offset(math.sin(t * math.pi * 4) * 6 * (1 - t), 0);
          case _Settle.vanish:
            scale = zoom * (1 - Curves.easeIn.transform(t));
            opacity = 1 - t;
            at = _settleFrom + Offset(d.piece.size.width, d.piece.size.height) * zoom * 0.5 * Curves.easeIn.transform(t);
        }
        return Positioned(
          left: at.dx,
          top: at.dy,
          child: IgnorePointer(
            child: Opacity(
              opacity: opacity.clamp(0.0, 1.0),
              child: Transform.scale(
                scale: math.max(0.001, scale),
                alignment: Alignment.topLeft,
                child: BkLayoutView(
                  key: const ValueKey('bk-drag-piece'),
                  layout: d.piece,
                  kit: kit,
                  state: BkPaintState(lifted: lifted),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// 拖动时盖在积木盒位置上的垃圾桶。
  Widget buildTrash(BuildContext context) {
    final c = context.colors;
    final hot = overTrash;
    final n = _drag?.deleteCount ?? 0;
    return AnimatedContainer(
      key: const ValueKey('bk-trash'),
      duration: const Duration(milliseconds: 120),
      height: dockHeight,
      decoration: BoxDecoration(
        // 整片染成淡红就够了：满屏大红太吓人，也会盖过手上那块积木。
        color: hot ? Color.alphaBlend(c.danger.withValues(alpha: 0.18), c.surface) : c.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        border: Border(
          top: BorderSide(color: hot ? c.danger : c.border, width: hot ? 2 : 1),
        ),
      ),
      // 字放在上沿：手指和手上的积木在下面，不会把它挡住。
      alignment: Alignment.topCenter,
      padding: const EdgeInsets.only(top: 18),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedScale(
            scale: hot ? 1.25 : 1,
            duration: const Duration(milliseconds: 120),
            child: Icon(hot ? Icons.delete_forever_rounded : Icons.delete_outline_rounded, color: hot ? c.danger : c.textMuted, size: 26),
          ),
          const SizedBox(width: 8),
          Text(
            hot ? (n > 1 ? '松手删除（$n 块）' : '松手删除') : '拖到这里删除',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: hot ? c.danger : c.textMuted, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
