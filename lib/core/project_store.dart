import 'dart:convert';
import 'dart:io';

import 'package:lopicode/core/path_guard.dart';
import 'package:lopicode/core/safe_file.dart';
import 'package:lopicode/core/templates.dart';
import 'package:path/path.dart' as p;

class Project {
  Project({
    required this.id,
    required this.name,
    required this.template,
    required this.createdAt,
    required this.dir,
    this.linuxPath,
    this.pinned = false,
    this.group = '',
  });

  /// 目录名，创建后不变（改名只改显示名）。
  final String id;
  String name;
  final ProjectTemplate template;
  final DateTime createdAt;
  final String dir;

  /// Ubuntu 环境里的目录（如 `/root/app`）作为工作区时，它在环境里的路径；
  /// 应用目录里的项目为 null。[dir] 始终是手机上的真实路径。
  final String? linuxPath;

  /// 置顶、分组：只是列表里的摆法，不动文件。
  bool pinned;
  String group;

  bool get isLinux => linuxPath != null;

  /// 列表里显示的目录。
  String get displayDir => linuxPath ?? '应用目录/projects/$id';

  PathGuard get guard => PathGuard(dir);

  Map<String, dynamic> toJson() => {
    'name': name,
    'template': template.id,
    'createdAt': createdAt.toIso8601String(),
  };
}

class ProjectException implements Exception {
  ProjectException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// 工作区仓库。工作区有两种：
/// - 应用文档目录下 `projects/` 里的一个文件夹（原来的“项目”）；
/// - Ubuntu 环境里的任意目录（如 `/root/app`），登记在 `projects/.workspaces.json` 里。
///
/// 置顶、分组、“从列表移除”也记在这个登记文件里，不动工作区的文件。
class ProjectStore {
  ProjectStore(this.rootDir, {this.linuxRootfs});
  final String rootDir;

  /// Ubuntu 环境的根目录在手机上的位置（没装环境时也可以给，目录不存在而已）。
  String? linuxRootfs;

  static const _metaFile = 'project.json';

  File get _registryFile => File(p.join(rootDir, '.workspaces.json'));

  Future<Map<String, dynamic>> _registry() async {
    // 登记文件坏了：备份后当空的，应用目录里的项目照样能列出来
    final j = await readJsonFile(_registryFile, accept: (j) => j is Map<String, dynamic>, label: '工作区登记文件');
    return j is Map<String, dynamic> ? j : {};
  }

  Future<void> _saveRegistry(Map<String, dynamic> reg) async {
    await writeJsonAtomic(_registryFile, reg);
  }

  Future<void> _patch(String id, Map<String, dynamic> patch) async {
    final reg = await _registry();
    final entry = reg[id] is Map ? Map<String, dynamic>.from(reg[id] as Map) : <String, dynamic>{};
    entry.addAll(patch);
    reg[id] = entry;
    await _saveRegistry(reg);
  }

