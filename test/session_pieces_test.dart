// Agent 引擎拆出来的几块纯计算：从消息记录重建条目、导出成 Markdown、子代理的名额排队、标题与截断。
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/session/chat_export.dart';
import 'package:lopicode/session/chat_items.dart';
import 'package:lopicode/session/chat_models.dart';
import 'package:lopicode/session/session_core.dart';
import 'package:lopicode/session/subagents.dart';

void main() {
  group('从消息记录重建条目', () {
    List<ChatItem> build(List<Map<String, dynamic>> messages, {List<String> kids = const []}) => chatItemsFromMessages(messages, childConversationIds: kids, hostPathOf: (rel) => '/host/$rel');

    test('用户消息带附件、助手文字、工具调用和结果一一对上', () {
      final items = build([
        {
          'role': 'user',
          'content': '看图',
          '_images': [
            {'path': 'a.png', 'mime': 'image/png'},
            '不是表的忽略',
          ],
        },
        {
          'role': 'assistant',
          'content': '好的',
          'tool_calls': [
            {
              'id': 'c1',
              'function': {'name': 'read_file', 'arguments': '{"path":"a"}'},
            },
            {
              'id': 'c2',
              'function': {'name': 'run_command', 'arguments': '{}'},
            },
            {
              'id': 'c3',
              'function': {'name': 'write_file', 'arguments': '{}'},
            },
          ],
        },
        {'role': 'tool', 'tool_call_id': 'c1', 'content': '内容'},
        {'role': 'tool', 'tool_call_id': 'c2', 'content': '用户拒绝了这次操作'},
        {'role': 'tool', 'tool_call_id': 'c3', 'content': '错误：写不了'},
        {'role': 'tool', 'tool_call_id': '不存在', 'content': '没人认领'},
      ]);
      expect(items, hasLength(5));
      final user = items[0] as UserItem;
      expect(user.text, '看图');
      expect(user.images, ['/host/a.png']);
      expect((items[1] as AssistantItem).text, '好的');
      final read = items[2] as ToolItem;
      expect((read.name, read.result, read.ok, read.denied), ('read_file', '内容', true, false));
      final cmd = items[3] as ToolItem;
      expect((cmd.ok, cmd.denied), (false, true), reason: '“用户拒绝”开头的结果算被拒绝');
      expect((items[4] as ToolItem).ok, isFalse, reason: '“错误”开头的结果算失败');
    });

    test('没记到结果的工具调用写明“没有记录到结果”；spawn_agent 按顺序对上子对话', () {
      final items = build(
        [
          {
            'role': 'assistant',
            'content': '',
            'tool_calls': [
              {
                'id': 's1',
                'function': {'name': 'spawn_agent', 'arguments': '{}'},
              },
              {
                'id': 'r1',
                'function': {'name': 'read_file', 'arguments': '{}'},
              },
              {
                'id': 's2',
                'function': {'name': 'spawn_agent', 'arguments': '{}'},
              },
              {
                'id': 's3',
                'function': {'name': 'spawn_agent', 'arguments': '{}'},
              },
            ],
          },
        ],
        kids: ['kidA', 'kidB'],
      );
      final tools = items.cast<ToolItem>();
      expect([for (final t in tools) t.childConversationId], ['kidA', null, 'kidB', null], reason: '子对话不够时多出来的那次不乱指');
      expect(tools.first.result, '（没有记录到结果）');
    });

    test('坏数据不崩：字段类型不对、缺字段', () {
      final items = build([
        {'role': 'user'},
        {'role': 'user', 'content': 1, '_images': '不是列表'},
        {'role': 'assistant', 'content': 3, 'tool_calls': '不是列表'},
        {
          'role': 'assistant',
          'tool_calls': [
            '不是表',
            {'id': 'x'},
          ],
        },
        {'role': '没见过的角色'},
      ]);
      expect(items.whereType<UserItem>().map((u) => u.text), ['', '1']);
      expect(items.whereType<ToolItem>().single.name, '');
    });

    test('消息上挂着的用量变成一条用量条目', () {
      final items = build([
        {'role': 'user', 'content': '你好'},
        {
          'role': 'assistant',
          'content': '在',
          '_usage': {'ms': 1200, 'steps': <Object>[]},
        },
      ]);
      expect(items.whereType<UsageItem>(), hasLength(1));
      expect(items.last, isA<UsageItem>());
    });
  });

  group('导出成 Markdown', () {
    test('标题、我 / Agent、附件、工具调用和结果都在；太长的截断', () {
      final md = conversationMarkdown('我的对话', [
        {
          'role': 'user',
          'content': '帮我看看',
          '_images': [
            {'path': 'a.png'},
          ],
        },
        {
          'role': 'assistant',
          'content': '行',
          'tool_calls': [
            {
              'function': {'name': 'read_file', 'arguments': 'x' * 400},
            },
            '坏的',
          ],
        },
        {'role': 'tool', 'content': '第一行\n第二行'},
        {'role': 'assistant', 'content': ''},
      ]);
      expect(md, startsWith('# 我的对话\n\n'));
      expect(md, contains('## 我\n\n帮我看看'));
      expect(md, contains('（附件：a.png）'));
      expect(md, contains('## Agent\n\n行'));
      expect(md, contains('> 调用工具 `read_file`：`${'x' * 300}…`'));
      expect(md, contains('> 工具结果：第一行 第二行'));
      expect('## Agent'.allMatches(md), hasLength(1), reason: '空的助手消息不出标题');
    });
  });

  group('小工具', () {
    test('标题取第一行、最多 18 个字；截断加省略号', () {
      expect(titleFromText('  第一行\n第二行'), '第一行');
      expect(titleFromText('一' * 30), '${'一' * 18}…');
      expect(clipText('abc', 5), 'abc');
      expect(clipText('abcdef', 3), 'abc…');
    });

    test('名额排队：满了就等，先来先得；放一个进一个', () async {
      final slots = RunSlots(2);
      await slots.acquire();
      await slots.acquire();
      final order = <int>[];
      unawaited(slots.acquire().then((_) => order.add(1)));
      unawaited(slots.acquire().then((_) => order.add(2)));
      await Future<void>.delayed(Duration.zero);
      expect(order, isEmpty, reason: '两个名额都占着，后来的要等');
      slots.release();
      await Future<void>.delayed(Duration.zero);
      expect(order, [1]);
      slots.release();
      await Future<void>.delayed(Duration.zero);
      expect(order, [1, 2]);
      // 都放掉以后又能直接拿到
      slots.release();
      slots.release();
      await slots.acquire().timeout(const Duration(seconds: 1));
    });
  });
}
