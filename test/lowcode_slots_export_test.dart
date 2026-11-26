// 带插槽的自定义组件（第 3 期第 3 段）：四种导出。Vue / React 的真编译在 dev_webdev_compile_test.dart。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/lowcode/export_dart.dart';
import 'package:lopicode/lowcode/export_html.dart';
import 'package:lopicode/lowcode/export_react.dart';
import 'package:lopicode/lowcode/export_vue.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:material_ui/material_ui.dart';

import 'generated/slot_card_page.dart';
import 'support/html_check.dart';
import 'support/slot_sample.dart';

void main() {
  test('Vue：定义里是 <slot>（带默认内容），实例里每个插槽一个 <template #名字>；没填的实例是自闭合标签', () {
    final e = exportVue(slotCardPage());
    final page = e.file('Shop.vue')!.content, card = e.file('components/ProductCard.vue')!.content;
    expect(e.files.every((f) => f.formatProblem == null), isTrue);
    expect(card, contains('<slot>'));
    expect(card, contains('<slot name="footer">'));
    expect(card, allOf(contains('暂无介绍'), contains('加入购物车')));
    expect(RegExp(r'<slot>\s*<p[^>]*>暂无介绍</p>\s*</slot>').hasMatch(card), isTrue, reason: card);
    expect(page, contains('<template #default>'));
    expect(page, contains('<template #footer>'));
    expect(RegExp(r'<template #footer>\s*<button[^>]*>立即购买</button>\s*<button[^>]*>收藏</button>\s*</template>').hasMatch(page), isTrue, reason: page);
    expect(RegExp(r'<ProductCard class="lc-component n-b" />').hasMatch(page), isTrue, reason: page);
    // 填进去的内容的样式在页面这个文件里（Vue：插槽内容归父组件管）；“父容器”按占位节点所在的容器算：
    // p1 在竖排的列里“撑满”＝ align-self: stretch；按钮在横排的行里。
    expect(RegExp(r'\.n-p1 \{[^}]*align-self: stretch').hasMatch(page), isTrue, reason: page);
    expect(card, isNot(contains('n-p1')));
    expect(e.notes.join(), isNot(contains('插槽占位')));
  });

  test('React：默认插槽走 children，具名插槽当属性传一段 JSX；组件里“外面没传就用默认内容”', () {
    final e = exportReact(slotCardPage());
    final page = e.files.firstWhere((f) => f.path == 'Shop.jsx').content, card = e.file('components/ProductCard.jsx')!.content;
    expect(e.files.every((f) => f.formatProblem == null), isTrue);
    expect(card, contains('export default function ProductCard({ title = "商品名", children, footer, className, style, ...lcRest })'));
    expect(RegExp(r'\{children \?\? \(\s*<>').hasMatch(card), isTrue, reason: card);
    expect(RegExp(r'\{footer \?\? \(\s*<>').hasMatch(card), isTrue, reason: card);
    expect(RegExp(r'footer=\{\s*<>\s*<button[^>]*>\s*立即购买').hasMatch(page), isTrue, reason: page);
    expect(page, contains('</ProductCard>'));
    expect(RegExp(r'<ProductCard className="lc-component n-b" />').hasMatch(page), isTrue, reason: page);
  });

  test('网页：插槽内容内联进去，填的在填的位置、默认的在默认的位置；结构检查通过', () {
    final e = exportHtml(slotCardPage());
    expect(htmlProblems(e.html), isEmpty);
    final order = ['今日推荐', '草莓蛋糕', '新鲜草莓，当天现做', '¥ 68', '立即购买', '收藏', '商品名', '暂无介绍', '加入购物车'];
    var at = -1;
    for (final t in order) {
      final i = e.html.indexOf(t, at + 1);
      expect(i, greaterThan(at), reason: '“$t”不在该在的位置：${e.html}');
      at = i;
    }
    expect('暂无介绍'.allMatches(e.html).length, 1, reason: '填了内容的那个实例里不该再有默认内容');
    expect(e.html, isNot(contains('slot')));
    expect(e.css, contains('.n-p1 {'));
  });

  test('定义里已经没有插槽、实例还带着内容：不导出这些内容，记一条说明', () {
    final json = slotCardJson();
    final root = ((json['components']! as List).single as Map)['root'] as Map;
    (root['children'] as List).removeRange(1, 3);
    ((json['components']! as List).single as Map).remove('slots');
    final doc = LcDocument.parse(const JsonEncoder().convert(json));
    for (final e in [exportVue(doc), exportReact(doc)]) {
      expect(e.notes.join(), contains('已经没有插槽了'));
      expect(e.files.map((f) => f.content).join(), isNot(contains('立即购买')));
    }
    expect(exportHtml(doc).html, isNot(contains('立即购买')));
  });

  group('Flutter', () {
    test('检入的样本和导出器当前的输出一致', () {
      expect(File('test/generated/slot_card_page.dart').readAsStringSync(), exportDart(slotCardPage(), className: 'SlotCardPage'), reason: '导出器改了：运行 dart run tool/gen_sample_export.dart 重新生成');
    });

    testWidgets('能在 390 宽上渲染；填的内容和默认内容各在各的卡片里', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(home: SlotCardPage()));
      await tester.pump();
      expect(tester.takeException(), isNull);
      for (final t in ['草莓蛋糕', '新鲜草莓，当天现做', '¥ 68', '立即购买', '收藏', '商品名', '暂无介绍', '加入购物车']) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
      double y(String t) => tester.getTopLeft(find.text(t)).dy;
      expect(y('草莓蛋糕') < y('新鲜草莓，当天现做') && y('¥ 68') < y('立即购买') && y('立即购买') < y('商品名') && y('商品名') < y('暂无介绍') && y('暂无介绍') < y('加入购物车'), isTrue);
      expect((y('立即购买') - y('收藏')).abs() < 1, isTrue, reason: '两个按钮在同一行（占位节点所在的那一行）');
    });
  });
}
