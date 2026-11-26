// 打包页的主题冒烟：十套内置主题，每套把新打包页的每种状态都摆一遍——不许抛异常、不许溢出；
// 再垫一张背景图片摆一遍（有背景时小标题和说明要垫着底）。
//   flutter test --no-pub test/theme_pack_smoke_test.dart
//   LOPI_SHOTS=1 LOPI_SHOT_DIR=../preview flutter test --no-pub test/theme_pack_smoke_test.dart   # 同时出 pack-<主题>-*.png
//
// 覆盖的状态：本地打包表单（上半、下半）、权限面板、打包进行中、打包完成（产物卡）、打包失败（失败卡）、
// 不适用的项目、签名钥匙页（没有钥匙 / 有钥匙）、GitHub Actions 方式、SSH 构建机方式。
// 打包器是假的（test/support/fake_local_pack.dart），不真打包。
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/apkpack/apk_pack_contract.dart';
import 'package:lopicode/appearance/theme_builtin.dart';
import 'package:lopicode/build/apk_output.dart';
import 'package:lopicode/build/build_screen.dart';
import 'package:lopicode/build/local_pack_backend.dart';
import 'package:lopicode/build/signing_key_screen.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/state/local_pack.dart';
import 'package:lopicode/state/themes_state.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/backdrop_images.dart';
import 'package:lopicode/ui/shell.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import 'support/backdrop_ui_support.dart';
import 'support/fake_local_pack.dart';
import 'support/harness.dart';

final bool writeShots = Platform.environment['LOPI_SHOTS'] == '1';
final String shotDir = Platform.environment['LOPI_SHOT_DIR'] ?? '.tmp/theme-shots';
bool fontsLoaded = false;

