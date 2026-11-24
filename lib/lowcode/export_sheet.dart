// 占位：导出成 Vue / React 的面板（D 块）。签名是定好的，内容待实现。
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/project_session.dart';
import 'package:material_ui/material_ui.dart';

/// 选一种框架导出，把生成的文件写进项目的 export/ 目录并展示代码。
Future<void> showFrameworkExport(BuildContext context, {required LcDocument doc, required ProjectSession session}) => showModalBottomSheet<void>(
  context: context,
  builder: (_) => const SizedBox(height: 120, child: Center(child: Text('导出 Vue / React（建设中）'))),
);
