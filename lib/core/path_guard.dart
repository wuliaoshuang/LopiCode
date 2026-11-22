import 'dart:io';

import 'package:path/path.dart' as p;

/// 路径越界或不合法时抛出。消息是给用户 / 模型看的中文。
class PathGuardException implements Exception {
  PathGuardException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// 把所有文件访问限制在一个项目目录内。
///
/// 这是代码层面的硬约束：Agent 工具、预览服务器、文件树都只通过它解析路径，
/// 不依赖提示词去“劝”模型别越界。
class PathGuard {
  PathGuard(String root) : root = p.normalize(p.absolute(root));

  /// 项目根目录（绝对路径、已规范化）。
  final String root;

  /// 应用内部目录：存项目元数据和对话记录，Agent 与预览都不能碰。
  static const String reservedDir = '.lopicode';

  /// 把相对路径解析成项目内的绝对路径；任何逃逸都会抛 [PathGuardException]。
  String resolve(String relative, {bool allowReserved = false}) {
    var rel = relative.trim().replaceAll('\\', '/');
    if (rel.contains('\u0000')) {
      throw PathGuardException('路径里有非法字符');
    }
    if (rel.isEmpty || rel == '.' || rel == './') return root;
    if (rel.startsWith('/') ||
        rel.startsWith('~') ||
        RegExp(r'^[A-Za-z]:').hasMatch(rel) ||
        rel.contains('://')) {
      throw PathGuardException('只能使用项目内的相对路径，不能用绝对路径：$relative');
    }
    final full = p.normalize(p.join(root, rel));
    if (full != root && !p.isWithin(root, full)) {
      throw PathGuardException('路径越出了项目目录：$relative');
    }
    // 符号链接也不能把访问带出项目目录。
    final realRoot = _realExisting(root);
    final real = _realExisting(full);
    if (real != realRoot && !p.isWithin(realRoot, real)) {
      throw PathGuardException('路径通过符号链接越出了项目目录：$relative');
    }
    if (!allowReserved && full != root) {
      final first = p.split(p.relative(full, from: root)).first;
      if (first == reservedDir) {
        throw PathGuardException('$reservedDir 是应用内部目录，不能访问');
      }
    }
    return full;
  }

  /// 绝对路径 → 项目内相对路径（统一用 `/`）。
  String relative(String full) =>
      p.relative(full, from: root).replaceAll('\\', '/');

  /// 解析“最深的已存在祖先”的真实路径，再拼回尚不存在的部分。
  static String _realExisting(String path) {
    var current = path;
    final pending = <String>[];
    while (true) {
      final type = FileSystemEntity.typeSync(current, followLinks: false);
      if (type != FileSystemEntityType.notFound) {
        String real;
        try {
          real = type == FileSystemEntityType.directory
              ? Directory(current).resolveSymbolicLinksSync()
              : File(current).resolveSymbolicLinksSync();
        } on FileSystemException {
          // 断掉的符号链接：按链接目标处理，宁可拒绝。
          real = p.normalize(
            p.join(p.dirname(current), Link(current).targetSync()),
          );
        }
        return pending.isEmpty
            ? real
            : p.normalize(p.joinAll([real, ...pending.reversed]));
      }
      final parent = p.dirname(current);
      if (parent == current) return path;
      pending.add(p.basename(current));
      current = parent;
    }
  }
}
