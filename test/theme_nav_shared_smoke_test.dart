// 第四轮 B1 新界面状态的主题冒烟：十套内置主题，每套把底部导航跨页共用的每种界面状态摆一遍——不许抛异常、不许溢出。
//   flutter test --no-pub test/theme_nav_shared_smoke_test.dart
//   LOPI_SHOTS=1 LOPI_SHOT_DIR=<目录> flutter test --no-pub test/theme_nav_shared_smoke_test.dart   # 同时出 themenav-<主题>-*.png
//
// 覆盖的状态：各页不一样时“以哪一页的为准”的单子、改成共用的确认框、面板里“各页共用”那一块（说明条、这一页不显示、取消共用、
// 只给看的当前项）、取消共用的确认框、“页面”单子里“不显示底部导航”的小字和页面 ⋮ 菜单里的新项、
// 平板档“常用”页里样子类的行和标着“不分屏宽”的行（共用的导航栏上）。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/appearance/theme_builtin.dart';
import 'package:lopicode/core/safe_file.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/lowcode/builder_screen.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/model_v3_components.dart';
import 'package:lopicode/lowcode/nav_shared.dart';
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
      expect(tester.takeException(), isNull, reason: '${theme.name} · 底部导航共用 · $page 渲染时出了异常（溢出也算）');
      await lbShot(tester, shotDir, 'themenav-${theme.id}-$page');
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

    testWidgets('${theme.name}：底部导航跨页共用的每种界面状态', (tester) async {
      usePhoneViewport(tester);
      late TestEnv env;
      late ProjectSession session;
      await tester.runAsync(() async {
        env = await TestEnv.create();
        expect(await env.services.container.read(themesProvider.notifier).select(theme.id), isNull);
        final project = await env.services.projects.create('我的小站', ProjectTemplate.lowcode);
        session = ProjectSession(env.services, project);
        // 第二页的导航项和别的页不一样：改成共用时要问“以哪一页的为准”。
        final doc = pagesSample();
        final nav2 = lcNavsIn(doc.pageById('p2')!.root).first;
        nav2.props['items'] = [for (final m in lcObjects(nav2, 'items')) Map<String, dynamic>.of(m)]..[0]['label'] = '主页';
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

      // 各页不一样：以哪一页的为准
      await tap(tester, lbNode('nav'));
      await lbOpenCommon(tester);
      await lbTapShown(tester, lbKey('lc-nav-share'));
      expect(lbKey('lc-nav-share-pick'), findsOneWidget);
      await shot(tester, 'pick-base');
      await tap(tester, lbKey('lc-nav-share-base-p1'));
      // 共用以后的那一块
      await lbShow(tester, lbKey('lc-nav-shared'));
      expect(find.textContaining('各页共用'), findsOneWidget);
      await shot(tester, 'shared-block');
      await lbShow(tester, lbKey('lc-items-current-1'));
      await shot(tester, 'shared-items');
      // 取消共用的确认框（不确认）
      await lbTapShown(tester, lbKey('lc-nav-unshare'));
      await shot(tester, 'unshare-confirm');
      await tap(tester, find.widgetWithText(TextButton, '取消'));
      // 平板档的“常用”页：共用的导航栏上，样子类的行和“不分屏宽”的行
      await back(tester);
      await tap(tester, lbKey('lc-bp-open'));
      await tap(tester, lbKey('lc-bp-tablet'));
      await tap(tester, lbNode('nav'));
      await lbOpenCommon(tester);
      expect(find.text('不分屏宽'), findsWidgets);
      await shot(tester, 'shared-tablet-common');
      await back(tester);
      await tap(tester, lbKey('lc-bp-open'));
      await tap(tester, lbKey('lc-bp-phone'));
      // 这一页不显示
      await tap(tester, lbNode('nav'));
      await lbOpenCommon(tester);
      await lbTapShown(tester, lbKey('lc-nav-hide-here'));
      await shot(tester, 'hidden-here');
      await back(tester);
      // “页面”单子和页面的菜单
      await tap(tester, lbKey('lc-pages-open'));
      expect(find.textContaining('· 不显示底部导航'), findsOneWidget);
      await shot(tester, 'pages-sheet');
      await tap(tester, lbKey('lc-page-menu-p1'));
      expect(find.widgetWithText(PopupMenuItem<String>, '这一页显示底部导航'), findsOneWidget);
      await shot(tester, 'page-menu');
      await back(tester);
      await back(tester);
    });
  }
}
