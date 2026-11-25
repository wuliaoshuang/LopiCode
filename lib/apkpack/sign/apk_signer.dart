// 把 v1、v2 两步串起来的便利类，形状照“打包器那边的签名接口”：
// 打包器先拿全部条目算 v1 的三个文件、放进 ZIP、对齐，再把整个 ZIP 交回来做 v2。
// 这里没有 `implements`——那个接口在打包器的分支里，合并时由协调者对上。
import 'dart:typed_data';

import 'package:lopicode/apkpack/apk_pack_contract.dart';
import 'package:lopicode/apkpack/sign/signing_key.dart';
import 'package:lopicode/apkpack/sign/v1_sign.dart';
import 'package:lopicode/apkpack/sign/v2_sign.dart';

class KeyApkSigner {
  KeyApkSigner(ApkSigningKey key) : _key = asRsaSigningKey(key);

  final RsaApkSigningKey _key;

  /// 签名证书的 SHA-256（小写十六进制），和 `apksigner verify --print-certs` 打印的一致。
  String get certSha256Hex => _key.certSha256Hex;

  /// v1：入参“条目名 → 未压缩内容”，返回要加进 ZIP 的 `META-INF/MANIFEST.MF`、`CERT.SF`、`CERT.RSA`。
  /// 加进去以后必须再调 [v2]（.SF 里写了“还有 v2 签名”的防剥离标记）。
  Map<String, Uint8List> v1Files(Map<String, Uint8List> entries) => v1SignatureFiles(entries, _key);

  /// v2：入参是加好 v1 文件、对齐好的整个 ZIP，返回签好的整个 APK。之后一个字节都不能再动。
  Uint8List v2(Uint8List alignedZip) => v2Sign(alignedZip, _key);

  @override
  String toString() => 'KeyApkSigner(证书 SHA-256 $certSha256Hex)';
}
