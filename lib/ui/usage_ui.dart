// 设计约束（用量相关的界面 · 390×844）
// 行为参照 dsh-Go 的做法（回合脚注 → 本轮轨迹 → 步骤详情；输入框旁的上下文小环 → 用量弹层；DeepSeek 余额卡和低余额提示），
// 代码、文案、布局都是自己写的。
// - 回合脚注：回复下方一行小字，“47 秒 · 12 步 · 约 ¥0.03 · 36K tokens ›”。放不下时依次省掉 tokens、步数、花费，用时永远保留。可点区域高 36。
// - 本轮轨迹（底部弹层）：顶部本轮合计；下面按时间一行一段（模型请求 / 工具调用，右侧是用时）；
//   同一步里连续 3 次以上已结束的工具调用折成一组，点开展开。点某一行进步骤详情。
// - 步骤详情（整页）：计时、用量分项、参数、结果，各一张卡片。
// - 上下文小环：直径 18 的环 + 百分比；<60% 主色、60–85% 警示色、>85% 危险色；不到 1% 写“<1%”。
// - 用量弹层：上下文 / 本对话 / DeepSeek 余额 三块。数字用 K、M。
// - 接口没给的数显示“—”或如实说明，不估不编；估算的地方（上下文分项、费用）都写明“估算”。
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:lopicode/agent/model_config.dart';
import 'package:lopicode/agent/presets.dart';
import 'package:lopicode/agent/quota.dart';
import 'package:lopicode/agent/usage.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/state/quota_state.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/app_ref.dart';
import 'package:lopicode/ui/chrome.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';

/// 上下文占用对应的颜色：<60% 主色、60–85% 警示色、>85% 危险色。
Color contextTone(AppColors c, double fraction) => fraction > 0.85 ? c.danger : (fraction >= 0.6 ? c.warning : c.accent);

String _two(int v) => v.toString().padLeft(2, '0');
String _clock(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}';

// ═══════════════════════════ 回合脚注 ═══════════════════════════

class TurnFootnote extends StatelessWidget {
  const TurnFootnote({super.key, required this.turn, this.onTap});
  final TurnUsage turn;
  final VoidCallback? onTap;

