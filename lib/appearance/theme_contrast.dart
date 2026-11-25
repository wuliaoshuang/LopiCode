/// 对比度：WCAG 2 的算法，加一份“一套主题要过哪些组合”的检查清单。纯 Dart。
///
/// 规矩：正文类的字和它的底 ≥ 4.5:1；大字、图标、标记这类 ≥ 3:1。半透明的颜色先按透明度叠到底色上再算。
library;

import 'dart:math' as math;

import 'package:lopicode/appearance/theme_builtin.dart';
import 'package:lopicode/appearance/theme_fields.dart';
import 'package:lopicode/appearance/theme_spec.dart';

const double kContrastText = 4.5;
const double kContrastLarge = 3;

double _channel(int v) {
  final s = v / 255;
  return s <= 0.03928 ? s / 12.92 : math.pow((s + 0.055) / 1.055, 2.4).toDouble();
}

/// 相对亮度（0–1）。不看透明度。
double relativeLuminance(int argb) => 0.2126 * _channel((argb >> 16) & 0xFF) + 0.7152 * _channel((argb >> 8) & 0xFF) + 0.0722 * _channel(argb & 0xFF);

/// 把带透明度的 [top] 叠到不透明的 [bottom] 上，得到看起来的颜色。
int compositeOver(int top, int bottom) {
  final a = ((top >> 24) & 0xFF) / 255;
  int mix(int shift) => (((top >> shift) & 0xFF) * a + ((bottom >> shift) & 0xFF) * (1 - a)).round();
  return 0xFF000000 | (mix(16) << 16) | (mix(8) << 8) | mix(0);
}

/// 对比度（1–21）。[fg] 带透明度的话先叠到 [bg] 上。
double contrastRatio(int fg, int bg) {
  final a = relativeLuminance(compositeOver(fg, bg));
  final b = relativeLuminance(bg);
  final hi = math.max(a, b), lo = math.min(a, b);
  return (hi + 0.05) / (lo + 0.05);
}

/// 清单里的一项：哪个前景放在哪个底上，至少要多少。
class ContrastCheck {
  const ContrastCheck(this.id, this.label, this.fg, this.bg, this.min);

  /// 稳定的标识（登记例外用），形如 `ui.text/ui.bg`。
  final String id;
  final String label;
  final int? Function(ThemeSpec t) fg;
  final int Function(ThemeSpec t) bg;
  final double min;
}

/// 不达标的一项。
class ContrastIssue {
  const ContrastIssue(this.id, this.label, this.ratio, this.min);
  final String id;
  final String label;
  final double ratio;
  final double min;

  /// 给人看的一句话。
  String get message => '$label：对比度 ${ratio.toStringAsFixed(2)}:1，至少要 ${min == min.roundToDouble() ? min.toStringAsFixed(0) : min}:1';

  @override
  String toString() => message;
}

String _label(String section, String key) {
  final fields = section == 'tokens' ? kTokenFields : kThemeColorSections[section]!;
  return '${kThemeSectionLabels[section]} › ${fields.firstWhere((f) => f.key == key).label}';
}

ContrastCheck _pair(String fgSection, String fgKey, String bgSection, String bgKey, double min) => ContrastCheck(
  '$fgSection.$fgKey/$bgSection.$bgKey',
  '“${_label(fgSection, fgKey)}”放在“${_label(bgSection, bgKey)}”上',
  (t) => t.section(fgSection)[fgKey],
  // 底色自己带透明度的（比如尺寸标签），按叠在白纸上算。
  (t) => compositeOver(t.section(bgSection)[bgKey] ?? 0xFFFFFFFF, 0xFFFFFFFF),
  min,
);

