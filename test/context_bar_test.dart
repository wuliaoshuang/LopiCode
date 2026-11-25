// 上下文占用分段条（390×844，浅色 + 深色）：分段估算的纯计算；横条 + 图例单独摆出来的几种样子；真的用量面板里的样子；
// 步骤详情里“查看完整输出”对不是命令的工具也可用。不联网。
//   LOPI_SHOTS=1 flutter test test/context_bar_test.dart   # 同时写截图到 docs/screenshots/
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/agent/agent_runner.dart';
import 'package:lopicode/agent/auto_compact.dart';
import 'package:lopicode/agent/chat_client.dart';
import 'package:lopicode/agent/context_segments.dart';
import 'package:lopicode/agent/model_config.dart';
import 'package:lopicode/agent/tool_output_spill.dart';
import 'package:lopicode/agent/usage.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/session/chat_rows.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/chat_extras.dart';
import 'package:lopicode/ui/chat_row_view.dart';
import 'package:lopicode/ui/context_bar.dart';
import 'package:lopicode/ui/project_shell.dart';
import 'package:lopicode/ui/shell.dart';
import 'package:material_ui/material_ui.dart';

import 'screens_test.dart' show shot, fontsLoaded;
import 'support/harness.dart';

void main() {
  setUpAll(() async => fontsLoaded = await loadRealFonts());

  group('分段估算（纯计算）', () {
    test('对话消息和工具结果分开估；已归档的不算；按 3 个字符 1 个 token，和 AgentRunner.estimateTokens 合得上', () {
      final messages = <Map<String, dynamic>>[
        {'role': 'user', 'content': '问' * 300, kArchivedMark: true},
        {'role': 'tool', 'tool_call_id': 'old', 'content': 'x' * 3000, kArchivedMark: true},
        {'role': 'user', 'content': '问' * 600},
        {
          'role': 'assistant',
          'content': '答' * 300,
          'tool_calls': [
            {
              'id': 'c1',
              'function': {'name': 'read_file', 'arguments': '{"path":"a.txt"}'},
            },
          ],
        },
        {'role': 'tool', 'tool_call_id': 'c1', 'content': 'y' * 9000},
        {
          'role': 'user',
          'content': '看图',
          '_images': [
            {'path': 'a.png'},
          ],
        },
      ];
      final s = ContextSegments.of(system: 1000, tools: 2000, messages: messages, limit: 128000);
      expect(s.toolResults, 3000);
      final callChars = '${(messages[3]['tool_calls'] as List).first}'.length;
      expect(s.messages, (600 + 300 + callChars + 2 + 3000) ~/ 3);
      expect((s.messages + s.toolResults - AgentRunner.estimateTokens(messages)).abs(), lessThanOrEqualTo(1), reason: '两段加起来就是原来“消息”那个数（各自取整最多差 1）');
      expect(s.used, 1000 + 2000 + s.messages + 3000);
      expect(s.remaining, 128000 - s.used);
      expect(s.total, 128000);
      expect(s.shareOf(s.remaining) + s.shareOf(s.used), closeTo(1, 1e-9));
    });

    test('估出来已经超了：剩余是 0，横条按已用的算、各段照比例挤满；上限是 0 也不除零', () {
      const over = ContextSegments(system: 10000, tools: 10000, messages: 60000, toolResults: 40000, limit: 100000);
      expect(over.remaining, 0);
      expect(over.total, 120000);
      expect(over.shareOf(over.messages), 0.5);
      const zero = ContextSegments(system: 0, tools: 0, messages: 0, toolResults: 0, limit: 0);
      expect(zero.shareOf(0), 0);
      expect(zero.remaining, 0);
    });

    test('占比的写法：0 写 0%，不到 1% 写 <1%，其余四舍五入', () {
      expect(segmentPercent(0), '0%');
      expect(segmentPercent(0.004), '<1%');
      expect(segmentPercent(0.126), '13%');
      expect(segmentPercent(1), '100%');
    });
  });

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    final suffix = mode == ThemeMode.light ? 'light' : 'dark';
    late TestEnv env;

    Future<void> bootEnv(WidgetTester tester) async {
      usePhoneViewport(tester);
      await tester.runAsync(() async => env = await TestEnv.create());
      addTearDown(() => env.dispose());
    }

    Future<void> showBars(WidgetTester tester, List<(String, ContextSegments?)> bars) async {
      await tester.pumpWidget(
        appFor(
          env,
          Scaffold(
            body: SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(Space.x4),
                children: [
                  for (final (i, b) in bars.indexed) ...[
                    Text(b.$1),
                    const SizedBox(height: Space.x2),
                    KeyedSubtree(
                      key: Key('bar-$i'),
                      child: ContextSegmentBar(segments: b.$2),
                    ),
                    const SizedBox(height: Space.x6),
                  ],
                ],
              ),
            ),
          ),
          mode: mode,
          font: kTestFont,
        ),
      );
      await settle(tester);
    }

    Finder inBar(int i, String key) => find.descendant(of: find.byKey(Key('bar-$i')), matching: find.byKey(Key(key)));

    testWidgets('分段条：五段颜色两两不同、和底色也不同；宽度按比例、加起来正好一整条；图例五行有名称、约数、占比 ($suffix)', (tester) async {
      await bootEnv(tester);
      const s = ContextSegments(system: 6000, tools: 9000, messages: 30000, toolResults: 45000, limit: 128000);
      await showBars(tester, [('对话进行到一半', s)]);
      expect(tester.takeException(), isNull);
      const ids = ['system', 'tools', 'messages', 'results', 'rest'];
      final colors = [for (final id in ids) (tester.widget<Container>(inBar(0, 'context-seg-$id')).color)!];
      expect(colors.toSet().length, 5, reason: '五段颜色各不相同');
      final surface = Theme.of(tester.element(inBar(0, 'context-bar'))).scaffoldBackgroundColor;
      expect(colors, isNot(contains(surface)));
      // 相邻两段明暗差得开（不只靠色相）：相对亮度至少差 0.08。
      for (var i = 0; i < 4; i++) {
        expect((colors[i].computeLuminance() - colors[i + 1].computeLuminance()).abs(), greaterThan(0.08), reason: '${ids[i]} 和 ${ids[i + 1]}（$suffix）');
      }
      final bar = tester.getSize(inBar(0, 'context-bar'));
      expect(bar.height, ContextSegmentBar.barHeight);
      expect(bar.width, 390 - Space.x4 * 2);
      final widths = [for (final id in ids) tester.getSize(inBar(0, 'context-seg-$id')).width];
      expect(widths.reduce((a, b) => a + b) + ContextSegmentBar.gap * 4, closeTo(bar.width, 0.01));
      expect(widths[3], greaterThan(widths[2]));
      expect(widths[2], greaterThan(widths[1]));
      expect(widths[1], greaterThan(widths[0]));
      // 图例：一段一行，文字说清是哪一段、大约多少、占多少。
      String legend(String id) => tester.widgetList<Text>(find.descendant(of: inBar(0, 'context-legend-$id'), matching: find.byType(Text))).map((t) => t.data).join(' | ');
      expect(legend('system'), '系统提示词 | ≈ ${formatTokens(6000)} | 5%');
      expect(legend('tools'), '工具定义 | ≈ ${formatTokens(9000)} | 7%');
      expect(legend('messages'), '对话消息 | ≈ ${formatTokens(30000)} | 23%');
      expect(legend('results'), '工具结果 | ≈ ${formatTokens(45000)} | 35%');
      expect(legend('rest'), '剩余 | ≈ ${formatTokens(38000)} | 30%');
      // 图例各行不重叠、不超出屏幕。
      final rows = [for (final id in ids) tester.getRect(inBar(0, 'context-legend-$id'))];
      for (var i = 0; i < 4; i++) {
        expect(rows[i].bottom, lessThanOrEqualTo(rows[i + 1].top));
      }
      expect(rows.every((r) => r.left >= 0 && r.right <= 390), isTrue);
      expect(tester.widget<Text>(inBar(0, 'usage-context-parts')).data, allOf(contains('估算'), contains('会有出入')));
      // 读屏：横条有一句文字说明。
      expect(find.bySemanticsLabel(RegExp('上下文占用分段（估算）.*系统提示词 5%.*剩余 30%')), findsOneWidget);
    });

    testWidgets('几种边角：很小的段也看得见（至少 3 宽）；是 0 的段不画但图例还在；估超了没有“剩余”段；还在算 ($suffix)', (tester) async {
      await bootEnv(tester);
      await showBars(tester, const [
        ('刚开始：只有固定开销', ContextSegments(system: 1500, tools: 3200, messages: 40, toolResults: 0, limit: 128000)),
        ('快满了', ContextSegments(system: 6000, tools: 9000, messages: 38000, toolResults: 62000, limit: 128000)),
        ('估出来已经超了', ContextSegments(system: 6000, tools: 9000, messages: 50000, toolResults: 80000, limit: 128000)),
        ('还在算', null),
      ]);
      expect(tester.takeException(), isNull);
      // 刚开始：对话消息只有 40 token（不到 1%），也画出来，至少 3 宽；工具结果是 0，不画，图例写 0。
      expect(tester.getSize(inBar(0, 'context-seg-messages')).width, greaterThanOrEqualTo(ContextSegmentBar.minSegment));
      expect(inBar(0, 'context-seg-results'), findsNothing);
      expect(find.descendant(of: inBar(0, 'context-legend-results'), matching: find.text('0%')), findsOneWidget);
      expect(find.descendant(of: inBar(0, 'context-legend-messages'), matching: find.text('<1%')), findsOneWidget);
      // 估超了：没有剩余段，四段挤满整条；图例里剩余写 0。
      expect(inBar(2, 'context-seg-rest'), findsNothing);
      final full = tester.getSize(inBar(2, 'context-bar')).width;
      final widths = [
        for (final id in ['system', 'tools', 'messages', 'results']) tester.getSize(inBar(2, 'context-seg-$id')).width,
      ];
      expect(widths.reduce((a, b) => a + b) + ContextSegmentBar.gap * 3, closeTo(full, 0.01));
      expect(find.descendant(of: inBar(2, 'context-legend-rest'), matching: find.text('0%')), findsOneWidget);
      // 还在算：一根灰条 + 一句话，没有图例。
      expect(inBar(3, 'context-bar-loading'), findsOneWidget);
      expect(inBar(3, 'context-legend-system'), findsNothing);
      expect(tester.widget<Text>(inBar(3, 'usage-context-parts')).data, '分项计算中…');
      await shot(tester, 'ctx-01-segment-bar-states-$suffix');
    });

    testWidgets('用量面板里：上下文那一节顶部是分段条 + 图例，写明是估算；数字和会话算的一致 ($suffix)', (tester) async {
      usePhoneViewport(tester);
      late Project project;
      late ProjectSession session;
      final script = <List<ChatDelta>>[
        [
          say('我先把几个文件都看一遍。'),
          call(0, 'list_files', '{}'),
          call(1, 'read_file', '{"path":"index.html"}'),
          call(2, 'read_file', '{"path":"style.css"}'),
          ChatDelta(finishReason: 'tool_calls', usage: const TokenUsage(uncached: 9000, output: 120)),
        ],
        [say('看完了：一个页面、一份样式，结构很清楚。'), ChatDelta(finishReason: 'stop', usage: const TokenUsage(uncached: 10800, output: 260))],
      ];
      await tester.runAsync(() async {
        env = await TestEnv.create(chatClient: () => ScriptedChatClient(script));
        await env.services.models.upsert(
          name: '我的中转站',
          protocol: ChatProtocol.openaiChat,
          baseUrl: 'https://relay.example.cn/v1',
          apiKey: 'test',
          models: [ModelSpec(id: 'some-model', contextLength: 128000)],
        );
        project = await env.services.projects.create('我的小站', ProjectTemplate.web);
        session = ProjectSession(env.services, project);
        await session.loadChat();
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      addTearDown(() async {
        session.dispose();
        await env.dispose();
      });
      await tester.pumpWidget(
        appFor(
          env,
          ProjectShell(project: project, session: session, initial: ShellDest.chat),
          mode: mode,
          font: kTestFont,
        ),
      );
      await settle(tester);
      await tester.runAsync(() => session.sendToAgent('看看项目里有什么').timeout(const Duration(seconds: 20)));
      await settle(tester, rounds: 3);
      final expected = await tester.runAsync(() => session.contextSegments());
      expect(expected, isNotNull);
      expect(expected!.system, greaterThan(0));
      expect(expected.tools, greaterThan(0));
      expect(expected.messages, greaterThan(0));
      expect(expected.toolResults, greaterThan(0), reason: '这一轮读了文件：工具结果单独成段');

      await tester.tap(find.byKey(const Key('context-ring')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await settle(tester);
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('context-bar')), findsOneWidget);
      for (final (id, label, tokens) in [
        ('system', '系统提示词', expected.system),
        ('tools', '工具定义', expected.tools),
        ('messages', '对话消息', expected.messages),
        ('results', '工具结果', expected.toolResults),
        ('rest', '剩余', expected.remaining),
      ]) {
        final row = find.byKey(Key('context-legend-$id'));
        expect(row, findsOneWidget);
        expect(find.descendant(of: row, matching: find.text(label)), findsOneWidget);
        expect(find.descendant(of: row, matching: find.text('≈ ${formatTokens(tokens)}')), findsOneWidget);
        expect(find.descendant(of: row, matching: find.text(segmentPercent(expected.shareOf(tokens)))), findsOneWidget);
      }
      // 在“上下文”那一节里：百分比那行下面紧跟着横条，横条不超出面板。
      final pct = tester.getRect(find.byKey(const Key('usage-context-pct')));
      final bar = tester.getRect(find.byKey(const Key('context-bar')));
      expect(bar.top, greaterThanOrEqualTo(pct.bottom));
      expect(bar.top - pct.bottom, lessThan(40));
      expect(bar.left, greaterThanOrEqualTo(0));
      expect(bar.right, lessThanOrEqualTo(390));
      expect(tester.widget<Text>(find.byKey(const Key('usage-context-parts'))).data, contains('估算'));
      await shot(tester, 'ctx-02-usage-sheet-segments-$suffix');
    });

    testWidgets('不是命令的工具结果被转存：步骤详情里也有“查看完整输出”，点开是全文；文件被清掉了说清楚 ($suffix)', (tester) async {
      await bootEnv(tester);
      final full = [for (var i = 1; i <= 2000; i++) '第 $i 条搜索结果 ${'内容' * 8}'].join('\n');
      const rel = '.lopicode/outputs/tool-20261125073000-0.txt';
      final result = spilledToolText(full, rel);
      final asked = <String>[];
      String? stored = full;
      await tester.pumpWidget(
        appFor(
          env,
          Scaffold(
            body: SafeArea(
              child: ChatRowActions(
                readOutput: (r) async {
                  asked.add(r);
                  return stored;
                },
                child: ListView(
                  padding: const EdgeInsets.all(Space.x4),
                  children: [
                    for (final row in deriveChatRows(
                      [const UserItem('搜一下'), ToolItem('s1', 'web_search', '{"query":"flutter"}', result: result), const AssistantItem('搜到了。')],
                      busy: false,
                      showThinking: true,
                    ))
                      ChatRowView(row: row),
                  ],
                ),
              ),
            ),
          ),
          mode: mode,
          font: kTestFont,
        ),
      );
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('step-s1')));
      await tester.pumpAndSettle();
      expect(find.text('查看完整输出'), findsOneWidget);
      await shot(tester, 'ctx-03-tool-output-spilled-$suffix');
      await tester.ensureVisible(find.text('查看完整输出'));
      await tester.tap(find.text('查看完整输出'));
      await tester.pumpAndSettle();
      expect(asked, [rel]);
      expect(find.byKey(const ValueKey('output-full-text')), findsOneWidget);
      expect(find.textContaining('第 1000 条搜索结果'), findsOneWidget, reason: '中间被省略的部分在这里看得到');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      stored = null;
      await tester.tap(find.text('查看完整输出'));
      await tester.pumpAndSettle();
      expect(find.textContaining('已经不在了'), findsOneWidget);
      expect(find.textContaining('重新做一次'), findsOneWidget);
    });
  }
}
