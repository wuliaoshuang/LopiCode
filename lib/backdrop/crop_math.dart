// 背景图片的裁剪数学（纯计算，不碰界面）。
//
// 裁剪区域用“相对图片的归一化矩形”表示（左、上、宽、高都在 0–1 之间），所以换屏幕尺寸、换解码分辨率都不坏。
// 这里的“图片”一律指**旋转之后**的样子（旋转 90° 后宽高互换）。
//
// 手感的约定（裁剪页照这个做）：选框固定在屏幕中间、比例＝手机屏幕；图片在选框下面被单指拖动、双指缩放。
// 所以这里只有两个动作：[CropMath.pan]（挪）和 [CropMath.zoom]（围绕一个点放大缩小），外加各种“夹回合法范围”。
import 'dart:math' as math;

/// 最多能放大多少倍（相对“选框刚好装下的最大区域”）。
const double kCropMaxZoom = 8;

/// 归一化的裁剪矩形。
class CropRect {
  const CropRect(this.left, this.top, this.width, this.height);

  /// 整张图。
  static const CropRect full = CropRect(0, 0, 1, 1);

  final double left;
  final double top;
  final double width;
  final double height;

  double get right => left + width;
  double get bottom => top + height;
  double get centerX => left + width / 2;
  double get centerY => top + height / 2;

  Map<String, dynamic> toJson() => {'l': left, 't': top, 'w': width, 'h': height};

  /// 从存盘读：类型不对、不是有限数、跑出 0–1 的都回退成整张图（之后由 [CropMath.refit] 按比例收好）。
  static CropRect fromJson(Object? j) {
    if (j is! Map) return full;
    double? n(Object? v) => v is num && v.isFinite ? v.toDouble() : null;
    final l = n(j['l']), t = n(j['t']), w = n(j['w']), h = n(j['h']);
    if (l == null || t == null || w == null || h == null) return full;
    if (w <= 0 || h <= 0 || l < -1e-6 || t < -1e-6 || l + w > 1 + 1e-6 || t + h > 1 + 1e-6) return full;
    return CropRect(l.clamp(0.0, 1.0), t.clamp(0.0, 1.0), w.clamp(0.0, 1.0), h.clamp(0.0, 1.0));
  }

  @override
  bool operator ==(Object other) => other is CropRect && other.left == left && other.top == top && other.width == width && other.height == height;

  @override
  int get hashCode => Object.hash(left, top, width, height);

  @override
  String toString() => 'CropRect(${left.toStringAsFixed(4)}, ${top.toStringAsFixed(4)}, ${width.toStringAsFixed(4)}, ${height.toStringAsFixed(4)})';
}

/// 一张（旋转后）宽 [imageWidth]、高 [imageHeight] 的图，配一个宽高比为 [aspect]（宽 ÷ 高）的选框。
class CropMath {
  CropMath({required double imageWidth, required double imageHeight, required double aspect})
    : imageWidth = imageWidth > 0 ? imageWidth : 1,
      imageHeight = imageHeight > 0 ? imageHeight : 1,
      aspect = aspect.isFinite && aspect > 0 ? aspect : 9 / 19.5;

  final double imageWidth;
  final double imageHeight;
  final double aspect;

  /// 选框比例换算到归一化坐标里：归一化宽 ÷ 归一化高。
  double get _normAspect => aspect * imageHeight / imageWidth;

  /// 不放大时（zoom＝1）的区域大小：比例对、且刚好不超出图片的最大矩形。
  (double, double) get maxSize {
    final a = _normAspect;
    return a >= 1 ? (1.0, 1 / a) : (a, 1.0);
  }

  /// 一开始的区域：居中、最大。
  CropRect initial() {
    final (w, h) = maxSize;
    return CropRect((1 - w) / 2, (1 - h) / 2, w, h);
  }

  /// 现在放大了多少倍（1＝最大区域）。
  double zoomOf(CropRect r) => (maxSize.$1 / r.width).clamp(1.0, kCropMaxZoom);

  /// 把任意矩形收成合法的：比例对、大小在范围内、不出图片。中心尽量不动。
  ///
  /// 存下来的区域是按当时的屏幕比例裁的；换了屏幕（比例不同）再打开时用它收一下。
  CropRect refit(CropRect r) {
    final (mw, mh) = maxSize;
    // 以原区域的“覆盖范围”为准：取能包住原区域高度的那个大小，再夹进允许的缩放范围
    var w = math.max(r.width, r.height * _normAspect);
    w = w.clamp(mw / kCropMaxZoom, mw);
    final h = w / _normAspect;
    return _clampInside(r.centerX - w / 2, r.centerY - h / 2, w, math.min(h, mh));
  }

  /// 挪：[dx]、[dy] 是区域在图片上移动的归一化距离（手指往右拖图片 ⇒ 区域往左，调用方自己取负）。
  CropRect pan(CropRect r, double dx, double dy) => _clampInside(r.left + dx, r.top + dy, r.width, r.height);

  /// 缩放到 [zoom] 倍（1–[kCropMaxZoom]），保持图片上的点（[focalX]、[focalY]，归一化）在选框里的相对位置不变。
  /// 不传焦点就围绕区域中心。
  CropRect zoomTo(CropRect r, double zoom, {double? focalX, double? focalY}) {
    final (mw, _) = maxSize;
    final z = zoom.isFinite ? zoom.clamp(1.0, kCropMaxZoom) : 1.0;
    final w = mw / z;
    final h = w / _normAspect;
    final fx = focalX ?? r.centerX;
    final fy = focalY ?? r.centerY;
    // 焦点在旧区域里的相对位置
    final u = r.width == 0 ? 0.5 : ((fx - r.left) / r.width).clamp(0.0, 1.0);
    final v = r.height == 0 ? 0.5 : ((fy - r.top) / r.height).clamp(0.0, 1.0);
    return _clampInside(fx - u * w, fy - v * h, w, h);
  }

  /// 在现在的倍数上乘 [factor]（双指捏合：两指距离之比）。
  CropRect zoomBy(CropRect r, double factor, {double? focalX, double? focalY}) => zoomTo(r, zoomOf(r) * (factor.isFinite && factor > 0 ? factor : 1), focalX: focalX, focalY: focalY);

  CropRect _clampInside(double l, double t, double w, double h) {
    final cw = w.clamp(0.0, 1.0);
    final ch = h.clamp(0.0, 1.0);
    return CropRect(l.clamp(0.0, 1 - cw), t.clamp(0.0, 1 - ch), cw, ch);
  }
}
