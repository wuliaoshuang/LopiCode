// 设计约束（设置 › 界面 › 外观 里的“主题”两行 + 点开的主题列表页 · 390×844）— 2026-11-26
// - 外观页里一组〔主题〕两行：浅色主题、深色主题，右边写现在用的那套的名字，点开进列表页。
//   分两行是因为“跟随系统”时两种都会用到：浅色时用哪套、深色时用哪套各选各的。
// - 列表页一行一套主题（单选，点了立刻生效，不用再点保存）：左边三个小色点（底色、强调色、文字色）
//   让人不点也大概知道长什么样；副标题写来源（内置 / 自己的 / 作者）。内置的在前，自己的在后。
// - 这里只管“选”。新建、编辑、导入导出在以后的主题管理页，这一页不放那些入口。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lopicode/appearance/theme_fields.dart';
import 'package:lopicode/state/themes_state.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/settings_widgets.dart';
import 'package:material_ui/material_ui.dart';

/// 外观页里的〔主题〕一组：浅色主题 / 深色主题两行。
class ThemeSlotsGroup extends ConsumerWidget {
  const ThemeSlotsGroup({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(themesProvider);
    return SettingsGroup(
      title: '主题',
      footer: '浅色和深色各选一套：颜色模式是“跟随系统”时，手机切到深色就自动换成深色那套。',
      children: [
        SettingsRow(
          key: const Key('appearance-theme-light'),
          title: '浅色主题',
          value: view.light.name,
          valueKey: const Key('appearance-theme-light-value'),
          onTap: () => pushSettingsPage<void>(context, const ThemePickScreen(dark: false)),
        ),
        SettingsRow(
          key: const Key('appearance-theme-dark'),
          title: '深色主题',
          value: view.dark.name,
          valueKey: const Key('appearance-theme-dark-value'),
          onTap: () => pushSettingsPage<void>(context, const ThemePickScreen(dark: true)),
        ),
      ],
    );
  }
}

/// 设置 › 界面 › 外观 › 浅色主题 / 深色主题：选一套。
class ThemePickScreen extends ConsumerWidget {
  const ThemePickScreen({super.key, required this.dark});
  final bool dark;

  static String sourceLabel(ThemeSpec t) {
    if (t.builtin) return '内置';
    final author = t.author;
    return author == null || author.isEmpty ? '自己的' : '自己的 · 作者 $author';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(themesProvider);
    final current = dark ? view.dark : view.light;
    final choices = view.choices(dark: dark);
    return SettingsPage(
      title: dark ? '深色主题' : '浅色主题',
      children: [
        SettingsGroup(
          footer: dark ? '颜色模式是深色（或跟随系统且手机是深色）时用这一套。' : '颜色模式是浅色（或跟随系统且手机是浅色）时用这一套。',
          children: [
            for (final t in choices)
              SettingsChoiceRow(
                key: Key('theme-pick-${t.id}'),
                title: t.name,
                subtitle: sourceLabel(t),
                selected: t.id == current.id,
                onTap: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  final failed = await ref.read(themesProvider.notifier).select(t.id);
                  if (failed != null) messenger.showSnackBar(SnackBar(content: Text(failed)));
                },
              ),
          ],
        ),
        SettingsGroup(
          title: '现在这套的样子',
          padded: true,
          children: [ThemeSwatches(theme: current)],
        ),
      ],
    );
  }
}

/// 一排小色块：让人大概知道这套主题长什么样（底色、表面、强调色、文字、代码底、终端底、几种积木）。
class ThemeSwatches extends StatelessWidget {
  const ThemeSwatches({super.key, required this.theme});
  final ThemeSpec theme;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final items = <(String, Color)>[
      ('底色', theme.uiColor(UiKey.bg)),
      ('表面', theme.uiColor(UiKey.surface)),
      ('强调', theme.uiColor(UiKey.accent)),
      ('文字', theme.uiColor(UiKey.text)),
      ('代码', theme.codeColor(CodeKey.bg)),
      ('终端', theme.terminalColor('bg')),
      ('积木', theme.blockColor(kBlockCategoryFields.first.key)),
    ];
    return Wrap(
      key: const Key('theme-swatches'),
      spacing: Space.x3,
      runSpacing: Space.x3,
      children: [
        for (final (label, color) in items)
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(c.radius(Radii.sm)),
                  border: Border.all(color: c.border, width: c.hairline),
                ),
              ),
              const SizedBox(height: Space.x1),
              Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: c.textMuted)),
            ],
          ),
      ],
    );
  }
}
