// 技能镜像：把开着的技能（带附带文件的）复制一份到运行环境自己的目录里，挂进 Ubuntu 的 /skills。
//
// 为什么是副本：PRoot 的 `-b` 只有“挂进去”，没有“只读挂进去”（对照过它自带的帮助：只有 `-b 主机路径:环境路径` 和结尾加 `!` 两种写法）。
// 直接挂原目录的话，环境里的命令能改掉、删掉技能文件。挂副本就碰不到原件；每次进环境前这里再按原件对齐一遍
// （内容不一样的重写、多出来的删掉），所以上一条命令在 /skills 里做的改动不会留到下一条命令。
//
// 全部是同步读写（拼 PRoot 命令那一步是同步的），技能文件有大小上限（见 skill_scripts.dart），所以很快。
// 任何一步读写失败都返回 null（不挂、不报错），不影响命令本身。
import 'dart:io';
import 'dart:typed_data';

import 'package:lopicode/agent/skill_scripts.dart';
import 'package:lopicode/agent/skills.dart';
import 'package:path/path.dart' as p;

class SkillMirror {
  SkillMirror(this.store, this.rootDir);
  final SkillStore store;

  /// 镜像放在哪（每个工作区一份，子目录名由工作区路径算出来）。
  final String rootDir;

  /// 工作区路径 → 镜像子目录名（FNV-1a，只为了不同工作区不撞在一起）。
  static String keyOf(String? workspaceDir) {
    if (workspaceDir == null) return 'global';
    var h = 0x811c9dc5;
    for (final unit in workspaceDir.codeUnits) {
      h = ((h ^ unit) * 0x01000193) & 0xffffffff;
    }
    return 'ws-${h.toRadixString(16).padLeft(8, '0')}';
  }

  /// 这次该放进镜像的技能：开着的、带附带文件的、没超上限的；同名取工作区那份。名字 → 技能目录。
  Map<String, String> wanted(String? workspaceDir) {
    final disabled = {
      for (final k in store.settings.get<List<dynamic>>(SkillStore.kDisabled) ?? const [])
        if (k is String) k,
    };
    final out = <String, String>{};
    void scan(String dir, bool global) {
      final root = Directory(dir);
      if (!root.existsSync()) return;
      final entries = root.listSync(followLinks: false)..sort((a, b) => a.path.compareTo(b.path));
      for (final e in entries) {
        if (e is! Directory) continue;
        final name = p.basename(e.path);
        if (out.containsKey(name) || disabled.contains('${global ? 'g' : 'w'}:$name')) continue;
        if (!File(p.join(e.path, 'SKILL.md')).existsSync()) continue;
        final files = scanSkillFilesSync(e.path);
        if (files.tooBig || !files.hasExtras) continue;
        out[name] = e.path;
      }
    }

    if (workspaceDir != null) scan(SkillStore.workspaceSkillsDir(workspaceDir), false);
    scan(store.globalDir, true);
    return out;
  }

  /// 把镜像对齐到原件，返回要挂进环境的目录；没有要挂的技能（或者读写失败）返回 null。
  String? sync(String? workspaceDir) {
    try {
      final want = wanted(workspaceDir);
      final mirror = Directory(p.join(rootDir, keyOf(workspaceDir)));
      if (want.isEmpty) {
        // 没有要挂的了：上次留下的镜像清掉，不占地方。
        if (mirror.existsSync()) mirror.deleteSync(recursive: true);
        return null;
      }
      mirror.createSync(recursive: true);
      // 镜像里多出来的技能（关掉了、删掉了、上一条命令自己建的）：删。
      for (final e in mirror.listSync(followLinks: false)) {
        if (e is Directory && want.containsKey(p.basename(e.path))) continue;
        e.deleteSync(recursive: true);
      }
      for (final entry in want.entries) {
        _syncOne(entry.value, p.join(mirror.path, entry.key));
      }
      return mirror.path;
    } on FileSystemException {
      return null;
    }
  }

  void _syncOne(String from, String to) {
    final files = scanSkillFilesSync(from);
    final rels = {'SKILL.md', ...files.scripts, ...files.others};
    Directory(to).createSync(recursive: true);
    // 先删镜像里不该有的（含被换成符号链接、目录的同名项）。
    for (final e in Directory(to).listSync(recursive: true, followLinks: false)) {
      if (!e.existsSync() && e is! Link) continue; // 上一轮循环里跟着父目录一起删掉了
      final rel = p.relative(e.path, from: to).split(p.separator).join('/');
      final keep = e is File ? rels.contains(rel) : (e is Directory && rels.any((r) => r.startsWith('$rel/')));
      if (!keep) e.deleteSync(recursive: true);
    }
    for (final rel in rels) {
      final src = File(p.joinAll([from, ...rel.split('/')]));
      final dst = File(p.joinAll([to, ...rel.split('/')]));
      final bytes = src.readAsBytesSync();
      if (dst.existsSync() && _same(dst.readAsBytesSync(), bytes)) continue;
      dst.parent.createSync(recursive: true);
      dst.writeAsBytesSync(bytes, flush: true);
    }
  }

  static bool _same(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
