// 二进制清单的读（[parseAxml]）和写（[writeAxml]）。写的时候各块大小、偏移、4 字节对齐全部重算。
// 遇到不认识的块、对不上的长度一律抛 [AxmlFormatException]，不猜、不悄悄写坏。
import 'dart:typed_data';

import 'package:lopicode/apkpack/axml/axml_model.dart';
import 'package:lopicode/apkpack/axml/axml_strings.dart';

const int _kNodeHeaderSize = 0x10;
const int _kAttrSize = 0x14;

AxmlDocument parseAxml(Uint8List bytes) {
  final r = ByteReader(bytes);
  if (bytes.length < 8) throw const AxmlFormatException('文件太短，不是二进制清单');
  final type = r.u16(0);
  final headerSize = r.u16(2);
  final total = r.u32(4);
  if (type != kResXmlType) {
    final looksText = bytes[0] == 0x3C; // '<'
    throw AxmlFormatException(looksText ? '这是文本格式的 XML，不是编译过的二进制清单' : '开头不是二进制 XML（类型 0x${type.toRadixString(16)}）');
  }
  if (headerSize != 8) throw AxmlFormatException('XML 头部长度应为 8，实际 $headerSize');
  if (total != bytes.length) throw AxmlFormatException('文件头写的大小是 $total 字节，实际是 ${bytes.length} 字节（文件被截断或多了内容）');

  var off = 8;
  final (pool, poolSize) = readStringPool(r, off);
  off += poolSize;
  var resIds = <int>[];
  var hasMap = false;
  final nodes = <AxmlNode>[];
  var depth = 0;
  while (off < total) {
    final t = r.u16(off, '块头');
    final hs = r.u16(off + 2, '块头');
    final size = r.u32(off + 4, '块头');
    if (size < 8 || size % 4 != 0 || off + size > total) throw AxmlFormatException('偏移 $off 处的块大小 $size 不合法');
    if (t == kResXmlResourceMapType) {
      if (hasMap || nodes.isNotEmpty) throw const AxmlFormatException('资源号表的位置不对（应该只有一个，且在所有节点之前）');
      if (hs != 8) throw AxmlFormatException('资源号表头部长度应为 8，实际 $hs');
      hasMap = true;
      resIds = [for (var p = off + 8; p < off + size; p += 4) r.u32(p)];
      if (resIds.length > pool.strings.length) throw const AxmlFormatException('资源号表比字符串池还长');
    } else if (t >= kResXmlStartNamespaceType && t <= kResXmlCdataType) {
      if (hs != _kNodeHeaderSize) throw AxmlFormatException('节点头部长度应为 16，实际 $hs');
      final line = r.u32(off + 8);
      final comment = r.u32(off + 12);
      final e = off + _kNodeHeaderSize;
      void want(int n) {
        if (size != _kNodeHeaderSize + n) throw AxmlFormatException('偏移 $off 处的节点大小 $size 和内容对不上（应为 ${_kNodeHeaderSize + n}）');
      }

      switch (t) {
        case kResXmlStartNamespaceType || kResXmlEndNamespaceType:
          want(8);
          nodes.add(AxmlNamespace(line: line, comment: comment, start: t == kResXmlStartNamespaceType, prefix: r.u32(e), uri: r.u32(e + 4)));
        case kResXmlStartElementType:
          if (size < _kNodeHeaderSize + 20) throw const AxmlFormatException('元素块太短');
          final attrStart = r.u16(e + 8);
          final attrSize = r.u16(e + 10);
          final count = r.u16(e + 12);
          if (attrStart != 20 || attrSize != _kAttrSize) throw AxmlFormatException('属性表的位置或单项大小不是标准值（$attrStart / $attrSize），不支持');
          want(20 + count * _kAttrSize);
          final attrs = <AxmlAttribute>[];
          for (var i = 0; i < count; i++) {
            final a = e + 20 + i * _kAttrSize;
            if (r.u16(a + 12) != 8) throw const AxmlFormatException('属性值的长度字段不是 8');
            attrs.add(AxmlAttribute(ns: r.u32(a), name: r.u32(a + 4), rawValue: r.u32(a + 8), res0: r.u8(a + 14), type: r.u8(a + 15), data: r.u32(a + 16)));
          }
          nodes.add(AxmlStartElement(line: line, comment: comment, ns: r.u32(e), name: r.u32(e + 4), attributes: attrs, idIndex: r.u16(e + 14), classIndex: r.u16(e + 16), styleIndex: r.u16(e + 18)));
          depth++;
        case kResXmlEndElementType:
          want(8);
          nodes.add(AxmlEndElement(line: line, comment: comment, ns: r.u32(e), name: r.u32(e + 4)));
          depth--;
          if (depth < 0) throw const AxmlFormatException('元素的开始和结束对不上');
        case kResXmlCdataType:
          want(12);
          if (r.u16(e + 4) != 8) throw const AxmlFormatException('文本节点的值长度字段不是 8');
          nodes.add(AxmlCdata(line: line, comment: comment, text: r.u32(e), res0: r.u8(e + 6), type: r.u8(e + 7), data: r.u32(e + 8)));
      }
    } else {
      throw AxmlFormatException('清单里有不认识的块（类型 0x${t.toRadixString(16)}，偏移 $off），不敢改');
    }
    off += size;
  }
  if (depth != 0) throw const AxmlFormatException('元素的开始和结束对不上（文件可能被截断）');
  final doc = AxmlDocument(pool: pool, resourceIds: resIds, hasResourceMap: hasMap, nodes: nodes);
  _checkRefs(doc);
  return doc;
}

