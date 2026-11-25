// 本地打包的假实现（测试和截图用）：不压缩、不签名，只按约定的形状走一遍，产物是一个写着几行字的假文件。
// 真的打包器 / 签名 / 壳模板在别的分支上，各有各的测试；这里只验界面和状态层怎么用它们。
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:lopicode/apkpack/apk_pack_contract.dart';
import 'package:lopicode/build/local_pack_backend.dart';
import 'package:path/path.dart' as p;

class FakeSigningKey implements ApkSigningKey {
  FakeSigningKey(this.certSha256Hex, this.createdAt);
  @override
  final String certSha256Hex;
  @override
  final DateTime createdAt;
  @override
  String serialize() => jsonEncode({'fp': certSha256Hex, 'at': createdAt.millisecondsSinceEpoch});
}

const kFakePermissions = [
  ApkPermissionOption(id: 'android.permission.INTERNET', label: '联网', hint: '网页要访问网络就得开', defaultOn: true),
  ApkPermissionOption(id: 'android.permission.ACCESS_NETWORK_STATE', label: '查看网络状态', hint: '判断现在有没有网'),
  ApkPermissionOption(id: 'android.permission.CAMERA', label: '相机', hint: '网页里要拍照、扫码'),
  ApkPermissionOption(id: 'android.permission.RECORD_AUDIO', label: '麦克风', hint: '网页里要录音'),
  ApkPermissionOption(id: 'android.permission.ACCESS_FINE_LOCATION', label: '位置', hint: '网页里要定位'),
  ApkPermissionOption(id: 'android.permission.VIBRATE', label: '振动', hint: '网页里要让手机振一下'),
  ApkPermissionOption(id: 'android.permission.WAKE_LOCK', label: '保持亮屏', hint: '播放时不让屏幕自己熄'),
];

class FakeLocalPackBackend implements LocalPackBackend {
  /// 识别项目的结果；不给就按“工作区里有没有 index.html”来。
  WebProjectInfo? project;

  /// 生成钥匙时卡在这里，测试自己放行（看等待状态用）。
  Completer<void>? keyGate;

  /// 打包时走到哪一步卡住，测试自己放行（看进度用）。
  ApkPackStep? holdAt;
  Completer<void>? packGate;

  /// 打包要抛的错。
  ApkPackException? packError;
  ApkPackStep packErrorAt = ApkPackStep.manifest;

  int generated = 0;
  int packs = 0;
  ApkPackRequest? lastRequest;
  ApkSigningKey? lastKey;

  /// 每生成一把换一个指纹。
  final List<String> fingerprints = ['3556a3b1c0ffee00112233445566778899aabbccddeeff00112233445566f51a', 'aa11bb22cc33dd44ee55ff66007788990011223344556677889900aabbccddee'];

  @override
  Future<WebProjectInfo> detectProject(String projectDir) async {
    final fixed = project;
    if (fixed != null) return fixed;
    if (File(p.join(projectDir, 'pubspec.yaml')).existsSync()) {
      return const WebProjectInfo(applicable: false, reason: '这是 Flutter 项目，要编译才能出包，手机上编不了。');
    }
    if (File(p.join(projectDir, 'index.html')).existsSync()) {
      return WebProjectInfo(applicable: true, reason: '会打包整个工作区目录，入口是 index.html。', webRoot: projectDir, entry: 'index.html', kind: 'static');
    }
    return const WebProjectInfo(applicable: false, reason: '没找到网页入口：工作区里没有 index.html。');
  }

  @override
  List<ApkPermissionOption> get permissionOptions => kFakePermissions;

  @override
  String? validateAppName(String value) => value.trim().isEmpty
      ? '应用名不能空着'
      : value.trim().runes.length > 50
      ? '应用名太长了，最多 50 个字'
      : null;

  @override
  String? validatePackageName(String value) => RegExp(r'^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$').hasMatch(value.trim()) ? null : '包名要像 com.example.app 这样：小写字母开头，用点分成至少两段';

  @override
  String? validateVersionName(String value) => value.trim().isEmpty ? '版本名不能空着' : null;

  @override
  String? validateVersionCode(String value) {
    final n = int.tryParse(value.trim());
    return n == null || n < 1 ? '版本号要是大于 0 的整数' : null;
  }

  @override
  Future<Uint8List> loadTemplate() async => Uint8List.fromList(const [0x50, 0x4b, 3, 4]);

  @override
  Future<ApkSigningKey> generateKey({required String commonName}) async {
    await keyGate?.future;
    final key = FakeSigningKey(fingerprints[generated % fingerprints.length], DateTime(2026, 11, 26, 2, 30));
    generated++;
    return key;
  }

  @override
  ApkSigningKey parseKey(String serialized) {
    final j = jsonDecode(serialized);
    if (j is! Map || j['fp'] is! String || j['at'] is! int) throw const FormatException('不是钥匙');
    return FakeSigningKey(j['fp'] as String, DateTime.fromMillisecondsSinceEpoch(j['at'] as int));
  }

  @override
  String exportKey(ApkSigningKey key, String passphrase) => 'LOPIKEY1:${base64Encode(utf8.encode('$passphrase\n${key.serialize()}'))}';

  @override
  ApkSigningKey importKey(String text, String passphrase) {
    if (!text.startsWith('LOPIKEY1:')) throw const FormatException('不是备份');
    final lines = utf8.decode(base64Decode(text.substring(9))).split('\n');
    if (lines.first != passphrase) throw const ApkPackException('口令不对。', field: 'key');
    return parseKey(lines.skip(1).join('\n'));
  }

  @override
  Future<ApkPackResult> pack({required Uint8List template, required ApkSigningKey key, required ApkPackRequest request, void Function(ApkPackProgress progress)? onProgress}) async {
    packs++;
    lastRequest = request;
    lastKey = key;
    const details = {ApkPackStep.collect: '找到 23 个文件，共 1.2 MB', ApkPackStep.zip: '23 / 23', ApkPackStep.sign: 'v1 + v2'};
    for (final step in ApkPackStep.values) {
      onProgress?.call(ApkPackProgress(step, detail: details[step] ?? ''));
      if (step == holdAt) await packGate?.future;
      final error = packError;
      if (error != null && step == packErrorAt) throw error;
      await Future<void>.delayed(Duration.zero);
    }
    final file = File(request.outputPath);
    await file.writeAsString('假安装包 ${request.packageName} ${request.versionCode}');
    return ApkPackResult(
      path: file.path,
      sizeBytes: 1258291,
      packageName: request.packageName,
      appName: request.appName,
      versionName: request.versionName,
      versionCode: request.versionCode,
      fileCount: 23,
      sha256Hex: 'e0ce3e02' * 8,
      certSha256Hex: key.certSha256Hex,
    );
  }
}
