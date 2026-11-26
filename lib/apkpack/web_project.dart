// 判断一个项目能不能走“网页套壳”（[detectWebProject]），以及从网页目录里收集要放进安装包的文件（[collectWebFiles]）。
// 规则和依据见 docs/apk-format-notes.md 的“项目识别”“收集文件”两节。
import 'dart:convert';
import 'dart:io';

import 'package:lopicode/apkpack/apk_pack_contract.dart';
import 'package:lopicode/core/templates.dart';
import 'package:path/path.dart' as p;

/// 收集上限（自定，写在文档里）：总大小、文件数、单个文件。
const int kMaxWebTotalBytes = 100 * 1024 * 1024;
const int kMaxWebFileCount = 5000;
const int kMaxWebFileBytes = 50 * 1024 * 1024;

/// 认作“构建产物目录”的候选，按这个顺序找，第一个里面有 index.html 的算数。
const List<String> kWebOutputDirs = ['dist', 'build', 'out', 'www', 'public', 'web'];

const String _toRemote = '这种项目请用“远程打包”。';

Future<WebProjectInfo> detectWebProject(String projectDir) async {
  final root = p.normalize(p.absolute(projectDir));
  if (!Directory(root).existsSync()) return const WebProjectInfo(applicable: false, reason: '找不到项目目录。');
  bool has(String rel) => File(p.join(root, rel)).existsSync();
  WebProjectInfo no(String why) => WebProjectInfo(applicable: false, reason: why);
  WebProjectInfo yes(String kind, String dir, String why) => WebProjectInfo(applicable: true, reason: why, webRoot: dir.isEmpty ? root : p.join(root, dir), entry: 'index.html', kind: kind);

  // 1. Flutter、原生安卓：要真的编译，套壳做不了
  if (has('pubspec.yaml')) return no('这是 Flutter 项目，要用完整的编译工具才能打包，手机上做不了。$_toRemote');
  if (has('build.gradle') || has('build.gradle.kts') || has('settings.gradle') || has('settings.gradle.kts')) {
    return no('这是原生安卓项目，要用完整的编译工具才能打包，手机上做不了。$_toRemote');
  }

  // 2. 低代码页面：搭建器每次保存都会把网页导出到项目根目录
  if (has(kLowcodePageFile)) {
    if (has('index.html')) return yes('lowcode', '', '会打包低代码页面导出的网页（项目根目录），入口是 index.html。');
    return no('这是低代码项目，但还没有导出网页（找不到 index.html）。先打开“搭建”保存一次页面，再回来打包。');
  }

  // 3. “前端 + 后端”模板：网页在 web/，后端在 server/。只打包网页
  final backend = has('server/backend.lc.json') || has('backend.lc.json');
  if (backend && has('web/index.html')) {
    return yes('web', 'web', '会打包 web 目录里的网页，入口是 index.html。后端不会放进安装包：网页里调的接口地址要改成手机能访问到的服务器地址。');
  }

  // 4. 要构建的前端工程（package.json 里有 build 脚本）：用构建出来的目录，不用源码
  final needsBuild = _hasBuildScript(File(p.join(root, 'package.json')));
  if (needsBuild) {
    for (final dir in kWebOutputDirs) {
      if (has('$dir/index.html')) return yes('dist', dir, '会打包构建好的 $dir 目录，入口是 index.html。改了代码要先重新构建再打包。');
    }
    return no('这个项目要先构建才能打包：在终端里运行构建命令（一般是 npm run build），生成 dist 目录后再回来。');
  }

  // 5. 纯网页
  if (has('index.html')) return yes('static', '', '会打包项目根目录里的网页，入口是 index.html。');

  // 6. 根目录没有入口，但有现成的产物目录
  for (final dir in kWebOutputDirs) {
    if (has('$dir/index.html')) return yes('dist', dir, '会打包 $dir 目录里的网页，入口是 index.html。');
  }

  // 7. 都不是
  const backendMarks = ['go.mod', 'pom.xml', 'requirements.txt', 'main.py', 'composer.json', 'package.json', 'main.go', 'index.php'];
  if (backend || backendMarks.any(has)) return no('这个项目里没有网页（看起来是后端服务），本地打包只能把网页装进安装包。$_toRemote');
  return no('找不到网页入口：项目里没有 index.html。本地打包只适用于网页项目；先做一个 index.html，或改用“远程打包”。');
}

bool _hasBuildScript(File packageJson) {
  try {
    if (!packageJson.existsSync() || packageJson.lengthSync() > 2 * 1024 * 1024) return false;
    final j = jsonDecode(packageJson.readAsStringSync());
    final scripts = j is Map ? j['scripts'] : null;
    final build = scripts is Map ? scripts['build'] : null;
    return build is String && build.trim().isNotEmpty;
  } on Object {
    // package.json 读不了 / 不是 JSON：当作没有构建脚本，按普通网页处理
    return false;
  }
}

