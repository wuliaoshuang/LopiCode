/// Flutter 导出怎么对待主题变量和断点（如实处理，局限写在导出文件的开头）。
///
/// Flutter 导出一直只读简写属性（底色、文字颜色、字号、内外边距、圆角、间距、宽高），不读样式。
/// 主题变量是写在样式里的（`background-color: var(--color-primary)`），所以导出前先做一步：
/// 把“整个值就是变量、而且简写属性表达得了”的那几条换成变量**现在的值**放进简写属性（只在一份副本上，不改文档）。
/// 结果：导出的代码里是写死的值，以后改了变量要重新导出。断点（屏幕更宽时的差别）不导出——导出的是手机的样子。
/// 项目里既没用变量也没用断点时，这一步什么都不做，导出结果和以前逐字节一样。
library;

import 'package:lopicode/lowcode/css_codec.dart';
import 'package:lopicode/lowcode/inspector_write.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/responsive.dart';
import 'package:lopicode/lowcode/theme_vars.dart';

const List<String> _numProps = ['padding', 'margin', 'radius', 'gap', 'fontSize', 'height', 'width'];
const List<String> _colorProps = ['bg', 'color'];
final RegExp _px = RegExp(r'^(-?\d+(?:\.\d+)?)px$');
final RegExp _hex = RegExp(r'^#[0-9a-fA-F]{6}$');

/// 一个节点：样式里用变量的那几条能换成简写属性的，返回换好的简写属性；没有返回 null。
Map<String, dynamic>? _folded(LcNode n, Map<String, String> vars) {
  if (n.style.isEmpty || !n.style.values.any((v) => v.contains('var(--'))) return null;
  final own = canonicalDeclarations(n.style);
  Map<String, dynamic>? props;
  for (final prop in [..._numProps, ..._colorProps]) {
    final names = prop == 'width' ? const ['width'] : legacyPropCssNames(prop);
    final raw = {for (final name in names) own[name]};
    if (raw.length != 1 || raw.first == null || !raw.first!.contains('var(--')) continue;
    final value = lcSubstVars(raw.first!, vars).trim();
    final Object? v;
    if (_colorProps.contains(prop)) {
      v = _hex.hasMatch(value) ? value.toUpperCase() : null;
    } else {
      final m = _px.firstMatch(value);
      final d = m == null ? null : double.parse(m[1]!);
      v = d == null ? null : (d == d.roundToDouble() ? d.round() : d);
    }
    if (v != null) (props ??= {...n.props})[prop] = v;
  }
  return props;
}

/// 导出 Flutter 用的树：用到变量的地方换成现在的值。没什么可换的返回 [root] 本身。
LcNode dartThemeTree(LcNode root, LcDocument doc) {
  final vars = lcThemeOf(doc).values;
  if (vars.isEmpty) return root;
  LcNode walk(LcNode n) {
    final kids = [for (final c in n.children) walk(c)];
    final props = _folded(n, vars);
    var same = props == null;
    for (var i = 0; same && i < kids.length; i++) {
      same = identical(kids[i], n.children[i]);
    }
    if (same) return n;
    return LcNode(
      id: n.id,
      type: n.type,
      props: props ?? n.props,
      children: kids,
      style: n.style,
      bind: n.bind,
      name: n.name,
      locked: n.locked,
      hidden: n.hidden,
      keptProps: n.keptProps,
      more: n.more,
      raw: n.raw,
    )..instSlots = n.instSlots;
  }

  return walk(root);
}

/// 导出文件开头要不要加说明、加什么（没用变量也没用断点时是空串）。
String dartThemeHeader(LcDocument doc) {
  var usesVars = false, usesBp = false;
  lcEachStyleMap(doc, (decl) {
    if (!usesVars && decl.values.any((v) => v is String && v.contains('var(--'))) usesVars = true;
  });
  void node(LcNode n) {
    if (lcHasBp(n)) usesBp = true;
    n.children.forEach(node);
  }

  for (final p in doc.pages) {
    node(p.root);
  }
  for (final c in doc.components) {
    node(c.root);
  }
  return [if (usesVars) '// 主题变量：这里写的是导出那一刻的值（底色、文字颜色、字号、内外边距、圆角、间距、宽高认得；别的样式本来就不导出）。改了变量要重新导出。\n', if (usesBp) '// 断点：屏幕更宽时（平板、桌面）的样式差别没有导出，这里是手机的样子。\n'].join();
}
