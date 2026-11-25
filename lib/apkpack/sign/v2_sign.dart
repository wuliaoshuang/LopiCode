// APK Signature Scheme v2：算整包摘要、组签名块、插到中央目录前面。纯 Dart。
//
// 格式依据：source.android.com 的《APK signature scheme v2》和 AOSP apksig 源码（核对记录见 docs/apk-signing-notes.md）。
// - 把 APK 分成：① ZIP 条目内容（从开头到签名块前）② 签名块 ③ 中央目录 ④ 中央目录结尾记录（EOCD）。
// - ①③④ 各自按 1MB 切块；每块摘要 = SHA-256(0xa5 ‖ 块长 uint32 ‖ 块内容)；
//   总摘要 = SHA-256(0x5a ‖ 块数 uint32 ‖ 各块摘要依次相连)。算 ④ 时，EOCD 里“中央目录偏移”那一格要当成“签名块的起点”。
// - 签名算法只用 0x0103（RSASSA-PKCS1-v1_5 + SHA2-256）。
// - 签名块：uint64 大小 ‖ 若干 (uint64 长度 ‖ uint32 ID ‖ 值) ‖ uint64 大小 ‖ 16 字节魔数；v2 那一项的 ID 是 0x7109871a。
//
// 4096 对齐（照 apksigner 现在的行为做，两处）：
// - 签名块前面补零，让签名块从 4096 的整数倍开始（补的零算进 ①，参与摘要）；
// - 签名块里加一项只用来占位的 (ID 0x42726577)，让整个签名块的大小是 4096 的整数倍。
// 这两处 v2 验证本身不要求（Android 只按偏移找），照做是为了和官方工具签出来的包布局一致、以后要加 v4 / fs-verity 也不用返工。
//
// 入参的几种情况：已有签名块——丢掉旧的、重新签；ZIP64、分卷——明确报错（Android 也不认这样的 APK）；
// EOCD 带注释——照常处理（注释在 ④ 里，一起受保护）；EOCD 后面还有多余字节、中央目录和 EOCD 之间有空隙——明确报错。
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:lopicode/apkpack/apk_pack_contract.dart';
import 'package:lopicode/apkpack/sign/der.dart';
import 'package:lopicode/apkpack/sign/signing_key.dart';

const int kV2BlockId = 0x7109871a;
const int kV2PaddingBlockId = 0x42726577;
const int kV2SigAlgRsaPkcs1Sha256 = 0x0103;
const int _chunkSize = 1024 * 1024;
const int _page = 4096;
const List<int> _magic = [0x41, 0x50, 0x4b, 0x20, 0x53, 0x69, 0x67, 0x20, 0x42, 0x6c, 0x6f, 0x63, 0x6b, 0x20, 0x34, 0x32]; // "APK Sig Block 42"

const int _eocdSignature = 0x06054b50;
const int _zip64LocatorSignature = 0x07064b50;
const int _eocdMinSize = 22;

/// 一个 ZIP（APK）按 v2 签名的眼光分出来的几段。
class ApkZipSections {
  const ApkZipSections({required this.entriesEnd, required this.cdOffset, required this.cdSize, required this.eocdOffset, required this.hasSigningBlock});

  /// ZIP 条目内容到哪里为止（＝已有签名块的起点；没有签名块就等于 [cdOffset]）。
  final int entriesEnd;
  final int cdOffset;
  final int cdSize;
  final int eocdOffset;
  final bool hasSigningBlock;
}

ApkPackException _bad(String why) => ApkPackException('安装包文件结构不对，没法签名：$why', field: 'template');

/// 找出 ZIP 的各段位置。结构不对、ZIP64、分卷都抛 [ApkPackException]。
ApkZipSections locateApkZipSections(Uint8List zip) {
  final data = ByteData.sublistView(zip);
  final len = zip.length;
  if (len < _eocdMinSize) throw _bad('文件太小，不是 ZIP。');
  // EOCD 在文件末尾：22 字节固定部分 + 最多 65535 字节注释；注释长度必须正好等于它后面剩下的字节数。
  var eocd = -1;
  final lowest = len - _eocdMinSize - 0xffff < 0 ? 0 : len - _eocdMinSize - 0xffff;
  for (var pos = len - _eocdMinSize; pos >= lowest; pos--) {
    if (data.getUint32(pos, Endian.little) == _eocdSignature && data.getUint16(pos + 20, Endian.little) == len - pos - _eocdMinSize) {
      eocd = pos;
      break;
    }
  }
  if (eocd < 0) throw _bad('找不到 ZIP 的结尾记录（文件不完整，或者结尾后面还有多余的内容）。');
  if (eocd >= 20 && data.getUint32(eocd - 20, Endian.little) == _zip64LocatorSignature) throw _bad('这是 ZIP64 格式的文件，Android 不支持这样的安装包。');
  final diskNo = data.getUint16(eocd + 4, Endian.little);
  final cdDisk = data.getUint16(eocd + 6, Endian.little);
  final entriesOnDisk = data.getUint16(eocd + 8, Endian.little);
  final entries = data.getUint16(eocd + 10, Endian.little);
  final cdSize = data.getUint32(eocd + 12, Endian.little);
  final cdOffset = data.getUint32(eocd + 16, Endian.little);
  if (entries == 0xffff || cdSize == 0xffffffff || cdOffset == 0xffffffff) throw _bad('这是 ZIP64 格式的文件，Android 不支持这样的安装包。');
  if (diskNo != 0 || cdDisk != 0 || entriesOnDisk != entries) throw _bad('这是分卷的 ZIP。');
  if (cdOffset + cdSize != eocd) throw _bad('ZIP 的目录和结尾记录没有挨在一起。');

  var entriesEnd = cdOffset;
  var hasBlock = false;
  if (cdOffset >= 32 && _matches(zip, cdOffset - 16, _magic)) {
    final size = data.getUint64(cdOffset - 24, Endian.little);
    final start = cdOffset - size - 8;
    if (size < 24 || size > 0x7fffffff || start < 0 || data.getUint64(start, Endian.little) != size) throw _bad('里面已有的签名块是坏的。');
    entriesEnd = start;
    hasBlock = true;
  }
  return ApkZipSections(entriesEnd: entriesEnd, cdOffset: cdOffset, cdSize: cdSize, eocdOffset: eocd, hasSigningBlock: hasBlock);
}

