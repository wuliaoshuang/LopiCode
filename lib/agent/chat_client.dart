import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:lopicode/agent/provider_presets.dart';
import 'package:lopicode/agent/quota.dart';
import 'package:lopicode/agent/usage.dart';

/// 流式回复里的一小块。字段名与 OpenAI Chat Completions 的
/// `chat.completion.chunk` 对应，见 docs/api-notes.md。
class ChatDelta {
  ChatDelta({this.content, this.reasoning, this.toolCalls = const [], this.finishReason, this.raw, this.usage, this.reasoningFromTag = false});

  /// [reasoning] 是从正文开头的 `<think>` 标签里剥出来的（见 think_tags.dart），不是接口单独给的思考字段：只显示，不带回给接口。
  final bool reasoningFromTag;

  /// 思考内容的增量（DeepSeek 等的 `reasoning_content`、Anthropic 的 thinking、Responses 的 reasoning summary）。
  /// 聊天页拿它显示“正在思考…”；DeepSeek 还要之后带回给接口。
  final String? reasoning;

  /// 这次请求的用量（接口在流的最后给；没给就一直是 null）。
  final TokenUsage? usage;
  final String? content;
  final List<ToolCallDelta> toolCalls;
  final String? finishReason;

  /// 这一轮回复在原协议里的完整样子（目前只有 Anthropic 用：思考块必须原样带回）。
  /// 由 Agent 存进对话记录的 `_raw` 字段，下一轮交还给同一协议的客户端。
  final Map<String, dynamic>? raw;
}

/// `choices[0].delta.tool_calls[]` 里的一项。`index` 是唯一可靠的拼接键，
/// `id` 和 `function.name` 只在该 index 的第一块里出现，`arguments` 分片到达。
class ToolCallDelta {
  ToolCallDelta({required this.index, this.id, this.name, this.arguments});
  final int index;
  final String? id;
  final String? name;
  final String? arguments;
}

class ChatApiException implements Exception {
  ChatApiException(this.message, {this.statusCode, this.transient = false});
  final String message;
  final int? statusCode;

  /// 临时性的失败（连不上、超时）：值得等一下再试。
  final bool transient;
  @override
  String toString() => message;
}

abstract class ChatClient {
  Stream<ChatDelta> streamChat({required List<Map<String, dynamic>> messages, List<Map<String, dynamic>> tools = const []});
}

/// 任意 OpenAI 兼容的 Chat Completions 接口。
class OpenAiChatClient implements ChatClient {
  OpenAiChatClient({
    required String baseUrl,
    required this.apiKey,
    required this.model,
    this.reasoningEffort,
    this.maxTokens,
    this.extraBody = const {},
    http.Client? httpClient,
    bool? deepSeekOfficial,
    bool? moonshotOfficial,
  }) : baseUrl = normalizeBaseUrl(baseUrl),
       deepSeekOfficial = deepSeekOfficial ?? isDeepSeekOfficial(baseUrl),
       moonshotOfficial = moonshotOfficial ?? presetForBaseUrl(baseUrl)?.id == 'moonshot',
       _http = httpClient ?? http.Client();

  final String baseUrl;
  final String apiKey;
  final String model;

  /// `reasoning_effort` 的值（`low` / `medium` / `high`，有的服务商还有 `max`、`none`），为空不发。
  final String? reasoningEffort;

  /// 这家服务商专属的思考参数（`enable_thinking`、`thinking: {type}` 之类），原样并进请求体。
  /// 发什么由 lib/agent/thinking_support.dart 按官方文档定；没核对过的服务商这里是空的。
  final Map<String, dynamic> extraBody;

  /// 最大输出，为空不发（各家兼容接口认的参数名不一样，默认不带最稳）。
  final int? maxTokens;
  final http.Client _http;

  /// 要不要带 `stream_options.include_usage`。接口明确不认这个参数时自动关掉。
  bool _askUsage = true;

  /// 接口地址是不是 DeepSeek 官方（测试里可以直接指定）。只有官方地址才发 DeepSeek 专有的参数：
  /// - 思考默认是开的：用户选了“关”就得明说 `thinking: {type: disabled}`；
  /// - 思考开着时，没存思考内容的旧 assistant 消息补一个空的 `reasoning_content`（官方文档没写这种情况，未核对）。
  final bool deepSeekOfficial;

  /// 接口地址是不是 Kimi 官方（api.moonshot.cn / api.moonshot.ai）。
  final bool moonshotOfficial;

