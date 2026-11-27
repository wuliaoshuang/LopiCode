/// 主题变量和断点怎么写进导出的 CSS（普通网页、Vue 3、React 三种共用；Flutter 的在 export_dart_live_tree.dart）。
///
/// - 主题变量：一段 `:root { --名字: 值; … }`（CSS 自定义属性）。**项目里有变量、而且真的有地方用到了才写**——
///   没用主题变量的页面导出来一个字节都不多。
/// - 断点：每一档一段 `@media (min-width: 768px) { … }`，放在样式的最后（同样的选择器，后写的赢）。
///   里面每个节点一条规则，内容是“这一档的最终样式和上一档比，哪几条不一样”。
library;

import 'package:lopicode/lowcode/css_codec.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/responsive.dart';
import 'package:lopicode/lowcode/style_resolve.dart';
import 'package:lopicode/lowcode/theme_vars.dart';

final RegExp _unsafe = RegExp(r'[{}<>\n\r\\]|\*/|/\*');

/// 主题变量那一段 CSS；项目没有变量返回空串。
String lcThemeRootCss(LcDocument doc) {
  final t = lcThemeOf(doc);
  final lines = [
    for (final e in t.values.entries)
      if (!_unsafe.hasMatch(e.value)) '  --${e.key}: ${e.value};',
  ];
  if (lines.isEmpty) return '';
  return '/* 主题变量：改这里的值，用到的地方都跟着变 */\n:root {\n${lines.join('\n')}\n}\n';
}

/// 整个项目里有没有地方用到变量（任何页面、任何自定义组件）。
bool lcProjectUsesVars(LcDocument doc) {
  var used = false;
  lcEachStyleMap(doc, (decl) {
    if (!used && decl.values.any((v) => v is String && v.contains('var(--'))) used = true;
  });
  return used;
}

/// Vue / React 用：要不要写、写什么（项目有变量并且用到了才有内容）。
String lcThemeCssIfUsed(LcDocument doc) => lcProjectUsesVars(doc) ? lcThemeRootCss(doc) : '';

/// 一棵树导出时攒着的断点规则。
class LcBpCss {
  final Map<String, List<String>> _rules = {};

  /// 记下 [n] 在各档的规则（没有断点样式的节点什么都不记）。[parent] 的意思同 resolvedStyle。
  void add(LcNode n, LcNode? parent, String selector) {
    if (n.more['responsive'] == null || !lcHasBp(n)) return;
    var prev = resolvedStyle(n, parent);
    var acc = n.style;
    for (final bp in kLcBreakpoints) {
      final own = lcBpStyle(n, bp);
      if (own.isEmpty) continue;
      acc = {...acc, ...own};
      final cur = resolvedStyle(LcNode(id: n.id, type: n.type, props: n.props, children: n.children, style: acc, more: n.more)..instSlots = n.instSlots, parent);
      final diff = <String, String>{
        for (final e in cur.entries)
          if (prev[e.key] != e.value) e.key: e.value,
        // 上一档有、这一档没了的（比如设了固定宽度以后不再“撑满”）：明说回到初始值。
        for (final k in prev.keys)
          if (!cur.containsKey(k)) k: 'initial',
      };
      prev = cur;
      final body = declarationsToCss(diff, multiline: false);
      if (body.isEmpty || _unsafe.hasMatch(body)) continue;
      (_rules[bp] ??= []).add('$selector { $body }');
    }
  }

  bool get isEmpty => _rules.isEmpty;

  /// 攒下来的规则写成 CSS（没有是空串）。
  String css() {
    final out = StringBuffer();
    for (final bp in kLcBreakpoints) {
      final rules = _rules[bp];
      if (rules == null) continue;
      out.writeln('/* ${kLcBpLabels[bp]}及更宽（≥${kLcBpMinWidth[bp]}px） */');
      out.writeln('@media (min-width: ${kLcBpMinWidth[bp]}px) {');
      for (final r in rules) {
        out.writeln('  $r');
      }
      out.writeln('}');
    }
    return out.toString();
  }
}
