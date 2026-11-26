// 打包门面的纯 Dart 测试（不依赖安卓 SDK）：流程、进度、产物内容、失败不留半截产物、坏输入报明确的错。
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/apkpack/apk_pack_contract.dart';
import 'package:lopicode/apkpack/apk_pack_core.dart';
import 'package:lopicode/apkpack/apk_packer.dart';
import 'package:lopicode/apkpack/axml/axml_codec.dart';
import 'package:lopicode/apkpack/axml/axml_model.dart';
import 'package:lopicode/apkpack/manifest_editor.dart';
import 'package:lopicode/apkpack/zip/zip_model.dart';
import 'package:lopicode/apkpack/zip/zip_reader.dart';
import 'package:lopicode/apkpack/zip/zip_writer.dart';
import 'package:path/path.dart' as p;

import 'support/apkpack_kit.dart';

/// 假签名器：v1 产出三个文件（内容里记下收到了哪些条目），v2 在末尾之外不动字节，只记录被调用。
class _FakeSigner implements ApkSigner {
  @override
  Map<String, Uint8List> v1Files(Map<String, Uint8List> entries) {
    final names = entries.keys.join('\n');
    final total = entries.values.fold<int>(0, (a, b) => a + b.length);
    return {
      'META-INF/MANIFEST.MF': Uint8List.fromList(utf8.encode('names:\n$names\ntotal:$total\n')),
      'META-INF/CERT.SF': Uint8List.fromList(utf8.encode('sf')),
      'META-INF/CERT.RSA': Uint8List.fromList([1, 2, 3]),
    };
  }

  @override
  Uint8List v2(Uint8List alignedZip) => alignedZip;
  @override
  String get certSha256Hex => 'ab' * 32;
}

class _CrashSigner extends NoSigner {
  const _CrashSigner();
  @override
  Uint8List v2(Uint8List alignedZip) => throw StateError('签名器炸了');
}

/// 把替身模板的条目改一改，造出各种“不对的模板”。
Uint8List _shellWith(List<ZipEntry> Function(List<ZipEntry>) change) => writeZip(change(readZip(fakeShell())));

