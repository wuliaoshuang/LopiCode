// MCP 服务器的状态（完整版：不可变快照 + Notifier，照额度那个样板）。
//
// 这里是这份状态唯一的主人：界面订阅 [mcpProvider]，要改就调 [McpNotifier] 的方法；Agent 调工具也从这里走。
// 配置落在 mcp_servers.json（lib/agent/mcp/mcp_config.dart 的 McpStore），请求头的值在 SecretStore，状态里没有。
// 防“旧结果盖新结果”：每个服务器一个代次，改了配置代次加一，旧的刷新回来发现代次不对就整个丢掉；容器销毁以后不再写。
// 工具清单：每段主对话第一次用到时刷新一次（[McpNotifier.refreshForConversation]），连不上就先用上次存的清单并给一句提示。
import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:lopicode/agent/channel_check.dart';
import 'package:lopicode/agent/mcp/mcp_client.dart';
import 'package:lopicode/agent/mcp/mcp_config.dart';
import 'package:lopicode/agent/mcp/mcp_http.dart';
import 'package:lopicode/agent/mcp/mcp_models.dart';
import 'package:lopicode/state/app_providers.dart';
import 'package:riverpod/riverpod.dart';

/// 测试钩子：换掉联网用的客户端；平时为 null（用真实网络）。
final mcpHttpFactoryProvider = Provider<http.Client Function()?>((ref) => null);

/// 几个等待时间（测试里换成很短的）。
final mcpTimeoutsProvider = Provider<McpTimeouts>((ref) => const McpTimeouts());

enum McpPhase { idle, checking, ok, failed }

/// 一个服务器最近一次连接的结果。
class McpStatus {
  const McpStatus(this.phase, [this.message = '']);
  final McpPhase phase;

  /// 失败时的一句人话（不含令牌）。
  final String message;
}

class McpState {
  McpState({List<McpServerConfig> servers = const [], Map<String, McpStatus> status = const {}, this.loaded = false}) : servers = List.unmodifiable(servers), status = Map.unmodifiable(status);

  final List<McpServerConfig> servers;
  final Map<String, McpStatus> status;

  /// 配置从盘上读完没有。
  final bool loaded;

  McpServerConfig? server(String? id) => servers.where((s) => s.id == id).firstOrNull;
  McpStatus statusOf(String id) => status[id] ?? const McpStatus(McpPhase.idle);

  /// 开着的服务器。
  List<McpServerConfig> get enabled => [...servers.where((s) => s.enabled)];

  /// 有没有开着的服务器（没有的话，聊天里不出现任何 MCP 的东西）。
  bool get active => servers.any((s) => s.enabled);

  McpState copyWith({List<McpServerConfig>? servers, Map<String, McpStatus>? status, bool? loaded}) =>
      McpState(servers: servers ?? this.servers, status: status ?? this.status, loaded: loaded ?? this.loaded);
}

/// “测试连接并读取工具”的结果（还没保存）。
class McpProbe {
  McpProbe(this.result, {List<McpToolInfo> tools = const [], this.mode}) : tools = List.unmodifiable(tools);
  final CheckResult result;
  final List<McpToolInfo> tools;
  final McpMode? mode;
}

/// 失败原因 → 结论 + 下一步（都不含令牌）。
CheckResult mcpFailureResult(McpException e) {
  final (title, advice) = switch (e.kind) {
    McpFailure.policy => ('这个地址不能连', '外网的服务器要用 https://；http:// 只能连本机或局域网。'),
    McpFailure.unreachable => ('连不上服务器', '检查地址和端口有没有填错、手机有没有联网；本机或局域网的服务要先启动。'),
    McpFailure.timeout => ('超时：服务器没有及时回应', '检查地址有没有填错；也可能是服务器太慢或者在你的网络里访问不了。'),
    McpFailure.auth => ('服务器拒绝了：令牌不对或没填', '回第 1 步检查请求头：名字（常见是 Authorization）和值（常见是“Bearer 加一个空格再加令牌”）。'),
    McpFailure.redirect => ('服务器要转去别的地址，没有跟过去', '请求头里常带令牌，所以不会自动转去别的主机。确认无误的话，把地址直接改成新地址。'),
    McpFailure.http => ('服务器回了错误', '多半是地址不对。核对一下服务商给的 MCP 地址（常以 /mcp 或 /sse 结尾）。'),
    McpFailure.badReply => ('地址有回应，但不是 MCP 服务器的回答', '多半是地址填错了（比如填成了网页地址）。'),
    McpFailure.rpc => ('服务器报错了', '原因看下面服务器的原话。'),
    McpFailure.unsupported => ('这个服务器要的功能本应用还不支持', '原因看下面的说明。'),
  };
  return CheckResult(ok: false, title: title, advice: advice, detail: e.message);
}

