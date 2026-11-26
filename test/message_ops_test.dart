// 消息操作里纯计算的部分：稳定 id、一轮的范围、删一条 / 删一轮之后记录是否合法、分享取哪几条。
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/agent/auto_compact.dart';
import 'package:lopicode/agent/message_ids.dart';
import 'package:lopicode/session/chat_items.dart';
import 'package:lopicode/session/chat_models.dart';
import 'package:lopicode/session/message_ops.dart';
import 'package:lopicode/session/reply_edit.dart';

Map<String, dynamic> user(String id, String text) => {'role': 'user', 'content': text, '_id': id};
Map<String, dynamic> bot(String id, String? text, {List<String> calls = const [], Map<String, dynamic> extra = const {}}) => {
  'role': 'assistant',
  'content': text,
  '_id': id,
  if (calls.isNotEmpty)
    'tool_calls': [
      for (final c in calls)
        {
          'id': c,
          'type': 'function',
          'function': {'name': 'read_file', 'arguments': '{"path":"a.txt"}'},
        },
    ],
  ...extra,
};
Map<String, dynamic> result(String callId, [String text = 'ok']) => {'role': 'tool', 'tool_call_id': callId, 'content': text};

List<String> ids(List<Map<String, dynamic>> messages) => [for (final m in messages) '${m['_id'] ?? 'tool:${m['tool_call_id']}'}'];

/// 两轮：第一轮“回复 → 两步 → 带字的一步 → 最后一段”，第二轮一问一答。
List<Map<String, dynamic>> sample() => [
  user('u1', '帮我看看'),
  bot('a1', '我先看两个文件。', calls: ['c1', 'c2'], extra: {'_reasoning': '想一想', '_reasoningMs': 12}),
  result('c1'),
  result('c2'),
  bot(
    'a2',
    '再看一个。',
    calls: ['c3'],
    extra: {
      '_raw': {
        'content': [
          {'type': 'thinking', 'thinking': '嗯', 'signature': 's'},
          {'type': 'text', 'text': '再看一个。'},
          {'type': 'tool_use', 'id': 'c3', 'name': 'read_file', 'input': <String, dynamic>{}},
        ],
      },
    },
  ),
  result('c3'),
  bot(
    'a3',
    '看完了，没问题。',
    extra: {
      '_usage': {'input': 10, 'output': 5},
      '_files': ['a.txt'],
    },
  ),
  user('u2', '谢谢'),
  bot('a4', '不客气。'),
];

