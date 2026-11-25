// 本地打包签名：打包钥匙的生成、存取、导出备份 / 导入（不依赖外部工具）。
//
// 真的 2048 位钥匙只生成两次（同步一次、isolate 一次），其余用提交在夹具里的“仅测试用”钥匙。
// 实测（2026-11-26，开发机 1.5 个共享核、同时有别的任务在跑）：单次生成 0.6–3.8 秒，
// 60 万次迭代的导出 / 导入各约 4–7 秒（空闲时纯计算约 0.9 秒）。
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/apkpack/apk_pack_contract.dart';
import 'package:lopicode/apkpack/sign/der.dart';
import 'package:lopicode/apkpack/sign/key_backup.dart';
import 'package:lopicode/apkpack/sign/rsa.dart';
import 'package:lopicode/apkpack/sign/signing_key.dart';
import 'package:lopicode/apkpack/sign/x509.dart';

import 'support/apkpack_sign_support.dart';

/// 钥匙里所有不许外泄的东西的几种写法；[text] 里一样都不许出现。
void expectNoSecrets(String text, RsaApkSigningKey key, {String? passphrase}) {
  final k = key.privateKey;
  for (final secret in [k.d, k.p, k.q, k.dp, k.dq, k.qInv]) {
    expect(text.contains(secret.toString()), isFalse);
    expect(text.toLowerCase().contains(secret.toRadixString(16)), isFalse);
  }
  final b64 = base64.encode(pkcs8Der(k));
  for (var i = 0; i + 24 <= b64.length; i += 24) {
    expect(text.contains(b64.substring(i, i + 24)), isFalse);
  }
  if (passphrase != null) expect(text.contains(passphrase), isFalse);
}

