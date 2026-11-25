import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:lopicode/terminal/pty_native.dart';
import 'package:xterm/xterm.dart';

/// 终端后端：往里写键盘输入的原始字节，读出要画到屏幕上的原始输出。
/// 终端仿真（光标、颜色、全屏程序）由 xterm 负责，后端只管收发。
abstract class TerminalBackend {
  /// 会话标签上的名字前缀，例如“本机”“SSH”。
  String get label;

  Stream<String> get output;
  Future<void> start({required int columns, required int rows});
  void write(String data);
  void resize(int columns, int rows);
  Future<void> close();
  bool get isRunning;
}

/// 后端里跑的是带行编辑的 shell（Ubuntu 里的 bash）时实现这个：“清屏”就可以发 Ctrl+L，
/// 让 shell 自己在第一行重画提示符，正打到一半的命令原样留着、不会被执行。
abstract interface class LineEditingShell {
  /// 现在是不是真的在跑这种 shell（退回本机 sh 以后不是）。
  bool get redrawsOnCtrlL;
}

/// 去掉开头的回车、换行（只认 `\r`、`\n` 两个字符，别的一律不动）。
/// 屏幕上还一个字都没有的时候，开头的空行没有任何意义，只会把第一行提示符往下顶。
String dropLeadingLineBreaks(String text) {
  var i = 0;
  while (i < text.length && (text.codeUnitAt(i) == 0x0d || text.codeUnitAt(i) == 0x0a)) {
    i++;
  }
  return i == 0 ? text : text.substring(i);
}

/// 一个跑在伪终端里的进程（flutter_pty 的抽象，测试里可以换成假的）。
abstract class PtyProcess {
  Stream<List<int>> get output;
  Future<int> get exitCode;
  void write(List<int> data);
  void resize(int rows, int columns);
  void kill();
}

typedef PtySpawner = PtyProcess Function(String executable, {required String workingDirectory, required Map<String, String> environment, required int rows, required int columns});

enum LocalShellMode { none, pty, pipe }

/// 本机 shell。优先开真正的伪终端（flutter_pty）：有回显、行编辑、Ctrl+C，
/// 能跑 vi、top 这类全屏程序。伪终端开不出来时退回管道模式（一次一条命令），
/// 并在屏幕上如实说明。
class LocalShellBackend implements TerminalBackend {
  LocalShellBackend(this.workingDirectory, {PtySpawner? spawner, this.allowPipeFallback = true}) : _spawn = spawner ?? FlutterPtyProcess.spawn;

  final String workingDirectory;
  final PtySpawner _spawn;
  final bool allowPipeFallback;

  final StreamController<String> _out = StreamController.broadcast();
  bool _closed = false;
  LocalShellMode mode = LocalShellMode.none;
  int _columns = 80;
  int _rows = 24;

  PtyProcess? _pty;
  Process? _pipe;
  final StringBuffer _line = StringBuffer();

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
  String get label => '本机';

  @override
  Stream<String> get output => _out.stream;

  @override
  bool get isRunning => _pty != null || _pipe != null;

  void _emit(String text) {
    if (!_closed) _out.add(text);
  }

  Map<String, String> get _environment => {'HOME': workingDirectory, 'TERM': 'xterm-256color', 'PATH': ?Platform.environment['PATH'], 'TMPDIR': ?Platform.environment['TMPDIR']};

  @override
  Future<void> start({required int columns, required int rows}) async {
    _columns = columns;
    _rows = rows;
    if (_closed || isRunning) return;
    try {
      final pty = _spawn(shellPath, workingDirectory: workingDirectory, environment: _environment, rows: rows, columns: columns);
      _pty = pty;
      mode = LocalShellMode.pty;
      pty.output.cast<List<int>>().transform(const Utf8Decoder(allowMalformed: true)).listen(_emit, onError: (_) {});
      unawaited(
        pty.exitCode.then((code) {
          if (identical(_pty, pty)) {
            _pty = null;
            _emit('\r\n[shell 已退出，退出码 $code。按回车重新启动]\r\n');
          }
        }),
      );
      return;
    } catch (_) {
      // 原生伪终端库加载不了或创建失败：下面退回管道模式。
      if (!allowPipeFallback) {
        mode = LocalShellMode.none;
        _emit('无法启动伪终端。\r\n');
        return;
      }
    }
    await _startPipe(announce: mode != LocalShellMode.pipe);
  }

