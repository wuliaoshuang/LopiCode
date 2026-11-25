// 上下文占用分段条：用量面板“上下文”那一节里，一根横条按段上色，下面是图例。
//
// 设计约束（Refactoring UI · 先层级、再排版、最后上色）
// - 层级：这一节的主角是上面的“百分比 + 已用 / 上限”；分段条是它的展开说明，所以条不高（10）、图例用小字。
// - 一行只做一件事：横条独占一行；图例一段一行——左边色块 + 名称，右边“≈ token 数”和占比（数字右对齐、等宽数字）。
//   五段挤在一行会折行，不好对齐，所以竖排。
// - 不只靠颜色：每段在图例里都有文字名称和数字；条上各段之间留 2 的缝；不为 0 的段至少画 3 宽，免得看不见。
// - 上色：固定开销（系统提示词、工具定义）用蓝色，对话内容（消息、工具结果）用暖色，剩余用边框灰。
//   四段按“深、浅、深、浅”交替排：相邻两段不光色相不同，明暗也差得开（色弱、灰度屏上也分得出）。
//   颜色都取自 Palette，浅色、深色各一套（test/context_bar_test.dart 守着相邻两段的明暗差）。
// - 全是估算：底下一行小字写明。
import 'package:lopicode/agent/context_segments.dart';
import 'package:lopicode/agent/usage.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// 一段：名称、token 数、颜色。
typedef ContextSegment = ({String id, String label, int tokens, Color color});

/// 把估算结果排成五段（顺序固定）。
List<ContextSegment> contextSegmentsOf(ContextSegments s, {required bool dark, required Color restColor}) => [
  (id: 'system', label: '系统提示词', tokens: s.system, color: dark ? Palette.primary400 : Palette.primary700),
  (id: 'tools', label: '工具定义', tokens: s.tools, color: dark ? Palette.primary200 : Palette.primary300),
  (id: 'messages', label: '对话消息', tokens: s.messages, color: Palette.warning700),
  (id: 'results', label: '工具结果', tokens: s.toolResults, color: dark ? Palette.warning300 : Palette.warning400),
  (id: 'rest', label: '剩余', tokens: s.remaining, color: restColor),
];

/// 占比的写法：不到 1% 写“<1%”，0 写“0%”。
String segmentPercent(double share) => share <= 0 ? '0%' : (share < 0.01 ? '<1%' : '${(share * 100).round()}%');

class ContextSegmentBar extends StatelessWidget {
  const ContextSegmentBar({super.key, required this.segments});

  /// 还在算是 null。
  final ContextSegments? segments;

  static const double barHeight = 10;
  static const double gap = 2;
  static const double minSegment = 3;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final faint = t.bodySmall?.copyWith(color: c.textFaint, height: 1.5);
    final s = segments;
    if (s == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            key: const Key('context-bar-loading'),
            height: barHeight,
            decoration: BoxDecoration(color: c.border, borderRadius: BorderRadius.circular(barHeight / 2)),
          ),
          const SizedBox(height: Space.x2),
          Text('分项计算中…', key: const Key('usage-context-parts'), style: faint),
        ],
      );
    }
    final parts = contextSegmentsOf(s, dark: Theme.of(context).brightness == Brightness.dark, restColor: c.border);
    final shown = [
      for (final p in parts)
        if (p.tokens > 0) p,
    ];
    final numbers = t.bodySmall?.copyWith(color: c.textMuted, fontFeatures: const [FontFeature.tabularFigures()]);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          label: '上下文占用分段（估算）：${[for (final p in parts) '${p.label} ${segmentPercent(s.shareOf(p.tokens))}'].join('，')}',
          child: ClipRRect(
            borderRadius: BorderRadius.circular(barHeight / 2),
            child: SizedBox(
              key: const Key('context-bar'),
              height: barHeight,
              child: LayoutBuilder(
                builder: (context, box) {
                  // 先给每段留出最小宽度和缝，剩下的宽度按比例分。
                  final free = box.maxWidth - gap * (shown.length - 1) - minSegment * shown.length;
                  final sum = shown.fold<int>(0, (a, p) => a + p.tokens);
                  return Row(
                    children: [
                      for (final (i, p) in shown.indexed) ...[
                        if (i > 0) const SizedBox(width: gap),
                        Container(key: Key('context-seg-${p.id}'), width: minSegment + (free <= 0 || sum == 0 ? 0 : free * p.tokens / sum), color: p.color),
                      ],
                    ],
                  );
                },
              ),
            ),
          ),
        ),
        const SizedBox(height: Space.x3),
        for (final p in parts)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.x1),
            child: Row(
              key: Key('context-legend-${p.id}'),
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(color: p.color, borderRadius: BorderRadius.circular(3)),
                ),
                const SizedBox(width: Space.x2),
                Expanded(
                  child: Text(p.label, style: t.bodySmall?.copyWith(color: c.text)),
                ),
                Text('≈ ${formatTokens(p.tokens)}', style: numbers),
                SizedBox(
                  width: 44,
                  child: Text(segmentPercent(s.shareOf(p.tokens)), textAlign: TextAlign.right, style: numbers),
                ),
              ],
            ),
          ),
        const SizedBox(height: Space.x1),
        Text('系统提示词、工具定义、对话消息、工具结果各段都是按字数估算的，和接口实际计的数会有出入。', key: const Key('usage-context-parts'), style: faint),
      ],
    );
  }
}
