// 本地打包签名：v1 / v2 签名产物的结构与自洽（不依赖外部工具；官方工具的验证在 apkpack_sign_tools_test.dart）。
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/apkpack/apk_pack_contract.dart';
import 'package:lopicode/apkpack/sign/apk_signer.dart';
import 'package:lopicode/apkpack/sign/der.dart';
import 'package:lopicode/apkpack/sign/rsa.dart';
import 'package:lopicode/apkpack/sign/v1_sign.dart';
import 'package:lopicode/apkpack/sign/v2_sign.dart';

import 'support/apkpack_sign_support.dart';

/// 把清单文本按 JAR 规范读回来：拼回折行，分成节。返回每节的 `名 → 值`。
List<Map<String, String>> parseManifest(Uint8List bytes) {
  // 先按字节把续行（CRLF + 空格）拼回去，再按 UTF-8 解码——读的一方就是这么做的。
  final joined = <int>[];
  for (var i = 0; i < bytes.length; i++) {
    if (bytes[i] == 0x0d && i + 2 < bytes.length && bytes[i + 1] == 0x0a && bytes[i + 2] == 0x20) {
      i += 2;
      continue;
    }
    joined.add(bytes[i]);
  }
  final sections = <Map<String, String>>[];
  for (final block in utf8.decode(joined).split('\r\n\r\n')) {
    if (block.trim().isEmpty) continue;
    final map = <String, String>{};
    for (final line in block.split('\r\n')) {
      if (line.isEmpty) continue;
      final at = line.indexOf(': ');
      map[line.substring(0, at)] = line.substring(at + 2);
    }
    sections.add(map);
  }
  return sections;
}

String b64Sha256(List<int> data) => base64.encode(crypto.sha256.convert(data).bytes);

