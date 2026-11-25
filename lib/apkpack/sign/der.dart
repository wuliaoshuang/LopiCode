// DER 编码与解析：只做打包签名用得到的那一小部分（定长长度、低号标签）。
// 纯 Dart。出错只说“哪里不对”，绝不把内容带进报错文字（里面可能是私钥）。
import 'dart:convert';
import 'dart:typed_data';

/// DER 内容读不懂。[message] 不含任何数据内容。
class DerException implements Exception {
  const DerException(this.message);
  final String message;

  @override
  String toString() => message;
}

const int derTagInteger = 0x02;
const int derTagBitString = 0x03;
const int derTagOctetString = 0x04;
const int derTagNull = 0x05;
const int derTagOid = 0x06;
const int derTagUtf8String = 0x0c;
const int derTagUtcTime = 0x17;
const int derTagGeneralizedTime = 0x18;
const int derTagSequence = 0x30;
const int derTagSet = 0x31;

Uint8List concatBytes(Iterable<List<int>> parts) {
  final out = BytesBuilder(copy: false);
  for (final p in parts) {
    out.add(p);
  }
  return out.toBytes();
}

/// 非负大整数 → 大端字节（[length] 给了就左边补零到这么长）。
Uint8List bigIntToBytes(BigInt value, [int? length]) {
  if (value.isNegative) throw const DerException('整数不能是负的');
  final n = length ?? ((value.bitLength + 7) >> 3);
  final out = Uint8List(n);
  var v = value;
  final mask = BigInt.from(0xff);
  for (var i = n - 1; i >= 0; i--) {
    out[i] = (v & mask).toInt();
    v = v >> 8;
  }
  if (v != BigInt.zero) throw const DerException('整数放不进指定的长度');
  return out;
}

BigInt bytesToBigInt(List<int> bytes) {
  var v = BigInt.zero;
  for (final b in bytes) {
    v = (v << 8) | BigInt.from(b & 0xff);
  }
  return v;
}

Uint8List derTlv(int tag, List<int> content) {
  final len = content.length;
  final head = <int>[tag];
  if (len < 0x80) {
    head.add(len);
  } else {
    final lenBytes = <int>[];
    for (var v = len; v > 0; v >>= 8) {
      lenBytes.insert(0, v & 0xff);
    }
    head
      ..add(0x80 | lenBytes.length)
      ..addAll(lenBytes);
  }
  return concatBytes([head, content]);
}

Uint8List derSeq(Iterable<List<int>> items) => derTlv(derTagSequence, concatBytes(items));

/// 只用在单个成员的 SET 上（多个成员 DER 要求排序，这里用不到）。
Uint8List derSetOfOne(List<int> item) => derTlv(derTagSet, item);

Uint8List derInt(BigInt value) {
  var bytes = bigIntToBytes(value);
  if (bytes.isEmpty || bytes[0] & 0x80 != 0) {
    bytes = Uint8List.fromList([0, ...bytes]);
  }
  return derTlv(derTagInteger, bytes);
}

Uint8List derSmallInt(int value) => derInt(BigInt.from(value));

Uint8List derNull() => Uint8List.fromList(const [derTagNull, 0]);

Uint8List derOctets(List<int> bytes) => derTlv(derTagOctetString, bytes);

/// BIT STRING，没有多余的位。
Uint8List derBits(List<int> bytes) => derTlv(
  derTagBitString,
  concatBytes([
    const [0],
    bytes,
  ]),
);

Uint8List derUtf8(String text) => derTlv(derTagUtf8String, utf8.encode(text));

Uint8List derBool(bool value) => Uint8List.fromList([0x01, 0x01, if (value) 0xff else 0x00]);

/// `[n] EXPLICIT`。
Uint8List derExplicit(int n, List<int> inner) => derTlv(0xa0 | n, inner);

Uint8List derOid(String dotted) {
  final parts = dotted.split('.').map(int.parse).toList();
  final out = <int>[parts[0] * 40 + parts[1]];
  for (final part in parts.skip(2)) {
    final chunk = <int>[part & 0x7f];
    for (var v = part >> 7; v > 0; v >>= 7) {
      chunk.insert(0, 0x80 | (v & 0x7f));
    }
    out.addAll(chunk);
  }
  return derTlv(derTagOid, out);
}

/// X.509 的时间（RFC 5280 §4.1.2.5）：2049 年及以前必须用 UTCTime（两位年份），
/// 2050 年及以后必须用 GeneralizedTime（四位年份）。都精确到秒、以 Z 结尾。
Uint8List derTime(DateTime time) {
  final t = time.toUtc();
  String two(int v) => v.toString().padLeft(2, '0');
  final tail = '${two(t.month)}${two(t.day)}${two(t.hour)}${two(t.minute)}${two(t.second)}Z';
  if (t.year >= 1950 && t.year <= 2049) {
    return derTlv(derTagUtcTime, ascii.encode('${two(t.year % 100)}$tail'));
  }
  if (t.year < 1950 || t.year > 9999) throw const DerException('年份超出证书能表示的范围');
  return derTlv(derTagGeneralizedTime, ascii.encode('${t.year.toString().padLeft(4, '0')}$tail'));
}

/// 解析出来的一个 DER 元素（不复制数据）。
class DerNode {
  DerNode._(this._buf, this.tag, this._start, this._contentStart, this._end);

  final Uint8List _buf;
  final int tag;
  final int _start;
  final int _contentStart;
  final int _end;

