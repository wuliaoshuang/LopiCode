// 设计约束（低代码 · 合一面板的“样式”页 · 390×844）
// - 九个分组原样保留：一行可横向滚动的分组标签（改过的带小圆点），下面一次只显示一个分组，每行只做一件事。
// - 最后是“自定义 CSS”小节：面板不认识的条目，每条可删。有才显示。
// - 取用的 tokens：Space.x1–x4、Radii.bubble（标签）、accentSoft / accent（选中的标签）、accentFill（小圆点）。
import 'package:lopicode/lowcode/style_controls_widgets.dart';
import 'package:lopicode/lowcode/style_css_sheet.dart';
import 'package:lopicode/lowcode/style_groups_widgets.dart';
import 'package:lopicode/lowcode/style_model.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';

/// 九个分组的那一行标签。
class StyleTabStrip extends StatelessWidget {
  const StyleTabStrip({super.key, required this.tab, required this.own, required this.onSelect});
  final StyleTab tab;
  final Map<String, String> own;
  final ValueChanged<StyleTab> onSelect;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.symmetric(horizontal: Space.x3, vertical: Space.x1),
    child: Row(children: [for (final t in StyleTab.values) _chip(context, t)]),
  );

  Widget _chip(BuildContext context, StyleTab item) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final on = item == tab;
    return Padding(
      padding: const EdgeInsets.only(right: Space.x1),
      child: Material(
        color: on ? c.accentSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(Radii.bubble),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: Key('lc-tab-${item.name}'),
          onTap: () => onSelect(item),
          child: Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: Space.x3),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  item.label,
                  style: t.bodyMedium?.copyWith(color: on ? c.accent : c.textMuted, fontWeight: on ? FontWeight.w600 : FontWeight.w400, height: 1.2),
                ),
                if (item.touched(own)) ...[
                  const SizedBox(width: Space.x1),
                  Container(
                    key: Key('lc-tab-dot-${item.name}'),
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(color: c.accentFill, shape: BoxShape.circle),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// “样式”页的内容：选中的那个分组 + 自定义 CSS。
class InspectorStylePage extends StatelessWidget {
  const InspectorStylePage({super.key, required this.ed, required this.tab, required this.dropped, required this.onDismissDropped, this.top});
  final StyleEdit ed;

  /// 最上面的一行（“状态”那一行）。
  final Widget? top;
  final StyleTab tab;

  /// 上次“应用 CSS”时没收下的条目。
  final List<String> dropped;
  final VoidCallback onDismissDropped;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final custom = LcStyle(ed.own).custom;
    final mono = t.bodySmall?.copyWith(fontFamily: kMonoFont, fontFamilyFallback: kMonoFallback, color: c.text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ?top,
        if (dropped.isNotEmpty) ...[
          Stack(
            children: [
              InfoBanner(key: const Key('lc-style-dropped'), droppedText(dropped), tone: BannerTone.warning),
              Positioned(
                right: 0,
                top: 0,
                child: StyleIconButton(key: const Key('lc-style-dropped-close'), icon: Icons.close, semantic: '知道了', onTap: onDismissDropped),
              ),
            ],
          ),
          const SizedBox(height: Space.x2),
        ],
        KeyedSubtree(key: ValueKey(tab), child: styleTabBody(tab, ed)),
        if (custom.isNotEmpty) ...[
          const SizedBox(height: Space.x4),
          Divider(height: 1, color: c.border),
          const SizedBox(height: Space.x4),
          Text('自定义 CSS', style: t.labelMedium),
          const SizedBox(height: Space.x1),
          Text('面板不认识的条目，原样留着、照样导出。要改点右上角“CSS”。', style: t.bodySmall?.copyWith(color: c.textFaint)),
          for (final e in custom.entries)
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Row(
                children: [
                  Expanded(
                    child: Text('${e.key}: ${e.value}', key: Key('lc-custom-${e.key}'), style: mono, maxLines: 2, overflow: TextOverflow.ellipsis),
                  ),
                  StyleIconButton(key: Key('lc-custom-del-${e.key}'), icon: Icons.delete_outline, semantic: '删除', onTap: () => ed.apply((s) => s.set(e.key, null))),
                ],
              ),
            ),
        ],
      ],
    );
  }
}
