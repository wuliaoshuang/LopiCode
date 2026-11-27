// 第四轮 B2：三种形状的组件（带事件、变体、状态、绑定）用在页面上以后的 Flutter 导出——
// 检入的样本和导出器当前输出逐字节一致；样本真装进界面（390 和平板 800），不抛异常、不溢出；
// 在代码里改状态界面跟着变；每个实例一份的组件状态互不相干。
// Flutter 这一份不导出积木逻辑（按钮的 onPressed 是空的），所以“点按钮事件传到页面”在这里验不了——那一条在三种网页导出里真跑过。
import 'dart:io';

// 导出的页面用的是 Flutter 自带的那套 Material（别人的工程里没有我们的 material_ui）：这里也得用它来装。
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/lowcode/export_dart.dart';

import 'generated/comp_card_page.dart';
import 'generated/comp_login_page.dart';
import 'generated/comp_tags_page.dart';
import 'support/comp_samples.dart';

Future<void> _show(WidgetTester tester, Widget page, double width) async {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: page));
  await tester.pump();
  expect(tester.takeException(), isNull);
}

void main() {
  test('检入的样本和导出器当前的输出逐字节一致', () {
    const hint = '导出器改了：运行 dart run tool/gen_sample_export.dart 重新生成';
    expect(File('test/generated/comp_card_page.dart').readAsStringSync(), exportDart(compUserDoc([productCardDef()]), className: 'CompCardPage'), reason: hint);
    expect(File('test/generated/comp_login_page.dart').readAsStringSync(), exportDart(compUserDoc([loginFormDef()]), className: 'CompLoginPage'), reason: hint);
    expect(File('test/generated/comp_tags_page.dart').readAsStringSync(), exportDart(compUserDoc([tagBarDef()]), className: 'CompTagsPage'), reason: hint);
  });

  for (final width in [390.0, 800.0]) {
    testWidgets('商品卡片（宽 $width）：装得进去；属性绑的状态变了卡片跟着变；两张卡片的“收藏”各是各的', (tester) async {
      await _show(tester, const CompCardPage(), width);
      expect(find.text('苹果'), findsOneWidget);
      expect(find.text('香蕉'), findsOneWidget);
      expect(find.text('¥3'), findsOneWidget);
      expect(find.text('¥2'), findsOneWidget);
      expect(find.text('加入购物车'), findsNWidgets(2));
      final state = tester.state<CompCardPageState>(find.byType(CompCardPage));
      state.update(() => state.s_apple = '红富士');
      await tester.pump();
      expect(find.text('红富士'), findsOneWidget);
      expect(find.text('苹果'), findsNothing);
      await tester.tap(find.byType(Checkbox).first);
      await tester.pump();
      expect(state.s_p1__liked, isTrue);
      expect(state.s_p2__liked, isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('登录表单（宽 $width）：装得进去；输入框写回页面状态', (tester) async {
      await _show(tester, const CompLoginPage(), width);
      expect(find.text('请登录'), findsOneWidget);
      expect(find.text('登录'), findsOneWidget);
      final state = tester.state<CompLoginPageState>(find.byType(CompLoginPage));
      await tester.enterText(find.byType(TextField).first, 'shuang');
      await tester.pump();
      expect(state.s_u, 'shuang');
      expect(find.textContaining('用户=shuang'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('标签筛选条（宽 $width）：装得进去；列表状态变了标签跟着变，空了显示“还没有标签”', (tester) async {
      await _show(tester, const CompTagsPage(), width);
      expect(find.text('水果'), findsOneWidget);
      expect(find.text('零食'), findsOneWidget);
      expect(find.text('现在选的：蔬菜'), findsOneWidget);
      final state = tester.state<CompTagsPageState>(find.byType(CompTagsPage));
      state.update(() => state.s_tagList = <Object?>['饮料']);
      await tester.pump();
      expect(find.text('饮料'), findsOneWidget);
      expect(find.text('水果'), findsNothing);
      state.update(() => state.s_tagList = <Object?>[]);
      await tester.pump();
      expect(find.text('还没有标签'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
