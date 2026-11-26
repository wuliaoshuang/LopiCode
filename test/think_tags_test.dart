// 正文里的 `<think>…</think>`：从正文剥出来进思考区（含流式半截标签），存盘、重开对话、不带回给接口。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/agent/agent_runner.dart';
import 'package:lopicode/agent/agent_tools.dart';
import 'package:lopicode/agent/chat_client.dart';
import 'package:lopicode/agent/think_tags.dart';
import 'package:lopicode/core/path_guard.dart';
import 'package:lopicode/core/safe_file.dart';
import 'package:lopicode/session/chat_models.dart';
import 'package:path/path.dart' as p;

import 'agent_round2_test.dart' show FnClient, OutputRunner, itemsOf;
import 'support/harness.dart';

/// 把 [chunks] 一块块喂进去，返回（正文，思考）和每一步吐出来的正文（看有没有闪半截标签）。
({String text, String thinking, List<String> shown}) feed(List<String> chunks) {
  final s = ThinkTagSplitter();
  final text = StringBuffer();
  final thinking = StringBuffer();
  final shown = <String>[];
  for (final c in chunks) {
    final part = s.add(c);
    text.write(part.text);
    thinking.write(part.thinking);
    shown.add(text.toString());
  }
  final rest = s.close();
  text.write(rest.text);
  thinking.write(rest.thinking);
  return (text: text.toString(), thinking: thinking.toString(), shown: shown);
}

