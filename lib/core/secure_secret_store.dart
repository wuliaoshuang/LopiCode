import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:lopicode/core/stores.dart';

/// 安全存储的最小接口：真实实现是 flutter_secure_storage，测试里换成假的。
abstract class SecureBackend {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// flutter_secure_storage：Android 上密钥由系统 Keystore 保管，值加密后存盘。
class FlutterSecureBackend implements SecureBackend {
  const FlutterSecureBackend([this._storage = const FlutterSecureStorage()]);
  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// API Key、GitHub Token、SSH 密码 / 私钥的存储。
///
/// 安全存储不可用（插件没注册、系统 Keystore 报错）时退回内存存储，
/// 并把 [persistent] 置为 false，界面会如实提示“重启后要重新填写”。
/// 任何情况下都不会把明文写进普通设置文件。
class SecureSecretStore implements SecretStore {
  SecureSecretStore([this._backend = const FlutterSecureBackend()]);

  final SecureBackend _backend;
  final MemorySecretStore _fallback = MemorySecretStore();
  bool _available = true;

  @override
  bool get persistent => _available;

  /// 启动时探测一次安全存储能不能用。
  Future<void> probe() async {
    try {
      await _backend.read('__probe__');
    } on MissingPluginException {
      _available = false;
    } on PlatformException {
      _available = false;
    }
  }

  @override
  Future<String?> read(String key) async {
    if (!_available) return _fallback.read(key);
    try {
      return await _backend.read(key);
    } on MissingPluginException {
      _available = false;
      return _fallback.read(key);
    } on PlatformException {
      return null; // 解不开（例如换了设备恢复的数据）就当没存过
    }
  }

  @override
  Future<void> write(String key, String value) async {
    if (!_available) return _fallback.write(key, value);
    try {
      await _backend.write(key, value);
    } on MissingPluginException {
      _available = false;
      await _fallback.write(key, value);
    } on PlatformException {
      // 这一次写不进安全存储：只留在内存里，并如实标成“不持久”。
      _available = false;
      await _fallback.write(key, value);
    }
  }

  @override
  Future<void> delete(String key) async {
    if (!_available) return _fallback.delete(key);
    try {
      await _backend.delete(key);
    } on MissingPluginException {
      _available = false;
      await _fallback.delete(key);
    } on PlatformException {
      // 删不掉就算了：下次读到解不开的值也会当作没存过
    }
  }
}
