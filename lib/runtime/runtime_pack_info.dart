// “运行环境”页要用、但快照里没有的几样只读信息：占了多大空间、装好的语言是哪个版本、上一次安装为什么没成。
//
// 全部只读文件、不起进程、不联网，也不碰安装逻辑（那在 linux_runtime.dart）。读不到就返回 null / 空，
// 界面据此“不显示”，不编数字。
import 'dart:io';

import 'package:lopicode/runtime/runtime_sources.dart';
import 'package:path/path.dart' as p;

/// 语言 / 工具 → material-icon-theme 里的图标名（`FileIcon.language` 认的叫法）。
/// 表里没有的直接用它自己的 id（go、java、php 这些本来就对得上），再找不到界面会退回通用的代码图标。
const Map<String, String> _packIcons = {'node': 'nodejs', 'python': 'python', 'git': 'git'};

String packIconId(String packId) => _packIcons[packId] ?? packId;

/// 一个目录现在占多大（字节）：把里面每个普通文件的大小加起来，不跟着符号链接走。
/// 目录不在返回 null。硬链接会被算多次、也没按磁盘块取整，所以界面上写“约”。
Future<int?> directorySize(String dir) async {
  final root = Directory(dir);
  if (!root.existsSync()) return null;
  var total = 0;
  try {
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      try {
        total += await entity.length();
      } on FileSystemException {
        // 数的过程中文件被删了（正在装软件 / 卸载）：跳过这一个
      }
    }
  } on FileSystemException {
    // 某个子目录读不了或中途被删：已经数到的照样算数
  }
  return total;
}

/// 用 apt 装的那几样，版本记在 dpkg 的清单里：语言 id → 包名。
const Map<String, String> _dpkgPackages = {'python': 'python3', 'git': 'git', 'java': 'openjdk-21-jdk-headless', 'php': 'php-cli'};

/// 读出已装语言的版本号（只读环境里的文件，不执行任何命令）。读不出来的那一项不在结果里。
/// - Node.js：官方包自带的 `usr/local/include/node/node_version.h`。
/// - Go：官方包自带的 `usr/local/go/VERSION`。
/// - apt 装的（Python、Git、JDK、PHP）：`var/lib/dpkg/status` 里对应包的 Version。
Future<Map<String, String>> readPackVersions(String rootfsDir, Iterable<String> packIds) async {
  final out = <String, String>{};
  String? dpkg;
  for (final id in packIds) {
    try {
      if (id == 'node') {
        final header = File(p.join(rootfsDir, 'usr/local/include/node/node_version.h'));
        if (!header.existsSync()) continue;
        final version = nodeVersionFromHeader(await header.readAsString());
        if (version != null) out[id] = version;
        continue;
      }
      if (id == 'go') {
        // Go 官方包根目录的 VERSION 文件，第一行形如 “go1.26.11”
        final file = File(p.join(rootfsDir, 'usr/local/go/VERSION'));
        if (!file.existsSync()) continue;
        final version = RegExp(r'^go([0-9][0-9A-Za-z.]*)').firstMatch((await file.readAsString()).trim())?.group(1);
        if (version != null) out[id] = version;
        continue;
      }
      final package = _dpkgPackages[id];
      if (package == null) continue;
      if (dpkg == null) {
        final status = File(p.join(rootfsDir, 'var/lib/dpkg/status'));
        dpkg = status.existsSync() ? await status.readAsString() : '';
      }
      final version = dpkgVersion(dpkg, package);
      if (version != null) out[id] = version;
    } on FileSystemException {
      // 读不到就不显示版本
    } on FormatException {
      // 文件不是合法的文字：同上
    }
  }
  return out;
}

String? nodeVersionFromHeader(String header) {
  String? part(String name) => RegExp('#define\\s+NODE_${name}_VERSION\\s+(\\d+)').firstMatch(header)?.group(1);
  final major = part('MAJOR'), minor = part('MINOR'), patch = part('PATCH');
  return major == null || minor == null || patch == null ? null : '$major.$minor.$patch';
}

/// dpkg 清单里某个包的上游版本号：去掉前面的 “1:” 和后面的发行版修订（“-0ubuntu2”）。没装返回 null。
String? dpkgVersion(String status, String package) {
  for (final block in status.split(RegExp(r'\n\s*\n'))) {
    final lines = block.split('\n');
    if (!lines.any((l) => l.trim() == 'Package: $package')) continue;
    if (!lines.any((l) => l.startsWith('Status:') && l.contains(' installed'))) continue;
    final raw = lines.firstWhere((l) => l.startsWith('Version:'), orElse: () => '').replaceFirst('Version:', '').trim();
    if (raw.isEmpty) return null;
    final upstream = RegExp(r'^(?:\d+:)?([0-9][0-9A-Za-z.]*)').firstMatch(raw)?.group(1);
    return upstream ?? raw;
  }
  return null;
}

/// 上一次一键安装（已经结束的那次）是哪一项、怎么收场的。
class PackAttempt {
  const PackAttempt({required this.packId, required this.stopped, required this.reason});
  final String packId;

  /// 是用户自己点的“停止 / 取消”，不算出错。
  final bool stopped;

  /// 给用户看的原因（安装器分好类的那句人话的第一行）。
  final String reason;
}

/// “上一次没装成的是哪一项、为什么”。正在装、已经装好、没有失败都返回 null。
/// 失败的那一项和原因由安装器（`PackInstaller`）记在快照的 `packErrorId` / `packError` 里，这里不再从输出里猜；
/// 用户自己停掉的不记成失败，只在输出最后留一行“已取消安装 X。”，据此认出来。
PackAttempt? lastFailedPack({
  required List<RuntimePack> packs,
  required Set<String> installed,
  required String? runningPack,
  required List<String> output,
  required String? errorId,
  required String? errorMessage,
}) {
  if (runningPack != null) return null;
  if (errorId != null) {
    if (installed.contains(errorId) || !packs.any((p) => p.id == errorId)) return null;
    final first = (errorMessage ?? '').split('\n').first.trim();
    return PackAttempt(packId: errorId, stopped: false, reason: first.isEmpty ? '安装没有成功' : first);
  }
  if (output.isEmpty) return null;
  for (final pack in packs) {
    if (output.last != '已取消安装 ${pack.title}。' || installed.contains(pack.id)) continue;
    return PackAttempt(packId: pack.id, stopped: true, reason: '已停止，没有装完');
  }
  return null;
}
