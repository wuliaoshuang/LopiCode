// 主题在界面上真的生效：设置 › 界面 › 外观 里的“浅色主题 / 深色主题”两行和主题列表页；
// 换一套非默认主题后，界面色、代码高亮、积木色表、终端色都跟着变；字号倍率只动界面字、不动代码字。
//
//   flutter test test/theme_ui_test.dart
//   LOPI_SHOTS=1 flutter test test/theme_ui_test.dart   # 同时写截图到 docs/screenshots/
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/appearance/theme_builtin.dart';
import 'package:lopicode/appearance/theme_json.dart';
import 'package:lopicode/appearance/theme_spec.dart';
import 'package:lopicode/blocks/block_colors.dart';
import 'package:lopicode/blocks/block_script_view.dart';
import 'package:lopicode/core/stores.dart';
import 'package:lopicode/state/themes_state.dart';
import 'package:lopicode/theme/text_scale.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/code_view.dart';
import 'package:lopicode/ui/diff_view.dart';
import 'package:lopicode/ui/settings_pages.dart';
import 'package:lopicode/ui/settings_theme.dart';
import 'package:material_ui/material_ui.dart';

import 'support/harness.dart';

final bool writeShots = Platform.environment['LOPI_SHOTS'] == '1';
bool fontsLoaded = false;

Future<void> shot(WidgetTester tester, String name) async {
  expect(tester.takeException(), isNull, reason: '$name 渲染时出了异常');
  if (!writeShots || !fontsLoaded) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(shotKey));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    File('docs/screenshots/$name.png')
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(data!.buffer.asUint8List());
  });
}

Finder k(String key) => find.byKey(Key(key));

/// 一套一眼就看得出来的主题：每一节都改一两个颜色。
ThemeSpec loud(ThemeSpec base) => base
    .withColors('ui', {UiKey.bg: 0xFF102030, UiKey.canvas: 0xFF203040, UiKey.accent: 0xFFFF00AA, UiKey.accentFill: 0xFFFF00AA, UiKey.snackBg: 0xFF00AA55, UiKey.bubbleMineBg: 0xFF334455})
    .withColors('code', {CodeKey.fg: 0xFF0A0B0C, CodeKey.diffAddBg: 0xFF010203})
    .withColors('terminal', {'red': 0xFF990000})
    .withColors('blocks', {'control': 0xFF123456, BlockKey.selection: 0xFF654321})
    .withToken('keyword', const TokenStyle(color: 0xFF00FF00, bold: true, italic: true));

/// 把当前上下文里的主题记下来。
class Probe extends StatelessWidget {
  const Probe({super.key, required this.onBuild, this.child});
  final void Function(BuildContext) onBuild;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    onBuild(context);
    return child ?? const SizedBox.shrink();
  }
}

