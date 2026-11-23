import 'dart:async';
import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';
import 'package:lopicode/terminal/terminal_session.dart';

/// 远程主机上的交互式 shell（带伪终端）。
class SshShellBackend implements TerminalBackend {
  SshShellBackend({required this.connect, required this.hostLabel});

  /// 建立连接（含指纹确认、登录）。失败时抛出带中文说明的异常。
  final Future<SSHClient> Function() connect;
  final String hostLabel;

  final StreamController<String> _out = StreamController.broadcast();
  SSHClient? _client;
  SSHSession? _shell;
  bool _closed = false;
  bool _connecting = false;
  int _columns = 80;
  int _rows = 24;

  @override
  String get label => 'SSH';

  @override
  Stream<String> get output => _out.stream;

  @override
  bool get isRunning => _shell != null;

  void _emit(String text) {
    if (!_closed) _out.add(text);
  }

  @override
  Future<void> start({required int columns, required int rows}) async {
    _columns = columns;
    _rows = rows;
    if (_closed || _connecting || isRunning) return;
    _connecting = true;
    _emit('正在连接 $hostLabel …\r\n');
    try {
      final client = await connect();
      if (_closed) {
        unawaited(client.close()); // 关连接不等它：对端没响应时不能卡住
        return;
      }
      final shell = await client.shell(
        pty: SSHPtyConfig(type: 'xterm-256color', width: _columns, height: _rows),
      );
      _client = client;
      _shell = shell;
      const decoder = Utf8Decoder(allowMalformed: true);
      shell.stdout.cast<List<int>>().transform(decoder).listen(_emit, onError: (_) {});
      shell.stderr.cast<List<int>>().transform(decoder).listen(_emit, onError: (_) {});
      unawaited(
        shell.done.whenComplete(() {
          if (identical(_shell, shell)) {
            _shell = null;
            _client = null;
            client.close();
            _emit('\r\n[连接已断开。按回车重新连接]\r\n');
          }
        }),
      );
    } catch (e) {
      _emit('\x1b[31m$e\x1b[0m\r\n[按回车重试]\r\n');
    } finally {
      _connecting = false;
    }
  }

  @override
  void write(String data) {
    if (_closed || data.isEmpty) return;
    final shell = _shell;
    if (shell != null) {
      shell.write(utf8.encode(data));
    } else if (!_connecting && (data.contains('\r') || data.contains('\n'))) {
      unawaited(start(columns: _columns, rows: _rows));
    }
  }

  @override
  void resize(int columns, int rows) {
    _columns = columns;
    _rows = rows;
    try {
      _shell?.resizeTerminal(columns, rows);
    } catch (_) {
      // 连接刚断开时会失败，忽略
    }
  }

  @override
  Future<void> close() async {
    _closed = true;
    _shell?.close();
    _shell = null;
    unawaited(_client?.close()); // 关连接不等它：对端没响应时不能卡住
    _client = null;
    await _out.close();
  }
}
