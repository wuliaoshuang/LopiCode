// 设计约束（MCP 服务器编辑页 · 390×844）— 2026-11-25 新增，步骤写法照“添加渠道”（channel_steps.dart）
// - 一页一条路，组标题带序号，一行只做一件事：
//   第 1 步 填名字、地址、连接方式、请求头 → 第 2 步 连接并读取工具 → 第 3 步 选工具 → 第 4 步 保存。
// - 没有单独的“测试连接”：它和“读取工具”是同一个动作。读到了＝连接正常；失败时分开说原因和下一步（CheckResultBanner）。
// - 请求头（常是令牌）：列表里只显示名字，值永远写成“••••••”；添加 / 修改在弹层里做，值的输入框默认遮住，旁边一个“显示”小按钮。
//   已保存的值不回显，留空＝不改。
// - 第 2 步缺东西（地址不对）时按钮置灰，旁边写明还差什么。读到工具之前第 3 步只有一句说明。
// - 第 3 步每个工具一行开关：名字在上、服务器给的说明在下（最多两行，是外部文字，只显示不执行）。
// - 主操作只有一个实心按钮：没读到工具时是第 2 步的“连接并读取工具”，读到以后让给第 4 步的“保存”。
// - 删除收在右上角“更多”里（红字，点了先确认），不和保存并排。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lopicode/agent/channel_check.dart';
import 'package:lopicode/agent/mcp/mcp_config.dart';
import 'package:lopicode/agent/mcp/mcp_http.dart';
import 'package:lopicode/agent/mcp/mcp_models.dart';
import 'package:lopicode/state/mcp_state.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/channel_steps.dart';
import 'package:lopicode/ui/settings_widgets.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';

/// 表单里的一个请求头。[value] 为 null＝沿用已保存的值。
class _HeaderDraft {
  _HeaderDraft(this.name, this.value);
  String name;
  String? value;
}

class McpServerEditScreen extends ConsumerStatefulWidget {
  const McpServerEditScreen({super.key, this.serverId});

  /// 为空＝添加。
  final String? serverId;

  @override
  ConsumerState<McpServerEditScreen> createState() => _McpServerEditScreenState();
}

