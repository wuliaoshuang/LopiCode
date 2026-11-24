// 设计约束（终端 · 没有终端可用时的两个页面 · 390×844）
//
// 安卓上不再用手机自带的命令行（没有 git、node、python，跑不了项目），所以终端页有两种“进不去”的时候：
//
// 一、运行环境还没装（[TerminalSetupView]）——整页就是一件事：把它装上。从上到下一行一件事：
//   1. 标题：先装运行环境。
//   2. 一句人话：为什么要装。
//   3. 要下载多大、占多大（数字和“运行环境”页同一个来源，不另写）。
//   4. 上次失败的原因（有才显示，原话照登）。
//   5. 主按钮“安装运行环境”（下到一半的写“继续下载（已有 …）”）；安装中换成进度条 + 一行进度 + “取消”。
//      全程在本页完成，不跳走；装好后终端列表自己开一个 Ubuntu 会话，本页自然消失。
//   6. 次要出路（文字按钮，各占一行）：连 SSH 远程主机；失败过才多一个“换个下载源”（去“运行环境”页）。
//
// 二、装了但 Ubuntu 没起来（[TerminalFailureView]）——不退回本机命令行，给原因和出路：
//   1. 标题 + 真实的失败原因（原话）。
//   2. 主按钮“重试”。
//   3. “用兼容模式重试”（已经定下用兼容模式时不出现：那时“重试”就是它）。
//   4. 一行两个次要出路：“一键诊断”“连接 SSH”。
//   5. 诊断在本页跑：进度一行；跑完列出结论，完整报告去“运行环境”页看。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lopicode/runtime/linux_runtime.dart';
import 'package:lopicode/runtime/linux_shell_backend.dart';
import 'package:lopicode/state/runtime_state.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/shell.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';

/// 终端页的安装引导：运行环境没装好（或这个安装包进不去）时，占满终端页。
class TerminalSetupView extends ConsumerWidget {
  const TerminalSetupView({super.key, required this.onConnectSsh});

  /// 点“连接 SSH 远程主机”。
  final VoidCallback onConnectSsh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final runtime = ref.watch(runtimeProvider);
    final ctl = ref.read(runtimeProvider.notifier);
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final canInstall = runtime.prootBundled && runtime.phase == RuntimePhase.notInstalled;
    return _Page(
      keyName: 'terminal-setup',
      children: [
        Icon(Icons.terminal, size: 40, color: c.accent),
        const SizedBox(height: Space.x4),
        Text(runtime.busy ? '正在安装运行环境' : '先装运行环境，终端才能用', style: t.titleLarge),
        const SizedBox(height: Space.x2),
        Text('手机自带的命令行没有 git、node、python，跑不了项目。装一个 Ubuntu 环境，终端和 Agent 执行命令都在它里面。', style: t.bodyMedium?.copyWith(color: c.textMuted, height: 1.5)),
        if (!runtime.prootBundled) ...[
          const SizedBox(height: Space.x4),
          InfoBanner(
            '这个安装包里缺少进入 Ubuntu 要用的文件（${runtime.missingLauncherFiles.join('、')}），装了也进不去，所以这里先不提供安装。请重新安装完整的 LopiCode 安装包。',
            key: const Key('terminal-setup-no-proot'),
            tone: BannerTone.warning,
          ),
        ],
        if (canInstall) ...[const SizedBox(height: Space.x3), Text(runtimeSpaceNote(runtime), key: const Key('terminal-setup-space'), style: t.bodySmall?.copyWith(height: 1.5))],
        if (runtime.installError != null) ...[const SizedBox(height: Space.x4), InfoBanner(runtime.installError!, key: const Key('terminal-setup-error'), tone: BannerTone.danger)],
        if (runtime.busy) ...[
          const SizedBox(height: Space.x6),
          ClipRRect(
            borderRadius: BorderRadius.circular(Radii.sm),
            child: LinearProgressIndicator(minHeight: 6, value: runtime.progressTotal > 0 ? runtime.progressDone / runtime.progressTotal : null),
          ),
          const SizedBox(height: Space.x2),
          Text(
            switch (runtime.phase) {
              RuntimePhase.downloading => '已下载 ${formatBytes(runtime.progressDone)} / ${formatBytes(runtime.progressTotal)}',
              RuntimePhase.verifying => '下载完成，正在核对文件',
              _ => '解压中，不要退出应用。装好后会直接进终端',
            },
            key: const Key('terminal-setup-progress'),
            style: t.bodySmall,
          ),
          const SizedBox(height: Space.x4),
          OutlinedButton(key: const Key('terminal-setup-cancel'), onPressed: ctl.cancelInstall, child: const Text('取消（下到一半的会留着）')),
        ],
        if (canInstall) ...[
          const SizedBox(height: Space.x6),
          FilledButton(key: const Key('terminal-setup-install'), onPressed: ctl.install, child: Text(runtime.partialBytes > 0 ? '继续下载（已有 ${formatBytes(runtime.partialBytes)}）' : '安装运行环境')),
        ],
        const SizedBox(height: Space.x2),
        TextButton(key: const Key('terminal-setup-ssh'), onPressed: onConnectSsh, child: const Text('改连 SSH 远程主机')),
        if (canInstall && runtime.installError != null)
          TextButton(key: const Key('terminal-setup-sources'), onPressed: () => ShellScope.maybeOf(context)?.go(ShellDest.runtime), child: const Text('换个下载源再试')),
      ],
    );
  }
}

