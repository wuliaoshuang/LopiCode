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
  final css = names.isEmpty ? null : _cssValue(prop, value);
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
