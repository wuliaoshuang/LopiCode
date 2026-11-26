/// 主题变量（第 4 期）：项目级的一份“颜色、字号、间距、圆角”，所有页面和自定义组件共用。
///
/// 存在页面文件最外层的 `theme` 里（格式见 docs/lowcode-page-format-v3.md）：
/// `{"vars": {"color-primary": "#058654", …}, "labels": {"color-primary": "主色", …}}`。
/// 组件的样式里写 `var(--color-primary)` 来用它；改了变量的值，用到的地方画布和导出都跟着变。
/// `theme` 里别的键、`vars` 里读不懂的项（名字写法不对、值不是字符串）不解释，原样留着。
///
/// 这里不碰界面库；变量的“种类”只看名字的开头（color- / font- / space- / radius-），不另存。
library;

import 'package:lopicode/lowcode/model.dart';

/// 变量的种类（面板按它分组、按它决定哪种属性能用哪种变量）。
enum LcVarKind {
  color('color-', '颜色'),
  font('font-', '字号'),
  space('space-', '间距'),
  radius('radius-', '圆角'),
  other('', '其它');

  const LcVarKind(this.prefix, this.label);
  final String prefix;
  final String label;

  static LcVarKind of(String name) {
    for (final k in values) {
      if (k != other && name.startsWith(k.prefix)) return k;
    }
    return other;
  }
}

/// 变量名（代码里的名字）的写法：小写字母开头，后面小写字母、数字、连字符，最长 40。
final RegExp kLcVarName = RegExp(r'^[a-z][a-z0-9-]{0,39}$');

/// 一个项目最多多少个变量；给人看的名字最长多少字（都是编辑器的限制，读文件不卡）。
const int kLcMaxVars = 60;
const int kLcVarLabelMax = 20;

final RegExp _badValue = RegExp(r'[{};\n\r<>]');

/// 值合不合规矩（和节点 `style` 的值同一条：不许带会把 CSS 截断的字符，最长 500）。
bool lcVarValueOk(String v) => v.trim().isNotEmpty && v.length <= 500 && !_badValue.hasMatch(v);

/// 读出来的主题：变量按文件里的先后排。不可变——每次改都换一份新的 `theme` 写回文档。
class LcTheme {
  const LcTheme(this.values, this.labels);
  static const LcTheme empty = LcTheme({}, {});

  /// 变量名 → 值（CSS 写法）。
  final Map<String, String> values;

  /// 变量名 → 给人看的名字（没起就没有）。
  final Map<String, String> labels;

  bool get isEmpty => values.isEmpty;

  /// 给人看的名字：自己起的 → 起步那一套的中文名 → 代码里的名字。
  String labelOf(String name) => labels[name] ?? kLcStarterLabels[name] ?? name;

  List<String> namesOf(LcVarKind kind) => [
    for (final n in values.keys)
      if (LcVarKind.of(n) == kind) n,
  ];

  /// 这个变量最后是什么值（它的值里又用了别的变量就接着换）；换不出来返回原文。
  String resolved(String name) => lcSubstVars(values[name] ?? '', values);
}

final Expando<(Object?, LcTheme)> _cache = Expando();

/// 文档的主题变量。同一份 `theme` 只读一遍（画布每画一个组件都会来问）。
LcTheme lcThemeOf(LcDocument doc) {
  final raw = doc.more['theme'];
  final hit = _cache[doc];
  if (hit != null && identical(hit.$1, raw)) return hit.$2;
  final theme = _read(raw);
  _cache[doc] = (raw, theme);
  return theme;
}

LcTheme _read(Object? raw) {
  final vars = raw is Map ? raw['vars'] : null;
  if (vars is! Map) return LcTheme.empty;
  final values = <String, String>{};
  vars.forEach((k, v) {
    if (k is String && v is String && kLcVarName.hasMatch(k) && lcVarValueOk(v)) values[k] = v.trim();
  });
  final labels = <String, String>{};
  final rawLabels = raw is Map ? raw['labels'] : null;
  if (rawLabels is Map) {
    rawLabels.forEach((k, v) {
      if (k is String && v is String && values.containsKey(k) && v.trim().isNotEmpty) labels[k] = v.trim();
    });
  }
  return LcTheme(values, labels);
}

final RegExp _varRef = RegExp(r'var\(\s*--([A-Za-z0-9_-]+)\s*(?:,([^()]*(?:\([^()]*\)[^()]*)*))?\)');

