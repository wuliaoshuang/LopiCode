// MCP 的界面（390×844，浅色 + 深色）：设置里的入口、服务器列表、四步编辑页（请求头打码）、聊天里的确认卡和“恢复询问”提示。
// 连的是本机假服务器（只绑 127.0.0.1），不发外网请求。
//   LOPI_SHOTS=1 flutter test test/mcp_ui_test.dart   # 同时写截图到 docs/screenshots/60-mcp-*.png
import 'dart:io';

import 'package:flutter/rendering.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/agent/mcp/mcp_config.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/state/mcp_state.dart';
import 'package:lopicode/ui/mcp_edit_screen.dart';
import 'package:lopicode/ui/project_shell.dart';
import 'package:lopicode/ui/settings_mcp.dart';
import 'package:lopicode/ui/settings_screen.dart';
import 'package:lopicode/ui/shell.dart';
import 'package:material_ui/material_ui.dart';

import 'agent_test.dart' show RecordingRunner;
import 'agent_ui_test.dart' show Launcher, waitReal;
import 'screens_test.dart' show fontsLoaded, shot;
import 'session_system_test.dart' show RoutingClient, Turn, reply, use;
import 'support/fake_mcp_server.dart';
import 'support/harness.dart';

const token = 'Bearer ui-secret-token-7788aabbcc';

