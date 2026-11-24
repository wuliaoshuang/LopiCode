// 设计约束（低代码 · 组件栏 · 390×844）
// - 固定在搭建页最底下：一行小字说明 + 一行可横向滑动的组件块。
// - 点一下直接添加，长按拖到画布（拖动中携带的东西是 LcDrag，画布上的插入位认它）。
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// 拖动中携带的东西：新组件的类型，或画布上已有组件的 id。
class LcDrag {
  const LcDrag.fresh(String this.type) : nodeId = null;
  const LcDrag.move(String this.nodeId) : type = null;
  final String? type;
  final String? nodeId;
}

IconData lcIcon(String type) => switch (type) {
  'page' => Icons.phone_android,
  'container' => Icons.crop_square,
  'row' => Icons.view_column_outlined,
  'column' => Icons.table_rows_outlined,
  'card' => Icons.featured_play_list_outlined,
  'text' => Icons.title,
  'button' => Icons.smart_button_outlined,
  'image' => Icons.image_outlined,
  'input' => Icons.text_fields,
  'list' => Icons.format_list_bulleted,
  'divider' => Icons.horizontal_rule,
  'spacer' => Icons.expand,
  _ => Icons.widgets_outlined,
};

class PaletteBar extends StatelessWidget {
  const PaletteBar({super.key, required this.onTap, required this.onDragging});
  final void Function(String type) onTap;
  final void Function(bool) onDragging;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.border)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.x4, Space.x2, Space.x4, Space.x1),
              child: Text('组件 · 点一下添加，长按拖到画布', style: t.labelSmall),
            ),
            SizedBox(
              height: 64,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x2),
                itemCount: lcPaletteTypes.length,
                separatorBuilder: (_, _) => const SizedBox(width: Space.x2),
                itemBuilder: (context, i) {
                  final type = lcPaletteTypes[i];
                  Widget chip({bool lifted = false}) => Container(
                    width: 60,
                    decoration: BoxDecoration(
                      color: lifted ? c.accentSoft : c.bg,
                      borderRadius: BorderRadius.circular(Radii.md),
                      border: Border.all(color: lifted ? c.accentFill : c.border),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(lcIcon(type), size: 20, color: lifted ? c.accent : c.textMuted),
                        const SizedBox(height: 2),
                        Text(lcSpecs[type]!.label, style: t.labelSmall?.copyWith(color: lifted ? c.accent : c.text)),
                      ],
                    ),
                  );
                  return LongPressDraggable<LcDrag>(
                    data: LcDrag.fresh(type),
                    delay: const Duration(milliseconds: 250),
                    onDragStarted: () => onDragging(true),
                    onDragEnd: (_) => onDragging(false),
                    onDraggableCanceled: (_, _) => onDragging(false),
                    feedback: Material(
                      color: Colors.transparent,
                      child: SizedBox(height: 56, child: chip(lifted: true)),
                    ),
                    child: GestureDetector(onTap: () => onTap(type), child: chip()),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
