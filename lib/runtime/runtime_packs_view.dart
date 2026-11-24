// “运行环境”页的“语言与工具”一组（设计约束见 runtime_screen.dart 开头）。
// 列表是数据驱动的：快照里有几项就画几行，新增语言不用改这里的布局。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lopicode/runtime/runtime_pack_info.dart';
import 'package:lopicode/runtime/runtime_screen_widgets.dart';
import 'package:lopicode/runtime/runtime_snapshot.dart';
import 'package:lopicode/runtime/runtime_sources.dart';
import 'package:lopicode/state/runtime_extras.dart';
import 'package:lopicode/state/runtime_state.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/file_icon.dart';
import 'package:lopicode/ui/settings_widgets.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';

class RuntimePacksGroup extends ConsumerWidget {
  const RuntimePacksGroup({super.key, required this.runtime, required this.ctl});
  final RuntimeView runtime;
  final RuntimeNotifier ctl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!runtime.usable) {
      return const SettingsGroup(
        title: '语言与工具',
        padded: true,
        children: [InfoBanner('环境进不去的时候装不了运行时。', tone: BannerTone.warning)],
      );
    }
    final versions = ref.watch(runtimePackVersionsProvider).value ?? const <String, String>{};
    final failed = lastFailedPack(packs: runtime.packs, installed: runtime.installedPacks, runningPack: runtime.runningPack, output: runtime.packOutput);
    Widget tile(RuntimePack pack) => _PackTile(runtime: runtime, ctl: ctl, pack: pack, version: versions[pack.id], failed: failed?.packId == pack.id ? failed : null);
    return SettingsGroup(
      title: '语言与工具',
      iconRows: true,
      children: [
        for (final (i, pack) in runtime.packs.indexed)
          if (i == runtime.packs.length - 1 && runtime.packOutput.isNotEmpty)
            // 输出跟在最后一行后面，中间的线画满（它不是又一行语言）
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                tile(pack),
                Divider(height: 1, thickness: 1, indent: Space.x4, endIndent: Space.x4, color: context.colors.border),
                Padding(
                  padding: const EdgeInsets.all(Space.x4),
                  child: RuntimeLogBox(lines: runtime.packOutput, keyName: 'pack-output', title: '安装输出'),
                ),
              ],
            )
          else
            tile(pack),
      ],
    );
  }
}

/// 一行：语言图标 + 名称 / 一句说明（已装是“已安装 · 版本”，安装中是最新一行输出，失败是原因）+ 右边的对勾或一个小按钮。
class _PackTile extends StatelessWidget {
  const _PackTile({required this.runtime, required this.ctl, required this.pack, required this.version, required this.failed});
  final RuntimeView runtime;
  final RuntimeNotifier ctl;
  final RuntimePack pack;
  final String? version;
  final PackAttempt? failed;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final installed = runtime.packInstalled(pack);
    final running = runtime.runningPack == pack.id;
    final canInstall = !installed && runtime.runningPack == null && runtime.shouldUseLinux;
    final hardFail = failed != null && !failed!.stopped;
    final subtitle = running
        ? (runtime.packOutput.isEmpty ? '正在安装…' : runtime.packOutput.last.trim())
        : installed
        ? (version == null ? '已安装' : '已安装 · $version')
        : failed != null
        ? failed!.reason
        : pack.subtitle;
    void install() => ctl.installPack(pack);
    return InkWell(
      // 整行都能点（只在“安装 / 重试”时）：右边的小按钮只有 32 高，手指不用瞄那么准
      onTap: canInstall ? install : null,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: SettingsMetrics.rowMinHeight),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.x4, vertical: Space.x3),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  SizedBox(
                    width: SettingsMetrics.iconSlot,
                    child: Center(child: FileIcon.language(packIconId(pack.id), size: SettingsMetrics.iconSlot)),
                  ),
                  const SizedBox(width: Space.x3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(pack.title, style: t.bodyLarge?.copyWith(height: 1.3), maxLines: 1, overflow: TextOverflow.ellipsis),
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            subtitle,
                            key: Key('pack-${pack.id}-note'),
                            style: t.bodySmall?.copyWith(color: hardFail ? c.danger : c.textFaint),
                            maxLines: running ? 1 : 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: Space.x3),
                  if (running)
                    RuntimeSmallButton(key: Key('pack-${pack.id}-stop'), label: '停止', onPressed: ctl.cancelPack)
                  else if (installed)
                    Semantics(
                      key: Key('pack-${pack.id}-installed'),
                      label: '已安装',
                      child: Icon(Icons.check_circle, size: 20, color: c.accent),
                    )
                  else
                    RuntimeSmallButton(key: Key('pack-${pack.id}-install'), label: failed != null ? '重试' : '安装', onPressed: canInstall ? install : null),
                ],
              ),
              if (running)
                Padding(
                  // 脚本不报百分比，所以是来回走的进度条 + 上面那行最新输出
                  padding: const EdgeInsets.only(left: SettingsMetrics.iconSlot + Space.x3, top: Space.x2),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(Radii.sm),
                    child: LinearProgressIndicator(key: Key('pack-${pack.id}-progress'), minHeight: 4),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
