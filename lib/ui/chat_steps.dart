// 设计约束（聊天里的“步骤组” · 390×844）— 2026-11-24 霜霜：多轮工具调用不许再一条条大卡片刷屏
// - 内容分三级：正式回复（气泡，最重）＞ 步骤组那一行摘要（次要文字色，无底无框）＞ 展开后的每一步（更淡，等宽的对象）。
//   步骤组不用卡片、不用色块：它是“过程”，不该和回复抢眼。
// - 一行只做一件事：
//   · 进行中：转圈 + 现在在做什么 + “第 N 步”，就一行；
//   · 做完：一行摘要“执行了 5 步 · 读 3 个文件 · 改 1 个文件 · 1 条命令”，有失败时行尾一个红色小标记；
//   · 折叠时失败 / 被拒绝的那几步单独露在摘要下面（看得见停在哪），其余收起；
//   · 点摘要展开清单：一条时间线（左边细竖线 + 每步一个状态圆点，见 step_timeline.dart），每步下面带一小段结果摘要；
//     再点某一步看详情（按工具分别排，见 step_detail.dart）。一步那一行在 step_row.dart。
//   · 某一步之前模型的思考也是清单里的一行（“思考了 N 秒”，见 chat_extras.dart），折叠时不露出来。
// - 只有一步、中间也没说话的，不套组，直接是一行。
// - 颜色只出现在状态上：失败红、被拒绝橙、子代理的“查看”用强调色；其余全是中性灰。
// - 主操作没有：这里全是“想看再点”的次要内容。
import 'package:lopicode/session/chat_models.dart';
import 'package:lopicode/session/chat_rows.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/chat_extras.dart';
import 'package:lopicode/ui/step_row.dart';
import 'package:lopicode/ui/step_timeline.dart';
import 'package:material_ui/material_ui.dart';

export 'package:lopicode/ui/step_detail.dart' show StepDetail, kStepResultMax, kStepResultPreview, stepDetailSections;
export 'package:lopicode/ui/step_row.dart' show StepRow;

/// 折叠时最多单独露出几条失败 / 被拒绝的步骤。
const int kExposedFailures = 2;

class StepGroupView extends StatefulWidget {
  const StepGroupView({super.key, required this.row, this.onOpenChild});
  final StepGroupRow row;

  /// 点子代理那一步的“查看”时进子对话。
  final void Function(String conversationId)? onOpenChild;

  @override
  State<StepGroupView> createState() => _StepGroupViewState();
}

class _StepGroupViewState extends State<StepGroupView> with AutomaticKeepAliveClientMixin {
  bool _expanded = false;

  // 展开着的组滚出屏幕也留着，不然滚回来又折上了。
  @override
  bool get wantKeepAlive => _expanded;

  void _toggle() {
    setState(() => _expanded = !_expanded);
    updateKeepAlive();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final row = widget.row;
    final tools = row.tools;
    // 只有一步、中间也没说话（也没有要显示的思考）：不套组。
    if (row.steps.length == 1) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.x1),
        child: StepRow(tool: tools.single, onOpenChild: widget.onOpenChild),
      );
    }
    final exposed = _expanded ? const <ToolItem>[] : [...tools.where((t) => !t.running && (!t.ok || t.denied))];
    final shown = exposed.length > kExposedFailures ? exposed.sublist(exposed.length - kExposedFailures) : exposed;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.x1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _GroupHeader(row: row, expanded: _expanded, onTap: _toggle),
          AnimatedSize(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: _expanded
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final (i, step) in row.steps.indexed)
                        if (step is ToolItem)
                          StepRow(
                            tool: step,
                            onOpenChild: widget.onOpenChild,
                            rail: RailSpot(first: i == 0, last: i == row.steps.length - 1),
                          )
                        else if (step is AssistantItem)
                          _Between(child: _Note(step.text))
                        else if (step is ThinkingItem)
                          _Between(child: ThinkingRow(item: step)),
                    ],
                  )
                : shown.isEmpty
                ? const SizedBox(width: double.infinity)
                // 折叠时露在外面的失败步骤：不是连着的一段，只有圆点、不画线。
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [for (final t in shown) StepRow(tool: t, onOpenChild: widget.onOpenChild)],
                  ),
          ),
        ],
      ),
    );
  }
}

