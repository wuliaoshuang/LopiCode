/// CSS 颜色：认不认得出、转成 0xAARRGGBB。
///
/// 单独一个文件是因为两处都要用：声明编解码要判断 `background: …` 是不是“只有一个颜色”，
/// 带类型的样式视图要把颜色交给界面画色块。
library;

import 'dart:math' as math;

/// 常见颜色名 → 0xRRGGBB。只收了数值确定的常用名；不在这里的颜色名不会被改动，只是转不成数值。
const Map<String, int> cssNamedColors = {
  'black': 0x000000,
  'silver': 0xC0C0C0,
  'gray': 0x808080,
  'grey': 0x808080,
  'white': 0xFFFFFF,
  'maroon': 0x800000,
  'red': 0xFF0000,
  'purple': 0x800080,
  'fuchsia': 0xFF00FF,
  'magenta': 0xFF00FF,
  'green': 0x008000,
  'lime': 0x00FF00,
  'olive': 0x808000,
  'yellow': 0xFFFF00,
  'navy': 0x000080,
  'blue': 0x0000FF,
  'teal': 0x008080,
  'aqua': 0x00FFFF,
  'cyan': 0x00FFFF,
  'orange': 0xFFA500,
  'pink': 0xFFC0CB,
  'gold': 0xFFD700,
  'brown': 0xA52A2A,
  'tomato': 0xFF6347,
  'coral': 0xFF7F50,
  'salmon': 0xFA8072,
  'crimson': 0xDC143C,
  'indigo': 0x4B0082,
  'violet': 0xEE82EE,
  'orchid': 0xDA70D6,
  'khaki': 0xF0E68C,
  'beige': 0xF5F5DC,
  'ivory': 0xFFFFF0,
  'lavender': 0xE6E6FA,
  'tan': 0xD2B48C,
  'skyblue': 0x87CEEB,
  'royalblue': 0x4169E1,
  'steelblue': 0x4682B4,
  'turquoise': 0x40E0D0,
  'darkgray': 0xA9A9A9,
  'darkgrey': 0xA9A9A9,
  'lightgray': 0xD3D3D3,
  'lightgrey': 0xD3D3D3,
  'dimgray': 0x696969,
  'dimgrey': 0x696969,
  'whitesmoke': 0xF5F5F5,
  'gainsboro': 0xDCDCDC,
  'darkred': 0x8B0000,
  'darkgreen': 0x006400,
  'darkblue': 0x00008B,
  'lightblue': 0xADD8E6,
  'lightgreen': 0x90EE90,
  'hotpink': 0xFF69B4,
  'slategray': 0x708090,
  'slategrey': 0x708090,
};

final RegExp _hex = RegExp(r'^#([0-9a-fA-F]{3}|[0-9a-fA-F]{4}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$');
final RegExp _colorFunction = RegExp(r'^(rgba?|hsla?|hwb|lab|lch|oklab|oklch|color|color-mix)\(.*\)$', caseSensitive: false, dotAll: true);

/// 这段文字是不是“单独一个颜色”：#十六进制、rgb()/hsl() 这类颜色函数、transparent、currentcolor、收录了的颜色名。
/// 拿不准的一律说不是（调用方就不会去动它）。
bool isCssColor(String text) {
  final t = text.trim();
  if (t.isEmpty) return false;
  if (_hex.hasMatch(t)) return true;
  final lower = t.toLowerCase();
  if (lower == 'transparent' || lower == 'currentcolor' || cssNamedColors.containsKey(lower)) return true;
  if (!_colorFunction.hasMatch(t)) return false;
  // 必须整段就是一个函数：`rgb(0,0,0) url(a.png)` 不算。
  var depth = 0;
  for (var i = 0; i < t.length; i++) {
    final c = t.codeUnitAt(i);
    if (c == 0x28) depth++;
    if (c == 0x29) {
      depth--;
      if (depth == 0 && i != t.length - 1) return false;
    }
  }
  return depth == 0;
}

