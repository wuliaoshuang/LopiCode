import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/lowcode/export_dart.dart';

import 'generated/sample_page.dart';
import 'support/sample_doc.dart';

/// 低代码导出的 Dart 代码不能只“看起来对”：
/// test/generated/sample_page.dart 是导出器的真实输出，被这个测试 import，
/// 所以它必须能编译；再把它真的渲染出来，确认没有布局错误。
void main() {
  test('检入的样本和导出器当前的输出一致', () {
    final current = exportDart(sample(), className: 'SamplePage');
    expect(
      File('test/generated/sample_page.dart').readAsStringSync(),
      current,
      reason: '导出器改了：运行 dart run tool/gen_sample_export.dart 重新生成',
    );
  });

  testWidgets('导出的页面能在 390 宽的屏幕上渲染，没有溢出或布局异常', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: SamplePage()));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('登录'), findsOneWidget);
    expect(find.text('注册'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.text('• 二 & 三'), findsOneWidget);
  });
}
