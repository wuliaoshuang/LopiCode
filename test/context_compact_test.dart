// 压缩改进（2026-11-25）：压缩请求和正常对话同前缀（系统提示词、工具定义、历史消息逐字节一致，只在末尾多一条指令）；
// 摘要有固定栏目、漏写的由代码补齐；模型反而去调工具时不执行、按失败处理；调用次数不增加。
// 不带界面、不联网：请求体用本机的假模型服务器收下来比对。
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/agent/agent_runner.dart';
import 'package:lopicode/agent/agent_tools.dart';
import 'package:lopicode/agent/auto_compact.dart';
import 'package:lopicode/agent/chat_client.dart';
import 'package:lopicode/agent/compact_summary.dart';
import 'package:lopicode/agent/context_relief.dart';
import 'package:lopicode/agent/loop_guard.dart';
import 'package:lopicode/agent/protocols.dart';
import 'package:lopicode/agent/usage.dart';
import 'package:lopicode/core/path_guard.dart';
import 'package:lopicode/core/safe_file.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/project_session.dart';
import 'package:path/path.dart' as p;

import 'agent_test.dart' show RecordingRunner;
import 'support/fake_model_server.dart';
import 'support/harness.dart';

/// 记下每次请求的消息和工具定义（整份），回什么由 [turn] 定。
class RecClient implements ChatClient {
  RecClient(this.turn);
  FutureOr<List<ChatDelta>> Function(List<Map<String, dynamic>> messages, List<Map<String, dynamic>> tools) turn;
  final List<({String messages, String tools, List<Map<String, dynamic>> list})> log = [];

  @override
  Stream<ChatDelta> streamChat({required List<Map<String, dynamic>> messages, List<Map<String, dynamic>> tools = const []}) async* {
    log.add((messages: jsonEncode(stripInternal(messages)), tools: jsonEncode(tools), list: [for (final m in messages) Map<String, dynamic>.from(m)]));
    for (final d in await turn(messages, tools)) {
      yield d;
    }
  }
}

bool isCompactAsk(List<Map<String, dynamic>> messages) => messages.isNotEmpty && messages.last['role'] == 'user' && '${messages.last['content']}'.startsWith(kCompactAskHead);

/// 七个栏目都写了的摘要。
String fullSummary([String body = '没有']) => [for (final s in kCompactSections) '${sectionHeading(s.title)}\n$body'].join('\n\n');

