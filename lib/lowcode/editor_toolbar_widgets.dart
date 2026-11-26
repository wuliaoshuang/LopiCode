// 设计约束（低代码 · 搭建台最底下那一条 · 390×844）——从 editor_workbench_widgets.dart 拆出来的
// - 工具条（56 高，拇指够得着）：[＋添加]（实心，主操作）在左；右边一排图标 [外面加的][图层][撤销][重做][预览]。一行只做这一件事。
// - 拖动时工具条换成“拖到这里删除”（从组件盒拖出来的新组件是“拖到这里取消”），手指进去变红。
// - 取用的 tokens：Space.x1/x2/x3/x4、surface / surfaceMuted / border、danger / dangerSoft、textMuted。
import 'package:flutter/foundation.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// 工具条多高。
const double kEditorToolbarHeight = 56;

class EditorToolbar extends StatelessWidget {
  const EditorToolbar({super.key, required this.adding, required this.onAdd, required this.onLayers, required this.onUndo, required this.onRedo, this.onPreview, this.extra = const []});

  /// 组件盒是不是展开着（“添加”上的图标跟着变）。
  final bool adding;
  final VoidCallback onAdd;
  final VoidCallback onLayers;
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;
  final VoidCallback? onPreview;
  final List<Widget> extra;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget icon(String tip, IconData data, VoidCallback? onPressed) =>
        IconButton(tooltip: tip, icon: Icon(data), onPressed: onPressed, constraints: const BoxConstraints.tightFor(width: 48, height: 48));
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.border)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          key: const ValueKey('lc-toolbar'),
          height: kEditorToolbarHeight,
          child: Padding(
            padding: const EdgeInsets.only(left: Space.x3, right: Space.x1),
            child: Row(
              children: [
                FilledButton.icon(
                  key: const ValueKey('lc-tool-add'),
                  onPressed: onAdd,
                  icon: Icon(adding ? Icons.keyboard_arrow_down : Icons.add, size: 20),
                  label: const Text('添加'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 40),
                    padding: const EdgeInsets.symmetric(horizontal: Space.x4),
                  ),
                ),
                const Spacer(),
                ...extra,
                icon('图层', Icons.layers_outlined, onLayers),
                icon('撤销', Icons.undo, onUndo),
                icon('重做', Icons.redo, onRedo),
                if (onPreview != null) icon('预览', Icons.play_arrow_outlined, onPreview),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class EditorDropZone extends StatelessWidget {
  const EditorDropZone({super.key, required this.over, required this.moving, required this.deletable});

  /// 手指在不在这一条上。
  final ValueListenable<bool> over;

  /// 拖的是画布上已有的组件（不是组件盒里新拖出来的）。
  final bool moving;
  final bool deletable;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final label = !moving ? '拖到这里取消' : (deletable ? '拖到这里删除' : '这个不能删 · 拖到这里放回去');
    return ValueListenableBuilder<bool>(
      valueListenable: over,
      builder: (context, over, _) {
        final hot = over && deletable;
        final fg = hot ? c.danger : c.textMuted;
        return DecoratedBox(
          decoration: BoxDecoration(
            color: hot ? c.dangerSoft : (over ? c.surfaceMuted : c.surface),
            border: Border(
              top: BorderSide(color: hot ? c.danger : c.border, width: hot ? 2 : 1),
            ),
          ),
          child: SafeArea(
            top: false,
            child: SizedBox(
              key: const ValueKey('lc-drop-zone'),
              height: kEditorToolbarHeight,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(deletable ? Icons.delete_outline : Icons.close, size: 20, color: fg),
                  const SizedBox(width: Space.x2),
                  Text(label, style: t.labelLarge?.copyWith(color: fg)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