void main() {
  group('ThinkTagSplitter', () {
    test('开头的 <think>…</think> 进思考，后面的是正文；收尾后的空行去掉', () {
      final r = feed(['<think>先看文件\n再回答</think>\n\n你好']);
      expect(r.thinking, '先看文件\n再回答');
      expect(r.text, '你好');
    });

    test('<thinking> 也认；不分大小写；开头允许有空白', () {
      final r = feed(['\n <Thinking>想</THINKING>答']);
      expect((r.text, r.thinking), ('答', '想'));
    });

    test('一个字一个字到达：标签被切开也不漏、正文里不闪半截标签', () {
      const whole = '<think>甲乙</think>\n丙丁';
      final r = feed(whole.split(''));
      expect(r.thinking, '甲乙');
      expect(r.text, '丙丁');
      expect(r.shown.where((s) => s.contains('<') || s.contains('>')), isEmpty, reason: '正文里任何时候都不该出现尖括号');
    });

    test('收尾标签被切在两块之间；思考里本来就有的 < 不丢', () {
      final r = feed(['<think>a < b 所以', '</thi', 'nk>好']);
      expect(r.thinking, 'a < b 所以');
      expect(r.text, '好');
    });

    test('没有标签：正文原样、一个字不少（包括开头的空白）', () {
      expect(feed(['  你好', '，世界']).text, '  你好，世界');
      expect(feed(['<', 'div>不是思考</div>']).text, '<div>不是思考</div>');
      expect(feed(['<thin']).text, '<thin', reason: '到结束都没凑成标签：按正文交出来');
    });

    test('正文中间出现的标签不动（模型可能正在讲这个标签）', () {
      final r = feed(['用 <think> 标签包住</think>就行']);
      expect(r.thinking, isEmpty);
      expect(r.text, '用 <think> 标签包住</think>就行');
    });

    test('一直没收尾：后面全算思考，正文是空的', () {
      final r = feed(['<think>想到一半', '就断了']);
      expect(r.thinking, '想到一半就断了');
      expect(r.text, isEmpty);
    });

    test('splitThinkTags：整段一次分好；没有标签原样返回', () {
      expect(splitThinkTags('<think> 想 </think>答'), (text: '答', thinking: '想'));
      expect(splitThinkTags('普通回复'), (text: '普通回复', thinking: ''));
    });
  });

  group('接进 Agent', () {
    late Directory tmp;
    late PathGuard guard;
    setUp(() {
      tmp = Directory.systemTemp.createTempSync('lopi_think_');
      Directory(p.join(tmp.path, 'proj')).createSync();
      File(p.join(tmp.path, 'proj', 'a.txt')).writeAsStringSync('hello');
      guard = PathGuard(p.join(tmp.path, 'proj'));
    });
    tearDown(() async {
      await pendingWrites();
      tmp.deleteSync(recursive: true);
    });
    AgentToolbox box() => AgentToolbox(guard: guard, runner: OutputRunner('ok'), requestApproval: (_) async => true, autoApprove: () => false);

    test('标签里的字走思考事件、不进正文；存进 _reasoning 并标 _reasoningTag；重开对话还在', () async {
      var n = 0;
      final client = FnClient(
        (m, t) => n++ == 0
            ? [say('<thi'), say('nk>先读文件</th'), say('ink>\n我看一下。'), call(0, 'read_file', '{"path":"a.txt"}'), ChatDelta(finishReason: 'tool_calls')]
            : [say('<think>可以答了</think>'), say('文件里是 hello'), ChatDelta(finishReason: 'stop')],
      );
      final runner = AgentRunner(client: client, toolbox: box());
      final events = await runner.send('看看 a.txt').toList();
      expect(events.whereType<ReasoningDelta>().map((e) => e.text).join('|'), '先读文件|可以答了');
      expect(events.whereType<AssistantDelta>().map((e) => e.text).join('|'), '我看一下。|文件里是 hello');
      expect(events.whereType<ReasoningDone>().length, 2);
      final assistants = runner.messages.where((m) => m['role'] == 'assistant').toList();
      expect(assistants[0]['content'], '我看一下。');
      expect(assistants[0]['_reasoning'], '先读文件');
      expect(assistants[0]['_reasoningTag'], isTrue);
      expect(assistants[0]['_reasoningMs'], isA<int>());
      expect(assistants[1]['content'], '文件里是 hello');
      expect(assistants[1]['_reasoning'], '可以答了');
      // 第二次请求里，上一条 assistant 的正文已经没有标签
      expect(client.seen[1].firstWhere((m) => m['role'] == 'assistant')['content'], '我看一下。');
      // 重开对话：从存下来的消息重建，思考还在、正文干净
      final items = itemsOf(runner.messages);
      expect(items.map((i) => i.runtimeType).toList(), [UserItem, ThinkingItem, AssistantItem, ToolItem, ThinkingItem, AssistantItem]);
      expect((items[1] as ThinkingItem).text, '先读文件');
      expect((items[2] as AssistantItem).text, '我看一下。');
    });

    test('只有标签、没有正文就结束：有思考、没有空的正文气泡', () async {
      final runner = AgentRunner(
        client: FnClient((m, t) => [say('<think>想了想'), ChatDelta(finishReason: 'stop')]),
        toolbox: box(),
      );
      final events = await runner.send('hi').toList();
      expect(events.whereType<ReasoningDelta>().map((e) => e.text).join(), '想了想');
      expect(events.whereType<AssistantDelta>(), isEmpty);
      expect(events.whereType<ReasoningDone>().length, 1);
    });

    test('没返回思考的：不造假（没有思考事件、消息上没有 _reasoning）', () async {
      final runner = AgentRunner(
        client: FnClient((m, t) => [say('你好'), ChatDelta(finishReason: 'stop')]),
        toolbox: box(),
      );
      final events = await runner.send('hi').toList();
      expect(events.where((e) => e is ReasoningDelta || e is ReasoningDone), isEmpty);
      expect(runner.messages.last.containsKey('_reasoning'), isFalse);
      expect(itemsOf(runner.messages).whereType<ThinkingItem>(), isEmpty);
    });

    test('标签里剥出来的思考不带回给接口；接口自己给的 reasoning_content 照旧带回（DeepSeek 的规矩没动）', () {
      final messages = [
        {'role': 'user', 'content': 'hi'},
        {'role': 'assistant', 'content': '甲', '_reasoning': '标签里的', '_reasoningTag': true},
        {'role': 'assistant', 'content': '乙', '_reasoning': '接口给的'},
      ];
      final wire = withReasoningContent(messages, fillMissing: false);
      expect(wire[1].containsKey('reasoning_content'), isFalse);
      expect(wire[2]['reasoning_content'], '接口给的');
      expect(wire.every((m) => m.keys.every((k) => !k.startsWith('_'))), isTrue);
      // 思考开着的 DeepSeek 官方地址：没有可带回的就补空串（原有做法）
      expect(withReasoningContent(messages, fillMissing: true)[1]['reasoning_content'], '');
    });

    test('旧存档里连标签一起存进正文的回复：显示时剥出来', () {
      final items = itemsOf([
        {'role': 'user', 'content': 'hi'},
        {'role': 'assistant', 'content': '<think>旧的思考</think>\n\n旧的回答', '_id': 'a1'},
      ]);
      expect(items.map((i) => i.runtimeType).toList(), [UserItem, ThinkingItem, AssistantItem]);
      expect((items[1] as ThinkingItem).text, '旧的思考');
      expect((items[1] as ThinkingItem).ms, isNull);
      expect((items[2] as AssistantItem).text, '旧的回答');
    });
  });
}
