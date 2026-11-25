// ZIP 条目的内存表示和公用小工具（CRC-32）。格式事实见 docs/apk-format-notes.md。
import 'dart:io';
import 'dart:typed_data';

/// ZIP 读写时的格式问题。消息是技术性的，门面再包成大白话。
class ZipFormatException implements Exception {
  const ZipFormatException(this.message);
  final String message;
  @override
  String toString() => 'ZipFormatException: $message';
}

const int kZipStored = 0;
const int kZipDeflated = 8;

/// 一个条目。[raw] 是 ZIP 里实际存放的字节（[method] 为 deflate 时是压缩后的原始 deflate 流）。
/// 从模板读来的条目直接带着压缩好的字节走，不重压，又快又保证字节不变。
class ZipEntry {
  ZipEntry._(this.name, this.method, this.raw, this.crc32, this.size, [this._plain]);

  /// 不压缩地存。
  factory ZipEntry.stored(String name, Uint8List data) => ZipEntry._(name, kZipStored, data, crc32Of(data), data.length, data);

  /// deflate 压缩（如果压完没变小就改成不压缩）。
  factory ZipEntry.deflated(String name, Uint8List data, {int level = 6}) {
    final packed = Uint8List.fromList(ZLibEncoder(raw: true, level: level).convert(data));
    if (packed.length >= data.length) return ZipEntry.stored(name, data);
    return ZipEntry._(name, kZipDeflated, packed, crc32Of(data), data.length, data);
  }

  /// 读 ZIP 时用：已知各字段。
  factory ZipEntry.raw({required String name, required int method, required Uint8List raw, required int crc32, required int size}) => ZipEntry._(name, method, raw, crc32, size);

  final String name;
  final int method;
  final Uint8List raw;
  final int crc32;

  /// 解压后的大小。
  final int size;

  /// 自己刚压的条目留着原文：签名时要用解压后的内容，不用再解一遍、再算一遍校验值。从 ZIP 读来的条目没有。
  final Uint8List? _plain;

  /// 解压后的内容；顺带核对大小和 CRC，对不上说明文件坏了。
  Uint8List content() {
    final plain = _plain;
    if (plain != null) return plain;
    Uint8List out;
    if (method == kZipStored) {
      out = raw;
    } else {
      try {
        out = Uint8List.fromList(ZLibDecoder(raw: true).convert(raw));
      } on FormatException {
        throw ZipFormatException('$name 解压失败，压缩数据是坏的');
      }
    }
    if (out.length != size || crc32Of(out) != crc32) throw ZipFormatException('$name 的内容和校验值对不上，文件是坏的');
    return out;
  }
}

final Uint32List _crcTable = () {
  final t = Uint32List(256);
  for (var n = 0; n < 256; n++) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
    }
    t[n] = c;
  }
  return t;
}();

int crc32Of(List<int> data) {
  var c = 0xFFFFFFFF;
  for (final b in data) {
    c = _crcTable[(c ^ b) & 0xFF] ^ (c >> 8);
  }
  return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}
