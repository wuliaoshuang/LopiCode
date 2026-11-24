// 设计约束（低代码 · 图层面板 · 390×844）
// - 底部面板，一行一个组件：图标 + 类型名 + 一句内容提示；按层级缩进，点一行选中并关闭面板。
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/palette_widgets.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

class LayerSheet extends StatelessWidget {
  const LayerSheet({super.key, required this.doc, required this.selected, required this.onSelect});
  final LcDocument doc;
  final String? selected;
  final void Function(String id) onSelect;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final rows = <(LcNode, int)>[];
    void walk(LcNode n, int depth) {
      rows.add((n, depth));
      for (final child in n.children) {
        walk(child, depth + 1);
      }
    }

    walk(doc.root, 0);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      builder: (context, scroll) => ListView.builder(
        controller: scroll,
        padding: const EdgeInsets.only(bottom: Space.x6),
        itemCount: rows.length + 1,
        itemBuilder: (context, i) {
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x2),
              child: Text('图层 · ${rows.length} 个组件', style: t.titleLarge),
            );
          }
          final (node, depth) = rows[i - 1];
          final active = node.id == selected;
          final hint = node.strProp('text') ?? node.strProp('placeholder') ?? '';
          return InkWell(
            onTap: () => onSelect(node.id),
            child: Container(
              color: active ? c.accentSoft : null,
              padding: EdgeInsets.fromLTRB(Space.x4 + depth * Space.x4, 10, Space.x4, 10),
              child: Row(
                children: [
                  Icon(lcIcon(node.type), size: 18, color: active ? c.accent : c.textFaint),
                  const SizedBox(width: Space.x2),
                  Text(node.spec.label, style: t.titleSmall?.copyWith(color: active ? c.accent : c.text)),
                  const SizedBox(width: Space.x2),
                  Expanded(
                    child: Text(hint, style: t.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