  /// 要不要把存着的思考内容带回去：DeepSeek / Kimi 的官方地址，或者模型名里带 deepseek / kimi 的中转站。
  /// 规矩见 docs/api-notes.md「DeepSeek 思考模式」：带了 tools 的对话，之前 assistant 消息的 `reasoning_content` 都要原样带回，否则 400。
  /// Kimi 的思考模型同样要求把 assistant 消息连同 `reasoning_content` 原样带回（api-notes「2026-11-25 思考档位」）。
  bool get echoReasoning {
    final name = model.toLowerCase();
    return deepSeekOfficial || moonshotOfficial || name.contains('deepseek') || name.contains('kimi');
  }

  /// 去掉结尾的 `/`；用户如果把完整的 `/chat/completions` 贴进来也接受。
  static String normalizeBaseUrl(String raw) {
    var url = raw.trim();
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    const suffix = '/chat/completions';
    if (url.endsWith(suffix)) url = url.substring(0, url.length - suffix.length);
    return url;
  }

  @override
  Stream<ChatDelta> streamChat({required List<Map<String, dynamic>> messages, List<Map<String, dynamic>> tools = const []}) async* {
    if (baseUrl.isEmpty || model.trim().isEmpty) {
      throw ChatApiException('还没配置模型：请到“设置 → 模型与渠道”添加渠道和模型');
    }
    final Uri uri;
    try {
      uri = Uri.parse('$baseUrl/chat/completions');
      if (!uri.hasScheme || uri.host.isEmpty) throw const FormatException();
    } on FormatException {
      throw ChatApiException('接口地址不是合法的网址：$baseUrl');
    }
    http.Request build() {
      final request = http.Request('POST', uri)
        ..headers['Content-Type'] = 'application/json'
        ..headers['Accept'] = 'text/event-stream'
        ..body = jsonEncode({
          'model': model.trim(),
          'messages': echoReasoning ? withReasoningContent(messages, fillMissing: deepSeekOfficial && reasoningEffort != null) : stripInternal(messages),
          'stream': true,
          // 让接口在流的最后多发一块用量（choices 为空、带 usage）。
          if (_askUsage) 'stream_options': {'include_usage': true},
          if (reasoningEffort != null) 'reasoning_effort': reasoningEffort,
          if (reasoningEffort == null && deepSeekOfficial) 'thinking': {'type': 'disabled'},
          ...extraBody,
          if (maxTokens != null) 'max_tokens': maxTokens,
          if (tools.isNotEmpty) 'tools': tools,
          if (tools.isNotEmpty) 'tool_choice': 'auto',
        });
      if (apiKey.isNotEmpty) request.headers['Authorization'] = 'Bearer $apiKey';
      return request;
    }

    // 只报错误类型和主机，不带请求头，避免把 Key 带进界面或日志。
    Future<http.StreamedResponse> post() => sendChatRequest(_http, build());

    var response = await post();
    if (response.statusCode != 200) {
      var body = await response.stream.bytesToString();
      // 有的兼容接口不认 stream_options：去掉它重发一次，这个客户端之后也不再带（那就拿不到用量）。
      if (_askUsage && (response.statusCode == 400 || response.statusCode == 422) && body.contains('stream_options')) {
        _askUsage = false;
        response = await post();
        if (response.statusCode != 200) body = await response.stream.bytesToString();
      }
      if (response.statusCode != 200) throw ChatApiException(chatErrorMessage(response.statusCode, body), statusCode: response.statusCode);
    }

    final lines = guardChatStream(response.stream, uri.host).transform(utf8.decoder).transform(const LineSplitter());
    await for (final line in lines) {
      if (!line.startsWith('data:')) continue; // 空行、注释行、event: 行都跳过
      final data = line.substring(5).trim();
      if (data.isEmpty) continue;
      if (data == '[DONE]') return;
      final Object? json;
      try {
        json = jsonDecode(data);
      } on FormatException {
        continue;
      }
      if (json is! Map<String, dynamic>) continue;
      if (json['error'] is Map) {
        throw ChatApiException('模型接口报错：${(json['error'] as Map)['message'] ?? '未知错误'}');
      }
      final usage = usageFromChatCompletions(json['usage']);
      final choices = json['choices'];
      // 开了 include_usage 时最后一块 choices 是空数组，只带 usage。
      if (choices is! List || choices.isEmpty || choices.first is! Map) {
        if (usage != null) yield ChatDelta(usage: usage);
        continue;
      }
      final choice = choices.first as Map;
      final delta = choice['delta'];
      final calls = <ToolCallDelta>[];
      String? content;
      String? reasoning;
      if (delta is Map) {
        if (delta['content'] is String) content = delta['content'] as String;
        // 思考内容：DeepSeek 等叫 reasoning_content；有些兼容接口（OpenRouter 等）叫 reasoning（未核对，见 api-notes）。
        if (delta['reasoning_content'] is String) {
          reasoning = delta['reasoning_content'] as String;
        } else if (delta['reasoning'] is String) {
          reasoning = delta['reasoning'] as String;
        }
        final rawCalls = delta['tool_calls'];
        if (rawCalls is List) {
          for (var i = 0; i < rawCalls.length; i++) {
            final c = rawCalls[i];
            if (c is! Map) continue;
            final fn = c['function'];
            calls.add(
              ToolCallDelta(
                index: c['index'] is int ? c['index'] as int : i,
                id: c['id'] is String ? c['id'] as String : null,
                name: fn is Map && fn['name'] is String ? fn['name'] as String : null,
                arguments: fn is Map && fn['arguments'] is String ? fn['arguments'] as String : null,
              ),
            );
          }
        }
      }
      final finish = choice['finish_reason'];
      yield ChatDelta(content: content, reasoning: reasoning, toolCalls: calls, finishReason: finish is String ? finish : null, usage: usage);
    }
  }
}

