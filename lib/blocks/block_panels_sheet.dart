// 设计约束（问题列表 / 有错误先别继续 / 看代码 三张底部面板，390 宽，浅色 + 深色）— 2026-11-24
// - 问题列表：标题一行（“N 个问题”），副标题一行（几个错误、几个警告，有错误时说明“代码没有更新”）。
//   （“提醒”和警告放在同一段里，图标不一样；有一键修的那条，建议下面一行是修法按钮，点了就改并关掉列表。）
//   下面先“错误”再“警告”两段；每段里按事件 / 接口分组，组名一行小字；每条：图标（错误圆、警告三角）+ 原因 + “建议：…” + 规则编号。
//   能定位到积木的那几条右边带一个小箭头，点了就关掉面板、画布跳到那块积木并闪一下。没有问题时只有一句“没有发现问题”。主操作＝点一条去修。
// - 有错误先别继续（启动 / 导出被拦时）：一句标题“有 N 个错误，代码没有更新”，一句说明，主按钮“查看问题”，次按钮“知道了”。
// - 看代码：整张面板就是只读的代码（等宽字），标题写是什么语言；一块积木都没有时给一句说明而不是空白。
import 'package:lopicode/blocks/block_host.dart';
import 'package:lopicode/blocks/block_issue_view.dart';
import 'package:lopicode/lowcode/code_sheet.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/code_highlight.dart';
import 'package:material_ui/material_ui.dart';

/// “有 N 个错误，代码没有更新”——界面上凡是说这件事的地方都用这一句。
String blockErrorsHeadline(int errors) => '有 $errors 个错误，代码没有更新';

/// 同一件事的短说法：顶栏副标题用（那里只放得下八九个字，长了会被截掉）。
String blockErrorsBrief(int errors) => '$errors 个错误，没更新';

/// 弹出问题列表；点了能定位的一条就返回它。条目的 key 是 `bk-issue-<它在 issues 里的下标>`。
Future<BlockIssue?> showBlockIssues(BuildContext context, List<BlockIssue> issues) {
  return showModalBottomSheet<BlockIssue>(
    context: context,
    isScrollControlled: true,
    builder: (sheet) {
      final c = sheet.colors;
      final t = Theme.of(sheet).textTheme;
      final errors = issues.where((i) => i.isError).length;
      final warnings = issues.length - errors;

      /// 一段（错误 / 警告）：按组排开，组的顺序＝第一次出现的顺序。
      List<Widget> section(bool error) {
        final groups = <String, List<int>>{};
        for (var i = 0; i < issues.length; i++) {
          if (issues[i].isError == error) (groups[issues[i].group] ??= []).add(i);
        }
        if (groups.isEmpty) return const [];
        return [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.x4, Space.x3, Space.x4, Space.x1),
            child: Text(
              error ? '错误 · $errors' : '警告 · $warnings',
              key: ValueKey(error ? 'bk-issues-errors' : 'bk-issues-warnings'),
              style: t.labelLarge?.copyWith(color: error ? c.danger : c.textMuted),
            ),
          ),
          for (final g in groups.entries) ...[
            if (g.key.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.x4, Space.x2, Space.x4, 0),
                child: Text(
                  g.key,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.labelMedium?.copyWith(color: c.textMuted),
                ),
              ),
            for (final i in g.value)
              InkWell(
                key: ValueKey('bk-issue-$i'),
                onTap: issues[i].scriptId == null ? null : () => Navigator.pop(sheet, issues[i]),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.x4, vertical: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: BkIssueLines(issue: issues[i], head: issues[i].spot, onFixed: () => Navigator.pop(sheet)),
                      ),
                      if (issues[i].scriptId != null) Icon(Icons.chevron_right_rounded, size: 20, color: c.textMuted),
                    ],
                  ),
                ),
              ),
          ],
        ];
      }

      return SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheet).height * 0.7),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x1),
                child: Text(issues.isEmpty ? '没有发现问题' : '${issues.length} 个问题', style: t.titleMedium),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, issues.isEmpty ? Space.x6 : Space.x1),
                child: Text(
                  issues.isEmpty ? '积木都拼好了，可以放心用。' : (errors > 0 ? '${blockErrorsHeadline(errors)}；修好错误以后会自动更新。' : '只有警告：代码照常更新，建议看一眼。'),
                  key: ValueKey(issues.isEmpty ? 'bk-issues-none' : 'bk-issues-summary'),
                  style: t.bodySmall?.copyWith(color: c.textMuted),
                ),
              ),
              if (issues.isNotEmpty)
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.only(bottom: Space.x4),
                    children: [...section(true), ...section(false)],
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

/// 有错误时拦下“启动 / 导出”：说清楚为什么、给“查看问题”。返回 true＝要去看问题。
/// `action`＝被拦下的是什么（“启动”“导出”），`kept`＝现在留着的是什么（“上一次生成的代码”）。
Future<bool> showBlockErrorsGate(BuildContext context, {required int errors, required String action, String kept = '上一次生成的代码'}) async {
  final go = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (sheet) {
      final c = sheet.colors;
      final t = Theme.of(sheet).textTheme;
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x4),
          child: Column(
            key: const ValueKey('bk-errors-gate'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const BkIssueIcon(error: true, size: 22),
                  const SizedBox(width: Space.x2),
                  Expanded(child: Text(blockErrorsHeadline(errors), style: t.titleMedium)),
                ],
              ),
              const SizedBox(height: Space.x2),
              Text('积木里有错误的时候不会生成新代码，$kept原样留着，所以现在不能$action。把标红的积木修好，代码会自动更新。', style: t.bodyMedium?.copyWith(color: c.textMuted)),
              const SizedBox(height: Space.x4),
              FilledButton(key: const ValueKey('bk-errors-gate-open'), onPressed: () => Navigator.pop(sheet, true), child: const Text('查看问题')),
              const SizedBox(height: Space.x1),
              TextButton(key: const ValueKey('bk-errors-gate-close'), onPressed: () => Navigator.pop(sheet, false), child: const Text('知道了')),
            ],
          ),
        ),
      );
    },
  );
  return go ?? false;
}

/// 弹出“看代码”。
Future<void> showBlockCode(BuildContext context, BlockHost host) {
  final code = host.codeText;
  final empty = host.scripts.isEmpty;
  final errors = host.issues.where((i) => i.isError).length;
  final note = empty ? '还没有积木，所以这里是空的。拼好积木以后，这里就是它们翻出来的代码（只读）。' : (errors > 0 ? '${blockErrorsHeadline(errors)}。下面只是照现在的积木翻出来的预览，项目里的文件还是上一次的。' : '只读。改积木，代码会跟着变。');
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => CodeSheetBody(title: '积木翻出来的 ${host.codeLanguage}', note: note, code: code, language: CodeHighlighter.languageFor(host.codeFileName)),
  );
}
