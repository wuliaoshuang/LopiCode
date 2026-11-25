// 第 11 条的单元测试：ask_user 的参数怎么读、回答怎么整理、拒绝原因怎么拼。界面和会话的测试在 test/ask_multi_test.dart。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/agent/agent_tools.dart';
import 'package:lopicode/session/ask_user.dart';
import 'package:lopicode/session/chat_rows.dart';

import 'ask_multi_test.dart' show kThreeQuestions;

void main() {
  group('读参数', () {
    test('旧写法（question + options）：一个单选问题', () {
      final plan = parseAskArgs({
        'question': ' 用哪个？ ',
        'options': ['甲', '乙', '甲', '', 3],
      });
      expect(plan.dropped, 0);
      expect(plan.parts.single.question, '用哪个？');
      expect(plan.parts.single.options, ['甲', '乙'], reason: '去重、去空、去掉不是文字的');
      expect(plan.parts.single.multiple, isFalse);
    });

    test('新写法（questions）：单选 / 多选 / 没选项；也认只写一句话的', () {
      final plan = parseAskArgs({...kThreeQuestions, 'question': '被忽略的旧写法'});
      expect(plan.parts.map((q) => q.question).toList(), ['主页用什么配色？', '要哪些页面？', '网站叫什么名字？']);
      expect(plan.parts.map((q) => q.multiple).toList(), [false, true, false]);
      expect(plan.parts[2].options, isEmpty);
      expect(
        parseAskArgs({
          'questions': ['直接一句话'],
        }).parts.single.question,
        '直接一句话',
      );
    });

    test('上限：最多 $kAskMaxQuestions 个问题、每个最多 $kAskMaxOptions 个选项；多出来的数得出来', () {
      final plan = parseAskArgs({
        'questions': [
          for (var i = 1; i <= 6; i++)
            {
              'question': '问题 $i',
              'options': [for (var j = 1; j <= 9; j++) '选项 $j'],
            },
        ],
      });
      expect(plan.parts, hasLength(4));
      expect(plan.dropped, 2);
      expect(plan.parts.first.options, hasLength(6));
    });

    test('坏参数不崩：类型不对的条目跳过；questions 是空的就退回旧写法；什么都没有报清楚', () {
      expect(
        parseAskArgs({
          'questions': [
            1,
            null,
            {'question': ''},
            {
              'options': ['a'],
            },
            {'question': '好的', 'options': '不是列表', 'multiple': 'yes'},
          ],
        }).parts.single.options,
        isEmpty,
      );
      expect(parseAskArgs({'questions': <Object>[], 'question': '旧的'}).parts.single.question, '旧的');
      expect(parseAskArgs({'questions': '不是列表', 'question': '旧的'}).parts.single.question, '旧的');
      for (final bad in [
        <String, dynamic>{},
        {'question': '  '},
        {'questions': <Object>[]},
        {'question': 5},
      ]) {
        expect(() => parseAskArgs(bad), throwsA(isA<ToolArgError>()), reason: '$bad');
      }
    });

    test('整理回答：按选项原来的顺序；多选用“；”隔开；自己写的单独标出；没答写明', () {
      final parts = parseAskArgs(kThreeQuestions).parts;
      final text = formatAnswers(parts, [
        (picked: ['深色、科技感'], written: ''),
        (picked: ['作品集', '首页', '不在选项里的'], written: ' 还要一个博客 '),
        (picked: <String>[], written: '霜霜的小站'),
      ]);
      expect(
        text,
        '1. 主页用什么配色？\n   回答：深色、科技感\n'
        '2. 要哪些页面？\n   回答：首页；作品集；用户另外写的：还要一个博客\n'
        '3. 网站叫什么名字？\n   回答：霜霜的小站',
      );
      expect(formatAnswers(parts.take(1).toList(), const []), contains('（用户没有回答）'));
    });

    test('步骤列表里的摘要；工具定义里两种写法都在', () {
      expect(stepLabel('ask_user', jsonEncode(kThreeQuestions)), ('向你提问', '3 个问题：主页用什么配色？'));
      expect(stepLabel('ask_user', '{"question":"用哪个？"}'), ('向你提问', '用哪个？'));
      expect(askSummary(const {}), '');
      final props = ((askUserSpec()['function'] as Map)['parameters'] as Map)['properties'] as Map;
      expect(props.keys, containsAll(['questions', 'question', 'options']));
    });

    test('拒绝原因：没写是空串；空白压成一个空格；超过 $kDenyReasonMaxChars 字截断', () {
      final r = ApprovalRequest(tool: 'run_command', title: '执行命令', detail: 'ls');
      expect(r.denyNote, '');
      r.denyReason = '   ';
      expect(r.denyNote, '');
      r.denyReason = ' 别动\n\n线上库 ';
      expect(r.denyNote, '用户写的原因：别动 线上库');
      r.denyReason = '啊' * 300;
      expect(r.denyNote, '用户写的原因：${'啊' * 200}…');
    });
  });
}
