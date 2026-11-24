// 占位：样式可视化编辑面板（B 块）。签名是定好的，内容待实现。
import 'package:lopicode/lowcode/edit_types.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:material_ui/material_ui.dart';

/// 打开某个节点的样式编辑面板。改动都通过 [onEdit] 交回搭建页。
Future<void> showStyleEditor(BuildContext context, {required LcDocument doc, required String nodeId, required LcEdit onEdit}) => showModalBottomSheet<void>(
  context: context,
  builder: (_) => const SizedBox(height: 120, child: Center(child: Text('样式编辑（建设中）'))),
);
