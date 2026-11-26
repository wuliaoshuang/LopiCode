/// 严格规矩（规矩版本 2）的后端文档：类型检查器（lib/lang/typecheck.dart 的 T 规则）报了什么，转成校验问题。
///
/// 只有 `doc.rules >= 2` 的文档才走这里；版本 1 的文档一步都不进来，校验结果一个字不变（test/rules_v1_frozen_test.dart 钉着）。
/// 检查本身和“问题对回哪一格”只在 backend_type_bridge.dart 做一遍（`beTypeCheckShared`），这里只是把它的结果
/// 按接口 / 按“我的积木”分开、换成 [BeLangFinding]（规则号、是不是错、提示语、哪块积木哪个参数、怎么改），
/// 交给 `validateBackend`——有“错”一级的就进 `backendErrors`，生成、运行、导出都被拦住。
///
/// 和编辑器里看到的是同一批问题：编辑器（backend_type_host.dart 的 `withTypeIssues`）会用带“式子里的位置”和一键修的
/// 那一份换掉这里出的，不会出现两次。“提醒”一级（T12）不进校验结果，只在编辑器里显示。
library;

import 'package:lopicode/backend/backend_func_table.dart';
import 'package:lopicode/backend/backend_function.dart';
import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/backend/backend_type_bridge.dart';
import 'package:lopicode/backend/backend_validate_lang.dart';
import 'package:lopicode/lang/type_issue.dart';

/// 这些规则说的是整块积木（不是它的某一格）。
const Set<String> _wholeBlock = {'T03', 'T04', 'T10'};

/// 是不是类型规则的规则号（T01…T18）。
bool beIsTypeRule(String? code) => code != null && code.length == 3 && code.startsWith('T') && int.tryParse(code.substring(1)) != null;

List<BeLangFinding> _of(BeDocument doc, String treeId) {
  final check = beTypeCheckShared(doc);
  if (check == null) return const [];
  final out = <BeLangFinding>[];
  for (final f in check.findings) {
    final i = f.issue;
    if (f.at.treeId != treeId || i.level == LTypeLevel.hint) continue;
    final labels = [for (final x in f.fixes) x.fix.label];
    final fix = labels.isEmpty ? i.rule.advice : '${i.rule.advice}（可以直接点：${labels.join(' / ')}）';
    final arg = _wholeBlock.contains(i.code) ? null : f.at.arg;
    out.add(BeLangFinding(i.code, i.isError, f.problem, f.at.path, arg, fix, exprPath: arg == null ? null : f.at.exprPath));
  }
  return out;
}

/// 一个接口的类型问题。不是严格规矩的文档：空表。
List<BeLangFinding> beTypeFindings(BeDocument doc, BeRoute route, {BeFuncTable? table}) => _of(doc, route.id);

/// 一块“我的积木”的定义里的类型问题。
List<BeLangFinding> beFuncTypeFindings(BeDocument doc, BeFuncTable table, BeFunction f) => _of(doc, f.id);
