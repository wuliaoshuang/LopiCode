// 重试 / 编辑 / 分支在真实会话里（不带界面，假模型客户端）：重试真的重新发了同一条消息并走确认流程、编辑发的是新文字、
// 旧内容另存成“旧版本”、忙的时候被拒、分支复制的各项状态（待办、用量、授权、子代理、收藏、压缩）、存盘与重开、旧文件兼容。
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/agent/agent_tools.dart';
import 'package:lopicode/agent/auto_compact.dart';
import 'package:lopicode/agent/chat_client.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/safe_file.dart';
import 'package:lopicode/core/stores.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/session/chat_items.dart';
import 'package:lopicode/session/chat_rows.dart' show latestTodos;
import 'package:lopicode/session/message_branches.dart';
import 'package:lopicode/session/message_ops.dart';
import 'package:lopicode/state/message_edit.dart';
import 'package:lopicode/state/workspace_favorites.dart';

import 'agent_test.dart' show RecordingRunner;
import 'session_system_test.dart' show RoutingClient, Turn, firstUser, hasToolResult, lastUser, reply, use, waitFor;
import 'support/harness.dart';

void main() {
  late TestEnv env;
  late Project project;
  late ProjectSession session;
  late RecordingRunner shell;
  late List<({List<Map<String, dynamic>> messages, List<String> tools})> log;
  Turn turn = (_, _) => reply('好的。');

  setUp(() async {
    turn = (_, _) => reply('好的。');
    log = [];
    env = await TestEnv.create(chatClient: () => RoutingClient((m, t) => turn(m, t), log));
    project = await env.services.projects.create('测试工作区', ProjectTemplate.web);
    session = ProjectSession(env.services, project, headless: true);
    shell = RecordingRunner();
    session.commandRunnerFactory = () => shell;
    await session.loadChat();
  });
  tearDown(() async {
    session.dispose();
    await env.dispose();
  });

  File f(String rel) => File('${project.dir}/$rel');
  List<Map<String, dynamic>> onDisk(String convId) => [
    for (final m in jsonDecode(f('.lopicode/${convId == 'main' ? 'chat.json' : 'chat-$convId.json'}').readAsStringSync()) as List) (m as Map).cast<String, dynamic>(),
  ];
  List<String> texts(ProjectSession s) => [
    for (final i in s.chat)
      if (i is UserItem) '我:${i.text}' else if (i is AssistantItem) 'AI:${i.text}' else if (i is ToolItem) '步骤:${i.name}',
  ];
  String idOf(String text, [ProjectSession? s]) => switch ((s ?? session).chat.firstWhere((i) => (i is UserItem && i.text == text) || (i is AssistantItem && i.text == text))) {
    UserItem(:final id) => id!,
    AssistantItem(:final id) => id!,
    _ => fail('不是消息'),
  };
  List<String> userTexts(List<Map<String, dynamic>> messages) => [
    for (final m in messages)
      if (m['role'] == 'user') '${m['content']}',
  ];
  Conversation oldVersion() => session.conversations.singleWhere((c) => c.origin?.old ?? false);

  Future<ProjectSession> reopen() async {
    final again = ProjectSession(env.services, project, headless: true);
    addTearDown(again.dispose);
    await again.loadChat();
    return again;
  }

  group('重试', () {
    test('最后一轮：真的用同一条消息重新发；原来的回复另存成旧版本；记录合法；存盘和重开一致', () async {
      var n = 0;
      turn = (m, t) => reply(lastUser(m) == '讲个笑话' ? '笑话 ${++n}' : '好的。');
      await session.sendToAgent('你好');
      await session.sendToAgent('讲个笑话');
      expect(texts(session), ['我:你好', 'AI:好的。', '我:讲个笑话', 'AI:笑话 1']);
      final before = log.length;
      final usedBefore = session.usageTotals.requests;

      final start = await session.branches.retry(idOf('笑话 1'));
      expect(start.error, isNull);
      await start.turn;
      expect(texts(session), ['我:你好', 'AI:好的。', '我:讲个笑话', 'AI:笑话 2']);
      expect(log.length, before + 1, reason: '只多发了一次请求');
      expect(userTexts(log.last.messages), ['你好', '讲个笑话'], reason: '发给模型的是同一条用户消息，旧回复不在里面');
      expect(jsonEncode(log.last.messages), isNot(contains('笑话 1')));
      expect(wireProblems(onDisk('main')), isEmpty);
      expect(session.usageTotals.requests, usedBefore + 1, reason: '这一轮的用量照常累计，之前的不清');

      // 旧版本：一段单独的对话，带出处，内容是重试前的全部
      final old = oldVersion();
      expect(start.oldVersionId, old.id);
      expect(old.title, session.activeConversation.title);
      expect((old.origin!.convId, old.origin!.title, old.origin!.messageId), ('main', '你好', idOf('好的。')));
      expect([for (final m in onDisk(old.id)) '${m['content']}'], ['你好', '好的。', '讲个笑话', '笑话 1']);
      expect(old.usage.requests, 0, reason: '旧版本的累计用量从 0 计');
      expect(session.activeConversationId, 'main', reason: '人还留在原对话里');
      expect(session.topConversations.map((c) => c.id), ['main', old.id], reason: '旧版本紧跟在原对话后面');

      // 重开应用：两段都在，出处还在，能切过去看旧回复
      final again = await reopen();
      expect(texts(again), ['我:你好', 'AI:好的。', '我:讲个笑话', 'AI:笑话 2']);
      final kept = again.conversations.singleWhere((c) => c.origin != null);
      expect(kept.origin!.old, isTrue);
      await again.selectConversation(kept.id);
      expect(texts(again), ['我:你好', 'AI:好的。', '我:讲个笑话', 'AI:笑话 1']);
    });

    test('走原有的发送流程：权限档照常弹确认卡，拒绝就不执行；计划模式下拿不到写工具', () async {
      turn = (m, t) => hasToolResult(m) && lastUser(m) == '列一下文件' && m.last['role'] == 'tool' ? reply('看完了。') : use('run_command', {'command': 'ls'});
      final first = session.sendToAgent('列一下文件');
      await waitFor(() => session.pendingApproval != null, what: '第一次的确认卡');
      session.resolveApproval(true);
      await first;
      expect(shell.commands, ['ls']);

      final start = await session.branches.retry(idOf('看完了。'));
      expect(start.error, isNull);
      await waitFor(() => session.pendingApproval != null, what: '重试时照样弹确认卡');
      expect(session.agentBusy, isTrue);
      session.resolveApproval(false);
      await start.turn;
      expect(shell.commands, ['ls'], reason: '拒绝了：命令没有再跑');
      expect(texts(session).first, '我:列一下文件');

      // 计划模式：重试时模型拿不到执行命令的工具
      await session.setPlanMode(true);
      turn = (m, t) => reply('这是计划。');
      final again = await session.branches.retry(idOf('列一下文件'));
      await again.turn;
      expect(log.last.tools, isNot(contains('run_command')));
      expect(texts(session), ['我:列一下文件', 'AI:这是计划。']);
    });

    test('“本对话都允许”：重试后原对话里还在；旧版本和分支是新对话，重新逐次问', () async {
      var n = 0;
      turn = (m, t) => m.last['role'] == 'tool' ? reply('看完了 ${++n}。') : use('run_command', {'command': 'ls'});
      final first = session.sendToAgent('列一下');
      await waitFor(() => session.pendingApproval != null);
      session.resolveApproval(true, always: true);
      await first;
      expect(session.autoAllowActive, isTrue);
      final start = await session.branches.retry(idOf('看完了 1。'));
      await start.turn;
      expect(shell.commands, ['ls', 'ls'], reason: '原对话里授权还在：不再问');
      final branch = await session.branches.branch(idOf('看完了 2。'));
      expect(branch.opened, isTrue);
      expect(session.autoAllowActive, isFalse, reason: '分支是新对话：授权不带过去');
      final running = session.sendToAgent('再列一下');
      await waitFor(() => session.pendingApproval != null, what: '分支里重新问');
      session.resolveApproval(false);
      await running;
      await session.selectConversation(start.oldVersionId!);
      expect(session.autoAllowActive, isFalse, reason: '旧版本也不带授权');
    });

    test('更早的一轮：它和后面的轮一起移走并另存；Agent 改过的文件不撤销', () async {
      turn = (m, t) => switch (lastUser(m)) {
        '写个文件' => m.last['role'] == 'tool' ? reply('写好了。') : use('write_file', {'path': 'note.txt', 'content': '第一版'}),
        _ => reply('回：${lastUser(m)}'),
      };
      await session.sendToAgent('写个文件');
      await session.sendToAgent('第二轮');
      await session.sendToAgent('第三轮');
      final plan = session.branches.previewRewind(idOf('写好了。'))!;
      expect((plan.laterTurns, plan.steps, plan.changedFiles), (2, 1, true));
      turn = (m, t) => reply('这次不写了。');
      final start = await session.branches.retry(idOf('写好了。'));
      await start.turn;
      expect(texts(session), ['我:写个文件', 'AI:这次不写了。']);
      expect(f('note.txt').readAsStringSync(), '第一版', reason: '文件改动不回滚');
      expect(userTexts(onDisk(start.oldVersionId!)), ['写个文件', '第二轮', '第三轮']);
      expect(oldVersion().origin!.messageId, isNull, reason: '原对话在那之前没有消息');
    });

    test('带图片的消息：重试时图片还在', () async {
      final image = await session.saveAttachment([9, 8, 7], 'a.png');
      await session.sendToAgent('这是什么', images: [image]);
      final start = await session.branches.retry(idOf('好的。'));
      await start.turn;
      expect(session.chat.whereType<UserItem>().single.images, hasLength(1));
      expect(onDisk('main').first['_images'], [image]);
      expect(log.last.messages.last['content'], contains(image['path']));
    });

    test('出错的一轮：一个字没回的，消息照旧交还输入框（没有东西可重试）；做了几步才出错的，能重试', () async {
      turn = (m, t) => throw ChatApiException('接口 500');
      await session.sendToAgent('第一问');
      expect(session.chat.whereType<UserItem>(), isEmpty, reason: '原有的规矩：整条撤回');
      expect(session.restoredDraft, '第一问');
      expect(session.conversations.where((c) => c.origin != null), isEmpty);

      turn = (m, t) => m.last['role'] == 'tool' ? throw ChatApiException('接口 500') : use('read_file', {'path': 'index.html'});
      await session.sendToAgent('读一下首页');
      expect(texts(session).take(2), ['我:读一下首页', '步骤:read_file']);
      turn = (m, t) => reply('这次好了。');
      final start = await session.branches.retry(idOf('读一下首页'));
      expect(start.error, isNull);
      await start.turn;
      expect(texts(session), ['我:读一下首页', 'AI:这次好了。']);
      expect(wireProblems(onDisk('main')), isEmpty);
      expect(texts(session).join(), isNot(contains('接口 500')), reason: '上次的报错不留在重试后的对话里');
    });

    test('App 被关掉留下的“上一轮没正常结束”提示：重试以后提示收掉，不重复出现', () async {
      final gate = Completer<void>();
      turn = (m, t) async {
        if (m.last['role'] == 'tool') await gate.future;
        return m.last['role'] == 'tool' ? reply('读完了。') : use('read_file', {'path': 'index.html'});
      };
      final done = session.sendToAgent('读一下');
      await waitFor(() => session.chat.whereType<ToolItem>().any((t) => !t.running), what: '第一步做完');
      await pendingWrites();
      final journalAtKill = f('.lopicode/turn.json').readAsStringSync();
      final chatAtKill = f('.lopicode/chat.json').readAsStringSync();
      gate.complete();
      await done;
      session.dispose();
      await pendingWrites();
      f('.lopicode/turn.json').writeAsStringSync(jsonEncode({...jsonDecode(journalAtKill) as Map<String, dynamic>, 'token': 'old'}));
      f('.lopicode/chat.json').writeAsStringSync(chatAtKill);
      session = ProjectSession(env.services, project, headless: true)..commandRunnerFactory = () => shell;
      await session.loadChat();
      expect(session.chat.whereType<InterruptedItem>(), hasLength(1));
      turn = (m, t) => reply('重新读完了。');
      final start = await session.branches.retry(idOf('读一下'));
      expect(start.error, isNull);
      await start.turn;
      expect(session.chat.whereType<InterruptedItem>(), isEmpty);
      expect(texts(session), ['我:读一下', 'AI:重新读完了。']);
      final again = await reopen();
      expect(again.chat.whereType<InterruptedItem>(), isEmpty, reason: '重开也不再提示');
    });

    test('停在步骤上的一轮（没有正式回复）：从我的那条消息“重新发送”', () async {
      final gate = Completer<void>();
      turn = (m, t) async {
        if (m.last['role'] == 'tool') await gate.future;
        return m.last['role'] == 'tool' ? reply('不会到这') : use('read_file', {'path': 'index.html'});
      };
      final running = session.sendToAgent('读一下');
      await waitFor(() => session.chat.whereType<ToolItem>().any((t) => !t.running), what: '第一步做完');
      session.stopAgent();
      gate.complete();
      await running;
      expect(session.chat.whereType<AssistantItem>(), isEmpty);
      turn = (m, t) => reply('读完了。');
      final start = await session.branches.retry(idOf('读一下'));
      expect(start.oldVersionId, isNotNull, reason: '有一步已经做了：另存');
      await start.turn;
      expect(texts(session), ['我:读一下', 'AI:读完了。']);
      expect(wireProblems(onDisk('main')), isEmpty);
    });

    test('Agent 正在回复时：重试、编辑都被拒，记录不动；排着的消息照常', () async {
      await session.sendToAgent('第一句');
      final gate = Completer<void>();
      turn = (m, t) async {
        await gate.future;
        return reply('第二句的回复');
      };
      final running = session.sendToAgent('第二句');
      await waitFor(() => session.agentBusy);
      final before = texts(session);
      expect((await session.branches.retry(idOf('好的。'))).error, kRewindWhileBusy);
      expect((await session.branches.resendEdited(idOf('第一句'), '改了', const [])).error, kRewindWhileBusy);
      expect(texts(session), before);
      expect(session.conversations.where((c) => c.origin != null), isEmpty);
      gate.complete();
      await running;
    });

    test('不在记录里的消息：说明原因，不动任何东西', () async {
      await session.sendToAgent('你好');
      expect((await session.branches.retry('没有这条')).error, kMessageGone);
      expect(texts(session), ['我:你好', 'AI:好的。']);
    });

    test('旧内容存不下来（存储写不了）：说明原因，当前对话一个字不动，也不发请求', () async {
      await session.sendToAgent('你好');
      await pendingWrites();
      final before = f('.lopicode/chat.json').readAsStringSync();
      final sent = log.length;
      // 把保留目录换成一个同名文件：往里写任何东西都会失败
      final dir = Directory('${project.dir}/.lopicode');
      final aside = dir.renameSync('${project.dir}/.lopicode.aside');
      final blocker = File(dir.path)..writeAsStringSync('x');
      final start = await session.branches.retry(idOf('好的。'));
      blocker.deleteSync();
      aside.renameSync(dir.path);
      expect(start.error, contains('存储写不了'));
      expect(start.turn, isNull);
      expect(log.length, sent);
      expect(texts(session), ['我:你好', 'AI:好的。']);
      expect(f('.lopicode/chat.json').readAsStringSync(), before);
      expect(session.conversations.where((c) => c.origin != null), isEmpty);
      // 存储恢复以后照常能重试
      final again = await session.branches.retry(idOf('好的。'));
      expect(again.error, isNull);
      await again.turn;
    });

    test('被移走的那几轮派出的子代理对话跟着旧版本走：旧版本里卡片还点得开，原对话重新派的对得上', () async {
      await env.services.settings.set(SettingKeys.subagentEnabled, true);
      await env.services.settings.set(SettingKeys.subagentMaxDepth, 1);
      var round = 0;
      turn = (m, t) {
        final task = firstUser(m);
        if (task.contains('写首页')) return reply('首页写好了 $round');
        return m.last['role'] == 'tool' ? reply('都做完了 $round') : use('spawn_agent', {'name': '前端', 'task': '写首页 home.html'});
      };
      round = 1;
      await session.sendToAgent('帮我做个站');
      final firstKid = session.subAgents.single.id;
      round = 2;
      final start = await session.branches.retry(idOf('都做完了 1'));
      await start.turn;
      final kids = session.subAgents;
      expect(kids, hasLength(1));
      expect(kids.single.id, isNot(firstKid));
      expect(session.chat.whereType<ToolItem>().single.childConversationId, kids.single.id);
      expect(session.conversationById(firstKid)!.parentId, start.oldVersionId);
      // 重开后也对得上（不是靠内存里的状态）
      final again = await reopen();
      expect(again.chat.whereType<ToolItem>().single.childConversationId, kids.single.id);
      await again.selectConversation(start.oldVersionId!);
      expect(again.chat.whereType<ToolItem>().single.childConversationId, firstKid);
      expect(onDisk(start.oldVersionId!)[1][kChildLinksKey], isA<Map<String, dynamic>>());
      // 删掉旧版本：它名下的子代理对话一起删，原对话的不受影响
      await again.deleteConversation();
      expect(again.conversationById(firstKid), isNull);
      expect(again.conversationById(kids.single.id), isNotNull);
    });

    test('收藏着被移走的消息：收藏跟到旧版本里，还能跳回原消息', () async {
      await session.sendToAgent('你好');
      final reply1 = session.chat.whereType<AssistantItem>().single;
      expect(await session.messageOps.toggleFavorite(reply1), isTrue);
      turn = (m, t) => reply('换个说法。');
      final start = await session.branches.retry(reply1.id!);
      await start.turn;
      final fav = env.services.container.read(favoritesProvider(session)).items.single;
      expect((fav.convId, fav.messageId, fav.gone), (start.oldVersionId, reply1.id, false));
      expect(session.messageOps.favoriteMissing(fav), isFalse);
    });

    test('这一轮中途自动压缩过：重试回到压缩之前的样子，发给模型的记录合法', () async {
      session.dispose();
      Map<String, dynamic> a(Map<String, dynamic> m) => {...m, kArchivedMark: true};
      f('.lopicode/chat.json').writeAsStringSync(
        jsonEncode([
          a({'role': 'user', 'content': '第一件', '_id': 'u1'}),
          a({'role': 'assistant', 'content': '做完了。', '_id': 'a1'}),
          a({'role': 'user', 'content': '第二件', '_id': 'u2'}),
          {'role': 'user', 'content': '$kCompactPrefix摘要', kCompactMark: true, '_id': 's1'},
          {'role': 'assistant', 'content': '第二件也做完了。', '_id': 'a2'},
        ]),
      );
      session = ProjectSession(env.services, project, headless: true);
      await session.loadChat();
      turn = (m, t) => reply('重做了第二件。');
      final start = await session.branches.retry('a2');
      expect(start.error, isNull);
      await start.turn;
      expect(userTexts(log.last.messages), ['第一件', '第二件'], reason: '摘要没了，原文重新发给模型');
      expect(wireProblems(onDisk('main')), isEmpty);
      expect(onDisk('main').any((m) => m[kArchivedMark] == true || m[kCompactMark] == true), isFalse);
      expect(onDisk(start.oldVersionId!).map((m) => m['_id']), ['u1', 'a1', 'u2', 's1', 'a2'], reason: '旧版本里是压缩后的原样');
    });
  });

  group('编辑', () {
    test('改了再发：发给模型的是新文字，旧的那一轮另存；后面的轮一起移走', () async {
      turn = (m, t) => reply('回：${lastUser(m)}');
      await session.sendToAgent('做个红色按钮');
      await session.sendToAgent('再大一点');
      final start = await session.branches.resendEdited(idOf('做个红色按钮'), '做个蓝色按钮', const []);
      expect(start.error, isNull);
      await start.turn;
      expect(texts(session), ['我:做个蓝色按钮', 'AI:回：做个蓝色按钮']);
      expect(userTexts(log.last.messages), ['做个蓝色按钮']);
      expect(userTexts(onDisk(start.oldVersionId!)), ['做个红色按钮', '再大一点']);
      expect(wireProblems(onDisk('main')), isEmpty);
    });

    test('编辑最后一条和更早的一条是同一套规矩；带上新图片', () async {
      turn = (m, t) => reply('回：${lastUser(m)}');
      await session.sendToAgent('一');
      await session.sendToAgent('二');
      final image = await session.saveAttachment([1, 2], 'b.png');
      final start = await session.branches.resendEdited(idOf('二'), '二（改）', [image]);
      await start.turn;
      expect(texts(session).take(3), ['我:一', 'AI:回：一', '我:二（改）']);
      expect(texts(session).last, startsWith('AI:回：二（改）'));
      expect(session.chat.whereType<UserItem>().last.images, hasLength(1));
      expect(userTexts(onDisk(start.oldVersionId!)), ['一', '二']);
    });

    test('改成空的：不发，不动', () async {
      await session.sendToAgent('你好');
      final start = await session.branches.resendEdited(idOf('你好'), '   ', const []);
      expect(start.error, contains('空的'));
      expect(texts(session), ['我:你好', 'AI:好的。']);
    });

    test('“正在编辑”的状态：开始、换一条、取消；换了对话自动取消；交接草稿拿走就清', () async {
      await session.sendToAgent('你好');
      final box = env.services.container;
      final sub = box.listen(messageEditProvider(session), (_, _) {});
      addTearDown(sub.close);
      final ctl = box.read(messageEditProvider(session).notifier);
      EditingMessage editing(String id) => EditingMessage(convId: 'main', messageId: id, original: ComposerDraft('你好', const []), laterTurns: 0, keepsOld: true);
      expect(box.read(messageEditProvider(session)).editing, isNull);
      ctl.start(editing('a'));
      ctl.start(editing('b'));
      expect(box.read(messageEditProvider(session)).editing!.messageId, 'b');
      ctl.cancel();
      expect(box.read(messageEditProvider(session)).editing, isNull);
      ctl.start(editing('a'));
      await session.newConversation();
      expect(box.read(messageEditProvider(session)).editing, isNull, reason: '换了对话：不再编辑');
      ctl.handOff(
        ComposerDraft('草稿', [
          {'path': 'a.png'},
        ]),
      );
      final taken = ctl.takeHandoff()!;
      expect((taken.text, taken.images.single['path']), ('草稿', 'a.png'));
      expect(() => taken.images.add({}), throwsUnsupportedError, reason: '交出去的是不可改的');
      expect(ctl.takeHandoff(), isNull);
    });
  });

  group('分支', () {
    Future<void> seed() async {
      turn = (m, t) => switch (lastUser(m)) {
        '列个计划' =>
          m.last['role'] == 'tool'
              ? reply('计划列好了。')
              : use('update_todos', {
                  'items': [
                    {'text': '写首页', 'status': 'in_progress'},
                    {'text': '写样式', 'status': 'pending'},
                  ],
                }),
        _ => reply('回：${lastUser(m)}'),
      };
      await session.sendToAgent('列个计划');
      await session.sendToAgent('第二轮');
    }

    test('从 Agent 的回复分支：另开一段对话并切过去，原对话一个字不动；两边互不影响，能切回去', () async {
      await seed();
      final before = onDisk('main');
      final at = idOf('计划列好了。');
      final r = await session.branches.branch(at);
      expect((r.error, r.opened, r.wholeTurn, r.draftHeld), (null, true, false, false));
      expect(session.activeConversationId, r.convId);
      expect(texts(session), ['我:列个计划', '步骤:update_todos', 'AI:计划列好了。']);
      expect(onDisk('main'), before);
      final conv = session.activeConversation;
      expect((conv.origin!.convId, conv.origin!.messageId, conv.origin!.old, conv.origin!.title), ('main', at, false, '列个计划'));
      expect(conv.title, '列个计划');
      expect(session.topConversations.first.id, conv.id, reason: '新分支排最前');

      // 在分支里接着聊：原对话不变；发给模型的是分支自己的记录
      await session.sendToAgent('分支里的话');
      expect(userTexts(log.last.messages), ['列个计划', '分支里的话']);
      expect(wireProblems(onDisk(conv.id)), isEmpty);
      expect(onDisk('main'), before);
      // 切回去
      expect(await session.branches.openOrigin(), isNull);
      expect(session.activeConversationId, 'main');
      expect(env.services.container.read(chatJumpProvider(session)), at, reason: '跳回分出来的那条消息');
      expect(texts(session).last, 'AI:回：第二轮');
      expect(session.branches.branchesByMessage[at]!.single.id, conv.id, reason: '原对话那条消息上看得到分出去的对话');
      expect(await session.branches.openConversation(conv.id), isNull);
      expect(texts(session).last, 'AI:回：分支里的话');
    });

    test('随对话走的东西：待办清单、每轮用量脚注带过去；累计用量从 0 计；模型 / 权限 / 计划模式 / 预设照抄', () async {
      await session.setPermission(PermissionLevel.view);
      await seed();
      final r = await session.branches.branch(idOf('计划列好了。'));
      final conv = session.conversationById(r.convId)!;
      expect(latestTodos(session.chat)!.map((t) => t.text), ['写首页', '写样式'], reason: '待办清单就在消息里，跟着过去');
      expect(session.chat.whereType<UsageItem>(), hasLength(1), reason: '消息上的用量脚注带过去');
      expect(conv.usage.requests, 0);
      expect(conv.lastInput, isNull);
      expect(session.permission, PermissionLevel.view);
      expect(session.conversationById('main')!.usage.requests, greaterThan(0), reason: '原对话的累计不动');
      // 重开：分支和出处都还在
      final again = await reopen();
      final back = again.conversationById(r.convId!)!;
      expect(back.origin!.convId, 'main');
      expect(back.permission, 'view');
    });

    test('从我的消息分支：抄到这条之前，这条的文字和图片交给输入框', () async {
      await seed();
      final r = await session.branches.branch(idOf('第二轮'));
      expect((r.opened, r.draftHeld), (true, true));
      expect(texts(session), ['我:列个计划', '步骤:update_todos', 'AI:计划列好了。']);
      final handoff = env.services.container.read(messageEditProvider(session)).handoff!;
      expect(handoff.text, '第二轮');
    });

    test('分支点落在一轮中间（带步骤的那句话）：抄到这一轮结束，记录合法', () async {
      turn = (m, t) => m.last['role'] == 'tool'
          ? reply('读完了。')
          : [
              say('我先读一下。'),
              ...use('read_file', {'path': 'index.html'}),
            ];
      await session.sendToAgent('看看首页');
      final mid = '${onDisk('main')[1]['_id']}';
      final r = await session.branches.branch(mid);
      expect(r.wholeTurn, isTrue);
      expect(wireProblems(onDisk(r.convId!)), isEmpty);
      expect(texts(session), ['我:看看首页', 'AI:我先读一下。', '步骤:read_file', 'AI:读完了。']);
    });

    // 2026-11-26 全量测试在机器很忙时撞到的：刚发出去的那句话已经显示、也已经在忙，但还没写进记录的那一小段时间里，
    // 原因说成了“这条消息已经不在记录里了”。这里一变忙就立刻问。
    test('刚发出去、还没写进记录的那句话：说的是“这一轮还没跑完”；真不在的消息照旧说“不在记录里”', () async {
      await session.sendToAgent('第一句');
      final gate = Completer<void>();
      turn = (m, t) async {
        await gate.future;
        return reply('第二句的回复');
      };
      final running = session.sendToAgent('第二句');
      while (!session.agentBusy) {
        await Future<void>.delayed(Duration.zero); // 让出一拍（发送前有真的读写文件，光等微任务等不到）
      }
      expect(session.branches.branchBlocked(idOf('第二句')), kBranchRunningTurn);
      expect((await session.branches.branch(idOf('第二句'))).error, kBranchRunningTurn);
      expect(session.branches.branchBlocked('没有这条'), kMessageGone, reason: '在忙也不能把真不在的消息说成“还没跑完”');
      // 上一轮早就跑完了：不管第二句写没写进记录，都能从它分支。
      expect(session.branches.branchBlocked(idOf('好的。')), isNull);
      gate.complete();
      await running;
      expect(session.branches.branchBlocked(idOf('第二句')), isNull);
    });

    test('Agent 正在回复时：能从已经跑完的轮分支（建好、不切过去）；正在跑的这一轮不行', () async {
      await session.sendToAgent('第一句');
      final gate = Completer<void>();
      turn = (m, t) async {
        await gate.future;
        return reply('第二句的回复');
      };
      final running = session.sendToAgent('第二句');
      await waitFor(() => session.agentBusy);
      expect(session.branches.branchBlocked(idOf('第二句')), kBranchRunningTurn);
      expect((await session.branches.branch(idOf('第二句'))).error, kBranchRunningTurn);
      final r = await session.branches.branch(idOf('好的。'));
      expect((r.error, r.opened), (null, false));
      expect(session.activeConversationId, 'main');
      expect(await session.branches.openConversation(r.convId!), kSwitchWhileBusy);
      expect([for (final m in onDisk(r.convId!)) '${m['content']}'], ['第一句', '好的。']);
      gate.complete();
      await running;
      expect(texts(session), ['我:第一句', 'AI:好的。', '我:第二句', 'AI:第二句的回复'], reason: '正在跑的那一轮不受影响');
      expect(await session.branches.openConversation(r.convId!), isNull);
      expect(texts(session), ['我:第一句', 'AI:好的。']);
    });

    test('子代理对话不复制：分支里的卡片点开的还是原来那段；在分支里删那一轮不会删掉原对话的子代理', () async {
      await env.services.settings.set(SettingKeys.subagentEnabled, true);
      await env.services.settings.set(SettingKeys.subagentMaxDepth, 1);
      turn = (m, t) {
        if (firstUser(m).contains('写首页')) return reply('首页写好了');
        return m.last['role'] == 'tool' ? reply('都做完了') : use('spawn_agent', {'name': '前端', 'task': '写首页 home.html'});
      };
      await session.sendToAgent('帮我做个站');
      final kid = session.subAgents.single.id;
      final count = session.conversations.length;
      final r = await session.branches.branch(idOf('都做完了'));
      expect(session.conversations.length, count + 1, reason: '只多了分支这一段，子代理对话没有复制');
      expect(session.subAgents, isEmpty, reason: '分支自己名下没有子代理');
      expect(session.chat.whereType<ToolItem>().single.childConversationId, kid);
      expect(await session.openRun(kid), isNotNull);
      // 在分支里整轮删：原对话的子代理对话还在
      expect(await session.messageOps.delete(idOf('都做完了'), DeleteScope.turn), isNull);
      expect(session.conversationById(kid), isNotNull);
      expect(f('.lopicode/chat-$kid.json').existsSync(), isTrue);
      // 原对话被删掉以后：分支还在，卡片不再连着
      await session.selectConversation('main');
      await session.deleteConversation();
      expect(session.conversationById(r.convId!), isNotNull);
      expect(await session.branches.openConversation(r.convId!), isNull);
      expect(await session.branches.openOrigin(), contains('已经被删掉了'));
    });

    test('分支点在压缩之后：摘要和归档的原件一起带过去；发给模型的还是摘要', () async {
      await session.sendToAgent('第一句');
      await session.sendToAgent('第二句');
      turn = (m, t) => reply('## 目标\n聊天');
      expect(await session.compactConversation(), '已压缩');
      turn = (m, t) => reply('回：${lastUser(m)}');
      await session.sendToAgent('第三句');
      final r = await session.branches.branch(idOf('回：第三句'));
      final copy = onDisk(r.convId!);
      expect(copy.where((m) => m[kCompactMark] == true), hasLength(1));
      await session.sendToAgent('第四句');
      expect(jsonEncode(log.last.messages), contains(kCompactPrefix.trim()));
      expect(userTexts(log.last.messages).last, '第四句');
    });

    test('收藏、原对话的收藏都不动；分支里同一条消息可以另外收藏', () async {
      await seed();
      final item = session.chat.whereType<AssistantItem>().first;
      await session.messageOps.toggleFavorite(item);
      final r = await session.branches.branch(item.id!);
      final favs = env.services.container.read(favoritesProvider(session)).items;
      expect(favs.single.convId, 'main');
      expect(await session.messageOps.toggleFavorite(session.chat.whereType<AssistantItem>().first), isTrue);
      expect(env.services.container.read(favoritesProvider(session)).items.map((f) => f.convId).toSet(), {'main', r.convId});
    });

    test('旧的目录文件（没有 from）和旧的对话文件：照常打开，可以分支和重试', () async {
      session.dispose();
      f('.lopicode/chats.json').writeAsStringSync(
        jsonEncode([
          {'id': 'main', 'title': '老对话', 'updatedAt': '2026-11-01T10:00:00.000'},
        ]),
      );
      f('.lopicode/chat.json').writeAsStringSync(
        jsonEncode([
          {'role': 'user', 'content': '老问题'},
          {'role': 'assistant', 'content': '老回答'},
        ]),
      );
      session = ProjectSession(env.services, project, headless: true);
      await session.loadChat();
      expect(session.activeConversation.origin, isNull);
      final r = await session.branches.branch(idOf('老回答'));
      expect(r.error, isNull);
      expect(session.activeConversation.origin!.title, '老对话');
      await session.selectConversation('main');
      final start = await session.branches.retry(idOf('老回答'));
      await start.turn;
      expect(texts(session), ['我:老问题', 'AI:好的。']);
    });

    test('分支的对话文件坏了：那段打开是空的、原件另存成 .bad，原对话和出处都不受影响', () async {
      await seed();
      final r = await session.branches.branch(idOf('计划列好了。'));
      await session.selectConversation('main');
      session.dispose();
      await pendingWrites();
      f('.lopicode/chat-${r.convId}.json').writeAsStringSync('{"半截": [1, 2');
      session = ProjectSession(env.services, project, headless: true);
      await session.loadChat();
      await session.selectConversation(r.convId!);
      expect(session.chat, isEmpty);
      expect(Directory('${project.dir}/.lopicode').listSync().where((e) => e.path.contains('chat-${r.convId}.json.bad-')), hasLength(1));
      expect(session.activeConversation.origin!.convId, 'main');
      expect(await session.branches.openOrigin(), isNull);
      expect(texts(session).last, 'AI:回：第二轮');
    });

    test('目录文件里 from 是坏的：那段对话当普通对话打开，别的不受影响', () async {
      await seed();
      final r = await session.branches.branch(idOf('计划列好了。'));
      session.dispose();
      final index = (jsonDecode(f('.lopicode/chats.json').readAsStringSync()) as List).cast<Map<String, dynamic>>();
      index.firstWhere((c) => c['id'] == r.convId)['from'] = {'conv': 42, 'msg': <String>[]};
      f('.lopicode/chats.json').writeAsStringSync(jsonEncode(index));
      session = ProjectSession(env.services, project, headless: true);
      await session.loadChat();
      expect(session.conversations.map((c) => c.id).toSet(), {'main', r.convId});
      expect(session.conversationById(r.convId)!.origin, isNull);
      await session.selectConversation(r.convId!);
      expect(texts(session), ['我:列个计划', '步骤:update_todos', 'AI:计划列好了。']);
      expect(await session.branches.openOrigin(), contains('不是从别处分出来的'));
    });
  });
}
