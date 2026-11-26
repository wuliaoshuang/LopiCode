// 用安卓官方工具（aapt2、zipalign、apksigner）核对打包器的产物。
// 开发机上有 SDK 才跑；找不到工具时整组 skip 并写明原因（不会假装通过）。不联网。
//
// 签名：打包器这里用“不签名”的替身，产物交给官方 apksigner 用临时钥匙签（v1 + v2），再 `apksigner verify --min-sdk-version 24`；
// 另用 `--min-sdk-version 21` 再验一遍，让 v1（JAR 签名）也真的被检查到。
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/apkpack/apk_packer.dart';
import 'package:lopicode/apkpack/axml/axml_codec.dart';
import 'package:lopicode/apkpack/axml/axml_model.dart';
import 'package:lopicode/apkpack/manifest_editor.dart';
import 'package:lopicode/apkpack/zip/zip_model.dart';
import 'package:lopicode/apkpack/zip/zip_reader.dart';
import 'package:lopicode/apkpack/zip/zip_writer.dart';
import 'package:path/path.dart' as p;

import 'support/apkpack_kit.dart';

const _internet = 'android.permission.INTERNET';
const _camera = 'android.permission.CAMERA';
const _fine = 'android.permission.ACCESS_FINE_LOCATION';
const _coarse = 'android.permission.ACCESS_COARSE_LOCATION';

/// 从 `aapt2 dump badging` 的输出里取值。
class _Badging {
  _Badging(this.text);
  final String text;
  String? _m(String pattern) => RegExp(pattern, multiLine: true).firstMatch(text)?.group(1);
  String? get package => _m(r"^package: name='([^']*)'");
  String? get versionCode => _m(r"^package: .*versionCode='([^']*)'");
  String? get versionName => _m(r"^package: .*versionName='([^']*)'");

  /// aapt2 打印应用名时会把双引号写成 `\"`（它的显示转义，实测；不是清单里的内容），这里还原回来再比。
  String? get label => _m(r"^application-label:'(.*)'$")?.replaceAll(r'\"', '"');
  Set<String> get permissions => {for (final m in RegExp(r"^uses-permission: name='([^']*)'", multiLine: true).allMatches(text)) m.group(1)!};
  Map<String, String> get icons => {for (final m in RegExp(r"^application-icon-(\d+):'([^']*)'", multiLine: true).allMatches(text)) m.group(1)!: m.group(2)!};
  String? get launchable => _m(r"^launchable-activity: name='([^']*)'");
}

const _iconsByDpi = {
  '160': 'res/mipmap-mdpi-v4/ic_launcher.png',
  '240': 'res/mipmap-hdpi-v4/ic_launcher.png',
  '320': 'res/mipmap-xhdpi-v4/ic_launcher.png',
  '480': 'res/mipmap-xxhdpi-v4/ic_launcher.png',
  '640': 'res/mipmap-xxxhdpi-v4/ic_launcher.png',
};

