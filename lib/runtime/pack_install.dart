/// 在 Ubuntu 环境里装语言 / 工具（清单见 runtime_sources.dart 的 `runtimePacks`）：
/// 起进程、收输出、取消、把失败翻成说得清的原因，以及“这个命令在不在”的核对。
///
/// 状态（正在装哪个、输出、上次失败的原因）挂在 [PackInstaller] 上，`LinuxRuntime` 把它们拍进快照。
/// 进程怎么起可以换（[GuestProcessStarter]）：测试里换成假的，不进 PRoot、不联网。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:lopicode/runtime/linux_runtime.dart';
import 'package:lopicode/runtime/proot_command.dart';
import 'package:lopicode/runtime/runtime_sources.dart';

/// 把一条 PRoot 命令变成进程。默认是真的 `Process.start`。
typedef GuestProcessStarter = Future<Process> Function(ProotCommand command);

Future<Process> startGuestProcess(ProotCommand command) => Process.start(command.executable, command.arguments, environment: command.environment, includeParentEnvironment: false);

/// 装失败的几类原因（界面和终端里的说法由 [PackInstallResult.message] 给，这里只是分类，测试和重试逻辑用）。
enum PackFailure {
  /// 用户取消的。
  cancelled,

  /// 已经有别的东西在装（同一时间只装一个）。
  busy,

  /// Ubuntu 环境还不能用（没装，或安装包里缺 PRoot）。
  notUsable,

  /// 手机剩余空间不够（装之前就查出来了，或装到一半写满了）。
  noSpace,

  /// 连不上下载源（解析不了域名、连不上、超时、中途断开）。
  network,

  /// 下载源里没有这个包 / 这个文件。
  notFound,

  /// 下到的文件校验不过。
  checksum,

  /// PRoot 进程起不来。
  launch,

  /// 别的原因（看输出）。
  other,
}

class PackInstallResult {
  const PackInstallResult.ok() : ok = true, failure = null, message = null, exitCode = 0;
  const PackInstallResult.failed(PackFailure this.failure, String this.message, {this.exitCode}) : ok = false;

  final bool ok;
  final PackFailure? failure;

  /// 失败的原因（大白话，带真正的原因）；成功是 null。
  final String? message;
  final int? exitCode;

  bool get cancelled => failure == PackFailure.cancelled;
}

/// 看安装脚本的输出，判断是哪一类失败。认的都是 apt、dpkg、curl、tar 自己的原话：
/// 这些原话没有在真机的 PRoot 里一条条触发过（见 docs/api-notes.md），认不出来就归到“别的原因”并把最后几行原样给出去。
PackFailure classifyPackFailure(Iterable<String> output) {
  final text = output.join('\n');
  bool has(String pattern) => RegExp(pattern, caseSensitive: false).hasMatch(text);
  if (has(r'No space left on device|enough free space|磁盘空间不足')) return PackFailure.noSpace;
  // “: FAILED” 是 sha256sum 的原话，要分大小写：apt 的 “E: Failed to fetch” 是网络问题。
  if (has(r'校验没通过|sha256sum: WARNING|Hash Sum mismatch') || RegExp(r': FAILED\s*$', multiLine: true).hasMatch(text)) return PackFailure.checksum;
  if (has(r'Unable to locate package|has no installation candidate|curl: \(22\)|404\s+Not Found')) return PackFailure.notFound;
  if (has(
    r'Temporary failure resolving|Could not resolve|Failed to fetch|Unable to connect|Connection timed out|Connection refused|Network is unreachable|Could not connect|curl: \((5|6|7|18|28|35|52|56)\)',
  )) {
    return PackFailure.network;
  }
  return PackFailure.other;
}

String _lastLines(List<String> output, int count) {
  final lines = [
    for (final l in output)
      if (l.trim().isNotEmpty) l.trim(),
  ];
  return lines.length <= count ? lines.join('\n') : lines.sublist(lines.length - count).join('\n');
}

/// 一次只装一个。[LinuxRuntime] 持有一个。
class PackInstaller {
  PackInstaller(this.runtime, {GuestProcessStarter? start}) : _start = start ?? startGuestProcess;

  final LinuxRuntime runtime;
  final GuestProcessStarter _start;

  /// 正在装的那一项的 id。
  String? running;
  final List<String> output = [];

  /// 上一次没装成的是哪一项、为什么（装成功或重新开始装就清掉）。
  String? errorPack;
  String? error;

  Process? _process;
  bool _cancelRequested = false;

  /// 取消正在装的那一项。脚本可以重复跑，下次再装会接着来。
  void cancel() {
    if (running == null) return;
    _cancelRequested = true;
    _process?.kill(ProcessSignal.sigkill);
  }

