// 重试 / 编辑 / 分支的界面（390×844，浅 / 深）：操作栏一排几个、重试确认面板、“正在编辑”条与取消恢复草稿、
// 改了再发、分支后的侧边栏标签与“回到原对话”、这条消息上分出去的对话、Agent 正在回复时变灰并写原因、子代理对话页没有。
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/stores.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/session/message_branches.dart';
import 'package:lopicode/ui/chat_panels.dart';
import 'package:lopicode/ui/keyboard_tap_dismiss.dart';
import 'package:lopicode/ui/message_action_bar.dart';
import 'package:lopicode/ui/message_text.dart';
import 'package:lopicode/ui/project_shell.dart';
import 'package:material_ui/material_ui.dart';

import 'agent_test.dart' show RecordingRunner;
import 'agent_ui_test.dart' show waitReal;
import 'screens_test.dart' show fontsLoaded, shot;
import 'session_system_test.dart' show RoutingClient, Turn, firstUser, hasToolResult, lastUser, reply, use;
import 'support/harness.dart';

/// 1×1 的 PNG。
const kTinyPng = <int>[
  137,
  80,
  78,
  71,
  13,
  10,
  26,
  10,
  0,
  0,
  0,
  13,
  73,
  72,
  68,
  82,
  0,
  0,
  0,
  1,
  0,
  0,
  0,
  1,
  8,
  6,
  0,
  0,
  0,
  31,
  21,
  196,
  137,
  0,
  0,
  0,
  13,
  73,
  68,
  65,
  84,
  120,
  218,
  99,
  100,
  96,
  248,
  95,
  15,
  0,
  2,
  135,
  1,
  128,
  235,
  71,
  186,
  146,
  0,
  0,
  0,
  0,
  73,
  69,
  78,
  68,
  174,
  66,
  96,
  130,
];

