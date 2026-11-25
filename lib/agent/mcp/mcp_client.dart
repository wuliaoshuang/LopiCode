// MCP 客户端：握手（或探测是哪一代协议）、列工具、调用工具、ping。只做远程连接，三种服务器都认：
//   新版 Streamable HTTP（2026-07-28，无会话）→ 握手版 Streamable HTTP（2025-06-18 / 2025-03-26）→ 旧版 HTTP+SSE（2024-11-05）。
// 自动探测的顺序就是上面这个顺序，是官方规范“向后兼容”一节写的做法。方法名、头名、版本号的出处见 docs/api-notes.md 的“MCP”一节。
//
// 这一版不做、也不向服务器声明的：resources、prompts、sampling、elicitation、roots；断线续传（Last-Event-ID）；OAuth；
// 新版里服务器“要求额外输入”（input_required）——遇到就报成人话。
// 服务器在回复流里夹带的通知一律忽略；夹带的请求：ping 回空结果，别的回“不支持”（-32601）。新版规定服务器不许夹带请求，夹了也忽略。
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:lopicode/agent/mcp/mcp_http.dart';
import 'package:lopicode/agent/mcp/mcp_models.dart';
import 'package:lopicode/agent/mcp/mcp_sse.dart';

/// 新版协议的版本号。
const String kMcpModernVersion = '2026-07-28';

/// 握手时报给老服务器的版本号，和我们认的几个老版本。
const String kMcpLegacyVersion = '2025-06-18';
const Set<String> kMcpLegacyVersions = {'2025-06-18', '2025-03-26', '2024-11-05'};

/// 列工具最多翻多少页、最多收多少个（防止服务器给个没完没了的清单）。
const int kMcpMaxToolPages = 20;
const int kMcpMaxTools = 200;

const String _kVersionKey = 'io.modelcontextprotocol/protocolVersion';
const String _kCapsKey = 'io.modelcontextprotocol/clientCapabilities';
const String _kClientKey = 'io.modelcontextprotocol/clientInfo';
const String _kServerKey = 'io.modelcontextprotocol/serverInfo';

/// 头的值能不能原样放：只含可见 ASCII、首尾没有空白、长得不像下面的编码格式。不能就按规范包成 base64。
String mcpHeaderValue(String value) {
  final plain = value.isNotEmpty && value.trim() == value && value.codeUnits.every((c) => c >= 0x20 && c <= 0x7E) && !(value.startsWith('=?base64?') && value.endsWith('?='));
  return plain ? value : '=?base64?${base64.encode(utf8.encode(value))}?=';
}

final RegExp _headerToken = RegExp(r"^[A-Za-z0-9!#$%&'*+.^_`|~-]+$");

/// 工具参数里标了 `x-mcp-header` 的（新版要求把这些参数的值同时放进 `Mcp-Param-名字` 头）。
/// 返回 参数路径 → 头名字；标得不合规矩（空、带换行、重名、类型不是字符串 / 整数 / 布尔）返回 null——这种工具按规范不能用。
Map<List<String>, String>? mcpParamHeaders(Map<String, dynamic> schema) {
  final out = <List<String>, String>{};
  final seen = <String>{};
  var bad = false;
  void walk(Object? node, List<String> path, int depth) {
    if (node is! Map || depth > 6) return;
    final mark = node['x-mcp-header'];
    if (mark != null && path.isNotEmpty) {
      final type = node['type'];
      if (mark is! String || !_headerToken.hasMatch(mark) || !seen.add(mark.toLowerCase()) || !(type == 'string' || type == 'integer' || type == 'boolean')) {
        bad = true;
        return;
      }
      out[path] = mark;
    }
    final props = node['properties'];
    if (props is Map) {
      for (final e in props.entries) {
        if (e.key is String) walk(e.value, [...path, e.key as String], depth + 1);
      }
    }
  }

  walk(schema, const [], 0);
  return bad ? null : out;
}

class McpClient {
  McpClient({
    required this.url,
    Map<String, String> headers = const {},
    this.transport = McpTransportChoice.auto,
    this.hint,
    this.timeouts = const McpTimeouts(),
    this.clientVersion = '1.0.0',
    http.Client Function()? clientFactory,
  }) : _wire = McpWire(headers: headers, timeouts: timeouts, clientFactory: clientFactory);

  final Uri url;
  final McpTransportChoice transport;

