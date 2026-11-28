// 重新生成 test/generated/sample_page.dart 和 v3_page.dart（低代码 Dart 导出的编译检查样本）：
//   dart run tool/gen_sample_export.dart
import 'dart:io';

import 'package:lopicode/lowcode/export_dart.dart';

import '../test/support/b7_live_sample.dart';
import '../test/support/b8_sample.dart';
import '../test/support/bind_sample.dart';
import '../test/support/box_off_sample.dart';
import '../test/support/builtin_p1_sample.dart';
import '../test/support/comp_event_samples.dart';
import '../test/support/comp_samples.dart';
import '../test/support/dart_live_sample.dart';
import '../test/support/pages_sample.dart';
import '../test/support/sample_doc.dart';
import '../test/support/slot_sample.dart';
import '../test/support/theme_bp_sample.dart';
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
  // 第 4 期 B2：带主题变量和断点的两页样例（test/lowcode_theme_bp_export_test.dart 会 import 它）。
  File('test/generated/theme_bp_page.dart').writeAsStringSync(exportDart(themeBpSample(), className: 'ThemeBpHomePage'));
  // 第四轮 B1：带状态和 8 种绑定的两页样例（“会动的”导出；test/lowcode_dart_live_test.dart 会 import 它）。
  File('test/generated/bind_page.dart').writeAsStringSync(exportDart(bindSample(), className: 'BindHomePage'));
  File('test/generated/live_page.dart').writeAsStringSync(exportDart(dartLiveSample(), className: 'LivePage'));
  // 第四轮 B2：三种形状的组件（带事件、变体、状态、绑定）用在页面上（test/lowcode_comp_dart_test.dart 会 import 它们）。
  File('test/generated/comp_card_page.dart').writeAsStringSync(exportDart(compUserDoc([productCardDef()]), className: 'CompCardPage'));
  File('test/generated/comp_login_page.dart').writeAsStringSync(exportDart(compUserDoc([loginFormDef()]), className: 'CompLoginPage'));
  File('test/generated/comp_tags_page.dart').writeAsStringSync(exportDart(compUserDoc([tagBarDef()]), className: 'CompTagsPage'));
  File('test/generated/class_style_page.dart').writeAsStringSync(exportDart(classStyleSample(), className: 'ClassStylePage'));
  // 第四轮 B6：组件事件接的动作、变体、能滚的区域、下划线在 Flutter 里（test/lowcode_dart_events_test.dart 会 import 它们）。
  File('test/generated/builtin_p1_page.dart').writeAsStringSync(exportDart(builtinP1Doc(), className: 'BuiltinP1Page'));
  File('test/generated/comp_event_page.dart').writeAsStringSync(exportDart(compEventDoc(), className: 'CompEventPage'));
  // 第四轮 B7：容器的禁用 / 说明文字、图标按钮的两个属性（test/lowcode_box_off_test.dart 会 import 它）。
  File('test/generated/box_off_page.dart').writeAsStringSync(exportDart(boxOffDoc(), className: 'BoxOffPage'));
  // 第四轮 B7：步进器开箱即用、“重复”里的事件、重复几次 / 等一会儿 / 打印（test/lowcode_b7_live_test.dart 会 import 它）。
  File('test/generated/b7_live_page.dart').writeAsStringSync(exportDart(b7LiveDoc(), className: 'B7LivePage'));
  // 第四轮 B8：不是按钮的组件“按下”时换样子、“重复”为空时显示一块内容、轻提示（test/lowcode_b8_export_test.dart 会 import 它）。
  File('test/generated/b8_page.dart').writeAsStringSync(exportDart(b8Doc(), className: 'B8Page'));
  stdout.writeln('ok');
}
