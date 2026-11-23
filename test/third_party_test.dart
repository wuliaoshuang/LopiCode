// 随包的第三方二进制和许可证：文件真的在、和声明里写的校验值逐字节一致、许可证是全文。
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/core/third_party.dart';
import 'package:lopicode/runtime/proot_command.dart';

String sha(File f) => sha256.convert(f.readAsBytesSync()).toString();

void main() {
  const jniDir = 'android/app/src/main/jniLibs/arm64-v8a';

  test('安装包里要带的四个文件都在，大小和 sha256 与声明一致', () {
    final declared = {for (final c in bundledComponents) for (final b in c.binaries) b.fileName: b};
    expect(declared.keys.toSet(), ProotFiles.bundled.toSet(), reason: '声明里的文件要和启动代码找的文件一一对应');
    for (final binary in declared.values) {
      final file = File('$jniDir/${binary.fileName}');
      expect(file.existsSync(), isTrue, reason: '${binary.fileName} 不在 jniLibs 里');
      expect(file.lengthSync(), binary.size, reason: binary.fileName);
      expect(sha(file), binary.sha256, reason: binary.fileName);
    }
    // 目录里不能有声明之外的文件
    final present = Directory(jniDir).listSync().whereType<File>().map((f) => f.uri.pathSegments.last).toSet();
    expect(present, declared.keys.toSet());
  });

  test('四个文件都是 64 位 ARM 的 ELF 文件', () {
    for (final name in ProotFiles.bundled) {
      final bytes = File('$jniDir/$name').readAsBytesSync();
      expect(bytes.sublist(0, 4), [0x7f, 0x45, 0x4c, 0x46], reason: '$name 不是 ELF');
      expect(bytes[4], 2, reason: '$name 不是 64 位');
      expect(bytes[18] | (bytes[19] << 8), 183, reason: '$name 不是 AArch64');
    }
  });

  test('留档的 Termux 原始包与声明、SHA256SUMS 一致', () {
    final sums = {
      for (final line in File('third_party/termux/SHA256SUMS').readAsLinesSync().where((l) => l.trim().isNotEmpty))
        line.split(RegExp(r'\s+'))[1]: line.split(RegExp(r'\s+'))[0],
    };
    for (final component in bundledComponents) {
      final name = Uri.parse(component.packageUrl).pathSegments.last;
      final file = File('third_party/termux/debs/$name');
      expect(file.existsSync(), isTrue, reason: name);
      expect(sha(file), component.packageSha256, reason: name);
      expect(sums['debs/$name'], component.packageSha256, reason: 'SHA256SUMS 里的 $name');
      for (final binary in component.binaries) {
        expect(sums['jniLibs/${binary.fileName}'], binary.sha256, reason: 'SHA256SUMS 里的 ${binary.fileName}');
      }
    }
  });

  test('许可证全文都在，而且确实是全文', () {
    String read(String asset) => File(asset).readAsStringSync();
    final gpl2 = read('assets/licenses/GPL-2.0.txt');
    expect(gpl2, contains('GNU GENERAL PUBLIC LICENSE'));
    expect(gpl2, contains('Version 2, June 1991'));
    expect(gpl2, contains('END OF TERMS AND CONDITIONS'));
    final gpl3 = read('assets/licenses/GPL-3.0.txt');
    expect(gpl3, contains('Version 3, 29 June 2007'));
    expect(gpl3, contains('END OF TERMS AND CONDITIONS'));
    final lgpl3 = read('assets/licenses/LGPL-3.0.txt');
    expect(lgpl3, contains('GNU LESSER GENERAL PUBLIC LICENSE'));
    expect(lgpl3, contains('Version 3, 29 June 2007'));
    expect(read('assets/licenses/libandroid-shmem.txt'), contains('Redistributions in binary form must reproduce'));
    for (final component in bundledComponents) {
      expect(component.licenseAssets, isNotEmpty);
      for (final asset in component.licenseAssets) {
        expect(File(asset).existsSync(), isTrue, reason: asset);
      }
    }
    // 仓库里也留一份
    for (final name in ['GPL-2.0.txt', 'GPL-3.0.txt', 'LGPL-3.0.txt', 'libandroid-shmem.txt']) {
      expect(File('third_party/termux/licenses/$name').readAsStringSync(), read('assets/licenses/$name'), reason: name);
    }
  });

  test('pubspec 把许可证目录打进了安装包', () {
    expect(File('pubspec.yaml').readAsStringSync(), contains('- assets/licenses/'));
  });
}
