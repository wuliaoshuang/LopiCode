// MCP 的数据：一个工具长什么样、一次调用的结果、连上以后知道的服务器信息。纯数据，不联网。
// 字段名出处见 docs/api-notes.md 的“MCP”一节。从 JSON 取字段一律先判断类型——服务器给的东西不可信。
import 'dart:convert';

/// 服务器是哪一代协议、走哪种连接方式（探测出来的结果，会记进配置，下次直接用）。
enum McpMode {
  /// 新版（2026-07-28 起）：没有握手、没有会话，每个请求自己带版本号。
  modern('modern', 'Streamable HTTP（新版，无会话）'),

  /// 老版 Streamable HTTP（2025-03-26 ～ 2025-06-18）：先 initialize 握手，可能有会话号。
  legacy('legacy', 'Streamable HTTP（握手版）'),

  /// 最老的 HTTP+SSE（2024-11-05）：一条长连接收消息，另一个地址发消息。
  sse('sse', '旧版 HTTP+SSE');

  const McpMode(this.id, this.label);
  final String id;
  final String label;

  static McpMode? byId(Object? id) {
    for (final m in values) {
      if (m.id == id) return m;
    }
    return null;
  }
}

/// 用户选的连接方式。
enum McpTransportChoice {
  auto('auto', '自动'),
  streamable('streamable', 'HTTP'),
  sse('sse', '旧版 SSE');

  const McpTransportChoice(this.id, this.label);
  final String id;
  final String label;

  static McpTransportChoice byId(Object? id) => values.firstWhere((t) => t.id == id, orElse: () => auto);
}

class McpServerInfo {
  const McpServerInfo({required this.mode, required this.protocolVersion, this.name = '', this.version = ''});
  final McpMode mode;
  final String protocolVersion;

  /// 服务器自报的名字和版本（只用来显示，不可信）。
  final String name;
  final String version;
}

/// 服务器上的一个工具。
class McpToolInfo {
  McpToolInfo({required this.name, this.title = '', this.description = '', Map<String, dynamic>? inputSchema}) : inputSchema = Map.unmodifiable(inputSchema ?? const {'type': 'object'});

  static const int maxNameChars = 128;
  static const int maxDescriptionChars = 2000;
  static const int maxSchemaChars = 20000;

  final String name;
  final String title;
  final String description;
  final Map<String, dynamic> inputSchema;

  Map<String, dynamic> toJson() => {'name': name, if (title.isNotEmpty) 'title': title, if (description.isNotEmpty) 'description': description, 'inputSchema': inputSchema};

  /// 从服务器给的（或存盘的）JSON 读一个工具；名字不合规矩、说明太长的在这里就处理掉。读不出来返回 null。
  static McpToolInfo? fromJson(Object? j) {
    if (j is! Map) return null;
    final name = j['name'];
    if (name is! String || name.trim().isEmpty || name.length > maxNameChars) return null;
    final title = j['title'];
    final desc = j['description'];
    final schema = j['inputSchema'];
    Map<String, dynamic>? clean;
    if (schema is Map<String, dynamic>) {
      // 太大的参数说明不要（会把每一轮请求都撑大），换成“任意对象”
      try {
        if (jsonEncode(schema).length <= maxSchemaChars) clean = {...schema, 'type': 'object'};
      } on JsonUnsupportedObjectError {
        clean = null;
      }
    }
    return McpToolInfo(name: name, title: title is String ? _clip(title, 120) : '', description: desc is String ? _clip(desc, maxDescriptionChars) : '', inputSchema: clean);
  }

  static String _clip(String s, int max) => s.length > max ? '${s.substring(0, max)}…' : s;
}

/// 一次工具调用的结果，已经变成文字。
class McpCallResult {
  const McpCallResult(this.text, {required this.isError});
  final String text;

  /// 工具自己说“我出错了”（不是网络或协议出错）。
  final bool isError;

  /// 把 tools/call 的 result 变成一段文字：文字块原样拼起来，图片 / 音频 / 资源只留一句说明。
  static McpCallResult fromResult(Map<String, dynamic> result) {
    final parts = <String>[];
    final content = result['content'];
    for (final block in content is List ? content : const <Object?>[]) {
      if (block is! Map) continue;
      final type = block['type'];
      final mime = block['mimeType'] is String ? block['mimeType'] : '未知格式';
      switch (type) {
        case 'text':
          final t = block['text'];
          if (t is String && t.isNotEmpty) parts.add(t);
        case 'image':
          parts.add('（工具返回了一张图片，$mime；这一版不显示图片）');
        case 'audio':
          parts.add('（工具返回了一段音频，$mime；这一版不播放）');
        case 'resource_link':
          parts.add('（资源链接：${block['name'] is String ? block['name'] : ''} ${block['uri'] is String ? block['uri'] : ''}）');
        case 'resource':
          final r = block['resource'];
          final text = r is Map ? r['text'] : null;
          if (text is String && text.isNotEmpty) {
            parts.add(text);
          } else {
            parts.add('（内嵌资源：${r is Map && r['uri'] is String ? r['uri'] : ''}；不是文字，这一版不显示）');
          }
      }
    }
    final structured = result['structuredContent'];
    if (parts.isEmpty && structured != null) {
      try {
        parts.add(const JsonEncoder.withIndent('  ').convert(structured));
      } on JsonUnsupportedObjectError {
        // 编不出来就当没有
      }
    }
    return McpCallResult(parts.isEmpty ? '（工具没有返回内容）' : parts.join('\n'), isError: result['isError'] == true);
  }
}
