/// 用户主题的存盘：应用数据目录下 `themes/`，每套一个 `<标识>.json`（格式同导出文件，不带背景图）。
///
/// 这里只管读写文件；“能不能删、名字重不重、上限多少”这些规矩在状态层（lib/state/themes_state.dart）。
library;

import 'dart:io';

import 'package:lopicode/appearance/theme_json.dart';
import 'package:lopicode/appearance/theme_spec.dart';
import 'package:lopicode/core/safe_file.dart';

/// 用户主题最多多少套。
const int kMaxUserThemes = 50;

class ThemeStore {
  ThemeStore(this.dir);

  final Directory dir;
  final Map<String, ThemeSpec> _user = {};

  /// 读过盘没有（没读过时 [user] 是空的，界面先用默认主题）。
  bool get loaded => _loaded;
  bool _loaded = false;

  /// 用户主题，按标识排（标识里带创建时间，所以就是创建的先后）。
  List<ThemeSpec> get user => List.unmodifiable(_user.values.toList()..sort((a, b) => a.id.compareTo(b.id)));

  ThemeSpec? byId(String id) => _user[id];

  File _fileOf(String id) => File('${dir.path}${Platform.pathSeparator}$id.json');

  /// 把目录里的主题都读进来。坏文件跳过（原件由 readJsonFile 另存成 .bad-时间戳），不抛异常。
  Future<void> load() async {
    _user.clear();
    _loaded = true;
    if (!await dir.exists()) return;
    final List<FileSystemEntity> entries;
    try {
      entries = await dir.list().toList();
    } on FileSystemException {
      // 目录读不了就当作没有用户主题：应用照常用默认主题起来。
      return;
    }
    for (final e in entries) {
      if (e is! File || !e.path.endsWith('.json')) continue;
      final id = e.uri.pathSegments.last.replaceFirst(RegExp(r'\.json$'), '');
      if (!isValidThemeId(id) || _user.length >= kMaxUserThemes) continue;
      final json = await readJsonFile(e, accept: (d) => decodeThemeJson(d).ok, label: '主题 $id');
      if (json == null) continue;
      final theme = decodeThemeJson(json).theme;
      // 以文件名为准：文件里写的标识对不上也用文件名，免得两个文件顶着同一个标识。
      if (theme != null) _user[id] = theme.copyWith(id: id, builtin: false);
    }
  }

  /// 写一套主题（新建或覆盖）。
  Future<void> save(ThemeSpec theme) async {
    if (!isValidThemeId(theme.id)) throw ArgumentError('主题标识不合法：${theme.id}');
    final spec = theme.copyWith(builtin: false);
    await dir.create(recursive: true);
    await writeJsonAtomic(_fileOf(spec.id), encodeTheme(spec));
    _user[spec.id] = spec;
  }

  Future<void> delete(String id) async {
    _user.remove(id);
    if (!isValidThemeId(id)) return;
    final f = _fileOf(id);
    if (await f.exists()) await f.delete();
  }
}
