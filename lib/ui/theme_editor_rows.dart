// 设计约束（主题编辑器里列表的每一种行 + “对比度偏低”的列表面板 · 宽 390）— 2026-11-26
// - 所有行一样高（[kThemeRowHeight]）：这样“跳到某一项”能直接算出滚到哪，191 项也只排屏幕上看得见的那几行。
// - 组的标题行：左边箭头（展开 / 收起）+ 组名，右边弱化写“改了几项 / 共几项”。整行可点。
// - 颜色行（一行一项）：色块 → 名字（第二行是现在的值，等宽字；改过的前面有一个小圆点）→ 右边：
//   对比度偏低的记号（只是记号，点整行照样进取色面板）；高亮分类多两个小开关“粗”“斜”。整行点开取色面板。
// - 数值行：名字（第二行是说明）→ 右边“减 · 数值 · 加”三个挨着的控件（不用滑杆：手指拖不准 0.05 这种步子）。
//   到头了那一边的按钮变灰。
// - 只读（内置主题）时：行照样能看，开关和加减是灰的，点行由编辑器给一句“复制一份来改”。
// - 颜色全部从主题取；色块里画的是“正在编辑的那份主题”里的颜色，不是全应用现在的主题。
import 'package:lopicode/appearance/theme_contrast.dart';
import 'package:lopicode/appearance/theme_edit_model.dart';
import 'package:lopicode/appearance/theme_fields.dart';
import 'package:lopicode/appearance/theme_json.dart';
import 'package:lopicode/appearance/theme_spec.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/theme_color_picker.dart';
import 'package:material_ui/material_ui.dart';

/// 编辑器列表里每一行的高度。
const double kThemeRowHeight = 56;