/// 颜色文字 → 0xAARRGGBB。认得出 #RGB / #RGBA / #RRGGBB / #RRGGBBAA、rgb()/rgba()、hsl()/hsla()、transparent、收录了的颜色名；
/// 其他（currentcolor、var(…)、没收录的名字、写错的）返回 null。
int? cssColorToArgb(String? text) {
  if (text == null) return null;
  final t = text.trim().toLowerCase();
  if (t.isEmpty) return null;
  if (t == 'transparent') return 0x00000000;
  final named = cssNamedColors[t];
  if (named != null) return 0xFF000000 | named;
  final hex = _hex.firstMatch(t);
  if (hex != null) {
    var h = hex[1]!;
    if (h.length <= 4) h = h.split('').map((c) => '$c$c').join();
    final rgb = int.parse(h.substring(0, 6), radix: 16);
    final a = h.length == 8 ? int.parse(h.substring(6), radix: 16) : 0xFF;
    return (a << 24) | rgb;
  }
  final fn = RegExp(r'^(rgba?|hsla?)\((.*)\)$').firstMatch(t);
  if (fn == null) return null;
  // 老写法用逗号（rgb(1, 2, 3)），新写法用空格和斜杠（rgb(1 2 3 / 50%)），两种都收。
  final parts = fn[2]!.split(RegExp(r'[\s,/]+')).where((s) => s.isNotEmpty).toList();
  if (parts.length != 3 && parts.length != 4) return null;
  final alpha = parts.length == 4 ? _unit(parts[3]) : 1.0;
  if (alpha == null) return null;
  final a = (alpha.clamp(0.0, 1.0) * 255).round();
  if (fn[1]!.startsWith('rgb')) {
    final channels = <int>[];
    for (final p in parts.take(3)) {
      final v = p.endsWith('%') ? _percent(p, 255) : double.tryParse(p);
      if (v == null || v.isNaN) return null;
      channels.add(v.clamp(0, 255).round());
    }
    return (a << 24) | (channels[0] << 16) | (channels[1] << 8) | channels[2];
  }
  final hue = double.tryParse(parts[0].replaceFirst(RegExp(r'deg$'), ''));
  final s = _percent(parts[1], 1);
  final l = _percent(parts[2], 1);
  if (hue == null || hue.isNaN || hue.isInfinite || s == null || l == null) return null;
  return (a << 24) | _hslToRgb(hue, s.clamp(0.0, 1.0), l.clamp(0.0, 1.0));
}

double? _percent(String p, double scale) {
  if (!p.endsWith('%')) return null;
  final v = double.tryParse(p.substring(0, p.length - 1));
  return v == null || v.isNaN ? null : v / 100 * scale;
}

/// 透明度：`0.5` 或 `50%`。
double? _unit(String p) {
  final v = p.endsWith('%') ? _percent(p, 1) : double.tryParse(p);
  return v == null || v.isNaN ? null : v;
}

int _hslToRgb(double hue, double s, double l) {
  final h = ((hue % 360) + 360) % 360 / 60;
  final c = (1 - (2 * l - 1).abs()) * s;
  final x = c * (1 - (h % 2 - 1).abs());
  final m = l - c / 2;
  final (double r, double g, double b) = switch (h.floor()) {
    0 => (c, x, 0),
    1 => (x, c, 0),
    2 => (0, c, x),
    3 => (0, x, c),
    4 => (x, 0, c),
    _ => (c, 0, x),
  };
  int ch(double v) => math.min(255, math.max(0, ((v + m) * 255).round()));
  return (ch(r) << 16) | (ch(g) << 8) | ch(b);
}

/// 0xAARRGGBB → CSS 文字：不透明的写 `#rrggbb`，带透明度的写 `#rrggbbaa`。
String argbToCss(int argb) {
  final a = (argb >> 24) & 0xFF;
  final rgb = (argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0');
  return a == 0xFF ? '#$rgb' : '#$rgb${a.toRadixString(16).padLeft(2, '0')}';
}