/// 步骤组那一行：进行中说现在在做什么，做完说一共做了什么。
class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.row, required this.expanded, required this.onTap});
  final StepGroupRow row;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final tools = row.tools;
    final sum = summarizeSteps(tools);
    final running = tools.where((x) => x.running).toList();
    final String label;
    if (!row.live) {
      label = sum.line;
    } else if (running.isEmpty) {
      label = '正在想下一步…';
    } else if (running.length == 1) {
      label = describeTool(running.single.name, running.single.arguments);
    } else {
      label = '同时进行 ${running.length} 步：${describeTool(running.first.name, running.first.arguments)}';
    }
    return Semantics(
      button: true,
      label: expanded ? '收起步骤' : '展开步骤',
      child: InkWell(
        key: ValueKey('step-group-${row.id}'),
        borderRadius: BorderRadius.circular(Radii.md),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 40),
          child: Row(
            children: [
              SizedBox(
                width: 24,
                child: Center(
                  child: row.live ? SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: c.accent)) : Icon(Icons.done_all, size: 16, color: c.textFaint),
                ),
              ),
              const SizedBox(width: Space.x2),
              Expanded(
                child: Text.rich(
                  // 做完的摘要：“执行了 N 步”是主体，后面的分项小一号、淡一点。
                  row.live || sum.parts.isEmpty
                      ? TextSpan(text: label)
                      : TextSpan(
                          text: '执行了 ${sum.total} 步',
                          children: [
                            TextSpan(
                              text: ' · ${sum.parts.join(' · ')}',
                              style: TextStyle(fontSize: FontSize.xs, color: c.textFaint),
                            ),
                          ],
                        ),
                  style: t.bodyMedium?.copyWith(color: c.textMuted),
                  // 进行中只占一行；做完的摘要放不下时折到第二行，不用省略号吃掉数字。
                  maxLines: row.live ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (row.live) ...[const SizedBox(width: Space.x2), Text('第 ${tools.length} 步', style: t.bodySmall?.copyWith(color: c.textFaint))],
              if (sum.failed > 0) ...[const SizedBox(width: Space.x2), _Flag(Icons.close, sum.failed, '步失败', c.danger)],
              if (sum.denied > 0) ...[const SizedBox(width: Space.x2), _Flag(Icons.block, sum.denied, '步被拒绝', c.warning)],
              const SizedBox(width: Space.x1),
              Icon(expanded ? Icons.expand_less : Icons.expand_more, size: 18, color: c.textFaint),
            ],
          ),
        ),
      ),
    );
  }
}

/// 行尾的小标记：一个小图标 + 个数，只有它带颜色（“几步失败”念给读屏听，不占地方）。
class _Flag extends StatelessWidget {
  const _Flag(this.icon, this.count, this.what, this.color);
  final IconData icon;
  final int count;
  final String what;
  final Color color;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '$count $what',
    child: Row(
      key: ValueKey('flag-$what'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 2),
        ExcludeSemantics(
          child: Text(
            '$count',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}

/// 时间线上两步之间的东西（模型说的话、思考）：竖线从它左边穿过去不断开，内容缩进到和步骤的文字对齐。
class _Between extends StatelessWidget {
  const _Between({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => TimelineRail(
    spot: const RailSpot(first: false, last: false),
    marker: false,
    child: Padding(
      padding: const EdgeInsets.only(left: kRailWidth + Space.x2),
      child: child,
    ),
  );
}

/// 模型在两步之间说的话：不套气泡，淡一点，放在它发生的位置。
class _Note extends StatelessWidget {
  const _Note(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: Space.x2),
    child: Text(text.trim(), style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: context.colors.textMuted)),
  );
}
