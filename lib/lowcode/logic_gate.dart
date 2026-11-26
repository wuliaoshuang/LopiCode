/// 页面的积木逻辑有“错误”时怎么办（和后端积木一个规矩）：不导出新的 logic.js，上一次导出的原样留着；
/// 页面文件、index.html、style.css 照常保存（版面和样式不受逻辑的错误连累）。只有“警告”时照常导出。
///
/// 存盘（lib/agent/agent_tools.dart 的 saveLowcodePage）、Vue / React 导出（export_sheet.dart）、
/// Agent 的页面工具都从这里问，文案也从这里拿，免得各说各的。
library;

import 'package:lopicode/lowcode/logic_validate.dart';
import 'package:lopicode/lowcode/model.dart';

/// 逻辑里“错误”级的问题有几条。大于 0＝logic.js 不更新、框架导出被拦下。
int lcLogicErrorCount(LcDocument doc) => logicErrors(doc).length;

/// 导出被拦下时说的那句话（Vue / React 导出面板用）。
String lcExportBlockedText(int errors) => '没有导出：积木逻辑里有 $errors 个错误，代码没有更新。回到“积木逻辑”，点右上角的“问题”，把标红的积木修好再导出。';

/// 给模型看的校验结果（接在页面工具的结果后面）。没有问题返回空字符串。
/// 有错误时说清楚 logic.js 没有更新；每条带规则编号、在哪、什么问题、建议怎么改。
///
/// 多页面时每一页都查（逻辑是每页各一份）：每条前面带上是哪一页；“脚本没有更新”说的是出错的那几页各自的脚本。
String lcLogicToolReport(LcDocument doc, {int limit = 20}) {
  final issues = <LcLogicIssue>[];
  final pageOf = <LcLogicIssue, String>{};
  final keep = doc.pageIndex;
  for (var i = 0; i < doc.pages.length; i++) {
    doc.openPageAt(i);
    for (final issue in validateLogic(doc)) {
      issues.add(issue);
      if (doc.isMultiPage) pageOf[issue] = '【${doc.page.title}】';
    }
  }
  doc.openPageAt(keep);
  if (issues.isEmpty) return '';
  String line(LcLogicIssue i) => '- ${pageOf[i] ?? ''}[${i.rule}] ${i.where}——${i.problem}${i.advice.isEmpty ? '' : '（建议：${i.advice}）'}';
  final errors = [
    for (final i in issues)
      if (i.isError) i,
  ];
  final warnings = [
    for (final i in issues)
      if (!i.isError) i,
  ];
  final out = StringBuffer();
  if (errors.isNotEmpty) {
    out.write('\n注意：积木逻辑里有 ${errors.length} 个错误，logic.js 没有更新（上一次导出的原样留着）；页面文件、index.html、style.css 已保存。修好下面的错误后再调一次本工具：');
    for (final i in errors.take(limit)) {
      out.write('\n${line(i)}');
    }
    if (errors.length > limit) out.write('\n- ……还有 ${errors.length - limit} 个错误');
  }
  if (warnings.isNotEmpty) {
    out.write('\n提醒（不影响导出）：');
    for (final i in warnings.take(limit)) {
      out.write('\n${line(i)}');
    }
    if (warnings.length > limit) out.write('\n- ……还有 ${warnings.length - limit} 条提醒');
  }
  return out.toString();
}
