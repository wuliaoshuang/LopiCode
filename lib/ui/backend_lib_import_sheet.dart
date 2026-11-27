// 后端积木·导入库之前的预览：把后端这边的预览（[BeLibPreview]）交给公用的预览页（lib/ui/lib_import_sheet.dart）。
// 界面的设计约束写在公用页里。
import 'package:lopicode/backend/backend_lib_pack.dart';
import 'package:lopicode/backend/lib_native_trust.dart';
import 'package:lopicode/lang/lib_model.dart';
import 'package:lopicode/lang/lib_native.dart';
import 'package:lopicode/ui/lib_import_sheet.dart';
import 'package:material_ui/material_ui.dart';

/// 后端这边的预览 → 公用页要的样子。
LibImportView beLibImportView(BeLibPreview p) => LibImportView(
  name: p.name,
  id: p.id,
  version: p.version,
  author: p.author,
  side: p.lib.side.label,
  summary: p.lib.summary,
  needs: p.needs,
  hasSource: p.hasSource,
  nativeFiles: {for (final f in p.nativeFiles) f: p.files[f] ?? ''},
  nativeEnabled: LibNativeTrust.instance.enabled,
  nativeNotes: [
    for (final n in p.lib.natives)
      '手写函数「${n.name}」：${n.waits ? '要等' : '不用等'}；有 ${[for (final l in kLibNativeLangs.keys)
        if (n.files.containsKey(l)) l].join('、')} 的写法',
  ],
  items: p.blocks,
  problems: p.problems,
);

/// 导入前的预览。返回 true＝用户点了“导入”。`existing`＝项目里已经有的同一个标识的库（有就是“盖掉”）。
Future<bool> showBeLibImport(BuildContext context, BeLibPreview preview, {required String file, LibLibrary? existing}) =>
    showLibImport(context, beLibImportView(preview), hint: '来自 $file。导入只是把库的文件放进项目的 blocks/ 里，不会运行它里面的任何东西。', action: existing == null ? '导入' : '导入，盖掉现在的版本 ${existing.version}');
