// 设计约束（问题列表 · 390×844）— 2026-11-24
// - 一行一个问题：左边红色（错误）或黄色（警告）的标记，先说问题本身，下面一行弱化的“在哪”。
// - 点一行＝关掉面板、跳到那个处理并选中那块积木。没有别的操作。
import 'package:lopicode/lowcode/logic_pick_sheet.dart';
import 'package:lopicode/lowcode/logic_validate.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// 列出校验问题；点了某条返回它。[title] 默认是整页的说法，单看一块积木时换一个。
Future<LcLogicIssue?> showLcIssuesSheet(BuildContext context, List<LcLogicIssue> issues, {String? title, bool jump = true}) {
  final errors = issues.where((i) => i.isError).length;
  final warnings = issues.length - errors;
  return showLcSheet<LcLogicIssue>(
    context,
    (sheet) => LcSheetFrame(
      title: title ?? '有 ${issues.length} 个问题',
      note: [if (errors > 0) '$errors 个错误（导出后不会按想的那样工作）', if (warnings > 0) '$warnings 个提醒', if (jump) '点一条跳过去'].join(' · '),
      children: [for (var i = 0; i < issues.length; i++) _IssueRow(key: ValueKey('lc-issue-row-$i'), issue: issues[i], onTap: jump ? () => Navigator.pop(sheet, issues[i]) : null)],
    ),
  );
}

class _IssueRow extends StatelessWidget {
  const _IssueRow({super.key, required this.issue, required this.onTap});
  final LcLogicIssue issue;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.x4, vertical: Space.x2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(issue.isError ? Icons.error_outline_rounded : Icons.warning_amber_rounded, size: 20, color: issue.isError ? c.danger : c.warning),
            ),
            const SizedBox(width: Space.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(issue.problem, style: t.bodyLarge?.copyWith(color: c.text)),
                  const SizedBox(height: 2),
                  Text(issue.where, maxLines: 3, overflow: TextOverflow.ellipsis, style: t.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
