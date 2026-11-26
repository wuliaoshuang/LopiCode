// 消息下面常驻四个按钮（复制、编辑、重试 / 重新发送、更多）和“编辑 Agent 的回复”的界面（390×844，浅 / 深）：
// 各类消息有没有操作栏（旧存档、压缩过的、带步骤的、出错留下半截的、被停下的、一轮里好几段的）、
// 编辑页（保存 / 取消 / 空内容 / 恢复原文 / 键盘弹起不遮挡 / 很长的回复）、“已编辑”记号、Agent 正在回复时变灰并说原因。
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/agent/chat_client.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/session/message_actions.dart';
import 'package:lopicode/session/message_ops.dart' show DeleteScope;
import 'package:lopicode/session/reply_edit.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/chat_steps.dart';
import 'package:lopicode/ui/message_action_bar.dart';
import 'package:lopicode/ui/message_reply_editor.dart';
import 'package:lopicode/ui/project_shell.dart';
import 'package:material_ui/material_ui.dart';

import 'agent_test.dart' show RecordingRunner;
import 'agent_ui_test.dart' show waitReal;
import 'screens_test.dart' show fontsLoaded, shot;
import 'session_system_test.dart' show Turn, hasToolResult, lastUser, reply, use;
import 'support/harness.dart';

/// 说到一半就断：先吐 [partial]，再抛接口错误。
class _Broken implements Exception {
  const _Broken(this.partial);
  final String partial;
}

class _Client implements ChatClient {
  _Client(this.turn);
  final Turn Function() turn;

  @override
  Stream<ChatDelta> streamChat({required List<Map<String, dynamic>> messages, List<Map<String, dynamic>> tools = const []}) async* {
    final snapshot = [for (final m in messages) Map<String, dynamic>.from(m)];
    try {
      for (final d in await turn()(snapshot, const [])) {
        yield d;
      }
    } on _Broken catch (e) {
      yield say(e.partial);
      throw ChatApiException('接口报错了（测试）');
    }
  }
}

