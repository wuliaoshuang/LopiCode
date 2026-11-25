// MCP 状态（lib/state/mcp_state.dart）：增删改、请求头只进安全存储、测试连接、刷新（失败留旧清单）、
// 旧结果不盖新设置（代次）、每段对话只刷新一次、调用时的各种拦截。服务器是本机假服务器，不发外网请求。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/agent/mcp/mcp_config.dart';
import 'package:lopicode/agent/mcp/mcp_http.dart';
import 'package:lopicode/agent/mcp/mcp_models.dart';
import 'package:lopicode/core/safe_file.dart';
import 'package:lopicode/state/app_providers.dart';
import 'package:lopicode/state/mcp_state.dart';
import 'package:riverpod/riverpod.dart';

import 'support/fake_mcp_server.dart';
import 'support/harness.dart';

const token = 'Bearer state-secret-token-1a2b3c4d';

void main() {
  late TestEnv env;
  late ProviderContainer box;
  late FakeMcpServer server;
  McpNotifier mcp() => box.read(mcpProvider.notifier);
  McpState state() => box.read(mcpProvider);
  File saved() => File('${env.tmp.path}/mcp_servers.json');

  setUp(() async {
    env = await TestEnv.create();
    // 照规矩用独立容器；等待时间调短，超时的用例才跑得快。
    box = ProviderContainer(
      overrides: [
        appServicesProvider.overrideWithValue(env.services),
        mcpTimeoutsProvider.overrideWithValue(
          const McpTimeouts(connect: Duration(seconds: 2), headers: Duration(milliseconds: 600), callHeaders: Duration(milliseconds: 600), idle: Duration(milliseconds: 600)),
        ),
      ],
    );
    server = await FakeMcpServer.start(FakeMcpKind.legacy);
  });
  tearDown(() async {
    box.dispose();
    await env.dispose();
    await server.close();
  });

  test('一开始是空的；不联网', () async {
    await mcp().ensureLoaded();
    expect(state().servers, isEmpty);
    expect(state().active, isFalse);
    expect(state().loaded, isTrue);
    expect(server.seen, isEmpty);
    expect(saved().existsSync(), isFalse, reason: '没配置就不写文件');
  });

  test('添加：存盘只有名字，请求头的值只进安全存储；订阅的人收到通知', () async {
    var notified = 0;
    box.listen(mcpProvider, (_, _) => notified++);
    final s = await mcp().upsert(name: ' 资料库 ', url: ' ${server.url} ', headers: {'Authorization': token, 'X-Team': 'blue-team-secret'});
    expect(s.name, '资料库');
    expect(s.url, '${server.url}');
    expect(s.enabled, isTrue);
    expect(s.headerNames, ['Authorization', 'X-Team']);
    expect(notified, greaterThan(0));
    expect(state().active, isTrue);
    final text = saved().readAsStringSync();
    expect(text, contains('Authorization'));
    expect(text, isNot(contains('state-secret-token')));
    expect(text, isNot(contains('blue-team-secret')));
    expect(await env.services.secrets.read(McpStore.secretKey(s.id, 'authorization')), token);
    expect(await env.services.mcp.headersOf(s), {'Authorization': token, 'X-Team': 'blue-team-secret'});
  });

  test('修改：值传 null＝沿用；没列出来的头删掉；换地址清掉旧工具清单', () async {
    final probe = await mcp().probe(url: '${server.url}');
    final s = await mcp().upsert(name: 'docs', url: '${server.url}', headers: {'Authorization': token, 'X-Old': 'old'}, tools: probe.tools, mode: probe.mode);
    expect(s.tools, isNotEmpty);
    expect(s.mode, McpMode.legacy);
    expect(s.toolsAt, isNotNull);

    final same = await mcp().upsert(id: s.id, name: 'docs2', url: '${server.url}', headers: {'Authorization': null});
    expect(same.id, s.id);
    expect(same.tools.length, s.tools.length, reason: '地址没变，清单留着');
    expect(await env.services.secrets.read(McpStore.secretKey(s.id, 'Authorization')), token, reason: '留空＝不改');
    expect(await env.services.secrets.read(McpStore.secretKey(s.id, 'X-Old')), isNull, reason: '去掉的头连值一起删');

    final moved = await mcp().upsert(id: s.id, name: 'docs2', url: 'https://example.com/mcp', headers: {'Authorization': null});
    expect(moved.tools, isEmpty);
    expect(moved.mode, isNull);
    expect(moved.toolsAt, isNull);
    expect(state().servers, hasLength(1));
  });

  test('不合规矩的都拦下并说人话：外网 http、空名字、坏的请求头、没填值、重复、太多', () async {
    Future<String> why(Future<Object?> f) async {
      try {
        await f;
      } on FormatException catch (e) {
        return e.message;
      }
      fail('应该被拦下');
    }

    expect(await why(mcp().upsert(name: 'a', url: 'http://example.com/mcp')), contains('https'));
    expect(await why(mcp().upsert(name: '  ', url: 'https://example.com/mcp')), contains('名字'));
    expect(await why(mcp().upsert(name: 'a', url: 'https://example.com/mcp', headers: {'bad name': 'x'})), isNotEmpty);
    expect(await why(mcp().upsert(name: 'a', url: 'https://example.com/mcp', headers: {'X-A': 'line1\nline2'})), contains('换行'));
    expect(await why(mcp().upsert(name: 'a', url: 'https://example.com/mcp', headers: {'X-A': null})), contains('还没填值'));
    expect(await why(mcp().upsert(name: 'a', url: 'https://example.com/mcp', headers: {'X-A': '1', 'x-a': '2'})), contains('两遍'));
    expect(state().servers, isEmpty);
    expect(saved().existsSync(), isFalse);
    for (var i = 0; i < McpStore.maxServers; i++) {
      await mcp().upsert(name: 's$i', url: 'https://example.com/mcp$i');
    }
    expect(await why(mcp().upsert(name: 'more', url: 'https://example.com/more')), contains('最多'));
  });

  test('删除：配置和存着的请求头一起删', () async {
    final s = await mcp().upsert(name: 'docs', url: '${server.url}', headers: {'Authorization': token});
    await mcp().remove(s.id);
    expect(state().servers, isEmpty);
    expect(await env.services.secrets.read(McpStore.secretKey(s.id, 'Authorization')), isNull);
    expect((jsonDecode(saved().readAsStringSync()) as Map)['servers'], isEmpty);
  });

  test('开关服务器、开关单个工具：存盘，重新读回来还在', () async {
    final probe = await mcp().probe(url: '${server.url}');
    final s = await mcp().upsert(name: 'docs', url: '${server.url}', tools: probe.tools, mode: probe.mode);
    await mcp().setToolEnabled(s.id, 'echo', false);
    await mcp().setEnabled(s.id, false);
    expect(state().server(s.id)!.activeTools.map((t) => t.name), isNot(contains('echo')));
    expect(state().active, isFalse);
    await pendingWrites();
    final again = McpStore(saved(), env.services.secrets);
    await again.load();
    expect(again.servers.single.enabled, isFalse);
    expect(again.servers.single.disabledTools, {'echo'});
    expect(again.servers.single.tools.length, probe.tools.length);
    await mcp().setToolEnabled(s.id, 'echo', true);
    expect(state().server(s.id)!.disabledTools, isEmpty);
  });

  test('测试连接：成功说读到几个工具；各种失败分开说，而且不含令牌', () async {
    final ok = await mcp().probe(url: '${server.url}');
    expect(ok.result.ok, isTrue);
    expect(ok.result.title, contains('读到 ${ok.tools.length} 个工具'));
    expect(ok.result.advice, contains('没有调用任何工具'));
    expect(server.toolCalls, 0);

    expect((await mcp().probe(url: 'http://example.com/mcp')).result.title, '这个地址不能连');

    server
      ..failStatus = 401
      ..failBody = 'bad $token';
    final auth = await mcp().probe(url: '${server.url}', headers: {'Authorization': token});
    expect(auth.result.ok, isFalse);
    expect(auth.result.title, contains('令牌'));
    expect('${auth.result.title}${auth.result.advice}${auth.result.detail}', isNot(contains('state-secret-token')));

    server
      ..failStatus = null
      ..garbage = true;
    expect((await mcp().probe(url: '${server.url}')).result.title, contains('不是 MCP 服务器'));

    server
      ..garbage = false
      ..hang = true;
    expect((await mcp().probe(url: '${server.url}')).result.title, contains('超时'));
    server.hang = false;

    final dead = '${server.url}';
    await server.close();
    expect((await mcp().probe(url: dead)).result.title, contains('连不上'));
    server = await FakeMcpServer.start(FakeMcpKind.legacy);
    final titles = {for (final k in McpFailure.values) mcpFailureResult(McpException(k, 'x')).title};
    expect(titles.length, McpFailure.values.length, reason: '每种原因的说法都不一样');
  });

  test('测试连接用已保存的请求头（值传 null）', () async {
    server.requireHeaders = {'authorization': token};
    final s = await mcp().upsert(name: 'docs', url: '${server.url}', headers: {'Authorization': token});
    final p = await mcp().probe(id: s.id, url: '${server.url}', headers: {'Authorization': null});
    expect(p.result.ok, isTrue, reason: p.result.title);
  });

  test('刷新：成功换新清单；失败留着旧清单、状态记成失败并带原因', () async {
    final probe = await mcp().probe(url: '${server.url}');
    final s = await mcp().upsert(name: 'docs', url: '${server.url}', tools: probe.tools, mode: probe.mode);
    server.tools = [
      {
        'name': 'only',
        'inputSchema': {'type': 'object'},
      },
    ];
    await mcp().refresh(s.id);
    expect(state().server(s.id)!.tools.map((t) => t.name), ['only']);
    expect(state().statusOf(s.id).phase, McpPhase.ok);

    server.failStatus = 500;
    await mcp().refresh(s.id);
    expect(state().server(s.id)!.tools.map((t) => t.name), ['only'], reason: '失败不清旧清单');
    expect(state().statusOf(s.id).phase, McpPhase.failed);
    expect(state().statusOf(s.id).message, contains('500'));
  });

  test('同一个服务器同时只刷新一次；刷完还能再刷（不会自己等自己）', () async {
    final s = await mcp().upsert(name: 'docs', url: '${server.url}');
    final a = mcp().refresh(s.id);
    final b = mcp().refresh(s.id);
    expect(identical(a, b), isTrue);
    await a.timeout(const Duration(seconds: 5));
    final lists = server.methods.where((m) => m == 'tools/list').length;
    expect(lists, 1);
    await mcp().refresh(s.id).timeout(const Duration(seconds: 5));
    expect(server.methods.where((m) => m == 'tools/list').length, 2);
  });

  test('代次：刷新在路上时改了设置，回来的旧结果丢掉，不盖新设置', () async {
    final s = await mcp().upsert(name: 'docs', url: '${server.url}');
    server.hang = true;
    final slow = mcp().refresh(s.id);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await mcp().upsert(id: s.id, name: 'docs', url: 'https://example.com/other');
    server.hang = false;
    await slow;
    final now = state().server(s.id)!;
    expect(now.url, 'https://example.com/other');
    expect(now.tools, isEmpty, reason: '旧地址的工具没有写进新设置');
    expect(state().statusOf(s.id).phase, isNot(McpPhase.failed), reason: '旧请求的失败也不算在新设置头上');
  });

  test('每段主对话只刷新一次；失败时返回一句提示（有旧清单 / 没旧清单说法不同）', () async {
    final probe = await mcp().probe(url: '${server.url}');
    final cached = await mcp().upsert(name: 'cached', url: '${server.url}', tools: probe.tools, mode: probe.mode);
    final before = server.seen.length;
    expect(await mcp().refreshForConversation('c1'), isEmpty);
    final afterFirst = server.seen.length;
    expect(afterFirst, greaterThan(before));
    expect(await mcp().refreshForConversation('c1'), isEmpty);
    expect(server.seen.length, afterFirst, reason: '同一段对话不重复刷');

    final dead = await FakeMcpServer.start(FakeMcpKind.legacy);
    final deadUrl = '${dead.url}';
    await dead.close();
    await mcp().upsert(name: 'empty', url: deadUrl);
    server.failStatus = 503;
    final notes = await mcp().refreshForConversation('c2');
    expect(notes, hasLength(2));
    expect(notes.firstWhere((n) => n.contains('cached')), contains('先用上次读到的 ${cached.tools.length} 个工具'));
    expect(notes.firstWhere((n) => n.contains('empty')), contains('暂时没有它的工具'));

    await mcp().setEnabled(cached.id, false);
    await mcp().setEnabled(state().servers.last.id, false);
    final quiet = server.seen.length;
    expect(await mcp().refreshForConversation('c3'), isEmpty);
    expect(server.seen.length, quiet, reason: '都关着就不联网');
  });

  test('调用：关掉的服务器 / 关掉的工具 / 已删除的，都不发请求', () async {
    final probe = await mcp().probe(url: '${server.url}');
    final s = await mcp().upsert(name: 'docs', url: '${server.url}', tools: probe.tools, mode: probe.mode);
    final echo = probe.tools.firstWhere((t) => t.name == 'echo');
    expect((await mcp().call(s.id, echo, {'text': 'hi'})).text, contains('回声：hi'));
    expect(server.toolCalls, 1);

    Future<String> why(Future<Object?> f) async {
      try {
        await f;
      } on McpException catch (e) {
        return e.message;
      }
      fail('应该被拦下');
    }

    await mcp().setToolEnabled(s.id, 'echo', false);
    expect(await why(mcp().call(s.id, echo, {})), contains('关掉'));
    await mcp().setToolEnabled(s.id, 'echo', true);
    await mcp().setEnabled(s.id, false);
    expect(await why(mcp().call(s.id, echo, {})), contains('关掉或删除'));
    await mcp().remove(s.id);
    expect(await why(mcp().call(s.id, echo, {})), contains('关掉或删除'));
    expect(server.toolCalls, 1);
  });

  test('调用超时后连接丢掉，下一次重新连，照样能用；不自动重试', () async {
    final probe = await mcp().probe(url: '${server.url}');
    final s = await mcp().upsert(name: 'docs', url: '${server.url}', tools: probe.tools, mode: probe.mode);
    final slow = probe.tools.firstWhere((t) => t.name == 'slow');
    final echo = probe.tools.firstWhere((t) => t.name == 'echo');
    await expectLater(mcp().call(s.id, slow, {}), throwsA(isA<McpException>().having((e) => e.kind, 'kind', McpFailure.timeout)));
    expect(server.toolCalls, 1, reason: '超时不重试（重试可能让工具执行两遍）');
    expect((await mcp().call(s.id, echo, {'text': 'again'})).text, contains('again'));
  });

  test('容器销毁后回来的结果不写状态、不抛异常', () async {
    final s = await mcp().upsert(name: 'docs', url: '${server.url}');
    final notifier = mcp();
    server.hang = true;
    final slow = notifier.refresh(s.id);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    box.dispose();
    server.hang = false;
    await slow;
    expect(notifier.snapshot.server(s.id), isNotNull);
    box = ProviderContainer(overrides: [appServicesProvider.overrideWithValue(env.services)]);
  });
}
