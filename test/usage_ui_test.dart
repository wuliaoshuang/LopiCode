// 用量与额度的界面（390×844，浅色 + 深色）：回合脚注 → 本轮轨迹 → 步骤详情；上下文小环 → 用量弹层（含 DeepSeek 余额卡）；
// 低余额小提示；到上限后的拦截提示；设置顶部卡的三种样子；额度上限页；项目规则页；两个开关。
//   LOPI_SHOTS=1 flutter test test/usage_ui_test.dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lopicode/agent/chat_client.dart';
import 'package:lopicode/agent/model_config.dart';
import 'package:lopicode/agent/quota.dart';
import 'package:lopicode/agent/usage.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/stores.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/project_shell.dart';
import 'package:lopicode/ui/settings_quota.dart';
import 'package:lopicode/ui/settings_screen.dart';
import 'package:lopicode/ui/shell.dart';
import 'package:lopicode/ui/usage_ui.dart';
import 'package:material_ui/material_ui.dart';

import 'screens_test.dart' show shot, fontsLoaded;
import 'support/harness.dart';

class Bal {
  double cny = 100;
  bool available = true;
  int status = 200;
  http.Client get client => MockClient((req) async {
    if (status != 200) return http.Response('{}', status);
    return http.Response(
      jsonEncode({
        'is_available': available,
        'balance_infos': [
          {'currency': 'CNY', 'total_balance': cny.toStringAsFixed(2), 'granted_balance': '2.00', 'topped_up_balance': (cny - 2).toStringAsFixed(2)},
        ],
      }),
      200,
    );
  });
}

TokenUsage u(int miss, int hit, int out, {int? think}) => TokenUsage(uncached: miss, cacheRead: hit, output: out, reasoning: think, hasCache: true);

