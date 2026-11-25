// 本地打包签名测试共用的东西：仅测试用的钥匙、一个只会“不压缩”的小 ZIP 写入器、找官方工具。
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:lopicode/apkpack/apk_pack_contract.dart';
import 'package:lopicode/apkpack/sign/signing_key.dart';

const String kSignFixtureDir = 'test/fixtures/apkpack_sign';

/// 提交在夹具里的“仅测试用”钥匙（公开的）。
RsaApkSigningKey fixtureKey([String file = 'test-only-key.pem']) => asRsaSigningKey(parseSigningKey(File('$kSignFixtureDir/$file').readAsStringSync()));

Uint8List hex(String s) {
  final clean = s.replaceAll(RegExp(r'\s'), '');
  return Uint8List.fromList([for (var i = 0; i < clean.length; i += 2) int.parse(clean.substring(i, i + 2), radix: 16)]);
}

String toHex(List<int> bytes) => bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// 能预料的失败应该抛 [ApkPackException]；返回它的文字。
String packError(void Function() body) {
  try {
    body();
  } on ApkPackException catch (e) {
    return e.message;
  }
  throw StateError('应该报错却没有报');
}

/// 写一个所有条目都“不压缩”的 ZIP（APK）。[comment] 是 ZIP 结尾记录里的注释。
Uint8List storedZip(Map<String, Uint8List> entries, {List<int> comment = const []}) {
  final out = BytesBuilder();
  final central = BytesBuilder();
  var count = 0;
  entries.forEach((name, data) {
    final nameBytes = utf8.encode(name);
    final flags = nameBytes.length == name.length ? 0 : 0x0800; // 非 ASCII 名字要标 UTF-8
    final crc = getCrc32(data);
    final offset = out.length;
    final local = ByteData(30)
      ..setUint32(0, 0x04034b50, Endian.little)
      ..setUint16(4, 20, Endian.little)
      ..setUint16(6, flags, Endian.little)
      ..setUint16(12, 0x21, Endian.little) // 1980-01-01
      ..setUint32(14, crc, Endian.little)
      ..setUint32(18, data.length, Endian.little)
      ..setUint32(22, data.length, Endian.little)
      ..setUint16(26, nameBytes.length, Endian.little);
    out
      ..add(local.buffer.asUint8List())
      ..add(nameBytes)
      ..add(data);
    final cd = ByteData(46)
      ..setUint32(0, 0x02014b50, Endian.little)
      ..setUint16(4, 20, Endian.little)
      ..setUint16(6, 20, Endian.little)
      ..setUint16(8, flags, Endian.little)
      ..setUint16(14, 0x21, Endian.little)
      ..setUint32(16, crc, Endian.little)
      ..setUint32(20, data.length, Endian.little)
      ..setUint32(24, data.length, Endian.little)
      ..setUint16(28, nameBytes.length, Endian.little)
      ..setUint32(42, offset, Endian.little);
    central
      ..add(cd.buffer.asUint8List())
      ..add(nameBytes);
    count++;
  });
  final cdBytes = central.toBytes();
  final eocd = ByteData(22)
    ..setUint32(0, 0x06054b50, Endian.little)
    ..setUint16(8, count, Endian.little)
    ..setUint16(10, count, Endian.little)
    ..setUint32(12, cdBytes.length, Endian.little)
    ..setUint32(16, out.length, Endian.little)
    ..setUint16(20, comment.length, Endian.little);
  out
    ..add(cdBytes)
    ..add(eocd.buffer.asUint8List())
    ..add(comment);
  return out.toBytes();
}

/// 读出 ZIP 里的全部文件条目（解压后的内容）。
Map<String, Uint8List> readZipEntries(Uint8List zip) {
  final out = <String, Uint8List>{};
  for (final f in ZipDecoder().decodeBytes(zip)) {
    if (f.isFile) out[f.name] = Uint8List.fromList(f.content as List<int>);
  }
  return out;
}

/// 开发机上的官方工具。找不到的那一项是 null，用到它的测试要明确 skip。
class SignTools {
  SignTools._(this.apksigner, this.zipalign, this.openssl, this.jarsigner, this.keytool, this.env);

  final String? apksigner;
  final String? zipalign;
  final String? openssl;
  final String? jarsigner;
  final String? keytool;
  final Map<String, String> env;

  static SignTools find() {
    final home = Platform.environment['HOME'] ?? '';
    final sdk = Platform.environment['ANDROID_HOME'] ?? '$home/workspace/tools/android-sdk';
    final jdk = Platform.environment['JAVA_HOME'] ?? '$home/workspace/tools/jdk';
    String? existing(String path) => File(path).existsSync() ? path : null;
    String? onPath(String name) {
      for (final dir in (Platform.environment['PATH'] ?? '').split(':')) {
        if (dir.isNotEmpty && File('$dir/$name').existsSync()) return '$dir/$name';
      }
      return null;
    }

    String? buildTool(String name) {
      final root = Directory('$sdk/build-tools');
      if (!root.existsSync()) return null;
      final versions = root.listSync().whereType<Directory>().map((d) => d.path).toList()..sort();
      for (final v in versions.reversed) {
        if (File('$v/$name').existsSync()) return '$v/$name';
      }
      return null;
    }

    final java = existing('$jdk/bin/java') ?? onPath('java');
    return SignTools._(
      java == null ? null : buildTool('apksigner'),
      buildTool('zipalign'),
      onPath('openssl'),
      existing('$jdk/bin/jarsigner') ?? onPath('jarsigner'),
      existing('$jdk/bin/keytool') ?? onPath('keytool'),
      {...Platform.environment, if (java != null) 'JAVA_HOME': File(java).parent.parent.path, if (java != null) 'PATH': '${File(java).parent.path}:${Platform.environment['PATH'] ?? ''}'},
    );
  }

  /// 跑一个工具，返回 (退出码, 标准输出 + 标准错误)。
  (int, String) run(String tool, List<String> args) {
    final r = Process.runSync(tool, args, environment: env, stdoutEncoding: utf8, stderrEncoding: utf8);
    return (r.exitCode, '${r.stdout}\n${r.stderr}');
  }
}
