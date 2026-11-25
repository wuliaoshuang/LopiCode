// 设计约束（聊天里的“步骤组” · 390×844）— 2026-11-24 霜霜：多轮工具调用不许再一条条大卡片刷屏
// - 内容分三级：正式回复（气泡，最重）＞ 步骤组那一行摘要（次要文字色，无底无框）＞ 展开后的每一步（更淡，等宽的对象）。
//   步骤组不用卡片、不用色块：它是“过程”，不该和回复抢眼。
// - 一行只做一件事：
//   · 进行中：转圈 + 现在在做什么 + “第 N 步”，就一行；
//   · 做完：一行摘要“执行了 5 步 · 读 3 个文件 · 改 1 个文件 · 1 条命令”，有失败时行尾一个红色小标记；
//   · 折叠时失败 / 被拒绝的那几步单独露在摘要下面（看得见停在哪），其余收起；
//   · 点摘要展开清单（左边一条细线串起来），再点某一步看参数和结果；长结果先截一段，点“显示全部”；
//     命令输出太长被转存成文件的，结果下面多一个“查看完整输出”（另开一页）。
//   · 某一步之前模型的思考也是清单里的一行（“思考了 N 秒”，见 chat_extras.dart），折叠时不露出来。
// - 只有一步、中间也没说话的，不套组，直接是一行。
// - 颜色只出现在状态上：失败红、被拒绝橙、子代理的“查看”用强调色；其余全是中性灰。
// - 主操作没有：这里全是“想看再点”的次要内容。
import 'dart:convert';

import 'package:lopicode/agent/command_output_store.dart';
import 'package:lopicode/session/chat_models.dart';
import 'package:lopicode/session/chat_rows.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/chat_extras.dart';
import 'package:material_ui/material_ui.dart';

/// 结果先显示这么多字，多的点“显示全部”。
const int kStepResultPreview = 1200;

/// “显示全部”也最多这么多字（再长在手机上也没法看）。
const int kStepResultMax = 20000;

/// 折叠时最多单独露出几条失败 / 被拒绝的步骤。
const int kExposedFailures = 2;

IconData _iconOf(StepKind kind) => switch (kind) {
  StepKind.read => Icons.description_outlined,
  StepKind.look => Icons.folder_open_outlined,
  StepKind.edit => Icons.edit_outlined,
  StepKind.delete => Icons.delete_outline,
  StepKind.command => Icons.terminal,
  StepKind.search => Icons.travel_explore,
  StepKind.agent => Icons.account_tree_outlined,
  StepKind.ask => Icons.help_outline,
  StepKind.plan => Icons.checklist,
  StepKind.other => Icons.build_outlined,
};

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
                ? _Thread(
                    children: [
                      for (final step in row.steps)
                        if (step is ToolItem)
                          StepRow(tool: step, onOpenChild: widget.onOpenChild)
                        else if (step is AssistantItem)
                          _Note(step.text)
                        else if (step is ThinkingItem)
                          ThinkingRow(item: step),
                    ],
                  )
                : shown.isEmpty
                ? const SizedBox(width: double.infinity)
                : _Thread(
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

/// 展开后的清单：左边一条细线把这一组串起来。
class _Thread extends StatelessWidget {
  const _Thread({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(left: 11),
    padding: const EdgeInsets.only(left: Space.x3),
    decoration: BoxDecoration(
      border: Border(left: BorderSide(color: context.colors.border)),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
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

/// 一步：一行“动作 + 对象”，行尾是状态；点开看参数和结果。
class StepRow extends StatefulWidget {
  const StepRow({super.key, required this.tool, this.onOpenChild});
  final ToolItem tool;
  final void Function(String conversationId)? onOpenChild;

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
    final (verb, target) = stepLabel(tool.name, tool.arguments);
    final failed = !tool.running && !tool.ok && !tool.denied;
    final child = tool.childConversationId;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          key: ValueKey('step-${tool.callId}'),
          borderRadius: BorderRadius.circular(Radii.sm),
          onTap: () => setState(() => _open = !_open),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 36),
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  child: Center(child: Icon(_iconOf(stepKindOf(tool.name)), size: 16, color: failed ? c.danger : c.textFaint)),
                ),
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
                if (tool.running) ...[const SizedBox(width: Space.x2), SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5, color: c.textFaint))],
                if (failed) ...[const SizedBox(width: Space.x2), Text('失败', style: t.bodySmall?.copyWith(color: c.danger))],
                if (tool.denied) ...[const SizedBox(width: Space.x2), Text('已拒绝', style: t.bodySmall?.copyWith(color: c.warning))],
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
        if (_open) _StepDetail(tool: tool),
      ],
    );
  }
}

