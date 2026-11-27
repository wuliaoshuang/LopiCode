// 没配好模型时的引导弹窗、选择服务商、推开式侧边栏的截图（390×844）。
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/agent/model_config.dart';
import 'package:lopicode/agent/provider_presets.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/ui/model_setup.dart';
import 'package:lopicode/ui/preview_tab.dart';
import 'package:lopicode/ui/project_shell.dart';
import 'package:lopicode/ui/provider_icon.dart';
import 'package:lopicode/ui/settings_ai.dart';
import 'package:lopicode/ui/shell.dart';
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

/// 等 SVG 图标从资源包里读出来（真实的异步读文件）。
Future<void> loadIcons(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUpAll(() async {
    fontsLoaded = await loadRealFonts();
    PreviewTab.debugViewBuilder = (uri) => const ColoredBox(color: Colors.white);
  });
  tearDownAll(() => PreviewTab.debugViewBuilder = null);

  Future<(TestEnv, Project, ProjectSession)> open(WidgetTester tester) async {
    usePhoneViewport(tester);
    late TestEnv env;
    late Project project;
    late ProjectSession session;
    await tester.runAsync(() async {
      env = await TestEnv.create();
      env.services.modelSetupPrompted = false; // 这里就是要测它
      project = await env.services.projects.create('我的小站', ProjectTemplate.web);
      session = ProjectSession(env.services, project);
      await session.loadChat();
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    addTearDown(() async {
      session.dispose();
      await env.dispose();
    });
    return (env, project, session);
  }

  /// 弹窗里要查安全存储（真实异步），多给几轮。
  Future<void> waitDialog(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await settle(tester, rounds: 4);
  }

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    final suffix = mode == ThemeMode.light ? 'light' : 'dark';

    testWidgets('没有渠道：进聊天页弹一次引导；点“稍后”后不再自动弹，点发送才再提示；“去配置”进选择服务商 ($suffix)', (tester) async {
      final (env, project, session) = await open(tester);
      await tester.pumpWidget(
        appFor(
          env,
          ProjectShell(project: project, session: session),
          mode: mode,
          font: kTestFont,
        ),
      );
      await waitDialog(tester);

      final dialog = find.byKey(const Key('model-setup-dialog'));
      expect(dialog, findsOneWidget, reason: '没有任何渠道，进聊天页要弹引导');
      expect(find.text('还没有配置模型'), findsOneWidget);
      expect(find.text('稍后'), findsOneWidget);
      expect(find.text('去配置'), findsOneWidget);
      await shot(tester, '90-model-setup-dialog-$suffix');

      await tester.tap(find.text('稍后'));
      await waitDialog(tester);
      expect(dialog, findsNothing);
      expect(env.services.modelSetupPrompted, isTrue);

      // 切走再切回来：不再自动弹
      await tester.tap(find.byKey(const ValueKey('nav-1')));
      await settle(tester, rounds: 6);
      await tester.tap(find.byKey(const ValueKey('nav-0')));
      await waitDialog(tester);
      expect(dialog, findsNothing, reason: '点过“稍后”，这次运行不再自动弹');

      // 点发送：再提示，消息不发出去，输入的字还在
      await tester.enterText(find.byType(TextField).hitTestable().first, '帮我做个主页');
      await settle(tester, rounds: 2);
      await tester.tap(find.byTooltip('发送'));
      await waitDialog(tester);
      expect(dialog, findsOneWidget, reason: '没模型时点发送要提示');
      expect(session.chat, isEmpty, reason: '没有可用模型，消息不该发出去');
      expect(session.agentBusy, isFalse);

      await tester.tap(find.text('去配置'));
      await waitDialog(tester);
      await loadIcons(tester);
      expect(find.byType(ProviderPickerScreen), findsOneWidget, reason: '一个渠道都没有：直接进“选择服务商”');
      expect(find.text('选择服务商'), findsOneWidget);
      await shot(tester, '91-provider-picker-$suffix');

      await tester.binding.handlePopRoute();
      await waitDialog(tester);
      expect(find.widgetWithText(TextField, '帮我做个主页'), findsOneWidget, reason: '输入的字留着');
    });

    testWidgets('选服务商 → 名称、协议、地址自动填好，只填 Key 就能保存；保存后回到渠道列表并带图标 ($suffix)', (tester) async {
      usePhoneViewport(tester);
      late TestEnv env;
      await tester.runAsync(() async => env = await TestEnv.create());
      addTearDown(env.dispose);
      await tester.pumpWidget(appFor(env, const ChannelsScreen(), mode: mode, font: kTestFont));
      await settle(tester);

      await tester.tap(find.text('添加渠道'));
      await settle(tester, rounds: 6);
      await loadIcons(tester);
      final list = find.byKey(const Key('provider-list'));
      expect(list, findsOneWidget);
      // 每个预设都有一行，最后是“自定义”
      for (final preset in kProviderPresets) {
        await tester.scrollUntilVisible(
          find.byKey(ValueKey('preset-${preset.id}')),
          200,
          scrollable: find.descendant(of: list, matching: find.byType(Scrollable)).first,
        );
        expect(find.descendant(of: find.byKey(ValueKey('preset-${preset.id}')), matching: find.text(preset.name)), findsOneWidget);
        expect(find.byKey(ValueKey('provider-icon-${preset.id}')), findsOneWidget, reason: '${preset.name} 要有图标');
      }
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('preset-custom')),
        200,
        scrollable: find.descendant(of: list, matching: find.byType(Scrollable)).first,
      );
      expect(find.text('自定义'), findsOneWidget);
      await loadIcons(tester);
      await shot(tester, '92-provider-picker-bottom-$suffix');

      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('preset-deepseek')),
        -200,
        scrollable: find.descendant(of: list, matching: find.byType(Scrollable)).first,
      );
      await tester.ensureVisible(find.byKey(const ValueKey('preset-deepseek')));
      await settle(tester, rounds: 2);
      await tester.tap(find.byKey(const ValueKey('preset-deepseek')));
      await settle(tester, rounds: 6);
      await loadIcons(tester);
      expect(find.text('添加渠道'), findsOneWidget);
      expect(tester.widget<TextField>(find.byKey(const Key('channel-url'))).controller!.text, 'https://api.deepseek.com');
      expect(find.widgetWithText(TextField, 'DeepSeek'), findsOneWidget, reason: '名称已填好');
      expect(tester.widget<ProviderIcon>(find.byKey(const Key('channel-icon'))).preset?.id, 'deepseek');
      expect(tester.widget<TextField>(find.byKey(const Key('channel-key'))).controller!.text, isEmpty);
      await shot(tester, '93-channel-from-preset-$suffix');

      // 把地址改成中转站：图标退回通用的
      await tester.enterText(find.byKey(const Key('channel-url')), 'https://relay.example.com/v1');
      await settle(tester, rounds: 2);
      expect(tester.widget<ProviderIcon>(find.byKey(const Key('channel-icon'))).preset, isNull);
      await tester.enterText(find.byKey(const Key('channel-url')), 'https://api.deepseek.com');
      await settle(tester, rounds: 2);

      await tester.enterText(find.byKey(const Key('channel-key')), 'sk-test-123');
      await tester.ensureVisible(find.byKey(const Key('channel-save')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const Key('channel-save')));
      await waitUntil(tester, () => env.services.models.channels.isNotEmpty && find.byType(ProviderPickerScreen).evaluate().isEmpty, '渠道存好并回到渠道列表');
      await settle(tester, rounds: 4);
      await loadIcons(tester);

      expect(find.byType(ProviderPickerScreen), findsNothing, reason: '保存后一路回到渠道列表');
      expect(find.byType(ChannelsScreen), findsOneWidget);
      final ch = env.services.models.channels.single;
      expect(ch.name, 'DeepSeek');
      expect(ch.protocol, ChatProtocol.openaiChat);
      expect(ch.baseUrl, 'https://api.deepseek.com');
      late String key;
      await tester.runAsync(() async => key = await env.services.models.apiKey(ch.id));
      expect(key, 'sk-test-123');
      expect(find.byKey(const ValueKey('provider-icon-deepseek')), findsOneWidget, reason: '渠道列表里带图标');
      await shot(tester, '94-channels-with-icons-$suffix');
    });

    testWidgets('选“自定义”走原来的手填；选 Ollama 提示不用填 Key；返回不保存则留在选择页 ($suffix)', (tester) async {
      usePhoneViewport(tester);
      late TestEnv env;
      await tester.runAsync(() async => env = await TestEnv.create());
      addTearDown(env.dispose);
      await tester.pumpWidget(appFor(env, const ProviderPickerScreen(), mode: mode, font: kTestFont));
      await settle(tester);
      final scroll = find.descendant(of: find.byKey(const Key('provider-list')), matching: find.byType(Scrollable)).first;

      await tester.scrollUntilVisible(find.byKey(const ValueKey('preset-custom')), 200, scrollable: scroll);
      await tester.ensureVisible(find.byKey(const ValueKey('preset-custom')));
      await settle(tester, rounds: 2);
      await tester.tap(find.byKey(const ValueKey('preset-custom')));
      await settle(tester, rounds: 6);
      expect(tester.widget<TextField>(find.byKey(const Key('channel-url'))).controller!.text, isEmpty);
      expect(tester.widget<ProviderIcon>(find.byKey(const Key('channel-icon'))).preset, isNull);
      await tester.binding.handlePopRoute();
      await settle(tester, rounds: 6);
      expect(find.byType(ProviderPickerScreen), findsOneWidget, reason: '没保存：留在选择页');
      expect(env.services.models.channels, isEmpty);

      await tester.scrollUntilVisible(find.byKey(const ValueKey('preset-ollama')), 200, scrollable: scroll);
      await tester.ensureVisible(find.byKey(const ValueKey('preset-ollama')));
      await settle(tester, rounds: 2);
      await tester.tap(find.byKey(const ValueKey('preset-ollama')));
      await settle(tester, rounds: 6);
      await loadIcons(tester);
      expect(tester.widget<TextField>(find.byKey(const Key('channel-url'))).controller!.text, 'http://localhost:11434/v1');
      expect(find.textContaining('localhost 指的是这台手机自己'), findsOneWidget);
      expect(find.text('本机服务可以不填'), findsOneWidget);
      await shot(tester, '95-channel-ollama-$suffix');
    });

    testWidgets('有渠道但没 Key：点发送提示缺 Key，“去配置”直接进那个渠道的编辑页 ($suffix)', (tester) async {
      final (env, project, session) = await open(tester);
      late Channel ch;
      await tester.runAsync(() async {
        ch = await env.services.models.upsert(
          name: 'DeepSeek',
          protocol: ChatProtocol.openaiChat,
          baseUrl: 'https://api.deepseek.com',
          models: [ModelSpec(id: 'deepseek-chat')],
        );
      });
      env.services.modelSetupPrompted = true; // 只测“点发送”这条路
      await tester.pumpWidget(
        appFor(
          env,
          ProjectShell(project: project, session: session),
          mode: mode,
          font: kTestFont,
        ),
      );
      await waitDialog(tester);
      expect(find.byKey(const Key('model-setup-dialog')), findsNothing);

      await tester.enterText(find.byType(TextField).hitTestable().first, '你好');
      await settle(tester, rounds: 2);
      await tester.tap(find.byTooltip('发送'));
      await waitDialog(tester);
      expect(find.text('还没有填 API Key'), findsOneWidget);
      expect(session.chat, isEmpty);
      await tester.tap(find.text('去配置'));
      await waitDialog(tester);
      expect(find.text('编辑渠道'), findsOneWidget);
      expect(tester.widget<ChannelEditScreen>(find.byType(ChannelEditScreen)).channel?.id, ch.id);
    });

    testWidgets('截图：推开式侧边栏 ($suffix)', (tester) async {
      final (env, project, session) = await open(tester);
      env.services.modelSetupPrompted = true;
      await tester.pumpWidget(
        appFor(
          env,
          ProjectShell(project: project, session: session),
          mode: mode,
          font: kTestFont,
        ),
      );
      await settle(tester);
      await tester.tap(find.byTooltip('打开侧边栏').hitTestable());
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await settle(tester, rounds: 3);
      expect(find.byType(AppDrawer), findsOneWidget);
      await shot(tester, '96-push-drawer-$suffix');
    });
  }
}
