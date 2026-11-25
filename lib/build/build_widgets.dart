// 设计约束（打包页三种方式共用的小控件 · 390×844）
// 层级：标签小而弱（12 / 600 / 弱色），输入的内容是正文（16）；说明和报错最小（12），报错用危险色并带图标（不只靠颜色）。
// 排版：全部取自 lib/theme/tokens.dart。输入项＝标签 → 8 → 输入框 → 4 → 说明或报错；一行一项，不并排。
// 颜色：强调色只给“选中的方式”和主按钮；路径、网址这类要原样看的字用等宽，字号跟着“代码字号”（小一号）走。

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lopicode/state/code_font.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/top_bar.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';

/// 把 [target] 滚到悬浮顶栏的下沿下面一点（进度卡、出错的输入框）。
/// 不能用固定比例：顶栏是悬浮的，内容从它下面穿过，滚得不够低就正好被顶栏盖住。
Future<void> revealBelowBar(BuildContext target) async {
  if (!target.mounted) return;
  final viewport = Scrollable.maybeOf(target)?.position.viewportDimension ?? 0;
  if (viewport <= 0) return;
  final alignment = ((PageBar.insetOf(target) + Space.x6) / viewport).clamp(0.0, 0.5);
  await Scrollable.ensureVisible(target, duration: const Duration(milliseconds: 240), curve: Curves.easeOut, alignment: alignment);
}

/// 三种打包方式。存进设置的是 [id]。
enum BuildMode {
  local('local', '本地打包'),
  github('github', 'GitHub Actions'),
  ssh('ssh', 'SSH 构建机');

  const BuildMode(this.id, this.label);
  final String id;
  final String label;

  /// 设置里存的值 → 方式。没存过（空）＝本地；认不出来的值也当本地。
  static BuildMode fromSetting(String value) => switch (value) {
    'github' => BuildMode.github,
    'ssh' => BuildMode.ssh,
    _ => BuildMode.local,
  };
}

/// 最上面的三选一：一条浅灰轨道，选中的那一格是白底 + 强调色字。[onChanged] 为 null 时锁住（打包中）。
class BuildModePicker extends StatelessWidget {
  const BuildModePicker({super.key, required this.mode, required this.onChanged});
  final BuildMode mode;
  final ValueChanged<BuildMode>? onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return Container(
      height: 44,
      padding: const EdgeInsets.all(Space.x1),
      decoration: BoxDecoration(color: c.surfaceMuted, borderRadius: BorderRadius.circular(Radii.lg)),
      child: Row(
        children: [
          for (final m in BuildMode.values)
            Expanded(
              child: Semantics(
                button: true,
                selected: m == mode,
                enabled: onChanged != null,
                child: Material(
                  color: m == mode ? c.surface : Colors.transparent,
                  borderRadius: BorderRadius.circular(Radii.md),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    key: Key('pack-mode-${m.id}'),
                    onTap: onChanged == null || m == mode ? null : () => onChanged!(m),
                    child: Center(
                      child: Text(
                        m.label,
                        maxLines: 1,
                        style: t.labelLarge?.copyWith(fontWeight: m == mode ? FontWeight.w600 : FontWeight.w400, color: m == mode ? c.accent : (onChanged == null ? c.textFaint : c.textMuted)),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 表单里的一项：标签在上，输入框独占一行，下面是一句说明；有错时说明换成报错。
class PackField extends StatelessWidget {
  const PackField({
    super.key,
    required this.label,
    required this.controller,
    this.fieldKey,
    this.hint,
    this.helper,
    this.error,
    this.enabled = true,
    this.obscure = false,
    this.mono = false,
    this.maxLines = 1,
    this.minLines,
    this.keyboardType,
    this.inputFormatters,
    this.focusNode,
    this.onChanged,
    this.last = false,
  });
  final String label;
  final TextEditingController controller;
  final Key? fieldKey;
  final String? hint;
  final String? helper;
  final String? error;
  final bool enabled;
  final bool obscure;

  /// 包名、路径、命令这类要逐字看的内容用等宽字。
  final bool mono;
  final int maxLines;
  final int? minLines;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;

  /// 一组里的最后一项：下面不再留间距。
  final bool last;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final hasError = error != null && error!.isNotEmpty;
    final errorBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(Radii.lg),
      borderSide: BorderSide(color: c.danger, width: 1.5),
    );
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : Space.x4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: t.labelMedium),
          const SizedBox(height: Space.x2),
          TextField(
            key: fieldKey,
            controller: controller,
            focusNode: focusNode,
            enabled: enabled,
            obscureText: obscure,
            autocorrect: false,
            enableSuggestions: !obscure,
            maxLines: obscure ? 1 : maxLines,
            minLines: minLines,
            keyboardType: keyboardType,
            inputFormatters: inputFormatters,
            onChanged: onChanged,
            style: mono
                ? TextStyle(fontFamily: kMonoFont, fontFamilyFallback: kMonoFallback, fontSize: FontSize.sm, height: 1.5, color: enabled ? c.text : c.textFaint)
                : t.bodyLarge?.copyWith(color: enabled ? c.text : c.textFaint),
            decoration: InputDecoration(
              hintText: hint,
              fillColor: c.canvas,
              enabledBorder: hasError ? errorBorder : null,
              focusedBorder: hasError ? errorBorder.copyWith(borderSide: BorderSide(color: c.danger, width: 2)) : null,
            ),
          ),
          if (hasError)
            Padding(
              padding: const EdgeInsets.only(top: Space.x1),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Icon(Icons.error_outline, size: 14, color: c.danger),
                  ),
                  const SizedBox(width: Space.x1),
                  Expanded(
                    child: Text(error!, style: t.bodySmall?.copyWith(color: c.danger, height: 1.5)),
                  ),
                ],
              ),
            )
          else if (helper != null)
            Padding(
              padding: const EdgeInsets.only(top: Space.x1),
              child: Text(helper!, style: t.bodySmall?.copyWith(color: c.textFaint, height: 1.5)),
            ),
        ],
      ),
    );
  }
}

