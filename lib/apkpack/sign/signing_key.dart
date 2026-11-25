// 用户的打包钥匙：RSA 2048 私钥 + 自签证书。生成、存进安全存储的形式、从存储读回。纯 Dart。
//
// 存储形式（[ApkSigningKey.serialize]）：两段标准 PEM 文本——`PRIVATE KEY`（不加密的 PKCS#8）+ `CERTIFICATE`，
// 约 2.9KB。它本身不加密，只许放进安全存储（flutter_secure_storage），不许写进设置文件、日志、报错。
// 要给用户带走的备份走 key_backup.dart（加口令）。
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:lopicode/apkpack/apk_pack_contract.dart';
import 'package:lopicode/apkpack/sign/der.dart';
import 'package:lopicode/apkpack/sign/rsa.dart';
import 'package:lopicode/apkpack/sign/x509.dart';

/// 证书有效期：从生成那一刻起 30 年。Android 官方建议签名钥匙有效期 25 年以上（见 docs/apk-signing-notes.md）。
const int kSigningCertYears = 30;

/// 证书名字（CN）最长多少个字符（X.520 的 ub-common-name 是 64）。
const int kSigningNameMaxLength = 64;

const String _pemPrivateKey = 'PRIVATE KEY';
const String _pemCertificate = 'CERTIFICATE';

/// [ApkSigningKey] 在这边的唯一实现。不可变。
class RsaApkSigningKey implements ApkSigningKey {
  RsaApkSigningKey._(this.privateKey, this.cert);

  /// 私钥。只给 lib/apkpack/sign/ 里的签名代码用，别处不要碰。
  final RsaPrivateKey privateKey;
  final CertInfo cert;

  Uint8List get certificateDer => cert.der;

  @override
  String get certSha256Hex => cert.sha256Hex;

  @override
  DateTime get createdAt => cert.notBefore;

  /// 证书到期时间。
  DateTime get expiresAt => cert.notAfter;

  /// 证书上的名字（CN）。
  String get commonName => cert.commonName;

  /// RSASSA-PKCS1-v1_5 + SHA-256 签名。
  Uint8List sign(List<int> data) => rsaSignSha256(privateKey, data);

  @override
  String serialize() => pemEncode(_pemPrivateKey, pkcs8Der(privateKey)) + pemEncode(_pemCertificate, cert.der);

  /// 只带证书指纹，绝不带私钥。
  @override
  String toString() => 'ApkSigningKey(证书 SHA-256 $certSha256Hex)';
}

/// 把传进来的钥匙认成这边的实现；不是就报错（别的实现这里没法拿它签名）。
RsaApkSigningKey asRsaSigningKey(ApkSigningKey key) {
  if (key is RsaApkSigningKey) return key;
  throw const ApkPackException('这把打包钥匙不是本应用生成或导入的，没法用它签名。', field: 'key');
}

/// 私钥和证书配成一把钥匙：公钥要对得上，并且真签一次、验一次（挡住内部自相矛盾的私钥）。
/// 对不上抛 [ApkPackException]（[mismatch] 是给用户看的那句话）。只支持 2048 / 4096 位（Android v2 签名文档列出的长度）。
RsaApkSigningKey signingKeyFromParts(RsaPrivateKey privateKey, CertInfo cert, {required String mismatch}) {
  if (privateKey.bits != 2048 && privateKey.bits != 4096) {
    throw ApkPackException('只支持 2048 位或 4096 位的 RSA 钥匙，这一把是 ${privateKey.bits} 位。', field: 'key');
  }
  if (privateKey.n != cert.n || privateKey.e != cert.e) throw ApkPackException(mismatch, field: 'key');
  const probe = [0x4c, 0x6f, 0x70, 0x69];
  try {
    if (!rsaVerifySha256(cert.n, cert.e, probe, rsaSignSha256(privateKey, probe))) throw ApkPackException(mismatch, field: 'key');
  } on StateError {
    throw ApkPackException(mismatch, field: 'key');
  }
  return RsaApkSigningKey._(privateKey, cert);
}

/// 检查证书名字；不合适抛 [ApkPackException]，合适返回去掉首尾空白后的名字。
String checkSigningName(String commonName) {
  final name = commonName.trim();
  if (name.isEmpty) throw const ApkPackException('钥匙的名字不能为空。', field: 'key');
  if (name.runes.length > kSigningNameMaxLength) throw const ApkPackException('钥匙的名字太长了，最多 $kSigningNameMaxLength 个字。', field: 'key');
  if (name.runes.any((r) => r < 0x20 || r == 0x7f)) throw const ApkPackException('钥匙的名字里不能有换行之类的控制字符。', field: 'key');
  return name;
}

/// 同步生成一把新钥匙（RSA 2048 + 自签证书）。很费时，会卡住当前线程——界面上请用 [generateSigningKey]。
/// [now]、[random] 只给测试换。
ApkSigningKey generateSigningKeySync({required String commonName, DateTime? now, Random? random}) {
  final name = checkSigningName(commonName);
  final rnd = random ?? Random.secure();
  final t = (now ?? DateTime.now()).toUtc();
  final notBefore = DateTime.utc(t.year, t.month, t.day, t.hour, t.minute, t.second);
  final notAfter = DateTime.utc(t.year + kSigningCertYears, t.month, t.day, t.hour, t.minute, t.second);
  final privateKey = rsaGenerate(random: rnd);
  // 序列号：随机 16 字节，最高位清零保证是正数，最低位置 1 保证不为零。
  final serialBytes = Uint8List(16);
  for (var i = 0; i < serialBytes.length; i++) {
    serialBytes[i] = rnd.nextInt(256);
  }
  serialBytes[0] &= 0x7f;
  serialBytes[15] |= 0x01;
  final der = buildSelfSignedCert(key: privateKey, commonName: name, notBefore: notBefore, notAfter: notAfter, serial: bytesToBigInt(serialBytes));
  return signingKeyFromParts(privateKey, parseCert(der), mismatch: '刚生成的钥匙自己对不上，请再生成一次。');
}

/// 在另一个 isolate 里生成新钥匙，不卡界面。手机上可能要几秒到十几秒。
Future<ApkSigningKey> generateSigningKey({required String commonName}) async {
  final name = checkSigningName(commonName);
  final serialized = await Isolate.run(() => generateSigningKeySync(commonName: name).serialize());
  return parseSigningKey(serialized);
}

/// 从 [ApkSigningKey.serialize] 的结果读回钥匙。内容坏了抛 [ApkPackException]（文字里不带任何钥匙内容）。
ApkSigningKey parseSigningKey(String serialized) {
  const broken = '保存的打包钥匙读不出来（内容不完整或被改动过）。请导入备份，或者重新生成一把。';
  final RsaPrivateKey privateKey;
  final CertInfo cert;
  try {
    final keyDer = pemDecode(serialized, _pemPrivateKey);
    final certDer = pemDecode(serialized, _pemCertificate);
    if (keyDer == null || certDer == null) throw const ApkPackException(broken, field: 'key');
    privateKey = parsePkcs8(keyDer);
    cert = parseCert(certDer);
  } on DerException {
    throw const ApkPackException(broken, field: 'key');
  } on RangeError {
    throw const ApkPackException(broken, field: 'key');
  }
  return signingKeyFromParts(privateKey, cert, mismatch: broken);
}