  Uint8List get content => Uint8List.sublistView(_buf, _contentStart, _end);

  /// 连头带内容的原始字节。
  Uint8List get encoded => Uint8List.sublistView(_buf, _start, _end);

  List<DerNode> get children {
    if (tag & 0x20 == 0) throw const DerException('这里应该是一个组合结构');
    final out = <DerNode>[];
    var pos = _contentStart;
    while (pos < _end) {
      final node = _readNode(_buf, pos, _end);
      out.add(node);
      pos = node._end;
    }
    return out;
  }

  /// 当成 SEQUENCE 取成员，至少 [min] 个。
  List<DerNode> seq([int min = 0]) {
    if (tag != derTagSequence) throw const DerException('这里应该是 SEQUENCE');
    final list = children;
    if (list.length < min) throw const DerException('SEQUENCE 的成员不够');
    return list;
  }

  BigInt get asInt {
    if (tag != derTagInteger || _end == _contentStart) throw const DerException('这里应该是整数');
    if (_buf[_contentStart] & 0x80 != 0) throw const DerException('整数不能是负的');
    return bytesToBigInt(content);
  }

  int get asSmallInt {
    final v = asInt;
    if (v.bitLength > 31) throw const DerException('整数太大');
    return v.toInt();
  }

  Uint8List get asOctets {
    if (tag != derTagOctetString) throw const DerException('这里应该是 OCTET STRING');
    return content;
  }

  Uint8List get asBits {
    if (tag != derTagBitString || _end == _contentStart || _buf[_contentStart] != 0) {
      throw const DerException('这里应该是整字节的 BIT STRING');
    }
    return Uint8List.sublistView(_buf, _contentStart + 1, _end);
  }

  String get asOid {
    if (tag != derTagOid || _end == _contentStart) throw const DerException('这里应该是 OID');
    final c = content;
    final parts = <int>[c[0] ~/ 40, c[0] % 40];
    var v = 0;
    for (var i = 1; i < c.length; i++) {
      v = (v << 7) | (c[i] & 0x7f);
      if (v > 0xfffffff) throw const DerException('OID 太长');
      if (c[i] & 0x80 == 0) {
        parts.add(v);
        v = 0;
      }
    }
    return parts.join('.');
  }

  DateTime get asTime {
    final String s;
    try {
      s = ascii.decode(content);
    } on FormatException {
      throw const DerException('时间写法不对');
    }
    final RegExpMatch? m;
    final int year;
    if (tag == derTagUtcTime) {
      m = RegExp(r'^(\d\d)(\d\d)(\d\d)(\d\d)(\d\d)(\d\d)Z$').firstMatch(s);
      if (m == null) throw const DerException('时间写法不对');
      final yy = int.parse(m.group(1)!);
      year = yy >= 50 ? 1900 + yy : 2000 + yy;
    } else if (tag == derTagGeneralizedTime) {
      m = RegExp(r'^(\d{4})(\d\d)(\d\d)(\d\d)(\d\d)(\d\d)Z$').firstMatch(s);
      if (m == null) throw const DerException('时间写法不对');
      year = int.parse(m.group(1)!);
    } else {
      throw const DerException('这里应该是时间');
    }
    int g(int i) => int.parse(m!.group(i)!);
    return DateTime.utc(year, g(2), g(3), g(4), g(5), g(6));
  }
}

DerNode _readNode(Uint8List buf, int pos, int limit) {
  if (pos + 2 > limit) throw const DerException('数据不完整');
  final tag = buf[pos];
  if (tag & 0x1f == 0x1f) throw const DerException('不支持的标签');
  var p = pos + 1;
  var len = buf[p++];
  if (len & 0x80 != 0) {
    final count = len & 0x7f;
    if (count == 0 || count > 4 || p + count > limit) throw const DerException('长度写法不对');
    len = 0;
    for (var i = 0; i < count; i++) {
      len = (len << 8) | buf[p++];
    }
  }
  if (p + len > limit) throw const DerException('数据不完整');
  return DerNode._(buf, tag, pos, p, p + len);
}

/// 解析一整段 DER；后面不许有多余的字节。
DerNode derParse(Uint8List bytes) {
  final node = _readNode(bytes, 0, bytes.length);
  if (node._end != bytes.length) throw const DerException('后面有多余的数据');
  return node;
}

/// PEM：把 [der] 包成 `-----BEGIN label-----` 文本块（每行 64 字符）。
String pemEncode(String label, List<int> der) {
  final b64 = base64.encode(der);
  final sb = StringBuffer('-----BEGIN $label-----\n');
  for (var i = 0; i < b64.length; i += 64) {
    sb.writeln(b64.substring(i, i + 64 > b64.length ? b64.length : i + 64));
  }
  sb.write('-----END $label-----\n');
  return sb.toString();
}

/// 从文本里找出第一个 [label] 的 PEM 块；没有返回 null，块里不是合法 base64 抛 [DerException]。
Uint8List? pemDecode(String text, String label) {
  final begin = '-----BEGIN $label-----';
  final end = '-----END $label-----';
  final s = text.indexOf(begin);
  if (s < 0) return null;
  final e = text.indexOf(end, s + begin.length);
  if (e < 0) throw const DerException('PEM 块没有结尾');
  final body = text.substring(s + begin.length, e).replaceAll(RegExp(r'\s'), '');
  try {
    return base64.decode(body);
  } on FormatException {
    throw const DerException('PEM 块里不是合法的 base64');
  }
}
