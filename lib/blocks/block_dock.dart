/// 积木盒面板“停在多高”的纯逻辑：三档的高度、拖动时不出界、松手后停在哪、同一次运行里记住上次停在哪。
///
/// 不带界面。高度都是“面板上沿到编辑区下沿”的距离；面板最高能顶到状态栏下沿（盖住页面顶栏），
/// 最低只剩手柄那一条。
library;

import 'dart:math' as math;

/// 三档：收起（只剩手柄条）/ 默认 / 全展开（顶到状态栏下沿）。
enum BkDockStop { collapsed, normal, full }

/// 一次排好的三档高度。
class BkDockStops {
  const BkDockStops({required this.collapsed, required this.normal, required this.full});

  /// `handle`＝手柄条多高；`normal`＝默认档想要多高；`area`＝状态栏下沿到编辑区下沿一共多高；
  /// `bottomInset`＝屏幕底部系统手势条占的高度（手柄条要露在它上面）。地方不够时三档互相挤，但始终 收起 ≤ 默认 ≤ 全展开。
  factory BkDockStops.of({required double handle, required double normal, required double area, double bottomInset = 0}) {
    final full = math.max(0.0, area);
    final collapsed = math.min(handle + bottomInset, full);
    return BkDockStops(collapsed: collapsed, normal: (normal + bottomInset).clamp(collapsed, full).toDouble(), full: full);
  }

  final double collapsed;
  final double normal;
  final double full;

  double of(BkDockStop stop) => switch (stop) {
    BkDockStop.collapsed => collapsed,
    BkDockStop.normal => normal,
    BkDockStop.full => full,
  };

  /// 拖动时：不许拖出界。
  double clamp(double height) => height.clamp(collapsed, full).toDouble();

  /// 离哪一档最近。
  BkDockStop nearest(double height) {
    var best = BkDockStop.collapsed;
    for (final s in BkDockStop.values) {
      if ((of(s) - height).abs() < (of(best) - height).abs()) best = s;
    }
    return best;
  }

  /// 松手以后去哪一档。`velocity`＝手指松开时的速度（每秒多少像素，往下为正）。
  /// 甩得够快（≥ [flingSpeed]）：往甩的方向去下一档（从手现在的位置算，不跳档）；否则去最近的一档。
  BkDockStop settle(double height, double velocity) {
    if (velocity.abs() < flingSpeed) return nearest(height);
    if (velocity < 0) {
      // 往上甩：比现在高的里面最矮的那一档。
      for (final s in BkDockStop.values) {
        if (of(s) > height + _eps) return s;
      }
      return BkDockStop.full;
    }
    for (final s in BkDockStop.values.reversed) {
      if (of(s) < height - _eps) return s;
    }
    return BkDockStop.collapsed;
  }

  /// 松手以后停在多高。甩得够快：去甩的方向上的下一档；否则离某一档不到 [magnet] 就吸过去，不然就停在手放开的地方。
  double rest(double height, double velocity) {
    final h = clamp(height);
    if (velocity.abs() >= flingSpeed) return of(settle(h, velocity));
    final near = of(nearest(h));
    return (near - h).abs() <= magnet ? near : h;
  }

  /// 点一下手柄以后去多高：收起着就回默认；比默认高就回默认；其余（默认或更矮）收起。
  double toggled(double height) => height <= collapsed + _eps || height > normal + _eps ? normal : collapsed;

  bool isCollapsed(double height) => height <= collapsed + _eps;
  bool isFull(double height) => full > normal + _eps && height >= full - _eps;

  /// 离一档多近算“吸过去”。
  static const double magnet = 28;

  static const double flingSpeed = 700;
  static const double _eps = 1;
}

/// 同一次运行里记住每个编辑器的面板停在多高（离开页面再回来还在那里）。不落盘：重新打开应用回到默认档。
///
/// 只是界面上的一点记性，没人订阅它，所以不是 provider；编辑器本身不认识应用状态（测试里常常单独摆出来）。
/// `full`＝停在全展开（屏幕高度变了也跟着顶到头）。
class BkDockMemory {
  BkDockMemory._();

  static final Map<String, ({double height, bool full})> _seen = {};

  static ({double height, bool full})? of(String? key) => key == null ? null : _seen[key];

  static void remember(String? key, double height, {required bool full}) {
    if (key != null) _seen[key] = (height: height, full: full);
  }

  /// 测试收尾用。
  static void clear() => _seen.clear();
}
