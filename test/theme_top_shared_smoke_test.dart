// 第四轮 B3 新界面状态的主题冒烟：十套内置主题，每套把顶部导航跨页共用的每种界面状态摆一遍——不许抛异常、不许溢出。
//   flutter test --no-pub test/theme_top_shared_smoke_test.dart
//   LOPI_SHOTS=1 LOPI_SHOT_DIR=<目录> flutter test --no-pub test/theme_top_shared_smoke_test.dart   # 同时出 themetop-<主题>-*.png
//
// 覆盖的状态：“以哪一页的为准”的单子、面板里“各页共用”那一块（说明条、三个“这一页用自己的…”开关、这一页不显示、取消共用）、
// 取消共用的确认框、“页面”单子里“不显示顶部导航”的小字和页面 ⋮ 菜单里的新项、“左右按钮换回共用的”确认框。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/appearance/theme_builtin.dart';
import 'package:lopicode/core/safe_file.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/lowcode/builder_screen.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/top_shared.dart';
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
      expect(tester.takeException(), isNull, reason: '${theme.name} · 顶部导航共用 · $page 渲染时出了异常（溢出也算）');
      await lbShot(tester, shotDir, 'themetop-${theme.id}-$page');
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

    testWidgets('${theme.name}：顶部导航跨页共用的每种界面状态', (tester) async {
      usePhoneViewport(tester);
      late TestEnv env;
      late ProjectSession session;
      await tester.runAsync(() async {
        env = await TestEnv.create();
        expect(await env.services.container.read(themesProvider.notifier).select(theme.id), isNull);
        final project = await env.services.projects.create('我的小站', ProjectTemplate.lowcode);
        session = ProjectSession(env.services, project);
        // 第二页顶栏的背景和别的页不一样（改成共用时要问“以哪一页的为准”），右边还放了一个自己的按钮。
        final doc = pagesSample();
        final bar2 = lcTopsIn(doc.pageById('p2')!.root).first;
        bar2.props['bg'] = '#EEF6F1';
        bar2.children.add(
          doc.newNode('button')
            ..props['text'] = '筛选'
            ..more['slot'] = 'right',
        );
        File(session.guard.resolve(kLowcodePageFile)).writeAsStringSync(doc.encode());
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

      // 各页样子不一样：以哪一页的为准
      await tap(tester, lbNode('bar'));
      await lbOpenCommon(tester);
      await lbTapShown(tester, lbKey('lc-top-share'));
      expect(lbKey('lc-top-share-pick'), findsOneWidget);
      await shot(tester, 'pick-base');
      await tap(tester, lbKey('lc-top-share-base-p1'));
      // 共用以后的那一块：说明条、三个开关、两个文字按钮
      await lbShow(tester, lbKey('lc-top-unshare'));
      expect(find.textContaining('各页共用'), findsOneWidget);
      await shot(tester, 'shared-block');
      // 取消共用的确认框（不确认）
      await lbTapShown(tester, lbKey('lc-top-unshare'));
      await shot(tester, 'unshare-confirm');
      await tap(tester, find.widgetWithText(TextButton, '取消'));
      // 这一页不显示
      await lbTapShown(tester, lbKey('lc-top-hide-here'));
      await shot(tester, 'hidden-here');
      await back(tester);
      // “页面”单子和页面的菜单
      await tap(tester, lbKey('lc-pages-open'));
      expect(find.textContaining('· 不显示顶部导航'), findsWidgets);
      await shot(tester, 'pages-sheet');
      await tap(tester, lbKey('lc-page-menu-p1'));
      expect(find.widgetWithText(PopupMenuItem<String>, '这一页显示顶部导航'), findsOneWidget);
      await shot(tester, 'page-menu');
      await back(tester);
      await back(tester);
      // 第二页：左右按钮换回共用的确认框（先放一个自己的按钮才会问）
      await tap(tester, lbKey('lc-pages-open'));
      await tap(tester, lbKey('lc-page-row-p2'));
      await tap(tester, lbNode('bar'));
      await lbOpenCommon(tester);
      await lbShow(tester, lbKey('lc-top-own-slots'));
      expect(tester.widget<Switch>(lbKey('lc-top-own-slots')).value, isTrue);
      await lbTapShown(tester, lbKey('lc-top-own-slots'));
      expect(find.text('左右按钮换回共用的'), findsOneWidget);
      await shot(tester, 'slots-back-confirm');
      await tap(tester, find.widgetWithText(TextButton, '取消'));
      await back(tester);
    });
  }
}
