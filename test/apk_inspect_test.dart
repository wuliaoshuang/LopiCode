// 看安装包信息（lib/apkpack/apk_inspect.dart、arsc_lookup.dart）：真打出来的包、应用名写在资源表里的包、各种坏文件。
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/apkpack/apk_inspect.dart';
import 'package:lopicode/apkpack/apk_packer.dart';
import 'package:lopicode/apkpack/sign/apk_signer.dart';
import 'package:lopicode/apkpack/zip/zip_reader.dart';
import 'package:path/path.dart' as p;

import 'support/apkpack_kit.dart';
import 'support/apkpack_sign_support.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('apk_inspect'));
  tearDown(() => tmp.deleteSync(recursive: true));

  String write(String name, List<int> bytes) {
    final f = File(p.join(tmp.path, name))..writeAsBytesSync(bytes);
    return f.path;
  }

  String messageOf(String path) {
    try {
      inspectApkSync(path);
    } on ApkInspectException catch (e) {
      return e.message;
    }
    fail('应该解析不了');
  }

  test('本地打包打出来的包：应用名、包名、版本、签名指纹都读得出，指纹和签名用的钥匙一致', () async {
    final web = p.join(tmp.path, 'web');
    sampleStatic(web);
    final key = fixtureKey();
    final out = p.join(tmp.path, 'out.apk');
    final result = await LocalApkPacker(template: realShell(), signer: KeyApkSigner(key)).pack(requestFor(web, out, appName: '我的小站', packageName: 'com.example.site', versionName: '1.2.3', versionCode: 45));
    final info = await inspectApk(out);
    expect(info.appName, '我的小站');
    expect(info.packageName, 'com.example.site');
    expect(info.versionName, '1.2.3');
    expect(info.versionCode, 45);
    expect(info.certSha256Hex, result.certSha256Hex);
    expect(info.certSha256Hex, key.certSha256Hex);
    expect(info.signScheme, 'v2');
  });

  test('只有 v1 签名的包：从 META-INF 里的证书读指纹', () async {
    final web = p.join(tmp.path, 'web');
    sampleStatic(web);
    final key = fixtureKey();
    final out = p.join(tmp.path, 'out.apk');
    await LocalApkPacker(template: realShell(), signer: KeyApkSigner(key)).pack(requestFor(web, out));
    // 把 v2 签名块去掉：按条目重新拼一个只有 v1 文件的 ZIP
    final entries = {for (final e in readZip(File(out).readAsBytesSync())) e.name: e.content()};
    expect(entries.keys, contains('META-INF/CERT.RSA'));
    final v1Only = write('v1.apk', storedZip(entries));
    final info = inspectApkSync(v1Only);
    expect(info.signScheme, 'v1');
    expect(info.certSha256Hex, key.certSha256Hex);
  });

  test('应用名、版本名写在资源表里的包（aapt2 打的）：到资源表里查出来，取默认配置那一条', () {
    final info = inspectApkSync('test/fixtures/apkpack/label_ref.apk');
    expect(info.packageName, 'com.example.labelref');
    expect(info.appName, 'Label From Table');
    expect(info.versionName, '2.3.4');
    expect(info.versionCode, 7);
    expect(info.certSha256Hex, isNull, reason: '这个包没签名');
    expect(info.signScheme, isNull);
  });

  test('没签名的模板：指纹是空的，其余照读', () {
    final info = inspectApkSync('test/fixtures/apkpack/real_shell.apk');
    expect(info.packageName, 'com.lopicode.shell');
    expect(info.appName, 'LopiApp');
  });

  test('坏文件各有各的大白话，不崩', () {
    expect(messageOf(p.join(tmp.path, '没有.apk')), contains('读不了'));
    expect(messageOf(write('empty.apk', const [])), contains('太小'));
    expect(messageOf(write('text.apk', List.filled(5000, 0x41))), contains('不是安装包'));
    expect(messageOf(write('zip.apk', storedZip({'a.txt': Uint8List.fromList('hi'.codeUnits)}))), contains('没有 AndroidManifest.xml'));
    expect(messageOf(write('badmanifest.apk', storedZip({'AndroidManifest.xml': Uint8List.fromList('<manifest/>'.codeUnits)}))), contains('读不懂'));
    // 截掉后半截：找不到结尾记录
    final real = realShell();
    expect(messageOf(write('cut.apk', real.sublist(0, real.length ~/ 2))), contains('不是安装包'));
    // 目录指到文件外面
    final broken = Uint8List.fromList(real);
    ByteData.sublistView(broken).setUint32(broken.length - 22 + 16, 0x7fffffff, Endian.little);
    expect(messageOf(write('broken.apk', broken)), contains('对不上'));
  });

  test('资源表是坏的：应用名读不出，但不崩，包名照读', () {
    final entries = {for (final e in readZip(File('test/fixtures/apkpack/label_ref.apk').readAsBytesSync())) e.name: e.content()};
    entries['resources.arsc'] = Uint8List.fromList(entries['resources.arsc']!.sublist(0, 40));
    final info = inspectApkSync(write('badarsc.apk', storedZip(entries)));
    expect(info.packageName, 'com.example.labelref');
    expect(info.appName, isNull);
  });
}
