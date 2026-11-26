// 打包钥匙的导出备份 / 导入。纯 Dart。
//
// 备份是一个文本文件：几行说明 + 标准的加密 PKCS#8 私钥（`ENCRYPTED PRIVATE KEY`）+ 证书（`CERTIFICATE`）。
// 加密方式是 PBES2（RFC 8018）：PBKDF2-HMAC-SHA256 派生钥匙 + AES-256-CBC，和
// `openssl pkcs8 -topk8 -v2 aes-256-cbc -v2prf hmacWithSHA256` 写出来的是同一种，所以拿到电脑上能用 openssl 解开：
//   openssl pkcs8 -in 备份文件 -out key.pem      （会问口令）
//   openssl x509  -in 备份文件 -noout -text
//
// 自定的数值（依据见 docs/apk-signing-notes.md）：
// - 迭代次数 [kBackupPbkdf2Iterations] = 600,000：OWASP Password Storage Cheat Sheet 对 PBKDF2-HMAC-SHA256 的现行建议。
// - 盐 16 字节、初始向量 16 字节，每次导出都重新随机取。
// - 口令最短 [kBackupMinPassphraseLength] = 8 个字符（导入不限，方便读 openssl 造的文件）。口令按 UTF-8 字节用，和 openssl 一致。
//
// 这两个函数都很费时（几十万次迭代），界面上请用带 Async 的版本（在另一个 isolate 里跑）。
import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:lopicode/apkpack/apk_pack_contract.dart';
import 'package:lopicode/apkpack/sign/aes.dart';
import 'package:lopicode/apkpack/sign/der.dart';
import 'package:lopicode/apkpack/sign/pbkdf2.dart';
import 'package:lopicode/apkpack/sign/rsa.dart';
import 'package:lopicode/apkpack/sign/signing_key.dart';
import 'package:lopicode/apkpack/sign/x509.dart';

const int kBackupPbkdf2Iterations = 600000;
const int kBackupMinPassphraseLength = 8;

/// 导入时肯接受的最大迭代次数（再大就当成坏文件，免得一个坏文件让手机算半天）。
const int kBackupMaxPbkdf2Iterations = 10000000;

const String _oidPbes2 = '1.2.840.113549.1.5.13';
const String _oidPbkdf2 = '1.2.840.113549.1.5.12';
const String _oidHmacSha256 = '1.2.840.113549.2.9';
const String _oidAes256Cbc = '2.16.840.1.101.3.4.1.42';

const String _pemEncryptedKey = 'ENCRYPTED PRIVATE KEY';
const String _pemCertificate = 'CERTIFICATE';

ApkPackException _err(String message) => ApkPackException(message, field: 'key');

Uint8List _randomBytes(int n, Random random) {
  final out = Uint8List(n);
  for (var i = 0; i < n; i++) {
    out[i] = random.nextInt(256);
  }
  return out;
}

/// 把钥匙导出成备份文本。[passphrase] 太短抛 [ApkPackException]。
/// [iterations]、[random] 只给测试换。
String exportSigningKey(ApkSigningKey key, String passphrase, {int iterations = kBackupPbkdf2Iterations, Random? random}) {
  final k = asRsaSigningKey(key);
  if (passphrase.runes.length < kBackupMinPassphraseLength) throw _err('口令太短了，至少要 $kBackupMinPassphraseLength 个字符。');
  if (iterations < 1 || iterations > kBackupMaxPbkdf2Iterations) throw ArgumentError('迭代次数不对');
  final rnd = random ?? Random.secure();
  final salt = _randomBytes(16, rnd);
  final iv = _randomBytes(16, rnd);
  final aesKey = pbkdf2HmacSha256(utf8.encode(passphrase), salt, iterations, 32);
  final cipher = aesCbcEncrypt(aesKey, iv, pkcs8Der(k.privateKey));
  final encrypted = derSeq([
    derSeq([
      derOid(_oidPbes2),
      derSeq([
        derSeq([
          derOid(_oidPbkdf2),
          derSeq([
            derOctets(salt),
            derSmallInt(iterations),
            derSeq([derOid(_oidHmacSha256), derNull()]),
          ]),
        ]),
        derSeq([derOid(_oidAes256Cbc), derOctets(iv)]),
      ]),
    ]),
    derOctets(cipher),
  ]);
  return '# LopiCode 打包钥匙备份。请和口令分开保管；丢了口令就解不开，丢了钥匙以后的新版本就装不上去。\n'
      '# 证书 SHA-256：${k.certSha256Hex}\n'
      '# 生成时间：${k.createdAt.toIso8601String()}\n'
      '# 在电脑上解开私钥：openssl pkcs8 -in 这个文件 -out key.pem   （会问口令）\n'
      '# 在电脑上看证书：  openssl x509 -in 这个文件 -noout -text\n'
      '${pemEncode(_pemEncryptedKey, encrypted)}'
      '${pemEncode(_pemCertificate, k.certificateDer)}';
}

