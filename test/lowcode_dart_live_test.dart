// 第四轮 B1·Flutter“会动的”导出：用了主题变量、状态与绑定、断点、状态样式、网格的项目，导出的代码
// 检入在 test/generated/ 里（和导出器当前输出逐字节一致），这里真的把它装进界面：390 宽和平板宽各渲染一遍，
// 改状态以后界面确实跟着变。没用这些功能的项目走原来的路（另有基线测试钉着）。
import 'dart:io';

// 导出的页面用的是 Flutter 自带的那套 Material（别人的工程里没有我们的 material_ui）：这里也得用它来装。
// ignore: deprecated_member_use
import 'package:flutter/material.dart' as m;
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/lowcode/export_dart.dart';
import 'package:lopicode/lowcode/export_dart_live.dart';

import 'generated/bind_page.dart';
import 'generated/live_page.dart';
import 'generated/theme_bp_page.dart';
import 'support/bind_sample.dart';
import 'support/dart_live_sample.dart';
import 'support/sample_doc.dart';
import 'support/theme_bp_sample.dart';

Future<void> _show(WidgetTester tester, m.Widget page, double width) async {
  tester.view.physicalSize = m.Size(width, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(m.MaterialApp(home: page));
  await tester.pump();
  expect(tester.takeException(), isNull);
}

void main() {
  // 跨页共用的状态是静态的：每条测试前放回初值。
  setUp(() {
    LcAppState.user = '小塔塔';
    LcAppState.visits = 0;
    LcAppState.cart = <Object?>[
      <String, Object?>{'id': 'a', 'name': '苹果', 'price': 3},
      <String, Object?>{'id': 'b', 'name': '香蕉', 'price': 2},
    ];
  });

  group('检入的样本', () {
    test('和导出器当前的输出逐字节一致', () {
      const hint = '导出器改了：运行 dart run tool/gen_sample_export.dart 重新生成';
      expect(File('test/generated/bind_page.dart').readAsStringSync(), exportDart(bindSample(), className: 'BindHomePage'), reason: hint);
      expect(File('test/generated/live_page.dart').readAsStringSync(), exportDart(dartLiveSample(), className: 'LivePage'), reason: hint);
    });

    test('哪些项目走“会动的那一路”：用了变量 / 绑定 / 断点 / 状态样式 / 网格的才走', () {
      expect(dartLiveWanted(sample()), isFalse);
      expect(dartLiveWanted(bindSample()), isTrue);
      expect(dartLiveWanted(themeBpSample()), isTrue);
      final onlyVarsDefined = themeBpSample();
      // 只定义了变量、哪儿都没用：不算。
      final plain = sample()..more['theme'] = onlyVarsDefined.more['theme'];
      expect(dartLiveWanted(plain), isFalse);
      expect(exportDart(plain), exportDart(sample()));
    });

    test('文件头：说了变量在哪、状态怎么改、断点怎么取；导不出的逐条写了', () {
      final live = exportDart(dartLiveSample(), className: 'LivePage');
      expect(live, contains('// 主题变量：集中在文件末尾的 LcVars 里'));
      expect(live, contains('update(() => s_xxx = 新值)'));
      expect(live, contains('// 断点：按屏幕宽度取样子'));
      expect(live, contains('样式绑定里的 letter-spacing'));
      expect(live, isNot(contains('四边不一样')), reason: '网格的行列间距不一样不算导不出');
      expect(live, contains('static const Color colorAccent = Color(0xFF058654);'));
      expect(live, contains('// --font-family-x: serif'), reason: '不是长度也不是颜色的变量：写成一行说明');
      expect(live, isNot(contains('var(--')));
      final bind = exportDart(bindSample(), className: 'BindHomePage');
      expect(bind, contains('类名开关 ready'));
      expect(bind, contains('abstract final class LcAppState'));
      expect(bind, isNot(contains('LcVars')), reason: '没定义变量的项目不带变量表');
    });
  });

  group('状态与绑定（bind_sample）', () {
    testWidgets('手机宽度：初值对；输入框写回状态，显示条件跟着变；勾选框解开禁用', (tester) async {
      await _show(tester, const BindHomePage(), 390);
      expect(find.text('你好，小塔塔'), findsOneWidget);
      expect(find.text('已点 0 次'), findsOneWidget, reason: '派生状态');
      expect(find.text('1. 苹果 ¥3'), findsOneWidget, reason: '重复：序号、这一项里的格子');
      expect(find.text('2. 香蕉 ¥2'), findsOneWidget);
      expect(find.text('共 2 件'), findsOneWidget, reason: '项目级的派生状态');
      expect(find.text('• 甲'), findsOneWidget, reason: '列表内容绑状态');
      expect(find.textContaining('在搜：'), findsNothing, reason: '显示条件不成立');
      expect(find.text('点够三次了'), findsNothing, reason: '存在条件不成立');

      await tester.enterText(find.byType(m.TextField), '曲奇');
      await tester.pump();
      expect(find.text('在搜：曲奇'), findsOneWidget, reason: '双向：输入框写回 keyword，绑了它的文字和显示条件跟着变');

      m.FilledButton submit() => tester.widget<m.FilledButton>(find.widgetWithText(m.FilledButton, '提交'));
      expect(submit().onPressed, isNull, reason: '禁用绑的是“没同意”');
      await tester.tap(find.byType(m.Checkbox));
      await tester.pump();
      expect(submit().onPressed, isNotNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('在代码里改状态：update(...) 之后界面重画（存在条件、派生、样式绑定的宽度）', (tester) async {
      await _show(tester, const BindHomePage(), 390);
      final state = tester.state<BindHomePageState>(find.byType(BindHomePage));
      expect(tester.getSize(find.widgetWithText(m.FilledButton, '提交')).width, 120, reason: '宽度绑的是 count * 10 + 120');
      state.update(() => state.s_count = 3);
      await tester.pump();
      expect(find.text('已点 3 次'), findsOneWidget);
      expect(find.text('点够三次了'), findsOneWidget);
      expect(tester.getSize(find.widgetWithText(m.FilledButton, '提交')).width, 150);
      state.update(() => state.s_keyword = '外面改的');
      await tester.pump();
      await tester.pump();
      expect(tester.widget<m.TextField>(find.byType(m.TextField)).controller!.text, '外面改的', reason: '状态被别处改了，输入框里的字下一帧对齐');
      expect(tester.takeException(), isNull);
    });

    testWidgets('跨页共用的状态：LcAppState.update 之后开着的页面跟着变；列表空了显示“空的时候”那句', (tester) async {
      await _show(tester, const BindHomePage(), 390);
      LcAppState.update(
        () => LcAppState.cart = <Object?>[
          ...(LcAppState.cart! as List<Object?>),
          <String, Object?>{'id': 'c', 'name': '曲奇', 'price': 5},
        ],
      );
      await tester.pump();
      expect(find.text('3. 曲奇 ¥5'), findsOneWidget);
      expect(find.text('共 3 件'), findsOneWidget);
      LcAppState.update(() => LcAppState.cart = <Object?>[]);
      await tester.pump();
      expect(find.text('购物车是空的'), findsOneWidget);
      expect(find.textContaining('苹果'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('平板宽度（800）：装得进去，没有异常、没有溢出', (tester) async {
      await _show(tester, const BindHomePage(), 800);
      expect(find.text('你好，小塔塔'), findsOneWidget);
    });
  });

  group('主题变量＋断点（theme_bp_sample）', () {
    m.Text title(WidgetTester tester) => tester.widget<m.Text>(find.text('欢迎来到小站'));

    testWidgets('手机 390：标题 20；卡片区竖排；按钮按下时的底色是变量 color-text', (tester) async {
      await _show(tester, const ThemeBpHomePage(), 390);
      expect(title(tester).style?.fontSize, 20);
      expect(tester.getTopLeft(find.text('抹茶卷')).dy, greaterThan(tester.getTopLeft(find.text('草莓蛋糕')).dy), reason: '竖排');
      final style = tester.widget<m.FilledButton>(find.byType(m.FilledButton)).style!;
      expect(style.backgroundColor!.resolve({}), const m.Color(0xFF058654));
      expect(style.backgroundColor!.resolve({m.WidgetState.pressed}), const m.Color(0xFF222435));
    });

    testWidgets('平板 800：标题 30；卡片区横排', (tester) async {
      await _show(tester, const ThemeBpHomePage(), 800);
      expect(title(tester).style?.fontSize, 30);
      expect(tester.getTopLeft(find.text('抹茶卷')).dy, tester.getTopLeft(find.text('草莓蛋糕')).dy, reason: '横排');
      expect(tester.getTopLeft(find.text('抹茶卷')).dx, greaterThan(tester.getTopLeft(find.text('草莓蛋糕')).dx));
    });

    testWidgets('桌面 1100：卡片之间的间距 24（平板是 8）', (tester) async {
      double gap(WidgetTester t) {
        final row = t.widget<m.Row>(find.ancestor(of: find.text('抹茶卷'), matching: find.byType(m.Row)).first);
        return row.spacing;
      }

      await _show(tester, const ThemeBpHomePage(), 800);
      expect(gap(tester), 8);
      await _show(tester, const ThemeBpHomePage(), 1100);
      expect(gap(tester), 24);
    });
  });

  group('网格、各种双向、样式绑定、状态样式（dart_live_sample）', () {
    testWidgets('手机 390：网格 2 列、甲跨两列；平板 800：4 列、只在手机上的那块没有', (tester) async {
      await _show(tester, const LivePage(), 390);
      double w(String text) => tester.getSize(find.ancestor(of: find.text(text), matching: find.byType(m.SizedBox)).first).width;
      const inner = 390.0 - 32;
      expect(w('乙'), closeTo((inner - 8) / 2, 0.01));
      expect(w('甲（跨两列）'), closeTo(inner, 0.01));
      expect(tester.getTopLeft(find.text('丙')).dy, tester.getTopLeft(find.text('乙')).dy, reason: '乙、丙在同一行');
      expect(find.text('只在手机上'), findsOneWidget);
      expect(find.text('数到 2'), findsOneWidget, reason: '顶栏标题绑状态');

      await _show(tester, const LivePage(), 800);
      const wide = 800.0 - 32;
      expect(w('乙'), closeTo((wide - 24) / 4, 0.01));
      expect(w('甲（跨两列）'), closeTo((wide - 24) / 4 * 2 + 8, 0.01));
      expect(tester.getTopLeft(find.text('乙')).dy, tester.getTopLeft(find.text('甲（跨两列）')).dy, reason: '4 列：甲、乙、丙排一行');
      expect(find.text('只在手机上'), findsNothing, reason: '平板档 display: none');
    });

    testWidgets('开关、单选、下拉、多行输入、数字输入都写回状态，绑了的地方跟着变', (tester) async {
      await _show(tester, const LivePage(), 390);
      final state = tester.state<LivePageState>(find.byType(LivePage));
      m.FilledButton go() => tester.widget<m.FilledButton>(find.widgetWithText(m.FilledButton, '提交'));

      expect(find.text('开着'), findsNothing);
      expect(go().onPressed, isNull);
      expect(go().style!.backgroundColor!.resolve({m.WidgetState.disabled}), const m.Color(0xFFCCCCCC), reason: '禁用时的底色');
      await tester.tap(find.byType(m.Switch));
      await tester.pump();
      expect(state.s_on, true);
      expect(find.text('开着'), findsOneWidget);
      expect(go().onPressed, isNotNull);
      expect(go().style!.foregroundColor!.resolve({m.WidgetState.pressed}), const m.Color(0xFFFFFF00), reason: '按下时的文字颜色');
      expect(go().style!.backgroundColor!.resolve({}), const m.Color(0xFF058654), reason: '平时的底色＝变量 color-accent');

      expect(find.text('选了：a'), findsOneWidget);
      await tester.tap(find.text('乙项'));
      await tester.pump();
      expect(find.text('选了：b'), findsOneWidget);
      expect(tester.widget<m.SegmentedButton<String>>(find.byType(m.SegmentedButton<String>)).selected, {'b'}, reason: '两个单选组绑的是同一个状态');
      await tester.tap(find.text('按钮甲'));
      await tester.pump();
      expect(find.text('选了：a'), findsOneWidget);

      await tester.enterText(find.widgetWithText(m.TextField, '备注'), '多放糖');
      await tester.pump();
      expect(find.text('备注：多放糖'), findsOneWidget);

      await tester.enterText(find.widgetWithText(m.TextField, '数字'), '5');
      await tester.pump();
      expect(state.s_n, 5, reason: '数字状态：写回去的是数');
      expect(find.text('双倍：10'), findsOneWidget);
      expect(find.text('数到 5'), findsOneWidget);
      final twice = tester.widget<m.Text>(find.text('双倍：10'));
      expect(twice.style!.fontSize, 50, reason: '字号绑的是 n * 10');
      expect(twice.style!.color, const m.Color(0xFFFF0000), reason: '颜色绑的是 tint');
      state.update(() => state.s_tint = '#00F');
      await tester.pump();
      expect(tester.widget<m.Text>(find.text('双倍：10')).style!.color, const m.Color(0xFF0000FF));
      state.update(() => state.s_tint = '乱写');
      await tester.pump();
      expect(tester.widget<m.Text>(find.text('双倍：10')).style!.color, const m.Color(0xFF222435), reason: '认不出来的颜色回到平时的');

      final border = tester.widget<m.TextField>(find.widgetWithText(m.TextField, '5')).decoration!.focusedBorder! as m.OutlineInputBorder;
      expect(border.borderSide.color, const m.Color(0xFFFF0000), reason: '聚焦时的边框颜色');

      state.update(() => state.s_city = 'sh');
      await tester.pump();
      expect(find.text('城市：sh'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('下拉选择点一项写回状态；弹窗开着的时候状态变了，标题跟着变', (tester) async {
      await _show(tester, const LivePage(), 390);
      final state = tester.state<LivePageState>(find.byType(LivePage));
      await tester.tap(find.byType(m.DropdownMenu<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('北京').last);
      await tester.pumpAndSettle();
      expect(state.s_city, 'bj');
      expect(find.text('城市：bj'), findsOneWidget);

      final context = tester.element(find.byType(LivePage));
      final closed = state.showDialog_dlg(context);
      await tester.pumpAndSettle();
      expect(find.text('现在是 2'), findsOneWidget);
      state.update(() => state.s_n = 9);
      await tester.pump();
      expect(find.text('现在是 9'), findsOneWidget);
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      await closed;
      expect(tester.takeException(), isNull);
    });
  });
}
