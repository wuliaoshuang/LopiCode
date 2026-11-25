// 设计约束（低代码搭建页自己的两处小部件 · 390×844）
// - 顶栏右边只有一个“⋮”菜单：不常点的都收在里面，一行一项。
// - 选中条（高 48，外壳在 editor_workbench_widgets.dart）：左边名字，右边 属性（实心）/ 样式（描边）/ 逻辑（文字，有逻辑带小圆点）/
//   “更多操作”（上移、下移、复制、存成组件 或 编辑组件 + 拆开、删除）。页面本身没有“更多操作”。
// - 第 2 期要往选中条加按钮（比如“常用”）：加在 actions 里，“更多操作”始终排最后；一排最多三个带字的按钮加一个“⋯”，
//   再多就收进“⋯”里。
import 'package:lopicode/lowcode/component_ops.dart';
import 'package:lopicode/lowcode/editor_workbench_widgets.dart';
import 'package:lopicode/lowcode/layers_sheet.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/palette_widgets.dart';
import 'package:lopicode/lowcode/props_sheet.dart';
import 'package:material_ui/material_ui.dart';

/// 顶栏“⋮”里的项（value 交给搭建页自己分发）。
class BuilderMoreMenu extends StatelessWidget {
  const BuilderMoreMenu({super.key, required this.onSelected});
  final void Function(String value) onSelected;

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    tooltip: '更多',
    onSelected: onSelected,
    itemBuilder: (_) => const [
      PopupMenuItem(value: 'view', child: Text('屏宽与缩放')),
      PopupMenuItem(value: 'logic', child: Text('积木逻辑')),
      PopupMenuItem(value: 'components', child: Text('自定义组件')),
      PopupMenuItem(value: 'dart', child: Text('导出 Flutter 代码')),
      PopupMenuItem(value: 'framework', child: Text('导出 Vue / React')),
      PopupMenuItem(value: 'title', child: Text('修改页面标题')),
    ],
  );
}

/// 选中了 [node] 时画布下面的那一条。[onAction] 收到：up / down / copy / delete / save / edit / detach。
class BuilderSelectionBar extends StatelessWidget {
  const BuilderSelectionBar({super.key, required this.doc, required this.node, required this.onProps, required this.onStyle, required this.onLogic, required this.onAction});
  final LcDocument doc;
  final LcNode node;
  final VoidCallback onProps;
  final VoidCallback onStyle;
  final VoidCallback onLogic;
  final void Function(String action) onAction;

  @override
  Widget build(BuildContext context) => EditorSelectionBar(
    icon: lcIcon(node.type),
    label: node.type == 'component' ? componentLabel(doc, node) : node.spec.label,
    actions: [
      EditorSelectionBar.primary('属性', onProps),
      EditorSelectionBar.outlined('样式', onStyle),
      EditorSelectionBar.plain('逻辑', onLogic, dot: doc.logic.handlersFor(node.id).isNotEmpty),
      // 页面本身不能移动、复制、删除。
      if (node.type != 'page')
        PopupMenuButton<String>(
          tooltip: '更多操作',
          icon: const Icon(Icons.more_horiz, size: 20),
          onSelected: onAction,
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'up', child: Text('上移')),
            const PopupMenuItem(value: 'down', child: Text('下移')),
            const PopupMenuItem(value: 'copy', child: Text('复制')),
            if (node.type == 'component') ...const [PopupMenuItem(value: 'edit', child: Text('编辑组件')), PopupMenuItem(value: 'detach', child: Text('拆开成普通控件'))] else
              const PopupMenuItem(value: 'save', child: Text('存成组件')),
            const PopupMenuItem(value: 'delete', child: Text('删除')),
          ],
        ),
    ],
  );
}

/// 打开属性面板：改一项就通过 [onEdit] 写回文档里的那个组件。
void showPropertySheet(BuildContext context, {required LcDocument doc, required LcNode node, required void Function(void Function(LcDocument doc) change) onEdit}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    barrierColor: Colors.black26,
    builder: (_) => PropertySheet(
      node: node,
      doc: doc,
      onChanged: (key, value) => onEdit((d) {
        final n = d.find(node.id);
        if (n == null) return;
        if (value == null) {
          n.props.remove(key);
        } else {
          n.props[key] = value;
        }
      }),
    ),
  );
}

/// 打开图层面板；点了哪个组件就返回它的 id（没点就关掉返回 null）。
Future<String?> showLayerSheet(BuildContext context, {required LcDocument doc, required String? selected}) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  builder: (sheetContext) => LayerSheet(doc: doc, selected: selected, onSelect: (id) => Navigator.pop(sheetContext, id)),
);
