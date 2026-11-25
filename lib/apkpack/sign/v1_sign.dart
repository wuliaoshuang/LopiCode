// APK 的 v1 签名（JAR 签名）：产出 META-INF/MANIFEST.MF、CERT.SF、CERT.RSA 三个文件的内容。纯 Dart。
//
// 格式依据（核对记录见 docs/apk-signing-notes.md）：
// - JAR 文件规范的 “Signed JAR File”“Notes on Manifest and Signature Files”：每节以空行结束；一行（UTF-8 编码后）
//   不超过 72 字节，超了就折行，续行以一个空格开头。这里和 JDK、apksig 一样把 72 算作“含行尾的 CRLF”，
//   所以一行内容最多 70 字节、续行是 1 个空格 + 最多 69 字节；并且不在一个 UTF-8 字符中间折（读的一方按字节拼回去，
//   折在哪都读得回来，只是这样文本更干净）。
// - 条目名非 ASCII：按 UTF-8 字节写进 `Name:`。名字里有回车、换行、NUL 的没法写进清单，直接报错。
// - .SF 主节带 `X-Android-APK-Signed: 2`：告诉 Android 7.0+ “这个包还有 v2 签名”，有人把 v2 签名剥掉就会被拒（防剥离）。
// - CERT.RSA 是 PKCS#7 SignedData（RFC 2315）：不带内容、不带签名属性，签的就是整个 CERT.SF 的字节；
//   摘要 SHA-256，签名算法标成 rsaEncryption（和 apksig 的做法一致，老系统也认）。
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:lopicode/apkpack/apk_pack_contract.dart';
import 'package:lopicode/apkpack/sign/der.dart';
import 'package:lopicode/apkpack/sign/signing_key.dart';
import 'package:lopicode/apkpack/sign/x509.dart';

const String kV1ManifestName = 'META-INF/MANIFEST.MF';
const String kV1SignatureFileName = 'META-INF/CERT.SF';
const String kV1SignatureBlockName = 'META-INF/CERT.RSA';

const String _createdBy = '1.0 (LopiCode)';
const String _oidPkcs7Data = '1.2.840.113549.1.7.1';
const String _oidPkcs7SignedData = '1.2.840.113549.1.7.2';

/// 这个条目是不是 v1 签名自己的文件（清单、*.SF、*.RSA / *.DSA / *.EC、SIG-*）。这些不进清单，旧的会被新的顶掉。
bool isV1SignatureEntry(String name) {
  if (!name.startsWith('META-INF/')) return false;
  final base = name.substring('META-INF/'.length).toUpperCase();
  if (base.contains('/')) return false;
  return base == 'MANIFEST.MF' || base.endsWith('.SF') || base.endsWith('.RSA') || base.endsWith('.DSA') || base.endsWith('.EC') || base.startsWith('SIG-');
}

/// 清单里的一行 `名: 值`，按 72 字节规则折行，带行尾 CRLF。
Uint8List manifestLine(String name, String value) {
  final bytes = utf8.encode('$name: $value');
  final out = BytesBuilder();
  var pos = 0;
  var room = 70;
  while (true) {
    var end = pos + room < bytes.length ? pos + room : bytes.length;
    // 别折在一个 UTF-8 字符中间：往回退到字符的开头。
    while (end < bytes.length && end > pos + 1 && bytes[end] & 0xc0 == 0x80) {
      end--;
    }
    out.add(Uint8List.sublistView(bytes, pos, end));
    out.add(const [0x0d, 0x0a]);
    pos = end;
    if (pos >= bytes.length) break;
    out.addByte(0x20);
    room = 69;
  }
  return out.toBytes();
}

const List<int> _crlf = [0x0d, 0x0a];

/// 算三个签名文件。[entries] 是“条目名 → 未压缩内容”（APK 里除签名文件外的全部条目；带进来的旧签名文件、目录条目会被忽略）。
/// [alsoV2Signed] 为 true（默认）时在 .SF 里写防剥离标记——之后**必须**再做 v2 签名，否则 Android 7.0+ 会拒装。
Map<String, Uint8List> v1SignatureFiles(Map<String, Uint8List> entries, ApkSigningKey key, {bool alsoV2Signed = true}) {
  final k = asRsaSigningKey(key);
  final names = entries.keys.where((n) => !isV1SignatureEntry(n) && !n.endsWith('/')).toList()..sort();
  for (final name in names) {
    if (name.isEmpty || name.contains('\r') || name.contains('\n') || name.contains('\u0000')) {
      throw const ApkPackException('安装包里有文件名带换行之类的特殊字符，没法签名。请改掉这个文件名。', field: 'project');
    }
  }

  final manifest = BytesBuilder();
  manifest
    ..add(manifestLine('Manifest-Version', '1.0'))
    ..add(manifestLine('Created-By', _createdBy))
    ..add(_crlf);
  final sf = BytesBuilder();
  final sections = <Uint8List>[];
  for (final name in names) {
    final section = BytesBuilder()
      ..add(manifestLine('Name', name))
      ..add(manifestLine('SHA-256-Digest', base64.encode(crypto.sha256.convert(entries[name]!).bytes)))
      ..add(_crlf);
    final bytes = section.toBytes();
    sections.add(bytes);
    manifest.add(bytes);
  }
  final manifestBytes = manifest.toBytes();

  sf
    ..add(manifestLine('Signature-Version', '1.0'))
    ..add(manifestLine('Created-By', _createdBy))
    ..add(manifestLine('SHA-256-Digest-Manifest', base64.encode(crypto.sha256.convert(manifestBytes).bytes)));
  if (alsoV2Signed) sf.add(manifestLine('X-Android-APK-Signed', '2'));
  sf.add(_crlf);
  for (var i = 0; i < names.length; i++) {
    sf
      ..add(manifestLine('Name', names[i]))
      ..add(manifestLine('SHA-256-Digest', base64.encode(crypto.sha256.convert(sections[i]).bytes)))
      ..add(_crlf);
  }
  final sfBytes = sf.toBytes();

  return {kV1ManifestName: manifestBytes, kV1SignatureFileName: sfBytes, kV1SignatureBlockName: _pkcs7(k, sfBytes)};
}

/// PKCS#7 SignedData（DER）：
/// `ContentInfo { signedData, [0] { version 1, { sha256 }, { data }, [0] 证书, { SignerInfo } } }`，
/// `SignerInfo { version 1, { 签发者, 序列号 }, sha256, rsaEncryption, 签名 }`。
Uint8List _pkcs7(RsaApkSigningKey key, Uint8List signedBytes) {
  final signerInfo = derSeq([
    derSmallInt(1),
    derSeq([key.cert.issuerDer, key.cert.serialDer]),
    derAlgorithm(oidSha256),
    derAlgorithm(oidRsaEncryption),
    derOctets(key.sign(signedBytes)),
  ]);
  final signedData = derSeq([
    derSmallInt(1),
    derSetOfOne(derAlgorithm(oidSha256)),
    derSeq([derOid(_oidPkcs7Data)]),
    derTlv(0xa0, key.certificateDer), // [0] IMPLICIT 证书集合
    derSetOfOne(signerInfo),
  ]);
  return derSeq([derOid(_oidPkcs7SignedData), derExplicit(0, signedData)]);
}
