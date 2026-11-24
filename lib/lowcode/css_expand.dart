/// CSS 简写属性怎么拆成单项（“规范写法”）。
///
/// 页面文件里 `style` 存的是拆开后的写法：`margin: 8px 4px` 存成四条 `margin-top/right/bottom/left`，
/// 这样可视化面板改“上边距”只动一条。拆不了的（带 `var(…)`、写法不认识）原样留着简写那一条，一条都不丢。
library;

import 'package:lopicode/lowcode/css_color.dart';
import 'package:lopicode/lowcode/css_scan.dart';

const List<String> cssSides = ['top', 'right', 'bottom', 'left'];
const List<String> cssCorners = ['top-left', 'top-right', 'bottom-right', 'bottom-left'];
const List<String> cssBorderKinds = ['width', 'style', 'color'];

const Set<String> cssBorderStyles = {'none', 'hidden', 'dotted', 'dashed', 'solid', 'double', 'groove', 'ridge', 'inset', 'outset'};

/// 边框简写里没写的部分取的默认值（CSS 规定简写会把没写的部分重置成初始值）。
const Map<String, String> cssBorderInitial = {'width': 'medium', 'style': 'none', 'color': 'currentcolor'};

/// 简写 → 它拆出来的单项，顺序固定（四边是 上 右 下 左；四角是 左上 右上 右下 左下）。
/// 不是简写、或者不拆的简写（font、background 另行处理）返回空表。
List<String> cssLonghands(String shorthand) {
  switch (shorthand) {
    case 'margin' || 'padding':
      return [for (final s in cssSides) '$shorthand-$s'];
    case 'inset':
      return cssSides;
    case 'border-radius':
      return [for (final c in cssCorners) 'border-$c-radius'];
    case 'gap':
      return const ['row-gap', 'column-gap'];
    case 'overflow':
      return const ['overflow-x', 'overflow-y'];
    case 'flex':
      return const ['flex-grow', 'flex-shrink', 'flex-basis'];
    case 'border-width' || 'border-style' || 'border-color':
      final kind = shorthand.substring(7);
      return [for (final s in cssSides) 'border-$s-$kind'];
    case 'border-top' || 'border-right' || 'border-bottom' || 'border-left':
      return [for (final k in cssBorderKinds) '$shorthand-$k'];
    case 'border':
      return [
        for (final s in cssSides)
          for (final k in cssBorderKinds) 'border-$s-$k',
      ];
  }
  return const [];
}

/// 一条简写盖住的所有条目：单项，加上范围比它小的简写（`border` 盖住 `border-top`、`border-width`）。
List<String> cssCovered(String shorthand) =>
    shorthand == 'border' ? [for (final s in cssSides) 'border-$s', for (final k in cssBorderKinds) 'border-$k', ...cssLonghands('border')] : cssLonghands(shorthand);

/// 边框简写里的一个词是宽度、样式还是颜色；判断不了返回 null。
String? cssBorderPartKind(String token) {
  final t = token.toLowerCase();
  if (isCssWideKeyword(t)) return null;
  if (cssBorderStyles.contains(t)) return 'style';
  if (t == 'thin' || t == 'medium' || t == 'thick' || RegExp(r'^[+-]?(\d|\.\d)').hasMatch(t) || RegExp(r'^(calc|min|max|clamp)\(').hasMatch(t)) return 'width';
  // 边框简写里，不是样式也不是宽度的单个英文词只可能是颜色名（没收录的颜色名也要认）。
  return isCssColor(token) || RegExp(r'^[a-z]+$').hasMatch(t) ? 'color' : null;
}

/// 1～4 个值 → 上 右 下 左（CSS 的补全规则）。
List<String>? _four(List<String> t) => switch (t.length) {
  1 => [t[0], t[0], t[0], t[0]],
  2 => [t[0], t[1], t[0], t[1]],
  3 => [t[0], t[1], t[2], t[1]],
  4 => t,
  _ => null,
};

