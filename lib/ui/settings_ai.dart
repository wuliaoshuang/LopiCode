// 设计约束（模型与渠道 · 390×844）
// - 渠道列表：一行一个渠道（名字强，协议 + 模型数弱）。最上面一块是“新对话用哪个模型”。主操作只有“添加渠道”。
// - 渠道编辑页从上到下：名称 → 协议 → 接口地址 → API Key → 两个次要按钮（测试连接、获取模型）→ 模型列表 → 保存。
//   每行只做一件事；删除渠道收进右上角菜单。
// - Key 输入框默认遮住；已保存的 Key 不回显，留空＝不改。
// - 单个模型的细节（显示名、上下文、最大输出、能不能看图、思考档位）在底部面板里改，不挤在列表行上。
import 'package:lopicode/agent/model_config.dart';
import 'package:lopicode/agent/protocols.dart';
import 'package:lopicode/agent/chat_client.dart';
import 'package:lopicode/app_services.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/chat_panels.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';

class ChannelsScreen extends StatefulWidget {
  const ChannelsScreen({super.key});

  @override
  State<ChannelsScreen> createState() => _ChannelsScreenState();
}

class _ChannelsScreenState extends State<ChannelsScreen> {
  Future<void> _edit([Channel? channel]) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ChannelEditScreen(channel: channel)));
    if (mounted) setState(() {});
  }

  Future<void> _pickFixed() async {
    final app = AppScope.of(context);
    final picked = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ModelPickerSheet(current: app.models.fixedSelection),
    );
    if (picked is ModelSelectionResult) {
      await app.models.setFixedSelection(picked.selection);
      await app.models.setNewChatUsesFixed(true);
      app.touch();
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final channels = app.models.channels;
    final fixed = app.models.resolve(app.models.fixedSelection);
    return Scaffold(
      appBar: AppBar(title: const Text('模型与渠道')),
      floatingActionButton: channels.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _edit,
              elevation: 2,
              shape: const StadiumBorder(),
              icon: const Icon(Icons.add),
              label: const Text('添加渠道'),
            ),
      body: channels.isEmpty
          ? EmptyState(
              icon: Icons.hub_outlined,
              title: '还没有渠道',
              message: '渠道就是一个模型服务：接口地址加 API Key。\n添加后勾选要用的模型。',
              action: FilledButton.icon(onPressed: _edit, icon: const Icon(Icons.add), label: const Text('添加渠道')),
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 96),
              children: [
                const SectionLabel('新对话用哪个模型'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.x4),
                  child: SegmentedButton<bool>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: false, label: Text('沿用上次')),
                      ButtonSegment(value: true, label: Text('固定默认')),
                    ],
                    selected: {app.models.newChatUsesFixed},
                    onSelectionChanged: (v) async {
                      if (v.first && fixed == null) {
                        await _pickFixed();
                      } else {
                        await app.models.setNewChatUsesFixed(v.first);
                        app.touch();
                        if (mounted) setState(() {});
                      }
                    },
                  ),
                ),
                if (app.models.newChatUsesFixed)
                  ListTile(
                    key: const Key('fixed-model'),
                    title: Text(fixed == null ? '还没选固定的模型' : fixed.model.name),
                    subtitle: Text(fixed == null ? '点这里选一个' : '${fixed.channel.name}${fixed.level == 'off' ? '' : ' · 思考：${thinkingLabel(fixed.level)}'}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _pickFixed,
                  )
                else
                  Padding(
                    padding: const EdgeInsets.fromLTRB(Space.x4, Space.x2, Space.x4, 0),
                    child: Text('新对话会用你上一次在对话里选的模型。', style: t.bodySmall),
                  ),
                const SectionLabel('渠道'),
                for (final ch in channels)
                  ListTile(
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(Radii.md)),
                      child: Icon(Icons.hub_outlined, color: c.accent, size: 20),
                    ),
                    title: Text(ch.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text('${ch.protocol.label} · ${ch.models.isEmpty ? '还没勾选模型' : '${ch.models.length} 个模型'}', maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _edit(ch),
                  ),
              ],
            ),
    );
  }
}

class ChannelEditScreen extends StatefulWidget {
  const ChannelEditScreen({super.key, this.channel});
  final Channel? channel;

  @override
  State<ChannelEditScreen> createState() => _ChannelEditScreenState();
}

class _ChannelEditScreenState extends State<ChannelEditScreen> {
  final _name = TextEditingController();
  final _baseUrl = TextEditingController();
  final _key = TextEditingController();
  ChatProtocol _protocol = ChatProtocol.openaiChat;
  final List<ModelSpec> _models = [];
  bool _hasKey = false;
  bool _busy = false;
  String? _status;
  bool _statusOk = true;