  Future<void> _startPipe({bool announce = false}) async {
    mode = LocalShellMode.pipe;
    if (announce) {
      _emit('\x1b[33m已退回基础模式：一次一条命令。\nvi、top 等全屏程序不可用。\x1b[0m\r\n');
    }
    try {
      final process = await Process.start(shellPath, const [], workingDirectory: workingDirectory, environment: {'TERM': 'dumb', 'HOME': workingDirectory});
      _pipe = process;
      const decoder = Utf8Decoder(allowMalformed: true);
      void show(String text) => _emit(text.replaceAll('\r\n', '\n').replaceAll('\n', '\r\n'));
      process.stdout.transform(decoder).listen(show, onError: (_) {});
      process.stderr.transform(decoder).listen(show, onError: (_) {});
      unawaited(
        process.exitCode.then((code) {
          if (identical(_pipe, process)) {
            _pipe = null;
            _emit('\r\n[shell 已退出，退出码 $code。按回车重新启动]\r\n');
          }
        }),
      );
      _emit('\$ ');
    } on ProcessException catch (e) {
      _emit('无法启动 shell：${e.message}\r\n');
    }
  }

  @override
  void write(String data) {
    if (_closed || data.isEmpty) return;
    final pty = _pty;
    if (pty != null) {
      pty.write(utf8.encode(data));
      return;
    }
    if (mode == LocalShellMode.pty || mode == LocalShellMode.none) {
      // 伪终端里的 shell 已经退出：回车重新开一个。
      if (data.contains('\r') || data.contains('\n')) unawaited(start(columns: _columns, rows: _rows));
      return;
    }
    _writePipe(data);
  }

  /// 管道模式没有内核的行规程，这里自己做最小的一套：回显、退格、回车提交、Ctrl+C、Ctrl+D。
  void _writePipe(String data) {
    for (final rune in data.runes) {
      switch (rune) {
        case 0x0d || 0x0a:
          final line = _line.toString();
          _line.clear();
          _emit('\r\n');
          final process = _pipe;
          if (process == null) {
            unawaited(_startPipe());
          } else {
            // 没有提示符可读：每条命令后面跟一句 printf，自己补一个。
            process.stdin.writeln(line);
            process.stdin.writeln(r'printf "$ "');
          }
        case 0x7f || 0x08:
          final text = _line.toString();
          if (text.isNotEmpty) {
            final chars = text.runes.toList()..removeLast();
            _line
              ..clear()
              ..write(String.fromCharCodes(chars));
            _emit('\b \b');
          }
        case 0x03:
          _line.clear();
          final process = _pipe;
          _pipe = null;
          process?.kill(ProcessSignal.sigkill);
          _emit('^C\r\n\x1b[2m已中断并重开 shell（当前目录回到项目根目录）\x1b[0m\r\n');
          unawaited(_startPipe());
        case 0x04:
          unawaited(_pipe?.stdin.close());
        case 0x0c:
          // Ctrl+L：清屏，在第一行重画提示符和正打到一半的那行
          _emit('\x1b[H\x1b[2J\$ $_line');
        case 0x1b:
          return; // 方向键等转义序列在基础模式下不处理
        default:
          if (rune >= 0x20 || rune == 0x09) {
            final ch = String.fromCharCode(rune);
            _line.write(ch);
            _emit(ch);
          }
      }
    }
  }

  @override
  void resize(int columns, int rows) {
    _columns = columns;
    _rows = rows;
    try {
      _pty?.resize(rows, columns);
    } catch (_) {
      // 进程刚好退出时调整大小会失败，忽略
    }
  }

  @override
  Future<void> close() async {
    _closed = true;
    final pty = _pty;
    _pty = null;
    try {
      pty?.kill();
    } catch (_) {}
    final pipe = _pipe;
    _pipe = null;
    final pipeExit = pipe?.exitCode;
    pipe?.kill(ProcessSignal.sigkill);
    if (pipeExit != null) await pipeExit.timeout(const Duration(seconds: 2), onTimeout: () => -1);
    await _out.close();
  }
}