class McpNotifier extends Notifier<McpState> {
  McpStore get _store => ref.read(appServicesProvider).mcp;

  late McpState _snap;
  final Map<String, int> _epoch = {};
  final Map<String, McpClient> _clients = {};
  final Map<String, Future<void>> _refreshing = {};
  final Set<String> _freshRoots = {};
  int _seq = 0;

  void _put(McpState next) {
    _snap = next;
    if (ref.mounted) state = next;
  }

  @override
  McpState build() {
    final store = ref.watch(appServicesProvider).mcp;
    ref.onDispose(() {
      for (final c in _clients.values) {
        unawaited(c.close()); // 收尾告诉服务器会话结束；成不成都不用等
      }
      _clients.clear();
    });
    _snap = McpState(servers: store.servers, loaded: store.loaded);
    if (!store.loaded) Future.microtask(ensureLoaded);
    return _snap;
  }

  /// 读配置（只读一次）。
  Future<void> ensureLoaded() async {
    if (_snap.loaded) return;
    await _store.load();
    if (!_snap.loaded) _put(_snap.copyWith(servers: _store.servers, loaded: true));
  }

  McpState get snapshot => _snap;

  void _bump(String id) {
    _epoch[id] = (_epoch[id] ?? 0) + 1;
    final old = _clients.remove(id);
    if (old != null) unawaited(old.close()); // 旧连接作废；关不关得掉都不用等
  }

  Future<void> _save(List<McpServerConfig> servers) async {
    _put(_snap.copyWith(servers: servers));
    await _store.save(servers);
  }

  void _setStatus(String id, McpStatus s) => _put(_snap.copyWith(status: {..._snap.status, id: s}));

  /// 新建（不传 id）或修改一个服务器。[headers]：名字 → 新的值；值为 null 表示沿用已经保存的；没列出来的头会被删掉。
  /// [tools] / [mode] 传了就一起存（刚测试连接读到的）。不合规矩抛 [FormatException]（消息是人话）。
  Future<McpServerConfig> upsert({
    String? id,
    required String name,
    required String url,
    McpTransportChoice transport = McpTransportChoice.auto,
    Map<String, String?> headers = const {},
    Set<String>? disabledTools,
    List<McpToolInfo>? tools,
    McpMode? mode,
  }) async {
    await ensureLoaded();
    final problem = mcpConfigProblem(name: name, url: url);
    if (problem != null) throw FormatException(problem);
    final old = _snap.server(id);
    if (old == null && _snap.servers.length >= McpStore.maxServers) throw const FormatException('最多配 ${McpStore.maxServers} 个 MCP 服务器');
    final names = <String>[];
    for (final e in headers.entries) {
      final n = e.key.trim();
      final nameProblem = mcpHeaderNameProblem(n);
      if (nameProblem != null) throw FormatException(nameProblem);
      if (names.any((x) => x.toLowerCase() == n.toLowerCase())) throw FormatException('请求头“$n”写了两遍');
      final v = e.value;
      if (v != null) {
        final valueProblem = mcpHeaderValueProblem(v);
        if (valueProblem != null) throw FormatException('请求头“$n”：$valueProblem');
      } else if (old == null || !old.headerNames.any((x) => x.toLowerCase() == n.toLowerCase())) {
        throw FormatException('请求头“$n”还没填值');
      }
      names.add(n);
    }
    final sid = old?.id ?? 'm${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${(_seq++).toRadixString(36)}';
    for (final e in headers.entries) {
      final v = e.value;
      if (v != null) await _store.writeHeader(sid, e.key.trim(), v.trim());
    }
    for (final gone in (old?.headerNames ?? const <String>[]).where((h) => !names.any((x) => x.toLowerCase() == h.toLowerCase()))) {
      await _store.deleteHeader(sid, gone);
    }
    final urlChanged = old != null && (old.url != url.trim() || old.transport != transport);
    final next = McpServerConfig(
      id: sid,
      name: name.trim(),
      url: url.trim(),
      transport: transport,
      enabled: old?.enabled ?? true,
      headerNames: names,
      disabledTools: disabledTools ?? old?.disabledTools ?? const {},
      // 地址换了：旧的工具清单不能再用
      tools: tools ?? (urlChanged ? const [] : old?.tools ?? const []),
      toolsAt: tools != null ? ref.read(clockProvider)() : (urlChanged ? null : old?.toolsAt),
      mode: mode ?? (urlChanged ? null : old?.mode),
    );
    _bump(sid);
    await _save([
      for (final s in _snap.servers)
        if (s.id == sid) next else s,
      if (old == null) next,
    ]);
    _setStatus(sid, tools != null ? const McpStatus(McpPhase.ok) : const McpStatus(McpPhase.idle));
    return next;
  }

