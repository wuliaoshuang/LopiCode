import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/agent/agent_runner.dart';
import 'package:lopicode/agent/agent_tools.dart';
import 'package:lopicode/agent/chat_client.dart';
import 'package:lopicode/agent/command_runner.dart';
import 'package:lopicode/core/path_guard.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:path/path.dart' as p;

import 'support/fake_model_server.dart';

/// 记录被执行的命令，不真的跑。
class RecordingRunner implements CommandRunner {
  final List<String> commands = [];
  @override
  String get description => 'test';
  @override
  Future<CommandResult> run(String command, {required String workingDirectory, Duration timeout = Duration.zero}) async {
    commands.add(command);
    return CommandResult(exitCode: 0, output: 'ran: $command');
  }
}

void main() {
  late Directory tmp;
  late PathGuard guard;
  late RecordingRunner shell;
  late List<ApprovalRequest> asked;
  late bool approveAnswer;
  late bool autoApprove;
  FakeModelServer? server;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('lopi_agent_');
    Directory(p.join(tmp.path, 'proj')).createSync();
    File(p.join(tmp.path, 'outside.txt')).writeAsStringSync('TOP SECRET');
    File(p.join(tmp.path, 'proj', 'index.html')).writeAsStringSync('<h1>hi</h1>');
    guard = PathGuard(p.join(tmp.path, 'proj'));
    shell = RecordingRunner();
    asked = [];
    approveAnswer = false;
    autoApprove = false;
  });
  tearDown(() async {
    await server?.stop();
    server = null;
    tmp.deleteSync(recursive: true);
  });

  AgentToolbox toolbox() => AgentToolbox(
    guard: guard,
    runner: shell,
    requestApproval: (r) async {
      asked.add(r);
      return approveAnswer;
    },
    autoApprove: () => autoApprove,
  );

  Future<AgentRunner> runnerFor(List<ScriptedReply> script, {ScriptedReply? fallback, int maxRounds = 12}) async {
    server = FakeModelServer(script, fallback: fallback);
    await server!.start();
    return AgentRunner(
      client: OpenAiChatClient(baseUrl: server!.baseUrl, apiKey: 'sk-test-key', model: 'fake-model'),
      toolbox: toolbox(),
      maxRounds: maxRounds,
    );
  }

  List<ToolFinished> finished(List<AgentEvent> events) => events.whereType<ToolFinished>().toList();

  test('正常流程：流式文字 + 工具调用 + 结果回填', () async {
    final runner = await runnerFor([
      ScriptedReply(text: '我先看看。', calls: [ScriptedCall('list_files', '{}'), ScriptedCall('read_file', '{"path":"index.html"}')]),
      ScriptedReply(calls: [ScriptedCall('write_file', jsonEncode({'path': 'css/a.css', 'content': 'body{color:red}'}))]),
      ScriptedReply(text: '改好了。'),
    ]);
    final events = await runner.send('帮我加个样式').toList();

    // 流式文字被拼起来
    expect(events.whereType<AssistantDelta>().map((e) => e.text).join(), '我先看看。改好了。');
    final done = finished(events);
    expect(done.map((e) => e.name), ['list_files', 'read_file', 'write_file']);
    expect(done[0].outcome.text, contains('index.html'));
    expect(done[1].outcome.text, '<h1>hi</h1>');
    expect(File(p.join(guard.root, 'css', 'a.css')).readAsStringSync(), 'body{color:red}');
    expect(asked, isEmpty, reason: '读写文件不需要确认');

    // 请求格式：stream、tools、Bearer 头
    final first = server!.requests.first;
    expect(first['stream'], true);
    expect(first['model'], 'fake-model');
    expect((first['tools'] as List).map((t) => (t as Map)['function']['name']),
        containsAll(['list_files', 'read_file', 'write_file', 'delete_file', 'run_command', 'lowcode_get_page', 'lowcode_update_page']));
    expect(server!.authHeaders.first, 'Bearer sk-test-key');

    // 第二次请求带上了 assistant.tool_calls 和对应的 tool 消息
    final second = server!.requests[1]['messages'] as List;
    expect(second.first['role'], 'system');
    final assistant = second.firstWhere((m) => m['role'] == 'assistant') as Map;
    final calls = assistant['tool_calls'] as List;
    expect(calls.length, 2);
    expect(calls[1]['function']['arguments'], '{"path":"index.html"}');
    final toolMsgs = second.where((m) => m['role'] == 'tool').toList();
    expect(toolMsgs.map((m) => m['tool_call_id']), calls.map((c) => c['id']));
    expect(server!.requests.length, 3);
  });

  test('强制场景：模型想读写项目目录以外的文件 → 被代码拦下', () async {
    final runner = await runnerFor([
      ScriptedReply(calls: [
        ScriptedCall('read_file', '{"path":"../outside.txt"}'),
        ScriptedCall('read_file', jsonEncode({'path': p.join(tmp.path, 'outside.txt')})),
        ScriptedCall('write_file', '{"path":"../../evil.sh","content":"rm -rf /"}'),
        ScriptedCall('write_file', '{"path":"/tmp/lopi_evil.txt","content":"x"}'),
        ScriptedCall('delete_file', '{"path":"../outside.txt"}'),
        ScriptedCall('list_files', '{"path":".."}'),
        ScriptedCall('read_file', '{"path":".lopicode/chat.json"}'),
      ]),
      ScriptedReply(text: '好吧。'),
    ]);
    approveAnswer = true; // 即使用户会点允许，越界删除也不该走到确认那一步
    final done = finished(await runner.send('读一下上级目录').toList());
    expect(done.length, 7);
    for (final d in done) {
      expect(d.outcome.ok, isFalse, reason: d.name);
      expect(d.outcome.text, startsWith('错误'), reason: d.name);
      expect(d.outcome.text, isNot(contains('TOP SECRET')));
    }
    expect(asked, isEmpty, reason: '越界请求不应该弹确认卡');
    expect(File(p.join(tmp.path, 'outside.txt')).readAsStringSync(), 'TOP SECRET');
    expect(File(p.join(tmp.path, 'evil.sh')).existsSync(), isFalse);
    expect(File('/tmp/lopi_evil.txt').existsSync(), isFalse);
    // 错误作为 tool 结果回给了模型，对话继续
    final second = server!.requests[1]['messages'] as List;
    expect(second.where((m) => m['role'] == 'tool').length, 7);
  });

  test('强制场景：模型停不下来 → 到轮次上限由代码停下', () async {
    final runner = await runnerFor(
      [],
      fallback: ScriptedReply(calls: [ScriptedCall('list_files', '{}')]),
      maxRounds: 4,
    );
    final events = await runner.send('一直干').toList();
    expect(server!.requests.length, 4, reason: '最多调 4 次模型');
    expect(finished(events).length, 4);
    expect(events.last, isA<AgentNotice>());
    expect((events.last as AgentNotice).text, contains('上限'));
    // 历史仍然合法：每个 tool_call 都有 tool 结果
    final callIds = [
      for (final m in runner.messages.where((m) => m['role'] == 'assistant'))
        for (final c in (m['tool_calls'] as List? ?? const [])) c['id'],
    ];
    final resultIds = runner.messages.where((m) => m['role'] == 'tool').map((m) => m['tool_call_id']).toList();
    expect(resultIds, callIds);
  });

  test('强制场景：命令和删除没有用户同意就不执行', () async {
    final runner = await runnerFor([
      ScriptedReply(calls: [
        ScriptedCall('run_command', '{"command":"rm -rf ."}'),
        ScriptedCall('delete_file', '{"path":"index.html"}'),
      ]),
      ScriptedReply(text: '明白，不执行了。'),
    ]);
    approveAnswer = false;
    final done = finished(await runner.send('清理一下').toList());
    expect(asked.map((a) => a.tool), ['run_command', 'delete_file']);
    expect(asked.first.detail, 'rm -rf .');
    expect(done.every((d) => d.outcome.denied && !d.outcome.ok), isTrue);
    expect(shell.commands, isEmpty);
    expect(File(p.join(guard.root, 'index.html')).existsSync(), isTrue);
    final toolMsgs = (server!.requests[1]['messages'] as List).where((m) => m['role'] == 'tool').toList();
    expect(toolMsgs.first['content'], contains('拒绝'));
  });

  test('用户点了允许才执行；开了自动批准就不再问', () async {
    var runner = await runnerFor([
      ScriptedReply(calls: [ScriptedCall('run_command', '{"command":"ls"}'), ScriptedCall('delete_file', '{"path":"index.html"}')]),
      ScriptedReply(text: 'ok'),
    ]);
    approveAnswer = true;
    var done = finished(await runner.send('go').toList());
    expect(asked.length, 2);
    expect(shell.commands, ['ls']);
    expect(done.first.outcome.text, contains('ran: ls'));
    expect(File(p.join(guard.root, 'index.html')).existsSync(), isFalse);
    await server!.stop();

    asked.clear();
    autoApprove = true;
    approveAnswer = false; // 不会被问到
    runner = await runnerFor([
      ScriptedReply(calls: [ScriptedCall('run_command', '{"command":"pwd"}')]),
      ScriptedReply(text: 'ok'),
    ]);
    done = finished(await runner.send('go').toList());
    expect(asked, isEmpty);
    expect(shell.commands, ['ls', 'pwd']);
  });

  test('坏参数、未知工具、缺参数都变成错误结果，不会崩', () async {
    final runner = await runnerFor([
      ScriptedReply(calls: [
        ScriptedCall('read_file', '{"path": "index.h'), // 截断的 JSON
        ScriptedCall('format_disk', '{}'),
        ScriptedCall('write_file', '{"path":"a.txt"}'), // 缺 content
        ScriptedCall('read_file', '{"path":"nope.txt"}'),
        ScriptedCall('read_file', '[1,2]'),
      ]),
      ScriptedReply(text: '抱歉。'),
    ]);
    final events = await runner.send('x').toList();
    final done = finished(events);
    expect(done.length, 5);
    expect(done.every((d) => !d.outcome.ok && d.outcome.text.startsWith('错误')), isTrue);
    expect(done[1].outcome.text, contains('format_disk'));
    expect(File(p.join(guard.root, 'a.txt')).existsSync(), isFalse);
    expect(events.whereType<AgentError>(), isEmpty);
  });

  test('低代码工具：读、更新并重新导出；坏页面不落盘', () async {
    final doc = LcDocument.starter('页面');
    await saveLowcodePage(guard, doc);
    final next = LcDocument.starter('新标题')..root.children.first.props['text'] = 'Agent 改的标题';
    final runner = await runnerFor([
      ScriptedReply(calls: [ScriptedCall('lowcode_get_page', '{}')]),
      ScriptedReply(calls: [
        ScriptedCall('lowcode_update_page', jsonEncode({'page': next.toJson()})),
        ScriptedCall('lowcode_update_page', jsonEncode({'page': {'title': 'x', 'root': {'type': 'text'}}})),
      ]),
      ScriptedReply(text: '好了'),
    ]);
    final done = finished(await runner.send('改标题').toList());
    expect(done[0].outcome.text, contains('"type": "page"'));
    expect(done[1].outcome.ok, isTrue);
    expect(done[2].outcome.ok, isFalse);
    final saved = LcDocument.parse(File(p.join(guard.root, kLowcodePageFile)).readAsStringSync());
    expect(saved.title, '新标题');
    expect(File(p.join(guard.root, 'index.html')).readAsStringSync(), contains('Agent 改的标题'));
    expect(File(p.join(guard.root, 'style.css')).existsSync(), isTrue);
  });

  test('接口报错：给出人话，不泄露 Key，用户消息撤回', () async {
    final runner = await runnerFor([
      ScriptedReply(status: 401, errorBody: '{"error":{"message":"Incorrect API key provided"}}'),
    ]);
    final events = await runner.send('hi').toList();
    final err = events.whereType<AgentError>().single;
    expect(err.text, contains('401'));
    expect(err.text, contains('API Key'));
    expect(err.text, isNot(contains('sk-test-key')));
    expect(runner.messages, isEmpty);
  });

  test('连不上服务器：报错里没有 Key', () async {
    final runner = AgentRunner(
      client: OpenAiChatClient(baseUrl: 'http://127.0.0.1:1/v1', apiKey: 'sk-test-key', model: 'm'),
      toolbox: toolbox(),
    );
    final events = await runner.send('hi').toList();
    final err = events.whereType<AgentError>().single;
    expect(err.text, contains('连不上'));
    expect(err.text, isNot(contains('sk-test-key')));
  });

  test('没配置模型时直接提示去设置', () async {
    final runner = AgentRunner(client: OpenAiChatClient(baseUrl: '', apiKey: '', model: ''), toolbox: toolbox());
    final events = await runner.send('hi').toList();
    expect(events.whereType<AgentError>().single.text, contains('设置'));
  });

  test('停止：取消后不再执行后面的工具', () async {
    final runner = await runnerFor([
      ScriptedReply(calls: [ScriptedCall('run_command', '{"command":"a"}'), ScriptedCall('run_command', '{"command":"b"}')]),
      ScriptedReply(text: '不该走到这'),
    ]);
    autoApprove = true;
    final events = <AgentEvent>[];
    await for (final e in runner.send('go')) {
      events.add(e);
      if (e is ToolFinished) runner.cancel();
    }
    expect(shell.commands, ['a']);
    expect(server!.requests.length, 1);
    expect(runner.messages.where((m) => m['role'] == 'tool').length, 2);
    expect(events.last, isA<AgentNotice>());
  });

  test('baseUrl 规范化', () {
    expect(OpenAiChatClient.normalizeBaseUrl(' https://api.x.com/v1/ '), 'https://api.x.com/v1');
    expect(OpenAiChatClient.normalizeBaseUrl('https://api.x.com/v1/chat/completions'), 'https://api.x.com/v1');
  });

  test('真实 shell 执行器：能跑命令、带超时', () async {
    final echoed = StringBuffer();
    final real = LocalShellRunner(onOutput: echoed.write);
    final ok = await real.run('echo hello && pwd', workingDirectory: guard.root);
    expect(ok.exitCode, 0);
    expect(ok.output, contains('hello'));
    expect(ok.output, contains('proj'));
    expect(echoed.toString(), contains('hello'));
    final fail = await real.run('exit 3', workingDirectory: guard.root);
    expect(fail.exitCode, 3);
    final slow = await real.run('sleep 5', workingDirectory: guard.root, timeout: const Duration(milliseconds: 300));
    expect(slow.timedOut, isTrue);
  });
}
