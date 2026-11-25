import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:lopicode/agent/process_tree.dart';

class CommandResult {
  CommandResult({required this.exitCode, required this.output, this.timedOut = false, this.stopped = false});
  final int exitCode;
  final String output;
  final bool timedOut;

  /// 用户点了“停止”，命令被中途结束（整棵进程树已经清掉）。
  final bool stopped;
}

/// 命令根本没有执行（执行环境还不能用）时的退出码。shell 里 126 的意思是“找到了但执行不了”，
/// 和“命令找不到”的 127、被信号结束的 128+ 都不混；工具结果的正文里会写清原因。
const int kCommandNotRun = 126;

/// Agent 的 run_command 通过它执行；界面把同一份输出回显到项目终端里。
abstract class CommandRunner {
  Future<CommandResult> run(String command, {required String workingDirectory, Duration timeout});

  /// 给模型和界面看的说明：这个环境能跑什么。
  String get description;
}

/// 需要比默认 60 秒更长时限的执行环境（例如 Ubuntu 里装依赖）实现它。
abstract class HasCommandTimeout {
  Duration get commandTimeout;
}

/// 执行环境可能“还不能用”（例如安卓上 Ubuntu 运行环境没装）的实现它：
/// 工具层在出确认卡之前先问一声，不能用就直接把原因回给模型，不让用户白点一次“允许”。
abstract class HasCommandAvailability {
  /// 现在执行不了命令的原因（给模型和用户看的人话）；能执行返回 null。
  String? get unavailableReason;
}

/// 能中途叫停的执行环境实现它：[stop] 完成时把这条命令连同它起的所有进程一起结束。
abstract class HasCommandStop {
  Future<CommandResult> runStoppable(String command, {required String workingDirectory, required Duration timeout, required Future<void> stop});
}

/// 一条已经起来、放在后台跑的命令（见 lib/agent/background_commands.dart）。
class StartedCommand {
  StartedCommand(this.process, this.tree, {this.onExit});
  final Process process;

  /// 停止时按它把整棵进程树清掉。
  final CommandProcessTree tree;

  /// 进程结束后要做的收尾（例如放掉后台保活）。
  final Future<void> Function()? onExit;
}

/// 能把命令放到后台跑的执行环境实现它。起不来抛 [ProcessException]。
abstract class HasBackgroundStart {
  /// [tag] 是这条命令的记号（见 process_tree.dart）：应用被杀后重开，还能凭它找到没清掉的进程。
  Future<StartedCommand> startBackground(String command, {required String workingDirectory, required String tag});
}

/// 本机 shell：桌面平台开发调试、宿主机上跑测试用。
/// 安卓上不再用它跑 Agent 的命令（手机自带的 /system/bin/sh 没有 git、node、python、编译器）：
/// 那边一律进 Ubuntu 运行环境，见 lib/runtime/linux_command_runner.dart。
class LocalShellRunner implements CommandRunner, HasCommandStop, HasBackgroundStart {
  LocalShellRunner({this.onOutput});

  /// 命令和输出的回显（写进项目终端）。
  final void Function(String text)? onOutput;

  static String get shellPath {
    if (Platform.isAndroid) return '/system/bin/sh';
    if (Platform.isWindows) {
      final root = Platform.environment['ProgramFiles'] ?? r'C:\Program Files';
      final gitShell = File('$root\\Git\\bin\\sh.exe');
      if (gitShell.existsSync()) return gitShell.path;
    }
    return '/bin/sh';
  }

  @override
  String get description => Platform.isAndroid
      ? '手机自带的 sh（toybox 基础命令；没有 git、node、python、编译器）'
      : Platform.isWindows
      ? '本机 Git Bash'
      : '本机 /bin/sh';

  @override
  Future<CommandResult> run(String command, {required String workingDirectory, Duration timeout = const Duration(seconds: 60)}) => _run(command, workingDirectory, timeout, null);

  @override
  Future<CommandResult> runStoppable(String command, {required String workingDirectory, required Duration timeout, required Future<void> stop}) => _run(command, workingDirectory, timeout, stop);

  Future<CommandResult> _run(String command, String workingDirectory, Duration timeout, Future<void>? stop) async {
    onOutput?.call('\r\n\x1b[2m[Agent] \$ $command\x1b[0m\r\n');
    final tag = newCommandTag();
    return runAndCollect(
      () => Process.start(shellPath, ['-c', command], workingDirectory: workingDirectory, environment: {kCommandTagEnv: tag}),
      timeout: timeout,
      onOutput: onOutput,
      startError: '无法启动 shell',
      stop: stop,
      tag: tag,
    );
  }

