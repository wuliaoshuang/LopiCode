// MCP 的网络层：发一个 POST / GET，守住超时、重定向、返回内容大小，把回来的东西变成一条条 JSON 消息。
// 协议细节（方法名、头名、版本号）在 mcp_client.dart；出处见 docs/api-notes.md 的“MCP”一节。
//
// 安全规矩（别改松）：
// - 只连 https，或 http 指向本机 / 局域网（[mcpUrlProblem]）。
// - 不自动跟重定向：同一个主机的 307 / 308 最多跟 [McpWire.maxRedirects] 次，转去别的主机一律拒绝（请求头里常带令牌）。
// - 报错文字出门前都过 [McpWire.scrub]：把请求头的值换成 ***，再过一遍 redactSecrets。网址只报主机名。
// - 每一步都有超时：连接、等响应头、流空闲。超时后把连接整个关掉重开，不留半截请求。
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:lopicode/agent/mcp/mcp_sse.dart';
import 'package:lopicode/agent/provider_presets.dart';
import 'package:lopicode/core/crash_log.dart';

/// 失败的种类（界面按它给“下一步怎么办”）。
enum McpFailure {
  /// 地址不合规矩（不是 https、也不是本机 / 局域网）。
  policy,

  /// 连不上。
  unreachable,

  /// 超时。
  timeout,

  /// 401 / 403：没带对令牌。
  auth,

  /// 服务器要转去别的地址。
  redirect,

  /// HTTP 报错（4xx / 5xx）。
  http,

  /// 返回的不是合法 JSON / 不是 MCP 的消息。
  badReply,

  /// 服务器按协议回了错误（JSON-RPC error）。
  rpc,

  /// 服务器要的功能这一版没做（协议版本谈不拢、要求额外输入）。
  unsupported,
}

class McpException implements Exception {
  McpException(this.kind, this.message, {this.status, this.code, this.data, this.body});
  final McpFailure kind;

  /// 一句人话（已经抹过密钥）。
  final String message;
  final int? status;

  /// JSON-RPC 的错误码。
  final int? code;
  final Object? data;

  /// 出错时服务器回的 JSON（如果是 JSON）。
  final Object? body;

  @override
  String toString() => message;
}

/// 几个等待时间。数值是自己定的（规范只说“应该设超时”），理由见 docs/api-notes.md。
class McpTimeouts {
  const McpTimeouts({
    this.connect = const Duration(seconds: 10),
    this.headers = const Duration(seconds: 20),
    this.callHeaders = const Duration(seconds: 120),
    this.idle = const Duration(seconds: 60),
    this.close = const Duration(seconds: 5),
  });

  /// 建立连接。
  final Duration connect;

  /// 握手、列工具、ping：发出请求后等响应头。
  final Duration headers;

  /// 调用工具：等响应头（服务器可能干完活才回，所以放宽）。
  final Duration callHeaders;

  /// 响应流里两段内容之间最多隔多久。
  final Duration idle;

  /// 收尾（告诉服务器会话结束）最多等多久。
  final Duration close;
}

/// 一次回复最多读多少字节（4 MB）。
const int kMcpMaxBodyBytes = 4 * 1024 * 1024;

/// 这个地址能不能连：能连返回 null，不能连返回原因。
String? mcpUrlProblem(String url) {
  final text = url.trim();
  if (text.isEmpty) return '还没填服务器地址';
  final uri = Uri.tryParse(text);
  if (uri == null || uri.host.isEmpty || !(uri.isScheme('https') || uri.isScheme('http'))) return '地址要以 https:// 开头（本机或局域网的服务可以用 http://）';
  if (uri.userInfo.isNotEmpty) return '地址里不要带用户名和密码；令牌请填在“请求头”里';
  if (uri.isScheme('http') && !isLocalBaseUrl(text)) return '外网的服务器必须用 https://。http:// 只允许连本机或局域网（比如 192.168.x.x）';
  return null;
}

/// 两个地址是不是同一个主机（协议、主机名、端口都一样）。
bool sameOrigin(Uri a, Uri b) => a.scheme == b.scheme && a.host.toLowerCase() == b.host.toLowerCase() && a.port == b.port;

/// 一次请求的回复。[messages] 是回复里的 JSON 消息（普通 JSON 回复就一条；SSE 流可以有很多条）。
class McpReply {
  McpReply(this.status, this.headers, this.messages);
  final int status;
  final Map<String, String> headers;
  final Stream<Map<String, dynamic>> messages;
}

class McpWire {
  McpWire({Map<String, String> headers = const {}, this.timeouts = const McpTimeouts(), http.Client Function()? clientFactory}) : _secretHeaders = Map.unmodifiable(headers), _factory = clientFactory;

  static const int maxRedirects = 2;

  final Map<String, String> _secretHeaders;
  final McpTimeouts timeouts;
  final http.Client Function()? _factory;
  http.Client? _client;
  bool _closed = false;