/// 一个终端会话：后端 + xterm 的屏幕状态。
class TerminalSession {
  TerminalSession({required this.title, required this.backend, int maxLines = 5000}) : terminal = Terminal(maxLines: maxLines) {
    terminal.onOutput = _fromKeyboard;
    terminal.onResize = (width, height, _, _) => backend.resize(width, height);
  }

  String title;
  final TerminalBackend backend;
  final Terminal terminal;
  StreamSubscription<String>? _sub;
  bool _started = false;

  /// 按键行上的 Ctrl 是“粘滞”的：点一下，下一个字母变成控制字符。
  bool get ctrlArmed => _ctrlArmed;
  bool _ctrlArmed = false;

  /// Ctrl 的点亮状态变了：终端列表（[TerminalsNotifier]）接这个回调，通知终端页重画。
  void Function()? onChanged;

  void toggleCtrl() {
    _ctrlArmed = !_ctrlArmed;
    onChanged?.call();
  }

  /// 屏幕上（含回滚区）的纯文字，测试和“复制全部”用。
  String get text => terminal.buffer.getText().trimRight();

  /// 屏幕还是空的（刚开、或刚点过“清屏”）：这时后端送来的开头空行不上屏，第一行就是提示符。
  bool _blank = true;

  void _fromBackend(String data) {
    if (_blank) {
      data = dropLeadingLineBreaks(data);
      if (data.isEmpty) return;
      _blank = false;
    }
    terminal.write(data);
  }

  Future<void> ensureStarted() async {
    if (_started) return;
    _started = true;
    _sub = backend.output.listen(_fromBackend, onError: (_) {});
    await backend.start(columns: terminal.viewWidth, rows: terminal.viewHeight);
  }

  /// 直接往屏幕上写文字（说明、Agent 命令的回显），不经过后端。
  void append(String raw) {
    if (raw.isEmpty) return;
    _blank = false;
    terminal.write(raw.replaceAll('\r\n', '\n').replaceAll('\n', '\r\n'));
  }

  void _fromKeyboard(String data) {
    if (_ctrlArmed) {
      _ctrlArmed = false;
      onChanged?.call();
      if (data.length == 1) {
        final control = controlCharFor(data);
        if (control != null) {
          backend.write(control);
          return;
        }
      }
    }
    backend.write(data);
  }

  /// 字母对应的控制字符（c → ^C），不是字母返回 null。
  static String? controlCharFor(String char) {
    final code = char.toUpperCase().codeUnitAt(0);
    if (code >= 0x40 && code <= 0x5f) return String.fromCharCode(code - 0x40);
    return null;
  }

  /// 发原始字符（符号键、粘贴）。
  void sendText(String text) => _fromKeyboard(text);

  /// 发一个功能键；方向键会按当前模式（普通 / 应用光标）编码。
  void sendKey(TerminalKey key, {bool ctrl = false}) {
    final armed = _ctrlArmed;
    if (armed) {
      _ctrlArmed = false;
      onChanged?.call();
    }
    terminal.keyInput(key, ctrl: ctrl || armed);
  }

  /// 输入一行并回车。
  void run(String line) {
    unawaited(ensureStarted().then((_) => backend.write('$line\r')));
  }

  /// 清屏：屏幕和回滚区都清掉，光标回第一行，再让 shell 把提示符重画出来。
  /// - Ubuntu 的 bash：发 Ctrl+L，它自己在第一行重画，正打到一半的命令还在、不会被执行；
  /// - 其他后端（SSH、桌面调试的本机 shell）不确定认不认 Ctrl+L，照旧发回车；回车带出来的那个空行不上屏。
  void clear() {
    terminal.write('\x1b[2J\x1b[3J\x1b[H');
    _blank = true;
    if (!backend.isRunning) return;
    final Object b = backend;
    backend.write(b is LineEditingShell && b.redrawsOnCtrlL ? '\x0c' : '\r');
  }

  void dispose() {
    onChanged = null;
    unawaited(_sub?.cancel());
    unawaited(backend.close());
  }
}
