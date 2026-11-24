/// 画布排版用的数值：把一个节点“最终样式”里的 CSS 文字换算成像素、枚举这些画布能直接用的东西。
///
/// 规矩：**认不出、换算不了的一律当“没写”**（返回 null 或默认值），绝不抛异常——
/// 页面文件可能是 Agent 写的或手改的，画布不能因为一条怪样式就整页画不出来。
/// 这里只做换算，不碰界面库；怎么画在 canvas_render_widgets.dart。
library;

import 'package:lopicode/lowcode/css_color.dart';
import 'package:lopicode/lowcode/style_model.dart';

/// 画布上允许的最大像素值：再大没有意义，还会让排版数值溢出。
const double kCanvasMaxPx = 100000;

/// 换算长度要参照的东西。
class CssScale {
  const CssScale({this.fontSize = 16, this.pageWidth = 390, this.pageHeight = 844});

  /// 当前文字大小（`em` 用）。
  final double fontSize;

  /// 画布上“页面”的宽高（`vw` / `vh` 用）。
  final double pageWidth;
  final double pageHeight;

  CssScale withFont(double size) => CssScale(fontSize: size, pageWidth: pageWidth, pageHeight: pageHeight);
}

double? _finite(double v) => v.isNaN || v.isInfinite ? null : v.clamp(-kCanvasMaxPx, kCanvasMaxPx).toDouble();

/// 长度 → 像素。[percentOf] 是百分比参照的尺寸，不给（null）时百分比换算不了。
/// `auto`、`calc(…)`、`var(…)`、不认识的单位都返回 null。
double? cssPx(String? text, CssScale scale, {double? percentOf}) {
  final len = LcLength.parse(text);
  final v = len?.value;
  if (len == null || v == null) return null;
  return switch (len.unit) {
    'px' => _finite(v),
    '%' => percentOf == null || percentOf.isInfinite ? null : _finite(v * percentOf / 100),
    'em' => _finite(v * scale.fontSize),
    'rem' => _finite(v * 16),
    'vw' => _finite(v * scale.pageWidth / 100),
    'vh' => _finite(v * scale.pageHeight / 100),
    _ => null,
  };
}

/// 不能是负数的长度（尺寸、内边距、边框、间距）：负的当没写。
double? cssSizePx(String? text, CssScale scale, {double? percentOf}) {
  final v = cssPx(text, scale, percentOf: percentOf);
  return v == null || v < 0 ? null : v;
}

/// 不带单位的数字；不是数字返回 null。
double? cssNumber(String? text) {
  final v = double.tryParse(text?.trim() ?? '');
  return v == null ? null : _finite(v);
}

/// 不透明度：0–1，也认百分比写法；没写或认不出＝1。
double cssOpacity(String? text) {
  final t = text?.trim() ?? '';
  final v = t.endsWith('%') ? (double.tryParse(t.substring(0, t.length - 1)) ?? 100) / 100 : double.tryParse(t);
  if (v == null || v.isNaN) return 1;
  return v.clamp(0, 1).toDouble();
}

/// 字重 → 100–900；`normal`＝400，`bold`＝700；认不出返回 null。
int? cssFontWeight(String? text) {
  final t = text?.trim().toLowerCase();
  if (t == 'normal') return 400;
  if (t == 'bold') return 700;
  final v = int.tryParse(t ?? '');
  if (v == null || v < 1 || v > 1000) return null;
  return (((v + 50) ~/ 100) * 100).clamp(100, 900);
}

/// 行高 → 相对字号的倍数。不带单位的数字就是倍数；带单位的换算成像素再除以字号；`normal` 和认不出的返回 null。
double? cssLineHeight(String? text, CssScale scale) {
  final plain = cssNumber(text);
  if (plain != null) return plain > 0 && plain <= 20 ? plain : null;
  final px = cssPx(text, scale, percentOf: scale.fontSize);
  if (px == null || px <= 0 || scale.fontSize <= 0) return null;
  final ratio = px / scale.fontSize;
  return ratio <= 20 ? ratio : null;
}

/// 四边的像素值，顺序和 CSS 一样：上 右 下 左。
class CssEdges {
  const CssEdges(this.top, this.right, this.bottom, this.left);
  static const CssEdges zero = CssEdges(0, 0, 0, 0);

  final double top;
  final double right;
  final double bottom;
  final double left;

  bool get isZero => top == 0 && right == 0 && bottom == 0 && left == 0;
  double get horizontal => left + right;
  double get vertical => top + bottom;

  CssEdges operator +(CssEdges o) => CssEdges(top + o.top, right + o.right, bottom + o.bottom, left + o.left);

  @override
  bool operator ==(Object other) => other is CssEdges && other.top == top && other.right == right && other.bottom == bottom && other.left == left;

  @override
  int get hashCode => Object.hash(top, right, bottom, left);

