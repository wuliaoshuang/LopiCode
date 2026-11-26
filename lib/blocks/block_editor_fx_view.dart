// 设计约束（积木编辑器里的几样小浮层，390 宽，浅色 + 深色）— 2026-11-24
// - 提示条：一句人话，贴在积木盒上沿之上（不盖画布顶上那串的帽子；键盘弹出时页面整体上移，它跟着在键盘上面）。
//   一行只做一件事：左边是话，需要时右边带一个动作（“撤销”），没有别的。两秒多自己消失。
// - 空画布引导：画布正中一句话 + 下面一个往上走的箭头（指着“从积木盒往上拖”这个动作）。箭头只在出现时、
//   和被提醒时动两下，不一直动（一直动费电，也让人分心）；系统开了“减弱动态效果”就不动。拖出第一块以后整个消失。
// - 就地输入框：长得和积木上的输入槽一样（同样的底色、同样的胶囊形），正好盖在那个槽上，只多一圈强调色描边。
//   不带投影：它是“槽变成了可以打字的样子”，不是浮在上面的另一层。
import 'dart:math' as math;

import 'package:lopicode/blocks/block_colors.dart';
import 'package:lopicode/blocks/block_script_view.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// 画布下沿的一句提示，可以带一个动作。
class BkToastBar extends StatelessWidget {
  const BkToastBar({super.key, required this.text, this.actionLabel, this.onAction});

  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(color: c.surface, fontWeight: FontWeight.w600);
    final label = actionLabel;
    return IgnorePointer(
      ignoring: label == null,
      child: Center(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: c.text,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: c.shadowOf(0.18), blurRadius: 10, offset: const Offset(0, 3))],
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, label == null ? 9 : 2, label == null ? 16 : 4, label == null ? 9 : 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(text, key: const ValueKey('bk-toast'), textAlign: TextAlign.center, style: style),
                ),
                if (label != null)
                  TextButton(
                    key: const ValueKey('bk-toast-action'),
                    onPressed: onAction,
                    style: TextButton.styleFrom(foregroundColor: c.accentSoft, minimumSize: const Size(52, 40), padding: const EdgeInsets.symmetric(horizontal: 12)),
                    child: Text(label, style: style?.copyWith(color: null, fontWeight: FontWeight.w700)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 空画布上的引导。`nudge` 每变一次，箭头再动两下。
class BkEmptyGuide extends StatefulWidget {
  const BkEmptyGuide({super.key, this.nudge = 0});

  final int nudge;

  @override
  State<BkEmptyGuide> createState() => _BkEmptyGuideState();
}

class _BkEmptyGuideState extends State<BkEmptyGuide> with SingleTickerProviderStateMixin {
  /// 一下多久、动几下。总共不到两秒：比提示条停留的时间短。
  static const Duration beat = Duration(milliseconds: 800);
  static const int beats = 2;

  late final AnimationController _anim = AnimationController(vsync: this, duration: beat);
  bool _still = false;

  void _play() {
    if (_still) {
      _anim.value = 0;
      return;
    }
    _anim.repeat(count: beats).whenCompleteOrCancel(() {
      if (mounted) _anim.value = 0;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.disableAnimationsOf(context);
    final first = !_anim.isAnimating && _anim.value == 0 && _anim.lastElapsedDuration == null;
    if (still != _still || first) {
      _still = still;
      _anim.stop();
      _play();
    }
  }

  @override
  void didUpdateWidget(BkEmptyGuide oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.nudge != widget.nudge) _play();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '还没有积木。\n从下面的积木盒里按住一块“事件”，\n拖上来放在这里，再往它下面拼积木。',
          key: const ValueKey('bk-empty'),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: c.textMuted, height: 1.6),
        ),
        const SizedBox(height: 18),
        SizedBox(
          height: 56,
          child: AnimatedBuilder(
            animation: _anim,
            builder: (context, _) {
              // 从下往上走一段，头尾淡一点：像一块积木被从下面提上来。
              final t = _anim.value;
              final lift = _still ? 0.0 : (0.5 - Curves.easeInOut.transform(t)) * 28;
              final fade = _still || !_anim.isAnimating ? 1.0 : 0.35 + 0.65 * math.sin(t * math.pi);
              return Transform.translate(
                offset: Offset(0, lift),
                child: Opacity(
                  opacity: fade,
                  child: Icon(Icons.keyboard_double_arrow_up_rounded, key: const ValueKey('bk-empty-arrow'), size: 36, color: c.accent),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// 就地输入框：盖在槽上，长得和槽一样。
class BkInlineField extends StatelessWidget {
  const BkInlineField({
    super.key,
    required this.kit,
    required this.tone,
    required this.controller,
    required this.focusNode,
    required this.number,
    required this.invalid,
    required this.zoom,
    this.onChanged,
    this.onSubmitted,
  });

  final BkKit kit;

  /// 这个槽所在积木的配色（输入框的底色、字色跟着它）。
  final BkTone tone;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool number;
  final bool invalid;
  final double zoom;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ring = invalid ? c.danger : c.accent;
    return LayoutBuilder(
      builder: (context, box) {
        final radius = BorderRadius.circular(math.min(box.maxHeight / 2, 14 * math.max(1, zoom)));
        return DecoratedBox(
          decoration: BoxDecoration(
            color: tone.fieldBg,
            borderRadius: radius,
            border: Border.all(color: ring, width: 2),
            // 一圈很淡的光晕代替投影：说明“现在在改这里”。
            boxShadow: [BoxShadow(color: ring.withValues(alpha: 0.28), blurRadius: 0, spreadRadius: 3)],
          ),
          child: Center(
            child: TextField(
              key: const ValueKey('bk-inline-input'),
              controller: controller,
              focusNode: focusNode,
              autofocus: true,
              keyboardType: number ? const TextInputType.numberWithOptions(decimal: true, signed: true) : TextInputType.text,
              textInputAction: TextInputAction.done,
              textAlign: TextAlign.center,
              cursorColor: c.accent,
              style: TextStyle(fontFamily: kit.text.fontFamily, fontSize: (kit.metrics.fontSize * zoom).clamp(13.0, 28.0), height: 1.25, color: tone.fieldText),
              decoration: InputDecoration(
                isDense: true,
                isCollapsed: true,
                filled: false,
                hintText: number ? '数字' : '文字',
                hintStyle: TextStyle(color: tone.fieldHint),
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
              onChanged: onChanged,
              onSubmitted: onSubmitted,
            ),
          ),
        );
      },
    );
  }
}