/// 发给接口前去掉我们自己加的内部字段（以 `_` 开头的键）。
List<Map<String, dynamic>> stripInternal(List<Map<String, dynamic>> messages) => [
  for (final m in messages)
    {
      for (final e in m.entries)
        if (!e.key.startsWith('_')) e.key: e.value,
    },
];

/// DeepSeek：去掉内部字段，并把存着的思考内容（`_reasoning`）按接口要的名字 `reasoning_content` 带回去。
/// [fillMissing]（思考开着时）：没存思考内容的 assistant 消息（旧对话、压缩后的摘要）补一个空字符串。
List<Map<String, dynamic>> withReasoningContent(List<Map<String, dynamic>> messages, {required bool fillMissing}) => [
  for (final m in messages)
    {
      for (final e in m.entries)
        if (!e.key.startsWith('_')) e.key: e.value,
      // 从正文标签里剥出来的思考（`_reasoningTag`）接口没单独给过，不带回
      if (m['role'] == 'assistant' && m['_reasoning'] is String && m['_reasoningTag'] != true)
        'reasoning_content': m['_reasoning']
      else if (m['role'] == 'assistant' && fillMissing)
        'reasoning_content': '',
    },
];

/// 发出请求后，这么久还没收到接口的响应头就算连不上。
const Duration kChatConnectTimeout = Duration(seconds: 60);

/// 流式回复中途，这么久一个字节都没来就算断了（思考型模型会停顿很久，所以放得宽）。
const Duration kChatStallTimeout = Duration(minutes: 5);

/// 发请求并等响应头，带超时；连不上统一报成 [ChatApiException]（只带主机名，不带请求头）。
Future<http.StreamedResponse> sendChatRequest(http.Client client, http.BaseRequest request, {Duration timeout = kChatConnectTimeout}) async {
  final host = request.url.host;
  try {
    return await client.send(request).timeout(timeout);
  } on TimeoutException {
    throw ChatApiException('模型接口（$host）${timeout.inSeconds} 秒没有响应。检查网络和接口地址后再试。', transient: true);
  } on Exception catch (e) {
    throw ChatApiException('连不上模型接口（$host）：${shortError(e)}', transient: true);
  }
}

/// 给流式响应的字节流加“卡住超时”，并把中途断线报成 [ChatApiException]。
Stream<List<int>> guardChatStream(Stream<List<int>> bytes, String host, {Duration stall = kChatStallTimeout}) {
  return bytes
      .cast<List<int>>()
      .timeout(
        stall,
        onTimeout: (sink) {
          sink.addError(ChatApiException('模型接口（$host）已经 ${stall.inMinutes} 分钟没有新内容，连接可能断了。可以重新发送。'));
          sink.close();
        },
      )
      .handleError((Object e) => throw ChatApiException('和模型接口（$host）的连接中断了：${shortError(e)}'), test: (e) => e is! ChatApiException);
}

String shortError(Object e) {
  final s = e.toString();
  return s.length > 160 ? '${s.substring(0, 160)}…' : s;
}

/// 把接口的错误响应变成一句人话（不带请求头，不会泄露 Key）。
String chatErrorMessage(int status, String body) {
  String? detail;
  try {
    final json = jsonDecode(body);
    if (json is Map && json['error'] is Map) detail = '${(json['error'] as Map)['message']}';
    if (json is Map && json['error'] is String) detail = json['error'] as String;
  } on FormatException {
    detail = body.trim().isEmpty ? null : body.trim();
  }
  if (detail != null && detail.length > 300) detail = '${detail.substring(0, 300)}…';
  final reason = switch (status) {
    401 => 'API Key 无效或没填',
    403 => '没有权限访问这个模型',
    404 => '接口地址或模型名不对',
    429 => '请求太频繁或额度用完了',
    >= 500 => '模型服务端出错',
    _ => '请求被拒绝',
  };
  return '模型接口返回 $status：$reason${detail != null ? '（$detail）' : ''}';
}
