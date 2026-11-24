/// 让位动画的纯逻辑：积木从“现在看到的位置”滑到“新排布里的位置”，每一帧该画在哪。
///
/// 不带界面，不排版：两头的位置都来自已经排好的 [BkCanvasLayout]，这里只做“认出同一块积木”和插值。
/// 界面那一层（block_editor_drag_view.dart）只管给一个 0–1 的进度。
///
/// 怎么认同一块积木：拖动期间所有排布都是“拿走以后的排布（base）”加上“某处让出一截”得来的，
/// 所以把让出来的那一截抠掉、后面的下标减回去，得到的路径在整个拖动期间不变——拿它当名字。
/// 让出来的那一截（落点阴影）没有名字：它不滑，只淡入。
///
/// 一块积木会变的只有三样：整块的位置、（C 形块）每个口的大小、口上横栏的位置。记成 [BkFrame]，都是画布坐标
/// （别的脚本被往下推时，整串的原点也在动，所以不能用脚本自己的坐标）。
library;

import 'dart:ui';

import 'package:lopicode/blocks/block_canvas_layout.dart';
import 'package:lopicode/blocks/block_geometry.dart';
import 'package:lopicode/lowcode/logic_model.dart';

/// 让出来的一截：哪一串、哪一列（`parent` + `inElse`）、从第几块起、一共几块。
typedef BkRoom = ({String scriptId, LcBlockPath parent, bool inElse, int start, int count});

/// 一块积木会跟着让位变的那部分外形（画布坐标）。
class BkFrame {
  const BkFrame(this.rect, [this.mouths = const [], this.bars = const []]);

  factory BkFrame.of(BkBlock b, Offset origin) =>
      BkFrame(b.rect.shift(origin), b.mouths.isEmpty ? const [] : [for (final m in b.mouths) m.rect.shift(origin)], b.mouths.isEmpty ? const [] : [for (final m in b.mouths) m.bar?.shift(origin)]);

  final Rect rect;
  final List<Rect> mouths;
  final List<Rect?> bars;

  static bool _near(double a, double b) => (a - b).abs() < 0.01;
  static bool _nearRect(Rect a, Rect b) => _near(a.left, b.left) && _near(a.top, b.top) && _near(a.right, b.right) && _near(a.bottom, b.bottom);

  /// 位置、形状都一样（不用动）。
  bool sameAs(BkFrame o) {
    if (!_nearRect(rect, o.rect) || mouths.length != o.mouths.length) return false;
    for (var i = 0; i < mouths.length; i++) {
      if (!_nearRect(mouths[i], o.mouths[i])) return false;
    }
    return true;
  }

  /// 只是整块挪了位置、形状没变（画的时候平移就行，不用重造轮廓）。
  bool sameShapeAs(BkFrame o) {
    if (!_near(rect.width, o.rect.width) || !_near(rect.height, o.rect.height) || mouths.length != o.mouths.length) return false;
    final d = o.rect.topLeft - rect.topLeft;
    for (var i = 0; i < mouths.length; i++) {
      if (!_nearRect(mouths[i].shift(d), o.mouths[i])) return false;
    }
    return true;
  }

  BkFrame shift(Offset d) => BkFrame(rect.shift(d), mouths.isEmpty ? const [] : [for (final m in mouths) m.shift(d)], bars.isEmpty ? const [] : [for (final b in bars) b?.shift(d)]);

  /// 两头之间的样子。口的个数对不上（不该发生）就直接是终点。
  static BkFrame lerp(BkFrame a, BkFrame b, double t) {
    if (t <= 0) return a;
    if (t >= 1 || a.mouths.length != b.mouths.length) return b;
    return BkFrame(
      Rect.lerp(a.rect, b.rect, t)!,
      [for (var i = 0; i < b.mouths.length; i++) Rect.lerp(a.mouths[i], b.mouths[i], t)!],
      [for (var i = 0; i < b.bars.length; i++) b.bars[i] == null ? null : Rect.lerp(a.bars[i] ?? b.bars[i], b.bars[i], t)],
    );
  }
}

/// 把“让出一截以后”的路径换回“没让之前”的路径。落在让出来的那一截里（落点阴影）返回 null。
LcBlockPath? bkPathBeforeRoom(LcBlockPath p, BkRoom? room) {
  if (room == null) return p;
  final n = room.parent.length;
  if (p.length <= n || !bkSameBlockPath(room.parent, p.sublist(0, n))) return p;
  final step = p[n];
  if (n > 0 && step.inElse != room.inElse) return p;
  if (step.index < room.start) return p;
  if (step.index < room.start + room.count) return null;
  return [...p.sublist(0, n), lcStep(step.index - room.count, inElse: step.inElse), ...p.sublist(n + 1)];
}

