/// CSS 声明文本 ↔ 规范写法的属性表（就是 `LcNode.style` 存的那种表）。
///
/// - [parseCss] / [parseDeclarations]：人写的 CSS → 表。简写拆成单项，认不出的属性原样保留。
/// - [declarationsToCss] / [mergedDeclarations]：表 → 给人看的 CSS。能合并的单项合并回简写，输出顺序固定。
/// - [mergeDeclarations] / [canonicalDeclarations]：一张表盖到另一张表上（算最终样式用）。
///
/// 两个方向往返稳定：`parseDeclarations(declarationsToCss(x))` 和 `x` 是同一张表（`x` 是规范写法时）。
/// 为了做到这一点，合并只在“拆回来一定还是原样”的时候才做，拿不准就保持单项。
library;

import 'package:lopicode/lowcode/css_color.dart';
import 'package:lopicode/lowcode/css_expand.dart';
import 'package:lopicode/lowcode/css_scan.dart';
import 'package:lopicode/lowcode/model.dart';

export 'package:lopicode/lowcode/css_expand.dart' show applyDeclaration, cssCorners, cssLonghands, cssSides;

class CssParseResult {
  const CssParseResult(this.declarations, this.dropped);

  /// 规范写法的属性表。里面每一条都过得了 `LcNode.cleanStyle`（存进页面文件再读出来不会少）。
  final Map<String, String> declarations;

  /// 没收下的条目，每条是“原文（原因）”，给界面提示用户用。
  final List<String> dropped;
}

final RegExp _cssName = RegExp(r'^-{0,2}[a-z][a-z0-9-]{0,63}$');
final RegExp _forbidden = RegExp(r'[{};\n\r<>]');

String _short(String text) {
  final t = text.trim().replaceAll(RegExp(r'\s+'), ' ');
  return t.length > 80 ? '${t.substring(0, 80)}…' : t;
}

/// 解析一段 CSS 声明（`a: b; c: d`），也接受外面包着 `选择器 { … }` 的一条规则和 `/* 注释 */`。
/// 对任何输入都不抛异常。
///
/// 会被丢掉并记进 [CssParseResult.dropped] 的：没有冒号、属性名不合法、没有值、
/// 值里有 `{ } ; < >` 或引号里有换行、值超过 500 个字符（都和 `LcNode.cleanStyle` 的规矩一致，
/// 免得这里收下了、存盘再读又悄悄没了）；以及第一条规则后面的其他规则。
///
/// 自己定的两处宽松：属性名一律转小写；引号外面的换行和连续空白收成一个空格（意思不变，多行写的值就不会被丢）。
CssParseResult parseCss(String css) {
  final out = <String, String>{};
  final dropped = <String>[];
  final rule = cssRuleBody(stripCssComments(css));
  if (rule.rest.trim().isNotEmpty) dropped.add('${_short(rule.rest)}（只读第一条规则，后面的没有读）');

  for (final piece in splitTopLevel(rule.body, ';')) {
    if (piece.trim().isEmpty) continue;
    final colon = piece.indexOf(':');
    if (colon < 0) {
      dropped.add('${_short(piece)}（没有冒号，不是一条声明）');
      continue;
    }
    final name = piece.substring(0, colon).trim().toLowerCase();
    final value = collapseCssSpace(piece.substring(colon + 1));
    final String? reason;
    if (!_cssName.hasMatch(name)) {
      reason = '属性名不合法';
    } else if (splitImportant(value).value.isEmpty) {
      reason = '没有值';
    } else if (_forbidden.hasMatch(value)) {
      reason = '值里不能有 { } ; < > 和换行';
    } else if (value.length > 500) {
      reason = '值太长（最多 500 个字符）';
    } else if (LcNode.cleanStyle({name: value}).isEmpty) {
      // 上面几条和模型的规矩是一一对应的；这里再让模型自己判一次，哪天模型的规矩改了也不会漏。
      reason = '页面文件存不下这种写法';
    } else {
      reason = null;
    }
    if (reason != null) {
      dropped.add('${_short(piece)}（$reason）');
      continue;
    }
    applyDeclaration(out, name, value);
  }
  return CssParseResult(out, dropped);
}

