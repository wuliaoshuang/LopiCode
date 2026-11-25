// 本地打包 APK 用的网页壳模板（assets/apk_shell/shell.apk）：文件和说明对得上、里面该有的都有、没有签名、
// 源码改了以后重编过。重编：shell_template/build.sh。
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

const _apkPath = 'assets/apk_shell/shell.apk';
const _jsonPath = 'assets/apk_shell/shell.json';
const _srcDir = 'shell_template';

const _icons = {
  48: 'res/mipmap-mdpi/ic_launcher.png',
  72: 'res/mipmap-hdpi/ic_launcher.png',
  96: 'res/mipmap-xhdpi/ic_launcher.png',
  144: 'res/mipmap-xxhdpi/ic_launcher.png',
  192: 'res/mipmap-xxxhdpi/ic_launcher.png',
};

/// 和 shell_template/tools/Describe.java 的 sourceHash 是同一个算法：
/// 除 build/ 和 README.md 以外的每个文件一行 `sha256  相对路径\n`，按路径排序，再整体算 sha256。
String _sourceHash() {
  final root = Directory(_srcDir);
  final prefix = '${root.path}/';
  final files = <String, File>{};
  for (final e in root.listSync(recursive: true, followLinks: false)) {
    if (e is! File) continue;
    final rel = e.path.replaceAll('\\', '/').substring(prefix.length);
    if (rel.startsWith('build/') || rel == 'README.md') continue;
    files[rel] = e;
  }
  final names = files.keys.toList()..sort();
  final lines = StringBuffer();
  for (final rel in names) {
    lines.write('${sha256.convert(files[rel]!.readAsBytesSync())}  $rel\n');
  }
  return sha256.convert(utf8.encode(lines.toString())).toString();
}

/// ZIP 中央目录里每个条目的存放方式（0＝原样存放，8＝压缩）和文件数据的起始位置。自己读，不依赖解压库怎么报。
Map<String, ({int method, int dataOffset})> _centralDirectory(Uint8List bytes) {
  final d = ByteData.sublistView(bytes);
  var eocd = bytes.length - 22;
  while (eocd >= 0 && d.getUint32(eocd, Endian.little) != 0x06054b50) {
    eocd--;
  }
  expect(eocd, greaterThanOrEqualTo(0), reason: '找不到 ZIP 的结尾记录');
  final count = d.getUint16(eocd + 10, Endian.little);
  var p = d.getUint32(eocd + 16, Endian.little);
  final out = <String, ({int method, int dataOffset})>{};
  for (var i = 0; i < count; i++) {
    expect(d.getUint32(p, Endian.little), 0x02014b50, reason: '中央目录第 $i 项的标记不对');
    final method = d.getUint16(p + 10, Endian.little);
    final nameLen = d.getUint16(p + 28, Endian.little);
    final extraLen = d.getUint16(p + 30, Endian.little);
    final commentLen = d.getUint16(p + 32, Endian.little);
    final local = d.getUint32(p + 42, Endian.little);
    final name = utf8.decode(bytes.sublist(p + 46, p + 46 + nameLen));
    expect(d.getUint32(local, Endian.little), 0x04034b50, reason: '$name 的本地文件头标记不对');
    final dataOffset = local + 30 + d.getUint16(local + 26, Endian.little) + d.getUint16(local + 28, Endian.little);
    out[name] = (method: method, dataOffset: dataOffset);
    p += 46 + nameLen + extraLen + commentLen;
  }
  return out;
}