  http.Client get _http => _client ??= _factory?.call() ?? IOClient(HttpClient()..connectionTimeout = timeouts.connect);

  /// 超时 / 出错后：把连接关掉，下次用新的。
  void _reset() {
    _client?.close();
    _client = null;
  }

  void close() {
    _closed = true;
    _reset();
  }

  /// 把文字里可能带出来的令牌抹掉（服务器有时会把收到的头原样写进报错）。
  String scrub(String text) {
    var out = text;
    for (final v in _secretHeaders.values) {
      final value = v.trim();
      if (value.length >= 4) out = out.replaceAll(value, '***');
      // “Bearer xxx” 这种，只把后半截也单独抹一次
      final space = value.lastIndexOf(' ');
      if (space > 0 && value.length - space - 1 >= 4) out = out.replaceAll(value.substring(space + 1), '***');
    }
    return redactSecrets(out);
  }

  static String _clip(String s, [int max = 300]) => s.length > max ? '${s.substring(0, max)}…' : s;

  /// 发请求、等响应头。[body] 为 null 时发 GET。重定向、超时、连不上都在这里变成 [McpException]。
  Future<http.StreamedResponse> open(String method, Uri url, {Object? body, Map<String, String> extra = const {}, Duration? headerTimeout}) async {
    if (_closed) throw McpException(McpFailure.unreachable, '连接已经关闭');
    final problem = mcpUrlProblem('$url');
    if (problem != null) throw McpException(McpFailure.policy, problem);
    var target = url;
    for (var hop = 0; ; hop++) {
      final req = http.Request(method, target)
        ..followRedirects = false
        ..headers.addAll(_secretHeaders)
        ..headers.addAll(extra);
      if (body != null) {
        req.headers['Content-Type'] = 'application/json';
        req.bodyBytes = utf8.encode(jsonEncode(body));
      }
      final http.StreamedResponse res;
      final wait = headerTimeout ?? timeouts.headers;
      try {
        res = await _http.send(req).timeout(wait);
      } on TimeoutException {
        _reset();
        throw McpException(McpFailure.timeout, '超时：等了 ${wait.inSeconds} 秒，服务器 ${target.host} 没有回应');
      } on SocketException catch (e) {
        _reset();
        throw McpException(McpFailure.unreachable, '连不上服务器 ${target.host}（${scrub(_clip(e.message, 120))}）');
      } on HandshakeException {
        _reset();
        throw McpException(McpFailure.unreachable, '和服务器 ${target.host} 建立加密连接失败（证书有问题，或者对方不是 https 服务）');
      } on TlsException {
        _reset();
        throw McpException(McpFailure.unreachable, '和服务器 ${target.host} 建立加密连接失败');
      } on http.ClientException catch (e) {
        _reset();
        throw McpException(McpFailure.unreachable, '连不上服务器 ${target.host}（${scrub(_clip(e.message, 120))}）');
      } on HttpException catch (e) {
        _reset();
        throw McpException(McpFailure.unreachable, '和服务器 ${target.host} 的连接出错（${scrub(_clip(e.message, 120))}）');
      }
      if (res.statusCode < 300 || res.statusCode >= 400) return res;
      // 3xx：先把这次的回复丢掉，再决定跟不跟
      await _drain(res);
      final location = res.headers['location'];
      final next = location == null ? null : Uri.tryParse(location);
      final resolved = next == null ? null : target.resolveUri(next);
      if (resolved == null) throw McpException(McpFailure.redirect, '服务器 ${target.host} 回了一个转向（${res.statusCode}），但没说转去哪', status: res.statusCode);
      if (!sameOrigin(resolved, url)) {
        throw McpException(McpFailure.redirect, '服务器 ${url.host} 想把请求转到另一个地址（${resolved.host}）。为了不把令牌发给别的主机，没有跟过去。确认无误的话，请把服务器地址直接改成新地址', status: res.statusCode);
      }
      if ((res.statusCode != 307 && res.statusCode != 308) || hop >= maxRedirects) {
        throw McpException(McpFailure.redirect, '服务器 ${url.host} 一直在转向（${res.statusCode} → ${resolved.path}），没有跟过去。请把服务器地址改成最终的地址', status: res.statusCode);
      }
      target = resolved;
    }
  }

  Future<void> _drain(http.StreamedResponse res) async {
    try {
      await res.stream.listen((_) {}, onError: (Object _) {}).cancel();
    } on Exception {
      // 丢弃回复时出错：不影响后面的判断
    }
  }

