/// 库在项目里怎么放（积木第 5 版·库 2）：
/// - 每个库一个文件夹：`blocks/作者段/库名/`，里面是清单 `lib.json`、`modules/` 里的模块、`source/backend.lc.json`（画布原件，
///   有它才能回到画布上接着改）；
/// - `blocks/libs.json` 记项目里有哪些库（标识、版本、从哪来的、内容的校验值）；
/// - 导出：把文件夹打成 `exports/库-名字-版本.lopilib`；导入：先出预览（[beLibOpenPack]），用户点了头再落盘（[beLibInstall]）；
/// - “复制一份来改”（[beLibFork]）：换一个标识另存一份，和原来的断开，清单里记一笔是从谁复制的；
/// - 库改了以后（存盘、导入盖掉旧的）把用它的文档重查一遍，新冒出来的问题交回去给界面说（[BeLibSaved.fresh]）。
///
/// 所有路径都过 [PathGuard]；不联网；不执行库里的任何东西。读到坏文件不抛异常。
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:lopicode/backend/backend_lib_build.dart';
import 'package:lopicode/backend/backend_lib_doc.dart';
import 'package:lopicode/backend/backend_lib_pack.dart';
import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/backend/backend_validate.dart';
import 'package:lopicode/backend/lib_native_trust.dart';
import 'package:lopicode/core/path_guard.dart';
import 'package:lopicode/core/safe_file.dart';
import 'package:lopicode/lang/lib_model.dart';
import 'package:lopicode/lang/rules.dart';
import 'package:lopicode/lowcode/lib_blocks.dart';

const String kBeLibsDir = 'blocks';
const String kBeLibsIndexFile = 'blocks/libs.json';

/// 一个项目里最多放几个库（自定的数）。
const int kBeMaxProjectLibs = 64;

/// 项目里的一个库。
class BeStoredLib {
  const BeStoredLib(this.id, this.files, this.lib, {this.from = 'project'});

  /// 文件夹说的标识（`作者段/库名`）。
  final String id;
  final Map<String, String> files;
  final LibLibrary lib;

  /// 从哪来的：`project`＝在这个项目里新建的；`file`＝从文件导入的；`copy`＝复制来改的。
  final String from;

  String get dir => '$kBeLibsDir/$id';
  String get sourceRel => '$dir/$kBeLibSourceFile';
  bool get hasSource => files.containsKey(kBeLibSourceFile);

  /// 文件夹名和清单里写的标识对不上：不认。
  bool get ok => lib.ok && lib.id == id;
  String get name => lib.name.isEmpty ? id : lib.name;
  String? get problem => lib.id != id && lib.problems.isEmpty ? '文件夹是 $id，清单里写的却是 ${lib.id}' : lib.problems.firstOrNull;
}

bool _keep(String rel) => rel == kLibManifestFile || rel.startsWith('modules/') || rel.startsWith('native/') || rel == kBeLibSourceFile || (!rel.contains('/') && rel.endsWith('.json'));

bool _safeRel(String rel) => rel.isNotEmpty && !rel.startsWith('/') && !rel.contains('\\') && !rel.contains(':') && rel.split('/').every((s) => s.isNotEmpty && s != '.' && s != '..');

String beLibSum(Map<String, String> files) {
  final keys = files.keys.where((k) => k != kBeLibSourceFile).toList()..sort();
  return sha256.convert(utf8.encode([for (final k in keys) '$k\u0000${files[k]}\u0000'].join())).toString();
}

Future<Map<String, String>> _readFolder(Directory dir) async {
  final out = <String, String>{};
  var count = 0;
  await for (final e in dir.list(recursive: true, followLinks: false)) {
    if (e is! File) continue;
    if (++count > kBeLibMaxPackFiles) break;
    final rel = e.path.substring(dir.path.length + 1).replaceAll('\\', '/');
    if (!_keep(rel) || !_safeRel(rel)) continue;
    try {
      if (await e.length() > kBeLibMaxFileBytes) continue;
      out[rel] = await e.readAsString();
    } on FileSystemException {
      continue; // 读不了的文件当没有：少了要紧的文件读入器会说
    } on FormatException {
      continue; // 不是文字
    }
  }
  return out;
}

