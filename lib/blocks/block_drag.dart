/// 一次拖动：手上拿着什么、从哪拿的、现在能落在哪、松手以后怎么改模型。
///
/// 不带界面（位置都用画布坐标），可以直接单元测试。界面那一层（block_editor_drag_view.dart）只管把手指的位置喂进来、
/// 把 [BkDragSession.display] 画出来。
///
/// 规矩（docs/blocks-v3-design.md “手感”一节）：
/// - 拖语句积木＝从它到所在那一列末尾的一整截；拖帽子＝整串；表达式单独拖。
/// - 拖起来的一瞬间原位置就合拢：[base] 是“拿走以后”的排布，可拼接点都在它上面找，所以不可能拖进自己里面。
/// - 靠近可拼接点（[snapRadius] 以内）时，[display] 里那个位置让出一块落点阴影；放回原来的位置算“没动”，不产生改动。
/// - 语句积木、表达式不能散放在空白处（模型里每块积木都得属于某一串）：没有落点就弹回去。
/// - 表达式拖进已经有值的槽：两个值**交换**（原值回到被拖表达式原来的槽），不丢东西；只有从积木盒拿来的新表达式、
///   或者把里面的一块拖出来盖住外面整块时，原值没处可去才丢掉（[BkDragSession.droppedExpr]，界面给“撤销”）。
library;

import 'dart:ui';

import 'package:lopicode/blocks/block_canvas_layout.dart';
import 'package:lopicode/blocks/block_geometry.dart';
import 'package:lopicode/blocks/block_host.dart';
import 'package:lopicode/blocks/block_layout.dart';
import 'package:lopicode/blocks/block_ops.dart';
import 'package:lopicode/lowcode/logic_expr.dart';
import 'package:lopicode/lowcode/logic_model.dart';

enum BkDragKind { statement, hat, expr }

/// 从积木盒里拿出来的是什么（和积木盒控件里的那一项对应，这里不依赖界面）。
class BkPaletteSource {
  const BkPaletteSource(this.kind, this.id);
  final BkDragKind kind;

  /// 帽子模板的 id / 积木的 op / 表达式的 e。
  final String id;
}

/// 现在能落在哪。
class BkDropTarget {
  const BkDropTarget({required this.scriptId, required this.snap, required this.anchor, required this.noop, this.mismatch = false});
  final String scriptId;
  final BkSnap snap;

  /// 画布坐标：语句＝被拖那一截的左上角该去的地方；表达式＝槽的左上角。
  final Offset anchor;

  /// 就是原来的位置：放下等于没动。
  final bool noop;

  /// 表达式：槽要“是 / 否”而拖来的不是（照样能放，翻代码时会自动转换，只是提醒一下）。
  final bool mismatch;
}

/// 松手以后的结果。
enum BkDropResult {
  /// 改了模型。
  applied,

  /// 放回原处，什么都没改。
  noop,

  /// 放不了（[BkDragSession.rejectReason] 里是原因），什么都没改。
  rejected,
}

class BkDragSession {
  BkDragSession._({
    required this.host,
    required this.engine,
    required this.normal,
    required this.kind,
    required this.piece,
    this.scriptId,
    this.path = const [],
    this.arg,
    this.exprPath = const [],
    this.palette,
    this.blocks = const [],
    this.expr,
    this.pieceOrigin,
  }) : revision = host.revision {
    base = _buildBase();
    display = base;
  }

  /// 吸附半径（画布坐标，逻辑像素）。
  static const double snapRadius = 36;

