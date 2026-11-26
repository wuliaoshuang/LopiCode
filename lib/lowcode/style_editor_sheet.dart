// 设计约束（单独弹出来的样式编辑面板；390×844，浅色 + 深色）
// - 就是合一面板（inspector_sheet.dart）直接开在“样式”页，放在一个普通的底部弹层里：遮罩很淡，用户是看着上面的画布调样式的。
// - 搭建页和自定义组件编辑页现在用的是不挡画布的那种（见 editor_workbench_widgets.dart）；这个入口留给别处单独调一个组件的样式。
import 'package:lopicode/lowcode/edit_types.dart';
import 'package:lopicode/lowcode/inspector_sheet.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:material_ui/material_ui.dart';

export 'package:lopicode/lowcode/inspector_sheet.dart' show kStyleCommitDelay;

/// 打开某个节点的样式编辑面板。改动都通过 [onEdit] 交回调用的地方。
Future<void> showStyleEditor(BuildContext context, {required LcDocument doc, required String nodeId, required LcEdit onEdit}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  // 遮罩要淡：用户是看着上面的画布调样式的。
  barrierColor: const Color(0x14000000),
  builder: (_) => InspectorPanel(doc: doc, nodeId: nodeId, onEdit: onEdit, initialPage: InspectorPage.style, modal: true),
);
