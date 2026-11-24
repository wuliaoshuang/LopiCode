// 设计约束（终端页 · 后端“运行”的准备条 · 390×844，浅色 + 深色）— 2026-11-25
// - 只在点了后端“运行”、而且有事要她知道的时候出现，贴在会话行下面、终端上面；没事的时候不占地方。
//   安装的输出本身在下面的终端里一行行出来，这条只说“现在在干什么”和给一个出路。
// - 一种状态一件事，从上到下：一行标题 → 一句说明（有才写）→ 一个主操作，次要出路在它右边。
//   · 核对中 / 等别的装完：标题 + “取消”。
//   · 正在装：标题 + 细进度条（不知道百分比，只表示“在动”）+ “取消”。
//   · 要先问一次（下载量过了门槛）：标题“要先装 …”+ 多大、装在哪 + 主按钮“安装并启动”，旁边“先不装”。
//   · 没装成：标题 + 真正的原因 + 主按钮“重试”，旁边“知道了”。
//   · 在等 Ubuntu 环境（这时开着的只会是 SSH 会话，安装引导不在眼前）：标题 + 一句说明 + “取消”。
// - 颜色只表达性质：平常是 surface，没装成用 dangerSoft，要她点头用 accentSoft。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/state/backend_run.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// 安装引导页顶上那句“装好后会接着启动后端”；没有在等就是 null。
String? backendRunSetupNotice(BackendRunState run) => run.phase == BackendRunPhase.waitingRuntime ? '装好后会接着准备好工具并启动后端，不用再回去点“运行”。' : null;

class BackendRunBar extends ConsumerWidget {
  const BackendRunBar({super.key, required this.session});
  final ProjectSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final run = ref.watch(backendRunProvider(session));
    if (run.phase == BackendRunPhase.idle) return const SizedBox.shrink();
    final ctl = ref.read(backendRunProvider(session).notifier);
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final name = run.packTitle ?? '工具';
    final (String title, String? body, Color bg, Color fg) = switch (run.phase) {
      BackendRunPhase.waitingRuntime => ('正在安装 Ubuntu 运行环境', '进度在侧边栏“运行环境”页。装好后接着启动后端。', c.surface, c.text),
      BackendRunPhase.checking => ('正在检查 $name 装没装…', null, c.surface, c.text),
      BackendRunPhase.installing => ('正在安装 $name', '进度看下面的终端。装好后自动启动后端。', c.surface, c.text),
      BackendRunPhase.confirming => ('要先装 $name', '${run.sizeNote == null ? '' : '${run.sizeNote}，'}装在 Ubuntu 环境里。建议连着 Wi-Fi 装；装好后自动启动后端。', c.accentSoft, c.text),
      BackendRunPhase.failed => ('$name 没装成，后端没有启动', run.error, c.dangerSoft, c.danger),
      BackendRunPhase.idle => ('', null, c.surface, c.text),
    };
    final busy = run.phase == BackendRunPhase.installing || run.phase == BackendRunPhase.checking || run.phase == BackendRunPhase.waitingRuntime;
    return Container(
      key: const Key('backend-run-bar'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(Space.x4, Space.x3, Space.x4, Space.x2),
      decoration: BoxDecoration(
        color: bg,
        border: Border(
          top: BorderSide(color: c.border),
          bottom: BorderSide(color: c.border),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            key: const Key('backend-run-title'),
            style: t.titleSmall?.copyWith(color: fg),
          ),
          if (body != null && body.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(body, key: const Key('backend-run-body'), maxLines: 6, overflow: TextOverflow.ellipsis, style: t.bodySmall?.copyWith(height: 1.5)),
          ],
          if (run.phase == BackendRunPhase.installing) ...[
            const SizedBox(height: Space.x2),
            ClipRRect(
              borderRadius: BorderRadius.circular(Radii.sm),
              child: const LinearProgressIndicator(key: Key('backend-run-progress'), minHeight: 4),
            ),
          ],
          const SizedBox(height: Space.x1),
          Row(
            children: [
              if (busy) TextButton(key: const Key('backend-run-cancel'), onPressed: ctl.cancel, child: const Text('取消')),
              if (run.phase == BackendRunPhase.confirming) ...[
                FilledButton(key: const Key('backend-run-confirm'), onPressed: ctl.confirmInstall, child: const Text('安装并启动')),
                const SizedBox(width: Space.x2),
                TextButton(key: const Key('backend-run-decline'), onPressed: ctl.cancel, child: const Text('先不装')),
              ],
              if (run.phase == BackendRunPhase.failed) ...[
                FilledButton(key: const Key('backend-run-retry'), onPressed: ctl.retry, child: const Text('重试')),
                const SizedBox(width: Space.x2),
                TextButton(key: const Key('backend-run-dismiss'), onPressed: ctl.dismiss, child: const Text('知道了')),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
