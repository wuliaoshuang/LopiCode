// 选模型的底部面板。
//
// 设计约束（390×844，按 refactoring-ui 的层级 / 间距规矩，颜色字号都走 lib/theme/ tokens）：
// - 上半截是“选哪个”：渠道（自动换行标签）→ 模型（列表），模型多了只滚这一截。
// - 下半截固定在面板底部、不跟着滚：“思考深度”和“用这个模型”。模型再多也不用滚到底才看得见。
// - 选中任何模型都有“思考深度”这一段。模型没标记“可思考”时不整段消失，而是一行说明加一个就地打开的开关。
// - 档位只给这个模型在这家接口上真实有区别的（lib/agent/thinking_support.dart）：只能开关的就只有“关 / 开”，
//   调不了的写一句为什么，不给点了没用的档位。
// - 每个模型上次设的档位记在设置里（ai.thinkingLevels），切走再切回来还是它。
// - 一行只做一件事；开关、分段、按钮的可点区域都不小于 44。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lopicode/agent/model_config.dart';
import 'package:lopicode/agent/thinking_support.dart';
import 'package:lopicode/state/models_state.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/provider_icon.dart';
import 'package:material_ui/material_ui.dart';

// ── 模型选择 ─────────────────────────────────────────
class ModelSelectionResult {
  ModelSelectionResult(this.selection);
  final ModelSelection selection;
}

/// 先选渠道，再选模型和思考深度。返回 [ModelSelectionResult]，或字符串 'manage'（去管理渠道）。
class ModelPickerSheet extends ConsumerStatefulWidget {
  const ModelPickerSheet({super.key, this.current});
  final ModelSelection? current;

  @override
  ConsumerState<ModelPickerSheet> createState() => _ModelPickerSheetState();
}

class _ModelPickerSheetState extends ConsumerState<ModelPickerSheet> {
  String? _channelId;
  String? _modelId;

  /// 这次在面板里手动点过的档位（键同 [thinkingLevelKey]）；没点过的模型用记住的那个。
  final Map<String, String> _picked = {};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _channelId = widget.current?.channelId;
    _modelId = widget.current?.modelId;
  }

  /// 这个模型现在该显示哪一档：这次点过的 → 以前记住的 → 打开面板时带进来的 → 关。
  String _levelFor(ModelsState models, Channel ch, ModelSpec m) {
    final cur = widget.current;
    final want = _picked[thinkingLevelKey(ch.id, m.id)] ?? models.thinkingLevelOf(ch.id, m.id) ?? (cur != null && cur.channelId == ch.id && cur.modelId == m.id ? cur.level : 'off');
    return normalizeThinkingLevel(thinkingOptions(ch, m), want);
  }

  Future<void> _mark(Channel ch, ModelSpec m, bool on) async {
    if (_saving) return;
    setState(() => _saving = true);
    await ref.read(modelsProvider.notifier).setModelThinking(ch.id, m.id, on);
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _confirm(Channel ch, ModelSpec m, String level) async {
    final nav = Navigator.of(context);
    if (m.thinking) await ref.read(modelsProvider.notifier).setThinkingLevel(ch.id, m.id, level);
    nav.pop(ModelSelectionResult(ModelSelection(ch.id, m.id, level)));
  }

  @override
  Widget build(BuildContext context) {
    final models = ref.watch(modelsProvider);
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final channels = models.channels;
    final channel = models.channel(_channelId) ?? channels.firstOrNull;
    final model = channel?.model(_modelId);
    final level = channel == null || model == null ? 'off' : _levelFor(models, channel, model);
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('选择模型', style: t.titleLarge),
              const SizedBox(height: Space.x3),
              if (channels.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: Space.x6),
                  child: Text('还没有渠道。先去添加一个渠道，填好接口地址和 API Key。', style: t.bodyMedium?.copyWith(color: c.textMuted)),
                )
              else ...[
                Flexible(
                  child: SingleChildScrollView(
                    key: const ValueKey('model-picker-list'),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('渠道', style: t.labelMedium),
                        const SizedBox(height: Space.x2),
                        Wrap(
                          spacing: Space.x2,
                          runSpacing: Space.x2,
                          children: [
                            for (final item in channels)
                              ChoiceChip(
                                avatar: ProviderIcon.forBaseUrl(item.baseUrl, size: 24),
                                label: Text(item.name),
                                selected: item.id == channel?.id,
                                onSelected: (_) => setState(() {
                                  _channelId = item.id;
                                  _modelId = null;
                                }),
                              ),
                          ],
                        ),
                        const SizedBox(height: Space.x4),
                        Text('模型', style: t.labelMedium),
                        const SizedBox(height: Space.x1),
                        if (channel!.models.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: Space.x3),
                            child: Text('这个渠道还没勾选模型。', style: t.bodyMedium?.copyWith(color: c.textMuted)),
                          )
                        else
                          for (final m in channel.models)
                            ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(m.id == model?.id ? Icons.radio_button_checked : Icons.radio_button_off, color: m.id == model?.id ? c.accent : c.textFaint),
                              title: Text(m.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: Text('${m.contextLength ~/ 1000}K 上下文 · ${m.vision ? '能看图' : '只看文字'}${m.thinking ? ' · 可思考' : ''}', style: t.bodySmall),
                              onTap: () => setState(() => _modelId = m.id),
                            ),
                      ],
                    ),
                  ),
                ),
                Divider(height: 1, color: c.border),
                if (model != null)
                  _ThinkingSection(
                    channel: channel,
                    model: model,
                    level: level,
                    busy: _saving,
                    onMark: (on) => _mark(channel, model, on),
                    onLevel: (l) => setState(() => _picked[thinkingLevelKey(channel.id, model.id)] = l),
                  ),
                const SizedBox(height: Space.x3),
                FilledButton(onPressed: model == null || _saving ? null : () => _confirm(channel, model, level), child: const Text('用这个模型')),
              ],
              TextButton(onPressed: () => Navigator.pop(context, 'manage'), child: const Text('管理渠道和模型')),
            ],
          ),
        ),
      ),
    );
  }
}