/// [parseCss] 只要属性表的简便写法。
Map<String, String> parseDeclarations(String css) => parseCss(css).declarations;

/// 把一张可能没拆简写的表（比如 Agent 直接写进页面文件的 `style`）整理成规范写法。
Map<String, String> canonicalDeclarations(Map<String, String> decl) => mergeDeclarations(const {}, decl);

/// [over] 盖在 [base] 上：同名的盖掉；[over] 里的简写会按 CSS 的规矩盖掉 [base] 里它管的那些单项。
/// 返回新表，不改传进来的两张。
Map<String, String> mergeDeclarations(Map<String, String> base, Map<String, String> over) {
  final out = <String, String>{};
  for (final table in [base, over]) {
    table.forEach((name, value) {
      final v = value.trim();
      if (v.isNotEmpty) applyDeclaration(out, name, v);
    });
  }
  return out;
}

/// 输出顺序（固定）。写的是“位置”：简写的位置上也放它拆出来的单项。认不出的属性排在最后，保持表里原来的顺序。
/// 为什么是这个顺序：第 1 版导出的 CSS 就是 伸缩 → 宽高 → 内外边距 → 背景 → 文字颜色 → 圆角 → 字 → 间距 → 对齐，
/// 没有 `style` 的节点必须和以前导出得一模一样，所以新属性都插在不打乱这个次序的地方。
const List<String> _order = [
  'position', 'inset', 'z-index', 'display', 'flex-direction', 'flex-wrap', 'flex', 'align-self', //
  'width', 'min-width', 'max-width', 'height', 'min-height', 'max-height', 'padding', 'margin', 'border', //
  'background', 'color', 'opacity', 'border-radius', 'box-shadow', //
  'font', 'font-family', 'font-size', 'font-weight', 'font-style', 'line-height', 'letter-spacing', 'text-align', 'text-decoration', 'text-decoration-line', //
  'gap', 'align-items', 'justify-content', 'overflow',
];

/// 四个值（上 右 下 左）写成最短的 1～4 个值。
String _minimal4(List<String> v) {
  if (v[1] != v[3]) return v.join(' ');
  if (v[0] != v[2]) return '${v[0]} ${v[1]} ${v[2]}';
  return v[0] == v[1] ? v[0] : '${v[0]} ${v[1]}';
}

/// 一组单项能不能合并：都在、`!important` 一致、每个值都是单独一个词、不带 `var(` 和最外层的 `/`
/// （这些拆回来会变样）；有全局关键字（inherit 等）时必须全都是同一个。
({List<String> values, bool important})? _group(Map<String, String> decl, List<String> names) {
  final values = <String>[];
  bool? important;
  for (final n in names) {
    final raw = decl[n];
    if (raw == null) return null;
    final p = splitImportant(raw);
    if (important != null && important != p.important) return null;
    important = p.important;
    if (cssTokens(p.value).length != 1 || p.value.toLowerCase().contains('var(') || splitTopLevel(p.value, '/').length > 1) return null;
    values.add(p.value);
  }
  if (values.any(isCssWideKeyword) && values.any((v) => v != values.first)) return null;
  return (values: values, important: important ?? false);
}

/// [宽度, 样式, 颜色] → 边框简写的值；拆回来会变样的返回 null。和初始值一样的部分省掉不写。
String? _borderText(List<String> v) {
  if (isCssWideKeyword(v[0])) return v[0];
  final parts = <String>[];
  for (var i = 0; i < 3; i++) {
    final kind = cssBorderKinds[i];
    if (cssBorderPartKind(v[i]) != kind) return null;
    if (v[i] != cssBorderInitial[kind]) parts.add(v[i]);
  }
  return parts.isEmpty ? 'none' : parts.join(' ');
}

