// 开发时用：把第 5 期样例的四种导出写到一个目录里，方便人看、方便拿 node 直接跑。平时跳过。
// 用法：LOPI_BIND_DUMP=<目录> flutter test test/lowcode_bind_dump_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/bind_export_files.dart';
import 'support/bind_sample.dart';

void main() {
  final dir = Platform.environment['LOPI_BIND_DUMP'] ?? '';
  test('把样例的四种导出写到 LOPI_BIND_DUMP', () {
    final files = allExportFiles(bindSample());
    for (final f in files.entries) {
      File('$dir/${f.key}')
        ..createSync(recursive: true)
        ..writeAsStringSync(f.value);
    }
    expect(files, isNotEmpty);
  }, skip: dir.isEmpty ? '没给 LOPI_BIND_DUMP，跳过' : false);
}
