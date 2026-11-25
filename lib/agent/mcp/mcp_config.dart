// MCP 服务器的配置和存盘。
//
// 存在哪：应用文档目录的 mcp_servers.json（原子写；坏文件备份后当成“没有配置”）。
// **请求头的值不在这个文件里**：只存头的名字，值放在 SecretStore（键见 [McpStore.secretKey]）。
// 文件里还缓存着上次读到的工具清单（名字、说明、参数说明），连不上的时候先用它。
import 'dart:io';

import 'package:lopicode/agent/mcp/mcp_http.dart';
import 'package:lopicode/agent/mcp/mcp_models.dart';
import 'package:lopicode/core/safe_file.dart';
import 'package:lopicode/core/stores.dart';

/// 一个 MCP 服务器。不可变：要改就 [copyWith] 一份新的。
class McpServerConfig {
  McpServerConfig({
    required this.id,
    required this.name,
    required this.url,
    this.transport = McpTransportChoice.auto,
    this.enabled = true,
    List<String> headerNames = const [],
    Set<String> disabledTools = const {},
    List<McpToolInfo> tools = const [],
    this.toolsAt,
    this.mode,
  }) : headerNames = List.unmodifiable(headerNames),
       disabledTools = Set.unmodifiable(disabledTools),
       tools = List.unmodifiable(tools);

  static const int maxNameChars = 40;

  final String id;
  final String name;
  final String url;
  final McpTransportChoice transport;
  final bool enabled;

  /// 自定义请求头的名字（值在 SecretStore 里）。
  final List<String> headerNames;

  /// 用户单独关掉的工具（服务器上的原名）。
  final Set<String> disabledTools;

  /// 上次读到的工具清单（缓存）。
  final List<McpToolInfo> tools;
  final DateTime? toolsAt;

  /// 上次探测出来的连接方式。
  final McpMode? mode;

  String get host => Uri.tryParse(url)?.host ?? '';

  /// 开着的工具。
  List<McpToolInfo> get activeTools => [...tools.where((t) => !disabledTools.contains(t.name))];

  McpServerConfig copyWith({
    String? name,
    String? url,
    McpTransportChoice? transport,
    bool? enabled,
    List<String>? headerNames,
    Set<String>? disabledTools,
    List<McpToolInfo>? tools,
    DateTime? toolsAt,
    McpMode? mode,
    bool clearMode = false,
  }) => McpServerConfig(
    id: id,
    name: name ?? this.name,
    url: url ?? this.url,
    transport: transport ?? this.transport,
    enabled: enabled ?? this.enabled,
    headerNames: headerNames ?? this.headerNames,
    disabledTools: disabledTools ?? this.disabledTools,
    tools: tools ?? this.tools,
    toolsAt: toolsAt ?? this.toolsAt,
    mode: clearMode ? null : (mode ?? this.mode),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'url': url,
    'transport': transport.id,
    'enabled': enabled,
    'headerNames': headerNames,
    'disabledTools': disabledTools.toList(),
    'tools': [for (final t in tools) t.toJson()],
    if (toolsAt != null) 'toolsAt': toolsAt!.toIso8601String(),
    if (mode != null) 'mode': mode!.id,
  };

  static McpServerConfig? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'];
    final name = j['name'];
    final url = j['url'];
    if (id is! String || id.isEmpty || name is! String || url is! String) return null;
    final headers = j['headerNames'];
    final disabled = j['disabledTools'];
    final tools = j['tools'];
    final at = j['toolsAt'];
    return McpServerConfig(
      id: id,
      name: name,
      url: url,
      transport: McpTransportChoice.byId(j['transport']),
      enabled: j['enabled'] is bool ? j['enabled'] as bool : true,
      headerNames: [
        for (final h in headers is List ? headers : const <Object?>[])
          if (h is String && mcpHeaderNameProblem(h) == null) h,
      ],
      disabledTools: {
        for (final t in disabled is List ? disabled : const <Object?>[])
          if (t is String) t,
      },
      tools: [for (final t in tools is List ? tools : const <Object?>[]) ?McpToolInfo.fromJson(t)],
      toolsAt: at is String ? DateTime.tryParse(at) : null,
      mode: McpMode.byId(j['mode']),
    );
  }
}