void main() {
  late Directory tmp;
  late PathGuard guard;
  late RecordingRunner shell;
  FakeModelServer? server;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('lopi_ctx_');
    Directory(p.join(tmp.path, 'proj')).createSync();
    File(p.join(tmp.path, 'proj', 'index.html')).writeAsStringSync('<h1>hi</h1>');
    guard = PathGuard(p.join(tmp.path, 'proj'));
    shell = RecordingRunner();
  });
  tearDown(() async {
    await server?.stop();
    server = null;
    await pendingWrites();
    tmp.deleteSync(recursive: true);
  });

  /// 额外工具 big：返回 [chars] 个字符（不到转存上限）。
  ExtraTool big(int chars) => ExtraTool(spec: toolSpec('big', '返回一段内容', {}), kind: ToolKind.read, run: (_) async => ToolOutcome('R' * chars));

  AgentToolbox toolbox({int bigChars = 15000}) => AgentToolbox(guard: guard, runner: shell, requestApproval: (_) async => true, autoApprove: () => false, extras: [big(bigChars)]);

  /// 一段较早的历史：[pairs] 组一问一答（每条 [chars] 字），外加 [toolPairs] 组“调工具 + 结果”（结果 [resultChars] 字）。
  List<Map<String, dynamic>> history({required int pairs, required int chars, int toolPairs = 8, int resultChars = 500}) => [
    for (var i = 0; i < pairs; i++) ...[
      {'role': 'user', 'content': '第 $i 个要求 ${'问' * chars}'},
      {'role': 'assistant', 'content': '第 $i 个回答 ${'答' * chars}'},
    ],
    {'role': 'user', 'content': '看看这些文件'},
    for (var i = 0; i < toolPairs; i++) ...[
      {
        'role': 'assistant',
        'content': '',
        '_reasoning': '想第 $i 步',
        'tool_calls': [
          {
            'id': 'h$i',
            'type': 'function',
            'function': {
              'name': i.isEven ? 'read_file' : 'run_command',
              'arguments': jsonEncode(i.isEven ? {'path': 'src/f$i.dart'} : {'command': 'ls -la dir$i'}),
            },
          },
        ],
      },
      {'role': 'tool', 'tool_call_id': 'h$i', 'content': '结果 $i ${'x' * resultChars}'},
    ],
    {'role': 'assistant', 'content': '都看过了。', '_reasoning': '收尾'},
  ];

  List<Map<String, dynamic>> sent(int i) => [for (final m in server!.requests[i]['messages'] as List) (m as Map).cast<String, dynamic>()];
  Map<String, dynamic> rest(int i) => {...server!.requests[i]}..remove('messages');

  /// 上下文 10 万 token：85% 线是 85000（255000 字符）。历史约 24.5 万字符，big 的 15000 字符结果一进来就过线。
  Future<AgentRunner> overTheLine(List<ScriptedReply> script, {bool deepseek = true}) async {
    server = FakeModelServer(script);
    await server!.start();
    return AgentRunner(
      client: OpenAiChatClient(
        baseUrl: server!.baseUrl,
        apiKey: 'sk-test-key',
        model: deepseek ? 'deepseek-v4-pro' : 'fake-model',
        reasoningEffort: deepseek ? 'high' : null,
        deepSeekOfficial: deepseek,
      ),
      toolbox: toolbox(),
      history: history(pairs: 40, chars: 3000),
      contextLimit: 100000,
      autoCompact: true,
      retryDelayOf: (_) => Duration.zero,
    );
  }

  group('同前缀的压缩请求（假模型服务器收到的请求体）', () {
    test('压缩请求 = 上一条正常请求原样 + 中间新增的消息 + 一条指令；system、tools、其余参数逐字节一致；一共三次请求', () async {
      final runner = await overTheLine([
        ScriptedReply(reasoning: '先取数据。', calls: [ScriptedCall('big', '{}')]),
        ScriptedReply(text: fullSummary('写了'), usage: {'prompt_tokens': 90000, 'completion_tokens': 300, 'total_tokens': 90300, 'prompt_cache_hit_tokens': 88000, 'prompt_cache_miss_tokens': 2000}),
        ScriptedReply(reasoning: '接着做。', text: '做完了。'),
      ]);
      expect(AgentRunner.estimateTokens(runner.messages), lessThan(85000), reason: '第一次请求之前还没过线');
      final events = await runner.send('继续').toList();
      expect(server!.requests.length, 3, reason: '正常一次 + 压缩一次 + 正常一次，没有多出来的请求');

      final normal = sent(0), compact = sent(1);
      // 前 N 项逐字节一致（N＝上一条正常请求的全部消息，含 system）。
      expect(jsonEncode(compact.sublist(0, normal.length)), jsonEncode(normal));
      expect(compact.first['role'], 'system');
      expect(jsonEncode(compact.first), jsonEncode(normal.first));
      // 中间只多了：模型那条工具调用 + 工具结果；末尾是压缩指令。
      expect(compact.length, normal.length + 3);
      expect(compact[normal.length]['role'], 'assistant');
      expect(compact[normal.length + 1]['role'], 'tool');
      expect(compact[normal.length + 1]['content'], 'R' * 15000, reason: '没有先省略再压：工具结果原样在');
      expect(isCompactAsk(compact), isTrue);
      for (final s in kCompactSections) {
        expect('${compact.last['content']}', contains(sectionHeading(s.title)));
      }
      expect(jsonEncode(compact), isNot(contains(kPrunedToolResult)));
      // tools、tool_choice、model、思考档位……除 messages 之外整份请求体一致。
      expect(jsonEncode(rest(1)), jsonEncode(rest(0)));
      expect(rest(1)['tools'], isNotEmpty);
      expect(rest(1)['tool_choice'], 'auto');

      // DeepSeek 思考模式：之前每条 assistant 的 reasoning_content 都还带着（压缩请求和压缩之后的请求都是）。
      expect(compact[normal.length]['reasoning_content'], '先取数据。');
      for (final i in [1, 2]) {
        for (final m in sent(i).where((m) => m['role'] == 'assistant')) {
          expect(m.containsKey('reasoning_content'), isTrue, reason: '第 ${i + 1} 次请求里的 assistant 消息都带 reasoning_content');
        }
      }
      // 压缩之后的请求：摘要顶替了较早的，最近 6 条原样在，调用和结果成对。
      final after = sent(2);
      expect(isCompactAsk(after), isFalse);
      expect(after.where((m) => '${m['content']}'.startsWith(kCompactPrefix)).length, 1);
      expect(after.length, lessThan(12));
      expect(after.last['role'], 'tool');
      expect(after.last['content'], 'R' * 15000);

      // 事件：压缩那次单独记一笔用量（带缓存命中数），然后是“已压缩”，没有“已省略”。
      final compactions = events.whereType<RequestFinished>().where((e) => e.compaction).toList();
      expect(compactions.length, 1);
      expect(compactions.single.usage!.cacheRead, 88000);
      expect(events.whereType<RequestFinished>().length, 3);
      final done = events.whereType<ContextCompacted>().single;
      expect(missingSections(done.summary), isEmpty);
      expect(done.summary, fullSummary('写了'), reason: '栏目齐全时原样用模型写的');
      expect(events.whereType<AgentNotice>().where((n) => n.text.contains('已省略')), isEmpty);
      // 原消息归档不删：被顶替的还在记录里，工具结果是原样的。
      final archived = runner.messages.where(isArchived).toList();
      expect(archived.length, done.replaced);
      expect(archived.where((m) => m['role'] == 'tool').every((m) => '${m['content']}'.startsWith('结果 ')), isTrue);
      expect(runner.messages.where((m) => !isArchived(m)).length, lessThanOrEqualTo(kCompactKeepRecent + 2));
    });

    test('不是 DeepSeek 的普通兼容接口也一样同前缀（不带 reasoning_content）', () async {
      final runner = await overTheLine([
        ScriptedReply(calls: [ScriptedCall('big', '{}')]),
        ScriptedReply(text: '只写了一句话的摘要'),
        ScriptedReply(text: '做完了。'),
      ], deepseek: false);
      final events = await runner.send('继续').toList();
      expect(server!.requests.length, 3);
      final normal = sent(0), compact = sent(1);
      expect(jsonEncode(compact.sublist(0, normal.length)), jsonEncode(normal));
      expect(jsonEncode(rest(1)), jsonEncode(rest(0)));
      expect(jsonEncode(compact), isNot(contains('reasoning_content')));
      // 模型只写了一句：七个栏目由代码补齐，文件和命令从工具调用记录里抄。
      final summary = events.whereType<ContextCompacted>().single.summary;
      expect(summary, startsWith('只写了一句话的摘要'));
      expect(missingSections(summary), isEmpty);
      expect(summary, contains('src/f0.dart（读过）'));
      expect(summary, contains('ls -la dir1'));
    });

    test('压缩请求里模型反而去调工具：不执行、按失败处理、只省略旧结果继续；这一轮不再试，请求数不多', () async {
      final runner = await overTheLine([
        ScriptedReply(calls: [ScriptedCall('big', '{}')]),
        ScriptedReply(text: '我先写个文件。', calls: [ScriptedCall('write_file', '{"path":"hack.txt","content":"x"}')]),
        ScriptedReply(calls: [ScriptedCall('big', '{"n":2}')]),
        ScriptedReply(text: '做完了。'),
      ]);
      final before = runner.messages.length;
      final events = await runner.send('继续').toList();
      expect(server!.requests.length, 4, reason: '正常、压缩（失败）、正常、正常——失败后没有重试，后面也没再压');
      expect(isCompactAsk(sent(1)), isTrue);
      expect(isCompactAsk(sent(2)), isFalse);
      expect(isCompactAsk(sent(3)), isFalse);
      expect(File(p.join(tmp.path, 'proj', 'hack.txt')).existsSync(), isFalse, reason: '压缩请求里的工具调用没有执行');
      expect(events.whereType<ToolFinished>().map((e) => e.name).toList(), ['big', 'big']);
      expect(events.whereType<ContextCompacted>(), isEmpty);
      expect(events.whereType<RequestFinished>().where((e) => e.compaction).length, 1, reason: '失败的那次也如实记一笔用量');
      final notices = events.whereType<AgentNotice>().map((n) => n.text).join('\n');
      expect(notices, contains('没成功'));
      expect(notices, contains('想去调用工具'));
      expect(notices, contains('已省略'));
      // 记录：没有归档、没有摘要，“我先写个文件”那句没进记录；只是较早的工具结果被省略了。
      expect(runner.messages.where(isArchived), isEmpty);
      expect(jsonEncode(runner.messages), isNot(contains('我先写个文件')));
      expect(runner.messages.length, before + 1 + 2 + 2 + 1);
      expect(runner.messages.where((m) => m['content'] == kPrunedToolResult), isNotEmpty);
      // 省略之后的正常请求照样合法：每个调用都有结果。
      final third = sent(2);
      final ids = [
        for (final m in third.where((m) => m['role'] == 'assistant'))
          for (final c in (m['tool_calls'] as List? ?? const [])) (c as Map)['id'],
      ];
      expect(third.where((m) => m['role'] == 'tool').map((m) => m['tool_call_id']).toList(), ids);
    });

    test('压缩请求接口报错：记录不动，这一轮照常做完，不重试压缩', () async {
      final runner = await overTheLine([
        ScriptedReply(calls: [ScriptedCall('big', '{}')]),
        ScriptedReply(status: 400, errorBody: '{"error":{"message":"bad request"}}'),
        ScriptedReply(text: '做完了。'),
      ]);
      final events = await runner.send('继续').toList();
      expect(server!.requests.length, 3);
      expect(events.whereType<ContextCompacted>(), isEmpty);
      expect(events.whereType<AgentNotice>().map((n) => n.text).join(), contains('没成功'));
      expect(runner.messages.where(isArchived), isEmpty);
      expect(events.whereType<AssistantDelta>().map((e) => e.text).join(), '做完了。');
    });
  });

  group('用哪份历史当前缀（relieveContext）', () {
    AgentRunner runnerOf(RecClient client, List<Map<String, dynamic>> h, {int? limit = 100000}) =>
        AgentRunner(client: client, toolbox: toolbox(), history: h, contextLimit: limit, autoCompact: true, systemPrompt: 'SYS');
    List<ChatDelta> summary() => [say(fullSummary()), ChatDelta(usage: const TokenUsage(uncached: 10, output: 5)), ChatDelta(finishReason: 'stop')];

    test('没过 85% 线：什么都不做、不发请求', () async {
      final client = RecClient((m, t) => summary());
      final r = await relieveContext(runnerOf(client, history(pairs: 10, chars: 3000)), compact: true);
      expect(r.pruned, 0);
      expect(r.compact, isNull);
      expect(client.log, isEmpty);
    });

    test('省略旧工具结果就够：只省略，不压缩、不发请求（和以前一样）', () async {
      final client = RecClient((m, t) => summary());
      // 20 个 1.5 万字的工具结果：省略掉较早的 14 个就回到线下。
      final runner = runnerOf(client, history(pairs: 2, chars: 100, toolPairs: 20, resultChars: 15000));
      final r = await relieveContext(runner, compact: true);
      expect(r.pruned, 14);
      expect(r.compact, isNull);
      expect(client.log, isEmpty);
      expect(runner.messages.where((m) => m['content'] == kPrunedToolResult).length, 14);
    });

    test('原样历史放得下：用原样的（同前缀），发一次', () async {
      final client = RecClient((m, t) => summary());
      final h = history(pairs: 43, chars: 3000);
      final runner = runnerOf(client, h);
      final normal = jsonEncode(stripInternal(await runner.buildRequest()));
      final r = await relieveContext(runner, compact: true);
      expect(client.log.length, 1);
      expect(r.compact!.ok, isTrue);
      expect(r.compact!.samePrefix, isTrue);
      expect(r.pruned, 0);
      final req = client.log.single;
      // 正常请求的 JSON 去掉结尾的 “]” 就是压缩请求的开头。
      expect(req.messages.startsWith(normal.substring(0, normal.length - 1)), isTrue);
      expect(req.tools, jsonEncode(runner.toolbox.specs));
      expect(isCompactAsk(req.list), isTrue);
      expect(req.messages, isNot(contains(kPrunedToolResult)));
    });

    test('原样的放不下、省略过的放得下：用省略过的（前缀对到第一处省略之前），仍然只发一次', () async {
      final client = RecClient((m, t) => summary());
      // 文字约 21 万字符 + 9 个 8000 字的工具结果：原样 ≈ 9.5 万 token（加 5000 余量放不下），省略 3 个后 ≈ 8.7 万（仍过线，但放得下）。
      final runner = runnerOf(client, history(pairs: 40, chars: 2642, toolPairs: 9, resultChars: 8000));
      final r = await relieveContext(runner, compact: true);
      expect(client.log.length, 1);
      expect(r.compact!.ok, isTrue);
      expect(r.compact!.samePrefix, isTrue);
      final req = client.log.single;
      expect(req.tools, jsonEncode(runner.toolbox.specs));
      expect(req.list.first['content'], 'SYS');
      expect(req.list.where((m) => m['content'] == kPrunedToolResult).length, 3);
      expect(isCompactAsk(req.list), isTrue);
    });

    test('两种都放不下：退回纯文字记录的老办法（不带工具定义），仍然只发一次', () async {
      final client = RecClient((m, t) => summary());
      final runner = runnerOf(client, history(pairs: 46, chars: 3100, toolPairs: 2));
      final r = await relieveContext(runner, compact: true);
      expect(client.log.length, 1);
      expect(r.compact!.ok, isTrue);
      expect(r.compact!.samePrefix, isFalse);
      final req = client.log.single;
      expect(req.tools, '[]');
      expect(req.list.length, 2);
      expect(req.list.first['content'], '你是对话记录整理员。');
      expect('${req.list.last['content']}', contains(kCompactAskHead));
      expect(missingSections(r.compact!.summary), isEmpty);
    });

    test('不许压缩（开关关着 / 这一轮已经失败过）：只省略，不发请求', () async {
      final client = RecClient((m, t) => summary());
      final runner = runnerOf(client, history(pairs: 43, chars: 3000, toolPairs: 9, resultChars: 500));
      final r = await relieveContext(runner, compact: false);
      expect(client.log, isEmpty);
      expect(r.compact, isNull);
      expect(r.pruned, 3);
    });

    test('余量：上下文的 5%，至少 2000', () {
      expect(compactReserveOf(128000), 6400);
      expect(compactReserveOf(8000), 2000);
    });

    test('/compact 的整段压缩：同前缀、带工具定义；太短不发请求；模型调工具算失败、记录不动', () async {
      final client = RecClient((m, t) => summary());
      final h = history(pairs: 3, chars: 50, toolPairs: 2);
      final runner = runnerOf(client, h, limit: null);
      final normal = jsonEncode(stripInternal(await runner.buildRequest()));
      final ok = await compactWholeConversation(runner);
      expect(ok.ok, isTrue);
      expect(ok.samePrefix, isTrue);
      expect(client.log.single.messages.startsWith(normal.substring(0, normal.length - 1)), isTrue);
      expect(client.log.single.tools, jsonEncode(runner.toolbox.specs));
      expect(runner.messages.length, 2, reason: '整段压：只剩摘要 + 一句承接');
      expect(runner.messages.where(isArchived), isEmpty, reason: '/compact 不归档（和以前一样）');

      final short = runnerOf(RecClient((m, t) => summary()), [
        {'role': 'user', 'content': '你好'},
      ]);
      expect((await compactWholeConversation(short)).skipped, isTrue);
      expect((short.client as RecClient).log, isEmpty);

      final naughty = RecClient((m, t) => [say('我看看'), call(0, 'read_file', '{"path":"index.html"}'), ChatDelta(finishReason: 'tool_calls')]);
      final h2 = history(pairs: 3, chars: 50, toolPairs: 2);
      final copy = jsonEncode(h2);
      final r2 = await compactWholeConversation(runnerOf(naughty, h2));
      expect(r2.ok, isFalse);
      expect(r2.error, contains('想去调用工具'));
      expect(naughty.log.length, 1, reason: '没有再发第二次');
      expect(jsonEncode(h2), copy, reason: '记录一个字都没动');
    });
  });

  group('摘要栏目（纯计算）', () {
    test('指令里七个栏目按顺序都在；同前缀的说法明说不要调工具', () {
      final ask = compactInstruction();
      expect(ask, startsWith(kCompactAskHead));
      expect(kCompactAskHead, isNotEmpty);
      expect(ask, contains('不要调用任何工具'));
      expect(kCompactSections.length, 7);
      var at = -1;
      for (final s in kCompactSections) {
        final i = ask.indexOf(sectionHeading(s.title));
        expect(i, greaterThan(at), reason: s.title);
        at = i;
      }
      expect(compactInstruction(transcript: true), contains('上面这段对话记录'));
    });

    test('认栏目：标题独占一行，# 的个数、结尾的冒号不计较；写在句子中间的不算', () {
      expect(hasSection('## 关键文件\n- a', '关键文件'), isTrue);
      expect(hasSection('### 关键文件：\n- a', '关键文件'), isTrue);
      expect(hasSection('这里没有关键文件这一栏', '关键文件'), isFalse);
      expect(missingSections(fullSummary()), isEmpty);
      expect(missingSections('随便写的').length, 7);
    });

    test('补齐：缺的栏目接在后面；文件（读过又改过记成改过）和命令从工具调用里抄，去重、有上限；别的栏写明没写', () {
      Map<String, dynamic> callOf(String name, Map<String, dynamic> args) => {
        'role': 'assistant',
        'content': '',
        'tool_calls': [
          {
            'id': 'x',
            'type': 'function',
            'function': {'name': name, 'arguments': jsonEncode(args)},
          },
        ],
      };
      final older = [
        callOf('read_file', {'path': 'a.dart'}),
        callOf('edit_file', {'path': 'a.dart'}),
        callOf('read_file', {'path': 'b.dart'}),
        callOf('read_file', {'path': 'b.dart'}),
        callOf('write_file', {'path': 'c.dart', 'content': '很长的内容'}),
        callOf('delete_file', {'path': 'd.dart'}),
        callOf('run_command', {'command': 'flutter test'}),
        callOf('run_command', {'command': 'flutter test'}),
        callOf('run_command', {'command': 'x' * 300}),
        {
          'role': 'assistant',
          'tool_calls': [
            {
              'id': 'bad',
              'function': {'name': 'read_file', 'arguments': '{坏 JSON'},
            },
          ],
        },
        for (var i = 0; i < 40; i++) callOf('read_file', {'path': 'many/$i.dart'}),
      ];
      final touched = touchedByTools(older);
      expect(touched.files.take(4).toList(), ['a.dart（修改）', 'b.dart（读过）', 'c.dart（写入）', 'd.dart（删除）']);
      expect(touched.commands.length, 2);
      expect(touched.commands.last.length, 201, reason: '命令最多 200 字再加一个省略号');

      const partial = '## 用户要做什么\n做个页面\n\n## 已经做了什么\n写了';
      final done = completeSummary(partial, older);
      expect(done, startsWith(partial));
      expect(missingSections(done), isEmpty);
      expect(done, contains('- a.dart（修改）'));
      expect(done, contains('- flutter test'));
      expect(done, isNot(contains('很长的内容')), reason: '只抄路径，不抄文件内容');
      expect('- many/'.allMatches(done).length, kSummaryMaxFiles - 4);
      expect(done, contains('还有 ${44 - kSummaryMaxFiles} 项没列出'));
      expect(done, contains('## 当前卡在哪\n（模型的摘要里没有写这一栏）'));
      // 栏目齐全的原样返回。
      expect(completeSummary(fullSummary(), older), fullSummary());
      // 没有工具调用可抄：那两栏也写明没写。
      expect(completeSummary('x', const []), contains('## 关键文件\n（模型的摘要里没有写这一栏）'));
    });
  });

  group('Anthropic 格式', () {
    test('转换之后前缀照样一致；这一轮没有加 cache_control', () async {
      final runner = AgentRunner(client: RecClient((m, t) => const []), toolbox: toolbox(), history: history(pairs: 3, chars: 50, toolPairs: 2), systemPrompt: 'SYS');
      final normal = await runner.buildRequest();
      final compact = [
        ...normal,
        {'role': 'user', 'content': compactInstruction()},
      ];
      final a = anthropicMessages(normal), b = anthropicMessages(compact);
      expect(b.system, a.system);
      expect(jsonEncode(b.messages.sublist(0, a.messages.length)), jsonEncode(a.messages));
      expect(b.messages.length, a.messages.length + 1);
      final tools = anthropicTools(runner.toolbox.specs);
      expect(jsonEncode([b.system, b.messages, tools]), isNot(contains('cache_control')));
    });
  });

  group('/compact（经会话）', () {
    test('和上一条正常请求同一份系统提示词、同一套工具定义、同样的历史；一次请求；用量、摘要栏目、失败不动记录', () async {
      late RecClient client;
      client = RecClient((m, t) => [say('页面做好了。'), ChatDelta(finishReason: 'stop')]);
      final env = await TestEnv.create(chatClient: () => client);
      final project = await env.services.projects.create('测试工作区', ProjectTemplate.web);
      final session = ProjectSession(env.services, project, headless: true);
      session.commandRunnerFactory = () => shell;
      await session.loadChat();
      addTearDown(() async {
        session.dispose();
        await env.dispose();
      });
      await session.sendToAgent('做个页面');
      expect(client.log.length, 1);
      final normal = client.log.single;

      // 模型去调工具：失败，记录不动。
      client.turn = (m, t) => [call(0, 'list_files', '{}'), ChatDelta(finishReason: 'tool_calls')];
      final failed = await session.compactConversation();
      expect(failed, contains('想去调用工具'));
      expect(client.log.length, 2);
      expect(session.chat.whereType<CompactionItem>(), isEmpty);

      client.turn = (m, t) => [say('摘要：做过一个页面'), ChatDelta(finishReason: 'stop')];
      expect(await session.compactConversation(), '已压缩');
      expect(client.log.length, 3, reason: '一次压缩 = 一次请求');
      final req = client.log.last;
      expect(req.tools, normal.tools);
      expect(req.tools, isNot('[]'));
      expect(jsonEncode(req.list.first), jsonEncode(normal.list.first), reason: '系统提示词一字不差');
      expect(req.messages.startsWith(normal.messages.substring(0, normal.messages.length - 1)), isTrue, reason: '上一条正常请求的消息是它的开头');
      expect(isCompactAsk(req.list), isTrue);
      expect(req.list.length, normal.list.length + 2, reason: '多了模型那句回答 + 压缩指令');
      final item = session.chat.whereType<CompactionItem>().single;
      expect(item.summary, startsWith('摘要：做过一个页面'));
      expect(missingSections(item.summary), isEmpty);

      client.turn = (m, t) => [say('继续'), ChatDelta(finishReason: 'stop')];
      await session.sendToAgent('接着做');
      expect(client.log.last.messages, contains('摘要：做过一个页面'));
      expect(client.log.last.messages, isNot(contains('做个页面')));
    });
  });
}
