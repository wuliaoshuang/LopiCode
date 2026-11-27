/// “常用”页往哪儿写（属性面板和样式面板合成一张以后的写入规矩，对应设计文档的 GAP-E-6）。
///
/// 页面文件里一个组件有两处能放外观：第 1 版的简写属性（`props` 里的 padding / bg / fontSize…）和 `style`（CSS 条目）。
/// 画布、网页、Vue、React 导出看的是“简写属性被 style 盖掉之后”的结果；**Flutter 导出只看简写属性**。
/// 所以“新改动一律写进 style”行不通：网页的 CSS 倒是一样，但 Flutter 导出就不跟着变了（比旧“属性”面板还退步）。
///
/// 规矩（文件格式一个字不变）：
/// - 这一项能用简写属性原样表达，而且组件的 style 里没有盖住它的条目 → 写简写属性（和旧“属性”面板写出来的一模一样，
///   四种导出逐字不变）。
/// - style 里已经有盖住它的条目（用户在“样式”页调过）→ 改 style 里的那几条。不然写了简写属性也被盖着，等于白改。
/// - 清掉（传 null）→ 两处都清，回到默认。
library;

import 'package:lopicode/lowcode/css_codec.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/style_resolve.dart';

String _n(num v) => v == v.roundToDouble() ? '${v.round()}' : '$v';

const Map<String, String> _alignCss = {'start': 'flex-start', 'center': 'center', 'end': 'flex-end', 'stretch': 'stretch'};
const Map<String, String> _justifyCss = {'start': 'flex-start', 'center': 'center', 'end': 'flex-end', 'between': 'space-between'};

/// 一个简写属性管着 style 里的哪几条（规范写法、拆开的单项）。不认识的属性返回空表。
List<String> legacyPropCssNames(String prop) => switch (prop) {
  'padding' => cssLonghands('padding'),
  'margin' => cssLonghands('margin'),
  'radius' => cssLonghands('border-radius'),
  'gap' => cssLonghands('gap'),
  'bg' => const ['background-color'],
  'color' => const ['color'],
  'fontSize' => const ['font-size'],
  'bold' => const ['font-weight'],
  'textAlign' => const ['text-align'],
  'align' => const ['align-items'],
  'justify' => const ['justify-content'],
  'height' => const ['height'],
  // “撑满”在行里是 flex 那一组、在列里是 align-self；固定宽度是 width。
  'width' => const ['width', 'flex-grow', 'flex-shrink', 'flex-basis', 'align-self'],
  _ => const [],
};

/// 这个简写属性的值翻成 style 里的写法；翻不了（比如宽度的“撑满”）返回 null。
String? _cssValue(String prop, Object value) => switch (prop) {
  'padding' || 'margin' || 'radius' || 'gap' || 'fontSize' || 'height' => value is num ? '${_n(value)}px' : null,
  'width' => value is num ? '${_n(value)}px' : null,
  'bg' || 'color' => value is String ? value.toLowerCase() : null,
  'bold' => value == true ? '600' : '400',
  'textAlign' => value is String ? value : null,
  'align' => _alignCss[value],
  'justify' => _justifyCss[value],
  _ => null,
};

/// style 里有没有盖住这个简写属性的条目。
bool styleOverrides(LcNode n, String prop) {
  if (n.style.isEmpty) return false;
  final own = canonicalDeclarations(n.style);
  return legacyPropCssNames(prop).any(own.containsKey);
}

void _dropFromStyle(LcNode n, List<String> names) {
  if (n.style.isEmpty || names.isEmpty) return;
  final own = canonicalDeclarations(n.style);
  if (!names.any(own.containsKey)) return;
  names.forEach(own.remove);
  n.style
    ..clear()
    ..addAll(own);
}

/// “常用”页改一项。[prop] 是简写属性的名字，[value] 为 null＝清掉。
///
/// 返回这次写到了哪儿：`props` / `style`（测试和面板上的小字用）。
String writeCommon(LcNode n, String prop, Object? value) {
  final names = legacyPropCssNames(prop);
  if (value == null) {
    n.props.remove(prop);
    _dropFromStyle(n, names);
    return 'props';
  }
  if (value is String && value.startsWith('var(')) {
    // 用主题变量：变量只能写在 style 里（简写属性放不了）。简写属性留着不动——反正被 style 盖着，
    // 以后不用变量了它还在；Flutter 导出时会把变量现在的值放回简写属性（见 export_dart_theme.dart）。
    final own = canonicalDeclarations(n.style);
    for (final name in names) {
      if (prop == 'width' && name != 'width') {
        own.remove(name);
      } else {
        own[name] = value;
      }
    }
    n.style
      ..clear()
      ..addAll(own);
    return 'style';
  }
  final css = names.isEmpty ? null : _cssValue(prop, value);
  // style 里盖着它的全是主题变量（在“常用”页选的）：换成普通值时把变量那几条去掉，回到写简写属性。
  if (css != null && n.style.isNotEmpty) {
    final own = canonicalDeclarations(n.style);
    final covering = [
      for (final name in names)
        if (own[name] != null) own[name]!,
    ];
    if (covering.isNotEmpty && covering.every((v) => v.startsWith('var('))) _dropFromStyle(n, names);
  }
  if (css == null || !styleOverrides(n, prop)) {
    // 能用简写属性表达、style 里也没盖着它：照旧写简写属性。
    // （宽度的“撑满”只有简写属性能表达：这时把 style 里盖着它的条目去掉，不然不生效。）
    if (css == null) _dropFromStyle(n, names);
    n.props[prop] = value;
    return 'props';
  }
  // style 里盖着：改 style。先把没拆开的简写（Agent 或手改文件写进来的）换成规范写法，再改这几条。
  final own = canonicalDeclarations(n.style);
  for (final name in names) {
    if (prop == 'width' && name != 'width') {
      own.remove(name);
    } else {
      own[name] = css;
    }
  }
  n.style
    ..clear()
    ..addAll(own);
  return 'style';
}

