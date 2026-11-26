/// 主题编辑器的“数据那一半”：把一份主题摊成一张“可改项”的清单，读 / 写某一项，算哪些项改过，
/// 某一项和它的底色对比度多少，以及编辑过程里的撤销 / 重做。纯 Dart，界面在 lib/ui/theme_editor_*.dart。
library;

import 'package:lopicode/appearance/theme_builtin.dart';
import 'package:lopicode/appearance/theme_contrast.dart';
import 'package:lopicode/appearance/theme_fields.dart';
import 'package:lopicode/appearance/theme_spec.dart';

/// 编辑器里各节的顺序（“形状与密度”单列，不在这里）。
const List<String> kThemeEditSections = ['ui', 'code', 'tokens', 'terminal', 'blocks', 'lowcode'];

/// 一个可以改的颜色项。
class ThemeItem {
  const ThemeItem(this.section, this.field);
  final String section;
  final ThemeField field;

  String get key => field.key;
  String get label => field.label;
  String get group => field.group;
  String get note => field.note;

  /// 稳定的标识：`节.键`（和对比度检查里用的写法一样）。
  String get id => '$section.$key';

  /// 是不是代码高亮的一类（可以不单独上色、可以加粗 / 倾斜）。
  bool get isToken => section == 'tokens';

  String get sectionLabel => kThemeSectionLabels[section] ?? section;
}

/// 全部颜色项（191 个），按编辑器里的顺序。
final List<ThemeItem> kThemeItems = List.unmodifiable([
  for (final s in kThemeEditSections)
    for (final f in s == 'tokens' ? kTokenFields : kThemeColorSections[s]!) ThemeItem(s, f),
]);

final Map<String, ThemeItem> _itemsById = {for (final i in kThemeItems) i.id: i};

ThemeItem? themeItemById(String id) => _itemsById[id];

/// 这一项现在的颜色。高亮分类没单独上色时是 null。
int? itemColor(ThemeSpec t, ThemeItem item) => item.isToken ? t.tokens[item.key]?.color : t.section(item.section)[item.key];

/// 换这一项的颜色，得到一份新的主题。只有高亮分类能给 null（＝不单独上色）。
ThemeSpec setItemColor(ThemeSpec t, ThemeItem item, int? color) {
  if (item.isToken) return t.withToken(item.key, (t.tokens[item.key] ?? const TokenStyle()).copyWith(color: () => color));
  return color == null ? t : t.withColors(item.section, {item.key: color});
}

/// 这一项能不能带透明度：两套默认主题里它本来就是半透明的，或者说明里写了“带透明度”。
bool itemAllowsAlpha(ThemeItem item) {
  if (item.note.contains('带透明度')) return true;
  for (final d in [kDefaultLightTheme, kDefaultDarkTheme]) {
    final c = itemColor(d, item);
    if (c != null && (c >> 24) & 0xFF != 0xFF) return true;
  }
  return false;
}

/// 同明暗的默认主题里这一项的值（“恢复这一项的默认值”用）。
int? itemDefaultColor(ThemeItem item, {required bool dark}) => itemColor(defaultThemeFor(dark: dark), item);

/// [now] 相对 [origin] 改过的项的标识（颜色项是 `节.键`，数是 `metrics.键`）。高亮分类的粗体 / 斜体变了也算。
Set<String> changedThemeItems(ThemeSpec origin, ThemeSpec now) {
  final out = <String>{};
  for (final i in kThemeItems) {
    final same = i.isToken ? origin.tokens[i.key] == now.tokens[i.key] : origin.section(i.section)[i.key] == now.section(i.section)[i.key];
    if (!same) out.add(i.id);
  }
  for (final f in kMetricFields) {
    if (origin.metric(f.key) != now.metric(f.key)) out.add('metrics.${f.key}');
  }
  return out;
}

/// 一项和它某个搭档的对比度。
class ItemContrast {
  const ItemContrast({required this.ratio, required this.min, required this.other, required this.asFg});
  final double ratio;
  final double min;

  /// 搭档的名字（“界面 › 卡片 / 面板”这种）。
  final String other;

  /// 这一项是字（true）还是底（false）。
  final bool asFg;

