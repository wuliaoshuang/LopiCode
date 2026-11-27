// 第四轮 B2：类名开关配上“成立时的样子”以后——三种网页导出把样式写出来；Flutter 按“条件成立时用另一组属性”导出；
// 没配样子的照旧（说明还在）；面板里“状态”一行多出这条类名的药丸。
import 'dart:io';

// 导出的页面用的是 Flutter 自带的那套 Material：装它的时候也得用这一套。
// ignore: deprecated_member_use
import 'package:flutter/material.dart' as fm;
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/lowcode/bind_model.dart';
import 'package:lopicode/lowcode/export_dart.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:material_ui/material_ui.dart';

import 'generated/class_style_page.dart';
import 'support/bind_export_files.dart';
import 'support/bind_sample.dart';
import 'support/lowcode_builder.dart';

LcDocument _styled() => classStyleSample();

void main() {
  test('存盘再读：样子还在；改条件不丢样子', () {
    final doc = LcDocument.parse(_styled().encode());
    final c = lcClassIfOf(doc.find('submit')!).single;
    expect(c.name, 'ready');
    expect(c.style['background-color'], '#00AA00');
    expect(c.style.length, 4);
  });

  test('三种网页导出：样式表里有“.控件.类名 { … }”这一条；没配样子时没有', () {
    final plain = allExportFiles(bindSample()), styled = allExportFiles(_styled());
    for (final kind in ['html', 'vue', 'react']) {
      String all(Map<String, String> files) => [
        for (final e in files.entries)
          if (e.key.startsWith('$kind/')) e.value,
      ].join('\n');
      final rule = RegExp(r'\.ready\s*\{[^}]*background(-color)?:\s*#00AA00[^}]*\}');
      expect(rule.hasMatch(all(styled)), isTrue, reason: '$kind 应该写出这条类名的样式');
      expect(all(styled), contains('text-decoration: underline'));
      expect(rule.hasMatch(all(plain)), isFalse, reason: '$kind 没配样子时不该有');
    }
  });

  test('Flutter 导出：配了样子就按条件换属性，不认的那条写进说明；没配的还是原来那句说明；检入的样本逐字节一致', () {
    final plain = allExportFiles(bindSample())['flutter/page.dart']!, styled = allExportFiles(_styled())['flutter/page.dart']!;
    expect(plain, contains('类名开关 ready（它还没配“成立时的样子”'));
    expect(styled, isNot(contains('类名开关 ready（它还没配')));
    expect(styled, contains("_lcColor(_lcBool(s_agree) ? '#00AA00' : null)"));
    expect(styled, contains("_lcPxOrNull(_lcBool(s_agree) ? '18px' : null)"), reason: '原来没写字号：条件不成立时用默认字号，不能落成 0');
    expect(styled, contains('类名开关 ready 的样子里的 text-decoration'));
    expect(File('test/generated/class_style_page.dart').readAsStringSync(), exportDart(_styled(), className: 'ClassStylePage'), reason: '导出器改了：运行 dart run tool/gen_sample_export.dart 重新生成');
  });

  testWidgets('Flutter 导出真装进界面：没勾“同意”时按钮是原来的样子（字号不是 0），勾了以后底色、字号换成配的', (tester) async {
    await tester.pumpWidget(const fm.MaterialApp(home: ClassStylePage()));
    await tester.pump();
    final state = tester.state<ClassStylePageState>(find.byType(ClassStylePage));
    fm.ButtonStyle style() => tester.widget<fm.FilledButton>(find.widgetWithText(fm.FilledButton, '提交')).style!;
    expect(style().textStyle?.resolve({})?.fontSize, isNull);
    expect(style().backgroundColor?.resolve({}), isNot(const Color(0xFF00AA00)));
    state.update(() => state.s_agree = true);
    await tester.pump();
    expect(style().backgroundColor?.resolve({}), const Color(0xFF00AA00));
    expect(style().textStyle?.resolve({})?.fontSize, 18);
    expect(tester.takeException(), isNull);
  });

  testWidgets('面板：选中带类名开关的控件，样式页“状态”一行多出“类名 ready”的药丸，点了以后说明在', (tester) async {
    await lbOpen(tester, doc: bindSample());
    await lbTap(tester, lbNode('submit'));
    await lbTap(tester, find.widgetWithText(OutlinedButton, '样式'));
    final pill = find.byKey(const Key('lc-state-class:ready'));
    await tester.ensureVisible(pill);
    await tester.pump();
    expect(pill, findsOneWidget);
    await lbTap(tester, pill);
    expect(find.byKey(const Key('lc-state-note')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
