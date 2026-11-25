/// 快捷生成：换强调色、从一个主色生成整套、把对比度不够的项调到达标。纯 Dart，算法说明见
/// docs/themes-design.md 的“主题编辑器与导入导出界面 › 生成算法”。
///
/// 三个函数都只返回一份新的主题，不存盘；存不存由编辑器决定（都能撤销）。
library;

import 'package:lopicode/appearance/theme_builtin.dart';
import 'package:lopicode/appearance/theme_color_math.dart';
import 'package:lopicode/appearance/theme_contrast.dart';
import 'package:lopicode/appearance/theme_edit_model.dart';
import 'package:lopicode/appearance/theme_fields.dart';
import 'package:lopicode/appearance/theme_spec.dart';

/// 强调色浅底里强调色占多少（其余是卡片色）。
const double kAccentSoftMixLight = 0.12;
const double kAccentSoftMixDark = 0.28;

/// 饱和度低于这个数的颜色算“中性色”（底色、文字、边线这些），生成整套时跟着底色倾向走。
const double kNeutralSaturation = 0.25;

/// 底色倾向给中性色加多少饱和：很亮的 / 很暗的 / 中间的。再乘上用户选的那个颜色自己的鲜艳程度。
const double kTintOnLight = 0.55;
const double kTintOnDark = 0.35;
const double kTintOnMid = 0.2;

/// 跟着“换强调色”一起走的固定几项（另外：凡是原来和旧强调色、旧浅底同色的项也跟着换）。
/// 白字放在强调色上的对比度到这个数，就坚持用白字（再把按钮底压深到 4.5:1）。
const double kOnAccentKeepWhite = 3.0;

const List<String> kAccentFamily = ['ui.accent', 'ui.accentFill', 'ui.onAccent', 'ui.accentSoft', 'ui.selectedBg'];

/// 换强调色：重算强调色这一组，并把原来和旧强调色 / 旧实心按钮底 / 旧浅底同色的项一起换掉（各自的透明度不变）。
///
/// - 实心按钮底＝[accent] 本身；上面的字：白字已有 3:1 就用白，否则取黑白里更清楚的；还不到 4.5:1 就把按钮底的亮度挪一挪。
/// - 强调色浅底＝[accent] 混进卡片色（浅色主题混 12%，深色 28%）；选中项的底同它。
/// - 强调色（文字、图标）＝[accent] 调亮度，直到在主页面底色、卡片、浅底上都 ≥ 4.5:1。
ThemeSpec reaccentTheme(ThemeSpec t, int accent) {
  final a0 = withAlpha(accent, 255);
  final ui = t.ui;
  final oldAccent = ui[UiKey.accent], oldFill = ui[UiKey.accentFill], oldSoft = ui[UiKey.accentSoft], oldSelected = ui[UiKey.selectedBg];
  final surface = ui[UiKey.surface] ?? (t.dark ? 0xFF1E1F25 : 0xFFFFFFFF);
  final bg = ui[UiKey.bg] ?? surface;

  // 不太浅的强调色（白字在上面已有 3:1）一律配白字、把按钮底压深一点：
  // 直接取“黑白里更清楚的”会让青绿、橙这类中等深浅的颜色配上黑字、黑色开关头，很难看。
  final on = contrastRatio(0xFFFFFFFF, a0) >= kOnAccentKeepWhite ? 0xFFFFFFFF : bestOn(a0);
  final fill = ensureContrast(a0, [on], kContrastText);
  final soft = mixArgb(surface, a0, t.dark ? kAccentSoftMixDark : kAccentSoftMixLight);
  final text = ensureContrast(a0, [bg, surface, soft], kContrastText);

  int? follow(int c) {
    if (oldAccent != null && sameRgb(c, oldAccent)) return withAlpha(text, alphaOf(c));
    if (oldFill != null && sameRgb(c, oldFill)) return withAlpha(fill, alphaOf(c));
    if (oldSoft != null && sameRgb(c, oldSoft)) return withAlpha(soft, alphaOf(c));
    if (oldSelected != null && sameRgb(c, oldSelected)) return withAlpha(soft, alphaOf(c));
    return null;
  }

  var out = t;
  for (final section in const ['ui', 'code', 'terminal', 'lowcode']) {
    final changes = <String, int>{};
    for (final e in t.section(section).entries) {
      final next = follow(e.value);
      if (next != null) changes[e.key] = next;
    }
    if (changes.isNotEmpty) out = out.withColors(section, changes);
  }
  return out.withColors('ui', {UiKey.accent: text, UiKey.accentFill: fill, UiKey.onAccent: on, UiKey.accentSoft: soft, UiKey.selectedBg: soft});
}

