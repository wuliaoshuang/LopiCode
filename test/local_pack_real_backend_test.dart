// 界面用的生产实现（RealLocalPackBackend）走一遍真流程：读应用自带的模板 → 现生成一把钥匙 → 导出备份再导入 →
// 识别项目 → 打包 → 官方 apksigner / aapt2 核对。找不到官方工具时最后的核对 skip 并写明原因。不联网。
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/apkpack/apk_pack_contract.dart';
import 'package:lopicode/build/local_pack_backend_real.dart';
import 'package:path/path.dart' as p;

import 'support/apkpack_kit.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final tools = AndroidTools.find();

  test('生产实现：模板、钥匙、备份往返、打包，产物官方工具认', () async {
    const real = RealLocalPackBackend();
    final tmp = Directory.systemTemp.createTempSync('apkpack_real_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final template = await real.loadTemplate();
    expect(sha256.convert(template).toString(), sha256.convert(File(kApkShellAsset).readAsBytesSync()).toString());

    final key = await real.generateKey(commonName: 'LopiCode App Key');
    expect(key.certSha256Hex, hasLength(64));
    expect(real.parseKey(key.serialize()).certSha256Hex, key.certSha256Hex);

    final backup = await real.exportKey(key, '口令 passphrase 1');
    expect(backup, isNot(contains(key.serialize().split('\n')[1])), reason: '备份里不是明文私钥');
    final back = await real.importKey(backup, '口令 passphrase 1');
    expect(back.certSha256Hex, key.certSha256Hex);
    await expectLater(real.importKey(backup, '不对的口令 123'), throwsA(isA<ApkPackException>()));

    final root = p.join(tmp.path, 'proj');
    sampleStatic(root);
    final info = await real.detectProject(root);
    expect(info.applicable, isTrue, reason: info.reason);

    final steps = <ApkPackStep>[];
    final out = p.join(root, 'build', '演示-1.0.0-3.apk');
    final r = await real.pack(
      template: template,
      key: back,
      request: requestFor(info.webRoot!, out, entry: info.entry!, packageName: 'com.lopicode.app.demo', appName: '演示', versionCode: 3),
      onProgress: (pr) => steps.add(pr.step),
    );
    expect(steps.toSet(), containsAll([ApkPackStep.collect, ApkPackStep.manifest, ApkPackStep.sign, ApkPackStep.done]));
    expect(r.certSha256Hex, key.certSha256Hex);
    expect(File(out).existsSync(), isTrue);

    if (tools.missing != null) {
      markTestSkipped(tools.missing!);
      return;
    }
    String run(String tool, List<String> args) {
      final x = Process.runSync(p.join(tools.buildTools!, tool), args);
      return '${x.stdout}${x.stderr}';
    }

    final v = run('apksigner', ['verify', '--verbose', '--print-certs', '--min-sdk-version', '21', out]);
    expect(v, contains('Verified using v1 scheme (JAR signing): true'));
    expect(v, contains('Verified using v2 scheme (APK Signature Scheme v2): true'));
    expect(v, contains('certificate SHA-256 digest: ${key.certSha256Hex}'));
    expect(run('aapt2', ['dump', 'badging', out]), contains("package: name='com.lopicode.app.demo' versionCode='3' versionName='1.0.0'"));
    expect(run('zipalign', ['-c', '-v', '4', out]), contains('Verification succes'));
  }, timeout: const Timeout(Duration(minutes: 15)));
}
