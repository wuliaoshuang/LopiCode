// 字符串池（ResStringPool）的读和写。两种编码都认：UTF-8（flags 带 UTF8_FLAG=1<<8）和 UTF-16。
// UTF-8 池子里的字符串按 aapt2 的做法用“改良 UTF-8”：基本平面以外的字符（表情）写成两个代理项、各占 3 字节；
// 读的时候标准 4 字节写法和代理项写法都认。
import 'dart:typed_data';

import 'package:lopicode/apkpack/axml/axml_model.dart';

const int _kSortedFlag = 1 << 0;
const int _kUtf8Flag = 1 << 8;
const int _kPoolHeaderSize = 0x1C;

/// 解析 [off] 处的字符串池块，返回池子和块的总大小。
(AxmlStringPool, int) readStringPool(ByteReader r, int off) {
  final type = r.u16(off, '字符串池');
  final headerSize = r.u16(off + 2, '字符串池');
  final size = r.u32(off + 4, '字符串池');
  if (type != kResStringPoolType) throw AxmlFormatException('应该是字符串池（类型 0x0001），实际是 0x${type.toRadixString(16)}');
  if (headerSize != _kPoolHeaderSize) throw AxmlFormatException('字符串池头部长度应为 28，实际 $headerSize');
  if (size < headerSize || off + size > r.length) throw AxmlFormatException('字符串池的大小 $size 超出了文件');
  final count = r.u32(off + 8, '字符串池');
  final styleCount = r.u32(off + 12, '字符串池');
  final flags = r.u32(off + 16, '字符串池');
  final stringsStart = r.u32(off + 20, '字符串池');
  if (styleCount != 0) throw const AxmlFormatException('字符串池带样式（styleCount≠0），清单里不该有，这里不支持');
  if ((flags & ~(_kSortedFlag | _kUtf8Flag)) != 0) throw AxmlFormatException('字符串池有不认识的标志 0x${flags.toRadixString(16)}');
  if (headerSize + count * 4 > size) throw const AxmlFormatException('字符串池的偏移表超出了块');
  final utf8 = (flags & _kUtf8Flag) != 0;
  final end = off + size;
  final strings = <String>[];
  for (var i = 0; i < count; i++) {
    final so = off + stringsStart + r.u32(off + headerSize + i * 4, '字符串偏移表');
    if (so >= end) throw AxmlFormatException('第 $i 条字符串的偏移超出了字符串池');
    strings.add(utf8 ? _readUtf8(r, so, end, i) : _readUtf16(r, so, end, i));
  }
  return (AxmlStringPool(strings: strings, utf8: utf8, sorted: (flags & _kSortedFlag) != 0), size);
}

String _readUtf16(ByteReader r, int off, int end, int i) {
  var len = r.u16(off, '字符串长度');
  off += 2;
  if ((len & 0x8000) != 0) {
    len = ((len & 0x7FFF) << 16) | r.u16(off, '字符串长度');
    off += 2;
  }
  if (off + len * 2 + 2 > end) throw AxmlFormatException('第 $i 条字符串超出了字符串池');
  final units = List<int>.generate(len, (k) => r.u16(off + k * 2));
  return String.fromCharCodes(units);
}

String _readUtf8(ByteReader r, int off, int end, int i) {
  // 先是 UTF-16 长度（用不上，跳过），再是字节数；各 1 或 2 字节
  if ((r.u8(off, '字符串长度') & 0x80) != 0) off++;
  off++;
  var n = r.u8(off, '字符串长度');
  off++;
  if ((n & 0x80) != 0) {
    n = ((n & 0x7F) << 8) | r.u8(off, '字符串长度');
    off++;
  }
  if (off + n + 1 > end) throw AxmlFormatException('第 $i 条字符串超出了字符串池');
  return decodeModifiedUtf8(r.bytes, off, n, i);
}

