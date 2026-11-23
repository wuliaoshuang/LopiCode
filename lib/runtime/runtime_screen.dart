import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lopicode/runtime/linux_runtime.dart';
import 'package:lopicode/runtime/runtime_snapshot.dart';
import 'package:lopicode/runtime/runtime_sources.dart';
import 'package:lopicode/state/runtime_state.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/shell.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';

/// “运行环境”页：安装 / 卸载 Ubuntu 环境、选下载源、一键装常用运行时、看启动日志。
class RuntimeScreen extends ConsumerWidget {
  const RuntimeScreen({super.key, this.projectDir});

  /// 当前打开的项目目录；诊断时顺便检查它在 Ubuntu 里看不看得见。
  final String? projectDir;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final runtime = ref.watch(runtimeProvider);
    final ctl = ref.read(runtimeProvider.notifier);
    return Scaffold(
      appBar: const ShellAppBar(title: '运行环境'),
      body: Builder(
        builder: (context) => ListView(
          padding: const EdgeInsets.only(bottom: Space.x12),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.x4, Space.x4, Space.x4, 0),
              child: _StatusCard(runtime: runtime, ctl: ctl),
            ),
            const SectionLabel('下载源'),
            _MirrorRow(keyName: 'rootfs-source', label: '系统包', options: rootfsSources, value: runtime.rootfsSourceId, enabled: !runtime.busy, onChanged: ctl.setRootfsSource),
            _MirrorRow(keyName: 'apt-mirror', label: '装软件（apt）', options: aptMirrors, value: runtime.aptMirrorId, enabled: !runtime.busy, onChanged: ctl.setAptMirror),
            if (runtime.installed) ...[
              const SectionLabel('常用运行时'),
              if (!runtime.usable)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: Space.x4),
                  child: InfoBanner('环境进不去的时候装不了运行时。', tone: BannerTone.warning),
                )
              else ...[
                for (final pack in runtime.packs) _PackRow(runtime: runtime, ctl: ctl, pack: pack),
                if (runtime.packOutput.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(Space.x4, Space.x3, Space.x4, 0),
                    child: _LogBox(lines: runtime.packOutput, keyName: 'pack-output'),
                  ),
              ],
            ],
            if (runtime.installed) ...[
              const SectionLabel('一键诊断'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.x4),
                child: _DiagnosticsPanel(runtimeBusy: runtime.busy, projectDir: projectDir),
              ),
            ],
            const SectionLabel('日志'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.x4),
              child: runtime.logLines.isEmpty
                  ? Text('还没有记录。安装和每次启动失败的原因会记在这里。', style: Theme.of(context).textTheme.bodySmall)
                  : _LogBox(lines: runtime.logLines, keyName: 'runtime-log', copyable: true),
            ),
            if (runtime.installed || runtime.partialBytes > 0) ...[
              const SectionLabel('卸载'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.x4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('删掉整个 Ubuntu 环境和里面装的所有软件。项目文件不受影响。', style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: Space.x3),
                    OutlinedButton(
                      key: const Key('runtime-uninstall'),
                      style: OutlinedButton.styleFrom(foregroundColor: context.colors.danger),
                      onPressed: runtime.busy || runtime.runningPack != null ? null : () => _confirmUninstall(context, ctl),
                      child: Text(runtime.installed ? '卸载运行环境' : '删除没下完的文件'),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _confirmUninstall(BuildContext context, RuntimeNotifier ctl) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('卸载运行环境？'),
        content: const Text('Ubuntu 环境和里面装的 Node.js、Python 等都会删掉，要用得重新下载。项目文件不受影响。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          TextButton(
            key: const Key('runtime-uninstall-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: Text('卸载', style: TextStyle(color: context.colors.danger)),
          ),
        ],
      ),
    );
    if (ok == true) await ctl.uninstall();
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.runtime, required this.ctl});
  final RuntimeView runtime;
  final RuntimeNotifier ctl;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final (String status, Color tone) = switch (runtime.phase) {
      RuntimePhase.installed when !runtime.prootBundled => ('已下载，但进不去', c.warning),
      RuntimePhase.installed when !runtime.shouldUseLinux => ('启动失败，已退回本机 shell', c.danger),
      RuntimePhase.installed => ('已安装，新开的终端会直接进 Ubuntu', c.accent),
      RuntimePhase.downloading => ('正在下载…', c.textMuted),
      RuntimePhase.verifying => ('正在校验…', c.textMuted),
      RuntimePhase.extracting => ('正在解压…', c.textMuted),
      RuntimePhase.notInstalled => ('未安装', c.textMuted),
    };
    return Container(
      padding: const EdgeInsets.all(Space.x4),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Ubuntu 24.04', style: t.titleLarge),
          const SizedBox(height: Space.x1),
          Text(
            status,
            key: const Key('runtime-status'),
            style: t.bodyMedium?.copyWith(color: tone),
          ),
          const SizedBox(height: Space.x3),
          Text(runtime.installed ? '在手机上跑一个不需要 root 的 Ubuntu，终端和 Agent 的命令都在里面执行，项目目录挂在 /workspace。' : '装好后终端里能直接用 apt、node、python。不装也不影响别的功能。', style: t.bodySmall?.copyWith(height: 1.5)),
          if (!runtime.prootBundled) ...[
            const SizedBox(height: Space.x3),
            InfoBanner('这个安装包里缺少进入 Ubuntu 要用的文件（${runtime.missingLauncherFiles.join('、')}），环境装了也进不去，所以这里先不提供安装。请重新安装完整的 LopiCode 安装包。', key: const Key('runtime-no-proot'), tone: BannerTone.warning),
          ],
          if (runtime.installError != null) ...[const SizedBox(height: Space.x3), InfoBanner(runtime.installError!, key: const Key('runtime-install-error'), tone: BannerTone.danger)],
          if (runtime.installed && runtime.usable && !runtime.shouldUseLinux) ...[
            const SizedBox(height: Space.x3),
            InfoBanner(runtime.lastLaunchError ?? '连续启动失败', tone: BannerTone.danger),
            const SizedBox(height: Space.x3),
            FilledButton(key: const Key('runtime-retry-launch'), onPressed: ctl.resetLaunchFailures, child: const Text('重新尝试进入 Ubuntu')),
          ],
          if (runtime.busy) ...[
            const SizedBox(height: Space.x4),
            ClipRRect(
              borderRadius: BorderRadius.circular(Radii.sm),
              child: LinearProgressIndicator(minHeight: 6, value: runtime.progressTotal > 0 ? runtime.progressDone / runtime.progressTotal : null),
            ),
            const SizedBox(height: Space.x2),
            Text(
              runtime.phase == RuntimePhase.downloading
                  ? '已下载 ${formatBytes(runtime.progressDone)} / ${formatBytes(runtime.progressTotal)}'
                  : runtime.phase == RuntimePhase.verifying
                  ? '下载完成，正在核对文件'
                  : '解压中，不要退出应用',
              key: const Key('runtime-progress'),
              style: t.bodySmall,
            ),
            const SizedBox(height: Space.x3),
            OutlinedButton(key: const Key('runtime-cancel'), onPressed: ctl.cancelInstall, child: const Text('取消（下到一半的会留着）')),
          ],
          if (runtime.phase == RuntimePhase.notInstalled && runtime.prootBundled) ...[
            const SizedBox(height: Space.x3),
            Text(_spaceNote(runtime), key: const Key('runtime-space'), style: t.bodySmall?.copyWith(height: 1.5)),
            const SizedBox(height: Space.x4),
            FilledButton(key: const Key('runtime-install'), onPressed: ctl.install, child: Text(runtime.partialBytes > 0 ? '继续下载（已有 ${formatBytes(runtime.partialBytes)}）' : '安装运行环境')),
          ],
        ],
      ),
    );
  }

  static String _spaceNote(RuntimeView runtime) {
    final free = runtime.freeSpace;
    final need =
        '需要下载 ${formatBytes(runtime.imageSize)}，解压后占约 ${formatBytes(RootfsImage.extractedBytes)}，'
        '建议留出 ${formatBytes(RootfsImage.requiredBytes)}。Node.js、Python 另算。';
    return free == null ? need : '$need\n手机现在剩余 ${formatBytes(free)}。';
  }
}