void main() {
  setUpAll(() async => fontsLoaded = await loadRealFonts());
  // 界面测试默认把所有网络请求挡成 400；这里要连本机的假服务，放开（只会连 127.0.0.1）。
  setUp(() => HttpOverrides.global = null);

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    final suffix = mode == ThemeMode.light ? 'light' : 'dark';

    group('MCP 界面 ($suffix)', () {
      late TestEnv env;
      late FakeMcpServer server;
      late Project project;
      late ProjectSession session;
      Turn turn = (_, _) => reply('好的。');
      McpNotifier mcp() => env.services.container.read(mcpProvider.notifier);

      Future<void> boot(WidgetTester tester, {bool withSession = false}) async {
        usePhoneViewport(tester);
        turn = (_, _) => reply('好的。');
        await tester.runAsync(() async {
          server = await FakeMcpServer.start(FakeMcpKind.legacy);
          env = await TestEnv.create(chatClient: () => RoutingClient((m, t) => turn(m, t), []));
          if (withSession) {
            project = await env.services.projects.create('我的小站', ProjectTemplate.web);
            session = ProjectSession(env.services, project);
            session.commandRunnerFactory = RecordingRunner.new;
            await session.loadChat();
          }
        });
        addTearDown(() async {
          if (withSession) session.dispose();
          await env.dispose();
          await server.close();
        });
      }

      Future<McpServerConfig> addServer(WidgetTester tester, {String name = 'docs', Map<String, String?> headers = const {}}) async {
        late McpServerConfig s;
        await tester.runAsync(() async {
          final probe = await mcp().probe(url: '${server.url}', headers: headers);
          s = await mcp().upsert(name: name, url: '${server.url}', headers: headers, tools: probe.tools, mode: probe.mode);
        });
        return s;
      }

      Future<void> show(WidgetTester tester, Widget home, {bool push = true}) async {
        await tester.pumpWidget(
          appFor(
            env,
            push ? Launcher(key: UniqueKey(), page: home) : home,
            mode: mode,
            font: fontsLoaded ? kTestFont : null,
          ),
        );
        await settle(tester, rounds: 6);
      }

      Future<void> tapVisible(WidgetTester tester, Finder f) async {
        // 顶栏是悬浮的：滚到屏幕中间再点，免得被顶栏盖住。
        await Scrollable.ensureVisible(tester.element(f), alignment: 0.5);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(f);
        await settle(tester, rounds: 3);
      }

      testWidgets('设置一级页有“MCP 服务器”入口，右边写当前状态；没配置时列表页只有说明和“添加”', (tester) async {
        await boot(tester);
        await show(tester, const SettingsScreen());
        final row = find.byKey(const Key('settings-mcp'));
        await tester.scrollUntilVisible(row, 120, scrollable: find.byType(Scrollable).first);
        expect(find.descendant(of: row, matching: find.text('MCP 服务器')), findsOneWidget);
        expect(find.descendant(of: row, matching: find.text('未配置')), findsOneWidget);
        await tapVisible(tester, row);
        expect(find.byType(McpServersScreen), findsOneWidget);
        expect(find.byKey(const Key('mcp-add')), findsOneWidget);
        expect(find.textContaining('每次调用这些工具都会先问你'), findsOneWidget);
        expect(find.textContaining('对话里不会出现任何 MCP 的东西'), findsOneWidget);
        expect(find.byType(Switch), findsNothing);
        await shot(tester, '60-mcp-empty-$suffix');
      });

      testWidgets('添加一个服务器走四步：填地址 → 加请求头（打码）→ 连接并读取工具 → 关掉一个工具 → 保存', (tester) async {
        await boot(tester);
        server.requireHeaders = {'authorization': token};
        await show(tester, const McpServersScreen());
        await tapVisible(tester, find.byKey(const Key('mcp-add')));
        expect(find.byType(McpServerEditScreen), findsOneWidget);
        for (final step in ['第 1 步 · 填名字和地址', '第 2 步 · 连接并读取工具']) {
          expect(find.text(step), findsOneWidget);
        }
        // 没填地址：第 2 步点不了，旁边写明还差什么
        FilledButton probeButton() => tester.widget<FilledButton>(find.byKey(const Key('mcp-probe')));
        expect(probeButton().onPressed, isNull);
        expect(find.byKey(const Key('mcp-probe-missing')), findsOneWidget);

        await tester.enterText(find.byKey(const Key('mcp-name')), '资料库');
        // 外网 http 地址：当场说不行
        await tester.enterText(find.byKey(const Key('mcp-url')), 'http://example.com/mcp');
        await settle(tester, rounds: 1);
        expect(find.textContaining('https'), findsWidgets);
        expect(probeButton().onPressed, isNull);
        await tester.enterText(find.byKey(const Key('mcp-url')), '${server.url}');
        await settle(tester, rounds: 1);
        expect(probeButton().onPressed, isNotNull);
        expect(find.byKey(const Key('mcp-probe-missing')), findsNothing);

        // 请求头：在弹层里填，值默认遮住
        await tapVisible(tester, find.byKey(const Key('mcp-header-add')));
        final valueField = find.byKey(const Key('mcp-header-value'));
        expect(tester.widget<TextField>(valueField).obscureText, isTrue, reason: '值默认打码');
        // 空着点“好”：两处都提示
        await tester.tap(find.byKey(const Key('mcp-header-ok')));
        await settle(tester, rounds: 1);
        expect(find.textContaining('还没填'), findsWidgets);
        await tester.enterText(find.byKey(const Key('mcp-header-name')), 'Authorization');
        await tester.enterText(valueField, token);
        await tester.tap(find.byKey(const Key('mcp-header-show')));
        await settle(tester, rounds: 1);
        expect(tester.widget<TextField>(valueField).obscureText, isFalse, reason: '点“显示”才看得到');
        await tester.tap(find.byKey(const Key('mcp-header-ok')));
        await settle(tester, rounds: 3);
        expect(find.byKey(const Key('mcp-header-Authorization')), findsOneWidget);
        expect(find.textContaining('••••••'), findsOneWidget);
        expect(find.textContaining('ui-secret-token'), findsNothing, reason: '页面上不显示令牌');
        // 连接方式三段在 390 宽里都写得全，不被截断
        for (final label in ['自动', 'HTTP', '旧版 SSE']) {
          final text = tester.renderObject<RenderParagraph>(find.descendant(of: find.byKey(const Key('mcp-transport')), matching: find.text(label)));
          expect(text.didExceedMaxLines, isFalse, reason: label);
          expect(text.size.width, greaterThanOrEqualTo(text.getMaxIntrinsicWidth(double.infinity) - 0.5), reason: '$label 被挤短了');
        }
        await shot(tester, '61a-mcp-edit-top-$suffix');

        // 第 2 步：连接并读取工具
        await tapVisible(tester, find.byKey(const Key('mcp-probe')));
        await waitReal(tester, () => find.byKey(const Key('mcp-probe-result')).evaluate().isNotEmpty, what: '连接结果');
        expect(find.textContaining('连上了，读到 5 个工具'), findsOneWidget);
        expect(server.toolCalls, 0, reason: '只读清单，不调用工具');
        expect(find.text('第 3 步 · 选工具（5 / 5）'), findsOneWidget);
        await tester.ensureVisible(find.byKey(const Key('mcp-tool-echo')));
        await tester.pump(const Duration(milliseconds: 300));
        await shot(tester, '61-mcp-edit-$suffix');

        // 第 3 步：关掉一个工具
        final failSwitch = find.descendant(of: find.byKey(const Key('mcp-tool-fail')), matching: find.byType(Switch));
        await tapVisible(tester, failSwitch);
        expect(find.text('第 3 步 · 选工具（4 / 5）'), findsOneWidget);

        // 第 4 步：保存
        await tapVisible(tester, find.byKey(const Key('mcp-save')));
        await settle(tester, rounds: 6);
        expect(find.byType(McpServerEditScreen), findsNothing);
        final saved = mcp().snapshot.servers.single;
        expect(saved.name, '资料库');
        expect(saved.headerNames, ['Authorization']);
        expect(saved.disabledTools, {'fail'});
        expect(saved.tools, hasLength(5));
        late String? secret;
        await tester.runAsync(() async => secret = await env.services.secrets.read(McpStore.secretKey(saved.id, 'Authorization')));
        expect(secret, token);
        for (final name in ['settings.json', 'mcp_servers.json']) {
          final f = File('${env.tmp.path}/$name');
          if (f.existsSync()) expect(f.readAsStringSync(), isNot(contains('ui-secret-token')), reason: name);
        }
        // 回到列表：一行，名字 + 工具数 + 开关
        final row = find.byKey(Key('mcp-server-${saved.id}'));
        expect(find.descendant(of: row, matching: find.text('资料库')), findsOneWidget);
        expect(find.descendant(of: row, matching: find.textContaining('4 / 5 个工具开着')), findsOneWidget);
        expect(find.descendant(of: row, matching: find.byType(Switch)), findsOneWidget);
      });

      testWidgets('连不上时：分开说原因和下一步，不显示令牌；仍然可以先保存', (tester) async {
        await boot(tester);
        server
          ..failStatus = 401
          ..failBody = 'bad $token';
        await show(tester, const McpServerEditScreen());
        await tester.enterText(find.byKey(const Key('mcp-name')), '资料库');
        await tester.enterText(find.byKey(const Key('mcp-url')), '${server.url}');
        await settle(tester, rounds: 1);
        await tapVisible(tester, find.byKey(const Key('mcp-probe')));
        await waitReal(tester, () => find.byKey(const Key('mcp-probe-result')).evaluate().isNotEmpty, what: '连接结果');
        expect(find.textContaining('令牌不对或没填'), findsOneWidget);
        expect(find.textContaining('回第 1 步检查请求头'), findsOneWidget);
        expect(find.textContaining('ui-secret-token'), findsNothing);
        expect(find.text('再试一次'), findsOneWidget);
        await tester.ensureVisible(find.byKey(const Key('mcp-probe-result')));
        await tester.pump(const Duration(milliseconds: 300));
        await shot(tester, '62-mcp-edit-failed-$suffix');
        expect(find.byKey(const Key('mcp-tools-empty')), findsOneWidget);
        expect(find.byKey(const Key('mcp-save-hint')), findsOneWidget);
      });

      testWidgets('列表：开关只管开关；编辑页不回显已保存的请求头；删除在“更多”里，要确认', (tester) async {
        await boot(tester);
        final s = await addServer(tester, headers: {'Authorization': token});
        await tester.runAsync(() => mcp().upsert(name: 'wiki', url: 'https://example.com/mcp'));
        await show(tester, const McpServersScreen());
        expect(find.textContaining('5 个工具'), findsOneWidget);
        expect(find.textContaining('还没读过工具清单'), findsOneWidget);
        await shot(tester, '63-mcp-list-$suffix');

        await tester.tap(find.byKey(Key('mcp-switch-${s.id}')));
        await settle(tester, rounds: 4);
        expect(mcp().snapshot.server(s.id)!.enabled, isFalse);
        expect(find.byType(McpServerEditScreen), findsNothing, reason: '点开关不进编辑页');
        expect(find.textContaining('已关闭'), findsOneWidget);

        await tester.tap(find.text('docs'));
        await settle(tester, rounds: 4);
        expect(find.byType(McpServerEditScreen), findsOneWidget);
        expect(find.textContaining('已保存 ••••••'), findsOneWidget);
        expect(find.textContaining('ui-secret-token'), findsNothing);
        // 点开请求头：值是空的，留空表示不改
        await tapVisible(tester, find.byKey(const Key('mcp-header-Authorization')));
        expect(tester.widget<TextField>(find.byKey(const Key('mcp-header-value'))).controller!.text, isEmpty);
        expect(find.text('已保存，留空表示不改'), findsOneWidget);
        await tester.tap(find.text('取消'));
        await settle(tester, rounds: 2);

        await tester.tap(find.byKey(const Key('mcp-more')));
        await settle(tester, rounds: 2);
        await tester.tap(find.text('删除服务器'));
        await settle(tester, rounds: 2);
        expect(find.text('删除这个服务器？'), findsOneWidget);
        expect(mcp().snapshot.server(s.id), isNotNull, reason: '没确认前不删');
        await tester.tap(find.text('删除'));
        await settle(tester, rounds: 6);
        expect(mcp().snapshot.server(s.id), isNull);
        expect(find.byType(McpServerEditScreen), findsNothing);
        expect(find.text('docs'), findsNothing);
        expect(find.text('wiki'), findsOneWidget);
      });

      testWidgets('聊天里的确认卡：写清服务器和工具；“这个工具都允许”要二次确认；之后有一条可以“恢复询问”的提示', (tester) async {
        await boot(tester, withSession: true);
        await addServer(tester);
        var n = 0;
        turn = (m, t) => switch (n++) {
          0 => use('mcp__docs__echo', {'text': '查一下 LopiCode'}),
          1 => use('mcp__docs__echo', {'text': '第二次'}),
          _ => reply('查完了。'),
        };
        await tester.pumpWidget(
          appFor(
            env,
            ProjectShell(project: project, session: session, initial: ShellDest.chat),
            mode: mode,
            font: fontsLoaded ? kTestFont : null,
          ),
        );
        await settle(tester, rounds: 6);
        expect(find.byKey(const ValueKey('mcp-allow-chip')), findsNothing);
        expect(find.textContaining('MCP'), findsNothing, reason: '没用到之前聊天页没有 MCP 的东西');

        late Future<void> done;
        // 大括号别省：写成 `=> done = …` 会让 runAsync 一直等到这一轮结束，而这一轮在等确认卡。
        await tester.runAsync(() async {
          done = session.sendToAgent('帮我查一下');
        });
        await waitReal(tester, () => session.pendingApproval != null, what: '确认卡');
        expect(find.textContaining('调用 MCP 工具 echo（服务器“docs”）'), findsOneWidget);
        expect(find.textContaining('查一下 LopiCode'), findsWidgets);
        expect(find.textContaining('会把下面的参数发给外部服务器'), findsOneWidget);
        expect(find.text('本对话里这个工具都允许'), findsOneWidget);
        expect(server.toolCalls, 0);
        await shot(tester, '64-mcp-approval-$suffix');

        await tester.tap(find.text('本对话里这个工具都允许'));
        await settle(tester, rounds: 2);
        expect(session.pendingApproval, isNotNull, reason: '只点一次不能生效');
        expect(server.toolCalls, 0);
        expect(find.byKey(const Key('always-explain')), findsOneWidget);
        expect(find.textContaining('其他工具、其他服务器照样每次都问'), findsOneWidget);
        await tester.tap(find.byKey(const Key('always-confirm')));
        await waitReal(tester, () => server.toolCalls == 2 && !session.agentBusy, what: '两次调用做完');
        await tester.runAsync(() => done);
        await settle(tester, rounds: 4);
        expect(server.toolCalls, 2, reason: '第二次同一个工具没有再问');
        final chip = find.byKey(const ValueKey('mcp-allow-chip'));
        expect(chip, findsOneWidget);
        expect(find.textContaining('有 1 个 MCP 工具在本对话里不再逐次问你'), findsOneWidget);
        await shot(tester, '65-mcp-allow-chip-$suffix');
        await tester.tap(find.descendant(of: chip, matching: find.text('恢复询问')));
        await settle(tester, rounds: 2);
        expect(session.mcpAllowCount, 0);
        expect(chip, findsNothing);
      });
    });
  }
}