  static double _width(BuildContext context, String text, TextStyle? style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final w = painter.width;
    painter.dispose();
    return w;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(color: c.textFaint, height: 1.3, fontFeatures: const [FontFeature.tabularFigures()]);
    final options = footnoteVariants(turn);
    return Align(
      alignment: Alignment.centerLeft,
      child: Semantics(
        button: onTap != null,
        label: '本轮用量：${options.first}。点开看本轮轨迹',
        excludeSemantics: true,
        child: InkWell(
          key: const Key('turn-footnote'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(Radii.sm),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 36),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.x1, vertical: Space.x1),
              child: LayoutBuilder(
                builder: (context, box) {
                  final room = box.maxWidth - 18;
                  final text = options.firstWhere((o) => _width(context, o, style) <= room, orElse: () => options.last);
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(text, key: const Key('turn-footnote-text'), maxLines: 1, softWrap: false, overflow: TextOverflow.fade, style: style),
                      ),
                      Icon(Icons.chevron_right, size: 18, color: c.textFaint),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════ 本轮轨迹 ═══════════════════════════

/// 轨迹里的一行。
sealed class _Row {}

class _RequestRow extends _Row {
  _RequestRow(this.index, this.request, this.owner);
  final int index;
  final RequestUsage request;
  final String? owner;
}

class _ToolRow extends _Row {
  _ToolRow(this.step);
  final ToolStep step;
}

class _GroupRow extends _Row {
  _GroupRow(this.tools);
  final List<ToolStep> tools;
}

class _HeaderRow extends _Row {
  _HeaderRow(this.text);
  final String text;
}

/// 把一轮的步骤排成行：同一步（两次模型请求之间）里连续 3 次以上已结束的工具调用折成一组。
List<_Row> _rowsOf(TurnUsage turn, {String? owner}) {
  final rows = <_Row>[];
  var n = 0;
  var run = <ToolStep>[];
  void flush() {
    if (run.length >= 3) {
      rows.add(_GroupRow(run));
    } else {
      rows.addAll(run.map(_ToolRow.new));
    }
    run = <ToolStep>[];
  }

  for (final s in turn.steps) {
    switch (s) {
      case RequestStep(:final request):
        flush();
        rows.add(_RequestRow(++n, request, owner));
      case final ToolStep tool:
        if (tool.ms == null) {
          flush();
          rows.add(_ToolRow(tool)); // 没结束的不折
        } else {
          run.add(tool);
        }
    }
  }
  flush();
  return rows;
}

/// 一组工具调用的摘要：“5 次工具调用：读取文件 3 · 写入文件 2”。
String toolGroupSummary(List<ToolStep> tools) {
  final counts = <String, int>{};
  for (final t in tools) {
    counts[toolLabel(t.name)] = (counts[toolLabel(t.name)] ?? 0) + 1;
  }
  return '${tools.length} 次工具调用：${[for (final e in counts.entries) '${e.key} ${e.value}'].join(' · ')}';
}

/// 工具调用针对的东西（文件路径或命令），从参数里取；取不到是 null。
String? toolTarget(String? arguments) {
  if (arguments == null || arguments.isEmpty) return null;
  try {
    final j = jsonDecode(arguments);
    if (j is! Map) return null;
    for (final k in const ['path', 'command', 'query', 'name']) {
      final v = j[k];
      if (v is String && v.trim().isNotEmpty) return v.trim().split('\n').first;
    }
  } on FormatException {
    return null;
  }
  return null;
}

extension on String {
  String? get nullIfEmpty => isEmpty ? null : this;
}

/// 工具名 → 简短的人话（不带参数）。和设置页、对话页用同一张表（lib/agent/presets.dart 的 kToolLabels），新工具只在那里加一次。
String toolLabel(String name) => kToolLabels[name] ?? name;

class TrajectorySheet extends StatefulWidget {
  const TrajectorySheet({super.key, required this.turn, required this.findTool});
  final TurnUsage turn;

  /// 按调用 id 找聊天记录里的那次工具调用（参数和结果）；找不到返回 null。
  final ToolItem? Function(String callId) findTool;

  @override
  State<TrajectorySheet> createState() => _TrajectorySheetState();
}

class _TrajectorySheetState extends State<TrajectorySheet> {
  final Set<_GroupRow> _open = {};
  late final List<_Row> _rows = [
    ..._rowsOf(widget.turn),
    for (final kid in widget.turn.children) ...[_HeaderRow('子代理“${kid.name}”：${totalsLine(kid.turn.totals)}'), ..._rowsOf(kid.turn, owner: kid.name)],
  ];

  void _openStep(Widget page) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final turn = widget.turn;
    final totals = turn.totals;
    final faint = t.bodySmall?.copyWith(color: c.textFaint);

    Widget line({Key? key, required IconData icon, required String title, String? sub, required String trailing, Color? tone, VoidCallback? onTap, double indent = 0}) => InkWell(
      key: key,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: EdgeInsets.fromLTRB(Space.x4 + indent, Space.x2, Space.x3, Space.x2),
          child: Row(
            children: [
              Icon(icon, size: 20, color: tone ?? c.textMuted),
              const SizedBox(width: Space.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: t.bodyMedium?.copyWith(color: tone ?? c.text),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (sub != null) Text(sub, style: faint, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              const SizedBox(width: Space.x2),
              Text(trailing, style: faint?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
              if (onTap != null) Icon(Icons.chevron_right, size: 18, color: c.textFaint),
            ],
          ),
        ),
      ),
    );

    Widget toolLine(ToolStep step, {double indent = 0}) {
      final item = widget.findTool(step.callId);
      return line(
        key: Key('traj-tool-${step.callId}'),
        icon: step.ok ? Icons.build_outlined : Icons.error_outline,
        tone: step.ok ? null : c.danger,
        title: toolLabel(step.name),
        sub: [if (!step.ok) '没成功', ?toolTarget(item?.arguments)].join(' · ').nullIfEmpty,
        trailing: step.ms == null ? '没结束' : formatSpan(step.ms!),
        indent: indent,
        onTap: () => _openStep(ToolStepPage(step: step, item: item)),
      );
    }

    final children = <Widget>[];
    for (final row in _rows) {
      switch (row) {
        case _HeaderRow(:final text):
          children.add(
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.x4, Space.x3, Space.x4, Space.x1),
              child: Text(text, style: t.labelMedium?.copyWith(color: c.textMuted)),
            ),
          );
        case _RequestRow(:final index, :final request, :final owner):
          final u = request.usage;
          children.add(
            line(
              key: Key('traj-request-${owner ?? ''}$index'),
              icon: Icons.auto_awesome_outlined,
              title: request.compaction ? '模型请求 $index（压缩对话）' : '模型请求 $index',
              sub: u == null ? '接口没返回用量' : '输入 ${formatTokens(u.input)} · 输出 ${formatTokens(u.output)}',
              trailing: formatSpan(request.ms),
              onTap: () => _openStep(RequestStepPage(index: index, request: request, owner: owner)),
            ),
          );
        case _ToolRow(:final step):
          children.add(toolLine(step));
        case final _GroupRow group:
          final open = _open.contains(group);
          final ms = group.tools.fold<int>(0, (n, s) => n + (s.ms ?? 0));
          children.add(
            InkWell(
              key: const Key('traj-group'),
              onTap: () => setState(() => open ? _open.remove(group) : _open.add(group)),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(Space.x4, Space.x2, Space.x3, Space.x2),
                  child: Row(
                    children: [
                      Icon(Icons.build_outlined, size: 20, color: c.textMuted),
                      const SizedBox(width: Space.x3),
                      Expanded(
                        child: Text(toolGroupSummary(group.tools), style: t.bodyMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
                      ),
                      const SizedBox(width: Space.x2),
                      Text(formatSpan(ms), style: faint),
                      Icon(open ? Icons.expand_less : Icons.expand_more, size: 18, color: c.textFaint),
                    ],
                  ),
                ),
              ),
            ),
          );
          if (open) children.addAll([for (final s in group.tools) toolLine(s, indent: Space.x6)]);
      }
    }

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
                  Text('本轮轨迹', style: t.titleLarge),
                  const SizedBox(height: Space.x1),
                  Text(
                    '用时 ${formatSpan(turn.ms)} · ${totalsLine(totals)}',
                    key: const Key('traj-summary'),
                    style: t.bodySmall?.copyWith(color: c.textMuted, height: 1.5),
                  ),
                  if (totals.requests > 0 && totals.reported == 0) const InfoBanner('这一轮接口没返回用量，所以没有 token 数。', margin: EdgeInsets.only(top: Space.x2)),
                ],
              ),
            ),
            Divider(height: 1, color: c.border),
            Flexible(
              child: ListView(
                key: const Key('traj-list'),
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: Space.x2),
                children: children,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════ 步骤详情 ═══════════════════════════

Widget _kv(BuildContext context, String label, String value, {Key? key}) {
  final t = Theme.of(context).textTheme;
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Expanded(
          child: Text(label, style: t.bodyMedium?.copyWith(color: context.colors.textMuted)),
        ),
        const SizedBox(width: Space.x3),
        Text(
          value,
          key: key,
          style: t.bodyMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
        ),
      ],
    ),
  );
}

