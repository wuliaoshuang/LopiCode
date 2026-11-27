// 多页面界面的主题冒烟：十套内置主题，每套把多页面新加的每种界面状态都摆一遍——不许抛异常、不许溢出。
//   flutter test --no-pub test/theme_pages_smoke_test.dart
//   LOPI_SHOTS=1 LOPI_SHOT_DIR=../preview flutter test --no-pub test/theme_pages_smoke_test.dart   # 同时出 pages-<主题>-*.png
//
// 覆盖的状态：顶栏的“N 页”按钮、页面面板、一页的 ⋮ 菜单、改名对话框、删除确认、
// 导航项的“点了去”、选页面的单子、“改成各页共用”确认（原来是“同步到其它页面”）、事件页的“点击时去页面”和它的选页单子、跨页撤销的提示。
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
import 'support/pages_sample.dart';

final String shotDir = Platform.environment['LOPI_SHOT_DIR'] ?? '.tmp/theme-shots';

void main() {
  setUpAll(() async => lbFontsLoaded = await loadRealFonts());

  for (final theme in kBuiltinThemes) {
    Future<void> shot(WidgetTester tester, String page) async {
      expect(tester.takeException(), isNull, reason: '${theme.name} · 多页面 · $page 渲染时出了异常（溢出也算）');
      await lbShot(tester, shotDir, 'pages-${theme.id}-$page');
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

    testWidgets('${theme.name}：多页面的每种界面状态', (tester) async {
      usePhoneViewport(tester);
      late TestEnv env;
      late ProjectSession session;
      await tester.runAsync(() async {
        env = await TestEnv.create();
        expect(await env.services.container.read(themesProvider.notifier).select(theme.id), isNull);
        final project = await env.services.projects.create('我的小站', ProjectTemplate.lowcode);
        session = ProjectSession(env.services, project);
        File(session.guard.resolve(kLowcodePageFile)).writeAsStringSync(pagesSample().encode());
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
      expect(find.descendant(of: lbKey('lc-pages-open'), matching: find.text('3 页')), findsOneWidget);
      await shot(tester, 'bar');

      // 页面面板、行菜单、改名、删除确认。
      await tap(tester, lbKey('lc-pages-open'));
      expect(lbKey('lc-pages-sheet'), findsOneWidget);
      await shot(tester, 'sheet');
      await tap(tester, lbKey('lc-page-menu-p2'));
      await shot(tester, 'row-menu');
      await tap(tester, find.widgetWithText(PopupMenuItem<String>, '改名'));
      await shot(tester, 'rename');
      await tap(tester, find.widgetWithText(TextButton, '取消'));
      await tap(tester, lbKey('lc-page-menu-p2'));
      await tap(tester, find.widgetWithText(PopupMenuItem<String>, '删除'));
      await shot(tester, 'delete-confirm');
      await tap(tester, find.widgetWithText(TextButton, '取消'));
      await back(tester);
      expect(lbKey('lc-pages-sheet'), findsNothing);

      // 导航项：“点了去”、选页面、同步确认。
      await tap(tester, lbNode('nav'));
      await lbOpenCommon(tester);
      await lbShow(tester, lbKey('lc-items-page-2'));
      await shot(tester, 'nav-items');
      await lbTapShown(tester, lbKey('lc-items-page-1'));
      expect(lbKey('lc-items-page-pick-p1'), findsOneWidget);
      await shot(tester, 'nav-pick');
      await back(tester);
      await lbTapShown(tester, lbKey('lc-nav-share'));
      await shot(tester, 'nav-sync-confirm');
      await tap(tester, find.widgetWithText(TextButton, '取消'));
      await back(tester);

      // 事件页：点击时去页面。
      await tap(tester, lbNode('hello'));
      await tap(tester, find.widgetWithText(TextButton, '逻辑'));
      await lbShow(tester, lbKey('lc-quick-goPage'));
      await shot(tester, 'quick');
      await lbTapShown(tester, lbKey('lc-quick-goPage'));
      await shot(tester, 'quick-pick');
      await tap(tester, lbKey('lc-quick-page-p3'));
      await back(tester);

      // 跨页撤销的提示：换到第二页再撤销，刚才那一步在首页上。
      await tap(tester, lbKey('lc-pages-open'));
      await tap(tester, lbKey('lc-page-row-p2'));
      await tap(tester, find.byTooltip('撤销'));
      expect(find.textContaining('已换到'), findsOneWidget);
      await shot(tester, 'undo-hint');
    });
  }
}
