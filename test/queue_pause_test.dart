// 第 8 条：排队的消息可以编辑 / 删除；这一轮出错或被停止后队列“已暂停”，点“继续发送”才发。
// 状态单元 + 会话（假模型）+ 390×844 界面（浅色 / 深色）。不联网。
//   LOPI_SHOTS=1 flutter test test/queue_pause_test.dart   # 同时写截图到 docs/screenshots/（ap8-…）
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/agent/chat_client.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/state/workspace_chat.dart';
import 'package:lopicode/ui/project_shell.dart';
import 'package:material_ui/material_ui.dart';

import 'agent_test.dart' show RecordingRunner;
import 'agent_ui_test.dart' show waitReal;
import 'screens_test.dart' show shot, fontsLoaded;
import 'session_system_test.dart' show lastUser, reply, waitFor;
import 'support/harness.dart';

/// 每次调用模型都交给 [turn]（拿到“第几次”和消息），它给一条流：可以先吐字再抛错。
class StreamClient implements ChatClient {
  StreamClient(this.turn, this.seen);
  final Stream<ChatDelta> Function(int call, List<Map<String, dynamic>> messages) turn;
  final List<String> seen;

  @override
  Stream<ChatDelta> streamChat({required List<Map<String, dynamic>> messages, List<Map<String, dynamic>> tools = const []}) {
    seen.add(lastUser(messages));
    return turn(seen.length - 1, messages);
  }
}

Stream<ChatDelta> ok([String text = '好']) => Stream.fromIterable(reply(text));
Stream<ChatDelta> boom({String? after}) async* {
  if (after != null) yield say(after);
  throw ChatApiException('服务器开小差了', statusCode: 400);
}

