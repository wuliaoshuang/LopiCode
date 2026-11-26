// 本地打包签名：拿官方工具验（apksigner、zipalign、jarsigner、keytool、openssl）。
// 开发机上真跑；哪个工具不在，用到它的测试就明确 skip（纯 Dart 的向量测试在另外几个文件里，不受影响）。全程不联网。
//
// 夹具：test/fixtures/apkpack_sign/minimal-unsigned.apk（make_fixture.sh 用 aapt2 / d8 / zipalign 造的最小未签名 APK）。
// 注意 apksigner 的一个脾气（2026-11-26 实测，官方工具自己签的包也一样）：带 --min-sdk-version 24 时它根本不去验 v1，
// 所以那一行永远打印 “Verified using v1 scheme (JAR signing): false”。要看到 v1、v2 同时为 true，得用 --min-sdk-version 21（不设上限）。
// 大文件：~/workspace/lopicode/.tmp/ 下已有的 LopiCode 安装包（只读，不在就 skip）。
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/apkpack/sign/apk_signer.dart';
import 'package:lopicode/apkpack/sign/der.dart';
import 'package:lopicode/apkpack/sign/key_backup.dart';
import 'package:lopicode/apkpack/sign/signing_key.dart';
import 'package:lopicode/apkpack/sign/v1_sign.dart';
import 'package:lopicode/apkpack/sign/v2_sign.dart';
import 'package:lopicode/apkpack/sign/x509.dart';

import 'support/apkpack_sign_support.dart';