void main() {
  final key = fixtureKey();
  final rnd = Random(11);
  Uint8List randomBytes(int n) => Uint8List.fromList(List.generate(n, (_) => rnd.nextInt(256)));

  final entries = <String, Uint8List>{
    'AndroidManifest.xml': randomBytes(900),
    'classes.dex': randomBytes(3000),
    'assets/www/index.html': Uint8List.fromList(utf8.encode('<h1>你好</h1>')),
    'assets/www/图片/封面 图.png': randomBytes(120),
    'assets/www/${'很长的目录名' * 8}/${'x' * 90}.js': randomBytes(10),
    'assets/empty.txt': Uint8List(0),
    'META-INF/services/some.Service': randomBytes(20),
  };

  group('清单的折行', () {
    test('每行连 CRLF 不超过 72 字节；续行以空格开头；不在一个汉字中间折；拼回去是原文', () {
      for (final value in ['短', 'a' * 64, 'a' * 65, 'a' * 200, '汉' * 60, 'ab${'汉字' * 40}c', '😀' * 30, 'x${'😀' * 30}']) {
        final bytes = manifestLine('Name', value);
        final lines = <List<int>>[];
        var start = 0;
        for (var i = 0; i + 1 < bytes.length; i++) {
          if (bytes[i] == 0x0d && bytes[i + 1] == 0x0a) {
            lines.add(bytes.sublist(start, i));
            start = i + 2;
          }
        }
        expect(start, bytes.length, reason: '以 CRLF 结尾');
        for (var i = 0; i < lines.length; i++) {
          expect(lines[i].length + 2 <= 72, isTrue, reason: '第 $i 行 ${lines[i].length} 字节');
          if (i > 0) expect(lines[i][0], 0x20);
          // 每一行单独都是合法的 UTF-8（没有把字符拦腰折断）。
          expect(() => utf8.decode(i == 0 ? lines[i] : lines[i].sublist(1)), returnsNormally);
        }
        expect(parseManifest(Uint8List.fromList([...bytes, 0x0d, 0x0a])).single, {'Name': value});
      }
      // 正好 70 字节的内容不折，71 字节的折。
      expect(manifestLine('Name', 'a' * 64).length, 72);
      expect(manifestLine('Name', 'a' * 65).length, 70 + 2 + 2 + 2);
    });
  });

  group('v1', () {
    final files = v1SignatureFiles(entries, key);
    final manifest = files[kV1ManifestName]!;
    final sf = files[kV1SignatureFileName]!;
    final rsa = files[kV1SignatureBlockName]!;

    test('产出三个文件；清单里每个条目的摘要都对，名字（含中文、超长）读得回来', () {
      expect(files.keys.toSet(), {'META-INF/MANIFEST.MF', 'META-INF/CERT.SF', 'META-INF/CERT.RSA'});
      final sections = parseManifest(manifest);
      expect(sections.first, {'Manifest-Version': '1.0', 'Created-By': '1.0 (LopiCode)'});
      expect(sections.skip(1).map((s) => s['Name']).toList(), entries.keys.toList()..sort());
      for (final s in sections.skip(1)) {
        expect(s['SHA-256-Digest'], b64Sha256(entries[s['Name']]!));
      }
    });

    test('.SF：整份清单的摘要、每一节的摘要都对；带防剥离标记 X-Android-APK-Signed: 2', () {
      final sections = parseManifest(sf);
      expect(sections.first, {'Signature-Version': '1.0', 'Created-By': '1.0 (LopiCode)', 'SHA-256-Digest-Manifest': b64Sha256(manifest), 'X-Android-APK-Signed': '2'});
      // 清单的每一节（从 "Name:" 到空行为止，含空行）的摘要。
      final text = latin1.decode(manifest);
      final parts = text.split('\r\n\r\n').where((p) => p.isNotEmpty).skip(1).map((p) => latin1.encode('$p\r\n\r\n')).toList();
      expect(parts.length, entries.length);
      final names = entries.keys.toList()..sort();
      for (var i = 0; i < names.length; i++) {
        expect(sections[i + 1]['Name'], names[i]);
        expect(sections[i + 1]['SHA-256-Digest'], b64Sha256(parts[i]));
      }
      final only = parseManifest(v1SignatureFiles(entries, key, alsoV2Signed: false)[kV1SignatureFileName]!);
      expect(only.first.containsKey('X-Android-APK-Signed'), isFalse);
    });

    test('.RSA：PKCS#7 SignedData，里面是这把钥匙的证书，签名是对整个 .SF 签的', () {
      final top = derParse(rsa).seq(2);
      expect(top[0].asOid, '1.2.840.113549.1.7.2');
      expect(top[1].tag, 0xa0);
      final sd = top[1].children.single.seq(5);
      expect(sd[0].asSmallInt, 1);
      expect(sd[1].tag, derTagSet);
      expect(sd[1].children.single.seq(2)[0].asOid, '2.16.840.1.101.3.4.2.1');
      expect(sd[2].seq(1).single.asOid, '1.2.840.113549.1.7.1'); // 不带内容
      expect(sd[3].tag, 0xa0);
      expect(sd[3].content, key.certificateDer);
      final si = sd[4].children.single.seq(5);
      expect(si[0].asSmallInt, 1);
      expect(si[1].seq(2)[0].encoded, key.cert.issuerDer);
      expect(si[1].seq(2)[1].encoded, key.cert.serialDer);
      expect(si[2].seq(2)[0].asOid, '2.16.840.1.101.3.4.2.1');
      expect(si[3].seq(2)[0].asOid, '1.2.840.113549.1.1.1');
      expect(rsaVerifySha256(key.cert.n, key.cert.e, sf, si[4].asOctets), isTrue);
    });

    test('带进来的旧签名文件、目录条目不进清单；结果是确定的', () {
      final withOld = {
        ...entries,
        'META-INF/MANIFEST.MF': randomBytes(10),
        'META-INF/OLD.SF': randomBytes(10),
        'META-INF/OLD.RSA': randomBytes(10),
        'META-INF/x.EC': randomBytes(10),
        'META-INF/a.dsa': randomBytes(10),
        'META-INF/SIG-ABC': randomBytes(10),
        'assets/dir/': Uint8List(0),
      };
      final again = v1SignatureFiles(withOld, key);
      expect(again[kV1ManifestName], manifest);
      expect(again[kV1SignatureFileName], sf);
      expect(again[kV1SignatureBlockName], rsa);
      expect(isV1SignatureEntry('META-INF/services/x.SF'), isFalse);
      expect(isV1SignatureEntry('assets/CERT.RSA'), isFalse);
    });

    test('名字里有换行的条目：明确报错', () {
      expect(packError(() => v1SignatureFiles({'a\nb': Uint8List(1)}, key)), contains('文件名'));
      expect(packError(() => v1SignatureFiles({'a\rb': Uint8List(1)}, key)), contains('文件名'));
      expect(packError(() => v1SignatureFiles({'a\u0000b': Uint8List(1)}, key)), contains('文件名'));
    });
  });

  group('v2', () {
    /// 独立照文档写的整包摘要（不分函数、不走被测代码），用来对拍。
    List<int> referenceDigest(List<Uint8List> sections) {
      final digests = <int>[];
      var count = 0;
      for (final s in sections) {
        for (var off = 0; off < s.length; off += 1048576) {
          final chunk = s.sublist(off, min(off + 1048576, s.length));
          final len = ByteData(4)..setUint32(0, chunk.length, Endian.little);
          digests.addAll(crypto.sha256.convert([0xa5, ...len.buffer.asUint8List(), ...chunk]).bytes);
          count++;
        }
      }
      final n = ByteData(4)..setUint32(0, count, Endian.little);
      return crypto.sha256.convert([0x5a, ...n.buffer.asUint8List(), ...digests]).bytes;
    }

    /// 把签好的 APK 拆开，照 v2 的验证步骤自己验一遍；返回签名块里记的证书。
    Uint8List verifyV2(Uint8List apk) {
      final s = locateApkZipSections(apk);
      expect(s.hasSigningBlock, isTrue);
      expect(s.entriesEnd % 4096, 0, reason: '签名块从 4096 的整数倍开始');
      expect((s.cdOffset - s.entriesEnd) % 4096, 0, reason: '签名块大小是 4096 的整数倍');
      final d = ByteData.sublistView(apk);
      final size = d.getUint64(s.entriesEnd, Endian.little);
      expect(size, s.cdOffset - s.entriesEnd - 8);
      expect(d.getUint64(s.cdOffset - 24, Endian.little), size);
      expect(ascii.decode(apk.sublist(s.cdOffset - 16, s.cdOffset)), 'APK Sig Block 42');
      // 逐项读 ID-值。
      final pairs = <int, Uint8List>{};
      var pos = s.entriesEnd + 8;
      while (pos < s.cdOffset - 24) {
        final len = d.getUint64(pos, Endian.little);
        pairs[d.getUint32(pos + 8, Endian.little)] = apk.sublist(pos + 12, pos + 8 + len);
        pos += 8 + len;
      }
      expect(pos, s.cdOffset - 24);
      expect(pairs.keys.toSet().difference({0x7109871a, 0x42726577}), isEmpty);
      final v2 = pairs[0x7109871a]!;
      final vd = ByteData.sublistView(v2);
      var p = 0;
      Uint8List lp(Uint8List buf, ByteData view) {
        final len = view.getUint32(p, Endian.little);
        final out = buf.sublist(p + 4, p + 4 + len);
        p += 4 + len;
        return out;
      }

      final signers = lp(v2, vd);
      expect(p, v2.length);
      p = 0;
      final signer = lp(signers, ByteData.sublistView(signers));
      expect(p, signers.length, reason: '只有一个签名者');
      p = 0;
      final sv = ByteData.sublistView(signer);
      final signedData = lp(signer, sv);
      final signatures = lp(signer, sv);
      final publicKey = lp(signer, sv);
      expect(p, signer.length);
      expect(publicKey, key.cert.spki);
      // 签名：算法 0x0103，签的是 signed data。
      final sigView = ByteData.sublistView(signatures);
      expect(sigView.getUint32(0, Endian.little), signatures.length - 4);
      expect(sigView.getUint32(4, Endian.little), 0x0103);
      expect(sigView.getUint32(8, Endian.little), 256);
      expect(rsaVerifySha256(key.cert.n, key.cert.e, signedData, signatures.sublist(12)), isTrue);
      // signed data：摘要们、证书们、附加属性（空）。
      p = 0;
      final sdv = ByteData.sublistView(signedData);
      final digests = lp(signedData, sdv);
      final certs = lp(signedData, sdv);
      final attrs = lp(signedData, sdv);
      expect(p, signedData.length);
      expect(attrs, isEmpty);
      final dv = ByteData.sublistView(digests);
      expect(dv.getUint32(0, Endian.little), digests.length - 4);
      expect(dv.getUint32(4, Endian.little), 0x0103);
      expect(dv.getUint32(8, Endian.little), 32);
      final eocd = Uint8List.fromList(apk.sublist(s.eocdOffset));
      ByteData.sublistView(eocd).setUint32(16, s.entriesEnd, Endian.little);
      expect(toHex(digests.sublist(12)), toHex(referenceDigest([apk.sublist(0, s.entriesEnd), apk.sublist(s.cdOffset, s.eocdOffset), eocd])));
      expect(ByteData.sublistView(certs).getUint32(0, Endian.little), certs.length - 4);
      return certs.sublist(4);
    }

    final signer = KeyApkSigner(key);
    Uint8List signedApk([Map<String, Uint8List>? more, List<int> comment = const []]) {
      final all = {...entries, ...?more};
      return signer.v2(storedZip({...all, ...signer.v1Files(all)}, comment: comment));
    }

    test('整包摘要和照文档独立写的版本一致：空段、不满一块、正好 1MB、1MB 多 1 字节、两块多', () {
      const mb = 1048576;
      for (final sizes in [
        [0, 0, 22],
        [1, 1, 22],
        [mb, 100, 22],
        [mb + 1, 100, 22],
        [mb - 1, mb, 22],
        [2 * mb, mb + 5, 30],
        [2 * mb + 4096, 3, 22],
      ]) {
        final sections = [for (final n in sizes) randomBytes(n)];
        expect(toHex(v2ContentDigest(sections)), toHex(referenceDigest(sections)), reason: '$sizes');
      }
      // 空的 APK 内容段：0 个块也要算进“块数”。
      expect(toHex(v2ContentDigest([Uint8List(0)])), toHex(crypto.sha256.convert([0x5a, 0, 0, 0, 0]).bytes));
    });

    test('签完自己照验证步骤验一遍：结构、摘要、签名、证书都对；ZIP 条目原样读得出来', () {
      final apk = signedApk();
      expect(verifyV2(apk), key.certificateDer);
      expect(signer.certSha256Hex, crypto.sha256.convert(key.certificateDer).toString());
      final back = readZipEntries(apk);
      for (final name in entries.keys) {
        expect(back[name], entries[name], reason: name);
      }
      expect(back.keys.where((n) => n.startsWith('META-INF/CERT') || n == 'META-INF/MANIFEST.MF').length, 3);
      expect(signer.toString(), 'KeyApkSigner(证书 SHA-256 ${key.certSha256Hex})');
    });

    test('条目内容段正好是 1MB、2MB 的整数倍（块边界），以及跨好几块', () {
      const mb = 1048576;
      for (final target in [mb, 2 * mb, 3 * mb + 4096]) {
        // 先量出不带填充文件时条目段有多长，再用一个不压缩的填充文件把它凑到正好 target。
        final probe = locateApkZipSections(signedApk({'assets/pad.bin': Uint8List(0)}));
        final unsignedLen = locateApkZipSections(
          storedZip({
            ...entries,
            'assets/pad.bin': Uint8List(0),
            ...signer.v1Files({...entries, 'assets/pad.bin': Uint8List(0)}),
          }),
        ).cdOffset;
        expect(probe.entriesEnd >= unsignedLen, isTrue);
        final apk = signedApk({'assets/pad.bin': randomBytes(target - unsignedLen)});
        final s = locateApkZipSections(apk);
        expect(s.entriesEnd, target, reason: '条目段正好 $target 字节');
        verifyV2(apk);
      }
    });

    test('ZIP 结尾带注释：照常签，注释原样保留', () {
      final comment = utf8.encode('这是一段注释 with PK\u0005\u0006 inside');
      final apk = signedApk(null, comment);
      verifyV2(apk);
      expect(apk.sublist(apk.length - comment.length), comment);
    });

    test('已经签过的包再签一次：旧签名块被换掉，大小不变，照样验得过', () {
      final once = signedApk();
      final twice = signer.v2(once);
      expect(twice, once); // 0x0103 的签名是确定的
      final other = KeyApkSigner(fixtureKey('test-only-key-2.pem')).v2(once);
      expect(other.length, once.length);
      expect(locateApkZipSections(other).entriesEnd, locateApkZipSections(once).entriesEnd);
      // 只有 v2 的包换一把钥匙重签：旧证书不该留在包里（带 v1 的包里 CERT.RSA 还是旧的，那得由打包器重做 v1）。
      final v2Only = signer.v2(storedZip(entries));
      final resigned = KeyApkSigner(fixtureKey('test-only-key-2.pem')).v2(v2Only);
      expect(toHex(v2Only).contains(toHex(key.certificateDer.sublist(0, 64))), isTrue);
      expect(toHex(resigned).contains(toHex(key.certificateDer.sublist(0, 64))), isFalse);
    });

    test('只做 v2（包里没有 v1 文件）也行', () {
      verifyV2(signer.v2(storedZip(entries)));
      verifyV2(signer.v2(storedZip({})));
    });

    test('改动任何一段的一个字节，自己的验证都能发现', () {
      final apk = signedApk();
      final s = locateApkZipSections(apk);
      for (final at in [100, s.entriesEnd - 1, s.cdOffset + 10, s.eocdOffset + 10]) {
        final bad = Uint8List.fromList(apk)..[at] ^= 0x01;
        expect(() => verifyV2(bad), throwsA(anyOf(isA<TestFailure>(), isA<ApkPackException>())), reason: '改了偏移 $at');
      }
    });

    test('不认的输入都明确报错：太小、不是 ZIP、结尾后有多余字节、ZIP64、分卷、目录和结尾不挨着、旧签名块是坏的', () {
      final zip = storedZip(entries);
      final s = locateApkZipSections(zip);
      expect(s.hasSigningBlock, isFalse);
      expect(s.entriesEnd, s.cdOffset);
      expect(packError(() => signer.v2(Uint8List(10))), contains('文件太小'));
      expect(packError(() => signer.v2(randomBytes(5000))), contains('找不到 ZIP 的结尾记录'));
      expect(packError(() => signer.v2(Uint8List.fromList([...zip, 0]))), contains('找不到 ZIP 的结尾记录'));

      // ZIP64：结尾记录前面有 ZIP64 定位记录，或者数量 / 偏移写成全 F。
      final locator = ByteData(20)..setUint32(0, 0x07064b50, Endian.little);
      final zip64 = Uint8List.fromList([...zip.sublist(0, s.eocdOffset), ...locator.buffer.asUint8List(), ...zip.sublist(s.eocdOffset)]);
      expect(packError(() => signer.v2(zip64)), contains('ZIP64'));
      final allF = Uint8List.fromList(zip);
      ByteData.sublistView(allF).setUint32(s.eocdOffset + 16, 0xffffffff, Endian.little);
      expect(packError(() => signer.v2(allF)), contains('ZIP64'));
      final manyEntries = Uint8List.fromList(zip);
      ByteData.sublistView(manyEntries)
        ..setUint16(s.eocdOffset + 8, 0xffff, Endian.little)
        ..setUint16(s.eocdOffset + 10, 0xffff, Endian.little);
      expect(packError(() => signer.v2(manyEntries)), contains('ZIP64'));

      final multiDisk = Uint8List.fromList(zip);
      ByteData.sublistView(multiDisk).setUint16(s.eocdOffset + 4, 1, Endian.little);
      expect(packError(() => signer.v2(multiDisk)), contains('分卷'));

      final gap = Uint8List.fromList(zip);
      ByteData.sublistView(gap).setUint32(s.eocdOffset + 16, s.cdOffset - 3, Endian.little);
      expect(packError(() => signer.v2(gap)), contains('没有挨在一起'));
      final beyond = Uint8List.fromList(zip);
      ByteData.sublistView(beyond).setUint32(s.eocdOffset + 12, s.cdSize + 500, Endian.little);
      expect(packError(() => signer.v2(beyond)), contains('没有挨在一起'));

      // 旧签名块的两个大小对不上 / 大得离谱。
      final signed = signer.v2(zip);
      final ss = locateApkZipSections(signed);
      final badBlock = Uint8List.fromList(signed);
      ByteData.sublistView(badBlock).setUint64(ss.entriesEnd, 12345, Endian.little);
      expect(packError(() => signer.v2(badBlock)), contains('签名块是坏的'));
      final hugeBlock = Uint8List.fromList(signed);
      ByteData.sublistView(hugeBlock).setUint64(ss.cdOffset - 24, 0x7fffffffff, Endian.little);
      expect(packError(() => signer.v2(hugeBlock)), contains('签名块是坏的'));
      final negBlock = Uint8List.fromList(signed);
      ByteData.sublistView(negBlock).setUint64(ss.cdOffset - 24, ss.cdOffset + 4096, Endian.little);
      expect(packError(() => signer.v2(negBlock)), contains('签名块是坏的'));
    });

    test('随便截断、乱改的输入：要么签成功，要么是明确的报错，不会崩', () {
      final zip = storedZip(entries);
      for (var i = 0; i < 300; i++) {
        final cut = rnd.nextInt(zip.length);
        final bad = Uint8List.fromList(i.isEven ? zip.sublist(0, cut) : zip);
        if (i.isOdd) bad[zip.length - 1 - rnd.nextInt(60)] = rnd.nextInt(256);
        try {
          signer.v2(bad);
        } on Exception catch (e) {
          expect(e.toString(), contains('安装包文件结构不对'));
        }
      }
    });
  });
}
