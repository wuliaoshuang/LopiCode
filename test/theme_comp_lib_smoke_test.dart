// 第四轮 B2 新界面状态的主题冒烟（也是组件库面板的界面测试）：十套内置主题，每套把新界面走一遍——不许抛异常、不许溢出。
//   flutter test --no-pub test/theme_comp_lib_smoke_test.dart
//   LOPI_SHOTS=1 LOPI_SHOT_DIR=<目录> flutter test --no-pub test/theme_comp_lib_smoke_test.dart   # 同时出 themecomp-<主题>-*.png
//
// 覆盖的状态：实例“常用”页多出来的三组（样子、属性跟着状态变、组件的事件）和它们各自的挑选单；组件库面板空的时候；
// “存成一个库”那张表（含写错标识的提示）；库的清单和行尾菜单；导出后的说明；选文件；导入前的预览；看库里的组件；
// 编辑组件页的“事件”表和“变体”表。走的过程中顺带断言：库真的落盘、导出文件真的在、再导入同一个文件预览说“更新”。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/appearance/theme_builtin.dart';
import 'package:lopicode/core/safe_file.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/lowcode/builder_screen.dart';
import 'package:lopicode/lowcode/comp_lib_store.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/state/themes_state.dart';
import 'package:material_ui/material_ui.dart';

import 'support/comp_samples.dart';
import 'support/harness.dart';
import 'support/lowcode_builder.dart';

final String shotDir = Platform.environment['LOPI_SHOT_DIR'] ?? '.tmp/theme-shots';