void main() {
  setUpAll(() async => fontsLoaded = await loadRealFonts());

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    final suffix = mode == ThemeMode.light ? 'light' : 'dark';
    late TestEnv env;
    late Project project;
    late ProjectSession session;
    Turn turn = (_, _) => reply('好的。');

    Future<void> boot(WidgetTester tester, {List<Map<String, dynamic>>? seed}) async {
      usePhoneViewport(tester);
      turn = (_, _) => reply('好的。');
      await tester.runAsync(() async {
        env = await TestEnv.create(chatClient: () => _Client(() => turn));
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

    String idOf(String text) => switch (session.chat.firstWhere((i) => (i is UserItem && i.text == text) || (i is AssistantItem && i.text == text))) {
      UserItem(:final id) => id!,
      AssistantItem(:final id) => id!,
      _ => fail('不是消息'),
    };
    List<Map<String, dynamic>> onDisk() => [for (final m in jsonDecode(File('${project.dir}/.lopicode/chat.json').readAsStringSync()) as List) (m as Map).cast<String, dynamic>()];

    Future<void> steps(WidgetTester tester) async {
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 150));
      }
    }

    Finder bar(String id) => find.byKey(ValueKey('message-actions-$id'));
    Finder icon(String kind, String id) => find.byKey(ValueKey('message-$kind-$id'));
    final field = find.byKey(const ValueKey('reply-edit-input'));
    final save = find.byKey(const ValueKey('reply-edit-save'));
    final note = find.byKey(const ValueKey('reply-edit-note'));
    String noteText(WidgetTester tester) => tester.widget<Text>(note).data!;
    bool canSave(WidgetTester tester) => tester.widget<FilledButton>(save).onPressed != null;

    Future<void> tapIcon(WidgetTester tester, String kind, String id) async {
      await tester.ensureVisible(icon(kind, id));
      await tester.pump();
      await tester.tap(icon(kind, id));
      await steps(tester);
    }

    /// 我的每条消息、Agent 每一轮最后一段正文下面都是四个按钮，从左到右：复制、编辑、重试、更多；都够 44×44。
    void expectFour(WidgetTester tester, String id, {required String why}) {
      expect(bar(id), findsOneWidget, reason: '$why：应该有操作栏');
      final xs = <double>[];
      for (final k in ['copy', 'edit', 'retry', 'more']) {
        expect(icon(k, id), findsOneWidget, reason: '$why：缺“$k”');
        expect(tester.getSize(icon(k, id)), const Size(44, 44), reason: '$why：$k 的可点区域');
        xs.add(tester.getTopLeft(icon(k, id)).dx);
      }
      expect(xs, orderedEquals([...xs]..sort()), reason: '$why：复制、编辑、重试、更多 从左到右');
      expect(xs[1] - xs[0], 44, reason: '$why：编辑紧跟在复制后面');
    }

    testWidgets('各类消息逐类排查：没有 id 的旧存档、压缩归档的、带步骤的、一轮里好几段的——我的每条消息、Agent 每一轮的末尾都是四个按钮；一轮有几段正文时先选改哪一段 ($suffix)', (tester) async {
      // 旧存档：全都没有 _id。前两轮已经被压缩归档；第三轮带一步工具；第四轮中间夹着一条应用通知，所以有两段正式回复。
      final seed = <Map<String, dynamic>>[
        {'role': 'user', 'content': '很早的问题', '_archived': true},
        {'role': 'assistant', 'content': '很早的回答', '_archived': true},
        {'role': 'user', 'content': '摘要：之前聊过首页', '_compact': true},
        {'role': 'assistant', 'content': '好的，我已经了解之前的进展，可以接着做。', '_compactAck': true},
        {'role': 'user', 'content': '看看首页'},
        {
          'role': 'assistant',
          'content': '我先读一下。',
          'tool_calls': [
            {
              'id': 'c1',
              'type': 'function',
              'function': {'name': 'read_file', 'arguments': '{"path":"index.html"}'},
            },
          ],
        },
        {'role': 'tool', 'tool_call_id': 'c1', 'content': '<html>'},
        {'role': 'assistant', 'content': '首页看完了。'},
        {'role': 'user', 'content': '跑一下构建'},
        {'role': 'assistant', 'content': '已经在后台跑了。'},
        {'role': 'user', 'content': '后台命令结束了', '_notice': '后台命令 #1 结束了'},
        {'role': 'assistant', 'content': '构建成功。'},
      ];
      await boot(tester, seed: seed);
      await show(tester);
      final position = tester.state<ScrollableState>(find.byType(Scrollable).first).position;
      Future<void> reveal(String id) async {
        for (final at in [0.0, position.maxScrollExtent / 2, position.maxScrollExtent]) {
          if (bar(id).evaluate().isNotEmpty) break;
          position.jumpTo(at);
          await tester.pump();
        }
        await tester.ensureVisible(bar(id));
        await tester.pump();
      }

      for (final (text, why) in [('很早的问题', '压缩归档的我的消息'), ('很早的回答', '压缩归档的回复'), ('看看首页', '带步骤那一轮的提问'), ('首页看完了。', '步骤后面的正式回复'), ('跑一下构建', '普通提问'), ('构建成功。', '一轮里最后一段回复')]) {
        final id = idOf(text);
        await reveal(id);
        expectFour(tester, id, why: why);
      }
      // 我的消息第三个叫“重新发送”，Agent 的叫“重试”
      expect(tester.widget<Tooltip>(find.descendant(of: icon('retry', idOf('跑一下构建')), matching: find.byType(Tooltip)).first).message, '重新发送');
      expect(tester.widget<Tooltip>(find.descendant(of: icon('retry', idOf('构建成功。')), matching: find.byType(Tooltip)).first).message, '重试');
      // Agent 的一轮只在最后一段正文下面有一排；这一排管的是这一轮的全部正文
      final mid = idOf('已经在后台跑了。');
      final last = idOf('构建成功。');
      expect(bar(mid), findsNothing, reason: '一轮中间的正文段下面没有操作栏');
      final target = tester.widget<MessageActionBar>(find.ancestor(of: bar(last), matching: find.byType(MessageActionBar))).target;
      expect([for (final p in target.parts) p.id], [mid, last]);
      expect(target.copyText, '已经在后台跑了。\n\n构建成功。', reason: '复制＝这一轮各段正文连起来');
      expect(tester.widget<MessageActionBar>(find.ancestor(of: bar(idOf('首页看完了。')), matching: find.byType(MessageActionBar))).target.copyText, '我先读一下。\n\n首页看完了。', reason: '工具调用之间说的话也是这一轮的正文');
      // 不该有的：一轮中间的话下面、压缩那一行、应用通知
      expect(session.chat.whereType<AssistantItem>().where((i) => i.text == '我先读一下。').single.id, isNotNull);
      expect(bar(idOf('我先读一下。')), findsNothing, reason: '工具之间说的话是一轮中间的一段，操作栏只在这一轮末尾');
      expect(session.chat.whereType<UserItem>().map((i) => i.text), isNot(contains('后台命令结束了')));
      expect(tester.takeException(), isNull);
      await shot(tester, 'fb5-edit-01-four-buttons-$suffix');

      // 这一轮有两段正文：点编辑先选改哪一段
      await tapIcon(tester, 'edit', last);
      await tester.pumpAndSettle();
      expect(find.byType(ReplyPartSheet), findsOneWidget);
      expect(find.text('改哪一段？'), findsOneWidget);
      expect(find.byKey(ValueKey('reply-part-$mid')), findsOneWidget);
      expect(find.byKey(ValueKey('reply-part-$last')), findsOneWidget);
      expect(tester.getSize(find.byKey(ValueKey('reply-part-$mid'))).height, greaterThanOrEqualTo(48));
      await shot(tester, 'fb5-edit-08-pick-part-$suffix');
      await tester.tap(find.byKey(ValueKey('reply-part-$mid')));
      await tester.pumpAndSettle();
      expect(find.byType(ReplyEditorScreen), findsOneWidget);
      expect(tester.widget<TextField>(field).controller!.text, '已经在后台跑了。');
      await tester.enterText(field, '构建已经放到后台跑了。');
      await tester.pump();
      await tester.runAsync(() async {
        await tester.tap(save);
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();
      expect(find.byType(ReplyEditorScreen), findsNothing);
      expect(session.chat.whereType<AssistantItem>().map((i) => i.text), contains('构建已经放到后台跑了。'));
      expect(find.byKey(ValueKey('message-edited-$last')), findsOneWidget, reason: '这一轮有改过的段：末尾那一排标“已编辑”');
      expect(onDisk().where((m) => m['content'] == '构建已经放到后台跑了。').single['_edited'], isTrue);
      expect(onDisk().where((m) => m['content'] == '构建成功。').single.containsKey('_edited'), isFalse);
      // 取消选择：什么都不发生
      await tapIcon(tester, 'edit', last);
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(195, 60));
      await tester.pumpAndSettle();
      expect(find.byType(ReplyPartSheet), findsNothing);
      expect(find.byType(ReplyEditorScreen), findsNothing);
      expect(tester.takeException(), isNull);
    });

    Future<void> until(bool Function() cond, String what) async {
      for (var i = 0; i < 500 && !cond(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      if (!cond()) fail('等不到：$what');
    }

    Future<void> expectBars(WidgetTester tester, List<(String, String)> rows) async {
      await show(tester);
      expect(session.agentBusy, isFalse);
      for (final (text, why) in rows) {
        final id = idOf(text);
        await tester.ensureVisible(bar(id));
        await tester.pump();
        expectFour(tester, id, why: why);
      }
      expect(tester.takeException(), isNull);
    }

    testWidgets('说到一半接口报错：半截回复留着，它和我的那条消息下面都是四个按钮 ($suffix)', (tester) async {
      await boot(tester);
      turn = (m, t) => throw const _Broken('说到一半');
      await tester.runAsync(() async {
        unawaited(session.sendToAgent('第一问'));
        await until(() => !session.agentBusy && session.chat.whereType<AssistantItem>().any((i) => i.text == '说到一半' && !i.streaming), '出错收尾');
      });
      await expectBars(tester, [('第一问', '出错那一轮的提问'), ('说到一半', '出错留下的半截回复')]);
    });

    // 点停止要走原生通道（保活通知、清进程），界面测试台里不应答；所以这两种用“停下以后盘上留下的样子”来搭。
    // 停止 / 出错时消息照样带稳定 id，见 message_branches_session_test.dart、message_actions_session_test.dart。
    testWidgets('被停下的那一轮：已经说出来的那段、只有步骤没有正式回复的那一轮——都有地方点编辑和重试 ($suffix)', (tester) async {
      await boot(
        tester,
        seed: [
          {'role': 'user', 'content': '第二问'},
          {
            'role': 'assistant',
            'content': '',
            'tool_calls': [
              {
                'id': 'c1',
                'type': 'function',
                'function': {'name': 'read_file', 'arguments': '{"path":"index.html"}'},
              },
            ],
          },
          {'role': 'tool', 'tool_call_id': 'c1', 'content': '<html>'},
          {'role': 'user', 'content': '第三问'},
          {'role': 'assistant', 'content': '说了一句就被停了'},
        ],
      );
      await expectBars(tester, [('第二问', '只有步骤的那一轮的提问'), ('第三问', '被停下那一轮的提问'), ('说了一句就被停了', '被停下时已经说出来的那段')]);
      expect(find.byType(StepGroupView), findsWidgets);
    });

    testWidgets('编辑 Agent 的回复：整页编辑器；没改动“保存”是灰的；改了保存→回到聊天、气泡是新文字、带“已编辑”、盘上也是；没有重新生成 ($suffix)', (tester) async {
      await boot(tester);
      var calls = 0;
      turn = (m, t) {
        calls++;
        return lastUser(m) == '看看首页' ? (hasToolResult(m) ? reply('首页看完了，结构没问题。') : use('read_file', {'path': 'index.html'})) : reply('不客气。');
      };
      await tester.runAsync(() async {
        await session.sendToAgent('看看首页');
        await session.sendToAgent('谢谢');
      });
      await show(tester);
      final id = idOf('首页看完了，结构没问题。');
      final asked = calls;
      expect(find.byKey(ValueKey('message-edited-$id')), findsNothing);
      await tapIcon(tester, 'edit', id);
      await tester.pumpAndSettle();
      expect(find.byType(ReplyEditorScreen), findsOneWidget);
      expect(find.text('编辑回复'), findsOneWidget);
      expect(tester.widget<TextField>(field).controller!.text, '首页看完了，结构没问题。');
      expect(noteText(tester), contains('不会让 Agent 重新回答'));
      expect(canSave(tester), isFalse, reason: '还没改动');
      expect(find.byKey(const ValueKey('reply-edit-restore')), findsNothing, reason: '没改过的回复没有“恢复原文”');
      expect(find.byKey(const ValueKey('edit-chip')), findsNothing, reason: '不是“从这条重新来”那种编辑');
      await shot(tester, 'fb5-edit-02-editor-$suffix');

      // 清空：不许保存，写明原因
      await tester.enterText(field, '   ');
      await tester.pump();
      expect(canSave(tester), isFalse);
      expect(noteText(tester), kReplyEditEmpty);
      await shot(tester, 'fb5-edit-03-editor-empty-$suffix');

      await tester.enterText(field, '首页看完了：标题太长，建议缩短。\n\n另外页脚少了备案号。');
      await tester.pump();
      expect(canSave(tester), isTrue);
      await tester.tap(save);
      await settle(tester, rounds: 5);
      expect(find.byType(ReplyEditorScreen), findsNothing, reason: '存好就回到聊天');
      expect(find.textContaining('已保存修改'), findsOneWidget);
      expect(find.textContaining('首页看完了：标题太长，建议缩短。'), findsWidgets);
      expect(find.text('首页看完了，结构没问题。'), findsNothing);
      expect(find.byKey(ValueKey('message-edited-$id')), findsOneWidget);
      expect(find.text('已编辑'), findsOneWidget, reason: '只有改过的这一条带记号');
      expectFour(tester, id, why: '改过的回复');
      expect(tester.getTopLeft(find.byKey(ValueKey('message-edited-$id'))).dx, greaterThan(tester.getTopLeft(icon('more', id)).dx), reason: '记号在四个按钮外侧');
      final disk = onDisk().firstWhere((m) => m['_id'] == id);
      expect(disk['content'], '首页看完了：标题太长，建议缩短。\n\n另外页脚少了备案号。');
      expect(disk[kEditedMark], isTrue);
      expect(calls, asked, reason: '没有重新生成');
      expect(session.conversations, hasLength(1), reason: '没有另存旧版本');
      await shot(tester, 'fb5-edit-04-edited-mark-$suffix');

      // 再打开：多了“恢复原文”；点了把原话放回输入框，还要点保存才算
      await tester.pump(const Duration(seconds: 5));
      await tapIcon(tester, 'edit', id);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('reply-edit-restore')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('reply-edit-restore')));
      await tester.pump();
      expect(tester.widget<TextField>(field).controller!.text, '首页看完了，结构没问题。');
      expect(find.byKey(const ValueKey('reply-edit-restore')), findsNothing, reason: '已经是原文了');
      expect(onDisk().firstWhere((m) => m['_id'] == id)[kEditedMark], isTrue, reason: '还没点保存');
      await tester.tap(save);
      await settle(tester, rounds: 5);
      expect(find.textContaining('已恢复成原文'), findsOneWidget);
      expect(find.byKey(ValueKey('message-edited-$id')), findsNothing);
      expect(onDisk().firstWhere((m) => m['_id'] == id).containsKey(kEditedMark), isFalse);
    });

    testWidgets('取消：没改动直接回去；改了要先问一句，选“取消”留在编辑页、选“放弃”才走，什么都没存 ($suffix)', (tester) async {
      await boot(tester);
      await tester.runAsync(() => session.sendToAgent('你好'));
      await show(tester);
      final id = idOf('好的。');
      await tapIcon(tester, 'edit', id);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('reply-edit-cancel')));
      await tester.pumpAndSettle();
      expect(find.byType(ReplyEditorScreen), findsNothing);

      await tapIcon(tester, 'edit', id);
      await tester.pumpAndSettle();
      await tester.enterText(field, '改了一半');
      await tester.pump();
      // 系统返回键也一样要问
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('放弃修改？'), findsOneWidget);
      await shot(tester, 'fb5-edit-05-discard-confirm-$suffix');
      await tester.tap(find.widgetWithText(TextButton, '取消').last);
      await tester.pumpAndSettle();
      expect(find.byType(ReplyEditorScreen), findsOneWidget);
      expect(tester.widget<TextField>(field).controller!.text, '改了一半', reason: '改的还在');
      await tester.tap(find.byTooltip('取消'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, '放弃'));
      await tester.pumpAndSettle();
      expect(find.byType(ReplyEditorScreen), findsNothing);
      expect(find.text('好的。'), findsWidgets);
      expect(find.text('已编辑'), findsNothing);
      expect(onDisk().firstWhere((m) => m['_id'] == id)['content'], '好的。');
    });

    testWidgets('手机上好不好用：很长的回复能滚；键盘弹起时输入框缩短，说明和“取消 / 保存”都在键盘上面 ($suffix)', (tester) async {
      await boot(tester);
      final long = [for (var i = 1; i <= 300; i++) '第 $i 行：这是一段比较长的说明文字，用来把回复撑得很长。'].join('\n');
      turn = (m, t) => reply(long);
      await tester.runAsync(() => session.sendToAgent('写长一点'));
      await show(tester);
      final id = session.chat.whereType<AssistantItem>().single.id!;
      await tester.ensureVisible(bar(id));
      await tester.pump();
      await tapIcon(tester, 'edit', id);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final tall = tester.getSize(field).height;
      expect(tall, greaterThan(500), reason: '输入框占满中间');
      expect(tester.getBottomLeft(save).dy, lessThanOrEqualTo(844));

      // 键盘弹起（占 320）
      tester.view.viewInsets = const FakeViewPadding(bottom: 320);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      const keyboardTop = 844 - 320;
      expect(tester.getBottomLeft(save).dy, lessThanOrEqualTo(keyboardTop), reason: '保存没被键盘挡住');
      expect(tester.getBottomLeft(note).dy, lessThan(tester.getTopLeft(save).dy));
      expect(tester.getBottomLeft(field).dy, lessThan(tester.getTopLeft(note).dy));
      expect(tester.getSize(field).height, lessThan(tall));
      expect(tester.getSize(field).height, greaterThan(200), reason: '键盘弹起后还有地方看字');
      expect(tester.getSize(save).height, greaterThanOrEqualTo(48));
      expect(tester.getSize(find.byKey(const ValueKey('reply-edit-cancel'))).height, greaterThanOrEqualTo(48));
      await shot(tester, 'fb5-edit-06-editor-keyboard-$suffix');
      await tester.enterText(field, '$long\n最后加一行');
      await tester.pump();
      await tester.tap(save);
      await settle(tester, rounds: 5);
      expect(find.byType(ReplyEditorScreen), findsNothing);
      expect(onDisk().last['content'], endsWith('最后加一行'));
    });

    testWidgets('Agent 正在回复：回复下面的“编辑”“重试”是灰的，点了说原因、不打开编辑页；停下后能用 ($suffix)', (tester) async {
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
      final ok = idOf('好的。');
      final c = tester.element(bar(ok)).colors;
      for (final k in ['edit', 'retry']) {
        expect(
          tester.widget<Icon>(find.descendant(of: icon(k, ok), matching: find.byType(Icon))).color,
          c.border,
          reason: '$k 是灰的',
        );
      }
      expect(
        tester.widget<Icon>(find.descendant(of: icon('copy', ok), matching: find.byType(Icon))).color,
        c.textFaint,
        reason: '复制照常',
      );
      await tapIcon(tester, 'edit', ok);
      expect(find.text(kEditReplyWhileBusy), findsOneWidget);
      expect(find.byType(ReplyEditorScreen), findsNothing);
      await shot(tester, 'fb5-edit-07-busy-$suffix');
      gate.complete();
      await waitReal(tester, () => !session.agentBusy, what: '这一轮结束');
      await tester.pump(const Duration(seconds: 5));
      await tapIcon(tester, 'edit', ok);
      await tester.pumpAndSettle();
      expect(find.byType(ReplyEditorScreen), findsOneWidget);
    });

    testWidgets('编辑页开着的时候这段回复被删了：保存时说明原因，留在编辑页，不崩 ($suffix)', (tester) async {
      await boot(tester);
      await tester.runAsync(() => session.sendToAgent('你好'));
      await show(tester);
      final id = idOf('好的。');
      await tapIcon(tester, 'edit', id);
      await tester.pumpAndSettle();
      await tester.runAsync(() => session.messageOps.delete(id, DeleteScope.turn));
      await tester.enterText(field, '改了');
      await tester.pump();
      await tester.tap(save);
      await settle(tester, rounds: 4);
      expect(find.byType(ReplyEditorScreen), findsOneWidget);
      expect(noteText(tester), contains('不在记录里'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('编辑我的消息：还是老样子——放回输入框、出现“正在编辑”条，不打开整页编辑器 ($suffix)', (tester) async {
      await boot(tester);
      await tester.runAsync(() => session.sendToAgent('你好'));
      await show(tester);
      await tapIcon(tester, 'edit', idOf('你好'));
      expect(find.byKey(const ValueKey('edit-chip')), findsOneWidget);
      expect(find.byType(ReplyEditorScreen), findsNothing);
      expect(find.byType(MessageActionBar), findsNWidgets(2));
    });
  }
}