/// 所有字符串引用都得落在池子里。
void _checkRefs(AxmlDocument doc) {
  final n = doc.pool.strings.length;
  void ref(int i, {bool optional = true}) {
    if (i == kNoString && optional) return;
    if (i >= n) throw AxmlFormatException('有字符串引用（$i）指到了池子外面');
  }

  forEachStringRef(doc, (get, set, {required optional}) => ref(get(), optional: optional));
}

/// 遍历文档里每一处字符串引用（读、写回调），给校验和“清理池子后重排下标”共用。
void forEachStringRef(AxmlDocument doc, void Function(int Function() get, void Function(int) set, {required bool optional}) visit) {
  for (final node in doc.nodes) {
    visit(() => node.comment, (v) => node.comment = v, optional: true);
    switch (node) {
      case AxmlNamespace():
        visit(() => node.prefix, (v) => node.prefix = v, optional: true);
        visit(() => node.uri, (v) => node.uri = v, optional: true);
      case AxmlStartElement():
        visit(() => node.ns, (v) => node.ns = v, optional: true);
        visit(() => node.name, (v) => node.name = v, optional: false);
        for (final a in node.attributes) {
          visit(() => a.ns, (v) => a.ns = v, optional: true);
          visit(() => a.name, (v) => a.name = v, optional: false);
          visit(() => a.rawValue, (v) => a.rawValue = v, optional: true);
          if (a.type == kTypeString) visit(() => a.data, (v) => a.data = v, optional: false);
        }
      case AxmlEndElement():
        visit(() => node.ns, (v) => node.ns = v, optional: true);
        visit(() => node.name, (v) => node.name = v, optional: false);
      case AxmlCdata():
        visit(() => node.text, (v) => node.text = v, optional: true);
        if (node.type == kTypeString) visit(() => node.data, (v) => node.data = v, optional: false);
    }
  }
}

/// 把没人引用的“值字符串”从池子里删掉并重排下标。带资源号的属性名（池子前部）一条不动。
void compactStringPool(AxmlDocument doc) {
  final used = <int>{};
  forEachStringRef(doc, (get, set, {required optional}) {
    final v = get();
    if (v != kNoString) used.add(v);
  });
  final keep = doc.resourceIds.length;
  final old = doc.pool.strings;
  final map = <int, int>{};
  final next = <String>[];
  for (var i = 0; i < old.length; i++) {
    if (i < keep || used.contains(i)) {
      map[i] = next.length;
      next.add(old[i]);
    }
  }
  if (next.length == old.length) return;
  forEachStringRef(doc, (get, set, {required optional}) {
    final v = get();
    if (v != kNoString) set(map[v]!);
  });
  old
    ..clear()
    ..addAll(next);
  doc.pool.sorted = false;
}

Uint8List writeAxml(AxmlDocument doc) {
  if (doc.resourceIds.length > doc.pool.strings.length) throw const AxmlFormatException('资源号表比字符串池还长');
  final body = ByteWriter()..bytes(writeStringPool(doc.pool));
  if (doc.hasResourceMap) {
    body
      ..u16(kResXmlResourceMapType)
      ..u16(8)
      ..u32(8 + doc.resourceIds.length * 4);
    for (final id in doc.resourceIds) {
      body.u32(id);
    }
  }
  void head(int type, AxmlNode n, int extSize) {
    body
      ..u16(type)
      ..u16(_kNodeHeaderSize)
      ..u32(_kNodeHeaderSize + extSize)
      ..u32(n.line)
      ..u32(n.comment);
  }

  for (final n in doc.nodes) {
    switch (n) {
      case AxmlNamespace():
        head(n.start ? kResXmlStartNamespaceType : kResXmlEndNamespaceType, n, 8);
        body
          ..u32(n.prefix)
          ..u32(n.uri);
      case AxmlStartElement():
        if (n.attributes.length > 0xFFFF) throw const AxmlFormatException('一个元素的属性太多');
        head(kResXmlStartElementType, n, 20 + n.attributes.length * _kAttrSize);
        body
          ..u32(n.ns)
          ..u32(n.name)
          ..u16(20)
          ..u16(_kAttrSize)
          ..u16(n.attributes.length)
          ..u16(n.idIndex)
          ..u16(n.classIndex)
          ..u16(n.styleIndex);
        for (final a in n.attributes) {
          body
            ..u32(a.ns)
            ..u32(a.name)
            ..u32(a.rawValue)
            ..u16(8)
            ..u8(a.res0)
            ..u8(a.type)
            ..u32(a.data);
        }
      case AxmlEndElement():
        head(kResXmlEndElementType, n, 8);
        body
          ..u32(n.ns)
          ..u32(n.name);
      case AxmlCdata():
        head(kResXmlCdataType, n, 12);
        body
          ..u32(n.text)
          ..u16(8)
          ..u8(n.res0)
          ..u8(n.type)
          ..u32(n.data);
    }
  }
  final b = body.take();
  final out = ByteWriter()
    ..u16(kResXmlType)
    ..u16(8)
    ..u32(8 + b.length)
    ..bytes(b);
  return out.take();
}
