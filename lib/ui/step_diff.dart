// 设计约束（步骤里的改动对比、确认卡里的预览 · 390×844）
// - 步骤那一行：改完的写成“改 lib/a.dart”（新建写“新建”、删掉写“删除”），行尾跟一个“+3 −1”，一行放完。
// - 点开步骤：最上面先放对比（小标题一行“改动对比”，新建的在标题后标“新建”），下面才是结果文字。
//   还没执行 / 没执行成的 edit_file：用参数里的原文和新文画一份“打算这样改”的预览（没有行号，因为不知道在文件哪一行）。
// - 确认卡里的预览：默认只有一行“看看会删掉什么 −12 行”，点了才在卡里展开（限高，自己滚），不把卡片撑得很高。
// - 颜色只有对比里的红绿；标题、说明都是中性灰。
import 'dart:convert';

import 'package:lopicode/agent/edit_file_tool.dart';
import 'package:lopicode/agent/line_diff.dart';
import 'package:lopicode/session/chat_models.dart';
import 'package:lopicode/session/chat_rows.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/diff_view.dart';
import 'package:material_ui/material_ui.dart';

/// 确认卡里展开的预览最高多少。
const double kApprovalPreviewMaxHeight = 160;

/// 步骤那一行的“动作 + 对象”：这一步有改动记录就按改动说（改 / 新建 / 删除 + 路径），否则照原来的。
(String verb, String target) stepLabelOf(ToolItem tool) {
  final change = tool.change;
  if (change == null || !tool.ok || tool.denied) return stepLabel(tool.name, tool.arguments, result: tool.result);
  return (
    switch (change.kind) {
      ChangeKind.created => '新建',
      ChangeKind.modified => '改',
      ChangeKind.deleted => '删除',
    },
    change.path,
  );
}

/// 还没执行 / 没执行成的 edit_file：用参数里的原文和新文算一份预览。算不出来返回 null。
FileChange? editPreviewOf(ToolItem tool) {
  if (tool.name != kEditFileTool || tool.change != null) return null;
  try {
    final args = jsonDecode(tool.arguments);
    if (args is! Map) return null;
    final path = args['path'], oldText = args['old_text'], newText = args['new_text'];
    if (path is! String || oldText is! String || newText is! String || oldText.isEmpty) return null;
    final change = diffFileChange(path, kind: ChangeKind.modified, before: oldText, after: newText).slim;
    return change.hasDiff ? change : null;
  } on FormatException {
    return null; // 参数还没写完整
  }
}

/// 步骤行尾的“+3 −1”。这一步没有改动记录（或者没成功）就不占地方。
class StepStat extends StatelessWidget {
  const StepStat({super.key, required this.tool});
  final ToolItem tool;

  @override
  Widget build(BuildContext context) {
    final change = tool.change;
    if (change == null || !tool.ok || tool.denied || change.added + change.removed == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: Space.x2),
      child: DiffStat(key: ValueKey('step-stat-${tool.callId}'), added: change.added, removed: change.removed),
    );
  }
}

/// 步骤详情最上面的对比：改完的是真实对比，没执行的 edit_file 是预览。都没有就不占地方。
class StepDiffBlock extends StatelessWidget {
  const StepDiffBlock({super.key, required this.tool});
  final ToolItem tool;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final done = tool.change;
    final preview = done == null ? editPreviewOf(tool) : null;
    final change = done ?? preview;
    if (change == null || (!change.hasDiff && change.note == null)) return const SizedBox.shrink();
    final title = done != null ? (done.kind == ChangeKind.created ? '改动对比 · 新建' : (done.kind == ChangeKind.deleted ? '改动对比 · 删除' : '改动对比')) : (tool.running ? '打算这样改（还没执行）' : '打算这样改（没有执行）');
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.x3),
      child: Column(
        key: ValueKey(done != null ? 'step-diff' : 'step-diff-preview'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(title, style: t.bodySmall?.copyWith(color: c.textFaint)),
              ),
              DiffStat(added: change.added, removed: change.removed),
            ],
          ),
          const SizedBox(height: Space.x1),
          FileChangeBody(change: change, numbers: done != null),
        ],
      ),
    );
  }
}

/// 确认卡里的预览：一行入口，点了在卡里展开。
class ApprovalPreview extends StatefulWidget {
  const ApprovalPreview({super.key, required this.change});
  final FileChange change;

  @override
  State<ApprovalPreview> createState() => _ApprovalPreviewState();
}

class _ApprovalPreviewState extends State<ApprovalPreview> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final change = widget.change;
    final what = switch (change.kind) {
      ChangeKind.deleted => '看看会删掉什么',
      ChangeKind.created => '看看会新建什么',
      ChangeKind.modified => '看看会改成什么样',
    };
    return Padding(
      padding: const EdgeInsets.only(top: Space.x2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            key: const ValueKey('approval-preview-toggle'),
            borderRadius: BorderRadius.circular(Radii.sm),
            onTap: () => setState(() => _open = !_open),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 36),
              child: Row(
                children: [
                  Expanded(
                    child: Text(what, style: t.bodySmall?.copyWith(color: c.accent)),
                  ),
                  DiffStat(added: change.added, removed: change.removed),
                  const SizedBox(width: Space.x1),
                  Icon(_open ? Icons.expand_less : Icons.expand_more, size: 18, color: c.textFaint),
                ],
              ),
            ),
          ),
          if (_open)
            Container(
              key: const ValueKey('approval-preview-body'),
              constraints: const BoxConstraints(maxHeight: kApprovalPreviewMaxHeight),
              padding: const EdgeInsets.all(Space.x2),
              decoration: BoxDecoration(color: c.codeBg, borderRadius: BorderRadius.circular(Radii.md)),
              child: SingleChildScrollView(child: FileChangeBody(change: change)),
            ),
        ],
      ),
    );
  }
}
