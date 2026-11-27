/// 组件库在项目里怎么放（第四轮 B2；和积木库 backend_lib_store.dart 是并列的一套，登记表各用各的）：
/// - 每个库一个文件夹：`components/作者段/库名/`，里面是 `lib.json`、`components.json`、`images.json`（见 comp_lib.dart）；
/// - `components/libs.json` 记项目里有哪些组件库（标识、版本、从哪来的、内容的校验值）；
/// - 导出：打成 `exports/组件库-名字-版本.lopilib`；导入：先读出来给人看（[compLibOpenPack]），点了头再落盘（[compLibStore]）。
///
/// 所有路径都过 [PathGuard]；不联网；不执行库里的任何东西。读到坏文件不抛异常。
library;

import 'dart:convert';
import 'dart:io';

import 'package:lopicode/backend/backend_lib_pack.dart';
import 'package:lopicode/core/path_guard.dart';
import 'package:lopicode/core/safe_file.dart';
import 'package:lopicode/lowcode/comp_lib.dart';

const String kCompLibsDir = 'components';
const String kCompLibsIndexFile = 'components/libs.json';

/// 一个项目里最多放几个组件库（自定的数，和积木库一样）。
const int kCompMaxProjectLibs = 64;

const List<String> _libFiles = [kCompLibManifest, kCompLibDefsFile, kCompLibImagesFile];

/// 项目里的一个组件库。
class CompStoredLib {
  const CompStoredLib(this.id, this.files, this.lib, {this.from = 'project'});
  final String id;
  final Map<String, String> files;
  final CompLib lib;

  /// 从哪来的：`project`＝在这个项目里存的；`file`＝从文件导入的。
  final String from;

  bool get ok => lib.ok && lib.id == id;
  String get name => lib.name.isEmpty ? id : lib.name;
  String? get problem => lib.id != id && lib.problems.isEmpty ? '文件夹是 $id，清单里写的却是 ${lib.id}' : lib.problems.firstOrNull;
  String get sum => compLibSum(files);
}

Future<Map<String, String>> _readFolder(Directory dir) async {
  final out = <String, String>{};
  for (final name in _libFiles) {
    final f = File('${dir.path}/$name');
    try {
      if (!await f.exists() || await f.length() > kBeLibMaxFileBytes) continue;
      out[name] = await f.readAsString();
    } on FileSystemException {
      continue; // 读不了当没有：少了要紧的文件读的时候会说
    } on FormatException {
      continue;
    }
  }
  return out;
}

Future<Map<String, String>> _fromIndex(PathGuard guard) async {
  final json = await readJsonFile(File(guard.resolve(kCompLibsIndexFile)), accept: (j) => j is Map, label: '项目的组件库清单');
  final libs = json is Map ? json['libs'] : null;
  return {
    if (libs is List)
      for (final l in libs)
        if (l is Map && l['id'] is String && l['from'] is String) l['id'] as String: l['from'] as String,
  };
}

String _last(Directory d) => d.uri.pathSegments.where((s) => s.isNotEmpty).last;

/// 项目里的全部组件库（按标识排好）。坏的也列出来（[CompStoredLib.ok] 是 false）。
Future<List<CompStoredLib>> compLibsRead(PathGuard guard) async {
  final out = <CompStoredLib>[];
  try {
    final root = Directory(guard.resolve(kCompLibsDir));
    if (!await root.exists()) return out;
    final from = await _fromIndex(guard);
    await for (final a in root.list(followLinks: false)) {
      if (a is! Directory) continue;
      await for (final l in a.list(followLinks: false)) {
        if (l is! Directory || out.length >= kCompMaxProjectLibs) continue;
        final id = '${_last(a)}/${_last(l)}';
        if (!kCompLibId.hasMatch(id)) continue;
        final files = await _readFolder(l);
        if (!files.containsKey(kCompLibManifest)) continue;
        out.add(CompStoredLib(id, files, compLibRead(files), from: from[id] ?? 'project'));
      }
    }
  } on FileSystemException {
    return out;
  } on PathGuardException {
    return out;
  }
  out.sort((a, b) => a.id.compareTo(b.id));
  return out;
}

/// 把一个库写进它的文件夹，再更新登记表。写不成返回原因。
Future<String?> compLibStore(PathGuard guard, CompLib lib, {String from = 'project'}) async {
  if (!lib.ok) return lib.problems.first;
  final files = compLibFiles(lib);
  try {
    final have = await compLibsRead(guard);
    if (!have.any((s) => s.id == lib.id) && have.length >= kCompMaxProjectLibs) return '一个项目最多放 $kCompMaxProjectLibs 个组件库';
    final known = await _fromIndex(guard);
    final dir = Directory(guard.resolve('$kCompLibsDir/${lib.id}'));
    await dir.create(recursive: true);
    for (final name in _libFiles) {
      final f = File(guard.resolve('$kCompLibsDir/${lib.id}/$name'));
      final text = files[name];
      if (text == null) {
        if (await f.exists()) await f.delete();
      } else {
        await writeStringAtomic(f, text);
      }
    }
    final all = await compLibsRead(guard);
    await writeJsonAtomic(File(guard.resolve(kCompLibsIndexFile)), {
      'format': 1,
      'libs': [
        for (final s in all) {'id': s.id, 'version': s.lib.version, 'from': s.id == lib.id ? from : (known[s.id] ?? s.from), 'sum': s.sum},
      ],
    });
    return null;
  } on FileSystemException catch (e) {
    return '没写成：${e.message}';
  } on PathGuardException {
    return '这个位置不在项目里，没有写';
  }
}