  /// 从画布上拖：`hit` 是手指按下的地方。按到表达式块＝拖表达式；按到帽子＝拖整串；否则拖那块积木和它下面的。
  static BkDragSession? fromHit(BlockHost host, BlockLayoutEngine engine, BkCanvasLayout normal, BkPlaced script, BkHit hit) {
    final tree = host.script(script.id);
    if (tree == null) return null;
    final e = hit.expr, slot = hit.slot;
    if (e != null && slot != null) {
      // hit.slot 可能是表达式里面的小槽：往外找到“装着这个表达式”的那个槽。
      final owner = _slotOf(script.layout, hit.block, e);
      if (owner == null) return null;
      return BkDragSession._(
        host: host,
        engine: engine,
        normal: normal,
        kind: BkDragKind.expr,
        piece: engine.layoutExpr(e.expr),
        scriptId: script.id,
        path: hit.block.path,
        arg: owner.arg,
        exprPath: owner.exprPath,
        expr: e.expr,
        pieceOrigin: script.origin + e.rect.topLeft,
      );
    }
    if (hit.block.isHat) {
      return BkDragSession._(host: host, engine: engine, normal: normal, kind: BkDragKind.hat, piece: script.layout, scriptId: script.id, blocks: tree.body, pieceOrigin: script.origin);
    }
    final path = hit.block.path;
    final parent = path.sublist(0, path.length - 1);
    final list = tree.listAt(parent, inElse: path.last.inElse);
    if (list == null || path.last.index >= list.length) return null;
    final tail = list.sublist(path.last.index);
    return BkDragSession._(
      host: host,
      engine: engine,
      normal: normal,
      kind: BkDragKind.statement,
      piece: engine.layoutStack(tail, parent: parent, inElse: path.last.inElse, startIndex: path.last.index),
      scriptId: script.id,
      path: path,
      blocks: tail,
      pieceOrigin: script.origin + hit.block.rect.topLeft,
    );
  }

  /// 从积木盒里拖出来。`piece` 是积木盒里那个样品的排版。
  static BkDragSession fromPalette(BlockHost host, BlockLayoutEngine engine, BkCanvasLayout normal, BkPaletteSource source, BkScriptLayout piece) {
    return BkDragSession._(
      host: host,
      engine: engine,
      normal: normal,
      kind: source.kind,
      piece: piece,
      palette: source,
      blocks: source.kind == BkDragKind.statement ? [host.newBlock(source.id)] : const [],
      expr: source.kind == BkDragKind.expr ? host.newExpr(source.id) : null,
    );
  }

  static BkSlot? _slotOf(BkScriptLayout layout, BkBlock block, BkExpr expr) {
    for (final (b, s) in layout.allSlots) {
      if (identical(b, block) && identical(s.expr, expr)) return s;
    }
    return null;
  }

  final BlockHost host;
  final BlockLayoutEngine engine;

  /// 拖之前的排布。
  final BkCanvasLayout normal;
  final int revision;
  final BkDragKind kind;

  /// 拖在手上的东西的排版（左上角是原点）。
  final BkScriptLayout piece;

  /// 从哪拿的：哪一串、哪块积木（帽子为空）、（表达式）哪个参数里的哪个位置。从积木盒拿的 `scriptId` 为 null。
  final String? scriptId;
  final LcBlockPath path;
  final String? arg;
  final BkExprPath exprPath;
  final BkPaletteSource? palette;

  /// 手上的积木 / 表达式（只读着用，排预览；真正改模型时重新从宿主找）。
  final List<LcBlock> blocks;
  final Map<String, dynamic>? expr;

  /// 拿起来之前，这一截的左上角在画布的哪里（弹回去时用）；积木盒来的为 null。
  final Offset? pieceOrigin;

  /// “拿走以后”的排布：可拼接点都在这上面找。整个拖动期间不变。
  late final BkCanvasLayout base;

  /// 现在该画的排布（＝[base]，有落点时那里多让出一块）。
  late BkCanvasLayout display;
  BkDropTarget? target;

  /// 没放成的原因（给人看的一句话）。
  String rejectReason = '';

  /// [commit] 以后：表达式放进了已经有值的槽，原来那个值有没有换回被拖表达式原来的槽里（交换）。
  bool swapped = false;

  /// [commit] 以后：被换下来、没处可去而丢掉的值（从积木盒拖来的新表达式盖住了旧值；或者把里面的一块拖出来盖住了外面整块）。
  /// 原来就是默认值的不算。界面拿它给一条带“撤销”的提示。
  Map<String, dynamic>? droppedExpr;

  static bool _isPrefix(BkExprPath a, BkExprPath b) => a.length < b.length && bkSameExprPath(a, b.sublist(0, a.length));

  bool get isNew => palette != null;

