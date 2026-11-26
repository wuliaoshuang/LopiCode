// Agent 的一整轮是一条连续的内容流（2026-11-26 真机反馈第五轮）：
// “思考→说话→工具→说话→工具→最终回答”在聊天页上的结构——Agent 这边不套气泡、操作栏一轮只有一排、一轮中间的段怎么单独操作。
//   LOPI_SHOTS=1 LOPI_FLOW_TAG=after flutter test test/chat_flow_ui_test.dart   # 顺带写 docs/screenshots/flow-<tag>-*.png
// 做完的一轮走真实聊天页（从存档读，带操作栏）；进行到一半的走行列表（不依赖时间）。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/session/chat_rows.dart';
import 'package:lopicode/state/workspace_favorites.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/chat_extras.dart';
import 'package:lopicode/ui/chat_row_view.dart';
import 'package:lopicode/ui/message_action_bar.dart';
import 'package:lopicode/ui/message_text.dart';
import 'package:lopicode/ui/project_shell.dart';
import 'package:material_ui/material_ui.dart';

import 'screens_test.dart' show fontsLoaded, shot;
import 'support/harness.dart';

final String kFlowTag = Platform.environment['LOPI_FLOW_TAG'] ?? 'after';

Map<String, dynamic> _calls(String id, String text, String thought, int ms, List<(String, String, String)> calls) => {
  'role': 'assistant',
  'content': text,
  '_id': id,
  '_reasoning': thought,
  '_reasoningMs': ms,
  'tool_calls': [
    for (final (cid, name, args) in calls)
      {
        'id': cid,
        'type': 'function',
        'function': {'name': name, 'arguments': args},
      },
  ],
};

Map<String, dynamic> _result(String cid, String text) => {'role': 'tool', 'tool_call_id': cid, 'content': text};

/// 思考 → 说话 → 两步 → 思考 → 说话 → 两步 → 思考 → 最终回答。
final List<Map<String, dynamic>> kFlowSeed = [
  {'role': 'user', 'content': '给首页加一个深色模式开关', '_id': 'u1'},
  _calls('a1', '我先看看项目里有哪些文件。', '用户要深色模式开关。先确认页面结构和现有样式，再决定按钮放哪。', 6200, [('c1', 'list_files', '{}'), ('c2', 'read_file', '{"path":"index.html"}')]),
  _result('c1', 'index.html\nstyle.css\napp.js'),
  _result('c2', '<!doctype html>\n<html>…</html>'),
  _calls('a2', '页面结构清楚了，接下来加一份深色样式，再在右上角放按钮。', '页面只有一个 header，按钮放右上角最合适。样式单独一个文件，方便以后改。', 3100, [
    ('c3', 'write_file', '{"path":"dark.css","content":"body.dark { background: #111; color: #eee; }"}'),
    ('c4', 'edit_file', '{"path":"index.html","old":"</header>","new":"<button id=\\"theme\\">深色</button></header>"}'),
  ]),
  _result('c3', '已写入 dark.css（44 字符）'),
  _result('c4', '已修改 index.html'),
  {'role': 'assistant', 'content': '加好了：右上角多了一个“深色”按钮，点一下整页切到深色，再点切回来。样式在 dark.css 里，想调颜色改它就行。', '_id': 'a3', '_reasoning': '两步都成功了，告诉她怎么用、去哪改。', '_reasoningMs': 2400},
];

