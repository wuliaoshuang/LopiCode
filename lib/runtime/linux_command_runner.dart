import 'dart:io';

import 'package:lopicode/agent/command_runner.dart';
import 'package:lopicode/agent/process_tree.dart';
import 'package:lopicode/agent/skill_scripts.dart';
import 'package:lopicode/runtime/linux_runtime.dart';
import 'package:lopicode/runtime/proot_command.dart';

/// Agent 的 run_command：Ubuntu 环境能用就在里面执行（当前目录是项目目录）。
///
/// 环境不能用的时候分平台（判断在 `LinuxRuntime.localShellAllowed`）：
/// - 安卓：**不退回手机自带的 sh**。没装（或进不去）就不执行，返回一条说清原因、告诉模型该怎么办的结果；
///   装了但启动不了，返回真实的启动错误。
/// - 桌面 / 宿主机测试：和以前一样用本机 shell（开发调试用）。
///
/// 要不要先问用户，由调用它的工具层决定，这里不管。
class LinuxCommandRunner implements CommandRunner, HasCommandTimeout, HasCommandAvailability, HasCommandStop, HasBackgroundStart, HasSkillMount {
  LinuxCommandRunner(this.runtime, {this.onOutput, this.guestCwd}) : _local = LocalShellRunner(onOutput: onOutput);

  final LinuxRuntime runtime;
  final void Function(String text)? onOutput;
  final LocalShellRunner _local;

  /// 工作区是 Ubuntu 里的目录时，它在环境里的路径（命令就在那里执行）。
  final String? guestCwd;

  /// 不许用本机 shell 的平台上，命令是不是只能进 Ubuntu。
  bool get _linuxOnly => !runtime.localShellAllowed;
  bool get _useLinux => _linuxOnly ? runtime.usable : runtime.shouldUseLinux;

  /// 命令进 Ubuntu 跑时，这个工作区的技能镜像挂在环境里的哪（没有技能 / 没挂上是 null）。
  @override
  String? skillsGuestDirFor(String workingDirectory) => _useLinux && runtime.skillsHostDirFor(workingDirectory) != null ? kGuestSkillsDir : null;

  /// 命令现在是进 Ubuntu 跑的：技能脚本只能从 /skills 跑，没挂上就是跑不了。
  @override
  bool get skillMountRequired => _useLinux;

  /// 环境不能用时给模型（也会原样显示给用户）的说明；能用返回 null。
  @override
  String? get unavailableReason {
    if (!_linuxOnly || runtime.usable) return null;
    if (runtime.busy) return 'Ubuntu 运行环境正在安装，还没装完，命令没有执行。请告诉用户：等终端页的安装进度走完再让你继续。';
    if (runtime.installed) return 'Ubuntu 运行环境已经下载，但这个安装包里缺少进入它要用的文件，进不去，命令没有执行。请告诉用户：重新安装完整的 LopiCode 安装包后再试。';
    return 'Ubuntu 运行环境还没有安装，命令没有执行（手机自带的命令行没有 git、node、python，已不再使用）。'
        '请告诉用户：到底部“终端”页或侧边栏“运行环境”页点“安装运行环境”，装好后再让你继续。'
        '不需要执行命令的事（读写文件、改页面）可以照常做；不要反复重试这条命令。';
  }

  @override
  String get description => _linuxOnly && !runtime.usable
      ? 'Ubuntu 运行环境还没装好：现在执行不了任何命令（run_command 会直接返回“没有执行”）。需要跑命令时，先请用户到“终端”页安装运行环境'
      : _useLinux
      ? 'Ubuntu 24.04 环境（bash；可以用 apt 装软件，工作区目录在 ${guestCwd ?? '/workspace'}）'
      : _local.description;

  /// Ubuntu 里装依赖、构建都比较慢，给 5 分钟；本机 sh 还是 60 秒。
  @override
  Duration get commandTimeout => _useLinux ? const Duration(minutes: 5) : const Duration(seconds: 60);

  /// Ubuntu 里执行 [command] 的完整命令行。命令前面套一层 `env 记号=…`：记号跟着命令起的所有进程走，
  /// 停止、应用重开后清理都凭它认（见 lib/agent/process_tree.dart）。
  ProotCommand _proot(String command, String workingDirectory, String tag) =>
      runtime.prootCommand(guestCommand: ['/usr/bin/env', '$kCommandTagEnv=$tag', ...guestRun(command)], projectDir: workingDirectory, guestCwd: guestCwd, term: 'dumb');

  @override
  Future<CommandResult> run(String command, {required String workingDirectory, Duration timeout = const Duration(seconds: 60)}) => _run(command, workingDirectory, timeout, null);

  @override
  Future<CommandResult> runStoppable(String command, {required String workingDirectory, required Duration timeout, required Future<void> stop}) => _run(command, workingDirectory, timeout, stop);

  /// 放到后台跑：进程起来就返回。运行期间占着后台保活，结束后（[StartedCommand.onExit]）放掉。
  @override
  Future<StartedCommand> startBackground(String command, {required String workingDirectory, required String tag}) async {
    final blocked = unavailableReason;
    if (blocked != null) throw ProcessException('', const [], blocked);
    if (!_useLinux) return _local.startBackground(command, workingDirectory: workingDirectory, tag: tag);
    final proot = _proot(command, workingDirectory, tag);
    await runtime.acquireKeepAlive();
    try {
      final process = await Process.start(proot.executable, proot.arguments, environment: proot.environment, includeParentEnvironment: false);
      return StartedCommand(process, CommandProcessTree(process.pid, tag: tag, rootIsTracer: true), onExit: runtime.releaseKeepAlive);
    } on ProcessException catch (e) {
      await runtime.releaseKeepAlive();
      runtime.recordLaunchFailure('Agent 启动后台命令时 PRoot 启动不了', output: e.message);
      rethrow;
    }
  }

  Future<CommandResult> _run(String command, String workingDirectory, Duration timeout, Future<void>? stop) async {
    final blocked = unavailableReason;
    if (blocked != null) {
      onOutput?.call('\r\n\x1b[2m[Agent] \$ $command\x1b[0m\r\n\x1b[33m$blocked\x1b[0m\r\n');
      runtime.log('Agent 的命令没有执行：运行环境还不能用');
      return CommandResult(exitCode: kCommandNotRun, output: blocked);
    }
    if (!_useLinux) {
      return stop == null ? _local.run(command, workingDirectory: workingDirectory, timeout: timeout) : _local.runStoppable(command, workingDirectory: workingDirectory, timeout: timeout, stop: stop);
    }
    onOutput?.call('\r\n\x1b[2m[Agent · Ubuntu] \$ $command\x1b[0m\r\n');
    final tag = newCommandTag();
    final proot = _proot(command, workingDirectory, tag);
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
        stop: stop,
        tag: tag,
        rootIsTracer: true,
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