  /// 落点阴影在哪一串的哪一段（语句积木才有）。
  ({String scriptId, LcBlockPath parent, bool inElse, int start, int count})? get ghost {
    final t = target;
    if (t == null || kind != BkDragKind.statement) return null;
    return (scriptId: t.scriptId, parent: t.snap.parent, inElse: t.snap.inElse, start: t.snap.index, count: blocks.length);
  }

  Map<String, Offset> get _origins => {for (final p in normal.scripts) p.id: p.origin};

  /// 某一串“拿走以后”的积木。
  List<LcBlock>? _baseBody(String id) {
    final tree = host.script(id);
    if (tree == null) return null;
    if (id != scriptId || isNew) return tree.body;
    switch (kind) {
      case BkDragKind.statement:
        final start = path.last.index;
        return bkEditedBody(tree.body, path.sublist(0, path.length - 1), path.last.inElse, (list) {
          if (start <= list.length) list.removeRange(start, list.length);
        });
      case BkDragKind.expr:
        return bkBodyWithBlock(tree.body, path, (b) {
          final copy = bkCopyArgs(b);
          bkTakeExpr(host, copy, arg!, exprPath);
          return copy;
        });
      case BkDragKind.hat:
        return tree.body;
    }
  }

  BkCanvasLayout _buildBase() {
    final id = scriptId;
    if (id == null) return normal;
    // 没动的那些串沿用拖之前排好的，只重排被拿走东西的那一串。
    final keep = {
      for (final p in normal.scripts)
        if (p.id != id) p.id: p.layout,
    };
    if (kind == BkDragKind.hat) return layoutBlockCanvas(host, engine, hide: {id}, origins: _origins, layouts: keep);
    final body = _baseBody(id);
    return layoutBlockCanvas(host, engine, bodies: {id: ?body}, origins: _origins, layouts: keep);
  }

  /// 手指动了：`topLeft` 是手上那一截的左上角现在在画布的哪里。返回落点有没有变。
  bool update(Offset topLeft) {
    if (kind == BkDragKind.hat) return false;
    final probe = kind == BkDragKind.statement ? topLeft : topLeft + Offset(6, piece.size.height / 2);
    final found = base.nearestSnap(probe, kind: kind == BkDragKind.statement ? BkSnapKind.statement : BkSnapKind.expr, maxDistance: snapRadius);
    if (found == null) return clearTarget();
    final old = target;
    if (old != null && identical(old.snap, found.snap)) return false;
    final snap = found.snap;
    if (kind == BkDragKind.statement) {
      final same = !isNew && found.script.id == scriptId && bkSameBlockPath(snap.parent, path.sublist(0, path.length - 1)) && (path.length == 1 || snap.inElse == path.last.inElse);
      target = BkDropTarget(scriptId: found.script.id, snap: snap, anchor: found.anchor, noop: same && snap.index == path.last.index);
    } else {
      final same = !isNew && found.script.id == scriptId && bkSameBlockPath(snap.parent, path) && snap.arg == arg && bkSameExprPath(snap.exprPath, exprPath);
      target = BkDropTarget(scriptId: found.script.id, snap: snap, anchor: found.script.origin + snap.rect.topLeft, noop: same, mismatch: snap.hex && !host.isBooleanExpr(expr!));
    }
    _rebuildDisplay();
    return true;
  }

  /// 手指离开了画布（去了垃圾桶 / 积木盒）：不再有落点。返回落点有没有变。
  bool clearTarget() {
    if (target == null) return false;
    target = null;
    display = base;
    return true;
  }

  void _rebuildDisplay() {
    final t = target;
    if (t == null || kind != BkDragKind.statement) {
      display = base;
      return;
    }
    final body = _baseBody(t.scriptId);
    final tree = host.script(t.scriptId);
    if (body == null || tree == null) {
      display = base;
      return;
    }
    final shown = bkEditedBody(body, t.snap.parent, t.snap.inElse, (list) => list.insertAll(t.snap.index.clamp(0, list.length), blocks));
    // 只有落点所在的那一串要重排；别的串沿用“拿走以后”排好的（每换一个落点只排一串，不是整张画布）。
    final made = engine.layoutScript(tree, body: shown);
    final layouts = {
      for (final p in base.scripts)
        if (p.id != t.scriptId) p.id: p.layout,
      t.scriptId: made,
    };
    display = layoutBlockCanvas(host, engine, layouts: layouts, origins: bkPushedOrigins(normal, t.scriptId, made.size.height));
  }