  @override
  void initState() {
    super.initState();
    final ch = widget.channel;
    if (ch != null) {
      _name.text = ch.name;
      _baseUrl.text = ch.baseUrl;
      _protocol = ch.protocol;
      _models.addAll([for (final m in ch.models) ModelSpec.fromJson(m.toJson())!]);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ch = widget.channel;
    if (ch != null) {
      AppScope.of(context).models.hasKey(ch.id).then((v) {
        if (mounted) setState(() => _hasKey = v);
      });
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _baseUrl.dispose();
    _key.dispose();
    super.dispose();
  }

  /// 测试连接 / 获取模型用的 Key：新填的优先，否则用已保存的。
  Future<String> _effectiveKey() async {
    if (_key.text.trim().isNotEmpty) return _key.text.trim();
    final ch = widget.channel;
    return ch == null ? '' : AppScope.of(context).models.apiKey(ch.id);
  }

  Future<List<RemoteModel>?> _fetch() async {
    if (_baseUrl.text.trim().isEmpty) {
      setState(() {
        _status = '先填接口地址';
        _statusOk = false;
      });
      return null;
    }
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      return await listRemoteModels(protocol: _protocol, baseUrl: _baseUrl.text.trim(), apiKey: await _effectiveKey());
    } on ChatApiException catch (e) {
      if (mounted) {
        setState(() {
          _status = e.message;
          _statusOk = false;
        });
      }
      return null;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _test() async {
    final list = await _fetch();
    if (list != null && mounted) {
      setState(() {
        _status = '连接正常：读到 ${list.length} 个模型（只读了模型列表，没有产生对话费用）';
        _statusOk = true;
      });
    }
  }

  Future<void> _fetchModels() async {
    final list = await _fetch();
    if (list == null || !mounted) return;
    if (list.isEmpty) {
      setState(() {
        _status = '接口返回的模型列表是空的，可以手动添加模型 ID';
        _statusOk = false;
      });
      return;
    }
    final picked = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _RemoteModelsSheet(models: list, selected: {for (final m in _models) m.id}),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _models.removeWhere((m) => !picked.contains(m.id) && list.any((r) => r.id == m.id));
      for (final r in list) {
        if (picked.contains(r.id) && !_models.any((m) => m.id == r.id)) _models.add(ModelSpec(id: r.id, name: r.displayName));
      }
    });
  }

  Future<void> _addManually() async {
    final id = await promptDialog(context, title: '手动添加模型', hint: '模型 ID，和接口文档里写的一样', confirmLabel: '添加');
    if (id == null || id.trim().isEmpty || !mounted) return;
    if (_models.any((m) => m.id == id.trim())) {
      showSnack(context, '这个模型已经在列表里了');
      return;
    }
    setState(() => _models.add(ModelSpec(id: id.trim())));
  }

  Future<void> _editModel(ModelSpec m) async {
    final result = await showModalBottomSheet<Object>(context: context, isScrollControlled: true, builder: (_) => ModelSpecSheet(model: m));
    if (!mounted) return;
    setState(() {
      if (result == 'remove') _models.remove(m);
    });
  }

  Future<void> _save() async {
    final app = AppScope.of(context);
    if (_baseUrl.text.trim().isEmpty) {
      showSnack(context, '接口地址不能为空');
      return;
    }
    await app.models.upsert(
      id: widget.channel?.id,
      name: _name.text.trim(),
      protocol: _protocol,
      baseUrl: _baseUrl.text.trim(),
      apiKey: _key.text, // 留空＝保留原来的 Key
      models: _models,
    );
    app.touch();
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final app = AppScope.of(context);
    final ok = await confirmDialog(context, title: '删除这个渠道？', message: '渠道和它保存的 API Key 会被删除。用着它的对话会改用别的可用模型。', confirmLabel: '删除', danger: true);
    if (!ok) return;
    await app.models.remove(widget.channel!.id);
    app.touch();
    if (mounted) Navigator.pop(context);
  }

  Future<void> _clearKey() async {
    await AppScope.of(context).models.clearKey(widget.channel!.id);
    if (mounted) setState(() => _hasKey = false);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.channel == null ? '添加渠道' : '编辑渠道'),
        actions: [
          if (widget.channel != null)
            PopupMenuButton<String>(
              tooltip: '更多',
              onSelected: (_) => _delete(),
              itemBuilder: (_) => [PopupMenuItem(value: 'delete', child: Text('删除渠道', style: TextStyle(color: c.danger)))],
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.x4, Space.x2, Space.x4, Space.x8),
        children: [
          TextField(controller: _name, decoration: const InputDecoration(labelText: '渠道名称', hintText: '给自己看的名字，不填就用协议名')),
          const SizedBox(height: Space.x3),
          DropdownButtonFormField<ChatProtocol>(
            key: const Key('channel-protocol'),
            initialValue: _protocol,
            decoration: const InputDecoration(labelText: '接口协议'),
            items: [for (final p in ChatProtocol.values) DropdownMenuItem(value: p, child: Text(p.label))],
            onChanged: (v) => setState(() => _protocol = v ?? _protocol),
          ),
          const SizedBox(height: Space.x3),
          TextField(
            key: const Key('channel-url'),
            controller: _baseUrl,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: InputDecoration(labelText: '接口地址', hintText: _protocol.exampleBaseUrl),
          ),
          const SizedBox(height: Space.x3),
          TextField(
            key: const Key('channel-key'),
            controller: _key,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: 'API Key',
              hintText: _hasKey ? '已保存，留空表示不改' : '粘贴你的 Key',
              helperText: _hasKey ? '已保存一个 Key（不显示明文）' : null,
              suffixIcon: _hasKey ? IconButton(tooltip: '清除已保存的 Key', icon: const Icon(Icons.delete_outline), onPressed: _clearKey) : null,
            ),
          ),
          const SizedBox(height: Space.x3),
          InfoBanner(
            app.secrets.persistent ? 'Key 用系统密钥库（Android Keystore）加密保存，不会写进普通设置文件或日志。' : '这台设备上安全存储不可用，Key 只保存在内存里，关掉应用后要重新填写。',
            tone: app.secrets.persistent ? BannerTone.info : BannerTone.warning,
          ),
          const SizedBox(height: Space.x3),
          OutlinedButton.icon(
            onPressed: _busy ? null : _test,
            icon: const Icon(Icons.wifi_tethering, size: 18),
            label: const Text('测试连接'),
          ),
          if (_busy) const Padding(padding: EdgeInsets.only(top: Space.x2), child: LinearProgressIndicator()),
          if (_status != null) InfoBanner(_status!, tone: _statusOk ? BannerTone.info : BannerTone.danger, margin: const EdgeInsets.only(top: Space.x2)),
          const SizedBox(height: Space.x6),
          Text('模型（${_models.length}）', style: t.labelMedium),
          const SizedBox(height: Space.x2),
          if (_models.isEmpty)
            Text('还没有模型。点“获取模型”从接口读列表勾选，或者手动添加模型 ID。', style: t.bodySmall)
          else
            for (final m in _models)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(m.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  '${m.contextLength ~/ 1000}K 上下文 · 输出 ${m.maxOutput ~/ 1000}K · ${m.vision ? '文本和图片' : '文本'}${m.thinking ? ' · 可思考' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.tune, size: 20),
                onTap: () => _editModel(m),
              ),
          const SizedBox(height: Space.x2),
          OutlinedButton.icon(
            key: const Key('channel-fetch'),
            onPressed: _busy ? null : _fetchModels,
            icon: const Icon(Icons.cloud_download_outlined, size: 18),
            label: const Text('获取模型'),
          ),
          const SizedBox(height: Space.x2),
          TextButton(onPressed: _addManually, child: const Text('手动添加模型 ID')),
          const SizedBox(height: Space.x4),
          FilledButton(key: const Key('channel-save'), onPressed: _save, child: const Text('保存')),
        ],
      ),
    );
  }
}