bool _matches(Uint8List data, int offset, List<int> expected) {
  for (var i = 0; i < expected.length; i++) {
    if (data[offset + i] != expected[i]) return false;
  }
  return true;
}

class _DigestSink implements Sink<crypto.Digest> {
  crypto.Digest? value;

  @override
  void add(crypto.Digest data) => value = data;

  @override
  void close() {}
}

List<int> _sha256Of(List<List<int>> parts) {
  final sink = _DigestSink();
  final input = crypto.sha256.startChunkedConversion(sink);
  for (final p in parts) {
    input.add(p);
  }
  input.close();
  return sink.value!.bytes;
}

Uint8List _u32(int v) => Uint8List(4)..buffer.asByteData().setUint32(0, v, Endian.little);

Uint8List _u64(int v) => Uint8List(8)..buffer.asByteData().setUint64(0, v, Endian.little);

/// uint32 长度前缀 + 内容。
Uint8List _lp(List<int> content) => concatBytes([_u32(content.length), content]);

/// v2 的整包摘要：[sections] 依次是 ①③④（④ 要先把中央目录偏移改好）。
Uint8List v2ContentDigest(List<Uint8List> sections) {
  final chunkDigests = BytesBuilder();
  var count = 0;
  for (final section in sections) {
    for (var off = 0; off < section.length; off += _chunkSize) {
      final end = off + _chunkSize < section.length ? off + _chunkSize : section.length;
      chunkDigests.add(
        _sha256Of([
          const [0xa5],
          _u32(end - off),
          Uint8List.sublistView(section, off, end),
        ]),
      );
      count++;
    }
  }
  return Uint8List.fromList(
    _sha256Of([
      const [0x5a],
      _u32(count),
      chunkDigests.toBytes(),
    ]),
  );
}

/// 组 APK Signing Block：v2 那一项 + （需要时）占位项，整块大小凑成 4096 的整数倍。
Uint8List _signingBlock(Uint8List v2Value) {
  var size = 8 + (8 + 4 + v2Value.length) + 8 + 16;
  var padding = 0;
  if (size % _page != 0) {
    padding = _page - size % _page;
    if (padding < 12) padding += _page; // 一项最少 12 字节（长度 8 + ID 4）
    size += padding;
  }
  final out = BytesBuilder()
    ..add(_u64(size - 8))
    ..add(_u64(4 + v2Value.length))
    ..add(_u32(kV2BlockId))
    ..add(v2Value);
  if (padding > 0) {
    out
      ..add(_u64(padding - 8))
      ..add(_u32(kV2PaddingBlockId))
      ..add(Uint8List(padding - 12));
  }
  out
    ..add(_u64(size - 8))
    ..add(_magic);
  return out.toBytes();
}

/// 给一个已经对齐好的 ZIP（要 v1 的话，v1 的三个文件已经在里面）加上 v2 签名，返回签好的整个文件。
/// 之后这个文件一个字节都不能再动。
Uint8List v2Sign(Uint8List alignedZip, ApkSigningKey key) {
  final k = asRsaSigningKey(key);
  final s = locateApkZipSections(alignedZip);

  // ① 条目内容，后面补零到 4096 的整数倍。
  final padBefore = (_page - s.entriesEnd % _page) % _page;
  final before = Uint8List(s.entriesEnd + padBefore)..setRange(0, s.entriesEnd, alignedZip);
  final centralDir = Uint8List.sublistView(alignedZip, s.cdOffset, s.eocdOffset);
  // ④ 算摘要时，中央目录偏移那一格 = 签名块的起点。
  final eocd = Uint8List.fromList(Uint8List.sublistView(alignedZip, s.eocdOffset));
  final eocdData = ByteData.sublistView(eocd);
  eocdData.setUint32(16, before.length, Endian.little);

  final digest = v2ContentDigest([before, centralDir, eocd]);
  final signedData = concatBytes([
    _lp(_lp(concatBytes([_u32(kV2SigAlgRsaPkcs1Sha256), _lp(digest)]))), // 摘要们
    _lp(_lp(k.certificateDer)), // 证书们
    _lp(const []), // 附加属性：没有
  ]);
  final signer = concatBytes([
    _lp(signedData),
    _lp(_lp(concatBytes([_u32(kV2SigAlgRsaPkcs1Sha256), _lp(k.sign(signedData))]))), // 签名们
    _lp(k.cert.spki), // 公钥
  ]);
  final block = _signingBlock(_lp(_lp(signer)));

  final newCdOffset = before.length + block.length;
  if (newCdOffset + centralDir.length + eocd.length > 0xffffffff) throw _bad('签完以后超过 4GB 了。');
  eocdData.setUint32(16, newCdOffset, Endian.little);
  return concatBytes([before, block, centralDir, eocd]);
}
