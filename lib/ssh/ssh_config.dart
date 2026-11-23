import 'package:lopicode/core/stores.dart';

/// 一台 SSH 主机的连接信息（不含密码 / 私钥，那些在安全存储里）。
/// 终端的 SSH 会话和 SSH 构建机共用这一份。
class SshConfig {
  const SshConfig({required this.host, this.port = 22, required this.user, this.useKey = false});

  final String host;
  final int port;
  final String user;

  /// true = 私钥登录，false = 密码登录。
  final bool useKey;

  String get hostPort => '$host:$port';
  String get display => port == 22 ? '$user@$host' : '$user@$host:$port';
  bool get isComplete => host.isNotEmpty && user.isNotEmpty && port > 0 && port < 65536;

  static SshConfig load(SettingsStore settings) => SshConfig(
    host: settings.getString(SettingKeys.sshHost),
    port: settings.get<int>(SettingKeys.sshPort) ?? 22,
    user: settings.getString(SettingKeys.sshUser),
    useKey: settings.getString(SettingKeys.sshAuth) == 'key',
  );

  Future<void> save(SettingsStore settings) async {
    await settings.set(SettingKeys.sshHost, host);
    await settings.set(SettingKeys.sshPort, port);
    await settings.set(SettingKeys.sshUser, user);
    await settings.set(SettingKeys.sshAuth, useKey ? 'key' : 'password');
  }

  /// 校验表单输入，返回错误提示；没问题返回 null。
  static String? validate({required String host, required String port, required String user}) {
    if (host.trim().isEmpty) return '请填写主机地址';
    if (host.trim().contains(RegExp(r'[\s/@]'))) return '主机地址只填域名或 IP，不带用户名和路径';
    final p = int.tryParse(port.trim());
    if (p == null || p <= 0 || p > 65535) return '端口要在 1 到 65535 之间';
    if (user.trim().isEmpty) return '请填写用户名';
    return null;
  }
}

enum HostKeyStatus { trusted, unknown, changed }

/// 记住的主机指纹（首次连接时由用户确认，之后每次核对）。
class KnownHosts {
  KnownHosts(this._settings);
  final SettingsStore _settings;

  Map<String, String> _all() {
    final raw = _settings.get<Map<String, dynamic>>(SettingKeys.sshKnownHosts) ?? const {};
    return {for (final e in raw.entries) e.key: '${e.value}'};
  }

  String? fingerprintOf(String hostPort) => _all()[hostPort];

  HostKeyStatus check(String hostPort, String fingerprint) {
    final known = fingerprintOf(hostPort);
    if (known == null) return HostKeyStatus.unknown;
    return known == fingerprint ? HostKeyStatus.trusted : HostKeyStatus.changed;
  }

  Future<void> trust(String hostPort, String fingerprint) =>
      _settings.set(SettingKeys.sshKnownHosts, _all()..[hostPort] = fingerprint);

  Future<void> forget(String hostPort) => _settings.set(SettingKeys.sshKnownHosts, _all()..remove(hostPort));
}