/// 一次模型请求的详情：计时 + 用量分项。
class RequestStepPage extends StatelessWidget {
  const RequestStepPage({super.key, required this.index, required this.request, this.owner});
  final int index;
  final RequestUsage request;
  final String? owner;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final r = request;
    final u = r.usage;
    final speed = r.speed;
    return Scaffold(
      backgroundColor: c.canvas,
      appBar: PageBar(background: c.canvas, title: Text('模型请求 $index')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.x4, Space.x2, Space.x4, Space.x8),
        children: [
          if (owner != null)
            Padding(
              padding: const EdgeInsets.only(left: Space.x4, bottom: Space.x2),
              child: Text('子代理“$owner”发的请求', style: t.bodySmall?.copyWith(color: c.textMuted)),
            ),
          const GroupLabel('计时'),
          GroupCard(
            dividers: false,
            padding: const EdgeInsets.symmetric(horizontal: Space.x4, vertical: Space.x2),
            children: [
              _kv(context, '开始', r.startedAt == null ? '—' : _clock(r.startedAt!)),
              _kv(context, '首字', r.firstMs == null ? '—' : formatSpan(r.firstMs!), key: const Key('step-first')),
              _kv(context, '生成', r.generationMs == null ? '—' : formatSpan(r.generationMs!)),
              _kv(context, '总用时', formatSpan(r.ms)),
              _kv(context, '速度', speed == null ? '—' : '${speed.toStringAsFixed(1)} tokens/秒', key: const Key('step-speed')),
            ],
          ),
          const GroupLabel('用量'),
          GroupCard(
            dividers: false,
            padding: const EdgeInsets.symmetric(horizontal: Space.x4, vertical: Space.x2),
            children: u == null
                ? [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: Space.x2),
                      child: Text(
                        '这次请求接口没返回用量。',
                        key: const Key('step-no-usage'),
                        style: t.bodyMedium?.copyWith(color: c.textMuted),
                      ),
                    ),
                  ]
                : [
                    _kv(context, '命中缓存', u.hasCache ? formatTokens(u.cacheRead) : '—', key: const Key('step-hit')),
                    _kv(context, '未命中', formatTokens(u.uncached), key: const Key('step-miss')),
                    _kv(context, '写入缓存', u.hasCache ? formatTokens(u.cacheWrite) : '—'),
                    _kv(context, '推理', u.reasoning == null ? '—' : formatTokens(u.reasoning!)),
                    _kv(context, '回答', formatTokens(u.reasoning == null ? u.output : math.max(0, u.output - u.reasoning!))),
                    Divider(height: Space.x4, color: c.border),
                    _kv(context, '输入合计', formatTokens(u.input)),
                    _kv(context, '输出合计', formatTokens(u.output)),
                    if (r.cost != null) _kv(context, '估算费用', formatCost(r.cost!)),
                  ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.x4),
            child: Text('用量是接口返回的原始数字；“—”表示接口没给这一项。速度 = 输出 ÷ 生成用时。${r.cost != null ? '费用按你给模型填的单价估算，以服务商账单为准。' : ''}', style: t.bodySmall?.copyWith(color: c.textFaint, height: 1.6)),
          ),
        ],
      ),
    );
  }
}