Future<Map<String, String>> _fromIndex(PathGuard guard) async {
  final json = await readJsonFile(File(guard.resolve(kBeLibsIndexFile)), accept: (j) => j is Map, label: '项目的库清单');
  final libs = json is Map ? json['libs'] : null;
  return {
    if (libs is List)
      for (final l in libs)
        if (l is Map && l['id'] is String && l['from'] is String) l['id'] as String: l['from'] as String,
  };
}

/// 项目里的全部库（按标识排好）。坏的也列出来（[BeStoredLib.ok] 是 false）。
Future<List<BeStoredLib>> beLibsRead(PathGuard guard) async {
  final out = <BeStoredLib>[];
  try {
    final root = Directory(guard.resolve(kBeLibsDir));
    if (!await root.exists()) return out;
    final from = await _fromIndex(guard);
    await for (final a in root.list(followLinks: false)) {
      if (a is! Directory) continue;
      await for (final l in a.list(followLinks: false)) {
        if (l is! Directory || out.length >= kBeMaxProjectLibs) continue;
        final id = '${a.uri.pathSegments.where((s) => s.isNotEmpty).last}/${l.uri.pathSegments.where((s) => s.isNotEmpty).last}';
        if (!kLibIdPattern.hasMatch(id)) continue;
        final files = await _readFolder(l);
        if (!files.containsKey(kLibManifestFile) && !files.containsKey(kBeLibSourceFile)) continue;
        final nativeOk = LibNativeTrust.instance.allows(guard.root, id, libNativeSum(files));
        out.add(BeStoredLib(id, files, libRead(_forRead(files), builtin: false, nativeOk: nativeOk), from: from[id] ?? 'project'));
      }
    }
  } on FileSystemException {
    return out; // 目录读不了：当成没有库
  } on PathGuardException {
    return out;
  }
  out.sort((a, b) => a.id.compareTo(b.id));
  return out;
}

/// 读入器只看库本身的文件：画布原件不算。
Map<String, String> _forRead(Map<String, String> files) => {
  for (final e in files.entries)
    if (e.key != kBeLibSourceFile) e.key: e.value,
};

/// 把项目里的库交给文档（它“用上”的库从这里找）。库文档自己不算。
Future<List<BeStoredLib>> beLibsAttach(PathGuard guard, LibUser doc, {List<BeStoredLib>? stored}) async {
  final all = stored ?? await beLibsRead(guard);
  doc.loaded = [
    for (final s in all)
      if (s.id != doc.libraryId && s.lib.id == s.id) s.lib,
  ];
  return all;
}

Future<void> _writeIndex(PathGuard guard) async {
  final all = await beLibsRead(guard);
  final file = File(guard.resolve(kBeLibsIndexFile));
  if (all.isEmpty && !await file.exists()) return;
  await file.parent.create(recursive: true);
  await writeJsonAtomic(file, {
    'format': 1,
    'libs': [
      for (final s in all) {'id': s.id, 'version': s.lib.version, 'from': s.from, 'sum': beLibSum(s.files)},
    ],
  });
}

