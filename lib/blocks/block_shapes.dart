/// 积木的外形：帽子、语句块、C / E 形块、表达式块（胶囊 / 六边形）各自的轮廓。只造 Path，不上色。
///
/// 外形是自己设计的：凹口和凸起是一个带小圆角的梯形“榫头”，位置和尺寸都从 [BkMetrics] 取，
/// 所以上一块的凸起一定落进下一块的凹口。帽子左上有一个圆顶。
library;

import 'dart:math' as math;
import 'dart:ui';

import 'package:lopicode/blocks/block_geometry.dart';

/// 从路径现在的位置出发，依次走过 `pts`，中间的拐角按 `radii` 修圆（最后一个点直接连过去）。
/// `pts[0]` 必须就是路径现在所在的点。
void _polyline(Path p, List<Offset> pts, List<double> radii) {
  for (var i = 1; i < pts.length - 1; i++) {
    final a = pts[i - 1], c = pts[i], b = pts[i + 1];
    final r = radii[i];
    final la = (a - c).distance, lb = (b - c).distance;
    if (r <= 0 || la == 0 || lb == 0) {
      p.lineTo(c.dx, c.dy);
      continue;
    }
    final da = math.min(r, la / 2), db = math.min(r, lb / 2);
    final p1 = c + (a - c) / la * da, p2 = c + (b - c) / lb * db;
    p.lineTo(p1.dx, p1.dy);
    p.quadraticBezierTo(c.dx, c.dy, p2.dx, p2.dy);
  }
  p.lineTo(pts.last.dx, pts.last.dy);
}

/// 一圈封闭的多边形，每个角按 `radii` 修圆。
Path _polygon(List<Offset> pts, List<double> radii) {
  final start = (pts[0] + pts[1]) / 2;
  final p = Path()..moveTo(start.dx, start.dy);
  _polyline(p, [start, ...pts.sublist(1), pts[0], start], [0, ...radii.sublist(1), radii[0], 0]);
  return p..close();
}

/// 一组带圆角的点。
class _Pts {
  final List<Offset> pts = [];
  final List<double> radii = [];
  void add(double x, double y, double r) {
    pts.add(Offset(x, y));
    radii.add(r);
  }

  /// 朝下的榫头（上边的凹口、下边的凸起都是它），从 `x` 往右走；`reverse`＝从右往左走。
  void tab(double x, double y, BkMetrics m, {bool reverse = false}) {
    const r = 1.8;
    final xs = [x + m.notchX, x + m.notchX + m.notchSlope, x + m.notchX + m.notchW - m.notchSlope, x + m.notchX + m.notchW];
    final ys = [y, y + m.notchD, y + m.notchD, y];
    for (var i = 0; i < 4; i++) {
      final k = reverse ? 3 - i : i;
      add(xs[k], ys[k], r);
    }
  }
}

/// 语句块：上边有凹口，下边有凸起。
Path bkStackPath(Rect r, BkMetrics m, {bool notch = true, bool bump = true}) {
  final c = m.corner;
  final q = _Pts()..add(r.left, r.top, c);
  if (notch) q.tab(r.left, r.top, m);
  q
    ..add(r.right, r.top, c)
    ..add(r.right, r.bottom, c);
  if (bump) q.tab(r.left, r.bottom, m, reverse: true);
  q.add(r.left, r.bottom, c);
  return _polygon(q.pts, q.radii);
}

/// 帽子块：左上一个圆顶（顶在 `r.top`，平的那段在 `r.top + hatDome`），下边有凸起。
Path bkHatPath(Rect r, BkMetrics m) {
  final c = m.corner;
  final flat = r.top + m.hatDome;
  final dw = math.min(m.hatDomeW, r.width - c * 2);
  final p = Path()..moveTo(r.left, flat + c);
  p.cubicTo(r.left, flat - m.hatDome * 0.9, r.left + dw * 0.22, r.top, r.left + dw * 0.5, r.top);
  p.cubicTo(r.left + dw * 0.78, r.top, r.left + dw * 0.86, flat, r.left + dw, flat);
  final q = _Pts()
    ..add(r.left + dw, flat, 0)
    ..add(r.right, flat, c)
    ..add(r.right, r.bottom, c)
    ..tab(r.left, r.bottom, m, reverse: true)
    ..add(r.left, r.bottom, c)
    ..add(r.left, flat + c, 0);
  _polyline(p, q.pts, q.radii);
  return p..close();
}

/// C / E 形块：`head` 是上面写字的那条，`mouths` 是一个或两个口，`rect` 是整块。
Path bkMouthPath(BkBlock b, BkMetrics m, {bool notch = true, bool bump = true}) {
  final c = m.corner;
  final r = b.rect;
  final q = _Pts()..add(r.left, r.top, c);
  if (notch) q.tab(r.left, r.top, m);
  q.add(r.right, r.top, c);
  for (final mouth in b.mouths) {
    final o = mouth.rect;
    // 口的上沿：从右往左，带一个往下的凸起（口里第一块的凹口接它）。
    q
      ..add(r.right, o.top, c)
      ..tab(o.left, o.top, m, reverse: true)
      ..add(o.left, o.top, c)
      // 口的下沿：从左往右，带一个凹口（口里最后一块的凸起落进来）。
      ..add(o.left, o.bottom, c)
      ..tab(o.left, o.bottom, m)
      ..add(r.right, o.bottom, c);
  }
  q.add(r.right, r.bottom, c);
  if (bump) q.tab(r.left, r.bottom, m, reverse: true);
  q.add(r.left, r.bottom, c);
  return _polygon(q.pts, q.radii);
}

/// 一块积木的轮廓（按它的形状挑上面三种之一）。
Path bkBlockPath(BkBlock b, BkMetrics m) => switch (b.shape) {
  BkShape.hat => bkHatPath(b.rect, m),
  BkShape.mouth => bkMouthPath(b, m),
  _ => bkStackPath(b.rect, m),
};

/// 胶囊（表达式块、输入框、下拉）：两头是半圆；很高（多行）时圆角封顶，不然像个大圆球。
Path bkPillPath(Rect r, {double maxRadius = 14}) => Path()..addRRect(RRect.fromRectAndRadius(r, Radius.circular(math.min(r.height / 2, maxRadius))));

/// 六边形（“是 / 否”的表达式和槽）：两头是尖角。
Path bkHexPath(Rect r, BkMetrics m) {
  final tip = math.min(m.hexTip, r.height / 2);
  final cy = r.center.dy;
  return _polygon(
    [Offset(r.left + tip, r.top), Offset(r.right - tip, r.top), Offset(r.right, cy), Offset(r.right - tip, r.bottom), Offset(r.left + tip, r.bottom), Offset(r.left, cy)],
    const [2.5, 2.5, 1.5, 2.5, 2.5, 1.5],
  );
}

/// 槽位 / 表达式块的轮廓。
Path bkSlotPath(Rect r, BkMetrics m, {required bool hex}) => hex ? bkHexPath(r, m) : bkPillPath(r);