void main() {
  final key = fixtureKey();
  final key2 = fixtureKey('test-only-key-2.pem');
  const pass = '仅测试用的口令 test-only';
  // 测试里用很少的迭代次数，省时间；真实次数只在“读提交的备份”那一条跑一次。
  String quickExport(ApkSigningKey k, [String p = pass]) => exportSigningKey(k, p, iterations: 1000);

  group('生成', () {
    test('同步生成一把真的 2048 位钥匙：证书内容、有效期 30 年、时间编码、名字支持中文', () {
      final now = DateTime.utc(2026, 11, 26, 2, 30, 45, 678);
      final k = asRsaSigningKey(generateSigningKeySync(commonName: '  霜霜的打包钥匙  ', now: now));
      expect(k.privateKey.bits, 2048);
      expect(k.privateKey.e, BigInt.from(65537));
      expect(k.createdAt, DateTime.utc(2026, 11, 26, 2, 30, 45)); // 截到秒
      expect(k.createdAt.isUtc, isTrue);
      expect(k.expiresAt, DateTime.utc(2056, 11, 26, 2, 30, 45));
      expect(k.commonName, '霜霜的打包钥匙');
      expect(k.certSha256Hex, matches(RegExp(r'^[0-9a-f]{64}$')));

      // 证书结构：v3、序列号是正数、签名算法 sha256WithRSAEncryption、签发者 = 主题、起始用 UTCTime、到期（2056）用 GeneralizedTime。
      final cert = derParse(k.certificateDer).seq(3);
      final tbs = cert[0].seq(8);
      expect(tbs[0].tag, 0xa0);
      expect(tbs[0].children.single.asSmallInt, 2);
      expect(tbs[1].asInt > BigInt.zero, isTrue);
      expect(tbs[1].content.length, inInclusiveRange(1, 16));
      expect(tbs[2].seq(2)[0].asOid, '1.2.840.113549.1.1.11');
      expect(cert[1].seq(2)[0].asOid, '1.2.840.113549.1.1.11');
      expect(tbs[3].encoded, tbs[5].encoded);
      expect(tbs[3].seq(1)[0].children.single.seq(2)[1].tag, derTagUtf8String);
      expect(tbs[4].seq(2)[0].tag, derTagUtcTime);
      expect(tbs[4].seq(2)[1].tag, derTagGeneralizedTime);
      expect(tbs[7].tag, 0xa3);
      // 证书是自己签的：用里面的公钥验得过。
      expect(rsaVerifySha256(k.cert.n, k.cert.e, cert[0].encoded, cert[2].asBits), isTrue);

      // 存进去、读回来是同一把。
      final again = asRsaSigningKey(parseSigningKey(k.serialize()));
      expect(again.certSha256Hex, k.certSha256Hex);
      expect(again.privateKey.d, k.privateKey.d);
      expect(again.createdAt, k.createdAt);
      expect(again.serialize(), k.serialize());
    });

    test('在 isolate 里生成（界面用的那个入口）：两次生成的钥匙和序列号都不一样', () async {
      final k = asRsaSigningKey(await generateSigningKey(commonName: 'LopiCode'));
      expect(k.privateKey.bits, 2048);
      expect(k.commonName, 'LopiCode');
      expect(k.privateKey.n == key.privateKey.n, isFalse);
      expect(k.cert.serialDer, isNot(key.cert.serialDer));
      expect(k.expiresAt.year - k.createdAt.year, 30);
      expect(DateTime.now().toUtc().difference(k.createdAt).inMinutes.abs() <= 5, isTrue);
    });

    test('名字不合适：空的、太长的、带换行的都报大白话', () async {
      expect(packError(() => generateSigningKeySync(commonName: '   ')), contains('不能为空'));
      expect(packError(() => generateSigningKeySync(commonName: '字' * 65)), contains('太长'));
      expect(packError(() => generateSigningKeySync(commonName: '第一行\n第二行')), contains('控制字符'));
      await expectLater(generateSigningKey(commonName: ''), throwsA(isA<ApkPackException>()));
      expect(checkSigningName('字' * 64), '字' * 64);
    });
  });

  group('存取', () {
    test('大小：存储形式约 2.8KB，是两段 PEM', () {
      final s = key.serialize();
      expect(s.length, inInclusiveRange(2600, 3100));
      expect(s, contains('-----BEGIN PRIVATE KEY-----'));
      expect(s, contains('-----BEGIN CERTIFICATE-----'));
    });

    test('toString 只带证书指纹，不带私钥', () {
      expect(key.toString(), 'ApkSigningKey(证书 SHA-256 ${key.certSha256Hex})');
      expectNoSecrets(key.toString(), key);
      expectNoSecrets(key.privateKey.toString(), key);
    });

    test('坏内容：空的、乱码、截断、改了一个字符、证书换成别人的——都是明确的报错，不崩，也不带出钥匙内容', () {
      final good = key.serialize();
      final bad = <String>[
        '',
        '这不是钥匙',
        '{"json": true}',
        good.substring(0, good.indexOf('-----BEGIN CERTIFICATE-----')), // 只有私钥
        good.substring(good.indexOf('-----BEGIN CERTIFICATE-----')), // 只有证书
        for (var cut = 40; cut < good.length - 30; cut += 97) good.substring(0, cut),
        for (var at = 60; at < good.length - 60; at += 211) good.replaceRange(at, at + 1, good[at] == 'A' ? 'B' : 'A'),
        good.replaceFirst('PRIVATE KEY-----\n', 'PRIVATE KEY-----\n!!!'),
        // 别人的证书配这把私钥
        good.substring(0, good.indexOf('-----BEGIN CERTIFICATE-----')) + key2.serialize().substring(key2.serialize().indexOf('-----BEGIN CERTIFICATE-----')),
      ];
      var rejected = 0;
      for (final text in bad) {
        try {
          final parsed = parseSigningKey(text);
          // 改到的是不影响内容的地方（比如 PEM 里的换行、证书里签名之外不查的位）才可能读成功；读成功就必须还是那把钥匙的私钥。
          expect(asRsaSigningKey(parsed).privateKey.d, key.privateKey.d);
        } on ApkPackException catch (e) {
          rejected++;
          expect(e.field, 'key');
          expect(e.message, contains('读不出来'));
          expectNoSecrets(e.message, key);
          expectNoSecrets(e.toString(), key);
        }
      }
      expect(rejected > bad.length ~/ 2, isTrue);
      expect(packError(() => parseSigningKey('')), contains('读不出来'));
    });

    test('私钥改坏但格式完好（CRT 参数不对）：读的时候就发现', () {
      final k = key.privateKey;
      final broken = RsaPrivateKey(n: k.n, e: k.e, d: k.d, p: k.p, q: k.q, dp: k.dp, dq: (k.dq + BigInt.two) % k.q, qInv: k.qInv);
      final text = pemEncode('PRIVATE KEY', pkcs8Der(broken)) + pemEncode('CERTIFICATE', key.certificateDer);
      expect(packError(() => parseSigningKey(text)), contains('读不出来'));
    });

    test('不是这边实现的钥匙：签名代码明确拒绝', () {
      expect(packError(() => asRsaSigningKey(_FakeKey())), contains('不是本应用生成或导入的'));
      expect(packError(() => exportSigningKey(_FakeKey(), pass)), contains('不是本应用生成或导入的'));
    });
  });

  group('导出备份 / 导入', () {
    test('导出再导入是同一把钥匙；每次导出的盐和密文都不一样', () {
      final a = quickExport(key);
      final b = quickExport(key);
      expect(a == b, isFalse);
      expect(a, contains('-----BEGIN ENCRYPTED PRIVATE KEY-----'));
      expect(a, contains('-----BEGIN CERTIFICATE-----'));
      expect(a, contains(key.certSha256Hex));
      expect(a.contains('-----BEGIN PRIVATE KEY-----'), isFalse);
      expectNoSecrets(a, key, passphrase: pass);
      for (final text in [a, b, a.replaceAll('\n', '\r\n')]) {
        final back = asRsaSigningKey(importSigningKey(text, pass));
        expect(back.certSha256Hex, key.certSha256Hex);
        expect(back.serialize(), key.serialize());
      }
    });

    test('备份的结构：PBES2 + PBKDF2（HMAC-SHA256，默认 60 万次）+ AES-256-CBC', () {
      expect(kBackupPbkdf2Iterations, 600000);
      final der = pemDecode(quickExport(key), 'ENCRYPTED PRIVATE KEY')!;
      final top = derParse(der).seq(2);
      final alg = top[0].seq(2);
      expect(alg[0].asOid, '1.2.840.113549.1.5.13');
      final params = alg[1].seq(2);
      expect(params[0].seq(2)[0].asOid, '1.2.840.113549.1.5.12');
      final kdf = params[0].seq(2)[1].seq(3);
      expect(kdf[0].asOctets.length, 16);
      expect(kdf[1].asSmallInt, 1000);
      expect(kdf[2].seq(2)[0].asOid, '1.2.840.113549.2.9');
      expect(params[1].seq(2)[0].asOid, '2.16.840.1.101.3.4.1.42');
      expect(params[1].seq(2)[1].asOctets.length, 16);
      expect(top[1].asOctets.length % 16, 0);
    });

    test('提交在夹具里的备份（真实的 60 万次迭代）能导入；导入耗时在可接受范围', () {
      final text = File('$kSignFixtureDir/test-only-backup.txt').readAsStringSync();
      final sw = Stopwatch()..start();
      final back = importSigningKey(text, pass);
      expect(back.certSha256Hex, key.certSha256Hex);
      expect(sw.elapsed.inSeconds < 120, isTrue);
    });

    test('口令不对：明确说口令不对，不带出口令', () {
      final text = quickExport(key);
      for (final wrong in ['仅测试用的口令 test-onlx', 'x', '$pass ', pass.toUpperCase()]) {
        final msg = packError(() => importSigningKey(text, wrong));
        expect(msg, contains('口令不对'));
        expect(msg.contains(wrong), isFalse);
        expectNoSecrets(msg, key, passphrase: pass);
      }
      expect(packError(() => importSigningKey(text, '')), contains('请输入'));
    });

    test('口令太短（少于 8 个字符）不让导出；正好 8 个可以，中文也按字符数算', () {
      expect(kBackupMinPassphraseLength, 8);
      final msg = packError(() => exportSigningKey(key, '1234567'));
      expect(msg, contains('口令太短'));
      expect(msg.contains('1234567'), isFalse);
      expect(packError(() => exportSigningKey(key, '')), contains('口令太短'));
      expect(importSigningKey(quickExport(key, '12345678'), '12345678').certSha256Hex, key.certSha256Hex);
      expect(importSigningKey(quickExport(key, '八个字的中文口令'), '八个字的中文口令').certSha256Hex, key.certSha256Hex);
    });

    test('文件坏了：不是备份、没加口令的私钥、被截断、密文被改——各有明确的话', () {
      final text = quickExport(key);
      expect(packError(() => importSigningKey('随便一段文字', pass)), contains('不是打包钥匙的备份文件'));
      expect(packError(() => importSigningKey('', pass)), contains('不是打包钥匙的备份文件'));
      expect(packError(() => importSigningKey(text.substring(0, text.indexOf('-----BEGIN CERTIFICATE-----')), pass)), contains('不是打包钥匙的备份文件'));
      expect(packError(() => importSigningKey(key.serialize(), pass)), contains('没有加口令'));
      expect(packError(() => importSigningKey(text.substring(0, text.length - 40), pass)), contains('备份文件坏了'));
      expect(packError(() => importSigningKey(text.replaceFirst('-----END ENCRYPTED PRIVATE KEY-----', ''), pass)), contains('备份文件坏了'));

      // 改 PEM 里的每一段：要么报“坏了”，要么报“口令不对（或被改动过）”，要么报对不上；绝不崩，也绝不悄悄导入成另一把钥匙。
      final rnd = Random(5);
      final start = text.indexOf('-----BEGIN ENCRYPTED PRIVATE KEY-----') + 40;
      final end = text.lastIndexOf('-----END CERTIFICATE-----') - 4;
      for (var i = 0; i < 60; i++) {
        final at = start + rnd.nextInt(end - start);
        final ch = text[at];
        if (!RegExp('[A-Za-z0-9]').hasMatch(ch)) continue;
        final changed = text.replaceRange(at, at + 1, ch == 'Q' ? 'R' : 'Q');
        try {
          final back = asRsaSigningKey(importSigningKey(changed, pass));
          expect(back.privateKey.d, key.privateKey.d); // 改到证书里不查的地方才可能成功，私钥必须还是原来那把
        } on ApkPackException catch (e) {
          expect(e.message, anyOf(contains('备份文件坏了'), contains('口令不对'), contains('对不上'), contains('不支持'), contains('只支持')));
          expectNoSecrets(e.message, key, passphrase: pass);
        }
      }
    });

    test('证书和私钥对不上：明确说不是同一把', () {
      final a = quickExport(key);
      final b = quickExport(key2);
      final mixed = a.substring(0, a.indexOf('-----BEGIN CERTIFICATE-----')) + b.substring(b.indexOf('-----BEGIN CERTIFICATE-----'));
      expect(packError(() => importSigningKey(mixed, pass)), contains('对不上'));
    });

    test('加密方式不认识（比如 AES-128、HMAC-SHA1）：明确说不支持', () {
      final der = pemDecode(quickExport(key), 'ENCRYPTED PRIVATE KEY')!;
      final cert = pemEncode('CERTIFICATE', key.certificateDer);
      // 把 aes256-CBC 的 OID（…1.42）改成 aes128-CBC（…1.2）。
      final aes128 = List<int>.of(der);
      final at = toHex(der).indexOf('60864801650304012a') ~/ 2;
      aes128[at + 8] = 0x02;
      expect(packError(() => importSigningKey(pemEncode('ENCRYPTED PRIVATE KEY', aes128) + cert, pass)), contains('不支持'));
      // 把 hmacWithSHA256（…2.9）改成 hmacWithSHA1（…2.7）。
      final sha1 = List<int>.of(der);
      final at2 = toHex(der).indexOf('2a864886f70d0209') ~/ 2;
      sha1[at2 + 7] = 0x07;
      expect(packError(() => importSigningKey(pemEncode('ENCRYPTED PRIVATE KEY', sha1) + cert, pass)), contains('不支持'));
    });

    test('迭代次数离谱的坏文件：直接当坏文件，不去算', () {
      final salt = List.filled(16, 1);
      final enc = derSeq([
        derSeq([
          derOid('1.2.840.113549.1.5.13'),
          derSeq([
            derSeq([
              derOid('1.2.840.113549.1.5.12'),
              derSeq([
                derOctets(salt),
                derInt(BigInt.from(2000000000)),
                derSeq([derOid('1.2.840.113549.2.9'), derNull()]),
              ]),
            ]),
            derSeq([derOid('2.16.840.1.101.3.4.1.42'), derOctets(salt)]),
          ]),
        ]),
        derOctets(List.filled(32, 0)),
      ]);
      final sw = Stopwatch()..start();
      expect(packError(() => importSigningKey(pemEncode('ENCRYPTED PRIVATE KEY', enc) + pemEncode('CERTIFICATE', key.certificateDer), pass)), contains('备份文件坏了'));
      expect(sw.elapsed.inSeconds < 5, isTrue);
    });

    test('不卡界面的版本（isolate）：导出再导入', () async {
      // 这一条走真实的 60 万次迭代各一次。
      final text = await exportSigningKeyAsync(key, pass);
      final back = await importSigningKeyAsync(text, pass);
      expect(back.certSha256Hex, key.certSha256Hex);
      await expectLater(importSigningKeyAsync(text, '不对的口令 12345'), throwsA(isA<ApkPackException>()));
    });
  });
}

class _FakeKey implements ApkSigningKey {
  @override
  String get certSha256Hex => '00';

  @override
  DateTime get createdAt => DateTime.utc(2026);

  @override
  String serialize() => '';
}
