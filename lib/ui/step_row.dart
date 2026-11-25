// 设计约束（步骤清单里的一步 · 390×844）— 2026-11-25 改成时间线
// - 一行只做一件事：左边一个圆点（状态）＋“动作 + 对象”，行尾依次是 改动行数（+3 −1）、用时、“失败 / 已拒绝”两个字、子代理的“查看”、展开箭头。
//   行尾这几样都很短，而且大多数步骤只有其中一两样；对象放不下用省略号，不换行。
// - 行下面是结果摘要（见 step_timeline.dart）；点这一行换成详情（见 step_detail.dart），摘要让位，不重复。
// - 原来每行开头的工具小图标拿掉了：动作已经写在字里（读取 / 执行 / 修改…），那个位置现在给状态圆点。
// - 颜色只出现在状态上。没有主操作。
import 'package:lopicode/session/chat_models.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/step_detail.dart';
import 'package:lopicode/ui/step_diff.dart';
import 'package:lopicode/ui/step_timeline.dart';
import 'package:material_ui/material_ui.dart';

/// 一步：一行“动作 + 对象”，行尾是状态；下面是结果摘要；点开看参数和结果。
/// [rail]：这一步在时间线里的位置（画竖线用）；单独一步、折叠时露在外面的失败步骤不给，就只有圆点没有线。
class StepRow extends StatefulWidget {
  const StepRow({super.key, required this.tool, this.onOpenChild, this.rail});
  final ToolItem tool;
  final void Function(String conversationId)? onOpenChild;
  final RailSpot? rail;

  @override
  State<StepRow> createState() => _StepRowState();
}

class _StepRowState extends State<StepRow> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final tool = widget.tool;
    final (verb, target) = stepLabelOf(tool);
    final state = stepStateOf(tool);
    final child = tool.childConversationId;
    return TimelineRail(
      spot: widget.rail,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            key: ValueKey('step-${tool.callId}'),
            borderRadius: BorderRadius.circular(Radii.sm),
            onTap: () => setState(() => _open = !_open),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: kStepRowHeight),
              child: Row(
                children: [
                  StepMarker(state: state),
                  const SizedBox(width: Space.x2),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        text: verb,
                        children: [
                          if (target.isNotEmpty)
                            TextSpan(
                              text: ' ${target.replaceAll('\n', ' ')}',
                              style: TextStyle(fontFamily: kMonoFont, fontFamilyFallback: kMonoFallback, fontSize: FontSize.xs, color: c.textFaint),
                            ),
                        ],
                      ),
                      style: t.bodyMedium?.copyWith(color: c.textMuted),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  StepStat(tool: tool),
                  StepElapsed(tool: tool),
                  if (state == StepPhase.failed) ...[const SizedBox(width: Space.x2), Text('失败', style: t.bodySmall?.copyWith(color: c.danger))],
                  if (state == StepPhase.denied) ...[const SizedBox(width: Space.x2), Text('已拒绝', style: t.bodySmall?.copyWith(color: c.warning))],
                  if (child != null && widget.onOpenChild != null)
                    InkWell(
                      borderRadius: BorderRadius.circular(Radii.sm),
                      onTap: () => widget.onOpenChild!(child),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: Space.x2, vertical: Space.x2),
                        child: Text('查看', style: t.bodySmall?.copyWith(color: c.accent)),
                      ),
                    ),
                  const SizedBox(width: Space.x1),
                  Icon(_open ? Icons.expand_less : Icons.expand_more, size: 16, color: c.textFaint),
                ],
              ),
            ),
          ),
          if (_open) StepDetail(tool: tool) else StepDigestView(tool: tool),
        ],
      ),
    );
  }
}
