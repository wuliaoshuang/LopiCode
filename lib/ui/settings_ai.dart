// 设计约束（模型与渠道 · 390×844）— 2026-11-24 按设置的统一样式重排
// - 渠道列表页两组：〔新对话用哪个模型〕分段选择独占一行（沿用上次 / 固定默认），选了“固定默认”下面多一行跳转行选模型；
//   〔渠道〕一行一个渠道（服务商图标 + 名字，副标题是协议和模型数）。主操作只有右下角“添加渠道”。
// - 渠道编辑页三组：〔连接〕名称 → 协议 → 接口地址 → API Key → Key 怎么存的说明 → 测试连接（表单组）；
//   〔模型〕一行一个模型，下面两行操作（获取模型 / 手动添加模型 ID）；最底下一个实心“保存”。删除渠道收进右上角菜单。
// - Key 输入框默认遮住；已保存的 Key 不回显，留空＝不改。
// - 单个模型的细节在底部面板里改（settings_model_sheets.dart），不挤在列表行上。
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lopicode/agent/chat_client.dart';
import 'package:lopicode/agent/model_config.dart';
import 'package:lopicode/agent/protocols.dart';
import 'package:lopicode/agent/provider_presets.dart';
import 'package:lopicode/state/models_state.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/app_ref.dart';
import 'package:lopicode/ui/chat_panels.dart';
import 'package:lopicode/ui/chrome.dart';
import 'package:lopicode/ui/model_setup.dart';
import 'package:lopicode/ui/provider_icon.dart';
import 'package:lopicode/ui/settings_model_sheets.dart';
import 'package:lopicode/ui/settings_widgets.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';

export 'package:lopicode/ui/settings_model_sheets.dart';

class ChannelsScreen extends ConsumerStatefulWidget {
  const ChannelsScreen({super.key});

  @override
  ConsumerState<ChannelsScreen> createState() => _ChannelsScreenState();
}

class _ChannelsScreenState extends ConsumerState<ChannelsScreen> {
  /// 点已有渠道进编辑页；“添加渠道”先去选服务商。
  Future<void> _edit([Channel? channel]) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => channel == null ? const ProviderPickerScreen() : ChannelEditScreen(channel: channel)));
    if (mounted) setState(() {});
  }

  Future<void> _pickFixed() async {
    final app = appOf(context);
    final picked = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ModelPickerSheet(current: app.models.fixedSelection),
    );
    if (picked is ModelSelectionResult) {
      final models = ref.read(modelsProvider.notifier);
      await models.setFixedSelection(picked.selection);
      await models.setNewChatUsesFixed(true);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(modelsProvider);
    final app = appOf(context);
    final channels = app.models.channels;
    final fixed = app.models.resolve(app.models.fixedSelection);
    if (channels.isEmpty) {
      return Scaffold(
        backgroundColor: context.colors.canvas,
        appBar: PageBar(background: context.colors.canvas, titleText: '模型与渠道'),
        body: EmptyState(
          icon: Icons.hub_outlined,
          title: '还没有渠道',
          message: '渠道就是一个模型服务。\n选一个服务商、填上 API Key，再勾选要用的模型。',
          action: FilledButton.icon(onPressed: _edit, icon: const Icon(Icons.add), label: const Text('添加渠道')),
        ),
      );
    }
    return SettingsPage(
      title: '模型与渠道',
      bottom: 96,
      floatingActionButton: FloatingActionButton.extended(onPressed: _edit, elevation: 2, shape: const StadiumBorder(), icon: const Icon(Icons.add), label: const Text('添加渠道')),
      children: [
        SettingsGroup(
          title: '新对话用哪个模型',
          footer: app.models.newChatUsesFixed ? '每段新对话都从上面这个模型开始；对话里还可以随时换。' : '新对话会用你上一次在对话里选的模型。',
          children: [
            SettingsSegmentRow<bool>(
              segments: const [(false, '沿用上次'), (true, '固定默认')],
              selected: app.models.newChatUsesFixed,
              onChanged: (v) async {
                if (v && fixed == null) {
                  await _pickFixed();
                } else {
                  await ref.read(modelsProvider.notifier).setNewChatUsesFixed(v);
                  if (mounted) setState(() {});
                }
              },
            ),
            if (app.models.newChatUsesFixed)
              SettingsRow(
                key: const Key('fixed-model'),
                title: fixed == null ? '还没选固定的模型' : fixed.model.name,
                subtitle: fixed == null ? '点这里选一个' : '${fixed.channel.name}${fixed.level == 'off' ? '' : ' · 思考：${thinkingLabel(fixed.level)}'}',
                onTap: _pickFixed,
              ),
          ],
        ),
        SettingsGroup(
          title: '渠道',
          children: [
            for (final ch in channels)
              SettingsRow(
                leading: ProviderIcon.forBaseUrl(ch.baseUrl, size: 32),
                title: ch.name,
                subtitle: '${ch.protocol.label} · ${ch.models.isEmpty ? '还没勾选模型' : '${ch.models.length} 个模型'}',
                onTap: () => _edit(ch),
              ),
          ],
        ),
      ],
    );
  }
}