/// 把 [value] 里的 `var(--名字)` 换成变量的值（值里又有变量就接着换，最多 6 层，防止绕圈）。
/// 没有这个变量：有后备值（`var(--x, 8px)`）用后备值，没有就原样留着（画布会当成“没写”）。
String lcSubstVars(String value, Map<String, String> vars) {
  if (!value.contains('var(')) return value;
  var out = value;
  for (var i = 0; i < 6 && out.contains('var('); i++) {
    final next = out.replaceAllMapped(_varRef, (m) => vars[m[1]!] ?? m[2]?.trim() ?? m[0]!);
    if (next == out) break;
    out = next;
  }
  return out;
}

/// [value] 整个就是一个变量（`var(--名字)`）时返回名字；不是返回 null。
String? lcVarNameIn(String? value) {
  final m = RegExp(r'^var\(\s*--([a-z][a-z0-9-]{0,39})\s*\)$').firstMatch(value?.trim() ?? '');
  return m?[1];
}

/// 用这个变量的写法。
String lcVarRef(String name) => 'var(--$name)';

/// 一种 CSS 属性能用哪几种变量（面板上“用变量”列出来的）；空表＝这种属性不提供“用变量”。
List<LcVarKind> lcVarKindsFor(String cssName) {
  if (cssName == 'color' || cssName.endsWith('-color')) return const [LcVarKind.color];
  if (cssName == 'font-size') return const [LcVarKind.font];
  if (cssName.endsWith('-radius')) return const [LcVarKind.radius];
  // `box`：样式页“间距”那张示意图底下的长度框（改的是内 / 外边距）。
  if (cssName.startsWith('padding') || cssName.startsWith('margin') || cssName == 'gap' || cssName.endsWith('-gap') || cssName == 'box') return const [LcVarKind.space];
  return const [];
}

// ───────────── 改 ─────────────

void _write(LcDocument doc, Map<String, String> values, Map<String, String> labels) {
  final old = doc.more['theme'];
  final oldVars = old is Map ? old['vars'] : null;
  // 读不懂的项原样留着，排在读得懂的后面。
  final keptVars = <String, dynamic>{
    if (oldVars is Map)
      for (final e in oldVars.entries)
        if (e.key is String && !(e.value is String && kLcVarName.hasMatch(e.key as String) && lcVarValueOk(e.value as String))) e.key as String: e.value,
  };
  final rest = <String, dynamic>{
    if (old is Map)
      for (final e in old.entries)
        if (e.key is String && e.key != 'vars' && e.key != 'labels') e.key as String: e.value,
  };
  final keepLabels = {
    for (final e in labels.entries)
      if (values.containsKey(e.key)) e.key: e.value,
  };
  final vars = {...values, ...keptVars};
  if (vars.isEmpty && rest.isEmpty) {
    doc.more.remove('theme');
  } else {
    doc.more['theme'] = <String, dynamic>{'vars': vars, if (keepLabels.isNotEmpty) 'labels': keepLabels, ...rest};
  }
}

/// 新加或改一个变量的值 / 名字。[label] 传 null＝名字不动，传空串＝去掉自己起的名字。写法不对、满了返回 false。
bool lcSetVar(LcDocument doc, String name, String value, {String? label}) {
  final t = lcThemeOf(doc);
  if (!kLcVarName.hasMatch(name) || !lcVarValueOk(value)) return false;
  if (!t.values.containsKey(name) && t.values.length >= kLcMaxVars) return false;
  final labels = Map.of(t.labels);
  if (label != null) {
    final l = label.trim();
    l.isEmpty ? labels.remove(name) : labels[name] = l.length > kLcVarLabelMax ? l.substring(0, kLcVarLabelMax) : l;
  }
  _write(doc, {...t.values, name: value.trim()}, labels);
  return true;
}

/// 给一个新变量找个没用过的代码名：`color-1`、`color-2`…
String lcFreshVarName(LcTheme t, LcVarKind kind) {
  final prefix = kind == LcVarKind.other ? 'var-' : kind.prefix;
  var i = 1;
  while (t.values.containsKey('$prefix$i')) {
    i++;
  }
  return '$prefix$i';
}

/// 所有“放样式声明的地方”走一遍：每个页面、每个自定义组件定义里的每个节点的 `style`、各状态样式、各断点的样式。
/// [visit] 拿到的是可以就地改的声明表（值是字符串的那些条目）。
void lcEachStyleMap(LcDocument doc, void Function(Map<dynamic, dynamic> decl) visit) {
  void node(LcNode n) {
    visit(n.style);
    final states = n.more['states'];
    if (states is Map) {
      for (final s in states.values) {
        if (s is Map) visit(s);
      }
    }
    final resp = n.more['responsive'];
    if (resp is Map) {
      for (final b in resp.values) {
        if (b is Map && b['style'] is Map) visit(b['style'] as Map);
      }
    }
    n.children.forEach(node);
  }

  for (final p in doc.pages) {
    node(p.root);
  }
  for (final c in doc.components) {
    node(c.root);
  }
}