void main() {
  late Directory tmp;
  late String web;
  late String out;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('apkpack_pack_');
    web = p.join(tmp.path, 'proj');
    out = p.join(tmp.path, 'proj', 'build', 'demo.apk');
    sampleStatic(web);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  Matcher packError(String field, String part) => throwsA(isA<ApkPackException>().having((e) => e.field, 'field', field).having((e) => e.message, 'message', contains(part)));
  void expectNoLeftovers() {
    final dir = Directory(p.dirname(out));
    expect(File(out).existsSync(), isFalse, reason: '失败了不该有产物');
    if (dir.existsSync()) expect(dir.listSync(), isEmpty, reason: '不该留半截文件');
  }

  test('在后台 isolate 里打包：步骤按顺序上报，产物内容对得上', () async {
    final steps = <ApkPackStep>[];
    final packer = LocalApkPacker(template: fakeShell(), signer: const NoSigner());
    final r = await packer.pack(
      requestFor(web, out, appName: '我的应用', versionCode: 12, versionName: '1.2', permissions: {'android.permission.INTERNET', 'android.permission.CAMERA'}),
      onProgress: (x) => steps.add(x.step),
    );
    final order = [
      for (var i = 0; i < steps.length; i++)
        if (i == 0 || steps[i] != steps[i - 1]) steps[i],
    ];
    expect(order, ApkPackStep.values);
    final bytes = File(out).readAsBytesSync();
    expect((r.path, r.sizeBytes, r.fileCount, r.sha256Hex), (out, bytes.length, 3, sha256.convert(bytes).toString()));
    expect((r.packageName, r.appName, r.versionName, r.versionCode, r.certSha256Hex), ('com.example.demo', '我的应用', '1.2', 12, ''));
    expect(Directory(p.dirname(out)).listSync().map((e) => p.basename(e.path)), ['demo.apk']);

    final entries = {for (final e in readZip(bytes)) e.name: e};
    final info = readManifestInfo(entries['AndroidManifest.xml']!.content());
    expect((info.packageName, info.label, info.versionCode, info.versionName), ('com.example.demo', '我的应用', 12, '1.2'));
    expect(info.permissions, ['android.permission.INTERNET', 'android.permission.CAMERA']);
    expect(jsonDecode(utf8.decode(entries['assets/lopi_shell.json']!.content())), {'entry': 'index.html'});
    expect(entries.keys.where((k) => k.startsWith('assets/www/')), ['assets/www/index.html', 'assets/www/script.js', 'assets/www/style.css']);
    expect(utf8.decode(entries['assets/www/index.html']!.content()), contains('<h1>你好</h1>'), reason: '模板自带的占位网页被换掉了');
    expect(entries['resources.arsc']!.method, kZipStored);
    // 模板里没动的条目字节不变
    final shell = {for (final e in readZip(fakeShell())) e.name: e};
    for (final name in ['classes.dex', 'resources.arsc', 'res/mipmap-mdpi-v4/ic_launcher.png']) {
      expect(entries[name]!.raw, shell[name]!.raw, reason: name);
    }
  });

  test('同样输入两次打包字节完全一样；放不放后台跑也一样', () async {
    final req = requestFor(web, out, icons: fiveIcons());
    await LocalApkPacker(template: fakeShell(), signer: const NoSigner()).pack(req);
    final a = File(out).readAsBytesSync();
    await Future<void>.delayed(const Duration(milliseconds: 1100)); // 跨过一秒：证明产物里没有“当前时间”
    await LocalApkPacker(template: fakeShell(), signer: const NoSigner(), useIsolate: false).pack(req);
    expect(File(out).readAsBytesSync(), a);
  });

  test('换图标：五个密度都换成给的 PNG，不压缩', () async {
    final icons = fiveIcons(r: 10);
    await LocalApkPacker(template: fakeShell(), signer: const NoSigner()).pack(requestFor(web, out, icons: icons));
    final entries = {for (final e in readZip(File(out).readAsBytesSync())) e.name: e};
    const dirs = {48: 'mdpi', 72: 'hdpi', 96: 'xhdpi', 144: 'xxhdpi', 192: 'xxxhdpi'};
    for (final s in dirs.keys) {
      final e = entries['res/mipmap-${dirs[s]}-v4/ic_launcher.png']!;
      expect(e.method, kZipStored);
      expect(e.content(), icons[s]);
    }
  });

  test('签名器对接：v1 拿到全部条目的解压内容，签名文件进了包，证书指纹带回结果', () async {
    final r = await LocalApkPacker(template: fakeShell(), signer: _FakeSigner()).pack(requestFor(web, out));
    expect(r.certSha256Hex, 'ab' * 32);
    final entries = {for (final e in readZip(File(out).readAsBytesSync())) e.name: e};
    expect(entries.keys.where((k) => k.startsWith('META-INF/')), ['META-INF/CERT.RSA', 'META-INF/CERT.SF', 'META-INF/MANIFEST.MF']);
    final mf = utf8.decode(entries['META-INF/MANIFEST.MF']!.content());
    final others = entries.keys.where((k) => !k.startsWith('META-INF/')).toList();
    expect(mf.split('\n').sublist(1, 1 + others.length), others, reason: '签名文件之外的每个条目都交给了 v1');
    final total = others.fold<int>(0, (a, k) => a + entries[k]!.size);
    expect(mf, contains('total:$total'));
  });

  test('模板里原有的签名文件、占位网页不会带进产物；lopi_shell.json 的其他设置保留', () async {
    final shell = _shellWith(
      (es) => [
        for (final e in es)
          if (e.name != 'assets/lopi_shell.json') e,
        ZipEntry.stored('assets/lopi_shell.json', Uint8List.fromList(utf8.encode('{"entry":"old.html","fullscreen":true}'))),
        ZipEntry.stored('META-INF/MANIFEST.MF', Uint8List(3)),
        ZipEntry.stored('META-INF/OLD.SF', Uint8List(3)),
        ZipEntry.stored('META-INF/OLD.RSA', Uint8List(3)),
        ZipEntry.stored('META-INF/services/keep', Uint8List(3)),
      ],
    );
    await LocalApkPacker(template: shell, signer: const NoSigner()).pack(requestFor(web, out));
    final entries = {for (final e in readZip(File(out).readAsBytesSync())) e.name: e};
    expect(entries.keys.where((k) => k.startsWith('META-INF/')), ['META-INF/services/keep']);
    expect(jsonDecode(utf8.decode(entries['assets/lopi_shell.json']!.content())), {'entry': 'index.html', 'fullscreen': true});
  });

  group('真的壳模板', () {
    test('读得出来，符合约定：默认包名、应用名、只有联网、五个图标（目录不带 -v4）、资源表不压缩', () {
      final shell = parseShellTemplate(realShell());
      expect(sha256.convert(realShell()).toString(), '4976223b2b60909d758c636241beaee7fbde9c63fecd0f272226b57033b6d658');
      expect((shell.info.packageName, shell.info.label, shell.info.versionCode, shell.info.versionName), ('com.lopicode.shell', 'LopiApp', 1, '1.0'));
      expect(shell.info.permissions, ['android.permission.INTERNET']);
      expect(shell.iconPaths, {
        for (final d in const ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi']) d: 'res/mipmap-$d/ic_launcher.png',
      });
      expect(shell.entries.firstWhere((e) => e.name == 'resources.arsc').method, kZipStored);
      expect(shell.shellConfig, isEmpty, reason: '真模板不带 assets/lopi_shell.json');
    });

    test('清单读入再原样写出字节一致', () {
      final m = readZip(realShell()).firstWhere((e) => e.name == 'AndroidManifest.xml').content();
      expect(writeAxml(parseAxml(m)), m);
    });

    test('打包：清单改对了、别的属性没动、代码和资源表原样、网页和设置文件放进去了', () async {
      final icons = fiveIcons(r: 90);
      final r = await LocalApkPacker(template: realShell(), signer: const NoSigner()).pack(
        requestFor(
          web,
          out,
          packageName: 'com.shuang.demo',
          appName: '霜霜的应用 😀',
          versionName: '2.3.4',
          versionCode: 77,
          permissions: {'android.permission.INTERNET', 'android.permission.CAMERA', 'android.permission.ACCESS_FINE_LOCATION'},
          icons: icons,
        ),
      );
      final before = {for (final e in readZip(realShell())) e.name: e};
      final after = {for (final e in readZip(File(r.path).readAsBytesSync())) e.name: e};
      final info = readManifestInfo(after['AndroidManifest.xml']!.content());
      expect((info.packageName, info.label, info.versionCode, info.versionName), ('com.shuang.demo', '霜霜的应用 😀', 77, '2.3.4'));
      expect(info.permissions.toSet(), {'android.permission.INTERNET', 'android.permission.CAMERA', 'android.permission.ACCESS_FINE_LOCATION', 'android.permission.ACCESS_COARSE_LOCATION'});
      for (final same in const ['classes.dex', 'resources.arsc']) {
        expect(after[same]!.raw, before[same]!.raw, reason: '$same 一个字节都不该动');
        expect(after[same]!.method, before[same]!.method);
      }
      // 清单里不该动的：主题和图标的资源引用、Activity 类名、meta-data
      final doc = parseAxml(after['AndroidManifest.xml']!.content());
      final strings = doc.pool.strings;
      expect(strings, containsAll(['lopi.shell.MainActivity', 'android.webkit.WebView.MetricsOptOut']));
      expect(strings, isNot(contains('com.lopicode.shell')));
      expect(strings, isNot(contains('LopiApp')));
      final refs = [
        for (final n in doc.nodes.whereType<AxmlStartElement>())
          for (final a in n.attributes)
            if (a.type == kTypeReference) a.data,
      ];
      expect(refs, unorderedEquals([0x7f020000, 0x7f010000]));
      const sizes = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192};
      for (final e in sizes.entries) {
        expect(after['res/mipmap-${e.key}/ic_launcher.png']!.content(), icons[e.value]);
        expect(after['res/mipmap-${e.key}/ic_launcher.png']!.method, kZipStored);
      }
      expect(jsonDecode(utf8.decode(after['assets/lopi_shell.json']!.content())), {'entry': 'index.html'});
      expect(after.keys.where((k) => k.startsWith('assets/www/')), ['assets/www/index.html', 'assets/www/script.js', 'assets/www/style.css']);
    });
  });

  group('坏输入：报明确的错，不留半截产物', () {
    Future<void> packWith(Uint8List template, {ApkPackRequest? req}) => LocalApkPacker(template: template, signer: const NoSigner()).pack(req ?? requestFor(web, out));

    test('损坏的模板', () async {
      final good = fakeShell();
      await expectLater(packWith(Uint8List.fromList(utf8.encode('这不是安装包'))), packError('template', '模板损坏或不匹配'));
      await expectLater(packWith(Uint8List.sublistView(good, 0, good.length ~/ 2)), packError('template', '模板损坏或不匹配'));
      await expectLater(packWith(Uint8List(0)), packError('template', '模板损坏或不匹配'));
      expectNoLeftovers();
    });

    test('模板缺东西：清单、资源表、代码、图标', () async {
      Uint8List without(String name) => _shellWith(
        (es) => [
          for (final e in es)
            if (e.name != name) e,
        ],
      );
      await expectLater(packWith(without('AndroidManifest.xml')), packError('template', '没有 AndroidManifest.xml'));
      await expectLater(packWith(without('resources.arsc')), packError('template', '没有 resources.arsc'));
      await expectLater(packWith(without('classes.dex')), packError('template', '没有 classes.dex'));
      await expectLater(packWith(without('res/mipmap-xhdpi-v4/ic_launcher.png')), packError('template', 'xhdpi'));
      expectNoLeftovers();
    });

    test('模板里某个条目的压缩数据是坏的（代码被改坏）：算模板的问题，不说成“装不下”', () async {
      final bad = _shellWith(
        (es) => [
          for (final e in es) e.name == 'classes.dex' ? ZipEntry.raw(name: e.name, method: e.method, raw: Uint8List.fromList(e.raw)..[e.raw.length ~/ 2] ^= 0xFF, crc32: e.crc32, size: e.size) : e,
        ],
      );
      await expectLater(packWith(bad), packError('template', 'classes.dex'));
      expectNoLeftovers();
    });

    test('模板的清单被截断 / 不符合约定', () async {
      Uint8List withManifest(Uint8List m) => _shellWith((es) => [for (final e in es) e.name == 'AndroidManifest.xml' ? ZipEntry.deflated(e.name, m) : e]);
      final m = fakeManifest();
      await expectLater(packWith(withManifest(Uint8List.sublistView(m, 0, m.length - 40))), packError('template', '截断'));
      final doc = parseAxml(m);
      ManifestEditor(doc).setPackage('com.someone.else');
      await expectLater(packWith(withManifest(writeAxml(doc))), packError('template', '包名应该是 com.lopicode.shell'));
      expectNoLeftovers();
    });

    test('非法包名、应用名、版本、权限', () async {
      await expectLater(packWith(fakeShell(), req: requestFor(web, out, packageName: 'my app')), packError('packageName', '空格'));
      await expectLater(packWith(fakeShell(), req: requestFor(web, out, packageName: 'single')), packError('packageName', '两段'));
      await expectLater(packWith(fakeShell(), req: requestFor(web, out, appName: '')), packError('appName', '不能为空'));
      await expectLater(packWith(fakeShell(), req: requestFor(web, out, versionName: ' ')), packError('versionName', '不能为空'));
      await expectLater(packWith(fakeShell(), req: requestFor(web, out, versionCode: 0)), packError('versionCode', '1 或更大'));
      await expectLater(packWith(fakeShell(), req: requestFor(web, out, versionCode: 2100000001)), packError('versionCode', '2100000000'));
      await expectLater(packWith(fakeShell(), req: requestFor(web, out, permissions: {'not a permission'})), packError('permissions', '写法不对'));
      expectNoLeftovers();
    });

    test('不是 PNG 的图标、尺寸不对、没给齐', () async {
      final jpg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, ...List.filled(200, 7)]);
      await expectLater(packWith(fakeShell(), req: requestFor(web, out, icons: {...fiveIcons(), 96: jpg})), packError('icon', '不是 PNG'));
      await expectLater(packWith(fakeShell(), req: requestFor(web, out, icons: {...fiveIcons(), 96: solidPng(100)})), packError('icon', '100×100'));
      await expectLater(packWith(fakeShell(), req: requestFor(web, out, icons: {48: solidPng(48)})), packError('icon', '还缺'));
      expectNoLeftovers();
    });

    test('项目的问题：没有入口、目录不存在、文件数超限（5001 个）', () async {
      await expectLater(packWith(fakeShell(), req: requestFor(web, out, entry: 'home.html')), packError('project', '找不到入口文件'));
      await expectLater(packWith(fakeShell(), req: requestFor(web, out, entry: '../index.html')), packError('project', '入口文件的路径不对'));
      await expectLater(packWith(fakeShell(), req: requestFor(p.join(tmp.path, 'gone'), out)), packError('project', '找不到要打包的网页目录'));
      for (var i = 0; i < 5001; i++) {
        File(p.join(web, 'many', 'f$i.txt')).createSync(recursive: true);
      }
      await expectLater(packWith(fakeShell()), packError('project', '超过 5000 个'));
      expectNoLeftovers();
    });

    test('单个文件超过 50MB', () async {
      final big = File(p.join(web, 'video.mp4')).openSync(mode: FileMode.write);
      big
        ..setPositionSync(50 * 1024 * 1024)
        ..writeByteSync(1)
        ..closeSync();
      await expectLater(packWith(fakeShell()), packError('project', 'video.mp4 太大了'));
      expectNoLeftovers();
    });

    test('保存不了（输出位置的上级是个文件）：报错，原来打好的旧包还在', () async {
      await packWith(fakeShell());
      final old = File(out).readAsBytesSync();
      final blocker = File(p.join(tmp.path, 'blocker'))..writeAsStringSync('x');
      await expectLater(packWith(fakeShell(), req: requestFor(web, p.join(blocker.path, 'x.apk'))), throwsA(isA<ApkPackException>().having((e) => e.message, 'message', contains('保存不了'))));
      // 打包失败（这次是非法包名）不会动上一次的产物
      await expectLater(packWith(fakeShell(), req: requestFor(web, out, packageName: 'x')), packError('packageName', '两段'));
      expect(File(out).readAsBytesSync(), old);
      expect(Directory(p.dirname(out)).listSync().length, 1);
    });

    test('没预料到的错误（签名器内部出错）原样抛出来，不会卡住', () async {
      final packer = LocalApkPacker(template: fakeShell(), signer: const _CrashSigner());
      await expectLater(packer.pack(requestFor(web, out)), throwsA(isA<StateError>().having((e) => e.message, 'message', contains('签名器炸了'))));
      expectNoLeftovers();
    });
  });

  test('输出文件就在网页目录里（构建产物目录叫 build 的情况）：不会把旧安装包再装进新安装包', () async {
    final dist = p.join(tmp.path, 'proj2', 'build');
    sampleStatic(dist);
    final apk = p.join(dist, 'app.apk');
    await LocalApkPacker(template: fakeShell(), signer: const NoSigner()).pack(requestFor(dist, apk));
    final r = await LocalApkPacker(template: fakeShell(), signer: const NoSigner()).pack(requestFor(dist, apk));
    expect(r.fileCount, 3);
    expect(parseShellTemplate(fakeShell()).iconPaths.length, 5);
  });
}
