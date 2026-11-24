// 设计约束（设置一级页顶部的概况卡 · 390×844）— 2026-11-24 随设置重排收紧
// - 只读状态，两段，一段一件事：①新对话用的模型（和它的余额 / 额度）②运行环境。整段可点，分别进“模型与渠道”“运行环境”。
//   不再有蓝色文字入口：额度上限的入口只在下面“模型”组的“额度与余额”一处。
// - 每段：名称（16 / 600）+ 右边一句状态（14 弱色）；下面一行小字（12 弱色）；有真实进度时再加一根进度条。
// - 数字都是真实的：只有渠道是 DeepSeek 官方、且设了额度上限时才有进度条（已用 ÷ 上限）和“已使用 x%（剩余 ¥y）”；
//   DeepSeek 没设上限只写余额；其他渠道只写模型名和渠道名。运行环境装好 = 满，下载中 = 滚动条。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lopicode/agent/model_config.dart';
import 'package:lopicode/agent/quota.dart';
import 'package:lopicode/app_services.dart';
import 'package:lopicode/runtime/runtime_snapshot.dart';
import 'package:lopicode/state/models_state.dart';
import 'package:lopicode/state/runtime_state.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/app_ref.dart';
import 'package:lopicode/ui/chrome.dart';
import 'package:material_ui/material_ui.dart';

/// 运行环境现在的状态，一个短词。
String runtimeStateLabel(RuntimeView r) => switch (r.phase) {
  RuntimePhase.installed when !r.usable => '已下载，进不去',
  RuntimePhase.installed => '已安装',
  RuntimePhase.downloading => '正在下载',
  RuntimePhase.verifying => '正在校验',
  RuntimePhase.extracting => '正在解压',
  RuntimePhase.notInstalled => '未安装',
};

class SettingsOverviewCard extends ConsumerStatefulWidget {
  const SettingsOverviewCard({super.key, required this.onModels, required this.onRuntime});
  final VoidCallback onModels;
  final VoidCallback onRuntime;

  @override
  ConsumerState<SettingsOverviewCard> createState() => _SettingsOverviewCardState();
}

class _SettingsOverviewCardState extends ConsumerState<SettingsOverviewCard> {
  bool _asked = false;

  ResolvedModel? _model(AppServices app) {
    final models = app.models;
    return models.resolve(models.newChatUsesFixed ? models.fixedSelection : models.lastSelection) ?? models.firstAvailable;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_asked) return;
    _asked = true;
    // 进设置页查一次余额（有节流；不是 DeepSeek 官方渠道什么都不做）。
    final app = appOf(context);
    final model = _model(app);
    if (model != null) app.quota.refresh(model.channel);
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(modelsProvider);
    final app = appOf(context);
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final model = _model(app);

    /// [value] 为 null 时不画进度条（[bar] 为 true 且 value 为 null 是“进行中”的滚动条）。
    Widget block({required Key key, required VoidCallback onTap, required String title, required String sub, String? state, double? value, bool bar = true, Color? color, Key? stateKey}) => InkWell(
      key: key,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(Space.x4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(title, style: t.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                if (state != null) ...[
                  const SizedBox(width: Space.x3),
                  Text(
                    state,
                    key: stateKey,
                    style: t.bodyMedium?.copyWith(color: color ?? c.textFaint, height: 1.3),
                  ),
                ],
                const SizedBox(width: Space.x1),
                Icon(Icons.chevron_right, size: 20, color: c.textFaint),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              sub,
              style: t.bodySmall?.copyWith(color: c.textFaint),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (bar) ...[
              const SizedBox(height: Space.x3),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(key: const Key('overview-bar'), value: value, minHeight: 6, color: color ?? c.accentFill, backgroundColor: c.border),
              ),
            ],
          ],
        ),
      ),
    );

    const modelsKey = Key('overview-models');
    Widget modelBlock() {
      if (model == null) return block(key: modelsKey, onTap: widget.onModels, title: '还没有可用的模型', sub: '添加渠道和模型后才能和 Agent 对话', state: '未配置', bar: false);
      final sub = '新对话用的模型 · ${model.channel.name}';
      // 不是 DeepSeek 官方：只有模型名和渠道名。
      if (!isDeepSeekOfficial(model.channel.baseUrl)) return block(key: modelsKey, onTap: widget.onModels, title: model.model.name, sub: sub, bar: false);
      return QuotaBuilder(
        builder: (context, _) {
          final q = app.quota.quotaOf(model.channel.id);
          final state = app.quota.stateOf(model.channel.id);
          if (q != null) {
            final info = state.result?.of(q.currency);
            return block(
              key: modelsKey,
              onTap: widget.onModels,
              title: model.model.name,
              sub: '${model.channel.name} · ${info != null ? '余额 ${formatMoney(info.currency, info.total)}' : (state.keyInvalid ? 'Key 无效，查不到余额' : (state.loading ? '正在查余额…' : '余额没查到'))}',
              state: '已使用 ${q.percent}%（剩余 ${formatMoney(q.currency, q.remaining)}）',
              stateKey: const Key('overview-quota'),
              value: q.fraction,
              color: q.reached ? c.danger : null,
            );
          }
          // 没设上限：只写余额，不画进度条。
          final infos = state.result?.infos ?? const <BalanceInfo>[];
          final text = infos.isNotEmpty
              ? '余额 ${[for (final i in infos) formatMoney(i.currency, i.total)].join(' / ')}'
              : (state.loading ? '正在查余额…' : (state.keyInvalid ? 'Key 无效，查不到余额' : (state.error != null ? '余额没查到' : null)));
          return block(key: modelsKey, onTap: widget.onModels, title: model.model.name, sub: sub, state: text, stateKey: const Key('overview-balance'), bar: false);
        },
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: Space.x6),
      child: GroupCard(
        key: const Key('settings-overview'),
        margin: EdgeInsets.zero,
        dividers: false,
        children: [
          modelBlock(),
          Divider(height: 1, thickness: 1, indent: Space.x4, endIndent: Space.x4, color: c.border),
          Consumer(
            builder: (context, ref, _) {
              final r = ref.watch(runtimeProvider);
              final double? value = switch (r.phase) {
                RuntimePhase.installed => 1.0,
                RuntimePhase.notInstalled => 0.0,
                _ => null,
              };
              return block(key: const Key('overview-runtime'), onTap: widget.onRuntime, title: '运行环境', sub: 'Ubuntu 24.04 · 终端和 Agent 的命令在里面跑', state: runtimeStateLabel(r), value: value);
            },
          ),
        ],
      ),
    );
  }
}
