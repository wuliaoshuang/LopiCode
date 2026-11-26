// 看一个安装包是谁：应用名、包名、版本、签名证书的指纹。给“文件”页的安装包信息面板用。
//
// 只读必要的几段，不把整个文件读进内存：文件尾（找目录）→ 中央目录 → 清单那一条
// （应用名写在资源表里时再读资源表）→ 签名块或 META-INF 里的证书。所以几百 MB 的包也只读几十 KB 到几 MB。
// 上限见下面几个常量；超过就不解析，界面照样给出文件的基本信息。重活放在后台 isolate（[inspectApk]）。
//
// 指纹只是“包里带的那张证书”的 SHA-256，这里**不验证签名有没有效**——装不装得上由系统安装器说了算。
// 纯 Dart，不 import 界面库。格式事实见 docs/apk-format-notes.md。
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:lopicode/apkpack/arsc_lookup.dart';
import 'package:lopicode/apkpack/axml/axml_codec.dart';
import 'package:lopicode/apkpack/axml/axml_model.dart';
import 'package:lopicode/apkpack/sign/der.dart';

/// 文件超过这么大就不解析（ZIP 的 32 位偏移最多到 4GB，再大是 ZIP64，这里不支持；留一半余量）。
const int kApkInspectMaxFileBytes = 2 * 1024 * 1024 * 1024;

/// 中央目录（文件清单）最多读这么大。
const int kApkInspectMaxDirectoryBytes = 32 * 1024 * 1024;

/// 清单解压后最多这么大。
const int kApkInspectMaxManifestBytes = 4 * 1024 * 1024;

/// 资源表解压后最多这么大；超过就不查“写在资源表里的应用名”。
const int kApkInspectMaxArscBytes = 32 * 1024 * 1024;

/// 签名块、证书文件最多读这么大。
const int kApkInspectMaxSignatureBytes = 8 * 1024 * 1024;

class ApkInfo {
  const ApkInfo({required this.packageName, this.appName, this.versionName, this.versionCode, this.certSha256Hex, this.signScheme});
  final String packageName;

  /// 应用名；读不出来（写在资源表里又查不到）是 null。
  final String? appName;
  final String? versionName;
  final int? versionCode;

  /// 包里带的签名证书的 SHA-256（小写十六进制）；没签名 / 读不出来是 null。没有验证签名是否有效。
  final String? certSha256Hex;

  /// 证书是从哪种签名里读到的：`v3` / `v2` / `v1`。
  final String? signScheme;
}

/// 解析不了。[message] 是直接给用户看的大白话。
class ApkInspectException implements Exception {
  const ApkInspectException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// 在后台 isolate 里解析。解析不了抛 [ApkInspectException]。
Future<ApkInfo> inspectApk(String path) => Isolate.run(() => inspectApkSync(path));

ApkInfo inspectApkSync(String path) {
  final RandomAccessFile f;
  try {
    f = File(path).openSync();
  } on FileSystemException {
    throw const ApkInspectException('这个文件读不了（可能已经被删掉或挪走了）。');
  }
  try {
    return _Reader(f).read();
  } on ApkInspectException {
    rethrow;
  } on FileSystemException {
    throw const ApkInspectException('读这个文件的时候出错了，文件可能不完整。');
  } on RangeError {
    throw const ApkInspectException('文件内容对不上，像是下载或拷贝到一半的安装包。');
  } finally {
    f.closeSync();
  }
}

class _Entry {
  _Entry(this.name, this.method, this.csize, this.usize, this.localOff);
  final String name;
  final int method;
  final int csize;
  final int usize;
  final int localOff;
}

class _Reader {
  _Reader(this.f) : length = f.lengthSync();
  final RandomAccessFile f;
  final int length;

  Uint8List at(int off, int n) {
    if (off < 0 || n < 0 || off + n > length) throw RangeError('超出文件');
    f.setPositionSync(off);
    final out = f.readSync(n);
    if (out.length != n) throw RangeError('读到的内容不够');
    return out;
  }