/// “常用”页显示用：这一项现在实际生效的值（style 盖过简写属性之后的），CSS 写法；没有就是 null。
String? effectiveCss(LcNode n, LcNode? parent, String cssName) => resolvedStyle(n, parent)[cssName];

/// 生效值里的像素数（`12px` → 12）；不是像素（百分比、auto…）或没有时返回 null。
num? effectivePx(LcNode n, LcNode? parent, String cssName) {
  final v = effectiveCss(n, parent, cssName);
  if (v == null) return null;
  final m = RegExp(r'^(-?\d+(?:\.\d+)?)(px)?$').firstMatch(v.trim());
  if (m == null || (m[2] == null && m[1] != '0')) return null;
  final d = double.parse(m[1]!);
  return d == d.roundToDouble() ? d.round() : d;
}

/// 只有 style 能表达的项（阴影、填充方式、宽高比、换行、最多几行…）：直接写 style。[value] 为 null＝去掉。
void writeStyleOnly(LcNode n, String cssName, String? value) {
  if (value == null || value.trim().isEmpty) {
    _dropFromStyle(n, [cssName, ...cssLonghands(cssName)]);
  } else {
    final own = canonicalDeclarations({...n.style, cssName: value.trim()});
    n.style
      ..clear()
      ..addAll(own);
  }
}

// ───────────── 预设档（5.4）：写死在编辑器里的刻度，不进页面文件 ─────────────

/// 间距档（内边距、外边距、子项间距）。
const List<int> kSpacingScale = [0, 4, 8, 12, 16, 24, 32, 48, 64];

/// 字号档。
const List<int> kFontScale = [12, 14, 16, 18, 20, 24, 30, 36, 48];

/// 圆角档；最后一档是“全圆”（一个足够大的数）。
const List<int> kRadiusScale = [0, 6, 10, 16, kRadiusFull];
const int kRadiusFull = 999;

/// 阴影五级（黑色两成不透明）。第 0 项是“无”。
const List<String> kShadowScale = [
  'none',
  '0 1px 3px rgba(0, 0, 0, 0.2)',
  '0 4px 6px rgba(0, 0, 0, 0.2)',
  '0 5px 15px rgba(0, 0, 0, 0.2)',
  '0 10px 24px rgba(0, 0, 0, 0.2)',
  '0 15px 35px rgba(0, 0, 0, 0.2)',
];

/// 文字级别：名字 → (字号, 加粗)。
const Map<String, (int, bool)> kTextLevels = {'h1': (30, true), 'h2': (24, true), 'h3': (20, true), 'body': (16, false), 'small': (12, false)};
const Map<String, String> kTextLevelLabels = {'h1': '标题 1', 'h2': '标题 2', 'h3': '标题 3', 'body': '正文', 'small': '小字'};

/// 现在是哪个文字级别；对不上任何一档返回 null。
String? textLevel(LcNode n, LcNode? parent) {
  final r = resolvedStyle(n, parent);
  final size = effectivePx(n, parent, 'font-size');
  final w = r['font-weight'];
  final bold = w == 'bold' || (int.tryParse(w ?? '') ?? 400) >= 600;
  for (final e in kTextLevels.entries) {
    if (e.value.$1 == size && e.value.$2 == bold) return e.key;
  }
  return null;
}

void setTextLevel(LcNode n, String level) {
  final v = kTextLevels[level];
  if (v == null) return;
  writeCommon(n, 'fontSize', v.$1);
  // 不加粗：旧面板是把 bold 去掉（不是写 false），照旧；样式里盖着字重时改成 400。
  if (v.$2 || styleOverrides(n, 'bold')) {
    writeCommon(n, 'bold', v.$2);
    if (!v.$2 && n.props['bold'] == false) n.props.remove('bold');
  } else {
    n.props.remove('bold');
  }
}

