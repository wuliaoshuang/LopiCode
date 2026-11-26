// 步骤时间线（圆点四种状态 + 竖线 + 结果摘要 + 用时）和按工具分别排的详情：390×844 浅色 + 深色。
//   LOPI_SHOTS=1 flutter test test/step_timeline_ui_test.dart   # 同时写截图到 docs/screenshots/
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/agent/agent_tools.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/session/chat_items.dart';
import 'package:lopicode/session/chat_rows.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/chat_row_view.dart';
import 'package:lopicode/ui/chat_steps.dart';
import 'package:lopicode/ui/step_detail.dart';
import 'package:lopicode/ui/step_timeline.dart';
import 'package:material_ui/material_ui.dart';

import 'agent_test.dart' show RecordingRunner;
import 'screens_test.dart' show shot, fontsLoaded;
import 'session_system_test.dart' show RoutingClient, reply, use;
import 'support/harness.dart';

final DateTime kNow = DateTime(2026, 11, 25, 16, 0, 0);

ToolItem tool(String id, String name, Map<String, dynamic> args, {String? result = 'ok', bool ok = true, bool denied = false, int? ms, DateTime? startedAt}) =>
    ToolItem(id, name, jsonEncode(args), result: result, ok: ok, denied: denied, ms: ms, startedAt: startedAt);

/// 一轮里四种状态都有：成功（带 / 不带用时）、失败、被拒绝、正在跑。
List<ChatItem> timelineItems({bool running = true}) => [
  const UserItem('跑一下测试，清掉旧文件'),
  tool('t1', 'read_file', {'path': 'package.json'}, result: '{\n  "name": "site"\n}', ms: 120),
  tool('t2', 'run_command', {'command': 'npm install'}, result: '退出码 0\nadded 212 packages in 12s\n\n31 packages are looking for funding\n  run `npm fund` for details', ms: 12400),
  tool('t3', 'run_command', {'command': 'npm test'}, result: '退出码 1\n  ok renders header\n  FAIL toggles dark mode\n1 failing', ok: false, ms: 2449),
  tool('t4', 'delete_file', {'path': 'old/notes.txt'}, result: '用户拒绝了这次删除，文件没有被改动。', ok: false, denied: true, ms: 8000),
  tool('t5', 'web_search', {'query': 'vitest dark mode toggle'}, result: '1. Vitest 文档：模拟 matchMedia\n   https://a\n   …\n\n2. 第二条\n   https://b\n   …', ms: 1800),
  if (running) tool('t6', 'run_command', {'command': 'npm test -- --watch=false'}, result: null, startedAt: kNow.subtract(const Duration(seconds: 75))),
];