  ApkInfo read() {
    if (length > kApkInspectMaxFileBytes) throw const ApkInspectException('文件超过 2GB，太大了，这里不解析它的内容。');
    if (length < 22) throw const ApkInspectException('文件太小，不是安装包。');
    // 结尾记录：固定 22 字节 + 最长 65535 字节的注释，从后往前找
    final tailLen = length < 22 + 0xffff ? length : 22 + 0xffff;
    final tailOff = length - tailLen;
    final tail = at(tailOff, tailLen);
    final td = ByteData.sublistView(tail);
    var eocd = -1;
    for (var o = tailLen - 22; o >= 0; o--) {
      if (td.getUint32(o, Endian.little) == 0x06054b50 && o + 22 + td.getUint16(o + 20, Endian.little) == tailLen) {
        eocd = o;
        break;
      }
    }
    if (eocd < 0) throw const ApkInspectException('它不是安装包：安装包本质上是一个 ZIP 压缩包，这个文件不是，或者没下载完整。');
    final count = td.getUint16(eocd + 10, Endian.little);
    final cdSize = td.getUint32(eocd + 12, Endian.little);
    final cdOff = td.getUint32(eocd + 16, Endian.little);
    if (count == 0xffff || cdSize == 0xffffffff || cdOff == 0xffffffff) throw const ApkInspectException('这个安装包用了超大文件的格式（ZIP64），这里不解析它的内容。');
    if (cdSize > kApkInspectMaxDirectoryBytes) throw const ApkInspectException('这个安装包里的文件太多了，这里不解析它的内容。');
    if (cdOff + cdSize > tailOff + eocd) throw const ApkInspectException('文件内容对不上，像是下载或拷贝到一半的安装包。');

    final cd = at(cdOff, cdSize);
    final d = ByteData.sublistView(cd);
    _Entry? manifest;
    _Entry? arsc;
    _Entry? v1Cert;
    var p = 0;
    for (var i = 0; i < count && p + 46 <= cd.length; i++) {
      if (d.getUint32(p, Endian.little) != 0x02014b50) break;
      final nameLen = d.getUint16(p + 28, Endian.little);
      final skip = 46 + nameLen + d.getUint16(p + 30, Endian.little) + d.getUint16(p + 32, Endian.little);
      if (p + 46 + nameLen > cd.length) break;
      final name = String.fromCharCodes(cd, p + 46, p + 46 + nameLen); // 要找的几个名字都是 ASCII
      final e = _Entry(name, d.getUint16(p + 10, Endian.little), d.getUint32(p + 20, Endian.little), d.getUint32(p + 24, Endian.little), d.getUint32(p + 42, Endian.little));
      if (name == 'AndroidManifest.xml') {
        manifest = e;
      } else if (name == 'resources.arsc') {
        arsc = e;
      } else if (v1Cert == null && name.startsWith('META-INF/') && !name.substring(9).contains('/')) {
        final upper = name.toUpperCase();
        if (upper.endsWith('.RSA') || upper.endsWith('.DSA') || upper.endsWith('.EC')) v1Cert = e;
      }
      p += skip;
    }
    if (manifest == null) throw const ApkInspectException('这是一个压缩包，但里面没有 AndroidManifest.xml，不是安卓安装包。');

    final Uint8List manifestBytes;
    try {
      manifestBytes = _content(manifest, kApkInspectMaxManifestBytes);
    } on _TooBig {
      throw const ApkInspectException('这个安装包的清单大得不正常，这里不解析。');
    }
    final AxmlDocument doc;
    try {
      doc = parseAxml(manifestBytes);
    } on AxmlFormatException {
      throw const ApkInspectException('安装包里的清单（AndroidManifest.xml）读不懂，可能是坏的，或者用了这里不认识的写法。');
    }

    Uint8List? arscBytes;
    var arscTried = false;
    String? text(AxmlAttribute? a) {
      if (a == null) return null;
      if (a.type == kTypeString) return doc.str(a.data);
      if (a.type != kTypeReference || arsc == null) return null;
      if (!arscTried) {
        arscTried = true;
        try {
          arscBytes = _content(arsc, kApkInspectMaxArscBytes);
        } on Exception {
          arscBytes = null; // 太大 / 坏的：应用名就当读不出
        } on RangeError {
          arscBytes = null;
        }
      }
      final table = arscBytes;
      return table == null ? null : arscString(table, a.data);
    }

    AxmlStartElement? root;
    AxmlStartElement? application;
    var depth = 0;
    for (final n in doc.nodes) {
      if (n is AxmlStartElement) {
        depth++;
        if (depth == 1) root = n;
        if (depth == 2 && application == null && n.ns == kNoString && doc.str(n.name) == 'application') application = n;
      } else if (n is AxmlEndElement) {
        depth--;
      }
    }
    if (root == null || doc.str(root.name) != 'manifest') throw const ApkInspectException('安装包里的清单（AndroidManifest.xml）读不懂，可能是坏的，或者用了这里不认识的写法。');
    AxmlAttribute? android(AxmlStartElement? e, int resId) => e?.attributes.where((a) => doc.resIdOf(a) == resId).firstOrNull;
    final pkg = root.attributes.where((a) => a.ns == kNoString && a.type == kTypeString && doc.str(a.name) == 'package').firstOrNull;
    if (pkg == null) throw const ApkInspectException('安装包的清单里没有写包名，不是正常的安装包。');
    final code = android(root, kAttrVersionCode);
    final cert = _certificate(cdOff, v1Cert);
    return ApkInfo(
      packageName: doc.str(pkg.data),
      appName: text(android(application, kAttrLabel)),
      versionName: text(android(root, kAttrVersionName)),
      versionCode: code != null && (code.type == kTypeIntDec || code.type == kTypeIntHex) ? code.data : null,
      certSha256Hex: cert?.$1,
      signScheme: cert?.$2,
    );
  }