  /// 上次探测出来的结果：先按它连，不行再重新探测。
  final McpMode? hint;
  final McpTimeouts timeouts;
  final String clientVersion;
  final McpWire _wire;

  McpServerInfo? _info;
  String? _sessionId;
  String _legacyVersion = kMcpLegacyVersion;
  int _nextId = 1;
  _SseLink? _sse;
  Future<McpServerInfo>? _connecting;

  McpServerInfo? get info => _info;
  String get _host => url.host;
  Map<String, String> get _clientInfo => {'name': 'LopiCode', 'version': clientVersion};

  /// 抹掉文字里的令牌（给上层拼报错用）。
  String scrub(String text) => _wire.scrub(text);

  /// 连上（握手 / 探测）。已经连上就直接返回。
  Future<McpServerInfo> connect() {
    final known = _info;
    if (known != null) return Future.value(known);
    return _connecting ??= _detect().whenComplete(() => _connecting = null);
  }

  Future<McpServerInfo> _detect() async {
    final order = switch (transport) {
      McpTransportChoice.sse => const [McpMode.sse],
      McpTransportChoice.streamable => const [McpMode.modern, McpMode.legacy],
      McpTransportChoice.auto => const [McpMode.modern, McpMode.legacy, McpMode.sse],
    };
    final hinted = hint;
    final tries = [if (hinted != null && order.contains(hinted)) hinted, ...order.where((m) => m != hinted)];
    McpException? last;
    McpException? versionProblem;
    for (final mode in tries) {
      try {
        final info = await switch (mode) {
          McpMode.modern => _discover(),
          McpMode.legacy => _initialize(McpMode.legacy),
          McpMode.sse => _connectSse(),
        };
        return _info = info;
      } on McpException catch (e) {
        _dropSse();
        _sessionId = null;
        // 这几种换个连接方式也没用：直接报
        if (const {McpFailure.auth, McpFailure.unreachable, McpFailure.timeout, McpFailure.redirect, McpFailure.policy}.contains(e.kind)) rethrow;
        // 服务器明说了它认哪些版本，而且里面没有我们会的：也不用再试
        if (e.kind == McpFailure.unsupported && mode != McpMode.modern) rethrow;
        if (e.kind == McpFailure.unsupported) versionProblem ??= e;
        last = e;
      }
    }
    // 服务器明说过“版本对不上”的话，这句比后面几次试连的报错更有用
    if (versionProblem != null) throw versionProblem;
    final e = last!;
    if (tries.length == 1) throw e;
    throw McpException(e.kind, '这个地址不像 MCP 服务器：${tries.length} 种连接方式都试过了，都没接上。最后一次的原因：${e.message}', status: e.status, code: e.code);
  }

  // ── 新版：没有握手，问一句“你支持哪些版本” ────────────────────────
  Future<McpServerInfo> _discover() async {
    final Map<String, dynamic> result;
    try {
      result = await _post(McpMode.modern, 'server/discover', null);
    } on McpException catch (e) {
      // 服务器是新版，但不认我们的版本号：看它列出来的版本里有没有老版本能握手
      if (e.code == -32022) {
        final data = e.data;
        final supported = data is Map && data['supported'] is List ? [...(data['supported'] as List).whereType<String>()] : const <String>[];
        throw McpException(McpFailure.unsupported, '服务器 $_host 不支持本应用用的协议版本 $kMcpModernVersion${supported.isEmpty ? '' : '（它支持：${supported.join('、')}）'}', code: e.code);
      }
      rethrow;
    }
    final versions = result['supportedVersions'];
    if (versions is! List) throw McpException(McpFailure.badReply, '服务器 $_host 的回答里没有“支持的版本”，不像新版 MCP 服务器');
    if (!versions.contains(kMcpModernVersion)) {
      throw McpException(McpFailure.unsupported, '服务器 $_host 不支持本应用用的协议版本 $kMcpModernVersion（它支持：${versions.whereType<String>().join('、')}）');
    }
    final meta = result['_meta'];
    final server = meta is Map ? meta[_kServerKey] : null;
    return McpServerInfo(mode: McpMode.modern, protocolVersion: kMcpModernVersion, name: _str(server, 'name'), version: _str(server, 'version'));
  }

