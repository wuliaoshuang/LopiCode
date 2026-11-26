// 设置重排（2026-11-24，霜霜：“设置页太乱，分门别类做好”）之后的“一个都不能丢”检查：
// 旧设置里的每一个入口 / 开关 / 输入项，在新结构里都要能走到（找到入口、点开、看到那个控件）。
// 对照表见 docs/settings-map.md。
//   flutter test test/settings_map_test.dart
//   LOPI_SHOTS=1 flutter test test/settings_map_test.dart   # 同时写截图到 docs/screenshots/（s6-…）
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/agent/model_config.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/stores.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/runtime/runtime_screen.dart';
import 'package:lopicode/ssh/ssh_connect_screen.dart';
import 'package:lopicode/ui/automation_screen.dart';
import 'package:lopicode/ui/error_guard.dart';
import 'package:lopicode/ui/settings_agent.dart';
import 'package:lopicode/ui/settings_ai.dart';
import 'package:lopicode/ui/settings_background.dart';
import 'package:lopicode/ui/settings_mcp.dart';
import 'package:lopicode/ui/settings_memory.dart';
import 'package:lopicode/ui/settings_pages.dart';
import 'package:lopicode/ui/settings_quota.dart';
import 'package:lopicode/ui/settings_screen.dart';
import 'package:lopicode/ui/settings_widgets.dart';
import 'package:lopicode/ui/third_party_screen.dart';
import 'package:material_ui/material_ui.dart';

import 'screens_test.dart' show fontsLoaded, shot;
import 'support/harness.dart';
import 'usage_ui_test.dart' show Bal;

/// 一级页的一个入口：行的 key、点开后应该是哪种页面、那一页里必须有的控件（key）和文字。
class _Entry {
  const _Entry(this.rowKey, this.page, {this.keys = const [], this.texts = const [], this.shot});
  final String rowKey;
  final Type page;
  final List<String> keys;
  final List<String> texts;
  final String? shot;
}

const _entries = <_Entry>[
  _Entry('settings-channels', ChannelsScreen, keys: [], texts: ['沿用上次', '固定默认', '添加渠道', 'DeepSeek'], shot: '02-channels'),
  _Entry('settings-quota', QuotaScreen, keys: ['quota-list'], texts: ['余额 · DeepSeek'], shot: '03-quota'),
  _Entry('settings-agent', AgentBehaviorScreen, keys: ['settings-permission', 'settings-step-limit', 'settings-auto-compact'], texts: ['新对话的权限', '连续执行多少步后问我', '上下文快满时自动压缩'], shot: '04-agent'),
  _Entry('settings-personalize', PersonalizeScreen, keys: ['prefs-field', 'prefs-save', 'preset-new'], texts: ['个人偏好', 'Agent 预设', '标准模式'], shot: '05-personalize'),
  _Entry(
    'settings-subagents',
    SubagentSettingsScreen,
    keys: ['subagent-enabled', 'subagent-depth', 'subagent-concurrent', 'team-enabled'],
    texts: ['子代理可以换用的模型', 'deepseek-chat'],
    shot: '06-subagents',
  ),
  _Entry(
    'settings-background',
    BackgroundSettingsScreen,
    keys: ['settings-keep-alive', 'settings-notify-done', 'settings-notification-permission', 'settings-open-app-settings'],
    texts: ['Agent 干活时保持后台运行', '做完时通知我'],
  ),
  _Entry('settings-search', WebSearchSettingsScreen, keys: ['search-url', 'search-key', 'search-save', 'search-test'], texts: ['填入 Tavily 的官方地址'], shot: '07-search'),
  _Entry('settings-mcp', McpServersScreen, keys: ['mcp-add'], texts: ['添加 MCP 服务器']),
  _Entry('settings-skills', SkillsScreen, texts: ['新建技能', '这个工作区：我的小站', '全局（所有工作区都能用）', '发版', '写周报'], shot: '08-skills'),
  _Entry('settings-memory', MemorySettingsScreen, keys: ['memory-enabled', 'memory-auto', 'memory-add-global', 'memory-add-project'], texts: ['让 Agent 使用记忆', '每轮结束后自动整理', '每轮结束后会多花一次模型调用']),
  _Entry('settings-automations', AutomationListScreen, shot: '09-automations'),
  _Entry('settings-chat', ChatDisplayScreen, keys: ['settings-suggestions', 'settings-usage', 'settings-thinking', 'settings-auto-images'], texts: ['在新对话里显示开场建议', '在回复下方显示用量', '显示思考过程', '自动加载网络图片'], shot: '10-chat-display'),
  _Entry('settings-appearance', AppearanceScreen, keys: ['appearance-system', 'appearance-light', 'appearance-dark'], shot: '11-appearance'),
  _Entry('settings-runtime', RuntimeScreen),
  _Entry('settings-ssh', SshConnectScreen, texts: ['保存'], shot: '12-ssh'),
  _Entry('settings-rules', ProjectRulesScreen, keys: ['rules-field', 'rules-save'], texts: ['工作区：我的小站'], shot: '13-rules'),
  _Entry('settings-third-party', ThirdPartyScreen),
  _Entry('settings-error-log', ErrorLogScreen, shot: '14-error-log'),
];