RegExp _refTo(String name) => RegExp('var\\(\\s*--${RegExp.escape(name)}\\s*(?=[,)])');

/// 这个变量在整个项目里用了几处（一条样式声明算一处；别的变量的值里用到它也算）。
int lcVarUseCount(LcDocument doc, String name) {
  final re = _refTo(name);
  var count = 0;
  lcEachStyleMap(doc, (decl) {
    for (final v in decl.values) {
      if (v is String && re.hasMatch(v)) count++;
    }
  });
  for (final e in lcThemeOf(doc).values.entries) {
    if (e.key != name && re.hasMatch(e.value)) count++;
  }
  return count;
}

void _rewrite(LcDocument doc, String Function(String value) change) => lcEachStyleMap(doc, (decl) {
  for (final k in decl.keys.toList()) {
    final v = decl[k];
    if (v is String && v.contains('var(')) decl[k] = change(v);
  }
});

/// 改代码里的名字：所有页面、所有自定义组件里用到它的地方（连同别的变量的值里用到的）一起改。
/// 新名字写法不对、已经有了返回 false，什么都不动。
bool lcRenameVar(LcDocument doc, String from, String to) {
  final t = lcThemeOf(doc);
  if (from == to) return true;
  if (!t.values.containsKey(from) || !kLcVarName.hasMatch(to) || t.values.containsKey(to)) return false;
  final re = _refTo(from);
  String fix(String v) => v.replaceAll(re, 'var(--$to');
  _rewrite(doc, fix);
  _write(doc, {for (final e in t.values.entries) e.key == from ? to : e.key: e.key == from ? e.value : fix(e.value)}, {for (final e in t.labels.entries) e.key == from ? to : e.key: e.value});
  return true;
}

/// 删一个变量：用到它的地方换成它现在的值（样子不变，只是以后不再跟着变）。返回换了几处。
int lcRemoveVar(LcDocument doc, String name) {
  final t = lcThemeOf(doc);
  if (!t.values.containsKey(name)) return 0;
  final used = lcVarUseCount(doc, name);
  final now = {name: t.resolved(name)};
  final re = _refTo(name);
  String fix(String v) => re.hasMatch(v) ? lcSubstVars(v, now) : v;
  _rewrite(doc, fix);
  _write(doc, {
    for (final e in t.values.entries)
      if (e.key != name) e.key: fix(e.value),
  }, t.labels);
  return used;
}

// ───────────── 起步的一套（点“加一套起步的变量”才写进文件）─────────────

/// 起步那一套的中文名（用户没另起名字时显示它）。
const Map<String, String> kLcStarterLabels = {
  'color-primary': '主色',
  'color-text': '文字',
  'color-text-muted': '次要文字',
  'color-bg': '背景',
  'color-card': '卡片',
  'color-danger': '危险',
  'font-sm': '小字',
  'font-md': '正文',
  'font-lg': '小标题',
  'font-xl': '大标题',
  'space-sm': '小间距',
  'space-md': '中间距',
  'space-lg': '大间距',
  'radius-sm': '小圆角',
  'radius-md': '中圆角',
  'radius-lg': '大圆角',
};

/// 起步那一套的值。颜色取自应用自带的那组“给用户页面用的颜色”，字号、间距、圆角取自面板上的预设档。
const Map<String, String> kLcStarterVars = {
  'color-primary': '#058654',
  'color-text': '#222435',
  'color-text-muted': '#5c6479',
  'color-bg': '#ffffff',
  'color-card': '#f3f4f6',
  'color-danger': '#c6212f',
  'font-sm': '12px',
  'font-md': '16px',
  'font-lg': '20px',
  'font-xl': '30px',
  'space-sm': '8px',
  'space-md': '16px',
  'space-lg': '24px',
  'radius-sm': '6px',
  'radius-md': '10px',
  'radius-lg': '16px',
};

/// 把起步那一套里还没有的加进来（已经有的不动）。返回加了几个。
int lcAddStarterVars(LcDocument doc) {
  final t = lcThemeOf(doc);
  final add = {
    for (final e in kLcStarterVars.entries)
      if (!t.values.containsKey(e.key)) e.key: e.value,
  };
  if (add.isEmpty) return 0;
  _write(doc, {...t.values, ...add}, t.labels);
  return add.length;
}