  @override
  Future<StartedCommand> startBackground(String command, {required String workingDirectory, required String tag}) async {
    final process = await Process.start(shellPath, ['-c', command], workingDirectory: workingDirectory, environment: {kCommandTagEnv: tag});
    return StartedCommand(process, CommandProcessTree(process.pid, tag: tag));
  }
}

/// 命令不需要输入：起来以后立刻把它的标准输入关掉。不关的话，有些命令行工具会把这根永远没人写的管道
/// 当成“还在等输入”，一直卡到超时（`cat`、`read`、等着问 y/n 的安装器）。关了它们马上读到“没有了”。
void closeCommandStdin(Process process) {
  // 进程已经退出时关闭会报错（管道断了）：不用管。
  unawaited(process.stdin.close().then((_) {}, onError: (_) {}));
}

/// 一条命令的输出最多收集这么多字符（约 2 MB）；再多的只回显到终端，不留。
const int kMaxCollectedOutputChars = 2000000;

/// 进程结束以后，最多再等这么久把剩下的输出读完（正常情况下输出早就读完了，一点都不用等）。
const Duration kOutputDrainGrace = Duration(seconds: 2);

/// 启动一个进程，收集并回显它的输出，超时就结束它。
///
/// - 起来后立刻关掉它的标准输入（见 [closeCommandStdin]）。
/// - 超时、或者 [stop] 完成（用户点了停止）：把整棵进程树清掉（见 process_tree.dart），不是只杀我们起的那一个。
///   超时直接强行结束；用户停止先请它退出、等 [kStopGrace] 再强行结束。
/// - [tag]：起进程时放进环境变量的记号；[rootIsTracer]：起的是 PRoot。
Future<CommandResult> runAndCollect(
  Future<Process> Function() start, {
  required Duration timeout,
  void Function(String text)? onOutput,
  String startError = '无法启动',
  Future<void>? stop,
  String? tag,
  bool rootIsTracer = false,
}) async {
  final Process process;
  try {
    process = await start();
  } on ProcessException catch (e) {
    return CommandResult(exitCode: 127, output: '$startError：${e.message}');
  }
  closeCommandStdin(process);
  final buffer = StringBuffer();
  void collect(String chunk) {
    if (buffer.length < kMaxCollectedOutputChars) buffer.write(chunk);
    onOutput?.call(chunk.replaceAll('\n', '\r\n'));
  }

  final out = process.stdout.transform(const Utf8Decoder(allowMalformed: true)).listen(collect, onError: (_) {});
  final err = process.stderr.transform(const Utf8Decoder(allowMalformed: true)).listen(collect, onError: (_) {});
  // 先把“读完了”的 Future 拿到手再等退出码：输出可能比退出码先结束，之后再拿就永远等不到了，
  // 每条命令都会白等满下面的兜底时限。
  final drained = Future.wait([out.asFuture<void>(), err.asFuture<void>()]);
  var timedOut = false;
  var stopped = false;
  final exit = process.exitCode;
  final ended = Completer<int>();
  void end(int code, void Function() mark) {
    if (ended.isCompleted) return;
    mark();
    ended.complete(code);
  }

  unawaited(exit.then((code) => end(code, () {})));
  final timer = Timer(timeout, () => end(-1, () => timedOut = true));
  // [stop] 出错也按“停止”算：只会少跑，不会多跑。
  unawaited(stop?.then((_) => end(-1, () => stopped = true), onError: (_) => end(-1, () => stopped = true)));
  final code = await ended.future;
  timer.cancel();
  if (timedOut || stopped) {
    await CommandProcessTree(process.pid, tag: tag, rootIsTracer: rootIsTracer).terminate(exited: exit, grace: stopped ? kStopGrace : Duration.zero);
  }
  // 进程结束了输出却没读完：留在后台的子进程（`xxx &`）、被杀掉的进程的子进程还攥着管道。最多再等这么久。
  await drained.timeout(kOutputDrainGrace, onTimeout: () => const []);
  await out.cancel();
  await err.cancel();
  return CommandResult(exitCode: code, output: buffer.toString(), timedOut: timedOut, stopped: stopped);
}