/// 把一个库的文件写进它的文件夹（多出来的旧文件删掉），再更新清单。标识、文件名不对返回原因。
Future<String?> beLibWriteFolder(PathGuard guard, String id, Map<String, String> files, {String? from}) async {
  if (!kLibIdPattern.hasMatch(id)) return '库的标识不对（$id）';
  if (beLibAuthorReserved(id.split('/').first)) return '作者段 lopi、local 是应用自己留着用的';
  for (final k in files.keys) {
    if (!_safeRel(k) || !_keep(k)) return '库里有一个不该有的文件（$k）';
  }
  final dir = Directory(guard.resolve('$kBeLibsDir/$id'));
  final old = await dir.exists() ? await _readFolder(dir) : const <String, String>{};
  final known = await _fromIndex(guard);
  await dir.create(recursive: true);
  for (final k in old.keys) {
    if (!files.containsKey(k)) await File(guard.resolve('$kBeLibsDir/$id/$k')).delete();
  }
  for (final e in files.entries) {
    if (old[e.key] == e.value) continue;
    final f = File(guard.resolve('$kBeLibsDir/$id/${e.key}'));
    await f.parent.create(recursive: true);
    await writeStringAtomic(f, e.value);
  }
  final file = File(guard.resolve(kBeLibsIndexFile));
  final all = await beLibsRead(guard);
  await writeJsonAtomic(file, {
    'format': 1,
    'libs': [
      for (final s in all) {'id': s.id, 'version': s.lib.version, 'from': s.id == id ? (from ?? known[id] ?? 'project') : (known[s.id] ?? s.from), 'sum': beLibSum(s.files)},
    ],
  });
  return null;
}

/// 把一个库从项目里拿掉（整个文件夹）。用着它的文档会报“找不到这个库”。
Future<void> beLibDelete(PathGuard guard, String id) async {
  if (!kLibIdPattern.hasMatch(id)) return;
  final dir = Directory(guard.resolve('$kBeLibsDir/$id'));
  if (await dir.exists()) await dir.delete(recursive: true);
  await _writeIndex(guard);
}

/// 库的画布原件该在哪：`blocks/作者段/库名/source/backend.lc.json`。
String beLibSourceRel(String id) => '$kBeLibsDir/$id/$kBeLibSourceFile';

/// 这个路径是不是某个库的画布原件；是就返回库的标识。
String? beLibIdOfSource(String rel) {
  final m = RegExp('^$kBeLibsDir/([^/]+/[^/]+)/$kBeLibSourceFile\$').firstMatch(rel.replaceAll('\\', '/'));
  return m == null || !kLibIdPattern.hasMatch(m[1]!) ? null : m[1];
}

/// 新建一个空的库：写好画布原件，返回它的路径（交给后端积木页打开）。不成返回原因。
Future<({String? rel, String? problem})> beLibCreate(PathGuard guard, {required String id, required String name, String author = '', LibSide side = LibSide.backend}) async {
  if (!kLibIdPattern.hasMatch(id)) return (rel: null, problem: '标识要写成“作者段/库名”：小写字母、数字、连字符，字母开头，比如 shuang/todo');
  if (beLibAuthorReserved(id.split('/').first)) return (rel: null, problem: '作者段 lopi、local 是应用自己留着用的，换一个');
  final title = name.trim();
  if (title.isEmpty || title.length > 24) return (rel: null, problem: '库的名字要 1 到 24 个字');
  final all = await beLibsRead(guard);
  if (all.any((s) => s.id == id) || await Directory(guard.resolve('$kBeLibsDir/$id')).exists()) return (rel: null, problem: '项目里已经有标识是 $id 的库了');
  if (all.length >= kBeMaxProjectLibs) return (rel: null, problem: '一个项目最多放 $kBeMaxProjectLibs 个库');
  final doc = BeDocument(
    name: title,
    rules: kLangRulesForNewDocs,
    library: BeLibInfo(id: id, author: author.trim(), side: side),
  );
  final rel = beLibSourceRel(id);
  final file = File(guard.resolve(rel));
  await file.parent.create(recursive: true);
  await saveBackendFile(file, doc);
  await beLibSaveSource(guard, rel, doc);
  return (rel: rel, problem: null);
}

/// 存库的结果。
class BeLibSaved {
  const BeLibSaved({this.problems = const [], this.written = false, this.fresh = const {}});

  /// 出不了库文件的原因（空＝出了）。有问题时库文件夹里上一次出的原样留着。
  final List<String> problems;
  final bool written;

  /// 库改了以后，用它的文档里新冒出来的问题：文档路径 → 问题。
  final Map<String, List<String>> fresh;

  /// 给人看的一句（没有新问题返回 null）。
  String? get freshNote {
    if (fresh.isEmpty) return null;
    final n = fresh.values.fold(0, (a, b) => a + b.length);
    return '库改了以后，用它的 ${fresh.length} 份文档里新冒出 $n 个问题：${fresh.entries.map((e) => '${e.key}——${e.value.first}').join('；')}';
  }
}