  /// 取一个条目解压后的内容。
  Uint8List _content(_Entry e, int cap) {
    if (e.csize > cap || e.usize > cap) throw const _TooBig();
    final head = at(e.localOff, 30);
    final hd = ByteData.sublistView(head);
    if (hd.getUint32(0, Endian.little) != 0x04034b50) throw RangeError('本地文件头不对');
    final raw = at(e.localOff + 30 + hd.getUint16(26, Endian.little) + hd.getUint16(28, Endian.little), e.csize);
    if (e.method == 0) return raw;
    if (e.method != 8) throw const ApkInspectException('安装包用了这里不认识的压缩方式，读不出内容。');
    try {
      return Uint8List.fromList(ZLibDecoder(raw: true).convert(raw));
    } on FormatException {
      throw const ApkInspectException('安装包里的内容解压失败，文件是坏的。');
    }
  }

  /// 包里带的第一张签名证书：(SHA-256, 来自哪种签名)。读不出来返回 null，不抛错。
  (String, String)? _certificate(int cdOff, _Entry? v1Cert) {
    try {
      final fromBlock = _blockCertificate(cdOff);
      if (fromBlock != null) return fromBlock;
    } on RangeError {
      // 签名块是坏的：接着试 v1
    }
    if (v1Cert == null) return null;
    try {
      // PKCS#7：ContentInfo{类型, [0]{SignedData{版本, 摘要算法, 内容, [0] 证书们, …}}}
      final signedData = derParse(_content(v1Cert, kApkInspectMaxSignatureBytes)).seq(2)[1].children.first.seq(3);
      final certs = signedData.where((n) => n.tag == 0xa0).firstOrNull;
      if (certs == null) return null;
      return (crypto.sha256.convert(certs.children.first.encoded).toString(), 'v1');
    } on Exception {
      return null; // 读不懂就当没有
    } on Error {
      return null;
    }
  }

  /// 从 APK 签名块（v3 优先，其次 v2）里取第一张证书。
  (String, String)? _blockCertificate(int cdOff) {
    if (cdOff < 32) return null;
    final foot = at(cdOff - 24, 24);
    if (String.fromCharCodes(foot, 8) != 'APK Sig Block 42') return null;
    final size = ByteData.sublistView(foot).getUint64(0, Endian.little);
    if (size < 24 || size > kApkInspectMaxSignatureBytes || cdOff - size - 8 < 0) return null;
    final block = at(cdOff - size, size - 24); // 一对一对的（长度, 编号, 值）
    final d = ByteData.sublistView(block);
    final found = <int, (int, int)>{}; // 编号 → (值的起点, 长度)
    var p = 0;
    while (p + 12 <= block.length) {
      final len = d.getUint64(p, Endian.little);
      if (len < 4 || p + 8 + len > block.length) break;
      found[d.getUint32(p + 8, Endian.little)] = (p + 12, len - 4);
      p += 8 + len;
    }
    for (final (id, scheme) in const [(0xf05368c0, 'v3'), (0x7109871a, 'v2')]) {
      final slot = found[id];
      if (slot == null) continue;
      // 值 → 签名者们 → 第一个签名者 → 被签的数据 → [摘要们][证书们…] → 第一张证书（每层前面 4 字节长度）
      int open(int off) => off + 4;
      int lenAt(int off) => d.getUint32(off, Endian.little);
      final signers = open(slot.$1);
      final signer = open(signers);
      final signedData = open(signer);
      final certs = signedData + 4 + lenAt(signedData);
      final cert = open(certs);
      final certLen = lenAt(cert);
      final start = cert + 4;
      if (lenAt(certs) < 4 || certLen <= 0 || start + certLen > block.length) continue;
      return (crypto.sha256.convert(Uint8List.sublistView(block, start, start + certLen)).toString(), scheme);
    }
    return null;
  }
}

class _TooBig implements Exception {
  const _TooBig();
}