  /// 在环境里执行 [pack] 的安装脚本。输出实时进 [output]，每一行也交给 [onLine]。
  Future<PackInstallResult> install(RuntimePack pack, {void Function(String line)? onLine}) async {
    if (!runtime.usable) return const PackInstallResult.failed(PackFailure.notUsable, 'Ubuntu 运行环境还不能用，先把它装好。');
    if (running != null) return const PackInstallResult.failed(PackFailure.busy, '已经有别的东西在装，等它装完再试。');
    running = pack.id;
    _cancelRequested = false;
    errorPack = null;
    error = null;
    output.clear();
    void collect(String line) {
      output.add(line);
      if (output.length > 400) output.removeRange(0, output.length - 400);
      onLine?.call(line);
      runtime.notifyChanged();
    }

    collect('开始安装 ${pack.title}…');
    await runtime.acquireKeepAlive();
    PackInstallResult result;
    try {
      result = await _run(pack, collect);
    } finally {
      _process = null;
      running = null;
      await runtime.releaseKeepAlive();
    }
    if (result.ok) {
      collect('${pack.title} 安装完成。');
    } else {
      if (!result.cancelled) {
        errorPack = pack.id;
        error = result.message;
      }
      collect(result.cancelled ? '已取消安装 ${pack.title}。' : '${pack.title} 没装成：${result.message}');
    }
    runtime.log('安装 ${pack.title}：${result.ok ? '成功' : (result.cancelled ? '已取消' : '失败（${result.failure!.name}${result.exitCode == null ? '' : '，退出码 ${result.exitCode}'}）')}');
    return result;
  }

  Future<PackInstallResult> _run(RuntimePack pack, void Function(String line) collect) async {
    final need = (pack.downloadBytes ?? 0) + (pack.diskBytes ?? 0);
    if (need > 0) {
      final free = await runtime.host.freeBytes(Directory(runtime.baseDir).parent.path);
      if (_cancelRequested) return const PackInstallResult.failed(PackFailure.cancelled, '已取消');
      if (free != null && free < need) {
        return PackInstallResult.failed(PackFailure.noSpace, '手机剩余空间不够：装 ${pack.title} 大约要 ${formatBytes(need)}（下载的包加上装好后占的），现在只剩 ${formatBytes(free)}。清出空间后再试。');
      }
    }
    final Process process;
    try {
      process = _process = await _start(runtime.prootCommand(guestCommand: guestRun(pack.script), term: 'dumb'));
    } on ProcessException catch (e) {
      return PackInstallResult.failed(PackFailure.launch, '进不去 Ubuntu 环境（${e.message}）。到“运行环境”页做一次一键诊断。');
    }
    if (_cancelRequested) process.kill(ProcessSignal.sigkill);
    const decoder = Utf8Decoder(allowMalformed: true);
    // 流出错（进程被杀时管道断开）不用管：退出码会说明结果。
    final out = process.stdout.cast<List<int>>().transform(decoder).transform(const LineSplitter()).listen(collect, onError: (_) {});
    final err = process.stderr.cast<List<int>>().transform(decoder).transform(const LineSplitter()).listen(collect, onError: (_) {});
    // 先把“读完了”的 Future 拿到手再等退出码：流可能比退出码先结束，之后再拿就永远等不到了。
    final drained = Future.wait([out.asFuture<void>(), err.asFuture<void>()]);
    final code = await process.exitCode;
    await drained.timeout(const Duration(seconds: 2), onTimeout: () => const []);
    await out.cancel();
    await err.cancel();
    if (_cancelRequested) return PackInstallResult.failed(PackFailure.cancelled, '已取消', exitCode: code);
    if (code == 0) return const PackInstallResult.ok();
    final kind = classifyPackFailure(output);
    final mirror = runtime.aptMirror.label;
    final message = switch (kind) {
      PackFailure.noSpace => '手机空间写满了。清出空间后再试（已经下好的部分会留着）。',
      PackFailure.network => '连不上下载源（现在用的是“$mirror”）。检查网络，或到“运行环境”页换一个下载源再试。',
      PackFailure.notFound => '下载源里找不到要装的包（现在用的是“$mirror”）。到“运行环境”页换一个下载源再试。',
      PackFailure.checksum => '下到的文件校验没通过（多半是下载中途出了错），已经删掉，再试一次会重新下。',
      _ => '安装脚本中途出错了（退出码 $code）。最后的输出：\n${_lastLines(output, 3)}',
    };
    return PackInstallResult.failed(kind, message, exitCode: code);
  }

  /// 进 Ubuntu 核对 [commands] 是不是都能直接用（`command -v`）。
  /// true＝都在；false＝至少缺一个；null＝核对不了（环境不能用、进程起不来、[timeout] 内没回来）。
  Future<bool?> hasCommands(List<String> commands, {Duration timeout = const Duration(seconds: 20)}) async {
    if (!runtime.usable) return null;
    if (commands.isEmpty) return true;
    final script = [for (final c in commands) 'command -v $c >/dev/null 2>&1'].join(' && ');
    final Process process;
    try {
      process = await _start(runtime.prootCommand(guestCommand: guestRun(script), term: 'dumb'));
    } on ProcessException {
      return null;
    }
    // 输出用不着，但要读掉，免得管道写满把进程卡住。
    final out = process.stdout.listen((_) {}, onError: (_) {});
    final err = process.stderr.listen((_) {}, onError: (_) {});
    try {
      final code = await process.exitCode.timeout(timeout);
      return code == 0;
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
      return null;
    } finally {
      await out.cancel();
      await err.cancel();
    }
  }
}