  bool get ok => ratio + 0.005 >= min;
}

String _itemLabel(String id) {
  final i = _itemsById[id];
  return i == null ? id : '${i.sectionLabel} › ${i.label}';
}

/// 这一项在 [t] 里最吃紧的那一对（实际对比度离要求最远的）。它不在检查清单里就是 null。
ItemContrast? worstContrastOf(ThemeSpec t, String itemId) {
  ItemContrast? worst;
  for (final c in kContrastChecks) {
    final parts = c.id.split('/');
    if (parts.length != 2 || (parts[0] != itemId && parts[1] != itemId)) continue;
    final fg = c.fg(t);
    if (fg == null) continue;
    final asFg = parts[0] == itemId;
    final r = ItemContrast(ratio: contrastRatio(fg, c.bg(t)), min: c.min, other: _itemLabel(asFg ? parts[1] : parts[0]), asFg: asFg);
    if (worst == null || r.ratio / r.min < worst.ratio / worst.min) worst = r;
  }
  return worst;
}

/// 不达标的检查里，“字”那一项的标识（编辑器在这些行旁边打标记）。
Set<String> lowContrastItems(List<ContrastIssue> issues) => {for (final i in issues) i.id.split('/').first};

/// 形状与密度每个数一步走多少。
double metricStep(String key) => switch (key) {
  MetricKey.radiusScale => 0.1,
  MetricKey.shadowStrength => 0.1,
  MetricKey.dividerWidth => 0.5,
  _ => 0.05,
};

/// 在现在的值上走一步（[dir] 是 +1 / −1），夹在范围里，留两位小数。
double bumpMetric(ThemeMetricField f, double value, int dir) {
  final next = (value + dir * metricStep(f.key)).clamp(f.min, f.max);
  return (next * 100).round() / 100;
}

String formatMetric(double v) {
  final s = v.toStringAsFixed(2);
  return s.endsWith('0') ? s.substring(0, s.length - 1) : s;
}

/// 一次编辑会话的历史：起点、现在、能撤销 / 重做的各一摞。不可变——每个操作返回一份新的。
class ThemeHistory {
  const ThemeHistory._(this.origin, this.current, this._undo, this._redo, this._tag);

  /// 打开编辑器时的那份主题就是起点。
  ThemeHistory(ThemeSpec origin) : this._(origin, origin, const [], const [], null);

  /// 最多记多少步。
  static const int maxSteps = 100;

  final ThemeSpec origin;
  final ThemeSpec current;
  final List<ThemeSpec> _undo;
  final List<ThemeSpec> _redo;
  final String? _tag;

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  /// 和起点比有没有变。
  bool get dirty => current != origin;

  /// 记一步。[tag] 相同的连续几步并成一步（拖取色面板时一路在变，撤销时应该一下回到拖之前）。
  ThemeHistory apply(ThemeSpec next, {String? tag}) {
    if (next == current) return this;
    if (tag != null && tag == _tag && _undo.isNotEmpty) return ThemeHistory._(origin, next, _undo, const [], tag);
    final undo = [..._undo, current];
    return ThemeHistory._(origin, next, undo.length > maxSteps ? undo.sublist(undo.length - maxSteps) : undo, const [], tag);
  }

  ThemeHistory undo() => canUndo ? ThemeHistory._(origin, _undo.last, _undo.sublist(0, _undo.length - 1), [..._redo, current], null) : this;

  ThemeHistory redo() => canRedo ? ThemeHistory._(origin, _redo.last, [..._undo, current], _redo.sublist(0, _redo.length - 1), null) : this;

  /// 全部恢复为起点（这一步本身可以撤销）。
  ThemeHistory reset() => apply(origin.copyWith(name: current.name));

  /// 存好以后：现在这份成了新的起点，撤销 / 重做照旧能用。
  ThemeHistory saved() => ThemeHistory._(current, current, _undo, _redo, null);

  /// 只换名字（不进撤销历史：改名是单独存的）。
  ThemeHistory renamed(String name) =>
      ThemeHistory._(origin.copyWith(name: name), current.copyWith(name: name), [for (final t in _undo) t.copyWith(name: name)], [for (final t in _redo) t.copyWith(name: name)], _tag);
}
