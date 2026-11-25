// 设计约束（模型的两个底部面板 · 390×844）— 2026-11-24 从 settings_ai.dart 拆出来（那个文件只许变短）
// - “勾选要用的模型”：标题 + 一句统计 + 搜索框 + 一行一个模型的勾选列表 + 确定。
// - “模型设置”：显示名 → 上下文长度（档位 + 手填）→ 最大输出 → 输入类型 → 可以思考（和档位）→ 单价 → 确定 / 从这个渠道去掉。
//   单个模型的细节都在这里改，不挤在渠道页的列表行上。
// - 思考参数没对着官方文档核对过的服务商 / 模型：“可以思考”不给开关和档位，原位置只有标题和一句灰色说明
//   （和选模型面板里是同一句话）；存着的标记原样留着不动。
import 'package:lopicode/agent/model_config.dart';
import 'package:lopicode/agent/protocols.dart';
import 'package:lopicode/agent/thinking_support.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// 从接口读到的模型里勾选要用的；点“确定”交回勾上的模型 ID。
class RemoteModelsSheet extends StatefulWidget {
  const RemoteModelsSheet({super.key, required this.models, required this.selected});
  final List<RemoteModel> models;
  final Set<String> selected;

  @override
  State<RemoteModelsSheet> createState() => _RemoteModelsSheetState();
}

class _RemoteModelsSheetState extends State<RemoteModelsSheet> {
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

/// 改一个模型的细节。不动传进来的 [model]：点“确定”交回一份改好的 [ModelSpec]；交回 'remove' 表示把它从渠道里去掉。
class ModelSpecSheet extends StatefulWidget {
  const ModelSpecSheet({super.key, required this.model, required this.protocol, required this.baseUrl});
  final ModelSpec model;

  /// 这个模型所在渠道现在填的协议和地址：用来判断它的思考参数核对过没有。
  final ChatProtocol protocol;
  final String baseUrl;

  @override
  State<ModelSpecSheet> createState() => _ModelSpecSheetState();
}

class _ModelSpecSheetState extends State<ModelSpecSheet> {
  late final _name = TextEditingController(text: widget.model.name);
  late final _context = TextEditingController(text: '${widget.model.contextLength ~/ 1000}');
  late final _maxOut = TextEditingController(text: '${widget.model.maxOutput ~/ 1000}');
  static String _priceText(double? v) => v == null ? '' : (v == v.roundToDouble() ? v.toStringAsFixed(0) : '$v');
  late final _priceHit = TextEditingController(text: _priceText(widget.model.priceHit));
  late final _priceMiss = TextEditingController(text: _priceText(widget.model.priceMiss));
  late final _priceOut = TextEditingController(text: _priceText(widget.model.priceOutput));
  late bool _vision = widget.model.vision;
  late bool _thinking = widget.model.thinking;
  late final Set<String> _levels = {...widget.model.levels};
  late final ThinkingCaps _caps = thinkingCaps(widget.protocol, widget.baseUrl, widget.model.id);

  @override
  void dispose() {
    _name.dispose();
    _context.dispose();
    _maxOut.dispose();
    _priceHit.dispose();
    _priceMiss.dispose();
    _priceOut.dispose();
    super.dispose();
  }

  static double? _price(TextEditingController c) {
    final v = double.tryParse(c.text.trim());
    return v == null || v < 0 || !v.isFinite ? null : v;
  }

  void _save() {
    final m = widget.model;
    final ctx = int.tryParse(_context.text.trim());
    final out = int.tryParse(_maxOut.text.trim());
    final edited = m.copyWith(
      name: _name.text.trim().isEmpty ? m.id : _name.text.trim(),
      contextLength: ModelSpec.clampContext((ctx ?? ModelSpec.defaultContext ~/ 1000) * 1000),
      maxOutput: ((out ?? ModelSpec.defaultMaxOutput ~/ 1000) * 1000).clamp(1000, 400000),
      vision: _vision,
      // 没核对过的服务商这里改不了，存着的标记和档位原样留着
      thinking: _caps.verified ? _thinking && _levels.isNotEmpty : m.thinking,
      levels: _caps.verified
          ? [
              for (final l in kThinkingLevels)
                if (_levels.contains(l)) l,
            ]
          : m.levels,
      prices: (hit: _price(_priceHit), miss: _price(_priceMiss), output: _price(_priceOut)),
    );
    Navigator.pop(context, edited);
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
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: '显示名'),
            ),
            const SizedBox(height: Space.x4),
            Text('上下文长度', style: t.labelMedium),
            const SizedBox(height: Space.x2),
            Wrap(
              spacing: Space.x2,
              runSpacing: Space.x1,
              children: [
                for (final v in ModelSpec.contextChoices)
                  ChoiceChip(label: Text(v >= 1000000 ? '1M' : '${v ~/ 1000}K'), selected: ctxK == v ~/ 1000, onSelected: (_) => setState(() => _context.text = '${v ~/ 1000}')),
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
            if (!_caps.verified) ...[
              const SizedBox(height: Space.x4),
              Text('可以思考', style: t.labelMedium),
              const SizedBox(height: Space.x1),
              Text(_caps.note, key: const ValueKey('spec-thinking-unverified'), style: t.bodySmall),
            ] else ...[
              SwitchListTile(
                key: const ValueKey('spec-thinking'),
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
                      FilterChip(label: Text(thinkingLabel(l)), selected: _levels.contains(l), onSelected: (v) => setState(() => v ? _levels.add(l) : _levels.remove(l))),
                  ],
                ),
                const SizedBox(height: Space.x1),
                Text('有的服务商只分“关 / 开”，或者另有“最高”档；选模型时按它真实支持的显示。', style: t.bodySmall),
              ],
            ],
            const SizedBox(height: Space.x3),
            Text('单价（可不填）', style: t.labelMedium),
            const SizedBox(height: Space.x1),
            Text('单位：元 / 百万 tokens。三项都填了，聊天里的用量才会带“估算”金额；价格请照服务商官网填，LopiCode 不内置价格表。', style: t.bodySmall),
            const SizedBox(height: Space.x2),
            for (final (key, label, ctrl) in [('price-hit', '输入（缓存命中）', _priceHit), ('price-miss', '输入（缓存未命中）', _priceMiss), ('price-out', '输出', _priceOut)]) ...[
              TextField(
                key: Key(key),
                controller: ctrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: label, suffixText: '元 / 百万'),
              ),
              const SizedBox(height: Space.x2),
            ],
            const SizedBox(height: Space.x2),
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
