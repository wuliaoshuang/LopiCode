import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// 流式回复里的一小块。字段名与 OpenAI Chat Completions 的
/// `chat.completion.chunk` 对应，见 docs/api-notes.md。
class ChatDelta {
  ChatDelta({this.content, this.toolCalls = const [], this.finishReason});
  final String? content;
  final List<ToolCallDelta> toolCalls;
  final String? finishReason;
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
  ChatApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => message;
}

abstract class ChatClient {
  Stream<ChatDelta> streamChat({
    required List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>> tools = const [],
  });
}

/// 任意 OpenAI 兼容的 Chat Completions 接口。
class OpenAiChatClient implements ChatClient {
  OpenAiChatClient({
    required String baseUrl,
    required this.apiKey,
    required this.model,
    http.Client? httpClient,
  }) : baseUrl = normalizeBaseUrl(baseUrl),
       _http = httpClient ?? http.Client();

  final String baseUrl;
  final String apiKey;
  final String model;
  final http.Client _http;

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
  Stream<ChatDelta> streamChat({
    required List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>> tools = const [],
  }) async* {
    if (baseUrl.isEmpty || model.trim().isEmpty) {
      throw ChatApiException('还没配置模型：请到“设置 → Agent 模型”填写接口地址和模型名');
    }
    final Uri uri;
    try {
      uri = Uri.parse('$baseUrl/chat/completions');
      if (!uri.hasScheme || uri.host.isEmpty) throw const FormatException();
    } on FormatException {
      throw ChatApiException('接口地址不是合法的网址：$baseUrl');
    }
    final request = http.Request('POST', uri)
      ..headers['Content-Type'] = 'application/json'
      ..headers['Accept'] = 'text/event-stream'
      ..body = jsonEncode({
        'model': model.trim(),
        'messages': messages,
        'stream': true,
        if (tools.isNotEmpty) 'tools': tools,
        if (tools.isNotEmpty) 'tool_choice': 'auto',
      });
    if (apiKey.isNotEmpty) request.headers['Authorization'] = 'Bearer $apiKey';

    final http.StreamedResponse response;
    try {
      response = await _http.send(request);
    } on Exception catch (e) {
      // 只报错误类型和主机，不带请求头，避免把 Key 带进界面或日志。
      throw ChatApiException('连不上模型接口（${uri.host}）：${_short(e)}');
    }
    if (response.statusCode != 200) {
      final body = await response.stream.bytesToString();
      throw ChatApiException(_errorMessage(response.statusCode, body), statusCode: response.statusCode);
    }

    final lines = response.stream.transform(utf8.decoder).transform(const LineSplitter());
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
      final choices = json['choices'];
      // 开了 include_usage 时最后一块 choices 是空数组。
      if (choices is! List || choices.isEmpty || choices.first is! Map) continue;
      final choice = choices.first as Map;
      final delta = choice['delta'];
      final calls = <ToolCallDelta>[];
      String? content;
      if (delta is Map) {
        if (delta['content'] is String) content = delta['content'] as String;
        final rawCalls = delta['tool_calls'];
        if (rawCalls is List) {
          for (var i = 0; i < rawCalls.length; i++) {
            final c = rawCalls[i];
            if (c is! Map) continue;
            final fn = c['function'];
            calls.add(ToolCallDelta(
              index: c['index'] is int ? c['index'] as int : i,
              id: c['id'] is String ? c['id'] as String : null,
              name: fn is Map && fn['name'] is String ? fn['name'] as String : null,
              arguments: fn is Map && fn['arguments'] is String ? fn['arguments'] as String : null,
            ));
          }
        }
      }
      final finish = choice['finish_reason'];
      yield ChatDelta(content: content, toolCalls: calls, finishReason: finish is String ? finish : null);
    }
  }

  static String _short(Object e) {
    final s = e.toString();
    return s.length > 160 ? '${s.substring(0, 160)}…' : s;
  }

  static String _errorMessage(int status, String body) {
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
}
