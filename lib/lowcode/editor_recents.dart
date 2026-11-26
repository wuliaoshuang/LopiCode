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
Future<Map<String, dynamic>> _read(PathGuard guard) async {
  final Object? raw;
  try {
    raw = await readJsonFile(_file(guard));
  } on PathGuardException {
    return {};
  }
  return raw is Map
      ? {
          for (final e in raw.entries)
            if (e.key is String) e.key as String: e.value,
        }
      : {};
}

List<String> _strings(Object? list) => [
  if (list is List)
    for (final v in list)
      if (v is String && v.isNotEmpty) v,
];

/// 同一个文件的“读出来 → 改一项 → 写回去”排队做，免得两处同时改把对方那一项盖掉。
final Map<String, Future<void>> _updates = {};

Future<void> _update(PathGuard guard, String key, Object? value) {
  final path = _file(guard).path;
  final next = (_updates[path] ?? Future<void>.value()).catchError((Object _) {}).then((_) async {
    final all = await _read(guard);
    all[key] = value;
    await writeJsonAtomic(_file(guard), all);
  });
  _updates[path] = next;
  return next;
}

Future<List<String>> loadPaletteRecent(PathGuard guard) async => _strings((await _read(guard))['recent']);

Future<void> savePaletteRecent(PathGuard guard, List<String> keys) => _update(guard, 'recent', keys.take(kPaletteRecentMax).toList());

/// 图层面板里折起来的那些组件（编号）。只是编辑器自己的记性，不进页面文件。
Future<Set<String>> loadLayersCollapsed(PathGuard guard) async => _strings((await _read(guard))['layersCollapsed']).toSet();

Future<void> saveLayersCollapsed(PathGuard guard, Set<String> ids) => _update(guard, 'layersCollapsed', ids.toList()..sort());
