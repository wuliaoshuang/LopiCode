// 编辑 Agent 的回复：纯计算（改完的记录长什么样、哪些不能改、旧存档、Anthropic 原始内容块）
// 和真实会话里（不带界面）：存盘、重开一致、发给模型的是改后的文字、忙的时候不能改、收藏跟着变、
// 分支各改各的、分享导出、用量不变、恢复原文、盘写不了什么都不改。
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/agent/auto_compact.dart';
import 'package:lopicode/agent/chat_client.dart';
import 'package:lopicode/agent/protocols.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/session/branch_ops.dart';
import 'package:lopicode/session/chat_items.dart';
import 'package:lopicode/session/message_actions.dart';
import 'package:lopicode/session/message_ops.dart';
import 'package:lopicode/session/reply_edit.dart';
import 'package:lopicode/state/workspace_favorites.dart';

import 'agent_test.dart' show RecordingRunner;
import 'session_system_test.dart' show RoutingClient, Turn, hasToolResult, lastUser, reply, use, waitFor;
import 'support/harness.dart';

List<ChatItem> _items(List<Map<String, dynamic>> m) => chatItemsFromMessages(m, childConversationIds: const [], hostPathOf: (p) => p);

void main() {
  group('纯计算', () {
    List<Map<String, dynamic>> sample() => [
      {'role': 'user', 'content': '看看首页', '_id': 'u1'},
      {
        'role': 'assistant',
        'content': '我先读一下。',
        '_id': 'a1',
        'tool_calls': [
          {
            'id': 'c1',
            'type': 'function',
            'function': {'name': 'read_file', 'arguments': '{"path":"index.html"}'},
          },
        ],
      },
      {'role': 'tool', 'tool_call_id': 'c1', 'content': '<html>'},
      {'role': 'assistant', 'content': '首页看完了。', '_id': 'a2', '_reasoning': '想了想', '_usage': <String, dynamic>{}},
    ];

    test('改一段回复：只换这一条的文字，标上已编辑、留着原话；别的消息还是原来那个对象', () {
      final m = sample();
      final plan = planReplyEdit(m, 'a2', '首页看完了，有两处要改。')!;
      expect(plan.error, isNull);
      expect(plan.changed, isTrue);
      expect(plan.edited, isTrue);
      final next = plan.messages[3];
      expect(next['content'], '首页看完了，有两处要改。');
      expect(next[kEditedMark], isTrue);
      expect(next[kOriginalTextKey], '首页看完了。');
      expect(next['_reasoning'], '想了想', reason: '思考内容不动');
      expect(next.containsKey('_usage'), isTrue, reason: '这一轮的用量脚注不动');
      for (var i = 0; i < 3; i++) {
        expect(identical(plan.messages[i], m[i]), isTrue);
      }
      expect(m[3]['content'], '首页看完了。', reason: '原来的记录没被就地改');
      expect(wireProblems(plan.messages), isEmpty);
    });

    test('改第二次：原话还是模型最初那句；改回和原话一样：两个记号都拿掉', () {
      final once = planReplyEdit(sample(), 'a2', '第一次改')!.messages;
      final twice = planReplyEdit(once, 'a2', '第二次改')!;
      expect(twice.messages[3][kOriginalTextKey], '首页看完了。');
      expect(infoOfReply(twice.messages, 'a2')!.original, '首页看完了。');
      final back = planReplyEdit(twice.messages, 'a2', '首页看完了。')!;
      expect(back.changed, isTrue);
      expect(back.edited, isFalse);
      expect(back.messages[3].containsKey(kEditedMark), isFalse);
      expect(back.messages[3].containsKey(kOriginalTextKey), isFalse);
      expect(infoOfReply(back.messages, 'a2')!.original, isNull);
    });

    test('空内容（只有空白）不许保存；和现在一样：什么都不用存', () {
      final m = sample();
      for (final blank in ['', '   ', '\n\n \t']) {
        expect(planReplyEdit(m, 'a2', blank)!.error, kReplyEditEmpty);
      }
      final same = planReplyEdit(m, 'a2', '首页看完了。')!;
      expect(same.changed, isFalse);
      expect(same.error, isNull);
      expect(identical(same.messages, m), isTrue);
    });

    test('带工具调用的那句话也能改：工具调用和结果原样留着，记录仍然合法', () {
      final plan = planReplyEdit(sample(), 'a1', '我先看一眼文件。')!;
      expect(plan.messages[1]['content'], '我先看一眼文件。');
      expect((plan.messages[1]['tool_calls'] as List).single['id'], 'c1');
      expect(wireProblems(plan.messages), isEmpty);
    });

    test('不能改的：我的消息、工具结果、没有文字的回复、压缩摘要和承接语、找不到的 id', () {
      final m = [
        {'role': 'user', 'content': '摘要……', kCompactMark: true, '_id': 's1'},
        {'role': 'assistant', 'content': '好的，我已经了解之前的进展，可以接着做。', kCompactAckMark: true, '_id': 's2'},
        ...sample(),
        {
          'role': 'assistant',
          'content': null,
          '_id': 'a3',
          'tool_calls': [
            {
              'id': 'c2',
              'type': 'function',
              'function': {'name': 'list_files', 'arguments': '{}'},
            },
          ],
        },
        {'role': 'tool', 'tool_call_id': 'c2', 'content': 'x'},
      ];
      for (final id in ['u1', 's1', 's2', 'a3', 'c1', '没有这条']) {
        expect(planReplyEdit(m, id, '新的'), isNull, reason: id);
        expect(infoOfReply(m, id), isNull, reason: id);
      }
    });

    test('Anthropic 的原始内容块：文字块换成新的、多出来的文字块拿掉，思考块和工具调用块不动；发出去的就是改后的', () {
      final m = [
        {'role': 'user', 'content': '看看首页', '_id': 'u1'},
        {
          'role': 'assistant',
          'content': '我先读一下。再说一句。',
          '_id': 'a1',
          'tool_calls': [
            {
              'id': 'c1',
              'type': 'function',
              'function': {'name': 'read_file', 'arguments': '{"path":"index.html"}'},
            },
          ],
          '_raw': {
            'protocol': 'anthropic',
            'content': [
              {'type': 'thinking', 'thinking': '想', 'signature': 'sig'},
              {'type': 'text', 'text': '我先读一下。'},
              {'type': 'text', 'text': '再说一句。'},
              {
                'type': 'tool_use',
                'id': 'c1',
                'name': 'read_file',
                'input': {'path': 'index.html'},
              },
            ],
          },
        },
        {'role': 'tool', 'tool_call_id': 'c1', 'content': '<html>'},
      ];
      // 和从盘上读回来的一样（全是 JSON 解出来的 Map）
      final loaded = cloneMessages(m);
      final plan = planReplyEdit(loaded, 'a1', '改过的话')!;
      final blocks = (plan.messages[1]['_raw'] as Map)['content'] as List;
      expect([for (final b in blocks) (b as Map)['type']], ['thinking', 'text', 'tool_use']);
      expect((blocks[0] as Map)['signature'], 'sig');
      expect((blocks[1] as Map)['text'], '改过的话');
      final wire = anthropicMessages(plan.messages).messages;
      final sent = jsonEncode(wire);
      expect(sent, contains('改过的话'));
      expect(sent, isNot(contains('我先读一下')));
      expect(sent, isNot(contains('再说一句')));
      expect(sent, contains('tool_use'));
      // 存一遍再读回来还是一样
      final again = anthropicMessages(cloneMessages(plan.messages)).messages;
      expect(jsonEncode(again), sent);
    });

    test('旧存档兼容：没有这两个键的照常读、不带“已编辑”；键的类型不对当没改过，不抛异常', () {
      final old = sample();
      expect(_items(old).whereType<AssistantItem>().every((i) => !i.edited), isTrue);
      final odd = sample();
      odd[3][kEditedMark] = 'yes';
      odd[3][kOriginalTextKey] = 42;
      expect(_items(odd).whereType<AssistantItem>().last.edited, isFalse);
      expect(infoOfReply(odd, 'a2')!.original, isNull);
      // 只有原话、没有记号（坏数据）：也当没改过
      final half = sample();
      half[3][kOriginalTextKey] = '别的';
      expect(infoOfReply(half, 'a2')!.original, isNull);
      // 改过的：条目带上记号
      final edited = planReplyEdit(sample(), 'a2', '改了')!.messages;
      final item = _items(edited).whereType<AssistantItem>().last;
      expect(item.edited, isTrue);
      expect(item.text, '改了');
    });

    test('已经压缩归档的回复：能改，归档记号留着（不会重新发给模型），编辑页知道它归档了', () {
      final m = [
        for (final x in sample()) {...x, kArchivedMark: true},
        {'role': 'user', 'content': '摘要：看过首页了', kCompactMark: true, '_id': 's1'},
        {'role': 'assistant', 'content': '好的，我已经了解之前的进展，可以接着做。', kCompactAckMark: true, '_id': 's2'},
      ];
      expect(infoOfReply(m, 'a2')!.archived, isTrue);
      final plan = planReplyEdit(m, 'a2', '改了归档的')!;
      expect(isArchived(plan.messages[3]), isTrue);
      expect(plan.messages[4]['content'], '摘要：看过首页了', reason: '摘要不跟着变');
    });

    test('一轮里有几段回复：从哪一段点“重试”都是重试这一整轮（回到我的那条消息）', () {
      final m = [
        {'role': 'user', 'content': '跑一下', '_id': 'u1'},
        {'role': 'assistant', 'content': '第一段', '_id': 'a1'},
        {'role': 'user', 'content': '后台命令结束了', '_notice': '后台命令 #1 结束了', '_id': 'n1'},
        {'role': 'assistant', 'content': '第二段', '_id': 'a2'},
        {'role': 'user', 'content': '谢谢', '_id': 'u2'},
        {'role': 'assistant', 'content': '不客气', '_id': 'a3'},
      ];
      final first = planRewind(m, 'a1')!, second = planRewind(m, 'a2')!, mine = planRewind(m, 'u1')!;
      for (final p in [first, second, mine]) {
        expect(p.userId, 'u1');
        expect(p.text, '跑一下');
        expect(p.kept, isEmpty);
        expect(p.laterTurns, 1);
        expect(p.replies, 3);
      }
    });
  });

  group('真实会话', () {
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
    AssistantItem itemOf(String text) => session.chat.whereType<AssistantItem>().firstWhere((i) => i.text == text);
    String idOf(String text) => itemOf(text).id!;
    FavoritesNotifier favorites() => env.services.container.read(favoritesProvider(session).notifier);

    Future<void> twoTurns() async {
      turn = (m, t) => lastUser(m) == '看看首页'
          ? (hasToolResult(m)
                ? reply('首页看完了。')
                : [
                    say('我先读一下。'),
                    ...use('read_file', {'path': 'index.html'}),
                  ])
          : reply('收到：${lastUser(m)}');
      await session.sendToAgent('看看首页');
      await session.sendToAgent('谢谢');
    }

    test('保存：界面条目、内存、盘上三处都是新文字并带“已编辑”；重开一致；别的条目（步骤、用量脚注）都还在', () async {
      await twoTurns();
      final id = idOf('首页看完了。');
      final before = session.chat.length;
      final usage = session.activeConversation.usage.requests;
      final done = await session.messageOps.editReply(id, '首页看完了，标题要改。');
      expect(done.error, isNull);
      expect(done.changed, isTrue);
      expect(done.edited, isTrue);
      final item = itemOf('首页看完了，标题要改。');
      expect(item.id, id, reason: 'id 不变');
      expect(item.edited, isTrue);
      expect(session.chat, hasLength(before), reason: '只换了这一条，没有重建、没有丢别的条目');
      expect(session.messageOps.messageById(id)!['content'], '首页看完了，标题要改。');
      final disk = onDisk().firstWhere((m) => m['_id'] == id);
      expect(disk['content'], '首页看完了，标题要改。');
      expect(disk[kEditedMark], isTrue);
      expect(disk[kOriginalTextKey], '首页看完了。');
      expect(disk.containsKey('_usage'), isTrue);
      expect(session.activeConversation.usage.requests, usage, reason: '累计用量不变');
      expect(session.activeConversation.lastInput, isNull, reason: '上下文占用改回估算');

      final again = ProjectSession(env.services, project, headless: true);
      addTearDown(again.dispose);
      await again.loadChat();
      final reopened = again.chat.whereType<AssistantItem>().firstWhere((i) => i.id == id);
      expect(reopened.text, '首页看完了，标题要改。');
      expect(reopened.edited, isTrue);
      expect(again.chat.whereType<ToolItem>(), hasLength(1));
    });

    test('之后发给模型的历史用的是改后的文字，而且不带我们自己的记号', () async {
      await twoTurns();
      await session.messageOps.editReply(idOf('首页看完了。'), '首页看完了，标题要改。');
      log.clear();
      await session.sendToAgent('那就改吧');
      // log 记的是交给接口那一层之前的样子（还带着 `_` 开头的内部键）；真正发出去的三种写法都要查
      final history = log.single.messages;
      for (final sent in [jsonEncode(stripInternal(history)), jsonEncode(withReasoningContent(history, fillMissing: true)), jsonEncode(anthropicMessages(history).messages)]) {
        expect(sent, contains('首页看完了，标题要改。'));
        expect(sent, isNot(contains('首页看完了。"')), reason: '原话不能跟着发出去');
        expect(sent, isNot(contains(kEditedMark)));
        expect(sent, isNot(contains(kOriginalTextKey)));
      }
      expect(log.single.messages.where((m) => m['role'] == 'assistant' && m['content'] == '首页看完了，标题要改。'), hasLength(1));
    });

    test('没有触发重新生成：不发请求、不多出对话、消息条数不变', () async {
      await twoTurns();
      final calls = log.length, convs = session.conversations.length, count = onDisk().length;
      await session.messageOps.editReply(idOf('收到：谢谢'), '不客气。');
      expect(log, hasLength(calls));
      expect(session.conversations, hasLength(convs));
      expect(onDisk(), hasLength(count));
      expect(session.agentBusy, isFalse);
    });

    test('Agent 正在回复：不能改，说明原因，什么都没变；停下后能改', () async {
      await session.sendToAgent('第一句');
      final id = idOf('好的。');
      final gate = Completer<void>();
      turn = (m, t) async {
        await gate.future;
        return reply('第二句的回复');
      };
      unawaited(session.sendToAgent('第二句'));
      await waitFor(() => session.agentBusy, what: 'Agent 开始跑');
      final done = await session.messageOps.editReply(id, '改不了');
      expect(done.error, kEditReplyWhileBusy);
      expect(done.changed, isFalse);
      expect(itemOf('好的。').edited, isFalse);
      gate.complete();
      await waitFor(() => !session.agentBusy, what: '这一轮结束');
      expect((await session.messageOps.editReply(id, '现在能改了')).error, isNull);
      expect(onDisk().firstWhere((m) => m['_id'] == id)['content'], '现在能改了');
      expect(onDisk().last['content'], '第二句的回复', reason: '没把后来的消息弄丢');
    });

    test('空内容不保存；没改动不写盘；这条不在了说明原因', () async {
      await session.sendToAgent('你好');
      final id = idOf('好的。');
      expect((await session.messageOps.editReply(id, '  \n ')).error, kReplyEditEmpty);
      final stamp = f('.lopicode/chat.json').lastModifiedSync();
      final same = await session.messageOps.editReply(id, '好的。');
      expect(same.error, isNull);
      expect(same.changed, isFalse);
      expect(f('.lopicode/chat.json').lastModifiedSync(), stamp);
      expect(itemOf('好的。').edited, isFalse);
      expect((await session.messageOps.editReply('没有这条', '新的')).error, contains('不在记录里'));
      final mine = session.chat.whereType<UserItem>().single.id!;
      expect((await session.messageOps.editReply(mine, '新的')).error, isNotNull, reason: '我的消息不走这条路');
      expect(session.chat.whereType<UserItem>().single.text, '你好');
    });

    test('恢复原文：改回模型的原话，记号拿掉，盘上也没有了', () async {
      await session.sendToAgent('你好');
      final id = idOf('好的。');
      await session.messageOps.editReply(id, '改过');
      expect(session.messageOps.replyEditInfo(id)!.original, '好的。');
      final back = await session.messageOps.editReply(id, '好的。');
      expect(back.changed, isTrue);
      expect(back.edited, isFalse);
      expect(itemOf('好的。').edited, isFalse);
      final disk = onDisk().firstWhere((m) => m['_id'] == id);
      expect(disk.containsKey(kEditedMark), isFalse);
      expect(disk.containsKey(kOriginalTextKey), isFalse);
    });

    test('收藏：这条收藏着，留的文字跟着换成新的；存到盘上', () async {
      await session.sendToAgent('你好');
      final id = idOf('好的。');
      await session.messageOps.toggleFavorite(itemOf('好的。'));
      await session.messageOps.editReply(id, '改过的回复');
      expect(favorites().current.items.single.text, '改过的回复');
      expect(favorites().current.items.single.gone, isFalse);
      expect(f('.lopicode/favorites.json').readAsStringSync(), contains('改过的回复'));
    });

    test('分支：改之前分出去的那段不跟着变；改之后分出去的带着“已编辑”；两边各改各的，收藏也各是各的', () async {
      await session.sendToAgent('你好');
      final id = idOf('好的。');
      await session.messageOps.toggleFavorite(itemOf('好的。'));
      final early = await session.branches.branch(id);
      expect(session.activeConversationId, early.convId);
      await session.messageOps.toggleFavorite(itemOf('好的。'));
      await session.selectConversation('main');
      await session.messageOps.editReply(id, '主对话里改的');
      expect(onDisk('chat-${early.convId}.json').firstWhere((m) => m['_id'] == id)['content'], '好的。', reason: '早先分出去的那段不动');
      final kept = favorites().current.items.firstWhere((x) => x.convId == early.convId);
      expect(kept.text, '好的。', reason: '分支里那条收藏不动');
      expect(favorites().current.items.firstWhere((x) => x.convId == 'main').text, '主对话里改的');

      final late = await session.branches.branch(id);
      final copied = onDisk('chat-${late.convId}.json').firstWhere((m) => m['_id'] == id);
      expect(copied['content'], '主对话里改的');
      expect(copied[kEditedMark], isTrue);
      expect(itemOf('主对话里改的').edited, isTrue);
      await session.messageOps.editReply(id, '分支里又改的');
      expect(onDisk().firstWhere((m) => m['_id'] == id)['content'], '主对话里改的', reason: '在分支里改，原对话不动');
      expect(onDisk('chat-${late.convId}.json').firstWhere((m) => m['_id'] == id)[kOriginalTextKey], '好的。', reason: '原话一路带着');
    });

    test('分享 / 导出：用的是改后的文字', () async {
      await session.sendToAgent('你好');
      final id = idOf('好的。');
      await session.messageOps.editReply(id, '改过的回复');
      expect(session.messageOps.markdownOf(id, wholeTurn: false), allOf(contains('改过的回复'), isNot(contains('好的。'))));
      expect(session.messageOps.markdownOf(id, wholeTurn: true), allOf(contains('你好'), contains('改过的回复')));
      final rel = await session.exportConversation();
      expect(f(rel!).readAsStringSync(), contains('改过的回复'));
    });

    test('改过以后重试这一轮：改过的那版进“旧版本”，带着“已编辑”', () async {
      await session.sendToAgent('你好');
      final id = idOf('好的。');
      await session.messageOps.editReply(id, '改过的回复');
      final start = await session.branches.retry(id);
      await start.turn;
      expect(start.error, isNull);
      final old = onDisk('chat-${start.oldVersionId}.json').firstWhere((m) => m['_id'] == id);
      expect(old['content'], '改过的回复');
      expect(old[kEditedMark], isTrue);
      expect(session.chat.whereType<AssistantItem>().single.edited, isFalse, reason: '重新回答的是新的一段');
    });

    test('盘写不了：什么都不改，说明原因', () async {
      await session.sendToAgent('你好');
      final id = idOf('好的。');
      // 把对话文件换成一个非空目录：原子写最后的“改名”这一步过不去
      final file = f('.lopicode/chat.json')..deleteSync();
      Directory(file.path).createSync();
      File('${file.path}/占位').writeAsStringSync('x');
      final done = await session.messageOps.editReply(id, '存不进去的');
      expect(done.error, contains('存储写不了'));
      expect(done.changed, isFalse);
      expect(itemOf('好的。').edited, isFalse);
      expect(session.messageOps.messageById(id)!['content'], '好的。');
      Directory(file.path).deleteSync(recursive: true);
    });
  });

  test('turnRepliesOf：每一轮 Agent 说的话（工具调用之间的说明也算），键是最后一段正式回复；压缩的承接语、应用通知不算', () {
    final m = <Map<String, dynamic>>[
      {'role': 'user', 'content': '摘要', '_compact': true},
      {'role': 'assistant', 'content': '好的。', '_compactAck': true, '_id': 'ack'},
      {'role': 'user', 'content': '问一', '_id': 'u1'},
      {
        'role': 'assistant',
        'content': '我先看看。',
        '_id': 'a0',
        'tool_calls': [
          {'id': 'c1'},
        ],
      },
      {'role': 'tool', 'tool_call_id': 'c1', 'content': 'x'},
      {'role': 'assistant', 'content': '第一段', '_id': 'a1', '_edited': true, '_orig': '原话'},
      {'role': 'user', 'content': '通知', '_notice': '后台命令结束了'},
      {'role': 'assistant', 'content': '第二段', '_id': 'a2'},
      {'role': 'user', 'content': '问二', '_id': 'u2'},
      {'role': 'assistant', 'content': '只有一段', '_id': 'a3'},
      {'role': 'user', 'content': '问三', '_id': 'u3'},
    ];
    final turns = turnRepliesOf(m);
    expect(turns.keys.toSet(), lastReplyIdsOf(m));
    expect(turns.keys, ['a2', 'a3']);
    expect([for (final p in turns['a2']!) (p.id, p.text, p.edited, p.note)], [('a0', '我先看看。', false, true), ('a1', '第一段', true, false), ('a2', '第二段', false, false)]);
    expect(joinReplyParts(turns['a2']!), '我先看看。\n\n第一段\n\n第二段');
    expect([for (final p in turns['a3']!) p.id], ['a3']);
  });
}