class _MirrorRow extends StatelessWidget {
  const _MirrorRow({required this.keyName, required this.label, required this.options, required this.value, required this.enabled, required this.onChanged});
  final String keyName;
  final String label;
  final List<MirrorOption> options;
  final String value;
  final bool enabled;
  final Future<void> Function(String id) onChanged;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x2, 0),
      child: Row(
        children: [
          Expanded(child: Text(label, style: t.bodyMedium)),
          DropdownButton<String>(
            key: Key(keyName),
            value: value,
            underline: const SizedBox.shrink(),
            borderRadius: BorderRadius.circular(Radii.md),
            padding: const EdgeInsets.symmetric(horizontal: Space.x2),
            style: t.bodyMedium,
            onChanged: enabled ? (id) => id == null ? null : onChanged(id) : null,
            items: [for (final o in options) DropdownMenuItem(value: o.id, child: Text(o.label))],
          ),
        ],
      ),
    );
  }
}

class _PackRow extends StatelessWidget {
  const _PackRow({required this.runtime, required this.ctl, required this.pack});
  final RuntimeView runtime;
  final RuntimeNotifier ctl;
  final RuntimePack pack;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final installed = runtime.packInstalled(pack);
    final running = runtime.runningPack == pack.id;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.x4, Space.x2, Space.x4, Space.x2),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(pack.title, style: t.bodyLarge),
                const SizedBox(height: 2),
                Text(pack.subtitle, style: t.bodySmall),
              ],
            ),
          ),
          const SizedBox(width: Space.x3),
          if (running)
            OutlinedButton(onPressed: ctl.cancelPack, child: const Text('停止'))
          else if (installed)
            Text(
              '已安装',
              key: Key('pack-${pack.id}-installed'),
              style: t.bodySmall?.copyWith(color: c.accent),
            )
          else
            OutlinedButton(key: Key('pack-${pack.id}-install'), onPressed: runtime.runningPack == null && runtime.shouldUseLinux ? () => ctl.installPack(pack) : null, child: const Text('安装')),
        ],
      ),
    );
  }
}