class ChannelEditScreen extends ConsumerStatefulWidget {
  const ChannelEditScreen({super.key, this.channel, this.preset});
  final Channel? channel;

  /// 新建时选的服务商：名称、协议、接口地址先填好。
  final ProviderPreset? preset;

  @override
  ConsumerState<ChannelEditScreen> createState() => _ChannelEditScreenState();
}

class _ChannelEditScreenState extends ConsumerState<ChannelEditScreen> {
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
      _models.addAll(ch.models); // 模型不可变，直接拿；改的时候是换一份新的
    } else if (widget.preset case final p?) {
      _name.text = p.name;
      _baseUrl.text = p.baseUrl;
      _protocol = p.protocol;
    }
    _baseUrl.addListener(_onUrl);
  }

  void _onUrl() {
    if (mounted) setState(() {}); // 图标和“要不要 Key”跟着地址变
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ch = widget.channel;
    if (ch != null) {
      appOf(context).models.hasKey(ch.id).then((v) {
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
    return ch == null ? '' : appOf(context).models.apiKey(ch.id);
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
      builder: (_) => RemoteModelsSheet(models: list, selected: {for (final m in _models) m.id}),
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
    final result = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ModelSpecSheet(model: m),
    );
    if (!mounted) return;
    final at = _models.indexWhere((x) => identical(x, m));
    if (at < 0) return;
    // 面板交回来一份改好的就换上；交回 'remove' 就去掉
    if (result == 'remove') setState(() => _models.removeAt(at));
    if (result is ModelSpec) setState(() => _models[at] = result);
  }

  Future<void> _save() async {
    final app = appOf(context);
    if (_baseUrl.text.trim().isEmpty) {
      showSnack(context, '接口地址不能为空');
      return;
    }
    final saved = await ref
        .read(modelsProvider.notifier)
        .upsert(
          id: widget.channel?.id,
          name: _name.text.trim(),
          protocol: _protocol,
          baseUrl: _baseUrl.text.trim(),
          apiKey: _key.text, // 留空＝保留原来的 Key
          models: _models,
        );
    // 换了 Key：马上重查余额（不是 DeepSeek 官方渠道什么都不做）。
    if (_key.text.trim().isNotEmpty) unawaited(app.quota.refresh(saved, force: true));
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _delete() async {
    final app = appOf(context);
    final ok = await confirmDialog(context, title: '删除这个渠道？', message: '渠道和它保存的 API Key 会被删除。用着它的对话会改用别的可用模型。', confirmLabel: '删除', danger: true);
    if (!ok) return;
    await ref.read(modelsProvider.notifier).remove(widget.channel!.id);
    await app.quota.clearLimit(widget.channel!.id);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _clearKey() async {
    await ref.read(modelsProvider.notifier).clearKey(widget.channel!.id);
    if (mounted) setState(() => _hasKey = false);
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(modelsProvider);
    final app = appOf(context);
    final c = context.colors;
    final recognized = presetForBaseUrl(_baseUrl.text);
    // 提醒只在地址还是这家的时候显示（改成别家的地址就不该再说这句）。
    final note = recognized?.note;
    final keyHint = recognized?.keyHint;
    final local = isLocalBaseUrl(_baseUrl.text);
    return SettingsPage(
      title: widget.channel == null ? '添加渠道' : '编辑渠道',
      actions: [
        if (widget.channel != null)
          PopupMenuButton<String>(
            tooltip: '更多',
            onSelected: (_) => _delete(),
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'delete',
                child: Text('删除渠道', style: TextStyle(color: c.danger)),
              ),
            ],
          ),
      ],
      children: [
        SettingsGroup(
          title: '连接',
          padded: true,
          children: [
            Row(
              children: [
                ProviderIcon(key: const Key('channel-icon'), preset: recognized),
                const SizedBox(width: Space.x3),
                Expanded(
                  child: TextField(
                    controller: _name,
                    decoration: const InputDecoration(labelText: '渠道名称', hintText: '给自己看的名字，不填就用协议名'),
                  ),
                ),
              ],
            ),
            if (note != null) InfoBanner(note, margin: const EdgeInsets.only(top: Space.x3)),
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
                hintText: _hasKey ? '已保存，留空表示不改' : (local ? '本机服务可以不填' : '粘贴你的 Key'),
                helperText: _hasKey ? '已保存一个 Key（不显示明文）' : keyHint,
                helperMaxLines: 2,
                suffixIcon: _hasKey ? IconButton(tooltip: '清除已保存的 Key', icon: const Icon(Icons.delete_outline), onPressed: _clearKey) : null,
              ),
            ),
            const SizedBox(height: Space.x3),
            InfoBanner(
              app.secrets.persistent ? 'Key 用系统密钥库（Android Keystore）加密保存，不会写进普通设置文件或日志。' : '这台设备上安全存储不可用，Key 只保存在内存里，关掉应用后要重新填写。',
              tone: app.secrets.persistent ? BannerTone.info : BannerTone.warning,
            ),
            const SizedBox(height: Space.x3),
            OutlinedButton.icon(onPressed: _busy ? null : _test, icon: const Icon(Icons.wifi_tethering, size: 18), label: const Text('测试连接')),
            if (_busy)
              const Padding(
                padding: EdgeInsets.only(top: Space.x2),
                child: LinearProgressIndicator(),
              ),
            if (_status != null)
              InfoBanner(
                _status!,
                tone: _statusOk ? BannerTone.info : BannerTone.danger,
                margin: const EdgeInsets.only(top: Space.x2),
              ),
          ],
        ),
        SettingsGroup(
          title: '模型（${_models.length}）',
          footer: _models.isEmpty ? '还没有模型。点“获取模型”从接口读列表勾选，或者手动添加模型 ID。' : '点一个模型改它的上下文长度、最大输出、能不能看图、思考档位和单价。',
          children: [
            for (final m in _models)
              SettingsRow(
                title: m.name,
                subtitle: '${m.contextLength ~/ 1000}K 上下文 · 输出 ${m.maxOutput ~/ 1000}K · ${m.vision ? '文本和图片' : '文本'}${m.thinking ? ' · 可思考' : ''}',
                trailing: Icon(Icons.tune, size: 20, color: c.textFaint),
                onTap: () => _editModel(m),
              ),
            SettingsRow(key: const Key('channel-fetch'), icon: Icons.cloud_download_outlined, title: '获取模型', subtitle: '从接口读模型列表，勾选要用的', enabled: !_busy, onTap: _fetchModels),
            SettingsRow(icon: Icons.add, title: '手动添加模型 ID', accent: true, onTap: _addManually),
          ],
        ),
        FilledButton(key: const Key('channel-save'), onPressed: _save, child: const Text('保存')),
      ],
    );
  }
}