Future<BeDocument?> _readDoc(PathGuard guard, String rel) async {
  try {
    final file = File(guard.resolve(rel));
    if (!await file.exists() || await file.length() > 2 * 1024 * 1024) return null;
    final json = jsonDecode(await file.readAsString());
    if (json is! Map || (json['kind'] != null && json['kind'] != 'backend')) return null;
    return BeDocument.fromJson(json).doc;
  } on FileSystemException {
    return null;
  } on FormatException {
    return null;
  } on PathGuardException {
    return null;
  }
}

/// 项目里用了库 [libId] 的文档，各有哪些“错误”级的问题。[docs]＝要看哪些后端文档（相对路径）。
Future<Map<String, Set<String>>> beLibUserIssues(
  PathGuard guard,
  String libId,
  List<BeStoredLib> stored, {
  List<String> docs = const ['backend.lc.json', 'server/backend.lc.json', 'backend/backend.lc.json', 'api/backend.lc.json'],
}) async {
  final out = <String, Set<String>>{};
  final rels = [
    ...docs,
    for (final s in stored)
      if (s.id != libId && s.hasSource) s.sourceRel,
  ];
  for (final rel in rels) {
    final doc = await _readDoc(guard, rel);
    if (doc == null || doc.use(libId) == null) continue;
    await beLibsAttach(guard, doc, stored: stored);
    try {
      out[rel] = {for (final i in backendErrors(doc)) '${i.where}：${i.problem}'};
    } on Object {
      out[rel] = {'这份文档查不动了'}; // 检查器自己出了岔子：当成一个问题报出来，不让存盘崩掉
    }
  }
  return out;
}

Map<String, List<String>> _fresh(Map<String, Set<String>> before, Map<String, Set<String>> after) => {
  for (final e in after.entries)
    if (e.value.difference(before[e.key] ?? const {}).isNotEmpty) e.key: e.value.difference(before[e.key] ?? const {}).toList(),
};

/// 库的画布原件存好以后调：出库文件、写进它的文件夹，再把用它的文档重查一遍。
Future<BeLibSaved> beLibSaveSource(PathGuard guard, String rel, BeDocument doc) async {
  final info = doc.library;
  final id = beLibIdOfSource(rel);
  if (info == null) return const BeLibSaved(problems: ['这份文档不是一个库']);
  if (id == null) return const BeLibSaved(problems: ['库的画布原件要放在 blocks/作者段/库名/source/ 里']);
  if (id != info.id) return BeLibSaved(problems: ['这个库放在 $id 的文件夹里，文档里写的标识却是 ${info.id}']);
  final stored = await beLibsAttach(guard, doc);
  final built = beLibFiles(doc);
  if (built.files == null || built.problems.isNotEmpty) return BeLibSaved(problems: built.problems.isEmpty ? const ['库文件出不来'] : built.problems);
  final old = stored.where((s) => s.id == id).firstOrNull;
  final files = {...built.files!, kBeLibSourceFile: '${doc.encode()}\n'};
  final changed = old == null || beLibSum(old.files) != beLibSum(files);
  final before = changed && old != null ? await beLibUserIssues(guard, id, stored) : const <String, Set<String>>{};
  final bad = await beLibWriteFolder(guard, id, files);
  if (bad != null) return BeLibSaved(problems: [bad]);
  if (!changed || old == null) return const BeLibSaved(written: true);
  final after = await beLibUserIssues(guard, id, await beLibsRead(guard));
  return BeLibSaved(written: true, fresh: _fresh(before, after));
}

String _stem(String name) {
  final cleaned = name.trim().replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '').replaceAll(RegExp(r'\s+'), '-').replaceAll(RegExp(r'^\.+'), '');
  return String.fromCharCodes((cleaned.isEmpty ? '库' : cleaned).runes.take(24));
}

