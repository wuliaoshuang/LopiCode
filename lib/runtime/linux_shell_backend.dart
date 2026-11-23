import 'dart:async';
import 'dart:convert';

import 'package:lopicode/runtime/linux_runtime.dart';
import 'package:lopicode/runtime/proot_command.dart';
import 'package:lopicode/terminal/pty_native.dart';
import 'package:lopicode/terminal/terminal_session.dart';

typedef PtyArgsSpawner =
    PtyProcess Function(
      String executable,
      List<String> arguments, {
      required String workingDirectory,
      required Map<String, String> environment,
      required int rows,
      required int columns,
    });

/// 终端后端：在伪终端里跑 PRoot，进到 Ubuntu 的 bash。
///
/// 起不来的时候不能把人卡在黑屏上：
/// - 第一次失败：屏幕上说明原因，按回车重试，重试会改用兼容模式；
/// - 连续失败到上限：退回手机自带的 sh，并告诉用户去“运行环境”页看日志。
class LinuxShellBackend implements TerminalBackend {
  LinuxShellBackend({
    required this.runtime,
    required this.projectDir,
    PtyArgsSpawner? spawner,
    this.fallbackSpawner,
    this.quickExit = const Duration(seconds: 3),
  }) : _spawn = spawner ?? FlutterPtyProcess.spawnWithArgs;

  final LinuxRuntime runtime;
  final String projectDir;
  final PtyArgsSpawner _spawn;
  final PtySpawner? fallbackSpawner;

  /// 启动后这么短时间内就非正常退出，算启动失败。
  final Duration quickExit;

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
    if (!runtime.shouldUseLinux) return _startFallback(runtime.lastLaunchError);

    final command = runtime.prootCommand(guestCommand: guestLoginShell, projectDir: projectDir);
    final startedAt = DateTime.now();
    final head = StringBuffer();
    final PtyProcess pty;
    try {
      pty = _spawn(
        command.executable,
        command.arguments,
        workingDirectory: projectDir,
        environment: command.environment,
        rows: rows,
        columns: columns,
      );
    } catch (e) {
      runtime.recordLaunchFailure('伪终端里启动不了 PRoot：$e');
      return _afterFailure();
    }
    _pty = pty;
    _keepAlive = true;
    unawaited(runtime.acquireKeepAlive());
    _stableTimer = Timer(quickExit, () {
      if (identical(_pty, pty)) runtime.recordLaunchSuccess();
    });
    pty.output.transform(const Utf8Decoder(allowMalformed: true)).listen((text) {
      if (head.length < 4000) head.write(text);
      _emit(text);
    }, onError: (_) {});
    unawaited(
      pty.exitCode.then((code) async {
        if (!identical(_pty, pty)) return;
        _pty = null;
        _stableTimer?.cancel();
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
