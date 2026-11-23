// 另外两种协议的客户端、模型列表、以及“按渠道配置造客户端”。
// 字段名的出处和核对情况见 docs/api-notes.md（2026-11-23 那一节）。
//
// 三种协议对外是同一个 [ChatClient]：进来的 messages / tools 一律是 OpenAI Chat Completions
// 的格式（对话记录就按这个格式存盘），各客户端自己转成本协议的样子。
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:lopicode/agent/chat_client.dart';
import 'package:lopicode/agent/model_config.dart';
import 'package:lopicode/agent/usage.dart';

/// 一条 SSE 事件。
class SseEvent {
  SseEvent(this.event, this.data);
  final String? event;
  final String data;
}

/// 把字节流切成 SSE 事件（`event:` 可有可无，`data:` 可以多行）。
Stream<SseEvent> sseEvents(Stream<List<int>> bytes) async* {
  String? event;
  final data = <String>[];
  await for (final line in bytes.cast<List<int>>().transform(utf8.decoder).transform(const LineSplitter())) {
    if (line.isEmpty) {
      if (data.isNotEmpty) yield SseEvent(event, data.join('\n'));
      event = null;
      data.clear();
    } else if (line.startsWith('event:')) {
      event = line.substring(6).trim();
    } else if (line.startsWith('data:')) {
      data.add(line.substring(5).trimLeft());
    }
  }
  if (data.isNotEmpty) yield SseEvent(event, data.join('\n'));
}

String _trimBase(String raw, List<String> suffixes) {
  var url = raw.trim();
  while (url.endsWith('/')) {
    url = url.substring(0, url.length - 1);
  }
  for (final s in suffixes) {
    if (url.endsWith(s)) url = url.substring(0, url.length - s.length);
  }
  return url;
}

Uri _endpoint(String base, String path) {
  if (base.isEmpty) throw ChatApiException('还没填接口地址');
  try {
    final uri = Uri.parse('$base$path');
    if (!uri.hasScheme || uri.host.isEmpty) throw const FormatException();
    return uri;
  } on FormatException {
    throw ChatApiException('接口地址不是合法的网址：$base');
  }
}

Future<http.StreamedResponse> _post(http.Client client, Uri uri, Map<String, String> headers, Object body) async {
  final request = http.Request('POST', uri)
    ..headers.addAll({'Content-Type': 'application/json', 'Accept': 'text/event-stream', ...headers})
    ..body = jsonEncode(body);
  final http.StreamedResponse response;
  try {
    response = await client.send(request);
  } on Exception catch (e) {
    throw ChatApiException('连不上模型接口（${uri.host}）：${shortError(e)}');
  }
  if (response.statusCode != 200) {
    final text = await response.stream.bytesToString();
    throw ChatApiException(chatErrorMessage(response.statusCode, text), statusCode: response.statusCode);
  }
  return response;
}

/// `data:<mime>;base64,<data>` → (mime, data)。
(String, String)? parseDataUrl(Object? url) {
  if (url is! String) return null;
  final m = RegExp(r'^data:([^;,]+);base64,(.*)$', dotAll: true).firstMatch(url);
  return m == null ? null : (m.group(1)!, m.group(2)!);
}

Map<String, dynamic> _decodeArgs(Object? raw) {
  if (raw is Map<String, dynamic>) return raw;
  if (raw is String && raw.trim().isNotEmpty) {
    try {
      final v = jsonDecode(raw);
      if (v is Map<String, dynamic>) return v;
    } on FormatException {
      // 模型给了坏 JSON：按空对象回传，工具层已经给过它报错了
    }
  }
  return <String, dynamic>{};
}

// ═══════════════════════════ Anthropic Messages ═══════════════════════════

/// 思考档位 → `budget_tokens`（自己定的换算，见 api-notes）。
int anthropicBudget(String level) => switch (level) {
  'low' => 4096,
  'medium' => 16384,
  _ => 32768,
};

/// OpenAI 格式的工具定义 → Anthropic 的 `tools`。
List<Map<String, dynamic>> anthropicTools(List<Map<String, dynamic>> tools) => [
  for (final t in tools)
    if (t['function'] case final Map fn)
      {'name': fn['name'], 'description': fn['description'] ?? '', 'input_schema': fn['parameters'] ?? {'type': 'object', 'properties': {}}},
];

