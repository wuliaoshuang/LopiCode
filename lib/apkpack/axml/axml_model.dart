// 二进制清单（AXML）的内存模型。格式事实见 docs/apk-format-notes.md（对着 AOSP 的 ResourceTypes.h 核对）。
//
// 设计：字符串池保持“下标”语义——节点里存的都是池下标，不是字符串本身。这样原样读入再写出能做到字节一致；
// 要改字符串时只往池子后面追加、把引用改过去，不改已有条目（别的属性可能共用同一条）。
import 'dart:typed_data';

/// 读写清单时遇到不认识 / 不合法的内容。消息是技术性的；门面会把它包成给用户看的“模板损坏/不匹配”。
class AxmlFormatException implements Exception {
  const AxmlFormatException(this.message);
  final String message;
  @override
  String toString() => 'AxmlFormatException: $message';
}

/// 块类型（ResourceTypes.h 的 RES_*_TYPE）。
const int kResStringPoolType = 0x0001;
const int kResXmlType = 0x0003;
const int kResXmlStartNamespaceType = 0x0100;
const int kResXmlEndNamespaceType = 0x0101;
const int kResXmlStartElementType = 0x0102;
const int kResXmlEndElementType = 0x0103;
const int kResXmlCdataType = 0x0104;
const int kResXmlResourceMapType = 0x0180;

/// Res_value::dataType。
const int kTypeNull = 0x00;
const int kTypeReference = 0x01;
const int kTypeString = 0x03;
const int kTypeIntDec = 0x10;
const int kTypeIntHex = 0x11;
const int kTypeIntBoolean = 0x12;

/// “没有”的字符串引用（ResStringPool_ref.index = 0xFFFFFFFF）。
const int kNoString = 0xFFFFFFFF;

/// 用到的系统属性资源号（android.R.attr）。
const int kAttrLabel = 0x01010001;
const int kAttrIcon = 0x01010002;
const int kAttrName = 0x01010003;
const int kAttrAuthorities = 0x01010018;
const int kAttrVersionCode = 0x0101021b;
const int kAttrVersionName = 0x0101021c;

const String kAndroidNsUri = 'http://schemas.android.com/apk/res/android';

/// 字符串池。[utf8]＝池子用 UTF-8 编码（否则 UTF-16）；[sorted] 是原文件的 SORTED 标志。
class AxmlStringPool {
  AxmlStringPool({required this.strings, required this.utf8, required this.sorted});
  final List<String> strings;
  final bool utf8;
  bool sorted;

  String at(int index) {
    if (index < 0 || index >= strings.length) throw AxmlFormatException('字符串下标 $index 越界（池子只有 ${strings.length} 条）');
    return strings[index];
  }
}

/// 一个属性（ResXMLTree_attribute，20 字节）。
class AxmlAttribute {
  AxmlAttribute({required this.ns, required this.name, required this.rawValue, required this.type, required this.data, this.res0 = 0});
  int ns;
  int name;
  int rawValue;
  int type;
  int data;
  int res0;
}

sealed class AxmlNode {
  AxmlNode({required this.line, required this.comment});
  int line;
  int comment;
}

class AxmlNamespace extends AxmlNode {
  AxmlNamespace({required super.line, required super.comment, required this.start, required this.prefix, required this.uri});
  final bool start;
  int prefix;
  int uri;
}

class AxmlStartElement extends AxmlNode {
  AxmlStartElement({required super.line, required super.comment, required this.ns, required this.name, required this.attributes, this.idIndex = 0, this.classIndex = 0, this.styleIndex = 0});
  int ns;
  int name;
  final List<AxmlAttribute> attributes;
  int idIndex;
  int classIndex;
  int styleIndex;
}

class AxmlEndElement extends AxmlNode {
  AxmlEndElement({required super.line, required super.comment, required this.ns, required this.name});
  int ns;
  int name;
}

class AxmlCdata extends AxmlNode {
  AxmlCdata({required super.line, required super.comment, required this.text, required this.type, required this.data, this.res0 = 0});
  int text;
  int type;
  int data;
  int res0;
}

/// 整份清单：字符串池 + 资源号表 + 节点序列。
class AxmlDocument {
  AxmlDocument({required this.pool, required this.resourceIds, required this.hasResourceMap, required this.nodes});
  final AxmlStringPool pool;

  /// 资源号表：第 i 项是池子里第 i 条字符串（属性名）对应的资源号。
  final List<int> resourceIds;
  final bool hasResourceMap;
  final List<AxmlNode> nodes;

  String str(int index) => pool.at(index);

  /// 属性的资源号（没有就是 null）。
  int? resIdOf(AxmlAttribute a) => a.name < resourceIds.length ? resourceIds[a.name] : null;

  /// 找一个“值字符串”的下标，没有就追加。只在资源号表之后的区域里找，不复用属性名那几条。
  int internValue(String s) {
    for (var i = resourceIds.length; i < pool.strings.length; i++) {
      if (pool.strings[i] == s) return i;
    }
    pool.strings.add(s);
    pool.sorted = false;
    return pool.strings.length - 1;
  }
}

/// 小端读取器，越界时报清楚的错。
class ByteReader {
  ByteReader(this.bytes) : _d = ByteData.sublistView(bytes);
  final Uint8List bytes;
  final ByteData _d;
  int get length => bytes.length;

  void _need(int off, int n, String what) {
    if (off < 0 || off + n > bytes.length) throw AxmlFormatException('$what：文件在偏移 $off 处被截断（需要 $n 字节，文件共 ${bytes.length} 字节）');
  }

  int u8(int off, [String what = '读取']) {
    _need(off, 1, what);
    return bytes[off];
  }

  int u16(int off, [String what = '读取']) {
    _need(off, 2, what);
    return _d.getUint16(off, Endian.little);
  }

  int u32(int off, [String what = '读取']) {
    _need(off, 4, what);
    return _d.getUint32(off, Endian.little);
  }
}

/// 小端写入器。
class ByteWriter {
  final BytesBuilder _b = BytesBuilder(copy: false);
  int get length => _b.length;
  void u8(int v) => _b.addByte(v & 0xFF);
  void u16(int v) => _b.add(Uint8List(2)..buffer.asByteData().setUint16(0, v & 0xFFFF, Endian.little));
  void u32(int v) => _b.add(Uint8List(4)..buffer.asByteData().setUint32(0, v & 0xFFFFFFFF, Endian.little));
  void bytes(List<int> v) => _b.add(v);
  void padTo4() {
    while (_b.length % 4 != 0) {
      _b.addByte(0);
    }
  }

  Uint8List take() => _b.takeBytes();
}
