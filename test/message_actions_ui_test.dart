// 消息操作的界面（390×844，浅 / 深）：操作栏出现在对的行、还在往外冒的回复没有、整轮级别的动作只在最后一段下面、
// “更多”面板、复制、收藏、分享、删除确认、Agent 正在回复时不能删、收藏页、跳回原消息。
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/session/chat_rows.dart';
import 'package:lopicode/session/message_actions.dart';
import 'package:lopicode/session/message_ops.dart';
import 'package:lopicode/state/workspace_favorites.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/chat_row_view.dart';
import 'package:lopicode/ui/message_action_bar.dart';
import 'package:lopicode/ui/project_shell.dart';
import 'package:material_ui/material_ui.dart';

import 'agent_test.dart' show RecordingRunner;
import 'agent_ui_test.dart' show waitReal;
import 'screens_test.dart' show fontsLoaded, shot;
import 'session_system_test.dart' show RoutingClient, Turn, hasToolResult, lastUser, reply, use;
import 'support/harness.dart';

void main() {
  setUpAll(() async => fontsLoaded = await loadRealFonts());

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    final suffix = mode == ThemeMode.light ? 'light' : 'dark';
    late TestEnv env;
    late Project project;
    late ProjectSession session;
    late List<String> clipboard;
    Turn turn = (_, _) => reply('好的。');

    /// [seed]：开会话之前先写进 chat.json 的旧记录。
    Future<void> boot(WidgetTester tester, {List<Map<String, dynamic>>? seed}) async {
      usePhoneViewport(tester);
      turn = (_, _) => reply('好的。');
      clipboard = [];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') clipboard.add('${(call.arguments as Map)['text']}');
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await tester.runAsync(() async {
        env = await TestEnv.create(chatClient: () => RoutingClient((m, t) => turn(m, t), []));
        project = await env.services.projects.create('我的小站', ProjectTemplate.web);
        if (seed != null) {
          Directory('${project.dir}/.lopicode').createSync(recursive: true);
          File('${project.dir}/.lopicode/chat.json').writeAsStringSync(jsonEncode(seed));
        }
        session = ProjectSession(env.services, project);
        session.commandRunnerFactory = RecordingRunner.new;
        await session.loadChat();
      });
      addTearDown(() async {
        session.dispose();
        await env.dispose();
      });
    }

    Future<void> show(WidgetTester tester) async {
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

    /// 一轮带一步读文件（先说一句、再读、再总结），然后一问一答。
    Future<void> twoTurns(WidgetTester tester) async {
      turn = (m, t) => lastUser(m) == '看看首页'
          ? (hasToolResult(m)
                ? reply('首页看完了，结构没问题。')
                : [
                    say('我先读一下。'),
                    ...use('read_file', {'path': 'index.html'}),
                  ])
          : reply('不客气。');
      await tester.runAsync(() async {
        await session.sendToAgent('看看首页');
        await session.sendToAgent('谢谢');
      });
    }

    String idOf(String text) => switch (session.chat.firstWhere((i) => (i is UserItem && i.text == text) || (i is AssistantItem && i.text == text))) {
      UserItem(:final id) => id!,
      AssistantItem(:final id) => id!,
      _ => fail('不是消息'),
    };

    /// 推几帧让面板的进出动画走完（Agent 在跑时有转圈动画，不能等“全部静止”）。
    Future<void> steps(WidgetTester tester) async {
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 150));
      }
    }

    /// 聊天里的一个气泡（对话名、侧边栏里也可能有同样的字，所以只认气泡）。
    Finder bubble(String text) => find.byWidgetPredicate((w) => w is SelectableText && w.data == text);
    Finder bar(String id) => find.byKey(ValueKey('message-actions-$id'));
    Finder icon(String kind, String id) => find.byKey(ValueKey('message-$kind-$id'));

    Future<void> openMore(WidgetTester tester, String id) async {
      await tester.ensureVisible(icon('more', id));
      await tester.pump();
      await tester.tap(icon('more', id));
      await steps(tester);
    }

    testWidgets('操作栏：只在我的消息和 Agent 的正式回复下面；可点区域 44×44；复制拿到原文 ($suffix)', (tester) async {
      await boot(tester);
      await twoTurns(tester);
      await show(tester);
      final mine = idOf('看看首页'), last = idOf('首页看完了，结构没问题。'), thanks = idOf('谢谢'), bye = idOf('不客气。');
      for (final id in [mine, last, thanks, bye]) {
        expect(bar(id), findsOneWidget, reason: id);
        expect(icon('copy', id), findsOneWidget);
        expect(icon('more', id), findsOneWidget);
      }
      // 这一步只登记了四个动作：常驻的只有复制和“更多”，重试 / 编辑 / 分支的位置不显示任何东西
      expect(find.descendant(of: bar(last), matching: find.byType(InkResponse)), findsNWidgets(2));
      expect(find.descendant(of: bar(mine), matching: find.byType(InkResponse)), findsNWidgets(2));
      // 一共 4 条看得见的消息 → 4 排；步骤组下面没有
      expect(find.byType(MessageActionBar), findsNWidgets(4));
      expect(tester.getSize(icon('copy', last)), const Size(44, 44));
      expect(tester.getSize(icon('more', mine)), const Size(44, 44));
      // 我的消息靠右、Agent 的靠左
      expect(tester.getTopRight(bar(mine)).dx, greaterThan(300));
      expect(tester.getTopLeft(bar(last)).dx, lessThan(40));
      await shot(tester, 'ops-01-action-bar-$suffix');

      await tester.tap(icon('copy', last));
      await tester.pump();
      expect(clipboard, ['首页看完了，结构没问题。']);
      expect(find.text('已复制'), findsOneWidget);
      await tester.tap(icon('copy', mine));
      await tester.pump();
      expect(clipboard.last, '看看首页');
      // 长按选字的老行为还在：正文仍然是可选择的文字
      expect(find.widgetWithText(SelectableText, '首页看完了，结构没问题。'), findsOneWidget);
    });

    testWidgets('“更多”面板：一行一个——收藏、分享、删除；收藏后图标变实心并常驻，再点取消 ($suffix)', (tester) async {
      await boot(tester);
      await twoTurns(tester);
      await show(tester);
      final id = idOf('首页看完了，结构没问题。');
      await openMore(tester, id);
      final ys = [
        for (final k in ['favorite', 'share', 'delete']) tester.getTopLeft(find.byKey(ValueKey('more-$k'))).dy,
      ];
      expect(ys, orderedEquals([...ys]..sort()), reason: '从上到下：收藏、分享、删除（删除在最后）');
      expect(ys.toSet(), hasLength(3), reason: '一行一个');
      expect(find.byKey(const ValueKey('more-copy')), findsNothing, reason: '常驻的不在“更多”里重复');
      for (final k in ['retry', 'edit', 'branch']) {
        expect(find.byKey(ValueKey('more-$k')), findsNothing, reason: '$k 还没登记，不放空按钮');
      }
      expect(find.text('收藏'), findsOneWidget);
      expect(find.text('分享'), findsOneWidget);
      expect(find.text('删除'), findsOneWidget);
      expect(find.text('可以只删这一条，也可以删掉这一整轮'), findsOneWidget);
      await shot(tester, 'ops-02-more-sheet-$suffix');

      await tester.tap(find.byKey(const ValueKey('more-favorite')));
      await settle(tester, rounds: 3);
      expect(find.byKey(const ValueKey('more-favorite')), findsNothing, reason: '面板关了');
      expect(find.textContaining('已收藏'), findsOneWidget);
      expect(icon('favorite', id), findsOneWidget, reason: '收藏过的消息多一个实心书签');
      expect(tester.widget<Icon>(find.descendant(of: icon('favorite', id), matching: find.byType(Icon))).icon, Icons.bookmark);
      expect(env.services.container.read(favoritesProvider(session)).items.single.text, '首页看完了，结构没问题。');
      await shot(tester, 'ops-03-favorited-$suffix');

      // “更多”里那一行变成“取消收藏”……但它现在常驻了，所以不在“更多”里
      await openMore(tester, id);
      expect(find.byKey(const ValueKey('more-favorite')), findsNothing);
      await tester.tapAt(const Offset(195, 80));
      await tester.pumpAndSettle();
      await tester.tap(icon('favorite', id));
      await settle(tester, rounds: 3);
      expect(icon('favorite', id), findsNothing);
      expect(env.services.container.read(favoritesProvider(session)).items, isEmpty);
    });

    testWidgets('删除：先确认并说清影响；两种删法；不能单删的那种是灰的并写原因；删完行就没了、盘上也没了 ($suffix)', (tester) async {
      await boot(tester);
      await twoTurns(tester);
      await show(tester);
      // 我的提问：后面跟着回复，不能单删
      await openMore(tester, idOf('看看首页'));
      await tester.tap(find.byKey(const ValueKey('more-delete')));
      await tester.pumpAndSettle();
      expect(find.text('删除消息'), findsOneWidget);
      expect(find.text('只删这条消息'), findsOneWidget);
      expect(find.textContaining('只能整轮删'), findsOneWidget);
      expect(tester.widget<ListTile>(find.byKey(const ValueKey('delete-message'))).enabled, isFalse);
      expect(tester.widget<ListTile>(find.byKey(const ValueKey('delete-turn'))).selected, isTrue, reason: '只剩一种能选时默认选它');
      expect(find.text('你的 1 条消息、Agent 的 2 段话、1 个步骤一起删。'), findsOneWidget);
      expect(find.textContaining('删掉后，Agent 之后也看不到这些内容。'), findsOneWidget);
      expect(find.textContaining('不会撤销它对文件做过的修改'), findsOneWidget);
      await shot(tester, 'ops-04-delete-confirm-$suffix');
      // 取消：什么都没变
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(session.chat.whereType<UserItem>(), hasLength(2));

      // Agent 的一段回复：默认“只删这段回复”
      await openMore(tester, idOf('首页看完了，结构没问题。'));
      await tester.tap(find.byKey(const ValueKey('more-delete')));
      await tester.pumpAndSettle();
      expect(find.text('只删这段回复'), findsOneWidget);
      expect(tester.widget<ListTile>(find.byKey(const ValueKey('delete-message'))).selected, isTrue);
      await tester.tap(find.byKey(const ValueKey('delete-confirm')));
      await settle(tester, rounds: 4);
      expect(bubble('首页看完了，结构没问题。'), findsNothing);
      expect(find.text('已删除'), findsOneWidget);
      expect(bubble('看看首页'), findsOneWidget, reason: '这一轮别的内容留着');

      // 再把这一整轮删掉
      await openMore(tester, idOf('看看首页'));
      await tester.tap(find.byKey(const ValueKey('more-delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('delete-confirm')));
      await settle(tester, rounds: 4);
      expect(bubble('看看首页'), findsNothing);
      expect(find.text('已删除这一轮'), findsOneWidget);
      expect(bubble('谢谢'), findsOneWidget);
      expect(find.byType(MessageActionBar), findsNWidgets(2));
      final disk = jsonDecode(File('${project.dir}/.lopicode/chat.json').readAsStringSync()) as List;
      expect([for (final m in disk) (m as Map)['content']], ['谢谢', '不客气。']);
    });

    testWidgets('分享：选范围；复制为 Markdown、存成文件（告诉路径）；没有“发给别的应用” ($suffix)', (tester) async {
      await boot(tester);
      await twoTurns(tester);
      await show(tester);
      final id = idOf('首页看完了，结构没问题。');
      Future<void> openShare() async {
        await openMore(tester, id);
        await tester.tap(find.byKey(const ValueKey('more-share')));
        await tester.pumpAndSettle();
      }

      await openShare();
      expect(find.text('这一条'), findsOneWidget);
      expect(find.text('这一轮：提问 + 回复'), findsOneWidget);
      expect(find.text('复制为 Markdown'), findsOneWidget);
      expect(find.text('存成文件'), findsOneWidget);
      expect(find.text('发给别的应用'), findsNothing, reason: '跟霜霜说定先不调系统分享面板');
      expect(find.textContaining('会换成 ***'), findsOneWidget);
      await shot(tester, 'ops-05-share-sheet-$suffix');
      await tester.tap(find.byKey(const ValueKey('share-copy')));
      await settle(tester, rounds: 2);
      expect(clipboard.last, contains('首页看完了，结构没问题。'));
      expect(clipboard.last, isNot(contains('## 我')), reason: '这一条：不带提问');
      expect(find.text('已复制为 Markdown'), findsOneWidget);

      await openShare();
      await tester.tap(find.text('这一轮：提问 + 回复'));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('share-copy')));
      await settle(tester, rounds: 2);
      expect(clipboard.last, allOf(contains('看看首页'), contains('我先读一下。'), contains('首页看完了，结构没问题。')));
      expect(clipboard.last, isNot(contains('不客气')));

      await openShare();
      await tester.tap(find.byKey(const ValueKey('share-save')));
      await settle(tester, rounds: 4);
      expect(find.textContaining('已存到工作区：exports/消息-'), findsOneWidget);
      final saved = Directory('${project.dir}/exports').listSync().whereType<File>().single;
      expect(saved.readAsStringSync(), contains('首页看完了，结构没问题。'));
    });

    testWidgets('Agent 正在回复：还在往外冒的那一轮没法删（更多里“删除”是灰的并写原因），复制、收藏照常；停下后恢复 ($suffix)', (tester) async {
      await boot(tester);
      await tester.runAsync(() => session.sendToAgent('第一句'));
      await show(tester);
      final gate = Completer<void>();
      turn = (m, t) async {
        await gate.future;
        return reply('第二句的回复');
      };
      await tester.runAsync(() async => unawaited(session.sendToAgent('第二句')));
      await waitReal(tester, () => session.agentBusy, what: 'Agent 开始跑');
      final id = idOf('好的。');
      await openMore(tester, id);
      expect(tester.widget<ListTile>(find.byKey(const ValueKey('more-delete'))).enabled, isFalse);
      expect(find.text(kDeleteWhileBusy), findsOneWidget);
      expect(tester.widget<ListTile>(find.byKey(const ValueKey('more-favorite'))).enabled, isTrue);
      expect(tester.widget<ListTile>(find.byKey(const ValueKey('more-share'))).enabled, isTrue);
      await shot(tester, 'ops-06-busy-more-$suffix');
      // 灰掉的那行点了没反应
      await tester.tap(find.byKey(const ValueKey('more-delete')), warnIfMissed: false);
      await steps(tester);
      expect(find.text('删除消息'), findsNothing);
      await tester.tapAt(const Offset(195, 80));
      await steps(tester);
      await tester.tap(icon('copy', id));
      await tester.pump();
      expect(clipboard.last, '好的。');

      gate.complete();
      await waitReal(tester, () => !session.agentBusy, what: '这一轮结束');
      await openMore(tester, id);
      expect(tester.widget<ListTile>(find.byKey(const ValueKey('more-delete'))).enabled, isTrue);
    });

    testWidgets('行级：还在往外冒的回复没有操作栏；没有 id 的没有；整轮级别的动作只在这一轮最后一段回复下面；没有聊天页环境（子代理对话页）不显示 ($suffix)', (tester) async {
      await boot(tester);
      Future<void> noop(BuildContext context, MessageTarget t) async {}
      final actions = [
        ...kMessageActions,
        MessageAction(slot: MessageActionSlot.retry, label: (_) => '重试', icon: (_) => Icons.refresh, appliesTo: (t) => !t.mine, pinned: (_) => true, turnLevel: true, run: noop),
        MessageAction(slot: MessageActionSlot.edit, label: (_) => '编辑', icon: (_) => Icons.edit_outlined, appliesTo: (t) => t.mine, pinned: (_) => true, run: noop),
        MessageAction(slot: MessageActionSlot.branch, label: (_) => '分支', icon: (_) => Icons.call_split, hint: (_) => '从这里另开一段对话', run: noop),
      ];
      const items = <ChatItem>[
        UserItem('帮我改首页', id: 'u1'),
        AssistantItem('我先看看。', id: 'a1'),
        ToolItem('c1', 'read_file', '{"path":"index.html"}', result: '<html>'),
        AssistantItem('改好了。', id: 'a2'),
        UserItem('再改一下标题', id: 'u2'),
        AssistantItem('正在改', streaming: true, id: 'a3'),
        AssistantItem('还没存进记录的', id: null),
      ];
      Widget rows({required bool scoped}) {
        final list = ListView(
          padding: const EdgeInsets.all(Space.x4),
          children: [for (final row in deriveChatRows(items, busy: true)) ChatRowView(row: row)],
        );
        return appFor(
          env,
          Scaffold(
            body: SafeArea(
              child: scoped ? MessageOpsScope(session: session, busy: true, lastReplyIds: const {'a2'}, favoriteIds: const {'u1'}, actions: actions, child: list) : list,
            ),
          ),
          mode: mode,
          font: kTestFont,
        );
      }

      await tester.pumpWidget(rows(scoped: true));
      await tester.pump(const Duration(milliseconds: 300));
      // “我先看看。”是步骤中间的话，收在步骤组里，不是正式回复，所以没有操作栏
      expect(find.byType(MessageActionBar), findsNWidgets(3), reason: 'u1、a2、u2 各一排；往外冒的、没 id 的、步骤组都没有');
      expect(bar('a1'), findsNothing);
      expect(bar('a3'), findsNothing);
      // 登记了以后：重试只在这一轮最后一段回复下面；编辑只在我的消息下面
      expect(icon('retry', 'a2'), findsOneWidget);
      expect(icon('retry', 'u1'), findsNothing);
      expect(icon('edit', 'u1'), findsOneWidget);
      expect(icon('edit', 'u2'), findsOneWidget);
      expect(icon('edit', 'a2'), findsNothing);
      // 从左到右按登记的位置排：复制、重试、更多
      final xs = [
        for (final k in ['copy', 'retry', 'more']) tester.getTopLeft(icon(k, 'a2')).dx,
      ];
      expect(xs, orderedEquals([...xs]..sort()));
      expect(icon('favorite', 'u1'), findsOneWidget);
      await shot(tester, 'ops-07-registered-actions-$suffix');
      await tester.tap(icon('more', 'a2'));
      await tester.pumpAndSettle();
      expect(find.text('分支'), findsOneWidget);
      expect(find.text('从这里另开一段对话'), findsOneWidget);
      await tester.tapAt(const Offset(195, 80));
      await tester.pumpAndSettle();

      await tester.pumpWidget(rows(scoped: false));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(MessageActionBar), findsNothing);
      expect(find.text('改好了。'), findsOneWidget);
    });

    testWidgets('收藏页：空状态；按时间倒序列出对话名、开头几行、时间；点一条跳回原消息；列表里取消收藏；原消息删了标出来 ($suffix)', (tester) async {
      // 一段很长的旧对话（没有 _id）：40 轮，每轮回复都有好几行
      final seed = [
        for (var i = 1; i <= 40; i++) ...[
          {'role': 'user', 'content': '第 $i 个问题'},
          {'role': 'assistant', 'content': '第 $i 个回答。\n${'这是一段比较长的说明文字，用来把列表撑高。' * 4}'},
        ],
      ];
      await boot(tester, seed: seed);
      await show(tester);
      // 翻到最下面（离要跳回去的那条很远）
      final position = tester.state<ScrollableState>(find.byType(Scrollable).first).position;
      for (var i = 0; i < 80 && position.pixels < position.maxScrollExtent; i++) {
        position.jumpTo(position.maxScrollExtent);
        await tester.pump();
      }
      expect(bubble('第 40 个问题'), findsOneWidget);
      expect(bubble('第 2 个问题'), findsNothing);

      Future<void> openPage() async {
        await tester.tap(find.byTooltip('打开侧边栏').hitTestable());
        await tester.pumpAndSettle();
        await tester.tap(find.text('收藏的消息'));
        await settle(tester, rounds: 4);
      }

      await openPage();
      expect(find.text('还没有收藏'), findsOneWidget);
      await shot(tester, 'ops-08-favorites-empty-$suffix');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      // 收藏三条：很靠前的一条提问、最后一条回答、另一段对话里的一条
      final early = session.chat.whereType<UserItem>().firstWhere((i) => i.text == '第 2 个问题');
      final late = session.chat.whereType<AssistantItem>().last;
      await tester.runAsync(() async {
        await session.messageOps.toggleFavorite(early);
        await Future<void>.delayed(const Duration(milliseconds: 5));
        await session.messageOps.toggleFavorite(late);
        await session.newConversation();
        await session.sendToAgent('另一段对话里的话');
        await session.messageOps.toggleFavorite(session.chat.whereType<AssistantItem>().last);
      });
      await settle(tester, rounds: 3);
      final other = session.activeConversationId;

      await openPage();
      expect(find.byKey(const ValueKey('favorite-remove')), findsNWidgets(3));
      final tops = [
        for (final t in ['好的。', '第 40 个回答。', '第 2 个问题']) tester.getTopLeft(find.textContaining(t).first).dy,
      ];
      expect(tops, orderedEquals([...tops]..sort()), reason: '新收藏的在上面');
      expect(find.textContaining('我 · 第 1 个问题'), findsOneWidget, reason: '出处：谁说的 · 对话名');
      expect(find.textContaining('Agent · 另一段对话里的话'), findsOneWidget);
      expect(find.textContaining(RegExp(r'\d+月\d+日 \d\d:\d\d')), findsNWidgets(3));
      expect(find.byKey(const ValueKey('favorite-gone')), findsNothing);
      await shot(tester, 'ops-09-favorites-$suffix');

      // 点很靠前的那条：切回那段对话，滚到它
      await tester.tap(find.text('第 2 个问题'));
      await settle(tester, rounds: 8);
      expect(session.activeConversationId, 'main');
      expect(bubble('第 2 个问题').hitTestable(), findsOneWidget, reason: '滚到了原消息');
      expect(bubble('第 40 个问题'), findsNothing);
      await shot(tester, 'ops-10-jumped-back-$suffix');
      expect(env.services.container.read(chatJumpProvider(session)), isNull, reason: '跳完就清掉');
      await tester.pump(const Duration(seconds: 2)); // 高亮自己消掉

      // 在列表里取消收藏
      await openPage();
      await tester.tap(find.descendant(of: find.byKey(ValueKey('favorite-main/${early.id}')), matching: find.byKey(const ValueKey('favorite-remove'))));
      await settle(tester, rounds: 3);
      expect(find.byKey(const ValueKey('favorite-remove')), findsNWidgets(2));
      expect(find.text('第 2 个问题'), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      // 原消息删掉：收藏还在，标“原消息已删除”，点开看到留下的文字，可以复制
      await tester.runAsync(() => session.messageOps.delete(late.id!, DeleteScope.turn));
      await settle(tester, rounds: 3);
      await openPage();
      expect(find.byKey(const ValueKey('favorite-gone')), findsOneWidget);
      expect(find.text('原消息已删除'), findsOneWidget);
      await shot(tester, 'ops-11-favorites-gone-$suffix');
      await tester.tap(find.textContaining('第 40 个回答。'));
      await tester.pumpAndSettle();
      expect(find.text('原消息已删除，这是收藏时留下的文字'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('favorite-copy')));
      await tester.pumpAndSettle();
      expect(clipboard.last, startsWith('第 40 个回答。'));

      // 另一段对话里那条：点了切过去
      await tester.tap(find.textContaining('好的。').first);
      await settle(tester, rounds: 6);
      expect(session.activeConversationId, other);
      expect(bubble('另一段对话里的话'), findsOneWidget);
    });

    testWidgets('对话页右上角菜单里也能进“收藏的消息” ($suffix)', (tester) async {
      await boot(tester);
      await show(tester);
      await tester.tap(find.byTooltip('更多').hitTestable());
      await tester.pumpAndSettle();
      await tester.tap(find.text('收藏的消息').last);
      await settle(tester, rounds: 4);
      expect(find.text('还没有收藏'), findsOneWidget);
    });
  }
}