void main() {
  setUpAll(() async => fontsLoaded = await loadRealFonts());

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    final suffix = mode == ThemeMode.light ? 'light' : 'dark';
    const font = kTestFont;

    late TestEnv env;
    late Project project;
    late ProjectSession session;
    late Bal bal;
    late Channel ds;

    Future<void> boot(WidgetTester tester, {List<List<ChatDelta>> script = const [], bool deepseek = true, bool priced = true}) async {
      usePhoneViewport(tester);
      bal = Bal();
      await tester.runAsync(() async {
        env = await TestEnv.create(chatClient: () => ScriptedChatClient(script), quotaHttp: bal.client);
        ds = await env.services.models.upsert(
          name: deepseek ? 'DeepSeek' : '我的中转站',
          protocol: ChatProtocol.openaiChat,
          baseUrl: deepseek ? 'https://api.deepseek.com' : 'https://relay.example.cn/v1',
          apiKey: 'sk-test',
          models: [ModelSpec(id: 'deepseek-chat', contextLength: 128000, priceHit: priced ? 0.5 : null, priceMiss: priced ? 2 : null, priceOutput: priced ? 8 : null)],
        );
        project = await env.services.projects.create('我的小站', ProjectTemplate.web);
        session = ProjectSession(env.services, project);
        await session.loadChat();
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      addTearDown(() async {
        session.dispose();
        env.dispose();
      });
    }

    Future<void> showChat(WidgetTester tester) async {
      await tester.pumpWidget(appFor(env, ProjectShell(project: project, session: session, initial: ShellDest.chat), mode: mode, font: font));
      await settle(tester);
    }

    Future<void> send(WidgetTester tester, String text) async {
      await tester.runAsync(() => session.sendToAgent(text).timeout(const Duration(seconds: 20)));
      await settle(tester, rounds: 3);
    }

    final toolTurn = <List<ChatDelta>>[
      [
        say('我先把几个文件都看一遍。'),
        call(0, 'list_files', '{}'),
        call(1, 'read_file', '{"path":"index.html"}'),
        call(2, 'read_file', '{"path":"style.css"}'),
        call(3, 'read_file', '{"path":"script.js"}'),
        ChatDelta(finishReason: 'tool_calls', usage: u(9000, 0, 120, think: 40)),
      ],
      [say('看完了：一个页面、一份样式、一段脚本，结构很清楚。'), ChatDelta(finishReason: 'stop', usage: u(1800, 9000, 260))],
    ];

    testWidgets('脚注 → 本轮轨迹 → 步骤详情 ($suffix)', (tester) async {
      await boot(tester, script: toolTurn);
      await showChat(tester);
      expect(find.byKey(const Key('turn-footnote')), findsNothing);
      await send(tester, '看看项目里有什么');

      final foot = find.byKey(const Key('turn-footnote'));
      expect(foot, findsOneWidget);
      final text = tester.widget<Text>(find.byKey(const Key('turn-footnote-text'))).data!;
      expect(text, allOf(contains('秒'), contains('2 步'), contains('约 ¥0.03'), contains('20.2K tokens')));
      // 脚注在这一轮回复的下方
      expect(tester.getTopLeft(foot).dy, greaterThan(tester.getTopLeft(find.textContaining('看完了：一个页面')).dy));
      await shot(tester, '70-chat-footnote-$suffix');

      await tester.tap(foot);
      await settle(tester, rounds: 3);
      expect(find.text('本轮轨迹'), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('traj-summary'))).data, allOf(contains('20.2K tokens'), contains('缓存命中 45%'), contains('2 次请求'), contains('推理 40')));
      expect(find.byKey(const Key('traj-request-1')), findsOneWidget);
      expect(find.byKey(const Key('traj-request-2')), findsOneWidget);
      // 连续 4 次已结束的工具调用折成一组
      expect(find.byKey(const Key('traj-group')), findsOneWidget);
      expect(find.textContaining('4 次工具调用'), findsOneWidget);
      expect(find.byKey(const Key('traj-tool-call_read_file_1')), findsNothing);
      await shot(tester, '71-trajectory-$suffix');
      await tester.tap(find.byKey(const Key('traj-group')));
      await settle(tester, rounds: 2);
      expect(find.byKey(const Key('traj-tool-call_read_file_1')), findsOneWidget);
      await shot(tester, '72-trajectory-open-$suffix');

      // 某次请求的详情
      await tester.tap(find.byKey(const Key('traj-request-2')));
      await settle(tester, rounds: 10);
      expect(find.byType(RequestStepPage), findsOneWidget);
      expect(find.text('模型请求 2'), findsWidgets);
      expect(tester.widget<Text>(find.byKey(const Key('step-hit'))).data, contains('9K'));
      expect(tester.widget<Text>(find.byKey(const Key('step-miss'))).data, contains('1.8K'));
      expect(find.byKey(const Key('step-no-usage')), findsNothing);
      await shot(tester, '73-step-request-$suffix');
      await tester.tap(find.byTooltip('返回').last);
      await settle(tester, rounds: 8);

      // 某次工具调用的详情：参数、结果
      await tester.tap(find.byKey(const Key('traj-tool-call_read_file_1')));
      await settle(tester, rounds: 10);
      expect(find.byKey(const Key('step-args')), findsOneWidget);
      expect(find.byKey(const Key('step-result')), findsOneWidget);
      expect(find.textContaining('index.html'), findsWidgets);
      await shot(tester, '74-step-tool-$suffix');
    });

    testWidgets('接口没返回用量：脚注和详情如实写；关掉开关就不显示脚注 ($suffix)', (tester) async {
      await boot(tester, script: [[say('好的。'), ChatDelta(finishReason: 'stop')]], deepseek: false, priced: false);
      await showChat(tester);
      await send(tester, '你好');
      final text = tester.widget<Text>(find.byKey(const Key('turn-footnote-text'))).data!;
      expect(text, contains('接口没返回用量'));
      expect(text, isNot(contains('¥')));
      await tester.tap(find.byKey(const Key('turn-footnote')));
      await settle(tester, rounds: 3);
      await tester.tap(find.byKey(const Key('traj-request-1')));
      await settle(tester, rounds: 10);
      expect(find.byKey(const Key('step-no-usage')), findsOneWidget);
      await shot(tester, '75-step-no-usage-$suffix');
      await tester.tap(find.byTooltip('返回').last);
      await settle(tester, rounds: 8);
      await tester.tapAt(const Offset(195, 40));
      await settle(tester, rounds: 3);

      await tester.runAsync(() => env.services.settings.set(SettingKeys.chatUsage, false));
      env.services.touch();
      await settle(tester, rounds: 2);
      expect(find.byKey(const Key('turn-footnote')), findsNothing, reason: '“在回复下方显示用量”关掉后不显示');
    });

    testWidgets('脚注放不下时依次省掉 tokens、步数、花费 ($suffix)', (tester) async {
      usePhoneViewport(tester);
      late TestEnv e;
      await tester.runAsync(() async => e = await TestEnv.create());
      addTearDown(e.dispose);
      final turn = TurnUsage(ms: 47000, steps: [for (var i = 0; i < 12; i++) RequestStep(RequestUsage(usage: u(1000, 2000, 0), ms: 100, cost: 0.0025))]);
      Future<String> at(double width) async {
        await tester.pumpWidget(appFor(e, Scaffold(body: Align(alignment: Alignment.topLeft, child: SizedBox(width: width, child: TurnFootnote(turn: turn, onTap: () {})))), mode: mode, font: font));
        await tester.pump();
        expect(tester.takeException(), isNull);
        return tester.widget<Text>(find.byKey(const Key('turn-footnote-text'))).data!;
      }

      expect(await at(390), '47 秒 · 12 步 · 约 ¥0.03 · 36K tokens');
      final widths = <String, double>{};
      for (var w = 390.0; w >= 60; w -= 10) {
        widths.putIfAbsent(await at(w), () => w);
      }
      expect(widths.keys.toList(), ['47 秒 · 12 步 · 约 ¥0.03 · 36K tokens', '47 秒 · 12 步 · 约 ¥0.03', '47 秒 · 约 ¥0.03', '47 秒']);
    });

    testWidgets('上下文小环 → 用量弹层：上下文、本对话、DeepSeek 余额卡 ($suffix)', (tester) async {
      await boot(tester, script: toolTurn);
      await showChat(tester);
      final ring = find.byKey(const Key('context-ring'));
      expect(ring, findsOneWidget);
      await send(tester, '看看项目里有什么');
      // 上次请求输入 10.8K ÷ 128K = 8%
      expect(tester.widget<Text>(find.byKey(const Key('context-ring-label'))).data, '8%');
      await tester.tap(ring);
      await settle(tester, rounds: 4);
      expect(find.text('用量'), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('usage-context-kind'))).data, '上次请求');
      expect(tester.widget<Text>(find.byKey(const Key('usage-context-pct'))).data, '8%');
      expect(tester.widget<Text>(find.byKey(const Key('usage-context'))).data, '10.8K / 128K');
      expect(tester.widget<Text>(find.byKey(const Key('usage-context-parts'))).data, allOf(contains('系统'), contains('工具'), contains('消息'), contains('估')));
      expect(tester.widget<Text>(find.byKey(const Key('usage-total-in'))).data, '19.8K');
      expect(tester.widget<Text>(find.byKey(const Key('usage-total-rate'))).data, '45%');
      expect(tester.widget<Text>(find.byKey(const Key('usage-total-out'))).data, '380');
      expect(tester.widget<Text>(find.byKey(const Key('usage-total-turns'))).data, '1');
      expect(tester.widget<Text>(find.byKey(const Key('usage-total-cost'))).data, '约 ¥0.03');
      expect(find.textContaining('输入含缓存命中'), findsOneWidget);
      // DeepSeek 余额卡
      expect(find.byKey(const Key('balance-card')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('balance-amount'))).data, '¥100.00');
      expect(find.textContaining('充值 ¥98.00 · 赠送 ¥2.00'), findsOneWidget);
      expect(find.byKey(const Key('balance-topup')), findsOneWidget);
      expect(find.byKey(const Key('balance-low-line')), findsOneWidget);
      expect(find.byKey(const Key('balance-unavailable')), findsNothing);
      await shot(tester, '76-usage-sheet-$suffix');
    });

    testWidgets('用量弹层：非 DeepSeek 没有余额卡；没发过请求时上下文是估算；不到 1% 写 <1% ($suffix)', (tester) async {
      await boot(tester, deepseek: false, priced: false);
      await showChat(tester);
      expect(tester.widget<Text>(find.byKey(const Key('context-ring-label'))).data, '<1%');
      await tester.tap(find.byKey(const Key('context-ring')));
      await settle(tester, rounds: 4);
      expect(tester.widget<Text>(find.byKey(const Key('usage-context-kind'))).data, contains('预计下次请求'));
      expect(find.byKey(const Key('usage-empty')), findsOneWidget);
      expect(find.byKey(const Key('balance-card')), findsNothing);
      await shot(tester, '77-usage-sheet-empty-$suffix');
    });

    testWidgets('上下文小环的颜色：<60% 主色、60–85% 警示、>85% 危险 ($suffix)', (tester) async {
      usePhoneViewport(tester);
      late TestEnv e;
      await tester.runAsync(() async => e = await TestEnv.create());
      addTearDown(e.dispose);
      await tester.pumpWidget(appFor(e, Builder(builder: (context) {
        final c = context.colors;
        expect(contextTone(c, 0.59), c.accent);
        expect(contextTone(c, 0.6), c.warning);
        expect(contextTone(c, 0.85), c.warning);
        expect(contextTone(c, 0.86), c.danger);
        return const SizedBox();
      }), mode: mode, font: font));
      expect(tester.takeException(), isNull);
    });

    testWidgets('低余额小提示：低于提醒线才出现，能关，关了不再出现；余额不能调用时余额卡有提示 ($suffix)', (tester) async {
      await boot(tester);
      bal
        ..cny = 3.2
        ..available = false;
      await showChat(tester);
      await settle(tester, rounds: 3);
      final strip = find.byKey(const Key('low-balance-strip'));
      expect(strip, findsOneWidget, reason: '打开聊天时查了一次余额');
      expect(find.textContaining('余额仅剩 ¥3.20 · 低于 ¥5.00'), findsOneWidget);
      expect(tester.getBottomLeft(strip).dy, lessThanOrEqualTo(tester.getTopLeft(find.byKey(const ValueKey('chat-input'))).dy), reason: '在输入框上方');
      await shot(tester, '78-low-balance-$suffix');

      await tester.tap(find.byKey(const Key('context-ring')));
      await settle(tester, rounds: 4);
      expect(find.byKey(const Key('balance-unavailable')), findsOneWidget);
      await tester.scrollUntilVisible(find.byKey(const Key('balance-unavailable')), 80, scrollable: find.byType(Scrollable).last);
      await shot(tester, '79-balance-unavailable-$suffix');
      await tester.tapAt(const Offset(195, 40));
      await settle(tester, rounds: 3);

      await tester.tap(find.byKey(const Key('low-balance-close')));
      await settle(tester, rounds: 2);
      expect(strip, findsNothing);
      await tester.runAsync(() => env.services.quota.refresh(ds, force: true));
      await settle(tester, rounds: 2);
      expect(strip, findsNothing, reason: '这次运行里关掉后不再出现');
    });

    testWidgets('到上限：聊天里有拦截提示和“去调额度上限”，点了进额度上限页 ($suffix)', (tester) async {
      await boot(tester, script: [[say('不该出现'), ChatDelta(finishReason: 'stop')]]);
      await tester.runAsync(() async {
        await env.services.quota.setLimit(ds, limit: 10, currency: 'CNY');
        bal.cny = 89;
        await env.services.quota.refresh(ds, force: true);
      });
      await showChat(tester);
      await send(tester, '你好');
      expect(find.textContaining(kQuotaBlockedPrefix), findsOneWidget);
      expect(find.text('不该出现'), findsNothing);
      expect(find.text('去调额度上限'), findsOneWidget);
      await shot(tester, '80-chat-blocked-$suffix');
      await tester.tap(find.text('去调额度上限'));
      await settle(tester, rounds: 4);
      await settle(tester, rounds: 6);
      expect(find.byType(QuotaScreen), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('quota-used'))).data, contains('已使用 100%（剩余 ¥0.00）'));
      await shot(tester, '81-quota-reached-$suffix');
    });

    testWidgets('设置顶部卡：DeepSeek 没设上限只有余额；设了上限有进度条和百分比 ($suffix)', (tester) async {
      await boot(tester);
      await tester.pumpWidget(appFor(env, SettingsScreen(workspace: project, session: session), mode: mode, font: font));
      await settle(tester, rounds: 4);
      final overview = find.byKey(const Key('settings-overview'));
      expect(tester.widget<Text>(find.byKey(const Key('overview-balance'))).data, contains('余额 ¥100.00'));
      expect(find.descendant(of: overview, matching: find.textContaining('%')), findsNothing);
      expect(find.descendant(of: overview, matching: find.byKey(const Key('overview-bar'))), findsOneWidget, reason: '只有运行环境那一根');
      expect(find.text('设置额度上限'), findsOneWidget);
      await shot(tester, '82-settings-deepseek-nolimit-$suffix');

      // 进额度上限页，设 20 元
      await tester.tap(find.byKey(const Key('overview-set-quota')));
      await settle(tester, rounds: 4);
      await settle(tester, rounds: 6);
      expect(find.byType(QuotaScreen), findsOneWidget);
      await shot(tester, '83-quota-empty-$suffix');
      await tester.enterText(find.byKey(const Key('quota-limit')), '20');
      await tester.scrollUntilVisible(find.byKey(const Key('quota-save')), 120, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.byKey(const Key('quota-save')));
      await settle(tester, rounds: 4);
      final q = env.services.quota.quotaOf(ds.id)!;
      expect((q.limit, q.currency, q.warnPct, q.used), (20, 'CNY', 80, 0));
      // 花掉 6.4 元
      bal.cny = 93.6;
      await tester.runAsync(() => env.services.quota.refresh(ds, force: true));
      await settle(tester, rounds: 3);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 2000));
      await settle(tester, rounds: 2);
      expect(tester.widget<Text>(find.byKey(const Key('quota-used'))).data, contains('已使用 32%（剩余 ¥13.60）'));
      await shot(tester, '84-quota-used-$suffix');
      await tester.tap(find.byTooltip('返回').last);
      await settle(tester, rounds: 8);

      expect(tester.widget<Text>(find.byKey(const Key('overview-quota'))).data, '已使用 32%（剩余 ¥13.60）');
      expect(find.descendant(of: overview, matching: find.textContaining('余额 ¥93.60')), findsOneWidget);
      expect(find.descendant(of: overview, matching: find.byKey(const Key('overview-bar'))), findsNWidgets(2));
      await shot(tester, '85-settings-deepseek-limit-$suffix');
    });

    testWidgets('设置顶部卡：余额查不到时如实写，不编数字 ($suffix)', (tester) async {
      await boot(tester);
      bal.status = 401;
      await tester.pumpWidget(appFor(env, SettingsScreen(workspace: project, session: session), mode: mode, font: font));
      await settle(tester, rounds: 4);
      expect(tester.widget<Text>(find.byKey(const Key('overview-balance'))).data, contains('Key 无效，查不到余额'));
      expect(find.descendant(of: find.byKey(const Key('settings-overview')), matching: find.textContaining('¥')), findsNothing);
      await shot(tester, '86-settings-deepseek-nokey-$suffix');
    });

    testWidgets('设置里的两个开关和项目规则 ($suffix)', (tester) async {
      await boot(tester, deepseek: false);
      await tester.pumpWidget(appFor(env, SettingsScreen(workspace: project, session: session), mode: mode, font: font));
      await settle(tester, rounds: 3);
      final list = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(find.byKey(const Key('settings-usage')), 120, scrollable: list);
      expect(find.text('在新对话里显示开场建议'), findsOneWidget);
      expect(find.text('在回复下方显示用量'), findsOneWidget);
      expect(tester.widget<Switch>(find.byKey(const Key('settings-suggestions'))).value, isFalse, reason: '默认关');
      expect(tester.widget<Switch>(find.byKey(const Key('settings-usage'))).value, isTrue, reason: '默认开');
      await shot(tester, '87-settings-chat-group-$suffix');
      await tester.tap(find.byKey(const Key('settings-suggestions')));
      await settle(tester, rounds: 3);
      expect(env.services.settings.get<bool>(SettingKeys.chatSuggestions), isTrue);

      await tester.scrollUntilVisible(find.byKey(const Key('settings-rules')), -120, scrollable: list);
      await tester.tap(find.byKey(const Key('settings-rules')));
      await settle(tester, rounds: 4);
      await settle(tester, rounds: 6);
      expect(find.byType(ProjectRulesScreen), findsOneWidget);
      expect(find.textContaining('只对'), findsWidgets);
      await tester.enterText(find.byKey(const Key('rules-field')), '回答一律用简体中文。');
      await settle(tester, rounds: 1);
      await shot(tester, '88-rules-$suffix');

      await tester.tap(find.byTooltip('返回').last);
      await settle(tester, rounds: 8);
      // 开关打开后，新对话里出现开场建议
      await showChat(tester);
      expect(find.byKey(const Key('chat-ideas')), findsOneWidget);
      await shot(tester, '89-chat-ideas-on-$suffix');
    });
  }
}
