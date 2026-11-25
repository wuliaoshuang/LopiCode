/// 颜色换算和小工具（给主题编辑器的取色面板、快捷生成用）。纯 Dart，颜色都是 ARGB 整数。
///
/// - HSV：取色面板用（色相 0–360，饱和 / 明度 0–1）。
/// - HSL：生成、修对比度时用——只动“亮度”这一个数，色相和鲜艳程度不变。
/// - [parseLooseColor]：手输颜色时的宽松读法（导入文件用的是严格的 `parseThemeColor`，两者不要混）。
library;

import 'dart:math' as math;

import 'package:lopicode/appearance/theme_contrast.dart';

int _a(int c) => (c >> 24) & 0xFF;
int _r(int c) => (c >> 16) & 0xFF;
int _g(int c) => (c >> 8) & 0xFF;
int _b(int c) => c & 0xFF;

int argbOf(int a, int r, int g, int b) => ((a & 0xFF) << 24) | ((r & 0xFF) << 16) | ((g & 0xFF) << 8) | (b & 0xFF);

/// 透明度（0–255）。
int alphaOf(int argb) => _a(argb);

/// 换透明度（0–255），颜色不动。
int withAlpha(int argb, int alpha) => (argb & 0x00FFFFFF) | ((alpha.clamp(0, 255)) << 24);

/// 只比颜色、不比透明度。
bool sameRgb(int a, int b) => (a & 0x00FFFFFF) == (b & 0x00FFFFFF);

/// 色相 0–360、饱和 0–1、明度 0–1。
typedef Hsv = ({double h, double s, double v});

/// 色相 0–360、饱和 0–1、亮度 0–1。
typedef Hsl = ({double h, double s, double l});

double _hueOf(double r, double g, double b, double max, double d) {
  if (d == 0) return 0;
  double h;
  if (max == r) {
    h = ((g - b) / d) % 6;
  } else if (max == g) {
    h = (b - r) / d + 2;
  } else {
    h = (r - g) / d + 4;
  }
  h *= 60;
  return h < 0 ? h + 360 : h;
}

Hsv argbToHsv(int argb) {
  final r = _r(argb) / 255, g = _g(argb) / 255, b = _b(argb) / 255;
  final max = math.max(r, math.max(g, b)), min = math.min(r, math.min(g, b));
  final d = max - min;
  return (h: _hueOf(r, g, b, max, d), s: max == 0 ? 0 : d / max, v: max);
}

int hsvToArgb(double h, double s, double v, {int alpha = 255}) {
  final hh = (h % 360) / 60;
  final c = v * s;
  final x = c * (1 - ((hh % 2) - 1).abs());
  final m = v - c;
  final (double r, double g, double b) = switch (hh.floor()) {
    0 => (c, x, 0),
    1 => (x, c, 0),
    2 => (0, c, x),
    3 => (0, x, c),
    4 => (x, 0, c),
    _ => (c, 0, x),
  };
  int ch(double t) => ((t + m) * 255).round().clamp(0, 255);
  return argbOf(alpha, ch(r), ch(g), ch(b));
}

Hsl argbToHsl(int argb) {
  final r = _r(argb) / 255, g = _g(argb) / 255, b = _b(argb) / 255;
  final max = math.max(r, math.max(g, b)), min = math.min(r, math.min(g, b));
  final d = max - min;
  final l = (max + min) / 2;
  final s = d == 0 ? 0.0 : d / (1 - (2 * l - 1).abs());
  return (h: _hueOf(r, g, b, max, d), s: s.clamp(0.0, 1.0), l: l);
}

int hslToArgb(double h, double s, double l, {int alpha = 255}) {
  final c = (1 - (2 * l - 1).abs()) * s;
  final hh = (h % 360) / 60;
  final x = c * (1 - ((hh % 2) - 1).abs());
  final m = l - c / 2;
  final (double r, double g, double b) = switch (hh.floor()) {
    0 => (c, x, 0),
    1 => (x, c, 0),
    2 => (0, c, x),
    3 => (0, x, c),
    4 => (x, 0, c),
    _ => (c, 0, x),
  };
  int ch(double t) => ((t + m) * 255).round().clamp(0, 255);
  return argbOf(alpha, ch(r), ch(g), ch(b));
}

