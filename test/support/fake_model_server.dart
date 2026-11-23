import 'dart:convert';
import 'dart:io';

/// 一次模型回复的脚本：文字和 / 或若干工具调用。
class ScriptedReply {
  ScriptedReply({this.text, this.calls = const [], this.status = 200, this.errorBody, this.usage});

  /// 收尾块里的 usage；不给就发一个没有可用字段的 usage（当作“接口没返回用量”）。
  final Map<String, dynamic>? usage;
  final String? text;
  final List<ScriptedCall> calls;
  final int status;
  final String? errorBody;
}

class ScriptedCall {
  ScriptedCall(this.name, this.arguments, {this.id});
  final String name;

  /// 原样发出去的 arguments 字符串（可以故意给坏 JSON）。
  final String arguments;
  final String? id;
}

/// 本地假模型服务器：按 OpenAI Chat Completions 的流式格式回 SSE。
/// 回复按脚本顺序给；脚本用完后重复 [fallback]（用来模拟“模型停不下来”）。
class FakeModelServer {
  FakeModelServer(this.script, {this.fallback, this.rejectStreamOptions = false});

  /// 模拟不认 stream_options 的兼容接口：带了就回 400。
  final bool rejectStreamOptions;
  final List<ScriptedReply> script;
  final ScriptedReply? fallback;

  late HttpServer _server;
  final List<Map<String, dynamic>> requests = [];
  final List<String?> authHeaders = [];
  int _n = 0;

  String get baseUrl => 'http://127.0.0.1:${_server.port}/v1';

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen(_handle);
  }

  Future<void> stop() => _server.close(force: true);

  Future<void> _handle(HttpRequest req) async {
    if (req.method != 'POST' || req.uri.path != '/v1/chat/completions') {
      req.response.statusCode = 404;
      await req.response.close();
      return;
    }
    requests.add(jsonDecode(await utf8.decoder.bind(req).join()) as Map<String, dynamic>);
    authHeaders.add(req.headers.value('authorization'));
    if (rejectStreamOptions && requests.last.containsKey('stream_options')) {
      req.response.statusCode = 400;
      req.response.headers.contentType = ContentType.json;
      req.response.write('{"error":{"message":"Unknown parameter: stream_options"}}');
      await req.response.close();
      return;
    }
    final reply = _n < script.length ? script[_n] : fallback;
    _n++;
    if (reply == null) {
      req.response.statusCode = 500;
      req.response.write('{"error":{"message":"script exhausted"}}');
      await req.response.close();
      return;
    }
    if (reply.status != 200) {
      req.response.statusCode = reply.status;
      req.response.headers.contentType = ContentType.json;
      req.response.write(reply.errorBody ?? '{"error":{"message":"boom"}}');
      await req.response.close();
      return;
    }
    req.response.headers.contentType = ContentType('text', 'event-stream', charset: 'utf-8');
    void chunk(Map<String, dynamic> delta, [String? finish]) {
      req.response.write('data: ${jsonEncode({
        'id': 'chatcmpl-test',
        'object': 'chat.completion.chunk',
        'choices': [
          {'index': 0, 'delta': delta, 'finish_reason': finish},
        ],
      })}\n\n');
    }

    chunk({'role': 'assistant', 'content': ''});
    final text = reply.text;
    if (text != null) {
      // 拆成两半发，验证客户端会拼接。
      final mid = text.length ~/ 2;
      chunk({'content': text.substring(0, mid)});
      chunk({'content': text.substring(mid)});
    }
    for (var i = 0; i < reply.calls.length; i++) {
      final c = reply.calls[i];
      // 第一块带 id 和 name，arguments 分片到达（和真实接口一样）。
      chunk({
        'tool_calls': [
          {
            'index': i,
            'id': c.id ?? 'call_${_n}_$i',
            'type': 'function',
            'function': {'name': c.name, 'arguments': ''},
          },
        ],
      });
      final mid = c.arguments.length ~/ 2;
      for (final part in [c.arguments.substring(0, mid), c.arguments.substring(mid)]) {
        chunk({
          'tool_calls': [
            {
              'index': i,
              'function': {'arguments': part},
            },
          ],
        });
      }
    }
    chunk({}, reply.calls.isEmpty ? 'stop' : 'tool_calls');
    // 带 usage 的收尾块：choices 为空数组，客户端必须能跳过。
    // 和真实接口一样：只有请求里带了 stream_options.include_usage 才发。
    final opts = requests.last['stream_options'];
    if (opts is Map && opts['include_usage'] == true) {
      req.response.write('data: ${jsonEncode({'choices': [], 'usage': reply.usage ?? {'total_tokens': 1}})}\n\n');
    }
    req.response.write('data: [DONE]\n\n');
    await req.response.close();
  }
}