void main() {
  setUpAll(() async => fontsLoaded = await loadRealFonts());
  setUp(() => stepClock = () => kNow);
  tearDown(() => stepClock = DateTime.now);

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    final suffix = mode == ThemeMode.light ? 'light' : 'dark';
    late TestEnv env;

    Future<void> showRows(WidgetTester tester, List<ChatItem> items, {bool busy = false, bool still = false}) async {
      usePhoneViewport(tester);
      await tester.runAsync(() async => env = await TestEnv.create());
      addTearDown(() => env.dispose());
      await tester.pumpWidget(
        appFor(
          env,
          Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: still),
              child: Scaffold(
                body: SafeArea(
                  child: ListView(
                    padding: const EdgeInsets.all(Space.x4),
                    children: [for (final row in deriveChatRows(items, busy: busy)) ChatRowView(row: row)],
                  ),
                ),
              ),
            ),
          ),
          mode: mode,
          font: kTestFont,
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
    }

    Future<void> expand(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey('step-group-t1')));
      // 有一步在转圈：不能等“全部静止”。
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('时间线展开：四种状态的圆点形状各不相同，每步下面有结果摘要，行尾有用时 ($suffix)', (tester) async {
      await showRows(tester, timelineItems(), busy: true);
      await expand(tester);
      expect(tester.takeException(), isNull);

      // 四种状态各自的圆点
      expect(find.byKey(const ValueKey('step-marker-ok')), findsNWidgets(3));
      expect(find.byKey(const ValueKey('step-marker-failed')), findsOneWidget);
      expect(find.byKey(const ValueKey('step-marker-denied')), findsOneWidget);
      expect(find.byKey(const ValueKey('step-marker-running')), findsOneWidget);
      // 形状不同：失败是叉、被拒绝是圆圈斜杠、进行中是环；不只是换颜色
      expect(find.descendant(of: find.byKey(const ValueKey('step-marker-failed')), matching: find.byIcon(Icons.close)), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('step-marker-denied')), matching: find.byIcon(Icons.block)), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('step-marker-running')), matching: find.byType(CircularProgressIndicator)), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('step-marker-ok')), matching: find.byType(Icon)), findsNothing);
      // 失败 / 被拒绝在行尾还有字
      expect(find.text('失败'), findsOneWidget);
      expect(find.text('已拒绝'), findsOneWidget);

      // 结果摘要：不用点开就看得到
      expect(find.descendant(of: find.byKey(const ValueKey('step-digest-t1')), matching: find.text('3 行')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('step-digest-t2')), matching: find.text('退出码 0')), findsOneWidget);
      expect(find.text('run `npm fund` for details'), findsOneWidget);
      final exit = tester.widget<Text>(find.descendant(of: find.byKey(const ValueKey('step-digest-t3')), matching: find.text('退出码 1')));
      expect(exit.style!.color, (mode == ThemeMode.light ? AppColors.light : AppColors.dark).danger, reason: '退出码非 0 标红');
      expect(find.text('1 failing'), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('step-digest-t4')), matching: find.text('用户拒绝了这次删除，文件没有被改动。')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('step-digest-t5')), matching: find.text('2 条结果')), findsOneWidget);
      expect(find.text('Vitest 文档：模拟 matchMedia'), findsOneWidget);
      // 正在跑的那一步还没有结果：没有摘要
      expect(find.byKey(const ValueKey('step-digest-t6')), findsNothing);

      // 用时：不到 1 秒的不显示；做完的显示总用时；正在跑的显示已经跑了多久
      expect(find.byKey(const ValueKey('step-elapsed-t1')), findsNothing);
      expect(tester.widget<Text>(find.byKey(const ValueKey('step-elapsed-t2'))).data, '12 秒');
      expect(tester.widget<Text>(find.byKey(const ValueKey('step-elapsed-t3'))).data, '2.4 秒');
      expect(tester.widget<Text>(find.byKey(const ValueKey('step-elapsed-t6'))).data, '1 分 15 秒');
      await shot(tester, '82-timeline-running-$suffix');

      // 每秒跳一次
      stepClock = () => kNow.add(const Duration(seconds: 3));
      await tester.pump(const Duration(seconds: 1));
      expect(tester.widget<Text>(find.byKey(const ValueKey('step-elapsed-t6'))).data, '1 分 18 秒');
    });

    testWidgets('做完的一轮：折叠时失败 / 被拒绝的露在外面并带原因；展开是完整时间线 ($suffix)', (tester) async {
      await showRows(tester, [...timelineItems(running: false), const AssistantItem('测试没过：深色模式的切换有问题。')]);
      // 折叠：露出最后两条失败 / 被拒绝的，各带一行原因；成功的不露
      expect(find.byType(StepRow), findsNWidgets(2));
      expect(find.text('退出码 1'), findsOneWidget);
      expect(find.text('用户拒绝了这次删除，文件没有被改动。'), findsOneWidget);
      expect(find.text('退出码 0'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('step-group-t1')));
      await tester.pumpAndSettle();
      expect(find.byType(StepRow), findsNWidgets(5));
      expect(find.byKey(const ValueKey('step-marker-running')), findsNothing);
      expect(tester.takeException(), isNull);
      await shot(tester, '83-timeline-failed-$suffix');
    });

    testWidgets('系统开了“减少动画”：进行中的圆点不转，用时照样每秒跳 ($suffix)', (tester) async {
      await showRows(
        tester,
        [
          const UserItem('跑测试'),
          tool('t6', 'run_command', {'command': 'npm test'}, result: null, startedAt: kNow.subtract(const Duration(seconds: 5))),
        ],
        busy: true,
        still: true,
      );
      expect(find.descendant(of: find.byKey(const ValueKey('step-marker-running')), matching: find.byType(CircularProgressIndicator)), findsNothing);
      expect(tester.widget<Text>(find.byKey(const ValueKey('step-elapsed-t6'))).data, '5 秒');
      stepClock = () => kNow.add(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 1));
      expect(tester.widget<Text>(find.byKey(const ValueKey('step-elapsed-t6'))).data, '7 秒');
      // 跑完：停表，换成总用时（界面拆掉以后不能留着没取消的定时器——测试框架会查）
      await showRows(tester, [
        const UserItem('跑测试'),
        tool('t6', 'run_command', {'command': 'npm test'}, result: '退出码 0\nok', ms: 7300),
      ]);
      expect(tester.widget<Text>(find.byKey(const ValueKey('step-elapsed-t6'))).data, '7.3 秒');
      await tester.pump(const Duration(seconds: 3));
      expect(tester.widget<Text>(find.byKey(const ValueKey('step-elapsed-t6'))).data, '7.3 秒');
    });

    testWidgets('重新打开的旧记录（没有开始时间、没有用时）：不显示用时，也不开表 ($suffix)', (tester) async {
      await showRows(tester, [
        const UserItem('看看'),
        tool('o1', 'run_command', {'command': 'ls'}, result: '退出码 0\na\nb'),
      ]);
      expect(find.byKey(const ValueKey('step-elapsed-o1')), findsNothing);
      expect(find.text('退出码 0'), findsOneWidget);
    });

    testWidgets('详情按工具分别排：命令是 命令 / 输出 / 退出码；读文件是 文件（带行范围）/ 内容；能复制 ($suffix)', (tester) async {
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied.add('${(call.arguments as Map)['text']}');
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await showRows(tester, [
        const UserItem('跑测试'),
        tool('c1', 'run_command', {'command': 'npm test'}, result: '退出码 1\n  FAIL toggles dark mode\n1 failing', ok: false, ms: 2449),
        tool('c2', 'read_file', {'path': 'lib/a.dart', 'start_line': 10, 'end_line': 12}, result: '（lib/a.dart 第 10–12 行，全文共 80 行）\nfinal a = 1;\nfinal b = 2;\nfinal c = 3;', ms: 40),
        tool('c3', 'mcp__docs__search', {'q': 'dark'}, result: '找到 2 篇\n- a\n- b'),
        const AssistantItem('有一个测试没过。'),
      ]);
      await tester.tap(find.byKey(const ValueKey('step-group-c1')));
      await tester.pumpAndSettle();

      // 命令
      await tester.tap(find.byKey(const ValueKey('step-c1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('step-digest-c1')), findsNothing, reason: '点开以后摘要让位给详情，不重复');
      expect(find.text('命令'), findsOneWidget);
      expect(find.text(r'$ npm test'), findsOneWidget);
      expect(find.text('报错'), findsOneWidget);
      expect(find.text('  FAIL toggles dark mode\n1 failing'), findsOneWidget);
      expect(find.text('退出码'), findsOneWidget);
      // 一处是详情里的退出码，另一处是组标题上的红色失败计数
      expect(find.text('1'), findsNWidgets(2));
      expect(tester.widget<Text>(find.byKey(const ValueKey('step-detail-span'))).data, '用了 2.4 秒');
      // 限高
      final box = tester.getSize(find.ancestor(of: find.text(r'$ npm test'), matching: find.byType(Container)).first);
      expect(box.height, lessThanOrEqualTo(kStepDetailHeight));
      await shot(tester, '84-step-detail-command-$suffix');
      await tester.tap(find.byKey(const ValueKey('step-copy')));
      await tester.pump();
      expect(copied.single, '退出码 1\n  FAIL toggles dark mode\n1 failing');
      await tester.pump(const Duration(seconds: 6)); // 等提示条消失
      await tester.tap(find.byKey(const ValueKey('step-c1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('step-digest-c1')), findsOneWidget);

      // 读文件
      await tester.tap(find.byKey(const ValueKey('step-c2')));
      await tester.pumpAndSettle();
      expect(find.text('lib/a.dart · 第 10–12 行（全文 80 行）'), findsOneWidget);
      expect(find.text('内容'), findsOneWidget);
      expect(find.text('final a = 1;\nfinal b = 2;\nfinal c = 3;'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('step-c2')));
      await tester.pumpAndSettle();

      // 不认识的工具：参数 + 结果
      await tester.tap(find.byKey(const ValueKey('step-c3')));
      await tester.pumpAndSettle();
      expect(find.text('参数'), findsOneWidget);
      expect(find.text('结果'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('对象很长、摘要很长：390 宽不溢出 ($suffix)', (tester) async {
      await showRows(tester, [
        const UserItem('跑'),
        tool('w1', 'run_command', {'command': 'cd packages/very/long/path && npm run build -- --mode production --verbose --no-color'}, result: '退出码 3\n${'很长的一行输出' * 40}', ok: false, ms: 754000),
        tool('w2', 'spawn_agent', {'name': '调研员', 'task': '查一下深色模式的常见做法并写成对照表'}, result: '子代理“调研员”的汇报：\n${'结论很长' * 60}', ms: 91000),
        const AssistantItem('好了。'),
      ]);
      await tester.tap(find.byKey(const ValueKey('step-group-w1')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(tester.widget<Text>(find.byKey(const ValueKey('step-elapsed-w1'))).data, '12 分 34 秒');
    });
  }

  group('用时存进记录', () {
    test('记录里的 _ms 读成这一步的用时；没有、类型不对、是负数都当没有，不崩', () {
      List<ChatItem> load(Object? ms, {bool withKey = true}) => chatItemsFromMessages(
        [
          {'role': 'user', 'content': '跑'},
          {
            'role': 'assistant',
            'content': '',
            'tool_calls': [
              {
                'id': 'c1',
                'function': {'name': 'run_command', 'arguments': '{"command":"ls"}'},
              },
            ],
          },
          {'role': 'tool', 'tool_call_id': 'c1', 'content': '退出码 0\na', '_ms': ?(withKey ? ms : null)},
        ],
        childConversationIds: const [],
        hostPathOf: (r) => r,
      );
      ToolItem only(List<ChatItem> items) => items.whereType<ToolItem>().single;
      expect(only(load(1234)).ms, 1234);
      expect(only(load(0)).ms, 0);
      expect(only(load(null, withKey: false)).ms, isNull);
      expect(only(load('12')).ms, isNull);
      expect(only(load(1.5)).ms, isNull);
      expect(only(load(-3)).ms, isNull);
      expect(only(load({'x': 1})).ms, isNull);
      expect(only(load(1234)).startedAt, isNull, reason: '重新打开的记录不会再开表');
    });

    test('真跑一轮：每步的用时写进记录，重新打开对话还在；进行中的那一步带开始时间', () async {
      var n = 0;
      final env = await TestEnv.create(
        chatClient: () => RoutingClient(
          (m, t) => switch (n++) {
            0 => use('list_files', {}),
            1 => use('run_command', {'command': 'npm test'}),
            _ => reply('好了。'),
          },
          [],
        ),
      );
      addTearDown(env.dispose);
      final Project project = await env.services.projects.create('小站', ProjectTemplate.web);
      var session = ProjectSession(env.services, project, headless: true)..commandRunnerFactory = RecordingRunner.new;
      await session.loadChat();
      await session.setPermission(PermissionLevel.full);
      await session.sendToAgent('跑测试');
      final live = session.chat.whereType<ToolItem>().toList();
      expect(live.map((t) => t.name), ['list_files', 'run_command']);
      for (final t in live) {
        expect(t.ms, isNotNull, reason: t.name);
        expect(t.ms, greaterThanOrEqualTo(0));
        expect(t.startedAt, isNotNull);
      }
      session.dispose();
      session = ProjectSession(env.services, project, headless: true)..commandRunnerFactory = RecordingRunner.new;
      addTearDown(session.dispose);
      await session.loadChat();
      final again = session.chat.whereType<ToolItem>().toList();
      expect(again.map((t) => t.ms), live.map((t) => t.ms), reason: '重开后用时和当时一样');
      expect(again.every((t) => t.startedAt == null), isTrue);
    });
  });
}
