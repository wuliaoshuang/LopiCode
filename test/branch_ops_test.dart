// 重试 / 编辑 / 分支里纯计算的部分：从哪重新来、会移走什么、截在压缩过的地方怎么办、分支抄哪些消息、抄出来合不合法。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/agent/auto_compact.dart';
import 'package:lopicode/session/branch_ops.dart';
import 'package:lopicode/session/chat_items.dart';
import 'package:lopicode/session/chat_models.dart';
import 'package:lopicode/session/conversation.dart';
import 'package:lopicode/session/message_ops.dart';

import 'message_ops_test.dart' show bot, ids, result, sample, user;

Map<String, dynamic> archived(Map<String, dynamic> m) => {...m, kArchivedMark: true};
Map<String, dynamic> summary(String id) => {'role': 'user', 'content': '$kCompactPrefix摘要', kCompactMark: true, '_id': id};
Map<String, dynamic> ack(String id) => {'role': 'assistant', 'content': '好的，我已经了解之前的进展，可以接着做。', kCompactAckMark: true, '_id': id};

void main() {
  group('从这条消息重新来（重试 / 编辑）', () {
    test('最后一轮：从我的那条消息截断，前面的轮原样留着；数得出移走了什么', () {
      final messages = sample();
      for (final id in ['u2', 'a4']) {
        final plan = planRewind(messages, id)!;
        expect(plan.userId, 'u2');
        expect(plan.text, '谢谢');
        expect(ids(plan.kept), ['u1', 'a1', 'tool:c1', 'tool:c2', 'a2', 'tool:c3', 'a3']);
        expect(wireProblems(plan.kept), isEmpty);
        expect((plan.laterTurns, plan.replies, plan.steps, plan.changedFiles), (0, 1, 0, false));
        expect(plan.goneIds, {'u2', 'a4'});
        expect(plan.worthKeeping, isTrue);
        expect(plan.anchorId, 'a3', reason: '旧版本跳回原对话时滚到留下的最后一段回复');
      }
      expect(messages, sample(), reason: '只是算，不改原记录');
    });

    test('更早的一轮：后面的轮一起移走，步骤、改过文件都数进去；派子代理的调用 id 交出来', () {
      for (final id in ['u1', 'a3']) {
        final plan = planRewind(sample(), id)!;
        expect(plan.kept, isEmpty);
        expect(plan.anchorId, isNull);
        expect((plan.laterTurns, plan.replies, plan.steps, plan.changedFiles), (1, 4, 3, true));
        expect(plan.goneCallIds, {'c1', 'c2', 'c3'});
        expect(plan.goneIds, {'u1', 'a1', 'a2', 'a3', 'u2', 'a4'});
      }
    });

    test('带图片的消息：图片附件原样交出来（重试时还在）', () {
      final messages = [
        {
          ...user('u1', '看图'),
          '_images': [
            {'path': '.lopicode/attachments/a.png', 'mime': 'image/png'},
          ],
        },
        bot('a1', '看到了。'),
      ];
      final plan = planRewind(messages, 'a1')!;
      expect(plan.images, [
        {'path': '.lopicode/attachments/a.png', 'mime': 'image/png'},
      ]);
    });

    test('只有我的一条消息、没人回（出错 / 被停止）：没有东西值得另存', () {
      final plan = planRewind([...sample(), user('u3', '再来')], 'u3')!;
      expect(plan.worthKeeping, isFalse);
      expect(plan.kept.length, sample().length);
    });

    test('被打断的一轮（停在工具调用上、有思考内容）：截断后前面的记录合法', () {
      final messages = [
        ...sample(),
        user('u3', '改一下'),
        bot('a5', null, calls: ['c9'], extra: {'_reasoning': '想'}),
        result('c9', kUnknownResultNote),
      ];
      final plan = planRewind(messages, 'u3')!;
      expect(wireProblems(plan.kept), isEmpty);
      expect((plan.replies, plan.steps, plan.worthKeeping), (0, 1, true));
    });

    test('中途插的话把一轮切成两轮：重试后一轮，前一轮的步骤留着，记录合法', () {
      final messages = [
        user('u1', '做 A'),
        bot('a1', null, calls: ['c1']),
        result('c1'),
        user('u2', '顺便做 B'),
        bot('a2', '都做了。'),
      ];
      final plan = planRewind(messages, 'a2')!;
      expect(plan.text, '顺便做 B');
      expect(ids(plan.kept), ['u1', 'a1', 'tool:c1']);
      expect(wireProblems(plan.kept), isEmpty);
    });

    test('这一轮中途自动压缩过（我的那条消息已归档）：截断后摘要没了，前面的内容变回“发给模型的”', () {
      final messages = [
        archived(user('u1', '第一件')),
        archived(bot('a1', '做完了。')),
        archived(user('u2', '第二件')),
        archived(bot('a2', null, calls: ['c1'])),
        archived(result('c1')),
        summary('s1'),
        bot('a3', '第二件也做完了。'),
      ];
      final plan = planRewind(messages, 'a3')!;
      expect(plan.text, '第二件');
      expect(ids(plan.kept), ['u1', 'a1']);
      expect(plan.kept.any(isArchived), isFalse, reason: '一份摘要都没留下：全部变回来，不然模型什么都看不到');
      expect(wireProblems(plan.kept), isEmpty);
      expect(messages.first[kArchivedMark], isTrue, reason: '原记录不改');
    });

    test('压缩过两次：只把留下的最后一份摘要和它后面的变回来，更早的仍是归档', () {
      final messages = [
        archived(user('u1', '很早')),
        archived(bot('a1', '好。')),
        archived(summary('s1')),
        archived(ack('k1')),
        archived(user('u2', '中间')),
        archived(bot('a2', '好的。')),
        archived(user('u3', '后来')),
        archived(bot('a3', '行。')),
        summary('s2'),
        ack('k2'),
        user('u4', '现在'),
        bot('a4', '嗯。'),
      ];
      final plan = planRewind(messages, 'u3')!;
      expect(ids(plan.kept), ['u1', 'a1', 's1', 'k1', 'u2', 'a2']);
      expect([for (final m in plan.kept) isArchived(m)], [true, true, false, false, false, false]);
      expect(wireProblems(plan.kept), isEmpty);
      expect(plan.laterTurns, 1);
      // 截在最新的摘要之后：什么都不用变
      final late = planRewind(messages, 'a4')!;
      expect([for (final m in late.kept) isArchived(m)], [true, true, true, true, true, true, true, true, false, false]);
    });

    test('不认识的 id、压缩摘要、承接语、工具结果、摘要后面没有我的消息的回复：返回 null', () {
      final messages = [summary('s1'), bot('a0', '接着做完了。'), ...sample()];
      expect(planRewind(messages, '没有'), isNull);
      expect(planRewind(messages, 's1'), isNull);
      expect(planRewind(messages, 'a0'), isNull, reason: '它前面没有我的消息，没法“用同一条消息再发”');
      expect(planRewind([summary('s1'), ack('k1')], 'k1'), isNull);
    });
  });

  group('分支抄哪些消息', () {
    test('从 Agent 的最后一段回复分支：抄到它为止（含它），深拷贝，id 原样带过去', () {
      final messages = sample();
      final plan = planBranch(messages, 'a3')!;
      expect(ids(plan.messages), ['u1', 'a1', 'tool:c1', 'tool:c2', 'a2', 'tool:c3', 'a3']);
      expect(plan.draftText, isNull);
      expect((plan.wholeTurn, plan.turns), (false, 1));
      expect(wireProblems(plan.messages), isEmpty);
      // 两边不共用对象：改分支不影响原对话
      plan.messages.first['content'] = '改了';
      (plan.messages[1]['tool_calls'] as List).clear();
      expect(messages, sample());
      // 这一轮的用量脚注、改过的文件清单跟着消息走
      expect(plan.messages.last['_usage'], isNotNull);
      expect(plan.messages.last['_files'], isNotNull);
    });

    test('从我的消息分支：抄到这条之前，这条的文字和图片交给输入框', () {
      final messages = [
        ...sample(),
        {
          ...user('u3', '再看这张'),
          '_images': [
            {'path': 'a.png', 'mime': 'image/png'},
          ],
        },
        bot('a5', '好。'),
      ];
      final plan = planBranch(messages, 'u3')!;
      expect(ids(plan.messages).last, 'a4');
      expect(plan.draftText, '再看这张');
      expect(plan.draftImages, [
        {'path': 'a.png', 'mime': 'image/png'},
      ]);
      expect(plan.turns, 2);
      // 第一条消息上分支：新对话是空的
      expect(planBranch(messages, 'u1')!.messages, isEmpty);
    });

    test('分支点落在一轮中间（带工具调用的那句话）：只抄到它会缺结果，所以抄到这一轮结束', () {
      final plan = planBranch(sample(), 'a1')!;
      expect(plan.wholeTurn, isTrue);
      expect(ids(plan.messages), ['u1', 'a1', 'tool:c1', 'tool:c2', 'a2', 'tool:c3', 'a3']);
      expect(wireProblems(plan.messages), isEmpty);
    });

    test('一轮里有两段正式回复（中间夹着步骤）：从前一段分支，抄到它为止就合法', () {
      final messages = [
        user('u1', '做'),
        bot('a1', '先说结论。'),
        user('u2', '继续'),
        bot('a2', null, calls: ['c1']),
        result('c1'),
        bot('a3', '做完。'),
      ];
      final plan = planBranch(messages, 'a1')!;
      expect(ids(plan.messages), ['u1', 'a1']);
      expect(plan.wholeTurn, isFalse);
    });

    test('分支点在压缩之后：摘要、归档的原件一起带过去，归档标记不变', () {
      final messages = [archived(user('u1', '早')), archived(bot('a1', '好。')), summary('s1'), ack('k1'), user('u2', '现在'), bot('a2', '嗯。')];
      final plan = planBranch(messages, 'a2')!;
      expect(ids(plan.messages), ['u1', 'a1', 's1', 'k1', 'u2', 'a2']);
      expect([for (final m in plan.messages) isArchived(m)], [true, true, false, false, false, false]);
      expect(wireProblems(plan.messages), isEmpty);
    });

    test('分支点在压缩之前（已归档的消息上）：摘要不带，抄过去的内容变回“发给模型的”', () {
      final messages = [archived(user('u1', '早')), archived(bot('a1', '好。')), archived(user('u2', '再早')), archived(bot('a2', '行。')), summary('s1'), ack('k1'), user('u3', '现在'), bot('a3', '嗯。')];
      final plan = planBranch(messages, 'a1')!;
      expect(ids(plan.messages), ['u1', 'a1']);
      expect(plan.messages.any(isArchived), isFalse);
      expect(messages.first[kArchivedMark], isTrue);
    });

    test('不认识的 id、摘要、工具结果：返回 null', () {
      expect(planBranch(sample(), '没有'), isNull);
      expect(planBranch([summary('s1'), ack('k1')], 's1'), isNull);
    });

    test('各种组合逐条试：重试和分支算出来的记录都合法', () {
      final messages = [
        ...sample(),
        user('u3', '改一下'),
        bot('a5', '我改。', calls: ['c4'], extra: {'_reasoning': '想'}),
        result('c4'),
        user('u4', '插一句'),
        bot('a6', null, calls: ['c5', 'c6']),
        result('c5'),
        result('c6'),
        bot('a7', '改好了。'),
      ];
      for (final m in messages) {
        final id = m['_id'];
        if (id is! String) continue;
        final rewind = planRewind(messages, id);
        expect(rewind, isNotNull, reason: id);
        expect(wireProblems(rewind!.kept), isEmpty, reason: '重试 $id');
        final branch = planBranch(messages, id);
        expect(branch, isNotNull, reason: id);
        expect(wireProblems(branch!.messages), isEmpty, reason: '分支 $id');
        expect(jsonEncode(branch.messages), isNot(contains('没有拿到结果')), reason: '分支 $id：不靠“补一条说明”凑合法');
      }
    });
  });

  group('子代理对话的连线', () {
    Map<String, dynamic> spawn(String id, String callId) => {
      'role': 'assistant',
      'content': null,
      '_id': id,
      'tool_calls': [
        {
          'id': callId,
          'type': 'function',
          'function': {'name': 'spawn_agent', 'arguments': '{}'},
        },
      ],
    };
    List<String?> kidsOf(List<Map<String, dynamic>> messages, List<String> own, {bool Function(String)? exists}) => [
      for (final i in chatItemsFromMessages(messages, childConversationIds: own, hostPathOf: (r) => r, conversationExists: exists))
        if (i is ToolItem) i.childConversationId,
    ];

    test('抄出去的调用记着原来那段子对话；新分支里自己派的从第一个算起', () {
      final copy = cloneMessages([user('u1', '派'), spawn('a1', 'c1'), result('c1'), bot('a2', '派完了。')]);
      stampChildLinks(copy, {'c1': 'kid1', '别的': 'x'});
      expect(copy[1][kChildLinksKey], {'c1': 'kid1'});
      expect(kidsOf(copy, const []), ['kid1']);
      // 分支里又派了一个：它是这段对话自己的第一个
      final more = [...copy, user('u2', '再派'), spawn('a3', 'c2'), result('c2')];
      expect(kidsOf(more, ['mine1']), ['kid1', 'mine1']);
      // 原来那段子对话被删了：卡片不再连着
      expect(kidsOf(more, ['mine1'], exists: (id) => id != 'kid1'), [null, 'mine1']);
      // 旧记录（没有连线）：照旧按第几个对
      expect(kidsOf([user('u1', '派'), spawn('a1', 'c1'), result('c1')], ['k']), ['k']);
      // 连线的形状不对：当没有
      expect(
        kidsOf(
          [
            user('u1', '派'),
            {...spawn('a1', 'c1'), kChildLinksKey: 'bad'},
            result('c1'),
          ],
          ['k'],
        ),
        ['k'],
      );
    });
  });

  group('对话的出处（目录文件里的 from）', () {
    test('存了再读：原样回来；旧目录（没有 from）是 null', () {
      final conv = Conversation(
        'abc',
        '标题',
        DateTime(2026, 11, 25),
        origin: const BranchOrigin(convId: 'main', messageId: 'm1', title: '原对话', old: true),
      );
      final back = Conversation.fromJson(jsonDecode(jsonEncode(conv.toJson())))!;
      expect((back.origin!.convId, back.origin!.messageId, back.origin!.title, back.origin!.old, back.origin!.tag), ('main', 'm1', '原对话', true, '旧版本'));
      expect(Conversation.fromJson({'id': 'abc', 'title': 't'})!.origin, isNull);
      expect(conv.copyWith(title: '新').origin, isNotNull, reason: '改名不丢出处');
      expect(conv.movedUnder('p').parentId, 'p');
      expect(const BranchOrigin(convId: 'main', title: 't').tag, '分支');
    });

    test('from 的形状不对：当成普通对话，不抛异常', () {
      for (final bad in <Object?>[
        'x',
        3,
        <String>[],
        <String, dynamic>{},
        {'conv': 5},
        {'conv': '../../etc'},
        {'conv': ''},
      ]) {
        final conv = Conversation.fromJson({'id': 'abc', 'title': 't', 'from': bad});
        expect(conv, isNotNull, reason: '$bad');
        expect(conv!.origin, isNull, reason: '$bad');
      }
      final loose = Conversation.fromJson({
        'id': 'abc',
        'from': {'conv': 'main', 'msg': 7, 'title': null, 'old': 'yes'},
      })!;
      expect((loose.origin!.messageId, loose.origin!.title, loose.origin!.old), (null, '', false));
    });
  });
}