void main() {
  setUpAll(() async => fontsLoaded = await loadRealFonts());

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    final suffix = mode == ThemeMode.light ? 'light' : 'dark';

    late TestEnv env;
    late Project project;
    late ProjectSession session;

    Future<void> open(WidgetTester tester, List<Map<String, dynamic>> seed) async {
      usePhoneViewport(tester);
      await tester.runAsync(() async {
        env = await TestEnv.create();
        project = await env.services.projects.create('我的小站', ProjectTemplate.web);
        Directory('${project.dir}/.lopicode').createSync(recursive: true);
        File('${project.dir}/.lopicode/chat.json').writeAsStringSync(jsonEncode(seed));
        session = ProjectSession(env.services, project);
        await session.loadChat();
      });
      addTearDown(() async {
        session.dispose();
        await env.dispose();
      });
      await tester.pumpWidget(
        appFor(
          env,
          ProjectShell(project: project, session: session),
          mode: mode,
          font: kTestFont,
        ),
      );
      await settle(tester, rounds: 6);
    }

    Finder words(String text) => find.byWidgetPredicate((w) => w is MessageText && w.text == text);
    Finder boxed(Finder inner) => find.ancestor(
      of: inner,
      matching: find.descendant(
        of: find.byType(ChatRowView),
        matching: find.byWidgetPredicate((w) => w is Container && w.decoration is BoxDecoration && (w.decoration! as BoxDecoration).color != null),
      ),
    );
    Future<void> steps(WidgetTester tester) async {
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 150));
      }
    }

    Future<void> more(WidgetTester tester, String id, String action) async {
      await tester.ensureVisible(find.byKey(ValueKey('message-more-$id')));
      await tester.pump();
      await tester.tap(find.byKey(ValueKey('message-more-$id')));
      await steps(tester);
      await tester.tap(find.byKey(ValueKey('more-$action')));
      await steps(tester);
    }

    testWidgets('一整轮做完：思考、说的话、步骤按先后排；Agent 这边没有气泡；操作栏一轮只有一排（$suffix）', (tester) async {
      await open(tester, kFlowSeed);
      const said = ['我先看看项目里有哪些文件。', '页面结构清楚了，接下来加一份深色样式，再在右上角放按钮。'];
      const answer = '加好了：右上角多了一个“深色”按钮，点一下整页切到深色，再点切回来。样式在 dark.css 里，想调颜色改它就行。';
      // 正文都走同一个控件；我的消息有气泡，Agent 的三段话都没有
      expect(boxed(words('给首页加一个深色模式开关')), findsOneWidget, reason: '我的消息是气泡');
      for (final t in [...said, answer]) {
        expect(words(t), findsOneWidget, reason: '$t：中间说的话也一直看得见');
        expect(boxed(words(t)), findsNothing, reason: '$t：Agent 这边不套气泡');
        expect(tester.getTopLeft(words(t)).dx, Space.x4, reason: '左对齐通栏');
      }
      // 三段思考都看得见（都在说话之前，各占一行），不用展开步骤组
      expect(find.byType(ThinkingRow), findsNWidgets(3));
      expect(find.text('思考了 6 秒'), findsOneWidget);
      expect(find.text('思考了 3 秒'), findsOneWidget);
      expect(find.text('思考了 2 秒'), findsOneWidget);
      // 从上到下的先后：思考 → 说话 → 两步 → 思考 → 说话 → 两步 → 思考 → 回答
      final ys = [
        tester.getTopLeft(find.text('思考了 6 秒')).dy,
        tester.getTopLeft(words(said[0])).dy,
        tester.getTopLeft(find.byKey(const ValueKey('step-group-c1'))).dy,
        tester.getTopLeft(find.text('思考了 3 秒')).dy,
        tester.getTopLeft(words(said[1])).dy,
        tester.getTopLeft(find.byKey(const ValueKey('step-group-c3'))).dy,
        tester.getTopLeft(find.text('思考了 2 秒')).dy,
        tester.getTopLeft(words(answer)).dy,
      ];
      expect(ys, orderedEquals([...ys]..sort()));
      // 操作栏：我的消息一排、Agent 这一轮末尾一排；中间的段下面没有
      expect(find.byType(MessageActionBar), findsNWidgets(2));
      expect(find.byKey(const ValueKey('message-actions-a3')), findsOneWidget);
      expect(find.byKey(const ValueKey('message-actions-a1')), findsNothing);
      expect(find.byKey(const ValueKey('message-actions-a2')), findsNothing);
      expect(tester.getTopLeft(find.byKey(const ValueKey('message-actions-a3'))).dy, greaterThan(ys.last));
      final target = tester.widget<MessageActionBar>(find.ancestor(of: find.byKey(const ValueKey('message-actions-a3')), matching: find.byType(MessageActionBar))).target;
      expect(target.copyText, [...said, answer].join('\n\n'), reason: '复制＝这一轮说的话连起来');
      await shot(tester, 'flow-$kFlowTag-done-$suffix');
      // 点开思考看全文
      await tester.tap(find.text('思考了 6 秒'));
      await tester.pumpAndSettle();
      expect(find.textContaining('先确认页面结构和现有样式'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('一轮中间的段：从末尾“更多”里先选哪一段，再收藏 / 删除；收藏着的段让这一轮末尾亮书签（$suffix）', (tester) async {
      await open(tester, kFlowSeed);
      // 收藏中间那一段
      await more(tester, 'a3', 'favorite');
      expect(find.text('收藏 / 取消收藏哪一段？'), findsOneWidget);
      for (final id in ['a1', 'a2', 'a3']) {
        expect(find.byKey(ValueKey('reply-part-$id')), findsOneWidget);
      }
      await shot(tester, 'flow-$kFlowTag-pick-part-$suffix');
      await tester.tap(find.byKey(const ValueKey('reply-part-a2')));
      await settle(tester, rounds: 3);
      expect(env.services.container.read(favoritesProvider(session)).items.single.text, '页面结构清楚了，接下来加一份深色样式，再在右上角放按钮。');
      expect(find.byKey(const ValueKey('message-favorite-a3')), findsOneWidget, reason: '这一轮有一段收藏着：末尾亮书签');
      // 点书签：面板里标出哪一段收藏着；再选它＝取消
      await tester.tap(find.byKey(const ValueKey('message-favorite-a3')));
      await steps(tester);
      expect(find.text('第 2 段 · 已收藏'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('reply-part-a2')));
      await settle(tester, rounds: 3);
      expect(env.services.container.read(favoritesProvider(session)).items, isEmpty);
      expect(find.byKey(const ValueKey('message-favorite-a3')), findsNothing);

      // 分支：也先选哪一段
      await more(tester, 'a3', 'branch');
      expect(find.text('从哪一段分支？'), findsOneWidget);
      await tester.tapAt(const Offset(195, 60));
      await tester.pumpAndSettle();

      // 只删中间那一段的话：字没了，它后面的步骤还在
      await more(tester, 'a3', 'delete');
      expect(find.text('删哪一段？'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('reply-part-a1')));
      await tester.pumpAndSettle();
      expect(tester.widget<ListTile>(find.byKey(const ValueKey('delete-message'))).selected, isTrue);
      await tester.tap(find.byKey(const ValueKey('delete-confirm')));
      await settle(tester, rounds: 4);
      expect(words('我先看看项目里有哪些文件。'), findsNothing);
      expect(find.byKey(const ValueKey('step-group-c1')), findsOneWidget);
      expect(words('页面结构清楚了，接下来加一份深色样式，再在右上角放按钮。'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('被停下的一轮（只留下工具之间说的话）：操作栏挂在那句话下面，这一轮照样有入口（$suffix）', (tester) async {
      await open(tester, [...kFlowSeed.take(4)]);
      expect(find.byKey(const ValueKey('message-actions-a1')), findsOneWidget);
      expect(find.byType(MessageActionBar), findsNWidgets(2));
      for (final k in ['copy', 'edit', 'retry', 'more']) {
        expect(find.byKey(ValueKey('message-$k-a1')), findsOneWidget, reason: k);
      }
    });

    testWidgets('进行到一半：第二段话刚说完、下一步还没开始（$suffix）', (tester) async {
      usePhoneViewport(tester);
      await tester.runAsync(() async => env = await TestEnv.create());
      addTearDown(() => env.dispose());
      final items = <ChatItem>[
        const UserItem('给首页加一个深色模式开关'),
        const ThinkingItem('用户要深色模式开关。先确认页面结构和现有样式，再决定按钮放哪。', ms: 6200),
        const AssistantItem('我先看看项目里有哪些文件。'),
        const ToolItem('c1', 'list_files', '{}', result: 'index.html\nstyle.css\napp.js'),
        const ToolItem('c2', 'read_file', '{"path":"index.html"}', result: '<!doctype html>'),
        const ThinkingItem('页面只有一个 header，按钮放右上角最合适。', ms: 3100),
        const AssistantItem('页面结构清楚了，接下来加一份深色样式，再在右上角放按钮。', streaming: true),
      ];
      await tester.pumpWidget(
        appFor(
          env,
          Scaffold(
            body: SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(Space.x4),
                children: [for (final row in deriveChatRows(items, busy: true)) ChatRowView(row: row)],
              ),
            ),
          ),
          mode: mode,
          font: kTestFont,
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      // 前面说过的话、做过的步骤、想过的都还在原地；正在冒的这段话下面没有操作栏
      expect(find.text('我先看看项目里有哪些文件。'), findsOneWidget);
      expect(find.byKey(const ValueKey('step-group-c1')), findsOneWidget);
      expect(find.byType(ThinkingRow), findsNWidgets(2));
      expect(find.byType(MessageActionBar), findsNothing);
      await shot(tester, 'flow-$kFlowTag-live-$suffix');
    });

    testWidgets('两步之间正在想：步骤组那一行写“正在思考…”（$suffix）', (tester) async {
      usePhoneViewport(tester);
      await tester.runAsync(() async => env = await TestEnv.create());
      addTearDown(() => env.dispose());
      final items = <ChatItem>[
        const UserItem('看看'),
        const ToolItem('c1', 'read_file', '{"path":"a.txt"}', result: 'hello'),
        ThinkingItem('再看一个文件。', streaming: true, startedAt: DateTime.now().subtract(const Duration(seconds: 3))),
      ];
      await tester.pumpWidget(
        appFor(
          env,
          Scaffold(
            body: ListView(children: [for (final row in deriveChatRows(items, busy: true)) ChatRowView(row: row)]),
          ),
          mode: mode,
          font: kTestFont,
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('step-group-thinking')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const ValueKey('step-group-thinking'))).data, matches(RegExp(r'^正在思考… \d+ 秒$')));
      await tester.pumpWidget(const SizedBox());
    });
  }
}