/// 导出成一个文件：`exports/库-名字-版本.lopilib`。返回相对路径；库不在、有问题返回原因。
Future<({String? rel, String? problem})> beLibExport(PathGuard guard, String id) async {
  final s = (await beLibsRead(guard)).where((x) => x.id == id).firstOrNull;
  if (s == null) return (rel: null, problem: '项目里没有库 $id');
  if (!s.ok) return (rel: null, problem: '这个库现在有问题，先修好再导出：${s.problem}');
  final base = 'exports/库-${_stem(s.name)}-${s.lib.version}';
  var rel = '$base$kBeLibFileSuffix';
  for (var n = 2; n < 100 && await File(guard.resolve(rel)).exists(); n++) {
    rel = '$base-$n$kBeLibFileSuffix';
  }
  final file = File(guard.resolve(rel));
  await file.parent.create(recursive: true);
  await writeFileAtomic(file, beLibPack(s.files));
  return (rel: rel, problem: null);
}

/// 工作区里有哪些 `.lopilib` 文件（只看根目录和 exports/，按名字排）。
Future<List<String>> beLibPackFiles(PathGuard guard) async {
  final out = <String>[];
  for (final dir in const ['', 'exports']) {
    try {
      final d = Directory(guard.resolve(dir));
      if (!await d.exists()) continue;
      await for (final e in d.list(followLinks: false)) {
        if (e is File && e.path.endsWith(kBeLibFileSuffix)) out.add(guard.relative(e.path));
      }
    } on FileSystemException {
      continue; // 这个目录读不了就不列
    } on PathGuardException {
      continue;
    }
  }
  return out..sort();
}

/// 打开一个 `.lopilib` 看看（只读，不落盘）：成了是预览，不成是原因。
Future<({BeLibPreview? preview, String? problem})> beLibOpenPack(PathGuard guard, String rel) async {
  try {
    final file = File(guard.resolve(rel));
    if (!await file.exists()) return (preview: null, problem: '找不到 $rel');
    if (await file.length() > kBeLibMaxPackBytes) return (preview: null, problem: '这个文件太大了（超过 8MB），不像是一个库');
    final got = beLibUnpack(await file.readAsBytes());
    if (got.files == null) return (preview: null, problem: got.problem);
    final others = [for (final s in await beLibsRead(guard)) s.lib];
    return (preview: beLibPreview(got.files!, others: others), problem: null);
  } on FileSystemException catch (e) {
    return (preview: null, problem: '文件读不了（${e.osError?.message ?? e.message}）');
  } on PathGuardException catch (e) {
    return (preview: null, problem: e.message);
  }
}

/// 把预览过的库放进项目。项目里已经有同一个标识的库时，`replace` 是 true 才盖掉。
/// 带手写代码的库：`nativeConfirmed`＝她在预览页勾了“我看过这些代码了”。没勾、或者全应用的开关关着，一律不放进来。
Future<BeLibSaved> beLibInstall(PathGuard guard, BeLibPreview preview, {bool replace = false, bool nativeConfirmed = false}) async {
  if (!preview.canImport) return BeLibSaved(problems: preview.problems);
  if (preview.hasNative && !LibNativeTrust.instance.enabled) return const BeLibSaved(problems: ['这个库带了手写代码，而“允许库里的手写代码”是关着的']);
  if (preview.hasNative && !nativeConfirmed) return const BeLibSaved(problems: ['这个库带了手写代码：要先看过代码、勾上“我看过这些代码了”才能导入']);
  final id = preview.id;
  final stored = await beLibsRead(guard);
  final old = stored.where((s) => s.id == id).firstOrNull;
  if (old != null && !replace) return BeLibSaved(problems: ['项目里已经有「${old.name}」（$id，版本 ${old.lib.version}）了']);
  if (old == null && stored.length >= kBeMaxProjectLibs) return const BeLibSaved(problems: ['一个项目最多放 $kBeMaxProjectLibs 个库']);
  final before = old == null ? const <String, Set<String>>{} : await beLibUserIssues(guard, id, stored);
  final files = {...preview.files};
  final bad = await beLibWriteFolder(guard, id, files, from: 'file');
  if (bad != null) return BeLibSaved(problems: [bad]);
  // 确认记的是“这一份”：以后库里的手写代码或清单变了一个字，就要重新看、重新确认。
  if (preview.hasNative) await LibNativeTrust.instance.confirm(guard.root, id, libNativeSum(files));
  if (old == null) return const BeLibSaved(written: true);
  return BeLibSaved(written: true, fresh: _fresh(before, await beLibUserIssues(guard, id, await beLibsRead(guard))));
}

