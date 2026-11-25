// MCP 工具接进真实会话后的规矩（不带界面）：每次都问、拒绝不调用、只读 / 计划模式没有工具、无人值守自动拒绝、
// “本对话都允许”只管一个服务器的一个工具、子代理和上级一样、超长结果另存、没配置时一点痕迹都没有、
// 令牌不进任何存盘文件 / 日志 / 报错 / 发给模型的内容。
//
// 服务器是本机假服务器（test/support/fake_mcp_server.dart，只绑 127.0.0.1），不发任何外网请求。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/agent/agent_tools.dart';
import 'package:lopicode/agent/automation.dart';
import 'package:lopicode/agent/mcp/mcp_config.dart';
import 'package:lopicode/agent/mcp/mcp_models.dart';
import 'package:lopicode/agent/mcp/mcp_tools.dart';
import 'package:lopicode/core/crash_log.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/safe_file.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/state/mcp_state.dart';

import 'agent_test.dart' show RecordingRunner;
import 'session_system_test.dart' show RoutingClient, Turn, firstSystem, reply, toolResults, use, waitFor;
import 'support/fake_mcp_server.dart';
import 'support/harness.dart';

const token = 'Bearer mcp-secret-token-9f8e7d6c5b4a';

void main() {
  late TestEnv env;
  late Project project;
  late ProjectSession session;
  late RecordingRunner shell;
  late FakeMcpServer server;
  late List<({List<Map<String, dynamic>> messages, List<String> tools})> log;
  Turn turn = (_, _) => reply('好的。');

  McpNotifier mcp() => env.services.container.read(mcpProvider.notifier);

  /// 加一个指向假服务器的 MCP 服务器，并读好工具清单。
  Future<McpServerConfig> addServer({String name = 'docs', FakeMcpServer? to, Map<String, String?> headers = const {}}) async {
    final target = to ?? server;
    final probe = await mcp().probe(url: '${target.url}', headers: headers);
    expect(probe.result.ok, isTrue, reason: probe.result.title);
    return mcp().upsert(name: name, url: '${target.url}', headers: headers, tools: probe.tools, mode: probe.mode);
  }

  setUp(() async {
    CrashLog.instance.resetForTest();
    turn = (_, _) => reply('好的。');
    log = [];
    server = await FakeMcpServer.start(FakeMcpKind.legacy);
    env = await TestEnv.create(chatClient: () => RoutingClient((m, t) => turn(m, t), log));
    project = await env.services.projects.create('测试工作区', ProjectTemplate.web);
    session = ProjectSession(env.services, project, headless: true);
    shell = RecordingRunner();
    session.commandRunnerFactory = () => shell;
    await session.loadChat();
  });
  tearDown(() async {
    session.dispose();
    await env.dispose();
    await server.close();
  });

  group('起名字', () {
    McpServerConfig cfg(String id, String name, List<String> tools) => McpServerConfig(
      id: id,
      name: name,
      url: 'https://example.com/mcp',
      tools: [
        for (final t in tools) McpToolInfo(name: t, description: '说明', inputSchema: const {'type': 'object'}),
      ],
    );

    test('统一成 mcp__服务器__工具；怪字符换掉；中文名的服务器用编号顶上；长度不超', () {
      final out = mcpExposedTools([
        cfg('a1b2c3', 'My Docs!', ['search.items', 'get user']),
        cfg('z9y8x7', '知识库', ['查询']),
        cfg('q1', 'long', ['x' * 120]),
      ]);
      final names = [for (final t in out) t.exposedName];
      expect(names.take(2), ['mcp__My_Docs__search_items', 'mcp__My_Docs__get_user']);
      expect(names[2], startsWith('mcp__sz9y8x7__'));
      for (final n in names) {
        expect(n, matches(RegExp(r'^[A-Za-z0-9_-]+$')), reason: n);
        expect(n.length, lessThanOrEqualTo(kMcpToolNameChars));
      }
      expect(out[2].tool.name, '查询', reason: '调用时仍用服务器给的原名');
    });

    test('重名（两个服务器同名、合法化后撞车、和内置工具撞车）：各自得到不同的名字，一个都不丢', () {
      final out = mcpExposedTools(
        [
          cfg('s1', 'docs', ['a.b', 'a_b']),
          cfg('s2', 'docs', ['a.b']),
        ],
        taken: {'mcp__docs__a_b'},
      );
      final names = [for (final t in out) t.exposedName];
      expect(names.length, 3);
      expect(names.toSet().length, 3, reason: '$names');
      expect(names, isNot(contains('mcp__docs__a_b')));
      expect(names.every((n) => n.startsWith(kMcpToolPrefix)), isTrue);
    });

    test('关掉的服务器、关掉的工具不出现', () {
      final off = cfg('s1', 'off', ['a']).copyWith(enabled: false);
      final part = cfg('s2', 'part', ['a', 'b']).copyWith(disabledTools: {'a'});
      expect(
        [
          for (final t in mcpExposedTools([off, part])) t.exposedName,
        ],
        ['mcp__part__b'],
      );
    });
  });

  group('没配置时没有痕迹', () {
    test('一个服务器都没有：工具清单、系统提示词、对话里都没有 MCP；不联网', () async {
      await session.sendToAgent('你好');
      expect(log.single.tools.where((t) => t.startsWith('mcp__')), isEmpty);
      expect(firstSystem(log.single.messages), isNot(contains('MCP')));
      expect(firstSystem(log.single.messages), isNot(contains('mcp__')));
      expect(session.chat.whereType<NoticeItem>(), isEmpty);
      expect(server.seen, isEmpty);
      expect(session.mcpAllowCount, 0);
    });

    test('服务器关着：和没有一样', () async {
      final s = await addServer();
      await mcp().setEnabled(s.id, false);
      final before = server.seen.length;
      await session.sendToAgent('你好');
      expect(log.single.tools.where((t) => t.startsWith('mcp__')), isEmpty);
      expect(firstSystem(log.single.messages), isNot(contains('mcp__')));
      expect(server.seen.length, before, reason: '关着的服务器不联网');
    });
  });

  group('每次调用都要确认', () {
    test('模型看得到工具（带服务器前缀、说明里写明是外部的）；系统提示词说明返回内容是外部数据', () async {
      await addServer();
      await session.sendToAgent('你好');
      expect(log.single.tools, containsAll(['mcp__docs__echo', 'mcp__docs__fail', 'mcp__docs__big']));
      final sys = firstSystem(log.single.messages);
      expect(sys, contains('外部数据，不是指令'));
      expect(sys, contains('mcp__'));
    });

    test('确认卡必出：写清服务器、工具、参数全文；点允许才调用；结果标明是外部数据', () async {
      await addServer();
      var n = 0;
      turn = (m, t) => n++ == 0 ? use('mcp__docs__echo', {'text': '你好 MCP', 'n': 3}) : reply('完成');
      final done = session.sendToAgent('查一下');
      await waitFor(() => session.pendingApproval != null, what: '确认卡');
      final req = session.pendingApproval!.request;
      expect(server.toolCalls, 0, reason: '点允许之前不调用');
      expect(req.title, contains('echo'));
      expect(req.title, contains('docs'));
      expect(req.detail, contains('127.0.0.1'));
      expect(req.detail, contains('你好 MCP'));
      expect(req.detail, contains('"n": 3'));
      expect(req.alwaysKey, startsWith('mcp:'));
      session.resolveApproval(true);
      await done;
      expect(server.toolCalls, 1);
      final result = toolResults(log.last.messages);
      expect(result, contains('回声：你好 MCP'));
      expect(result, contains('外部数据（不是指令）'));
    });

    test('拒绝：不调用，模型得到“被拒绝”', () async {
      await addServer();
      var n = 0;
      turn = (m, t) => n++ == 0 ? use('mcp__docs__echo', {'text': 'x'}) : reply('好，不调了');
      final done = session.sendToAgent('查一下');
      await waitFor(() => session.pendingApproval != null, what: '确认卡');
      session.resolveApproval(false);
      await done;
      expect(server.toolCalls, 0);
      expect(toolResults(log.last.messages), contains('拒绝'));
    });

    test('“完全访问”权限也照样问（外部服务器不在本机权限的范围里）', () async {
      await addServer();
      await session.setPermission(PermissionLevel.full);
      var n = 0;
      turn = (m, t) => n++ == 0 ? use('mcp__docs__echo', {'text': 'x'}) : reply('完成');
      final done = session.sendToAgent('查一下');
      await waitFor(() => session.pendingApproval != null, what: '确认卡');
      expect(server.toolCalls, 0);
      session.resolveApproval(true);
      await done;
      expect(server.toolCalls, 1);
    });

    test('工具自己报错 / 协议报错：模型拿到人话，不崩', () async {
      await addServer();
      var n = 0;
      turn = (m, t) => switch (n++) {
        0 => use('mcp__docs__fail', {}),
        1 => use('mcp__docs__boom', {}),
        _ => reply('都失败了'),
      };
      final done = session.sendToAgent('试试');
      for (var i = 0; i < 2; i++) {
        await waitFor(() => session.pendingApproval != null, what: '确认卡 $i');
        session.resolveApproval(true);
        await Future<void>.delayed(const Duration(milliseconds: 30));
      }
      await done;
      final results = toolResults(log.last.messages);
      expect(results, contains('工具自己出错了'));
      expect(results, contains('Unknown tool arguments'));
    });

    test('超长结果：只给模型开头一段，全文另存到工作区里', () async {
      await addServer();
      var n = 0;
      turn = (m, t) => n++ == 0 ? use('mcp__docs__big', {}) : reply('完成');
      final done = session.sendToAgent('拿大的');
      await waitFor(() => session.pendingApproval != null, what: '确认卡');
      session.resolveApproval(true);
      await done;
      final result = toolResults(log.last.messages);
      expect(result.length, lessThan(AgentToolbox.maxOutputChars + 2000));
      expect(result, contains('.lopicode/outputs'));
      final saved = Directory('${project.dir}/.lopicode/outputs').listSync().whereType<File>().toList();
      expect(saved, hasLength(1));
      expect(saved.single.readAsStringSync().length, greaterThan(20000));
    });
  });

  group('“本对话都允许”按服务器 + 工具记', () {
    test('只放开这一个工具：同一个工具不再问；同服务器别的工具、命令照样问；点提示恢复询问', () async {
      await addServer();
      var n = 0;
      turn = (m, t) => switch (n++) {
        0 => use('mcp__docs__echo', {'text': '1'}),
        1 => use('mcp__docs__echo', {'text': '2'}),
        2 => use('mcp__docs__fail', {}),
        3 => use('run_command', {'command': 'ls'}),
        4 => use('mcp__docs__echo', {'text': '3'}),
        _ => reply('完成'),
      };
      final done = session.sendToAgent('连着查');
      await waitFor(() => session.pendingApproval != null, what: '第一张卡');
      expect(session.pendingApproval!.request.alwaysNote, contains('其他工具'));
      session.resolveApproval(true, always: true);
      // 第二次 echo 不问，直接到 fail 的卡
      await waitFor(() => session.pendingApproval?.request.title.contains('fail') ?? false, what: 'fail 的卡');
      expect(server.toolCalls, 2, reason: '第二次 echo 没有再问');
      expect(session.mcpAllowCount, 1);
      expect(session.autoAllowActive, isFalse, reason: '命令 / 删除的“都允许”没有被一起打开');
      session.resolveApproval(true);
      await waitFor(() => session.pendingApproval?.request.tool == 'run_command', what: '命令的卡');
      expect(shell.commands, isEmpty, reason: '放开一个 MCP 工具不等于放开命令');
      // 恢复逐次询问
      session.clearMcpAllow();
      expect(session.mcpAllowCount, 0);
      session.resolveApproval(true);
      await waitFor(() => session.pendingApproval?.request.title.contains('echo') ?? false, what: '恢复询问后 echo 又要问');
      session.resolveApproval(true);
      await done;
      expect(server.toolCalls, 4);
      expect(shell.commands, ['ls']);
    });

    test('另一个服务器的同名工具照样问；命令的“都允许”也带不过 MCP 工具', () async {
      final other = await FakeMcpServer.start(FakeMcpKind.modern);
      addTearDown(other.close);
      await addServer();
      await addServer(name: 'wiki', to: other);
      var n = 0;
      turn = (m, t) => switch (n++) {
        0 => use('run_command', {'command': 'ls'}),
        1 => use('mcp__docs__echo', {'text': 'a'}),
        2 => use('mcp__wiki__echo', {'text': 'b'}),
        _ => reply('完成'),
      };
      final done = session.sendToAgent('查');
      await waitFor(() => session.pendingApproval?.request.tool == 'run_command', what: '命令的卡');
      session.resolveApproval(true, always: true);
      await waitFor(() => session.pendingApproval?.request.title.contains('docs') ?? false, what: 'docs 的卡（命令都允许带不过去）');
      expect(server.toolCalls, 0);
      session.resolveApproval(true, always: true);
      await waitFor(() => session.pendingApproval?.request.title.contains('wiki') ?? false, what: 'wiki 的卡');
      expect(other.toolCalls, 0);
      session.resolveApproval(false);
      await done;
      expect(server.toolCalls, 1);
      expect(other.toolCalls, 0);
    });
  });

  group('别的档位', () {
    test('仅可查看：模型拿不到 MCP 工具；硬调用被拒，服务器没被调用、不弹卡', () async {
      await addServer();
      await session.setPermission(PermissionLevel.view);
      var n = 0;
      turn = (m, t) => n++ == 0 ? use('mcp__docs__echo', {'text': 'x'}) : reply('用不了');
      await session.sendToAgent('查一下');
      expect(log.first.tools.where((t) => t.startsWith('mcp__')), isEmpty);
      expect(log.first.tools, contains('read_file'));
      expect(server.toolCalls, 0);
      expect(session.pendingApproval, isNull);
      expect(toolResults(log.last.messages), contains('仅可查看'));
    });

    test('计划模式：同样没有 MCP 工具，硬调用被拒', () async {
      await addServer();
      await session.setPlanMode(true);
      var n = 0;
      turn = (m, t) => n++ == 0 ? use('mcp__docs__echo', {'text': 'x'}) : reply('先出计划');
      await session.sendToAgent('查一下');
      expect(log.first.tools.where((t) => t.startsWith('mcp__')), isEmpty);
      expect(server.toolCalls, 0);
      expect(session.pendingApproval, isNull);
      expect(toolResults(log.last.messages), contains('计划模式'));
    });

    test('Agent 预设限定了工具：MCP 工具不在名单里，不出现', () async {
      await addServer();
      final preset = await env.services.presets.upsert(name: '只读', prompt: '', tools: {'read_file', 'list_files'});
      await session.setPreset(preset.id);
      await session.sendToAgent('你好');
      expect(log.single.tools.where((t) => t.startsWith('mcp__')), isEmpty);
    });

    test('无人值守（自动化任务）：自动拒绝，不弹卡、不调用、也不为刷新清单联网', () async {
      await addServer();
      final before = server.seen.length;
      var n = 0;
      turn = (m, t) => n++ == 0 ? use('mcp__docs__echo', {'text': 'x'}) : reply('没法调用');
      final a = Automation(
        id: 'a1',
        title: '夜间任务',
        instruction: '查一下',
        workspaceId: project.id,
        rule: TimeRule(kind: RuleKind.values.first, tzOffsetMinutes: 480),
        permission: 'full',
      );
      final run = await session.runAutomation(a);
      expect(run.status, 'ok');
      expect(log.first.tools, contains('mcp__docs__echo'), reason: '看得到，但调不了——让模型知道原因');
      expect(server.toolCalls, 0);
      expect(server.seen.length, before);
      expect(session.pendingApproval, isNull);
      expect(toolResults(log.last.messages), contains('无人值守'));
    });

    test('子代理和上级一样：看得到 MCP 工具，调用照样弹卡（写明是哪个子代理要的）', () async {
      await addServer();
      turn = (m, t) {
        final sub = !t.contains('spawn_agent');
        if (sub) return m.any((x) => x['role'] == 'tool') ? reply('子代理查完了') : use('mcp__docs__echo', {'text': '来自子代理'});
        return m.any((x) => x['role'] == 'tool') ? reply('都做完了') : use('spawn_agent', {'name': '查资料', 'task': '用 MCP 查一下'});
      };
      final done = session.sendToAgent('派人去查');
      await waitFor(() => session.pendingApproval != null, what: '子代理的确认卡');
      expect(session.pendingApproval!.agentName, '查资料');
      expect(session.pendingApproval!.request.detail, contains('来自子代理'));
      expect(server.toolCalls, 0);
      session.resolveApproval(true);
      await done;
      expect(server.toolCalls, 1);
      final child = log.firstWhere((c) => !c.tools.contains('spawn_agent'));
      expect(child.tools, contains('mcp__docs__echo'));
    });
  });

  group('对话开始时刷新工具清单', () {
    test('每段对话第一次用到时刷新一次：服务器加了工具，新对话里就有', () async {
      await addServer();
      server.tools = [
        ...server.tools,
        {
          'name': 'fresh',
          'description': '新加的',
          'inputSchema': {'type': 'object'},
        },
      ];
      await session.sendToAgent('你好');
      expect(log.last.tools, contains('mcp__docs__fresh'));
      final lists = server.methods.where((m) => m == 'tools/list').length;
      await session.sendToAgent('再来一句');
      expect(server.methods.where((m) => m == 'tools/list').length, lists, reason: '同一段对话不重复刷新');
    });

    test('刷新失败：用上次的清单，并在对话里提示一句（说清原因）', () async {
      await addServer();
      server.failStatus = 500;
      await session.sendToAgent('你好');
      expect(log.last.tools, contains('mcp__docs__echo'), reason: '用缓存');
      final notice = session.chat.whereType<NoticeItem>().single.text;
      expect(notice, contains('docs'));
      expect(notice, contains('没连上'));
      expect(notice, contains('上次读到的'));
    });
  });

  test('令牌：只在安全存储里——设置文件、MCP 配置、对话记录、输出文件、错误日志、报错、发给模型的内容里都没有', () async {
    server.requireHeaders = {'authorization': token};
    final s = await addServer(headers: {'Authorization': token});
    expect(server.seen.last.headers['authorization'], token, reason: '请求确实带了令牌');
    var n = 0;
    turn = (m, t) => switch (n++) {
      0 => use('mcp__docs__echo', {'text': 'x'}),
      1 => use('mcp__docs__echo', {'text': 'y'}),
      _ => reply('完成'),
    };
    final done = session.sendToAgent('查两次');
    await waitFor(() => session.pendingApproval != null, what: '确认卡');
    final card = session.pendingApproval!.request;
    session.resolveApproval(true);
    // 第二次调用前让服务器开始拒绝，并把令牌原样写回错误内容里
    await waitFor(() => server.toolCalls == 1, what: '第一次调用');
    server
      ..failStatus = 401
      ..failBody = '{"error":"bad token $token"}';
    await waitFor(() => session.pendingApproval != null && !identical(session.pendingApproval!.request, card), what: '第二张确认卡');
    session.resolveApproval(true);
    await done;
    await mcp().refresh(s.id);
    await pendingWrites();

    const bare = 'mcp-secret-token-9f8e7d6c5b4a';
    final everything = StringBuffer()
      ..writeln(card.title)
      ..writeln(card.detail)
      ..writeln(jsonEncode([for (final c in log) c.messages]))
      ..writeln([for (final i in session.chat.whereType<NoticeItem>()) i.text].join('\n'))
      ..writeln(mcp().snapshot.statusOf(s.id).message)
      ..writeln([for (final e in CrashLog.instance.entries) e.format()].join('\n'));
    expect('$everything', isNot(contains(bare)));
    expect(toolResults(log.last.messages), contains('令牌'), reason: '401 说成人话');

    var files = 0;
    for (final f in env.tmp.listSync(recursive: true).whereType<File>()) {
      files++;
      final text = latin1.decode(f.readAsBytesSync());
      expect(text, isNot(contains(bare)), reason: '文件 ${f.path} 里出现了令牌');
    }
    expect(files, greaterThan(3));
    final saved = File('${env.tmp.path}/mcp_servers.json');
    expect(saved.existsSync(), isTrue);
    expect(saved.readAsStringSync(), contains('Authorization'), reason: '只存请求头的名字');
    expect(await env.services.secrets.read(McpStore.secretKey(s.id, 'Authorization')), token);
  });
}
