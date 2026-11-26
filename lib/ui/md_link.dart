// 设计约束（点了正文里的链接 · 390×844）— 2026-11-26
// - 应用绝不自己打开链接。点了先从底部弹出一张面板：这是什么链接、完整的网址（原样、可选字）。
// - 主操作只有一个：“复制链接”。应用现在没有“交给浏览器打开”的能力（要加新的依赖，得霜霜定），所以不放“打开”。
// - 一行只做一件事：标题一行、网址一块、说明一行、按钮一行。
import 'package:flutter/services.dart';
import 'package:lopicode/markdown/md_links.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';

Future<void> showMdLinkSheet(BuildContext context, String href) async {
  final copied = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _LinkSheet(href: href),
  );
  if (copied == true && context.mounted) showSnack(context, '已复制链接');
}

class _LinkSheet extends StatelessWidget {
  const _LinkSheet({required this.href});
  final String href;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(mdLinkKind(href), style: t.titleLarge),
            const SizedBox(height: Space.x3),
            Container(
              constraints: const BoxConstraints(maxHeight: 160),
              padding: const EdgeInsets.all(Space.x3),
              decoration: BoxDecoration(color: c.codeBg, borderRadius: BorderRadius.circular(Radii.md)),
              child: SingleChildScrollView(
                child: SelectableText(
                  mdVisibleUrl(href),
                  key: const Key('md-link-url'),
                  style: TextStyle(fontFamily: kMonoFont, fontFamilyFallback: kMonoFallback, fontSize: FontSize.sm, height: 1.5, color: c.text),
                ),
              ),
            ),
            const SizedBox(height: Space.x3),
            Text('LopiCode 不会自己打开链接。先看清上面的完整地址，复制后可以贴到浏览器里打开。', style: t.bodySmall?.copyWith(color: c.textMuted, height: 1.5)),
            const SizedBox(height: Space.x4),
            FilledButton(
              key: const Key('md-link-copy'),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: href));
                if (context.mounted) Navigator.pop(context, true);
              },
              child: const Text('复制链接'),
            ),
            const SizedBox(height: Space.x1),
            TextButton(
              key: const Key('md-link-cancel'),
              onPressed: () => Navigator.pop(context, false),
              style: TextButton.styleFrom(foregroundColor: c.textMuted),
              child: const Text('取消'),
            ),
          ],
        ),
      ),
    );
  }
}
