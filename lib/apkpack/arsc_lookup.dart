// 从 resources.arsc（资源表）里按资源号查一条字符串。只给“看安装包信息”用：
// 别处打出来的安装包，应用名常常不直接写在清单里，而是写成“见资源表第几号”，要到这里查。
// 只读、不改；只认字符串和“指向另一条资源”的值；查不到一律返回 null，不抛错。
// 格式事实见 docs/apk-format-notes.md 的“资源表”一节。
import 'dart:convert';
import 'dart:typed_data';

import 'package:lopicode/apkpack/axml/axml_strings.dart';

const int _kTableType = 0x0002;
const int _kStringPoolType = 0x0001;
const int _kPackageType = 0x0200;
const int _kTypeType = 0x0201;
const int _kValueReference = 0x01;
const int _kValueString = 0x03;

/// 查 [resId]（0xPPTTEEEE）对应的字符串。优先取“默认配置”（不分语言、屏幕）的那一条，没有就取遇到的第一条。
String? arscString(Uint8List arsc, int resId) {
  try {
    return _Table(arsc).string(resId, 0);
  } on RangeError {
    return null; // 文件是坏的 / 被截断
  } on FormatException {
    return null;
  }
}

class _Table {
  _Table(this.bytes) : d = ByteData.sublistView(bytes);
  final Uint8List bytes;
  final ByteData d;

  int u8(int o) => d.getUint8(o);
  int u16(int o) => d.getUint16(o, Endian.little);
  int u32(int o) => d.getUint32(o, Endian.little);

  String? string(int resId, int depth) {
    if (depth > 5 || bytes.length < 12 || u16(0) != _kTableType) return null;
    final total = u32(4) < bytes.length ? u32(4) : bytes.length;
    final pkgId = resId >>> 24;
    final typeId = (resId >> 16) & 0xff;
    final entry = resId & 0xffff;
    int? globalPool;
    (int, int)? fallback; // (值类型, 值)
    var off = u16(2);
    while (off + 8 <= total) {
      final type = u16(off);
      final size = u32(off + 4);
      if (size < 8 || off + size > total) break;
      if (type == _kStringPoolType) {
        globalPool ??= off;
      } else if (type == _kPackageType && u32(off + 8) == pkgId) {
        var p = off + u16(off + 2);
        final end = off + size;
        while (p + 8 <= end) {
          final t = u16(p);
          final s = u32(p + 4);
          if (s < 8 || p + s > end) break;
          if (t == _kTypeType && u8(p + 8) == typeId) {
            final v = _entryValue(p, entry);
            if (v != null) {
              if (_isDefaultConfig(p)) {
                fallback = v;
                break;
              }
              fallback ??= v;
            }
          }
          p += s;
        }
      }
      off += size;
    }
    if (fallback == null) return null;
    final (valueType, data) = fallback;
    if (valueType == _kValueString && globalPool != null) return _poolString(globalPool, data);
    if (valueType == _kValueReference && data != resId) return string(data, depth + 1);
    return null;
  }

  /// 这一块是不是“默认配置”：配置结构里除了开头的长度，其余全是 0。
  bool _isDefaultConfig(int typeChunk) {
    final cfg = typeChunk + 20;
    final size = u32(cfg);
    for (var i = cfg + 4; i < cfg + size && i < bytes.length; i++) {
      if (bytes[i] != 0) return false;
    }
    return true;
  }

  /// 在一个“类型块”里找第 [entry] 条的值：返回 (值类型, 值)；没有这一条或它是复合值（样式、数组）返回 null。
  (int, int)? _entryValue(int chunk, int entry) {
    final headerSize = u16(chunk + 2);
    final flags = u8(chunk + 9);
    final count = u32(chunk + 12);
    final entriesStart = u32(chunk + 16);
    final table = chunk + headerSize;
    int? rel;
    if ((flags & 0x01) != 0) {
      // 稀疏表：一对一对的（第几条, 偏移÷4）
      for (var i = 0; i < count; i++) {
        if (u16(table + i * 4) == entry) {
          rel = u16(table + i * 4 + 2) * 4;
          break;
        }
      }
    } else if (entry < count) {
      if ((flags & 0x02) != 0) {
        final v = u16(table + entry * 2);
        if (v != 0xffff) rel = v * 4;
      } else {
        final v = u32(table + entry * 4);
        if (v != 0xffffffff) rel = v;
      }
    }
    if (rel == null) return null;
    final e = chunk + entriesStart + rel;
    final entryFlags = u16(e + 2);
    if ((entryFlags & 0x0001) != 0) return null; // 复合值
    if ((entryFlags & 0x0008) != 0) return (entryFlags >> 8, u32(e + 4)); // 紧凑写法：值直接放在条目里
    final value = e + u16(e);
    return (u8(value + 3), u32(value + 4));
  }

  /// 字符串池里第 [index] 条。
  String? _poolString(int pool, int index) {
    final headerSize = u16(pool + 2);
    final size = u32(pool + 4);
    final count = u32(pool + 8);
    final flags = u32(pool + 16);
    final stringsStart = u32(pool + 20);
    if (index < 0 || index >= count) return null;
    final end = pool + size;
    var o = pool + stringsStart + u32(pool + headerSize + index * 4);
    if (o >= end) return null;
    if ((flags & (1 << 8)) != 0) {
      // UTF-8：先是字符数、再是字节数，各占 1 或 2 字节
      o += (u8(o) & 0x80) != 0 ? 2 : 1;
      var n = u8(o++);
      if ((n & 0x80) != 0) n = ((n & 0x7f) << 8) | u8(o++);
      if (o + n > end) return null;
      try {
        return decodeModifiedUtf8(bytes, o, n, index);
      } on Exception {
        return utf8.decode(Uint8List.sublistView(bytes, o, o + n), allowMalformed: true);
      }
    }
    var n = u16(o);
    o += 2;
    if ((n & 0x8000) != 0) {
      n = ((n & 0x7fff) << 16) | u16(o);
      o += 2;
    }
    if (o + n * 2 > end) return null;
    return String.fromCharCodes([for (var i = 0; i < n; i++) u16(o + i * 2)]);
  }
}
