// 设计约束（“这次改过的文件” · 390×844）
// - 聊天里只占一行，放在这一轮回复下面、用量脚注上面：“改了 3 个文件 +12 −4 ›”。和用量脚注一个级别（小号灰字），
//   只有 +/− 的数字带红绿。整行可点。
// - 点开是底部面板：标题一行、一句说明一行，下面一个文件一行——
//   左边“新建 / 修改 / 删除”小字标记，中间路径（等宽，太长省略中间看得见文件名），右边 +/−，最右一个箭头。
// - 点某个文件进一页：顶栏是文件名，正文是它这一轮合起来的对比（见 diff_view.dart）。
// - 没有主操作：全是“想看再点”。
import 'package:lopicode/agent/line_diff.dart';
import 'package:lopicode/session/turn_changes.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/code_view.dart';
import 'package:lopicode/ui/diff_view.dart';
import 'package:lopicode/ui/top_bar.dart';
import 'package:material_ui/material_ui.dart';

/// 路径太长时从前面省略，保住文件名：“…/widgets/very_long_name.dart”。
String shortPath(String path, {int max = 34}) => path.length <= max ? path : '…${path.substring(path.length - max + 1)}';

/// 聊天里那一行。
class ChangedFilesRow extends StatelessWidget {
  const ChangedFilesRow({super.key, required this.files});
  final List<FileChange> files;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final total = totalsOfChanges(files);
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(color: c.textFaint, height: 1.3);
    return Align(
      alignment: Alignment.centerLeft,
      child: Semantics(
        button: true,
        label: '这一轮改了 ${total.files} 个文件，增 ${total.added} 行，删 ${total.removed} 行。点开看清单',
        excludeSemantics: true,
        child: InkWell(
          key: const Key('changed-files'),
          borderRadius: BorderRadius.circular(Radii.sm),
          onTap: () => showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            builder: (_) => ChangedFilesSheet(files: files),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 36),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.x1, vertical: Space.x1),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.edit_outlined, size: 14, color: c.textFaint),
                  const SizedBox(width: Space.x1),
                  Text('改了 ${total.files} 个文件', key: const Key('changed-files-text'), style: style),
                  if (total.added + total.removed > 0) ...[const SizedBox(width: Space.x2), DiffStat(added: total.added, removed: total.removed)],
                  Icon(Icons.chevron_right, size: 18, color: c.textFaint),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 文件清单（底部面板）。
class ChangedFilesSheet extends StatelessWidget {
  const ChangedFilesSheet({super.key, required this.files});
  final List<FileChange> files;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final total = totalsOfChanges(files);
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text('这一轮改过的文件', style: t.titleLarge)),
                      DiffStat(added: total.added, removed: total.removed),
                    ],
                  ),
                  const SizedBox(height: Space.x1),
                  Text('共 ${total.files} 个。只算 Agent 用“写入 / 局部修改 / 删除”改的，命令里改的不在这里。', style: t.bodySmall?.copyWith(color: c.textFaint, height: 1.5)),
                ],
              ),
            ),
            Flexible(
              child: ListView.builder(
                key: const Key('changed-files-list'),
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: Space.x4),
                itemCount: files.length,
                itemBuilder: (context, i) => _FileLine(change: files[i]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FileLine extends StatelessWidget {
  const _FileLine({required this.change});
  final FileChange change;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final d = DiffColors.of(context);
    final t = Theme.of(context).textTheme;
    final tone = switch (change.kind) {
      ChangeKind.created => d.addFg,
      ChangeKind.modified => c.textMuted,
      ChangeKind.deleted => d.delFg,
    };
    return InkWell(
      key: ValueKey('changed-file-${change.path}'),
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => FileDiffPage(change: change))),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.x4, Space.x2, Space.x3, Space.x2),
          child: Row(
            children: [
              SizedBox(
                width: 36,
                child: Text(
                  change.kind.label,
                  style: t.bodySmall?.copyWith(color: tone, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: Space.x2),
              Expanded(
                child: Text(
                  shortPath(change.path),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontFamily: kMonoFont, fontFamilyFallback: kMonoFallback, fontSize: FontSize.sm, color: c.text),
                ),
              ),
              const SizedBox(width: Space.x2),
              DiffStat(added: change.added, removed: change.removed),
              Icon(Icons.chevron_right, size: 18, color: c.textFaint),
            ],
          ),
        ),
      ),
    );
  }
}

/// 一个文件这一轮合起来的对比（整页）。
class FileDiffPage extends StatelessWidget {
  const FileDiffPage({super.key, required this.change});
  final FileChange change;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: c.canvas,
      extendBodyBehindAppBar: true,
      appBar: PageBar(background: c.canvas, title: Text(change.path.split('/').where((s) => s.isNotEmpty).lastOrNull ?? change.path)),
      body: Scrollbar(
        child: SingleChildScrollView(
          key: const Key('file-diff-scroll'),
          padding: EdgeInsets.fromLTRB(Space.x4, PageBar.insetOf(context) + Space.x2, Space.x4, Space.x6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                change.path,
                style: TextStyle(fontFamily: kMonoFont, fontFamilyFallback: kMonoFallback, fontSize: FontSize.xs, color: c.textMuted),
              ),
              const SizedBox(height: Space.x1),
              Row(
                children: [
                  Text('这一轮：${change.kind.label}', style: t.bodySmall?.copyWith(color: c.textFaint)),
                  const SizedBox(width: Space.x2),
                  DiffStat(added: change.added, removed: change.removed),
                ],
              ),
              const SizedBox(height: Space.x3),
              Container(
                padding: const EdgeInsets.all(Space.x2),
                decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(Radii.md)),
                child: change.hasDiff || change.note != null ? CodeZoom(child: FileChangeBody(change: change)) : Text('这个文件没有保存对比。', style: t.bodySmall?.copyWith(color: c.textMuted)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