/// 一键诊断：一句说明、一个按钮；跑完显示结论和完整报告，可整段复制。
class _DiagnosticsPanel extends ConsumerWidget {
  const _DiagnosticsPanel({required this.runtimeBusy, required this.projectDir});

  /// 运行环境正在下载 / 解压：这时不让开始诊断。
  final bool runtimeBusy;
  final String? projectDir;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final diag = ref.watch(runtimeDiagnosticsProvider);
    final t = Theme.of(context).textTheme;
    return Builder(
      builder: (context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('终端进不去或没反应时点这里。会自动跑一遍检查（大约一两分钟），不会改动你的项目。', style: t.bodySmall),
          const SizedBox(height: Space.x3),
          FilledButton.tonal(
            key: const Key('runtime-diagnose'),
            onPressed: diag.running || runtimeBusy ? null : () => ref.read(runtimeDiagnosticsProvider.notifier).run(projectDir: projectDir),
            child: Text(diag.running ? '正在检查…' : (diag.hasReport ? '重新诊断' : '开始诊断')),
          ),
          if (diag.running) ...[
            const SizedBox(height: Space.x3),
            const LinearProgressIndicator(),
            const SizedBox(height: Space.x2),
            Text('第 ${diag.stepCount} 项：${diag.progress}', key: const Key('diag-progress'), style: t.bodySmall),
          ],
          if (diag.hasReport) ...[
            const SizedBox(height: Space.x3),
            for (final line in diag.conclusions)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.x1),
                child: Text('· $line', style: t.bodyMedium),
              ),
            const SizedBox(height: Space.x2),
            _LogBox(lines: diag.report.split('\n'), keyName: 'diag-report', fromTop: true, maxLines: 400, maxHeight: 360),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: const Key('diag-copy'),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: diag.report));
                  if (context.mounted) showSnack(context, '诊断结果已复制，可以直接粘贴发出去');
                },
                child: const Text('复制诊断结果'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _LogBox extends StatelessWidget {
  const _LogBox({required this.lines, required this.keyName, this.copyable = false, this.fromTop = false, this.maxLines = 60, this.maxHeight = 220});
  final List<String> lines;
  final String keyName;
  final bool copyable;

  /// 日志从最新（底部）看起；诊断报告从头看起。
  final bool fromTop;
  final int maxLines;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final shown = lines.length > maxLines ? lines.sublist(lines.length - maxLines) : lines;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          key: Key(keyName),
          constraints: BoxConstraints(maxHeight: maxHeight),
          padding: const EdgeInsets.all(Space.x3),
          decoration: BoxDecoration(color: c.codeBg, borderRadius: BorderRadius.circular(Radii.md)),
          child: SingleChildScrollView(
            reverse: !fromTop,
            child: SelectableText(
              shown.join('\n'),
              // 等宽字体里没有中文时，退回界面的默认字体。
              style: TextStyle(fontFamily: 'monospace', fontFamilyFallback: [?Theme.of(context).textTheme.bodySmall?.fontFamily], fontSize: FontSize.xs, height: 1.5, color: c.text),
            ),
          ),
        ),
        if (copyable)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: lines.join('\n')));
                if (context.mounted) showSnack(context, '日志已复制');
              },
              child: const Text('复制日志'),
            ),
          ),
      ],
    );
  }
}
