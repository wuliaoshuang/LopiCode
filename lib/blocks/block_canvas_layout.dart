/// 积木画布的排布：每串脚本摆在哪。纯计算。
///
/// 模型里有 x / y 的照着摆；没有的（旧页面、刚由别处加的）自动排成一列：从上到下、留间距，排在已经摆好的那些下面。
/// **自动排的位置只在这里用，不写回模型**（写回去就成了“改动”，会让没动过的旧页面文件变样）。
library;

import 'dart:math' as math;
import 'dart:ui';

import 'package:lopicode/blocks/block_geometry.dart';
import 'package:lopicode/blocks/block_host.dart';
import 'package:lopicode/blocks/block_layout.dart';
import 'package:lopicode/lowcode/logic_model.dart';

/// 摆在画布上的一串。
class BkPlaced {
  BkPlaced({required this.id, required this.origin, required this.layout, required this.auto});

  final String id;

  /// 这一串的左上角在画布上的位置。
  final Offset origin;
  final BkScriptLayout layout;

  /// 位置是自动排的（模型里没有 x / y）。
  final bool auto;

  Rect get bounds => origin & layout.size;
}

class BkCanvasLayout {
  BkCanvasLayout(this.scripts, this.extent);

  final List<BkPlaced> scripts;

  /// 所有脚本占的范围（从画布原点算起，含右、下的留白）。
  final Size extent;

  BkPlaced? placed(String id) {
    for (final s in scripts) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// 画布上的这个点是什么。后摆的在上面。
  ({BkPlaced script, BkHit hit})? hitTest(Offset p) {
    for (var i = scripts.length - 1; i >= 0; i--) {
      final s = scripts[i];
      if (!s.bounds.inflate(2).contains(p)) continue;
      final hit = s.layout.hitTest(p - s.origin);
      if (hit != null) return (script: s, hit: hit);
    }
    return null;
  }

  /// 画布上离这个点最近的可拼接点（所有脚本一起找）。参数的意思同 [BkScriptLayout.nearestSnap]；
  /// `excludeScript` + `exclude`＝正在拖的是哪一串的哪块（它自己里面的位置不算）。
  /// 返回的 `anchor` 已经换成画布坐标。
  ({BkPlaced script, BkSnap snap, Offset anchor, double distance})? nearestSnap(Offset p, {required BkSnapKind kind, double maxDistance = 36, String? excludeScript, LcBlockPath? exclude}) {
    ({BkPlaced script, BkSnap snap, Offset anchor, double distance})? best;
    for (final s in scripts) {
      final local = p - s.origin;
      final snap = s.layout.nearestSnap(local, kind: kind, maxDistance: maxDistance, exclude: s.id == excludeScript ? exclude : null);
      if (snap == null) continue;
      final d = snap.distanceTo(local);
      if (best == null || d < best.distance) best = (script: s, snap: snap, anchor: snap.anchor + s.origin, distance: d);
    }
    return best;
  }
}

/// 把宿主的所有脚本排到画布上。`margin`＝离画布左上的留白；`spacing`＝自动排时两串之间的间距。
BkCanvasLayout layoutBlockCanvas(BlockHost host, BlockLayoutEngine engine, {double margin = 16, double spacing = 28}) {
  final trees = host.scripts;
  final layouts = [for (final t in trees) engine.layoutScript(t)];
  final placed = List<BkPlaced?>.filled(trees.length, null);
  var floor = margin;
  for (var i = 0; i < trees.length; i++) {
    final x = trees[i].x, y = trees[i].y;
    if (x == null || y == null || !x.isFinite || !y.isFinite) continue;
    placed[i] = BkPlaced(id: trees[i].id, origin: Offset(x, y), layout: layouts[i], auto: false);
    floor = math.max(floor, y + layouts[i].size.height + spacing);
  }
  var right = 0.0, bottom = 0.0;
  for (var i = 0; i < trees.length; i++) {
    var p = placed[i];
    if (p == null) {
      p = BkPlaced(id: trees[i].id, origin: Offset(margin, floor), layout: layouts[i], auto: true);
      placed[i] = p;
      floor += layouts[i].size.height + spacing;
    }
    right = math.max(right, p.bounds.right);
    bottom = math.max(bottom, p.bounds.bottom);
  }
  return BkCanvasLayout([for (final p in placed) p!], Size(right + margin, bottom + margin));
}