/// OpenAI 格式的消息 → Anthropic 的 (`system`, `messages`)。
///
/// - system 消息合成顶层的 `system`；
/// - `role: tool` 变成 user 消息里的 `tool_result` 块；
/// - 连续的同角色消息合并成一条（工具结果后面紧跟的插话也并进同一条 user，`tool_result` 在前）；
/// - assistant 消息带着 `_raw`（上一轮 Anthropic 回复的原始内容块）时原样用它。
({String system, List<Map<String, dynamic>> messages}) anthropicMessages(
  List<Map<String, dynamic>> messages, {
  bool keepThinking = true,
}) {
  final system = <String>[];
  final out = <Map<String, dynamic>>[];
  void push(String role, List<Map<String, dynamic>> blocks) {
    if (blocks.isEmpty) return;
    if (out.isNotEmpty && out.last['role'] == role) {
      (out.last['content'] as List).addAll(blocks);
    } else {
      out.add({'role': role, 'content': blocks});
    }
  }

  List<Map<String, dynamic>> userBlocks(Object? content) {
    if (content is String) return content.isEmpty ? [] : [{'type': 'text', 'text': content}];
    final blocks = <Map<String, dynamic>>[];
    for (final part in content is List ? content : const []) {
      if (part is! Map) continue;
      if (part['type'] == 'text' && '${part['text'] ?? ''}'.isNotEmpty) {
        blocks.add({'type': 'text', 'text': '${part['text']}'});
      } else if (part['type'] == 'image_url') {
        final img = part['image_url'];
        final parsed = parseDataUrl(img is Map ? img['url'] : null);
        if (parsed != null) {
          blocks.add({
            'type': 'image',
            'source': {'type': 'base64', 'media_type': parsed.$1, 'data': parsed.$2},
          });
        }
      }
    }
    return blocks;
  }

  for (final m in messages) {
    switch (m['role']) {
      case 'system':
        if ('${m['content'] ?? ''}'.isNotEmpty) system.add('${m['content']}');
      case 'user':
        push('user', userBlocks(m['content']));
      case 'assistant':
        final raw = m['_raw'];
        if (raw is Map && raw['protocol'] == 'anthropic' && raw['content'] is List) {
          push('assistant', [
            for (final b in raw['content'] as List)
              if (b is Map<String, dynamic> && (keepThinking || (b['type'] != 'thinking' && b['type'] != 'redacted_thinking'))) b,
          ]);
          break;
        }
        final blocks = <Map<String, dynamic>>[];
        final text = m['content'];
        if (text is String && text.isNotEmpty) blocks.add({'type': 'text', 'text': text});
        for (final c in (m['tool_calls'] as List?) ?? const []) {
          if (c is! Map) continue;
          final fn = c['function'];
          blocks.add({
            'type': 'tool_use',
            'id': '${c['id']}',
            'name': fn is Map ? '${fn['name']}' : '',
            'input': _decodeArgs(fn is Map ? fn['arguments'] : null),
          });
        }
        push('assistant', blocks);
      case 'tool':
        final text = '${m['content'] ?? ''}';
        push('user', [
          {
            'type': 'tool_result',
            'tool_use_id': '${m['tool_call_id']}',
            'content': text,
            if (text.startsWith('错误') || text.startsWith('用户拒绝')) 'is_error': true,
          },
        ]);
    }
  }
  return (system: system.join('\n\n'), messages: out);
}

class AnthropicChatClient implements ChatClient {
  AnthropicChatClient({
    required String baseUrl,
    required this.apiKey,
    required this.model,
    required this.maxTokens,
    this.thinkingLevel,
    http.Client? httpClient,
  }) : baseUrl = _trimBase(baseUrl, const ['/messages']),
       _http = httpClient ?? http.Client();

  static const String apiVersion = '2023-06-01';

  final String baseUrl;
  final String apiKey;
  final String model;
  final int maxTokens;

  /// `low` / `medium` / `high`；为空不开思考。
  final String? thinkingLevel;
  final http.Client _http;

