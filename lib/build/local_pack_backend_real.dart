// 本地打包的生产实现：只做一层薄转接，把 [LocalPackBackend] 的每个方法接到 lib/apkpack/ 的真实现上。
//
// 【留给合并的人接的位置】这一轮打包器（la-packer）、签名（la-signer）、壳模板（la-shell）在别的分支上，
// 还没合过来，所以下面每个方法先是“还没接好”的占位。合并时照每个方法上面注释里写的那一行换掉即可：
//   import 'package:flutter/services.dart' show rootBundle;
//   import 'package:lopicode/apkpack/apk_packer.dart';
//   import 'package:lopicode/apkpack/sign/….dart';
// 接好以后把 [kLocalPackWired] 改成 true（test/local_pack_state_test.dart 守着：没接好时界面如实说“还没接好”，不假装能用）。
import 'dart:typed_data';

import 'package:lopicode/apkpack/apk_pack_contract.dart';
import 'package:lopicode/build/local_pack_backend.dart';

/// 真实现接没接好。没接好时打包页的“本地打包”会明说，不让点了没反应。
const bool kLocalPackWired = false;

const String _notWired = '这个版本里本地打包的打包器还没接进来，先用 GitHub Actions 或 SSH 构建机。';

class RealLocalPackBackend implements LocalPackBackend {
  const RealLocalPackBackend();

  /// 接：`detectWebProject(projectDir)`
  @override
  Future<WebProjectInfo> detectProject(String projectDir) async => const WebProjectInfo(applicable: false, reason: _notWired);

  /// 接：`kApkPermissionOptions`
  @override
  List<ApkPermissionOption> get permissionOptions => const [ApkPermissionOption(id: 'android.permission.INTERNET', label: '联网', hint: '网页要访问网络就得开', defaultOn: true)];

  /// 接：`validateAppName(value)`
  @override
  String? validateAppName(String value) => value.trim().isEmpty ? '应用名不能空着' : null;

  /// 接：`validatePackageName(value)`
  @override
  String? validatePackageName(String value) => value.trim().isEmpty ? '包名不能空着' : null;

  /// 接：`validateVersionName(value)`
  @override
  String? validateVersionName(String value) => value.trim().isEmpty ? '版本名不能空着' : null;

  /// 接：`validateVersionCode(value)`
  @override
  String? validateVersionCode(String value) => int.tryParse(value.trim()) == null ? '版本号要是一个整数' : null;

  /// 接：`(await rootBundle.load('assets/apk_shell/shell.apk')).buffer.asUint8List()`，读不到抛 ApkPackException(…, field: 'template')
  @override
  Future<Uint8List> loadTemplate() async => throw const ApkPackException(_notWired, field: 'template');

  /// 接：`generateSigningKey(commonName: commonName)`
  @override
  Future<ApkSigningKey> generateKey({required String commonName}) async => throw const ApkPackException(_notWired, field: 'key');

  /// 接：`parseSigningKey(serialized)`
  @override
  ApkSigningKey parseKey(String serialized) => throw const ApkPackException(_notWired, field: 'key');

  /// 接：`exportSigningKey(key, passphrase)`
  @override
  String exportKey(ApkSigningKey key, String passphrase) => throw const ApkPackException(_notWired, field: 'key');

  /// 接：`importSigningKey(text, passphrase)`
  @override
  ApkSigningKey importKey(String text, String passphrase) => throw const ApkPackException(_notWired, field: 'key');

  /// 接：`LocalApkPacker(template: template, signer: <la-signer 里拿 key 做 v1+v2 签名的 ApkSigner 实现>(key)).pack(request, onProgress: onProgress)`
  @override
  Future<ApkPackResult> pack({required Uint8List template, required ApkSigningKey key, required ApkPackRequest request, void Function(ApkPackProgress progress)? onProgress}) async =>
      throw const ApkPackException(_notWired, field: 'template');
}
