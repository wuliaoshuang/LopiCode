// 设计约束（设置 › 界面 › 外观 ›“代码字号”这一组 · 390×844）— 2026-11-25
// - 一行只做一件事：第一行“字号 + 减 / 数字 / 加”，第二行是一小段带高亮的示例（改了立刻看到效果），第三行“恢复默认”。
// - 不用滑块（手机上拖不准）；范围 10–24、一步 1、默认 14。到头的那个按钮灰掉。
// - 同一个值也能在任何代码区域里双指捏合来改，组下面的说明里写明。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lopicode/state/code_font.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/code_view.dart';
import 'package:lopicode/ui/settings_widgets.dart';
import 'package:material_ui/material_ui.dart';

const String _sample = 'function hello(name) {\n  // 示例\n  return "你好，" + name;\n}';

class CodeFontGroup extends ConsumerWidget {
  const CodeFontGroup({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final size = ref.watch(codeFontProvider);
    final notifier = ref.read(codeFontProvider.notifier);
    Widget step(Key key, IconData icon, String tip, bool enabled, double delta) =>
        IconButton(key: key, tooltip: tip, constraints: const BoxConstraints(minWidth: 44, minHeight: 44), icon: Icon(icon, size: 20), onPressed: enabled ? () => notifier.bump(delta) : null);
    return SettingsGroup(
      title: '代码字号',
      footer: '文件编辑器、“看代码”、导出预览、原始 CSS 都用这个字号。在代码上用两根手指捏合也能调。',
      padded: true,
      children: [
        Row(
          children: [
            Expanded(child: Text('字号', style: t.bodyLarge)),
            step(const Key('code-font-minus'), Icons.remove, '小一号', size > kCodeFontMin, -kCodeFontStep),
            SizedBox(
              width: 36,
              child: Text(
                size.toStringAsFixed(0),
                key: const Key('code-font-value'),
                textAlign: TextAlign.center,
                style: t.titleMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
              ),
            ),
            step(const Key('code-font-plus'), Icons.add, '大一号', size < kCodeFontMax, kCodeFontStep),
          ],
        ),
        const SizedBox(height: Space.x2),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(Space.x3),
          decoration: BoxDecoration(color: c.codeBg, borderRadius: BorderRadius.circular(Radii.md)),
          child: const CodeView(key: Key('code-font-sample'), code: _sample, language: 'js'),
        ),
        const SizedBox(height: Space.x1),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            key: const Key('code-font-reset'),
            onPressed: size == kCodeFontDefault ? null : notifier.reset,
            style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(44, 44)),
            child: Text('恢复默认（${kCodeFontDefault.toStringAsFixed(0)}）'),
          ),
        ),
      ],
    );
  }
}