class _McpServerEditScreenState extends ConsumerState<McpServerEditScreen> {
  final _name = TextEditingController();
  final _url = TextEditingController();
  McpTransportChoice _transport = McpTransportChoice.auto;
  final List<_HeaderDraft> _headers = [];
  List<McpToolInfo> _tools = const [];
  Set<String> _disabled = {};
  McpMode? _mode;
  bool _probed = false;
  bool _busy = false;
  CheckResult? _result;
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    final server = ref.read(mcpProvider).server(widget.serverId);
    if (server == null) return;
    _name.text = server.name;
    _url.text = server.url;
    _transport = server.transport;
    _headers.addAll([for (final h in server.headerNames) _HeaderDraft(h, null)]);
    _tools = server.tools;
    _disabled = {...server.disabledTools};
    _mode = server.mode;
  }

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    super.dispose();
  }

  Map<String, String?> get _headerMap => {for (final h in _headers) h.name: h.value};

  /// 第 2 步还差什么；不差就是 null。
  String? get _missing => mcpUrlProblem(_url.text);

  Future<void> _editHeader([_HeaderDraft? existing]) async {
    final others = {
      for (final h in _headers)
        if (!identical(h, existing)) h.name.toLowerCase(),
    };
    final edited = await showDialog<_HeaderDraft>(
      context: context,
      builder: (_) => _HeaderDialog(existing: existing, taken: others),
    );
    if (edited == null || !mounted) return;
    setState(() {
      if (existing == null) {
        _headers.add(edited);
      } else {
        existing
          ..name = edited.name
          ..value = edited.value;
      }
      // 请求头变了：之前的连接结果不算数了
      _result = null;
    });
  }

  Future<void> _probe() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _result = null;
    });
    final probe = await ref.read(mcpProvider.notifier).probe(id: widget.serverId, url: _url.text, transport: _transport, headers: _headerMap);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _result = probe.result;
      if (probe.result.ok) {
        _probed = true;
        _tools = probe.tools;
        _mode = probe.mode;
        _disabled = _disabled.intersection({for (final t in probe.tools) t.name});
      }
    });
  }

  Future<void> _save() async {
    final mcp = ref.read(mcpProvider.notifier);
    try {
      await mcp.upsert(
        id: widget.serverId,
        name: _name.text,
        url: _url.text,
        transport: _transport,
        headers: _headerMap,
        disabledTools: _disabled,
        tools: _probed ? _tools : null,
        mode: _probed ? _mode : null,
      );
    } on FormatException catch (e) {
      if (mounted) showSnack(context, e.message);
      return;
    }
    if (!mounted) return;
    showSnack(context, _tools.isEmpty ? '已保存。还没读到工具：回到这一页点“连接并读取工具”，Agent 才用得上' : '已保存：新对话里 Agent 可以用这个服务器的工具了（每次调用都会先问你）');
    Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final id = widget.serverId;
    if (id == null) return;
    final ok = await confirmDialog(context, title: '删除这个服务器？', message: '“${_name.text}”和它保存的请求头都会删掉，Agent 不再有它的工具。', confirmLabel: '删除', danger: true);
    if (!ok || !mounted) return;
    await ref.read(mcpProvider.notifier).remove(id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final missing = _missing;
    final urlEmpty = _url.text.trim().isEmpty;
    final gotTools = _result?.ok ?? false;
    return SettingsPage(
      title: widget.serverId == null ? '添加 MCP 服务器' : '编辑 MCP 服务器',
      actions: [
        if (widget.serverId != null)
          PopupMenuButton<String>(
            key: const Key('mcp-more'),
            tooltip: '更多',
            onSelected: (_) => _delete(),
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'delete',
                child: Text('删除服务器', style: TextStyle(color: c.danger)),
              ),
            ],
          ),
      ],
      children: [
        SettingsGroup(
          title: '第 1 步 · 填名字和地址',
          footer: '地址要以 https:// 开头；本机或局域网的服务可以用 http://。连接方式一般选“自动”，连不上再手选：HTTP 是现在通用的 Streamable HTTP，旧版 SSE 是老服务器用的。',
          padded: true,
          children: [
            TextField(
              key: const Key('mcp-name'),
              controller: _name,
              maxLength: McpServerConfig.maxNameChars,
              decoration: const InputDecoration(labelText: '名字', hintText: '比如：公司知识库', counterText: ''),
            ),
            const SizedBox(height: Space.x3),
            TextField(
              key: const Key('mcp-url'),
              controller: _url,
              keyboardType: TextInputType.url,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(labelText: '服务器地址', hintText: 'https://example.com/mcp', errorText: urlEmpty ? null : missing, errorMaxLines: 3),
              onChanged: (_) => setState(() => _result = null),
            ),
            const SizedBox(height: Space.x4),
            Text('连接方式', style: t.bodySmall?.copyWith(color: c.textMuted)),
            const SizedBox(height: Space.x2),
            SegmentedButton<McpTransportChoice>(
              key: const Key('mcp-transport'),
              showSelectedIcon: false,
              segments: [for (final v in McpTransportChoice.values) ButtonSegment(value: v, label: Text(v.label, maxLines: 1, softWrap: false))],
              selected: {_transport},
              onSelectionChanged: (s) => setState(() {
                _transport = s.first;
                _result = null;
              }),
            ),
          ],
        ),
        SettingsGroup(
          title: '请求头（没有令牌可以不填）',
          footer: '服务商给了令牌的话，常见填法：名字 Authorization，值是“Bearer”加一个空格再加令牌。值只存在系统的安全存储里，这里不显示。不支持网页登录授权（OAuth）。',
          children: [
            for (final h in _headers)
              SettingsRow(
                key: Key('mcp-header-${h.name}'),
                icon: Icons.key_outlined,
                title: h.name,
                subtitle: h.value == null ? '已保存 ••••••' : '已填 ••••••（保存后生效）',
                onTap: () => _editHeader(h),
                trailing: IconButton(
                  key: Key('mcp-header-del-${h.name}'),
                  tooltip: '删除这个请求头',
                  icon: Icon(Icons.close, size: 20, color: c.textFaint),
                  onPressed: () => setState(() {
                    _headers.remove(h);
                    _result = null;
                  }),
                ),
              ),
            SettingsRow(key: const Key('mcp-header-add'), icon: Icons.add, title: '添加请求头', accent: true, onTap: _editHeader),
          ],
        ),
        SettingsGroup(
          title: '第 2 步 · 连接并读取工具',
          padded: true,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('连一次服务器，读它提供哪些工具。读得到，就说明地址和请求头都能用——只读清单，不会调用任何工具。', style: t.bodySmall?.copyWith(color: c.textMuted, height: 1.5)),
                const SizedBox(height: Space.x3),
                if (gotTools)
                  OutlinedButton.icon(key: const Key('mcp-probe'), onPressed: _busy ? null : _probe, icon: const Icon(Icons.sync, size: 18), label: Text(_busy ? '正在连接…' : '重新读取'))
                else
                  FilledButton.icon(
                    key: const Key('mcp-probe'),
                    onPressed: missing != null || _busy ? null : _probe,
                    icon: const Icon(Icons.power_outlined, size: 18),
                    label: Text(_busy ? '正在连接…' : (_result == null ? '连接并读取工具' : '再试一次')),
                  ),
                if (missing != null)
                  Padding(
                    key: const Key('mcp-probe-missing'),
                    padding: const EdgeInsets.only(top: Space.x2),
                    child: Text(urlEmpty ? '还差服务器地址：先在第 1 步填好，这一步才能点。' : '第 1 步的地址还不能用，改好这一步才能点。', style: t.bodySmall?.copyWith(color: c.textFaint, height: 1.5)),
                  ),
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.only(top: Space.x2),
                    child: LinearProgressIndicator(),
                  ),
                if (_result != null && !_busy)
                  CheckResultBanner(
                    _result!,
                    key: const Key('mcp-probe-result'),
                    margin: const EdgeInsets.only(top: Space.x3),
                  ),
              ],
            ),
          ],
        ),
        SettingsGroup(
          title: '第 3 步 · 选工具（${_tools.length - _disabled.length} / ${_tools.length}）',
          footer: _tools.isEmpty ? null : '关掉的工具 Agent 看不到。工具的名字和说明是服务器给的，只是显示出来。',
          padded: _tools.isEmpty,
          children: [
            if (_tools.isEmpty)
              Text(
                '还没有工具。先做第 2 步。',
                key: const Key('mcp-tools-empty'),
                style: t.bodySmall?.copyWith(color: c.textFaint, height: 1.5),
              )
            else
              for (final tool in _tools)
                SettingsSwitchRow(
                  key: Key('mcp-tool-${tool.name}'),
                  title: tool.name,
                  subtitle: tool.description.isEmpty ? (tool.title.isEmpty ? '服务器没有给说明' : tool.title) : tool.description.replaceAll(RegExp(r'\s+'), ' '),
                  value: !_disabled.contains(tool.name),
                  onChanged: (on) => setState(() => on ? _disabled.remove(tool.name) : _disabled.add(tool.name)),
                ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x2),
          child: Text('第 4 步 · 保存', style: t.labelMedium?.copyWith(color: c.textFaint)),
        ),
        FilledButton(key: const Key('mcp-save'), onPressed: _busy ? null : _save, child: const Text('保存')),
        if (_tools.isEmpty)
          Padding(
            key: const Key('mcp-save-hint'),
            padding: const EdgeInsets.fromLTRB(Space.x4, Space.x2, Space.x4, 0),
            child: Text('还没读到工具。现在也能保存，但 Agent 要用它，得先在第 2 步读到工具。', style: t.bodySmall?.copyWith(color: c.textFaint, height: 1.5)),
          ),
      ],
    );
  }
}