/// 组的标题行。
class ThemeSectionHeader extends StatelessWidget {
  const ThemeSectionHeader({super.key, required this.id, required this.title, required this.total, required this.changed, required this.expanded, required this.onTap});
  final String id;
  final String title;
  final int total;
  final int changed;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      label: '$title，$total 项${expanded ? '，已展开' : '，已收起'}',
      excludeSemantics: true,
      child: InkWell(
        key: Key('theme-section-$id'),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.x4),
          child: Row(
            children: [
              Icon(expanded ? Icons.expand_more : Icons.chevron_right, size: 20, color: c.textMuted),
              const SizedBox(width: Space.x2),
              Expanded(
                child: Text(title, style: t.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              Text(
                changed > 0 ? '改了 $changed 项 · 共 $total 项' : '$total 项',
                key: Key('theme-section-$id-count'),
                style: t.bodySmall?.copyWith(color: changed > 0 ? c.accent : c.textFaint),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 一个颜色项。
class ThemeColorRow extends StatelessWidget {
  const ThemeColorRow({super.key, required this.item, required this.spec, required this.changed, required this.low, required this.readOnly, required this.onTap, required this.onStyle});
  final ThemeItem item;

  /// 正在编辑的那份主题。
  final ThemeSpec spec;
  final bool changed;

  /// 对比度偏低。
  final bool low;
  final bool readOnly;
  final VoidCallback onTap;

  /// 高亮分类的粗体 / 斜体开关（只有高亮分类会用到）。
  final ValueChanged<TokenStyle> onStyle;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final color = itemColor(spec, item);
    final style = item.isToken ? (spec.tokens[item.key] ?? const TokenStyle()) : null;
    return InkWell(
      key: Key('theme-item-${item.id}'),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(left: Space.x4, right: Space.x3),
        child: Row(
          children: [
            ThemeSwatch(color, key: Key('theme-item-${item.id}-swatch'), size: 32),
            const SizedBox(width: Space.x3),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.label, style: t.bodyMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                  Row(
                    children: [
                      if (changed)
                        Container(
                          key: Key('theme-item-${item.id}-changed'),
                          width: 6,
                          height: 6,
                          margin: const EdgeInsets.only(right: Space.x1),
                          decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle),
                        ),
                      Flexible(
                        child: Text(
                          color == null ? '跟着代码文字的颜色' : formatThemeColor(color),
                          key: Key('theme-item-${item.id}-value'),
                          style: t.bodySmall?.copyWith(color: c.textFaint, fontFamily: color == null ? null : kMonoFont, fontFamilyFallback: color == null ? null : kMonoFallback),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (low)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.x1),
                child: Tooltip(
                  message: '对比度偏低',
                  child: Icon(Icons.warning_amber_rounded, key: Key('theme-item-${item.id}-low'), size: 18, color: c.warning),
                ),
              ),
            if (style != null) ...[
              _StyleToggle(
                key: Key('theme-item-${item.id}-bold'),
                label: '粗',
                tooltip: '粗体',
                on: style.bold,
                bold: true,
                onTap: readOnly ? null : () => onStyle(style.copyWith(bold: !style.bold)),
              ),
              _StyleToggle(
                key: Key('theme-item-${item.id}-italic'),
                label: '斜',
                tooltip: '斜体',
                on: style.italic,
                italic: true,
                onTap: readOnly ? null : () => onStyle(style.copyWith(italic: !style.italic)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StyleToggle extends StatelessWidget {
  const _StyleToggle({super.key, required this.label, required this.tooltip, required this.on, required this.onTap, this.bold = false, this.italic = false});
  final String label;
  final String tooltip;
  final bool on;
  final VoidCallback? onTap;
  final bool bold;
  final bool italic;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      toggled: on,
      label: tooltip,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.sm),
        // 可点范围 40×44，里面画一个 32 的小方块。
        child: SizedBox(
          width: 40,
          height: 44,
          child: Center(
            child: Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: on ? c.accentSoft : null,
                borderRadius: BorderRadius.circular(Radii.sm),
                border: Border.all(color: on ? c.accent : c.border),
              ),
              child: Text(
                label,
                style: Theme.of(context).textTheme.labelLarge
                    ?.copyWith(color: onTap == null ? c.textFaint : (on ? c.accent : c.textMuted), fontWeight: bold ? FontWeight.w700 : null, fontStyle: italic ? FontStyle.italic : null),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 一个数（形状与密度）：减 · 数值 · 加。
class ThemeMetricRow extends StatelessWidget {
  const ThemeMetricRow({super.key, required this.field, required this.value, required this.changed, required this.readOnly, required this.onChanged});
  final ThemeMetricField field;
  final double value;
  final bool changed;
  final bool readOnly;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final down = bumpMetric(field, value, -1), up = bumpMetric(field, value, 1);
    Widget step(String id, IconData icon, String tip, double to) => IconButton(
      key: Key('theme-metric-${field.key}-$id'),
      icon: Icon(icon, size: 20),
      tooltip: tip,
      visualDensity: VisualDensity.compact,
      onPressed: readOnly || to == value ? null : () => onChanged(to),
    );
    return Padding(
      key: Key('theme-metric-${field.key}'),
      padding: const EdgeInsets.only(left: Space.x4, right: Space.x2),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (changed)
                      Container(
                        width: 6,
                        height: 6,
                        margin: const EdgeInsets.only(right: Space.x1),
                        decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle),
                      ),
                    Flexible(
                      child: Text(field.label, style: t.bodyMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
                Text(
                  field.note.isEmpty ? '${formatMetric(field.min)} – ${formatMetric(field.max)}' : field.note,
                  style: t.bodySmall?.copyWith(color: c.textFaint),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          step('minus', Icons.remove, '减一点', down),
          SizedBox(
            width: 44,
            child: Text(
              formatMetric(value),
              key: Key('theme-metric-${field.key}-value'),
              textAlign: TextAlign.center,
              style: t.bodyMedium?.copyWith(fontFamily: kMonoFont, fontFamilyFallback: kMonoFallback),
            ),
          ),
          step('plus', Icons.add, '加一点', up),
        ],
      ),
    );
  }
}

/// 一行“动作”（快捷生成那两行）：图标 + 名字 + 一句说明 + 右箭头。
class ThemeActionRow extends StatelessWidget {
  const ThemeActionRow({super.key, required this.icon, required this.title, required this.subtitle, required this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.x4),
        child: Row(
          children: [
            SizedBox(width: 32, child: Icon(icon, size: 20, color: onTap == null ? c.textFaint : c.accent)),
            const SizedBox(width: Space.x3),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: t.bodyMedium?.copyWith(color: onTap == null ? c.textFaint : null),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    subtitle,
                    style: t.bodySmall?.copyWith(color: c.textFaint),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 20, color: c.textFaint),
          ],
        ),
      ),
    );
  }
}

/// 顶上那条“N 项对比度偏低”。
class ThemeContrastBanner extends StatelessWidget {
  const ThemeContrastBanner({super.key, required this.count, required this.onTap});
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.warningSoft,
      child: InkWell(
        key: const Key('theme-contrast-banner'),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.x4, vertical: Space.x2),
          child: Row(
            children: [
              Icon(Icons.warning_amber_rounded, size: 18, color: c.warning),
              const SizedBox(width: Space.x2),
              Expanded(
                child: Text('$count 项对比度偏低', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: c.warning)),
              ),
              Text('看看', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: c.warning)),
              Icon(Icons.chevron_right, size: 18, color: c.warning),
            ],
          ),
        ),
      ),
    );
  }
}

/// “对比度偏低”的列表（底部面板）。点一条返回那一项的标识（编辑器跳过去）；点“自动调到达标”返回 [kThemeFixContrast]。
const String kThemeFixContrast = '__fix__';

Future<String?> showThemeContrastSheet(BuildContext context, {required List<ContrastIssue> issues, required bool readOnly}) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  builder: (context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x1),
              child: Text('${issues.length} 项对比度偏低', style: t.titleMedium),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x2),
              child: Text('字和它的底颜色太接近，看起来会费劲。只是提醒，不拦着保存。点一条跳到那一项去改。', style: t.bodySmall?.copyWith(color: c.textMuted)),
            ),
            Flexible(
              child: ListView.builder(
                key: const Key('theme-contrast-list'),
                shrinkWrap: true,
                itemCount: issues.length,
                itemBuilder: (context, i) {
                  final issue = issues[i];
                  return ListTile(
                    key: Key('theme-contrast-${issue.id}'),
                    dense: true,
                    leading: Icon(Icons.warning_amber_rounded, size: 18, color: c.warning),
                    title: Text(issue.label, maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text('对比度 ${issue.ratio.toStringAsFixed(2)}:1，至少要 ${formatMetric(issue.min)}:1'),
                    trailing: Icon(Icons.chevron_right, size: 18, color: c.textFaint),
                    onTap: () => Navigator.pop(context, issue.id.split('/').first),
                  );
                },
              ),
            ),
            if (!readOnly)
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.x4, Space.x2, Space.x4, Space.x2),
                child: OutlinedButton.icon(
                  key: const Key('theme-contrast-fix'),
                  onPressed: () => Navigator.pop(context, kThemeFixContrast),
                  icon: const Icon(Icons.auto_fix_high_outlined, size: 18),
                  label: const Text('自动调到达标（只动字的深浅，可以撤销）'),
                ),
              ),
          ],
        ),
      ),
    );
  },
);
