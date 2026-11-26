// 本地打包的生产实现：只做一层薄转接，把 [LocalPackBackend] 的每个方法接到 lib/apkpack/ 的真实现上
// （打包器 apk_packer.dart、签名 sign/、随应用发的壳模板 assets/apk_shell/shell.apk）。
// 费时的事（生成钥匙、导出 / 导入备份、打包）都在后台 isolate 里跑，不卡界面。
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:lopicode/apkpack/apk_pack_contract.dart';
import 'package:lopicode/apkpack/apk_packer.dart';
import 'package:lopicode/apkpack/apk_packer.dart' as apk;
import 'package:lopicode/apkpack/sign/apk_signer.dart';
import 'package:lopicode/apkpack/sign/key_backup.dart';
import 'package:lopicode/apkpack/sign/signing_key.dart';
import 'package:lopicode/build/local_pack_backend.dart';

/// 壳模板在应用资源里的位置。
const String kApkShellAsset = 'assets/apk_shell/shell.apk';

class RealLocalPackBackend implements LocalPackBackend {
  const RealLocalPackBackend();

  @override
  Future<WebProjectInfo> detectProject(String projectDir) => detectWebProject(projectDir);

  @override
  List<ApkPermissionOption> get permissionOptions => kApkPermissionOptions;

  @override
  String? validateAppName(String value) => apk.validateAppName(value);

  @override
  String? validatePackageName(String value) => apk.validatePackageName(value);

  @override
  String? validateVersionName(String value) => apk.validateVersionName(value);

  /// 打包器收的是整数：先看是不是整数，再交给它查范围。
  @override
  String? validateVersionCode(String value) {
    final n = int.tryParse(value.trim());
    if (n == null) return '版本号要是一个整数';
    return apk.validateVersionCode(n);
  }

  @override
  Future<Uint8List> loadTemplate() async {
    try {
      final data = await rootBundle.load(kApkShellAsset);
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } catch (e) {
      throw ApkPackException('应用里自带的打包模板读不出来（${e.runtimeType}），这个安装包可能不完整，重装一次 LopiCode 再试。', field: 'template');
    }
  }

  @override
  Future<ApkSigningKey> generateKey({required String commonName}) => generateSigningKey(commonName: commonName);

  @override
  ApkSigningKey parseKey(String serialized) => parseSigningKey(serialized);

  @override
  Future<String> exportKey(ApkSigningKey key, String passphrase) => exportSigningKeyAsync(key, passphrase);

  @override
  Future<ApkSigningKey> importKey(String text, String passphrase) => importSigningKeyAsync(text, passphrase);

  /// 失败抛的 [ApkPackException.field] 除约定文件里列的以外还可能是 `permissions`（界面有落点）。
  @override
  Future<ApkPackResult> pack({required Uint8List template, required ApkSigningKey key, required ApkPackRequest request, void Function(ApkPackProgress progress)? onProgress}) =>
      LocalApkPacker(template: template, signer: KeyApkSigner(key)).pack(request, onProgress: onProgress);
}