  // ── 老版：initialize 握手 → notifications/initialized ─────────────
  Future<McpServerInfo> _initialize(McpMode mode) async {
    _sessionId = null;
    final result = await _request(mode, 'initialize', {'protocolVersion': kMcpLegacyVersion, 'capabilities': <String, dynamic>{}, 'clientInfo': _clientInfo}, handshake: true);
    final version = result['protocolVersion'];
    if (version is! String || !kMcpLegacyVersions.contains(version)) {
      throw McpException(McpFailure.unsupported, '服务器 $_host 要用的协议版本（${version is String ? version : '没写'}）本应用不支持。本应用支持：$kMcpModernVersion、${kMcpLegacyVersions.join('、')}');
    }
    _legacyVersion = version;
    final server = result['serverInfo'];
    final info = McpServerInfo(mode: mode, protocolVersion: version, name: _str(server, 'name'), version: _str(server, 'version'));
    _info = info; // 后面这条通知要带上谈好的版本号
    await _notify(mode, 'notifications/initialized');
    return info;
  }

  static String _str(Object? map, String key) {
    final v = map is Map ? map[key] : null;
    return v is String ? (v.length > 80 ? '${v.substring(0, 80)}…' : v) : '';
  }

  // ── 旧版 HTTP+SSE：先开一条长连接，等服务器告诉我们往哪发 ─────────────
  Future<McpServerInfo> _connectSse() async {
    final res = await _wire.open('GET', url, extra: const {'Accept': 'text/event-stream'});
    if (res.statusCode >= 400) {
      final text = await _wire.readText(res, maxBytes: 64 * 1024);
      throw _httpError(res.statusCode, [
        {'_raw': _wire.scrub(text.trim())},
      ]);
    }
    if (!McpWire.isEventStream(res)) {
      throw McpException(McpFailure.badReply, '服务器 $_host 没有按旧版 SSE 的方式回应（回的不是事件流）。多半是地址不对，旧版的地址通常以 /sse 结尾');
    }
    final link = _SseLink(this);
    _sse = link;
    link.listen(_wire.events(res, idle: false));
    final Uri endpoint;
    try {
      endpoint = await link.endpoint.future.timeout(timeouts.headers);
    } on TimeoutException {
      throw McpException(McpFailure.timeout, '超时：连上了 $_host，但等了 ${timeouts.headers.inSeconds} 秒它没告诉我们往哪里发消息');
    }
    if (!sameOrigin(endpoint, url)) {
      throw McpException(McpFailure.redirect, '服务器 $_host 让我们把消息发到另一个主机（${endpoint.host}）。为了不把令牌发给别的主机，没有照做');
    }
    link.postUrl = endpoint;
    return _initialize(McpMode.sse);
  }

  void _dropSse() {
    _sse?.close();
    _sse = null;
  }

  // ── 对外的三件事 ────────────────────────────────────
  /// 列出服务器上的工具（自动翻页）。参数说明标得不合规矩的工具会被去掉。
  Future<List<McpToolInfo>> listTools() async {
    final info = await connect();
    final tools = <McpToolInfo>[];
    final seenCursors = <String>{};
    String? cursor;
    for (var page = 0; page < kMcpMaxToolPages && tools.length < kMcpMaxTools; page++) {
      final result = await _request(info.mode, 'tools/list', cursor == null ? null : {'cursor': cursor});
      final list = result['tools'];
      if (list is! List) throw McpException(McpFailure.badReply, '服务器 $_host 回的工具清单格式不对（没有 tools 这一项）');
      for (final item in list) {
        final tool = McpToolInfo.fromJson(item);
        if (tool == null || tools.any((t) => t.name == tool.name)) continue;
        if (mcpParamHeaders(tool.inputSchema) == null) continue;
        tools.add(tool);
        if (tools.length >= kMcpMaxTools) break;
      }
      final next = result['nextCursor'];
      if (next is! String || next.isEmpty || !seenCursors.add(next)) break;
      cursor = next;
    }
    return tools;
  }