  @override
  Stream<ChatDelta> streamChat({
    required List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>> tools = const [],
  }) async* {
    if (model.trim().isEmpty) throw ChatApiException('还没选模型');
    final uri = _endpoint(baseUrl, '/messages');
    final thinking = thinkingLevel != null;
    final converted = anthropicMessages(messages, keepThinking: thinking);
    // 思考预算必须小于 max_tokens。
    final budget = thinking ? anthropicBudget(thinkingLevel!).clamp(1024, maxTokens > 2048 ? maxTokens - 1024 : 1024) : 0;
    final response = await _post(
      _http,
      uri,
      {'x-api-key': apiKey, 'anthropic-version': apiVersion},
      {
        'model': model.trim(),
        'max_tokens': maxTokens,
        'stream': true,
        if (converted.system.isNotEmpty) 'system': converted.system,
        'messages': converted.messages,
        if (tools.isNotEmpty) 'tools': anthropicTools(tools),
        if (thinking && maxTokens > 2048) 'thinking': {'type': 'enabled', 'budget_tokens': budget},
      },
    );

    final blocks = <int, Map<String, dynamic>>{};
    final partial = <int, StringBuffer>{};
    String? stop;
    Object? usageStart, usageDelta;
    await for (final ev in sseEvents(response.stream)) {
      final Object? json;
      try {
        json = jsonDecode(ev.data);
      } on FormatException {
        continue;
      }
      if (json is! Map<String, dynamic>) continue;
      switch (json['type']) {
        case 'error':
          final err = json['error'];
          throw ChatApiException('模型接口报错：${err is Map ? err['message'] ?? err['type'] : '未知错误'}');
        case 'content_block_start':
          final index = json['index'];
          final block = json['content_block'];
          if (index is! int || block is! Map) break;
          blocks[index] = Map<String, dynamic>.from(block);
          if (block['type'] == 'tool_use') {
            partial[index] = StringBuffer();
            yield ChatDelta(toolCalls: [ToolCallDelta(index: index, id: '${block['id']}', name: '${block['name']}')]);
          }
        case 'content_block_delta':
          final index = json['index'];
          final delta = json['delta'];
          final block = blocks[index];
          if (index is! int || delta is! Map || block == null) break;
          switch (delta['type']) {
            case 'text_delta':
              final t = '${delta['text'] ?? ''}';
              block['text'] = '${block['text'] ?? ''}$t';
              if (t.isNotEmpty) yield ChatDelta(content: t);
            case 'input_json_delta':
              final part = '${delta['partial_json'] ?? ''}';
              partial[index]?.write(part);
              yield ChatDelta(toolCalls: [ToolCallDelta(index: index, arguments: part)]);
            case 'thinking_delta':
              block['thinking'] = '${block['thinking'] ?? ''}${delta['thinking'] ?? ''}';
            case 'signature_delta':
              block['signature'] = '${block['signature'] ?? ''}${delta['signature'] ?? ''}';
          }
        case 'content_block_stop':
          final index = json['index'];
          final block = blocks[index];
          if (block != null && block['type'] == 'tool_use') block['input'] = _decodeArgs(partial[index]?.toString());
        case 'message_start':
          final message = json['message'];
          if (message is Map) usageStart = message['usage'];
        case 'message_delta':
          // usage 和 delta 平级，里面的数是累计值（覆盖，不相加）。
          if (json['usage'] is Map) usageDelta = json['usage'];
          final delta = json['delta'];
          if (delta is Map && delta['stop_reason'] is String) stop = delta['stop_reason'] as String;
        case 'message_stop':
          break;
        default:
          break; // ping 和以后新增的事件：跳过
      }
    }
    final ordered = [for (final k in blocks.keys.toList()..sort()) blocks[k]!];
    yield ChatDelta(
      finishReason: switch (stop) {
        'tool_use' => 'tool_calls',
        'max_tokens' => 'length',
        _ => 'stop',
      },
      raw: {'protocol': 'anthropic', 'content': ordered},
      usage: usageFromAnthropic(usageStart, usageDelta),
    );
  }
}

// ═══════════════════════════ OpenAI Responses ═══════════════════════════

/// OpenAI Chat 格式的工具定义 → Responses 的扁平格式。
List<Map<String, dynamic>> responsesTools(List<Map<String, dynamic>> tools) => [
  for (final t in tools)
    if (t['function'] case final Map fn)
      {
        'type': 'function',
        'name': fn['name'],
        'description': fn['description'] ?? '',
        'parameters': fn['parameters'] ?? {'type': 'object', 'properties': {}},
        'strict': false, // 我们的参数表有可选项，不满足严格模式的要求
      },
];

