// 端到端：随应用发的真壳模板（assets/apk_shell/shell.apk）+ 打包器 + 我们自己的 v1/v2 签名，
// 打出来的包交给官方 aapt2 / zipalign / apksigner 核对。找不到官方工具时整组 skip 并写明原因。不联网。
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/apkpack/apk_pack_contract.dart';
import 'package:lopicode/apkpack/apk_packer.dart';
import 'package:lopicode/apkpack/sign/apk_signer.dart';
import 'package:path/path.dart' as p;

import 'support/apkpack_kit.dart';
import 'support/apkpack_sign_support.dart';

const _internet = 'android.permission.INTERNET';
const _camera = 'android.permission.CAMERA';
const _fine = 'android.permission.ACCESS_FINE_LOCATION';
const _coarse = 'android.permission.ACCESS_COARSE_LOCATION';

void main() {
  final tools = AndroidTools.find();
  late Directory tmp;
  final shell = File('assets/apk_shell/shell.apk').readAsBytesSync();

  setUpAll(() => tmp = Directory.systemTemp.createTempSync('apkpack_e2e_'));
  tearDownAll(() => tmp.deleteSync(recursive: true));

  test('测试夹具里的真模板拷贝和随应用发的模板是同一份（壳重编后要重新拷）', () {
    expect(sha256.convert(realShell()).toString(), sha256.convert(shell).toString());
  });

  String run(String tool, List<String> args) {
    final r = Process.runSync(p.join(tools.buildTools!, tool), args);
    return '${r.stdout}${r.stderr}';
  }

  Future<ApkPackResult> packOne(
    String name,
    void Function(String root) sample, {
    required String packageName,
    required String appName,
    required String versionName,
    required int versionCode,
    required Set<String> permissions,
    Map<int, Uint8List> icons = const {},
    bool useIsolate = false,
  }) async {
    final root = p.join(tmp.path, name);
    sample(root);
    final info = await detectWebProject(root);
    expect(info.applicable, isTrue, reason: info.reason);
    final signer = KeyApkSigner(fixtureKey());
    final out = p.join(tmp.path, 'out', '$name.apk');
    final result = await LocalApkPacker(template: shell, signer: signer, useIsolate: useIsolate).pack(
      requestFor(
        info.webRoot!,
        out,
        entry: info.entry!,
        packageName: packageName,
        appName: appName,
        versionName: versionName,
        versionCode: versionCode,
        permissions: permissions,
        icons: icons,
      ),
    );
    expect(result.certSha256Hex, signer.certSha256Hex);
    expect(File(out).lengthSync(), result.sizeBytes);
    return result;
  }

  void checkOfficial(ApkPackResult r, {required Set<String> permissions}) {
    // 对齐
    expect(run('zipalign', ['-c', '-v', '4', r.path]), contains('Verification succes'));
    // 签名：按最低安卓 5 验，v1、v2 都要是 true；证书指纹和我们报的一致
    final v = run('apksigner', ['verify', '--verbose', '--print-certs', '--min-sdk-version', '21', r.path]);
    expect(v, contains('Verifies'));
    expect(v, contains('Verified using v1 scheme (JAR signing): true'));
    expect(v, contains('Verified using v2 scheme (APK Signature Scheme v2): true'));
    expect(v, contains('certificate SHA-256 digest: ${r.certSha256Hex}'));
    // 按壳的最低版本（安卓 7）再验一次
    expect(run('apksigner', ['verify', '--min-sdk-version', '24', r.path]), isNot(contains('DOES NOT VERIFY')));
    // 清单
    final b = run('aapt2', ['dump', 'badging', r.path]);
    expect(b, contains("package: name='${r.packageName}' versionCode='${r.versionCode}' versionName='${r.versionName}'"));
    expect(b.replaceAll(r'\"', '"'), contains("application-label:'${r.appName}'"));
    expect({for (final m in RegExp(r"^uses-permission: name='([^']*)'", multiLine: true).allMatches(b)) m.group(1)!}, permissions);
    expect(b, contains("application-icon-640:'res/mipmap-xxxhdpi/ic_launcher.png'"));
    expect(b, contains("launchable-activity: name='lopi.shell.MainActivity'"));
    expect(b, contains("minSdkVersion:'24'"));
  }

  group('真模板 + 真签名，官方工具核对', skip: tools.missing, () {
    test('样例一 纯静态页：中文应用名、只联网（在后台 isolate 里打）', () async {
      final r = await packOne('s1', sampleStatic, packageName: 'com.shuang.hello', appName: '你好世界', versionName: '1.0.0', versionCode: 1, permissions: {_internet}, useIsolate: true);
      checkOfficial(r, permissions: {_internet});
    }, timeout: const Timeout(Duration(minutes: 10)));

    test('样例二 带子目录和大图：换五个图标、摄像头 + 定位、表情应用名、很长的包名', () async {
      final longPkg = 'com.${List.filled(13, 'verylongsegment').join('.')}.app';
      final r = await packOne(
        's2',
        sampleWithAssets,
        packageName: longPkg,
        appName: '霜霜的应用 😀 & "测试"',
        versionName: '2.3.4-测试',
        versionCode: 2100000000,
        permissions: {_internet, _camera, _fine},
        icons: fiveIcons(r: 90),
      );
      checkOfficial(r, permissions: {_internet, _camera, _fine, _coarse});
      // 包里的图标确实换成了传进去的
      final unzip = Process.runSync('unzip', ['-p', r.path, 'res/mipmap-xxxhdpi/ic_launcher.png'], stdoutEncoding: null);
      expect(sha256.convert(unzip.stdout as List<int>).toString(), sha256.convert(fiveIcons(r: 90)[192]!).toString());
    }, timeout: const Timeout(Duration(minutes: 10)));

    test('样例三 低代码导出：一个权限都不要', () async {
      final r = await packOne('s3', sampleLowcode, packageName: 'a.b', appName: 'LC', versionName: '0.1', versionCode: 7, permissions: {});
      checkOfficial(r, permissions: {});
    }, timeout: const Timeout(Duration(minutes: 10)));

    test('打好的包改一个字节，官方工具验不过（不是空签）', () async {
      final r = await packOne('s4', sampleStatic, packageName: 'com.shuang.t', appName: 'T', versionName: '1', versionCode: 1, permissions: {_internet});
      final bytes = File(r.path).readAsBytesSync();
      bytes[bytes.length ~/ 3] ^= 0x01;
      final bad = p.join(tmp.path, 'out', 'bad.apk');
      File(bad).writeAsBytesSync(bytes);
      expect(run('apksigner', ['verify', '--min-sdk-version', '24', bad]), contains('DOES NOT VERIFY'));
    }, timeout: const Timeout(Duration(minutes: 10)));
  });
}