/// “复制一份来改”：换一个标识另存一份。要有画布原件才行（没有就说清楚）。成了返回新库画布原件的路径。
Future<({String? rel, String? problem})> beLibFork(PathGuard guard, String fromId, {required String id, required String name}) async {
  final stored = await beLibsRead(guard);
  final src = stored.where((s) => s.id == fromId).firstOrNull;
  if (src == null) return (rel: null, problem: '项目里没有库 $fromId');
  if (!src.hasSource) return (rel: null, problem: '这个库没有带画布原件（导出它的人没有带上），所以没法回到画布上改。可以新建一个库，把它用上，在它上面再包一层');
  if (!kLibIdPattern.hasMatch(id)) return (rel: null, problem: '标识要写成“作者段/库名”：小写字母、数字、连字符，字母开头');
  if (beLibAuthorReserved(id.split('/').first)) return (rel: null, problem: '作者段 lopi、local 是应用自己留着用的，换一个');
  if (id == fromId || stored.any((s) => s.id == id)) return (rel: null, problem: '项目里已经有标识是 $id 的库了，换一个');
  final title = name.trim();
  if (title.isEmpty || title.length > 24) return (rel: null, problem: '库的名字要 1 到 24 个字');
  Object? json;
  try {
    json = jsonDecode(src.files[kBeLibSourceFile]!);
  } on FormatException {
    return (rel: null, problem: '这个库的画布原件坏了，读不出来');
  }
  final doc = json is Map ? BeDocument.fromJson(json).doc : null;
  final info = doc?.library;
  if (doc == null || info == null) return (rel: null, problem: '这个库的画布原件坏了，读不出来');
  doc.name = title;
  info
    ..originId = fromId
    ..originVersion = src.lib.version
    ..id = id;
  final rel = beLibSourceRel(id);
  final file = File(guard.resolve(rel));
  await file.parent.create(recursive: true);
  await saveBackendFile(file, doc);
  final saved = await beLibSaveSource(guard, rel, doc);
  if (saved.problems.isNotEmpty) {
    await beLibDelete(guard, id);
    return (rel: null, problem: '复制出来的库出不了库文件：${saved.problems.first}');
  }
  await beLibWriteFolder(guard, id, (await beLibsRead(guard)).firstWhere((s) => s.id == id).files, from: 'copy');
  return (rel: rel, problem: null);
}

/// 把一份文档里对库 [fromId] 的用法换成 [toId]（“复制一份来改”以后问用户要不要换）。返回换好的文档和换了几处；没用过 [fromId] 返回 null。
({BeDocument doc, int count})? beLibSwitchUses(BeDocument doc, String fromId, String toId) {
  if (doc.use(fromId) == null || doc.use(toId) != null) return null;
  var n = 0;
  Object? walk(Object? v) {
    if (v is Map) return {for (final e in v.entries) e.key: walk(e.value)};
    if (v is List) return [for (final x in v) walk(x)];
    final ref = beLibOpOf(v);
    if (ref != null && ref.lib == fromId) {
      n++;
      return beLibOp(toId, ref.block);
    }
    return v;
  }

  final next = walk(jsonDecode(jsonEncode(doc.toJson())));
  if (next is! Map) return null;
  final uses = next['uses'];
  if (uses is List) {
    for (final u in uses) {
      if (u is Map && u['id'] == fromId) u['id'] = toId;
    }
  }
  return (doc: BeDocument.fromJson(next).doc..loaded = doc.loaded, count: n);
}
