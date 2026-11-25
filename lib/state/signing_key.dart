// 本地打包用的签名钥匙（全应用一把）。
//
// 为什么全应用一把、不是每个工作区一把：安卓认“同一个签名者”才让升级包覆盖安装；她打出来的所有应用都是她一个人的，
// 一把钥匙备份一次就够，换手机 / 重装 LopiCode 后导入一次全部应用都能接着升级。每个工作区一把的话要备份很多份，漏一份那个应用就升不了级。
//
// 钥匙本体只在两处：内存里的 [SigningKeyNotifier._key]、安全存储（SecretKeys.apkSigningKey）。
// 状态里只有“指纹 + 生成时间”这类能给人看的东西；口令哪儿都不存；报错里不带钥匙和口令。
//
// 防并发 / 防销毁后写：生成、导入各自同一时间只有一次（进行中的 Future 复用）；每次换钥匙换一个代次，
// `await` 回来代次对不上或应用已销毁就不写状态。
import 'dart:async';

import 'package:lopicode/apkpack/apk_pack_contract.dart';
import 'package:lopicode/build/local_pack_backend.dart';
import 'package:lopicode/core/crash_log.dart';
import 'package:lopicode/core/stores.dart';
import 'package:lopicode/state/app_providers.dart';
import 'package:riverpod/riverpod.dart';

/// 证书里写的名字（只是个标签，装机时不显示）。
const String kSigningKeyCommonName = 'LopiCode App Key';

/// 备份口令在界面上的最短长度。
const int kKeyPassphraseMin = 8;

enum SigningKeyBusy { none, generating, importing }

class SigningKeyState {
  const SigningKeyState({this.loaded = false, this.fingerprint, this.createdAt, this.busy = SigningKeyBusy.none, this.error});

  /// 安全存储读过了没有。
  final bool loaded;

  /// 证书 SHA-256（小写十六进制）；null ＝ 还没有钥匙。
  final String? fingerprint;
  final DateTime? createdAt;
  final SigningKeyBusy busy;

  /// 上一次读 / 生成 / 导入没成的原因（大白话）。
  final String? error;

  bool get hasKey => fingerprint != null;

  /// 指纹前 8 位，给人对一眼用。
  String get shortFingerprint => fingerprint == null ? '' : (fingerprint!.length > 8 ? fingerprint!.substring(0, 8) : fingerprint!);
}

/// 钥匙操作没成：[message] 直接给用户看。
class SigningKeyException implements Exception {
  const SigningKeyException(this.message);
  final String message;
  @override
  String toString() => message;
}

class SigningKeyNotifier extends Notifier<SigningKeyState> {
  late SecretStore _secrets;
  late SigningKeyState _snap;
  ApkSigningKey? _key;
  int _gen = 0;
  Future<void>? _loading;
  Future<ApkSigningKey>? _generating;

  LocalPackBackend get _backend => currentLocalPackBackend();

  @override
  SigningKeyState build() {
    _secrets = ref.watch(secretStoreProvider);
    ref.onDispose(() => _gen++);
    // 重建时（比如安全存储换了）Notifier 对象可能还是同一个：从头再读一遍，不沿用上一轮的钥匙和“读过了”的记号。
    _loading = null;
    _generating = null;
    _key = null;
    return _snap = const SigningKeyState();
  }

  void _put(SigningKeyState next) {
    _snap = next;
    if (ref.mounted) state = next;
  }

  SigningKeyState _with(ApkSigningKey? key, {String? error}) => SigningKeyState(loaded: true, fingerprint: key?.certSha256Hex, createdAt: key?.createdAt, error: error);

  /// 从安全存储读一次（重复调用复用同一次）。
  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    final gen = _gen;
    String? raw;
    try {
      raw = await _secrets.read(SecretKeys.apkSigningKey);
    } catch (e, st) {
      CrashLog.instance.record(StateError('读打包钥匙失败：${e.runtimeType}'), st, source: '打包钥匙', fatal: false);
    }
    if (gen != _gen || !ref.mounted) return;
    if (raw == null || raw.isEmpty) return _put(_with(null));
    try {
      _key = _backend.parseKey(raw);
      _put(_with(_key));
    } catch (e) {
      // 只记类型，不带内容：内容就是钥匙。
      _key = null;
      _put(_with(null, error: '手机里存着一把打包钥匙，但读不出来（${e is ApkPackException ? e.message : e.runtimeType}）。有备份就导入备份；没有只能重新生成，之前装过的应用要先卸载才能装新包。'));
    }
  }

  /// 拿钥匙；还没有就生成一把并存好（第一次打包走这里）。生成不了抛 [SigningKeyException]。
  Future<ApkSigningKey> ensure() async {
    await load();
    final key = _key;
    if (key != null) return key;
    if (_snap.error != null) throw SigningKeyException(_snap.error!);
    return _generating ??= _generate().whenComplete(() => _generating = null);
  }

  /// 重新生成一把，换掉现在的（危险：换了以后装不了升级包）。界面要先二次确认。
  Future<void> regenerate() async {
    await load();
    await (_generating ??= _generate().whenComplete(() => _generating = null));
  }

  Future<ApkSigningKey> _generate() async {
    final gen = ++_gen;
    _put(SigningKeyState(loaded: true, fingerprint: _snap.fingerprint, createdAt: _snap.createdAt, busy: SigningKeyBusy.generating));
    try {
      final key = await _backend.generateKey(commonName: kSigningKeyCommonName);
      await _secrets.write(SecretKeys.apkSigningKey, key.serialize());
      if (gen == _gen) {
        _key = key;
        _put(_with(key));
      }
      return key;
    } catch (e) {
      final message = '没能生成打包钥匙：${e is ApkPackException ? e.message : e.runtimeType}';
      if (gen == _gen) _put(_with(_key, error: message));
      throw SigningKeyException(message);
    }
  }

  /// 导出备份文本（用口令加密）。没有钥匙 / 口令太短抛 [SigningKeyException]。
  Future<String> exportBackup(String passphrase) async {
    await load();
    final key = _key;
    if (key == null) throw const SigningKeyException('还没有钥匙，没东西可备份。');
    if (passphrase.length < kKeyPassphraseMin) throw const SigningKeyException('口令至少 $kKeyPassphraseMin 位。');
    try {
      return _backend.exportKey(key, passphrase);
    } catch (e) {
      throw SigningKeyException('没能导出：${e is ApkPackException ? e.message : e.runtimeType}');
    }
  }

  /// 导入备份，换掉现在的钥匙。界面要先二次确认。口令不对 / 文本不对抛 [SigningKeyException]。
  Future<void> importBackup(String text, String passphrase) async {
    await load();
    if (_snap.busy != SigningKeyBusy.none) throw const SigningKeyException('钥匙正在处理中，等一下再试。');
    final gen = ++_gen;
    _put(SigningKeyState(loaded: true, fingerprint: _snap.fingerprint, createdAt: _snap.createdAt, busy: SigningKeyBusy.importing));
    try {
      final key = _backend.importKey(text.trim(), passphrase);
      await _secrets.write(SecretKeys.apkSigningKey, key.serialize());
      if (gen == _gen) {
        _key = key;
        _put(_with(key));
      }
    } catch (e) {
      if (gen == _gen) _put(_with(_key));
      throw SigningKeyException(e is ApkPackException ? e.message : (e is FormatException ? '这不是 LopiCode 导出的钥匙备份，或者内容不完整。' : '没能导入：${e.runtimeType}'));
    }
  }
}

final signingKeyProvider = NotifierProvider<SigningKeyNotifier, SigningKeyState>(SigningKeyNotifier.new);
