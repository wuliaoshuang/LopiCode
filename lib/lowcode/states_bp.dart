/// 状态样式分屏宽（第四轮 B5；格式见 docs/lowcode-page-format-v3.md）。
///
/// 存法：`responsive.<档>.states.<状态>`——这一档上，这个状态的样子和“更窄的屏上这个状态的样子”不一样的那几条。
/// 和普通样式一个规矩：手机优先，宽的档叠在窄的上面。只管三种状态（按下 / 禁用 / 聚焦）；
/// “类名成立时的样子”不分屏宽（那是一条带类名的规则，要分屏宽请直接在各档改平时的样子）。
/// 网页类导出写在各档的 `@media` 里（export_theme_bp.dart）；Flutter 导出不带这一部分（会在说明里写一句）。
library;

import 'package:lopicode/lowcode/css_codec.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/responsive.dart';
import 'package:lopicode/lowcode/states.dart';

/// [bp] 这一档自己给 [state] 记的差别；没有是空表。
Map<String, String> lcBpStateStyle(LcNode n, String bp, String state) {
  final all = n.more['responsive'];
  final b = all is Map ? all[bp] : null;
  final states = b is Map ? b['states'] : null;
  final s = states is Map ? states[state] : null;
  if (s is! Map) return const {};
  return {
    for (final e in s.entries)
      if (e.value is String) '${e.key}': e.value as String,
  };
}

/// 有没有在任何一档给任何状态写过差别。
bool lcHasBpStates(LcNode n) => n.more['responsive'] != null && kLcBreakpoints.any((b) => kLcStateNames.any((s) => lcBpStateStyle(n, b, s).isNotEmpty));

/// 能不能分屏宽设：三种状态能；类名开关那种不能。
bool lcStateSplitsByBp(String? state) => state != null && kLcStateNames.contains(state);

/// 在 [bp] 这一档看，[state] 时和平时不一样的全部声明（手机上这个状态的 + 更窄各档的 + 这一档的）。[bp] 是 null＝手机。
Map<String, String> lcStateStyleAt(LcNode n, String state, String? bp) {
  final base = lcStateStyle(n, state);
  if (bp == null || !lcStateSplitsByBp(state) || n.more['responsive'] == null) return base;
  var out = canonicalDeclarations(base);
  var any = false;
  for (final b in kLcBreakpoints) {
    final own = lcBpStateStyle(n, b, state);
    if (own.isNotEmpty) {
      out = mergeDeclarations(out, own);
      any = true;
    }
    if (b == bp) break;
  }
  return any ? out : base;
}

/// 把 [bp] 这一档上 [state] 的差别整个换成 [decl]；空表＝清掉。这一档别的东西（普通样式、别的状态）原样留着；都空了字段也去掉。
void lcReplaceBpState(LcNode n, String bp, String state, Map<String, String> decl) {
  final old = n.more['responsive'];
  final all = <String, dynamic>{
    if (old is Map)
      for (final e in old.entries) '${e.key}': e.value,
  };
  final cur = all[bp];
  final entry = <String, dynamic>{
    if (cur is Map)
      for (final e in cur.entries) '${e.key}': e.value,
  };
  final curStates = entry['states'];
  final states = <String, dynamic>{
    if (curStates is Map)
      for (final e in curStates.entries) '${e.key}': e.value,
  };
  final curDecl = states[state];
  // 读不懂的条目（值不是字符串的）原样留着。
  final next = <String, dynamic>{
    if (curDecl is Map)
      for (final e in curDecl.entries)
        if (e.value is! String) '${e.key}': e.value,
    ...decl,
  };
  if (next.isEmpty) {
    states.remove(state);
  } else {
    states[state] = next;
  }
  if (states.isEmpty) {
    entry.remove('states');
  } else {
    entry['states'] = states;
  }
  if (entry.isEmpty) {
    all.remove(bp);
  } else {
    all[bp] = entry;
  }
  if (all.isEmpty) {
    n.more.remove('responsive');
  } else {
    n.more['responsive'] = all;
  }
}

/// 在 [bp] 这一档上改 [state] 的样子：[change] 拿到的是“这一档上这个状态看到的整份”，
/// 改完只把和下面那几层（手机上这个状态的、更窄各档的）不一样的记成这一档的差别。
void lcEditStateAtBp(LcNode n, String bp, String state, void Function(Map<String, String> style) change) {
  var below = canonicalDeclarations(lcStateStyle(n, state));
  for (final b in kLcBreakpoints) {
    if (b == bp) break;
    below = mergeDeclarations(below, lcBpStateStyle(n, b, state));
  }
  final seen = mergeDeclarations(below, lcBpStateStyle(n, bp, state));
  change(seen);
  lcReplaceBpState(n, bp, state, {
    for (final e in seen.entries)
      if (below[e.key] != e.value) e.key: e.value,
  });
}
