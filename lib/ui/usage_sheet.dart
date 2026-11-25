// 用量弹层：上下文占了多少、这段对话累计用了多少、缓存命中率、余额卡。从 usage_ui.dart 拆出来的。

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lopicode/agent/context_segments.dart';
import 'package:lopicode/agent/model_config.dart';
import 'package:lopicode/agent/quota.dart';
import 'package:lopicode/agent/usage.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/state/models_state.dart';
import 'package:lopicode/state/workspace_chat.dart';
import 'package:lopicode/state/workspace_conversations.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/app_ref.dart';
import 'package:lopicode/ui/context_bar.dart';
import 'package:lopicode/ui/usage_ui.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';

// ═══════════════════════════ 用量弹层 ═══════════════════════════

class UsageSheet extends ConsumerStatefulWidget {
  const UsageSheet({super.key, required this.session, this.onOpenQuota});
  final ProjectSession session;
  final void Function(Channel channel)? onOpenQuota;

  @override
  ConsumerState<UsageSheet> createState() => _UsageSheetState();
}

class _UsageSheetState extends ConsumerState<UsageSheet> {
  ContextSegments? _parts;
  bool _asked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_asked) return;
    _asked = true;
    widget.session.contextSegments().then((v) {
      if (mounted) setState(() => _parts = v);
    });
    // 打开用量弹层时查一次余额（最多每分钟一次）。
    final ch = widget.session.currentModel?.channel;
    if (ch != null) appOf(context).quota.refresh(ch);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final s = widget.session;
    // 弹层开着的时候 Agent 可能还在跑：对话的用量、换了模型（上下文窗口跟着变）都要跟上
    ref
      ..watch(activeChatProvider(s))
      ..watch(conversationsProvider(s))
      ..watch(modelsProvider);
    final ctx = s.contextUsage;
    final u = s.usageTotals;
    final rate = u.hitRate;
    final ch = s.currentModel?.channel;
    final faint = t.bodySmall?.copyWith(color: c.textFaint, height: 1.5);

    Widget stat(String label, String value, {Key? key}) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: t.bodySmall?.copyWith(color: c.textMuted)),
          const SizedBox(height: 2),
          Text(
            value,
            key: key,
            style: t.titleMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
          ),
        ],
      ),
    );

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('用量', style: t.titleLarge),
            const SizedBox(height: Space.x3),
            // ① 上下文
            Row(
              children: [
                Expanded(child: Text('上下文', style: t.labelMedium)),
                if (ctx != null) Text(ctx.estimated ? '预计下次请求（估算）' : '上次请求', key: const Key('usage-context-kind'), style: faint),
              ],
            ),
            const SizedBox(height: Space.x2),
            if (ctx == null)
              Text('还没选模型，算不出来。', style: t.bodyMedium?.copyWith(color: c.textMuted))
            else ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    formatPercent(ctx.fraction),
                    key: const Key('usage-context-pct'),
                    style: t.headlineSmall?.copyWith(color: ctx.fraction >= 0.6 ? contextTone(c, ctx.fraction) : c.text),
                  ),
                  const SizedBox(width: Space.x3),
                  Text(
                    '${formatTokens(ctx.used)} / ${formatTokens(ctx.limit)}',
                    key: const Key('usage-context'),
                    style: t.bodyMedium?.copyWith(color: c.textMuted),
                  ),
                ],
              ),
              const SizedBox(height: Space.x2),
              // 分段条：系统提示词 / 工具定义 / 对话消息 / 工具结果 / 剩余（估算），见 context_bar.dart。
              ContextSegmentBar(segments: _parts),
              if (ctx.fraction > 0.85)
                const InfoBanner(
                  '上下文快满了。发 /compact 可以把前面的内容压缩成摘要再继续。',
                  tone: BannerTone.warning,
                  margin: EdgeInsets.only(top: Space.x2),
                ),
            ],
            const SizedBox(height: Space.x4),
            Divider(height: 1, color: c.border),
            const SizedBox(height: Space.x4),
            // ② 本对话
            Text('本对话', style: t.labelMedium),
            const SizedBox(height: Space.x2),
            if (u.requests == 0)
              Text(
                '还没有向模型发过请求。',
                key: const Key('usage-empty'),
                style: t.bodyMedium?.copyWith(color: c.textMuted),
              )
            else ...[
              Row(
                children: [
                  stat('累计输入', u.reported == 0 ? '—' : formatTokens(u.input), key: const Key('usage-total-in')),
                  stat('缓存命中率', rate == null ? '—' : formatPercent(rate), key: const Key('usage-total-rate')),
                  stat('输出', u.reported == 0 ? '—' : formatTokens(u.output), key: const Key('usage-total-out')),
                ],
              ),
              const SizedBox(height: Space.x3),
              Row(
                children: [
                  stat('共几轮', '${u.turns}', key: const Key('usage-total-turns')),
                  stat('写入缓存', u.hasCache ? formatTokens(u.cacheWrite) : '—'),
                  stat('估算费用', u.costed > 0 ? formatCost(u.cost) : '—', key: const Key('usage-total-cost')),
                ],
              ),
              const SizedBox(height: Space.x2),
              Text(
                [
                  '输入含缓存命中。共 ${u.requests} 次请求${u.unreported > 0 ? '，其中 ${u.unreported} 次接口没返回用量' : ''}，含派出去的子代理；压缩对话那一次不计。',
                  if (u.costed == 0) '给模型填了单价（设置 → 模型与渠道 → 点模型）才有估算费用。',
                  if (u.costed > 0 && u.costed < u.reported) '费用只算了填过单价的 ${u.costed} 次请求。',
                  if (rate == null && u.reported > 0) '接口没给缓存数据，所以没有命中率。',
                ].join(''),
                style: faint,
              ),
            ],
            // ③ DeepSeek 余额
            if (ch != null && isDeepSeekOfficial(ch.baseUrl)) ...[
              const SizedBox(height: Space.x4),
              Divider(height: 1, color: c.border),
              const SizedBox(height: Space.x4),
              QuotaBuilder(
                builder: (context, _) => BalanceCard(channel: ch, onOpenQuota: widget.onOpenQuota == null ? null : () => widget.onOpenQuota!(ch)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
