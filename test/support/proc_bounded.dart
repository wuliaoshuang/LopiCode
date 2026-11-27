// 测试里跑外面的程序、起服务用的两样小工具：到时间没跑完就**按进程号杀掉**；杀服务时连它的子进程一起。
// 为什么要有：`Process.run(...).timeout(...)` 超时只是不等了，程序还活着，会一直占着全机的锁
//（2026-11-27 出过一次：一个开了服务不退出的生成程序超时后留了 17 分钟，是别的线发现并结束的）。
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

/// 这个进程现在的子进程、孙进程的进程号（查不了就是空表）。要在杀父进程**之前**查：父进程一死就查不到了。
List<int> procDescendants(int pid) {
  final out = <int>[];
  void walk(int p, int depth) {
    if (depth > 6) return;
    try {
      final r = Process.runSync('pgrep', ['-P', '$p']);
      for (final l in '${r.stdout}'.split('\n')) {
        final c = int.tryParse(l.trim());
        if (c != null && !out.contains(c)) {
          out.add(c);
          walk(c, depth + 1);
        }
      }
    } on Object {
      // 没有 pgrep：只杀得了它自己
    }
  }

  walk(pid, 0);
  return out;
}

/// 按进程号强杀 [proc] 和它当时的子孙进程。已经退出的不碍事。
void procKillTree(Process proc) {
  final kids = procDescendants(proc.pid);
  proc.kill(ProcessSignal.sigkill);
  for (final k in kids) {
    Process.killPid(k, ProcessSignal.sigkill);
  }
}

/// 跑一条命令到结束，最多 [limit]。超时＝先连子孙进程一起杀掉，再抛 [TimeoutException]。
/// [binaryOut]：标准输出交回原始字节（不然是文字）。标准错误总是文字。
Future<ProcessResult> runBounded(
  String exe,
  List<String> args, {
  String? workingDirectory,
  Map<String, String>? environment,
  bool includeParentEnvironment = true,
  required Duration limit,
  bool binaryOut = false,
}) async {
  final proc = await Process.start(exe, args, workingDirectory: workingDirectory, environment: environment, includeParentEnvironment: includeParentEnvironment);
  final out = BytesBuilder(copy: false);
  final outDone = proc.stdout.forEach(out.add);
  final err = proc.stderr.transform(const Utf8Decoder(allowMalformed: true)).join();
  unawaited(proc.stdin.close().catchError((Object _) {}));
  try {
    final code = await proc.exitCode.timeout(limit);
    await outDone;
    final bytes = out.takeBytes();
    return ProcessResult(proc.pid, code, binaryOut ? bytes : utf8.decode(bytes, allowMalformed: true), await err);
  } on TimeoutException {
    procKillTree(proc);
    rethrow;
  }
}

/// 一个起好的服务。
class RunningBackend {
  RunningBackend(this.process, this.port, this.stdoutLines, this.stderrText, this._subs) {
    // 保底：测试没走到 stop()（失败、超时）时，收尾也把服务连子进程杀掉。
    addTearDown(() => procKillTree(process));
  }
  final Process process;
  final int port;

  /// “已启动”之后标准输出的每一行。
  final List<String> stdoutLines;
  final StringBuffer stderrText;
  final List<StreamSubscription<String>> _subs;

  Future<void> stop() async {
    procKillTree(process);
    await process.exitCode.timeout(const Duration(seconds: 10), onTimeout: () => -1);
    for (final s in _subs) {
      await s.cancel();
    }
  }
}
