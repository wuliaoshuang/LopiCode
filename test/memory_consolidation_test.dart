// 后台整理记忆（lib/session/memory_consolidation.dart）：默认不发请求；打开后只在符合条件时发一次；
// 额度满不发；失败不影响对话；用量记进那一轮并标成“整理记忆”；出错 / 被停止 / 等确认的轮次、子代理、自动化任务都不整理。
// 不调用任何真实接口：模型走本机假服务器（127.0.0.1）或脚本客户端。
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/agent/automation.dart';
import 'package:lopicode/agent/memory_store.dart';
import 'package:lopicode/agent/model_config.dart';
import 'package:lopicode/agent/usage.dart';
import 'package:lopicode/core/crash_log.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/safe_file.dart';
import 'package:lopicode/core/stores.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/session/memory_consolidation.dart';
import 'package:path/path.dart' as p;

import 'agent_test.dart' show RecordingRunner;
import 'quota_usage_test.dart' show FakeBalance;
import 'session_system_test.dart' show RoutingClient, Turn, reply, use, firstUser, hasToolResult, waitFor;
import 'support/fake_model_server.dart';
import 'support/harness.dart';

const _marker = '记忆整理员';

/// 模型按约定格式回的整理结果。
String items(List<Map<String, String>> list) => jsonEncode({'items': list});

