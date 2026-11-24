// 设计约束（问题列表 / 看代码 两张底部面板，390 宽，浅色 + 深色）— 2026-11-24
// - 问题列表：标题一行（“N 个问题”），下面每条一行：红 / 黄小圆点 + 一句完整的话；能定位到积木的那几条右边带一个小箭头，
//   点了就关掉面板、画布跳到那块积木并闪一下。没有问题时只有一句“没有问题”。主操作＝点一条去修。
// - 看代码：整张面板就是只读的代码（等宽字），标题写是什么语言；一块积木都没有时给一句说明而不是空白。
import 'package:lopicode/blocks/block_host.dart';
import 'package:lopicode/lowcode/code_sheet.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// 弹出问题列表；点了能定位的一条就返回它。
Future<BlockIssue?> showBlockIssues(BuildContext context, List<BlockIssue> issues) {
  return showModalBottomSheet<BlockIssue>(
    context: context,
    isScrollControlled: true,
    builder: (sheet) {
      final c = sheet.colors;
      final t = Theme.of(sheet).textTheme;
      return SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheet).height * 0.7),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x2),
                child: Text(issues.isEmpty ? '没有问题' : '${issues.length} 个问题', style: t.titleMedium),
              ),
              if (issues.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x6),
                  child: Text(
                    '积木都拼好了，可以放心用。',
                    key: const ValueKey('bk-issues-none'),
                    style: t.bodyMedium?.copyWith(color: c.textMuted),
                  ),
                )
              else
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.only(bottom: Space.x4),
                    children: [
                      for (var i = 0; i < issues.length; i++)
                        InkWell(
                          key: ValueKey('bk-issue-$i'),
                          onTap: issues[i].scriptId == null ? null : () => Navigator.pop(sheet, issues[i]),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: Space.x4, vertical: 12),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(color: issues[i].isError ? c.danger : c.warning, shape: BoxShape.circle),
                                  ),
                                ),
                                const SizedBox(width: Space.x3),
                                Expanded(child: Text(issues[i].message, style: t.bodyMedium)),
                                if (issues[i].scriptId != null) Icon(Icons.chevron_right_rounded, size: 20, color: c.textMuted),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

/// 弹出“看代码”。
Future<void> showBlockCode(BuildContext context, BlockHost host) {
  final code = host.codeText;
  final empty = host.scripts.isEmpty;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => CodeSheetBody(title: '积木翻出来的 ${host.codeLanguage}', note: empty ? '还没有积木，所以这里是空的。拼好积木以后，这里就是它们翻出来的代码（只读）。' : '只读。改积木，代码会跟着变。', code: code),
  );
}