/// 面板底部固定的“思考深度”：一行开关（这个模型能不能思考），下面是它真实支持的档位。
class _ThinkingSection extends StatelessWidget {
  const _ThinkingSection({required this.channel, required this.model, required this.level, required this.busy, required this.onMark, required this.onLevel});
  final Channel channel;
  final ModelSpec model;
  final String level;
  final bool busy;
  final ValueChanged<bool> onMark;
  final ValueChanged<String> onLevel;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final caps = thinkingCaps(channel.protocol, channel.baseUrl, model.id);
    final options = thinkingOptions(channel, model);
    final hint = t.bodySmall?.copyWith(color: c.textMuted);
    return Column(
      key: const ValueKey('thinking-section'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 整行可点（高 48），开关只是这一行的状态
        InkWell(
          key: const ValueKey('thinking-mark'),
          onTap: busy ? null : () => onMark(!model.thinking),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('思考深度', style: t.labelMedium),
                      if (!model.thinking) Text('这个模型没有标记为可思考', style: hint),
                    ],
                  ),
                ),
                Text(model.thinking ? '可思考' : '打开', style: t.bodySmall?.copyWith(color: model.thinking ? c.textMuted : c.accent)),
                const SizedBox(width: Space.x2),
                IgnorePointer(
                  child: Switch(value: model.thinking, onChanged: (_) {}),
                ),
              ],
            ),
          ),
        ),
        if (!model.thinking)
          Text('模型支持思考（推理）的话，打开就能在这里调。不支持的模型打开了，接口可能会报错。', style: hint)
        else ...[
          if (options.length > 1)
            SegmentedButton<String>(
              key: const ValueKey('thinking-levels'),
              showSelectedIcon: false,
              // 默认只有 40 高：加一点上下留白，凑够 44 的可点高度
              style: const ButtonStyle(visualDensity: VisualDensity(vertical: 1)),
              segments: [for (final l in options) ButtonSegment(value: l, label: Text(thinkingOptionLabel(caps, l)))],
              selected: {level},
              onSelectionChanged: (v) => onLevel(v.first),
            ),
          const SizedBox(height: Space.x2),
          Text(
            [if (caps.note.isNotEmpty) caps.note, if (options.length > 1) (options.contains('on') ? '开着思考，回答更慢、花的 token 更多。' : '档位越高，思考越久、花的 token 越多。')].join('\n'),
            key: const ValueKey('thinking-note'),
            style: hint,
          ),
        ],
      ],
    );
  }
}