/// 一步的参数和结果要显示的几段：（小标题，内容）。
List<(String, String)> stepDetailSections(ToolItem tool) {
  Map<String, dynamic> args = const {};
  try {
    final decoded = jsonDecode(tool.arguments);
    if (decoded is Map<String, dynamic>) args = decoded;
  } on FormatException {
    // 不是合法 JSON：下面按原文显示
  }
  String a(String key) => '${args[key] ?? ''}';
  final out = <(String, String)>[];
  switch (tool.name) {
    case 'run_command':
      out.add(('命令', '\$ ${a('command')}'));
    case 'write_file':
      out
        ..add(('文件', a('path')))
        ..add(('写入的内容', a('content')));
    case 'read_file' || 'delete_file' || 'view_image':
      out.add(('文件', a('path')));
    default:
      final raw = tool.arguments.trim();
      if (args.isNotEmpty) {
        out.add(('参数', const JsonEncoder.withIndent('  ').convert(args)));
      } else if (raw.isNotEmpty && raw != '{}') {
        out.add(('参数', raw));
      }
  }
  final result = tool.result;
  out.add((
    result == null
        ? '结果'
        : tool.denied
        ? '没有执行'
        : tool.ok
        ? '结果'
        : '报错',
    result ?? '执行中…',
  ));
  return out;
}

class _StepDetail extends StatefulWidget {
  const _StepDetail({required this.tool});
  final ToolItem tool;

  @override
  State<_StepDetail> createState() => _StepDetailState();
}

class _StepDetailState extends State<_StepDetail> {
  bool _full = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final mono = TextStyle(fontFamily: kMonoFont, fontFamilyFallback: kMonoFallback, fontSize: FontSize.xs, height: 1.5, color: c.textMuted);
    final sections = stepDetailSections(widget.tool);
    final limit = _full ? kStepResultMax : kStepResultPreview;
    final clipped = sections.any((s) => s.$2.length > kStepResultPreview);
    // 命令输出太长、完整的转存成了文件：给一个整页查看的入口。
    final spilled = spilledOutputPathOf(widget.tool.result);
    final readOutput = ChatRowActions.maybeOf(context)?.readOutput;
    return Container(
      margin: const EdgeInsets.only(left: Space.x8, bottom: Space.x2),
      constraints: BoxConstraints(maxHeight: _full ? 420 : 240),
      decoration: BoxDecoration(color: c.codeBg, borderRadius: BorderRadius.circular(Radii.md)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(Space.x3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final (i, (title, body)) in sections.indexed) ...[
                    if (i > 0) const SizedBox(height: Space.x3),
                    Text(title, style: t.bodySmall?.copyWith(color: c.textFaint)),
                    const SizedBox(height: Space.x1),
                    SelectableText(body.length > limit ? '${body.substring(0, limit)}\n…（共 ${body.length} 字，${_full ? '太长，只显示前 $limit 字' : '还有 ${body.length - limit} 字没显示'}）' : body, style: mono),
                  ],
                  if (clipped && !_full)
                    Padding(
                      padding: const EdgeInsets.only(top: Space.x2),
                      child: InkWell(
                        onTap: () => setState(() => _full = true),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: Space.x1),
                          child: Text('显示全部', style: t.bodySmall?.copyWith(color: c.accent)),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          // 完整输出的入口钉在框底，不跟着内容滚走：输出很长时不用先滑到底才看得见。
          if (spilled != null && readOutput != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.x3, 0, Space.x3, Space.x2),
              child: InkWell(
                key: const ValueKey('open-full-output'),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => CommandOutputPage(path: spilled, load: readOutput),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: Space.x1),
                  child: Text('查看完整输出', style: t.bodySmall?.copyWith(color: c.accent)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
