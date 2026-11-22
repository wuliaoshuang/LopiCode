import 'package:flutter/services.dart';
import 'package:lopicode/core/stores.dart';

/// 走 MainActivity 里的 `lopicode/secrets` 通道：Android Keystore（AES-256-GCM）
/// 加密后存盘。通道不可用（非 Android、测试环境）时退回内存存储，
/// 并把 [persistent] 置为 false，界面会如实提示“重启后要重新填写”。
class KeystoreSecretStore implements SecretStore {
  static const MethodChannel _channel = MethodChannel('lopicode/secrets');
  final MemorySecretStore _fallback = MemorySecretStore();
  bool _available = true;

  @override
  bool get persistent => _available;

  /// 启动时探测一次通道是否可用。
  Future<void> probe() async {
    try {
      await _channel.invokeMethod<String>('read', {'key': '__probe__'});
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
      return await _channel.invokeMethod<String>('read', {'key': key});
    } on PlatformException {
      return null; // 解不开（例如换了设备恢复的数据）就当没存过
    } on MissingPluginException {
      _available = false;
      return _fallback.read(key);
    }
  }

  @override
  Future<void> write(String key, String value) async {
    if (!_available) return _fallback.write(key, value);
    try {
      await _channel.invokeMethod<void>('write', {'key': key, 'value': value});
    } on MissingPluginException {
      _available = false;
      await _fallback.write(key, value);
    }
  }

  @override
  Future<void> delete(String key) async {
    if (!_available) return _fallback.delete(key);
    try {
      await _channel.invokeMethod<void>('delete', {'key': key});
    } on MissingPluginException {
      _available = false;
      await _fallback.delete(key);
    }
  }
}