void main() {
  group('消息的稳定 id', () {
    test('新 id 不重复，形状固定（m 开头）', () {
      final many = {for (var i = 0; i < 2000; i++) newMessageId()};
      expect(many, hasLength(2000));
      expect(many.every((id) => RegExp(r'^m[0-9a-z]{8,}$').hasMatch(id)), isTrue);
    });

    test('旧记录（没有 id）：非工具消息补上，工具结果不带；已有的不动；再跑一次什么都不改', () {
      final messages = [
        {'role': 'user', 'content': '旧的'},
        {
          'role': 'assistant',
          'content': null,
          'tool_calls': [
            {'id': 'c1'},
          ],
        },
        result('c1'),
        bot('keep', '已有'),
      ];
      expect(ensureMessageIds(messages), 2);
      expect(messageIdOf(messages[0]), isNotNull);
      expect(messageIdOf(messages[1]), isNotNull);
      expect(messages[2].containsKey(kMessageIdKey), isFalse);
      expect(messageIdOf(messages[3]), 'keep');
      final first = ids(messages);
      expect(ensureMessageIds(messages), 0);
      expect(ids(messages), first);
    });

    test('重复的 id、类型不对的 id：第一条留着，后面的换新', () {
      final messages = [
        user('same', '一'),
        bot('same', '二'),
        {'role': 'user', 'content': '三', '_id': 42},
        {'role': 'user', 'content': '四', '_id': ''},
      ];
      expect(ensureMessageIds(messages), 3);
      expect(messageIdOf(messages[0]), 'same');
      expect({for (final m in messages) messageIdOf(m)}, hasLength(4));
      expect(indexOfMessage(messages, 'same'), 0);
      expect(indexOfMessage(messages, '没有'), -1);
    });

    test('界面条目带着消息的 id（我的消息和 Agent 的回复）', () {
      final items = chatItemsFromMessages(sample(), childConversationIds: const [], hostPathOf: (rel) => rel);
      expect([for (final i in items.whereType<UserItem>()) i.id], ['u1', 'u2']);
      expect([for (final i in items.whereType<AssistantItem>()) i.id], ['a1', 'a2', 'a3', 'a4']);
    });
  });

  group('一轮的范围', () {
    test('从我的一条消息到下一条之前；每轮最后一段回复', () {
      final m = sample();
      expect(turnRangeAt(m, 0), (start: 0, end: 7));
      expect(turnRangeAt(m, 4), (start: 0, end: 7));
      expect(turnRangeAt(m, 8), (start: 7, end: 9));
      expect(lastReplyIdsOf(m), {'a3', 'a4'});
    });

    test('一轮停在带工具调用的那句话上（被打断）：那句现在是正文，这一轮没有正式回复，操作栏就挂在它下面', () {
      final m = [
        user('u1', '看看'),
        bot('a1', '好，先说结论。'),
        user('u2', '再看'),
        bot('a2', '我读一下。', calls: ['c1']),
        result('c1'),
      ];
      expect(lastReplyIdsOf(m), {'a1', 'a2'});
      expect(turnRepliesOf(m).keys.toSet(), {'a1', 'a2'});
      // 有正式回复时还是挂在最后一段正式回复下面
      expect(lastReplyIdsOf([...m, bot('a3', '读完了。')]), {'a1', 'a3'});
    });

    test('压缩摘要、应用通知不算“我的消息”，不会把一轮切开', () {
      final m = [
        {'role': 'user', 'content': '摘要', kCompactMark: true, '_id': 's'},
        {'role': 'assistant', 'content': '明白', kCompactAckMark: true, '_id': 'k'},
        user('u1', '继续'),
        bot('a1', '好'),
      ];
      expect(isRealUserMessage(m[0]), isFalse);
      expect(turnRangeAt(m, 3), (start: 2, end: 4));
      expect(lastReplyIdsOf(m), {'a1'}, reason: '承接语不是回复');
    });
  });

  group('合法性检查', () {
    test('正常记录没有问题', () => expect(wireProblems(sample()), isEmpty));

    test('认得出：调用没结果、结果没调用、开头是 assistant、两条 assistant 挨着', () {
      expect(
        wireProblems([
          user('u', 'x'),
          bot('a', null, calls: ['c1']),
        ]),
        contains(contains('没有结果')),
      );
      expect(wireProblems([user('u', 'x'), result('c9')]), contains(contains('前面没有调用它的消息')));
      expect(wireProblems([bot('a', '嗨')]), contains('head'));
      expect(wireProblems([user('u', 'x'), bot('a', '一'), bot('b', '二')]), contains('pair:2'));
    });
  });

  group('删除', () {
    /// 每一种删法删完都必须合法，而且不改原来的列表。
    void checkAll(List<Map<String, dynamic>> messages) {
      final before = ids(messages);
      for (final m in [...messages]) {
        final id = messageIdOf(m);
        if (id == null) continue;
        final p = previewDelete(messages, id);
        if (p == null) continue;
        for (final r in [p.single, p.turn]) {
          if (r == null) continue;
          expect(wireProblems(r.messages), isEmpty, reason: '删 $id 之后：${ids(r.messages)}');
        }
        expect(p.single == null, p.singleBlocked != null, reason: '不能单删时要有原因');
      }
      expect(ids(messages), before, reason: '预览不许改原记录');
    }

    test('各种带工具调用的组合：两种删法删完都合法', () {
      checkAll(sample());
      // 只有步骤没有回复的一轮（被停掉）
      checkAll([
        user('u1', 'x'),
        bot('a1', null, calls: ['c1']),
        result('c1'),
        user('u2', 'y'),
        bot('a2', '好'),
      ]);
      // 中途插话
      checkAll([
        user('u1', 'x'),
        bot('a1', '先做', calls: ['c1']),
        result('c1'),
        user('u2', '顺便'),
        bot('a2', null, calls: ['c2']),
        result('c2'),
        bot('a3', '完'),
      ]);
      // 并行多个调用、多组
      checkAll([
        user('u1', 'x'),
        bot('a1', '甲', calls: ['c1', 'c2', 'c3']),
        result('c1'),
        result('c2'),
        result('c3'),
        bot('a2', '乙', calls: ['c4']),
        result('c4'),
        bot('a3', '丙'),
        user('u2', 'z'),
      ]);
      // 开头是压缩摘要
      checkAll([
        {'role': 'user', 'content': '摘要', kCompactMark: true, '_id': 's'},
        {'role': 'assistant', 'content': '明白', kCompactAckMark: true, '_id': 'k'},
        user('u1', '继续'),
        bot('a1', '读', calls: ['c1']),
        result('c1'),
        bot('a2', '好'),
      ]);
      // 只有一条提问（还没回复）
      checkAll([user('u1', 'x')]);
    });

    test('只删一段带工具调用的回复：文字抹掉，调用、结果、思考留着；Anthropic 原始块里的文字块也拿掉', () {
      final p = previewDelete(sample(), 'a2')!;
      final after = p.single!.messages;
      expect(ids(after), ids(sample()), reason: '条数不变');
      final a2 = after[4];
      expect(a2['content'], isNull);
      expect((a2['tool_calls'] as List), hasLength(1));
      expect([for (final b in (a2['_raw'] as Map)['content'] as List) (b as Map)['type']], ['thinking', 'tool_use']);
      expect(p.single!.goneIds, {'a2'});
      expect(p.single!.goneCallIds, isEmpty);

      final a1 = previewDelete(sample(), 'a1')!.single!.messages[1];
      expect(a1['content'], isNull);
      expect(a1['_reasoning'], '想一想', reason: 'DeepSeek 的思考内容跟着工具调用留下（接口要求回传）');
    });

    test('只删最后一段回复：整条拿掉，这一轮的用量和改动清单挪到前一条上', () {
      final p = previewDelete(sample(), 'a3')!;
      final after = p.single!.messages;
      expect(ids(after), ['u1', 'a1', 'tool:c1', 'tool:c2', 'a2', 'tool:c3', 'u2', 'a4']);
      expect(after[5]['_usage'], {'input': 10, 'output': 5});
      expect(after[5]['_files'], ['a.txt']);
      expect(sample()[5].containsKey('_usage'), isFalse);
    });

    test('整条拿掉的回复：思考内容、原始内容块跟着一起没了', () {
      final m = [
        user('u1', 'x'),
        bot(
          'a1',
          '答',
          extra: {
            '_reasoning': '想',
            '_raw': {'content': <Object>[]},
          },
        ),
        user('u2', 'y'),
      ];
      final after = previewDelete(m, 'a1')!.single!.messages;
      expect(ids(after), ['u1', 'u2']);
      expect(after.any((x) => x.containsKey('_reasoning') || x.containsKey('_raw')), isFalse);
    });

    test('只删提问而后面跟着回复：不给单删（会让回复顶在最前面 / 两段回复挨着），整轮删可以', () {
      final first = previewDelete(sample(), 'u1')!;
      expect(first.single, isNull);
      expect(first.singleBlocked, contains('只能整轮删'));
      final second = previewDelete(sample(), 'u2')!;
      expect(second.single, isNull);
      expect(ids(second.turn.messages), ['u1', 'a1', 'tool:c1', 'tool:c2', 'a2', 'tool:c3', 'a3']);
    });

    test('还没人回的提问、中途插的话：可以单删', () {
      expect(ids(previewDelete([user('u1', 'x'), bot('a1', '好'), user('u2', 'y')], 'u2')!.single!.messages), ['u1', 'a1']);
      final steer = [
        user('u1', 'x'),
        bot('a1', null, calls: ['c1']),
        result('c1'),
        user('u2', '顺便'),
        bot('a2', '完'),
      ];
      expect(ids(previewDelete(steer, 'u2')!.single!.messages), ['u1', 'a1', 'tool:c1', 'a2']);
    });

    test('删一整轮：我的话、步骤、结果、回复一起走，别的轮不动；数得出带走了什么', () {
      final p = previewDelete(sample(), 'a2')!;
      expect(ids(p.turn.messages), ['u2', 'a4']);
      expect(p.turn.goneIds, {'u1', 'a1', 'a2', 'a3'});
      expect(p.turn.goneCallIds, {'c1', 'c2', 'c3'});
      expect((p.turnMine, p.turnReplies, p.turnSteps), (1, 3, 3));
      expect(p.of(DeleteScope.turn), same(p.turn));
      expect(p.of(DeleteScope.message), same(p.single));
    });

    test('插话把一轮切成两轮：删后一轮不碰前一轮', () {
      final steer = [
        user('u1', 'x'),
        bot('a1', '先做', calls: ['c1']),
        result('c1'),
        user('u2', '顺便'),
        bot('a2', '完'),
      ];
      expect(ids(previewDelete(steer, 'a2')!.turn.messages), ['u1', 'a1', 'tool:c1']);
    });

    test('压缩摘要和承接语：自己不能删，整轮删也不会带走', () {
      final m = [
        {'role': 'user', 'content': '摘要', kCompactMark: true, '_id': 's'},
        {'role': 'assistant', 'content': '明白', kCompactAckMark: true, '_id': 'k'},
        user('u1', '继续'),
        bot('a1', '好'),
      ];
      expect(previewDelete(m, 's'), isNull);
      expect(previewDelete(m, 'k'), isNull);
      expect(ids(previewDelete(m, 'a1')!.turn.messages), ['s', 'k']);
    });

    test('已经归档（压缩前的原文还留着显示）的消息：能删，标明已归档', () {
      final m = [
        {...user('u0', '老的'), kArchivedMark: true},
        {...bot('a0', '老回复'), kArchivedMark: true},
        {'role': 'user', 'content': '摘要', kCompactMark: true, '_id': 's'},
        {'role': 'assistant', 'content': '明白', kCompactAckMark: true, '_id': 'k'},
        user('u1', '继续'),
        bot('a1', '好'),
      ];
      final p = previewDelete(m, 'a0')!;
      expect(p.archived, isTrue);
      expect(ids(p.turn.messages), ['s', 'k', 'u1', 'a1']);
      expect(wireProblems(p.turn.messages), isEmpty);
    });

    test('不认识的 id、工具结果：返回 null', () {
      expect(previewDelete(sample(), '没有'), isNull);
      expect(
        previewDelete([
          user('u', 'x'),
          {'role': 'tool', 'tool_call_id': 'c', 'content': 'x', '_id': 't'},
        ], 't'),
        isNull,
      );
    });
  });

  group('分享取哪几条', () {
    test('这一条：只有它自己，不带工具调用；这一轮：提问 + 步骤 + 回复', () {
      final one = messagesForShare(sample(), 'a2', wholeTurn: false)!;
      expect(one, hasLength(1));
      expect(one.single.containsKey('tool_calls'), isFalse);
      expect(one.single['content'], '再看一个。');
      expect(sample()[4].containsKey('tool_calls'), isTrue);
      expect(ids(messagesForShare(sample(), 'a2', wholeTurn: true)!), ['u1', 'a1', 'tool:c1', 'tool:c2', 'a2', 'tool:c3', 'a3']);
      expect(messagesForShare(sample(), '没有', wholeTurn: true), isNull);
    });
  });
}
