// 设计约束（低代码 · 组件栏 · 390×844）
// - 固定在搭建页最底下：一行小字说明 + 一行可横向滑动的组件块。
// - 点一下直接添加，长按拖到画布（拖动中携带的东西是 LcDrag，画布上的插入位认它）。
// - 自定义组件排在内置组件后面，中间一道竖线隔开；图标统一用“组件”图标、名字用强调色，一眼能分清。交互和内置的一样。
import 'package:lopicode/lowcode/component_model.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// 拖动中携带的东西：新组件的类型，或画布上已有组件的 id。
class LcDrag {
  const LcDrag.fresh(String this.type) : nodeId = null, ref = null;
  const LcDrag.move(String this.nodeId) : type = null, ref = null;

  /// 一个自定义组件的新实例。
  const LcDrag.component(String this.ref) : type = 'component', nodeId = null;
  final String? type;
  final String? nodeId;

  /// 自定义组件的 id（只有新实例有）。
  final String? ref;
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
  const PaletteBar({super.key, required this.onTap, required this.onDragging, this.components = const []});

  /// 点了一个组件块。内置组件 [ref] 是 null；自定义组件 type 是 `component`、[ref] 是它的 id。
  final void Function(String type, String? ref) onTap;
  final void Function(bool) onDragging;

  /// 自定义组件，排在内置组件后面。
  final List<LcComponentDef> components;

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
                itemCount: lcPaletteTypes.length + components.length,
                // 内置和自定义之间隔一道竖线。
                separatorBuilder: (_, i) => i == lcPaletteTypes.length - 1
                    ? Padding(
                        padding: const EdgeInsets.symmetric(horizontal: Space.x2, vertical: Space.x2),
                        child: VerticalDivider(width: 1, color: c.border),
                      )
                    : const SizedBox(width: Space.x2),
                itemBuilder: (context, i) {
                  final custom = i < lcPaletteTypes.length ? null : components[i - lcPaletteTypes.length];
                  final type = custom == null ? lcPaletteTypes[i] : 'component';
                  Widget chip({bool lifted = false}) => Container(
                    key: custom == null || lifted ? null : ValueKey('palette-comp-${custom.id}'),
                    width: custom == null ? 60 : 72,
                    padding: const EdgeInsets.symmetric(horizontal: 2),
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
                        Text(
                          custom?.name ?? lcSpecs[type]!.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.labelSmall?.copyWith(color: lifted || custom != null ? c.accent : c.text),
                        ),
                      ],
                    ),
                  );
                  return LongPressDraggable<LcDrag>(
                    data: custom == null ? LcDrag.fresh(type) : LcDrag.component(custom.id),
                    delay: const Duration(milliseconds: 250),
                    onDragStarted: () => onDragging(true),
                    onDragEnd: (_) => onDragging(false),
                    onDraggableCanceled: (_, _) => onDragging(false),
                    feedback: Material(
                      color: Colors.transparent,
                      child: SizedBox(height: 56, child: chip(lifted: true)),
                    ),
                    child: GestureDetector(onTap: () => onTap(type, custom?.id), child: chip()),
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
