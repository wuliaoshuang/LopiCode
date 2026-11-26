// 二进制清单（AXML）读写、改清单的纯 Dart 测试（不依赖安卓 SDK）。用官方工具核对的在 apkpack_official_tools_test.dart。
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/apkpack/axml/axml_codec.dart';
import 'package:lopicode/apkpack/axml/axml_model.dart';
import 'package:lopicode/apkpack/axml/axml_strings.dart';
import 'package:lopicode/apkpack/manifest_editor.dart';

import 'support/apkpack_kit.dart';

const _internet = 'android.permission.INTERNET';
const _camera = 'android.permission.CAMERA';

ManifestEdit _edit({String pkg = 'com.example.demo', String name = '演示', int code = 7, String ver = '2.3', Set<String> perms = const {_internet}}) =>
    ManifestEdit(packageName: pkg, appName: name, versionCode: code, versionName: ver, permissions: perms);

/// 把文档换成 UTF-8 字符串池（官方工具写清单只用 UTF-16，UTF-8 的靠自己转出来测）。
AxmlDocument _asUtf8(AxmlDocument d) => AxmlDocument(
  pool: AxmlStringPool(strings: [...d.pool.strings], utf8: true, sorted: false),
  resourceIds: d.resourceIds,
  hasResourceMap: d.hasResourceMap,
  nodes: d.nodes,
);