void main() {
  setUpAll(() async => fontsLoaded = await loadRealFonts());

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    final suffix = mode == ThemeMode.light ? 'light' : 'dark';
    late TestEnv env;
    late Project project;
    late ProjectSession session;
    late List<List<Map<String, dynamic>>> sent;
    Turn turn = (_, _) => reply('好的。');

    Future<void> boot(WidgetTester tester) async {
      usePhoneViewport(tester);
      sent = [];
      turn = (_, _) => reply('好的。');
      await tester.runAsync(() async {
        env = await TestEnv.create(
          chatClient: () => RoutingClient((m, t) {
            sent.add(m);
            return turn(m, t);
          }, []),
        );
        project = await env.services.projects.create('我的小站', ProjectTemplate.web);
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

    /// 一轮带一步读文件，然后一问一答。回复带序号，看得出是不是重新回答的。
    Future<void> twoTurns(WidgetTester tester) async {
      var n = 0;
      turn = (m, t) => switch (lastUser(m)) {
        '看看首页' => hasToolResult(m) && m.last['role'] == 'tool' ? reply('首页看完了，结构没问题。') : use('read_file', {'path': 'index.html'}),
        '谢谢' => reply('不客气 ${++n}。'),
        _ => reply('收到：${lastUser(m)}'),
      };
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
    Future<void> steps(WidgetTester tester) async {
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 150));
      }
    }

    Finder bubble(String text) => find.byWidgetPredicate((w) => w is MessageText && w.text == text);
    Finder bar(String id) => find.byKey(ValueKey('message-actions-$id'));
    Finder icon(String kind, String id) => find.byKey(ValueKey('message-$kind-$id'));
    Finder more(String kind) => find.byKey(ValueKey('more-$kind'));
    final input = find.byType(TextField);
    String typed(WidgetTester tester) => tester.widget<TextField>(input).controller!.text;

    Future<void> tapIcon(WidgetTester tester, String kind, String id) async {
      await tester.ensureVisible(icon(kind, id));
      await tester.pump();
      await tester.tap(icon(kind, id));
      await steps(tester);
    }

    Future<void> openDrawer(WidgetTester tester) async {
      await tester.tap(find.byTooltip('打开侧边栏').hitTestable().first);
      await settle(tester, rounds: 4);
    }

    testWidgets('操作栏：常驻四个——我的消息是复制、编辑、重新发送、更多；Agent 回复是复制、编辑、重试、更多；都够 44×44；分支在“更多”里 ($suffix)', (tester) async {
      await boot(tester);
      await twoTurns(tester);
      await show(tester);
      final mine = idOf('看看首页'), last = idOf('首页看完了，结构没问题。'), bye = idOf('不客气 1。');
      for (final (id, kinds) in [
        (mine, ['copy', 'edit', 'retry', 'more']),
        (last, ['copy', 'edit', 'retry', 'more']),
        (bye, ['copy', 'edit', 'retry', 'more']),
      ]) {
        final xs = [for (final k in kinds) tester.getTopLeft(icon(k, id)).dx];
        expect(xs, orderedEquals([...xs]..sort()), reason: '$kinds 从左到右');
        expect(find.descendant(of: bar(id), matching: find.byType(InkResponse)), findsNWidgets(4));
        for (final k in kinds) {
          expect(tester.getSize(icon(k, id)), const Size(44, 44));
        }
      }
      expect(find.byTooltip('重新发送'), findsNWidgets(2), reason: '我的两条消息上第三个按钮叫“重新发送”');
      expect(find.byTooltip('重试'), findsNWidgets(2));
      await shot(tester, 'ops2-01-action-bar-$suffix');

      // Agent 回复的“更多”：从这里分支排第一
      await tapIcon(tester, 'more', last);
      expect(find.text('从这里分支'), findsOneWidget);
      expect(find.text('另开一段对话：到这段回复为止。原对话不动'), findsOneWidget);
      expect(more('retry'), findsNothing, reason: '常驻的不重复');
      expect(more('edit'), findsNothing, reason: '常驻的不重复');
      await shot(tester, 'ops2-02-more-reply-$suffix');
      await tester.tapAt(const Offset(195, 80));
      await steps(tester);
      // 我的消息的“更多”：从这里分支在；重新发送已经常驻，不在这里重复
      await tapIcon(tester, 'more', mine);
      expect(more('retry'), findsNothing, reason: '常驻的不重复');
      expect(find.text('从这里分支'), findsOneWidget);
      expect(more('edit'), findsNothing);
      await shot(tester, 'ops2-03-more-mine-$suffix');
    });

    testWidgets('重试最后一轮：先确认（说清移走什么、存到哪、文件不撤销、用量照算）；取消什么都不动；确认后重新回答，旧回复进“旧版本” ($suffix)', (tester) async {
      await boot(tester);
      await twoTurns(tester);
      await show(tester);
      final bye = idOf('不客气 1。');
      await tapIcon(tester, 'retry', bye);
      expect(find.text('重试这一轮？'), findsOneWidget);
      expect(find.textContaining('用同一条消息重新问一遍'), findsOneWidget);
      expect(find.textContaining('Agent 的 1 段话'), findsOneWidget);
      expect(find.textContaining('另存成“看看首页 · 旧版本”'), findsOneWidget);
      expect(find.textContaining('已经花掉的用量不变'), findsOneWidget);
      expect(find.textContaining('不会撤销'), findsNothing, reason: '这一轮没有步骤：不提文件');
      await shot(tester, 'ops2-04-retry-confirm-$suffix');
      final before = sent.length;
      await tester.tap(find.text('取消'));
      await steps(tester);
      expect(sent.length, before);
      expect(bubble('不客气 1。'), findsOneWidget);
      expect(session.conversations, hasLength(1));

      await tapIcon(tester, 'retry', bye);
      await tester.tap(find.byKey(const ValueKey('retry-confirm')));
      await waitReal(tester, () => sent.length == before + 1 && !session.agentBusy, what: '重试跑完');
      await settle(tester, rounds: 4);
      expect(bubble('不客气 2。'), findsOneWidget);
      expect(bubble('不客气 1。'), findsNothing);
      expect(bubble('谢谢'), findsOneWidget, reason: '我的那条消息还是同一条');
      expect(
        [
          for (final m in sent.last)
            if (m['role'] == 'user') m['content'],
        ],
        ['看看首页', '谢谢'],
      );
      expect(find.textContaining('旧版本'), findsWidgets, reason: '提示里说了旧内容在哪');
      await shot(tester, 'ops2-05-retry-done-$suffix');

      // 侧边栏：原对话下面多一条带“旧版本”标签的；点进去看得到旧回复，菜单里能回到原对话
      await tester.pump(const Duration(seconds: 5)); // 提示条自己收掉
      await openDrawer(tester);
      expect(find.text('旧版本'), findsOneWidget);
      await shot(tester, 'ops2-06-drawer-old-version-$suffix');
      await tester.tap(find.text('旧版本'));
      await waitReal(tester, () => session.activeConversation.origin != null, what: '切到旧版本');
      expect(bubble('不客气 1。'), findsOneWidget);
    });

    testWidgets('重试更早的一轮：确认面板写明连同后面几轮一起移走、文件修改不撤销 ($suffix)', (tester) async {
      await boot(tester);
      await twoTurns(tester);
      await show(tester);
      await tapIcon(tester, 'retry', idOf('首页看完了，结构没问题。'));
      expect(find.text('从这一轮重新来？'), findsOneWidget);
      expect(find.textContaining('连同后面的 1 轮对话'), findsOneWidget);
      expect(find.textContaining('1 个步骤'), findsOneWidget);
      expect(find.text('Agent 已经对文件做过的修改不会撤销。'), findsOneWidget);
      // 面板不超出屏幕、按钮够大
      final confirm = find.byKey(const ValueKey('retry-confirm'));
      expect(tester.getBottomLeft(confirm).dy, lessThanOrEqualTo(844));
      expect(tester.getSize(confirm).height, greaterThanOrEqualTo(44));
      await shot(tester, 'ops2-07-retry-earlier-confirm-$suffix');
      await tester.tap(confirm);
      await waitReal(tester, () => !session.agentBusy && session.conversations.length == 2, what: '重试跑完');
      expect(bubble('谢谢'), findsNothing, reason: '后面的轮移走了');
      expect(bubble('看看首页'), findsOneWidget);
    });

    testWidgets('编辑：消息放回输入框，上方出现“正在编辑”条（在键盘线以下）；取消恢复原来打了一半的草稿 ($suffix)', (tester) async {
      await boot(tester);
      await twoTurns(tester);
      await show(tester);
      await tester.enterText(input, '打了一半的草稿');
      await tester.pump();
      await tapIcon(tester, 'edit', idOf('谢谢'));
      expect(typed(tester), '谢谢');
      final chip = find.byKey(const ValueKey('edit-chip'));
      expect(chip, findsOneWidget);
      expect(find.textContaining('正在编辑之前的消息。发送后从这条重新来'), findsOneWidget);
      expect(find.textContaining('它后面的内容另存为旧版本'), findsOneWidget);
      // 在 KeyboardDock 线以下、输入框以上
      final dock = tester.getTopLeft(find.byType(KeyboardDock)).dy;
      expect(tester.getTopLeft(chip).dy, greaterThanOrEqualTo(dock));
      expect(tester.getBottomLeft(chip).dy, lessThanOrEqualTo(tester.getTopLeft(input).dy));
      expect(tester.getSize(find.descendant(of: chip, matching: find.text('取消'))).height, greaterThan(0));
      await shot(tester, 'ops2-08-editing-$suffix');

      // 换一条编辑：收着的仍是最开始那份草稿
      await tapIcon(tester, 'edit', idOf('看看首页'));
      expect(typed(tester), '看看首页');
      expect(find.textContaining('这一轮和后面 1 轮另存为旧版本'), findsOneWidget);
      await tester.tap(find.descendant(of: chip, matching: find.text('取消')));
      await steps(tester);
      expect(chip, findsNothing);
      expect(typed(tester), '打了一半的草稿');
      expect(session.conversations, hasLength(1), reason: '取消：什么都没动');
      expect(bubble('不客气 1。'), findsOneWidget);
    });

    testWidgets('编辑带图片的消息：图片回到附件条；取消后原来的附件和草稿都回来 ($suffix)', (tester) async {
      await boot(tester);
      late Map<String, dynamic> image;
      await tester.runAsync(() async {
        image = await session.saveAttachment(kTinyPng, 'a.png');
        await session.sendToAgent('看这张图', images: [image]);
      });
      await show(tester);
      expect(find.descendant(of: find.byType(AttachmentStrip), matching: find.byType(ImageThumb)), findsNothing);
      await tapIcon(tester, 'edit', idOf('看这张图'));
      expect(typed(tester), '看这张图');
      expect(find.descendant(of: find.byType(AttachmentStrip), matching: find.byType(ImageThumb)), findsOneWidget);
      await shot(tester, 'ops2-09-editing-image-$suffix');
      await tester.tap(find.descendant(of: find.byKey(const ValueKey('edit-chip')), matching: find.text('取消')));
      await steps(tester);
      expect(typed(tester), '');
      expect(find.descendant(of: find.byType(AttachmentStrip), matching: find.byType(ImageThumb)), findsNothing);
    });

    testWidgets('编辑后发送：发的是新文字，从这条消息重新来；旧的进“旧版本”；编辑条收掉 ($suffix)', (tester) async {
      await boot(tester);
      await twoTurns(tester);
      await show(tester);
      await tapIcon(tester, 'edit', idOf('看看首页'));
      await tester.enterText(input, '看看关于页');
      await tester.pump();
      final before = sent.length;
      await tester.tap(find.byKey(const ValueKey('send-button')));
      await waitReal(tester, () => sent.length > before && !session.agentBusy, what: '改了再发跑完');
      await settle(tester, rounds: 4);
      expect(
        [
          for (final m in sent.last)
            if (m['role'] == 'user') m['content'],
        ],
        ['看看关于页'],
      );
      expect(bubble('看看关于页'), findsOneWidget);
      expect(bubble('收到：看看关于页'), findsOneWidget);
      expect(bubble('看看首页'), findsNothing);
      expect(bubble('谢谢'), findsNothing);
      expect(find.byKey(const ValueKey('edit-chip')), findsNothing);
      expect(typed(tester), '');
      expect(find.textContaining('旧版本'), findsWidgets);
      final old = session.conversations.singleWhere((c) => c.origin?.old ?? false);
      expect(old.title, '看看首页');
      await shot(tester, 'ops2-10-edit-sent-$suffix');
    });

    testWidgets('分支：另开一段并切过去；侧边栏带“分支”标签；菜单“回到原对话”跳回那条消息；原消息上看得到分出去的对话 ($suffix)', (tester) async {
      await boot(tester);
      await twoTurns(tester);
      await show(tester);
      final at = idOf('首页看完了，结构没问题。');
      await tapIcon(tester, 'more', at);
      await tester.tap(more('branch'));
      await waitReal(tester, () => session.activeConversationId != 'main', what: '切到分支');
      await settle(tester, rounds: 4);
      expect(find.textContaining('已另开分支'), findsOneWidget);
      expect(bubble('首页看完了，结构没问题。'), findsOneWidget);
      expect(bubble('谢谢'), findsNothing, reason: '分支只到那段回复为止');
      await shot(tester, 'ops2-11-branch-opened-$suffix');
      await tester.pump(const Duration(seconds: 5));

      await openDrawer(tester);
      expect(find.text('分支'), findsOneWidget);
      await shot(tester, 'ops2-12-drawer-branch-$suffix');
      await tester.tapAt(const Offset(380, 400)); // 点右边露出来的主界面：收起侧边栏
      await settle(tester, rounds: 4);

      // 右上角菜单：回到原对话
      await tester.tap(find.byTooltip('更多').hitTestable());
      await tester.pumpAndSettle();
      expect(find.text('回到原对话：看看首页'), findsOneWidget);
      await shot(tester, 'ops2-13-menu-origin-$suffix');
      await tester.tap(find.text('回到原对话：看看首页'));
      await waitReal(tester, () => session.activeConversationId == 'main', what: '回到原对话');
      await settle(tester, rounds: 6);
      expect(bubble('谢谢'), findsOneWidget);
      // 原消息上多了一个“分出去的对话”记号：排在四个按钮的外侧（Agent 的回复在右边），四个按钮不动
      await tester.ensureVisible(bar(at));
      await tester.pump();
      expect(icon('branches', at), findsOneWidget);
      expect(find.descendant(of: bar(at), matching: find.byType(InkResponse)), findsNWidgets(5));
      expect(tester.getTopLeft(icon('branches', at)).dx, greaterThan(tester.getTopLeft(icon('more', at)).dx));
      await shot(tester, 'ops2-14-origin-branches-icon-$suffix');
      await tapIcon(tester, 'branches', at);
      expect(find.text('这里分出去的对话'), findsOneWidget);
      final branchId = session.conversations.singleWhere((c) => c.origin != null).id;
      expect(find.byKey(ValueKey('branch-$branchId')), findsOneWidget);
      await shot(tester, 'ops2-15-branch-list-$suffix');
      await tester.tap(find.byKey(ValueKey('branch-$branchId')));
      await waitReal(tester, () => session.activeConversationId == branchId, what: '从列表切到分支');
    });

    testWidgets('从我的消息分支：这条消息放进新分支的输入框；已收藏 + 有分支时两个记号都在四个按钮外侧、一排放得下 ($suffix)', (tester) async {
      await boot(tester);
      await twoTurns(tester);
      await show(tester);
      final at = idOf('谢谢');
      await tapIcon(tester, 'more', at);
      await tester.tap(more('branch'));
      await waitReal(tester, () => session.activeConversationId != 'main', what: '切到分支');
      await settle(tester, rounds: 4);
      expect(typed(tester), '谢谢');
      expect(bubble('谢谢'), findsNothing);
      expect(find.textContaining('这条消息放进了输入框'), findsOneWidget);
      expect(find.byKey(const ValueKey('edit-chip')), findsNothing, reason: '这是新分支的草稿，不是“正在编辑”');

      await tester.runAsync(() async {
        await session.selectConversation('main');
        await session.messageOps.toggleFavorite(session.chat.whereType<UserItem>().last);
      });
      await settle(tester, rounds: 6);
      await tester.ensureVisible(bar(at));
      await tester.pump();
      // 四个按钮 + 收藏、分支两个记号；记号在我的消息上排在左边，一排没有超出屏幕
      expect(find.descendant(of: bar(at), matching: find.byType(InkResponse)), findsNWidgets(6));
      expect(icon('favorite', at), findsOneWidget);
      expect(icon('branches', at), findsOneWidget);
      for (final k in ['favorite', 'branches']) {
        expect(tester.getTopLeft(icon(k, at)).dx, lessThan(tester.getTopLeft(icon('copy', at)).dx), reason: k);
      }
      expect(tester.getTopLeft(bar(at)).dx, greaterThanOrEqualTo(0));
      expect(tester.getTopRight(bar(at)).dx, lessThanOrEqualTo(390));
      expect(tester.takeException(), isNull);
      // 两个记号都常驻了，“更多”里不重复
      await tapIcon(tester, 'more', at);
      expect(find.textContaining('这里分出去的对话（1）'), findsNothing);
      await shot(tester, 'ops2-16-favorite-and-branches-$suffix');
    });

    testWidgets('Agent 正在回复：重试、编辑是灰的，点了说原因；分支在跑完的轮上可用、在正在跑的轮上是灰的 ($suffix)', (tester) async {
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
      final first = idOf('第一句'), ok = idOf('好的。'), second = idOf('第二句');
      await shot(tester, 'ops2-17-busy-bar-$suffix');
      await tapIcon(tester, 'retry', ok);
      expect(find.text(kRewindWhileBusy), findsOneWidget);
      expect(find.text('重试这一轮？'), findsNothing);
      await tapIcon(tester, 'edit', first);
      expect(find.byKey(const ValueKey('edit-chip')), findsNothing);
      expect(session.conversations, hasLength(1));
      // 正在跑的这一轮里我的那条：重新发送（现在常驻）也是灰的，点了说原因
      await tester.pump(const Duration(seconds: 5));
      await tapIcon(tester, 'retry', second);
      expect(find.text(kRewindWhileBusy), findsOneWidget);

      await tapIcon(tester, 'more', second);
      expect(tester.widget<ListTile>(more('branch')).enabled, isFalse);
      expect(find.text(kBranchRunningTurn), findsOneWidget);
      expect(more('retry'), findsNothing, reason: '重新发送常驻了，不在“更多”里');
      await shot(tester, 'ops2-18-busy-more-$suffix');
      await tester.tapAt(const Offset(195, 80));
      await steps(tester);

      await tapIcon(tester, 'more', ok);
      expect(tester.widget<ListTile>(more('branch')).enabled, isTrue);
      await tester.tap(more('branch'));
      await waitReal(tester, () => session.conversations.length == 2, what: '分支建好');
      expect(session.activeConversationId, 'main', reason: '忙的时候只建、不切过去');
      expect(find.textContaining('Agent 停下后，在侧边栏的对话列表里打开它'), findsOneWidget);
      gate.complete();
      await waitReal(tester, () => !session.agentBusy, what: '这一轮结束');
      expect(bubble('第二句的回复'), findsOneWidget);
    });

    testWidgets('子代理对话页（只读）：没有操作栏，也就没有重试 / 编辑 / 分支 ($suffix)', (tester) async {
      await boot(tester);
      await tester.runAsync(() async {
        await env.services.settings.set(SettingKeys.subagentEnabled, true);
        await env.services.settings.set(SettingKeys.subagentMaxDepth, 1);
        turn = (m, t) {
          if (firstUser(m).contains('写首页')) return reply('首页写好了');
          return m.last['role'] == 'tool' ? reply('都做完了') : use('spawn_agent', {'name': '前端', 'task': '写首页 home.html'});
        };
        await session.sendToAgent('帮我做个站');
      });
      final kid = session.subAgents.single;
      await tester.pumpWidget(
        appFor(
          env,
          SubConversationScreen(session: session, conversationId: kid.id),
          mode: mode,
          font: kTestFont,
        ),
      );
      await settle(tester, rounds: 6);
      expect(find.textContaining('首页写好了'), findsWidgets);
      expect(find.byType(MessageActionBar), findsNothing);
      expect(find.byTooltip('重试'), findsNothing);
      expect(find.byTooltip('编辑'), findsNothing);
    });
  }
}