void main() {
  setUpAll(() async => fontsLoaded = await loadRealFonts());

  Future<TestEnv> boot(WidgetTester tester, Widget home, {ThemeMode mode = ThemeMode.light}) async {
    usePhoneViewport(tester);
    late TestEnv env;
    await tester.runAsync(() async => env = await TestEnv.create());
    addTearDown(() => tester.runAsync(env.dispose));
    await tester.pumpWidget(appFor(env, home, mode: mode, font: kTestFont));
    await settle(tester, rounds: 2);
    return env;
  }

  /// 新建一套主题、改成 [make] 的样子、选用。
  Future<ThemeSpec> use(WidgetTester tester, TestEnv env, {required bool dark, required ThemeSpec Function(ThemeSpec) make, String name = '试试'}) async {
    late ThemeSpec saved;
    await tester.runAsync(() async {
      final n = env.services.container.read(themesProvider.notifier);
      final created = await n.create(dark: dark, name: name);
      expect(created.ok, isTrue, reason: created.error);
      final failed = await n.save(make(created.theme!));
      expect(failed, isNull);
      expect(await n.select(created.theme!.id), isNull);
      saved = env.services.container.read(themesProvider).byId(created.theme!.id)!;
    });
    await settle(tester, rounds: 2);
    return saved;
  }

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    final dark = mode == ThemeMode.dark;
    final suffix = dark ? 'dark' : 'light';

    group('设置 › 界面 › 外观（$suffix）', () {
      testWidgets('多了“浅色主题 / 深色主题”两行，写着现在用的那套；原来的三行单选和代码字号还在', (tester) async {
        await boot(tester, const AppearanceScreen(), mode: mode);
        expect(k('appearance-system'), findsOneWidget);
        expect(k('appearance-light'), findsOneWidget);
        expect(k('appearance-dark'), findsOneWidget);
        expect(k('appearance-theme-light'), findsOneWidget);
        expect(k('appearance-theme-dark'), findsOneWidget);
        expect(tester.widget<Text>(k('appearance-theme-light-value')).data, '默认浅色');
        expect(tester.widget<Text>(k('appearance-theme-dark-value')).data, '默认深色');
        // 顺序：颜色模式 → 主题 → 代码字号。
        final modeY = tester.getTopLeft(k('appearance-dark')).dy;
        final themeY = tester.getTopLeft(k('appearance-theme-light')).dy;
        expect(themeY, greaterThan(modeY));
        expect(tester.getTopLeft(k('appearance-theme-dark')).dy, greaterThan(themeY));
        await tester.scrollUntilVisible(k('code-font-reset'), 120, scrollable: find.byType(Scrollable).first);
        expect(tester.getTopLeft(k('code-font-reset')).dy, greaterThan(tester.getTopLeft(k('appearance-theme-dark')).dy));
        expect(tester.takeException(), isNull);
      });

      testWidgets('截图：外观页、主题列表页', (tester) async {
        final env = await boot(tester, const AppearanceScreen(), mode: mode);
        await tester.runAsync(() async {
          final n = env.services.container.read(themesProvider.notifier);
          await n.create(dark: dark, name: '海边');
          await n.importText(encodeThemeText(kDefaultLightTheme.copyWith(name: '别人给的', author: () => '闯闯')));
        });
        await settle(tester, rounds: 2);
        await shot(tester, '126-appearance-themes-$suffix');
        await tester.tap(k(dark ? 'appearance-theme-dark' : 'appearance-theme-light'));
        await tester.pumpAndSettle();
        expect(find.byType(ThemePickScreen), findsOneWidget);
        await shot(tester, '126-theme-pick-$suffix');
      });

      testWidgets('点开列表：只列同一种明暗的；点一套立刻生效、整页颜色跟着变；回到外观页那一行写着新名字', (tester) async {
        final env = await boot(tester, const AppearanceScreen(), mode: mode);
        late ThemeSpec mine;
        late ThemeSpec other;
        await tester.runAsync(() async {
          final n = env.services.container.read(themesProvider.notifier);
          mine = (await n.create(dark: dark, name: '我这边的')).theme!;
          await n.save(loud(mine));
          other = (await n.create(dark: !dark, name: '另一边的')).theme!;
        });
        await settle(tester, rounds: 2);

        await tester.tap(k(dark ? 'appearance-theme-dark' : 'appearance-theme-light'));
        await tester.pumpAndSettle();
        expect(find.text(dark ? '深色主题' : '浅色主题'), findsWidgets);
        expect(k('theme-pick-${dark ? kDefaultDarkThemeId : kDefaultLightThemeId}'), findsOneWidget);
        expect(k('theme-pick-${mine.id}'), findsOneWidget);
        expect(k('theme-pick-${other.id}'), findsNothing, reason: '另一种明暗的主题不该出现在这个列表里');
        expect(k('theme-pick-${dark ? kDefaultLightThemeId : kDefaultDarkThemeId}'), findsNothing);
        expect(find.text('内置'), findsOneWidget);
        expect(find.text('自己的'), findsOneWidget);
        expect(k('theme-swatches'), findsOneWidget);

        Color canvasNow() => tester.widget<Scaffold>(find.byType(Scaffold).last).backgroundColor!;
        final before = canvasNow();
        await tester.tap(k('theme-pick-${mine.id}'));
        await settle(tester, rounds: 2);
        await tester.pumpAndSettle();
        expect(env.services.settings.getString(dark ? SettingKeys.themeDark : SettingKeys.themeLight), mine.id);
        expect(canvasNow(), const Color(0xFF203040));
        expect(canvasNow(), isNot(before));
        expect(env.services.settings.getString(dark ? SettingKeys.themeLight : SettingKeys.themeDark, 'unset'), 'unset', reason: '另一个槽没动过');
        await shot(tester, '126-theme-picked-$suffix');

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(tester.widget<Text>(k(dark ? 'appearance-theme-dark-value' : 'appearance-theme-light-value')).data, '我这边的');
        expect(tester.widget<Text>(k(dark ? 'appearance-theme-light-value' : 'appearance-theme-dark-value')).data, dark ? '默认浅色' : '默认深色');

        // 选回默认：颜色回到原样。
        await tester.tap(k(dark ? 'appearance-theme-dark' : 'appearance-theme-light'));
        await tester.pumpAndSettle();
        await tester.tap(k('theme-pick-${dark ? kDefaultDarkThemeId : kDefaultLightThemeId}'));
        await settle(tester, rounds: 2);
        await tester.pumpAndSettle();
        expect(canvasNow(), before);
        expect(tester.takeException(), isNull);
      });
    });

    group('换了主题，各处取到的颜色都是新的（$suffix）', () {
      testWidgets('界面色、ThemeData、代码高亮、改动对比、积木色表', (tester) async {
        BuildContext? ctx;
        final env = await boot(
          tester,
          Scaffold(
            body: Column(
              children: [
                Probe(onBuild: (c) => ctx = c),
                const CodeView(code: 'if (true) return 1;', language: 'dart'),
              ],
            ),
          ),
          mode: mode,
        );
        final base = dark ? kDefaultDarkTheme : kDefaultLightTheme;
        expect(ctx!.themeSpec, same(base));
        expect(BkKit.of(ctx!).palette, same(BkPalette.of(dark: dark)));
        final kitBefore = BkKit.of(ctx!);
        expect(kitBefore.fits(ctx!), isTrue);

        final mine = await use(tester, env, dark: dark, make: loud);
        final c = ctx!;
        expect(c.themeSpec, mine);
        expect(c.colors.bg, const Color(0xFF102030));
        expect(c.colors.accent, const Color(0xFFFF00AA));
        expect(c.colors.bubbleMineBg, const Color(0xFF334455));
        expect(c.colors.surface.toARGB32(), base.ui[UiKey.surface], reason: '没改的还是原来的');
        final theme = Theme.of(c);
        expect(theme.scaffoldBackgroundColor, const Color(0xFF102030));
        expect(theme.colorScheme.primary, const Color(0xFFFF00AA));
        expect(theme.snackBarTheme.backgroundColor, const Color(0xFF00AA55));
        expect(theme.brightness, dark ? Brightness.dark : Brightness.light);
        expect(DiffColors.of(c).addBg, const Color(0xFF010203));
        expect(c.themeSpec.terminalColor('red'), const Color(0xFF990000));

        // 积木：这一类的主色换了，其余几档跟着主色重算；没改的类不变；旧的那套工具认得出“主题变了”。
        final p = BkKit.of(c).palette;
        expect(p.tone('control').fill, const Color(0xFF123456));
        expect(p.tone('control').deep, isNot(BkPalette.of(dark: dark).tone('control').deep));
        expect(p.tone('event').fill.toARGB32(), BkPalette.of(dark: dark).tone('event').fill.toARGB32());
        expect(p.tone('event').edge.toARGB32(), BkPalette.of(dark: dark).tone('event').edge.toARGB32());
        expect(p.selection, const Color(0xFF654321));
        expect(kitBefore.fits(c), isFalse);

        // 代码：普通字用主题的代码文字色；关键字是主题给的颜色 + 粗体 + 斜体。
        final text = tester.widget<SelectableText>(k('code-view-text'));
        expect(text.style!.color, const Color(0xFF0A0B0C));
        TextStyle? keyword;
        text.textSpan!.visitChildren((s) {
          if (s is TextSpan && s.text == 'if') keyword = s.style;
          return true;
        });
        expect(keyword?.color, const Color(0xFF00FF00));
        expect(keyword?.fontWeight, FontWeight.w700);
        expect(keyword?.fontStyle, FontStyle.italic);
        expect(tester.takeException(), isNull);
      });

      testWidgets('形状与密度：圆角 / 间距 / 分隔线粗细倍率进了 ThemeData 和 context.colors', (tester) async {
        BuildContext? ctx;
        final env = await boot(
          tester,
          Scaffold(body: Probe(onBuild: (c) => ctx = c)),
          mode: mode,
        );
        double cardRadius(BuildContext c) => ((Theme.of(c).cardTheme.shape! as RoundedRectangleBorder).borderRadius as BorderRadius).topLeft.x;
        final r0 = cardRadius(ctx!);
        final d0 = Theme.of(ctx!).dividerTheme.thickness;
        await use(
          tester,
          env,
          dark: dark,
          make: (t) => t.withMetric(MetricKey.radiusScale, 2).withMetric(MetricKey.spaceScale, 1.25).withMetric(MetricKey.dividerWidth, 2).withMetric(MetricKey.shadowStrength, 0),
        );
        final c = ctx!;
        expect(cardRadius(c), r0 * 2);
        expect(Theme.of(c).dividerTheme.thickness, (d0 ?? 1) * 2);
        expect(c.colors.radius(Radii.md), Radii.md * 2);
        expect(c.colors.space(Space.x4), Space.x4 * 1.25);
        expect(c.colors.hairline, 2);
        expect(c.colors.shadowOf(0.5).a, 0, reason: '阴影强弱调到 0：阴影全透明');
        expect(c.colors.scrimOf(0.5).a, closeTo(0.5, 0.001), reason: '遮罩不受阴影强弱影响');
      });

      testWidgets('界面字号倍率：界面的字跟着变，代码区域的字不变；默认主题什么都不包', (tester) async {
        BuildContext? uiCtx;
        BuildContext? codeCtx;
        final env = await boot(
          tester,
          Scaffold(
            body: Column(
              children: [
                Probe(onBuild: (c) => uiCtx = c),
                const Text('界面的字', key: Key('ui-text')),
                SystemTextScale(child: Probe(onBuild: (c) => codeCtx = c)),
                const CodeView(code: 'x = 1', language: 'python'),
              ],
            ),
          ),
          mode: mode,
        );
        expect(MediaQuery.textScalerOf(uiCtx!).scale(10), 10);
        expect(MediaQuery.textScalerOf(uiCtx!), isNot(isA<ThemeTextScaler>()), reason: '默认主题倍率是 1：不包任何东西');
        final uiH = tester.getSize(k('ui-text')).height;
        final codeH = tester.getSize(k('code-view-text')).height;

        await use(tester, env, dark: dark, make: (t) => t.withMetric(MetricKey.fontScale, 1.3));
        expect(MediaQuery.textScalerOf(uiCtx!).scale(10), closeTo(13, 0.001));
        expect(MediaQuery.textScalerOf(codeCtx!).scale(10), 10, reason: '代码区域只留系统自己的缩放');
        expect(tester.getSize(k('ui-text')).height, greaterThan(uiH * 1.2));
        expect(tester.getSize(k('code-view-text')).height, codeH, reason: '代码字号是独立的设置，不跟主题的界面字号走');
        expect(tester.takeException(), isNull);
      });
    });
  }

  testWidgets('跟随系统：系统切深色就换成深色槽里那套', (tester) async {
    BuildContext? ctx;
    usePhoneViewport(tester);
    late TestEnv env;
    await tester.runAsync(() async => env = await TestEnv.create());
    addTearDown(() => tester.runAsync(env.dispose));
    late ThemeSpec light;
    late ThemeSpec dark;
    await tester.runAsync(() async {
      final n = env.services.container.read(themesProvider.notifier);
      light = (await n.create(dark: false, name: '白天')).theme!;
      dark = (await n.create(dark: true, name: '夜里')).theme!;
      await n.select(light.id);
      await n.select(dark.id);
    });
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.pumpWidget(
      appFor(
        env,
        Scaffold(body: Probe(onBuild: (c) => ctx = c)),
        mode: ThemeMode.system,
        font: kTestFont,
      ),
    );
    await settle(tester, rounds: 2);
    expect(ctx!.themeSpec.id, light.id);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pumpAndSettle();
    expect(ctx!.themeSpec.id, dark.id);
  });
}