final RegExp _headerName = RegExp(r"^[A-Za-z0-9!#$%&'*+.^_`|~-]+$");

/// 这些头由应用自己管，不许用户覆盖。
const Set<String> _reservedHeaders = {
  'host',
  'content-length',
  'content-type',
  'accept',
  'connection',
  'transfer-encoding',
  'mcp-session-id',
  'mcp-protocol-version',
  'mcp-method',
  'mcp-name',
  'last-event-id',
};

/// 请求头的名字合不合规矩：合规矩返回 null。
String? mcpHeaderNameProblem(String name) {
  final n = name.trim();
  if (n.isEmpty) return '还没填请求头的名字';
  if (n.length > 64 || !_headerName.hasMatch(n)) return '请求头的名字只能用英文字母、数字和短横线，比如 Authorization';
  if (_reservedHeaders.contains(n.toLowerCase()) || n.toLowerCase().startsWith('mcp-param-')) return '“$n”由应用自己填，不能自定义';
  return null;
}

/// 请求头的值合不合规矩：合规矩返回 null。
String? mcpHeaderValueProblem(String value) {
  if (value.trim().isEmpty) return '还没填请求头的值';
  if (value.length > 4096) return '请求头的值太长了（最多 4096 个字符）';
  if (value.codeUnits.any((c) => c < 0x20 || c == 0x7F)) return '请求头的值里不能有换行';
  if (value.codeUnits.any((c) => c > 0x7E)) return '请求头的值只能是英文字母、数字和符号';
  return null;
}

class McpStore {
  McpStore(this.file, this.secrets);

  final File file;
  final SecretStore secrets;

  /// 最多配几个服务器。
  static const int maxServers = 20;

  List<McpServerConfig> _servers = const [];
  List<McpServerConfig> get servers => _servers;
  bool get loaded => _loading != null && _loaded;
  bool _loaded = false;
  Future<void>? _loading;

  static String secretKey(String serverId, String headerName) => 'mcp_header.$serverId.${headerName.toLowerCase()}';

  /// 从盘上读。可以反复调用，只读一次。文件坏了＝没有配置（坏文件已另存备份）。
  Future<void> load() => _loading ??= () async {
    final decoded = await readJsonFile(file, accept: (d) => d is Map && d['servers'] is List, label: 'MCP 服务器配置');
    final list = decoded is Map ? decoded['servers'] : null;
    final seen = <String>{};
    _servers = List.unmodifiable([
      for (final j in list is List ? list : const <Object?>[])
        if (McpServerConfig.fromJson(j) case final s? when seen.add(s.id)) s,
    ]);
    _loaded = true;
  }();

  Future<void> save(List<McpServerConfig> servers) async {
    _servers = List.unmodifiable(servers);
    await writeJsonAtomic(file, {
      'version': 1,
      'servers': [for (final s in servers) s.toJson()],
    });
  }

  /// 这个服务器的全部请求头（名字 → 值）。值读不到的那一项不带。
  Future<Map<String, String>> headersOf(McpServerConfig server) async {
    final out = <String, String>{};
    for (final name in server.headerNames) {
      final value = await secrets.read(secretKey(server.id, name));
      if (value != null && value.isNotEmpty) out[name] = value;
    }
    return out;
  }

  Future<void> writeHeader(String serverId, String name, String value) => secrets.write(secretKey(serverId, name), value);
  Future<void> deleteHeader(String serverId, String name) => secrets.delete(secretKey(serverId, name));
}

/// 能不能保存这份配置：能返回 null，不能返回原因。
String? mcpConfigProblem({required String name, required String url}) {
  if (name.trim().isEmpty) return '给这个服务器起个名字';
  if (name.trim().length > McpServerConfig.maxNameChars) return '名字太长了（最多 ${McpServerConfig.maxNameChars} 个字）';
  return mcpUrlProblem(url);
}
