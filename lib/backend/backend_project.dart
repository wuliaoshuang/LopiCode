/// 后端积木在“项目里”的那一层：认出项目里的后端（[findBackendProjects]）、把积木生成的代码写进项目（[regenerateBackend]）。
///
/// 规矩：
/// - `backend.lc.json` 可以在工作区根目录，也可以在子目录（全栈模板放在 `server/`）；代码生成在它所在的目录。
/// - 所有路径都过 [PathGuard]；生成器给的文件名里带 `..`、绝对路径的，整次生成作废，一个文件都不写。
/// - **只覆盖我们自己生成的文件**。怎么认：`.lopicode/backend-gen.json` 里记着上次写进去的内容的校验值——
///   和现在磁盘上的一样＝没人动过，可以覆盖；不一样＝手改过，不覆盖，放进冲突清单。
///   没有记录时（比如项目是拷过来的）看文件开头有没有生成标记（[kBackendGeneratedMarkers]），有就当成我们的。
/// - 换语言时，上一种语言留下的生成文件（同样只删没人动过的）会清掉。
/// - 坏的 `backend.lc.json`（不是 JSON、不是后端文档）不生成、不改任何文件、不抛异常。
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/backend/backend_readme.dart';
import 'package:lopicode/backend/backend_targets.dart';
import 'package:lopicode/backend/backend_validate.dart';
import 'package:lopicode/core/path_guard.dart';
import 'package:lopicode/core/safe_file.dart';
import 'package:path/path.dart' as p;

/// 在工作区的哪些目录里找 `backend.lc.json`（相对路径，空＝根目录），按这个顺序。
const List<String> kBackendDirs = ['', 'server', 'backend', 'api'];

/// 记“上次生成了哪些文件”的登记文件（在工作区的 `.lopicode/` 里）。
const String kBackendManifestFile = 'backend-gen.json';

/// 生成的文件开头会有的标记（任一条）。各语言的生成器请保留其中一条在文件的头几行里。
const List<String> kBackendGeneratedMarkers = ['由 LopiCode 后端积木生成', 'LopiCode 后端运行时小库'];

/// `backend.lc.json` 最大读多少（防止误把大文件读进内存）。
const int kBackendMaxFileBytes = 2 * 1024 * 1024;

/// 文件开头（前 12 行、2000 字以内）有没有生成标记。
bool hasBackendMarker(String content) {
  final head = content.length > 2000 ? content.substring(0, 2000) : content;
  final lines = const LineSplitter().convert(head).take(12).join('\n');
  return kBackendGeneratedMarkers.any(lines.contains);
}

String _hash(String content) => sha256.convert(utf8.encode(content)).toString();

String _join(String dir, String rel) => dir.isEmpty ? rel : '$dir/$rel';

String _cmd(List<String> command) => command.join(' ');

/// 按文档选的语言（或指定的 `language`）生成要放进项目的文件：生成器的结果，README 后面再接上
/// “在 LopiCode 里怎么启动”和“用 curl 试一试”（见 backend_readme.dart）。`dir`＝后端在工作区里的子目录（空＝根目录）。
/// 这种语言还没有生成器返回 null。
BeGenerated? backendProjectFiles(BeDocument doc, {String? language, String dir = ''}) {
  final gen = generateBackend(doc, language: language);
  if (gen == null) return null;
  final files = {...gen.files};
  final readme = files['README.md'];
  if (readme != null) files['README.md'] = '$readme${beReadmeExtras(doc, gen.target, dir: dir)}';
  return (target: gen.target, files: files);
}

// —— 认出后端项目 ——

/// 工作区里的一份后端。
class BackendProjectInfo {
  const BackendProjectInfo({
    required this.file,
    required this.dir,
    required this.readable,
    this.note,
    this.name = '',
    this.language = '',
    this.port = kBeDefaultPort,
    this.target,
    this.routeCount = 0,
    this.errorCount = 0,
  });