/// 一个可以复制的值（路径 / 网址）：小标签在上，等宽的值在下，右边一个复制按钮。
class CopyLine extends ConsumerWidget {
  const CopyLine({super.key, required this.label, required this.value, this.note});
  final String label;
  final String value;

  /// 值下面的一句说明（怎么找到它）。
  final String? note;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final size = ref.watch(compactCodeFontProvider);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: t.labelMedium),
              const SizedBox(height: Space.x1),
              Text(
                value,
                style: TextStyle(fontFamily: kMonoFont, fontFamilyFallback: kMonoFallback, fontSize: size, height: 1.5, color: c.text),
              ),
              if (note != null)
                Padding(
                  padding: const EdgeInsets.only(top: Space.x1),
                  child: Text(note!, style: t.bodySmall?.copyWith(color: c.textFaint, height: 1.5)),
                ),
            ],
          ),
        ),
        const SizedBox(width: Space.x2),
        IconButton(
          tooltip: '复制',
          visualDensity: VisualDensity.compact,
          icon: Icon(Icons.copy_rounded, size: 18, color: c.textMuted),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: value));
            if (context.mounted) showSnack(context, '已复制');
          },
        ),
      ],
    );
  }
}

/// 结果卡 / 进度卡的外框：白底大圆角，和上面的分组卡片一个样。
class RunCard extends StatelessWidget {
  const RunCard({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(Space.x4),
    decoration: BoxDecoration(color: context.colors.surface, borderRadius: BorderRadius.circular(Radii.card)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: children),
  );
}

enum RunTone { busy, done, failed, paused }

/// 卡片的标题行：状态图标 + 一句结论（+ 进行中的小圈）。颜色之外还有图标区分状态。
class RunHeader extends StatelessWidget {
  const RunHeader({super.key, required this.tone, required this.title, this.subtitle});
  final RunTone tone;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final (Color color, IconData? icon) = switch (tone) {
      RunTone.busy => (c.text, null),
      RunTone.done => (c.accent, Icons.check_circle_rounded),
      RunTone.failed => (c.danger, Icons.error_rounded),
      RunTone.paused => (c.warning, Icons.pause_circle_rounded),
    };
    return Row(
      children: [
        if (icon != null) Icon(icon, size: 22, color: color) else const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
        const SizedBox(width: Space.x3),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: t.titleMedium?.copyWith(color: color)),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(subtitle!, style: t.bodySmall?.copyWith(color: c.textFaint)),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 页面唯一的主按钮：整行宽、48 高。[onPressed] 为 null 时是灰的。
class PrimaryBuildButton extends StatelessWidget {
  const PrimaryBuildButton({super.key, required this.label, required this.onPressed, this.buttonKey});
  final String label;
  final VoidCallback? onPressed;
  final Key? buttonKey;

  @override
  Widget build(BuildContext context) => FilledButton(
    key: buttonKey,
    onPressed: onPressed,
    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
    child: Text(label),
  );
}

/// 图标的小预览：有自己选的图就显示它，没有就是默认图标的样子（一个圆角方块里的安卓小人）。
class ApkIconPreview extends StatelessWidget {
  const ApkIconPreview({super.key, required this.png, this.size = 40, this.busy = false});
  final Uint8List? png;
  final double size;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final radius = BorderRadius.circular(size * 0.22);
    return SizedBox.square(
      dimension: size,
      child: busy
          ? Center(
              child: SizedBox.square(dimension: size * 0.45, child: const CircularProgressIndicator(strokeWidth: 2)),
            )
          : png != null
          ? ClipRRect(
              borderRadius: radius,
              child: Image.memory(png!, width: size, height: size, fit: BoxFit.cover, gaplessPlayback: true),
            )
          : DecoratedBox(
              decoration: BoxDecoration(color: c.accentSoft, borderRadius: radius),
              child: Icon(Icons.android_rounded, size: size * 0.6, color: c.accent),
            ),
    );
  }
}
