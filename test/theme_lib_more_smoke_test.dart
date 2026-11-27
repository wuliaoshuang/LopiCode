// 第四轮·A1 新界面的主题冒烟：十套内置主题，每套把新加的状态摆一遍（390×844）——不许抛异常、不许溢出。
//   flutter test --no-pub test/theme_lib_more_smoke_test.dart
//   LOPI_SHOTS=1 LOPI_SHOT_DIR=../preview/front/a1 flutter test --no-pub test/theme_lib_more_smoke_test.dart   # 同时出 a1-<主题>-*.png
//
// 覆盖的状态：设置里“积木库的手写代码”页（关）、打开时的确认框、（开）；新建库的“给谁用”；自带库的面板（复制一份来改）；
// 复制出来的库的面板（用它顶替、它直接用的宿主能力、改库的文字）；改库的文字的文件清单、编辑页（带存不了的原因）；
// 带手写代码的库的导入预览（开关关着／开着并勾上）、看手写代码；“给谁用”对不上的库的面板（开关灰着）。
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/appearance/theme_builtin.dart';
import 'package:lopicode/backend/backend_lib_pack.dart';
import 'package:lopicode/backend/lib_native_trust.dart';
import 'package:lopicode/state/themes_state.dart';
import 'package:lopicode/ui/settings_lib_native.dart';
import 'package:material_ui/material_ui.dart';

import 'support/backend_core_samples.dart';
import 'support/backend_func_blocks.dart';
import 'support/backend_lang_blocks.dart';
import 'support/harness.dart' hide say;
import 'support/lib_ui.dart';
import 'support/native_lib.dart';
import 'support/user_libs.dart';

final bool writeShots = Platform.environment['LOPI_SHOTS'] == '1';
final String shotDir = Platform.environment['LOPI_SHOT_DIR'] ?? '.tmp/theme-shots';
bool fontsLoaded = false;