/// 从备份文本导入钥匙。口令错、文件坏、证书和私钥对不上都抛 [ApkPackException]，各有一句大白话；
/// 报错里不带口令和钥匙内容。
ApkSigningKey importSigningKey(String text, String passphrase) {
  const notBackup = '这不是打包钥匙的备份文件：里面找不到加密的私钥和证书。';
  const damaged = '备份文件坏了（内容不完整或被改动过），读不出来。';
  const unsupported = '这个文件的加密方式这里不支持。只支持 PBES2（PBKDF2-HMAC-SHA256 + AES-256-CBC），也就是本应用导出的那一种。';
  const wrongPass = '口令不对，解不开这份备份。（如果确定口令没错，那就是备份文件被改动过。）';
  const mismatch = '备份里的证书和私钥对不上，不是同一把钥匙。';

  if (text.contains('-----BEGIN PRIVATE KEY-----') || text.contains('-----BEGIN RSA PRIVATE KEY-----')) {
    if (!text.contains('-----BEGIN $_pemEncryptedKey-----')) throw _err('这个文件里的私钥没有加口令，这里只导入加了口令的备份。');
  }
  final Uint8List? encDer;
  final Uint8List? certDer;
  try {
    encDer = pemDecode(text, _pemEncryptedKey);
    certDer = pemDecode(text, _pemCertificate);
  } on DerException {
    throw _err(damaged);
  }
  if (encDer == null || certDer == null) throw _err(notBackup);
  if (passphrase.isEmpty) throw _err('请输入导出备份时设的口令。');

  final Uint8List salt;
  final Uint8List iv;
  final Uint8List cipher;
  final int iterations;
  final CertInfo cert;
  try {
    final top = derParse(encDer).seq(2);
    final alg = top[0].seq(2);
    if (alg[0].asOid != _oidPbes2) throw _err(unsupported);
    final params = alg[1].seq(2);
    final kdf = params[0].seq(2);
    final scheme = params[1].seq(2);
    if (kdf[0].asOid != _oidPbkdf2 || scheme[0].asOid != _oidAes256Cbc) throw _err(unsupported);
    final kdfParams = kdf[1].seq(2);
    // PBKDF2-params：盐、迭代次数、[钥匙长度]、[伪随机函数，不写就是 HMAC-SHA1]。
    var prf = '';
    for (final extra in kdfParams.skip(2)) {
      if (extra.tag == derTagInteger) {
        if (extra.asSmallInt != 32) throw _err(unsupported);
      } else {
        prf = extra.seq(1)[0].asOid;
      }
    }
    if (prf != _oidHmacSha256) throw _err(unsupported);
    salt = kdfParams[0].asOctets;
    iterations = kdfParams[1].asSmallInt;
    iv = scheme[1].asOctets;
    cipher = top[1].asOctets;
    if (iterations < 1 || iterations > kBackupMaxPbkdf2Iterations || iv.length != 16 || cipher.isEmpty || cipher.length % 16 != 0) throw _err(damaged);
    cert = parseCert(certDer);
  } on DerException {
    throw _err(damaged);
  } on RangeError {
    throw _err(damaged);
  }

  final aesKey = pbkdf2HmacSha256(utf8.encode(passphrase), salt, iterations, 32);
  final plain = aesCbcDecrypt(aesKey, iv, cipher);
  if (plain == null) throw _err(wrongPass);
  final RsaPrivateKey privateKey;
  try {
    privateKey = parsePkcs8(plain);
  } on DerException {
    // 口令错时有约 1/256 的机会补位碰巧像对的，解出来的是乱码——同样按口令不对报。
    throw _err(wrongPass);
  } on RangeError {
    throw _err(wrongPass);
  }
  return signingKeyFromParts(privateKey, cert, mismatch: mismatch);
}

/// [exportSigningKey] 的不卡界面版本。
Future<String> exportSigningKeyAsync(ApkSigningKey key, String passphrase) {
  final serialized = key.serialize();
  return Isolate.run(() => exportSigningKey(parseSigningKey(serialized), passphrase));
}

/// [importSigningKey] 的不卡界面版本。
Future<ApkSigningKey> importSigningKeyAsync(String text, String passphrase) async {
  final serialized = await Isolate.run(() => importSigningKey(text, passphrase).serialize());
  return parseSigningKey(serialized);
}