/// 一套主题要过的全部组合。
final List<ContrastCheck> kContrastChecks = List.unmodifiable([
  for (final bg in [UiKey.bg, UiKey.canvas, UiKey.surface, UiKey.surfaceMuted, UiKey.codeBg, UiKey.cardBg, UiKey.inputBg, UiKey.selectedBg]) _pair('ui', UiKey.text, 'ui', bg, kContrastText),
  for (final bg in [UiKey.bg, UiKey.canvas, UiKey.surface, UiKey.surfaceMuted]) _pair('ui', UiKey.textMuted, 'ui', bg, kContrastText),
  for (final bg in [UiKey.bg, UiKey.canvas, UiKey.surface, UiKey.inputBg]) _pair('ui', UiKey.textFaint, 'ui', bg, kContrastText),
  for (final bg in [UiKey.bg, UiKey.surface, UiKey.accentSoft, UiKey.selectedBg]) _pair('ui', UiKey.accent, 'ui', bg, kContrastText),
  _pair('ui', UiKey.onAccent, 'ui', UiKey.accentFill, kContrastText),
  for (final bg in [UiKey.bg, UiKey.surface]) _pair('ui', UiKey.link, 'ui', bg, kContrastText),
  for (final bg in [UiKey.bg, UiKey.surface, UiKey.dangerSoft]) _pair('ui', UiKey.danger, 'ui', bg, kContrastText),
  _pair('ui', UiKey.onDanger, 'ui', UiKey.danger, kContrastText),
  for (final bg in [UiKey.bg, UiKey.surface, UiKey.warningSoft]) _pair('ui', UiKey.warning, 'ui', bg, kContrastText),
  for (final bg in [UiKey.surface, UiKey.successSoft]) _pair('ui', UiKey.success, 'ui', bg, kContrastText),
  for (final bg in [UiKey.surface, UiKey.infoSoft]) _pair('ui', UiKey.info, 'ui', bg, kContrastText),
  _pair('ui', UiKey.navActive, 'ui', UiKey.navBg, kContrastText),
  _pair('ui', UiKey.navInactive, 'ui', UiKey.navBg, kContrastText),
  _pair('ui', UiKey.bubbleMineText, 'ui', UiKey.bubbleMineBg, kContrastText),
  _pair('ui', UiKey.bubbleAgentText, 'ui', UiKey.bubbleAgentBg, kContrastText),
  _pair('ui', UiKey.snackText, 'ui', UiKey.snackBg, kContrastText),
  _pair('ui', UiKey.noticeText, 'ui', UiKey.noticeBg, kContrastText),
  for (final k in [UiKey.chart1, UiKey.chart2, UiKey.chart3, UiKey.chart4]) _pair('ui', k, 'ui', UiKey.surface, kContrastLarge),
  // 代码
  _pair('code', CodeKey.fg, 'code', CodeKey.bg, kContrastText),
  _pair('code', CodeKey.lineNumber, 'code', CodeKey.bg, kContrastLarge),
  _pair('code', CodeKey.lineNumberActive, 'code', CodeKey.bg, kContrastText),
  _pair('code', CodeKey.cursor, 'code', CodeKey.bg, kContrastLarge),
  _pair('code', CodeKey.diffAddFg, 'code', CodeKey.diffAddBg, kContrastText),
  _pair('code', CodeKey.diffDelFg, 'code', CodeKey.diffDelBg, kContrastText),
  for (final f in kTokenFields)
    ContrastCheck('tokens.${f.key}/code.bg', '“${_label('tokens', f.key)}”放在“${_label('code', CodeKey.bg)}”上', (t) => t.tokens[f.key]?.color, (t) => t.code[CodeKey.bg] ?? 0xFFFFFFFF, kContrastText),
  // 终端
  _pair('terminal', 'fg', 'terminal', 'bg', kContrastText),
  _pair('terminal', 'cursor', 'terminal', 'bg', kContrastLarge),
  _pair('terminal', 'searchHitFg', 'terminal', 'searchHitBg', kContrastText),
  for (final f in kTerminalFields.where((f) => f.group != '基本')) _pair('terminal', f.key, 'terminal', 'bg', kContrastLarge),
  // 积木
  for (final f in kBlockCategoryFields) _pair('blocks', BlockKey.text, 'blocks', f.key, kContrastText),
  _pair('blocks', BlockKey.fieldText, 'blocks', BlockKey.fieldBg, kContrastText),
  _pair('blocks', BlockKey.fieldHint, 'blocks', BlockKey.fieldBg, kContrastLarge),
  _pair('blocks', BlockKey.selection, 'blocks', BlockKey.canvas, kContrastLarge),
  _pair('blocks', BlockKey.error, 'blocks', BlockKey.canvas, kContrastLarge),
  _pair('blocks', BlockKey.warning, 'blocks', BlockKey.canvas, kContrastLarge),
  _pair('blocks', BlockKey.onError, 'blocks', BlockKey.error, kContrastLarge),
  _pair('blocks', BlockKey.onWarning, 'blocks', BlockKey.warning, kContrastLarge),
  // 低代码编辑器
  _pair('lowcode', LowcodeKey.selectionText, 'lowcode', LowcodeKey.selection, kContrastText),
  _pair('lowcode', LowcodeKey.sizeTagText, 'lowcode', LowcodeKey.sizeTagBg, kContrastText),
  _pair('lowcode', LowcodeKey.dragChipText, 'lowcode', LowcodeKey.dragChipBg, kContrastText),
  _pair('lowcode', LowcodeKey.missingText, 'lowcode', LowcodeKey.missingBg, kContrastText),
  _pair('lowcode', LowcodeKey.missingIcon, 'lowcode', LowcodeKey.missingBg, kContrastLarge),
]);

