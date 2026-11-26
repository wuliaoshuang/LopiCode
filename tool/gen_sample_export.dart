// 重新生成 test/generated/sample_page.dart 和 v3_page.dart（低代码 Dart 导出的编译检查样本）：
//   dart run tool/gen_sample_export.dart
import 'dart:io';

import 'package:lopicode/lowcode/export_dart.dart';

import '../test/support/sample_doc.dart';
import '../test/support/v3_sample.dart';

void main() {
  File('test/generated/sample_page.dart').writeAsStringSync(exportDart(sample(), className: 'SamplePage'));
  // 格式第 3 版新属性的样本（test/lowcode_v3_fields_test.dart 会 import 它，所以必须能编译）。
  File('test/generated/v3_page.dart').writeAsStringSync(exportDart(v3Sample(), className: 'V3Page'));
  stdout.writeln('ok');
}
