// 设计约束（低代码 · 面板里“用主题变量”的小零件 · 390×844）
// - 这里只有两样：把项目的主题变量带给面板里各个控件的一层（LcThemeScope），和“这是个变量”的小牌子（LcVarBadge）。
// - 小牌子：一个链环小图标 + 变量给人看的名字，强调色字、浅强调底——和“自己填的数”一眼分得开；高 36，和档位药丸一样高。
// - 取用的 tokens：Space.x1/x2/x3、Radii.sm、accent、accentSoft。
import 'package:lopicode/lowcode/theme_vars.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// 把项目的主题变量带给下面的控件（颜色按钮、长度框、预设档各自来取，不用一层层传）。
class LcThemeScope extends InheritedWidget {
  const LcThemeScope({super.key, required this.theme, required super.child});
  final LcTheme theme;

  /// 上面没有这一层（别的页面里单独用这些控件）就是“没有变量”。
  static LcTheme of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<LcThemeScope>()?.theme ?? LcTheme.empty;

  @override
  bool updateShouldNotify(LcThemeScope old) => !identical(old.theme, theme);
}

/// 这种 CSS 属性能用的变量（按种类挑）：名字、给人看的名字、现在的值。
List<({String name, String label, String value})> lcVarChoices(LcTheme theme, String cssName) => [
  for (final kind in lcVarKindsFor(cssName))
    for (final name in theme.namesOf(kind)) (name: name, label: theme.labelOf(name), value: theme.resolved(name)),
];

/// “这是个变量”的小牌子。[onTap] 不给就只是显示。
class LcVarBadge extends StatelessWidget {
  const LcVarBadge({super.key, required this.label, this.value, this.onTap, this.selected = true});
  final String label;

  /// 现在的值（写在名字后面，灰一点）；不给不写。
  final String? value;
  final VoidCallback? onTap;

  /// false＝只是一个可以选的变量（还没选它）：灰底。
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final fg = selected ? c.accent : c.text;
    return Material(
      color: selected ? c.accentSoft : c.surfaceMuted,
      borderRadius: BorderRadius.circular(Radii.sm),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: Space.x2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.link, size: 16, color: fg, semanticLabel: '主题变量'),
              const SizedBox(width: Space.x1),
              Flexible(
                child: Text(
                  label,
                  style: t.bodyMedium?.copyWith(color: fg, fontWeight: selected ? FontWeight.w600 : FontWeight.w400, height: 1.2),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (value != null) ...[const SizedBox(width: Space.x1), Text(value!, style: t.bodySmall?.copyWith(color: c.textMuted, height: 1.2), maxLines: 1)],
            ],
          ),
        ),
      ),
    );
  }
}
