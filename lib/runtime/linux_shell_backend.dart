import 'dart:async';
import 'dart:convert';

import 'package:lopicode/runtime/linux_runtime.dart';
import 'package:lopicode/runtime/proot_command.dart';
import 'package:lopicode/terminal/pty_native.dart';
import 'package:lopicode/terminal/terminal_session.dart';

typedef PtyArgsSpawner = PtyProcess Function(
  String executable,
  List<String> arguments, {
  required String workingDirectory,
  required Map<String, String> environment,
  required int rows,
  required int columns,
});

/// 终端后端：在伪终端里跑 PRoot，进到 Ubuntu 的 bash。
///
/// 起不来的时候不能把人卡在黑屏上。分两种平台（判断在 `LinuxRuntime.localShellAllowed`）：
/// - 安卓（不许用本机 shell）：一失败就进“启动失败”状态（[failure] 有原因），终端页据此换成失败页，
///   给出重试、兼容模式重试、一键诊断、连接 SSH 四条出路；**不退回手机自带的 sh**。
/// - 桌面 / 宿主机测试（允许本机 shell，开发调试用）：和以前一样——第一次失败提示按回车重试（改用兼容模式），
///   连续失败到上限退回本机 shell。
class LinuxShellBackend implements TerminalBackend {
  LinuxShellBackend({
    required this.runtime,
    required this.projectDir,
    this.guestCwd,
    PtyArgsSpawner? spawner,
    this.fallbackSpawner,
    this.quickExit = const Duration(seconds: 3),
    this.stallTimeout = const Duration(seconds: 8),
  }) : _spawn = spawner ?? FlutterPtyProcess.spawnWithArgs;

  final LinuxRuntime runtime;
  final String projectDir;

  /// 工作区是 Ubuntu 里的目录时，它在环境里的路径。
  final String? guestCwd;
  final PtyArgsSpawner _spawn;
  final PtySpawner? fallbackSpawner;

  /// 启动后这么短时间内就非正常退出，算启动失败。
  final Duration quickExit;

  /// 进去后这么久一个字都没输出，算“没有响应”（PRoot 活着但卡住了）。
  final Duration stallTimeout;

  /// 现在是不是处于“没有响应”状态。界面据此显示三个出路：兼容模式重试、连接 SSH（桌面上是退回本机）、去诊断。
  bool get stalled => _stalled;
  bool _stalled = false;

  /// 启动失败的真实原因；没失败（或已经在重试）是 null。只在不许用本机 shell 的平台上会有值。
  String? get failure => _failure;
  String? _failure;

  /// “没有响应”或“启动失败”状态变了：终端列表接这个回调，通知终端页重画。
  void Function()? onStalledChanged;

  void _setFailure(String? value) {
    if (_failure == value) return;
    _failure = value;
    onStalledChanged?.call();
  }

  void _setStalled(bool value) {
    if (_stalled == value) return;
    _stalled = value;
    onStalledChanged?.call();
  }

  Timer? _stallTimer;

  final StreamController<String> _out = StreamController.broadcast();
  bool _closed = false;
  int _columns = 80;
  int _rows = 24;
  PtyProcess? _pty;
  LocalShellBackend? _fallback;
  StreamSubscription<String>? _fallbackSub;
  Timer? _stableTimer;
  bool _keepAlive = false;

  /// 现在是不是已经退回本机 shell 了。
  bool get usingFallback => _fallback != null;

  @override
  String get label => usingFallback ? '本机' : 'Ubuntu';

  @override
  Stream<String> get output => _out.stream;

  @override
  bool get isRunning => _pty != null || (_fallback?.isRunning ?? false);

  void _emit(String text) {
    if (!_closed) _out.add(text);
  }

