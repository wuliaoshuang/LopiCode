import 'dart:convert';
import 'dart:io';

/// 密钥存储接口。API Key、GitHub Token、SSH 密码 / 私钥只走这里，
/// 永远不进普通设置文件，也不进日志。
abstract class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);

  /// 是否能在应用重启后保留（用于界面如实提示）。
  bool get persistent;
}

/// 只存在内存里的实现：测试用，也是安全存储插件不可用时的退路。
class MemorySecretStore implements SecretStore {
  final Map<String, String> _data = {};

  @override
  bool get persistent => false;

  @override
  Future<String?> read(String key) async => _data[key];

  @override
  Future<void> write(String key, String value) async => _data[key] = value;

  @override
  Future<void> delete(String key) async => _data.remove(key);
}

/// 普通（非敏感）设置：一个 JSON 文件。
class SettingsStore {
  SettingsStore(this.file);
  final File file;
  Map<String, dynamic> _data = {};

  Future<void> load() async {
    try {
      if (await file.exists()) {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map<String, dynamic>) _data = decoded;
      }
    } catch (_) {
      _data = {};
    }
  }

  T? get<T>(String key) {
    final v = _data[key];
    return v is T ? v : null;
  }

  String getString(String key, [String fallback = '']) =>
      get<String>(key) ?? fallback;

  bool getBool(String key, [bool fallback = false]) =>
      get<bool>(key) ?? fallback;

  Future<void> set(String key, Object? value) async {
    if (value == null) {
      _data.remove(key);
    } else {
      _data[key] = value;
    }
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(_data));
  }
}

/// 设置项的键名集中在这里。
class SettingKeys {
  static const agentBaseUrl = 'agent.baseUrl';
  static const agentModel = 'agent.model';
  static const themeMode = 'ui.themeMode'; // system / light / dark
  static const githubOwner = 'github.owner';
  static const githubRepo = 'github.repo';
  static const githubRef = 'github.ref';
  static const githubWorkflow = 'github.workflow';
  static const sshHost = 'ssh.host';
  static const sshPort = 'ssh.port';
  static const sshUser = 'ssh.user';
  static const sshAuth = 'ssh.auth'; // password / key
  static const sshBuildCommand = 'ssh.buildCommand';
  static const sshBuildOutput = 'ssh.buildOutput';
  static const lastProject = 'ui.lastProject';
  static String autoApprove(String projectId) => 'project.$projectId.autoApprove';
}

class SecretKeys {
  static const agentApiKey = 'agent_api_key';
  static const githubToken = 'github_token';
  static const sshPassword = 'ssh_password';
  static const sshPrivateKey = 'ssh_private_key';
}
