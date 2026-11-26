// 主题变量＋断点界面的主题冒烟：十套内置主题，每套把这一段新加的每种界面状态都摆一遍——不许抛异常、不许溢出。
//   flutter test --no-pub test/theme_vars_bp_smoke_test.dart
//   LOPI_SHOTS=1 LOPI_SHOT_DIR=../preview flutter test --no-pub test/theme_vars_bp_smoke_test.dart   # 同时出 themebp-<主题>-*.png
//
// 覆盖的状态：顶栏的“看哪种屏宽”按钮和它的菜单、平板档的画布、“常用”页和“样式”页顶上的断点提示（带“清掉”）、
// 数值格的变量牌和“用变量…”的单子、颜色按钮的链环、取色面板的“主题色”、预设档那一行的变量牌、
// “主题变量”页（单子、改一个、写错了、删除确认、加一个的种类菜单、空页）。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/appearance/theme_builtin.dart';
import 'package:lopicode/core/safe_file.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/lowcode/builder_screen.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/state/themes_state.dart';
import 'package:material_ui/material_ui.dart';

import 'support/harness.dart';
import 'support/lowcode_builder.dart';
import 'support/theme_bp_sample.dart';

final String shotDir = Platform.environment['LOPI_SHOT_DIR'] ?? '.tmp/theme-shots';

void main() {
  setUpAll(() async => lbFontsLoaded = await loadRealFonts());

  for (final theme in kBuiltinThemes) {
    Future<void> shot(WidgetTester tester, String page) async {
      expect(tester.takeException(), isNull, reason: '${theme.name} · 主题变量和断点 · $page 渲染时出了异常（溢出也算）');
      await lbShot(tester, shotDir, 'themebp-${theme.id}-$page');
    }

    Future<void> tap(WidgetTester tester, Finder f) async {
      expect(f, findsWidgets, reason: '${theme.name}：要点的东西不在界面上');
      await tester.tap(f.first, warnIfMissed: false);
      await tester.pumpAndSettle();
      await settle(tester, rounds: 2);
    }

    Future<void> back(WidgetTester tester) async {
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await settle(tester, rounds: 2);
    }

    testWidgets('${theme.name}：主题变量和断点的每种界面状态', (tester) async {
      usePhoneViewport(tester);
      late TestEnv env;
      late ProjectSession session;
      await tester.runAsync(() async {
        env = await TestEnv.create();
        expect(await env.services.container.read(themesProvider.notifier).select(theme.id), isNull);
        final project = await env.services.projects.create('我的小站', ProjectTemplate.lowcode);
        session = ProjectSession(env.services, project);
        File(session.guard.resolve(kLowcodePageFile)).writeAsStringSync(themeBpSample().encode());
      });
      addTearDown(() async {
        await pendingWrites();
        session.dispose();
        await env.dispose();
      });
      await tester.pumpWidget(
        appFor(
          env,
          BuilderScreen(key: UniqueKey(), session: session),
          mode: theme.dark ? ThemeMode.dark : ThemeMode.light,
          font: lbFontsLoaded ? kTestFont : null,
        ),
      );
      await settle(tester, rounds: 6);
      expect(lbKey('lc-bp-open'), findsOneWidget);

      // 断点：菜单、平板的画布、样式页和常用页顶上的提示。
      await tap(tester, lbKey('lc-bp-open'));
      await shot(tester, 'bp-menu');
      await tap(tester, lbKey('lc-bp-tablet'));
      await shot(tester, 'bp-tablet');
      await tap(tester, lbNode('title'));
      await lbOpenCommon(tester);
      expect(lbKey('lc-bp-note'), findsOneWidget);
      await shot(tester, 'bp-common');
      await tap(tester, find.text('样式').last);
      await lbTapShown(tester, lbKey('lc-tab-text'));
      await lbShow(tester, lbKey('lc-bp-note'));
      expect(lbKey('lc-bp-clear'), findsOneWidget, reason: '标题在平板档改过字号');
      await shot(tester, 'bp-style');
      await tap(tester, lbKey('lc-bp-open'));
      await tap(tester, lbKey('lc-bp-phone'));

      // 用变量：数值格的变量牌、“用变量…”的单子、颜色按钮的链环、取色面板的主题色。
      await lbShow(tester, lbKey('lc-len-font-size-var'));
      await shot(tester, 'var-style');
      await lbTapShown(tester, lbKey('lc-len-font-size-var'));
      await shot(tester, 'var-length-menu');
      await back(tester);
      await lbTapShown(tester, lbKey('lc-color-color'));
      expect(find.textContaining('主题色'), findsOneWidget);
      await shot(tester, 'var-color-sheet');
      await back(tester);
      // “常用”页：预设档那一行用着变量。
      await tap(tester, find.text('常用').last);
      await shot(tester, 'var-common');
      await back(tester);

      // 主题变量页：单子、改一个、写错了、删除确认、加一个。
      await tap(tester, find.byTooltip('更多'));
      await tap(tester, find.widgetWithText(PopupMenuItem<String>, '主题变量'));
      await shot(tester, 'theme-list');
      await tap(tester, lbKey('lc-var-row-color-primary'));
      await shot(tester, 'theme-edit');
      await tester.enterText(lbKey('lc-var-value'), 'red!');
      await tester.pump();
      await shot(tester, 'theme-edit-bad');
      await tap(tester, lbKey('lc-var-delete'));
      await shot(tester, 'theme-delete-confirm');
      await tap(tester, find.widgetWithText(TextButton, '取消'));
      await tap(tester, lbKey('lc-var-row-font-lg'));
      await shot(tester, 'theme-edit-number');
      await back(tester);
      await tester.scrollUntilVisible(
        lbKey('lc-var-add'),
        300,
        scrollable: find.descendant(of: lbKey('lc-var-list'), matching: find.byType(Scrollable)).first,
      );
      await tap(tester, lbKey('lc-var-add'));
      await shot(tester, 'theme-add-menu');
      await back(tester);
      await back(tester);
      expect(lbKey('lc-bp-open'), findsOneWidget);
    });

    testWidgets('${theme.name}：还没有主题变量的空页', (tester) async {
      usePhoneViewport(tester);
      late TestEnv env;
      late ProjectSession session;
      await tester.runAsync(() async {
        env = await TestEnv.create();
        expect(await env.services.container.read(themesProvider.notifier).select(theme.id), isNull);
        final project = await env.services.projects.create('我的小站', ProjectTemplate.lowcode);
        session = ProjectSession(env.services, project);
      });
      addTearDown(() async {
        await pendingWrites();
        session.dispose();
        await env.dispose();
      });
      await tester.pumpWidget(
        appFor(
          env,
          BuilderScreen(key: UniqueKey(), session: session),
          mode: theme.dark ? ThemeMode.dark : ThemeMode.light,
          font: lbFontsLoaded ? kTestFont : null,
        ),
      );
      await settle(tester, rounds: 6);
      await tap(tester, find.byTooltip('更多'));
      await tap(tester, find.widgetWithText(PopupMenuItem<String>, '主题变量'));
      expect(find.text('还没有主题变量'), findsOneWidget);
      await shot(tester, 'theme-empty');
    });
  }
}
