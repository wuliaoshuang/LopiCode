// 本地打包（模板套壳）对界面的全部入口。界面和状态层只认这个接口，不直接碰打包器 / 签名 / 壳模板：
// - 生产实现在 lib/build/local_pack_backend_real.dart（一层薄转接，接 lib/apkpack/ 里的真实现）；
// - 测试和截图用假实现（test/support/fake_local_pack.dart）。
// 纯逻辑，不 import 界面库。
import 'dart:typed_data';

import 'package:lopicode/apkpack/apk_pack_contract.dart';
import 'package:lopicode/build/local_pack_backend_real.dart';

abstract class LocalPackBackend {
  /// 这个工作区能不能走“网页套壳”，会打包哪个目录、入口是哪个文件。
  Future<WebProjectInfo> detectProject(String projectDir);

  /// 可勾选的权限表（固定表；`defaultOn` 的默认勾上）。
  List<ApkPermissionOption> get permissionOptions;

  /// 四项输入的校验：null ＝ 通过，否则是直接给用户看的话。
  String? validateAppName(String value);
  String? validatePackageName(String value);
  String? validateVersionName(String value);
  String? validateVersionCode(String value);

  /// 读壳模板（应用自带的资源）。读不到抛 [ApkPackException]（field 为 `template`）。
  Future<Uint8List> loadTemplate();

  /// 生成一把新钥匙。手机上可能要几秒到十几秒，界面要有等待状态。
  Future<ApkSigningKey> generateKey({required String commonName});

  /// 从安全存储里的文本还原钥匙。文本坏了抛 [ApkPackException]（field 为 `key`）或 [FormatException]。
  ApkSigningKey parseKey(String serialized);

  /// 用口令把钥匙加密成一段可以存成文件的备份文本。
  String exportKey(ApkSigningKey key, String passphrase);

  /// 从备份文本 + 口令还原钥匙。口令不对 / 文本不对抛 [ApkPackException] 或 [FormatException]。
  ApkSigningKey importKey(String text, String passphrase);

  /// 执行一次打包（在后台 isolate 里跑由实现保证）。失败抛 [ApkPackException]。
  Future<ApkPackResult> pack({required Uint8List template, required ApkSigningKey key, required ApkPackRequest request, void Function(ApkPackProgress progress)? onProgress});
}

/// 测试 / 截图用：换掉真实现。
LocalPackBackend? localPackBackendOverride;

LocalPackBackend currentLocalPackBackend() => localPackBackendOverride ?? const RealLocalPackBackend();
