/// 组件盒“常用”的存盘：最近用过哪些组件，每个项目各记各的。
///
/// - 存在项目的内部目录里：`.lopicode/lowcode-editor.json`，内容 `{"recent": ["text", "component:c1", …]}`。
///   **不进页面文件**（page.lc.json 的格式一个字都不动），也不进导出的网页。
/// - 读：文件没有、坏了、形状不对都当“没用过”，不报错（坏文件由 readJsonFile 另存一份备份）。
/// - 写：原子写；写不进去只是下次打开不记得，不打扰用户（由调用方记错误日志）。
library;

import 'dart:io';

import 'package:lopicode/core/path_guard.dart';
import 'package:lopicode/core/safe_file.dart';
import 'package:lopicode/lowcode/palette_catalog.dart';

/// 相对项目目录的路径。
const String kLowcodeEditorStateFile = '${PathGuard.reservedDir}/lowcode-editor.json';

File _file(PathGuard guard) => File(guard.resolve(kLowcodeEditorStateFile, allowReserved: true));

/// 读“最近用过”。读不到一律返回空表。
Future<List<String>> loadPaletteRecent(PathGuard guard) async {
  final Object? raw;
  try {
    raw = await readJsonFile(_file(guard));
  } on PathGuardException {
    return const [];
  }
  if (raw is! Map) return const [];
  final list = raw['recent'];
  if (list is! List) return const [];
  return [
    for (final v in list)
      if (v is String && v.isNotEmpty) v,
  ].take(kPaletteRecentMax).toList();
}

/// 存“最近用过”。
Future<void> savePaletteRecent(PathGuard guard, List<String> keys) => writeJsonAtomic(_file(guard), {'recent': keys.take(kPaletteRecentMax).toList()});