  /// 列出工作区：置顶的在前，其余按创建时间新到旧。[hidden] 为 true 时列出“已从列表移除”的应用目录项目。
  Future<List<Project>> list({bool hidden = false}) async {
    final reg = await _registry();
    final result = <Project>[];
    final root = Directory(rootDir);
    if (await root.exists()) {
      await for (final entity in root.list()) {
        if (entity is! Directory) continue;
        final project = await _read(entity.path);
        if (project == null) continue;
        final entry = reg[project.id];
        final isHidden = entry is Map && entry['hidden'] == true;
        if (isHidden != hidden) continue;
        if (entry is Map) {
          project
            ..pinned = entry['pinned'] == true
            ..group = '${entry['group'] ?? ''}';
        }
        result.add(project);
      }
    }
    final rootfs = linuxRootfs;
    if (!hidden && rootfs != null) {
      for (final e in reg.entries) {
        final v = e.value;
        if (v is! Map || v['linuxPath'] is! String) continue;
        final linuxPath = v['linuxPath'] as String;
        result.add(
          Project(
            id: e.key,
            name: '${v['name'] ?? p.posix.basename(linuxPath)}',
            template: ProjectTemplate.empty,
            createdAt: DateTime.tryParse('${v['createdAt']}') ?? DateTime.fromMillisecondsSinceEpoch(0),
            dir: hostPathOf(rootfs, linuxPath),
            linuxPath: linuxPath,
            pinned: v['pinned'] == true,
            group: '${v['group'] ?? ''}',
          ),
        );
      }
    }
    result.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      return b.createdAt.compareTo(a.createdAt);
    });
    return result;
  }

  static String hostPathOf(String rootfs, String linuxPath) => p.join(rootfs, linuxPath.substring(1));

  /// 检查并整理 Ubuntu 里的路径：必须是绝对路径，不能有 `..`，不能是系统目录。
  static String validateLinuxPath(String raw) {
    final path = raw.trim();
    if (!path.startsWith('/')) throw ProjectException('要写 Ubuntu 里的完整路径，以 / 开头，例如 /root/myapp');
    final parts = path.split('/').where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) throw ProjectException('不能把整个 Ubuntu 的根目录当工作区');
    if (parts.any((s) => s == '..' || s == '.')) throw ProjectException('路径里不能有 . 或 ..');
    const system = {'proc', 'sys', 'dev', 'bin', 'sbin', 'lib', 'lib64', 'usr', 'etc', 'boot', 'run', 'tmp', 'var', 'workspace'};
    if (system.contains(parts.first)) throw ProjectException('/${parts.first} 是系统目录，不能当工作区。建议放在 /root 或 /home 下面');
    if (parts.length == 1 && parts.first != 'root') throw ProjectException('请选一个更具体的目录，例如 /root/myapp');
    return '/${parts.join('/')}';
  }

  /// 把 Ubuntu 环境里的一个目录加成工作区。目录不存在会建一个空的；已经有的文件不动。
  Future<Project> addLinux(String rawPath, {String? name}) async {
    final rootfs = linuxRootfs;
    if (rootfs == null || !await Directory(rootfs).exists()) {
      throw ProjectException('还没安装 Ubuntu 环境。先到侧边栏“运行环境”安装，再来添加');
    }
    final linuxPath = validateLinuxPath(rawPath);
    final reg = await _registry();
    for (final v in reg.values) {
      if (v is Map && v['linuxPath'] == linuxPath) throw ProjectException('$linuxPath 已经在工作区列表里了');
    }
    final host = hostPathOf(rootfs, linuxPath);
    final type = await FileSystemEntity.type(host);
    if (type == FileSystemEntityType.file) throw ProjectException('$linuxPath 是一个文件，不是目录');
    await Directory(host).create(recursive: true);
    var id = 'u${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
    while (reg.containsKey(id)) {
      id = '${id}x';
    }
    final display = name == null || name.trim().isEmpty ? p.posix.basename(linuxPath) : validateName(name);
    final createdAt = DateTime.now();
    reg[id] = {'linuxPath': linuxPath, 'name': display, 'createdAt': createdAt.toIso8601String()};
    await _saveRegistry(reg);
    return Project(id: id, name: display, template: ProjectTemplate.empty, createdAt: createdAt, dir: host, linuxPath: linuxPath);
  }

  Future<void> setPinned(Project project, bool pinned) async {
    project.pinned = pinned;
    await _patch(project.id, {'pinned': pinned});
  }

  Future<void> setGroup(Project project, String group) async {
    final g = group.trim();
    if (g.length > 20) throw ProjectException('分组名最多 20 个字');
    project.group = g;
    await _patch(project.id, {'group': g});
  }

  /// 从列表里移除，**不删文件**。应用目录里的项目之后可以从“已移除的项目”里加回来。
  Future<void> removeFromList(Project project) async {
    final reg = await _registry();
    if (project.isLinux) {
      reg.remove(project.id);
    } else {
      final entry = reg[project.id] is Map ? Map<String, dynamic>.from(reg[project.id] as Map) : <String, dynamic>{};
      entry['hidden'] = true;
      reg[project.id] = entry;
    }
    await _saveRegistry(reg);
  }

  /// 把移除过的应用目录项目加回列表。
  Future<void> restoreToList(Project project) => _patch(project.id, {'hidden': false});

  /// 这个工作区里有几段对话（不算子代理的、不算空的）。
  static Future<int> conversationCount(Project project) async {
    try {
      final file = File(p.join(project.dir, PathGuard.reservedDir, 'chats.json'));
      if (!await file.exists()) {
        return await File(p.join(project.dir, PathGuard.reservedDir, 'chat.json')).exists() ? 1 : 0;
      }
      final j = jsonDecode(await file.readAsString());
      if (j is! List) return 0;
      return j.where((c) => c is Map && c['parent'] == null && '${c['title'] ?? ''}'.isNotEmpty).length;
    } on Exception {
      return 0;
    }
  }

  Future<Project?> _read(String dir) async {
    final meta = File(p.join(dir, PathGuard.reservedDir, _metaFile));
    try {
      if (!await meta.exists()) return null; // 不是项目目录
      // project.json 坏了：备份后用目录名顶上，项目不能因此从列表里消失
      final decoded = await readJsonFile(meta, accept: (j) => j is Map<String, dynamic>, label: '项目信息');
      final json = decoded is Map<String, dynamic> ? decoded : const <String, dynamic>{};
      return Project(
        id: p.basename(dir),
        name: json['name'] is String && (json['name'] as String).trim().isNotEmpty ? json['name'] as String : p.basename(dir),
        template: ProjectTemplate.byId(json['template'] is String ? json['template'] as String : null),
        createdAt:
            DateTime.tryParse(json['createdAt'] is String ? json['createdAt'] as String : '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        dir: dir,
      );
    } catch (_) {
      return null;
    }
  }

  static String validateName(String raw) {
    final name = raw.trim();
    if (name.isEmpty) throw ProjectException('项目名不能为空');
    if (name.length > 40) throw ProjectException('项目名最多 40 个字');
    return name;
  }

  Future<Project> create(String rawName, ProjectTemplate template) async {
    final name = validateName(rawName);
    await Directory(rootDir).create(recursive: true);
    final id = await _freeId(name);
    final dir = p.join(rootDir, id);
    await Directory(p.join(dir, PathGuard.reservedDir)).create(recursive: true);
    final project = Project(
      id: id,
      name: name,
      template: template,
      createdAt: DateTime.now(),
      dir: dir,
    );
    await _writeMeta(project);
    for (final entry in templateFiles(template, name).entries) {
      final file = File(p.join(dir, entry.key));
      await file.parent.create(recursive: true);
      await file.writeAsString(entry.value);
    }
    return project;
  }

  /// 改名只改显示名，目录不动。
  Future<void> rename(Project project, String rawName) async {
    project.name = validateName(rawName);
    if (project.isLinux) {
      await _patch(project.id, {'name': project.name});
    } else {
      await _writeMeta(project);
    }
  }

  /// 连文件一起删（只对应用目录里的项目开放）。
  Future<void> delete(Project project) async {
    if (project.isLinux) throw ProjectException('Ubuntu 里的目录不在这里删，只能从列表移除');
    final dir = Directory(project.dir);
    // 只删 projects/ 下面的目录，防止误删。
    if (!p.isWithin(p.normalize(p.absolute(rootDir)), p.normalize(p.absolute(dir.path)))) {
      throw ProjectException('项目目录不在应用目录内，已拒绝删除');
    }
    if (await dir.exists()) await dir.delete(recursive: true);
    final reg = await _registry();
    if (reg.remove(project.id) != null) await _saveRegistry(reg);
  }

  Future<void> _writeMeta(Project project) async {
    final meta = File(p.join(project.dir, PathGuard.reservedDir, _metaFile));
    await writeJsonAtomic(meta, project.toJson());
  }

  Future<String> _freeId(String name) async {
    var slug = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    if (slug.isEmpty) slug = 'project';
    if (slug.length > 24) slug = slug.substring(0, 24);
    var candidate = slug;
    var n = 2;
    while (await Directory(p.join(rootDir, candidate)).exists()) {
      candidate = '$slug-$n';
      n++;
    }
    return candidate;
  }
}

/// 列出项目里的文件（相对路径，目录以 `/` 结尾），跳过内部目录。
Future<List<String>> listProjectFiles(
  PathGuard guard, {
  String sub = '',
  int limit = 500,
}) async {
  final start = Directory(guard.resolve(sub));
  if (!await start.exists()) {
    throw PathGuardException('目录不存在：${sub.isEmpty ? '.' : sub}');
  }
  final out = <String>[];
  Future<void> walk(Directory dir) async {
    final entries = await dir.list(followLinks: false).toList();
    entries.sort((a, b) => a.path.compareTo(b.path));
    for (final e in entries) {
      if (out.length >= limit) return;
      final rel = guard.relative(e.path);
      if (rel == PathGuard.reservedDir || rel.startsWith('${PathGuard.reservedDir}/')) {
        continue;
      }
      if (e is Directory) {
        out.add('$rel/');
        await walk(e);
      } else if (e is File) {
        out.add(rel);
      }
    }
  }

  await walk(start);
  return out;
}
