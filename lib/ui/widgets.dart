import 'package:lopicode/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// 空状态：一个图标、一句说明、最多一个主操作。
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, required this.message, this.action});
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(Space.x6, Space.x6, Space.x6, Space.x8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(Radii.md)),
                child: Icon(icon, size: 22, color: c.accent),
              ),
              const SizedBox(height: Space.x4),
              Text(title, style: t.titleMedium),
              const SizedBox(height: Space.x1),
              Text(message, style: t.bodyMedium?.copyWith(color: c.textMuted, height: 1.45)),
              if (action != null) ...[const SizedBox(height: Space.x4), action!],
            ],
          ),
        ),
      ),
    );
  }
}

/// 分组小标题。
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(Space.x4, Space.x6, Space.x4, Space.x2),
    child: Text(text, style: Theme.of(context).textTheme.labelMedium),
  );
}

enum BannerTone { info, warning, danger }

/// 一条如实说明限制 / 状态的提示条。
class InfoBanner extends StatelessWidget {
  const InfoBanner(this.text, {super.key, this.tone = BannerTone.info, this.margin});
  final String text;
  final BannerTone tone;
  final EdgeInsets? margin;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (bg, fg, icon) = switch (tone) {
      BannerTone.info => (c.surfaceMuted, c.textMuted, Icons.info_outline),
      BannerTone.warning => (c.warningSoft, c.warning, Icons.warning_amber_rounded),
      BannerTone.danger => (c.dangerSoft, c.danger, Icons.error_outline),
    };
    return Container(
      margin: margin,
      padding: const EdgeInsets.all(Space.x3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(Radii.md)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: fg),
          const SizedBox(width: Space.x2),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: fg, height: 1.5)),
          ),
        ],
      ),
    );
  }
}

void showSnack(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

Future<bool> confirmDialog(BuildContext context, {required String title, required String message, required String confirmLabel, bool danger = false}) async {
  final c = context.colors;
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          style: TextButton.styleFrom(foregroundColor: c.textMuted),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          style: TextButton.styleFrom(foregroundColor: danger ? c.danger : c.accent),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// 输入一行文字的对话框；返回 null 表示取消。
Future<String?> promptDialog(BuildContext context, {required String title, String initial = '', String? hint, String confirmLabel = '确定'}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(hintText: hint),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          style: TextButton.styleFrom(foregroundColor: context.colors.textMuted),
          child: const Text('取消'),
        ),
        TextButton(onPressed: () => Navigator.pop(context, controller.text), child: Text(confirmLabel)),
      ],
    ),
  );
}
