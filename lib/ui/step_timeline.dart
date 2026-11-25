// 设计约束（步骤时间线的零件：圆点、竖线、用时、结果摘要 · 390×844）— 2026-11-25
// - 层级：步骤那一行（动作 + 对象）＞ 结果摘要（更小、更淡，等宽的几行）＞ 竖线和圆点（最淡，只是把一组步骤串起来）。
// - 圆点四种状态，形状各不相同，不只靠颜色区分：
//   · 进行中：空心圆环（会转；系统开了“减少动画”就是不转的空心环）；
//   · 成功：小实心点；
//   · 失败：叉；
//   · 被拒绝：圆圈加一道斜杠。
//   失败 / 被拒绝在行尾还各有两个字（“失败”“已拒绝”），读屏也念得出来。
// - 竖线从上一步的圆点连到下一步的圆点，在圆点处断开；一组里第一步上面、最后一步下面没有线。
// - 用时在行尾，一小段灰字：进行中每秒跳一次（“12 秒”），做完显示总用时；不到 1 秒的做完就不显示（详情里有）。
// - 结果摘要最多 1 行标题 + 3 行内容，每行都只占一行、放不下用省略号；点开这一步时摘要让位给详情，不重复。
// - 颜色只出现在状态上：失败红、被拒绝橙、进行中的环用强调色；其余全是中性灰。没有主操作。
import 'dart:async';

import 'package:lopicode/session/chat_models.dart';
import 'package:lopicode/session/step_digest.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// 圆点那一列的宽度（竖线画在它正中间）。
const double kRailWidth = 24;

/// 步骤那一行的最小高度；圆点的中心在它的一半。
const double kStepRowHeight = 36;

/// 竖线在圆点上下各让开多少。
const double kRailGap = 9;

/// 现在几点（界面测试换成假的钟，好让“用时”往前走）。
@visibleForTesting
DateTime Function() stepClock = DateTime.now;

enum StepPhase { running, ok, failed, denied }

StepPhase stepStateOf(ToolItem tool) => tool.running
    ? StepPhase.running
    : tool.denied
    ? StepPhase.denied
    : tool.ok
    ? StepPhase.ok
    : StepPhase.failed;

/// 一步在一组里的位置：决定竖线画不画上半段 / 下半段。
class RailSpot {
  const RailSpot({required this.first, required this.last});
  final bool first;
  final bool last;
}

/// 时间线上的圆点。
class StepMarker extends StatelessWidget {
  const StepMarker({super.key, required this.state});
  final StepPhase state;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final (String label, Widget mark) = switch (state) {
      StepPhase.running => (
        '进行中',
        still
            ? Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: c.accent, width: 2),
                ),
              )
            : SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: c.accent)),
      ),
      StepPhase.ok => (
        '完成',
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(shape: BoxShape.circle, color: c.textFaint),
        ),
      ),
      StepPhase.failed => ('失败', Icon(Icons.close, size: 15, color: c.danger)),
      StepPhase.denied => ('被拒绝', Icon(Icons.block, size: 14, color: c.warning)),
    };
    return Semantics(
      label: label,
      child: SizedBox(
        key: ValueKey('step-marker-${state.name}'),
        width: kRailWidth,
        height: kStepRowHeight,
        child: Center(child: mark),
      ),
    );
  }
}

/// 给一步（或者步骤之间的一句话）画上左边那条竖线。[spot] 为 null 就不画线。
/// [marker]＝true：这一项有圆点，线在圆点处断开；false：线从上到下不断（步骤之间的话、思考）。
class TimelineRail extends StatelessWidget {
  const TimelineRail({super.key, required this.spot, required this.child, this.marker = true});
  final RailSpot? spot;
  final Widget child;
  final bool marker;

  @override
  Widget build(BuildContext context) {
    final spot = this.spot;
    if (spot == null) return child;
    return Stack(
      children: [
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: kRailWidth,
          child: CustomPaint(
            painter: _RailPainter(color: context.colors.border, first: spot.first, last: spot.last, marker: marker),
          ),
        ),
        child,
      ],
    );
  }
}

class _RailPainter extends CustomPainter {
  const _RailPainter({required this.color, required this.first, required this.last, required this.marker});
  final Color color;
  final bool first;
  final bool last;
  final bool marker;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    final x = size.width / 2;
    if (!marker) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
      return;
    }
    const center = kStepRowHeight / 2;
    if (!first) canvas.drawLine(Offset(x, 0), const Offset(kRailWidth / 2, center - kRailGap), paint);
    if (!last && size.height > center + kRailGap) canvas.drawLine(Offset(x, center + kRailGap), Offset(x, size.height), paint);
  }

  @override
  bool shouldRepaint(_RailPainter old) => old.color != color || old.first != first || old.last != last || old.marker != marker;
}

/// 行尾的用时：进行中每秒跳一次；做完显示总用时（不到 [kStepShowSpanMs] 不显示）。
class StepElapsed extends StatefulWidget {
  const StepElapsed({super.key, required this.tool});
  final ToolItem tool;

  @override
  State<StepElapsed> createState() => _StepElapsedState();
}

class _StepElapsedState extends State<StepElapsed> {
  Timer? _tick;

  bool get _ticking => widget.tool.running && widget.tool.startedAt != null;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(StepElapsed oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  /// 只有正在跑的那一步才开表；跑完就停。这是数字在变，不是动画，所以“减少动画”时照样跳。
  void _sync() {
    if (_ticking) {
      _tick ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else {
      _tick?.cancel();
      _tick = null;
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tool = widget.tool;
    final String text;
    if (_ticking) {
      final secs = stepClock().difference(tool.startedAt!).inSeconds;
      text = formatStepSeconds(secs < 0 ? 0 : secs);
    } else {
      final ms = tool.ms;
      if (tool.running || ms == null || ms < kStepShowSpanMs) return const SizedBox.shrink();
      text = formatStepSpan(ms);
    }
    return Padding(
      padding: const EdgeInsets.only(left: Space.x2),
      child: Text(
        text,
        key: ValueKey('step-elapsed-${tool.callId}'),
        maxLines: 1,
        semanticsLabel: _ticking ? '已经跑了 $text' : '用了 $text',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.colors.textFaint, fontFeatures: const [FontFeature.tabularFigures()]),
      ),
    );
  }
}

/// 一步下面的结果摘要：一行标题 + 几行原样的输出。
class StepDigestView extends StatelessWidget {
  const StepDigestView({super.key, required this.tool});
  final ToolItem tool;

  @override
  Widget build(BuildContext context) {
    final change = tool.change;
    final digest = stepDigest(tool.name, tool.arguments, tool.result, ok: tool.ok, denied: tool.denied, hasChange: change != null && change.added + change.removed > 0);
    if (digest == null || digest.isEmpty) return const SizedBox.shrink();
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final headColor = switch (digest.tone) {
      DigestTone.bad => c.danger,
      DigestTone.denied => c.warning,
      DigestTone.plain => c.textFaint,
    };
    return Padding(
      key: ValueKey('step-digest-${tool.callId}'),
      padding: const EdgeInsets.only(left: kRailWidth + Space.x2, right: Space.x2, bottom: Space.x2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (digest.head.isNotEmpty)
            Text(
              digest.head,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.bodySmall?.copyWith(color: headColor),
            ),
          for (final line in digest.lines)
            Text(
              line,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontFamily: kMonoFont, fontFamilyFallback: kMonoFallback, fontSize: FontSize.xs, height: 1.5, color: c.textFaint),
            ),
        ],
      ),
    );
  }
}