  /// `backend.lc.json` 在工作区里的相对路径（`backend.lc.json` / `server/backend.lc.json`）。
  final String file;

  /// 它所在的目录，相对工作区（空＝根目录）。生成的代码也在这里。
  final String dir;

  /// 文件读不读得懂。读不懂时下面的字段都是默认值，[note] 里是原因。
  final bool readable;
  final String? note;

  final String name;

  /// 文档里记的语言 id。
  final String language;
  final int port;

  /// 这种语言的生成器；还没有生成器（或文件读不懂）为 null。
  final BackendTarget? target;
  final int routeCount;

  /// 校验出的“错误”有几条。
  final int errorCount;

  /// 启动前要先跑的命令（编译等），每条是一整行；在 [dir] 里跑。
  List<String> get buildCommands => [for (final c in target?.buildCommands ?? const <List<String>>[]) _cmd(c)];

  /// 启动命令（在 [dir] 里跑）；没有生成器为 null。
  String? get startCommand => target == null ? null : _cmd(target!.startCommand);

  /// 可以直接贴进应用终端的一整行：从工作区根目录出发，先进目录、再编译、再启动。没有生成器为 null。
  String? get terminalCommand {
    final start = startCommand;
    if (start == null) return null;
    return [if (dir.isNotEmpty) 'cd $dir', ...buildCommands, start].join(' && ');
  }

  /// 服务起来以后的地址（手机上 localhost 指手机自己）。
  String get localUrl => 'http://localhost:$port';
}

/// 读一份后端文件（只读，不备份、不改盘）。`null`＝文件不存在。
Future<({BeDocument? doc, String? note})?> _readBackend(File file) async {
  try {
    if (!await file.exists()) return null;
    if (await file.length() > kBackendMaxFileBytes) return (doc: null, note: '后端文件太大了（超过 2MB），没有读');
    final source = await file.readAsString();
    Object? json;
    try {
      json = jsonDecode(source);
    } on FormatException catch (e) {
      return (doc: null, note: '后端文件不是合法的 JSON（${e.message}）');
    }
    if (json is! Map) return (doc: null, note: '后端文件的内容不是预期的格式（应该是一个对象）');
    final kind = json['kind'];
    if (kind != null && kind != 'backend') return (doc: null, note: '这个文件不是后端积木文件（kind 不是 backend）');
    final parsed = BeDocument.fromJson(json);
    return (doc: parsed.doc, note: parsed.note);
  } on FileSystemException catch (e) {
    return (doc: null, note: '后端文件读不了（${e.osError?.message ?? e.message}）');
  }
}

/// 工作区里有哪些后端（按 [kBackendDirs] 的顺序找：根目录、`server/`…）。没有返回空表。不抛异常。
Future<List<BackendProjectInfo>> findBackendProjects(String workspaceDir) async {
  final guard = PathGuard(workspaceDir);
  final out = <BackendProjectInfo>[];
  for (final dir in kBackendDirs) {
    final rel = _join(dir, kBackendFileName);
    String full;
    try {
      full = guard.resolve(rel);
    } on PathGuardException {
      continue; // 子目录是指到外面去的符号链接：不认
    }
    final read = await _readBackend(File(full));
    if (read == null) continue;
    final doc = read.doc;
    if (doc == null) {
      out.add(BackendProjectInfo(file: rel, dir: dir, readable: false, note: read.note));
      continue;
    }
    out.add(
      BackendProjectInfo(
        file: rel,
        dir: dir,
        readable: true,
        note: read.note,
        name: doc.name,
        language: doc.language,
        port: doc.port,
        target: backendTargetFor(doc.language),
        routeCount: doc.routes.length,
        errorCount: backendErrors(doc).length,
      ),
    );
  }
  return out;
}

