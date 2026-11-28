// 设计约束（“运行环境”页 · 390×844 · 浅色 + 深色）— 2026-11-25 霜霜真机批注“好丑啊”后整页重排
// 和设置页同一套视觉语言：浅灰底（canvas）+ 白色圆角分组卡片，组和行直接用 lib/ui/settings_widgets.dart，不另造。
// 层级（先定的这个，再定排版，最后才是颜色）：
// - 第一：状态卡——Ubuntu 现在怎样（未安装 / 下载·校验·解压中 / 上次没装成 / 已安装 / 进不去）。整页唯一的实心主按钮只在这张卡里，
//   而且一次只有一个：安装（或继续下载 / 重新安装）、取消、重新尝试进入。已安装且一切正常时没有主按钮，只摆事实（占用空间、项目目录）。
// - 第二：语言与工具——一行一样（图标 + 名称 + 一句说明 + 右边状态）。右边只会是：对勾（版本号写在说明那一行：“已安装 · 24.9.0”）、或一个 64×32 的描边小按钮（安装 / 重试 / 停止）。
//   这一组是数据驱动的（遍历快照里的 packs），新增语言不用动布局。没装环境时整组不出现。
// - 第三：下载源（两行跳转行，值在右，点开底部面板单选）、诊断（一行强调色的入口，不是大按钮；进度和报告展开在同一张卡里）、日志。
// - 最后：卸载，一行红字的危险行，点了先确认。
// - 例外的顺序：Ubuntu 连续启动失败时，“诊断”提到状态卡正下面（这时它是最该点的），其余顺序不变。
// 排版（全部取自 lib/theme/tokens.dart 和 SettingsMetrics，不写表外的数）：
// - 页边 16；组与组 24；组标题到卡片 8；卡片内边 16；行高至少 56、行内左右 16 上下 12。
// - 字：卡片标题 16/600；行名 16/400；说明 12 弱色；右侧值 14 弱色；组标题 12/600 弱色。
// - 语言图标 24（material-icon-theme，原色不着色），和设置行的图标格同宽，名称起点对齐。
// 颜色：强调蓝只给主按钮、对勾、进度条和“开始诊断”；红色只给失败原因和卸载；其余全是正文色 / 弱色。
// 一行只做一件事；功能对照清单见 test/runtime_redesign_test.dart 开头。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lopicode/backdrop/backdrop_model.dart';
import 'package:lopicode/runtime/runtime_packs_view.dart';
import 'package:lopicode/runtime/runtime_screen_widgets.dart';
import 'package:lopicode/runtime/runtime_sources.dart';
import 'package:lopicode/runtime/runtime_status_view.dart';
import 'package:lopicode/state/runtime_state.dart';
import 'package:lopicode/theme/breakpoints.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/app_backdrop.dart';
import 'package:lopicode/ui/settings_widgets.dart';
import 'package:lopicode/ui/shell.dart';
import 'package:lopicode/ui/top_bar.dart';
import 'package:material_ui/material_ui.dart';

/// “运行环境”页：安装 / 卸载 Ubuntu 环境、一键装语言和工具、选下载源、一键诊断、看日志。
class RuntimeScreen extends ConsumerWidget {
  const RuntimeScreen({super.key, this.projectDir});

  /// 当前打开的项目目录；诊断时顺便检查它在 Ubuntu 里看不看得见。
  final String? projectDir;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final runtime = ref.watch(runtimeProvider);
    final ctl = ref.read(runtimeProvider.notifier);
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    // 连续启动失败：诊断是这时候最该点的，提到状态卡正下面
    final launchFailing = runtime.installed && runtime.usable && !runtime.shouldUseLinux;
    final diagnostics = RuntimeDiagnosticsGroup(runtimeBusy: runtime.busy, projectDir: projectDir);
    final removable = !runtime.busy && runtime.runningPack == null;
    return AppBackdrop(
      area: BackdropArea.pages,
      builder: (context, on) => Scaffold(
        backgroundColor: on ? Colors.transparent : c.canvas,
        extendBodyBehindAppBar: true,
        appBar: ShellAppBar(title: '运行环境', background: c.canvas),
        body: ContentWidth(
          child: Builder(
            // 不用懒加载的列表：这一页不长，一次排完，滚到哪儿都不会把诊断报告、日志的滚动位置丢掉
            builder: (context) => SingleChildScrollView(
              key: const Key('runtime-page'),
              padding: EdgeInsets.fromLTRB(Space.x4, PageBar.insetOf(context) + Space.x2, Space.x4, Space.x12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: SettingsMetrics.groupGap),
                    child: RuntimeStatusCard(runtime: runtime, ctl: ctl),
                  ),
                  if (launchFailing) diagnostics,
                  if (runtime.installed) RuntimePacksGroup(runtime: runtime, ctl: ctl),
                  SettingsGroup(
                    title: '下载源',
                    children: [
                      _mirrorRow(
                        context,
                        keyName: 'rootfs-source',
                        label: '系统包',
                        note: '下载 Ubuntu 本体从哪儿下',
                        options: rootfsSources,
                        value: runtime.rootfsSourceId,
                        enabled: !runtime.busy,
                        onChanged: ctl.setRootfsSource,
                      ),
                      _mirrorRow(
                        context,
                        keyName: 'apt-mirror',
                        label: '装软件（apt）',
                        note: '在 Ubuntu 里装软件从哪儿下',
                        options: aptMirrors,
                        value: runtime.aptMirrorId,
                        enabled: !runtime.busy,
                        onChanged: ctl.setAptMirror,
                      ),
                    ],
                  ),
                  if (runtime.installed && !launchFailing) diagnostics,
                  SettingsGroup(
                    title: '日志',
                    padded: true,
                    children: [
                      if (runtime.logLines.isEmpty)
                        Text('还没有记录。安装和每次启动失败的原因会记在这里。', style: t.bodySmall?.copyWith(color: c.textFaint, height: 1.5))
                      else
                        RuntimeLogBox(lines: runtime.logLines, keyName: 'runtime-log', copyLabel: '复制日志', copiedHint: '日志已复制', copyKey: const Key('runtime-log-copy')),
                    ],
                  ),
                  if (runtime.installed || runtime.partialBytes > 0)
                    SettingsGroup(
                      children: [
                        SettingsRow(
                          key: const Key('runtime-uninstall'),
                          title: runtime.installed ? '卸载运行环境' : '删除没下完的文件',
                          subtitle: '删掉整个 Ubuntu 环境和里面装的所有软件。项目文件不受影响。',
                          danger: removable,
                          enabled: removable,
                          // 不能点的时候不画箭头
                          trailing: removable ? null : const SizedBox.shrink(),
                          onTap: () => _confirmUninstall(context, ctl),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 下载源的一行：名称 + 一句说明，当前值在右，点开底部面板单选。
  Widget _mirrorRow(
    BuildContext context, {
    required String keyName,
    required String label,
    required String note,
    required List<MirrorOption> options,
    required String value,
    required bool enabled,
    required Future<void> Function(String id) onChanged,
  }) => SettingsRow(
    key: Key(keyName),
    title: label,
    subtitle: note,
    value: mirrorById(options, value).label,
    valueKey: Key('$keyName-value'),
    enabled: enabled,
    onTap: () async {
      final picked = await showMirrorSheet(context, title: label, note: note, options: options, current: value);
      if (picked != null && picked != value) await onChanged(picked);
    },
  );

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
