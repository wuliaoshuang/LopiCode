import 'dart:async';
import 'dart:convert';
import 'dart:io';

class CommandResult {
  CommandResult({required this.exitCode, required this.output, this.timedOut = false});
  final int exitCode;
  final String output;
  final bool timedOut;
}

/// Agent 的 run_command 通过它执行；界面把同一份输出回显到项目终端里。
abstract class CommandRunner {
  Future<CommandResult> run(String command, {required String workingDirectory, Duration timeout});

  /// 给模型和界面看的说明：这个环境能跑什么。
  String get description;
}

/// 本机 shell（Android 上是系统自带的 /system/bin/sh，没有编译器）。
class LocalShellRunner implements CommandRunner {
  LocalShellRunner({this.onOutput});

  /// 命令和输出的回显（写进项目终端）。
  final void Function(String text)? onOutput;

  static String get shellPath => Platform.isAndroid ? '/system/bin/sh' : '/bin/sh';

  @override
  String get description => Platform.isAndroid
      ? '手机自带的 sh（toybox 基础命令；没有 git、node、python、编译器）'
      : '本机 /bin/sh';

  @override
  Future<CommandResult> run(
    String command, {
    required String workingDirectory,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    onOutput?.call('\r\n\x1b[2m[Agent] \$ $command\x1b[0m\r\n');
    final Process process;
    try {
      process = await Process.start(shellPath, ['-c', command], workingDirectory: workingDirectory);
    } on ProcessException catch (e) {
      return CommandResult(exitCode: 127, output: '无法启动 shell：${e.message}');
    }
    final buffer = StringBuffer();
    void collect(String chunk) {
      if (buffer.length < 200000) buffer.write(chunk);
      onOutput?.call(chunk.replaceAll('\n', '\r\n'));
    }

    final out = process.stdout.transform(const Utf8Decoder(allowMalformed: true)).listen(collect);
    final err = process.stderr.transform(const Utf8Decoder(allowMalformed: true)).listen(collect);
    var timedOut = false;
    final code = await process.exitCode.timeout(timeout, onTimeout: () {
      timedOut = true;
      process.kill(ProcessSignal.sigkill);
      return -1;
    });
    await Future.wait([out.asFuture<void>(), err.asFuture<void>()]).timeout(
      const Duration(seconds: 2),
      onTimeout: () => const [],
    );
    await out.cancel();
    await err.cancel();
    return CommandResult(exitCode: code, output: buffer.toString(), timedOut: timedOut);
  }
}
