import 'dart:async';
import 'dart:io';

import 'package:lopicode/build/build_controller.dart';
import 'package:lopicode/build/remote_exec.dart';
import 'package:path/path.dart' as p;

/// 在 SSH 构建机上打包：
/// 连接 →（可选）把项目文件传到远程目录 → 在那个目录里跑构建命令、流式看日志 → SFTP 把 APK 拉回来。
class SshBuildController extends BuildJob {
  SshBuildController({
    required this.exec,
    required this.remoteDir,
    required this.command,
    required this.apkRemotePath,
    required this.outputDir,
    this.maxOutputChars = 20000,
  });

  final RemoteExec exec;

  /// 远程工作目录（上传到这里，命令也在这里跑）。
  final String remoteDir;
  final String command;

  /// APK 在远程的位置；相对路径按 [remoteDir] 算。
  final String apkRemotePath;
  final String outputDir;
  final int maxOutputChars;

  final StringBuffer _output = StringBuffer();
  bool _cancelled = false;

  @override
  String get output => _output.toString();

  String get _apkAbsolute =>
      apkRemotePath.startsWith('/') || apkRemotePath.startsWith('~') ? apkRemotePath : p.posix.join(remoteDir, apkRemotePath);

  /// `~/x` 这种路径不能整个加引号（加了就不展开了）。
  static String quotePath(String path) {
    if (path == '~') return '~';
    if (path.startsWith('~/')) return '~/${shellQuote(path.substring(2))}';
    return shellQuote(path);
  }

  void _onOutput(String chunk) {
    _output.write(chunk);
    if (_output.length > maxOutputChars) {
      final kept = _output.toString().substring(_output.length - maxOutputChars);
      _output
        ..clear()
        ..write(kept);
    }
    notifyListeners();
  }

  @override
  void cancel() {
    if (!busy) return;
    _cancelled = true;
    unawaited(exec.close()); // 断开连接，远程命令随会话结束
  }

  void _check() {
    if (_cancelled) throw _Cancelled();
  }

  Future<void> run({Map<String, List<int>>? uploadFiles}) async {
    if (busy) return;
    _cancelled = false;
    log.clear();
    _output.clear();
    apkPath = null;
    apkBytes = null;
    try {
      setPhase(BuildPhase.connecting);
      say('连接构建机…');
      await exec.connect();
      _check();

      if (uploadFiles != null) {
        setPhase(BuildPhase.pushing);
        say('上传 ${uploadFiles.length} 个文件到 $remoteDir…');
        final dirs = <String>{remoteDir, for (final rel in uploadFiles.keys) p.posix.join(remoteDir, p.posix.dirname(rel))};
        final mkdir = await exec.run('mkdir -p ${dirs.map(quotePath).join(' ')}', onOutput: _onOutput);
        if (mkdir != 0) throw _Failed('在构建机上建目录失败（退出码 ${mkdir ?? '未知'}）。');
        // SFTP 不认 ~，先问出远程目录的绝对路径。
        final pwd = StringBuffer();
        await exec.run('cd ${quotePath(remoteDir)} && pwd', onOutput: pwd.write);
        final base = pwd.toString().trim().split('\n').last.trim();
        if (!base.startsWith('/')) throw _Failed('拿不到远程目录的绝对路径。');
        for (final entry in uploadFiles.entries) {
          _check();
          await exec.upload(p.posix.join(base, entry.key), entry.value);
        }
        say('上传完成');
      }

      setPhase(BuildPhase.building);
      say('运行构建命令…');
      final code = await exec.run('cd ${quotePath(remoteDir)} && $command', onOutput: _onOutput);
      _check();
      if (code != 0) {
        throw _Failed(code == null ? '构建命令没跑完：连接中断了。' : '构建命令失败，退出码 $code。看上面的输出找原因。');
      }
      say('构建命令成功');

      setPhase(BuildPhase.downloading);
      final resolved = StringBuffer();
      final found = await exec.run(
        'f=${quotePath(_apkAbsolute)}; [ -f "\$f" ] && (cd "\$(dirname "\$f")" && printf "%s/%s" "\$(pwd)" "\$(basename "\$f")")',
        onOutput: resolved.write,
      );
      final remoteApk = resolved.toString().trim();
      if (found != 0 || !remoteApk.startsWith('/')) {
        throw _Failed('构建成功了，但在构建机上没找到 $_apkAbsolute。检查“APK 路径”。');
      }
      say('下载 $remoteApk…');
      await Directory(outputDir).create(recursive: true);
      final file = File(p.join(outputDir, p.posix.basename(remoteApk)));
      final bytes = await exec.download(remoteApk, file);
      _check();
      apkPath = file.path;
      apkBytes = bytes;
      say('APK 已保存（${ApkBuildController.formatBytes(bytes)}）');
      setPhase(BuildPhase.done);
    } on _Cancelled {
      say('已停止并断开连接。');
      setPhase(BuildPhase.cancelled);
    } on _Failed catch (e) {
      say(e.message);
      setPhase(BuildPhase.failed);
    } on FileSystemException catch (e) {
      say('保存 APK 失败：${e.osError?.message ?? e.message}');
      setPhase(BuildPhase.failed);
    } catch (e) {
      if (_cancelled) {
        say('已停止并断开连接。');
        setPhase(BuildPhase.cancelled);
      } else {
        say('$e');
        setPhase(BuildPhase.failed);
      }
    } finally {
      await exec.close();
    }
  }
}

class _Cancelled implements Exception {}

class _Failed implements Exception {
  _Failed(this.message);
  final String message;
}