  /// 把回复整个读成文字（有大小上限和空闲超时）。
  Future<String> readText(http.StreamedResponse res, {int maxBytes = kMcpMaxBodyBytes}) async {
    final host = res.request?.url.host ?? '';
    final bytes = BytesBuilder(copy: false);
    try {
      await for (final chunk in res.stream.cast<List<int>>().timeout(timeouts.idle)) {
        bytes.add(chunk);
        if (bytes.length > maxBytes) {
          _reset();
          throw McpException(McpFailure.badReply, '服务器 $host 回的内容太大（超过 ${maxBytes ~/ (1024 * 1024)} MB），已经断开');
        }
      }
    } on TimeoutException {
      _reset();
      throw McpException(McpFailure.timeout, '超时：服务器 $host 回到一半停了 ${timeouts.idle.inSeconds} 秒没有新内容');
    } on http.ClientException catch (e) {
      _reset();
      throw McpException(McpFailure.unreachable, '和服务器 $host 的连接中断了（${scrub(_clip(e.message, 120))}）');
    } on SocketException catch (e) {
      _reset();
      throw McpException(McpFailure.unreachable, '和服务器 $host 的连接中断了（${scrub(_clip(e.message, 120))}）');
    } on HttpException catch (e) {
      _reset();
      throw McpException(McpFailure.unreachable, '和服务器 $host 的连接中断了（${scrub(_clip(e.message, 120))}）');
    }
    return utf8.decode(bytes.takeBytes(), allowMalformed: true);
  }

  /// 回复是不是 SSE 流。
  static bool isEventStream(http.BaseResponse res) => (res.headers['content-type'] ?? '').toLowerCase().startsWith('text/event-stream');

  /// SSE 流里的事件（带空闲超时；[idle] 传 null 表示这条流可以一直安静，比如旧版 SSE 的长连接）。
  Stream<SseEvent> events(http.StreamedResponse res, {required bool idle}) async* {
    final host = res.request?.url.host ?? '';
    final Stream<List<int>> raw = res.stream.cast<List<int>>();
    try {
      await for (final e in parseSse(idle ? raw.timeout(timeouts.idle) : raw)) {
        yield e;
      }
    } on TimeoutException {
      _reset();
      throw McpException(McpFailure.timeout, '超时：服务器 $host 的回复流停了 ${timeouts.idle.inSeconds} 秒没有新内容');
    } on SseTooLargeException catch (e) {
      _reset();
      throw McpException(McpFailure.badReply, '$e');
    } on http.ClientException catch (e) {
      throw McpException(McpFailure.unreachable, '和服务器 $host 的连接中断了（${scrub(_clip(e.message, 120))}）');
    } on SocketException catch (e) {
      throw McpException(McpFailure.unreachable, '和服务器 $host 的连接中断了（${scrub(_clip(e.message, 120))}）');
    } on HttpException catch (e) {
      throw McpException(McpFailure.unreachable, '和服务器 $host 的连接中断了（${scrub(_clip(e.message, 120))}）');
    }
  }

  /// 一段文字解析成 JSON 消息（一个对象，或者一组对象——老版本允许成批回）。不是合法 JSON 就报成人话。
  List<Map<String, dynamic>> decodeMessages(String text, String host) {
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      throw McpException(McpFailure.badReply, '服务器 $host 回的不是合法的 JSON（开头是：${scrub(_clip(text.trim(), 80))}）。多半是地址填错了，填成了网页地址');
    }
    if (decoded is Map<String, dynamic>) return [decoded];
    if (decoded is List) {
      return [
        for (final item in decoded)
          if (item is Map<String, dynamic>) item,
      ];
    }
    throw McpException(McpFailure.badReply, '服务器 $host 回的 JSON 不是 MCP 的消息格式');
  }

  /// POST 一条 JSON-RPC 消息，回来的东西整理成消息流。4xx / 5xx 不在这里抛（上层要看状态码决定怎么退），
  /// 但会把错误内容读出来放进 [McpReply.messages]（是 JSON 的话）。
  Future<McpReply> post(Uri url, Object body, {Map<String, String> extra = const {}, Duration? headerTimeout}) async {
    final res = await open('POST', url, body: body, extra: {'Accept': 'application/json, text/event-stream', ...extra}, headerTimeout: headerTimeout);
    final host = url.host;
    if (res.statusCode >= 400) {
      final text = await readText(res, maxBytes: 64 * 1024);
      List<Map<String, dynamic>> parsed;
      try {
        parsed = decodeMessages(text, host);
      } on McpException {
        parsed = [
          {'_raw': scrub(_clip(text.trim()))},
        ];
      }
      return McpReply(res.statusCode, res.headers, Stream.fromIterable(parsed));
    }
    if (isEventStream(res)) {
      return McpReply(res.statusCode, res.headers, events(res, idle: true).expand((e) => e.event == 'message' ? decodeMessages(e.data, host) : const <Map<String, dynamic>>[]));
    }
    // 202（通知已收下）或者别的没有内容的回复
    if (res.statusCode == 202 || res.statusCode == 204) {
      await _drain(res);
      return McpReply(res.statusCode, res.headers, const Stream.empty());
    }
    final text = await readText(res);
    if (text.trim().isEmpty) return McpReply(res.statusCode, res.headers, const Stream.empty());
    return McpReply(res.statusCode, res.headers, Stream.fromIterable(decodeMessages(text, host)));
  }
}