void main() {
  setUpAll(() async => fontsLoaded = await loadRealFonts());

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    final suffix = mode == ThemeMode.light ? 'light' : 'dark';

    late TestEnv env;
    late Project project;
    late ProjectSession session;

    /// [deepseek]：加几个 DeepSeek 官方渠道（0 = 只有一个别家的渠道）。
    Future<void> boot(WidgetTester tester, {int deepseek = 1, bool open = true}) async {
      usePhoneViewport(tester);
      await tester.runAsync(() async {
        env = await TestEnv.create(quotaHttp: Bal().client);
        for (var i = 0; i < (deepseek == 0 ? 1 : deepseek); i++) {
          await env.services.models.upsert(
            name: deepseek == 0 ? '我的中转站' : (i == 0 ? 'DeepSeek' : 'DeepSeek 备用'),
            protocol: ChatProtocol.openaiChat,
            baseUrl: deepseek == 0 ? 'https://relay.example.cn/v1' : 'https://api.deepseek.com',
            apiKey: 'sk-test',
            models: [ModelSpec(id: 'deepseek-chat', contextLength: 128000)],
          );
        }
        project = await env.services.projects.create('我的小站', ProjectTemplate.web);
        await env.services.skills.create(name: '发版', description: '发版流程', body: '打包再上传');
        await env.services.skills.create(name: '写周报', description: '这个工作区的周报怎么写', body: '第一步……', workspaceDir: project.dir);
        session = ProjectSession(env.services, project);
        await session.loadChat();
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      addTearDown(() async {
        await tester.runAsync(() async {
          session.dispose();
          await env.dispose();
        });
      });
      await tester.pumpWidget(
        appFor(
          env,
          open ? SettingsScreen(workspace: project, session: session) : const SettingsScreen(),
          mode: mode,
          font: kTestFont,
        ),
      );
      await settle(tester, rounds: 4);
    }

    Finder list() => find.descendant(of: find.byKey(const Key('settings-list')), matching: find.byType(Scrollable)).first;

    /// 滚到这一行，并且让它整行都在屏幕里（只露出一条边时点不中）。
    Future<void> reveal(WidgetTester tester, Finder f, double delta) async {
      await tester.scrollUntilVisible(f, delta, scrollable: list());
      await tester.ensureVisible(f);
      await settle(tester, rounds: 1);
    }

    Future<void> back(WidgetTester tester) async {
      await tester.tap(find.byTooltip('返回').last);
      await settle(tester, rounds: 6);
    }

    testWidgets('一级页只放入口；旧设置的每一项在新结构里都能走到 ($suffix)', (tester) async {
      await boot(tester);
      expect(find.byType(Switch), findsNothing, reason: '一级页没有开关');
      expect(find.byType(TextField), findsNothing, reason: '一级页没有输入框');
      expect(find.byType(SegmentedButton<Object>), findsNothing);
      await shot(tester, 's6-01-home-top-$suffix');

      for (final e in _entries) {
        final row = find.byKey(Key(e.rowKey));
        await reveal(tester, row, 120);
        await settle(tester, rounds: 1);
        expect(row, findsOneWidget, reason: '${e.rowKey} 这个入口在一级页');
        expect(
          find.descendant(of: row, matching: find.byIcon(Icons.chevron_right)),
          findsOneWidget,
          reason: '${e.rowKey} 右边有箭头',
        );
        await tester.tap(row);
        await settle(tester, rounds: 8);
        expect(find.byType(e.page), findsOneWidget, reason: '${e.rowKey} 点开是 ${e.page}');
        for (final k in e.keys) {
          final f = find.byKey(Key(k));
          await tester.scrollUntilVisible(
            f,
            120,
            scrollable: find.descendant(of: find.byType(e.page), matching: find.byType(Scrollable)).first,
          );
          expect(f, findsOneWidget, reason: '${e.page} 里有 $k');
        }
        for (final t in e.texts) {
          expect(find.textContaining(t, skipOffstage: false), findsWidgets, reason: '${e.page} 里有“$t”');
        }
        if (e.shot != null) {
          final inner = find.descendant(of: find.byType(e.page), matching: find.byType(Scrollable));
          if (inner.evaluate().isNotEmpty && e.keys.isNotEmpty) {
            await tester.drag(inner.first, const Offset(0, 3000));
            await settle(tester, rounds: 2);
          }
          await shot(tester, 's6-${e.shot}-$suffix');
        }
        await back(tester);
        expect(find.byType(e.page), findsNothing);
      }
      await shot(tester, 's6-01-home-bottom-$suffix');
    });

    testWidgets('一级页每一行同一个样子：一样高（≥48）、名称左边对齐、开关行整行可点 ($suffix)', (tester) async {
      await boot(tester);
      final heights = <double>{};
      final lefts = <double>{};
      for (final e in _entries) {
        final row = find.byKey(Key(e.rowKey));
        await reveal(tester, row, 120);
        final frame = find.descendant(of: row, matching: find.byType(InkWell)).first;
        heights.add(tester.getSize(frame).height);
        final title = find.descendant(of: row, matching: find.byType(Text)).first;
        lefts.add(tester.getTopLeft(title).dx);
      }
      expect(heights, {SettingsMetrics.rowMinHeight}, reason: '一级页的行全都一样高');
      expect(SettingsMetrics.rowMinHeight, greaterThanOrEqualTo(48));
      expect(lefts, hasLength(1), reason: '名称都从同一条竖线开始');

      // 二级页的开关行：≥48 高，点名称（不点开关）也能切换
      await reveal(tester, find.byKey(const Key('settings-chat')), -120);
      await tester.tap(find.byKey(const Key('settings-chat')));
      await settle(tester, rounds: 6);
      final switchRow = find.ancestor(of: find.byKey(const Key('settings-usage')), matching: find.byType(InkWell)).first;
      expect(tester.getSize(switchRow).height, greaterThanOrEqualTo(48));
      await tester.tap(find.text('在回复下方显示用量'));
      await settle(tester, rounds: 2);
      expect(env.services.settings.getBool(SettingKeys.chatUsage, true), isFalse);
      expect(tester.widget<Switch>(find.byKey(const Key('settings-usage'))).value, isFalse);
    });

    testWidgets('外观：三行单选，选了立刻存下来，回到一级页那一行跟着变 ($suffix)', (tester) async {
      await boot(tester);
      await reveal(tester, find.byKey(const Key('settings-appearance')), 120);
      await tester.tap(find.byKey(const Key('settings-appearance')));
      await settle(tester, rounds: 6);
      for (final label in ['跟随系统', '浅色', '深色']) {
        expect(find.text(label), findsOneWidget);
      }
      await tester.tap(find.byKey(const Key('appearance-dark')));
      await settle(tester, rounds: 3);
      expect(env.services.settings.getString(SettingKeys.themeMode), 'dark');
      await back(tester);
      expect(
        find.descendant(of: find.byKey(const Key('settings-appearance')), matching: find.text('深色')),
        findsOneWidget,
        reason: '留在后面的一级页订阅了设置，回来是新值',
      );
    });

    testWidgets('额度与余额：没有 DeepSeek 官方渠道就没有这一行；有两个就先选渠道 ($suffix)', (tester) async {
      await boot(tester, deepseek: 0);
      expect(find.byKey(const Key('settings-channels')), findsOneWidget);
      expect(find.byKey(const Key('settings-quota')), findsNothing, reason: '别的服务商查不了余额');
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        for (final name in ['DeepSeek', 'DeepSeek 备用']) {
          await env.services.models.upsert(
            name: name,
            protocol: ChatProtocol.openaiChat,
            baseUrl: 'https://api.deepseek.com',
            apiKey: 'sk-test',
            models: [ModelSpec(id: 'deepseek-chat', contextLength: 128000)],
          );
        }
      });
      await tester.pumpWidget(
        appFor(
          env,
          SettingsScreen(workspace: project, session: session),
          mode: mode,
          font: kTestFont,
        ),
      );
      await settle(tester, rounds: 4);
      final row = find.byKey(const Key('settings-quota'));
      expect(find.descendant(of: row, matching: find.text('2 个渠道')), findsOneWidget);
      await tester.tap(row);
      await settle(tester, rounds: 6);
      expect(find.byType(QuotaChannelsScreen), findsOneWidget);
      final ids = [
        for (final ch in env.services.models.channels)
          if (ch.baseUrl.contains('deepseek')) ch.id,
      ];
      expect(ids, hasLength(2));
      for (final id in ids) {
        expect(find.byKey(Key('settings-quota-$id')), findsOneWidget);
      }
      await shot(tester, 's6-03b-quota-channels-$suffix');
      await tester.tap(find.byKey(Key('settings-quota-${ids.last}')));
      await settle(tester, rounds: 8);
      expect(find.byType(QuotaScreen), findsOneWidget);
      expect(find.textContaining('余额 · DeepSeek 备用'), findsOneWidget, reason: '进的是点的那个渠道');
    });

    testWidgets('没打开工作区：项目规则那一行灰掉、点了没反应，脚注说明原因 ($suffix)', (tester) async {
      await boot(tester, open: false);
      final row = find.byKey(const Key('settings-rules'));
      await reveal(tester, row, 120);
      expect(find.text('当前工作区'), findsOneWidget);
      expect(find.textContaining('打开一个工作区后'), findsOneWidget);
      await tester.tap(row);
      await settle(tester, rounds: 4);
      expect(find.byType(ProjectRulesScreen), findsNothing);
      // 没打开工作区也能进运行环境和技能（全局的）
      await reveal(tester, find.byKey(const Key('settings-skills')), -120);
      await tester.tap(find.byKey(const Key('settings-skills')));
      await settle(tester, rounds: 6);
      expect(find.byType(SkillsScreen), findsOneWidget);
    });
  }
}