/// 按钮大小：名字 → (字号, 内边距)。
const Map<String, (int, int)> kButtonSizes = {'s': (14, 8), 'm': (16, 12), 'l': (18, 16)};

String? buttonSize(LcNode n, LcNode? parent) {
  final size = effectivePx(n, parent, 'font-size'), pad = effectivePx(n, parent, 'padding-top');
  for (final e in kButtonSizes.entries) {
    if (e.value.$1 == size && e.value.$2 == pad) return e.key;
  }
  return null;
}

void setButtonSize(LcNode n, String size) {
  final v = kButtonSizes[size];
  if (v == null) return;
  writeCommon(n, 'fontSize', v.$1);
  writeCommon(n, 'padding', v.$2);
}

bool _transparent(String? css) {
  final v = css?.trim().toLowerCase();
  return v == 'transparent' || v == 'rgba(0, 0, 0, 0)' || v == 'rgba(0,0,0,0)';
}

/// 按钮的样子：solid 实心 / outline 描边 / text 只有字。
String buttonVariant(LcNode n, LcNode? parent) {
  final r = resolvedStyle(n, parent);
  if (!_transparent(r['background-color'])) return 'solid';
  final line = r['border-top-style'];
  return line != null && line != 'none' ? 'outline' : 'text';
}

/// 按钮的主色：实心看底色，描边 / 只有字看字的颜色。
String? buttonAccent(LcNode n, LcNode? parent) {
  final r = resolvedStyle(n, parent);
  return buttonVariant(n, parent) == 'solid' ? r['background-color'] : r['color'];
}

const List<String> _borderNames = [
  'border-top-width',
  'border-right-width',
  'border-bottom-width',
  'border-left-width',
  'border-top-style',
  'border-right-style',
  'border-bottom-style',
  'border-left-style',
  'border-top-color',
  'border-right-color',
  'border-bottom-color',
  'border-left-color',
];

/// 换按钮的样子，主色不变。
///
/// 实心只用简写属性（底色 + 白字），和旧面板写出来的一样。描边 / 只有字要“透明底”和“边框”，简写属性表达不了，
/// 写在样式里——所以这两种样子导出的 Flutter 代码里看不出来（Flutter 导出不读样式，本来就这样）。
void setButtonVariant(LcNode n, LcNode? parent, String variant) {
  final accent = buttonAccent(n, parent) ?? '#058654';
  _dropFromStyle(n, ['background-color', ..._borderNames]);
  if (variant == 'solid') {
    writeCommon(n, 'bg', accent.startsWith('#') ? accent.toUpperCase() : accent);
    writeCommon(n, 'color', '#FFFFFF');
    return;
  }
  writeCommon(n, 'color', accent.startsWith('#') ? accent.toUpperCase() : accent);
  writeStyleOnly(n, 'background-color', 'transparent');
  if (variant == 'outline') writeStyleOnly(n, 'border', '1px solid ${accent.toLowerCase()}');
}

/// 换按钮的主色，样子不变。
void setButtonAccent(LcNode n, LcNode? parent, String color) {
  switch (buttonVariant(n, parent)) {
    case 'solid':
      writeCommon(n, 'bg', color);
    case 'outline':
      writeCommon(n, 'color', color);
      writeStyleOnly(n, 'border', '1px solid ${color.toLowerCase()}');
    default:
      writeCommon(n, 'color', color);
  }
}

/// 文字最多几行（null＝不限）。网页里靠 `-webkit-line-clamp` 那一组四条，画布只看行数那一条。
int? textMaxLines(Map<String, String> resolved) {
  final v = int.tryParse(resolved['-webkit-line-clamp']?.trim() ?? '');
  return v == null || v < 1 ? null : v;
}

void setTextMaxLines(LcNode n, int? lines) {
  if (lines == null || lines < 1) {
    _dropFromStyle(n, const ['-webkit-line-clamp', '-webkit-box-orient']);
    if (n.style['display'] == '-webkit-box') n.style.remove('display');
    if (n.style['overflow-x'] == 'hidden' && n.style['overflow-y'] == 'hidden') _dropFromStyle(n, const ['overflow-x', 'overflow-y']);
    return;
  }
  writeStyleOnly(n, 'display', '-webkit-box');
  writeStyleOnly(n, '-webkit-box-orient', 'vertical');
  writeStyleOnly(n, '-webkit-line-clamp', '$lines');
  writeStyleOnly(n, 'overflow', 'hidden');
}

/// 图片的宽高比（`aspect-ratio`）：设了比例就不再固定高度（两样都写比例不生效）；回到“自动”时恢复默认高度。
void setImageRatio(LcNode n, String? ratio) {
  if (ratio == null) {
    writeStyleOnly(n, 'aspect-ratio', null);
    if (!n.props.containsKey('height') && !canonicalDeclarations(n.style).containsKey('height')) n.props['height'] = 160;
    return;
  }
  writeCommon(n, 'height', null);
  writeStyleOnly(n, 'aspect-ratio', ratio);
}