void main() {
  final tools = SignTools.find();
  final key = fixtureKey();
  final signer = KeyApkSigner(key);
  final fixture = File('$kSignFixtureDir/minimal-unsigned.apk').readAsBytesSync();
  final rnd = Random(21);
  Uint8List randomBytes(int n) => Uint8List.fromList(List.generate(n, (_) => rnd.nextInt(256)));
  late Directory tmp;

  setUpAll(() => tmp = Directory.systemTemp.createTempSync('lopi_sign_'));
  tearDownAll(() => tmp.deleteSync(recursive: true));

  String write(String name, List<int> bytes) {
    final f = File('${tmp.path}/$name')..writeAsBytesSync(bytes);
    return f.path;
  }

  String? need(List<String?> which, String names) => which.any((t) => t == null) ? '开发机上没有 $names，这一条跳过' : null;
  final noApksigner = need([tools.apksigner], 'apksigner（或 Java）');

  (int, String) verify(String path, {int min = 24, int? max}) => tools.run(tools.apksigner!, [
    'verify',
    '--verbose',
    '--print-certs',
    '--min-sdk-version',
    '$min',
    if (max != null) ...['--max-sdk-version', '$max'],
    path,
  ]);

  /// v1 + v2 全套：算 v1 文件 → 写 ZIP → （有 zipalign 就对齐）→ v2。
  Uint8List fullSign(Map<String, Uint8List> entries, {String tag = 'a'}) {
    var zip = storedZip({...entries, ...signer.v1Files(entries)});
    if (tools.zipalign != null) {
      final raw = write('$tag-raw.apk', zip);
      final aligned = '${tmp.path}/$tag-aligned.apk';
      final (code, out) = tools.run(tools.zipalign!, ['-f', '4', raw, aligned]);
      expect(code, 0, reason: out);
      zip = File(aligned).readAsBytesSync();
    }
    return signer.v2(zip);
  }

  final fixtureEntries = readZipEntries(fixture);

  group('apksigner', () {
    test('v1 + v2：--min-sdk-version 24 验证通过（v2 true）；--min-sdk-version 21 时 v1、v2 都是 true；证书 SHA-256 和 certSha256Hex 一致；签完仍然是对齐的', () {
      final path = write('full.apk', fullSign(fixtureEntries));
      final (code24, out24) = verify(path);
      expect(code24, 0, reason: out24);
      expect(out24, contains('Verifies'));
      expect(out24, contains('Verified using v2 scheme (APK Signature Scheme v2): true'));
      expect(out24, contains('Signer #1 certificate SHA-256 digest: ${key.certSha256Hex}'));
      final (code, out) = verify(path, min: 21);
      expect(code, 0, reason: out);
      expect(out, contains('Verifies'));
      expect(out, contains('Verified using v1 scheme (JAR signing): true'));
      expect(out, contains('Verified using v2 scheme (APK Signature Scheme v2): true'));
      expect(out, contains('Number of signers: 1'));
      expect(out, contains('Signer #1 certificate SHA-256 digest: ${key.certSha256Hex}'));
      expect(out, contains('Signer #1 key size (bits): 2048'));
      expect(out.contains('WARNING'), isFalse, reason: out);
      if (tools.zipalign != null) {
        final (c, o) = tools.run(tools.zipalign!, ['-c', '4', path]);
        expect(c, 0, reason: o);
      }
    }, skip: noApksigner);

    test('同一个包按 Android 5–6（--min-sdk-version 21 --max-sdk-version 23，只看 v1）验证也通过', () {
      final path = write('full-old.apk', fullSign(fixtureEntries, tag: 'b'));
      final (code, out) = verify(path, min: 21, max: 23);
      expect(code, 0, reason: out);
      expect(out, contains('Verified using v1 scheme (JAR signing): true'));
      expect(out, contains('Signer #1 certificate SHA-256 digest: ${key.certSha256Hex}'));
    }, skip: noApksigner);

    test('只做 v2（夹具原样，不加 v1 文件）：--min-sdk-version 24 通过，v1 false、v2 true', () {
      final path = write('v2only.apk', signer.v2(fixture));
      final (code, out) = verify(path);
      expect(code, 0, reason: out);
      expect(out, contains('Verified using v1 scheme (JAR signing): false'));
      expect(out, contains('Verified using v2 scheme (APK Signature Scheme v2): true'));
      expect(out, contains('Signer #1 certificate SHA-256 digest: ${key.certSha256Hex}'));
      // 只有 v2 的包在 Android 6 及以前装不上：apksigner 也应该这么说。
      expect(verify(path, min: 21, max: 23).$1 == 0, isFalse);
    }, skip: noApksigner);

    test('只做 v1（不写防剥离标记）：按 Android 5–6 验证通过；写了防剥离标记却没做 v2 的包，Android 7+ 拒绝', () {
      final v1Only = storedZip({...fixtureEntries, ...v1SignatureFiles(fixtureEntries, key, alsoV2Signed: false)});
      final path = write('v1only.apk', v1Only);
      final (code, out) = verify(path, min: 21, max: 23);
      expect(code, 0, reason: out);
      expect(out, contains('Verified using v1 scheme (JAR signing): true'));
      // 不设上限时不通过，是因为夹具的 targetSdk 是 35：Android 11 起的目标版本必须有 v2。这是系统的规矩，不是 v1 签错了。
      final (c1, o1) = verify(path, min: 21);
      expect(c1 == 0, isFalse);
      expect(o1, contains('requires a minimum of signature scheme v2'));

      final stripped = write('stripped.apk', storedZip({...fixtureEntries, ...signer.v1Files(fixtureEntries)}));
      final (c2, o2) = verify(stripped);
      expect(c2 == 0, isFalse, reason: '防剥离标记应该让它不通过：$o2');
    }, skip: noApksigner);

    test('条目名带中文、带空格、超长（清单折行）：v1、v2 都通过', () {
      final entries = {
        ...fixtureEntries,
        'assets/www/首页.html': Uint8List.fromList(utf8.encode('<h1>你好</h1>')),
        'assets/www/图片 目录/封 面.png': randomBytes(300),
        'assets/www/${'很长的目录名' * 8}/${'x' * 90}.js': randomBytes(50),
        'assets/www/empty.css': Uint8List(0),
      };
      final path = write('names.apk', fullSign(entries, tag: 'n'));
      for (final (min, max) in [(21, null), (21, 23)]) {
        final (code, out) = verify(path, min: min, max: max);
        expect(code, 0, reason: out);
        expect(out, contains('Verified using v1 scheme (JAR signing): true'));
      }
      final (code, out) = verify(path);
      expect(code, 0, reason: out);
      expect(out, contains('Verified using v2 scheme (APK Signature Scheme v2): true'));
    }, skip: noApksigner);

    test('多块：条目内容段超过 1MB、正好 1MB、正好 2MB，都通过', () {
      const mb = 1048576;
      // 跨好几块。
      final big = {...fixtureEntries, 'assets/big.bin': randomBytes(3 * mb + 12345)};
      var (code, out) = verify(write('big.apk', fullSign(big, tag: 'big')));
      expect(code, 0, reason: out);
      expect(out, contains('Verified using v2 scheme (APK Signature Scheme v2): true'));

      // 正好落在块边界：先量出没有填充时条目段多长，再用填充文件凑到正好 1MB / 2MB（这里不过 zipalign，免得它挪动偏移）。
      for (final target in [mb, 2 * mb]) {
        Map<String, Uint8List> withPad(int n) => {...fixtureEntries, 'assets/pad.bin': n == 0 ? Uint8List(0) : randomBytes(n)};
        Uint8List build(int n) {
          final all = withPad(n); // 只造一次：清单里记的摘要和包里放的得是同一份内容
          return storedZip({...all, ...signer.v1Files(all)});
        }

        final base = locateApkZipSections(build(0)).cdOffset;
        final apk = signer.v2(build(target - base));
        expect(locateApkZipSections(apk).entriesEnd, target);
        (code, out) = verify(write('edge-$target.apk', apk), min: 21);
        expect(code, 0, reason: out);
        expect(out, contains('Verified using v1 scheme (JAR signing): true'));
        expect(out, contains('Verified using v2 scheme (APK Signature Scheme v2): true'));
      }
    }, skip: noApksigner);

    test('ZIP 结尾带注释的包：通过', () {
      final zip = storedZip({...fixtureEntries, ...signer.v1Files(fixtureEntries)}, comment: utf8.encode('built by LopiCode 测试'));
      final (code, out) = verify(write('comment.apk', signer.v2(zip)));
      expect(code, 0, reason: out);
    }, skip: noApksigner);

    test('签完以后改一个字节（条目内容、中央目录、签名块里的签名各改一次）：验证必须失败', () {
      final good = fullSign(fixtureEntries, tag: 't');
      expect(verify(write('tamper-good.apk', good)).$1, 0);
      final s = locateApkZipSections(good);
      // 找到 classes.dex 的内容所在位置（不压缩，内容原样在文件里）。
      final dex = fixtureEntries['classes.dex']!;
      final dexAt = toHex(good).indexOf(toHex(dex)) ~/ 2;
      expect(dexAt > 0, isTrue);
      final spots = {'条目内容': dexAt + 40, '中央目录': s.cdOffset + 20, '签名块': s.entriesEnd + 700};
      spots.forEach((what, at) {
        final bad = Uint8List.fromList(good)..[at] ^= 0x01;
        final path = write('tamper-$at.apk', bad);
        final (code, out) = verify(path);
        expect(code == 0, isFalse, reason: '改了$what还通过了：$out');
        expect(out, contains('DOES NOT VERIFY'));
      });
      // 条目内容被改，老系统（只看 v1）也要验不过。
      final bad = Uint8List.fromList(good)..[dexAt + 40] ^= 0x01;
      final (code, out) = verify(write('tamper-v1.apk', bad), min: 21, max: 23);
      expect(code == 0, isFalse, reason: out);
    }, skip: noApksigner);

    test('换一把钥匙签：打印的证书 SHA-256 跟着变', () {
      final key2 = fixtureKey('test-only-key-2.pem');
      final s2 = KeyApkSigner(key2);
      final apk = s2.v2(storedZip({...fixtureEntries, ...s2.v1Files(fixtureEntries)}));
      final (code, out) = verify(write('key2.apk', apk));
      expect(code, 0, reason: out);
      expect(out, contains('Signer #1 certificate SHA-256 digest: ${key2.certSha256Hex}'));
      expect(out.contains(key.certSha256Hex), isFalse);
    }, skip: noApksigner);

    final bigApk = File('${Platform.environment['HOME']}/workspace/lopicode/.tmp/LopiCode-1.0.0-1125e.apk');
    test(
      '大文件：已有的 LopiCode 安装包（13MB，官方工具签过）——直接重签 v2、以及拆开全部条目重做 v1 + v2，都通过',
      () {
        final original = bigApk.readAsBytesSync();
        expect(locateApkZipSections(original).hasSigningBlock, isTrue);
        // 一、原包（压缩方式原样）丢掉旧签名块，用测试钥匙重签 v2。
        var (code, out) = verify(write('lopi-v2.apk', signer.v2(original)));
        expect(code, 0, reason: out);
        expect(out, contains('Verified using v2 scheme (APK Signature Scheme v2): true'));
        expect(out, contains('Signer #1 certificate SHA-256 digest: ${key.certSha256Hex}'));
        // 二、读出全部条目（去掉旧的签名文件），重做 v1 + v2。
        final entries = readZipEntries(original)..removeWhere((name, _) => isV1SignatureEntry(name));
        expect(entries.length > 50, isTrue);
        final path = write('lopi-full.apk', signer.v2(storedZip({...entries, ...signer.v1Files(entries)})));
        (code, out) = verify(path);
        expect(code, 0, reason: out);
        (code, out) = verify(path, min: 21);
        expect(code, 0, reason: out);
        expect(out, contains('Verified using v1 scheme (JAR signing): true'));
        expect(out, contains('Verified using v2 scheme (APK Signature Scheme v2): true'));
        (code, out) = verify(path, min: 21, max: 23);
        expect(code, 0, reason: out);
      },
      skip: noApksigner ?? (bigApk.existsSync() ? null : '没有 ${bigApk.path}，这一条跳过'),
      timeout: const Timeout(Duration(minutes: 10)),
    );
  });

  group('JDK 的 jarsigner / keytool（交叉验证 v1）', () {
    test('jarsigner -verify：jar verified；keytool -printcert -jarfile 读出的证书 SHA-256 一致', () {
      final entries = {...fixtureEntries, 'assets/www/首页.html': Uint8List.fromList(utf8.encode('你好')), 'assets/${'long/' * 30}a.txt': randomBytes(9)};
      final path = write('jar.apk', signer.v2(storedZip({...entries, ...signer.v1Files(entries)})));
      var (code, out) = tools.run(tools.jarsigner!, ['-verify', '-verbose', '-certs', path]);
      expect(code, 0, reason: out);
      expect(out, contains('jar verified.'));
      expect(out.contains('jar is unsigned'), isFalse);
      expect(out.contains('SecurityException'), isFalse);
      // 每个条目都标成“签名已验证”（s）且在清单里（m）。
      expect(RegExp(r'^\s*sm\s+\d+ .* classes\.dex$', multiLine: true).hasMatch(out), isTrue, reason: out);

      (code, out) = tools.run(tools.keytool!, ['-printcert', '-jarfile', path]);
      expect(code, 0, reason: out);
      final fingerprint = RegExp(r'SHA256: ([0-9A-F:]+)').firstMatch(out)?.group(1)?.replaceAll(':', '').toLowerCase();
      expect(fingerprint, key.certSha256Hex);
      expect(out, contains('SHA256withRSA'));
      expect(out, contains('2048-bit RSA key'));

      // 改一个字节的内容，jarsigner 也要发现。
      final good = File(path).readAsBytesSync();
      final at = toHex(good).indexOf(toHex(fixtureEntries['classes.dex']!)) ~/ 2;
      final bad = Uint8List.fromList(good)..[at + 30] ^= 0x01;
      (code, out) = tools.run(tools.jarsigner!, ['-verify', write('jar-bad.apk', bad)]);
      expect(out.contains('jar verified.'), isFalse, reason: out);
    }, skip: need([tools.jarsigner, tools.keytool], 'jarsigner / keytool'));
  });

  group('openssl', () {
    final noOpenssl = need([tools.openssl], 'openssl');
    const pass = '仅测试用的口令 test-only';

    test('x509 -inform DER -text 读得出证书：v3、sha256WithRSAEncryption、2048 位、30 年、中文名字', () {
      final k = asRsaSigningKey(parseSigningKey(File('$kSignFixtureDir/test-only-key.pem').readAsStringSync()));
      final (code, out) = tools.run(tools.openssl!, [
        'x509',
        '-inform',
        'DER',
        '-in',
        write('cert.der', k.certificateDer),
        '-noout',
        '-text',
        '-nameopt',
        'utf8,sep_comma_plus',
        '-fingerprint',
        '-sha256',
      ]);
      expect(code, 0, reason: out);
      expect(out, contains('Version: 3 (0x2)'));
      expect(out, contains('Signature Algorithm: sha256WithRSAEncryption'));
      expect(out, contains('Public-Key: (2048 bit)'));
      expect(out, contains('Exponent: 65537 (0x10001)'));
      expect(out, contains('CN=LopiCode 仅测试用钥匙'));
      expect(out, contains('CA:TRUE'));
      final notBefore = RegExp(r'Not Before: .* (\d{4}) GMT').firstMatch(out)!.group(1)!;
      final notAfter = RegExp(r'Not After : .* (\d{4}) GMT').firstMatch(out)!.group(1)!;
      expect(int.parse(notAfter) - int.parse(notBefore), 30);
      expect(out.replaceAll(':', '').toLowerCase(), contains(k.certSha256Hex));
      // 证书的自签名 openssl 也验得过。
      final pem = write('cert.pem', utf8.encode(pemEncode('CERTIFICATE', k.certificateDer)));
      final (c2, o2) = tools.run(tools.openssl!, ['verify', '-CAfile', pem, pem]);
      expect(c2, 0, reason: o2);
      expect(o2, contains('OK'));
    }, skip: noOpenssl);

    test('dgst -sha256 -verify 验得过我们的 RSA 签名；改了内容验不过；pkey -check 说私钥是好的', () {
      final data = randomBytes(5000);
      final sig = key.sign(data);
      final (c0, pub) = tools.run(tools.openssl!, ['x509', '-in', write('k.pem', utf8.encode(key.serialize())), '-pubkey', '-noout']);
      expect(c0, 0);
      final pubPath = write('pub.pem', utf8.encode(pub));
      final sigPath = write('sig.bin', sig);
      var (code, out) = tools.run(tools.openssl!, ['dgst', '-sha256', '-verify', pubPath, '-signature', sigPath, write('data.bin', data)]);
      expect(code, 0, reason: out);
      expect(out, contains('Verified OK'));
      (code, out) = tools.run(tools.openssl!, [
        'dgst',
        '-sha256',
        '-verify',
        pubPath,
        '-signature',
        sigPath,
        write('data2.bin', [...data, 0]),
      ]);
      expect(out, contains('Verification failure'));
      (code, out) = tools.run(tools.openssl!, ['pkey', '-in', '${tmp.path}/k.pem', '-noout', '-check']);
      expect(code, 0, reason: out);
      expect(out, contains('Key is valid'));
    }, skip: noOpenssl);

    test('CERT.RSA：openssl cms -verify 用 CERT.SF 当内容验得过', () {
      final files = signer.v1Files(fixtureEntries);
      final (code, out) = tools.run(tools.openssl!, [
        'cms', '-verify', '-binary', '-noverify', '-inform', 'DER', //
        '-in', write('CERT.RSA', files[kV1SignatureBlockName]!),
        '-content', write('CERT.SF', files[kV1SignatureFileName]!),
        '-out', '${tmp.path}/cms.out',
      ]);
      expect(code, 0, reason: out);
      expect(out, contains('Verification successful'));
      final (c2, o2) = tools.run(tools.openssl!, [
        'cms',
        '-verify',
        '-binary',
        '-noverify',
        '-inform',
        'DER',
        '-in',
        '${tmp.path}/CERT.RSA',
        '-content',
        write('CERT2.SF', [...files[kV1SignatureFileName]!, 0x20]),
        '-out',
        '${tmp.path}/cms2.out',
      ]);
      expect(c2 == 0, isFalse, reason: o2);
    }, skip: noOpenssl);

    test('导出的备份（真实的 60 万次迭代）：openssl pkcs8 用口令解得开，解出来就是那把私钥；口令错解不开', () {
      final sw = Stopwatch()..start();
      final text = exportSigningKey(key, pass);
      expect(sw.elapsed.inSeconds < 120, isTrue);
      final path = write('backup.txt', utf8.encode(text));
      var (code, out) = tools.run(tools.openssl!, ['pkcs8', '-in', path, '-passin', 'pass:$pass', '-nocrypt', '-topk8', '-outform', 'DER', '-out', '${tmp.path}/plain.der']);
      expect(code, 0, reason: out);
      expect(File('${tmp.path}/plain.der').readAsBytesSync(), pkcs8Der(key.privateKey));
      (code, out) = tools.run(tools.openssl!, ['pkcs8', '-in', path, '-passin', 'pass:wrong-pass-123', '-nocrypt', '-topk8']);
      expect(code == 0, isFalse);
      // 备份里的证书 openssl 也读得出来。
      (code, out) = tools.run(tools.openssl!, ['x509', '-in', path, '-noout', '-fingerprint', '-sha256']);
      expect(code, 0, reason: out);
      expect(out.replaceAll(':', '').toLowerCase(), contains(key.certSha256Hex));
      // 提交在夹具里的那份备份也一样。
      (code, out) = tools.run(tools.openssl!, [
        'pkcs8',
        '-in',
        '$kSignFixtureDir/test-only-backup.txt',
        '-passin',
        'pass:$pass',
        '-nocrypt',
        '-topk8',
        '-outform',
        'DER',
        '-out',
        '${tmp.path}/plain2.der',
      ]);
      expect(code, 0, reason: out);
      expect(File('${tmp.path}/plain2.der').readAsBytesSync(), pkcs8Der(key.privateKey));
    }, skip: noOpenssl);

    test('反过来：openssl 造的钥匙 + 自签证书 + 加密 PKCS#8，这边能导入，签出来的包 apksigner 认', () {
      final k = '${tmp.path}/o-key.pem';
      final c = '${tmp.path}/o-cert.pem';
      final e = '${tmp.path}/o-enc.pem';
      var (code, out) = tools.run(tools.openssl!, ['req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-keyout', k, '-out', c, '-days', '10000', '-subj', '/CN=openssl made/O=Test Only']);
      expect(code, 0, reason: out);
      (code, out) = tools.run(tools.openssl!, ['pkcs8', '-topk8', '-v2', 'aes-256-cbc', '-v2prf', 'hmacWithSHA256', '-iter', '5000', '-in', k, '-out', e, '-passout', 'pass:openssl-side-pass']);
      expect(code, 0, reason: out);
      final text = File(e).readAsStringSync() + File(c).readAsStringSync();
      final imported = asRsaSigningKey(importSigningKey(text, 'openssl-side-pass'));
      expect(imported.commonName, 'openssl made');
      expect(packError(() => importSigningKey(text, 'not-the-pass')), contains('口令不对'));
      // AES-128 的加密 PKCS#8：明确说不支持。
      (code, out) = tools.run(tools.openssl!, ['pkcs8', '-topk8', '-v2', 'aes-128-cbc', '-in', k, '-out', '${tmp.path}/o-128.pem', '-passout', 'pass:openssl-side-pass']);
      expect(code, 0, reason: out);
      expect(packError(() => importSigningKey(File('${tmp.path}/o-128.pem').readAsStringSync() + File(c).readAsStringSync(), 'openssl-side-pass')), contains('不支持'));

      if (tools.apksigner != null) {
        final s = KeyApkSigner(imported);
        final apk = s.v2(storedZip({...fixtureEntries, ...s.v1Files(fixtureEntries)}));
        for (final (min, max) in [(24, null), (21, null), (21, 23)]) {
          final (vc, vo) = verify(write('openssl-key-$min-$max.apk', apk), min: min, max: max);
          expect(vc, 0, reason: vo);
          expect(vo, contains('Signer #1 certificate SHA-256 digest: ${imported.certSha256Hex}'));
        }
      }
    }, skip: noOpenssl);
  });
}
