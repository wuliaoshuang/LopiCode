// 写 ZIP：条目顺序照给的来、时间戳固定，同样输入一定产出同样字节。
// 不压缩的条目数据起点按 4 字节对齐（等价 zipalign 4；.so 按 16KB 页对齐），靠本地文件头的 extra 字段垫位置。
// 不写 ZIP64、不写数据描述符；超限直接报错。
import 'dart:convert';
import 'dart:typed_data';

import 'package:lopicode/apkpack/zip/zip_model.dart';

/// 固定的时间戳：1980-01-01 00:00:00（DOS 格式能表示的最早时间）。
const int _kDosTime = 0;
const int _kDosDate = 0x0021;

/// 垫位置用的 extra 字段编号（和官方 apksigner 用的同一个：0xd935，内容是对齐值 + 若干个 0）。
const int _kAlignExtraId = 0xd935;

const int kZipMaxEntries = 0xFFFF - 1;

/// 不压缩条目的对齐值：共享库按页（16KB，新机型的页大小；也是 4KB 的倍数），其余 4 字节。
int alignmentFor(String name) => name.endsWith('.so') ? 16384 : 4;

Uint8List writeZip(List<ZipEntry> entries) {
  if (entries.length > kZipMaxEntries) throw ZipFormatException('文件太多（${entries.length} 个），超过 ZIP 的上限 $kZipMaxEntries');
  final out = BytesBuilder(copy: false);
  final central = BytesBuilder(copy: false);
  final seen = <String>{};
  for (final e in entries) {
    if (!seen.add(e.name)) throw ZipFormatException('有两个同名条目：${e.name}');
    final name = utf8.encode(e.name);
    if (name.isEmpty || name.length > 0xFFFF) throw ZipFormatException('文件名太长或为空：${e.name}');
    if (e.raw.length >= 0xFFFFFFFF || e.size >= 0xFFFFFFFF) throw ZipFormatException('${e.name} 太大，超过 4GB');
    final offset = out.length;
    if (offset >= 0xFFFFFFFF) throw const ZipFormatException('安装包超过 4GB，放不下');
    var extra = Uint8List(0);
    if (e.method == kZipStored) {
      final align = alignmentFor(e.name);
      final dataStart = offset + 30 + name.length;
      if (dataStart % align != 0) {
        // extra 至少 6 字节（编号 2 + 长度 2 + 对齐值 2），不够就再多垫一个对齐周期
        var pad = align - dataStart % align;
        while (pad < 6) {
          pad += align;
        }
        extra = Uint8List(pad);
        ByteData.sublistView(extra)
          ..setUint16(0, _kAlignExtraId, Endian.little)
          ..setUint16(2, pad - 4, Endian.little)
          ..setUint16(4, align, Endian.little);
      }
    }
    // 文件名不是纯 ASCII 时置第 11 位，表示名字是 UTF-8
    final flags = name.any((b) => b >= 0x80) ? 0x0800 : 0;
    final version = e.method == kZipDeflated ? 20 : 10;
    final local = ByteData(30)
      ..setUint32(0, 0x04034b50, Endian.little)
      ..setUint16(4, version, Endian.little)
      ..setUint16(6, flags, Endian.little)
      ..setUint16(8, e.method, Endian.little)
      ..setUint16(10, _kDosTime, Endian.little)
      ..setUint16(12, _kDosDate, Endian.little)
      ..setUint32(14, e.crc32, Endian.little)
      ..setUint32(18, e.raw.length, Endian.little)
      ..setUint32(22, e.size, Endian.little)
      ..setUint16(26, name.length, Endian.little)
      ..setUint16(28, extra.length, Endian.little);
    out
      ..add(local.buffer.asUint8List())
      ..add(name)
      ..add(extra)
      ..add(e.raw);
    final c = ByteData(46)
      ..setUint32(0, 0x02014b50, Endian.little)
      ..setUint16(4, version, Endian.little)
      ..setUint16(6, version, Endian.little)
      ..setUint16(8, flags, Endian.little)
      ..setUint16(10, e.method, Endian.little)
      ..setUint16(12, _kDosTime, Endian.little)
      ..setUint16(14, _kDosDate, Endian.little)
      ..setUint32(16, e.crc32, Endian.little)
      ..setUint32(20, e.raw.length, Endian.little)
      ..setUint32(24, e.size, Endian.little)
      ..setUint16(28, name.length, Endian.little)
      ..setUint32(42, offset, Endian.little);
    central
      ..add(c.buffer.asUint8List())
      ..add(name);
  }
  final cdOffset = out.length;
  final cd = central.takeBytes();
  if (cdOffset >= 0xFFFFFFFF || cdOffset + cd.length >= 0xFFFFFFFF) throw const ZipFormatException('安装包超过 4GB，放不下');
  final end = ByteData(22)
    ..setUint32(0, 0x06054b50, Endian.little)
    ..setUint16(8, entries.length, Endian.little)
    ..setUint16(10, entries.length, Endian.little)
    ..setUint32(12, cd.length, Endian.little)
    ..setUint32(16, cdOffset, Endian.little);
  out
    ..add(cd)
    ..add(end.buffer.asUint8List());
  return out.takeBytes();
}