  @override
  String toString() => 'CssEdges($top, $right, $bottom, $left)';
}

/// 读四边：[group] 是 `margin` / `padding`。负值、`auto`、换算不了的那一边按 0 算
/// （画布不支持负外边距和 `margin: auto` 居中，见汇报里的“近似”清单）。
/// 百分比按 CSS 的规矩都参照**宽度**（[percentOf]）。
CssEdges cssEdges(Map<String, String> style, String group, CssScale scale, {double? percentOf}) {
  double side(String s) => cssSizePx(style['$group-$s'], scale, percentOf: percentOf) ?? 0;
  return CssEdges(side('top'), side('right'), side('bottom'), side('left'));
}

/// 一条边框：宽度（像素）和颜色。
class CssBorderSide {
  const CssBorderSide(this.width, this.argb);
  final double width;

  /// 0xAARRGGBB；null＝用文字颜色（CSS 的 currentcolor）。
  final int? argb;
}

/// 读某一边的边框；这一边没有边框（没写样式、样式是 none / hidden、宽度是 0）返回 null。
/// CSS 规定边框样式默认是 none，所以只写宽度不写样式是画不出边框的，这里照做。
CssBorderSide? cssBorderSide(Map<String, String> style, String side, CssScale scale) {
  final kind = style['border-$side-style']?.trim().toLowerCase();
  if (kind == null || kind == 'none' || kind == 'hidden') return null;
  final raw = style['border-$side-width']?.trim().toLowerCase();
  final width = switch (raw) {
    null || 'medium' => 3.0,
    'thin' => 1.0,
    'thick' => 5.0,
    _ => cssSizePx(raw, scale),
  };
  if (width == null || width <= 0) return null;
  return CssBorderSide(width > 200 ? 200 : width, cssColorToArgb(style['border-$side-color']));
}

/// 四边边框占的宽度（没有边框的边是 0）。
CssEdges cssBorderWidths(Map<String, String> style, CssScale scale) {
  double w(String s) => cssBorderSide(style, s, scale)?.width ?? 0;
  return CssEdges(w('top'), w('right'), w('bottom'), w('left'));
}

/// 四角圆角（左上 右上 右下 左下）的像素值。百分比画布换算不了准确值：
/// 50% 及以上画成“尽量圆”（一个很大的半径，画的时候会被压到边长的一半），小于 50% 的忽略。
List<double> cssRadii(Map<String, String> style, CssScale scale) {
  double corner(String c) {
    final text = style['border-$c-radius'];
    final len = LcLength.parse(text);
    if (len != null && len.unit == '%') return (len.value ?? 0) >= 50 ? 9999 : 0;
    // `10px 20px` 这种椭圆角只取第一个值。
    final first = text?.trim().split(RegExp(r'\s+')).first;
    return cssSizePx(first, scale) ?? 0;
  }

  return [corner('top-left'), corner('top-right'), corner('bottom-right'), corner('bottom-left')];
}

/// 单层外阴影的像素值。多层、内阴影（inset）、认不出的返回 null（画布不画）。
class CssShadowPx {
  const CssShadowPx(this.x, this.y, this.blur, this.spread, this.argb);
  final double x;
  final double y;
  final double blur;
  final double spread;
  final int? argb;
}

CssShadowPx? cssShadow(Map<String, String> style, CssScale scale) {
  final s = LcShadow.parse(style['box-shadow']);
  if (s == null || s.inset) return null;
  final x = cssPx(s.x.toCss(), scale), y = cssPx(s.y.toCss(), scale);
  final blur = cssSizePx(s.blur.toCss(), scale) ?? 0;
  final spread = cssPx(s.spread.toCss(), scale) ?? 0;
  if (x == null || y == null) return null;
  return CssShadowPx(x, y, blur > 500 ? 500 : blur, spread.clamp(-500, 500).toDouble(), cssColorToArgb(s.color));
}

/// 主轴怎么分布。
enum CssJustify { start, center, end, between, around, evenly }

/// 交叉轴怎么对齐。
enum CssAlign { start, center, end, stretch }

CssJustify? cssJustify(String? text) => switch (text?.trim().toLowerCase()) {
  'flex-start' || 'start' || 'left' || 'normal' => CssJustify.start,
  'center' => CssJustify.center,
  'flex-end' || 'end' || 'right' => CssJustify.end,
  'space-between' => CssJustify.between,
  'space-around' => CssJustify.around,
  'space-evenly' => CssJustify.evenly,
  _ => null,
};

/// `baseline` 画布按起点画；`auto`、认不出的返回 null。
CssAlign? cssAlign(String? text) => switch (text?.trim().toLowerCase()) {
  'flex-start' || 'start' || 'baseline' => CssAlign.start,
  'center' => CssAlign.center,
  'flex-end' || 'end' => CssAlign.end,
  'stretch' => CssAlign.stretch,
  _ => null,
};

