// 设计约束（低代码搭建页自己的两处小部件 · 390×844）
// - 顶栏右边只有一个“⋮”菜单：不常点的都收在里面，一行一项。
// - 选中条（高 48，外壳在 editor_selection_bar_widgets.dart）：左边“选上一层”＋名字，右边 常用（实心，唯一主操作）/
//   样式（描边）/ 逻辑（文字，有逻辑带小圆点）/“更多操作”。三个带字的按钮打开的是同一张合一面板的三页。
// - “更多操作”和长按菜单是同一份（lcNodeMenuItems）：复制、粘贴到它后面（剪贴板里有东西才亮）、重复一份 ｜ 包成容器、
//   存成组件（实例是 编辑组件 + 拆开）｜ 删除（红字，最后）。“更多操作”里多“上移 / 下移”。
//   页面本身不能移动、复制、删除：只有剪贴板里有东西时才有“更多操作”，里面只有“粘贴到页面里”。
import 'package:lopicode/lowcode/component_ops.dart';
import 'package:lopicode/lowcode/editor_clipboard.dart';
import 'package:lopicode/lowcode/editor_workbench_widgets.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/palette_widgets.dart';
import 'package:lopicode/theme/tokens.dart';
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

/// 一个组件能做的事（长按菜单和选中条的“更多操作”共用一份）。
///
/// 选了哪项，value 是：clip 复制 / paste 粘贴到它后面 / dup 重复一份 / wrap 包成容器 / save 存成组件 /
/// edit 编辑组件 / detach 拆开 / up 上移 / down 下移 / delete 删除 / pasteInto 粘贴到页面里。
///
/// [withMove]：带不带“上移 / 下移”。[componentActions]：带不带和自定义组件有关的三项（组件编辑页里没有）。
/// [fixed]：这个组件不能移动、复制、删除（页面本身、组件的最外层）——只剩“粘贴到里面”。
List<PopupMenuEntry<String>> lcNodeMenuItems(BuildContext context, LcNode node, {bool withMove = false, bool componentActions = true, bool fixed = false}) {
  final canPaste = lcClipboardHasContent && (componentActions || !lcClipboardHasInstances);
  if (fixed) return [PopupMenuItem(value: 'pasteInto', enabled: canPaste, child: Text(node.type == 'page' ? '粘贴到页面里' : '粘贴到里面'))];
  return [
    const PopupMenuItem(value: 'clip', child: Text('复制')),
    PopupMenuItem(value: 'paste', enabled: canPaste, child: const Text('粘贴到它后面')),
    const PopupMenuItem(value: 'dup', child: Text('重复一份')),
    const PopupMenuDivider(),
    const PopupMenuItem(value: 'wrap', child: Text('包成容器')),
    if (componentActions && node.type == 'component') ...const [PopupMenuItem(value: 'edit', child: Text('编辑组件')), PopupMenuItem(value: 'detach', child: Text('拆开成普通控件'))] else if (componentActions)
      const PopupMenuItem(value: 'save', child: Text('存成组件')),
    if (withMove) ...const [PopupMenuDivider(), PopupMenuItem(value: 'up', child: Text('上移')), PopupMenuItem(value: 'down', child: Text('下移'))],
    const PopupMenuDivider(),
    PopupMenuItem(
      value: 'delete',
      child: Text('删除', style: TextStyle(color: context.colors.danger)),
    ),
  ];
}

/// 在 [at]（屏幕坐标）弹出一个组件的长按菜单；选了哪项返回它的 value。
Future<String?> showLcNodeMenu(BuildContext context, Offset at, LcNode node, {bool componentActions = true, bool fixed = false}) {
  final size = MediaQuery.sizeOf(context);
  return showMenu<String>(
    context: context,
    position: RelativeRect.fromLTRB(at.dx, at.dy, size.width - at.dx, size.height - at.dy),
    items: lcNodeMenuItems(context, node, componentActions: componentActions, fixed: fixed),
  );
}

/// 选中条上的“更多操作”。
class LcNodeMoreButton extends StatelessWidget {
  const LcNodeMoreButton({super.key, required this.node, required this.onAction, this.componentActions = true, this.fixed = false});
  final LcNode node;
  final void Function(String action) onAction;
  final bool componentActions;
  final bool fixed;

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    tooltip: '更多操作',
    icon: const Icon(Icons.more_horiz, size: 20),
    onSelected: onAction,
    itemBuilder: (context) => lcNodeMenuItems(context, node, withMove: true, componentActions: componentActions, fixed: fixed),
  );
}

/// 选中了 [node] 时画布下面的那一条。[onAction] 收到的值见 [lcNodeMenuItems]。
class BuilderSelectionBar extends StatelessWidget {
  const BuilderSelectionBar({super.key, required this.doc, required this.node, required this.onCommon, required this.onStyle, required this.onLogic, required this.onAction, this.onParent});
  final LcDocument doc;
  final LcNode node;
  final VoidCallback onCommon;
  final VoidCallback onStyle;
  final VoidCallback onLogic;
  final void Function(String action) onAction;
  final VoidCallback? onParent;

  @override
  Widget build(BuildContext context) => EditorSelectionBar(
    icon: lcIcon(node.type),
    label: node.type == 'component' ? componentLabel(doc, node) : node.spec.label,
    onParent: node.type == 'page' ? null : onParent,
    actions: [
      EditorSelectionBar.primary('常用', onCommon),
      EditorSelectionBar.outlined('样式', onStyle),
      EditorSelectionBar.plain('逻辑', onLogic, dot: doc.logic.handlersFor(node.id).isNotEmpty),
      // 页面本身不能移动、复制、删除：剪贴板里有东西时才有“更多操作”（粘贴到页面里）。
      if (node.type != 'page') LcNodeMoreButton(node: node, onAction: onAction) else if (lcClipboardHasContent) LcNodeMoreButton(node: node, onAction: onAction, fixed: true),
    ],
  );
}
