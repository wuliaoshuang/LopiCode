// 占位：自定义组件面板（E 块）。签名是定好的，内容待实现。
import 'package:lopicode/lowcode/edit_types.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:material_ui/material_ui.dart';

/// 自定义组件：列出已有组件（可插入、改名、改 props、删除），并可把 [selectedNodeId] 那棵子树存成新组件。
/// 返回新插入 / 新变成实例的节点 id（没有就是 null），搭建页拿去选中。
Future<String?> showComponentSheet(BuildContext context, {required LcDocument doc, required LcEdit onEdit, String? selectedNodeId}) => showModalBottomSheet<String>(
  context: context,
  builder: (_) => const SizedBox(height: 120, child: Center(child: Text('自定义组件（建设中）'))),
);