/// OpenAI Chat 格式的消息 → Responses 的 (`instructions`, `input`)。
({String instructions, List<Map<String, dynamic>> input}) responsesInput(List<Map<String, dynamic>> messages) {
  final system = <String>[];
  final input = <Map<String, dynamic>>[];
  for (final m in messages) {
    switch (m['role']) {
      case 'system':
        if ('${m['content'] ?? ''}'.isNotEmpty) system.add('${m['content']}');
      case 'user':
        final content = m['content'];
        final parts = <Map<String, dynamic>>[];
        if (content is String) {
          parts.add({'type': 'input_text', 'text': content});
        } else if (content is List) {
          for (final part in content) {
            if (part is! Map) continue;
            if (part['type'] == 'text') parts.add({'type': 'input_text', 'text': '${part['text'] ?? ''}'});
            if (part['type'] == 'image_url' && part['image_url'] is Map) {
              parts.add({'type': 'input_image', 'image_url': '${(part['image_url'] as Map)['url']}'});
            }
          }
        }
        if (parts.isNotEmpty) input.add({'role': 'user', 'content': parts});
      case 'assistant':
        final text = m['content'];
        if (text is String && text.isNotEmpty) {
          input.add({
            'role': 'assistant',
            'content': [
              {'type': 'output_text', 'text': text},
            ],
          });
        }
        for (final c in (m['tool_calls'] as List?) ?? const []) {
          if (c is! Map) continue;
          final fn = c['function'];
          input.add({
            'type': 'function_call',
            'call_id': '${c['id']}',
            'name': fn is Map ? '${fn['name']}' : '',
            'arguments': fn is Map ? '${fn['arguments'] ?? ''}' : '',
          });
        }
      case 'tool':
        input.add({'type': 'function_call_output', 'call_id': '${m['tool_call_id']}', 'output': '${m['content'] ?? ''}'});
    }
  }
  return (instructions: system.join('\n\n'), input: input);
}

class OpenAiResponsesClient implements ChatClient {
  OpenAiResponsesClient({
    required String baseUrl,
    required this.apiKey,
    required this.model,
    this.maxOutputTokens,
    this.reasoningEffort,
    http.Client? httpClient,
  }) : baseUrl = _trimBase(baseUrl, const ['/responses']),
       _http = httpClient ?? http.Client();

  final String baseUrl;
  final String apiKey;
  final String model;
  final int? maxOutputTokens;
  final String? reasoningEffort;
  final http.Client _http;

  @override
  Stream<ChatDelta> streamChat({
    required List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>> tools = const [],
  }) async* {
    if (model.trim().isEmpty) throw ChatApiException('还没选模型');
    final uri = _endpoint(baseUrl, '/responses');
    final converted = responsesInput(messages);
    final response = await _post(
      _http,
      uri,
      {if (apiKey.isNotEmpty) 'Authorization': 'Bearer $apiKey'},
      {
        'model': model.trim(),
        'input': converted.input,
        if (converted.instructions.isNotEmpty) 'instructions': converted.instructions,
        'stream': true,
        'store': false,
        if (maxOutputTokens != null) 'max_output_tokens': maxOutputTokens,
        if (reasoningEffort != null) 'reasoning': {'effort': reasoningEffort},
        if (tools.isNotEmpty) 'tools': responsesTools(tools),
      },
    );

    final gotArgs = <int>{}; // 收到过参数增量的输出项
    var sawCall = false;
    await for (final ev in sseEvents(response.stream)) {
      if (ev.data == '[DONE]') break; // 官方不发，有些兼容接口会发
      final Object? json;
      try {
        json = jsonDecode(ev.data);
      } on FormatException {
        continue;
      }
      if (json is! Map<String, dynamic>) continue;
      final index = json['output_index'] is int ? json['output_index'] as int : 0;
      switch (json['type'] ?? ev.event) {
        case 'response.output_text.delta':
          final t = json['delta'];
          if (t is String && t.isNotEmpty) yield ChatDelta(content: t);
        case 'response.output_item.added':
          final item = json['item'];
          if (item is Map && item['type'] == 'function_call') {
            sawCall = true;
            yield ChatDelta(
              toolCalls: [ToolCallDelta(index: index, id: '${item['call_id'] ?? item['id'] ?? ''}', name: '${item['name'] ?? ''}')],
            );
          }
        case 'response.function_call_arguments.delta':
          final d = json['delta'];
          if (d is String) {
            gotArgs.add(index);
            yield ChatDelta(toolCalls: [ToolCallDelta(index: index, arguments: d)]);
          }
        case 'response.output_item.done':
          // 有的接口不发增量，只在这里给完整参数。
          final item = json['item'];
          if (item is Map && item['type'] == 'function_call' && !gotArgs.contains(index)) {
            sawCall = true;
            yield ChatDelta(
              toolCalls: [
                ToolCallDelta(
                  index: index,
                  id: '${item['call_id'] ?? item['id'] ?? ''}',
                  name: '${item['name'] ?? ''}',
                  arguments: '${item['arguments'] ?? ''}',
                ),
              ],
            );
          }
        case 'response.failed':
        case 'error':
          final resp = json['response'];
          final err = json['error'] ?? (resp is Map ? resp['error'] : null);
          throw ChatApiException('模型接口报错：${err is Map ? err['message'] ?? '未知错误' : json['message'] ?? '未知错误'}');
        case 'response.incomplete':
          yield ChatDelta(finishReason: 'length', usage: _responseUsage(json));
          return;
        case 'response.completed':
          yield ChatDelta(finishReason: sawCall ? 'tool_calls' : 'stop', usage: _responseUsage(json));
          return;
      }
    }
  }
}