void main() {
  final manifest = fakeManifest();

  group('往返', () {
    test('读入再原样写出，字节和原文件完全一致', () {
      final doc = parseAxml(manifest);
      expect(writeAxml(doc), manifest);
    });

    test('替身模板的清单是 UTF-16 字符串池；读出来的内容对得上', () {
      final doc = parseAxml(manifest);
      expect(doc.pool.utf8, isFalse);
      final info = ManifestEditor(doc).read();
      expect(info.packageName, 'com.lopicode.shell');
      expect(info.versionCode, 1);
      expect(info.versionName, '1.0');
      expect(info.label, 'LopiCode Shell');
      expect(info.permissions, [_internet]);
    });

    test('UTF-8 字符串池：写出再读回，内容一致（含中文、表情、超过 127 字节的长串）', () {
      final doc = _asUtf8(parseAxml(manifest));
      final long = '长' * 100;
      ManifestEditor(doc)
        ..setLabel('我的应用😀🎉')
        ..setVersionName(long);
      final back = parseAxml(writeAxml(doc));
      expect(back.pool.utf8, isTrue);
      final info = ManifestEditor(back).read();
      expect(info.label, '我的应用😀🎉');
      expect(info.versionName, long);
      expect(writeAxml(back), writeAxml(doc), reason: 'UTF-8 池子自己的往返也要字节一致');
    });

    test('UTF-8 解码：标准 4 字节写法和代理项各 3 字节的写法都认', () {
      final standard = Uint8List.fromList([0xF0, 0x9F, 0x98, 0x80]);
      final modified = encodeModifiedUtf8('😀');
      expect(modified.length, 6);
      expect(decodeModifiedUtf8(standard, 0, 4, 0), '😀');
      expect(decodeModifiedUtf8(modified, 0, 6, 0), '😀');
      expect(() => decodeModifiedUtf8(Uint8List.fromList([0xE4, 0xBD]), 0, 2, 0), throwsA(isA<AxmlFormatException>()));
    });

    test('UTF-16 超长字符串（超过 32767 个码元）用两段长度', () {
      final doc = parseAxml(manifest);
      final big = 'a' * 40000;
      ManifestEditor(doc).setVersionName(big);
      expect(ManifestEditor(parseAxml(writeAxml(doc))).read().versionName, big);
    });
  });

  group('改清单', () {
    test('包名、版本、应用名、权限一起改；别的内容不变', () {
      final out = editManifestBytes(manifest, _edit(perms: {_internet, _camera}));
      final doc = parseAxml(out);
      final info = ManifestEditor(doc).read();
      expect(info.packageName, 'com.example.demo');
      expect(info.versionCode, 7);
      expect(info.versionName, '2.3');
      expect(info.label, '演示');
      expect(info.permissions, [_internet, _camera]);
      // 旧字符串清掉了
      expect(doc.pool.strings, isNot(contains('com.lopicode.shell')));
      expect(doc.pool.strings, isNot(contains('LopiCode Shell')));
      // 组件的类名没被动
      expect(doc.pool.strings, contains('lopi.shell.MainActivity'));
      // 资源号表和池子前部对齐没被破坏
      final before = parseAxml(manifest);
      expect(doc.resourceIds, before.resourceIds);
      expect(doc.pool.strings.sublist(0, doc.resourceIds.length), before.pool.strings.sublist(0, before.resourceIds.length));
      expect(out.length % 4, 0);
    });

    test('versionCode 写成整数类型，versionName 的原始值和类型化值指向同一条字符串', () {
      final doc = parseAxml(editManifestBytes(manifest, _edit(code: 2100000000, ver: '9.9.9-beta')));
      final root = doc.nodes.whereType<AxmlStartElement>().first;
      final code = root.attributes.firstWhere((a) => doc.resIdOf(a) == kAttrVersionCode);
      expect(code.type, kTypeIntDec);
      expect(code.data, 2100000000);
      expect(code.rawValue, kNoString);
      final name = root.attributes.firstWhere((a) => doc.resIdOf(a) == kAttrVersionName);
      expect(name.type, kTypeString);
      expect(name.rawValue, name.data);
      expect(doc.str(name.data), '9.9.9-beta');
    });

    test('权限：只联网 → 加摄像头和定位（连带粗略定位）→ 全部去掉只留联网', () {
      const fine = 'android.permission.ACCESS_FINE_LOCATION';
      const coarse = 'android.permission.ACCESS_COARSE_LOCATION';
      final a = editManifestBytes(manifest, _edit(pkg: kShellDefaultPackage, perms: {_internet, _camera, fine}));
      expect(readManifestInfo(a).permissions, [_internet, coarse, fine, _camera], reason: '已有的留在原位，新加的按名字排在后面');
      expect(readManifestInfo(a).permissions.toSet(), {_internet, _camera, fine, coarse});
      final b = editManifestBytes(a, _edit(pkg: kShellDefaultPackage, perms: {_internet}));
      expect(readManifestInfo(b).permissions, [_internet]);
      final strings = parseAxml(b).pool.strings;
      expect(strings, isNot(contains(_camera)));
      expect(strings, isNot(contains(coarse)));
    });

    test('同名权限不重复；一个权限都不要也行；再加回来也行', () {
      final same = editManifestBytes(manifest, _edit(pkg: kShellDefaultPackage, perms: {_internet}));
      expect(readManifestInfo(same).permissions, [_internet]);
      final none = editManifestBytes(manifest, _edit(pkg: kShellDefaultPackage, perms: {}));
      expect(readManifestInfo(none).permissions, isEmpty);
      expect(parseAxml(none).pool.strings, isNot(contains('uses-permission')));
      final again = editManifestBytes(none, _edit(pkg: kShellDefaultPackage, perms: {_camera, _internet}));
      expect(readManifestInfo(again).permissions, [_camera, _internet]);
      // 新加的权限元素放在 application 前面
      final doc = parseAxml(again);
      final names = [for (final n in doc.nodes.whereType<AxmlStartElement>()) doc.str(n.name)];
      expect(names.indexOf('uses-permission'), lessThan(names.indexOf('application')));
    });

    test('应用名和某个属性名同字（name）时，不会去复用属性名那条字符串', () {
      final doc = parseAxml(editManifestBytes(manifest, _edit(name: 'name')));
      final app = doc.nodes.whereType<AxmlStartElement>().firstWhere((n) => doc.str(n.name) == 'application');
      final label = app.attributes.firstWhere((a) => doc.resIdOf(a) == kAttrLabel);
      expect(label.data, greaterThanOrEqualTo(doc.resourceIds.length));
      expect(doc.str(label.data), 'name');
    });

    test('模板里以旧包名开头的 authorities 跟着包名换', () {
      final doc = parseAxml(manifest);
      // 手工给 activity 加一个 authorities 属性（借 activity 元素模拟 provider）
      final idx = doc.resourceIds.indexOf(kAttrName);
      doc.resourceIds[idx] = kAttrAuthorities; // 只为造数据：把 name 这条的资源号换成 authorities
      final act = doc.nodes.whereType<AxmlStartElement>().firstWhere((n) => doc.str(n.name) == 'activity');
      final v = doc.internValue('com.lopicode.shell.files;other.auth');
      act.attributes.first
        ..rawValue = v
        ..data = v;
      ManifestEditor(doc).setPackage('org.me.app');
      expect(doc.str(act.attributes.first.data), 'org.me.app.files;other.auth');
    });
  });

  group('坏输入要报明确的错', () {
    void bad(Uint8List bytes, String part) => expect(() => parseAxml(bytes), throwsA(isA<AxmlFormatException>().having((e) => e.message, 'message', contains(part))));

    test('截断的清单（各种长度都不能崩，也不能悄悄读成功）', () {
      bad(Uint8List.sublistView(manifest, 0, manifest.length - 20), '截断');
      for (final n in [0, 4, 7, 8, 30, 100, 500, manifest.length - 1]) {
        expect(() => parseAxml(Uint8List.sublistView(manifest, 0, n)), throwsA(isA<AxmlFormatException>()), reason: '截到 $n 字节');
      }
    });

    test('文本格式的 XML', () => bad(Uint8List.fromList('<?xml version="1.0"?><manifest/>'.codeUnits), '文本格式'));

    test('不认识的块', () {
      final b = Uint8List.fromList(manifest);
      // 第一个命名空间块的类型 0x0100 改成 0x0199
      final doc = parseAxml(manifest);
      final poolSize = ByteData.sublistView(b).getUint32(12, Endian.little);
      final nsOff = 8 + poolSize + 8 + doc.resourceIds.length * 4;
      expect(ByteData.sublistView(b).getUint16(nsOff, Endian.little), kResXmlStartNamespaceType);
      ByteData.sublistView(b).setUint16(nsOff, 0x0199, Endian.little);
      bad(b, '不认识的块');
    });

    test('字符串引用指到池子外面', () {
      final doc = parseAxml(manifest);
      doc.nodes.whereType<AxmlStartElement>().first.name = 9999;
      bad(writeAxml(doc), '池子外面');
    });

    test('清单不符合约定：包名不是默认、label 不是字面字符串、缺版本号', () {
      void mismatch(void Function(AxmlDocument) breakIt, String part) {
        final doc = parseAxml(manifest);
        breakIt(doc);
        expect(() => editManifestBytes(writeAxml(doc), _edit()), throwsA(isA<AxmlFormatException>().having((e) => e.message, 'message', contains(part))));
      }

      mismatch((d) => ManifestEditor(d).setPackage('com.other.pkg'), '包名应该是');
      mismatch((d) {
        final app = d.nodes.whereType<AxmlStartElement>().firstWhere((n) => d.str(n.name) == 'application');
        app.attributes.firstWhere((a) => d.resIdOf(a) == kAttrLabel)
          ..type = kTypeReference
          ..rawValue = kNoString
          ..data = 0x7f020000;
      }, '应用名');
      mismatch((d) => d.nodes.whereType<AxmlStartElement>().first.attributes.removeWhere((a) => d.resIdOf(a) == kAttrVersionCode), 'versionCode');
      mismatch((d) => d.nodes.whereType<AxmlStartElement>().first.name = d.internValue('nope'), 'manifest');
    });
  });
}
