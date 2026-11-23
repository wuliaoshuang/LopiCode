import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_pty/flutter_pty.dart';
import 'package:lopicode/terminal/terminal_session.dart';

/// flutter_pty 的真实伪终端。只在这个文件里碰原生库，
/// 原生库加载不了（例如单元测试的宿主机）时这里会抛错，调用方退回管道模式。
class FlutterPtyProcess implements PtyProcess {
  FlutterPtyProcess(this._pty);
  final Pty _pty;

  static PtyProcess spawn(
    String executable, {
    required String workingDirectory,
    required Map<String, String> environment,
    required int rows,
    required int columns,
  }) => FlutterPtyProcess(
    Pty.start(executable, workingDirectory: workingDirectory, environment: environment, rows: rows, columns: columns),
  );

  @override
  Stream<List<int>> get output => _pty.output;

  @override
  Future<int> get exitCode => _pty.exitCode;

  @override
  void write(List<int> data) => _pty.write(data is Uint8List ? data : Uint8List.fromList(data));

  @override
  void resize(int rows, int columns) => _pty.resize(rows, columns);

  @override
  void kill() => _pty.kill(ProcessSignal.sigkill);
}
