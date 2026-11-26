// 自签 X.509 v3 证书、SubjectPublicKeyInfo、PKCS#8 私钥的 DER 编码与解析。纯 Dart。
// 结构依据：RFC 5280（证书）、RFC 8017 附录 A.1（RSA 公私钥）、RFC 5208 / 5958（PKCS#8）。
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:lopicode/apkpack/sign/der.dart';
import 'package:lopicode/apkpack/sign/rsa.dart';

const String oidRsaEncryption = '1.2.840.113549.1.1.1';
const String oidSha256WithRsa = '1.2.840.113549.1.1.11';
const String oidSha256 = '2.16.840.1.101.3.4.2.1';
const String oidCommonName = '2.5.4.3';
const String _oidSubjectKeyId = '2.5.29.14';
const String _oidBasicConstraints = '2.5.29.19';

Uint8List derAlgorithm(String oid) => derSeq([derOid(oid), derNull()]);

/// SubjectPublicKeyInfo：`SEQ { SEQ { rsaEncryption, NULL }, BIT STRING { SEQ { n, e } } }`。
Uint8List spkiDer(BigInt n, BigInt e) => derSeq([
  derAlgorithm(oidRsaEncryption),
  derBits(derSeq([derInt(n), derInt(e)])),
]);

/// PKCS#8（不加密）：`SEQ { 0, SEQ { rsaEncryption, NULL }, OCTET STRING { RSAPrivateKey } }`。
Uint8List pkcs8Der(RsaPrivateKey k) => derSeq([
  derSmallInt(0),
  derAlgorithm(oidRsaEncryption),
  derOctets(derSeq([derSmallInt(0), derInt(k.n), derInt(k.e), derInt(k.d), derInt(k.p), derInt(k.q), derInt(k.dp), derInt(k.dq), derInt(k.qInv)])),
]);

/// 解析 PKCS#8 私钥。读不懂抛 [DerException]（文字里不带内容）。
RsaPrivateKey parsePkcs8(Uint8List der) {
  final top = derParse(der).seq(3);
  final alg = top[1].seq(1);
  if (alg[0].asOid != oidRsaEncryption) throw const DerException('不是 RSA 私钥');
  final f = derParse(top[2].asOctets).seq(9);
  if (f[0].asSmallInt != 0) throw const DerException('不支持多素数的 RSA 私钥');
  final k = RsaPrivateKey(n: f[1].asInt, e: f[2].asInt, d: f[3].asInt, p: f[4].asInt, q: f[5].asInt, dp: f[6].asInt, dq: f[7].asInt, qInv: f[8].asInt);
  // 八个数要互相对得上（只查 CRT 那几项不够：d 被改了也照样签得出名，但存下来的就是一把坏钥匙）。
  final one = BigInt.one;
  if (k.p < BigInt.two || k.q < BigInt.two || k.p * k.q != k.n || k.e.isEven || k.e < BigInt.from(3) || k.d < one || k.d >= k.n) throw const DerException('RSA 私钥内部对不上');
  final p1 = k.p - one;
  final q1 = k.q - one;
  final lcm = (p1 * q1) ~/ p1.gcd(q1);
  if ((k.e * k.d) % lcm != one || k.dp != k.d % p1 || k.dq != k.d % q1 || k.qInv >= k.p || (k.qInv * k.q) % k.p != one) throw const DerException('RSA 私钥内部对不上');
  return k;
}

Uint8List _nameDer(String commonName) => derSeq([
  derSetOfOne(derSeq([derOid(oidCommonName), derUtf8(commonName)])),
]);

/// 造一张自签证书（v3，sha256WithRSAEncryption；主题和签发者都是 `CN=[commonName]`，UTF8String）。
/// 扩展：basicConstraints（关键，CA:TRUE）和 subjectKeyIdentifier——和 `openssl req -x509` 造的自签证书同一类。
Uint8List buildSelfSignedCert({required RsaPrivateKey key, required String commonName, required DateTime notBefore, required DateTime notAfter, required BigInt serial}) {
  final name = _nameDer(commonName);
  final spki = spkiDer(key.n, key.e);
  final keyId = crypto.sha1.convert(derSeq([derInt(key.n), derInt(key.e)])).bytes;
  final extensions = derSeq([
    derSeq([
      derOid(_oidBasicConstraints),
      derBool(true),
      derOctets(derSeq([derBool(true)])),
    ]),
    derSeq([derOid(_oidSubjectKeyId), derOctets(derOctets(keyId))]),
  ]);
  final tbs = derSeq([
    derExplicit(0, derSmallInt(2)), // v3
    derInt(serial),
    derAlgorithm(oidSha256WithRsa),
    name,
    derSeq([derTime(notBefore), derTime(notAfter)]),
    name,
    spki,
    derExplicit(3, extensions),
  ]);
  return derSeq([tbs, derAlgorithm(oidSha256WithRsa), derBits(rsaSignSha256(key, tbs))]);
}

/// 从证书里读出签名要用的那几样。
class CertInfo {
  CertInfo._({
    required this.der,
    required this.issuerDer,
    required this.serialDer,
    required this.spki,
    required this.n,
    required this.e,
    required this.notBefore,
    required this.notAfter,
    required this.commonName,
  });

  /// 整张证书的 DER。
  final Uint8List der;

  /// 签发者 Name 的原始 DER（PKCS#7 里要原样用）。
  final Uint8List issuerDer;

  /// 序列号那个 INTEGER 的原始 DER（PKCS#7 里原样用；别处造的证书偶尔有负的序列号，所以不当数算）。
  final Uint8List serialDer;

  /// SubjectPublicKeyInfo 的原始 DER（v2 签名里要原样用）。
  final Uint8List spki;
  final BigInt n;
  final BigInt e;
  final DateTime notBefore;
  final DateTime notAfter;

  /// 主题里的第一个 CN（没有就是空串），只拿来显示。
  final String commonName;

  String get sha256Hex => crypto.sha256.convert(der).toString();
}

/// 解析证书。读不懂、不是 RSA 的抛 [DerException]。
CertInfo parseCert(Uint8List der) {
  final tbs = derParse(der).seq(3)[0].seq(6);
  // 第一个成员是 [0] 版本号时跳过（v1 证书没有这一项）。
  final o = tbs[0].tag == 0xa0 ? 1 : 0;
  if (tbs.length < o + 6) throw const DerException('证书内容不完整');
  final serialNode = tbs[o];
  if (serialNode.tag != derTagInteger || serialNode.content.isEmpty) throw const DerException('证书序列号写法不对');
  final validity = tbs[o + 3].seq(2);
  final spkiNode = tbs[o + 5];
  final spki = spkiNode.seq(2);
  if (spki[0].seq(1)[0].asOid != oidRsaEncryption) throw const DerException('证书里不是 RSA 公钥');
  final pub = derParse(Uint8List.fromList(spki[1].asBits)).seq(2);
  var cn = '';
  for (final rdn in tbs[o + 4].seq()) {
    for (final atv in rdn.children) {
      final pair = atv.seq(2);
      if (cn.isEmpty && pair[0].asOid == oidCommonName) cn = utf8.decode(pair[1].content, allowMalformed: true);
    }
  }
  return CertInfo._(
    der: der,
    issuerDer: Uint8List.fromList(tbs[o + 2].encoded),
    serialDer: Uint8List.fromList(serialNode.encoded),
    spki: Uint8List.fromList(spkiNode.encoded),
    n: pub[0].asInt,
    e: pub[1].asInt,
    notBefore: validity[0].asTime,
    notAfter: validity[1].asTime,
    commonName: cn,
  );
}
