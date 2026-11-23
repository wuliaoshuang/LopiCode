// “正在聊”的状态（lib/state/workspace_chat.dart）：一段对话的条目和忙不忙、确认卡 / 提问卡、排队的消息。
// Agent 真跑起来的行为（权限、插话、子代理……）在 test/session_system_test.dart。
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/agent/agent_tools.dart';
import 'package:lopicode/agent/usage.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/state/team_state.dart';
import 'package:lopicode/state/workspace_chat.dart';
import 'package:lopicode/state/workspace_conversations.dart';
import 'package:riverpod/riverpod.dart';

import 'support/harness.dart';

void main() {
  late TestEnv env;
  late Project project;
  late ProjectSession session;
  late ProviderContainer box;

  setUp(() async {
    env = await TestEnv.create();
    project = await env.services.projects.create('测试工作区', ProjectTemplate.web);
    session = ProjectSession(env.services, project, headless: true);
    box = env.services.container;
  });
  tearDown(() {
    session.dispose();
    env.dispose();
  });

  ApprovalRequest request({bool allowAlways = true}) => ApprovalRequest(tool: 'run_command', title: '执行命令', detail: 'ls', allowAlways: allowAlways);

  group('一段对话的运行', () {
    test('加、换、删条目：每次都是新列表，旧的那份和旧条目都不变；列表不能被外面直接改', () {
      final run = box.read(chatRunProvider((session, 'main')).notifier);
      var n = 0;
      box.listen(chatRunProvider((session, 'main')), (_, _) => n++);
      run.add(const UserItem('你好'));
      const first = AssistantItem('好', streaming: true);
      run.add(first);
      final before = box.read(chatRunProvider((session, 'main')));
      final grown = run.replace(first, first.copyWith(text: '好的。'));
      expect((first.text, first.streaming), ('好', true), reason: '旧条目没被改');
      expect(before.items.last, same(first), reason: '旧状态没被改');
      expect((run.items.last as AssistantItem).text, '好的。');
      run.replace(grown, grown.copyWith(streaming: false));
      expect((run.items.last as AssistantItem).streaming, isFalse);

      const tool = ToolItem('c1', 'run_command', '{}');
      run.add(tool);
      expect(tool.running, isTrue);
      run.replace(tool, tool.copyWith(result: '用户拒绝', ok: false, denied: true));
      final done = run.items.last as ToolItem;
      expect((done.running, done.ok, done.denied, done.callId), (false, false, true, 'c1'));
      expect(run.replace(tool, tool.copyWith(result: '再换一次')), same(tool), reason: '已经不在列表里的换不了');
      expect((run.items.last as ToolItem).result, '用户拒绝');

      run.removeAt(0);
      run.removeAt(99);
      expect(run.items.length, 2);
      expect(() => box.read(chatRunProvider((session, 'main'))).items.add(const NoticeItem('x')), throwsUnsupportedError);
      expect(n, 7, reason: '七次真改动各通知一次；没改成的不通知');
    });

    test('忙不忙、读没读过、这一轮的用量：各自通知；两段对话互不串', () {
      final a = box.read(chatRunProvider((session, 'a')).notifier);
      var na = 0, nb = 0;
      box.listen(chatRunProvider((session, 'a')), (_, _) => na++);
      box.listen(chatRunProvider((session, 'b')), (_, _) => nb++);
      a.setBusy(true);
      a.markLoaded();
      final turn = TurnUsage();
      a.setTurn(turn);
      a.bumpRev();
      final st = box.read(chatRunProvider((session, 'a')));
      expect((st.busy, st.loaded, st.rev), (true, true, 1));
      expect(st.turn, same(turn));
      expect((na, nb), (4, 0));
      expect(box.read(chatRunProvider((session, 'b'))).busy, isFalse);
    });

    test('当前对话换了，“当前对话的运行状态”跟着换', () async {
      final convs = box.read(conversationsProvider(session).notifier);
      await convs.load();
      convs.add(Conversation('two', '', DateTime(2026, 11, 23)));
      box.read(chatRunProvider((session, 'main')).notifier).add(const UserItem('主对话里的'));
      box.read(chatRunProvider((session, 'two')).notifier).add(const UserItem('第二段里的'));
      String shown() => (box.read(activeChatProvider(session)).items.single as UserItem).text;
      expect(shown(), '主对话里的');
      convs.activate('two');
      expect(shown(), '第二段里的');
    });

    test('工作区关掉并收完尾：还能记（收尾存盘要读），但不再通知；应用退出后临时建的也只记不通知', () {
      final closing = ProjectSession(env.services, project, headless: true);
      final run = box.read(chatRunProvider((closing, 'main')).notifier);
      var n = 0;
      box.listen(chatRunProvider((closing, 'main')), (_, _) => n++);
      closing.dispose();
      expect(closing.released, isTrue);
      box.read(chatRunProvider((closing, 'main')));
      final n0 = n;
      run.add(const NoticeItem('收尾时加的'));
      expect(run.items.single, isA<NoticeItem>());
      expect(n, n0);

      final detached = ChatRunNotifier((closing, 'x'))..add(const UserItem('没接容器'));
      expect(detached.items.single, isA<UserItem>());
    });
  });

  group('确认卡 / 提问卡', () {
    PendingCardsNotifier cards() => box.read(pendingCardsProvider(session).notifier);
    PendingCardsState now() => box.read(pendingCardsProvider(session));
    String? rootOf(String id) => switch (id) {
      'main' || 'kid' => 'main',
      'other' => 'other',
      _ => null,
    };

    test('一张一张出：先来的先答；拒绝就是 false', () async {
      final a = cards().requestApproval(PendingApproval(request(), conversationId: 'main'));
      final b = cards().requestApproval(PendingApproval(request(), conversationId: 'main'));
      expect(now().approvals.length, 2);
      cards().resolveApproval(false, rootOf: rootOf, fallbackRoot: 'main');
      expect(await a, isFalse);
      expect(now().approvals.length, 1);
      cards().resolveApproval(true, rootOf: rootOf, fallbackRoot: 'main');
      expect(await b, isTrue);
      expect(now().approval, isNull);
      expect(now().autoAllow, isEmpty, reason: '没点“本对话都允许”就不记');
      cards().resolveApproval(true, rootOf: rootOf, fallbackRoot: 'main'); // 没有卡了：不报错
    });

    test('“本对话都允许”：只放行同一段主对话里排着的同类卡；别的对话的、不允许“都允许”的卡照样要问', () async {
      final first = cards().requestApproval(PendingApproval(request(), conversationId: 'kid'));
      final sameRoot = cards().requestApproval(PendingApproval(request(), conversationId: 'main'));
      final otherRoot = cards().requestApproval(PendingApproval(request(), conversationId: 'other'));
      final special = cards().requestApproval(PendingApproval(request(allowAlways: false), conversationId: 'main'));
      cards().resolveApproval(true, always: true, rootOf: rootOf, fallbackRoot: 'main');
      expect(await first, isTrue);
      expect(await sameRoot, isTrue);
      expect(now().autoAllow, {'main'});
      expect(cards().autoAllowed('main'), isTrue);
      expect(cards().autoAllowed('other'), isFalse);
      expect(now().approvals.map((a) => a.conversationId), ['other', 'main'], reason: '另一段对话的卡、单独确认的卡还在等');
      // 单独确认的卡点“都允许”也不算数
      cards().resolveApproval(false, rootOf: rootOf, fallbackRoot: 'main');
      expect(await otherRoot, isFalse);
      cards().resolveApproval(true, always: true, rootOf: rootOf, fallbackRoot: 'x');
      expect(await special, isTrue);
      expect(now().autoAllow, {'main'}, reason: '不允许“都允许”的卡不会把别的对话记成都允许');
      cards().clearAutoAllow('main');
      expect(cards().autoAllowed('main'), isFalse);
    });

    test('拒绝时点“都允许”不算数', () async {
      final a = cards().requestApproval(PendingApproval(request(), conversationId: 'main'));
      cards().resolveApproval(false, always: true, rootOf: rootOf, fallbackRoot: 'main');
      expect(await a, isFalse);
      expect(now().autoAllow, isEmpty);
    });

    test('提问卡：空回答写成“没有回答”；对话停了，它名下的卡都收掉（确认卡按拒绝）', () async {
      final q1 = cards().ask(PendingQuestion('用哪个配色？', const ['蓝', '绿'], conversationId: 'main'));
      cards().answerQuestion('  ');
      expect(await q1, '（用户没有回答）');
      final q2 = cards().ask(PendingQuestion('再问一次', const [], conversationId: 'kid'));
      final a = cards().requestApproval(PendingApproval(request(), conversationId: 'kid'));
      final keep = cards().requestApproval(PendingApproval(request(), conversationId: 'other'));
      cards().dropOf({'kid'});
      expect(await q2, contains('已停止'));
      expect(await a, isFalse);
      expect(now().approvals.single.conversationId, 'other');
      expect(now().question, isNull);
      cards().resolveApproval(true, rootOf: rootOf, fallbackRoot: 'main');
      expect(await keep, isTrue);
    });
  });

  group('排队 / 插话', () {
    SendQueueNotifier queue() => box.read(sendQueueProvider(session).notifier);
    SendQueueState now() => box.read(sendQueueProvider(session));

    test('排队、改成插话、撤回、取下一条：消息不可变，改了是换一条新的', () {
      const a = QueuedMessage('第一条'), b = QueuedMessage('第二条');
      queue()
        ..add(a)
        ..add(b);
      final steered = queue().setSteer(a, true)!;
      expect((a.steer, steered.steer), (false, true), reason: '旧的那条没被改');
      expect(now().queue.first, same(steered));
      expect(queue().setSteer(a, true), isNull, reason: '旧的那条已经不在队里');
      queue().unsteerAll();
      expect(now().queue.every((q) => !q.steer), isTrue);
      expect(queue().remove(a), isFalse);
      expect(queue().remove(b), isTrue);
      expect(queue().takeFirst()!.text, '第一条');
      expect(queue().takeFirst(), isNull);
      expect(() => now().queue.add(a), throwsUnsupportedError);
    });

    test('模型看到插话后从队里拿掉：只拿插话的那条，排队的同样文字不动', () {
      queue()
        ..add(const QueuedMessage('改成红色', steer: true))
        ..add(const QueuedMessage('改成红色'));
      queue().dropSteered('改成红色');
      expect(now().queue.single.steer, isFalse);
    });

    test('草稿：交还给输入框的文字，拿走就清掉；清空队列不动草稿', () {
      var n = 0;
      box.listen(sendQueueProvider(session), (_, _) => n++);
      queue().setDraft('没发出去的话');
      queue().clear();
      expect(n, 1, reason: '队列本来就是空的，清空不通知');
      expect(now().restoredDraft, '没发出去的话');
      expect(queue().takeDraft(), '没发出去的话');
      expect(now().restoredDraft, isNull);
      expect(queue().takeDraft(), isNull);
    });
  });

  test('任务板的状态：工作区关掉以后不再通知', () async {
    final key = (session, session.activeConversationId);
    var n = 0;
    box.listen(teamProvider(key), (_, _) => n++);
    final board = await session.boardById(key.$2);
    await board.create(title: '搭框架');
    final seen = n;
    expect(seen, greaterThan(0));
    expect(box.read(teamProvider(key))!.tasks.single.title, '搭框架');

    final closing = ProjectSession(env.services, project, headless: true);
    final closingKey = (closing, 'c1');
    var m = 0;
    box.listen(teamProvider(closingKey), (_, _) => m++);
    final late_ = box.read(teamProvider(closingKey).notifier);
    final lateBoard = await closing.boardById('c1');
    closing.dispose();
    box.read(teamProvider(closingKey));
    final after = m;
    late_.publish(lateBoard.view);
    await lateBoard.create(title: '关掉以后');
    expect(m, after, reason: '关掉的工作区不再写状态');
    expect(box.read(teamProvider(closingKey)), isNull);
    await board.create(title: '写页面');
    expect(n, greaterThan(seen));
  });
}