  /// 删掉一个服务器和它存的请求头。
  Future<void> remove(String id) async {
    final old = _snap.server(id);
    if (old == null) return;
    _bump(id);
    for (final h in old.headerNames) {
      await _store.deleteHeader(id, h);
    }
    await _save([..._snap.servers.where((s) => s.id != id)]);
    _put(_snap.copyWith(status: {..._snap.status}..remove(id)));
  }

  Future<void> _update(String id, McpServerConfig Function(McpServerConfig s) change) async {
    if (_snap.server(id) == null) return;
    await _save([
      for (final s in _snap.servers)
        if (s.id == id) change(s) else s,
    ]);
  }

  /// 开 / 关一个服务器。
  Future<void> setEnabled(String id, bool on) => _update(id, (s) => s.copyWith(enabled: on));

  /// 开 / 关一个工具。
  Future<void> setToolEnabled(String id, String tool, bool on) => _update(id, (s) => s.copyWith(disabledTools: on ? ({...s.disabledTools}..remove(tool)) : {...s.disabledTools, tool}));

  McpClient _newClient(String url, McpTransportChoice transport, Map<String, String> headers, McpMode? hint, {McpTimeouts? timeouts}) =>
      McpClient(url: Uri.parse(url.trim()), headers: headers, transport: transport, hint: hint, timeouts: timeouts ?? ref.read(mcpTimeoutsProvider), clientFactory: ref.read(mcpHttpFactoryProvider));

  /// 用表单里（还没保存）的内容连一次、读工具清单。[headers] 的值为 null＝用这个服务器已保存的那个值。只有用户点了才调。
  Future<McpProbe> probe({String? id, required String url, McpTransportChoice transport = McpTransportChoice.auto, Map<String, String?> headers = const {}}) async {
    final problem = mcpUrlProblem(url);
    if (problem != null) return McpProbe(CheckResult(ok: false, title: '这个地址不能连', advice: problem));
    final real = <String, String>{};
    for (final e in headers.entries) {
      final v = e.value ?? (id == null ? null : await _store.secrets.read(McpStore.secretKey(id, e.key.trim())));
      if (v != null && v.isNotEmpty) real[e.key.trim()] = v.trim();
    }
    final client = _newClient(url, transport, real, null);
    try {
      final info = await client.connect();
      final tools = await client.listTools();
      final who = info.name.isEmpty ? '' : '服务器自称“${info.name}${info.version.isEmpty ? '' : ' ${info.version}'}”。';
      return McpProbe(
        CheckResult(ok: true, title: tools.isEmpty ? '连上了，但这个服务器没有提供工具' : '连上了，读到 ${tools.length} 个工具', advice: '$who连接方式：${info.mode.label}（协议版本 ${info.protocolVersion}）。只读了工具清单，没有调用任何工具。'),
        tools: tools,
        mode: info.mode,
      );
    } on McpException catch (e) {
      return McpProbe(mcpFailureResult(e));
    } finally {
      unawaited(client.close()); // 测试用的连接，关不关得掉都不用等
    }
  }

  /// 重新连一次、刷新工具清单。失败不清旧清单，只把状态记成失败。同一个服务器同时只刷一次。
  Future<void> refresh(String id, {McpTimeouts? timeouts}) => _refreshing[id] ??= _refresh(id, timeouts).whenComplete(() {
    // 注意要用大括号：写成 `=> _refreshing.remove(id)` 会把这个 Future 自己当返回值，变成“自己等自己”，永远不结束。
    _refreshing.remove(id);
  });

