// “添加 / 编辑渠道”页的步骤流程（真机反馈第二轮第 6 条）：390×844，浅色 + 深色，用本机假模型服务走真实请求。
//   第 1 步填地址和 Key → 第 2 步获取模型（＝连接测试）→ 第 3 步选模型（可单独测试）→ 第 4 步保存。
//   LOPI_SHOTS=1 flutter test test/channel_flow_test.dart   # 同时写截图到 docs/screenshots/06-*.png
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:lopicode/agent/channel_check.dart';
import 'package:lopicode/agent/chat_client.dart';
import 'package:lopicode/agent/model_config.dart';
import 'package:lopicode/agent/protocols.dart';
import 'package:lopicode/agent/provider_presets.dart';
import 'package:lopicode/ui/settings_ai.dart';
import 'package:material_ui/material_ui.dart';

import 'agent_ui_test.dart' show Launcher, waitReal;
import 'screens_test.dart' show shot, fontsLoaded;
import 'support/fake_model_server.dart';
import 'support/harness.dart';

void main() {
  setUpAll(() async => fontsLoaded = await loadRealFonts());
  // 界面测试默认把所有网络请求挡成 400；这里要连本机的假服务，放开（只会连 127.0.0.1）。
  setUp(() => HttpOverrides.global = null);

  test('读模型列表失败：六种原因分开说，各有下一步；报错里出现 Key 就遮掉', () {
    CheckResult of(ModelListFailure k) => modelListFailed(ModelListException(k, '原话 sk-secret-1'), apiKey: 'sk-secret-1', local: false);
    expect(of(ModelListFailure.badKey).title, contains('Key 不能用'));
    expect(of(ModelListFailure.noListEndpoint).title, contains('没有模型列表接口'));
    expect(of(ModelListFailure.noListEndpoint).suggestManual, isTrue);
    expect(of(ModelListFailure.noListEndpoint).advice, contains('手动添加模型 ID'));
    expect(of(ModelListFailure.timeout).title, contains('超时'));
    expect(of(ModelListFailure.unreachable).title, contains('地址不通'));
    expect(of(ModelListFailure.notAList).title, contains('不是模型列表'));
    expect(of(ModelListFailure.other).title, contains('服务返回了错误'));
    final titles = {for (final k in ModelListFailure.values) of(k).title};
    expect(titles.length, ModelListFailure.values.length, reason: '每种原因的说法都不一样');
    for (final k in ModelListFailure.values) {
      expect(of(k).ok, isFalse);
      expect(of(k).detail, isNot(contains('sk-secret-1')));
      expect(of(k).detail, contains('Key 已隐藏'));
    }
    expect(modelListFailed(ChatApiException('接口地址不是合法的网址：abc'), apiKey: '', local: false).title, '接口地址不对');
    expect(modelListFailed(ModelListException(ModelListFailure.timeout, 'x'), apiKey: '', local: true).advice, contains('有没有启动'));
    expect(modelListOk(3).title, '连接正常，读到 3 个模型');
    expect(modelListOk(0).suggestManual, isTrue);
  });

  group('真实请求（本机假服务）', () {
    FakeModelServer? server;
    tearDown(() async => server?.stop());

    Future<ModelListFailure> kindOf(Future<Object?> f) async {
      try {
        await f;
      } on ModelListException catch (e) {
        return e.kind;
      }
      fail('应该失败');
    }

    test('读模型列表：401 / 404 / 连不上 / 超时 各归各的原因', () async {
      server = FakeModelServer([], models: ['m'], requireKey: 'sk-good');
      await server!.start();
      expect(await kindOf(listRemoteModels(protocol: ChatProtocol.openaiChat, baseUrl: server!.baseUrl, apiKey: 'sk-bad')), ModelListFailure.badKey);
      expect((await listRemoteModels(protocol: ChatProtocol.openaiChat, baseUrl: server!.baseUrl, apiKey: 'sk-good')).single.id, 'm');
      expect(await kindOf(listRemoteModels(protocol: ChatProtocol.openaiChat, baseUrl: '${server!.baseUrl}/nope', apiKey: 'sk-good')), ModelListFailure.noListEndpoint);
      final dead = server!.baseUrl;
      await server!.stop();
      server = null;
      expect(await kindOf(listRemoteModels(protocol: ChatProtocol.openaiChat, baseUrl: dead, apiKey: '')), ModelListFailure.unreachable);
      final never = MockClient((_) => throw TimeoutException('x'));
      expect(await kindOf(listRemoteModels(protocol: ChatProtocol.openaiChat, baseUrl: dead, apiKey: '', httpClient: never)), ModelListFailure.timeout);
    });

    test('测一个模型：能对话 / Key 不对 / 连不上，都给结论不抛异常；报错里不带 Key', () async {
      server = FakeModelServer([ScriptedReply(text: '在')], requireKey: 'sk-good');
      await server!.start();
      final m = ModelSpec(id: 'm1');
      final ok = await testModelChat(protocol: ChatProtocol.openaiChat, baseUrl: server!.baseUrl, apiKey: 'sk-good', model: m);
      expect(ok.ok, isTrue);
      final bad = await testModelChat(protocol: ChatProtocol.openaiChat, baseUrl: server!.baseUrl, apiKey: 'sk-bad-key', model: m);
      expect(bad.ok, isFalse);
      expect(bad.detail, contains('401'));
      expect(bad.detail, isNot(contains('sk-bad-key')));
      final dead = server!.baseUrl;
      await server!.stop();
      server = null;
      final down = await testModelChat(protocol: ChatProtocol.openaiChat, baseUrl: dead, apiKey: 'sk-good', model: m);
      expect(down.ok, isFalse);
      expect(down.detail, contains('连不上'));
      expect(down.detail, isNot(contains('sk-good')));
    });
  });

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    final suffix = mode == ThemeMode.light ? 'light' : 'dark';
    late TestEnv env;
    FakeModelServer? server;

    Future<void> boot(WidgetTester tester, {FakeModelServer? fake}) async {
      usePhoneViewport(tester);
      server = fake;
      await tester.runAsync(() async {
        env = await TestEnv.create();
        await fake?.start();
      });
      addTearDown(() async {
        await server?.stop();
        await env.dispose();
      });
    }

    Future<void> open(WidgetTester tester, Widget page) async {
      await tester.pumpWidget(
        appFor(
          env,
          Launcher(key: UniqueKey(), page: page),
          mode: mode,
          font: kTestFont,
        ),
      );
      await settle(tester);
    }

    Future<void> tapKey(WidgetTester tester, String key) async {
      await tester.ensureVisible(find.byKey(Key(key)));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(Key(key)));
      await tester.pump();
    }

    bool enabled(WidgetTester tester, String key) => tester.widget<ButtonStyleButton>(find.byKey(Key(key))).onPressed != null;
    bool sees(String text) => find.textContaining(text).evaluate().isNotEmpty;

    testWidgets('刚进来：四步带序号，没有“测试连接”；没填 Key / 地址时第 2 步置灰并写明还差什么；没有模型也能保存 ($suffix)', (tester) async {
      await boot(tester);
      await open(tester, ChannelEditScreen(preset: presetForBaseUrl('https://api.deepseek.com')));
      for (final title in ['第 1 步 · 填接口地址和 Key', '第 2 步 · 获取模型', '第 3 步 · 选模型（0）', '第 4 步 · 保存']) {
        expect(find.text(title), findsOneWidget);
      }
      expect(find.text('测试连接'), findsNothing, reason: '和“获取模型”是同一个请求，不再单独放按钮');
      expect(enabled(tester, 'channel-fetch'), isFalse);
      expect(find.byKey(const Key('channel-fetch-missing')), findsOneWidget);
      expect(sees('还差 API Key'), isTrue);
      expect(find.byKey(const Key('channel-save-hint')), findsOneWidget);
      await shot(tester, '06-channel-1-enter-$suffix');
      await tester.ensureVisible(find.byKey(const Key('channel-save')));
      await tester.pump(const Duration(milliseconds: 300));
      await shot(tester, '06-channel-1-enter-bottom-$suffix');

      // 填了 Key：第 2 步能点了
      await tester.enterText(find.byKey(const Key('channel-key')), 'sk-typed');
      await tester.pump();
      expect(enabled(tester, 'channel-fetch'), isTrue);
      expect(find.byKey(const Key('channel-fetch-missing')), findsNothing);
      // 地址清空：又置灰，说差的是地址
      await tester.enterText(find.byKey(const Key('channel-url')), '');
      await tester.pump();
      expect(enabled(tester, 'channel-fetch'), isFalse);
      expect(sees('还差接口地址'), isTrue);
      // 本机 / 局域网地址不要 Key
      await tester.enterText(find.byKey(const Key('channel-key')), '');
      await tester.enterText(find.byKey(const Key('channel-url')), 'http://192.168.1.8:11434/v1');
      await tester.pump();
      expect(enabled(tester, 'channel-fetch'), isTrue);

      // 没有模型也能保存（和以前一样，不变严）
      await tester.enterText(find.byKey(const Key('channel-url')), 'https://api.deepseek.com');
      await tapKey(tester, 'channel-save');
      await settle(tester, rounds: 6);
      expect(env.services.models.channels.single.models, isEmpty);
      expect(env.services.models.channels.single.baseUrl, 'https://api.deepseek.com');
    });

    testWidgets('获取成功：显示“连接正常，读到 N 个模型”，接着勾选；按模型测试成功；保存 ($suffix)', (tester) async {
      await boot(
        tester,
        fake: FakeModelServer(
          [ScriptedReply(text: '你好')],
          models: ['model-a', 'model-b', 'model-c'],
          requireKey: 'sk-good',
        ),
      );
      await open(tester, const ChannelEditScreen());
      await tester.enterText(find.byKey(const Key('channel-url')), server!.baseUrl);
      await tester.enterText(find.byKey(const Key('channel-key')), 'sk-good');
      await tester.pump();
      await tapKey(tester, 'channel-fetch');
      await waitReal(tester, () => sees('勾选要用的模型'), what: '勾选面板');
      expect(sees('接口一共有 3 个'), isTrue);
      await tester.tap(find.text('model-b'));
      await tester.pump();
      await tester.tap(find.text('确定'));
      await settle(tester, rounds: 3);
      expect(sees('连接正常，读到 3 个模型'), isTrue);
      expect(find.text('第 3 步 · 选模型（1）'), findsOneWidget);
      expect(find.text('重新获取'), findsOneWidget);
      expect(server!.modelListRequests, 1);
      expect(server!.requests, isEmpty, reason: '获取模型不发对话请求，不花钱');
      await tester.ensureVisible(find.byKey(const Key('model-test-model-b')));
      await tester.pump(const Duration(milliseconds: 300));
      await shot(tester, '06-channel-2-fetched-$suffix');

      // 按模型测试：用户点了才发，一条很短的对话请求
      expect(sees('会花一点点额度'), isTrue);
      await tapKey(tester, 'model-test-model-b');
      await waitReal(tester, () => find.byKey(const Key('model-test-result-model-b')).evaluate().isNotEmpty, what: '测试结果');
      expect(sees('能对话：收到了回复'), isTrue);
      expect(server!.requests.length, 1);
      expect(server!.requests.single['model'], 'model-b');
      expect(server!.requests.single['messages'], [
        {'role': 'user', 'content': 'hi'},
      ]);
      expect(server!.requests.single.containsKey('tools'), isFalse);
      expect(server!.authHeaders.single, 'Bearer sk-good');
      await tester.ensureVisible(find.byKey(const Key('channel-save')));
      await tester.pump(const Duration(milliseconds: 300));
      await shot(tester, '06-channel-3-model-ok-$suffix');
      expect(find.byKey(const Key('channel-save-hint')), findsNothing);

      // 改了 Key：之前的结果不作数
      await tester.enterText(find.byKey(const Key('channel-key')), 'sk-good ');
      await tester.pump();
      expect(find.byKey(const Key('channel-fetch-result')), findsNothing);
      expect(find.byKey(const Key('model-test-result-model-b')), findsNothing);

      await tapKey(tester, 'channel-save');
      await settle(tester, rounds: 6);
      final saved = env.services.models.channels.single;
      expect(saved.models.single.id, 'model-b');
      late String key;
      await tester.runAsync(() async => key = await env.services.models.apiKey(saved.id));
      expect(key.trim(), 'sk-good');
    });

    testWidgets('Key 错（401）：说“Key 不能用”，让回第 1 步；不弹勾选面板，界面上不出现 Key ($suffix)', (tester) async {
      await boot(
        tester,
        fake: FakeModelServer([], models: ['model-a'], requireKey: 'sk-good'),
      );
      await open(tester, const ChannelEditScreen());
      await tester.enterText(find.byKey(const Key('channel-url')), server!.baseUrl);
      await tester.enterText(find.byKey(const Key('channel-key')), 'sk-wrong-key');
      await tester.pump();
      await tapKey(tester, 'channel-fetch');
      await waitReal(tester, () => find.byKey(const Key('channel-fetch-result')).evaluate().isNotEmpty, what: '获取结果');
      expect(sees('Key 不能用：服务拒绝了这个 API Key'), isTrue);
      expect(sees('回第 1 步检查 Key'), isTrue);
      expect(sees('401'), isTrue, reason: '接口原话照实给');
      expect(sees('勾选要用的模型'), isFalse);
      // 输入框里自己填的（遮着的）不算；别的文字里不能出现
      expect(find.byWidgetPredicate((w) => w is Text && (w.data ?? '').contains('sk-wrong-key')), findsNothing);
      await tester.ensureVisible(find.byKey(const Key('channel-fetch-result')));
      await tester.pump(const Duration(milliseconds: 300));
      await shot(tester, '06-channel-4-bad-key-$suffix');
    });

    testWidgets('没有模型列表接口（404）：引导手动添加模型 ID，添加后可以测；模型测不通给接口原话 ($suffix)', (tester) async {
      await boot(
        tester,
        fake: FakeModelServer([ScriptedReply(text: '在的'), ScriptedReply(status: 404, errorBody: '{"error":{"message":"The model `typo-model` does not exist"}}')]),
      );
      await open(tester, const ChannelEditScreen());
      await tester.enterText(find.byKey(const Key('channel-url')), server!.baseUrl);
      await tester.pump();
      expect(enabled(tester, 'channel-fetch'), isTrue, reason: '本机地址不填 Key 也能点');
      await tapKey(tester, 'channel-fetch');
      await waitReal(tester, () => find.byKey(const Key('channel-fetch-result')).evaluate().isNotEmpty, what: '获取结果');
      expect(sees('这个地址没有模型列表接口'), isTrue);
      expect(sees('到第 3 步“手动添加模型 ID”'), isTrue);
      await tester.ensureVisible(find.byKey(const Key('channel-add-manual')));
      await tester.pump(const Duration(milliseconds: 300));
      await shot(tester, '06-channel-5-no-list-$suffix');

      Future<void> addManually(String id) async {
        await tapKey(tester, 'channel-add-manual');
        await settle(tester, rounds: 2);
        await tester.enterText(find.byType(TextField).last, id);
        await tester.tap(find.text('添加'));
        await settle(tester, rounds: 2);
      }

      await addManually('good-model');
      expect(find.text('第 3 步 · 选模型（1）'), findsOneWidget);
      await tapKey(tester, 'model-test-good-model');
      await waitReal(tester, () => find.byKey(const Key('model-test-result-good-model')).evaluate().isNotEmpty, what: '测试结果');
      expect(sees('能对话：收到了回复'), isTrue);

      await addManually('typo-model');
      await tapKey(tester, 'model-test-typo-model');
      await waitReal(tester, () => find.byKey(const Key('model-test-result-typo-model')).evaluate().isNotEmpty, what: '测试结果');
      expect(sees('不能对话'), isTrue);
      expect(sees('does not exist'), isTrue);
      expect(server!.requests.map((r) => r['model']), ['good-model', 'typo-model']);
      await tester.ensureVisible(find.byKey(const Key('channel-save')));
      await tester.pump(const Duration(milliseconds: 300));
      await shot(tester, '06-channel-6-manual-tested-$suffix');
    });

    testWidgets('地址不通：说“地址不通”，和 Key 错、没有接口不是一句话 ($suffix)', (tester) async {
      await boot(tester, fake: FakeModelServer([]));
      final dead = server!.baseUrl;
      await tester.runAsync(() => server!.stop());
      server = null;
      await open(tester, const ChannelEditScreen());
      await tester.enterText(find.byKey(const Key('channel-url')), dead);
      await tester.pump();
      await tapKey(tester, 'channel-fetch');
      await waitReal(tester, () => find.byKey(const Key('channel-fetch-result')).evaluate().isNotEmpty, what: '获取结果');
      expect(sees('地址不通：连不上这个接口地址'), isTrue);
      expect(sees('有没有启动'), isTrue);
    });

    testWidgets('编辑已有渠道：同一套步骤；用已保存的 Key 获取和测试，Key 不回显；没存 Key 的远程渠道第 2 步和“测试”置灰 ($suffix)', (tester) async {
      await boot(
        tester,
        fake: FakeModelServer(
          [ScriptedReply(text: '在')],
          models: ['old-model', 'new-model'],
          requireKey: 'sk-saved',
        ),
      );
      late Channel ch;
      late Channel noKey;
      await tester.runAsync(() async {
        ch = await env.services.models.upsert(
          name: '我的渠道',
          protocol: ChatProtocol.openaiChat,
          baseUrl: server!.baseUrl,
          apiKey: 'sk-saved',
          models: [ModelSpec(id: 'old-model')],
        );
        noKey = await env.services.models.upsert(
          name: '没 Key 的',
          protocol: ChatProtocol.openaiChat,
          baseUrl: 'https://api.example.com/v1',
          models: [ModelSpec(id: 'some-model')],
        );
      });
      await open(tester, ChannelEditScreen(channel: ch));
      for (final title in ['第 1 步 · 填接口地址和 Key', '第 2 步 · 获取模型', '第 3 步 · 选模型（1）', '第 4 步 · 保存']) {
        expect(find.text(title), findsOneWidget);
      }
      expect(find.text('测试连接'), findsNothing);
      expect(tester.widget<TextField>(find.byKey(const Key('channel-key'))).controller!.text, isEmpty);
      expect(find.textContaining('sk-saved'), findsNothing);
      expect(enabled(tester, 'channel-fetch'), isTrue);
      await tester.ensureVisible(find.byKey(const Key('model-test-old-model')));
      await tester.pump(const Duration(milliseconds: 300));
      await shot(tester, '06-channel-7-edit-$suffix');

      await tapKey(tester, 'model-test-old-model');
      await waitReal(tester, () => find.byKey(const Key('model-test-result-old-model')).evaluate().isNotEmpty, what: '测试结果');
      expect(sees('能对话：收到了回复'), isTrue);
      expect(server!.authHeaders.single, 'Bearer sk-saved', reason: '没重新填 Key 就用已保存的');

      await tapKey(tester, 'channel-fetch');
      await waitReal(tester, () => sees('勾选要用的模型'), what: '勾选面板');
      await tester.tap(find.text('new-model'));
      await tester.pump();
      await tester.tap(find.text('确定'));
      await settle(tester, rounds: 3);
      expect(sees('连接正常，读到 2 个模型'), isTrue);
      expect(find.text('第 3 步 · 选模型（2）'), findsOneWidget);
      await tapKey(tester, 'channel-save');
      await settle(tester, rounds: 6);
      expect(env.services.models.channel(ch.id)!.models.map((m) => m.id), ['old-model', 'new-model']);
      late String key;
      await tester.runAsync(() async => key = await env.services.models.apiKey(ch.id));
      expect(key, 'sk-saved', reason: 'Key 留空＝保留原来的');

      // 没存 Key 的远程渠道
      await open(tester, ChannelEditScreen(channel: noKey));
      expect(enabled(tester, 'channel-fetch'), isFalse);
      expect(sees('还差 API Key'), isTrue);
      expect(enabled(tester, 'model-test-some-model'), isFalse);
      expect(find.byKey(const Key('channel-save-hint')), findsNothing);
    });
  }
}
