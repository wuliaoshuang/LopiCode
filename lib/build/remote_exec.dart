import 'dart:typed_data';

/// SSH 构建机的抽象：在远程主机上跑一条构建命令、流式看日志、再把产物拉回来。
///
/// 这一版只有接口，没有实现：实现需要 dartssh2（SSH + SFTP），
/// 开发环境当时拿不到这个依赖包。接入时实现这个接口，
/// APK 打包页的“SSH 构建机”和终端页的“SSH 远程主机”都用它。
abstract class RemoteExec {
  /// 连接。密码 / 私钥从安全存储里取，不经过普通设置。
  Future<void> connect({
    required String host,
    required int port,
    required String user,
    String? password,
    String? privateKey,
  });

  /// 执行命令，逐块吐出 stdout / stderr，结束时返回退出码。
  Stream<String> run(String command, {void Function(int exitCode)? onExit});

  /// 通过 SFTP 下载一个文件。
  Future<Uint8List> download(String remotePath);

  Future<void> close();
}
