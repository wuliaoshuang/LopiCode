// Agent 能力（2026-11-24）：参数错误回给模型、重复失败的死循环、结果截断、只读工具并行、
// 上下文快满时省掉旧结果、接口临时出错自动重试、DeepSeek 思考内容回传、待办清单。
// 全部用本地假模型服务器，不联网。
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/agent/agent_runner.dart';
import 'package:lopicode/agent/agent_tools.dart';
import 'package:lopicode/agent/chat_client.dart';
import 'package:lopicode/agent/command_output_store.dart';
import 'package:lopicode/agent/loop_guard.dart';
import 'package:lopicode/agent/todos.dart';
import 'package:lopicode/core/path_guard.dart';
import 'package:lopicode/session/chat_models.dart';
import 'package:lopicode/session/chat_rows.dart';
import 'package:path/path.dart' as p;

import 'agent_test.dart' show RecordingRunner;
import 'support/fake_model_server.dart';

void main() {
  late Directory tmp;
  late PathGuard guard;
  late RecordingRunner shell;
  late List<ApprovalRequest> asked;
  FakeModelServer? server;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('lopi_cap_');
    Directory(p.join(tmp.path, 'proj')).createSync();
    File(p.join(tmp.path, 'proj', 'index.html')).writeAsStringSync('<h1>hi</h1>');
    File(p.join(tmp.path, 'proj', 'lines.txt')).writeAsStringSync([for (var i = 1; i <= 50; i++) 'line $i'].join('\n'));
    guard = PathGuard(p.join(tmp.path, 'proj'));
    shell = RecordingRunner();
    asked = [];
  });
  tearDown(() async {
    await server?.stop();
    server = null;
    tmp.deleteSync(recursive: true);
  });

  AgentToolbox toolbox({List<ExtraTool> extras = const []}) => AgentToolbox(
    guard: guard,
    runner: shell,
    requestApproval: (r) async {
      asked.add(r);
      return false;
    },
    autoApprove: () => false,
    extras: extras,
  );

  Future<AgentRunner> runnerFor(
    List<ScriptedReply> script, {
    ScriptedReply? fallback,
    int maxSteps = 12,
    List<ExtraTool> extras = const [],
    int? contextLimit,
    String model = 'fake-model',
    String? reasoningEffort,
    bool? deepSeekOfficial,
  }) async {
    server = FakeModelServer(script, fallback: fallback);
    await server!.start();
    return AgentRunner(
      client: OpenAiChatClient(baseUrl: server!.baseUrl, apiKey: 'sk-test-key', model: model, reasoningEffort: reasoningEffort, deepSeekOfficial: deepSeekOfficial),
      toolbox: toolbox(extras: extras),
      maxSteps: maxSteps,
      contextLimit: contextLimit,
      retryDelayOf: (_) => Duration.zero,
    );
  }

  List<ToolFinished> finished(List<AgentEvent> events) => events.whereType<ToolFinished>().toList();
  List<Map<String, dynamic>> sentMessages(int request) => [for (final m in server!.requests[request]['messages'] as List) (m as Map).cast<String, dynamic>()];

  group('LoopGuard（纯逻辑）', () {
    test('键顺序、空白不同算同一个调用；参数不同不算', () {
      expect(LoopGuard.keyOf('read_file', '{"a":1,"b":2}'), LoopGuard.keyOf('read_file', '{ "b": 2, "a": 1 }'));
      expect(LoopGuard.keyOf('read_file', '{"a":1}'), isNot(LoopGuard.keyOf('read_file', '{"a":2}')));
      expect(LoopGuard.keyOf('read_file', ''), LoopGuard.keyOf('read_file', '{}'));
    });

    test('连续失败：前 2 次照跑，第 3、4 次拦下，第 5 次整轮停；中间夹了别的调用就重新数', () {
      final g = LoopGuard();
      for (var i = 0; i < kRepeatFailLimit - 1; i++) {
        expect(g.check('read_file', '{"path":"x"}'), LoopVerdict.run);
        g.record('read_file', '{"path":"x"}', ok: false);
      }
      for (var i = kRepeatFailLimit - 1; i < kRepeatFailStop - 1; i++) {
        expect(g.check('read_file', '{"path":"x"}'), LoopVerdict.refuse);
        g.record('read_file', '{"path":"x"}', ok: false);
      }
      expect(g.check('read_file', '{"path":"x"}'), LoopVerdict.stop);
      // 换一个调用：重新数
      expect(g.check('list_files', '{}'), LoopVerdict.run);
      g.record('list_files', '{}', ok: true);
      expect(g.check('read_file', '{"path":"x"}'), LoopVerdict.run);
    });

    test('连续成功到第 4 次给一句提醒，只给一次', () {
      final g = LoopGuard();
      final notes = [for (var i = 0; i < 6; i++) g.record('list_files', '{}', ok: true)];
      expect(notes.where((n) => n != null).length, 1);
      expect(notes[kRepeatOkNudge - 1], contains('不要再重复'));
    });

    test('clipToolResult：不超不动；超了留头留尾并说明省了多少', () {
      expect(clipToolResult('abc'), 'abc');
      final long = '${'H' * 100}${'M' * 1000}${'T' * 100}';
      final out = clipToolResult(long, max: 200);
      expect(out.startsWith('H' * 100), isTrue);
      expect(out.endsWith('T' * 60), isTrue);
      expect(out, contains('中间省略 1000 字符'));
      expect(out, contains('共 1200 字符'));
    });

    test('pruneOldToolResults：只换较早的长结果，最近的不动，配对不坏，不重复裁', () {
      final messages = <Map<String, dynamic>>[
        {'role': 'user', 'content': 'hi'},
        for (var i = 0; i < 10; i++) ...[
          {
            'role': 'assistant',
            'content': '',
            'tool_calls': [
              {'id': 'c$i'},
            ],
          },
          {'role': 'tool', 'tool_call_id': 'c$i', 'content': i == 1 ? '短' : 'x' * 1000},
        ],
      ];
      expect(pruneOldToolResults(messages), 3, reason: '前 4 条里有 1 条很短，不值得裁');
      final tools = messages.where((m) => m['role'] == 'tool').toList();
      expect(tools.map((m) => m['tool_call_id']), [for (var i = 0; i < 10; i++) 'c$i']);
      expect(tools[0]['content'], kPrunedToolResult);
      expect(tools[1]['content'], '短');
      expect(tools.skip(4).every((m) => (m['content'] as String).length == 1000), isTrue);
      expect(pruneOldToolResults(messages), 0);
    });

    test('哪些状态码值得重试', () {
      expect([429, 500, 502, 503, 504].every(isRetryableStatus), isTrue);
      expect([400, 401, 403, 404, null].any(isRetryableStatus), isFalse);
    });
  });

  group('参数错误回给模型', () {
    test('坏 JSON：说明错在哪并带上原文，模型下一轮改对了，整轮不失败', () async {
      final runner = await runnerFor([
        ScriptedReply(calls: [ScriptedCall('read_file', '{"path": index.html}')]),
        ScriptedReply(calls: [ScriptedCall('read_file', '{"path":"index.html"}')]),
        ScriptedReply(text: '读到了。'),
      ]);
      final events = await runner.send('读一下').toList();
      final done = finished(events);
      expect(done[0].outcome.ok, isFalse);
      expect(done[0].outcome.text, allOf(contains('read_file'), contains('不是合法的 JSON'), contains('{"path": index.html}'), contains('重新调用')));
      expect(done[1].outcome.text, '<h1>hi</h1>');
      expect(events.whereType<AgentError>(), isEmpty);
      // 错误确实发回给了模型
      expect(sentMessages(1).last['content'], done[0].outcome.text);
    });

    test('参数是数组不是对象：也说清楚', () async {
      final runner = await runnerFor([
        ScriptedReply(calls: [ScriptedCall('read_file', '["index.html"]')]),
        ScriptedReply(text: '好。'),
      ]);
      final done = finished(await runner.send('读').toList());
      expect(done.single.outcome.text, contains('必须是一个 JSON 对象'));
    });

    test('输出被长度上限截断（finish_reason=length）：最后一个调用不执行，哪怕看起来完整', () async {
      final runner = await runnerFor([
        ScriptedReply(
          calls: [
            ScriptedCall('list_files', '{}'),
            ScriptedCall('write_file', jsonEncode({'path': 'a.txt', 'content': '半截'})),
          ],
          finish: 'length',
        ),
        ScriptedReply(text: '好。'),
      ]);
      final done = finished(await runner.send('写').toList());
      expect(done[0].outcome.ok, isTrue, reason: '前面的调用是完整的，照常执行');
      expect(done[1].outcome.ok, isFalse);
      expect(done[1].outcome.text, allOf(contains('截断'), contains('分几次写')));
      expect(File(p.join(guard.root, 'a.txt')).existsSync(), isFalse);
    });

    test('不存在的工具：报错里列出现在能用的工具', () async {
      final runner = await runnerFor([
        ScriptedReply(calls: [ScriptedCall('grep', '{}')]),
        ScriptedReply(text: '好。'),
      ]);
      final done = finished(await runner.send('搜').toList());
      expect(done.single.outcome.text, allOf(contains('没有名为 grep 的工具'), contains('read_file'), contains('list_files')));
    });
  });

  group('重复失败的死循环', () {
    test('模型一直用同样的参数读不存在的文件：真跑 2 次，拦 2 次，第 5 次整轮停下', () async {
      final runner = await runnerFor([], fallback: ScriptedReply(calls: [ScriptedCall('read_file', '{"path":"nope.txt"}')]));
      final events = await runner.send('读').toList();
      final done = finished(events);
      expect(done.length, kRepeatFailStop);
      expect(done.take(2).every((d) => d.outcome.text.contains('文件不存在')), isTrue);
      expect(done[2].outcome.text, contains('都失败了，这一次没有执行'));
      expect(done[3].outcome.text, contains('都失败了，这一次没有执行'));
      expect(server!.requests.length, kRepeatFailStop, reason: '不会一直跑到 12 轮');
      expect(events.last, isA<AgentNotice>());
      expect((events.last as AgentNotice).text, contains('重复同一个失败的操作'));
      // 历史仍然合法
      final callIds = [
        for (final m in runner.messages.where((m) => m['role'] == 'assistant'))
          for (final c in (m['tool_calls'] as List? ?? const [])) (c as Map)['id'],
      ];
      expect(runner.messages.where((m) => m['role'] == 'tool').map((m) => m['tool_call_id']).toList(), callIds);
    });

    test('被用户拒绝的命令反复重试：问 2 次后不再弹确认卡', () async {
      final runner = await runnerFor([], fallback: ScriptedReply(calls: [ScriptedCall('run_command', '{"command":"rm -rf ."}')]));
      await runner.send('删').toList();
      expect(asked.length, 2);
      expect(shell.commands, isEmpty);
    });

    test('失败后改了参数就不算重复', () async {
      final runner = await runnerFor([
        ScriptedReply(calls: [ScriptedCall('read_file', '{"path":"a"}')]),
        ScriptedReply(calls: [ScriptedCall('read_file', '{"path":"b"}')]),
        ScriptedReply(calls: [ScriptedCall('read_file', '{"path":"c"}')]),
        ScriptedReply(calls: [ScriptedCall('read_file', '{"path":"d"}')]),
        ScriptedReply(text: '都没有。'),
      ]);
      final done = finished(await runner.send('找').toList());
      expect(done.every((d) => d.outcome.text.contains('文件不存在')), isTrue);
    });
  });

  group('结果截断与分段读', () {
    test('额外工具返回超长结果：兜底截断，头尾都在', () async {
      final big = ExtraTool(spec: toolSpec('big', '返回很长的内容', {}), kind: ToolKind.read, run: (_) async => ToolOutcome('BEGIN${'x' * (kMaxToolResultChars * 2)}END'));
      final runner = await runnerFor(
        [
          ScriptedReply(calls: [ScriptedCall('big', '{}')]),
          ScriptedReply(text: '好。'),
        ],
        extras: [big],
      );
      final out = finished(await runner.send('来').toList()).single.outcome;
      expect(out.ok, isTrue);
      // 2026-11-25：超长结果现在全文转存成文件，回给模型的多了“存在哪、怎么接着看”那段话，所以余量从 200 放到 400。
      expect(out.text.length, lessThan(kMaxToolResultChars + 400));
      expect(out.text, allOf(startsWith('BEGIN'), endsWith('END'), contains('中间省略')));
      final rel = spilledOutputPathOf(out.text);
      expect(rel, isNotNull, reason: '全文存成了文件，路径写在结果里');
      expect(File(p.join(tmp.path, 'proj', rel)).readAsStringSync(), 'BEGIN${'x' * (kMaxToolResultChars * 2)}END');
    });

    test('read_file 按行号读一段；越界、行号不合法都给明确的错', () async {
      final box = toolbox();
      final part = await box.execute('read_file', {'path': 'lines.txt', 'start_line': 10, 'end_line': 12});
      expect(part.text, '（lines.txt 第 10–12 行，全文共 50 行）\nline 10\nline 11\nline 12');
      final tail = await box.execute('read_file', {'path': 'lines.txt', 'start_line': '49'});
      expect(tail.text, endsWith('line 49\nline 50'));
      final beyond = await box.execute('read_file', {'path': 'lines.txt', 'start_line': 99});
      expect(beyond.ok, isFalse);
      expect(beyond.text, contains('一共只有 50 行'));
      final bad = await box.execute('read_file', {'path': 'lines.txt', 'start_line': 0});
      expect(bad.ok, isFalse);
      expect(bad.text, contains('从 1 开始'));
      final reversed = await box.execute('read_file', {'path': 'lines.txt', 'start_line': 5, 'end_line': 2});
      expect(reversed.ok, isFalse);
      // 不带行号：和以前一样，原样返回
      expect((await box.execute('read_file', {'path': 'index.html'})).text, '<h1>hi</h1>');
    });

    test('文件太长：提示用行号分段读', () async {
      File(p.join(guard.root, 'huge.txt')).writeAsStringSync([for (var i = 0; i < 20000; i++) 'row $i'].join('\n'));
      final out = await toolbox().execute('read_file', {'path': 'huge.txt'});
      expect(out.text, allOf(contains('只显示前 ${AgentToolbox.maxReadChars} 字符'), contains('start_line')));
    });
  });

  group('只读工具并行', () {
    ExtraTool slow(String name, ToolKind kind, List<String> log) => ExtraTool(
      spec: toolSpec(name, name, {}),
      kind: kind,
      run: (args) async {
        log.add('start $name ${args['n']}');
        await Future<void>.delayed(const Duration(milliseconds: 60));
        log.add('end $name ${args['n']}');
        return ToolOutcome('$name ${args['n']}');
      },
    );

    test('连着的只读工具同时开始；结果顺序和调用顺序一致', () async {
      final log = <String>[];
      final runner = await runnerFor(
        [
          ScriptedReply(calls: [for (var i = 0; i < 3; i++) ScriptedCall('peek', '{"n":$i}')]),
          ScriptedReply(text: '好。'),
        ],
        extras: [slow('peek', ToolKind.read, log)],
      );
      final events = await runner.send('看').toList();
      expect(log.take(3), ['start peek 0', 'start peek 1', 'start peek 2'], reason: '三个都开始了才有第一个结束');
      expect(finished(events).map((e) => e.outcome.text), ['peek 0', 'peek 1', 'peek 2']);
      expect(sentMessages(1).where((m) => m['role'] == 'tool').map((m) => m['content']), ['peek 0', 'peek 1', 'peek 2']);
    });

    test('写和执行类工具仍然一个一个来；只读的不会越过中间的写操作', () async {
      final log = <String>[];
      final runner = await runnerFor(
        [
          ScriptedReply(calls: [ScriptedCall('peek', '{"n":0}'), ScriptedCall('poke', '{"n":1}'), ScriptedCall('poke', '{"n":2}'), ScriptedCall('peek', '{"n":3}')]),
          ScriptedReply(text: '好。'),
        ],
        extras: [slow('peek', ToolKind.read, log), slow('poke', ToolKind.write, log)],
      );
      await runner.send('改').toList();
      expect(log, ['start peek 0', 'end peek 0', 'start poke 1', 'end poke 1', 'start poke 2', 'end poke 2', 'start peek 3', 'end peek 3']);
    });

    test('一批最多 ${AgentRunner.maxReadParallel} 个', () async {
      final log = <String>[];
      final runner = await runnerFor(
        [
          ScriptedReply(calls: [for (var i = 0; i < 6; i++) ScriptedCall('peek', '{"n":$i}')]),
          ScriptedReply(text: '好。'),
        ],
        extras: [slow('peek', ToolKind.read, log)],
      );
      await runner.send('看').toList();
      expect(log.take(AgentRunner.maxReadParallel).every((l) => l.startsWith('start')), isTrue);
      expect(log[AgentRunner.maxReadParallel], startsWith('end'));
    });
  });

  group('上下文快满', () {
    test('估算超过 85%：较早的工具结果换成占位再发请求，并出一条提示；最近的保留', () async {
      final big = ExtraTool(spec: toolSpec('big', 'big', {}), kind: ToolKind.read, run: (args) async => ToolOutcome('R${args['n']}:${'y' * 3000}'));
      final runner = await runnerFor(
        [
          for (var i = 0; i < 9; i++) ScriptedReply(calls: [ScriptedCall('big', '{"n":$i}')]),
          ScriptedReply(text: '完。'),
        ],
        extras: [big],
        contextLimit: 8000, // 约 24000 字符；8 条 3000 字的结果就到线
      );
      final events = await runner.send('跑').toList();
      final notice = events.whereType<AgentNotice>().where((n) => n.text.contains('已省略')).toList();
      expect(notice, isNotEmpty);
      final last = sentMessages(server!.requests.length - 1).where((m) => m['role'] == 'tool').toList();
      expect(last.first['content'], kPrunedToolResult);
      expect((last.last['content'] as String).startsWith('R8:'), isTrue, reason: '最近的结果原样保留');
      expect(last.length, 9, reason: '消息一条不少，配对不坏');
    });

    test('没给上下文长度就不动', () async {
      final big = ExtraTool(spec: toolSpec('big', 'big', {}), kind: ToolKind.read, run: (args) async => ToolOutcome('R${args['n']}:${'y' * 3000}'));
      final runner = await runnerFor(
        [
          for (var i = 0; i < 9; i++) ScriptedReply(calls: [ScriptedCall('big', '{"n":$i}')]),
          ScriptedReply(text: '完。'),
        ],
        extras: [big],
      );
      final events = await runner.send('跑').toList();
      expect(events.whereType<AgentNotice>(), isEmpty);
    });
  });

  group('接口临时出错自动重试', () {
    test('503 两次后成功：自动重试，用户消息不丢，有提示', () async {
      final runner = await runnerFor([ScriptedReply(status: 503), ScriptedReply(status: 503), ScriptedReply(text: '来了。')]);
      final events = await runner.send('在吗').toList();
      expect(server!.requests.length, 3);
      expect(events.whereType<AgentNotice>().length, 2);
      expect(events.whereType<AgentNotice>().first.text, contains('自动重试（第 1 次，最多 2 次）'));
      expect(events.whereType<AgentError>(), isEmpty);
      expect(events.whereType<AssistantMessage>().single.text, '来了。');
    });

    test('一直 503：重试 2 次后如实报错', () async {
      final runner = await runnerFor([], fallback: ScriptedReply(status: 503));
      final events = await runner.send('在吗').toList();
      expect(server!.requests.length, 3);
      expect(events.last, isA<AgentError>());
    });

    test('401、400 这类重试也没用的：不重试', () async {
      for (final status in [401, 400, 404]) {
        final runner = await runnerFor([], fallback: ScriptedReply(status: status));
        final events = await runner.send('在吗').toList();
        expect(server!.requests.length, 1, reason: '$status 不该重试');
        expect(events.last, isA<AgentError>());
        await server!.stop();
      }
    });

    test('等重试的时候点停止：不再发请求', () async {
      server = FakeModelServer([], fallback: ScriptedReply(status: 503));
      await server!.start();
      final runner = AgentRunner(
        client: OpenAiChatClient(baseUrl: server!.baseUrl, apiKey: 'k', model: 'm'),
        toolbox: toolbox(),
        retryDelayOf: (_) => const Duration(seconds: 30),
      );
      final events = <AgentEvent>[];
      final done = Completer<void>();
      runner.send('在吗').listen((e) {
        events.add(e);
        if (e is AgentNotice) runner.cancel();
      }, onDone: done.complete);
      await done.future.timeout(const Duration(seconds: 10));
      expect(server!.requests.length, 1);
      expect(events.last, isA<AgentError>());
    });
  });

  group('DeepSeek 思考内容回传', () {
    test('带工具调用的那条回复的思考内容存下来，下一次请求原样带回（reasoning_content）', () async {
      final runner = await runnerFor(
        [
          ScriptedReply(reasoning: '先看看有什么文件。', calls: [ScriptedCall('list_files', '{}')]),
          ScriptedReply(reasoning: '看完了。', text: '有一个 index.html。'),
          ScriptedReply(text: '不客气。'),
        ],
        model: 'deepseek-v4-pro',
        reasoningEffort: 'high',
        deepSeekOfficial: true,
      );
      final events = await runner.send('看看').toList();
      expect(events.whereType<AssistantDelta>().map((e) => e.text).join(), '有一个 index.html。', reason: '思考内容不当作回答显示');
      final second = sentMessages(1);
      final assistant = second.firstWhere((m) => m['role'] == 'assistant');
      expect(assistant['reasoning_content'], '先看看有什么文件。');
      expect(assistant.keys.where((k) => k.startsWith('_')), isEmpty, reason: '内部字段不外发');
      // 下一轮用户消息：之前两条 assistant 的思考都还带着
      await runner.send('谢谢').toList();
      final third = sentMessages(2).where((m) => m['role'] == 'assistant').toList();
      expect(third.map((m) => m['reasoning_content']), ['先看看有什么文件。', '看完了。']);
      expect(server!.requests[0].containsKey('thinking'), isFalse);
    });

    test('思考档位选“关”：明说 thinking disabled（DeepSeek 默认是开的），不带 reasoning_effort', () async {
      final runner = await runnerFor([ScriptedReply(text: '好。')], model: 'deepseek-flash', deepSeekOfficial: true);
      await runner.send('hi').toList();
      expect(server!.requests.single['thinking'], {'type': 'disabled'});
      expect(server!.requests.single.containsKey('reasoning_effort'), isFalse);
    });

    test('思考开着、旧对话里的 assistant 消息没存思考内容：补空字符串', () {
      final out = withReasoningContent([
        {'role': 'user', 'content': 'a'},
        {'role': 'assistant', 'content': 'b', '_raw': 1},
        {'role': 'assistant', 'content': 'c', '_reasoning': 'r'},
        {'role': 'tool', 'tool_call_id': 'x', 'content': 'd'},
      ], fillMissing: true);
      expect(out[0].containsKey('reasoning_content'), isFalse);
      expect(out[1], {'role': 'assistant', 'content': 'b', 'reasoning_content': ''});
      expect(out[2], {'role': 'assistant', 'content': 'c', 'reasoning_content': 'r'});
      expect(out[3].containsKey('reasoning_content'), isFalse);
      expect(
        withReasoningContent([
          {'role': 'assistant', 'content': 'b'},
        ], fillMissing: false).single.containsKey('reasoning_content'),
        isFalse,
      );
    });

    test('中转站上的 deepseek 模型：思考内容照样带回，但不发 thinking 这个官方专有参数、不补空字符串', () async {
      final runner = await runnerFor([
        ScriptedReply(reasoning: '想一想。', calls: [ScriptedCall('list_files', '{}')]),
        ScriptedReply(text: '好。'),
        ScriptedReply(text: '嗯。'),
      ], model: 'deepseek-ai/DeepSeek-V4');
      await runner.send('看').toList();
      await runner.send('再看').toList();
      expect(server!.requests.every((r) => !r.containsKey('thinking')), isTrue);
      final assistants = sentMessages(2).where((m) => m['role'] == 'assistant').toList();
      expect(assistants[0]['reasoning_content'], '想一想。');
      expect(assistants[1].containsKey('reasoning_content'), isFalse);
    });

    test('地址是 api.deepseek.com 才算官方', () {
      expect(OpenAiChatClient(baseUrl: 'https://api.deepseek.com', apiKey: 'k', model: 'm').deepSeekOfficial, isTrue);
      expect(OpenAiChatClient(baseUrl: 'https://api.example.com/v1', apiKey: 'k', model: 'deepseek-flash').deepSeekOfficial, isFalse);
    });

    test('不是 DeepSeek：请求里既没有 thinking 也没有 reasoning_content', () async {
      final runner = await runnerFor([
        ScriptedReply(reasoning: '想一想。', calls: [ScriptedCall('list_files', '{}')]),
        ScriptedReply(text: '好。'),
      ]);
      await runner.send('看').toList();
      expect(server!.requests.every((r) => !r.containsKey('thinking')), isTrue);
      expect(sentMessages(1).every((m) => !m.containsKey('reasoning_content') && !m.containsKey('_reasoning')), isTrue);
    });
  });

  group('待办清单', () {
    test('解析：三种状态；completed 当 done；不合规矩的报清楚', () {
      final todos = parseTodos({
        'items': [
          {'text': '读代码', 'status': 'completed'},
          {'text': '改样式', 'status': 'in_progress'},
          {'text': '跑测试'},
        ],
      });
      expect(todos.map((t) => t.status), [TodoStatus.done, TodoStatus.inProgress, TodoStatus.pending]);
      expect(() => parseTodos({'items': 'x'}), throwsA(isA<ToolArgError>()));
      expect(
        () => parseTodos({
          'items': [
            {'text': ' '},
          ],
        }),
        throwsA(isA<ToolArgError>().having((e) => e.message, 'message', contains('第 1 项'))),
      );
      expect(
        () => parseTodos({
          'items': [
            {'text': 'a', 'status': 'doing'},
          ],
        }),
        throwsA(isA<ToolArgError>()),
      );
      expect(
        () => parseTodos({
          'items': [
            {'text': 'a', 'status': 'in_progress'},
            {'text': 'b', 'status': 'in_progress'},
          ],
        }),
        throwsA(isA<ToolArgError>().having((e) => e.message, 'message', contains('只能有一项'))),
      );
      expect(
        () => parseTodos({
          'items': List.filled(kMaxTodos + 1, {'text': 'a'}),
        }),
        throwsA(isA<ToolArgError>()),
      );
    });

    test('工具：计划模式、仅可查看下也能用（只是记一笔）；出错回给模型', () async {
      final box = AgentToolbox(
        guard: guard,
        runner: shell,
        requestApproval: (_) async => false,
        autoApprove: () => false,
        permission: () => PermissionLevel.view,
        planMode: () => true,
        extras: [todoTool()],
      );
      final ok = await box.execute('update_todos', {
        'items': [
          {'text': '读代码', 'status': 'done'},
          {'text': '改样式', 'status': 'in_progress'},
        ],
      });
      expect(ok.ok, isTrue);
      expect(ok.text, allOf(contains('2 项'), contains('已完成 1 项'), contains('改样式')));
      final bad = await box.execute('update_todos', {'x': 1});
      expect(bad.ok, isFalse);
      // 写文件仍然被挡：待办工具没有放松任何权限
      expect((await box.execute('write_file', {'path': 'a', 'content': 'b'})).ok, isFalse);
    });

    test('latestTodos：取这一轮最近一次成功的；用户发了新消息就没有了；失败的、进行中的不算', () {
      String args(String status) => jsonEncode({
        'items': [
          {'text': '甲', 'status': status},
        ],
      });
      final first = ToolItem('1', 'update_todos', args('pending'), result: 'ok');
      final second = ToolItem('2', 'update_todos', args('done'), result: 'ok');
      expect(latestTodos([const UserItem('做'), first, second])!.single.status, TodoStatus.done);
      expect(latestTodos([const UserItem('做'), first, const ToolItem('3', 'update_todos', '{bad', result: '错误', ok: false)])!.single.status, TodoStatus.pending);
      expect(latestTodos([const UserItem('做'), first, ToolItem('4', 'update_todos', args('done'))])!.single.status, TodoStatus.pending);
      expect(latestTodos([const UserItem('做'), first, const UserItem('下一件')]), isNull);
      expect(latestTodos(const []), isNull);
    });
  });
}
