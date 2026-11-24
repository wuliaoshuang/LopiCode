// 设计约束（子代理与团队 · 390×844）— 2026-11-24 从 settings_agent.dart 拆出来并按设置的统一样式重排
// - 三组：〔子代理〕总开关；开着时下面多两行分段选择（最多委派几层 / 最多同时跑几个），名称在上、分段独占一行；
//   〔子代理可以换用的模型〕（子代理开着才有）一行一个模型勾选，用途写在脚注；
//   〔智能体团队〕一个开关，代价（明显多花钱）写在脚注。
// - 说明只在副标题和脚注里，卡片里不再夹说明段落。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lopicode/core/stores.dart';
import 'package:lopicode/state/config_providers.dart';
import 'package:lopicode/state/models_state.dart';
import 'package:lopicode/ui/app_ref.dart';
import 'package:lopicode/ui/settings_widgets.dart';
import 'package:material_ui/material_ui.dart';

class SubagentSettingsScreen extends ConsumerStatefulWidget {
  const SubagentSettingsScreen({super.key});

  @override
  ConsumerState<SubagentSettingsScreen> createState() => _SubagentSettingsScreenState();
}

class _SubagentSettingsScreenState extends ConsumerState<SubagentSettingsScreen> {
  Future<void> _set(String key, Object? value) async {
    final app = appOf(context);
    await app.settings.set(key, value);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    ref
      ..watch(agentSettingsRevProvider)
      ..watch(modelsProvider);
    final app = appOf(context);
    final on = app.settings.getBool(SettingKeys.subagentEnabled, true);
    final depth = (app.settings.get<int>(SettingKeys.subagentMaxDepth) ?? 1).clamp(0, 3);
    final conc = (app.settings.get<int>(SettingKeys.subagentMaxConcurrent) ?? 2).clamp(1, 4);
    final allowed = {
      for (final m in app.settings.get<List<dynamic>>(SettingKeys.subagentAllowedModels) ?? const [])
        if (m is String) m,
    };
    final noModels = app.models.channels.every((ch) => ch.models.isEmpty);
    return SettingsPage(
      title: '子代理与团队',
      children: [
        SettingsGroup(
          title: '子代理',
          children: [
            SettingsSwitchRow(
              key: const Key('subagent-enabled'),
              title: '允许派出子代理',
              subtitle: 'Agent 可以把一件事交给另一个独立的 Agent 去做，做完把结果交回来',
              value: on,
              onChanged: (v) => _set(SettingKeys.subagentEnabled, v),
            ),
            if (on) ...[
              SettingsSegmentRow<int>(
                segmentKey: const Key('subagent-depth'),
                title: '最多委派几层',
                subtitle: '1 层＝只有主智能体能派；2 层＝子代理还能再派一层。层数越多越费钱',
                segments: const [(1, '1 层'), (2, '2 层'), (3, '3 层')],
                selected: depth.clamp(1, 3),
                onChanged: (v) => _set(SettingKeys.subagentMaxDepth, v),
              ),
              SettingsSegmentRow<int>(
                segmentKey: const Key('subagent-concurrent'),
                title: '最多同时跑几个',
                segments: const [(1, '1'), (2, '2'), (3, '3'), (4, '4')],
                selected: conc,
                onChanged: (v) => _set(SettingKeys.subagentMaxConcurrent, v),
              ),
            ],
          ],
        ),
        if (on)
          SettingsGroup(
            title: '子代理可以换用的模型',
            footer: '默认和上级用同一个模型。勾上的模型，Agent 派子代理时可以指定改用（比如便宜的小模型）。',
            children: [
              if (noModels) const SettingsRow(title: '还没有模型', subtitle: '先到“模型与渠道”添加', enabled: false),
              for (final ch in app.models.channels)
                for (final m in ch.models)
                  SettingsCheckRow(
                    title: m.name,
                    subtitle: ch.name,
                    checked: allowed.contains('${ch.id}/${m.id}'),
                    onChanged: (v) {
                      final next = {...allowed};
                      v ? next.add('${ch.id}/${m.id}') : next.remove('${ch.id}/${m.id}');
                      _set(SettingKeys.subagentAllowedModels, next.toList()..sort());
                    },
                  ),
            ],
          ),
        SettingsGroup(
          title: '智能体团队',
          footer: '默认关闭。开启后在对话页右上角的菜单里能看到“智能体团队”。团队会明显多花钱，适合大任务。',
          children: [
            SettingsSwitchRow(
              key: const Key('team-enabled'),
              title: '开启智能体团队',
              subtitle: '主智能体和子代理共用一块任务板：谁负责什么、先后顺序、各自能改哪些文件',
              value: app.settings.getBool(SettingKeys.teamEnabled),
              onChanged: (v) => _set(SettingKeys.teamEnabled, v),
            ),
          ],
        ),
      ],
    );
  }
}
