// 读 ZIP（只读模板用）：从末尾找中央目录，逐条取出原始字节。不支持 ZIP64、加密、分卷、deflate 以外的压缩。
import 'dart:convert';
import 'dart:typed_data';

import 'package:lopicode/apkpack/zip/zip_model.dart';

const int _kEocdSig = 0x06054b50;
const int _kCentralSig = 0x02014b50;
const int _kLocalSig = 0x04034b50;

List<ZipEntry> readZip(Uint8List bytes) {
  final d = ByteData.sublistView(bytes);
  int u16(int o) => d.getUint16(o, Endian.little);
  int u32(int o) => d.getUint32(o, Endian.little);
  void need(int off, int n, String what) {
    if (off < 0 || off + n > bytes.length) throw ZipFormatException('$what 超出了文件（文件被截断）');
  }

  if (bytes.length < 22) throw const ZipFormatException('文件太短，不是 ZIP');
  // 结尾记录固定 22 字节 + 最长 65535 字节的注释，从后往前找
  var eocd = -1;
  for (var o = bytes.length - 22; o >= 0 && o >= bytes.length - 22 - 0xFFFF; o--) {
    if (u32(o) == _kEocdSig && o + 22 + u16(o + 20) == bytes.length) {
      eocd = o;
      break;
    }
  }
  if (eocd < 0) throw const ZipFormatException('找不到 ZIP 的结尾记录，不是 ZIP 或文件被截断');
  if (u16(eocd + 4) != 0 || u16(eocd + 6) != 0) throw const ZipFormatException('不支持分卷 ZIP');
  final count = u16(eocd + 10);
  final cdSize = u32(eocd + 12);
  final cdOff = u32(eocd + 16);
  if (count == 0xFFFF || cdSize == 0xFFFFFFFF || cdOff == 0xFFFFFFFF) throw const ZipFormatException('不支持 ZIP64');
  if (u16(eocd + 8) != count) throw const ZipFormatException('ZIP 结尾记录里的条目数前后不一致');
  need(cdOff, cdSize, '中央目录');
  if (cdOff + cdSize > eocd) throw const ZipFormatException('中央目录的位置不对');

  final out = <ZipEntry>[];
  final names = <String>{};
  var p = cdOff;
  for (var i = 0; i < count; i++) {
    need(p, 46, '中央目录第 ${i + 1} 条');
    if (u32(p) != _kCentralSig) throw ZipFormatException('中央目录第 ${i + 1} 条的标记不对');
    final flags = u16(p + 8);
    final method = u16(p + 10);
    final crc = u32(p + 16);
    final csize = u32(p + 20);
    final usize = u32(p + 24);
    final nameLen = u16(p + 28);
    final extraLen = u16(p + 30);
    final commentLen = u16(p + 32);
    final localOff = u32(p + 42);
    need(p + 46, nameLen + extraLen + commentLen, '中央目录第 ${i + 1} 条');
    final nameBytes = Uint8List.sublistView(bytes, p + 46, p + 46 + nameLen);
    final name = utf8.decode(nameBytes, allowMalformed: true);
    p += 46 + nameLen + extraLen + commentLen;
    if ((flags & 0x0001) != 0) throw ZipFormatException('$name 是加密的，不支持');
    if (method != kZipStored && method != kZipDeflated) throw ZipFormatException('$name 用了不支持的压缩方式（$method）');
    if (csize == 0xFFFFFFFF || usize == 0xFFFFFFFF || localOff == 0xFFFFFFFF) throw const ZipFormatException('不支持 ZIP64');
    if (method == kZipStored && csize != usize) throw ZipFormatException('$name 不压缩，但两个大小不一样');
    if (!names.add(name)) throw ZipFormatException('ZIP 里有两个同名条目：$name');
    need(localOff, 30, '$name 的本地文件头');
    if (u32(localOff) != _kLocalSig) throw ZipFormatException('$name 的本地文件头标记不对');
    final dataOff = localOff + 30 + u16(localOff + 26) + u16(localOff + 28);
    need(dataOff, csize, '$name 的数据');
    if (dataOff + csize > cdOff) throw ZipFormatException('$name 的数据和中央目录重叠了');
    if (name.endsWith('/')) continue; // 目录条目不要
    out.add(ZipEntry.raw(name: name, method: method, raw: Uint8List.sublistView(bytes, dataOff, dataOff + csize), crc32: crc, size: usize));
  }
  if (p != cdOff + cdSize) throw const ZipFormatException('中央目录的长度和内容对不上');
  return out;
}