class _RemoteModelsSheet extends StatefulWidget {
  const _RemoteModelsSheet({required this.models, required this.selected});
  final List<RemoteModel> models;
  final Set<String> selected;

  @override
  State<_RemoteModelsSheet> createState() => _RemoteModelsSheetState();
}

class _RemoteModelsSheetState extends State<_RemoteModelsSheet> {
  late final Set<String> _picked = {...widget.selected};
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final shown = widget.models.where((m) => m.id.toLowerCase().contains(_filter.toLowerCase())).toList();
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, MediaQuery.viewInsetsOf(context).bottom + Space.x4),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.75),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('勾选要用的模型', style: t.titleLarge),
              const SizedBox(height: Space.x1),
              Text('接口一共有 ${widget.models.length} 个，已勾 ${_picked.length} 个。', style: t.bodySmall),
              const SizedBox(height: Space.x3),
              TextField(
                decoration: const InputDecoration(hintText: '搜索模型 ID', prefixIcon: Icon(Icons.search)),
                onChanged: (v) => setState(() => _filter = v.trim()),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final m in shown)
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: _picked.contains(m.id),
                        title: Text(m.id, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: m.displayName == null || m.displayName == m.id ? null : Text(m.displayName!, maxLines: 1, overflow: TextOverflow.ellipsis),
                        onChanged: (v) => setState(() => v == true ? _picked.add(m.id) : _picked.remove(m.id)),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: Space.x3),
              FilledButton(onPressed: () => Navigator.pop(context, _picked), child: const Text('确定')),
            ],
          ),
        ),
      ),
    );
  }
}