void main() {
  setUp(CrashLog.instance.resetForTest);

  group('纯函数', () {
    test('对话记录：只留用户和助手说的话，脱敏，太长留结尾', () {
      final key = 'sk-${'q1w2e3r4' * 3}';
      final t = consolidationTranscript([
        {'role': 'system', 'content': '系统提示词'},
        {'role': 'user', 'content': '密钥是 $key，帮我部署'},
        {'role': 'assistant', 'content': '', 'tool_calls': <Object>[]},
        {'role': 'tool', 'content': '工具结果一大段'},
        {'role': 'assistant', 'content': '部署好了'},
        {'role': 'user', 'content': '摘要', '_compact': true},
      ]);
      expect(t, contains('用户'));
      expect(t, contains('帮我部署'));
      expect(t, contains('助手'));
      expect(t, contains('部署好了'));
      expect(t, isNot(contains(key)));
      expect(t, isNot(contains('系统提示词')));
      expect(t, isNot(contains('工具结果')));
      expect(t, isNot(contains('摘要')));

      final long = consolidationTranscript([
        for (var i = 0; i < 40; i++) {'role': 'user', 'content': '第 $i 条 ${'字' * 1500}'},
      ]);
      expect(long.length, lessThanOrEqualTo(kConsolidateMaxTranscriptChars + 20));
      expect(long, contains('第 39 条'));
      expect(long, isNot(contains('第 0 条')));
    });

    test('请求里带现有的记忆（好让模型合并去重），并写明不要记密钥', () {
      final e = MemoryEntry(scope: MemoryScope.global, id: '甲', title: '回答的语言', body: '用简体中文', updatedAt: DateTime(2026));
      final r = consolidationRequest([e], const [], '对话');
      final text = jsonEncode(r);
      expect(text, contains(_marker));
      expect(text, contains('回答的语言'));
      expect(text, contains('不要记密钥'));
      expect(jsonEncode(consolidationRequest([e], null, '对话')), contains('只考虑 global'));
    });

    test('解析模型的回答：外面包了代码块、带了废话也认；形状不对的条目跳过；整个读不懂是 null', () {
      final ok = parseConsolidation(
        '好的，结果如下：\n```json\n${items([
          {'scope': 'global', 'title': '甲', 'content': '一'},
          {'scope': 'project', 'title': '乙', 'content': '二'},
          {'scope': '火星', 'title': '丙', 'content': '三'},
          {'scope': 'global', 'title': '', 'content': '没标题'},
        ])}\n```',
      );
      expect(ok!.map((i) => (i.scope, i.title)), [(MemoryScope.global, '甲'), (MemoryScope.project, '乙')]);
      expect(parseConsolidation('{"items": []}'), isEmpty);
      expect(parseConsolidation('我觉得没什么可记的'), isNull);
      expect(parseConsolidation('{"items": "不是列表"}'), isNull);
      expect(parseConsolidation('{半截'), isNull);
      expect(parseConsolidation('{"items": [1, "x", null, {"scope": "global", "title": 3, "content": []}]}'), isEmpty);
      final many = parseConsolidation(
        items([
          for (var i = 0; i < 9; i++) {'scope': 'global', 'title': '第 $i', 'content': '内容'},
        ]),
      );
      expect(many, hasLength(kConsolidateMaxItems));
    });
  });

  group('走本机假模型服务器', () {
    late TestEnv env;
    late Project project;
    late ProjectSession session;
    late FakeModelServer server;
    late DateTime clock;

    Future<void> boot(List<ScriptedReply> script) async {
      server = FakeModelServer(script);
      await server.start();
      env = await TestEnv.create();
      final ch = await env.services.models.upsert(
        name: '本机假服务器',
        protocol: ChatProtocol.openaiChat,
        baseUrl: server.baseUrl,
        apiKey: 'test-only',
        models: [ModelSpec(id: 'fake-model', priceHit: 1, priceMiss: 2, priceOutput: 8)],
      );
      project = await env.services.projects.create('测试工作区', ProjectTemplate.web);
      session = ProjectSession(env.services, project, headless: true);
      session.commandRunnerFactory = RecordingRunner.new;
      await session.loadChat();
      await session.setModel(ModelSelection(ch.id, 'fake-model'));
      clock = DateTime(2026, 11, 25, 9);
      env.services.memory.now = () => clock;
    }

    tearDown(() async {
      await env.services.memory.idle();
      session.dispose();
      await env.dispose();
      await server.stop();
    });

    AppMemory memory() => env.services.memory;
    Future<void> turnOn() => env.services.settings.set(SettingKeys.memoryAutoConsolidate, true);
    Future<void> say(String text) async {
      await session.sendToAgent(text);
      await memory().idle();
    }

    List<Map<String, dynamic>> consolidations() => [
      for (final r in server.requests)
        if (jsonEncode(r['messages']).contains(_marker)) r,
    ];

    test('默认关：聊多少轮都不多发请求', () async {
      await boot([for (var i = 0; i < 5; i++) ScriptedReply(text: '回答 $i')]);
      expect(memory().autoConsolidate, isFalse);
      for (var i = 0; i < 5; i++) {
        await say('问题 $i');
      }
      expect(server.requests, hasLength(5), reason: '一轮一次，没有多出来的');
      expect(consolidations(), isEmpty);
      expect(memory().global.entries, isEmpty);
    });

    test('打开后：消息不够不发；够了发一次，记进记忆、聊天里说一声、用量记进那一轮并标成“整理记忆”；间隔内不再发', () async {
      final key = 'sk-${'m5n6b7v8' * 3}';
      await boot([
        ScriptedReply(text: '好的，以后提交说明用中文。', usage: {'prompt_tokens': 100, 'completion_tokens': 10, 'total_tokens': 110}),
        ScriptedReply(text: '记下了。', usage: {'prompt_tokens': 120, 'completion_tokens': 10, 'total_tokens': 130}),
        ScriptedReply(text: '好。', usage: {'prompt_tokens': 140, 'completion_tokens': 10, 'total_tokens': 150}),
        // 第 4 次请求＝整理
        ScriptedReply(
          text: items([
            {'scope': 'global', 'title': '提交说明的语言', 'content': '提交说明一律用中文写。'},
            {'scope': 'project', 'title': '部署方式', 'content': '这个项目用 scp 传到服务器。'},
          ]),
          usage: {'prompt_tokens': 900, 'completion_tokens': 60, 'total_tokens': 960},
        ),
        ScriptedReply(text: '第四轮的回答', usage: {'prompt_tokens': 160, 'completion_tokens': 10, 'total_tokens': 170}),
      ]);
      await turnOn();
      await say('以后提交说明都用中文写');
      await say('这个项目部署用 scp，密钥是 $key');
      expect(consolidations(), isEmpty, reason: '才 4 条消息，不到 $kConsolidateMinMessages 条');
      await say('就这样');

      // 发了一次，而且只有一次
      expect(server.requests, hasLength(4));
      final c = consolidations().single;
      expect(c.containsKey('tools'), isFalse, reason: '整理请求不带工具');
      final body = jsonEncode(c['messages']);
      expect(body, contains('以后提交说明都用中文写'));
      expect(body, contains('部署用 scp'));
      expect(body, isNot(contains(key)), reason: '对话内容先脱敏再发');

      // 记进了记忆
      expect(memory().global.entries.single.title, '提交说明的语言');
      expect(memory().project(project).entries.single.body, '这个项目用 scp 传到服务器。');
      expect(memory().global.changes.last.by, 'auto');
      expect(File(p.join(env.tmp.path, 'memory', '提交说明的语言.md')).existsSync(), isTrue);

      // 聊天里说一声
      final notice = session.chat.whereType<NoticeItem>().last;
      expect(notice.isError, isFalse);
      expect(notice.text, contains('整理记忆：记住了 2 条'));
      expect(notice.text, contains('提交说明的语言'));

      // 用量：记在刚结束的那一轮上，标着 memory；对话累计也加上了，轮数不变
      final turnUsage = session.chat.whereType<UsageItem>().last.turn;
      final steps = turnUsage.steps.whereType<RequestStep>().toList();
      expect(steps, hasLength(2));
      expect(steps.first.request.memory, isFalse);
      expect(steps.last.request.memory, isTrue);
      expect(steps.last.request.kindNote, '（整理记忆）');
      expect(steps.last.request.usage!.input, 900);
      expect(steps.last.request.cost, isNotNull, reason: '模型填了单价就估算费用');
      final totals = session.activeConversation.usage;
      expect(totals.requests, 4);
      expect(totals.turns, 3);
      expect(totals.input, 100 + 120 + 140 + 900);
      expect(totals.output, 10 + 10 + 10 + 60);

      // 存了盘：重开还在，还标着“整理记忆”
      await pendingWrites();
      final saved = jsonDecode(File(p.join(project.dir, '.lopicode', 'chat.json')).readAsStringSync()) as List;
      final usage = (saved.last as Map)['_usage'] as Map;
      expect(jsonEncode(usage), contains('"k":"memory"'));
      final back = RequestUsage.fromJson(((usage['steps'] as List).last as Map).cast<String, dynamic>());
      expect(back.memory, isTrue);
      expect(back.compaction, isFalse);

      // 间隔内再聊：不再发
      await say('再聊一句');
      expect(server.requests, hasLength(5));
      expect(consolidations(), hasLength(1));
    });

    test('过了最小间隔，还要攒够新消息才发第二次；第二次只带上次之后的新对话', () async {
      await boot([
        for (var i = 0; i < 3; i++) ScriptedReply(text: '第一批回答 $i'),
        ScriptedReply(text: items([])),
        for (var i = 0; i < 3; i++) ScriptedReply(text: '第二批回答 $i'),
        ScriptedReply(
          text: items([
            {'scope': 'global', 'title': '甲', 'content': '一'},
          ]),
        ),
      ]);
      await turnOn();
      for (var i = 0; i < 3; i++) {
        await say('第一批问题 $i');
      }
      expect(consolidations(), hasLength(1));
      expect(session.chat.whereType<NoticeItem>(), isEmpty, reason: '没有值得记的：不出声');
      expect(memory().global.entries, isEmpty);

      clock = clock.add(kConsolidateMinInterval).add(const Duration(seconds: 1));
      await say('第二批问题 0');
      await say('第二批问题 1');
      expect(consolidations(), hasLength(1), reason: '间隔到了，但新消息才 4 条');
      await say('第二批问题 2');
      expect(consolidations(), hasLength(2));
      final second = jsonEncode(consolidations().last['messages']);
      expect(second, contains('第二批问题 0'));
      expect(second, isNot(contains('第一批问题 0')), reason: '整理过的不再重复发');
      expect(memory().global.entries.single.title, '甲');
    });

    test('间隔没到：消息再多也不发', () async {
      await boot([for (var i = 0; i < 3; i++) ScriptedReply(text: '回答 $i'), ScriptedReply(text: items([])), for (var i = 0; i < 4; i++) ScriptedReply(text: '后面的回答 $i')]);
      await turnOn();
      for (var i = 0; i < 3; i++) {
        await say('问题 $i');
      }
      clock = clock.add(kConsolidateMinInterval - const Duration(seconds: 5));
      for (var i = 0; i < 4; i++) {
        await say('后面的问题 $i');
      }
      expect(consolidations(), hasLength(1));
      expect(server.requests, hasLength(8));
    });

    test('整理请求失败（接口报 500）：对话不受影响，不出错误提示，只记一笔日志；间隔内不重试', () async {
      await boot([for (var i = 0; i < 3; i++) ScriptedReply(text: '回答 $i'), ScriptedReply(status: 500, errorBody: '{"error":{"message":"upstream exploded"}}'), ScriptedReply(text: '下一轮照常回答')]);
      await turnOn();
      for (var i = 0; i < 3; i++) {
        await say('问题 $i');
      }
      expect(server.requests, hasLength(4));
      expect(session.chat.whereType<NoticeItem>(), isEmpty, reason: '失败不打扰');
      expect(session.chat.whereType<AssistantItem>().last.text, '回答 2');
      expect(memory().global.entries, isEmpty);
      final notes = CrashLog.instance.entries.where((e) => e.source == '记忆').toList();
      expect(notes.single.fatal, isFalse);
      expect(notes.single.message, contains('没整理成'));

      await say('下一个问题');
      expect(session.chat.whereType<AssistantItem>().last.text, '下一轮照常回答');
      expect(server.requests, hasLength(5), reason: '间隔内不再去撞坏掉的接口');

      // 过了间隔再试：上次没整理成的那些对话这次补上
      server.script.add(ScriptedReply(text: '再下一轮'));
      server.script.add(ScriptedReply(text: items([])));
      clock = clock.add(kConsolidateMinInterval).add(const Duration(seconds: 1));
      await say('再问一个');
      expect(consolidations(), hasLength(2));
      expect(jsonEncode(consolidations().last['messages']), contains('问题 0'));
    });

    test('模型回的不是约定格式：什么都不写，对话照常，记一笔日志', () async {
      await boot([for (var i = 0; i < 3; i++) ScriptedReply(text: '回答 $i'), ScriptedReply(text: '我觉得你们聊得很开心！')]);
      await turnOn();
      for (var i = 0; i < 3; i++) {
        await say('问题 $i');
      }
      expect(consolidations(), hasLength(1));
      expect(memory().global.entries, isEmpty);
      expect(session.chat.whereType<NoticeItem>(), isEmpty);
      expect(CrashLog.instance.entries.where((e) => e.source == '记忆').single.message, contains('不是约定的格式'));
      // 这一次请求是真发了的：用量照记
      expect(session.chat.whereType<UsageItem>().last.turn.steps.whereType<RequestStep>().last.request.memory, isTrue);
    });

    test('模型想记一条像密钥的：那一条被拒，别的照记；超长的也被拒', () async {
      final key = 'sk-${'k1j2h3g4' * 3}';
      await boot([
        for (var i = 0; i < 3; i++) ScriptedReply(text: '回答 $i'),
        ScriptedReply(
          text: items([
            {'scope': 'global', 'title': '服务器密钥', 'content': '密钥是 $key'},
            {'scope': 'global', 'title': '太长的', 'content': '字' * (kMemoryMaxBodyChars + 1)},
            {'scope': 'global', 'title': '正常的', 'content': '回答短一点'},
          ]),
        ),
      ]);
      await turnOn();
      for (var i = 0; i < 3; i++) {
        await say('问题 $i');
      }
      expect(memory().global.entries.single.title, '正常的');
      expect(session.chat.whereType<NoticeItem>().single.text, contains('记住了 1 条'));
      final dir = Directory(p.join(env.tmp.path, 'memory'));
      for (final f in dir.listSync().whereType<File>()) {
        expect(f.readAsStringSync(), isNot(contains(key)), reason: f.path);
      }
      expect(CrashLog.instance.entries.map((e) => e.message).join('\n'), isNot(contains(key)));
    });

    test('和现有的同标题：合并成一条（改写），不另起；能在设置里撤销回原来的', () async {
      await boot([
        for (var i = 0; i < 3; i++) ScriptedReply(text: '回答 $i'),
        ScriptedReply(
          text: items([
            {'scope': 'global', 'title': '回答的风格', 'content': '回答短一点；先给结论。'},
          ]),
        ),
      ]);
      await memory().global.write('回答的风格', '回答短一点。', by: 'user');
      await turnOn();
      for (var i = 0; i < 3; i++) {
        await say('问题 $i');
      }
      expect(jsonEncode(consolidations().single['messages']), contains('回答短一点。'), reason: '现有的记忆发给了模型');
      expect(memory().global.entries.single.body, '回答短一点；先给结论。');
      await memory().global.undoLast();
      expect(memory().global.entries.single.body, '回答短一点。');
    });

    test('总开关关着：自动整理开着也不做', () async {
      await boot([for (var i = 0; i < 3; i++) ScriptedReply(text: '回答 $i')]);
      await turnOn();
      await env.services.settings.set(SettingKeys.memoryEnabled, false);
      for (var i = 0; i < 3; i++) {
        await say('问题 $i');
      }
      expect(server.requests, hasLength(3));
    });

    test('这一轮出错了（接口报错）：不整理', () async {
      await boot([ScriptedReply(text: '回答 0'), ScriptedReply(text: '回答 1'), ScriptedReply(text: '回答 2'), ScriptedReply(text: items([])), ScriptedReply(status: 400)]);
      await turnOn();
      // 先让“消息够了”这个条件成立，但把间隔卡住；然后放开间隔，让出错的那一轮来触发
      for (var i = 0; i < 3; i++) {
        await say('问题 $i');
      }
      expect(consolidations(), hasLength(1));
      clock = clock.add(const Duration(hours: 1));
      final before = server.requests.length;
      await say('这一轮会出错');
      expect(session.chat.whereType<NoticeItem>().last.isError, isTrue);
      expect(server.requests, hasLength(before + 1), reason: '只有出错的那一次，没有整理');
      expect(consolidations(), hasLength(1));
    });

    test('进度文件 memory-state.json 坏了：不崩，当作从没整理过', () async {
      await boot([for (var i = 0; i < 3; i++) ScriptedReply(text: '回答 $i'), ScriptedReply(text: items([]))]);
      await turnOn();
      final state = File(p.join(project.dir, '.lopicode', 'memory-state.json'));
      state.writeAsStringSync('{"at": "不是数字", "seen": [1, 2');
      for (var i = 0; i < 3; i++) {
        await say('问题 $i');
      }
      expect(consolidations(), hasLength(1));
      expect(state.parent.listSync().where((e) => p.basename(e.path).startsWith('memory-state.json.bad-')), isNotEmpty);
      await pendingWrites();
      final saved = jsonDecode(state.readAsStringSync()) as Map;
      expect(saved['at'], clock.millisecondsSinceEpoch);
      expect((saved['seen'] as Map)['main'], isA<int>());
    });

    test('进度存了盘：重开工作区后，间隔和“整理到哪了”都还算数', () async {
      await boot([for (var i = 0; i < 3; i++) ScriptedReply(text: '回答 $i'), ScriptedReply(text: items([])), for (var i = 0; i < 3; i++) ScriptedReply(text: '重开后的回答 $i')]);
      await turnOn();
      for (var i = 0; i < 3; i++) {
        await say('问题 $i');
      }
      expect(consolidations(), hasLength(1));
      session.dispose();
      session = ProjectSession(env.services, project, headless: true);
      session.commandRunnerFactory = RecordingRunner.new;
      await session.loadChat();
      for (var i = 0; i < 3; i++) {
        await say('重开后的问题 $i');
      }
      expect(consolidations(), hasLength(1), reason: '离上次不到 ${kConsolidateMinInterval.inMinutes} 分钟');
    });
  });

  group('走脚本客户端（要卡时机的几种情况）', () {
    late TestEnv env;
    late FakeBalance fake;
    late Project project;
    late ProjectSession session;
    late Channel ds;
    late List<({List<Map<String, dynamic>> messages, List<String> tools})> log;
    Turn turn = (_, _) => reply('好的。');
    Turn consolidate = (_, _) => reply(items([]));

    setUp(() async {
      log = [];
      turn = (_, _) => reply('好的。');
      consolidate = (_, _) => reply(items([]));
      fake = FakeBalance();
      env = await TestEnv.create(chatClient: () => RoutingClient((m, t) => jsonEncode(m).contains(_marker) ? consolidate(m, t) : turn(m, t), log), quotaHttp: fake.client);
      ds = await env.services.models.upsert(
        name: 'DeepSeek',
        protocol: ChatProtocol.openaiChat,
        baseUrl: 'https://api.deepseek.com',
        apiKey: 'test-only',
        models: [ModelSpec(id: 'deepseek-chat')],
      );
      project = await env.services.projects.create('测试工作区', ProjectTemplate.web);
      session = ProjectSession(env.services, project, headless: true);
      session.commandRunnerFactory = RecordingRunner.new;
      await session.loadChat();
      await session.setModel(ModelSelection(ds.id, 'deepseek-chat'));
      await env.services.settings.set(SettingKeys.memoryAutoConsolidate, true);
    });
    tearDown(() async {
      await env.services.memory.idle();
      if (!session.disposed) session.dispose();
      await env.dispose();
    });

    AppMemory memory() => env.services.memory;
    int consolidations() => log.where((l) => jsonEncode(l.messages).contains(_marker)).length;
    Future<void> chat(int rounds) async {
      for (var i = 0; i < rounds; i++) {
        await session.sendToAgent('问题 $i');
        await memory().idle();
      }
    }

    test('对照：条件都满足时会发一次（下面几条都是在这个基础上变一个条件）', () async {
      await chat(3);
      expect(consolidations(), 1);
    });

    test('额度到顶：整理请求不发；对话里不多出报错', () async {
      await env.services.quota.setLimit(ds, limit: 10, currency: 'CNY');
      await chat(2);
      // 第三轮的回答发出去之后额度到顶
      turn = (m, t) async {
        fake.cny = 85;
        await env.services.quota.refresh(ds, force: true);
        return reply('第三轮的回答');
      };
      await session.sendToAgent('第三个问题');
      await memory().idle();
      expect(env.services.quota.quotaOf(ds.id)!.reached, isTrue);
      expect(session.chat.whereType<AssistantItem>().last.text, '第三轮的回答');
      expect(consolidations(), 0, reason: '额度到顶：这次多出来的请求被拦住了');
      expect(log, hasLength(3));
      expect(session.chat.whereType<UsageItem>().last.turn.steps.whereType<RequestStep>(), hasLength(1), reason: '没发出去就不记用量');
      expect(CrashLog.instance.entries.where((e) => e.source == '记忆').single.message, contains('没整理成'));
    });

    test('被停止的轮次不整理', () async {
      await chat(2);
      final gate = Completer<void>();
      turn = (m, t) async {
        await gate.future;
        return reply('来不及说完');
      };
      final sending = session.sendToAgent('第三个问题');
      await waitFor(() => log.length == 3);
      session.stopAgent();
      gate.complete();
      await sending;
      await memory().idle();
      expect(consolidations(), 0);
    });

    test('等确认的时候被停下（确认卡没人点）：不整理', () async {
      await chat(2);
      turn = (m, t) => hasToolResult(m) && jsonEncode(m.last).contains('拒绝') ? reply('好吧') : use('run_command', {'command': 'ls'});
      final sending = session.sendToAgent('跑个命令');
      await waitFor(() => session.pendingApproval != null, what: '确认卡');
      expect(consolidations(), 0, reason: '还在等确认：这一轮没结束');
      session.stopAgent();
      await sending;
      await memory().idle();
      expect(consolidations(), 0);
    });

    test('自动化任务（没人在场）不整理', () async {
      await chat(2);
      final before = log.length;
      turn = (_, _) => reply('巡检完了，${'一切正常。' * 3}');
      await session.runAutomation(
        Automation(
          id: 'a1',
          title: '每日巡检',
          instruction: '看看有没有问题',
          workspaceId: project.id,
          rule: TimeRule(kind: RuleKind.daily, tzOffsetMinutes: 480),
        ),
      );
      await memory().idle();
      expect(log.length, before + 1);
      expect(consolidations(), 0);
    });

    test('子代理那一轮不整理；主对话结束时照常整理一次', () async {
      await chat(2);
      turn = (m, t) {
        if (firstUser(m).contains('子任务')) return reply('子做完');
        return hasToolResult(m) ? reply('完') : use('spawn_agent', {'name': '子', 'task': '子任务：随便做点什么'});
      };
      await session.sendToAgent('派个子代理');
      await memory().idle();
      expect(consolidations(), 1);
      final sent = jsonEncode(log.firstWhere((l) => jsonEncode(l.messages).contains(_marker)).messages);
      expect(sent, contains('派个子代理'), reason: '整理的是主对话');
    });

    test('整理到一半工作区关了：回来的结果丢掉，不写记忆', () async {
      final gate = Completer<void>();
      final asked = Completer<void>();
      consolidate = (m, t) async {
        asked.complete();
        await gate.future;
        return reply(
          items([
            {'scope': 'global', 'title': '关了以后才回来', 'content': '不该写进去'},
          ]),
        );
      };
      for (var i = 0; i < 3; i++) {
        await session.sendToAgent('问题 $i');
      }
      await asked.future;
      session.dispose();
      gate.complete();
      await memory().idle();
      await memory().global.load();
      expect(memory().global.entries, isEmpty);
    });

    test('同一时间只做一个：上一次整理还没回来，这一轮结束不再发', () async {
      final gate = Completer<void>();
      consolidate = (m, t) async {
        await gate.future;
        return reply(items([]));
      };
      for (var i = 0; i < 5; i++) {
        await session.sendToAgent('问题 $i');
      }
      expect(consolidations(), 1);
      gate.complete();
      await memory().idle();
      expect(consolidations(), 1);
    });

    test('整理的时候主对话也在写同一条记忆：两边排队，最后只有一个文件', () async {
      consolidate = (m, t) => reply(
        items([
          {'scope': 'global', 'title': '同一条', 'content': '后台整理写的'},
        ]),
      );
      await chat(2);
      var called = false;
      turn = (m, t) {
        if (called) return reply('记好了');
        called = true;
        return use('memory_write', {'scope': 'global', 'title': '同一条', 'content': '主对话写的'});
      };
      await session.sendToAgent('记一下');
      await memory().idle();
      await memory().global.load();
      expect(memory().global.entries, hasLength(1));
      expect(Directory(p.join(env.tmp.path, 'memory')).listSync().where((e) => e.path.endsWith('.md')), hasLength(1));
    });
  });
}