/// 把一条简写拆成单项；拆不了返回 null（调用方原样保留这条简写）。[value] 不带 `!important`。
Map<String, String>? expandShorthand(String name, String value) {
  final names = cssLonghands(name);
  if (names.isEmpty) return null;
  // var(…) 展开后可能是好几个词，没法知道哪个词归哪一边。
  if (value.toLowerCase().contains('var(')) return null;
  final tokens = cssTokens(value);
  // 值中间夹着 `!`（比如写错位置的 !important）：拆开会得到一条只有 `!important`、没有值的单项，所以不拆。
  if (tokens.isEmpty || tokens.any((t) => t.contains('!'))) return null;
  if (tokens.length == 1 && isCssWideKeyword(tokens[0])) return {for (final n in names) n: tokens[0]};

  List<String>? values;
  switch (name) {
    case 'margin' || 'padding' || 'inset' || 'border-width' || 'border-style' || 'border-color':
      values = _four(tokens);
    case 'gap' || 'overflow':
      values = tokens.length == 1 ? [tokens[0], tokens[0]] : (tokens.length == 2 ? tokens : null);
    case 'border-radius':
      values = _radius(value);
    case 'flex':
      values = _flex(tokens);
    case 'border-top' || 'border-right' || 'border-bottom' || 'border-left':
      values = _borderParts(tokens);
    case 'border':
      final parts = _borderParts(tokens);
      values = parts == null ? null : [for (var i = 0; i < 4; i++) ...parts];
  }
  if (values == null) return null;
  return {for (var i = 0; i < names.length; i++) names[i]: values[i]};
}

/// `border-radius: 横向 1～4 个 [/ 纵向 1～4 个]`。横纵不一样的角存成 `横 纵` 两个值。
List<String>? _radius(String value) {
  final halves = splitTopLevel(value, '/');
  if (halves.length > 2) return null;
  final h = _four(cssTokens(halves[0]));
  if (h == null) return null;
  if (halves.length == 1) return h;
  final v = _four(cssTokens(halves[1]));
  if (v == null) return null;
  return [for (var i = 0; i < 4; i++) h[i] == v[i] ? h[i] : '${h[i]} ${v[i]}'];
}

/// `flex` 的几种写法 → [放大, 缩小, 基准]。
List<String>? _flex(List<String> t) {
  if (t.length == 1) {
    switch (t[0].toLowerCase()) {
      case 'none':
        return const ['0', '0', 'auto'];
      case 'auto':
        return const ['1', '1', 'auto'];
    }
    // 只写一个数字：放大系数，基准是 0%；只写一个长度：基准，放大系数是 1。
    return isCssNumber(t[0]) ? [t[0], '1', '0%'] : ['1', '1', t[0]];
  }
  if (t.length == 2 && isCssNumber(t[0])) return isCssNumber(t[1]) ? [t[0], t[1], '0%'] : [t[0], '1', t[1]];
  if (t.length == 3 && isCssNumber(t[0]) && isCssNumber(t[1])) return t;
  return null;
}

/// 边框简写的三个部分顺序任意、都可以省略 → [宽度, 样式, 颜色]，省略的补初始值。
List<String>? _borderParts(List<String> tokens) {
  if (tokens.length > 3) return null;
  final found = <String, String>{};
  for (final t in tokens) {
    final kind = cssBorderPartKind(t);
    if (kind == null || found.containsKey(kind)) return null;
    found[kind] = t;
  }
  return [for (final k in cssBorderKinds) found[k] ?? cssBorderInitial[k]!];
}

void _put(Map<String, String> out, String name, String value) {
  // 先删再放：同一条写了两遍时，位置按后写的算（认不出的属性输出时保持这个顺序）。
  out.remove(name);
  out[name] = value;
}

/// 往规范写法的表 [out] 里放一条声明，效果等于“在 CSS 里后写的这一条生效”：
/// - 能拆的简写拆成单项放进去，并删掉之前留下的、被它整个盖住的原样简写；
/// - 拆不了的简写原样放进去，并删掉之前被它盖住的单项（它们已经不生效了）；
/// - 普通属性直接放。
///
/// [value] 要是已经去过首尾空格的；`!important` 会被统一成 ` !important` 的写法，并带到拆出来的每个单项上。
void applyDeclaration(Map<String, String> out, String name, String value) {
  final parsed = splitImportant(value);
  final normalized = withImportant(parsed.value, parsed.important);
  if (parsed.value.isEmpty) return;

  if (name == 'background') {
    // background 只在“整条就是一个颜色”时翻成 background-color，其余原样保留。
    // 不管哪种，它都会重置之前写的 background-* 单项。
    out.removeWhere((k, _) => k == 'background' || k.startsWith('background-'));
    out[isCssColor(parsed.value) ? 'background-color' : 'background'] = normalized;
    return;
  }

  final covered = cssCovered(name);
  if (covered.isEmpty) {
    _put(out, name, normalized);
    return;
  }
  final expanded = expandShorthand(name, parsed.value);
  out.remove(name);
  covered.forEach(out.remove);
  if (expanded == null) {
    out[name] = normalized;
    return;
  }
  expanded.forEach((k, v) => out[k] = withImportant(v, parsed.important));
}
