// 重新生成 test/generated/sample_page.dart（低代码 Dart 导出的编译检查样本）：
//   dart run tool/gen_sample_export.dart
import 'dart:io';

import 'package:lopicode/lowcode/export_dart.dart';

import '../test/support/sample_doc.dart';

void main() {
  File('test/generated/sample_page.dart').writeAsStringSync(exportDart(sample(), className: 'SamplePage'));
  stdout.writeln('ok');
}