void main() {
  final tools = AndroidTools.find();
  late Directory tmp;
  String? keystore;

  setUpAll(() {
    tmp = Directory.systemTemp.createTempSync('apkpack_official_');
    if (tools.missing == null) keystore = AndroidTools.makeTestKey(tmp.path);
  });
  tearDownAll(() => tmp.deleteSync(recursive: true));

  /// 打包 + 三项官方核对。返回 badging。
  Future<_Badging> packAndCheck(
    String name,
    void Function(String root) sample, {
    required String packageName,
    required String appName,
    required String versionName,
    required int versionCode,
    required Set<String> permissions,
    Map<int, Uint8List> icons = const {},
    Uint8List? template,
    Map<String, String> iconPaths = _iconsByDpi,
    bool sign = true,
  }) async {
    final root = p.join(tmp.path, name);
    sample(root);
    final out = p.join(tmp.path, 'out', '$name.apk');
    final watch = Stopwatch()..start();
    final r = await LocalApkPacker(
      template: template ?? fakeShell(),
      signer: const NoSigner(),
    ).pack(requestFor(root, out, packageName: packageName, appName: appName, versionName: versionName, versionCode: versionCode, permissions: permissions, icons: icons));
    final ms = watch.elapsedMilliseconds;
    // ignore: avoid_print 汇报要用：一次打包在开发机上的耗时
    print('[$name] 打包耗时 $ms 毫秒，${r.fileCount} 个网页文件，安装包 ${r.sizeBytes} 字节');

    // 1. aapt2 dump badging：包名、应用名、版本、权限、图标路径
    final b = _Badging(tools.badging(out));
    expect(b.package, packageName);
    expect(b.label, appName);
    expect(b.versionCode, '$versionCode');
    expect(b.versionName, versionName);
    expect(b.permissions, expandPermissions(permissions));
    expect(b.icons, iconPaths);
    expect(b.launchable, 'lopi.shell.MainActivity');
    // aapt2 dump xmltree 也读得出来
    expect(tools.xmltree(out), contains('E: manifest'));

    // 2. zipalign -c -v 4
    final z = tools.zipalignCheck(out);
    expect(z.exitCode, 0, reason: 'zipalign：${z.stdout}${z.stderr}');
    expect(z.stdout as String, matches(RegExp('Verification succes+ful')));
    expect(z.stdout as String, isNot(contains('BAD')));

    // 3. apksigner（临时钥匙）签名后验证
    if (sign) {
      expect(keystore, isNotNull, reason: '没有 keytool，造不出临时钥匙');
      final (ok, log) = tools.signAndVerify(out, keystore!, p.join(tmp.path, 'out', '$name-signed.apk'));
      expect(ok, isTrue, reason: 'apksigner：$log');
      final at24 = log.substring(0, log.indexOf('[min-sdk 21]'));
      expect(at24, contains('Verifies'));
      expect(at24, contains('Verified using v2 scheme (APK Signature Scheme v2): true'));
      expect(log.substring(log.indexOf('[min-sdk 21]')), contains('Verified using v1 scheme (JAR signing): true'));
      // ignore: avoid_print 汇报要用：官方工具的结论原话
      print('[$name] apksigner verify --min-sdk-version 24：${at24.split('\n').where((l) => l.startsWith('Verif')).take(3).join('；')}');
      // 签完以后清单没变
      expect(_Badging(tools.badging(p.join(tmp.path, 'out', '$name-signed.apk'))).package, packageName);
    }
    return b;
  }

  group('官方工具核对', skip: tools.missing, () {
    test('样例一 纯静态页：中文应用名、比默认短的包名、只联网、版本号下边界', () async {
      await packAndCheck('static', sampleStatic, packageName: 'a.b', appName: '我的第一个应用', versionName: '1.0.0', versionCode: 1, permissions: {_internet});
    }, timeout: const Timeout(Duration(minutes: 10)));

    test('样例二 带子目录和大图：表情和特殊字符的应用名、很长的包名、换五个图标、摄像头 + 定位、版本号上边界', () async {
      final icons = fiveIcons(r: 20);
      final longPkg = 'com.example.${List.filled(19, 'abcdefghij').join('.')}.xy'; // 223 个字符，上限
      expect(longPkg.length, 223);
      await packAndCheck(
        'assets',
        sampleWithAssets,
        packageName: longPkg,
        appName: 'A&B <测试> "引号" 😀🎉 100%',
        versionName: '2.10.3-beta+build.5',
        versionCode: 2100000000,
        permissions: {_internet, _camera, _fine},
        icons: icons,
      );
      final out = p.join(tmp.path, 'out', 'assets.apk');
      final entries = {for (final e in readZip(File(out).readAsBytesSync())) e.name: e};
      const sizeByDpi = {'160': 48, '240': 72, '320': 96, '480': 144, '640': 192};
      for (final e in _iconsByDpi.entries) {
        expect(entries[e.value]!.content(), icons[sizeByDpi[e.key]], reason: 'aapt2 报的图标路径上放的就是给的那张图');
      }
      expect(entries['assets/www/img/big.png']!.method, kZipStored, reason: '图片不再压缩');
      expect(entries['assets/www/js/app/main.js']!.method, kZipDeflated);
      expect(entries.keys, contains('assets/www/img/图标 一.svg'));
      expect(entries.keys.where((k) => k.contains('node_modules') || k.contains('.git') || k.contains('.env') || k.contains('old.apk')), isEmpty);
    }, timeout: const Timeout(Duration(minutes: 10)));

    test('样例三 模拟低代码导出：比默认长的包名、一个权限都不要', () async {
      final b = await packAndCheck('lowcode', sampleLowcode, packageName: 'io.github.someone.lowcode_page.release', appName: '低代码页面', versionName: '0.1', versionCode: 42, permissions: {});
      expect(b.permissions, isEmpty);
      final entries = readZip(File(p.join(tmp.path, 'out', 'lowcode.apk')).readAsBytesSync()).map((e) => e.name).where((n) => n.startsWith('assets/'));
      expect(entries, ['assets/lopi_shell.json', 'assets/www/index.html', 'assets/www/logic.js', 'assets/www/style.css']);
    }, timeout: const Timeout(Duration(minutes: 10)));

    test('真的壳模板 + 带子目录和大图的样例：换图标、摄像头 + 定位、中文和表情应用名，三项官方核对都过', () async {
      final icons = fiveIcons(r: 120);
      const paths = {
        '160': 'res/mipmap-mdpi/ic_launcher.png',
        '240': 'res/mipmap-hdpi/ic_launcher.png',
        '320': 'res/mipmap-xhdpi/ic_launcher.png',
        '480': 'res/mipmap-xxhdpi/ic_launcher.png',
        '640': 'res/mipmap-xxxhdpi/ic_launcher.png',
      };
      await packAndCheck(
        'real',
        sampleWithAssets,
        packageName: 'com.shuang.demo.app2',
        appName: '霜霜的应用 😀 & "测试"',
        versionName: '2.3.4-测试',
        versionCode: 77,
        permissions: {_internet, _camera, _fine},
        icons: icons,
        template: realShell(),
        iconPaths: paths,
      );
      final tree = tools.xmltree(p.join(tmp.path, 'out', 'real.apk'));
      // 不该动的都还在：主题和图标的资源引用、Activity、meta-data、SDK 版本
      expect(tree, contains('@0x7f020000'));
      expect(tree, contains('@0x7f010000'));
      expect(tree, contains('lopi.shell.MainActivity'));
      expect(tree, contains('android.webkit.WebView.MetricsOptOut'));
      final badging = tools.badging(p.join(tmp.path, 'out', 'real.apk'));
      expect(badging, contains("minSdkVersion:'24'"));
      expect(badging, contains("targetSdkVersion:'35'"));
    }, timeout: const Timeout(Duration(minutes: 10)));

    test('真的壳模板 + 纯静态页和低代码样例：默认图标、只联网 / 一个权限都不要', () async {
      const paths = {
        '160': 'res/mipmap-mdpi/ic_launcher.png',
        '240': 'res/mipmap-hdpi/ic_launcher.png',
        '320': 'res/mipmap-xhdpi/ic_launcher.png',
        '480': 'res/mipmap-xxhdpi/ic_launcher.png',
        '640': 'res/mipmap-xxxhdpi/ic_launcher.png',
      };
      await packAndCheck('real-static', sampleStatic, packageName: 'a.b', appName: '我的第一个应用', versionName: '1.0.0', versionCode: 1, permissions: {_internet}, template: realShell(), iconPaths: paths);
      final b = await packAndCheck(
        'real-lowcode',
        sampleLowcode,
        packageName: 'io.github.someone.lowcode_page.release',
        appName: '低代码页面',
        versionName: '0.1',
        versionCode: 2100000000,
        permissions: {},
        template: realShell(),
        iconPaths: paths,
      );
      expect(b.permissions, isEmpty);
    }, timeout: const Timeout(Duration(minutes: 15)));

    test('权限一步步改：只联网 → 加摄像头和定位 → 全部去掉只留联网，每一步 aapt2 都读得对', () {
      Set<String> permsOf(Uint8List manifest, String name) {
        final apk = p.join(tmp.path, '$name.apk');
        File(apk).writeAsBytesSync(writeZip([for (final e in readZip(fakeShell())) e.name == 'AndroidManifest.xml' ? ZipEntry.deflated(e.name, manifest) : e]));
        expect(tools.xmltree(apk), contains('E: manifest'));
        return _Badging(tools.badging(apk)).permissions;
      }

      ManifestEdit edit(Set<String> perms) => ManifestEdit(packageName: kShellDefaultPackage, appName: '权限', versionCode: 1, versionName: '1', permissions: perms);
      final m1 = editManifestBytes(fakeManifest(), edit({_internet}));
      expect(permsOf(m1, 'p1'), {_internet});
      final m2 = editManifestBytes(m1, edit({_internet, _camera, _fine}));
      expect(permsOf(m2, 'p2'), {_internet, _camera, _fine, _coarse});
      final m3 = editManifestBytes(m2, edit({_internet}));
      expect(permsOf(m3, 'p3'), {_internet});
      expect(m3, m1, reason: '改过去再改回来，清单字节和一开始改出来的一样');
    });

    test('UTF-8 字符串池的模板：打出来的包 aapt2 一样读得对（含表情）', () async {
      final doc = parseAxml(fakeManifest());
      final utf8Doc = AxmlDocument(
        pool: AxmlStringPool(strings: [...doc.pool.strings], utf8: true, sorted: false),
        resourceIds: doc.resourceIds,
        hasResourceMap: doc.hasResourceMap,
        nodes: doc.nodes,
      );
      final shell = writeZip([for (final e in readZip(fakeShell())) e.name == 'AndroidManifest.xml' ? ZipEntry.deflated(e.name, writeAxml(utf8Doc)) : e]);
      await packAndCheck(
        'utf8',
        sampleStatic,
        packageName: 'com.example.utf8',
        appName: '表情😀应用 & more',
        versionName: '3.2.1',
        versionCode: 99,
        permissions: {_internet, _camera},
        template: shell,
        sign: false,
      );
    }, timeout: const Timeout(Duration(minutes: 10)));

    test('包名改了、resources.arsc 没动：aapt2 仍能从资源表里找到图标（文档里“不用改 arsc”的最低证据）', () async {
      final b = await packAndCheck('arsc', sampleStatic, packageName: 'org.totally.different', appName: 'x', versionName: '1', versionCode: 1, permissions: {_internet}, sign: false);
      expect(b.icons.length, 5);
      final r = tools.run('aapt2', ['dump', 'resources', p.join(tmp.path, 'out', 'arsc.apk')]);
      expect(r.stdout as String, contains('Package name=com.lopicode.shell id=7f'));
    }, timeout: const Timeout(Duration(minutes: 10)));
  });
}
