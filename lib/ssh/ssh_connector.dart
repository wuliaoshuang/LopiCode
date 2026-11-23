import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:lopicode/core/stores.dart';
import 'package:lopicode/ssh/ssh_config.dart';

/// 第一次连一台主机时问用户：这个指纹信不信。
typedef HostKeyPrompt = Future<bool> Function(SshConfig config, String keyType, String fingerprint);

/// 连接失败，[message] 是可以直接给用户看的中文原因。
class SshConnectException implements Exception {
  SshConnectException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// 主机指纹核对：认识且一致 → 放行；没见过 → 问用户，同意才记住；
/// 和记住的不一样 → 一律拒绝（可能是中间人，也可能是服务器重装）。
class HostKeyVerifier {
  HostKeyVerifier({required this.config, required this.knownHosts, this.prompt});
  final SshConfig config;
  final KnownHosts knownHosts;
  final HostKeyPrompt? prompt;

  /// 拒绝的原因（给界面看）；放行时为 null。
  String? rejection;

  Future<bool> verify(String keyType, String fingerprint) async {
    switch (knownHosts.check(config.hostPort, fingerprint)) {
      case HostKeyStatus.trusted:
        return true;
      case HostKeyStatus.changed:
        rejection =
            '${config.hostPort} 的主机指纹和上次记住的不一样，已拒绝连接。'
            '如果服务器确实重装过，到“SSH 主机设置”里点“忘记这台主机的指纹”后再连。';
        return false;
      case HostKeyStatus.unknown:
        final ask = prompt;
        if (ask == null) {
          rejection = '第一次连接 ${config.hostPort}，需要先确认主机指纹。请先在终端里新建一个 SSH 会话连一次。';
          return false;
        }
        if (await ask(config, keyType, fingerprint)) {
          await knownHosts.trust(config.hostPort, fingerprint);
          return true;
        }
        rejection = '你没有信任这台主机的指纹，连接已取消。';
        return false;
    }
  }
}

/// 把各种底层错误翻成一句用户看得懂的话。
String describeSshError(Object error, SshConfig config) {
  if (error is SshConnectException) return error.message;
  if (error is SSHAuthFailError || error is SSHAuthAbortError) {
    return config.useKey ? '登录被拒绝：服务器不接受这把私钥（或用户名不对）。' : '登录被拒绝：用户名或密码不对。';
  }
  if (error is SSHKeyDecryptError) return '私钥解不开：密码短语不对。';
  if (error is SSHKeyDecodeError || error is FormatException || error is UnsupportedError) {
    return '私钥格式不对：请粘贴完整的 PEM / OpenSSH 私钥（含 BEGIN 和 END 两行）。';
  }
  if (error is TimeoutException) return '连接 ${config.hostPort} 超时：检查地址、端口和网络。';
  if (error is SocketException) return '连不上 ${config.hostPort}：${error.osError?.message ?? error.message}';
  if (error is SSHHostkeyError) return '主机指纹校验没通过，连接已中断。';
  if (error is SSHError) return 'SSH 出错：$error';
  return '连接失败：$error';
}

/// 建立一条已登录的 SSH 连接。密码 / 私钥从安全存储里读，不落进任何日志。
Future<SSHClient> connectSsh({
  required SshConfig config,
  required SecretStore secrets,
  required KnownHosts knownHosts,
  HostKeyPrompt? onUnknownHost,
  Duration timeout = const Duration(seconds: 15),
}) async {
  if (!config.isComplete) throw SshConnectException('还没填 SSH 主机信息。');
  final verifier = HostKeyVerifier(config: config, knownHosts: knownHosts, prompt: onUnknownHost);
  SSHClient? client;
  try {
    List<SSHKeyPair>? identities;
    String? password;
    if (config.useKey) {
      final pem = await secrets.read(SecretKeys.sshPrivateKey);
      if (pem == null || pem.trim().isEmpty) throw SshConnectException('还没保存私钥。');
      final passphrase = await secrets.read(SecretKeys.sshKeyPassphrase);
      identities = SSHKeyPair.fromPem(pem, passphrase == null || passphrase.isEmpty ? null : passphrase);
    } else {
      password = await secrets.read(SecretKeys.sshPassword);
      if (password == null || password.isEmpty) throw SshConnectException('还没保存密码。');
    }
    final socket = await SSHSocket.connect(config.host, config.port, timeout: timeout);
    client = SSHClient(
      socket,
      username: config.user,
      identities: identities,
      onPasswordRequest: password == null ? null : () => password,
      onVerifyHostKey: (type, fingerprint) => verifier.verify(type, utf8.decode(fingerprint)),
    );
    await client.authenticated.timeout(timeout + const Duration(seconds: 60));
    return client;
  } catch (e) {
    client?.close();
    throw SshConnectException(verifier.rejection ?? describeSshError(e, config));
  }
}