bool _isNeutral(int c) {
  final hsl = argbToHsl(c);
  return hsl.s < kNeutralSaturation || hsl.l > 0.985 || hsl.l < 0.02;
}

/// 这些项不跟底色倾向走：纯黑纯白的“只取色相”项、画在别的颜色上的字。
const Set<String> _tintSkip = {'ui.scrim', 'ui.shadow', 'ui.backdropScrim', 'ui.onAccent', 'ui.onDanger'};

/// 积木里只有画布跟着走（积木上的字、输入框是画在彩色积木上的，不动）。
const Set<String> _tintBlocks = {'blocks._canvas', 'blocks._canvasDot'};

int _tinted(int c, double hue, double strength) {
  final hsl = argbToHsl(c);
  final s = strength * (hsl.l > 0.8 ? kTintOnLight : (hsl.l < 0.25 ? kTintOnDark : kTintOnMid));
  return hslToArgb(hue, s, hsl.l, alpha: alphaOf(c));
}

/// 从一个主色生成整套（初稿，之后可以逐项细调）。
///
/// 做法是“拿同明暗的默认主题当骨架换色”，所以各项之间的深浅关系和默认主题一样：
/// 1. 中性色（底色、卡片、文字、边线、代码底、终端底、注释、积木画布…）：亮度不动，色相换成 [tint] 的色相，
///    饱和度按 [tint] 自己的鲜艳程度给（[tint] 是灰的就得到纯灰）。
/// 2. 强调色这一组按 [accent] 重算（[reaccentTheme]）。
/// 3. 其余有颜色的项（危险 / 警告 / 成功、高亮各类、终端 16 色、积木各类）保留默认的色相。
/// 4. 最后把对比度不够的项调到达标（[repairContrast]）。
///
/// [shell] 给了就沿用它的标识、名字、作者和“形状与密度”。
ThemeSpec generateTheme({required bool dark, required int tint, required int accent, ThemeSpec? shell}) {
  final base = defaultThemeFor(dark: dark);
  final hsv = argbToHsv(tint);
  var out = base.copyWith(id: shell?.id, name: shell?.name, author: () => shell?.author, builtin: false, metrics: shell?.metrics);
  for (final item in kThemeItems) {
    if (item.section == 'lowcode' || _tintSkip.contains(item.id)) continue;
    if (item.section == 'blocks' && !_tintBlocks.contains(item.id)) continue;
    final c = itemColor(out, item);
    if (c == null || !_isNeutral(c)) continue;
    out = setItemColor(out, item, _tinted(c, hsv.h, hsv.s));
  }
  return repairContrast(reaccentTheme(out, accent));
}

/// 这几对里要调的是“底”而不是“字”：积木上的字是所有分类共用的，动它不如动那一类的主色。
bool _adjustsBg(String checkId) => checkId.startsWith('blocks._text/');

/// 把对比度不够的项调到达标：只动亮度，色相不变；一项要同时放在几种底上的，调到每一种都够。
/// [only] 给了就只管这些检查项。调不动的（半透明的颜色、底色自己是中灰）留着不动。
ThemeSpec repairContrast(ThemeSpec t, {Set<String>? only}) {
  var out = t;
  for (var pass = 0; pass < 4; pass++) {
    final issues = [
      for (final i in checkThemeContrast(out))
        if (only == null || only.contains(i.id)) i,
    ];
    if (issues.isEmpty) break;
    var moved = false;
    final done = <String>{};
    for (final issue in issues) {
      final parts = issue.id.split('/');
      if (parts.length != 2) continue;
      final targetId = _adjustsBg(issue.id) ? parts[1] : parts[0];
      if (!done.add(targetId)) continue;
      final item = themeItemById(targetId);
      final now = item == null ? null : itemColor(out, item);
      if (item == null || now == null) continue;
      int next;
      if (_adjustsBg(issue.id)) {
        final fgItem = themeItemById(parts[0]);
        final fg = fgItem == null ? null : itemColor(out, fgItem);
        if (fg == null) continue;
        next = ensureContrast(now, [fg], issue.min);
      } else {
        // 这一项当“字”出现的每一对都要过，免得修好这一对、弄坏那一对。
        final mine = [
          for (final c in kContrastChecks)
            if (c.id.startsWith('$targetId/')) c,
        ];
        final min = mine.map((c) => c.min).reduce((a, b) => a > b ? a : b);
        next = ensureContrast(now, [for (final c in mine) c.bg(out)], min);
      }
      if (next != now) {
        out = setItemColor(out, item, next);
        moved = true;
      }
    }
    if (!moved) break;
  }
  return out;
}