  /// 把落点对回原来的位置（弹回去之前调：原位先让出空来，手上那一截飞回去正好落进去）。
  /// 只有从画布上拿起来的语句积木有“原来的位置”；别的情况等于 [clearTarget]。返回落点有没有变。
  bool aimHome() {
    final id = scriptId;
    if (kind != BkDragKind.statement || isNew || id == null) return clearTarget();
    final t = target;
    if (t != null && t.noop) return false;
    final placed = base.placed(id);
    if (placed == null) return clearTarget();
    final parent = path.sublist(0, path.length - 1);
    for (final snap in placed.layout.snaps) {
      if (snap.kind != BkSnapKind.statement || snap.index != path.last.index || !bkSameBlockPath(snap.parent, parent)) continue;
      if (path.length > 1 && snap.inElse != path.last.inElse) continue;
      target = BkDropTarget(scriptId: id, snap: snap, anchor: placed.origin + snap.anchor, noop: true);
      _rebuildDisplay();
      return true;
    }
    return clearTarget();
  }

  bool get _stale => host.revision != revision;

  /// 松手了。`topLeft`＝手上那一截的左上角在画布的哪里（帽子就放在那）。先只判断、不改：返回会是什么结果。
  BkDropResult check(Offset topLeft) {
    rejectReason = '';
    if (_stale) return BkDropResult.noop;
    final t = target;
    switch (kind) {
      case BkDragKind.hat:
        final from = pieceOrigin;
        return from != null && (from - topLeft).distance < 1 ? BkDropResult.noop : BkDropResult.applied;
      case BkDragKind.statement:
        if (t == null) {
          rejectReason = host.scripts.isEmpty ? '先从“事件”里拖一块出来，积木要接在它下面。' : '积木要接在事件下面，不能单独放着。';
          return BkDropResult.rejected;
        }
        if (t.noop) return BkDropResult.noop;
        if (!bkFitsDepth(t.snap.parent, blocks)) {
          rejectReason = '积木套得太深了（最多 ${LcBlock.maxDepth + 1} 层），放不进去。';
          return BkDropResult.rejected;
        }
        if (host.script(t.scriptId)?.listAt(t.snap.parent, inElse: t.snap.inElse) == null) return BkDropResult.noop;
        return BkDropResult.applied;
      case BkDragKind.expr:
        if (t == null) {
          rejectReason = '把它放进积木上的槽里。';
          return BkDropResult.rejected;
        }
        return t.noop ? BkDropResult.noop : BkDropResult.applied;
    }
  }

