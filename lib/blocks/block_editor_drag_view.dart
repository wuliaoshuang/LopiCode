// 设计约束（拖积木这一层，390 宽，浅色 + 深色）— 2026-11-24
// - 手上的积木画在最上面一层（盖过积木盒），跟着手指走，略放大带投影；它原来的位置立刻合拢。
// - 靠近能拼的地方：那里的积木让开，露出一块落点阴影，手机轻轻“咔”一下；表达式则是目标槽亮起描边。
// - 拖动时底部的积木盒换成一整条“拖到这里删除”（和面板一样高，面板收起时也不矮于 96），手指进去变红；从积木盒新拿出来的积木拖回去＝不要了。
//   一开始拖，面板要是比默认档高就自己滑回默认档，把画布让出来。
// - 拿起来：积木从原大“被拿起”放大到 104%（约 110 毫秒，带一点过冲）；原位的积木滑着合拢。
// - 靠近落点：手上的积木被“吸”过去一半（看得出它要去哪），落点处的积木滑开让位、露出同形的落点阴影。
// - 松手：飞向落点（120 毫秒，缓出），到位立刻改模型，然后画布上那块轻弹一下（100 毫秒，1.04 → 0.98 → 1）＋亮一圈。
//   没地方放就晃着弹回原处（原位先滑开让出空）并说一句为什么；删除是缩小淡出。
// - 动画不挡手：飞的过程中又按下去，动画立刻走完（模型当场改好），新的手势照常接。只有“删掉这一整串？”的确认框开着时不接。
// - 系统开了“减弱动态效果”：全部直接到终态。
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:lopicode/blocks/block_canvas_layout.dart';
import 'package:lopicode/blocks/block_canvas_view.dart';
import 'package:lopicode/blocks/block_drag.dart';
import 'package:lopicode/blocks/block_editor_canvas_view.dart';
import 'package:lopicode/blocks/block_editor_view.dart';
import 'package:lopicode/blocks/block_geometry.dart';
import 'package:lopicode/blocks/block_motion.dart';
import 'package:lopicode/blocks/block_paint_view.dart';
import 'package:lopicode/blocks/block_palette_view.dart';
import 'package:lopicode/blocks/block_script_view.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';

enum _Settle { none, drop, back, vanish, hold }