/// 解 UTF-8：标准写法和“代理项各 3 字节”的写法都认，得到 UTF-16 码元序列。
String decodeModifiedUtf8(Uint8List b, int off, int n, int index) {
  final units = <int>[];
  final end = off + n;
  Never bad() => throw AxmlFormatException('第 $index 条字符串不是合法的 UTF-8');
  int cont(int p) {
    if (p >= end || (b[p] & 0xC0) != 0x80) bad();
    return b[p] & 0x3F;
  }

  var p = off;
  while (p < end) {
    final c = b[p];
    if (c < 0x80) {
      units.add(c);
      p += 1;
    } else if ((c & 0xE0) == 0xC0) {
      units.add(((c & 0x1F) << 6) | cont(p + 1));
      p += 2;
    } else if ((c & 0xF0) == 0xE0) {
      units.add(((c & 0x0F) << 12) | (cont(p + 1) << 6) | cont(p + 2));
      p += 3;
    } else if ((c & 0xF8) == 0xF0) {
      final cp = ((c & 0x07) << 18) | (cont(p + 1) << 12) | (cont(p + 2) << 6) | cont(p + 3);
      if (cp < 0x10000 || cp > 0x10FFFF) bad();
      units.add(0xD800 + ((cp - 0x10000) >> 10));
      units.add(0xDC00 + ((cp - 0x10000) & 0x3FF));
      p += 4;
    } else {
      bad();
    }
  }
  return String.fromCharCodes(units);
}

/// 按 UTF-16 码元逐个编码（代理项各写 3 字节），和 aapt2 写 UTF-8 池子的做法一致。
Uint8List encodeModifiedUtf8(String s) {
  final out = BytesBuilder(copy: false);
  for (final u in s.codeUnits) {
    if (u < 0x80) {
      out.addByte(u);
    } else if (u < 0x800) {
      out.addByte(0xC0 | (u >> 6));
      out.addByte(0x80 | (u & 0x3F));
    } else {
      out.addByte(0xE0 | (u >> 12));
      out.addByte(0x80 | ((u >> 6) & 0x3F));
      out.addByte(0x80 | (u & 0x3F));
    }
  }
  return out.takeBytes();
}

/// 把池子写成一个完整的块（含头部，已补齐到 4 字节）。
Uint8List writeStringPool(AxmlStringPool pool) {
  final data = ByteWriter();
  final offsets = <int>[];
  for (final s in pool.strings) {
    offsets.add(data.length);
    if (pool.utf8) {
      final enc = encodeModifiedUtf8(s);
      if (s.length > 0x7FFF || enc.length > 0x7FFF) throw const AxmlFormatException('字符串太长，UTF-8 字符串池放不下（上限 32767）');
      _len8(data, s.length);
      _len8(data, enc.length);
      data.bytes(enc);
      data.u8(0);
    } else {
      final n = s.length;
      if (n > 0x7FFFFFFF) throw const AxmlFormatException('字符串太长');
      if (n > 0x7FFF) {
        data.u16(0x8000 | (n >> 16));
        data.u16(n & 0xFFFF);
      } else {
        data.u16(n);
      }
      for (final u in s.codeUnits) {
        data.u16(u);
      }
      data.u16(0);
    }
  }
  data.padTo4();
  final body = data.take();
  final stringsStart = _kPoolHeaderSize + offsets.length * 4;
  final w = ByteWriter()
    ..u16(kResStringPoolType)
    ..u16(_kPoolHeaderSize)
    ..u32(stringsStart + body.length)
    ..u32(offsets.length)
    ..u32(0)
    ..u32((pool.utf8 ? _kUtf8Flag : 0) | (pool.sorted ? _kSortedFlag : 0))
    ..u32(stringsStart)
    ..u32(0);
  for (final o in offsets) {
    w.u32(o);
  }
  w.bytes(body);
  return w.take();
}

void _len8(ByteWriter w, int n) {
  if (n > 0x7F) {
    w.u8(0x80 | (n >> 8));
    w.u8(n & 0xFF);
  } else {
    w.u8(n);
  }
}