/// 工作区里的（第一份）后端；没有返回 null。
Future<BackendProjectInfo?> detectBackendProject(String workspaceDir) async => (await findBackendProjects(workspaceDir)).firstOrNull;

// —— 生成并写进项目 ——

/// 一个没有覆盖的文件。
class BackendConflict {
  const BackendConflict(this.path, this.reason);

  /// 工作区里的相对路径。
  final String path;

  /// 为什么没动它（人话）。
  final String reason;

  @override
  String toString() => '$path：$reason';
}

/// [regenerateBackend] 的结果。路径都是相对工作区的。
class BackendRegenResult {
  const BackendRegenResult({
    this.error,
    this.file = '',
    this.dir = '',
    this.language = '',
    this.languageLabel = '',
    this.written = const [],
    this.unchanged = const [],
    this.removed = const [],
    this.conflicts = const [],
    this.errorCount = 0,
    this.note,
  });

  /// 没做成的原因；null＝生成了（[conflicts] 里的文件除外）。有 error 时一个文件都没动。
  final String? error;
  final String file;
  final String dir;
  final String language;
  final String languageLabel;

  /// 新写 / 覆盖的。
  final List<String> written;

  /// 内容本来就一样、没有重写的。
  final List<String> unchanged;

  /// 清掉的旧文件（换语言后上一种语言留下的）。
  final List<String> removed;

  /// 没有覆盖 / 没有删的：手改过，或者不是我们生成的同名文件。
  final List<BackendConflict> conflicts;

  /// 文档里校验出的“错误”条数（有错误的接口生成器会跳过）。
  final int errorCount;

  /// 读文件时的说明（比如跳过了几条读不懂的内容）。
  final String? note;

  bool get ok => error == null;

  /// 一段给人（或模型）看的总结。
  String get summary {
    if (error != null) return '没有生成：$error';
    final out = StringBuffer('已按 $languageLabel 生成到 ${dir.isEmpty ? '项目根目录' : '$dir/'}：写入 ${written.length} 个文件');
    if (unchanged.isNotEmpty) out.write('，${unchanged.length} 个没有变化');
    if (removed.isNotEmpty) out.write('，清掉旧文件 ${removed.join('、')}');
    out.write('。');
    if (conflicts.isNotEmpty) {
      out.write('\n下面的文件没有动（要用生成的版本，请先把它改名或删掉再生成）：');
      for (final c in conflicts) {
        out.write('\n- $c');
      }
    }
    if (errorCount > 0) out.write('\n注意：积木里还有 $errorCount 处错误，有错误的接口没有生成。');
    if (note != null) out.write('\n$note');
    return out.toString();
  }
}

File _manifestFile(PathGuard guard) => File(guard.resolve('${PathGuard.reservedDir}/$kBackendManifestFile', allowReserved: true));

/// 读登记文件里某个目录的记录：文件（相对那个目录）→ 校验值。读不懂当成没有。
Future<(Map<String, dynamic> all, Map<String, String> files)> _loadManifest(PathGuard guard, String dir) async {
  final json = await readJsonFile(_manifestFile(guard), accept: (j) => j is Map<String, dynamic>, label: '后端生成记录');
  final all = json is Map<String, dynamic> ? Map<String, dynamic>.from(json) : <String, dynamic>{};
  final entry = all[dir.isEmpty ? '.' : dir];
  final raw = entry is Map ? entry['files'] : null;
  return (
    all,
    {
      if (raw is Map)
        for (final e in raw.entries)
          if (e.key is String && e.value is String) e.key as String: e.value as String,
    },
  );
}

/// 生成器给的相对路径合不合规矩：不空、不是绝对路径、没有 `..` / `.` 段、没有反斜杠和控制字符。
bool _safeRelative(String rel) {
  if (rel.isEmpty || rel.startsWith('/') || rel.contains('\\') || rel.contains(':') || RegExp(r'[\x00-\x1f]').hasMatch(rel)) return false;
  return rel.split('/').every((s) => s.isNotEmpty && s != '.' && s != '..');
}