  @override
  Future<void> start({required int columns, required int rows}) async {
    _columns = columns;
    _rows = rows;
    if (_closed || isRunning) return;
    if (_fallback != null) return _fallback!.start(columns: columns, rows: rows);
    if (!runtime.shouldUseLinux) {
      if (runtime.localShellAllowed) return _startFallback(runtime.lastLaunchError);
      if (!runtime.usable) {
        // 环境没装（或被卸掉了）：不开本机 shell，如实说进不去。
        _setFailure(runtime.installed ? '这个安装包里缺少进入 Ubuntu 要用的文件，进不去。' : '运行环境还没有安装。');
        return;
      }
      // 装了但之前连续失败：这次是用户主动再试，照常往下走，不退回本机 shell。
    }
    _setFailure(null);

    final command = runtime.prootCommand(guestCommand: guestLoginShell, projectDir: projectDir, guestCwd: guestCwd);
    final startedAt = DateTime.now();
    final head = StringBuffer();
    final PtyProcess pty;
    try {
      pty = _spawn(command.executable, command.arguments, workingDirectory: projectDir, environment: command.environment, rows: rows, columns: columns);
    } catch (e) {
      runtime.recordLaunchFailure('伪终端里启动不了 PRoot：$e');
      return _afterFailure();
    }
    _pty = pty;
    _keepAlive = true;
    unawaited(runtime.acquireKeepAlive());
    // 只有“活过了头几秒”而且“真的有输出”才算启动成功：
    // 光是没退出不算——PRoot 卡住的时候进程也一直活着。
    var sawOutput = false;
    var stable = false;
    void maybeSuccess() {
      if (!sawOutput || !stable || !identical(_pty, pty)) return;
      runtime.recordLaunchSuccess();
      if (runtime.forceCompat) unawaited(runtime.rememberCompat('兼容模式下终端有了响应'));
    }

    _stableTimer = Timer(quickExit, () {
      stable = true;
      maybeSuccess();
    });
    _stallTimer?.cancel();
    _stallTimer = Timer(stallTimeout, () {
      if (!identical(_pty, pty) || sawOutput || _closed) return;
      _setStalled(true);
      runtime.recordStall(stallTimeout);
      _emit(
        '\r\n\x1b[33mUbuntu 环境 ${stallTimeout.inSeconds} 秒了还没有任何响应，多半是卡在启动这一步。\r\n'
        '下面有三个办法：改用兼容模式重试、${runtime.localShellAllowed ? '先退回本机 shell' : '改连 SSH 远程主机'}、去“运行环境”页做一键诊断。\x1b[0m\r\n',
      );
    });
    pty.output.cast<List<int>>().transform(const Utf8Decoder(allowMalformed: true)).listen((text) {
      if (text.isNotEmpty && !sawOutput) {
        sawOutput = true;
        _stallTimer?.cancel();
        if (identical(_pty, pty)) _setStalled(false);
        maybeSuccess();
      }
      if (head.length < 4000) head.write(text);
      _emit(text);
    }, onError: (_) {});
    unawaited(
      pty.exitCode.then((code) async {
        if (!identical(_pty, pty)) return;
        _pty = null;
        _stableTimer?.cancel();
        _stallTimer?.cancel();
        _setStalled(false);
        _releaseKeepAlive();
        final quick = DateTime.now().difference(startedAt) < quickExit;
        // 退出码可能比最后一段输出先到：等一下，让 PRoot 的报错进到日志里。
        await Future<void>.delayed(const Duration(milliseconds: 100));
        if (_closed) return;
        if (quick && code != 0) {
          runtime.recordLaunchFailure('PRoot 刚启动就退出了（退出码 $code）', output: head.toString());
          await _afterFailure();
        } else {
          _emit('\r\n[Ubuntu 会话已结束，退出码 $code。按回车重新进入]\r\n');
        }
      }),
    );
  }

  Future<void> _afterFailure() async {
    if (_closed) return;
    if (!runtime.localShellAllowed) {
      final reason = runtime.lastLaunchError ?? '没有拿到具体原因';
      _emit('\r\n\x1b[33mUbuntu 环境没能启动：$reason\x1b[0m\r\n');
      _setFailure(reason);
      return;
    }
    if (runtime.shouldUseLinux) {
      _emit('\r\n\x1b[33mUbuntu 环境没能启动：${runtime.lastLaunchError}\r\n按回车再试一次（会改用兼容模式）。\x1b[0m\r\n');
    } else {
      await _startFallback(runtime.lastLaunchError);
    }
  }

