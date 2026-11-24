// “运行环境”页顶上的状态卡（设计约束见 runtime_screen.dart 开头）。
// 一张卡只说一件事：Ubuntu 现在是什么状态；最多一个按钮，就是这一刻该做的那件事。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lopicode/runtime/linux_runtime.dart';
import 'package:lopicode/runtime/runtime_snapshot.dart';
import 'package:lopicode/state/runtime_extras.dart';
import 'package:lopicode/state/runtime_state.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/chrome.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';

class RuntimeStatusCard extends ConsumerWidget {
  const RuntimeStatusCard({super.key, required this.runtime, required this.ctl});
  final RuntimeView runtime;
  final RuntimeNotifier ctl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final failedInstall = runtime.phase == RuntimePhase.notInstalled && runtime.installError != null;
    final (String status, Color tone, IconData mark) = switch (runtime.phase) {
      RuntimePhase.installed when !runtime.prootBundled => ('已下载，但进不去', c.warning, Icons.warning_amber_rounded),
      RuntimePhase.installed when !runtime.shouldUseLinux => (runtime.localShellAllowed ? '启动失败，已退回本机 shell' : '连续启动失败，终端暂时进不去', c.danger, Icons.error_outline),
      RuntimePhase.installed => ('已安装，新开的终端会直接进 Ubuntu', c.accent, Icons.check_circle),
      RuntimePhase.downloading => ('正在下载…', c.textMuted, Icons.downloading),
      RuntimePhase.verifying => ('正在校验…', c.textMuted, Icons.downloading),
      RuntimePhase.extracting => ('正在解压…', c.textMuted, Icons.downloading),
      RuntimePhase.notInstalled when failedInstall => ('上次安装没有成功', c.danger, Icons.error_outline),
      RuntimePhase.notInstalled => ('未安装', c.textMuted, Icons.radio_button_unchecked),
    };
    final usage = runtime.installed ? ref.watch(runtimeDiskUsageProvider).value : null;
    return GroupCard(
      margin: EdgeInsets.zero,
      dividers: false,
      padding: const EdgeInsets.all(Space.x4),
      children: [
        Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(Radii.md)),
              child: Icon(Icons.terminal_rounded, size: 22, color: c.accent),
            ),
            const SizedBox(width: Space.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Ubuntu 24.04', style: t.titleMedium?.copyWith(height: 1.3)),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(mark, size: 14, color: tone),
                      const SizedBox(width: Space.x1),
                      Expanded(
                        child: Text(
                          status,
                          key: const Key('runtime-status'),
                          style: t.bodySmall?.copyWith(color: tone, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.x3),
        Text(
          runtime.installed
              ? '在手机上跑一个不需要 root 的 Ubuntu，终端和 Agent 的命令都在里面执行。'
              : runtime.localShellAllowed
              ? '装好后终端里能直接用 apt、node、python。不装也不影响别的功能。'
              : '终端和 Agent 执行命令都要用它，装好后能直接用 apt、node、python。不装的话聊天、文件、搭建照常能用。',
          style: t.bodySmall?.copyWith(color: c.textFaint, height: 1.5),
        ),
        if (runtime.installed) ...[
          const SizedBox(height: Space.x3),
          Divider(height: 1, thickness: 1, color: c.border),
          const SizedBox(height: Space.x3),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 占用是现数的：没数完、数不出来就不放这一格，不编数字
              if (usage != null)
                Expanded(
                  child: _Fact(label: '占用空间', value: '约 ${formatBytes(usage)}', valueKey: const Key('runtime-usage')),
                ),
              const Expanded(
                child: _Fact(label: '项目目录挂在', value: '/workspace'),
              ),
            ],
          ),
        ],
        if (!runtime.prootBundled) ...[
          const SizedBox(height: Space.x3),
          InfoBanner('这个安装包里缺少进入 Ubuntu 要用的文件（${runtime.missingLauncherFiles.join('、')}），环境装了也进不去，所以这里先不提供安装。请重新安装完整的 LopiCode 安装包。', key: const Key('runtime-no-proot'), tone: BannerTone.warning),
        ],
        if (runtime.installError != null) ...[const SizedBox(height: Space.x3), InfoBanner(runtime.installError!, key: const Key('runtime-install-error'), tone: BannerTone.danger)],
        if (runtime.installed && runtime.usable && !runtime.shouldUseLinux) ...[
          const SizedBox(height: Space.x3),
          InfoBanner(runtime.lastLaunchError ?? '连续启动失败', tone: BannerTone.danger),
          const SizedBox(height: Space.x4),
          FilledButton(key: const Key('runtime-retry-launch'), onPressed: ctl.resetLaunchFailures, child: const Text('重新尝试进入 Ubuntu')),
        ],
        if (runtime.busy) ...[
          const SizedBox(height: Space.x4),
          ClipRRect(
            borderRadius: BorderRadius.circular(Radii.sm),
            child: LinearProgressIndicator(minHeight: 6, value: runtime.progressTotal > 0 ? runtime.progressDone / runtime.progressTotal : null),
          ),
          const SizedBox(height: Space.x2),
          Row(
            children: [
              Expanded(
                child: Text(
                  runtime.phase == RuntimePhase.downloading
                      ? '已下载 ${formatBytes(runtime.progressDone)} / ${formatBytes(runtime.progressTotal)}'
                      : runtime.phase == RuntimePhase.verifying
                      ? '下载完成，正在核对文件'
                      : '解压中，不要退出应用',
                  key: const Key('runtime-progress'),
                  style: t.bodySmall,
                ),
              ),
              if (runtime.progressTotal > 0)
                Text(
                  '${(runtime.progressDone * 100 / runtime.progressTotal).clamp(0, 100).floor()}%',
                  key: const Key('runtime-percent'),
                  style: t.labelMedium?.copyWith(color: c.text),
                ),
            ],
          ),
          const SizedBox(height: Space.x4),
          OutlinedButton(key: const Key('runtime-cancel'), onPressed: ctl.cancelInstall, child: const Text('取消（下到一半的会留着）')),
        ],
        if (runtime.phase == RuntimePhase.notInstalled && runtime.prootBundled) ...[
          const SizedBox(height: Space.x3),
          Text(
            runtimeSpaceNote(runtime),
            key: const Key('runtime-space'),
            style: t.bodySmall?.copyWith(color: c.textFaint, height: 1.5),
          ),
          const SizedBox(height: Space.x4),
          FilledButton(
            key: const Key('runtime-install'),
            onPressed: ctl.install,
            child: Text(
              runtime.partialBytes > 0
                  ? '继续下载（已有 ${formatBytes(runtime.partialBytes)}）'
                  : failedInstall
                  ? '重新安装'
                  : '安装运行环境',
            ),
          ),
        ],
      ],
    );
  }
}

/// 状态卡里的一格事实：小字名称在上，数值在下。
class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value, this.valueKey});
  final String label;
  final String value;
  final Key? valueKey;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: t.bodySmall?.copyWith(color: context.colors.textFaint)),
        const SizedBox(height: 2),
        Text(value, key: valueKey, style: t.titleSmall),
      ],
    );
  }
}