/// 把一个库从项目里拿掉（整个文件夹）。
Future<void> compLibDelete(PathGuard guard, String id) async {
  if (!kCompLibId.hasMatch(id)) return;
  try {
    final dir = Directory(guard.resolve('$kCompLibsDir/$id'));
    if (await dir.exists()) await dir.delete(recursive: true);
    final all = await compLibsRead(guard);
    final known = await _fromIndex(guard);
    final file = File(guard.resolve(kCompLibsIndexFile));
    if (all.isEmpty && !await file.exists()) return;
    await writeJsonAtomic(file, {
      'format': 1,
      'libs': [
        for (final s in all) {'id': s.id, 'version': s.lib.version, 'from': known[s.id] ?? s.from, 'sum': s.sum},
      ],
    });
  } on FileSystemException {
    return;
  } on PathGuardException {
    return;
  }
}

String _fileSafe(String s) => s.replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '-');

/// 导出：返回写到了哪（相对路径）；不成返回原因。
Future<({String? rel, String? problem})> compLibExport(PathGuard guard, CompStoredLib lib) async {
  if (!lib.ok) return (rel: null, problem: lib.problem ?? '这个库有问题，导不出来');
  final rel = 'exports/组件库-${_fileSafe(lib.name)}-${lib.lib.version}$kBeLibFileSuffix';
  try {
    final f = File(guard.resolve(rel));
    await f.parent.create(recursive: true);
    final bytes = beLibPack(lib.files);
    if (bytes.length > kBeLibMaxPackBytes) return (rel: null, problem: '这个库打包以后超过 8MB 了，导不出来（图片太多的话先删掉几张）');
    await writeFileAtomic(f, bytes);
    return (rel: rel, problem: null);
  } on FileSystemException catch (e) {
    return (rel: null, problem: '没写成：${e.message}');
  } on PathGuardException {
    return (rel: null, problem: '这个位置不在项目里，没有写');
  }
}

/// 项目里能导入的文件：根目录和 `exports/` 里的 `.lopilib`（相对路径，排好）。
Future<List<String>> compLibPackFiles(PathGuard guard) async {
  final out = <String>[];
  for (final dir in const ['', 'exports']) {
    try {
      final d = Directory(guard.resolve(dir.isEmpty ? '.' : dir));
      if (!await d.exists()) continue;
      await for (final e in d.list(followLinks: false)) {
        if (e is File && e.path.endsWith(kBeLibFileSuffix)) out.add('${dir.isEmpty ? '' : '$dir/'}${e.uri.pathSegments.last}');
      }
    } on FileSystemException {
      continue;
    } on PathGuardException {
      continue;
    }
  }
  out.sort();
  return out;
}

/// 打开一个导出文件看看里面是什么（不落盘）。任何输入都不抛异常；打不开、有问题都写在 [CompLib.problems] 里。
/// [installed]：项目里已经有的库——同一个标识、同一个版本、内容却不一样的不让导入。
Future<({CompLib lib, Map<String, String> files})> compLibOpenPack(PathGuard guard, String rel, {List<CompStoredLib> installed = const []}) async {
  CompLib bad(String why) => CompLib(id: '', name: rel.split('/').last, version: '', problems: [why]);
  try {
    final f = File(guard.resolve(rel));
    if (!await f.exists()) return (lib: bad('找不到这个文件'), files: const <String, String>{});
    if (await f.length() > kBeLibMaxPackBytes) return (lib: bad('这个文件太大了（超过 8MB），不像是一个库'), files: const <String, String>{});
    final un = beLibUnpack(await f.readAsBytes());
    final files = un.files;
    if (files == null) return (lib: bad(un.problem ?? '这个文件打不开'), files: const <String, String>{});
    final mine = {
      for (final name in _libFiles)
        if (files[name] != null) name: files[name]!,
      for (final e in files.entries)
        if (e.key.startsWith('native/')) e.key: e.value,
    };
    final lib = compLibRead(mine);
    for (final s in installed) {
      if (s.id == lib.id && s.lib.version == lib.version && s.sum != compLibSum(compLibFiles(lib)) && lib.ok) {
        lib.problems.add('项目里已经有一个标识和版本都一样（${lib.id} ${lib.version}）、内容却不一样的库。请让对方改了版本号再导出，或者先把项目里那个删掉');
      }
    }
    return (lib: lib, files: mine);
  } on FileSystemException catch (e) {
    return (lib: bad('读不了：${e.message}'), files: const <String, String>{});
  } on PathGuardException {
    return (lib: bad('这个位置不在项目里'), files: const <String, String>{});
  }
}

/// 把库带的图片写进项目（已经有同名文件的不动）。返回写了几张。
Future<int> compLibWriteImages(PathGuard guard, CompLib lib) async {
  var n = 0;
  for (final e in lib.images.entries) {
    try {
      final f = File(guard.resolve(e.key));
      if (await f.exists()) continue;
      await f.parent.create(recursive: true);
      await writeFileAtomic(f, base64Decode(e.value));
      n++;
    } on FileSystemException {
      continue;
    } on PathGuardException {
      continue;
    } on FormatException {
      continue; // 不是合法的 base64：这张不要
    }
  }
  return n;
}

/// 读项目里的一张图片（收库的时候用）；读不到、太大返回 null。
List<int>? compLibReadImage(PathGuard guard, String rel) {
  try {
    final f = File(guard.resolve(rel));
    if (!f.existsSync() || f.lengthSync() > kCompLibMaxImageBytes) return null;
    return f.readAsBytesSync();
  } on FileSystemException {
    return null;
  } on PathGuardException {
    return null;
  }
}