  Future<void> _startFallback(String? reason) async {
    if (reason != null) {
      _emit(
        '\r\n\x1b[33mUbuntu 环境连续启动失败，已退回手机自带的 sh。\r\n'
        '原因：$reason\r\n'
        '完整日志在侧边栏“运行环境”页，那里可以重新尝试。\x1b[0m\r\n\r\n',
      );
    }
    final fallback = _fallback = LocalShellBackend(projectDir, spawner: fallbackSpawner);
    _fallbackSub = fallback.output.listen(_emit);
    await fallback.start(columns: _columns, rows: _rows);
  }

  /// 把卡住的那个 PRoot 结束掉（不触发“会话已结束”的提示）。
  void _dropStalled() {
    final pty = _pty;
    _pty = null;
    _stableTimer?.cancel();
    _stallTimer?.cancel();
    _setStalled(false);
    try {
      pty?.kill();
    } catch (_) {}
    _releaseKeepAlive();
  }

  /// 启动失败后的“重试”：清掉失败计数，按原来的方式再进一次（没定下兼容模式的话就是默认模式）。
  Future<void> retry() async {
    if (_closed || _fallback != null) return;
    _dropStalled();
    runtime.resetLaunchFailures();
    runtime.log('用户选择：重试进入 Ubuntu');
    _emit('\r\n\x1b[2m正在重新进入 Ubuntu…\x1b[0m\r\n');
    await start(columns: _columns, rows: _rows);
  }

  /// “没有响应”/“启动失败”时的出路：结束卡住的进程，改用兼容模式再进一次。
  Future<void> retryCompat() async {
    if (_closed) return;
    _dropStalled();
    runtime.forceCompat = true;
    runtime.log('用户选择：改用兼容模式重试');
    _emit('\r\n\x1b[2m正在用兼容模式重新进入 Ubuntu…\x1b[0m\r\n');
    await start(columns: _columns, rows: _rows);
  }

  /// “没有响应”时的出路二（只在允许本机 shell 的平台上有）：结束卡住的进程，这个会话改用本机 shell。
  Future<void> switchToLocal() async {
    if (_closed || _fallback != null || !runtime.localShellAllowed) return;
    _dropStalled();
    runtime.log('用户选择：这个会话退回本机 shell');
    _emit('\r\n\x1b[33m已退回手机自带的 sh。Ubuntu 的问题可以到侧边栏“运行环境”页做一键诊断。\x1b[0m\r\n\r\n');
    await _startFallback(null);
  }

  void _releaseKeepAlive() {
    if (_keepAlive) {
      _keepAlive = false;
      unawaited(runtime.releaseKeepAlive());
    }
  }

  @override
  void write(String data) {
    if (_closed || data.isEmpty) return;
    final fallback = _fallback;
    if (fallback != null) return fallback.write(data);
    final pty = _pty;
    if (pty != null) return pty.write(utf8.encode(data));
    if (data.contains('\r') || data.contains('\n')) unawaited(start(columns: _columns, rows: _rows));
  }

  @override
  void resize(int columns, int rows) {
    _columns = columns;
    _rows = rows;
    _fallback?.resize(columns, rows);
    try {
      _pty?.resize(rows, columns);
    } catch (_) {
      // 进程刚好退出时调整大小会失败，忽略
    }
  }

  @override
  Future<void> close() async {
    _closed = true;
    _stableTimer?.cancel();
    _stallTimer?.cancel();
    final pty = _pty;
    _pty = null;
    try {
      pty?.kill();
    } catch (_) {}
    _releaseKeepAlive();
    await _fallbackSub?.cancel();
    await _fallback?.close();
    await _out.close();
  }
}
