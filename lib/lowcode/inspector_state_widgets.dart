// 设计约束（低代码 · 合一面板“样式”页顶上的“状态”一行 · 390×844）
// - 内容主次：一行只做一件事——选“现在改的是哪个状态的样子”。左边灰字“状态”，右边四个药丸：平时 / 按下 / 禁用 / 聚焦。
// - 唯一主操作：没有。选中的药丸用浅强调底 + 强调色字；写过东西的状态药丸右上角一个小圆点（不选它也看得出“这个状态设过”）。
// - 选了“平时”以外的：下面多一行小字说清楚“现在改的只记成这个状态下和平时不一样的地方”，右边“清掉”（这个状态写过东西才有）。
//   这一行用强调色的浅底，时刻提醒她现在改的不是平时的样子。
// - 选了“禁用”、可这种组件不能禁用（文本、容器…）：提示条下面再加一句灰字，说清楚设了不生效、哪些组件能禁用。
// - 这个控件上有“类名开关”时（第四轮 B2）：每条类名在后面多一个药丸“类名 xx”，选了改的是这条类名成立时的样子。
// - 取用的 tokens：Space.x1/x2/x3、Radii.sm、accent、accentSoft、surfaceMuted、text、textMuted。
import 'package:lopicode/lowcode/states.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

class LcStateBar extends StatelessWidget {
  const LcStateBar({super.key, required this.state, required this.filled, required this.onPick, required this.onClear, this.caveat, this.classes = const [], this.note});

  /// 这个控件上的类名开关（第四轮 B2）：每条多一个药丸“类名 xx”，选了改的是它成立时的样子。
  final List<String> classes;

  /// 顶替“现在改的是…”那条提示的东西（画布在平板 / 桌面档时，屏宽和状态并成一条说，见 inspector_bp_widgets.dart）。
  final Widget? note;

  /// 这个状态在这种组件上不生效时的一句说明（灰字，写在提示条下面）。
  final String? caveat;

  /// 现在改的是哪个状态；null＝平时。
  final String? state;

  /// 写过东西的状态。
  final Set<String> filled;
  final ValueChanged<String?> onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    Widget pill(String? name) {
      final on = name == state;
      return Padding(
        padding: const EdgeInsets.only(right: Space.x2),
        child: Material(
          color: on ? c.accentSoft : c.surfaceMuted,
          borderRadius: BorderRadius.circular(Radii.sm),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: Key('lc-state-${name ?? 'normal'}'),
            onTap: on ? null : () => onPick(name),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 36, minWidth: 48),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.x3),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(name == null ? '平时' : (lcClassOfState(name) == null ? kLcStateLabels[name]! : '类名 ${lcClassOfState(name)}'), style: t.labelLarge?.copyWith(color: on ? c.accent : c.text)),
                    if (name != null && filled.contains(name))
                      Container(
                        key: Key('lc-state-dot-$name'),
                        margin: const EdgeInsets.only(left: Space.x1),
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    final now = state;
    return Column(
      key: const Key('lc-state-bar'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            SizedBox(
              width: 48,
              child: Text('状态', style: t.bodyMedium?.copyWith(color: c.textMuted)),
            ),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [pill(null), for (final s in kLcStateNames) pill(s), for (final k in classes) pill(lcClassState(k))]),
              ),
            ),
          ],
        ),
        if (now != null && note != null) ...[const SizedBox(height: Space.x2), note!],
        if (now != null && note == null) ...[
          const SizedBox(height: Space.x2),
          Container(
            key: const Key('lc-state-note'),
            padding: const EdgeInsets.fromLTRB(Space.x3, Space.x1, Space.x1, Space.x1),
            decoration: BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(Radii.sm)),
            child: Row(
              children: [
                Expanded(
                  child: Text('现在改的是“${lcStateLabel(now)}”时的样子：只记和平时不一样的地方。', style: t.bodySmall?.copyWith(color: c.text)),
                ),
                if (filled.contains(now)) TextButton(key: const Key('lc-state-clear'), onPressed: onClear, child: const Text('清掉')) else const SizedBox(height: 40),
              ],
            ),
          ),
        ],
        if (caveat != null)
          Padding(
            padding: const EdgeInsets.only(top: Space.x2),
            child: Text(
              caveat!,
              key: const Key('lc-state-caveat'),
              style: t.bodySmall?.copyWith(color: c.textMuted),
            ),
          ),
        if (now == null || note == null) const SizedBox(height: Space.x3),
      ],
    );
  }
}
