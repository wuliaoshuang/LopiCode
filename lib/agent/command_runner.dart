import 'dart:async';
import 'dart:convert';
import 'dart:io';

class CommandResult {
  CommandResult({required this.exitCode, required this.output, this.timedOut = false});
  final int exitCode;
  final String output;
  final bool timedOut;
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

/// 本机 shell：桌面平台开发调试、宿主机上跑测试用。
/// 安卓上不再用它跑 Agent 的命令（手机自带的 /system/bin/sh 没有 git、node、python、编译器）：
/// 那边一律进 Ubuntu 运行环境，见 lib/runtime/linux_command_runner.dart。
class LocalShellRunner implements CommandRunner {
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
  Future<CommandResult> run(String command, {required String workingDirectory, Duration timeout = const Duration(seconds: 60)}) async {
    onOutput?.call('\r\n\x1b[2m[Agent] \$ $command\x1b[0m\r\n');
    return runAndCollect(
      () => Process.start(shellPath, ['-c', command], workingDirectory: workingDirectory),
      timeout: timeout,
      onOutput: onOutput,
      startError: '无法启动 shell',
    );
  }
}

/// 一条命令的输出最多收集这么多字符（约 2 MB）；再多的只回显到终端，不留。
const int kMaxCollectedOutputChars = 2000000;

/// 进程结束以后，最多再等这么久把剩下的输出读完（正常情况下输出早就读完了，一点都不用等）。
const Duration kOutputDrainGrace = Duration(seconds: 2);

/// 启动一个进程，收集并回显它的输出，超时就结束它。
Future<CommandResult> runAndCollect(Future<Process> Function() start, {required Duration timeout, void Function(String text)? onOutput, String startError = '无法启动'}) async {
  final Process process;
  try {
    process = await start();
  } on ProcessException catch (e) {
    return CommandResult(exitCode: 127, output: '$startError：${e.message}');
  }
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
  final code = await process.exitCode.timeout(
    timeout,
    onTimeout: () {
      timedOut = true;
      process.kill(ProcessSignal.sigkill);
      return -1;
    },
  );
  // 进程结束了输出却没读完：留在后台的子进程（`xxx &`）、被杀掉的进程的子进程还攥着管道。最多再等这么久。
  await drained.timeout(kOutputDrainGrace, onTimeout: () => const []);
  await out.cancel();
  await err.cancel();
  return CommandResult(exitCode: code, output: buffer.toString(), timedOut: timedOut);
}
