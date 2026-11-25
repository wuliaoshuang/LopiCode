/// 积木的色表。宿主只说“哪一类”（[BlockColorKey]），具体颜色从当前主题来（主题的“积木”一节，
/// 默认值在 lib/appearance/theme_builtin.dart）。
///
/// 每一类主题里只定一个主色，其余几档（顶部亮一点、底边深一点、槽位更深一点）在这里由主色算出来，
/// 保证同一块积木上的深浅关系一致。默认主题：积木上的字是白色，主色都压在白字对比度 4.5:1 上下；
/// 深色用压暗、降一点饱和的主色——整屏是深底，原色会刺眼。
library;

import 'dart:ui';

import 'package:lopicode/appearance/theme_builtin.dart';
import 'package:lopicode/appearance/theme_fields.dart';
import 'package:lopicode/appearance/theme_spec.dart';
import 'package:lopicode/blocks/block_host.dart';

const Color _white = Color(0xFFFFFFFF);
const Color _black = Color(0xFF000000);

/// 量字宽时用的颜色：只参与排版、不会画出来（和默认浅色主题里积木上的字同色，量出来的结果能直接给画的时候复用）。
const Color kBkMeasureInk = _white;

/// 一类积木在一种主题下的几档颜色。
class BkTone {
  const BkTone({required this.fill, required this.fillTop, required this.edge, required this.deep, required this.text, required this.fieldBg, required this.fieldText, required this.fieldHint});

  /// 主色（渐变的下端）和顶部稍亮的那一端。
  final Color fill;
  final Color fillTop;

  /// 底下那道深色边、描边。
  final Color edge;

  /// 槽位（下拉、空槽、开关）的底色：比主色深。
  final Color deep;

  /// 积木上的字。
  final Color text;

  /// 输入框：底色、字、提示字。
  final Color fieldBg;
  final Color fieldText;
  final Color fieldHint;

  /// 嵌在同色积木里时用的一套：整体提亮一点，不然两层糊在一起分不出来。
  BkTone get nested =>
      BkTone(fill: Color.lerp(fill, _white, 0.16)!, fillTop: Color.lerp(fillTop, _white, 0.16)!, edge: edge, deep: deep, text: text, fieldBg: fieldBg, fieldText: fieldText, fieldHint: fieldHint);
}

/// 一种主题下的整张色表。从当前主题（[ThemeSpec] 的“积木”一节）来：`BkPalette.fromTheme(context.themeSpec)`。
class BkPalette {
  BkPalette._(ThemeSpec t)
    : dark = t.dark,
      _tones = {
        for (final f in kBlockCategoryFields)
          f.key: _tone(
            _base(t, f.key),
            dark: t.dark,
            text: _color(t, BlockKey.text),
            fieldBg: _color(t, BlockKey.fieldBg),
            fieldText: _color(t, BlockKey.fieldText),
            fieldHint: _color(t, BlockKey.fieldHint),
          ),
      },
      selection = _color(t, BlockKey.selection),
      ghost = _color(t, BlockKey.ghost),
      shadow = _color(t, BlockKey.shadow),
      canvas = _color(t, BlockKey.canvas),
      canvasDot = _color(t, BlockKey.canvasDot),
      error = _color(t, BlockKey.error),
      warning = _color(t, BlockKey.warning),
      onError = _color(t, BlockKey.onError),
      onWarning = _color(t, BlockKey.onWarning),
      gloss = _color(t, BlockKey.gloss),
      shade = _color(t, BlockKey.shade);

  final bool dark;
  final Map<String, BkTone> _tones;

  /// 选中积木的描边。
  final Color selection;

  /// 落点阴影（拖着积木靠近可拼位置时，那里出现的影子）。
  final Color ghost;

  /// 被拖起来的积木底下的阴影。
  final Color shadow;

  /// 画布底色和上面的点阵。
  final Color canvas;
  final Color canvasDot;

  /// 有问题的积木右上角的小圆点，和圆点上的符号。
  final Color error;
  final Color warning;
  final Color onError;
  final Color onWarning;

  /// 高光（积木顶上的亮边、提示闪动）和压暗（盖在不可用积木上的那层）：只定色相，深浅各处自己给。
  final Color gloss;
  final Color shade;

  BkTone tone(String key) => _tones[key] ?? _tones[BlockColorKey.unknown]!;

  static final Expando<BkPalette> _cache = Expando();

  /// 某份主题的色表（同一份主题对象只算一次）。
  static BkPalette fromTheme(ThemeSpec theme) => _cache[theme] ??= BkPalette._(theme);

  /// 默认浅色 / 默认深色主题的色表。
  static BkPalette get light => fromTheme(kDefaultLightTheme);
  static BkPalette get darkTheme => fromTheme(kDefaultDarkTheme);

  /// 默认主题的色表（测试、不在应用主题里的地方用；界面里用 [fromTheme]）。
  static BkPalette of({required bool dark}) => dark ? darkTheme : light;
}

Color _color(ThemeSpec t, String key) => Color(t.blocks[key] ?? defaultThemeFor(dark: t.dark).blocks[key] ?? 0xFFFF00FF);

/// 一类积木的主色。
///
/// 默认深色主题的主色原本是“默认浅色的主色压暗一点”现算出来的（[_dim]），带小数；主题里存的是取整后的值。
/// 直接拿取整后的值去算其余几档，个别档会和原来差 1/255。所以主题里这一类的主色**没改过**（还等于默认深色的值）时，
/// 用原来没取整的那个数接着算，默认外观一个像素都不变；改过了就用主题里的值。
Color _base(ThemeSpec t, String key) {
  final v = t.blocks[key];
  if (t.dark && v != null && v == kDefaultDarkTheme.blocks[key]) {
    final light = kDefaultLightTheme.blocks[key];
    if (light != null) {
      final exact = _dim(Color(light));
      if (exact.toARGB32() == v) return exact;
    }
  }
  return _color(t, key);
}

/// 默认深色主题的主色是这么来的：往黑里压一点，再往自己的灰度靠一点（降饱和）。
Color _dim(Color c) {
  final grey = c.computeLuminance();
  final g = (grey * 255).round().clamp(0, 255);
  final desat = Color.lerp(c, Color.fromARGB(255, g, g, g), 0.10)!;
  return Color.lerp(desat, _black, 0.10)!;
}

/// 每一类只定一个主色，其余几档由主色算出来（算法没变）。
BkTone _tone(Color base, {required bool dark, required Color text, required Color fieldBg, required Color fieldText, required Color fieldHint}) => BkTone(
  fill: base,
  fillTop: Color.lerp(base, _white, dark ? 0.07 : 0.10)!,
  edge: Color.lerp(base, _black, dark ? 0.38 : 0.30)!,
  deep: Color.lerp(base, _black, dark ? 0.26 : 0.20)!,
  text: text,
  fieldBg: fieldBg,
  fieldText: fieldText,
  fieldHint: fieldHint,
);
