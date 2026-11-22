import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// 终端后端的接口。v1 只有“本机 shell（管道）”一种实现；
/// PTY（flutter_pty）和 SSH（dartssh2）接进来时实现同一个接口即可。
abstract class TerminalBackend {
  String get label;
  Stream<String> get output;
  Future<void> start();
  void writeLine(String line);

  /// 中断当前命令。
  void interrupt();

  /// 结束输入（Ctrl+D）。
  void sendEof();
  Future<void> close();
  bool get isRunning;
}

/// 本机 shell，走普通管道（不是 PTY）：
/// 能跑一条条命令并看输出；不支持 vim / top 这类全屏程序，没有 Tab 补全。
/// 管道模式下没法只中断前台命令，所以“中断”＝结束这个 shell 再开一个新的。
class PipeShellBackend implements TerminalBackend {
  PipeShellBackend(this.workingDirectory);
  final String workingDirectory;

  Process? _process;
  final StreamController<String> _out = StreamController.broadcast();
  bool _closed = false;

  static String get shellPath => Platform.isAndroid ? '/system/bin/sh' : '/bin/sh';

  @override
  String get label => '本机';

  @override
  Stream<String> get output => _out.stream;

  @override
  bool get isRunning => _process != null;

  @override
  Future<void> start() async {
    try {
      final process = await Process.start(
        shellPath,
        const [],
        workingDirectory: workingDirectory,
        environment: {'TERM': 'dumb', 'HOME': workingDirectory},
      );
      _process = process;
      const decoder = Utf8Decoder(allowMalformed: true);
      process.stdout.transform(decoder).listen(_emit);
      process.stderr.transform(decoder).listen(_emit);
      unawaited(process.exitCode.then((code) {
        if (identical(_process, process)) {
          _process = null;
          _emit('\n[shell 已退出，退出码 $code。发一条命令会重新启动]\n');
        }
      }));
    } on ProcessException catch (e) {
      _emit('无法启动 shell：${e.message}\n');
    }
  }

  void _emit(String text) {
    if (!_closed) _out.add(text);
  }

  @override
  void writeLine(String line) {
    final process = _process;
    if (process == null) {
      unawaited(start().then((_) => _process?.stdin.writeln(line)));
      return;
    }
    process.stdin.writeln(line);
  }

  @override
  void interrupt() {
    final process = _process;
    if (process == null) return;
    _process = null;
    process.kill(ProcessSignal.sigkill);
    _emit('\n^C  已中断并重开 shell（当前目录回到项目根目录）\n');
    unawaited(start());
  }

  @override
  void sendEof() {
    unawaited(_process?.stdin.close());
  }

  @override
  Future<void> close() async {
    _closed = true;
    final process = _process;
    _process = null;
    process?.kill(ProcessSignal.sigkill);
    await _out.close();
  }
}

/// 一个终端会话：后端 + 屏幕上的文字缓冲 + 命令历史。
class TerminalSession extends ChangeNotifier {
  TerminalSession({required this.title, required this.backend});

  String title;
  final TerminalBackend backend;
  final StringBuffer _buffer = StringBuffer();
  final List<String> history = [];
  StreamSubscription<String>? _sub;
  bool _started = false;

  static const int maxChars = 120000;
  static final RegExp _ansi = RegExp(r'\x1B\[[0-9;?]*[ -/]*[@-~]|\x1B\][^\x07]*\x07|\x1B[@-Z\\-_]');

  String get text => _buffer.toString();

  Future<void> ensureStarted() async {
    if (_started) return;
    _started = true;
    _sub = backend.output.listen(append);
    await backend.start();
  }

  /// 往屏幕上追加文字（去掉 ANSI 控制序列；这个基础终端不解释颜色和光标移动）。
  void append(String raw) {
    final clean = raw.replaceAll(_ansi, '').replaceAll('\r\n', '\n').replaceAll('\r', '');
    if (clean.isEmpty) return;
    _buffer.write(clean);
    if (_buffer.length > maxChars) {
      final keep = _buffer.toString();
      _buffer
        ..clear()
        ..write(keep.substring(keep.length - maxChars ~/ 2));
    }
    notifyListeners();
  }

  void run(String line) {
    if (line.trim().isNotEmpty && (history.isEmpty || history.last != line)) history.add(line);
    append('\$ $line\n');
    unawaited(ensureStarted().then((_) => backend.writeLine(line)));
  }

  void interrupt() => backend.interrupt();
  void sendEof() => backend.sendEof();

  void clear() {
    _buffer.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    unawaited(backend.close());
    super.dispose();
  }
}