/// `response.completed` / `response.incomplete` 事件里的 `response.usage`。
TokenUsage? _responseUsage(Map<String, dynamic> event) {
  final resp = event['response'];
  return resp is Map ? usageFromResponses(resp['usage']) : null;
}

// ═══════════════════════════ 模型列表 / 测试连接 ═══════════════════════════

class RemoteModel {
  RemoteModel(this.id, [this.displayName]);
  final String id;
  final String? displayName;
}

/// 读渠道的模型列表。只发一个 GET，不产生对话费用；“测试连接”也是它。
Future<List<RemoteModel>> listRemoteModels({
  required ChatProtocol protocol,
  required String baseUrl,
  required String apiKey,
  http.Client? httpClient,
}) async {
  final client = httpClient ?? http.Client();
  final base = _trimBase(baseUrl, const ['/chat/completions', '/responses', '/messages', '/models']);
  final anthropic = protocol == ChatProtocol.anthropic;
  final uri = _endpoint(base, anthropic ? '/models?limit=1000' : '/models');
  final http.Response response;
  try {
    response = await client
        .get(
          uri,
          headers: anthropic
              ? {'x-api-key': apiKey, 'anthropic-version': AnthropicChatClient.apiVersion}
              : {if (apiKey.isNotEmpty) 'Authorization': 'Bearer $apiKey'},
        )
        .timeout(const Duration(seconds: 20));
  } on TimeoutException {
    throw ChatApiException('连接超时（${uri.host}）：20 秒没有回应');
  } on Exception catch (e) {
    throw ChatApiException('连不上接口（${uri.host}）：${shortError(e)}');
  } finally {
    if (httpClient == null) client.close();
  }
  if (response.statusCode != 200) {
    throw ChatApiException(
      chatErrorMessage(response.statusCode, utf8.decode(response.bodyBytes, allowMalformed: true)).replaceFirst('接口地址或模型名不对', '接口地址不对，或者这个服务不提供模型列表'),
      statusCode: response.statusCode,
    );
  }
  final Object? json;
  try {
    json = jsonDecode(utf8.decode(response.bodyBytes, allowMalformed: true));
  } on FormatException {
    throw ChatApiException('接口返回的不是模型列表（不是 JSON），请检查接口地址');
  }
  final data = json is Map ? json['data'] : json;
  if (data is! List) throw ChatApiException('接口返回的内容里没有模型列表，请检查接口地址');
  final out = <RemoteModel>[];
  for (final m in data) {
    if (m is Map && m['id'] is String) out.add(RemoteModel(m['id'] as String, m['display_name'] is String ? m['display_name'] as String : null));
  }
  out.sort((a, b) => a.id.compareTo(b.id));
  return out;
}

/// 按“渠道 + 模型 + 思考档位”造客户端。
ChatClient buildChatClient(ResolvedModel r, String apiKey, {http.Client? httpClient}) {
  final level = r.level == 'off' ? null : r.level;
  final m = r.model;
  return switch (r.channel.protocol) {
    ChatProtocol.openaiChat => OpenAiChatClient(
      baseUrl: r.channel.baseUrl,
      apiKey: apiKey,
      model: m.id,
      reasoningEffort: level,
      maxTokens: m.maxOutput == ModelSpec.defaultMaxOutput ? null : m.maxOutput,
      httpClient: httpClient,
    ),
    ChatProtocol.anthropic => AnthropicChatClient(
      baseUrl: r.channel.baseUrl,
      apiKey: apiKey,
      model: m.id,
      maxTokens: m.maxOutput,
      thinkingLevel: level,
      httpClient: httpClient,
    ),
    ChatProtocol.openaiResponses => OpenAiResponsesClient(
      baseUrl: r.channel.baseUrl,
      apiKey: apiKey,
      model: m.id,
      maxOutputTokens: m.maxOutput,
      reasoningEffort: level,
      httpClient: httpClient,
    ),
  };
}