/// 改一个模型的细节。直接改传进来的 [model]；返回 'remove' 表示把它从渠道里去掉。
class ModelSpecSheet extends StatefulWidget {
  const ModelSpecSheet({super.key, required this.model});
  final ModelSpec model;

  @override
  State<ModelSpecSheet> createState() => _ModelSpecSheetState();
}

class _ModelSpecSheetState extends State<ModelSpecSheet> {
  late final _name = TextEditingController(text: widget.model.name);
  late final _context = TextEditingController(text: '${widget.model.contextLength ~/ 1000}');
  late final _maxOut = TextEditingController(text: '${widget.model.maxOutput ~/ 1000}');
  late bool _vision = widget.model.vision;
  late bool _thinking = widget.model.thinking;
  late final Set<String> _levels = {...widget.model.levels};

  @override
  void dispose() {
    _name.dispose();
    _context.dispose();
    _maxOut.dispose();
    super.dispose();
  }

  void _save() {
    final m = widget.model;
    final ctx = int.tryParse(_context.text.trim());
    final out = int.tryParse(_maxOut.text.trim());
    m
      ..name = _name.text.trim().isEmpty ? m.id : _name.text.trim()
      ..contextLength = ModelSpec.clampContext((ctx ?? ModelSpec.defaultContext ~/ 1000) * 1000)
      ..maxOutput = ((out ?? ModelSpec.defaultMaxOutput ~/ 1000) * 1000).clamp(1000, 400000)
      ..vision = _vision
      ..thinking = _thinking && _levels.isNotEmpty
      ..levels = [for (final l in kThinkingLevels) if (_levels.contains(l)) l];
    Navigator.pop(context, 'saved');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final ctxK = int.tryParse(_context.text.trim());
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, MediaQuery.viewInsetsOf(context).bottom + Space.x4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('模型设置', style: t.titleLarge),
            const SizedBox(height: Space.x1),
            Text(widget.model.id, style: t.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: Space.x4),
            TextField(controller: _name, decoration: const InputDecoration(labelText: '显示名')),
            const SizedBox(height: Space.x4),
            Text('上下文长度', style: t.labelMedium),
            const SizedBox(height: Space.x2),
            Wrap(
              spacing: Space.x2,
              runSpacing: Space.x1,
              children: [
                for (final v in ModelSpec.contextChoices)
                  ChoiceChip(
                    label: Text(v >= 1000000 ? '1M' : '${v ~/ 1000}K'),
                    selected: ctxK == v ~/ 1000,
                    onSelected: (_) => setState(() => _context.text = '${v ~/ 1000}'),
                  ),
              ],
            ),
            const SizedBox(height: Space.x2),
            TextField(
              controller: _context,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '或者手动输入', suffixText: 'K', helperText: '32 到 1000（也就是 32K 到 1M）'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: Space.x3),
            TextField(
              controller: _maxOut,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '最大输出', suffixText: 'K', helperText: '默认 32'),
            ),
            const SizedBox(height: Space.x3),
            Text('输入类型', style: t.labelMedium),
            const SizedBox(height: Space.x2),
            SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: false, label: Text('文本')),
                ButtonSegment(value: true, label: Text('文本和图片')),
              ],
              selected: {_vision},
              onSelectionChanged: (v) => setState(() => _vision = v.first),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('可以思考'),
              subtitle: const Text('模型支持“思考 / 推理”时打开'),
              value: _thinking,
              onChanged: (v) => setState(() => _thinking = v),
            ),
            if (_thinking) ...[
              Text('对话里可选的思考档位', style: t.labelMedium),
              const SizedBox(height: Space.x2),
              Wrap(
                spacing: Space.x2,
                children: [
                  for (final l in kThinkingLevels)
                    FilterChip(
                      label: Text(thinkingLabel(l)),
                      selected: _levels.contains(l),
                      onSelected: (v) => setState(() => v ? _levels.add(l) : _levels.remove(l)),
                    ),
                ],
              ),
            ],
            const SizedBox(height: Space.x4),
            FilledButton(onPressed: _save, child: const Text('确定')),
            TextButton(
              onPressed: () => Navigator.pop(context, 'remove'),
              child: Text('从这个渠道去掉', style: TextStyle(color: c.danger)),
            ),
          ],
        ),
      ),
    );
  }
}
