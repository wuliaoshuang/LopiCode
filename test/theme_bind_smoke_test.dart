// 状态与数据绑定（编辑器第 5 期）界面的主题冒烟：十套内置主题，每套把这一段新加的每种界面状态都摆一遍——不许抛异常、不许溢出。
//   flutter test --no-pub test/theme_bind_smoke_test.dart
//   LOPI_SHOTS=1 LOPI_SHOT_DIR=../preview/editor/b3 flutter test --no-pub test/theme_bind_smoke_test.dart   # 同时出 bind-<主题>-*.png
//
// 覆盖的状态：画布按初值预览（绑的文字、重复的几份和角标、条件不成立的调淡）、面板里没绑的行（链环）和绑着的行（药丸）、
// “数据”一节（跟状态同步、重复、显示条件、更多绑定里的存在条件 / 类名开关 / 样式）、挑值的单子（用一个值、拼一段文字、写错了、比较、空状态）、
// 新建状态的对话框、重复的设置单子、样式页的“显示”开关（隐藏着）、“状态”页（单子、行菜单、哪里在用、改一个、删除确认、空页）。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/appearance/theme_builtin.dart';
import 'package:lopicode/core/safe_file.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/lowcode/builder_screen.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/state/themes_state.dart';
import 'package:material_ui/material_ui.dart';

import 'support/bind_sample.dart';
import 'support/harness.dart';
import 'support/lowcode_builder.dart';

final String shotDir = Platform.environment['LOPI_SHOT_DIR'] ?? '.tmp/theme-shots';

void main() {
  setUpAll(() async => lbFontsLoaded = await loadRealFonts());

  for (final theme in kBuiltinThemes) {
    Future<void> shot(WidgetTester tester, String page) async {
      expect(tester.takeException(), isNull, reason: '${theme.name} · 状态与绑定 · $page 渲染时出了异常（溢出也算）');
      await lbShot(tester, shotDir, 'bind-${theme.id}-$page');
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

    Future<void> open(WidgetTester tester, String? raw) async {
      usePhoneViewport(tester);
      late TestEnv env;
      late ProjectSession session;
      await tester.runAsync(() async {
        env = await TestEnv.create();
        expect(await env.services.container.read(themesProvider.notifier).select(theme.id), isNull);
        final project = await env.services.projects.create('我的小站', ProjectTemplate.lowcode);
        session = ProjectSession(env.services, project);
        if (raw != null) File(session.guard.resolve(kLowcodePageFile)).writeAsStringSync(raw);
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
    }

    Future<void> menu(WidgetTester tester, String item) async {
      await tap(tester, find.byTooltip('更多'));
      await tap(tester, find.widgetWithText(PopupMenuItem<String>, item));
    }

    testWidgets('${theme.name}：状态与绑定的每种界面状态', (tester) async {
      await open(tester, bindSample().encode());
      // 画布：按初值预览（绑的文字、重复、条件不成立）
      await shot(tester, 'canvas');

      // 面板：没绑的行（行尾链环）、“数据”一节
      await tap(tester, lbNode('toCart'));
      await lbOpenCommon(tester);
      expect(lbKey('lc-bind-text'), findsOneWidget);
      await shot(tester, 'panel-unbound');
      // 挑值的单子：用一个值 / 拼一段文字
      await lbTapShown(tester, lbKey('lc-bind-text'));
      await shot(tester, 'picker-value');
      await tap(tester, lbKey('lc-bind-mode-template'));
      await shot(tester, 'picker-template');
      await tester.enterText(lbKey('lc-bind-template'), '你好 {nobody}');
      await tap(tester, lbKey('lc-bind-use'));
      expect(lbKey('lc-bind-error'), findsOneWidget);
      await shot(tester, 'picker-template-bad');
      await back(tester);
      await back(tester);

      // 绑着的行（药丸）＋输入框的“跟状态同步”
      await tap(tester, lbNode('hello'));
      await lbOpenCommon(tester);
      expect(lbKey('lc-bound-text'), findsOneWidget);
      await shot(tester, 'panel-bound');
      await back(tester);
      await tap(tester, lbNode('kw'));
      await lbOpenCommon(tester);
      await lbShow(tester, lbKey('lc-bound-model'));
      await shot(tester, 'panel-model');
      await back(tester);

      // 条件、类名开关、样式（“更多绑定”展开着）＋比较的单子
      await tap(tester, lbNode('submit'));
      await lbOpenCommon(tester);
      await lbShow(tester, lbKey('lc-data-add-style'));
      await shot(tester, 'panel-more');
      await lbTapShown(tester, lbKey('lc-data-showIf'));
      await tap(tester, lbKey('lc-bind-mode-compare'));
      await shot(tester, 'picker-compare');
      await back(tester);
      await back(tester);

      // 重复：药丸、设置单子
      await tap(tester, lbNode('rowItem').first);
      await lbOpenCommon(tester);
      await lbShow(tester, lbKey('lc-bound-repeat'));
      await shot(tester, 'panel-repeat');
      await lbTapShown(tester, lbKey('lc-bound-repeat'));
      await shot(tester, 'repeat-sheet');
      await back(tester);

      // 样式页“显示”开关
      await tap(tester, find.text('样式').last);
      await lbTapShown(tester, lbKey('lc-tab-layout'));
      await lbTapShown(tester, lbKey('lc-style-visible'));
      await shot(tester, 'style-hidden');
      await lbTapShown(tester, lbKey('lc-style-visible'));
      await back(tester);

      // “状态”页：单子、菜单、哪里在用、改一个、删除确认
      await menu(tester, '状态');
      await shot(tester, 'state-list');
      await tap(tester, lbKey('lc-state-menu-l-count'));
      await shot(tester, 'state-menu');
      await tap(tester, find.text('看哪里在用'));
      await shot(tester, 'state-uses');
      await back(tester);
      await tap(tester, lbKey('lc-state-row-l-names'));
      await shot(tester, 'state-edit');
      await back(tester);
      await tap(tester, lbKey('lc-state-menu-l-count'));
      await tap(tester, find.text('删除').last);
      await shot(tester, 'state-delete-confirm');
      await tap(tester, find.widgetWithText(TextButton, '取消'));
      await back(tester);
      expect(lbKey('lc-bp-open'), findsOneWidget);
    });

    testWidgets('${theme.name}：还没有状态的空页、挑值单子的空状态', (tester) async {
      await open(tester, null);
      await menu(tester, '状态');
      expect(lbKey('lc-state-first'), findsOneWidget);
      await shot(tester, 'state-empty');
      await back(tester);
      await tap(tester, lbNode('n1'));
      await lbOpenCommon(tester);
      await lbTapShown(tester, lbKey('lc-bind-text'));
      expect(lbKey('lc-bind-new-first'), findsOneWidget);
      await shot(tester, 'picker-empty');
      await tap(tester, lbKey('lc-bind-new-first'));
      await shot(tester, 'new-state');
      await back(tester);
      await back(tester);
    });
  }
}
