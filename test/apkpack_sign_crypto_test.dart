// 本地打包签名：不依赖任何外部工具的密码学测试（已知答案向量 + 和 crypto 包对拍）。
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/apkpack/sign/aes.dart';
import 'package:lopicode/apkpack/sign/der.dart';
import 'package:lopicode/apkpack/sign/pbkdf2.dart';
import 'package:lopicode/apkpack/sign/rsa.dart';

import 'support/apkpack_sign_support.dart';

void main() {
  group('AES（NIST 已知答案）', () {
    final plain = hex('00112233445566778899aabbccddeeff');
    // FIPS 197 附录 C.1 / C.2 / C.3。
    final cases = {
      '000102030405060708090a0b0c0d0e0f': '69c4e0d86a7b0430d8cdb78070b4c55a',
      '000102030405060708090a0b0c0d0e0f1011121314151617': 'dda97ca4864cdfe06eaf70a0ec0d7191',
      '000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f': '8ea2b7ca516745bfeafc49904b496089',
    };
    cases.forEach((key, cipher) {
      test('FIPS 197 单块，${key.length * 4} 位钥匙：加密、解密', () {
        final aes = Aes(hex(key));
        final block = Uint8List.fromList(plain);
        aes.encryptBlock(block);
        expect(toHex(block), cipher);
        aes.decryptBlock(block);
        expect(toHex(block), toHex(plain));
      });
    });

    final cbcPlain = hex(
      '6bc1bee22e409f96e93d7e117393172a ae2d8a571e03ac9c9eb76fac45af8e51'
      '30c81c46a35ce411e5fbc1191a0a52ef f69f2445df4f9b17ad2b417be66c3710',
    );
    final iv = hex('000102030405060708090a0b0c0d0e0f');

    test('SP 800-38A F.2.5 / F.2.6：CBC-AES256 四个块', () {
      final key = hex('603deb1015ca71be2b73aef0857d7781 1f352c073b6108d72d9810a30914dff4');
      final cipher = hex(
        'f58c4c04d6e5f1ba779eabfb5f7bfbd6 9cfc4e967edb808d679f777bc6702c7d'
        '39f23369a9d9bacfa530e26304231461 b2eb05e2c39be9fcda6c19078c6a9d1b',
      );
      expect(toHex(aesCbcEncryptRaw(key, iv, cbcPlain)), toHex(cipher));
      expect(toHex(aesCbcDecryptRaw(key, iv, cipher)), toHex(cbcPlain));
    });

    test('SP 800-38A F.2.1 / F.2.2：CBC-AES128 四个块', () {
      final key = hex('2b7e151628aed2a6abf7158809cf4f3c');
      final cipher = hex(
        '7649abac8119b246cee98e9b12e9197d 5086cb9b507219ee95db113a917678b2'
        '73bed6b8e3c1743b7116e69e22229516 3ff1caa1681fac09120eca307586e1a7',
      );
      expect(toHex(aesCbcEncryptRaw(key, iv, cbcPlain)), toHex(cipher));
      expect(toHex(aesCbcDecryptRaw(key, iv, cipher)), toHex(cbcPlain));
    });

    test('PKCS#7 补位：各种长度来回一致；补位不对返回 null；钥匙长度不对报错', () {
      final key = Uint8List.fromList(List.generate(32, (i) => i * 7 & 0xff));
      for (final n in [0, 1, 15, 16, 17, 31, 32, 1217]) {
        final data = Uint8List.fromList(List.generate(n, (i) => i * 31 & 0xff));
        final c = aesCbcEncrypt(key, iv, data);
        expect(c.length, (n ~/ 16 + 1) * 16);
        expect(aesCbcDecrypt(key, iv, c), data);
      }
      expect(aesCbcDecrypt(key, iv, aesCbcEncryptRaw(key, iv, Uint8List(16))), isNull);
      expect(aesCbcDecrypt(key, iv, Uint8List(15)), isNull);
      expect(aesCbcDecrypt(key, iv, Uint8List(0)), isNull);
      expect(() => Aes(Uint8List(20)), throwsArgumentError);
    });
  });

  group('SHA-256 压缩函数与 PBKDF2', () {
    test('自己写的压缩函数和 crypto 包的 SHA-256 结果一致（单块消息）', () {
      final rnd = Random(7);
      for (var n = 0; n <= 55; n += 5) {
        final msg = List.generate(n, (_) => rnd.nextInt(256));
        final block = Uint8List(64)
          ..setRange(0, n, msg)
          ..[n] = 0x80;
        ByteData.sublistView(block).setUint32(60, n * 8);
        final w = Uint32List(64);
        for (var i = 0; i < 16; i++) {
          w[i] = ByteData.sublistView(block).getUint32(i * 4);
        }
        final out = Uint32List(8);
        sha256Compress(Uint32List.fromList([0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]), w, out);
        final got = Uint8List(32);
        for (var i = 0; i < 8; i++) {
          ByteData.sublistView(got).setUint32(i * 4, out[i]);
        }
        expect(toHex(got), crypto.sha256.convert(msg).toString(), reason: '长度 $n');
      }
    });

    // RFC 7914 §11 “Test Vectors for PBKDF2 with HMAC-SHA-256”。
    test('RFC 7914 §11 向量一：passwd / salt / 1 次 / 64 字节', () {
      expect(
        toHex(pbkdf2HmacSha256(ascii.encode('passwd'), ascii.encode('salt'), 1, 64)),
        '55ac046e56e3089fec1691c22544b605f94185216dde0465e68b9d57c20dacbc'
        '49ca9cccf179b645991664b39d77ef317c71b845b1e30bd509112041d3a19783',
      );
    });

    test('RFC 7914 §11 向量二：Password / NaCl / 80000 次 / 64 字节', () {
      expect(
        toHex(pbkdf2HmacSha256(ascii.encode('Password'), ascii.encode('NaCl'), 80000, 64)),
        '4ddcd8f60b98be21830cee5ef22701f9641a4418d04c0414aeff08876b34ab56'
        'a1d425a1225833549adb841b51c9b3176a272bdebba1d078478f62b397f33c8d',
      );
    });

    test('和照定义直接写的版本对拍：长口令（超过 64 字节）、长盐、不是 32 整数倍的长度', () {
      Uint8List reference(List<int> password, List<int> salt, int iterations, int length) {
        final hmac = crypto.Hmac(crypto.sha256, password);
        final out = <int>[];
        for (var block = 1; out.length < length; block++) {
          var u = hmac.convert([...salt, 0, 0, 0, block]).bytes;
          final t = List<int>.of(u);
          for (var i = 1; i < iterations; i++) {
            u = hmac.convert(u).bytes;
            for (var j = 0; j < 32; j++) {
              t[j] ^= u[j];
            }
          }
          out.addAll(t);
        }
        return Uint8List.fromList(out.sublist(0, length));
      }

      final long = List.generate(100, (i) => i);
      for (final (p, s, c, n) in [
        (long, long, 3, 32),
        (utf8.encode('中文口令'), [1, 2, 3], 37, 45),
        (<int>[], <int>[], 2, 1),
        (List.filled(64, 9), [0], 1, 100),
      ]) {
        expect(toHex(pbkdf2HmacSha256(p, s, c, n)), toHex(reference(p, s, c, n)));
      }
      expect(() => pbkdf2HmacSha256([1], [1], 0, 32), throwsArgumentError);
    });
  });

  group('DER', () {
    test('时间：2049 年及以前用 UTCTime，2050 年起用 GeneralizedTime，都能读回来', () {
      final before = derTime(DateTime.utc(2049, 12, 31, 23, 59, 59));
      expect(before[0], derTagUtcTime);
      expect(ascii.decode(before.sublist(2)), '491231235959Z');
      final after = derTime(DateTime.utc(2050, 1, 1));
      expect(after[0], derTagGeneralizedTime);
      expect(ascii.decode(after.sublist(2)), '20500101000000Z');
      expect(derParse(before).asTime, DateTime.utc(2049, 12, 31, 23, 59, 59));
      expect(derParse(after).asTime, DateTime.utc(2050, 1, 1));
      expect(derParse(derTime(DateTime.utc(2026, 11, 26, 2, 3, 4))).asTime, DateTime.utc(2026, 11, 26, 2, 3, 4));
      // 本地时间也先换成 UTC 再写。
      expect(derParse(derTime(DateTime.utc(2030, 5, 6, 7, 8, 9).toLocal())).asTime, DateTime.utc(2030, 5, 6, 7, 8, 9));
    });

    test('整数、OID、长度的写法', () {
      expect(toHex(derInt(BigInt.zero)), '020100');
      expect(toHex(derInt(BigInt.from(127))), '02017f');
      expect(toHex(derInt(BigInt.from(128))), '02020080'); // 最高位是 1 要垫一个 00，不然成了负数
      expect(toHex(derInt(BigInt.from(65537))), '0203010001');
      expect(toHex(derOid('1.2.840.113549.1.1.11')), '06092a864886f70d01010b');
      expect(toHex(derOid('2.16.840.1.101.3.4.2.1')), '0609608648016503040201');
      expect(derParse(derOid('1.2.840.113549.1.1.11')).asOid, '1.2.840.113549.1.1.11');
      expect(toHex(derOctets(Uint8List(127)).sublist(0, 2)), '047f');
      expect(toHex(derOctets(Uint8List(128)).sublist(0, 3)), '048180');
      expect(toHex(derOctets(Uint8List(300)).sublist(0, 4)), '0482012c');
      expect(derParse(derOctets(Uint8List(70000))).content.length, 70000);
    });

    test('读坏内容：只抛 DerException，不崩', () {
      final good = derSeq([
        derSmallInt(5),
        derOctets(const [1, 2, 3]),
      ]);
      for (var cut = 0; cut < good.length; cut++) {
        expect(() => derParse(Uint8List.sublistView(good, 0, cut)).seq(2), throwsA(isA<DerException>()), reason: '截到 $cut');
      }
      expect(() => derParse(Uint8List.fromList([...good, 0])), throwsA(isA<DerException>()));
      expect(() => derParse(hex('0281')), throwsA(isA<DerException>()));
      expect(() => derParse(hex('02850000000001 00')), throwsA(isA<DerException>()));
      expect(() => derParse(hex('0201ff')).asInt, throwsA(isA<DerException>()));
      expect(() => derParse(hex('1f0100')), throwsA(isA<DerException>()));
      expect(pemDecode('没有 PEM', 'CERTIFICATE'), isNull);
      expect(() => pemDecode('-----BEGIN X-----\n!!!\n-----END X-----', 'X'), throwsA(isA<DerException>()));
      expect(() => pemDecode('-----BEGIN X-----\nAAAA', 'X'), throwsA(isA<DerException>()));
      expect(pemDecode(pemEncode('X', List.generate(200, (i) => i)).replaceAll('\n', '\r\n'), 'X'), List.generate(200, (i) => i));
    });
  });

  group('RSA', () {
    test('Miller–Rabin：认得素数，也认得合数（含卡迈克尔数）', () {
      final rnd = Random(1);
      for (final p in [2, 3, 5, 2003, 2039, 7919, 104729, 2147483647]) {
        expect(isProbablePrime(BigInt.from(p), 16, rnd), isTrue, reason: '$p');
      }
      for (final c in [0, 1, 4, 561, 1105, 2047, 2041, 6601, 8911, 2147483649, 3215031751]) {
        expect(isProbablePrime(BigInt.from(c), 16, rnd), isFalse, reason: '$c');
      }
      expect(isProbablePrime((BigInt.one << 127) - BigInt.one, 16, rnd), isTrue); // 梅森素数 2^127-1
      expect(isProbablePrime((BigInt.one << 521) - BigInt.one, 16, rnd), isTrue);
      expect(isProbablePrime((BigInt.one << 129) - BigInt.one, 16, rnd), isFalse);
      // 两个大素数的积：没有小因子，只能靠 Miller–Rabin 认出来。
      expect(isProbablePrime(((BigInt.one << 127) - BigInt.one) * ((BigInt.one << 89) - BigInt.one), 16, rnd), isFalse);
    });

    test('小钥匙（768 位，生成快）满足生成条件，签名能验、改一点就验不过', () {
      final k = rsaGenerate(bits: 768, random: Random(42));
      expect(k.n.bitLength, 768);
      expect(k.p * k.q, k.n);
      expect(k.p > k.q, isTrue);
      expect(k.p.bitLength, 384);
      expect(k.q.bitLength, 384);
      expect(k.e, BigInt.from(65537));
      final lcm = ((k.p - BigInt.one) * (k.q - BigInt.one)) ~/ (k.p - BigInt.one).gcd(k.q - BigInt.one);
      expect((k.e * k.d) % lcm, BigInt.one);
      expect(k.dp, k.d % (k.p - BigInt.one));
      expect(k.dq, k.d % (k.q - BigInt.one));
      expect((k.qInv * k.q) % k.p, BigInt.one);
      expect(k.toString(), 'RsaPrivateKey(768 位)');

      final msg = utf8.encode('要签的内容');
      final sig = rsaSignSha256(k, msg);
      expect(sig.length, 96);
      expect(rsaVerifySha256(k.n, k.e, msg, sig), isTrue);
      // 签名是确定的（PKCS#1 v1.5），盲化不影响结果。
      expect(rsaSignSha256(k, msg), sig);
      expect(rsaVerifySha256(k.n, k.e, utf8.encode('要签的内容。'), sig), isFalse);
      final bad = Uint8List.fromList(sig)..[40] ^= 1;
      expect(rsaVerifySha256(k.n, k.e, msg, bad), isFalse);
      expect(rsaVerifySha256(k.n, k.e, msg, sig.sublist(1)), isFalse);
      expect(rsaVerifySha256(k.n, k.e, msg, bigIntToBytes(k.n, 96)), isFalse);
    });

    test('私钥内部被改坏：签名时发现并拒绝，不吐出错的签名', () {
      final k = rsaGenerate(bits: 768, random: Random(43));
      final broken = RsaPrivateKey(n: k.n, e: k.e, d: k.d, p: k.p, q: k.q, dp: k.dp + BigInt.two, dq: k.dq, qInv: k.qInv);
      expect(() => rsaSignSha256(broken, [1, 2, 3]), throwsStateError);
    });

    test('EMSA-PKCS1-v1_5 编码：00 01 FF…FF 00 + SHA-256 的 DigestInfo + 摘要', () {
      final em = emsaPkcs1v15Sha256(ascii.encode('abc'), 256);
      expect(em.length, 256);
      expect(em.sublist(0, 2), [0, 1]);
      expect(em.sublist(2, 256 - 52).every((b) => b == 0xff), isTrue);
      expect(em[256 - 52], 0);
      expect(toHex(em.sublist(256 - 51)), '3031300d060960864801650304020105000420ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
      expect(() => emsaPkcs1v15Sha256([1], 61), throwsArgumentError);
    });
  });
}
