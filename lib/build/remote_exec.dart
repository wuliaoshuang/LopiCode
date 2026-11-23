import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

/// SSH 构建机的抽象：在远程主机上跑一条构建命令、流式看日志、再把产物拉回来。
/// 真实实现是 [DartSshRemoteExec]；测试里换成假的。
abstract class RemoteExec {
  /// 连接并登录。失败时抛出带中文说明的异常。
  Future<void> connect();

  /// 执行命令，stdout / stderr 一块一块交给 [onOutput]，结束后返回退出码
  /// （远端没给退出码，例如连接中途断开，返回 null）。
  Future<int?> run(String command, {required void Function(String chunk) onOutput});

  /// 通过 SFTP 上传一个文件（父目录要已存在）。
  Future<void> upload(String remotePath, List<int> bytes);

  /// 通过 SFTP 把远程文件下载到本机 [target]，返回字节数。
  Future<int> download(String remotePath, File target, {void Function(int received, int? total)? onProgress});

  Future<void> close();
}

/// 把一个参数安全地放进远程 sh 命令行。
String shellQuote(String value) => "'${value.replaceAll("'", "'\\''")}'";

class DartSshRemoteExec implements RemoteExec {
  DartSshRemoteExec(this._connect);

  /// 建立已登录的连接（含主机指纹核对）。
  final Future<SSHClient> Function() _connect;
  SSHClient? _client;
  SftpClient? _sftp;

  SSHClient get _c => _client ?? (throw StateError('还没连接'));

  @override
  Future<void> connect() async {
    _client ??= await _connect();
  }

  @override
  Future<int?> run(String command, {required void Function(String chunk) onOutput}) async {
    final session = await _c.execute(command);
    const decoder = Utf8Decoder(allowMalformed: true);
    final out = session.stdout.cast<List<int>>().transform(decoder).listen(onOutput);
    final err = session.stderr.cast<List<int>>().transform(decoder).listen(onOutput);
    try {
      await session.done;
      await out.asFuture<void>().catchError((_) {});
      await err.asFuture<void>().catchError((_) {});
      return session.exitCode;
    } finally {
      await out.cancel();
      await err.cancel();
    }
  }

  Future<SftpClient> _sftpClient() async => _sftp ??= await _c.sftp();

  @override
  Future<void> upload(String remotePath, List<int> bytes) async {
    final sftp = await _sftpClient();
    final file = await sftp.open(remotePath, mode: SftpFileOpenMode.create | SftpFileOpenMode.truncate | SftpFileOpenMode.write);
    try {
      await file.writeBytes(bytes is Uint8List ? bytes : Uint8List.fromList(bytes));
    } finally {
      await file.close();
    }
  }

  @override
  Future<int> download(String remotePath, File target, {void Function(int received, int? total)? onProgress}) async {
    final sftp = await _sftpClient();
    final file = await sftp.open(remotePath);
    final sink = target.openWrite();
    var received = 0;
    try {
      final total = (await file.stat()).size;
      await for (final chunk in file.read()) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
    } finally {
      await sink.close();
      await file.close();
    }
    return received;
  }

  @override
  Future<void> close() async {
    unawaited(_sftp?.close()); // 关连接不等它：对端没响应时不能卡住
    _sftp = null;
    unawaited(_client?.close()); // 关连接不等它：对端没响应时不能卡住
    _client = null;
  }
}
