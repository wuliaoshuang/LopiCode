// 设计约束（低代码 · 合一面板的头部 · 390×844，浅色 + 深色）
// - 三层：① 组件名一行（右边是次要操作“CSS”“重置”和收起）→ ② 三页的切换（等宽三段）→ ③ “样式”页的分组标签（调用方给）。
// - 取用的 tokens：Space.x2–x4、Radii.sm、surface / surfaceMuted、accent（选中的那一段）、textMuted、border。
import 'package:lopicode/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

enum InspectorPage {
  common('常用'),
  style('样式'),
  events('事件');

  const InspectorPage(this.label);
  final String label;
}

class InspectorHeader extends StatelessWidget {
  const InspectorHeader({
    super.key,
    required this.title,
    required this.modal,
    required this.page,
    required this.pages,
    required this.onPage,
    this.onCss,
    this.onReset,
    required this.onClose,
    this.strip,
  });

  /// 单独弹出来的那种（只为改样式开的）标题带“样式”两个字；搭建页里的合一面板只写名字，页签已经说了是哪一页。
  final String title;
  final bool modal;
  final InspectorPage page;
  final List<InspectorPage> pages;
  final ValueChanged<InspectorPage> onPage;

  /// null＝不显示“CSS”“重置”这两个次要操作。
  final VoidCallback? onCss;
  final VoidCallback? onReset;
  final VoidCallback onClose;

  /// “样式”页的分组标签条。
  final Widget? strip;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final quiet = TextButton.styleFrom(
      foregroundColor: c.textMuted,
      minimumSize: const Size(48, 40),
      padding: const EdgeInsets.symmetric(horizontal: Space.x3),
    );
    return ColoredBox(
      color: c.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!modal)
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: Space.x2),
                width: 36,
                height: 4,
                decoration: BoxDecoration(color: c.border, borderRadius: BorderRadius.circular(2)),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(left: Space.x4, right: Space.x2),
            child: SizedBox(
              height: 44,
              child: Row(
                children: [
                  Expanded(
                    child: Text(title, key: const Key('lc-inspector-title'), style: t.titleLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  if (onCss != null) ...[
                    TextButton(
                      key: const Key('lc-style-css'),
                      onPressed: onCss,
                      style: TextButton.styleFrom(
                        minimumSize: const Size(48, 40),
                        padding: const EdgeInsets.symmetric(horizontal: Space.x3),
                      ),
                      child: const Text('CSS'),
                    ),
                    TextButton(key: const Key('lc-style-reset'), onPressed: onReset, style: quiet, child: const Text('重置')),
                  ],
                  if (!modal) IconButton(key: const Key('lc-inspector-close'), tooltip: '收起', icon: const Icon(Icons.close, size: 20), onPressed: onClose),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x2),
            child: Container(
              decoration: BoxDecoration(color: c.surfaceMuted, borderRadius: BorderRadius.circular(Radii.sm)),
              padding: const EdgeInsets.all(2),
              child: Row(children: [for (final p in pages) Expanded(child: _segment(context, p))]),
            ),
          ),
          ?strip,
          Divider(height: 1, color: c.border),
        ],
      ),
    );
  }

  Widget _segment(BuildContext context, InspectorPage p) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final on = p == page;
    return Material(
      color: on ? c.surface : Colors.transparent,
      borderRadius: BorderRadius.circular(Radii.sm - 2),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: Key('lc-page-${p.name}'),
        onTap: () => onPage(p),
        child: SizedBox(
          height: 36,
          child: Center(
            child: Text(
              p.label,
              style: t.bodyMedium?.copyWith(color: on ? c.accent : c.textMuted, fontWeight: on ? FontWeight.w600 : FontWeight.w400, height: 1.2),
            ),
          ),
        ),
      ),
    );
  }
}