void main() {
  setUpAll(() async => lbFontsLoaded = await loadRealFonts());

  for (final theme in kBuiltinThemes) {
    Future<void> shot(WidgetTester tester, String page) async {
      expect(tester.takeException(), isNull, reason: '${theme.name} · 组件库 · $page 渲染时出了异常（溢出也算）');
      await lbShot(tester, shotDir, 'themecomp-${theme.id}-$page');
    }

    /// 等到 [f] 出现（读写文件要真等）；最多等 40 轮。
    Future<void> until(WidgetTester tester, Finder f, String what) async {
      for (var i = 0; i < 40 && f.evaluate().isEmpty; i++) {
        await settle(tester, rounds: 1);
      }
      expect(f, findsWidgets, reason: '${theme.name}：等不到 $what');
    }

    Future<void> tap(WidgetTester tester, Finder f) async {
      await until(tester, f, '要点的东西');
      await tester.tap(f.first, warnIfMissed: false);
      // 不用 pumpAndSettle：组件库面板读文件的时候转着圈，那个动画不会自己停。
      await tester.pump();
      await settle(tester, rounds: 4);
    }

    Future<void> back(WidgetTester tester) async {
      await tester.binding.handlePopRoute();
      await tester.pump();
      await settle(tester, rounds: 4);
    }

    Future<void> menu(WidgetTester tester, String label) async {
      await tap(tester, find.byTooltip('更多').last);
      await tap(tester, find.widgetWithText(PopupMenuItem<String>, label));
    }

    testWidgets('${theme.name}：组件的事件 / 变体 / 绑定、组件库面板的每种界面状态', (tester) async {
      usePhoneViewport(tester);
      late TestEnv env;
      late ProjectSession session;
      await tester.runAsync(() async {
        env = await TestEnv.create();
        expect(await env.services.container.read(themesProvider.notifier).select(theme.id), isNull);
        final project = await env.services.projects.create('我的小站', ProjectTemplate.lowcode);
        session = ProjectSession(env.services, project);
        File(session.guard.resolve(kLowcodePageFile)).writeAsStringSync(compUserDoc([productCardDef()]).encode());
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
      await shot(tester, 'canvas');

      // 实例“常用”页多出来的三组
      await tap(tester, lbNode('p1'));
      await lbOpenCommon(tester);
      await lbShow(tester, lbKey('comp-instance-extras'));
      await shot(tester, 'instance-extras');
      await lbTapShown(tester, lbKey('comp-variant-kind'));
      await until(tester, lbKey('comp-variant-pick-hot'), '变体的挑选单');
      await shot(tester, 'variant-pick');
      await back(tester);
      await lbTapShown(tester, lbKey('comp-bind-title'));
      await shot(tester, 'bind-pick');
      await back(tester);
      await lbTapShown(tester, lbKey('comp-event-addCart'));
      await shot(tester, 'event-pick');
      await back(tester);
      await back(tester);

      // 组件库：空的 → 存成一个库（先写错标识）
      await menu(tester, '组件库');
      await until(tester, find.text('项目里还没有组件库'), '空的组件库面板');
      await shot(tester, 'lib-empty');
      await tap(tester, lbKey('complib-new'));
      await tester.enterText(lbKey('complib-form-name'), '商城组件');
      await tester.enterText(lbKey('complib-form-id'), 'Shop');
      await tap(tester, lbKey('complib-form-done'));
      expect(lbKey('complib-form-error'), findsOneWidget);
      await shot(tester, 'lib-form-error');
      await tester.enterText(lbKey('complib-form-id'), 'shuang/shop');
      await tester.enterText(lbKey('complib-form-author'), '霜霜');
      await tap(tester, lbKey('complib-form-done'));
      await until(tester, lbKey('complib-item-shuang/shop'), '存好的库');
      expect(find.textContaining('shuang/shop · 1.0.0 · 1 个组件 · 这个项目做的'), findsOneWidget);
      await shot(tester, 'lib-list');
      late List<CompStoredLib> stored;
      await tester.runAsync(() async => stored = await compLibsRead(session.guard));
      expect(stored.single.ok, isTrue);
      expect(stored.single.lib.defs.single.name, '商品卡片');

      // 行尾菜单 → 导出成文件
      await tap(tester, lbKey('complib-menu-shuang/shop'));
      await shot(tester, 'lib-menu');
      await tap(tester, find.widgetWithText(PopupMenuItem<String>, '导出成文件'));
      await until(tester, find.textContaining('已导出到项目的 exports/组件库-商城组件-1.0.0.lopilib'), '导出后的说明');
      await shot(tester, 'lib-exported');
      await tap(tester, find.widgetWithText(TextButton, '知道了'));
      expect(File(session.guard.resolve('exports/组件库-商城组件-1.0.0.lopilib')).existsSync(), isTrue);

      // 从文件导入：选文件 → 预览（同一个库：说的是“更新”）
      await tap(tester, lbKey('complib-import-open'));
      await until(tester, lbKey('complib-file-exports/组件库-商城组件-1.0.0.lopilib'), '选文件的单子');
      await shot(tester, 'lib-pick-file');
      await tap(tester, lbKey('complib-file-exports/组件库-商城组件-1.0.0.lopilib'));
      await until(tester, lbKey('be-lib-import-sheet'), '导入前的预览（和积木库同一页）');
      expect(find.text('前端'), findsOneWidget, reason: '给谁用那一行');
      expect(find.textContaining('组件（1 个）'), findsOneWidget);
      expect(find.text('更新组件库'), findsOneWidget);
      expect(find.textContaining('没有手写代码'), findsOneWidget);
      expect(find.textContaining('商品卡片'), findsWidgets);
      await shot(tester, 'lib-preview');
      await back(tester);

      // 看里面的组件
      await tap(tester, lbKey('complib-menu-shuang/shop'));
      await tap(tester, find.widgetWithText(PopupMenuItem<String>, '看里面的组件'));
      await until(tester, lbKey('complib-peek'), '库里的组件');
      expect(lbKey('complib-fork-c1'), findsOneWidget);
      await shot(tester, 'lib-peek');
      await back(tester);
      await back(tester);

      // 编辑组件页：事件表、变体表
      await tap(tester, lbNode('p1'));
      await tap(tester, find.byTooltip('更多操作'));
      expect(find.widgetWithText(PopupMenuItem<String>, '存进库…'), findsOneWidget);
      await shot(tester, 'node-menu');
      await tap(tester, find.widgetWithText(PopupMenuItem<String>, '编辑组件'));
      await until(tester, lbKey('comp-editor-done'), '编辑组件页');
      await menu(tester, '事件');
      await until(tester, lbKey('comp-event-row-addCart'), '事件表');
      await shot(tester, 'editor-events');
      // 第四轮 B4：事件的单子里多一行“发出时带上一项数据”，点开是一张单选的单子
      await tap(tester, lbKey('comp-event-row-addCart'));
      await until(tester, lbKey('comp-event-data'), '“发出时带上一项数据”');
      await shot(tester, 'editor-event-menu');
      await tap(tester, lbKey('comp-event-data'));
      await until(tester, lbKey('comp-event-data-price'), '能带出去的东西');
      await shot(tester, 'editor-event-data-pick');
      await tap(tester, lbKey('comp-event-data-price'));
      expect(find.textContaining('带：price'), findsOneWidget);
      await shot(tester, 'editor-events-with-data');
      await back(tester);
      await menu(tester, '变体');
      await until(tester, lbKey('comp-variant-row-kind-hot'), '变体表');
      await shot(tester, 'editor-variants');
      await back(tester);
      await back(tester);
    });
  }
}