/// 收集到的一个文件：[rel] 是相对网页目录的路径（统一用 `/`），[path] 是磁盘上的绝对路径。
class WebFile {
  const WebFile(this.rel, this.path, this.size);
  final String rel;
  final String path;
  final int size;
}

/// 从 [webRoot] 收集要打包的文件，按路径排序（保证每次顺序一样）。同步读盘：只在后台 isolate 里调。
///
/// 不收：以 `.` 开头的文件和目录（.git、.lopicode、.env…）、node_modules、顶层的 build 目录和 .apk 文件（打包产物自己）、
/// 签名钥匙的备份文件（名字以 [kKeyBackupPrefix] 开头，在哪一层都不收）、
/// 低代码项目的页面源文件和 export 目录、指到网页目录外面的符号链接、链接到目录的符号链接、[skipPaths] 里的文件。
List<WebFile> collectWebFiles(
  String webRoot, {
  required String entry,
  Set<String> skipPaths = const {},
  int maxTotalBytes = kMaxWebTotalBytes,
  int maxFileCount = kMaxWebFileCount,
  int maxFileBytes = kMaxWebFileBytes,
}) {
  final rootDir = Directory(webRoot);
  if (!rootDir.existsSync()) throw const ApkPackException('找不到要打包的网页目录，项目可能被移动或删除了。', field: 'project');
  final String realRoot;
  try {
    realRoot = rootDir.resolveSymbolicLinksSync();
  } on FileSystemException {
    throw const ApkPackException('读不了要打包的网页目录。', field: 'project');
  }
  final isLowcode = File(p.join(webRoot, kLowcodePageFile)).existsSync();
  final skip = {for (final s in skipPaths) p.normalize(p.absolute(s))};
  final out = <WebFile>[];
  var total = 0;

  void add(String rel, String path) {
    final size = File(path).lengthSync();
    if (size > maxFileBytes) throw ApkPackException('文件 $rel 太大了（${_mb(size)}），单个文件最多 ${_mb(maxFileBytes)}。', field: 'project');
    total += size;
    if (total > maxTotalBytes) throw ApkPackException('网页文件加起来超过 ${_mb(maxTotalBytes)} 了，安装包会太大。删掉不用的大文件（视频、原图）再打包。', field: 'project');
    out.add(WebFile(rel, path, size));
    if (out.length > maxFileCount) throw ApkPackException('网页目录里的文件超过 $maxFileCount 个了。检查是不是把不相关的目录也放进来了。', field: 'project');
  }

  void walk(Directory dir, String prefix) {
    final List<FileSystemEntity> items;
    try {
      items = dir.listSync(followLinks: false)..sort((a, b) => a.path.compareTo(b.path));
    } on FileSystemException {
      throw ApkPackException('读不了目录 ${prefix.isEmpty ? '（网页目录）' : prefix}。', field: 'project');
    }
    for (final e in items) {
      final name = p.basename(e.path);
      final rel = prefix.isEmpty ? name : '$prefix/$name';
      if (name.startsWith('.')) continue;
      if (skip.contains(p.normalize(p.absolute(e.path)))) continue;
      final top = prefix.isEmpty;
      if (e is Directory) {
        if (name == 'node_modules') continue;
        if (top && (name == 'build' || (isLowcode && name == 'export'))) continue;
        walk(e, rel);
      } else if (e is File) {
        if (top && (name.toLowerCase().endsWith('.apk') || (isLowcode && name == kLowcodePageFile))) continue;
        if (name.startsWith(kKeyBackupPrefix)) continue;
        add(rel, e.path);
      } else if (e is Link) {
        // 符号链接：只收指向网页目录里面的普通文件
        try {
          final target = e.resolveSymbolicLinksSync();
          if (FileSystemEntity.isFileSync(target) && p.isWithin(realRoot, target)) add(rel, target);
        } on FileSystemException {
          // 断掉的链接：不收
        }
      }
    }
  }

  walk(rootDir, '');
  final normEntry = entry.replaceAll('\\', '/');
  if (!out.any((f) => f.rel == normEntry)) throw ApkPackException('网页目录里找不到入口文件 $entry。', field: 'project');
  out.sort((a, b) => a.rel.compareTo(b.rel));
  return out;
}

String _mb(int bytes) => bytes >= 1024 * 1024 ? '${(bytes / 1024 / 1024).toStringAsFixed(bytes % (1024 * 1024) == 0 ? 0 : 1)}MB' : '${(bytes / 1024).ceil()}KB';
