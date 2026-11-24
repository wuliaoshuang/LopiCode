// 设计约束（步数上限的底部弹层 · 390×844）— 2026-11-24
// - 入口在 设置 › 权限与执行 ›“连续执行多少步后问我”（settings_pages.dart）。
// - 几个固定档位单选（不用滑块：手机上滑块拖不准，档位一眼能比），一行一档，点了就收起。
import 'package:lopicode/agent/agent_runner.dart';
import 'package:lopicode/core/stores.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// 步数上限可选的档位。
const List<int> kStepLimitChoices = [10, 20, 30, 50, 80, 100];

/// 现在的步数上限（没设过是默认 30；存了范围外的数会夹回 10–100）。
int stepLimitOf(SettingsStore settings) => (settings.get<int>(SettingKeys.agentMaxSteps) ?? AgentRunner.defaultMaxSteps).clamp(AgentRunner.minMaxSteps, AgentRunner.maxMaxSteps);

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