/// 容器的排列方式。
class CssFlow {
  const CssFlow({required this.row, required this.reverse, required this.wrap});

  /// 横着排（否则竖着排）。
  final bool row;
  final bool reverse;
  final bool wrap;
}

/// [rowByDefault]：这个容器类型本来是不是横排（“行”是，其余都是竖排）。
CssFlow cssFlow(Map<String, String> style, {required bool rowByDefault}) {
  final dir = style['flex-direction']?.trim().toLowerCase();
  final row = switch (dir) {
    'row' || 'row-reverse' => true,
    'column' || 'column-reverse' => false,
    _ => rowByDefault,
  };
  final wrap = style['flex-wrap']?.trim().toLowerCase();
  return CssFlow(row: row, reverse: dir == 'row-reverse' || dir == 'column-reverse', wrap: wrap == 'wrap' || wrap == 'wrap-reverse');
}

/// 一个节点的盒子尺寸（像素）。哪一项是 null 就是没设 / 换算不了。
class CssBoxSize {
  const CssBoxSize({this.width, this.height, this.minWidth, this.maxWidth, this.minHeight, this.maxHeight});
  final double? width;
  final double? height;
  final double? minWidth;
  final double? maxWidth;
  final double? minHeight;
  final double? maxHeight;

  bool get isEmpty => width == null && height == null && minWidth == null && maxWidth == null && minHeight == null && maxHeight == null;
}

/// [availWidth] / [availHeight]：父容器内容区的宽高（百分比的参照）；高度不知道就传 null，
/// 这时百分比高度不生效（和浏览器里父容器高度是 auto 时一样）。
/// 最小值比最大值大时以最小值为准（CSS 的规矩）。
CssBoxSize cssBoxSize(Map<String, String> style, CssScale scale, {required double? availWidth, double? availHeight}) {
  double? w(String name) => cssSizePx(style[name], scale, percentOf: availWidth);
  double? h(String name) => cssSizePx(style[name], scale, percentOf: availHeight);
  final minW = w('min-width'), minH = h('min-height');
  var maxW = w('max-width'), maxH = h('max-height');
  if (minW != null && maxW != null && maxW < minW) maxW = minW;
  if (minH != null && maxH != null && maxH < minH) maxH = minH;
  return CssBoxSize(width: w('width'), height: h('height'), minWidth: minW == 0 ? null : minW, maxWidth: maxW, minHeight: minH == 0 ? null : minH, maxHeight: maxH);
}

/// `overflow` 是不是要裁掉超出的部分（hidden / clip；scroll 和 auto 画布上也按裁掉画）。
bool cssClips(Map<String, String> style) {
  bool clip(String? v) => const {'hidden', 'clip', 'scroll', 'auto'}.contains(v?.trim().toLowerCase());
  return clip(style['overflow-x']) || clip(style['overflow-y']) || clip(style['overflow']);
}

/// 装饰线：underline / line-through / overline 可以同时有几个。`text-decoration` 简写里的颜色、线型忽略。
Set<String> cssDecorationLines(Map<String, String> style) {
  final text = '${style['text-decoration-line'] ?? ''} ${style['text-decoration'] ?? ''}'.toLowerCase();
  return {
    for (final k in const ['underline', 'line-through', 'overline'])
      if (text.contains(k)) k,
  };
}

/// 相对定位的平移量（像素）：`left` 优先于 `right`，`top` 优先于 `bottom`。
({double dx, double dy}) cssRelativeShift(Map<String, String> style, CssScale scale, {double? availWidth, double? availHeight}) {
  final left = cssPx(style['left'], scale, percentOf: availWidth), right = cssPx(style['right'], scale, percentOf: availWidth);
  final top = cssPx(style['top'], scale, percentOf: availHeight), bottom = cssPx(style['bottom'], scale, percentOf: availHeight);
  return (dx: left ?? (right == null ? 0 : -right), dy: top ?? (bottom == null ? 0 : -bottom));
}

/// 拖柄改尺寸：从起始宽高和手指位移算出新的宽高（取整，不小于 [min]）。
/// [hx] / [hy] 是拖柄在哪一侧：-1＝左 / 上，0＝中间（这个方向不变），1＝右 / 下。
/// 返回里哪一项是 null 就是这个方向没动。
({int? width, int? height}) resizeByHandle({required double startWidth, required double startHeight, required double dx, required double dy, required int hx, required int hy, double min = 8}) {
  int? side(double start, double delta, int h) {
    if (h == 0) return null;
    final v = start + delta * h;
    return (v.isNaN ? start : v.clamp(min, kCanvasMaxPx)).round();
  }

  return (width: side(startWidth, dx, hx), height: side(startHeight, dy, hy));
}
