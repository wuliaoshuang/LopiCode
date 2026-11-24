// 选模型的底部面板：渠道（自动换行标签）→ 模型（列表）→ 思考深度（一行分段）；内容多了可滚动。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lopicode/agent/model_config.dart';
import 'package:lopicode/state/models_state.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/app_ref.dart';
import 'package:lopicode/ui/provider_icon.dart';
import 'package:lopicode/ui/widgets.dart';
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
  String _level = 'off';

  @override
  void initState() {
    super.initState();
    _channelId = widget.current?.channelId;
    _modelId = widget.current?.modelId;
    _level = widget.current?.level ?? 'off';
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(modelsProvider);
    final app = appOf(context);
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final channels = app.models.channels;
    final channel = app.models.channel(_channelId) ?? channels.firstOrNull;
    final model = channel?.model(_modelId);
    final levels = model != null && model.thinking ? model.levels : const <String>[];
    final level = levels.contains(_level) ? _level : 'off';
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x4),
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
                const SectionLabel('渠道'),
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
                const SizedBox(height: Space.x3),
                const SectionLabel('模型'),
                if (channel!.models.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: Space.x3),
                    child: Text('这个渠道还没勾选模型。', style: t.bodyMedium?.copyWith(color: c.textMuted)),
                  )
                else ...[
                  for (final m in channel.models)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(m.id == model?.id ? Icons.radio_button_checked : Icons.radio_button_off, color: m.id == model?.id ? c.accent : c.textFaint),
                      title: Text(m.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text('${m.contextLength ~/ 1000}K 上下文 · ${m.vision ? '支持图片' : '纯文本'}${m.thinking ? ' · 支持思考' : ''}', style: t.bodySmall),
                      onTap: () => setState(() => _modelId = m.id),
                    ),
                ],
                if (levels.isNotEmpty) ...[
                  const SizedBox(height: Space.x2),
                  const SectionLabel('思考深度'),
                  SegmentedButton<String>(
                    showSelectedIcon: false,
                    segments: [
                      const ButtonSegment(value: 'off', label: Text('关')),
                      for (final l in levels) ButtonSegment(value: l, label: Text(thinkingLabel(l))),
                    ],
                    selected: {level},
                    onSelectionChanged: (v) => setState(() => _level = v.first),
                  ),
                ],
                const SizedBox(height: Space.x4),
                FilledButton(onPressed: model == null ? null : () => Navigator.pop(context, ModelSelectionResult(ModelSelection(channel.id, model.id, level))), child: const Text('确认模型')),
              ],
              TextButton(onPressed: () => Navigator.pop(context, 'manage'), child: const Text('管理渠道和模型')),
            ],
          ),
        ),
      ),
    );
  }
}