Future<String?> _readText(File file) async {
  try {
    return await file.readAsString();
  } on FileSystemException {
    return null; // 读不了（二进制、权限）：当成“不是我们的”
  }
}

/// 读 `backend.lc.json`、按里面记的语言生成代码、写进它所在的目录。任何输入都不抛异常，结果里说清楚做了什么。
///
/// - [workspaceDir]：工作区目录。
/// - [file]：`backend.lc.json` 在工作区里的相对路径；不给就按 [kBackendDirs] 找第一份。
/// - [doc]：调用方手里已经有文档时直接给（不再读文件；**不会**替你保存它）。
/// - [overwriteEdited]：true＝连手改过的 / 没有标记的同名文件也覆盖（界面在用户确认后才这样调）。
Future<BackendRegenResult> regenerateBackend(String workspaceDir, {String? file, BeDocument? doc, bool overwriteEdited = false}) async {
  final guard = PathGuard(workspaceDir);
  try {
    return await _regenerate(guard, file: file, doc: doc, overwriteEdited: overwriteEdited);
  } on PathGuardException catch (e) {
    return BackendRegenResult(error: e.message, file: file ?? '');
  } on FileSystemException catch (e) {
    return BackendRegenResult(error: '文件操作失败（${e.osError?.message ?? e.message}）', file: file ?? '');
  }
}

