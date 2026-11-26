// 外观页、主题管理页（手机尺寸 390×844）。原在 test/theme_editor_ui_test.dart，2026-11-26 按功能拆出来，断言没变。
//
//   flutter test test/theme_manage_ui_test.dart
//   LOPI_SHOTS=1 flutter test test/theme_manage_ui_test.dart   # 同时写截图到 docs/screenshots/editor-*.png

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/appearance/theme_builtin.dart';
import 'package:lopicode/appearance/theme_generate.dart';
import 'package:lopicode/core/stores.dart';
import 'package:lopicode/ui/settings_code_font.dart';
import 'package:lopicode/ui/settings_pages.dart';
import 'package:lopicode/ui/theme_editor_screen.dart';
import 'package:lopicode/ui/themes_screen.dart';
import 'package:material_ui/material_ui.dart';

import 'support/harness.dart';

import 'support/theme_ui_support.dart';

void main() {
  setUpAll(() async => fontsLoaded = await loadRealFonts());
  useFakeClipboard();

  group('外观页', () {
    testWidgets('顺序：颜色模式 → 主题（含“管理主题”）→ 背景图片 → 代码字号；点“管理主题”进管理页', (tester) async {
      await boot(tester, (_) => const AppearanceScreen());
      expect(k('appearance-themes-manage'), findsOneWidget);
      expect(tester.getTopLeft(k('appearance-themes-manage')).dy, greaterThan(tester.getTopLeft(k('appearance-theme-dark')).dy));
      // 背景图片已经接上（2026-11-26 合并）：一行“背景图片”，排在主题和代码字号之间，右边是当前状态
      expect(k('appearance-background'), findsOneWidget);
      expect(tester.getTopLeft(k('appearance-background')).dy, greaterThan(tester.getTopLeft(k('appearance-themes-manage')).dy));
      expect(tester.getTopLeft(k('appearance-background')).dy, lessThan(tester.getTopLeft(find.byType(CodeFontGroup)).dy));
      expect(find.descendant(of: k('appearance-background'), matching: find.text('未设置')), findsOneWidget);
      await shot(tester, 'appearance-light');
      await tester.tap(k('appearance-themes-manage'));
      await tester.pumpAndSettle();
      expect(find.byType(ThemesScreen), findsOneWidget);
    });
  });

  group('主题管理页', () {
    testWidgets('按浅色 / 深色分开列；点卡片立刻选用；“正在使用”跟着走', (tester) async {
      final env = await boot(tester, (_) => const ThemesScreen());
      final a = await mine(tester, env, name: '海边');
      final d = await mine(tester, env, dark: true, name: '夜里');
      await tester.pumpAndSettle();

      expect(k('themes-card-$kDefaultLightThemeId'), findsOneWidget);
      expect(k('themes-card-${a.id}'), findsOneWidget);
      expect(k('themes-card-${d.id}'), findsNothing, reason: '深色的不在浅色这一段');
      expect(tester.widget<Text>(k('themes-source-$kDefaultLightThemeId')).data, '内置');
      expect(tester.widget<Text>(k('themes-source-${a.id}')).data, '我的');
      expect(k('themes-inuse-$kDefaultLightThemeId'), findsOneWidget);
      expect(k('theme-mini-${a.id}'), findsOneWidget);

      await tester.tap(k('themes-card-${a.id}'));
      await io(tester);
      expect(env.services.settings.getString(SettingKeys.themeLight), a.id);
      expect(k('themes-inuse-${a.id}'), findsOneWidget);
      expect(k('themes-inuse-$kDefaultLightThemeId'), findsNothing);
      await shot(tester, 'themes-light');

      await tester.tap(find.text('深色'));
      await tester.pumpAndSettle();
      expect(k('themes-card-${d.id}'), findsOneWidget);
      expect(k('themes-card-${a.id}'), findsNothing);
      expect(k('themes-inuse-$kDefaultDarkThemeId'), findsOneWidget);
      await tester.tap(k('themes-card-${d.id}'));
      await io(tester);
      expect(env.services.settings.getString(SettingKeys.themeDark), d.id);
      expect(env.services.settings.getString(SettingKeys.themeLight), a.id, reason: '浅色那边选的不受影响');
    });

    testWidgets('深色模式下进来停在深色那一段（截图）', (tester) async {
      final env = await boot(tester, (_) => const ThemesScreen(), mode: ThemeMode.dark);
      await mine(
        tester,
        env,
        dark: true,
        name: '夜里',
        make: (t) => generateTheme(dark: true, tint: 0xFF4B3A7A, accent: 0xFFB388FF, shell: t),
      );
      await tester.pumpAndSettle();
      expect(k('themes-card-$kDefaultDarkThemeId'), findsOneWidget);
      expect(k('themes-card-$kDefaultLightThemeId'), findsNothing);
      await shot(tester, 'themes-dark');
    });

    testWidgets('“⋯”：内置只有看 / 复制一份来改 / 导出；我的有编辑、改名、复制、导出、删除', (tester) async {
      final env = await boot(tester, (_) => const ThemesScreen());
      final a = await mine(tester, env);
      await tester.pumpAndSettle();

      await tester.tap(k('themes-more-$kDefaultLightThemeId'));
      await tester.pumpAndSettle();
      for (final id in ['view', 'copy-edit', 'export']) {
        expect(k('themes-act-$id'), findsOneWidget);
      }
      for (final id in ['edit', 'rename', 'delete', 'copy']) {
        expect(k('themes-act-$id'), findsNothing);
      }
      await shot(tester, 'themes-more-builtin');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      await tester.tap(k('themes-more-${a.id}'));
      await tester.pumpAndSettle();
      for (final id in ['edit', 'rename', 'copy', 'export', 'delete']) {
        expect(k('themes-act-$id'), findsOneWidget);
      }
      await shot(tester, 'themes-more-mine');

      // 改名
      await tester.tap(k('themes-act-rename'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '山里');
      await tester.tap(find.text('改名').last);
      await io(tester);
      expect(viewOf(env).byId(a.id)!.name, '山里');
      expect(find.text('山里'), findsOneWidget);

      // 复制一份
      await tester.tap(k('themes-more-${a.id}'));
      await tester.pumpAndSettle();
      await tester.tap(k('themes-act-copy'));
      await io(tester);
      expect(viewOf(env).user.length, 2);
      expect(viewOf(env).user.map((t) => t.name), contains('山里 副本'));
      expect(find.byType(ThemeEditorScreen), findsNothing, reason: '“复制一份”只复制，不进编辑器');

      // 删除：先取消，再确认；正在用的删了退回默认
      // （内置主题从 2 套变成 10 套以后，这张卡片排到了屏幕底部、被“已复制”的提示条盖住，先滚到看得见的地方再点）
      await tester.ensureVisible(k('themes-card-${a.id}'));
      await tester.pumpAndSettle();
      await tester.tap(k('themes-card-${a.id}'));
      await io(tester);
      expect(env.services.settings.getString(SettingKeys.themeLight), a.id);
      await tester.tap(k('themes-more-${a.id}'));
      await tester.pumpAndSettle();
      await tester.tap(k('themes-act-delete'));
      await tester.pumpAndSettle();
      expect(find.textContaining('这套正在用'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await io(tester);
      expect(viewOf(env).byId(a.id), isNotNull, reason: '点了取消不该删');
      await tester.tap(k('themes-more-${a.id}'));
      await tester.pumpAndSettle();
      await tester.tap(k('themes-act-delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除').last);
      await io(tester);
      expect(viewOf(env).byId(a.id), isNull);
      expect(k('themes-card-${a.id}'), findsNothing);
      expect(viewOf(env).light.id, kDefaultLightThemeId);
      expect(k('themes-inuse-$kDefaultLightThemeId'), findsOneWidget);
    });

    testWidgets('新建主题：先问从哪套开始，复制一份、直接进编辑器；内置的“复制一份来改”也进编辑器', (tester) async {
      final env = await boot(tester, (_) => const ThemesScreen());
      await tester.tap(k('themes-new'));
      await tester.pumpAndSettle();
      expect(k('themes-from-$kDefaultLightThemeId'), findsOneWidget);
      expect(k('themes-from-$kDefaultDarkThemeId'), findsNothing);
      await shot(tester, 'themes-new-from');
      await tester.tap(k('themes-from-$kDefaultLightThemeId'));
      await io(tester);
      expect(find.byType(ThemeEditorScreen), findsOneWidget);
      expect(viewOf(env).user.single.name, '我的浅色主题');
      expect(viewOf(env).user.single.builtin, isFalse);
      expect(k('theme-readonly-banner'), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(ThemeEditorScreen), findsNothing);
      expect(k('themes-card-${viewOf(env).user.single.id}'), findsOneWidget);

      await tester.tap(k('themes-more-$kDefaultLightThemeId'));
      await tester.pumpAndSettle();
      await tester.tap(k('themes-act-copy-edit'));
      await io(tester);
      expect(find.byType(ThemeEditorScreen), findsOneWidget);
      expect(viewOf(env).user.length, 2);
    });
  });
}
