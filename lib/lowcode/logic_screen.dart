// 占位：积木逻辑编辑页（C 块界面）。签名是定好的，内容待实现。
import 'package:lopicode/lowcode/edit_types.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:material_ui/material_ui.dart';

/// 整页的积木逻辑编辑器。[doc] 是搭建页手里那份活的文档；[initialNodeId] 不为空时先看这个组件的事件。
class LogicScreen extends StatelessWidget {
  const LogicScreen({super.key, required this.doc, required this.onEdit, this.initialNodeId});
  final LcDocument doc;
  final LcEdit onEdit;
  final String? initialNodeId;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('积木逻辑')),
    body: const Center(child: Text('积木逻辑（建设中）')),
  );
}
