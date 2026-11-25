// 设置 › 能力 › 记忆（390×844，浅色 + 深色）：两个开关的默认值和费用说明、条目列表、点开看 / 改 / 删、新增、
// 像密钥的存不进去、撤销最近一次、清空；聊天步骤里的“记住了”；轨迹里的“整理记忆”。
//   flutter test test/settings_memory_test.dart
//   LOPI_SHOTS=1 flutter test test/settings_memory_test.dart   # 截图到 docs/screenshots/（mem-…）
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/agent/memory_store.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/stores.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/session/chat_rows.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/chat_row_view.dart';
import 'package:lopicode/ui/project_shell.dart';
import 'package:lopicode/ui/settings_memory.dart';
import 'package:lopicode/ui/settings_screen.dart';
import 'package:lopicode/ui/shell.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import 'screens_test.dart' show fontsLoaded, shot;
import 'session_system_test.dart' show RoutingClient, reply;
import 'support/harness.dart';

void main() {
  setUpAll(() async => fontsLoaded = await loadRealFonts());

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    final suffix = mode == ThemeMode.light ? 'light' : 'dark';
    late TestEnv env;
    late Project project;
    late ProjectSession session;

    AppMemory memory() => env.services.memory;

    /// [seed]：先放几条记忆进去。[open]：有没有打开工作区。
    Future<void> boot(WidgetTester tester, {bool seed = true, bool open = true, Widget? home}) async {
      usePhoneViewport(tester);
      await tester.runAsync(() async {
        env = await TestEnv.create(chatClient: () => RoutingClient((m, t) => jsonEncode(m).contains('记忆整理员') ? reply('{"items":[]}') : reply('好的。'), []));
        project = await env.services.projects.create('我的小站', ProjectTemplate.web);
        session = ProjectSession(env.services, project, headless: true);
        await session.loadChat();
        if (seed) {
          await memory().global.write('回答的风格', '用简体中文，先给结论再解释。\n步骤一步一步列出来。', by: 'user');
          await memory().global.write('提交说明', '提交说明用中文写，一行以内。');
          await memory().project(project).write('部署方式', '打包以后用 scp 传到服务器的 /opt/site。\n传完要重启 nginx。');
        }
      });
      addTearDown(() async {
        await tester.runAsync(() async {
          await memory().idle();
          session.dispose();
          await env.dispose();
        });
      });
      await tester.pumpWidget(
        appFor(
          env,
          home ?? MemorySettingsScreen(session: open ? session : null),
          mode: mode,
          font: kTestFont,
        ),
      );
      await settle(tester, rounds: 4);
    }

    /// 界面里点出来的存盘要走好多步真实文件读写：一小轮一小轮地等，直到条件成立。
    Future<void> until(WidgetTester tester, bool Function() done, String what) async {
      for (var i = 0; i < 60 && !done(); i++) {
        await settle(tester, rounds: 1);
      }
      expect(done(), isTrue, reason: '等不到：$what');
      await settle(tester, rounds: 2);
    }

    bool sw(WidgetTester tester, String key) => tester.widget<Switch>(find.byKey(Key(key))).value;
    Finder list() => find.descendant(of: find.byKey(const Key('memory-list')), matching: find.byType(Scrollable)).first;
    Future<void> reveal(WidgetTester tester, Finder f) async {
      await tester.scrollUntilVisible(f, 120, scrollable: list());
      await tester.ensureVisible(f);
      await settle(tester, rounds: 1);
    }

    Future<void> tapRow(WidgetTester tester, String key) async {
      await reveal(tester, find.byKey(Key(key)));
      await tester.tap(find.byKey(Key(key)));
      await settle(tester, rounds: 4);
    }

    testWidgets('两个开关：记忆默认开、自动整理默认关并写明要多花钱；关了总开关，自动整理跟着灰掉 ($suffix)', (tester) async {
      await boot(tester);
      expect(find.text('记忆'), findsWidgets);
      expect(sw(tester, 'memory-enabled'), isTrue);
      expect(sw(tester, 'memory-auto'), isFalse);
      expect(find.text('每轮结束后自动整理'), findsOneWidget);
      expect(find.text('每轮结束后会多花一次模型调用'), findsOneWidget, reason: '费用说明直接写在开关下面');
      expect(find.text('回答的风格'), findsOneWidget);
      expect(find.text('用简体中文，先给结论再解释。'), findsOneWidget, reason: '一行一条：标题 + 一句摘要');
      expect(tester.takeException(), isNull);
      await shot(tester, 'mem-01-page-top-$suffix');

      // 点名称（不点开关）也能切换；存下来了
      await tester.tap(find.text('每轮结束后自动整理'));
      await settle(tester, rounds: 3);
      expect(sw(tester, 'memory-auto'), isTrue);
      expect(env.services.settings.getBool(SettingKeys.memoryAutoConsolidate), isTrue);
      expect(memory().autoConsolidate, isTrue);

      await tester.tap(find.text('让 Agent 使用记忆'));
      await settle(tester, rounds: 3);
      expect(sw(tester, 'memory-enabled'), isFalse);
      expect(sw(tester, 'memory-auto'), isFalse, reason: '总开关关了：自动整理显示成关');
      expect(tester.widget<Switch>(find.byKey(const Key('memory-auto'))).onChanged, isNull, reason: '而且点不了');
      expect(memory().enabled, isFalse);
      expect(memory().autoConsolidate, isFalse);

      await reveal(tester, find.byKey(const Key('memory-clear-project')));
      expect(find.text('撤销最近一次改动'), findsOneWidget);
      expect(find.text('清空全局记忆'), findsOneWidget);
      expect(find.text('清空这个项目的记忆'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await shot(tester, 'mem-02-page-bottom-$suffix');
    });

    testWidgets('点开一条：看全文、改了保存（文件跟着变）；标题和正文各占一行 ($suffix)', (tester) async {
      await boot(tester);
      await tapRow(tester, 'memory-global-回答的风格');
      expect(find.byType(MemoryEntryScreen), findsOneWidget);
      expect(find.text('全局记忆'), findsOneWidget, reason: '顶栏副标题写明是哪一处');
      expect(tester.widget<TextField>(find.byKey(const Key('memory-body'))).controller!.text, contains('步骤一步一步列出来。'));
      expect(tester.getTopLeft(find.byKey(const Key('memory-body'))).dy, greaterThan(tester.getBottomLeft(find.byKey(const Key('memory-title'))).dy));
      expect(tester.takeException(), isNull);
      await shot(tester, 'mem-03-entry-$suffix');

      await tester.enterText(find.byKey(const Key('memory-body')), '用简体中文，回答短一点。');
      await tester.tap(find.byKey(const Key('memory-save')));
      await until(tester, () => find.byType(MemoryEntryScreen).evaluate().isEmpty, '存好就回到列表');
      expect(find.text('用简体中文，回答短一点。'), findsOneWidget, reason: '列表跟着变');
      final text = await tester.runAsync(() => File(p.join(env.tmp.path, 'memory', '回答的风格.md')).readAsString());
      expect(text, '# 回答的风格\n\n用简体中文，回答短一点。\n');
      expect(memory().global.changes.last.by, 'user');
    });

    testWidgets('删除一条要先确认；删错了能“撤销最近一次改动”放回来 ($suffix)', (tester) async {
      await boot(tester);
      await tapRow(tester, 'memory-project-部署方式');
      expect(find.text('项目记忆'), findsOneWidget);
      await tester.tap(find.byKey(const Key('memory-entry-menu')));
      await settle(tester, rounds: 3);
      await tester.tap(find.text('删除这一条'));
      await settle(tester, rounds: 3);
      expect(find.text('删除“部署方式”？'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await shot(tester, 'mem-04-delete-confirm-$suffix');
      await tester.tap(find.text('删除'));
      await until(tester, () => find.byType(MemoryEntryScreen).evaluate().isEmpty, '删完回到列表');
      expect(find.byKey(const Key('memory-project-部署方式')), findsNothing);
      expect(find.text('这个项目还没有记忆'), findsOneWidget);
      expect(File(p.join(project.dir, '.lopicode', 'memory', '部署方式.md')).existsSync(), isFalse);

      await reveal(tester, find.byKey(const Key('memory-undo')));
      expect(find.text('你删除了“部署方式”'), findsOneWidget, reason: '撤销那一行写明撤的是哪一次');
      await tester.tap(find.byKey(const Key('memory-undo')));
      await until(tester, () => memory().project(project).entries.isNotEmpty, '撤销完成');
      expect(memory().project(project).entries.single.title, '部署方式');
      expect(File(p.join(project.dir, '.lopicode', 'memory', '部署方式.md')).existsSync(), isTrue);
      expect(find.textContaining('已撤销'), findsOneWidget);
    });

    testWidgets('新增一条；像密钥的存不进去并说明原因；空标题也不行 ($suffix)', (tester) async {
      await boot(tester);
      await tapRow(tester, 'memory-add-global');
      expect(find.text('新增记忆'), findsOneWidget);
      await tester.tap(find.byKey(const Key('memory-save')));
      await settle(tester, rounds: 3);
      expect(find.text('标题不能为空'), findsOneWidget);
      expect(find.byType(MemoryEntryScreen), findsOneWidget);

      await tester.enterText(find.byKey(const Key('memory-title')), '服务器');
      await tester.enterText(find.byKey(const Key('memory-body')), '登录用的 key 是 sk-${'u7i8o9p0' * 3}');
      await tester.tap(find.byKey(const Key('memory-save')));
      await until(tester, () => find.textContaining('没有写入').evaluate().isNotEmpty, '拒绝的提示');
      expect(find.byType(MemoryEntryScreen), findsOneWidget, reason: '没存进去，留在这一页让她改');
      expect(memory().global.find('服务器'), isNull);
      expect(tester.takeException(), isNull);
      await shot(tester, 'mem-05-secret-rejected-$suffix');

      await tester.enterText(find.byKey(const Key('memory-body')), '服务器是 Ubuntu 24.04，网站放在 /opt/site。');
      await tester.tap(find.byKey(const Key('memory-save')));
      await until(tester, () => find.byType(MemoryEntryScreen).evaluate().isEmpty, '存好回到列表');
      expect(memory().global.find('服务器')!.body, '服务器是 Ubuntu 24.04，网站放在 /opt/site。');
      await reveal(tester, find.byKey(const Key('memory-global-服务器')));
      expect(find.text('服务器'), findsOneWidget);
    });

    testWidgets('清空要先确认，只清点的那一处；清完那一行灰掉 ($suffix)', (tester) async {
      await boot(tester);
      await tapRow(tester, 'memory-clear-global');
      expect(find.text('清空全局记忆？'), findsOneWidget);
      expect(find.textContaining('2 条都会被删除，不能撤销'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await settle(tester, rounds: 3);
      expect(memory().global.entries, hasLength(2), reason: '点取消什么都不动');

      await tapRow(tester, 'memory-clear-global');
      await tester.tap(find.text('清空'));
      await until(tester, () => memory().global.entries.isEmpty, '清空完成');
      expect(memory().global.entries, isEmpty);
      expect(memory().project(project).entries, hasLength(1), reason: '项目记忆没动');
      await reveal(tester, find.byKey(const Key('memory-add-global')));
      expect(find.text('还没有全局记忆'), findsOneWidget);
      // 再点已经灰掉的清空：没有反应
      await reveal(tester, find.byKey(const Key('memory-clear-global')));
      await tester.tap(find.byKey(const Key('memory-clear-global')), warnIfMissed: false);
      await settle(tester, rounds: 2);
      expect(find.text('清空全局记忆？'), findsNothing);
    });

    testWidgets('没打开工作区：项目记忆那组只有一行说明，全局记忆照常；还没有记忆时的样子 ($suffix)', (tester) async {
      await boot(tester, seed: false, open: false);
      expect(find.text('还没有全局记忆'), findsOneWidget);
      await reveal(tester, find.byKey(const Key('memory-no-project')));
      expect(find.text('打开一个工作区后，才能看它的项目记忆'), findsOneWidget);
      expect(find.byKey(const Key('memory-add-project')), findsNothing);
      expect(find.byKey(const Key('memory-clear-project')), findsNothing);
      await reveal(tester, find.byKey(const Key('memory-undo')));
      expect(find.text('现在没有可以撤销的'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await shot(tester, 'mem-06-empty-no-workspace-$suffix');
    });

    testWidgets('她直接改了文件：再进这一页看到的是新的 ($suffix)', (tester) async {
      await boot(tester, home: const SizedBox());
      await tester.runAsync(() => File(p.join(env.tmp.path, 'memory', '手写的.md')).writeAsString('# 手写的一条\n\n直接在文件里加的\n'));
      await tester.pumpWidget(
        appFor(
          env,
          MemorySettingsScreen(session: session),
          mode: mode,
          font: kTestFont,
        ),
      );
      await settle(tester, rounds: 5);
      expect(find.text('手写的一条'), findsOneWidget);
      expect(find.text('直接在文件里加的'), findsOneWidget);
    });

    testWidgets('设置一级页“能力”里有“记忆”入口，右边写着当前状态；点进去是记忆页 ($suffix)', (tester) async {
      await boot(tester, home: const SizedBox());
      await tester.pumpWidget(
        appFor(
          env,
          SettingsScreen(workspace: project, session: session),
          mode: mode,
          font: kTestFont,
        ),
      );
      await settle(tester, rounds: 4);
      final scroll = find.descendant(of: find.byKey(const Key('settings-list')), matching: find.byType(Scrollable)).first;
      final row = find.byKey(const Key('settings-memory'));
      await tester.scrollUntilVisible(row, 120, scrollable: scroll);
      // 让这一行停在屏幕中间偏上（别压在顶栏的渐隐下面）
      await Scrollable.ensureVisible(tester.element(row), alignment: 0.3);
      await settle(tester, rounds: 1);
      expect(find.descendant(of: row, matching: find.text('开')), findsOneWidget);
      expect(tester.getTopLeft(row).dy, greaterThan(tester.getTopLeft(find.byKey(const Key('settings-skills'))).dy), reason: '排在“技能”下面');
      expect(tester.takeException(), isNull);
      await shot(tester, 'mem-07-settings-entry-$suffix');

      await tester.tap(row);
      await settle(tester, rounds: 6);
      expect(find.byType(MemorySettingsScreen), findsOneWidget);
      await tester.tap(find.text('每轮结束后自动整理'));
      await settle(tester, rounds: 3);
      await tester.tap(find.byTooltip('返回').last);
      await settle(tester, rounds: 6);
      expect(
        find.descendant(of: row, matching: find.text('开 · 自动整理')),
        findsOneWidget,
        reason: '回到一级页，状态跟着变',
      );
    });

    testWidgets('聊天步骤里写明“记住了 + 标题”，折叠那一行有“记住 N 条” ($suffix)', (tester) async {
      await boot(tester, home: const SizedBox());
      ToolItem tool(String id, String name, Map<String, String> args, String result) => ToolItem(id, name, jsonEncode(args), result: result);
      final single = <ChatItem>[
        const UserItem('以后回答都短一点，记住'),
        tool('c1', 'memory_write', {'scope': 'global', 'title': '回答的风格', 'content': '回答短一点'}, '记住了：“回答的风格”（全局记忆，新增）。'),
        const AssistantItem('好的，记下了。'),
      ];
      final group = <ChatItem>[
        const UserItem('把这个项目的约定都记一下'),
        tool('d1', 'memory_search', {'query': '部署'}, '记忆里没有提到“部署”的内容。'),
        tool('d2', 'memory_write', {'scope': 'project', 'title': '部署方式', 'content': 'scp'}, '记住了：“部署方式”（项目记忆，新增）。'),
        tool('d3', 'memory_write', {'scope': 'project', 'title': '提交说明', 'content': '中文'}, '记住了：“提交说明”（项目记忆，新增）。'),
        tool('d4', 'conversation_search', {'query': '登录页'}, '找到 1 段…'),
        const AssistantItem('都记好了。'),
      ];
      await tester.pumpWidget(
        appFor(
          env,
          Scaffold(
            body: SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(Space.x4),
                children: [
                  for (final row in deriveChatRows([...single, ...group], busy: false)) ChatRowView(row: row),
                ],
              ),
            ),
          ),
          mode: mode,
          font: kTestFont,
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('记住了'), findsOneWidget, reason: '只有一步时直接一行：记住了 + 标题');
      expect(find.textContaining('回答的风格'), findsOneWidget);
      expect(find.textContaining('记住 2 条'), findsOneWidget, reason: '好几步折成一行时，摘要里写明记了几条');
      expect(tester.takeException(), isNull);
      await tester.tap(find.textContaining('记住 2 条'));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(find.textContaining('部署方式'), findsOneWidget);
      expect(find.textContaining('查历史对话'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await shot(tester, 'mem-08-chat-steps-$suffix');
    });

    testWidgets('自动整理发的那一次请求，在本轮轨迹里标着“整理记忆” ($suffix)', (tester) async {
      await boot(tester, seed: false, home: const SizedBox());
      await tester.runAsync(() async {
        await env.services.settings.set(SettingKeys.memoryAutoConsolidate, true);
        for (var i = 0; i < 3; i++) {
          await session.sendToAgent('问题 $i').timeout(const Duration(seconds: 20));
        }
        await memory().idle();
      });
      await tester.pumpWidget(
        appFor(
          env,
          ProjectShell(project: project, session: session, initial: ShellDest.chat),
          mode: mode,
          font: kTestFont,
        ),
      );
      await settle(tester, rounds: 4);
      final foot = find.byKey(const Key('turn-footnote'));
      expect(foot, findsWidgets);
      await tester.ensureVisible(foot.last);
      await tester.tap(foot.last);
      await settle(tester, rounds: 4);
      expect(find.text('本轮轨迹'), findsOneWidget);
      expect(find.text('模型请求 1'), findsOneWidget);
      expect(find.text('模型请求 2（整理记忆）'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await shot(tester, 'mem-09-trajectory-$suffix');
    });
  }
}
