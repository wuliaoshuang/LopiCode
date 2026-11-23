import 'dart:io';

import 'package:lopicode/agent/command_runner.dart';
import 'package:lopicode/runtime/linux_runtime.dart';
import 'package:lopicode/runtime/proot_command.dart';

/// Agent 的 run_command：Ubuntu 环境能用就在里面执行（当前目录是项目目录），
/// 不能用就退回手机自带的 sh。要不要先问用户，由调用它的工具层决定，这里不管。
class LinuxCommandRunner implements CommandRunner, HasCommandTimeout {
  LinuxCommandRunner(this.runtime, {this.onOutput, this.guestCwd}) : _local = LocalShellRunner(onOutput: onOutput);

  final LinuxRuntime runtime;
  final void Function(String text)? onOutput;
  final LocalShellRunner _local;

  /// 工作区是 Ubuntu 里的目录时，它在环境里的路径（命令就在那里执行）。
  final String? guestCwd;

  @override
  String get description => runtime.shouldUseLinux ? 'Ubuntu 24.04 环境（bash；可以用 apt 装软件，工作区目录在 ${guestCwd ?? '/workspace'}）' : _local.description;

  /// Ubuntu 里装依赖、构建都比较慢，给 5 分钟；本机 sh 还是 60 秒。
  @override
  Duration get commandTimeout => runtime.shouldUseLinux ? const Duration(minutes: 5) : const Duration(seconds: 60);

  @override
  Future<CommandResult> run(String command, {required String workingDirectory, Duration timeout = const Duration(seconds: 60)}) async {
    if (!runtime.shouldUseLinux) return _local.run(command, workingDirectory: workingDirectory, timeout: timeout);
    onOutput?.call('\r\n\x1b[2m[Agent · Ubuntu] \$ $command\x1b[0m\r\n');
    final proot = runtime.prootCommand(guestCommand: guestRun(command), projectDir: workingDirectory, guestCwd: guestCwd, term: 'dumb');
    await runtime.acquireKeepAlive();
    try {
      var started = true;
      final result = await runAndCollect(
        () async {
          try {
            return await Process.start(proot.executable, proot.arguments, environment: proot.environment, includeParentEnvironment: false);
          } on ProcessException {
            started = false;
            rethrow;
          }
        },
        timeout: timeout,
        onOutput: onOutput,
        startError: '无法启动 Ubuntu 环境',
      );
      if (!started) {
        runtime.recordLaunchFailure('Agent 执行命令时 PRoot 启动不了', output: result.output);
      } else if (result.exitCode == 0) {
        runtime.recordLaunchSuccess();
      }
      return result;
    } finally {
      await runtime.releaseKeepAlive();
    }
  }
}