/// Ubuntu 没能启动时占满终端区的页面：原因 + 出路，不退回本机命令行。
class TerminalFailureView extends ConsumerWidget {
  const TerminalFailureView({super.key, required this.backend, required this.reason, required this.onConnectSsh, this.projectDir});

  final LinuxShellBackend backend;

  /// 启动失败的真实原因。
  final String reason;
  final VoidCallback onConnectSsh;

  /// 诊断时顺便检查这个项目目录在 Ubuntu 里看不看得见。
  final String? projectDir;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final runtime = ref.watch(runtimeProvider);
    final diag = ref.watch(runtimeDiagnosticsProvider);
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final canDiagnose = runtime.installed && !runtime.busy && !diag.running;
    return _Page(
      keyName: 'terminal-failure',
      children: [
        Icon(Icons.error_outline, size: 40, color: c.danger),
        const SizedBox(height: Space.x4),
        Text('Ubuntu 没能启动', style: t.titleLarge),
        const SizedBox(height: Space.x3),
        InfoBanner(reason, key: const Key('terminal-failure-reason'), tone: BannerTone.danger),
        const SizedBox(height: Space.x3),
        Text(runtime.compatPinned ? '现在用的已经是兼容模式。还进不去就做一次诊断，或者先连 SSH 远程主机。' : '可以再试一次；还不行就换兼容模式（慢一点，但更多手机能进）。', style: t.bodySmall?.copyWith(height: 1.5)),
        const SizedBox(height: Space.x4),
        FilledButton(key: const Key('terminal-failure-retry'), onPressed: runtime.usable ? backend.retry : null, child: const Text('重试')),
        if (!runtime.compatPinned) ...[
          const SizedBox(height: Space.x2),
          OutlinedButton(key: const Key('terminal-failure-compat'), onPressed: runtime.usable ? backend.retryCompat : null, child: const Text('用兼容模式重试')),
        ],
        const SizedBox(height: Space.x1),
        Row(
          children: [
            Expanded(
              child: TextButton(
                key: const Key('terminal-failure-diagnose'),
                onPressed: canDiagnose ? () => ref.read(runtimeDiagnosticsProvider.notifier).run(projectDir: projectDir) : null,
                child: Text(diag.running ? '正在诊断…' : (diag.hasReport ? '重新诊断' : '一键诊断')),
              ),
            ),
            Expanded(
              child: TextButton(key: const Key('terminal-failure-ssh'), onPressed: onConnectSsh, child: const Text('连接 SSH')),
            ),
          ],
        ),
        if (diag.running) ...[
          const SizedBox(height: Space.x2),
          const LinearProgressIndicator(),
          const SizedBox(height: Space.x2),
          Text('第 ${diag.stepCount} 项：${diag.progress}（大约一两分钟，不会改动你的项目）', key: const Key('terminal-failure-diag-progress'), style: t.bodySmall),
        ] else if (diag.hasReport) ...[
          const SizedBox(height: Space.x3),
          Text('诊断结论', style: t.titleSmall),
          const SizedBox(height: Space.x1),
          for (final line in diag.conclusions)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.x1),
              child: Text('· $line', style: t.bodySmall?.copyWith(height: 1.5)),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(key: const Key('terminal-failure-report'), onPressed: () => ShellScope.maybeOf(context)?.go(ShellDest.runtime), child: const Text('看完整报告和日志')),
          ),
        ],
      ],
    );
  }
}

/// 两个页面共用的版式：内容靠上居中一栏，窄屏整页可滚（键盘、小屏都不溢出）。
class _Page extends StatelessWidget {
  const _Page({required this.keyName, required this.children});
  final String keyName;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      key: Key(keyName),
      color: context.colors.bg,
      child: SizedBox.expand(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(Space.x6, Space.x8, Space.x6, Space.x6),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
            ),
          ),
        ),
      ),
    );
  }
}