/// 合并简写、排好顺序后的声明列表（属性名 → 值）。给要自己排版的调用方用（比如 React 的行内样式）。
List<MapEntry<String, String>> mergedDeclarations(Map<String, String> decl) {
  final out = <MapEntry<String, String>>[];
  final done = <String>{};
  void emit(String name, String value) => out.add(MapEntry(name, value));
  void single(String name) {
    final v = decl[name];
    if (v != null && done.add(name)) emit(name, v);
  }

  // 一组单项：能合并就输出 [short]，不能就各自输出。拆不了而原样留着的简写排在它的单项前面（后写的单项才能盖住它）。
  void group(String short, String Function(List<String>) text) {
    single(short);
    final names = cssLonghands(short);
    final g = _group(decl, names);
    if (g == null) {
      names.forEach(single);
    } else {
      done.addAll(names);
      emit(short, withImportant(text(g.values), g.important));
    }
  }

  void flex() {
    single('flex');
    final names = cssLonghands('flex');
    final g = _group(decl, names);
    final v = g?.values;
    // 放大、缩小必须是数字才合并：`flex: calc(…)` 拆回来会被当成基准。
    if (g == null || v == null || !(isCssWideKeyword(v[0]) || (isCssNumber(v[0]) && isCssNumber(v[1])))) {
      names.forEach(single);
      return;
    }
    done.addAll(names);
    final text = isCssWideKeyword(v[0]) || (v[1] == '1' && v[2] == '0%') ? v[0] : v.join(' ');
    emit('flex', withImportant(text, g.important));
  }

  void border() {
    single('border');
    for (final k in cssBorderKinds) {
      single('border-$k');
    }
    for (final s in cssSides) {
      single('border-$s');
    }
    final all = _group(decl, cssLonghands('border'));
    if (all != null) {
      final v = all.values;
      final same = [for (var i = 3; i < 12; i++) v[i] == v[i % 3]].every((x) => x);
      final text = same ? _borderText(v.sublist(0, 3)) : null;
      if (text != null) {
        done.addAll(cssLonghands('border'));
        emit('border', withImportant(text, all.important));
        return;
      }
    }
    // 四边不一样：哪一边三样齐全就写成 border-top 这种；剩下的按“四边的宽度 / 样式 / 颜色”再试着合并。
    for (final s in cssSides) {
      final names = cssLonghands('border-$s');
      final g = _group(decl, names);
      final text = g == null ? null : _borderText(g.values);
      if (g != null && text != null) {
        done.addAll(names);
        emit('border-$s', withImportant(text, g.important));
      }
    }
    for (final k in cssBorderKinds) {
      final names = cssLonghands('border-$k');
      final g = names.any(done.contains) ? null : _group(decl, names);
      if (g == null) {
        names.forEach(single);
      } else {
        done.addAll(names);
        emit('border-$k', withImportant(_minimal4(g.values), g.important));
      }
    }
  }

  void background() {
    single('background');
    final color = decl['background-color'];
    if (color == null) return;
    // 单独一个背景色写成 `background: 颜色`（第 1 版一直这么导出）；
    // 同时有别的 background-* 时不能这么写，简写会把它们重置掉。
    final alone = !decl.keys.any((k) => k == 'background' || (k.startsWith('background-') && k != 'background-color'));
    if (alone && isCssColor(splitImportant(color).value)) {
      done.add('background-color');
      emit('background', color);
    } else {
      single('background-color');
    }
  }

  String pair(List<String> v) => v[0] == v[1] ? v[0] : '${v[0]} ${v[1]}';
  for (final slot in _order) {
    switch (slot) {
      case 'margin' || 'padding' || 'inset' || 'border-radius':
        group(slot, _minimal4);
      case 'gap' || 'overflow':
        group(slot, pair);
      case 'flex':
        flex();
      case 'border':
        border();
      case 'background':
        background();
      default:
        single(slot);
    }
  }
  decl.keys.forEach(single);
  return out;
}

/// 属性表 → 给人看的 CSS 声明文本。合并和顺序见 [mergedDeclarations]。
/// [multiline] 为 true 时一行一条（每行前面加 [indent]），否则全部写在一行、用空格隔开；每条都以分号结尾。空表返回空串。
String declarationsToCss(Map<String, String> decl, {bool multiline = true, String indent = ''}) {
  final lines = [for (final e in mergedDeclarations(decl)) '${multiline ? indent : ''}${e.key}: ${e.value};'];
  return lines.join(multiline ? '\n' : ' ');
}
