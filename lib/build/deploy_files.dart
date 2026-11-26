// “构建与部署”三种方式共用的收文件规则和压缩包：什么会被推送 / 上传 / 打进包，什么永远挡在外面。
// 规则见 docs/build-deploy-design.md 第 3 节。挡掉的文件连同原因一起交回去，界面列给用户看，不悄悄丢。
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:lopicode/apkpack/apk_pack_contract.dart';
import 'package:lopicode/core/path_guard.dart';
import 'package:path/path.dart' as p;

class DeployException implements Exception {
  const DeployException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// 上限（自定）。单个文件超限的跳过并列出；个数或总量超限直接不做。
class DeployLimits {
  const DeployLimits({required this.maxFiles, required this.maxFileBytes, required this.maxTotalBytes});
  final int maxFiles;
  final int maxFileBytes;
  final int maxTotalBytes;

  /// GitHub 推送：每个文件一个请求，所以卡得紧。
  static const push = DeployLimits(maxFiles: 2000, maxFileBytes: 5 * 1024 * 1024, maxTotalBytes: 50 * 1024 * 1024);

  /// SSH 上传 / 本地压缩包。
  static const archive = DeployLimits(maxFiles: 5000, maxFileBytes: 50 * 1024 * 1024, maxTotalBytes: 100 * 1024 * 1024);
}

class DeployFile {
  const DeployFile(this.rel, this.path, this.size);

  /// 相对收集起点的路径，统一用 `/`。
  final String rel;
  final String path;
  final int size;
}

class DeploySkipped {
  const DeploySkipped(this.rel, this.reason);
  final String rel;
  final String reason;
}

class DeployFileSet {
  const DeployFileSet(this.files, this.skipped);
  final List<DeployFile> files;
  final List<DeploySkipped> skipped;
  int get totalBytes => files.fold(0, (sum, f) => sum + f.size);
}

const Set<String> _skipDirsAnywhere = {'.git', 'node_modules', '__pycache__', '.venv', 'venv', '.gradle', '.idea'};
const Set<String> _skipDirsTop = {PathGuard.reservedDir, 'build'};
const List<String> _secretSuffixes = ['.pem', '.key', '.p12', '.pfx', '.jks', '.keystore'];
const List<String> _secretPrefixes = ['.env', 'id_rsa', 'id_dsa', 'id_ecdsa', 'id_ed25519', 'credentials', kKeyBackupPrefix];
const Set<String> _secretNames = {'.netrc', '.npmrc', '.pypirc'};
const List<String> _junkSuffixes = ['.class', '.pyc', '.apk'];

/// 这个文件名看起来是不是密钥 / 凭据（不分大小写）。是的话哪种方式都不带走。
bool isSecretFileName(String name) {
  final n = name.toLowerCase();
  return _secretNames.contains(n) || _secretPrefixes.any(n.startsWith) || _secretSuffixes.any(n.endsWith);
}

/// 从 [root] 收集要带走的文件，按路径排序。同步读目录（不读内容）。
///
/// [includeNodeModules]：本地打包打开“把依赖装进包”时才是 true。个数或总量超限抛 [DeployException]。
DeployFileSet collectDeployFiles(String root, {DeployLimits limits = DeployLimits.archive, bool includeNodeModules = false}) {
  final rootDir = Directory(root);
  if (!rootDir.existsSync()) throw const DeployException('找不到项目目录，可能被移动或删除了。');
  final files = <DeployFile>[];
  final skipped = <DeploySkipped>[];
  var total = 0;

  void walk(Directory dir, String prefix) {
    final List<FileSystemEntity> items;
    try {
      items = dir.listSync(followLinks: false)..sort((a, b) => a.path.compareTo(b.path));
    } on FileSystemException {
      skipped.add(DeploySkipped(prefix.isEmpty ? '.' : '$prefix/', '读不了这个目录'));
      return;
    }
    for (final e in items) {
      final name = p.basename(e.path);
      final rel = prefix.isEmpty ? name : '$prefix/$name';
      if (e is Link) {
        skipped.add(DeploySkipped(rel, '符号链接'));
      } else if (e is Directory) {
        if (prefix.isEmpty && _skipDirsTop.contains(name)) {
          skipped.add(DeploySkipped('$rel/', name == 'build' ? '构建产物目录' : '应用内部目录'));
        } else if (_skipDirsAnywhere.contains(name) && !(includeNodeModules && name == 'node_modules')) {
          skipped.add(DeploySkipped('$rel/', name == '.git' ? 'Git 内部目录' : '依赖 / 缓存目录'));
        } else {
          walk(e, rel);
        }
      } else if (e is File) {
        if (isSecretFileName(name)) {
          skipped.add(DeploySkipped(rel, '密钥 / 凭据类文件'));
          continue;
        }
        if (_junkSuffixes.any(name.toLowerCase().endsWith)) {
          skipped.add(DeploySkipped(rel, '编译产物'));
          continue;
        }
        final size = e.lengthSync();
        if (size > limits.maxFileBytes) {
          skipped.add(DeploySkipped(rel, '太大了（${formatDeployBytes(size)}，单个最多 ${formatDeployBytes(limits.maxFileBytes)}）'));
          continue;
        }
        total += size;
        files.add(DeployFile(rel, e.path, size));
        if (files.length > limits.maxFiles) throw DeployException('文件超过 ${limits.maxFiles} 个了。检查是不是把不相关的目录也放进来了。');
        if (total > limits.maxTotalBytes) throw DeployException('文件加起来超过 ${formatDeployBytes(limits.maxTotalBytes)} 了。删掉不用的大文件再试。');
      }
    }
  }

  walk(rootDir, '');
  return DeployFileSet(files, skipped);
}

/// 把 [set] 读成“相对路径 → 内容”（GitHub 推送用）。[prefix] 非空时每个路径前面加上它（后端在子目录里）。
Future<Map<String, List<int>>> readDeployFiles(DeployFileSet set, {String prefix = ''}) async {
  final out = <String, List<int>>{};
  for (final f in set.files) {
    out[prefix.isEmpty ? f.rel : '$prefix/${f.rel}'] = await File(f.path).readAsBytes();
  }
  return out;
}

/// 打成 tar.gz（在后台 isolate 里读文件、压缩）。包里所有文件都在一层 [topDir] 目录下面。
Future<Uint8List> buildDeployArchive(DeployFileSet set, {required String topDir}) {
  final entries = [for (final f in set.files) (f.rel, f.path)];
  return Isolate.run(() {
    final archive = Archive();
    for (final (rel, path) in entries) {
      final bytes = File(path).readAsBytesSync();
      archive.addFile(ArchiveFile('$topDir/$rel', bytes.length, bytes)..mode = 420); // 0644
    }
    final tar = TarEncoder().encode(archive);
    return Uint8List.fromList(GZipEncoder().encode(tar)!);
  });
}

String formatDeployBytes(int n) => n >= 1024 * 1024 ? '${(n / 1024 / 1024).toStringAsFixed(1)} MB' : (n >= 1024 ? '${(n / 1024).toStringAsFixed(n < 10240 ? 1 : 0)} KB' : '$n B');