  Future<void> _refresh(String id, McpTimeouts? timeouts) async {
    await ensureLoaded();
    final server = _snap.server(id);
    if (server == null) return;
    final epoch = _epoch[id] ?? 0;
    _setStatus(id, const McpStatus(McpPhase.checking));
    final client = _newClient(server.url, server.transport, await _store.headersOf(server), server.mode, timeouts: timeouts);
    try {
      final info = await client.connect();
      final tools = await client.listTools();
      if ((_epoch[id] ?? 0) != epoch || !ref.mounted) return;
      await _update(id, (s) => s.copyWith(tools: tools, toolsAt: ref.read(clockProvider)(), mode: info.mode));
      _setStatus(id, const McpStatus(McpPhase.ok));
    } on McpException catch (e) {
      if ((_epoch[id] ?? 0) != epoch) return;
      _setStatus(id, McpStatus(McpPhase.failed, e.message));
    } finally {
      unawaited(client.close()); // 刷新用的连接，关不关得掉都不用等
    }
  }

  /// 一段主对话开始时调：把开着的服务器的工具清单刷新一遍（每段主对话只刷一次）。
  /// 返回要告诉用户的话（哪个服务器没连上、现在用的是不是旧清单）；都顺利就是空的。
  Future<List<String>> refreshForConversation(String rootId) async {
    await ensureLoaded();
    final servers = _snap.enabled;
    if (servers.isEmpty || !_freshRoots.add(rootId)) return const [];
    if (_freshRoots.length > 500) _freshRoots.remove(_freshRoots.first);
    // 对话开头不能等太久：这一次用短一点的等待时间。
    const quick = McpTimeouts(connect: Duration(seconds: 6), headers: Duration(seconds: 8), idle: Duration(seconds: 8));
    final base = ref.read(mcpTimeoutsProvider);
    final timeouts = base.headers < quick.headers ? base : quick;
    await Future.wait([for (final s in servers) refresh(s.id, timeouts: timeouts)]);
    final notes = <String>[];
    for (final s in servers) {
      final now = _snap.server(s.id);
      final st = _snap.statusOf(s.id);
      if (now == null || st.phase != McpPhase.failed) continue;
      notes.add(now.tools.isEmpty ? 'MCP 服务器“${now.name}”这次没连上，这段对话里暂时没有它的工具。原因：${st.message}' : 'MCP 服务器“${now.name}”这次没连上，先用上次读到的 ${now.activeTools.length} 个工具（可能已经过时）。原因：${st.message}');
    }
    return notes;
  }

  /// 调用一个工具。连接按服务器留着复用；连不上 / 超时就把连接丢掉，下次重新连。不自动重试（重试可能让工具执行两遍）。
  Future<McpCallResult> call(String serverId, McpToolInfo tool, Map<String, dynamic> args) async {
    await ensureLoaded();
    final server = _snap.server(serverId);
    if (server == null || !server.enabled) throw McpException(McpFailure.unsupported, '这个 MCP 服务器已经被关掉或删除了');
    if (server.disabledTools.contains(tool.name)) throw McpException(McpFailure.unsupported, '这个工具已经在设置里关掉了');
    final epoch = _epoch[serverId] ?? 0;
    var client = _clients[serverId];
    if (client == null) {
      client = _newClient(server.url, server.transport, await _store.headersOf(server), server.mode);
      if ((_epoch[serverId] ?? 0) != epoch) {
        throw McpException(McpFailure.unsupported, '这个 MCP 服务器的设置刚刚改过，这次没有调用');
      }
      _clients[serverId] = client;
    }
    try {
      final result = await client.callTool(tool.name, args, schema: tool.inputSchema);
      // 旧版 SSE 要一直占着一条长连接：用完就关，不在后台挂着。
      if (client.info?.mode == McpMode.sse && identical(_clients[serverId], client)) {
        _clients.remove(serverId);
        unawaited(client.close());
      }
      return result;
    } on McpException catch (e) {
      if (e.kind != McpFailure.rpc && identical(_clients[serverId], client)) {
        _clients.remove(serverId);
        unawaited(client.close()); // 坏掉的连接，关不关得掉都不用等
      }
      rethrow;
    }
  }
}

final mcpProvider = NotifierProvider<McpNotifier, McpState>(McpNotifier.new);
