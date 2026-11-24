// “运行环境”页的小零件：统一尺寸的小按钮、日志框、下载源选择面板、诊断一组（设计约束见 runtime_screen.dart 开头）。
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lopicode/runtime/runtime_sources.dart';
import 'package:lopicode/state/runtime_state.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/settings_widgets.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';

/// 行尾的小按钮：全页一个尺寸（至少 64×32），描边、不抢主操作的风头。
class RuntimeSmallButton extends StatelessWidget {
  const RuntimeSmallButton({super.key, required this.label, required this.onPressed});
  final String label;
  final VoidCallback? onPressed;

  static const Size size = Size(64, 32);

  @override
  Widget build(BuildContext context) => OutlinedButton(
    style: OutlinedButton.styleFrom(
      minimumSize: size,
      fixedSize: const Size.fromHeight(32),
      padding: const EdgeInsets.symmetric(horizontal: Space.x3),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.standard,
      textStyle: Theme.of(context).textTheme.labelLarge,
    ),
    onPressed: onPressed,
    child: Text(label),
  );
}

/// 一块等宽字的输出（日志、安装输出、诊断报告）；可选上面一行小标题、下面一个“复制”。
class RuntimeLogBox extends StatelessWidget {
  const RuntimeLogBox({
    super.key,
    required this.lines,
    required this.keyName,
    this.title,
    this.copyLabel,
    this.copiedHint,
    this.copyKey,
    this.fromTop = false,
    this.maxLines = 60,
    this.maxHeight = 220,
  });
  final List<String> lines;
  final String keyName;
  final String? title;

  /// 给了就在下面放一个“复制”文字按钮。
  final String? copyLabel;
  final String? copiedHint;
  final Key? copyKey;

  /// 日志从最新（底部）看起；诊断报告从头看起。
  final bool fromTop;
  final int maxLines;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final shown = lines.length > maxLines ? lines.sublist(lines.length - maxLines) : lines;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.x2),
            child: Text(title!, style: t.labelMedium?.copyWith(color: c.textFaint)),
          ),
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
              style: TextStyle(fontFamily: 'monospace', fontFamilyFallback: [?t.bodySmall?.fontFamily], fontSize: FontSize.xs, height: 1.5, color: c.text),
            ),
          ),
        ),
        if (copyLabel != null)
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(top: Space.x1),
              child: TextButton(
                key: copyKey,
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 36),
                  padding: const EdgeInsets.symmetric(horizontal: Space.x3),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: lines.join('\n')));
                  if (context.mounted) showSnack(context, copiedHint ?? '已复制');
                },
                child: Text(copyLabel!),
              ),
            ),
          ),
      ],
    );
  }
}

/// 选下载源的底部面板：几行单选，点了就选中并收起。返回选中的 id，没选返回 null。
Future<String?> showMirrorSheet(BuildContext context, {required String title, required String note, required List<MirrorOption> options, required String current}) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  builder: (context) {
    final t = Theme.of(context).textTheme;
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: t.titleLarge),
                const SizedBox(height: 2),
                Text(note, style: t.bodySmall),
              ],
            ),
          ),
          for (final o in options)
            SettingsChoiceRow(key: Key('mirror-option-${o.id}'), title: o.label, subtitle: Uri.tryParse(o.base)?.host, selected: o.id == current, onTap: () => Navigator.pop(context, o.id)),
          const SizedBox(height: Space.x2),
        ],
      ),
    );
  },
);

/// “诊断”一组：一行入口（次要操作）；跑的时候下面出进度，跑完出结论和完整报告，可整段复制。
class RuntimeDiagnosticsGroup extends ConsumerWidget {
  const RuntimeDiagnosticsGroup({super.key, required this.runtimeBusy, required this.projectDir});

  /// 运行环境正在下载 / 解压：这时不让开始诊断。
  final bool runtimeBusy;
  final String? projectDir;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final diag = ref.watch(runtimeDiagnosticsProvider);
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final enabled = !diag.running && !runtimeBusy;
    return SettingsGroup(
      title: '诊断',
      children: [
        SettingsRow(
          key: const Key('runtime-diagnose'),
          title: diag.running ? '正在检查…' : (diag.hasReport ? '重新诊断' : '开始诊断'),
          subtitle: '终端进不去或没反应时点这里。会自动跑一遍检查（大约一两分钟），不会改动你的项目。',
          accent: enabled,
          enabled: enabled,
          // 不能点的时候不画箭头
          trailing: enabled ? null : const SizedBox.shrink(),
          onTap: () => ref.read(runtimeDiagnosticsProvider.notifier).run(projectDir: projectDir),
        ),
        if (diag.running)
          Padding(
            padding: const EdgeInsets.all(Space.x4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(borderRadius: BorderRadius.circular(Radii.sm), child: const LinearProgressIndicator(minHeight: 4)),
                const SizedBox(height: Space.x2),
                Text('第 ${diag.stepCount} 项：${diag.progress}', key: const Key('diag-progress'), style: t.bodySmall),
              ],
            ),
          ),
        if (diag.hasReport)
          Padding(
            padding: const EdgeInsets.all(Space.x4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('结论', style: t.labelMedium?.copyWith(color: c.textFaint)),
                const SizedBox(height: Space.x2),
                for (final line in diag.conclusions)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Space.x1),
                    child: Text('· $line', style: t.bodyMedium),
                  ),
                const SizedBox(height: Space.x3),
                RuntimeLogBox(
                  lines: diag.report.split('\n'),
                  keyName: 'diag-report',
                  title: '完整报告',
                  copyLabel: '复制诊断结果',
                  copiedHint: '诊断结果已复制，可以直接粘贴发出去',
                  copyKey: const Key('diag-copy'),
                  fromTop: true,
                  maxLines: 400,
                  maxHeight: 360,
                ),
              ],
            ),
          ),
      ],
    );
  }
}