/// 一块积木在整个拖动期间不变的名字。
String bkMotionKey(String scriptId, LcBlockPath path, {bool hat = false}) {
  if (hat) return '$scriptId#';
  final sb = StringBuffer(scriptId)..write('/');
  for (var i = 0; i < path.length; i++) {
    sb
      ..write(i > 0 && path[i].inElse ? 'e' : 'b')
      ..write(path[i].index)
      ..write('.');
  }
  return sb.toString();
}

/// 让位到一半 / 让完以后，落下的那一下缩放：先比原大大一点（刚才还在手上），压下去一点，再回到原大。
/// `t` 是 0–1 的进度。1.04 → 0.98 → 1.0。
double bkLandScale(double t) {
  if (t <= 0) return 1.04;
  if (t >= 1) return 1;
  if (t < 0.55) {
    final k = t / 0.55;
    return 1.04 + (0.98 - 1.04) * (1 - (1 - k) * (1 - k));
  }
  final k = (t - 0.55) / 0.45;
  return 0.98 + 0.02 * (k * k * (3 - 2 * k));
}

/// 从“现在看到的样子”滑到新排布。
class BkMotion {
  Map<String, BkFrame> _rest = const {};
  Map<BkBlock, ({BkFrame from, BkFrame to, String key})> _moves = Map.identity();
  Map<String, BkFrame> _fromByKey = const {};

  /// 有没有积木需要滑（没有就不用起动画）。
  bool get moving => _moves.isNotEmpty;

  /// 需要滑的积木有几块（测试、性能冒烟用）。
  int get moveCount => _moves.length;

  static Map<String, (BkBlock, BkFrame)> _frames(BkCanvasLayout layout, BkRoom? room) {
    final out = <String, (BkBlock, BkFrame)>{};
    for (final s in layout.scripts) {
      final r = room != null && room.scriptId == s.id ? room : null;
      for (final b in s.layout.blocks) {
        final path = b.isHat ? b.path : bkPathBeforeRoom(b.path, r);
        if (path == null) continue;
        out[bkMotionKey(s.id, path, hat: b.isHat)] = (b, BkFrame.of(b, s.origin));
      }
    }
    return out;
  }

  /// 直接摆成这个排布，不滑。
  void jump(BkCanvasLayout layout, {BkRoom? room}) {
    _rest = {for (final e in _frames(layout, room).entries) e.key: e.value.$2};
    _moves = Map.identity();
    _fromByKey = const {};
  }

  /// 换一个要去的排布。`progress`＝上一段滑到哪了（0–1，已经过了缓动）：新的一段从那时看到的位置接着走，不会跳。
  void retarget(BkCanvasLayout layout, {BkRoom? room, double progress = 1}) {
    final next = _frames(layout, room);
    final moves = Map<BkBlock, ({BkFrame from, BkFrame to, String key})>.identity();
    final fromByKey = <String, BkFrame>{};
    for (final e in next.entries) {
      final seen = _seen(e.key, progress);
      final to = e.value.$2;
      if (seen == null || seen.sameAs(to)) continue;
      moves[e.value.$1] = (from: seen, to: to, key: e.key);
      fromByKey[e.key] = seen;
    }
    _rest = {for (final e in next.entries) e.key: e.value.$2};
    _moves = moves;
    _fromByKey = fromByKey;
  }

  /// 上一段里，这块积木在进度 `progress` 时看起来在哪。
  BkFrame? _seen(String key, double progress) {
    final to = _rest[key];
    if (to == null) return null;
    final from = _fromByKey[key];
    return from == null ? to : BkFrame.lerp(from, to, progress);
  }

  /// 这块积木（必须是最近一次 [retarget] 给的排布里的）在进度 `t` 时该画在哪；不用动的返回 null。
  BkFrame? frameOf(BkBlock b, double t) {
    if (_moves.isEmpty || t >= 1) return null;
    final m = _moves[b];
    return m == null ? null : BkFrame.lerp(m.from, m.to, t);
  }

  /// 按名字查（测试用）：进度 `t` 时在哪。
  BkFrame? frameByKey(String key, double t) => _seen(key, t);
}