  /// 调用一个工具。[schema] 是这个工具的参数说明（新版要靠它决定哪些参数同时放进请求头）。
  Future<McpCallResult> callTool(String name, Map<String, dynamic> arguments, {Map<String, dynamic>? schema}) async {
    final info = await connect();
    final extra = <String, String>{};
    if (info.mode == McpMode.modern && schema != null) {
      final marks = mcpParamHeaders(schema);
      if (marks == null) throw McpException(McpFailure.unsupported, '工具 $name 的参数说明不合规范，不能调用');
      for (final e in marks.entries) {
        Object? v = arguments;
        for (final key in e.key) {
          v = v is Map ? v[key] : null;
        }
        if (v is String || v is int || v is bool) extra['Mcp-Param-${e.value}'] = mcpHeaderValue('$v');
      }
    }
    final result = await _request(info.mode, 'tools/call', {'name': name, 'arguments': arguments}, name: name, extra: extra, wait: timeouts.callHeaders);
    return McpCallResult.fromResult(result);
  }

  /// 问一句“还在吗”。新版协议没有 ping 这个方法，改问一次 server/discover。
  Future<void> ping() async {
    final info = await connect();
    await _request(info.mode, info.mode == McpMode.modern ? 'server/discover' : 'ping', null);
  }

  /// 收尾：有会话就告诉服务器结束了（对方不理也没关系），关掉连接。
  Future<void> close() async {
    final session = _sessionId;
    _sessionId = null;
    _dropSse();
    if (session != null && _info?.mode == McpMode.legacy) {
      try {
        final res = await _wire.open('DELETE', url, extra: {'Mcp-Session-Id': session, 'MCP-Protocol-Version': _legacyVersion}, headerTimeout: timeouts.close);
        await res.stream.listen((_) {}, onError: (Object _) {}).cancel();
      } on McpException {
        // 服务器可以不支持主动结束会话（会回 405）；连不上也无所谓，反正要关了
      }
    }
    _info = null;
    _wire.close();
  }

  // ── 发请求 ──────────────────────────────────────
  /// 发一个请求并拿到 result。握手版遇到“会话过期”（带着会话号却 404）会重新握手再试一次。
  Future<Map<String, dynamic>> _request(McpMode mode, String method, Map<String, dynamic>? params, {String? name, Map<String, String> extra = const {}, Duration? wait, bool handshake = false}) async {
    if (mode == McpMode.sse) return _sseRequest(method, params, wait ?? timeouts.headers);
    try {
      return await _post(mode, method, params, name: name, extra: extra, wait: wait);
    } on McpException catch (e) {
      if (mode == McpMode.legacy && !handshake && e.status == 404 && _sessionId != null) {
        _info = null;
        await _initialize(McpMode.legacy);
        return _post(mode, method, params, name: name, extra: extra, wait: wait);
      }
      rethrow;
    }
  }

  Map<String, String> _headersFor(McpMode mode, String method, String? name) => switch (mode) {
    McpMode.modern => {'MCP-Protocol-Version': kMcpModernVersion, 'Mcp-Method': method, if (name != null) 'Mcp-Name': mcpHeaderValue(name)},
    _ => {if (_info != null) 'MCP-Protocol-Version': _legacyVersion, 'Mcp-Session-Id': ?_sessionId},
  };

  Map<String, dynamic> _body(McpMode mode, Object? id, String method, Map<String, dynamic>? params) {
    final p = <String, dynamic>{...?params};
    if (mode == McpMode.modern) {
      p['_meta'] = {_kVersionKey: kMcpModernVersion, _kCapsKey: <String, dynamic>{}, _kClientKey: _clientInfo};
    }
    return {'jsonrpc': '2.0', 'id': ?id, 'method': method, if (p.isNotEmpty) 'params': p};
  }

  Future<Map<String, dynamic>> _post(McpMode mode, String method, Map<String, dynamic>? params, {String? name, Map<String, String> extra = const {}, Duration? wait}) async {
    final id = _nextId++;
    final reply = await _wire.post(url, _body(mode, id, method, params), extra: {..._headersFor(mode, method, name), ...extra}, headerTimeout: wait);
    if (reply.status >= 400) {
      final msgs = await reply.messages.toList();
      final rpc = msgs.where((m) => m['error'] is Map).firstOrNull;
      if (rpc != null && reply.status != 401 && reply.status != 403) throw _rpcError(rpc['error'] as Map, status: reply.status);
      throw _httpError(reply.status, msgs);
    }
    if (method == 'initialize') {
      final session = reply.headers['mcp-session-id'];
      // 会话号只许是可见 ASCII；不合规矩的不用
      if (session != null && session.isNotEmpty && session.length <= 512 && session.codeUnits.every((c) => c >= 0x21 && c <= 0x7E)) _sessionId = session;
    }
    await for (final msg in reply.messages) {
      final answer = _handleIncoming(mode, msg, id);
      if (answer != null) return answer;
    }
    throw McpException(McpFailure.badReply, '服务器 $_host 没给出结果就结束了回复');
  }

