// MCP 客户端（协议层）：对着本机假服务器（只绑 127.0.0.1）把三种连接方式都走一遍。不发任何外网请求。
//   flutter test test/mcp_client_test.dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/agent/mcp/mcp_client.dart';
import 'package:lopicode/agent/mcp/mcp_http.dart';
import 'package:lopicode/agent/mcp/mcp_models.dart';
import 'package:lopicode/agent/mcp/mcp_sse.dart';

import 'support/fake_mcp_server.dart';
import 'support/wait.dart';

const _token = 'tok-SECRET-9f8e7d6c5b4a';
const _fast = McpTimeouts(
  connect: Duration(seconds: 2),
  headers: Duration(milliseconds: 600),
  callHeaders: Duration(milliseconds: 600),
  idle: Duration(milliseconds: 600),
  close: Duration(milliseconds: 300),
);

void main() {
  late FakeMcpServer server;
  final clients = <McpClient>[];

  McpClient clientFor(FakeMcpServer s, {McpTransportChoice transport = McpTransportChoice.auto, Map<String, String> headers = const {}, McpMode? hint, McpTimeouts timeouts = _fast, Uri? url}) {
    final c = McpClient(url: url ?? s.url, headers: headers, transport: transport, hint: hint, timeouts: timeouts);
    clients.add(c);
    return c;
  }

  Future<McpException> failure(Future<Object?> f) async {
    try {
      await f;
    } on McpException catch (e) {
      return e;
    }
    fail('应该失败');
  }

  tearDown(() async {
    for (final c in clients) {
      await c.close();
    }
    clients.clear();
    await server.close();
  });

  group('SSE 解析', () {
    setUp(() async => server = await FakeMcpServer.start(FakeMcpKind.modern));

    List<SseEvent> feed(List<String> chunks) {
      final p = SseParser();
      return [for (final c in chunks) ...p.add(c)];
    }

    test('事件边界、多行 data、注释、默认事件名、三种换行', () {
      final events = feed([': 注释\n\n', 'event: endpoint\ndata: /x\n\n', 'data: 第一行\r\ndata: 第二行\r\n\r\n', 'data:不带空格\rdata:  两个空格\r\r', 'event: 没有data\n\n', 'id: 9\ndata: 带id\n\n']);
      expect([for (final e in events) (e.event, e.data)], [('endpoint', '/x'), ('message', '第一行\n第二行'), ('message', '不带空格\n 两个空格'), ('message', '带id')]);
      expect(events.last.id, '9');
    });

    test('数据从任何位置切开都一样（包括 \\r 和 \\n 之间）', () {
      const whole = 'event: message\r\ndata: {"a":\r\ndata: 1}\r\n\r\ndata: 尾巴\n\n';
      for (var cut = 1; cut < whole.length; cut++) {
        final events = feed([whole.substring(0, cut), whole.substring(cut)]);
        expect([for (final e in events) e.data], ['{"a":\n1}', '尾巴'], reason: '切在第 $cut 个字符');
      }
    });

    test('流结束时没有空行收尾的半个事件不派发；字节流里汉字被切开也能拼回来', () async {
      final bytes = utf8.encode('data: 你好\n\ndata: 半个');
      final events = await parseSse(Stream.fromIterable([bytes.sublist(0, 8), bytes.sublist(8)])).toList();
      expect([for (final e in events) e.data], ['你好']);
    });
  });

  group('新版 Streamable HTTP（2026-07-28，无会话）', () {
    setUp(() async => server = await FakeMcpServer.start(FakeMcpKind.modern));

    test('自动探测：不握手，每个请求带版本号 / 方法名头和 _meta', () async {
      final c = clientFor(server);
      final info = await c.connect();
      expect(info.mode, McpMode.modern);
      expect(info.protocolVersion, '2026-07-28');
      expect(info.name, 'fake-modern');
      final tools = await c.listTools();
      expect(tools.map((t) => t.name), containsAll(['echo', 'fail']));
      final r = await c.callTool('echo', {'text': '嗨'});
      expect(r.isError, isFalse);
      expect(r.text, contains('回声：嗨'));
      expect(r.text, contains('图片'));
      expect(server.methods, ['server/discover', 'tools/list', 'tools/call'], reason: '没有 initialize、没有 notifications/initialized');
      for (final req in server.seen) {
        expect(req.headers['mcp-protocol-version'], '2026-07-28');
        expect(req.headers['mcp-method'], req.rpcMethod);
        expect(req.headers['accept'], allOf(contains('application/json'), contains('text/event-stream')));
        expect(req.headers.containsKey('mcp-session-id'), isFalse);
        final meta = (req.body!['params'] as Map)['_meta'] as Map;
        expect(meta['io.modelcontextprotocol/protocolVersion'], '2026-07-28');
        expect(meta['io.modelcontextprotocol/clientCapabilities'], <String, dynamic>{}, reason: '不声明任何能力');
        expect((meta['io.modelcontextprotocol/clientInfo'] as Map)['name'], 'LopiCode');
      }
      expect(server.seen.last.headers['mcp-name'], 'echo');
    });

    test('ping：新版没有 ping 方法，改问一次 server/discover', () async {
      final c = clientFor(server);
      await c.ping();
      expect(server.methods, ['server/discover', 'server/discover']);
    });

    test('SSE 回复：夹带的注释和通知忽略，多行 data 拼回来', () async {
      server
        ..streamReplies = true
        ..interleave = true;
      final c = clientFor(server);
      final r = await c.callTool('echo', {'text': '流'});
      expect(r.text, contains('回声：流'));
      expect(server.seen.where((r) => r.rpcMethod == null), isEmpty, reason: '新版不给服务器回消息');
    });

    test('工具名带中文：Mcp-Name 头按规范包成 base64', () async {
      server.tools = [
        {
          'name': '查天气',
          'inputSchema': {'type': 'object'},
        },
      ];
      final c = clientFor(server);
      await failure(c.callTool('查天气', {}));
      expect(server.seen.last.headers['mcp-name'], '=?base64?${base64.encode(utf8.encode('查天气'))}?=');
      expect(mcpHeaderValue('plain-name_1'), 'plain-name_1');
      expect(mcpHeaderValue(' 前面有空格'), startsWith('=?base64?'));
      expect(mcpHeaderValue('=?base64?abc?='), isNot('=?base64?abc?='), reason: '长得像编码格式的也要再包一层');
    });

    test('x-mcp-header：参数值同时放进 Mcp-Param- 头；标得不合规矩的工具不出现在清单里', () async {
      server.tools = [
        {
          'name': 'echo',
          'inputSchema': {
            'type': 'object',
            'properties': {
              'text': {'type': 'string', 'x-mcp-header': 'Region'},
              'n': {'type': 'integer', 'x-mcp-header': 'Count'},
              'skip': {'type': 'string', 'x-mcp-header': 'Skip'},
            },
          },
        },
        {
          'name': 'bad',
          'inputSchema': {
            'type': 'object',
            'properties': {
              'o': {'type': 'object', 'x-mcp-header': 'Obj'},
            },
          },
        },
        {
          'name': 'dup',
          'inputSchema': {
            'type': 'object',
            'properties': {
              'a': {'type': 'string', 'x-mcp-header': 'Same'},
              'b': {'type': 'string', 'x-mcp-header': 'same'},
            },
          },
        },
      ];
      final c = clientFor(server);
      final tools = await c.listTools();
      expect(tools.map((t) => t.name), ['echo']);
      await c.callTool('echo', {'text': 'us-west', 'n': 3}, schema: tools.single.inputSchema);
      final h = server.seen.last.headers;
      expect(h['mcp-param-region'], 'us-west');
      expect(h['mcp-param-count'], '3');
      expect(h.containsKey('mcp-param-skip'), isFalse, reason: '没传的参数不带头');
    });

    test('服务器要求额外输入（input_required）：报成人话，不崩', () async {
      final c = clientFor(server);
      final e = await failure(c.callTool('need', {}));
      expect(e.kind, McpFailure.unsupported);
      expect(e.message, contains('额外的输入'));
    });

    test('版本对不上：服务器只认别的版本，说清它支持哪些', () async {
      server.supportedVersions = ['2027-01-01'];
      final e = await failure(clientFor(server).connect());
      expect(e.kind, McpFailure.unsupported);
      expect(e.message, allOf(contains('2026-07-28'), contains('2027-01-01')));
    });
  });

  group('握手版 Streamable HTTP（2025-06-18）', () {
    setUp(() async => server = await FakeMcpServer.start(FakeMcpKind.legacy));

    test('自动探测退到握手：initialize → notifications/initialized → 带会话号和版本号', () async {
      final c = clientFor(server);
      final info = await c.connect();
      expect(info.mode, McpMode.legacy);
      expect(info.protocolVersion, '2025-06-18');
      expect(info.name, 'fake-legacy');
      await c.listTools();
      await c.ping();
      expect(server.methods, ['server/discover', 'initialize', 'notifications/initialized', 'tools/list', 'ping']);
      final init = server.seen[1];
      expect(init.headers.containsKey('mcp-session-id'), isFalse);
      expect((init.body!['params'] as Map)['protocolVersion'], '2025-06-18');
      expect((init.body!['params'] as Map)['capabilities'], <String, dynamic>{}, reason: '不声明任何能力');
      for (final req in server.seen.skip(2)) {
        expect(req.headers['mcp-session-id'], 'sess-1');
        expect(req.headers['mcp-protocol-version'], '2025-06-18');
      }
      expect(server.seen[2].body!.containsKey('id'), isFalse, reason: '通知没有 id');
    });

    test('记住上次探测的结果：直接握手，不再先试新版', () async {
      final c = clientFor(server, hint: McpMode.legacy);
      await c.connect();
      expect(server.methods.first, 'initialize');
    });

    test('列工具分页：跟着 nextCursor 翻完', () async {
      server.pageSize = 2;
      final c = clientFor(server, hint: McpMode.legacy);
      final tools = await c.listTools();
      expect(tools.map((t) => t.name), ['echo', 'fail', 'boom', 'big', 'slow']);
      final cursors = [for (final r in server.seen.where((r) => r.rpcMethod == 'tools/list')) (r.body!['params'] as Map?)?['cursor']];
      expect(cursors, [null, '2', '4']);
    });

    test('调用：成功、工具自己报错、协议报错分得开', () async {
      final c = clientFor(server, hint: McpMode.legacy);
      expect((await c.callTool('echo', {'text': 'a'})).isError, isFalse);
      final bad = await c.callTool('fail', {});
      expect(bad.isError, isTrue);
      expect(bad.text, '工具自己出错了');
      final e = await failure(c.callTool('boom', {}));
      expect(e.kind, McpFailure.rpc);
      expect(e.code, -32602);
      expect(e.message, contains('Unknown tool arguments'));
    });

    test('SSE 回复：夹带的通知忽略；服务器的请求回“不支持”，ping 回空结果；多行 data 拼回来', () async {
      server
        ..streamReplies = true
        ..interleave = true;
      final c = clientFor(server, hint: McpMode.legacy);
      final r = await c.callTool('echo', {'text': '流'});
      expect(r.text, contains('回声：流'));
      // 等回给服务器的那两条发完
      await waitUntilReal(() => server.seen.where((r) => r.body != null && r.rpcMethod == null).length >= 2, '回给服务器的两条回音发完');
      final answers = {for (final r in server.seen.where((r) => r.body != null && r.rpcMethod == null)) r.body!['id']: r.body!};
      expect((answers['srv-1']!['error'] as Map)['code'], -32601);
      expect(answers['srv-2']!['result'], <String, dynamic>{});
    });

    test('会话过期（带着会话号却 404）：重新握手再试一次', () async {
      final c = clientFor(server, hint: McpMode.legacy);
      await c.connect();
      server.expireSessionOnce = true;
      final tools = await c.listTools();
      expect(tools, isNotEmpty);
      expect(server.methods, ['initialize', 'notifications/initialized', 'tools/list', 'initialize', 'notifications/initialized', 'tools/list']);
      expect(server.seen.last.headers['mcp-session-id'], 'sess-2');
    });

    test('收尾：有会话就发 DELETE 告诉服务器', () async {
      final c = clientFor(server, hint: McpMode.legacy);
      await c.connect();
      await c.close();
      expect(server.seen.last.httpMethod, 'DELETE');
      expect(server.seen.last.headers['mcp-session-id'], 'sess-1');
    });

    test('没有会话号的服务器也能用', () async {
      server.sessions = false;
      final c = clientFor(server);
      await c.listTools();
      expect(server.seen.every((r) => !r.headers.containsKey('mcp-session-id')), isTrue);
    });

    test('服务器要用不认识的版本：报成人话', () async {
      server.replyVersion = '1999-01-01';
      final e = await failure(clientFor(server, hint: McpMode.legacy, transport: McpTransportChoice.streamable).connect());
      expect(e.kind, McpFailure.unsupported);
      expect(e.message, contains('1999-01-01'));
    });

    test('服务器退到老一点的版本（2025-03-26）：接受，后面的请求带这个版本', () async {
      server.replyVersion = '2025-03-26';
      final c = clientFor(server, hint: McpMode.legacy);
      expect((await c.connect()).protocolVersion, '2025-03-26');
      await c.listTools();
      expect(server.seen.last.headers['mcp-protocol-version'], '2025-03-26');
    });
  });

  group('旧版 HTTP+SSE（2024-11-05）', () {
    setUp(() async => server = await FakeMcpServer.start(FakeMcpKind.sse));

    test('自动探测退到最后：GET 开流 → endpoint 事件 → 握手 → 列工具 → 调用', () async {
      server.interleave = true;
      final c = clientFor(server);
      final info = await c.connect();
      expect(info.mode, McpMode.sse);
      final tools = await c.listTools();
      expect(tools.length, 5);
      final r = await c.callTool('echo', {'text': '老'});
      expect(r.text, contains('回声：老'));
      expect(server.seen.where((r) => r.path == '/messages').map((r) => r.rpcMethod).whereType<String>(), ['initialize', 'notifications/initialized', 'tools/list', 'tools/call']);
      expect(server.seen.where((r) => r.httpMethod == 'GET' && r.path == '/sse').length, 1);
      await waitUntilReal(() => server.seen.where((r) => r.path == '/messages' && r.body != null && r.rpcMethod == null).length >= 2, '服务器夹带的两个请求都收到回音');
      final answered = server.seen.where((r) => r.path == '/messages' && r.body != null && r.rpcMethod == null).map((r) => r.body!['id']).toSet();
      expect(answered, {'srv-1', 'srv-2'}, reason: '服务器夹带的请求有回音');
    });

    test('手选旧版 SSE：不先试别的', () async {
      final c = clientFor(server, transport: McpTransportChoice.sse);
      await c.connect();
      expect(server.seen.first.httpMethod, 'GET');
    });

    test('endpoint 指向别的主机：不照做', () async {
      server.endpointData = 'http://192.168.77.77:9/messages';
      final e = await failure(clientFor(server, transport: McpTransportChoice.sse).connect());
      expect(e.kind, McpFailure.redirect);
      expect(e.message, contains('192.168.77.77'));
      expect(server.seen.where((r) => r.httpMethod == 'POST'), isEmpty);
    });

    test('调用超时：报成人话', () async {
      final c = clientFor(server, transport: McpTransportChoice.sse);
      final e = await failure(c.callTool('slow', {}));
      expect(e.kind, McpFailure.timeout);
      expect(e.message, contains('超时'));
    });
  });

  group('出错都报成人话，不崩', () {
    setUp(() async => server = await FakeMcpServer.start(FakeMcpKind.legacy));

    test('401：说是令牌的问题；令牌不出现在报错里（哪怕服务器把它写回来）', () async {
      server.requireHeaders = {'authorization': 'Bearer right'};
      final c = clientFor(server, headers: {'Authorization': 'Bearer $_token'});
      final e = await failure(c.connect());
      expect(e.kind, McpFailure.auth);
      expect(e.status, 401);
      expect(e.message, contains('令牌'));
      expect('$e ${e.body} ${e.data}', isNot(contains(_token)));
      expect(server.seen.length, 1, reason: '401 不用再换连接方式试');
    });

    test('带对了令牌就能连；令牌每个请求都带', () async {
      server.requireHeaders = {'authorization': 'Bearer $_token'};
      final c = clientFor(server, headers: {'Authorization': 'Bearer $_token'});
      await c.listTools();
      expect(server.seen.every((r) => r.headers['authorization'] == 'Bearer $_token'), isTrue);
    });

    test('服务器把令牌写进错误内容：抹掉', () async {
      server
        ..failStatus = 500
        ..failBody = '{"oops":"header was Bearer $_token"} 以及单独的 $_token';
      final e = await failure(clientFor(server, headers: {'Authorization': 'Bearer $_token'}, transport: McpTransportChoice.streamable).connect());
      expect(e.kind, McpFailure.http);
      expect(e.status, 500);
      expect(e.message, contains('自己出错了'));
      expect(e.message, isNot(contains(_token)));
    });

    test('返回的不是 JSON（网页）：说清多半是地址填错', () async {
      server.garbage = true;
      final e = await failure(clientFor(server, transport: McpTransportChoice.streamable).connect());
      expect(e.kind, McpFailure.badReply);
      expect(e.message, contains('不是合法的 JSON'));
    });

    test('服务器不回：超时', () async {
      server.hang = true;
      final sw = Stopwatch()..start();
      final e = await failure(clientFor(server).connect());
      expect(e.kind, McpFailure.timeout);
      expect(e.message, contains('超时'));
      expect(sw.elapsed, lessThan(const Duration(seconds: 3)), reason: '超时后不再换方式一个个等');
    });

    test('调用工具时服务器不回：超时，之后还能接着用', () async {
      final c = clientFor(server, hint: McpMode.legacy);
      await c.connect();
      final e = await failure(c.callTool('slow', {}));
      expect(e.kind, McpFailure.timeout);
      expect((await c.callTool('echo', {'text': '还在'})).text, contains('还在'));
    });

    test('连不上（端口没人听）', () async {
      final dead = await FakeMcpServer.start(FakeMcpKind.legacy);
      final url = dead.url;
      await dead.close();
      final e = await failure(clientFor(server, url: url).connect());
      expect(e.kind, McpFailure.unreachable);
      expect(e.message, contains('连不上'));
    });

    test('重定向到别的主机：不跟，令牌没发过去', () async {
      final other = await FakeMcpServer.start(FakeMcpKind.legacy);
      addTearDown(other.close);
      // 同一台机器换个写法（localhost ≠ 127.0.0.1）就算别的主机
      server.redirectTo = Uri.parse('http://localhost:${other.port}/mcp');
      final e = await failure(clientFor(server, headers: {'Authorization': 'Bearer $_token'}).connect());
      expect(e.kind, McpFailure.redirect);
      expect(e.message, contains('没有跟过去'));
      expect(other.seen, isEmpty);
      expect(server.seen.length, 1);
    });

    test('同一个主机的 307 会跟（最多 2 次），一直转就停', () async {
      server.redirectTo = server.url.replace(path: '/mcp2');
      final e = await failure(clientFor(server).connect());
      expect(e.kind, McpFailure.redirect);
      expect(server.seen.length, McpWire.maxRedirects + 1);
    });

    test('同一个主机的 302 不跟（POST 会被改成 GET）', () async {
      server
        ..redirectTo = server.url.replace(path: '/mcp2')
        ..redirectStatus = 302;
      final e = await failure(clientFor(server).connect());
      expect(e.kind, McpFailure.redirect);
      expect(server.seen.length, 1);
    });

    test('地址规矩：外网必须 https，本机 / 局域网可以 http，不许带账号密码', () {
      expect(mcpUrlProblem('https://mcp.example.com/mcp'), isNull);
      expect(mcpUrlProblem('http://127.0.0.1:8080/mcp'), isNull);
      expect(mcpUrlProblem('http://192.168.1.5/sse'), isNull);
      expect(mcpUrlProblem('http://mcp.example.com/mcp'), contains('https'));
      expect(mcpUrlProblem('ftp://x/y'), isNotNull);
      expect(mcpUrlProblem('https://user:pw@mcp.example.com/'), contains('请求头'));
      expect(mcpUrlProblem(''), isNotNull);
    });

    test('外网 http 地址：一个字节都不发', () async {
      final e = await failure(McpClient(url: Uri.parse('http://mcp.example.com/mcp'), timeouts: _fast).connect());
      expect(e.kind, McpFailure.policy);
    });

    test('三种方式都接不上：说清这不像 MCP 服务器', () async {
      server
        ..failStatus = 404
        ..failBody = 'Not Found';
      final e = await failure(clientFor(server).connect());
      expect(e.message, contains('不像 MCP 服务器'));
      expect(server.seen.map((r) => r.httpMethod), ['POST', 'POST', 'GET']);
    });
  });

  group('工具数据是不可信的', () {
    setUp(() async => server = await FakeMcpServer.start(FakeMcpKind.legacy));

    test('坏的工具条目跳过；超长说明截断；超大的参数说明换成“任意对象”', () async {
      server.tools = [
        {'name': 'ok', 'description': 'x' * 5000, 'inputSchema': <String, dynamic>{}},
        {'name': 123},
        'not a map',
        {'name': ''},
        {'name': 'n' * 200},
        {
          'name': 'huge',
          'inputSchema': {'type': 'object', 'description': 'y' * 30000},
        },
        {'name': 'ok'},
      ];
      final tools = await clientFor(server, hint: McpMode.legacy).listTools();
      expect(tools.map((t) => t.name), ['ok', 'huge']);
      expect(tools.first.description.length, lessThanOrEqualTo(McpToolInfo.maxDescriptionChars + 1));
      expect(tools.first.inputSchema['type'], 'object');
      expect(tools.last.inputSchema, {'type': 'object'});
    });

    test('调用结果：各种内容块变成文字；什么都没有也有一句话', () {
      final r = McpCallResult.fromResult({
        'content': [
          {'type': 'text', 'text': 'A'},
          {'type': 'audio', 'data': 'xx', 'mimeType': 'audio/wav'},
          {'type': 'resource_link', 'name': '文档', 'uri': 'file:///a'},
          {
            'type': 'resource',
            'resource': {'uri': 'file:///b', 'text': 'B'},
          },
          {
            'type': 'resource',
            'resource': {'uri': 'file:///c', 'blob': 'AAAA'},
          },
          {'type': '以后的新类型'},
          42,
        ],
      });
      expect(r.text, allOf(contains('A'), contains('音频'), contains('file:///a'), contains('B'), contains('file:///c')));
      expect(McpCallResult.fromResult({}).text, '（工具没有返回内容）');
      expect(
        McpCallResult.fromResult({
          'structuredContent': {'n': 1},
        }).text,
        contains('"n": 1'),
      );
      expect(McpCallResult.fromResult({'content': 'oops', 'isError': 'yes'}).isError, isFalse);
    });
  });
}