/// 把 [a] 往 [b] 混：[t]＝0 是 a，1 是 b。透明度跟 [a]。
int mixArgb(int a, int b, double t) {
  int ch(int x, int y) => (x + (y - x) * t).round().clamp(0, 255);
  return argbOf(_a(a), ch(_r(a), _r(b)), ch(_g(a), _g(b)), ch(_b(a), _b(b)));
}

/// 放在 [bg] 上更清楚的是黑字还是白字。
int bestOn(int bg) => contrastRatio(0xFFFFFFFF, bg) >= contrastRatio(0xFF000000, bg) ? 0xFFFFFFFF : 0xFF000000;

/// 把 [fg] 调到在每一个 [bgs] 上对比度都 ≥ [min]：只动亮度，色相和鲜艳程度不变，动得尽量少。
/// 本来就够、或者 [fg] 是半透明的（那种颜色靠透明度工作，不替它改）就原样返回；
/// 怎么调都不够（底色自己就是中灰）时退到黑或白里更清楚的那个。
int ensureContrast(int fg, List<int> bgs, double min) {
  if (bgs.isEmpty || _a(fg) != 0xFF) return fg;
  bool ok(int c) => bgs.every((b) => contrastRatio(c, b) + 0.005 >= min);
  if (ok(fg)) return fg;
  final hsl = argbToHsl(fg);
  final meanBg = bgs.map(relativeLuminance).reduce((a, b) => a + b) / bgs.length;
  // 底色偏暗就先试着调亮，偏亮先试着调暗。
  final first = meanBg < 0.4 ? 1 : -1;
  for (var i = 1; i <= 100; i++) {
    for (final dir in [first, -first]) {
      final l = hsl.l + dir * i / 100;
      if (l < 0 || l > 1) continue;
      final c = hslToArgb(hsl.h, hsl.s, l);
      if (ok(c)) return c;
    }
  }
  double worst(int c) => bgs.map((b) => contrastRatio(c, b)).reduce(math.min);
  return worst(0xFFFFFFFF) >= worst(0xFF000000) ? 0xFFFFFFFF : 0xFF000000;
}

/// 手输颜色的宽松读法。认：`#RGB`、`#RRGGBB`、`#AARRGGBB`（井号可以不写、可以是全角的 ＃，大小写随意，
/// 前后和中间的空格不管）、`0xAARRGGBB`、`rgb(r, g, b)`、`rgba(r, g, b, a)`（a 是 0–1）。读不出来返回 null。
int? parseLooseColor(String input) {
  var s = input.trim().replaceAll('＃', '#').replaceAll(RegExp(r'\s+'), '').toLowerCase();
  if (s.isEmpty) return null;
  final rgb = RegExp(r'^rgba?\((\d{1,3}),(\d{1,3}),(\d{1,3})(?:,([0-9.]+))?\)$').firstMatch(s);
  if (rgb != null) {
    final r = int.parse(rgb[1]!), g = int.parse(rgb[2]!), b = int.parse(rgb[3]!);
    final a = rgb[4] == null ? 1.0 : double.tryParse(rgb[4]!);
    if (r > 255 || g > 255 || b > 255 || a == null || a < 0 || a > 1) return null;
    return argbOf((a * 255).round(), r, g, b);
  }
  if (s.startsWith('0x')) {
    s = s.substring(2);
  } else if (s.startsWith('#')) {
    s = s.substring(1);
  }
  if (!RegExp(r'^[0-9a-f]+$').hasMatch(s)) return null;
  if (s.length == 3) s = s.split('').map((ch) => '$ch$ch').join();
  if (s.length == 6) return 0xFF000000 | int.parse(s, radix: 16);
  if (s.length == 8) return int.parse(s, radix: 16);
  return null;
}