void main() {
  late Uint8List apk;
  late Map<String, dynamic> info;

  setUpAll(() {
    apk = File(_apkPath).readAsBytesSync();
    info = jsonDecode(File(_jsonPath).readAsStringSync()) as Map<String, dynamic>;
  });

  test('shell.apk 的 sha256、字节数和 shell.json 写的一致', () {
    expect(info['file'], 'shell.apk');
    expect(apk.length, info['sizeBytes']);
    expect(sha256.convert(apk).toString(), info['sha256']);
    // 模板要随安装包发，体积是硬指标：超过 64KB 说明有人往里加了不该加的东西。
    expect(apk.length, lessThan(64 * 1024));
  });

  test('源码改了就必须重编模板（shell_template/build.sh）', () {
    expect(_sourceHash(), info['sourceSha256'], reason: 'shell_template/ 下的文件和模板编出来时不一样了。跑一遍 shell_template/build.sh，把新的 shell.apk 和 shell.json 一起提交。');
  });

  test('是合法的 ZIP，清单、代码、资源表、五个密度的图标都在，别的一概没有', () {
    final archive = ZipDecoder().decodeBytes(apk, verify: true);
    final names = archive.files.map((f) => f.name).toSet();
    expect(names, {'AndroidManifest.xml', 'classes.dex', 'resources.arsc', ..._icons.values});

    // 清单是编译后的二进制 XML（开头 0x0003、头长 8），不是文本。
    final manifest = archive.findFile('AndroidManifest.xml')!.content as List<int>;
    expect(manifest.sublist(0, 4), [0x03, 0x00, 0x08, 0x00]);
    // dex 文件头
    final dex = archive.findFile('classes.dex')!.content as List<int>;
    expect(ascii.decode(dex.sublist(0, 4)), 'dex\n');
    // 资源表（开头 0x0002、头长 12）
    final arsc = archive.findFile('resources.arsc')!.content as List<int>;
    expect(arsc.sublist(0, 4), [0x02, 0x00, 0x0c, 0x00]);

    // 图标：是 PNG，边长和密度对应（打包器按这些固定路径替换）。
    expect((info['icons'] as Map).map((k, v) => MapEntry(int.parse(k as String), v)), _icons);
    for (final e in _icons.entries) {
      final png = Uint8List.fromList(archive.findFile(e.value)!.content as List<int>);
      expect(png.sublist(0, 8), [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a], reason: e.value);
      final d = ByteData.sublistView(png);
      expect(d.getUint32(16), e.key, reason: '${e.value} 的宽');
      expect(d.getUint32(20), e.key, reason: '${e.value} 的高');
      // 和源码目录里的图标逐字节相同（构建时没有被重新压过）。
      expect(png, File('$_srcDir/${e.value}').readAsBytesSync(), reason: e.value);
    }
  });

  test('没有任何签名文件，也没有网页和设置文件（那是打包时才放进去的）', () {
    final names = _centralDirectory(apk).keys;
    expect(names.where((n) => n.startsWith('META-INF/')), isEmpty);
    expect(names.where((n) => n.startsWith('assets/')), isEmpty);
    expect(info['signed'], isFalse);
    // v2 / v3 签名块在中央目录前面，以这串字结尾；未签名的模板里不该出现。
    expect(latin1.decode(apk).contains('APK Sig Block 42'), isFalse);
  });

  test('存放方式和 shell.json 的条目清单一致：资源表和图标原样存放并按 4 字节对齐', () {
    final cd = _centralDirectory(apk);
    final entries = (info['entries'] as List).cast<Map<String, dynamic>>();
    expect(entries.map((e) => e['name']).toList(), cd.keys.toList(), reason: '条目顺序');
    for (final e in entries) {
      final name = e['name'] as String;
      final stored = cd[name]!.method == 0;
      expect(stored ? 'stored' : 'deflated', e['method'], reason: name);
      if (name == 'resources.arsc' || name.startsWith('res/')) {
        // targetSdk 30 起，资源表被压缩或没对齐的安装包装不上。
        expect(stored, isTrue, reason: '$name 必须原样存放');
        expect(cd[name]!.dataOffset % 4, 0, reason: '$name 没有按 4 字节对齐');
      }
    }
    expect(info['iconStorage'], 'stored');
    expect(info['zipAlignment'], 4);
  });

  test('shell.json 里给打包器用的约定和壳源码一致', () {
    final manifest = File('$_srcDir/AndroidManifest.xml').readAsStringSync();
    expect(info['package'], 'com.lopicode.shell');
    expect(manifest, contains('package="${info['package']}"'));
    expect(manifest, contains('android:label="${info['label']}"'));
    expect(manifest, contains('android:versionCode="${info['versionCode']}"'));
    expect(manifest, contains('android:versionName="${info['versionName']}"'));
    expect(manifest, contains('android:name="${info['mainActivity']}"'));
    expect(info['mainActivity'], 'lopi.shell.MainActivity');
    expect(manifest, contains('android:minSdkVersion="${info['minSdk']}"'));
    expect(manifest, contains('android:targetSdkVersion="${info['targetSdk']}"'));
    expect(info['minSdk'], 24);
    expect(info['targetSdk'], 35);
    expect(info['permissions'], ['android.permission.INTERNET']);

    // 清单里不能有依赖包名的写法：打包器只改 package 这一处。
    expect(manifest.contains(r'${applicationId}'), isFalse);
    expect(RegExp(r'android:name="\.').hasMatch(manifest), isFalse, reason: '组件名必须写全（不能以 . 开头）');
    expect(manifest.contains('<provider'), isFalse);
    expect(manifest.contains('<permission'), isFalse);
    expect(RegExp(r'android:label="@').hasMatch(manifest), isFalse, reason: '应用名必须是字面字符串');
    expect('com.lopicode.shell'.allMatches(manifest).length, 1, reason: '包名只该在 package 属性里出现一次');

    final server = File('$_srcDir/src/lopi/shell/AssetServer.java').readAsStringSync();
    final host = Uri.parse(info['localOrigin'] as String).host;
    expect(server, contains('HOST = "$host"'));
    expect(server, contains('WWW = "www/"'));
    expect(info['wwwDir'], 'assets/www/');
    final config = File('$_srcDir/src/lopi/shell/ShellConfig.java').readAsStringSync();
    expect(info['configAsset'], 'assets/lopi_shell.json');
    expect(config, contains('ASSET = "lopi_shell.json"'));
    expect(config, contains('entry = "${(info['configDefaults'] as Map)['entry']}"'));

    // 壳靠“清单里声明了没有”决定给不给网页用的那几项权限，源码里都要认得。
    final perms = File('$_srcDir/src/lopi/shell/Permissions.java').readAsStringSync();
    for (final p in ['CAMERA', 'RECORD_AUDIO', 'ACCESS_FINE_LOCATION', 'ACCESS_COARSE_LOCATION']) {
      expect(perms, contains('Manifest.permission.$p'));
      expect(info['supportedPermissions'], contains('android.permission.$p'));
    }
  });

  test('壳源码里没有统计、上报、远程加载代码，也没有第三方库', () {
    final sources = Directory('$_srcDir/src').listSync(recursive: true).whereType<File>().toList();
    expect(sources, isNotEmpty);
    for (final f in sources) {
      final text = f.readAsStringSync();
      for (final line in text.split('\n').where((l) => l.startsWith('import '))) {
        expect(RegExp(r'^import (android|java|org\.json)\.').hasMatch(line), isTrue, reason: '${f.path} 引了系统自带以外的东西：$line');
      }
      for (final banned in ['DexClassLoader', 'PathClassLoader', 'HttpURLConnection', 'java.net.URL;', 'java.net.Socket', 'Runtime.getRuntime']) {
        expect(text.contains(banned), isFalse, reason: '${f.path} 里出现了 $banned');
      }
      // 源码里唯一的网址是本地地址。
      for (final m in RegExp(r'https?://[A-Za-z0-9.\-]+').allMatches(text)) {
        expect(m.group(0), 'https://lopi.invalid', reason: f.path);
      }
    }
  });

  test('pubspec 里登记了模板目录', () {
    expect(File('pubspec.yaml').readAsStringSync(), contains('- assets/apk_shell/'));
  });
}
