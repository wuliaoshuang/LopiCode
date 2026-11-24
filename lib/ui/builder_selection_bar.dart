// 设计约束（组件选择栏 · 390×844）
// - 一行只显示当前组件和主操作“属性”；移动、复制、删除收进更多菜单。
import 'package:lopicode/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

class BuilderSelectionBar extends StatelessWidget {
  const BuilderSelectionBar({
    super.key,
    required this.icon,
    required this.label,
    required this.isRoot,
    required this.onProperties,
    required this.onUp,
    required this.onDown,
    required this.onCopy,
    required this.onDelete,
  });

  final IconData icon;
  final String label;
  final bool isRoot;
  final VoidCallback onProperties;
  final VoidCallback onUp;
  final VoidCallback onDown;
  final VoidCallback onCopy;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.border)),
      ),
      padding: const EdgeInsets.only(left: Space.x4, right: Space.x2),
      height: 48,
      child: Row(
        children: [
          Icon(icon, size: 18, color: c.accent),
          const SizedBox(width: Space.x2),
          Expanded(
            child: Text(label, style: t.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          if (!isRoot)
            PopupMenuButton<String>(
              tooltip: '编辑组件',
              icon: const Icon(Icons.more_horiz),
              onSelected: (v) {
                if (v == 'up') onUp();
                if (v == 'down') onDown();
                if (v == 'copy') onCopy();
                if (v == 'delete') onDelete();
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'up', child: Text('上移')),
                const PopupMenuItem(value: 'down', child: Text('下移')),
                const PopupMenuItem(value: 'copy', child: Text('复制')),
                PopupMenuItem(
                  value: 'delete',
                  child: Text('删除', style: TextStyle(color: c.danger)),
                ),
              ],
            ),
          const SizedBox(width: Space.x1),
          FilledButton(
            onPressed: onProperties,
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 36),
              padding: const EdgeInsets.symmetric(horizontal: Space.x3),
            ),
            child: const Text('属性'),
          ),
        ],
      ),
    );
  }
}