/// 一次工具调用的详情：用时、参数、结果。
class ToolStepPage extends StatelessWidget {
  const ToolStepPage({super.key, required this.step, required this.item});
  final ToolStep step;

  /// 聊天记录里的那次调用；对话被压缩后找不到，是 null。
  final ToolItem? item;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    Widget code(String text, Key key) => SelectableText(
      text.length > 6000 ? '${text.substring(0, 6000)}\n…（太长，只显示前 6000 个字）' : text,
      key: key,
      style: t.bodySmall?.copyWith(fontFamily: 'monospace', height: 1.5),
    );
    return Scaffold(
      backgroundColor: c.canvas,
      appBar: PageBar(background: c.canvas, title: Text(toolLabel(step.name))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.x4, Space.x2, Space.x4, Space.x8),
        children: [
          const GroupLabel('计时'),
          GroupCard(
            dividers: false,
            padding: const EdgeInsets.symmetric(horizontal: Space.x4, vertical: Space.x2),
            children: [_kv(context, '工具', step.name), _kv(context, '用时', step.ms == null ? '没结束' : formatSpan(step.ms!)), _kv(context, '结果', item?.denied ?? false ? '被拒绝' : (step.ok ? '成功' : '没成功'))],
          ),
          if (item == null)
            const InfoBanner('这次调用的参数和结果已经不在对话记录里了（对话被压缩过）。')
          else ...[
            const GroupLabel('参数'),
            GroupCard(dividers: false, padding: const EdgeInsets.all(Space.x4), children: [code(item!.arguments.isEmpty ? '（没有参数）' : item!.arguments, const Key('step-args'))]),
            const GroupLabel('结果'),
            GroupCard(dividers: false, padding: const EdgeInsets.all(Space.x4), children: [code(item!.result ?? '（还没有结果）', const Key('step-result'))]),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════ 上下文小环 ═══════════════════════════

class ContextRing extends StatelessWidget {
  const ContextRing({super.key, required this.usage, required this.onTap});
  final ContextUsage usage;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final f = usage.fraction;
    final tone = contextTone(c, f);
    final label = formatPercent(f);
    return Semantics(
      button: true,
      label: '上下文已用 $label，点开看用量',
      excludeSemantics: true,
      child: InkWell(
        key: const Key('context-ring'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: SizedBox(
          height: 44,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.x1),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(value: f, strokeWidth: 2.5, color: tone, backgroundColor: c.border),
                ),
                const SizedBox(width: Space.x1),
                Text(
                  label,
                  key: const Key('context-ring-label'),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(color: f >= 0.6 ? tone : c.textFaint),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════ DeepSeek 余额 ═══════════════════════════

/// 余额卡：金额、充值 · 赠送、去充值、低余额提醒线。只给 DeepSeek 官方渠道用。
class BalanceCard extends StatelessWidget {
  const BalanceCard({super.key, required this.channel, this.onOpenQuota});
  final Channel channel;
  final VoidCallback? onOpenQuota;

  @override
  Widget build(BuildContext context) {
    final app = appOf(context);
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final state = app.quota.stateOf(channel.id);
    final info = state.result?.preferred;
    final others = [
      for (final i in state.result?.infos ?? const <BalanceInfo>[])
        if (i != info) i,
    ];
    final q = app.quota.quotaOf(channel.id);
    final faint = t.bodySmall?.copyWith(color: c.textFaint, height: 1.5);
    final line = app.quota.lowLine;
    return Column(
      key: const Key('balance-card'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text('DeepSeek 余额', style: t.labelMedium)),
            if (state.at != null && state.error == null) Text('更新于 ${_clock(state.at!)}', style: faint),
          ],
        ),
        const SizedBox(height: Space.x2),
        if (info == null)
          Text(
            state.loading ? '正在查余额…' : (state.keyInvalid ? 'Key 无效，查不到余额' : (state.error != null ? '余额没查到' : '还没查过余额')),
            key: const Key('balance-amount'),
            style: t.bodyLarge?.copyWith(color: c.textMuted),
          )
        else ...[
          Text(
            formatMoney(info.currency, info.total),
            key: const Key('balance-amount'),
            style: t.headlineSmall?.copyWith(color: info.total < line ? c.danger : c.text),
          ),
          Text(
            [
              if (info.toppedUp != null) '充值 ${formatMoney(info.currency, info.toppedUp!)}',
              if (info.granted != null) '赠送 ${formatMoney(info.currency, info.granted!)}',
              for (final o in others) '另有 ${formatMoney(o.currency, o.total)}',
            ].join(' · '),
            style: faint,
          ),
          if (state.keyInvalid) Text('Key 无效，查不到余额；上面是上一次查到的数。', style: faint?.copyWith(color: c.danger)),
        ],
        if (state.result != null && !state.result!.isAvailable)
          const InfoBanner(
            'DeepSeek 说这个账号的余额已经不能调用接口了，充值后才能继续用。',
            key: Key('balance-unavailable'),
            tone: BannerTone.danger,
            margin: EdgeInsets.only(top: Space.x2),
          ),
        if (q != null) ...[
          const SizedBox(height: Space.x3),
          Text(
            '额度上限：已使用 ${q.percent}%（剩余 ${formatMoney(q.currency, q.remaining)}）',
            key: const Key('balance-quota'),
            style: t.bodyMedium?.copyWith(color: q.reached ? c.danger : c.text),
          ),
          const SizedBox(height: Space.x1),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(value: q.fraction, minHeight: 4, color: q.reached ? c.danger : c.accentFill, backgroundColor: c.border),
          ),
        ],
        const SizedBox(height: Space.x2),
        Row(
          children: [
            Expanded(child: Text('低余额提醒线', style: t.bodyMedium)),
            DropdownButton<int>(
              key: const Key('balance-low-line'),
              value: line,
              underline: const SizedBox.shrink(),
              items: [for (final v in QuotaNotifier.lowLineChoices) DropdownMenuItem(value: v, child: Text(v == 0 ? '不提醒' : '$v 元'))],
              onChanged: (v) => v == null ? null : app.quota.setLowLine(v),
            ),
          ],
        ),
        Wrap(
          spacing: Space.x2,
          children: [
            TextButton(key: const Key('balance-topup'), onPressed: () => copyTopUpLink(context), child: const Text('去充值')),
            if (onOpenQuota != null) TextButton(key: const Key('balance-open-quota'), onPressed: onOpenQuota, child: Text(q == null ? '设置额度上限' : '额度上限')),
            TextButton(onPressed: state.loading ? null : () => app.quota.refresh(channel, force: true), child: Text(state.loading ? '正在查…' : '刷新')),
          ],
        ),
      ],
    );
  }
}

/// “去充值”：LopiCode 没带打开外部浏览器的组件，这里把充值页网址复制到剪贴板，由用户贴进浏览器。
Future<void> copyTopUpLink(BuildContext context) async {
  await Clipboard.setData(const ClipboardData(text: QuotaNotifier.topUpUrl));
  if (context.mounted) showSnack(context, '充值页网址已复制，贴到浏览器里打开：${QuotaNotifier.topUpUrl}');
}

/// 输入框上方的低余额小提示：“余额仅剩 ¥x · 低于 ¥y　去充值 ×”。关掉后这次运行不再出现。
class LowBalanceStrip extends StatelessWidget {
  const LowBalanceStrip({super.key, required this.channel});
  final Channel channel;

  @override
  Widget build(BuildContext context) {
    final app = appOf(context);
    return QuotaBuilder(
      builder: (context, _) {
        final info = app.quota.lowBalance(channel);
        if (info == null) return const SizedBox.shrink();
        final c = context.colors;
        final t = Theme.of(context).textTheme;
        return Container(
          key: const Key('low-balance-strip'),
          margin: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x2),
          padding: const EdgeInsets.only(left: Space.x3),
          decoration: BoxDecoration(color: c.warningSoft, borderRadius: BorderRadius.circular(Radii.sm)),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '余额仅剩 ${formatMoney(info.currency, info.total)} · 低于 ${formatMoney(info.currency, app.quota.lowLine.toDouble())}',
                  style: t.bodySmall?.copyWith(color: c.text),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton(
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 44),
                  padding: const EdgeInsets.symmetric(horizontal: Space.x2),
                ),
                onPressed: () => copyTopUpLink(context),
                child: const Text('去充值'),
              ),
              IconButton(
                key: const Key('low-balance-close'),
                tooltip: '这次不再提示',
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                onPressed: () => app.quota.dismissLow(channel.id),
                icon: Icon(Icons.close, size: 18, color: c.textMuted),
              ),
            ],
          ),
        );
      },
    );
  }
}
