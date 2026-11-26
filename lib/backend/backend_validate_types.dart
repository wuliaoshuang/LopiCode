/// 严格规矩（规矩版本 2）的后端文档：类型检查器（lib/lang/typecheck.dart 的 T 规则）报了什么，对回到积木上。
///
/// 只有 `doc.rules >= 2` 的文档才走这里；版本 1 的文档一步都不进来，校验结果一个字不变（test/rules_v1_frozen_test.dart 钉着）。
/// 这里只出数据（[BeLangFinding]：规则号、是不是错、提示语、哪块积木哪一格、怎么改）；标红、一键修的界面不在这个文件。
/// 对法和 backend_validate_lang.dart 的 `beMapLangIssues` 一样：靠翻译时记的来源表（`BeLangSpot`）。
///
/// 现在检查到哪：用到第 4 版积木的接口（整个接口翻成了语法树的那些）和“我的积木”的定义。只用旧积木的接口没有语法树，不查。
/// 文档里声明的变量、“这次请求”一律按“任意”（宿主绑定的签名还没定，设计 GAP-B-6）；旧的“干活”积木（返回响应、数据集合…）
/// 检查器整句跳过。
library;

import 'package:lopicode/backend/backend_func_table.dart';
import 'package:lopicode/backend/backend_function.dart';
import 'package:lopicode/backend/backend_ir.dart';
import 'package:lopicode/backend/backend_lang.dart';
import 'package:lopicode/backend/backend_lower_lang.dart';
import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/backend/backend_validate_lang.dart';
import 'package:lopicode/lang/ast.dart';
import 'package:lopicode/lang/rules.dart';
import 'package:lopicode/lang/type_issue.dart';
import 'package:lopicode/lang/typecheck.dart';
import 'package:lopicode/lang/types.dart';

/// 这些规则说的是整块积木（不是它的某一格）。
const Set<String> _wholeBlock = {'T03', 'T04', 'T10'};

/// 类型检查器报的问题 → 对回到积木上。[spots] 是翻译时记的来源表；[script] 给了就只要这一串的。
/// “提醒”一级（T12）不进校验结果：它不拦运行，留给界面自己决定要不要显示。
List<BeLangFinding> beMapTypeIssues(Iterable<LTypeIssue> issues, List<BeLangSpot> spots, {String? script}) {
  final out = <BeLangFinding>[];
  for (final i in issues) {
    if (i.level == LTypeLevel.hint) continue;
    if (script != null && i.src?.script != script) continue;
    final problem = i.message.replaceAll('“req”', '“这次请求”').replaceAll('「req」', '“这次请求”');
    final labels = [for (final f in i.fixes) f.label];
    final fix = labels.isEmpty ? i.rule.advice : '${i.rule.advice}（可以直接点：${labels.join(' / ')}）';
    final at = int.tryParse(i.src?.block ?? '');
    if (at == null || at < 0 || at >= spots.length) {
      if (script != null) out.add(BeLangFinding(i.code, i.isError, problem, const [], null, fix));
      continue;
    }
    final spot = spots[at];
    out.add(BeLangFinding(i.code, i.isError, problem, spot.path, _wholeBlock.contains(i.code) ? null : spot.arg, fix));
  }
  return out;
}

Map<String, LType> _outer(BeDocument doc) => {for (final v in doc.variables) v.name: LType.any, kBeRequestName: LType.any};

List<LDecl> _decls(BeFuncTable? table) => table == null ? const [] : [for (final f in table.lowered) f.decl];

/// 一个接口的类型问题。不是严格规矩的文档、没用到第 4 版积木的接口：空表。
List<BeLangFinding> beTypeFindings(BeDocument doc, BeRoute route, {BeFuncTable? table}) {
  if (!langRulesStrict(doc.rules)) return const [];
  try {
    final lang = beLangLowerOf(doc, route, shadow: true);
    if (lang == null) return const [];
    final stmts = lang.stmts(route.body, const [], 0);
    final result = checkTypes(decls: _decls(table), scripts: [LTypeScript(route.id, stmts)], outer: _outer(doc));
    return beMapTypeIssues(result.issues, lang.spots, script: route.id);
  } on Object {
    // 检查器自己出了岔子不该让整个校验崩掉：当成没有类型问题，别的检查照常。
    return const [];
  }
}

/// 一块“我的积木”的定义里的类型问题。
List<BeLangFinding> beFuncTypeFindings(BeDocument doc, BeFuncTable table, BeFunction f) {
  if (!langRulesStrict(doc.rules)) return const [];
  try {
    final lowered = table.lowered.where((l) => identical(l.function, f)).firstOrNull;
    if (lowered == null) return const [];
    final result = checkTypes(decls: _decls(table), outer: _outer(doc));
    return beMapTypeIssues(result.issues, lowered.spots, script: f.id);
  } on Object {
    // 同上。
    return const [];
  }
}
