// 设计约束（设置 ›“对话”里和 Agent 干活方式有关的三行 · 390×844）— 2026-11-24
// - 和这张卡里别的行同一个样子：图标 + 名称 + 一行说明 + 右边的开关 / 当前值。一行只管一件事。
// - 说明里把代价写明白（自动压缩会多调用一次模型、多花一点额度），不藏。
// - 步数上限点开是底部弹层，几个固定档位单选（不用滑块：手机上滑块拖不准，档位一眼能比）。
import 'package:lopicode/agent/agent_runner.dart';
import 'package:lopicode/app_services.dart';
import 'package:lopicode/core/stores.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/chrome.dart';
import 'package:material_ui/material_ui.dart';

/// 步数上限可选的档位。
const List<int> kStepLimitChoices = [10, 20, 30, 50, 80, 100];

/// 现在的步数上限（没设过是默认 30；存了范围外的数会夹回 10–100）。
int stepLimitOf(SettingsStore settings) => (settings.get<int>(SettingKeys.agentMaxSteps) ?? AgentRunner.defaultMaxSteps).clamp(AgentRunner.minMaxSteps, AgentRunner.maxMaxSteps);

/// “对话”卡片里的三行：显示思考过程、上下文快满时自动压缩、连续执行多少步后问我。
List<Widget> agentChatSettingRows(BuildContext context, AppServices app) {
  final s = app.settings;
  final limit = stepLimitOf(s);
  return [
    GroupRow(
      icon: Icons.psychology_alt_outlined,
      title: '显示思考过程',
      subtitle: '模型给了思考内容时，在聊天里折成一行，点开看',
      trailing: Switch(key: const Key('settings-thinking'), value: s.getBool(SettingKeys.chatThinking, true), onChanged: (v) => s.set(SettingKeys.chatThinking, v)),
    ),
    GroupRow(
      icon: Icons.compress,
      title: '上下文快满时自动压缩',
      subtitle: '把较早的对话压成摘要再继续。会多调用一次模型、多花一点额度',
      trailing: Switch(key: const Key('settings-auto-compact'), value: s.getBool(SettingKeys.agentAutoCompact, true), onChanged: (v) => s.set(SettingKeys.agentAutoCompact, v)),
    ),
    GroupRow(
      key: const Key('settings-step-limit'),
      icon: Icons.format_list_numbered,
      title: '连续执行多少步后问我',
      subtitle: '到了会停下来问要不要继续；自动化任务到了直接停',
      value: '$limit 步',
      onTap: () async {
        final picked = await showModalBottomSheet<int>(
          context: context,
          builder: (_) => StepLimitSheet(current: limit),
        );
        if (picked != null && picked != limit) await s.set(SettingKeys.agentMaxSteps, picked);
      },
    ),
  ];
}

class StepLimitSheet extends StatelessWidget {
  const StepLimitSheet({super.key, required this.current});
  final int current;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x1),
              child: Text('连续执行多少步后问我', style: t.titleLarge),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x2),
              child: Text('一步＝Agent 调用一次工具（读文件、改文件、执行命令……）。一轮里连着做满这么多步，它会停下来问你要不要继续；选“继续”就再做这么多步。', style: t.bodySmall?.copyWith(color: c.textMuted, height: 1.5)),
            ),
            for (final n in kStepLimitChoices)
              ListTile(
                key: Key('step-limit-$n'),
                dense: true,
                leading: Icon(n == current ? Icons.radio_button_checked : Icons.radio_button_off, color: n == current ? c.accent : c.textFaint),
                title: Text(n == AgentRunner.defaultMaxSteps ? '$n 步（默认）' : '$n 步'),
                onTap: () => Navigator.pop(context, n),
              ),
            const SizedBox(height: Space.x2),
          ],
        ),
      ),
    );
  }
}