/// 添加 / 修改一个请求头的弹层：名字一行、值一行（默认遮住）。
class _HeaderDialog extends StatefulWidget {
  const _HeaderDialog({required this.existing, required this.taken});
  final _HeaderDraft? existing;
  final Set<String> taken;

  @override
  State<_HeaderDialog> createState() => _HeaderDialogState();
}

class _HeaderDialogState extends State<_HeaderDialog> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  final _value = TextEditingController();
  bool _show = false;
  String? _nameError;
  String? _valueError;

  @override
  void dispose() {
    _name.dispose();
    _value.dispose();
    super.dispose();
  }

  /// 原来就有、而且值是已保存的（没在这次编辑里重填过）：值可以留空表示不改。
  bool get _canKeep => widget.existing != null && widget.existing!.value == null && _name.text.trim().toLowerCase() == widget.existing!.name.toLowerCase();

  void _submit() {
    final name = _name.text.trim();
    final value = _value.text;
    final nameError = mcpHeaderNameProblem(name) ?? (widget.taken.contains(name.toLowerCase()) ? '已经有一个叫“$name”的请求头了' : null);
    final valueError = value.trim().isEmpty ? (_canKeep ? null : '还没填请求头的值') : mcpHeaderValueProblem(value);
    if (nameError != null || valueError != null) {
      setState(() {
        _nameError = nameError;
        _valueError = valueError;
      });
      return;
    }
    Navigator.of(context).pop(_HeaderDraft(name, value.trim().isEmpty ? null : value.trim()));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? '添加请求头' : '修改请求头'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const Key('mcp-header-name'),
              controller: _name,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(labelText: '名字', hintText: 'Authorization', errorText: _nameError, errorMaxLines: 3),
            ),
            const SizedBox(height: Space.x3),
            TextField(
              key: const Key('mcp-header-value'),
              controller: _value,
              obscureText: !_show,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: '值',
                hintText: _canKeep ? '已保存，留空表示不改' : 'Bearer 你的令牌',
                errorText: _valueError,
                errorMaxLines: 3,
                suffixIcon: IconButton(
                  key: const Key('mcp-header-show'),
                  tooltip: _show ? '遮住' : '显示',
                  icon: Icon(_show ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20),
                  onPressed: () => setState(() => _show = !_show),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
        FilledButton(key: const Key('mcp-header-ok'), onPressed: _submit, child: const Text('好')),
      ],
    );
  }
}
