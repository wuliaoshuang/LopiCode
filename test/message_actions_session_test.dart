// 消息操作在真实会话里（不带界面）：稳定 id 落盘与旧文件兼容、删除后存盘 / 重开一致 / 下一次请求合法、
// 忙的时候不能删、子代理对话连带删、收藏（存取、标“原消息已删除”、坏文件）、导出（脱敏、路径）。
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/agent/chat_client.dart';
import 'package:lopicode/agent/message_ids.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/stores.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/session/message_actions.dart';
import 'package:lopicode/session/message_ops.dart';
import 'package:lopicode/state/workspace_favorites.dart';

import 'agent_test.dart' show RecordingRunner;
import 'session_system_test.dart' show RoutingClient, Turn, hasToolResult, lastUser, reply, use, waitFor;
import 'support/harness.dart';

void main() {
  late TestEnv env;
  late Project project;
  late ProjectSession session;
  late List<({List<Map<String, dynamic>> messages, List<String> tools})> log;
  Turn turn = (_, _) => reply('好的。');

  setUp(() async {
    turn = (_, _) => reply('好的。');
    log = [];
    env = await TestEnv.create(chatClient: () => RoutingClient((m, t) => turn(m, t), log));
    project = await env.services.projects.create('测试工作区', ProjectTemplate.web);
    session = ProjectSession(env.services, project, headless: true);
    session.commandRunnerFactory = RecordingRunner.new;
    await session.loadChat();
  });
  tearDown(() async {
    session.dispose();
    await env.dispose();
  });

  File f(String rel) => File('${project.dir}/$rel');
  List<Map<String, dynamic>> onDisk([String name = 'chat.json']) => [for (final m in jsonDecode(f('.lopicode/$name').readAsStringSync()) as List) (m as Map).cast<String, dynamic>()];
  List<String> texts(ProjectSession s) => [
    for (final i in s.chat)
      if (i is UserItem) '我:${i.text}' else if (i is AssistantItem) 'AI:${i.text}' else if (i is ToolItem) '步骤:${i.name}',
  ];
  String idOf(String text) => switch (session.chat.firstWhere((i) => (i is UserItem && i.text == text) || (i is AssistantItem && i.text == text))) {
    UserItem(:final id) => id!,
    AssistantItem(:final id) => id!,
    _ => fail('不是消息'),
  };
  FavoritesNotifier favorites() => env.services.container.read(favoritesProvider(session).notifier);

  Future<ProjectSession> reopen() async {
    final again = ProjectSession(env.services, project, headless: true);
    addTearDown(again.dispose);
    await again.loadChat();
    return again;
  }

  /// 一轮带一步工具调用（读文件），然后一问一答。
  Future<void> twoTurns() async {
    turn = (m, t) => lastUser(m) == '看看首页'
        ? (hasToolResult(m)
              ? reply('首页看完了。')
              : [
                  say('我先读一下。'),
                  ...use('read_file', {'path': 'index.html'}),
                ])
        : reply('不客气。');
    await session.sendToAgent('看看首页');
    await session.sendToAgent('谢谢');
  }

  group('稳定 id', () {
    test('新消息生成时就带 id：界面条目、内存记录、盘上三处一致；工具结果不带；发给模型的请求里没有 _id', () async {
      await twoTurns();
      final disk = onDisk();
      expect([for (final m in disk) m['role']], ['user', 'assistant', 'tool', 'assistant', 'user', 'assistant']);
      expect(disk[2].containsKey(kMessageIdKey), isFalse);
      final diskIds = [
        for (final m in disk)
          if (m['role'] != 'tool') messageIdOf(m),
      ];
      expect(diskIds.toSet(), hasLength(5));
      expect(diskIds.contains(null), isFalse);
      final itemIds = [
        for (final i in session.chat)
          if (i is UserItem) i.id else if (i is AssistantItem) i.id,
      ];
      expect(itemIds, diskIds, reason: '生成时给界面条目的 id 就是落盘的那个');
      // 真正发请求的那一层（chat_client.dart）发之前会去掉所有下划线开头的键，_id 也在其中
      expect(jsonEncode(stripInternal(log.last.messages)), isNot(contains('"_id"')));
      expect(jsonEncode(withReasoningContent(log.last.messages, fillMissing: true)), isNot(contains('"_id"')));
    });

    test('旧对话文件（没有 _id）：照常打开，读进来就补上并马上写回；再开一次 id 不变', () async {
      session.dispose();
      f('.lopicode/chat.json').writeAsStringSync(
        jsonEncode([
          {'role': 'user', 'content': '老问题'},
          {
            'role': 'assistant',
            'content': '我看看',
            'tool_calls': [
              {
                'id': 'c1',
                'type': 'function',
                'function': {'name': 'read_file', 'arguments': '{"path":"index.html"}'},
              },
            ],
          },
          {'role': 'tool', 'tool_call_id': 'c1', 'content': '<html>'},
          {'role': 'assistant', 'content': '老回答'},
        ]),
      );
      session = await reopen();
      expect(texts(session), ['我:老问题', 'AI:我看看', '步骤:read_file', 'AI:老回答']);
      final disk = onDisk();
      final first = [for (final m in disk) messageIdOf(m)];
      expect(first, [isNotNull, isNotNull, isNull, isNotNull]);
      expect(idOf('老回答'), first[3]);
      final again = await reopen();
      expect([for (final m in onDisk()) messageIdOf(m)], first);
      expect((again.chat.last as AssistantItem).id, first[3]);
    });
  });

  group('删除', () {
    test('删一整轮：盘上立刻是删完的样子，重开一致；下一次请求里没有被删的内容，而且合法', () async {
      await twoTurns();
      final id = idOf('首页看完了。');
      expect(session.messageOps.lastReplyIds, {id, idOf('不客气。')});
      expect(await session.messageOps.delete(id, DeleteScope.turn), isNull);
      expect(texts(session), ['我:谢谢', 'AI:不客气。']);
      expect([for (final m in onDisk()) m['content']], ['谢谢', '不客气。']);
      expect(texts(await reopen()), ['我:谢谢', 'AI:不客气。']);

      await session.sendToAgent('再来');
      final sent = log.last.messages.where((m) => m['role'] != 'system').toList();
      expect(jsonEncode(sent), isNot(contains('看看首页')));
      expect(wireProblems(sent), isEmpty);
    });

    test('只删一段带工具调用的回复：文字没了，步骤留着；下一次请求里调用和结果还成对', () async {
      await twoTurns();
      expect(await session.messageOps.delete(idOf('我先读一下。'), DeleteScope.message), isNull);
      expect(texts(session), ['我:看看首页', '步骤:read_file', 'AI:首页看完了。', '我:谢谢', 'AI:不客气。']);
      expect(texts(await reopen()), texts(session));
      await session.sendToAgent('再来');
      final sent = log.last.messages.where((m) => m['role'] != 'system').toList();
      expect(jsonEncode(sent), isNot(contains('我先读一下')));
      expect(wireProblems(sent), isEmpty);
      expect(sent.where((m) => m['role'] == 'tool'), hasLength(1));
    });

    test('只删提问：不给删，说明原因，什么都没变', () async {
      await twoTurns();
      final before = f('.lopicode/chat.json').readAsStringSync();
      expect(await session.messageOps.delete(idOf('看看首页'), DeleteScope.message), contains('只能整轮删'));
      expect(f('.lopicode/chat.json').readAsStringSync(), before);
      expect(texts(session), hasLength(6));
    });

    test('不回滚文件改动，不改对话累计用量', () async {
      turn = (m, t) => hasToolResult(m) ? reply('写好了。') : use('write_file', {'path': 'note.txt', 'content': '内容'});
      await session.sendToAgent('写个文件');
      final used = session.activeConversation.toJson();
      expect(await session.messageOps.delete(idOf('写好了。'), DeleteScope.turn), isNull);
      expect(session.chat, isEmpty);
      expect(f('note.txt').readAsStringSync(), '内容', reason: '文件改动不撤销');
      final after = session.activeConversation.toJson();
      for (final k in used.keys.where((k) => k.toLowerCase().contains('token') || k.toLowerCase().contains('cost') || k.toLowerCase().contains('usage'))) {
        if (k.toLowerCase().contains('lastinput')) continue;
        expect(after[k], used[k], reason: '累计用量 $k 不变');
      }
    });

    test('Agent 正在回复时一律不删（复制、收藏、导出照常）；停下以后能删', () async {
      await session.sendToAgent('第一句');
      final gate = Completer<void>();
      turn = (m, t) async {
        await gate.future;
        return reply('第二句的回复');
      };
      final running = session.sendToAgent('第二句');
      await waitFor(() => session.agentBusy, what: 'Agent 开始跑');
      final id = idOf('好的。');
      final before = texts(session);
      expect(await session.messageOps.delete(id, DeleteScope.turn), kDeleteWhileBusy);
      expect(await session.messageOps.delete(idOf('第二句'), DeleteScope.turn), kDeleteWhileBusy);
      expect(texts(session), before);
      expect(session.messageOps.markdownOf(id, wholeTurn: true), contains('第一句'));
      expect(await session.messageOps.toggleFavorite(session.chat[1]), isTrue);
      gate.complete();
      await running;
      expect(await session.messageOps.delete(id, DeleteScope.turn), isNull);
      expect(texts(session), ['我:第二句', 'AI:第二句的回复']);
    });

    test('整轮删带走这一轮派出的子代理对话（连文件）；只抹文字不带走', () async {
      await env.services.settings.set(SettingKeys.subagentEnabled, true);
      await env.services.settings.set(SettingKeys.subagentMaxDepth, 1);
      turn = (m, t) {
        final task = '${m.firstWhere((x) => x['role'] == 'user')['content']}';
        if (task.contains('写首页')) return reply('首页写好了');
        return hasToolResult(m)
            ? reply('都做完了')
            : [
                say('我派个人。'),
                ...use('spawn_agent', {'name': '前端', 'task': '写首页 home.html'}),
              ];
      };
      await session.sendToAgent('帮我做个站');
      final kid = session.subAgents.single;
      expect(f('.lopicode/chat-${kid.id}.json').existsSync(), isTrue);

      expect(await session.messageOps.delete(idOf('我派个人。'), DeleteScope.message), isNull);
      expect(session.subAgents, hasLength(1), reason: '只抹文字：步骤还在，子对话留着');
      expect(session.chat.whereType<ToolItem>().single.childConversationId, kid.id);

      final p = session.messageOps.previewDelete(idOf('都做完了'))!;
      expect(session.messageOps.childConversationsOf(p.turn), [kid.id]);
      expect(await session.messageOps.delete(idOf('都做完了'), DeleteScope.turn), isNull);
      expect(session.subAgents, isEmpty);
      expect(f('.lopicode/chat-${kid.id}.json').existsSync(), isFalse);
      expect((await reopen()).conversations, hasLength(1));
    });

    test('消息已经不在了：返回原因，不抛异常', () async {
      await session.sendToAgent('你好');
      expect(await session.messageOps.delete('没有这个', DeleteScope.turn), contains('不在记录里'));
      expect(session.messageOps.previewDelete('没有这个'), isNull);
      expect(session.messageOps.messageById('没有这个'), isNull);
    });
  });

  group('分享', () {
    test('Markdown 里像密钥的内容被抹掉；存成文件在工作区 exports/ 里，同一秒存两次不互相盖', () async {
      turn = (m, t) => reply('用这个：api_key=abcd1234efgh5678 和 sk-abcdefgh12345678');
      await session.sendToAgent('我的密钥是 password=hunter2222');
      final id = idOf('用这个：api_key=abcd1234efgh5678 和 sk-abcdefgh12345678');
      final one = session.messageOps.markdownOf(id, wholeTurn: false)!;
      expect(one, isNot(contains('abcd1234efgh5678')));
      expect(one, isNot(contains('sk-abcdefgh12345678')));
      expect(one.split('\n').skip(1).join('\n'), isNot(contains('我的密钥是')), reason: '这一条：不带提问（第一行是对话名，对话名取自第一句提问）');
      final whole = session.messageOps.markdownOf(id, wholeTurn: true)!;
      expect(whole, contains('我的密钥是'));
      expect(whole, isNot(contains('hunter2222')));

      final now = DateTime(2026, 11, 25, 20, 5, 9);
      final a = await session.messageOps.saveMarkdown(id, wholeTurn: true, now: now);
      final b = await session.messageOps.saveMarkdown(id, wholeTurn: false, now: now);
      expect(a, startsWith('exports/消息-'));
      expect(a, endsWith('.md'));
      expect(b, isNot(a));
      expect(f(a!).readAsStringSync(), whole);
      expect(f(b!).readAsStringSync(), one);
      expect(await session.messageOps.saveMarkdown('没有', wholeTurn: false), isNull);
    });

    test('整段对话导出（原有功能）现在也过脱敏', () async {
      turn = (m, t) => reply('token=zzzzyyyyxxxx1111');
      await session.sendToAgent('导出试试');
      final rel = await session.exportConversation();
      expect(f(rel!).readAsStringSync(), isNot(contains('zzzzyyyyxxxx1111')));
    });
  });

  group('收藏', () {
    test('收藏 / 取消：存进 .lopicode/favorites.json，重开还在，新的排前面，长文字截到 4000 字', () async {
      turn = (m, t) => reply('长' * 5000);
      await session.sendToAgent('你好');
      final mine = session.chat[0], hers = session.chat[1];
      expect(await session.messageOps.toggleFavorite(mine), isTrue);
      expect(await session.messageOps.toggleFavorite(hers), isTrue);
      final state = favorites().current;
      expect([for (final x in state.items) x.role], ['assistant', 'user']);
      expect(state.items.first.text.length, 4001);
      expect(state.items.last.convId, session.activeConversationId);
      expect(state.contains(session.activeConversationId, (mine as UserItem).id!), isTrue);
      final saved = jsonDecode(f('.lopicode/favorites.json').readAsStringSync()) as Map;
      expect(saved['version'], 1);
      expect((saved['items'] as List), hasLength(2));

      final again = await reopen();
      final n = env.services.container.read(favoritesProvider(again).notifier);
      await n.load();
      expect(n.current.items, hasLength(2));

      expect(await session.messageOps.toggleFavorite(mine), isFalse);
      expect(favorites().current.items.single.role, 'assistant');
    });

    test('原消息被删：收藏留着文字快照，标“原消息已删除”；对话整个被删也算找不到', () async {
      await session.sendToAgent('第一轮');
      await session.messageOps.toggleFavorite(session.chat[1]);
      await session.newConversation();
      await session.sendToAgent('第二段对话');
      await session.messageOps.toggleFavorite(session.chat[0]);
      final second = session.activeConversationId;

      expect(await session.messageOps.delete(idOf('第二段对话'), DeleteScope.turn), isNull);
      var items = favorites().current.items;
      expect(items.first.gone, isTrue);
      expect(items.first.text, '第二段对话');
      expect(items.last.gone, isFalse);
      expect(session.messageOps.favoriteMissing(items.first), isTrue);
      expect(session.messageOps.favoriteMissing(items.last), isFalse);

      await session.selectConversation('main');
      await session.deleteConversation();
      items = favorites().current.items;
      expect(items, hasLength(2), reason: '对话删了，收藏不跟着丢');
      expect(session.messageOps.favoriteMissing(items.last), isTrue);
      expect(session.activeConversationId, isNot('main'));
      expect(second, isNotEmpty);
    });

    test('收藏文件坏了：不崩、当成没有收藏，坏文件留一份备份；之后还能收藏', () async {
      f('.lopicode/favorites.json').writeAsStringSync('{"version":1,"items":[{"conv":');
      await favorites().load();
      expect(favorites().current.items, isEmpty);
      expect(Directory('${project.dir}/.lopicode').listSync().where((e) => e.path.contains('favorites.json.bad-')), hasLength(1));
      await session.sendToAgent('你好');
      expect(await session.messageOps.toggleFavorite(session.chat[0]), isTrue);
      expect((jsonDecode(f('.lopicode/favorites.json').readAsStringSync()) as Map)['items'], hasLength(1));
    });

    test('“跳回原消息”的请求：记下、清掉', () {
      final jump = env.services.container.read(chatJumpProvider(session).notifier);
      jump.request('m1');
      expect(env.services.container.read(chatJumpProvider(session)), 'm1');
      jump.clear();
      expect(env.services.container.read(chatJumpProvider(session)), isNull);
    });
  });
}
