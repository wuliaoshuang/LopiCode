// 重新生成 test/generated/sample_page.dart 和 v3_page.dart（低代码 Dart 导出的编译检查样本）：
//   dart run tool/gen_sample_export.dart
import 'dart:io';

import 'package:lopicode/lowcode/export_dart.dart';

import '../test/support/pages_sample.dart';
import '../test/support/sample_doc.dart';
import '../test/support/slot_sample.dart';
import '../test/support/v3_components_sample.dart';
import '../test/support/v3_sample.dart';

void main() {
  File('test/generated/sample_page.dart').writeAsStringSync(exportDart(sample(), className: 'SamplePage'));
  // 格式第 3 版新属性的样本（test/lowcode_v3_fields_test.dart 会 import 它，所以必须能编译）。
  File('test/generated/v3_page.dart').writeAsStringSync(exportDart(v3Sample(), className: 'V3Page'));
  // 第 3 期第 2 段：11 个新组件的四个样例页（test/lowcode_v3_components_export_test.dart 会 import 它们）。
  File('test/generated/v3_login_page.dart').writeAsStringSync(exportDart(v3LoginPage(), className: 'V3LoginPage'));
  File('test/generated/v3_settings_page.dart').writeAsStringSync(exportDart(v3SettingsPage(), className: 'V3SettingsPage'));
  File('test/generated/v3_home_page.dart').writeAsStringSync(exportDart(v3HomePage(), className: 'V3HomePage'));
  File('test/generated/v3_all_page.dart').writeAsStringSync(exportDart(v3AllPage(), className: 'V3AllPage'));
  // 第 3 期第 3 段：带插槽的自定义组件（test/lowcode_slots_export_test.dart 会 import 它）。
  File('test/generated/slot_card_page.dart').writeAsStringSync(exportDart(slotCardPage(), className: 'SlotCardPage'));
  // 第 4 期：多页面样例（三页一个文件，test/lowcode_pages_export_test.dart 会 import 它）。
  File('test/generated/pages_page.dart').writeAsStringSync(exportDart(pagesSample(), className: 'PagesHomePage'));
  stdout.writeln('ok');
}