void main() {
  setUpAll(() async => fontsLoaded = await loadRealFonts());
  tearDown(BackdropImages.instance.clear);

  for (final theme in kBuiltinThemes) {
    final mode = theme.dark ? ThemeMode.dark : ThemeMode.light;
    late TestEnv env;
    late FakeLocalPackBackend fake;
    late Project project;
    late ProjectSession session;

    Future<void> shot(WidgetTester tester, String page) async {
      expect(tester.takeException(), isNull, reason: '${theme.name} · 打包页 · $page 渲染时出了异常（溢出也算）');
      if (!writeShots || !fontsLoaded) return;
      final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(shotKey));
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        File('$shotDir/pack-${theme.id}-$page.png')
          ..parent.createSync(recursive: true)
          ..writeAsBytesSync(data!.buffer.asUint8List());
      });
    }

    Future<void> boot(WidgetTester tester) async {
      usePhoneViewport(tester);
      fake = FakeLocalPackBackend();
      localPackBackendOverride = fake;
      await tester.runAsync(() async {
        env = await TestEnv.create();
        expect(await env.services.container.read(themesProvider.notifier).select(theme.id), isNull);
        externalFilesDirOverride = () async => p.join(env.tmp.path, 'external');
        project = await env.services.projects.create('我的小站', ProjectTemplate.web);
        session = ProjectSession(env.services, project);
        await session.loadChat();
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      addTearDown(() async {
        await tester.runAsync(() async {
          session.dispose();
          await env.dispose();
        });
        localPackBackendOverride = null;
        externalFilesDirOverride = null;
      });
    }

    Future<void> show(WidgetTester tester) async {
      await tester.pumpWidget(
        appFor(
          env,
          ShellScope(
            openDrawer: () {},
            go: (_) {},
            projectName: '我的小站',
            child: BuildScreen(key: UniqueKey(), session: session),
          ),
          mode: mode,
          font: kTestFont,
        ),
      );
      await settle(tester);
    }

    Future<void> reveal(WidgetTester tester, Finder f) async {
      await tester.scrollUntilVisible(f, 160, scrollable: find.byType(Scrollable).first);
      await tester.ensureVisible(f);
      await tester.pump(const Duration(milliseconds: 300));
    }

    Future<void> tapOn(WidgetTester tester, Finder f, {int rounds = 3}) async {
      await reveal(tester, f);
      await tester.tap(f);
      await settle(tester, rounds: rounds);
    }

    Future<void> toTop(WidgetTester tester) async {
      await tester.drag(find.byType(ListView).first, const Offset(0, 3000));
      await settle(tester, rounds: 2);
    }

    LocalPackState state() => env.services.container.read(localPackProvider(session));

    /// 把打包页的每种状态走一遍，每到一处截一张（[tag] 区分有没有背景图片）。
    Future<void> walk(WidgetTester tester, String tag) async {
      // 这套主题真的用上了
      final colors = tester.element(find.byType(BuildScreen)).colors;
      expect(colors.canvas, theme.uiColor(UiKey.canvas));
      expect(colors.accent, theme.uiColor(UiKey.accent));

      // 本地打包表单：上半、下半
      expect(find.byKey(const Key('pack-app-name')), findsOneWidget);
      await shot(tester, '$tag-form');
      await reveal(tester, find.byKey(const Key('pack-start')));
      await shot(tester, '$tag-form-bottom');
      // 权限面板
      await tapOn(tester, find.byKey(const Key('pack-perm-row')), rounds: 4);
      expect(find.text('相机'), findsOneWidget);
      await shot(tester, '$tag-permissions');
      await tester.binding.handlePopRoute();
      await settle(tester, rounds: 3);

      // 签名钥匙页：还没有钥匙
      await tapOn(tester, find.text('签名钥匙'), rounds: 4);
      expect(find.byType(SigningKeyScreen), findsOneWidget);
      expect(find.text('还没有钥匙'), findsOneWidget);
      await shot(tester, '$tag-key-none');
      await tester.binding.handlePopRoute();
      await settle(tester, rounds: 3);

      // 打包进行中（卡在“压缩”）
      fake
        ..holdAt = ApkPackStep.zip
        ..packGate = Completer<void>();
      await tapOn(tester, find.byKey(const Key('pack-start')), rounds: 5);
      expect(state().phase, LocalPackPhase.packing);
      expect(find.text('正在打包'), findsOneWidget);
      await shot(tester, '$tag-packing');
      // 打包完成
      fake.packGate!.complete();
      await settle(tester, rounds: 6);
      expect(state().phase, LocalPackPhase.done);
      expect(find.text('打包完成'), findsOneWidget);
      await shot(tester, '$tag-done');
      await reveal(tester, find.textContaining('怎么装到手机上'));
      await shot(tester, '$tag-done-bottom');
      // 打包失败
      fake
        ..holdAt = null
        ..packError = const ApkPackException('包名里的“app”这一段是系统保留的，换一个。', field: 'packageName')
        ..packErrorAt = ApkPackStep.manifest;
      await tapOn(tester, find.byKey(const Key('pack-start')), rounds: 6);
      expect(state().phase, LocalPackPhase.failed);
      expect(find.text('打包没成功'), findsOneWidget);
      await shot(tester, '$tag-failed');

      // 两种远程方式
      await toTop(tester);
      await tester.tap(find.byKey(const Key('pack-mode-github')));
      await settle(tester, rounds: 3);
      expect(find.text('① 仓库'), findsOneWidget);
      await shot(tester, '$tag-github');
      await tester.tap(find.byKey(const Key('pack-mode-ssh')));
      await settle(tester, rounds: 3);
      expect(find.text('① 构建机'), findsOneWidget);
      await shot(tester, '$tag-ssh');
      await tester.drag(find.byType(ListView).first, const Offset(0, -3000));
      await settle(tester, rounds: 2);
      await shot(tester, '$tag-ssh-bottom');

      // 签名钥匙页：有钥匙
      await toTop(tester);
      await tester.tap(find.byKey(const Key('pack-mode-local')));
      await settle(tester, rounds: 3);
      await tapOn(tester, find.text('签名钥匙'), rounds: 4);
      expect(find.byType(SigningKeyScreen), findsOneWidget);
      expect(find.text('重新生成钥匙'), findsOneWidget, reason: '第一次打包时已经生成了钥匙');
      await shot(tester, '$tag-key');
    }

    group('${theme.name}（${theme.id}）', () {
      testWidgets('打包页各状态：表单、权限、进行中、完成、失败、GitHub、SSH、钥匙页', (tester) async {
        await boot(tester);
        await show(tester);
        expect(find.byKey(const ValueKey('backdrop-plate')), findsNothing, reason: '没设背景图片：说明和小标题后面不垫东西');
        await walk(tester, 'plain');
      });

      testWidgets('打包页：这个项目不能本地打包', (tester) async {
        await boot(tester);
        await tester.runAsync(() => File(p.join(project.dir, 'pubspec.yaml')).writeAsString('name: demo\n'));
        await show(tester);
        expect(find.text('这个项目不能本地打包'), findsOneWidget);
        await shot(tester, 'plain-not-applicable');
      });

      testWidgets('垫着背景图片的打包页各状态：说明、小标题都垫着底', (tester) async {
        await boot(tester);
        await seedBackdrop(tester, env, scene: true, settings: (s) => s.copyWith(onPages: true)); // 一张图浅色深色共用
        await show(tester);
        expect(find.byKey(const ValueKey('app-backdrop-paint')), findsWidgets, reason: '打包页后面画着背景');
        expect(find.byKey(const ValueKey('backdrop-plate')), findsWidgets, reason: '说明和小标题垫着底');
        await walk(tester, 'bg');
      });
    });
  }
}