  /// 真的落到模型上（一次 edit）。先 [check] 过是 applied 才调。返回落下去以后在哪（选中它用）；没改成返回 null。
  ({String scriptId, LcBlockPath path})? commit(Offset topLeft) {
    if (check(topLeft) != BkDropResult.applied) return null;
    ({String scriptId, LcBlockPath path})? result;
    host.edit(() {
      switch (kind) {
        case BkDragKind.hat:
          final x = topLeft.dx.roundToDouble(), y = topLeft.dy.roundToDouble();
          final src = palette;
          final tree = src != null ? host.addScript(src.id, x: x, y: y) : host.script(scriptId!);
          if (tree == null) return;
          bkFreezeAuto(host, normal);
          tree
            ..x = x
            ..y = y;
          result = (scriptId: tree.id, path: const []);
        case BkDragKind.statement:
          final t = target!;
          final List<LcBlock> moving;
          final src = palette;
          if (src != null) {
            moving = [host.newBlock(src.id)];
          } else {
            final list = host.script(scriptId!)?.listAt(path.sublist(0, path.length - 1), inElse: path.last.inElse);
            if (list == null || path.last.index >= list.length) return;
            moving = list.sublist(path.last.index);
            list.removeRange(path.last.index, list.length);
          }
          final dst = host.script(t.scriptId);
          if (dst == null) return;
          for (var i = 0; i < moving.length; i++) {
            dst.insertBlock(t.snap.parent, moving[i], inElse: t.snap.inElse, index: t.snap.index + i);
          }
          bkPushDown(host, engine, normal, t.scriptId);
          result = (
            scriptId: t.scriptId,
            path: [
              ...t.snap.parent,
              lcStep(t.snap.index, inElse: t.snap.inElse),
            ],
          );
        case BkDragKind.expr:
          final t = target!;
          final tree = host.script(t.scriptId);
          final to = tree?.blockAt(t.snap.parent);
          if (tree == null || to == null) return;
          final toArg = t.snap.arg!;
          final src = palette;
          Map<String, dynamic>? moving;
          LcBlockTree? fromTree;
          LcBlock? from;
          var removedAt = -1;
          List<dynamic>? fromList;
          if (src != null) {
            moving = host.newExpr(src.id);
          } else {
            fromTree = host.script(scriptId!);
            from = fromTree?.blockAt(path);
            if (from == null) return;
            // 原来是“一串值”里的一项：拿走会少一项，换下来的值放回去时要插回原来的位置。
            final list = exprPath.isNotEmpty && exprPath.last is int ? bkExprAt(from, arg!, exprPath.sublist(0, exprPath.length - 1)) : null;
            final before = list is List ? list.length : -1;
            moving = bkTakeExpr(host, from, arg!, exprPath);
            if (list is List && list.length < before) {
              fromList = list;
              removedAt = exprPath.last as int;
            }
          }
          if (moving == null) return;
          // 落点是原槽的外层（把里面的一块拖出来盖住整块）：换下来的那块里已经没有原槽了，没法交换。
          final inside = from != null && t.scriptId == scriptId && bkSameBlockPath(t.snap.parent, path) && toArg == arg && _isPrefix(t.snap.exprPath, exprPath);
          final old = asExpr(bkExprAt(to, toArg, t.snap.exprPath));
          final wasDefault = old == null || bkSameJson(old, bkDefaultExprAt(host, to, toArg, t.snap.exprPath));
          if (!bkSetExprAt(to, toArg, t.snap.exprPath, moving)) return;
          host.argChanged(tree, to, toArg, t.snap.exprPath);
          if (old != null && from != null && !inside) {
            // 交换：换下来的值回到被拖的那块原来的槽里。
            final list = fromList;
            if (list != null) {
              list.insert(removedAt.clamp(0, list.length), old);
              swapped = true;
            } else {
              swapped = bkSetExprAt(from, arg!, exprPath, old);
            }
            if (swapped) host.argChanged(fromTree!, from, arg!, exprPath);
          }
          if (old != null && !swapped && !wasDefault) droppedExpr = old;
          bkPushDown(host, engine, normal, t.scriptId);
          final other = scriptId;
          if (swapped && other != null && other != t.scriptId) bkPushDown(host, engine, normal, other);
          result = (scriptId: t.scriptId, path: t.snap.parent);
      }
    });
    return result;
  }

  /// 拖进垃圾桶以后会删掉几块积木（积木盒来的＝0，什么都不删）。帽子算上它下面所有的。
  int get deleteCount => isNew ? 0 : (kind == BkDragKind.expr ? 0 : bkCountBlocks(blocks) + (kind == BkDragKind.hat ? 1 : 0));

  /// 删掉手上的东西（一次 edit）。积木盒来的不用删。返回有没有改。
  bool delete() {
    final id = scriptId;
    if (id == null || _stale) return false;
    var done = false;
    host.edit(() {
      switch (kind) {
        case BkDragKind.hat:
          done = host.removeScript(id);
        case BkDragKind.statement:
          final list = host.script(id)?.listAt(path.sublist(0, path.length - 1), inElse: path.last.inElse);
          if (list == null || path.last.index >= list.length) return;
          list.removeRange(path.last.index, list.length);
          done = true;
        case BkDragKind.expr:
          final block = host.script(id)?.blockAt(path);
          done = block != null && bkTakeExpr(host, block, arg!, exprPath) != null;
      }
    });
    return done;
  }
}
