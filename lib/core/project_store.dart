import 'dart:convert';
import 'dart:io';

import 'package:lopicode/core/path_guard.dart';
import 'package:lopicode/core/templates.dart';
import 'package:path/path.dart' as p;

class Project {
  Project({
    required this.id,
    required this.name,
    required this.template,
    required this.createdAt,
    required this.dir,
  });

  /// 目录名，创建后不变（改名只改显示名）。
  final String id;
  String name;
  final ProjectTemplate template;
  final DateTime createdAt;
  final String dir;

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

/// 项目 = 应用文档目录下 `projects/` 里的一个文件夹。
class ProjectStore {
  ProjectStore(this.rootDir);
  final String rootDir;

  static const _metaFile = 'project.json';

  Future<List<Project>> list() async {
    final root = Directory(rootDir);
    if (!await root.exists()) return [];
    final result = <Project>[];
    await for (final entity in root.list()) {
      if (entity is! Directory) continue;
      final project = await _read(entity.path);
      if (project != null) result.add(project);
    }
    result.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return result;
  }

  Future<Project?> _read(String dir) async {
    final meta = File(p.join(dir, PathGuard.reservedDir, _metaFile));
    try {
      final json = jsonDecode(await meta.readAsString()) as Map<String, dynamic>;
      return Project(
        id: p.basename(dir),
        name: (json['name'] as String?) ?? p.basename(dir),
        template: ProjectTemplate.byId(json['template'] as String?),
        createdAt:
            DateTime.tryParse(json['createdAt'] as String? ?? '') ??
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

  Future<void> rename(Project project, String rawName) async {
    project.name = validateName(rawName);
    await _writeMeta(project);
  }

  Future<void> delete(Project project) async {
    final dir = Directory(project.dir);
    // 只删 projects/ 下面的目录，防止误删。
    if (!p.isWithin(p.normalize(p.absolute(rootDir)), p.normalize(p.absolute(dir.path)))) {
      throw ProjectException('项目目录不在应用目录内，已拒绝删除');
    }
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  Future<void> _writeMeta(Project project) async {
    final meta = File(p.join(project.dir, PathGuard.reservedDir, _metaFile));
    await meta.parent.create(recursive: true);
    await meta.writeAsString(jsonEncode(project.toJson()));
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