mixin BkEditorDrag on State<BlockEditorView>, BkKitHolder<BlockEditorView>, TickerProvider, BkEditorCanvas {
  /// 飞向落点、弹回原处、缩小消失、被拿起各多久。落下以后画布上还有 100 毫秒的轻弹（[BkEditorCanvas.pulseTime]），加起来不超过 220。
  static const Duration dropTime = Duration(milliseconds: 120);
  static const Duration backTime = Duration(milliseconds: 180);
  static const Duration vanishTime = Duration(milliseconds: 160);
  static const Duration liftTime = Duration(milliseconds: 110);

  /// 有落点时，手上的积木往落点靠多少（0＝完全跟手，1＝直接贴上去）。
  static const double magnet = 0.5;

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
  late final AnimationController liftAnim = AnimationController(vsync: this, duration: liftTime, value: 1);
  _Settle _settle = _Settle.none;
  Offset _settleFrom = Offset.zero, _settleTo = Offset.zero;
  void Function()? _settleDone;
  int _settleGen = 0;

  /// 上一个落点（或没有落点）时，手上的积木被吸偏了多少：换落点时从这里接着滑，不会跳。
  Offset _pullFrom = Offset.zero;

  Timer? _edgeTimer;
  int _edgeTicks = 0;

  @override
  bool get busy => _settle != _Settle.none;

  /// 底部那一条（积木盒 / 垃圾桶）现在多高。
  double get dockHeight;

  /// 要往画布上放东西了：面板比默认档高就让开。
  void dockYield();
  void toast(String text, {String? actionLabel, VoidCallback? onAction});

  @override
  double get coveredBottom => dockHeight;

  /// 手上那一截的左上角现在在编辑区的哪里（只按手指算，找落点用这个）。
  Offset get _pieceView => _fingerAt - _grab * zoom;

  Offset get _pullTo {
    final d = _drag, t = _drag?.target;
    if (d == null || t == null || d.kind == BkDragKind.hat || reduceMotion) return Offset.zero;
    return (toView(t.anchor) - _pieceView) * magnet;
  }

  /// 手上那一截画在编辑区的哪里：跟手，有落点时被吸过去一半。
  Offset get pieceShownAt => _pieceView + Offset.lerp(_pullFrom, _pullTo, roomT)!;

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
    if ((busy && !settleNow()) || _drag != null) return;
    final kind = switch (item.kind) {
      BlockPaletteKind.hat => BkDragKind.hat,
      BlockPaletteKind.block => BkDragKind.statement,
      BlockPaletteKind.expr => BkDragKind.expr,
    };
    _begin(BkDragSession.fromPalette(host, engine, layout, BkPaletteSource(kind, item.id), item.layout), viewOf(global), grab);
  }

  void dragMoveGlobal(Offset global) => dragMove(viewOf(global));

  void _begin(BkDragSession session, Offset viewAt, Offset grab) {
    // 原位合拢是滑着合的：从拿起来之前的样子滑到“拿走以后”。
    motion.jump(session.normal);
    dockYield();
    setState(() {
      _drag = session;
      _fingerAt = viewAt;
      _grab = grab;
      overTrash = false;
      selection = null;
    });
    _pullFrom = Offset.zero;
    slideTo(session.display);
    if (reduceMotion) {
      liftAnim.value = 1;
    } else {
      unawaited(liftAnim.forward(from: 0));
    }
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
    final pull = pieceShownAt - _pieceView;
    final inDock = _inDock;
    overTrash = inDock && !d.isNew;
    final changed = inDock ? d.clearTarget() : d.update(toCanvas(_pieceView));
    if (!changed) return;
    _pullFrom = pull;
    slideTo(d.display, room: d.ghost, always: true);
    final t = d.target;
    if (t != null && !t.noop) unawaited(HapticFeedback.selectionClick());
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

  /// 这次拖动结束。`room`＝画布上刚放进去 / 原样放回去的那一截（它在让位时已经让好了位置，不再滑）。
  void _finish({BkRoom? room}) {
    _stopEdge();
    _settleGen++;
    _settleDone = null;
    setState(() {
      _drag = null;
      _settle = _Settle.none;
      overTrash = false;
    });
    _pullFrom = Offset.zero;
    slideTo(layout, room: room);
  }

  void _run(_Settle mode, Duration time, Offset to, void Function() done) {
    _stopEdge();
    final from = pieceShownAt;
    final gen = ++_settleGen;
    setState(() {
      _settle = mode;
      _settleFrom = from;
      _settleTo = to;
      _settleDone = done;
    });
    if (reduceMotion || time == Duration.zero) {
      settleNow();
      return;
    }
    settleAnim.duration = time;
    unawaited(
      settleAnim.forward(from: 0).whenComplete(() {
        if (mounted && gen == _settleGen) settleNow();
      }),
    );
  }

  @override
  bool settleNow() {
    if (_settle == _Settle.none) return true;
    if (_settle == _Settle.hold) return false;
    final f = _settleDone;
    _settleDone = null;
    _settleGen++;
    settleAnim.stop();
    if (f == null) {
      _finish();
    } else {
      f();
    }
    return _settle == _Settle.none;
  }

  /// 弹回原处（积木盒来的就地缩没）。原位先让出空来，飞回去正好落进去。
  void _bounceBack() {
    final d = _drag;
    final from = d?.pieceOrigin;
    if (d == null || from == null) return _run(_Settle.vanish, vanishTime, pieceShownAt, _finish);
    final pull = pieceShownAt - _pieceView;
    if (d.aimHome()) {
      _pullFrom = pull;
      slideTo(d.display, room: d.ghost, always: true);
    }
    final home = d.ghost;
    _run(_Settle.back, backTime, toView(from), () => _finish(room: home));
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
      if (d.isNew) return _run(_Settle.vanish, vanishTime, pieceShownAt, _finish);
      unawaited(_dropInTrash(d));
      return;
    }
    final at = toCanvas(_pieceView);
    switch (d.check(at)) {
      case BkDropResult.applied:
        unawaited(HapticFeedback.lightImpact());
        final t = d.target;
        final isHat = d.kind == BkDragKind.hat || t == null;
        final to = isHat ? _pieceView : toView(t.anchor);
        final room = d.ghost;
        _run(_Settle.drop, isHat ? Duration.zero : dropTime, to, () {
          final placed = d.commit(isHat ? at : toCanvas(to));
          _finish(room: placed == null ? null : room);
          if (placed == null) return toast('没放成，再试一次。');
          setState(() => selection = BlockSelection(placed.scriptId, placed.path));
          // 到位了：画布上那一段轻弹一下（表达式是槽的描边闪一下）。
          final snap = t?.snap;
          if (d.kind == BkDragKind.expr && snap != null) {
            pulseBlocks(placed.scriptId, slot: (block: snap.parent, arg: snap.arg ?? '', path: snap.exprPath));
          } else {
            pulseBlocks(placed.scriptId, range: room);
          }
          _afterExprDrop(d);
        });
      case BkDropResult.noop:
        _bounceBack();
      case BkDropResult.rejected:
        unawaited(HapticFeedback.heavyImpact());
        toast(d.rejectReason);
        _bounceBack();
    }
  }

  /// 表达式盖住了一个有内容的值、又没处可换：说一声，给个“撤销”。
  void _afterExprDrop(BkDragSession d) {
    if (d.droppedExpr == null) return;
    final rev = host.revision;
    toast(
      '原来的值被换掉了。',
      actionLabel: '撤销',
      onAction: () {
        if (host.revision == rev && host.canUndo) host.undo();
      },
    );
  }

  Future<void> _dropInTrash(BkDragSession d) async {
    if (d.kind == BkDragKind.hat && d.blocks.isNotEmpty) {
      // 先把手上的放稳（不再跟手），问清楚再删。
      final at = pieceShownAt;
      setState(() {
        _settleFrom = _settleTo = at;
        _settleDone = null;
        _settle = _Settle.hold;
      });
      final ok = await confirmDialog(context, title: '删掉这一整串？', message: '这个事件下面还有 ${d.deleteCount - 1} 块积木，会一起删掉。可以用撤销找回来。', confirmLabel: '删除', danger: true);
      if (!mounted || !identical(_drag, d)) return;
      setState(() => _settle = _Settle.none);
      if (!ok) {
        setState(() => overTrash = false);
        return _bounceBack();
      }
    }
    unawaited(HapticFeedback.mediumImpact());
    _run(_Settle.vanish, vanishTime, pieceShownAt, () {
      d.delete();
      _finish();
    });
  }

  void disposeDrag() {
    _stopEdge();
    settleAnim.dispose();
    liftAnim.dispose();
  }

  /// 手上那一截此刻的缩放（不算画布缩放）和不透明度。测试用。
  ({Offset at, double scale, double opacity}) get pieceLook {
    final t = reduceMotion ? 1.0 : settleAnim.value;
    switch (_settle) {
      case _Settle.none:
        // 被拿起：从原大放大到 104%，带一点过冲。
        final k = reduceMotion ? 1.0 : Curves.easeOutBack.transform(liftAnim.value);
        return (at: pieceShownAt, scale: 1 + 0.04 * k, opacity: 1);
      case _Settle.hold:
        return (at: _settleFrom, scale: 1.04, opacity: 1);
      case _Settle.drop:
        // 飞向落点：缓出。到位以后的回弹由画布上那块积木接着做（从 1.04 开始），所以这里不缩。
        return (at: Offset.lerp(_settleFrom, _settleTo, Curves.easeOutCubic.transform(t))!, scale: 1.04, opacity: 1);
      case _Settle.back:
        // 弹回去时左右晃两下，慢慢缩回原大。
        final at = Offset.lerp(_settleFrom, _settleTo, Curves.easeOutCubic.transform(t))! + Offset(math.sin(t * math.pi * 4) * 6 * (1 - t), 0);
        return (at: at, scale: 1 + 0.04 * (1 - t), opacity: 1);
      case _Settle.vanish:
        return (at: _settleFrom, scale: 1.04 * (1 - Curves.easeIn.transform(t)), opacity: 1 - t);
    }
  }

  /// 手上那一截（画在最上面一层）。
  Widget buildDragPiece(BuildContext context) {
    final d = _drag;
    if (d == null) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: Listenable.merge([settleAnim, liftAnim, roomAnim]),
      builder: (context, _) {
        final look = pieceLook;
        return Positioned(
          left: look.at.dx,
          top: look.at.dy,
          child: IgnorePointer(
            child: Opacity(
              opacity: look.opacity.clamp(0.0, 1.0),
              // 画布缩放绕左上角（位置才对得上）；“被拿起”的放大绕自己的中心（落下时和画布上那块的轻弹接得上）。
              child: Transform.scale(
                scale: zoom,
                alignment: Alignment.topLeft,
                child: Transform.scale(
                  scale: math.max(0.001, look.scale),
                  child: CustomPaint(
                    key: const ValueKey('bk-drag-piece'),
                    size: d.piece.size,
                    painter: BkScriptCustomPainter(layout: d.piece, painter: kit.painter, state: const BkPaintState(lifted: true)),
                  ),
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
    // 高度不做动画：它跟着面板走（面板自己会滑），再做一层就总慢一拍。
    return SizedBox(
      key: const ValueKey('bk-trash'),
      height: dockHeight,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
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
      ),
    );
  }
}