/// 查一套主题：返回不达标的项（空表＝全过）。没设颜色的高亮分类不查（它跟代码文字一个色）。
List<ContrastIssue> checkThemeContrast(ThemeSpec t) {
  final out = <ContrastIssue>[];
  for (final c in kContrastChecks) {
    final fg = c.fg(t);
    if (fg == null) continue;
    final ratio = contrastRatio(fg, c.bg(t));
    // 留一点点余量：4.499 这种算到小数点后两位是 4.50 的不算不达标。
    if (ratio + 0.005 < c.min) out.add(ContrastIssue(c.id, c.label, ratio, c.min));
  }
  return out;
}

/// 两套默认主题里**已知不达标**的项（检查项的 id → 为什么留着）。
///
/// 默认主题就是加主题系统之前应用的样子，一个颜色都不能动，所以这些只登记、不修；
/// 新加的内置主题不应该往这里加东西。清单和实际不符时 test/theme_contrast_test.dart 会失败。
const Map<String, Map<String, String>> kKnownContrastGaps = {kDefaultLightThemeId: _lightGaps, kDefaultDarkThemeId: _darkGaps};

const String _atom = '高亮沿用 Atom One 配色，原样保留';
const String _ansi = '终端 16 色里的“黑 / 白”本来就贴近底色';
const String _chart = '占用条的色块是装饰，旁边有文字图例';
const String _block = '积木画布上的选中描边、警告标记和报错符号是原来的配色，靠形状（描边、角标）也认得出';

const Map<String, String> _lightGaps = {
  'ui.chart2/ui.surface': _chart, // 1.80:1（要 3.0）
  'ui.chart4/ui.surface': _chart, // 1.72:1（要 3.0）
  'tokens.comment/code.bg': _atom, // 2.34:1（要 4.5）
  'tokens.string/code.bg': _atom, // 2.91:1（要 4.5）
  'tokens.number/code.bg': _atom, // 4.42:1（要 4.5）
  'tokens.literal/code.bg': _atom, // 3.80:1（要 4.5）
  'tokens.type/code.bg': _atom, // 4.42:1（要 4.5）
  'tokens.built_in/code.bg': _atom, // 2.91:1（要 4.5）
  'tokens.title/code.bg': _atom, // 3.68:1（要 4.5）
  'tokens.variable/code.bg': _atom, // 4.42:1（要 4.5）
  'tokens.regexp/code.bg': _atom, // 2.91:1（要 4.5）
  'tokens.subst/code.bg': _atom, // 3.33:1（要 4.5）
  'tokens.symbol/code.bg': _atom, // 3.68:1（要 4.5）
  'tokens.meta/code.bg': _atom, // 3.68:1（要 4.5）
  'tokens.name/code.bg': _atom, // 3.33:1（要 4.5）
  'tokens.attr/code.bg': _atom, // 4.42:1（要 4.5）
  'tokens.attribute/code.bg': _atom, // 2.91:1（要 4.5）
  'tokens.selector-tag/code.bg': _atom, // 3.33:1（要 4.5）
  'tokens.selector-id/code.bg': _atom, // 3.68:1（要 4.5）
  'tokens.selector-class/code.bg': _atom, // 4.42:1（要 4.5）
  'tokens.selector-attr/code.bg': _atom, // 4.42:1（要 4.5）
  'tokens.selector-pseudo/code.bg': _atom, // 4.42:1（要 4.5）
  'tokens.template-variable/code.bg': _atom, // 4.42:1（要 4.5）
  'tokens.section/code.bg': _atom, // 3.33:1（要 4.5）
  'tokens.bullet/code.bg': _atom, // 3.68:1（要 4.5）
  'tokens.quote/code.bg': _atom, // 2.34:1（要 4.5）
  'tokens.link/code.bg': _atom, // 3.68:1（要 4.5）
  'tokens.addition/code.bg': _atom, // 2.91:1（要 4.5）
  'tokens.deletion/code.bg': _atom, // 3.33:1（要 4.5）
  'blocks._selection/blocks._canvas': _block, // 1.43:1（要 3.0）
  'blocks._warning/blocks._canvas': _block, // 1.94:1（要 3.0）
};
const Map<String, String> _darkGaps = {
  'ui.chart3/ui.surface': _chart, // 2.89:1（要 3.0）
  'tokens.comment/code.bg': _atom, // 2.86:1（要 4.5）
  'tokens.quote/code.bg': _atom, // 2.86:1（要 4.5）
  'terminal.black/terminal.bg': _ansi, // 1.52:1（要 3.0）
  'blocks._onError/blocks._error': _block, // 2.78:1（要 3.0）
};

/// 给界面 / 测试用：一套主题里不在“已知例外”里的不达标项。
List<ContrastIssue> unexpectedContrastIssues(ThemeSpec t) {
  final known = kKnownContrastGaps[t.id] ?? const {};
  return [
    for (final i in checkThemeContrast(t))
      if (!known.containsKey(i.id)) i,
  ];
}