Future<BackendRegenResult> _regenerate(PathGuard guard, {String? file, BeDocument? doc, required bool overwriteEdited}) async {
  // 1. 后端文件在哪
  String? rel = file?.trim().replaceAll('\\', '/');
  if (rel == null || rel.isEmpty) {
    for (final dir in kBackendDirs) {
      final candidate = _join(dir, kBackendFileName);
      if (await File(guard.resolve(candidate)).exists()) {
        rel = candidate;
        break;
      }
    }
    if (rel == null || rel.isEmpty) return const BackendRegenResult(error: '这个项目里没有 $kBackendFileName');
  }
  final docPath = guard.resolve(rel); // 越界在这里被拒绝
  rel = guard.relative(docPath);
  if (p.posix.basename(rel) != kBackendFileName) return BackendRegenResult(error: '后端积木文件必须叫 $kBackendFileName（给的是 $rel）', file: rel);
  final dir = p.posix.dirname(rel) == '.' ? '' : p.posix.dirname(rel);

  // 2. 读文档
  String? note;
  var document = doc;
  if (document == null) {
    final read = await _readBackend(File(docPath));
    if (read == null) return BackendRegenResult(error: '找不到 $rel', file: rel, dir: dir);
    if (read.doc == null) return BackendRegenResult(error: '${read.note}。文件没有改动，代码也没有重新生成', file: rel, dir: dir);
    document = read.doc!;
    note = read.note;
  }

  // 3. 生成
  final gen = backendProjectFiles(document, dir: dir);
  if (gen == null) {
    return BackendRegenResult(error: '语言“${document.language}”还没有生成器（现在有：${backendTargets.map((t) => t.id).join('、')}）', file: rel, dir: dir, language: document.language);
  }
  final targets = <String, String>{}; // 相对后端目录的路径 → 绝对路径
  for (final key in gen.files.keys) {
    if (!_safeRelative(key) || key == kBackendFileName) {
      return BackendRegenResult(error: '生成器给了一个不对的文件路径（$key），没有写任何文件', file: rel, dir: dir, language: gen.target.id);
    }
    final full = guard.resolve(_join(dir, key));
    if (!p.isWithin(p.dirname(docPath), full)) {
      return BackendRegenResult(error: '生成的文件 $key 越出了后端目录，没有写任何文件', file: rel, dir: dir, language: gen.target.id);
    }
    targets[key] = full;
  }

  // 4. 哪些能写
  final (manifest, recorded) = await _loadManifest(guard, dir);
  final written = <String>[];
  final unchanged = <String>[];
  final removed = <String>[];
  final conflicts = <BackendConflict>[];
  final nextRecord = <String, String>{};
  final toWrite = <String>[];

  /// 磁盘上这个文件是不是“我们生成的、没人动过”。
  Future<String?> whyNotOurs(String key, String full) async {
    final type = await FileSystemEntity.type(full);
    if (type == FileSystemEntityType.directory) return '这里是一个目录';
    final current = await _readText(File(full));
    if (current == null) return '读不了这个文件';
    final known = recorded[key];
    if (known != null) return known == _hash(current) ? null : '生成之后被手改过';
    return hasBackendMarker(current) ? null : '不是积木生成的文件（开头没有生成标记）';
  }

  for (final e in gen.files.entries) {
    final full = targets[e.key]!;
    final path = _join(dir, e.key);
    final type = await FileSystemEntity.type(full);
    if (type == FileSystemEntityType.notFound) {
      toWrite.add(e.key);
      continue;
    }
    if (type == FileSystemEntityType.file && await _readText(File(full)) == e.value) {
      unchanged.add(path);
      nextRecord[e.key] = _hash(e.value);
      continue;
    }
    final why = await whyNotOurs(e.key, full);
    if (why == null || (overwriteEdited && type == FileSystemEntityType.file)) {
      toWrite.add(e.key);
    } else {
      conflicts.add(BackendConflict(path, why));
      final known = recorded[e.key];
      if (known != null) nextRecord[e.key] = known; // 记录留着：下次还认得出它被改过
    }
  }

  // 5. 上一种语言留下的：登记过的 + 别的生成器会生成的，这次不再生成的那些
  final stale = <String>{...recorded.keys};
  for (final t in backendTargets) {
    if (t.id != gen.target.id) stale.addAll(t.generate(document).keys);
  }
  stale.removeWhere((k) => gen.files.containsKey(k) || !_safeRelative(k) || k == kBackendFileName);
  final toRemove = <String, String>{};
  for (final key in stale) {
    final String full;
    try {
      full = guard.resolve(_join(dir, key));
    } on PathGuardException {
      continue;
    }
    if (await FileSystemEntity.type(full) != FileSystemEntityType.file) continue;
    final why = await whyNotOurs(key, full);
    if (why == null) {
      toRemove[key] = full;
    } else if (recorded.containsKey(key)) {
      conflicts.add(BackendConflict(_join(dir, key), '上一种语言留下的，$why，没有删'));
      nextRecord[key] = recorded[key]!;
    }
  }

  // 6. 动手
  for (final key in toWrite) {
    final f = File(targets[key]!);
    await f.parent.create(recursive: true);
    await writeStringAtomic(f, gen.files[key]!);
    written.add(_join(dir, key));
    nextRecord[key] = _hash(gen.files[key]!);
  }
  final backendDir = p.dirname(docPath);
  for (final e in toRemove.entries) {
    await File(e.value).delete();
    removed.add(_join(dir, e.key));
    // 清空了的子目录顺手删掉（只到后端目录为止）
    var parent = Directory(p.dirname(e.value));
    while (p.isWithin(backendDir, parent.path) && await parent.exists() && await parent.list().isEmpty) {
      await parent.delete();
      parent = parent.parent;
    }
  }
  manifest[dir.isEmpty ? '.' : dir] = {'language': gen.target.id, 'files': nextRecord};
  final mf = _manifestFile(guard);
  await mf.parent.create(recursive: true);
  await writeJsonAtomic(mf, manifest);

  return BackendRegenResult(
    file: rel,
    dir: dir,
    language: gen.target.id,
    languageLabel: gen.target.label,
    written: written,
    unchanged: unchanged,
    removed: removed,
    conflicts: conflicts,
    errorCount: backendErrors(document).length,
    note: note,
  );
}