  /// 看一条收到的消息：是我们等的回答就返回 result（或抛错）；是夹带的通知 / 请求就处理掉，返回 null。
  Map<String, dynamic>? _handleIncoming(McpMode mode, Map<String, dynamic> msg, Object expectId) {
    final method = msg['method'];
    if (method is String) {
      final Object? id = msg['id'];
      // 通知：忽略。请求：老版要回一句；新版规定服务器不许发，忽略。
      if (id != null && mode != McpMode.modern) unawaited(_answerServerRequest(mode, id, method));
      return null;
    }
    if (msg['id'] != expectId && '${msg['id']}' != '$expectId') return null;
    final error = msg['error'];
    if (error is Map) throw _rpcError(error);
    final result = msg['result'];
    if (result is! Map<String, dynamic>) throw McpException(McpFailure.badReply, '服务器 $_host 的回答格式不对（没有 result）');
    final type = result['resultType'];
    if (type == 'input_required') {
      throw McpException(McpFailure.unsupported, '服务器 $_host 要求先补充额外的输入（比如让你确认或填写内容）才肯继续。本应用这一版还不支持这种交互');
    }
    if (type != null && type != 'complete') throw McpException(McpFailure.badReply, '服务器 $_host 的回答类型（$type）本应用不认识');
    return result;
  }

  /// 服务器在回复流里向我们提的请求：ping 回空结果，别的一律“不支持”。回不出去就算了。
  Future<void> _answerServerRequest(McpMode mode, Object id, String method) async {
    final body = method == 'ping'
        ? {'jsonrpc': '2.0', 'id': id, 'result': <String, dynamic>{}}
        : {
            'jsonrpc': '2.0',
            'id': id,
            'error': {'code': -32601, 'message': 'Method not supported by this client: $method'},
          };
    try {
      final target = mode == McpMode.sse ? _sse?.postUrl : url;
      if (target == null) return;
      final reply = await _wire.post(target, body, extra: _headersFor(mode, method, null), headerTimeout: timeouts.close);
      await reply.messages.drain<void>();
    } on McpException {
      // 回不出去不影响我们自己的请求
    }
  }

  Future<void> _notify(McpMode mode, String method) async {
    final target = mode == McpMode.sse ? _sse?.postUrl : url;
    if (target == null) return;
    final reply = await _wire.post(target, _body(mode, null, method, null), extra: _headersFor(mode, method, null));
    final msgs = await reply.messages.toList();
    if (reply.status >= 400) throw _httpError(reply.status, msgs);
  }

  Future<Map<String, dynamic>> _sseRequest(String method, Map<String, dynamic>? params, Duration wait) async {
    final link = _sse;
    final target = link?.postUrl;
    if (link == null || target == null || link.closed) throw McpException(McpFailure.unreachable, '和服务器 $_host 的连接已经断开');
    final id = _nextId++;
    final waiter = link.expect(id);
    try {
      final reply = await _wire.post(target, _body(McpMode.sse, id, method, params), extra: _headersFor(McpMode.sse, method, null), headerTimeout: wait);
      final msgs = await reply.messages.toList();
      if (reply.status >= 400) {
        final rpc = msgs.where((m) => m['error'] is Map).firstOrNull;
        if (rpc != null && reply.status != 401 && reply.status != 403) throw _rpcError(rpc['error'] as Map, status: reply.status);
        throw _httpError(reply.status, msgs);
      }
      // 有的服务器直接在 POST 的回复里给答案
      for (final m in msgs) {
        final direct = _handleIncoming(McpMode.sse, m, id);
        if (direct != null) return direct;
      }
      final msg = await waiter.timeout(wait);
      final result = _handleIncoming(McpMode.sse, msg, id);
      if (result == null) throw McpException(McpFailure.badReply, '服务器 $_host 的回答格式不对');
      return result;
    } on TimeoutException {
      throw McpException(McpFailure.timeout, '超时：等了 ${wait.inSeconds} 秒，服务器 $_host 没有给出结果');
    } finally {
      link.forget(id);
    }
  }