void main() {
  setUpAll(() async => fontsLoaded = await loadRealFonts());
  setUp(() => LibNativeTrust.instance = LibNativeTrust());
  tearDown(() => LibNativeTrust.instance = LibNativeTrust());

  final front = buildUserLib({
    ...libDoc('只给前端', 'tata/front', blocks: const []),
    'functions': [
      tfn('f1', '甲', [tpar('话', tText)], [ret(pm('话'))], returns: tText),
    ],
    'library': {
      'id': 'tata/front',
      'version': '1.0.0',
      'for': 'frontend',
      'blocks': [
        def(
          'a',
          'call',
          fn: 'f1',
          look: look('甲', '甲 {话}', shape: 'value'),
        ),
      ],
    },
  });

  for (final theme in kBuiltinThemes) {
    final mode = theme.dark ? ThemeMode.dark : ThemeMode.light;

    Future<void> shot(WidgetTester tester, String page) async {
      expect(tester.takeException(), isNull, reason: '${theme.name} · A1 · $page 渲染时出了异常（溢出也算）');
      if (!writeShots || !fontsLoaded) return;
      final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(shotKey));
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        File('$shotDir/a1-${theme.id}-$page.png')
          ..parent.createSync(recursive: true)
          ..writeAsBytesSync(data!.buffer.asUint8List());
      });
    }

    group('${theme.name}（${theme.id}）', () {
      testWidgets('设置里的手写代码开关：关、确认框、开', (tester) async {
        usePhoneViewport(tester);
        late TestEnv env;
        await tester.runAsync(() async {
          env = await TestEnv.create();
          expect(await env.services.container.read(themesProvider.notifier).select(theme.id), isNull);
        });
        addTearDown(() => tester.runAsync(env.dispose));
        await tester.pumpWidget(appFor(env, const LibNativeSettingsScreen(), mode: mode, font: kTestFont));
        await settle(tester);
        await shot(tester, 'native-setting-off');
        await tester.tap(find.byKey(const Key('lib-native-switch')));
        await settle(tester);
        await shot(tester, 'native-setting-confirm');
        await tester.tap(find.text('我明白，打开'));
        await settle(tester);
        await shot(tester, 'native-setting-on');
      });

      testWidgets('库面板里新加的：给谁用、自带库、复制件、改文字、手写代码的预览、给谁用对不上', (tester) async {
        final ui = await openLibUi(
          tester,
          {...flowUserDoc(), 'uses': <J>[], 'hats': <J>[], 'start': <J>[]},
          files: {'手写示例.lopilib': beLibPack(handLibFiles()), for (final e in front.files.entries) 'blocks/tata/front/${e.key}': utf8.encode(e.value)},
          mode: mode,
          font: kTestFont,
          before: (env) async => expect(await env.services.container.read(themesProvider.notifier).select(theme.id), isNull),
        );
        await libTap(tester, 'be-more');
        await libTap(tester, 'be-menu-libs');
        await libUntil(tester, () => lk('be-lib-tata/front').evaluate().isNotEmpty, what: '库的清单');

        // 给谁用对不上的库
        await libTap(tester, 'be-lib-tata/front');
        await shot(tester, 'side-mismatch');
        await tester.tap(lk('be-sheet-done').last);
        await libSettle(tester, rounds: 3);

        // 带手写代码的库：开关关着
        await libTap(tester, 'be-lib-import');
        await libUntil(tester, () => lk('be-lib-import-sheet').evaluate().isNotEmpty, what: '预览');
        await shot(tester, 'import-native-off');
        await libSee(tester, 'be-lib-native-off');
        await shot(tester, 'import-native-off-2');
        await tester.tap(lk('be-sheet-done').last);
        await libSettle(tester, rounds: 3);

        // 开着：勾上
        await tester.runAsync(() => LibNativeTrust.instance.setEnabled(true));
        await libTap(tester, 'be-lib-import');
        await libUntil(tester, () => lk('be-lib-import-sheet').evaluate().isNotEmpty, what: '预览');
        await libTap(tester, 'be-lib-native-native/join.java');
        await shot(tester, 'import-native-code');
        await tester.tap(lk('be-sheet-done').last);
        await libSettle(tester, rounds: 3);
        await libTap(tester, 'be-lib-native-seen');
        await shot(tester, 'import-native-on');
        await tester.tap(lk('be-sheet-done').last);
        await libSettle(tester, rounds: 3);

        // 新建库的“给谁用”
        await libTap(tester, 'be-lib-new');
        await libType(tester, '问好');
        await libType(tester, 'shuang/hello');
        await shot(tester, 'side-ask');
        await tester.tapAt(const Offset(5, 5));
        await libSettle(tester, rounds: 3);

        // 自带库 → 复制一份来改
        await libTap(tester, 'be-lib-builtin');
        await shot(tester, 'builtin');
        await libTap(tester, 'be-lib-builtin-fork');
        await libType(tester, '我的接口服务');
        await libType(tester, 'shuang/svc');
        await libUntil(tester, () => lk('be-lib-sheet-shuang/svc').evaluate().isNotEmpty, what: '复制件的面板');
        await libTap(tester, 'be-lib-replace');
        await shot(tester, 'fork');
        await libTap(tester, 'be-lib-text-open');
        await shot(tester, 'text-files');
        await libTap(tester, 'be-lib-text-modules/service.lc');
        await shot(tester, 'text-page');
        final good = tester.widget<TextField>(lk('be-lib-text-field')).controller!.text;
        await tester.enterText(lk('be-lib-text-field'), '(模块 shuang/svc (函数 坏了');
        await tester.tap(lk('be-lib-text-save'));
        await libUntil(tester, () => lk('be-lib-text-problem').evaluate().isNotEmpty, what: '存不了的原因');
        await shot(tester, 'text-problem');
        await tester.enterText(lk('be-lib-text-field'), good);
        await tester.tap(lk('be-lib-text-check'));
        await libUntil(tester, () => lk('be-lib-text-fine').evaluate().isNotEmpty, what: '检查过了没有问题');
        await shot(tester, 'text-fine');
        expect(ui.screen.host!.doc.serviceLib, 'shuang/svc');
      });
    });
  }
}