void main() {
  setUpAll(() async => fontsLoaded = await loadRealFonts());

  group('队列状态', () {
    test('暂停只在队里有消息时成立；队列空了自动不算暂停；编辑是换一条新的，位置、附件、身份不变', () async {
      final env = await TestEnv.create();
      final project = await env.services.projects.create('q', ProjectTemplate.web);
      final session = ProjectSession(env.services, project, headless: true);
      addTearDown(() async {
        session.dispose();
        await env.dispose();
      });
      final q = env.services.container.read(sendQueueProvider(session).notifier);
      q.setPaused(true);
      expect(q.current.paused, isFalse, reason: '空队列暂停不起来');
      const a = QueuedMessage(
        '一',
        images: [
          {'path': 'a.png'},
        ],
      );
      const b = QueuedMessage('二', steer: true);
      q
        ..add(a)
        ..add(b)
        ..setPaused(true);
      expect(q.current.paused, isTrue);
      final a2 = a.withText('一改');
      expect(q.replace(a, a2), isTrue);
      expect(q.replace(a, a2), isFalse, reason: '旧的那条已经不在队里');
      expect(q.current.queue.map((m) => m.text), ['一改', '二']);
      expect(q.current.queue.first.images, a.images);
      expect(b.withText('二改').steer, isTrue);
      q.remove(a2);
      expect(q.current.paused, isTrue);
      q.takeFirst();
      expect(q.current.paused, isFalse);
      q
        ..add(a)
        ..setPaused(true)
        ..clear();
      expect(q.current.paused, isFalse);
      expect(q.current.queue, isEmpty);
    });
  });

  group('会话', () {
    late TestEnv env;
    late Project project;
    late ProjectSession session;
    late List<String> seen;
    late Stream<ChatDelta> Function(int call, List<Map<String, dynamic>> messages) turn;

    setUp(() async {
      seen = [];
      turn = (_, _) => ok();
      env = await TestEnv.create(chatClient: () => StreamClient((i, m) => turn(i, m), seen));
      project = await env.services.projects.create('测试工作区', ProjectTemplate.web);
      session = ProjectSession(env.services, project, headless: true)..commandRunnerFactory = RecordingRunner.new;
      await session.loadChat();
    });
    tearDown(() async {
      session.dispose();
      await env.dispose();
    });

    Future<void> idle() async {
      await waitFor(() => !session.agentBusy, what: '停下来');
      await Future<void>.delayed(const Duration(milliseconds: 60));
    }

    /// 第一条卡在 [gate] 上，期间排两条。
    Future<({Future<void> done})> startWithTwoQueued(Completer<void> gate, {Stream<ChatDelta> Function()? first}) async {
      turn = (i, _) async* {
        if (i == 0) {
          await gate.future;
          yield* (first ?? ok)();
        } else {
          yield* ok();
        }
      };
      final done = session.sendToAgent('第一条');
      await waitFor(() => seen.isNotEmpty);
      await session.sendToAgent('排一');
      await session.sendToAgent('排二');
      expect(session.queue.map((q) => q.text), ['排一', '排二']);
      return (done: done);
    }

    test('正常做完：排着的照旧一条条自动发，不暂停', () async {
      final gate = Completer<void>();
      final done = (await startWithTwoQueued(gate)).done;
      gate.complete();
      await done;
      await waitFor(() => seen.length == 3, what: '三条都发了');
      await idle();
      expect(seen, ['第一条', '排一', '排二']);
      expect(session.queuePaused, isFalse);
      expect(session.queue, isEmpty);
    });

    test('点了停止：队列进入已暂停，不自动发；之后再发新消息，排着的也不会跟着发出去；点继续才发', () async {
      final gate = Completer<void>();
      final done = (await startWithTwoQueued(gate)).done;
      session.stopAgent();
      gate.complete();
      await done;
      await idle();
      expect(session.queuePaused, isTrue);
      expect(seen, ['第一条']);
      // 以前这里有个口子：停止后再发一条新消息，那一轮做完会把排着的顺手发掉。
      await session.sendToAgent('新的一条');
      await idle();
      expect(seen, ['第一条', '新的一条']);
      expect(session.queuePaused, isTrue);
      expect(session.queue.map((q) => q.text), ['排一', '排二']);
      session.resumeQueue();
      await waitFor(() => seen.length == 4, what: '继续后都发了');
      await idle();
      expect(seen, ['第一条', '新的一条', '排一', '排二']);
      expect(session.queuePaused, isFalse);
    });

    test('出错（模型已经回了一半）：以前会接着自动发，现在暂停', () async {
      final gate = Completer<void>();
      final done = (await startWithTwoQueued(gate, first: () => boom(after: '写到一半'))).done;
      gate.complete();
      await done;
      await idle();
      expect(session.queuePaused, isTrue);
      expect(seen, ['第一条']);
      expect(session.queue, hasLength(2));
    });

    test('出错（一个字没回，消息退回输入框）：暂停；草稿被拿走以后也不会偷偷发', () async {
      final gate = Completer<void>();
      final done = (await startWithTwoQueued(gate, first: boom)).done;
      gate.complete();
      await done;
      await idle();
      expect(session.restoredDraft, '第一条');
      expect(session.takeRestoredDraft(), '第一条');
      await idle();
      expect(session.queuePaused, isTrue);
      expect(seen, ['第一条']);
    });

    test('暂停时清空：全删，不发，也不再算暂停', () async {
      final gate = Completer<void>();
      final done = (await startWithTwoQueued(gate)).done;
      session.stopAgent();
      gate.complete();
      await done;
      await idle();
      session.clearQueue();
      expect(session.queue, isEmpty);
      expect(session.queuePaused, isFalse);
      await idle();
      expect(seen, ['第一条']);
    });

    test('暂停时“立即发送”其中一条：只发它，剩下的还停着', () async {
      final gate = Completer<void>();
      final done = (await startWithTwoQueued(gate)).done;
      session.stopAgent();
      gate.complete();
      await done;
      await idle();
      session.sendQueuedNow(session.queue.last);
      await waitFor(() => seen.length == 2);
      await idle();
      expect(seen, ['第一条', '排二']);
      expect(session.queue.single.text, '排一');
      expect(session.queuePaused, isTrue);
    });

    test('生成中“立即发送 / 中断并发送”是她自己要发的：不算暂停，剩下的接着发', () async {
      final gate = Completer<void>();
      final done = (await startWithTwoQueued(gate)).done;
      session.sendQueuedNow(session.queue.last);
      gate.complete();
      await done;
      await waitFor(() => seen.length == 3, what: '都发了');
      await idle();
      expect(seen, ['第一条', '排二', '排一']);
      expect(session.queuePaused, isFalse);
    });

    test('编辑：发出去的是改过的文字，图片还在；改成空的＝删掉；删除不交还输入框', () async {
      final gate = Completer<void>();
      turn = (i, _) async* {
        if (i == 0) await gate.future;
        yield* ok();
      };
      final done = session.sendToAgent('第一条');
      await waitFor(() => seen.isNotEmpty);
      await session.sendToAgent(
        '带图的',
        images: [
          {'path': '.lopicode-attachments/x.png', 'mime': 'image/png', 'name': 'x.png'},
        ],
      );
      await session.sendToAgent('要删的');
      await session.sendToAgent('会被清空的');
      session.editQueued(session.queue[0], '带图的，改过');
      expect(session.queue[0].text, '带图的，改过');
      expect(session.queue[0].images.single['path'], '.lopicode-attachments/x.png');
      session.deleteQueued(session.queue[1]);
      session.editQueued(session.queue[1], '   ');
      expect(session.queue.map((q) => q.text), ['带图的，改过']);
      expect(session.restoredDraft, isNull);
      // 带图的那条文字清空：留着图，文字换成占位
      session.editQueued(session.queue[0], '');
      expect(session.queue.single.text, '（见附件）');
      session.editQueued(session.queue[0], '最终版');
      gate.complete();
      await done;
      await waitFor(() => seen.length == 2);
      await idle();
      expect(seen.last, contains('最终版'));
      expect(session.chat.whereType<UserItem>().last.images.single, endsWith('x.png'));
    });

    test('编辑一条插话：模型下一步看到的是改过的那句，旧的那句不会再出现', () async {
      final gate = Completer<void>();
      var n = 0;
      final all = <String>[];
      turn = (i, m) async* {
        all.add(m.where((x) => x['role'] == 'user').map((x) => '${x['content']}').join('|'));
        if (n++ == 0) {
          await gate.future;
          yield call(0, 'list_files', '{}');
          yield ChatDelta(finishReason: 'tool_calls');
        } else {
          yield* ok();
        }
      };
      final done = session.sendToAgent('第一条');
      await waitFor(() => seen.isNotEmpty);
      await session.sendToAgent('旧插话', mode: SendMode.steer);
      session.editQueued(session.queue.single, '新插话');
      expect(session.queue.single.steer, isTrue);
      gate.complete();
      await done;
      await idle();
      expect(all.last, contains('新插话'));
      expect(all.join(), isNot(contains('旧插话')));
      expect(session.queue, isEmpty);
    });

    test('换对话：排着的和暂停状态一起清掉', () async {
      final gate = Completer<void>();
      final done = (await startWithTwoQueued(gate)).done;
      session.stopAgent();
      gate.complete();
      await done;
      await idle();
      expect(session.queuePaused, isTrue);
      await session.newConversation();
      expect(session.queue, isEmpty);
      expect(session.queuePaused, isFalse);
    });
  });

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    final suffix = mode == ThemeMode.light ? 'light' : 'dark';
    group('界面 ($suffix)', () {
      late TestEnv env;
      late Project project;
      late ProjectSession session;
      late List<String> seen;
      late Completer<void> gate;

      Future<void> boot(WidgetTester tester) async {
        usePhoneViewport(tester);
        seen = [];
        gate = Completer<void>();
        await tester.runAsync(() async {
          env = await TestEnv.create(
            chatClient: () => StreamClient((i, _) async* {
              if (i == 0) await gate.future;
              yield* ok('做完了。');
            }, seen),
          );
          project = await env.services.projects.create('我的小站', ProjectTemplate.web);
          session = ProjectSession(env.services, project)..commandRunnerFactory = RecordingRunner.new;
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
            font: fontsLoaded ? kTestFont : null,
          ),
        );
        await settle(tester, rounds: 6);
        await tester.enterText(find.byType(TextField), '把首页改成深色');
        await tester.pump();
        await tester.tap(find.byTooltip('发送'));
        await waitReal(tester, () => seen.isNotEmpty, what: '第一条发出去');
        await tester.runAsync(() async {
          await session.sendToAgent('顺便把页脚的年份改成今年');
          await session.sendToAgent('再检查一下手机上会不会横向滚动');
        });
        await settle(tester, rounds: 2);
      }

      Future<void> stop(WidgetTester tester) async {
        session.stopAgent();
        gate.complete();
        await waitReal(tester, () => !session.agentBusy, what: '停下');
      }

      testWidgets('停止后：顶上一行“已暂停 · 继续发送 / 清空”，每条消息一行；点继续才发', (tester) async {
        await boot(tester);
        expect(find.byKey(const Key('queue-paused')), findsNothing, reason: '正在生成时不显示暂停');
        await stop(tester);
        expect(find.byKey(const Key('queue-paused')), findsOneWidget);
        expect(find.text('继续发送'), findsOneWidget);
        expect(find.text('清空'), findsOneWidget);
        expect(find.text('顺便把页脚的年份改成今年'), findsOneWidget);
        expect(find.text('再检查一下手机上会不会横向滚动'), findsOneWidget);
        // 一行只做一件事：两条消息各占一行，高度一样，行上只有一个“…”
        final a = tester.getRect(find.text('顺便把页脚的年份改成今年')), b = tester.getRect(find.text('再检查一下手机上会不会横向滚动'));
        expect(b.top, greaterThan(a.bottom - 1));
        expect(find.byTooltip('处理这条消息'), findsNWidgets(2));
        expect(seen, hasLength(1));
        await shot(tester, 'ap8-01-queue-paused-$suffix');
        await tester.tap(find.byKey(const Key('queue-resume')));
        await waitReal(tester, () => seen.length == 3 && !session.agentBusy, what: '继续后发完');
        expect(find.byKey(const Key('queue-paused')), findsNothing);
        expect(session.queue, isEmpty);
      });

      testWidgets('行尾菜单：立即发送 / 编辑 / 撤回 / 删除；编辑在底部面板里改，保存后那一行跟着变', (tester) async {
        await boot(tester);
        await stop(tester);
        await tester.tap(find.byTooltip('处理这条消息').first);
        await settle(tester, rounds: 3);
        for (final label in ['立即发送', '编辑', '撤回', '删除']) {
          expect(find.text(label), findsOneWidget);
        }
        expect(find.text('改为插话'), findsNothing, reason: '没在生成，插不了话');
        await shot(tester, 'ap8-02-queue-menu-$suffix');
        await tester.tap(find.text('编辑'));
        await settle(tester, rounds: 3);
        expect(find.text('编辑排队的消息'), findsOneWidget);
        await tester.enterText(find.byKey(const Key('queue-edit-field')), '顺便把页脚的年份改成 2026');
        await settle(tester, rounds: 1);
        await shot(tester, 'ap8-03-queue-edit-$suffix');
        await tester.tap(find.byKey(const Key('queue-edit-save')));
        await settle(tester, rounds: 3);
        expect(session.queue.first.text, '顺便把页脚的年份改成 2026');
        expect(find.text('顺便把页脚的年份改成 2026'), findsOneWidget);
        expect(session.queuePaused, isTrue, reason: '编辑不会让它自己发出去');
        expect(seen, hasLength(1));
      });

      testWidgets('长按一行也开同一个菜单；删除只删这一条；清空要再确认一次（多于一条时）', (tester) async {
        await boot(tester);
        await tester.runAsync(() => session.sendToAgent('第三条'));
        await stop(tester);
        await tester.longPress(find.text('第三条'));
        await settle(tester, rounds: 3);
        expect(find.text('删除'), findsOneWidget);
        await tester.tap(find.text('删除'));
        await settle(tester, rounds: 3);
        expect(session.queue, hasLength(2));
        expect(find.text('第三条'), findsNothing);
        await tester.tap(find.byKey(const Key('queue-clear')));
        await settle(tester, rounds: 3);
        expect(find.text('清空排队的消息？'), findsOneWidget);
        await tester.tap(find.text('取消'));
        await settle(tester, rounds: 3);
        expect(session.queue, hasLength(2));
        await tester.tap(find.byKey(const Key('queue-clear')));
        await settle(tester, rounds: 3);
        await tester.tap(find.widgetWithText(TextButton, '清空').last);
        await settle(tester, rounds: 3);
        expect(session.queue, isEmpty);
        expect(find.byKey(const Key('queue-paused')), findsNothing);
        expect(seen, hasLength(1));
      });
    });
  }
}