  McpException _rpcError(Map<dynamic, dynamic> error, {int? status}) {
    final code = error['code'];
    final message = error['message'];
    final text = message is String && message.trim().isNotEmpty ? _wire.scrub(message.trim()) : '没有说明';
    return McpException(
      McpFailure.rpc,
      '服务器 $_host 报错${code is int ? '（代码 $code）' : ''}：${text.length > 300 ? '${text.substring(0, 300)}…' : text}',
      status: status,
      code: code is int ? code : null,
      data: error['data'],
    );
  }

  McpException _httpError(int status, List<Map<String, dynamic>> msgs) {
    final raw = msgs.map((m) => m['_raw']).whereType<String>().firstOrNull ?? '';
    final tail = raw.isEmpty ? '' : '。服务器原话：${raw.length > 200 ? '${raw.substring(0, 200)}…' : raw}';
    return switch (status) {
      401 || 403 => McpException(McpFailure.auth, '服务器 $_host 拒绝了请求（$status）：令牌不对、过期了，或者没填。到“设置 › MCP 服务器”里检查这个服务器的请求头', status: status),
      404 => McpException(McpFailure.http, '地址不对：服务器 $_host 上没有这个路径（404）$tail', status: status),
      405 => McpException(McpFailure.http, '服务器 $_host 不接受这种请求（405），多半是地址或连接方式不对$tail', status: status),
      429 => McpException(McpFailure.http, '服务器 $_host 说请求太频繁了（429），过一会儿再试$tail', status: status),
      >= 500 => McpException(McpFailure.http, '服务器 $_host 自己出错了（$status）$tail', status: status),
      _ => McpException(McpFailure.http, '服务器 $_host 回了错误（$status）$tail', status: status),
    };
  }
}

/// 旧版 HTTP+SSE 的那条长连接：收服务器发来的消息，按 id 交给等它的请求。
class _SseLink {
  _SseLink(this.client);
  final McpClient client;
  final Completer<Uri> endpoint = Completer<Uri>();
  final Map<String, Completer<Map<String, dynamic>>> _waiting = {};
  StreamSubscription<Object?>? _sub;
  Uri? postUrl;
  bool closed = false;

  void listen(Stream<SseEvent> events) {
    _sub = events.listen(
      (e) {
        final event = e.event;
        final data = e.data;
        if (event == 'endpoint') {
          if (!endpoint.isCompleted) endpoint.complete(client.url.resolve(data.trim()));
          return;
        }
        if (event != 'message') return;
        final List<Map<String, dynamic>> msgs;
        try {
          msgs = client._wire.decodeMessages(data, client._host);
        } on McpException {
          return; // 一条坏消息不影响别的
        }
        for (final msg in msgs) {
          if (msg['method'] is String) {
            client._handleIncoming(McpMode.sse, msg, -1);
            continue;
          }
          final waiter = _waiting.remove('${msg['id']}');
          if (waiter != null && !waiter.isCompleted) waiter.complete(msg);
        }
      },
      onError: (Object e) => _fail(e is McpException ? e : McpException(McpFailure.unreachable, '和服务器 ${client._host} 的连接中断了')),
      onDone: () => _fail(McpException(McpFailure.unreachable, '服务器 ${client._host} 关掉了连接')),
      cancelOnError: true,
    );
  }

  Future<Map<String, dynamic>> expect(int id) {
    final c = Completer<Map<String, dynamic>>();
    // 没人等的时候出错也不算“没人接的异常”
    unawaited(c.future.then<void>((_) {}, onError: (Object _) {}));
    _waiting['$id'] = c;
    return c.future;
  }

  void forget(int id) => _waiting.remove('$id');

  void _fail(McpException e) {
    closed = true;
    if (!endpoint.isCompleted) {
      unawaited(endpoint.future.then<void>((_) {}, onError: (Object _) {}));
      endpoint.completeError(e);
    }
    for (final w in _waiting.values) {
      if (!w.isCompleted) w.completeError(e);
    }
    _waiting.clear();
  }

  void close() {
    closed = true;
    // 取消时连接正被关掉，流那头可能再报一次“连接断了”：已经不关心了，接住别让它变成没人管的异常。
    unawaited(_sub?.cancel().then<void>((_) {}, onError: (Object _) {}));
    _sub = null;
    _fail(McpException(McpFailure.unreachable, '连接已经关闭'));
  }
}
