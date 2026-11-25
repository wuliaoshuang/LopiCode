// ZIP 读写与对齐的纯 Dart 测试（不依赖安卓 SDK）。
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/apkpack/zip/zip_model.dart';
import 'package:lopicode/apkpack/zip/zip_reader.dart';
import 'package:lopicode/apkpack/zip/zip_writer.dart';

import 'support/apkpack_kit.dart';

Uint8List _bytes(String s) => Uint8List.fromList(s.codeUnits);

/// 每个条目的数据起点（从本地文件头算出来）。
Map<String, int> _dataOffsets(Uint8List zip) {
  final d = ByteData.sublistView(zip);
  final out = <String, int>{};
  var p = 0;
  while (d.getUint32(p, Endian.little) == 0x04034b50) {
    final n = d.getUint16(p + 26, Endian.little);
    final x = d.getUint16(p + 28, Endian.little);
    final name = String.fromCharCodes(zip.sublist(p + 30, p + 30 + n));
    out[name] = p + 30 + n + x;
    p = p + 30 + n + x + d.getUint32(p + 18, Endian.little);
  }
  return out;
}

void main() {
  test('CRC-32 的标准检验值', () => expect(crc32Of('123456789'.codeUnits), 0xCBF43926));

  test('写出再读回：内容、压缩方式一致；别的 ZIP 库也能读', () {
    final text = _bytes('hello ' * 500);
    final entries = [
      ZipEntry.deflated('a.txt', text),
      ZipEntry.stored('dir/b.bin', Uint8List.fromList([1, 2, 3])),
      ZipEntry.deflated('tiny', _bytes('x')),
      ZipEntry.stored('中文 名.txt', _bytes('ok')),
    ];
    expect(entries[0].method, kZipDeflated);
    expect(entries[2].method, kZipStored, reason: '压完不变小的改成不压缩');
    final zip = writeZip(entries);
    final back = readZip(zip);
    expect([for (final e in back) e.name], ['a.txt', 'dir/b.bin', 'tiny', '中文 名.txt']);
    expect(back[0].content(), text);
    expect(back[1].content(), [1, 2, 3]);
    final other = ZipDecoder().decodeBytes(zip);
    expect(other.files.map((f) => f.name), ['a.txt', 'dir/b.bin', 'tiny', '中文 名.txt']);
    expect(other.files[0].content, text);
    expect(other.files[3].content, _bytes('ok'));
  });

  test('不压缩的条目数据起点按 4 字节对齐（各种名字长度都试）；.so 按 16KB 对齐', () {
    for (var n = 1; n <= 12; n++) {
      final entries = [
        ZipEntry.deflated('pad${'x' * n}', _bytes('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa')),
        ZipEntry.stored('s${'y' * n}.png', _bytes('12345')),
        ZipEntry.stored('resources.arsc', _bytes('1234567')),
        ZipEntry.stored('lib/arm64-v8a/libx.so', _bytes('elf')),
      ];
      final zip = writeZip(entries);
      final offs = _dataOffsets(zip);
      expect(offs['s${'y' * n}.png']! % 4, 0, reason: '名字长度 $n');
      expect(offs['resources.arsc']! % 4, 0);
      expect(offs['lib/arm64-v8a/libx.so']! % 16384, 0);
      expect(readZip(zip).map((e) => e.name).toList(), entries.map((e) => e.name).toList());
      expect(ZipDecoder().decodeBytes(zip).files.length, 4);
    }
  });

  test('同样输入产出同样字节', () {
    List<ZipEntry> make() => [ZipEntry.deflated('a.html', _bytes('<p>${'x' * 3000}</p>')), ZipEntry.stored('b.png', solidPng(48))];
    expect(writeZip(make()), writeZip(make()));
  });

  test('替身模板读得出来：清单压缩、资源表和图标不压缩', () {
    final entries = {for (final e in readZip(fakeShell())) e.name: e};
    expect(entries.keys, containsAll(['AndroidManifest.xml', 'resources.arsc', 'classes.dex', 'assets/lopi_shell.json']));
    expect(entries['resources.arsc']!.method, kZipStored);
    expect(entries['AndroidManifest.xml']!.method, kZipDeflated);
    expect(entries['AndroidManifest.xml']!.content().length, 2244);
  });

  group('坏输入要报明确的错', () {
    final good = writeZip([ZipEntry.deflated('a.txt', _bytes('hello ' * 100)), ZipEntry.stored('b', _bytes('data'))]);
    void bad(Uint8List b, String part) => expect(() => readZip(b), throwsA(isA<ZipFormatException>().having((e) => e.message, 'message', contains(part))));

    test('不是 ZIP / 空文件', () {
      bad(Uint8List(0), '太短');
      bad(_bytes('this is definitely not a zip file at all'), '找不到 ZIP 的结尾记录');
    });

    test('截断', () {
      for (final n in [10, 40, good.length ~/ 2, good.length - 1]) {
        expect(() => readZip(Uint8List.sublistView(good, 0, n)), throwsA(isA<ZipFormatException>()), reason: '截到 $n');
      }
    });

    test('内容被改坏：校验值对不上', () {
      final b = Uint8List.fromList(good);
      final off = _dataOffsets(good)['b']!;
      b[off] ^= 0xFF;
      final e = readZip(b).firstWhere((e) => e.name == 'b');
      expect(e.content, throwsA(isA<ZipFormatException>().having((e) => e.message, 'message', contains('校验值'))));
    });

    test('写的时候：重名、条目太多都拒绝', () {
      expect(() => writeZip([ZipEntry.stored('a', _bytes('1')), ZipEntry.stored('a', _bytes('2'))]), throwsA(isA<ZipFormatException>()));
      final many = [for (var i = 0; i < 65535; i++) ZipEntry.stored('f$i', Uint8List(0))];
      expect(() => writeZip(many), throwsA(isA<ZipFormatException>().having((e) => e.message, 'message', contains('文件太多'))));
    });
  });
}
