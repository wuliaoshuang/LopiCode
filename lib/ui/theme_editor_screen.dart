// 设计约束（设置 › 界面 › 外观 › 管理主题 › 编辑 · 主题编辑器 · 390×844）— 2026-11-26
// - 顶栏：返回 · 主题名 · 撤销 · 重做 · “⋯”（改名、换强调色、从主色生成整套、全部恢复为起点）。挤不下的都在“⋯”里。
// - 顶栏下面固定不滚的一块（键盘升起来找东西时这一块让出去，只留搜索）：
//   1) 实时预览（高 232）——用“正在编辑的这份草稿”画，不影响全应用；**保存以后**全应用才换上。
//   2) 预览看哪一种：界面 / 代码 / 积木 / 终端 / 搭建（一行五段；“搭建”＝低代码编辑器那 21 项）。点某一项时自动切到它所在的那一种。
//   3) 一行找东西：搜索框 + “只看改过的”。
//   4) “N 项对比度偏低”（有才出现；点开列表、能跳到那一项；只提醒不拦保存）。
// - 再下面是能滚的列表，一行一项、行高都一样（见 theme_editor_rows.dart）：
//   快捷生成两行 → 形状与密度（6 个数）→ 界面 → 代码 → 代码高亮 → 终端 → 积木 → 低代码编辑器。
//   每组一个标题行，点了展开 / 收起（默认只展开“界面”）；在搜索或只看改过的时，所有组都摊开、只剩对得上的行。
// - 主操作“保存”：有改动时贴在底部一整行。没改动时不出现。
// - 离开时有没保存的改动要问：保存并离开 / 不保存 / 继续编辑。
// - 内置主题进来是只读：顶上一条说明 + “复制一份来改”；行可以看、点了提示，不能改。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lopicode/appearance/theme_contrast.dart';
import 'package:lopicode/appearance/theme_edit_model.dart';
import 'package:lopicode/appearance/theme_fields.dart';
import 'package:lopicode/appearance/theme_generate.dart';
import 'package:lopicode/appearance/theme_spec.dart';
import 'package:lopicode/backdrop/backdrop_model.dart';
import 'package:lopicode/state/theme_hooks.dart';
import 'package:lopicode/state/themes_state.dart';
import 'package:lopicode/theme/tokens.dart' hide ThemeSpec;
import 'package:lopicode/ui/app_backdrop.dart';
import 'package:lopicode/ui/keyboard_tap_dismiss.dart';
import 'package:lopicode/ui/theme_color_sheet.dart';
import 'package:lopicode/ui/theme_editor_rows.dart';
import 'package:lopicode/ui/theme_generate_sheet.dart';
import 'package:lopicode/ui/theme_preview.dart';
import 'package:lopicode/ui/top_bar.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';

enum _Kind { action, header, color, metric }

class _Entry {
  const _Entry(this.kind, {this.section = '', this.item, this.metric, this.action = ''});
  final _Kind kind;
  final String section;
  final ThemeItem? item;
  final ThemeMetricField? metric;
  final String action;
}

const String _kMetrics = 'metrics';

class ThemeEditorScreen extends ConsumerStatefulWidget {
  const ThemeEditorScreen({super.key, required this.theme});

  /// 要改的那套（内置的进来是只读）。
  final ThemeSpec theme;

  @override
  ConsumerState<ThemeEditorScreen> createState() => _ThemeEditorScreenState();
}

class _ThemeEditorScreenState extends ConsumerState<ThemeEditorScreen> {
  late ThemeHistory _h = ThemeHistory(widget.theme);
  ThemePreviewKind _kind = ThemePreviewKind.ui;
  final Set<String> _open = {'ui'};
  final TextEditingController _search = TextEditingController();
  final ScrollController _scroll = ScrollController();
  bool _onlyChanged = false;

  /// 刚跳过去的那一项（底色稍微亮一下，改了别的就不亮了）。
  String? _focus;

  /// 取色 / 生成面板开着：这时键盘升起来也不收预览。
  bool _sheetOpen = false;
  int _sheetSeq = 0;
  bool _saving = false;

  bool get _readOnly => widget.theme.builtin;
  ThemeSpec get _spec => _h.current;

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _say(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  void _apply(ThemeSpec next, {String? tag}) => setState(() {
    _h = _h.apply(next, tag: tag);
    _focus = null;
  });

  bool _blocked() {
    if (!_readOnly) return false;
    _say('内置主题不能直接改。点上面的“复制一份来改”。');
    return true;
  }

  // ── 列表里有哪些行 ──

  List<_Entry> _entries(Set<String> changed) {
    final q = _search.text.trim().toLowerCase();
    final filtering = q.isNotEmpty || _onlyChanged;
    bool hit(String id, List<String> words) => (!_onlyChanged || changed.contains(id)) && (q.isEmpty || words.any((w) => w.toLowerCase().contains(q)));
    final out = <_Entry>[];
    if (!filtering && !_readOnly) {
      out
        ..add(const _Entry(_Kind.action, action: 'accent'))
        ..add(const _Entry(_Kind.action, action: 'generate'));
    }
    final metricLabel = kThemeSectionLabels[_kMetrics] ?? _kMetrics;
    final metrics = [
      for (final f in kMetricFields)
        if (hit('$_kMetrics.${f.key}', [f.label, f.note, metricLabel])) _Entry(_Kind.metric, section: _kMetrics, metric: f),
    ];
    if (!filtering || metrics.isNotEmpty) {
      out.add(const _Entry(_Kind.header, section: _kMetrics));
      if (filtering || _open.contains(_kMetrics)) out.addAll(metrics);
    }
    for (final s in kThemeEditSections) {
      final rows = [
        for (final i in kThemeItems)
          if (i.section == s && hit(i.id, [i.label, i.note, i.group, i.sectionLabel, i.key])) _Entry(_Kind.color, section: s, item: i),
      ];
      if (filtering && rows.isEmpty) continue;
      out.add(_Entry(_Kind.header, section: s));
      if (filtering || _open.contains(s)) out.addAll(rows);
    }
    return out;
  }

  // ── 改一项 ──

  Future<void> _editColor(ThemeItem item) async {
    if (_blocked()) return;
    final before = itemColor(_spec, item);
    final tag = 'color-${++_sheetSeq}';
    setState(() {
      _sheetOpen = true;
      _focus = null;
      _kind = switch (item.section) {
        'ui' => ThemePreviewKind.ui,
        'code' || 'tokens' => ThemePreviewKind.code,
        'terminal' => ThemePreviewKind.terminal,
        'blocks' => ThemePreviewKind.blocks,
        'lowcode' => ThemePreviewKind.lowcode,
        _ => _kind,
      };
    });
    await showThemeColorSheet(
      context,
      item: item,
      spec: () => _spec,
      onChanged: (c) => _apply(setItemColor(_spec, item, c), tag: tag),
    );
    if (!mounted) return;
    setState(() => _sheetOpen = false);
    final after = itemColor(_spec, item);
    if (after != null && after != before) ref.read(recentColorsProvider.notifier).remember(after);
  }

  Future<void> _generate({required bool full}) async {
    if (_blocked()) return;
    final before = _h;
    final tag = 'gen-${++_sheetSeq}';
    setState(() => _sheetOpen = true);
    final ok = await showThemeGenerateSheet(
      context,
      full: full,
      accent: _spec.ui[UiKey.accentFill] ?? _spec.ui[UiKey.accent] ?? 0xFF2962CB,
      tint: _spec.ui[UiKey.bg] ?? 0xFFFFFFFF,
      // 每次都从打开面板之前的那份算起（不在算过的结果上再叠一遍）。
      onChanged: (accent, tint) => _apply(
        full ? generateTheme(dark: before.current.dark, tint: tint, accent: accent, shell: before.current) : reaccentTheme(before.current, accent),
        tag: tag,
      ),
    );
    if (!mounted) return;
    setState(() {
      _sheetOpen = false;
      if (ok != true) _h = before;
    });
  }

  Future<void> _showIssues(List<ContrastIssue> issues) async {
    final picked = await showThemeContrastSheet(context, issues: issues, readOnly: _readOnly);
    if (!mounted || picked == null) return;
    if (picked == kThemeFixContrast) {
      final fixed = repairContrast(_spec);
      final left = checkThemeContrast(fixed).length;
      _apply(fixed);
      _say(left == 0 ? '都调到达标了。不满意可以点撤销。' : '能调的都调了，还剩 $left 项要手动改（多半是半透明的颜色）。');
      return;
    }
    _jumpTo(picked);
  }

  /// 跳到某一项：清掉筛选、展开它那一组、滚过去。
  void _jumpTo(String itemId) {
    final item = themeItemById(itemId);
    if (item == null) return;
    setState(() {
      _search.clear();
      _onlyChanged = false;
      _open.add(item.section);
      _focus = itemId;
    });
    final index = _entries(const {}).indexWhere((e) => e.item?.id == itemId);
    if (index < 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.jumpTo((index * kThemeRowHeight - kThemeRowHeight).clamp(0.0, _scroll.position.maxScrollExtent));
    });
  }

  // ── 顶栏上的事 ──

  Future<void> _rename() async {
    if (_blocked()) return;
    final name = await promptDialog(context, title: '改名', initial: _spec.name, hint: '主题的名字', confirmLabel: '改名');
    if (name == null || !mounted) return;
    final failed = await ref.read(themesProvider.notifier).rename(_spec.id, name);
    if (!mounted) return;
    if (failed != null) return _say(failed);
    final saved = ref.read(themesProvider).byId(_spec.id)?.name ?? name.trim();
    setState(() => _h = _h.renamed(saved));
  }

  Future<void> _resetAll() async {
    if (_blocked()) return;
    if (!_h.dirty) return _say('现在就是起点的样子，没有改动。');
    final ok = await confirmDialog(context, title: '全部恢复为起点？', message: '这次打开（或上次保存）以后改的都退回去。退回去以后还可以点撤销找回来。', confirmLabel: '恢复');
    if (ok && mounted) setState(() => _h = _h.reset());
  }

  Future<bool> _save() async {
    if (_saving) return false;
    setState(() => _saving = true);
    final failed = await ref.read(themesProvider.notifier).save(_spec);
    if (!mounted) return false;
    setState(() {
      _saving = false;
      if (failed == null) _h = _h.saved();
    });
    _say(failed ?? '保存好了。');
    return failed == null;
  }

  Future<void> _copyToEdit() async {
    final nav = Navigator.of(context);
    final r = await ref.read(themesProvider.notifier).duplicate(widget.theme.id);
    if (!mounted) return;
    final copy = r.theme;
    if (copy == null) return _say(r.error ?? '没复制成。');
    await nav.pushReplacement(MaterialPageRoute<void>(builder: (_) => ThemeEditorScreen(theme: copy)));
  }

  Future<void> _askLeave() async {
    final nav = Navigator.of(context);
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('改动还没保存'),
        content: const Text('现在离开，这次的改动就没了。'),
        actions: [
          TextButton(
            key: const Key('theme-leave-discard'),
            onPressed: () => Navigator.pop(context, 'discard'),
            style: TextButton.styleFrom(foregroundColor: context.colors.danger),
            child: const Text('不保存'),
          ),
          TextButton(
            key: const Key('theme-leave-stay'),
            onPressed: () => Navigator.pop(context, 'stay'),
            style: TextButton.styleFrom(foregroundColor: context.colors.textMuted),
            child: const Text('继续编辑'),
          ),
          TextButton(key: const Key('theme-leave-save'), onPressed: () => Navigator.pop(context, 'save'), child: const Text('保存并离开')),
        ],
      ),
    );
    if (!mounted || choice == null || choice == 'stay') return;
    if (choice == 'save' && !await _save()) return;
    if (choice == 'discard') setState(() => _h = ThemeHistory(_h.origin));
    // 这时已经没有未保存的改动了，等这一帧排完（PopScope 放行）再走。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) nav.pop();
    });
  }

  // ── 搭界面 ──

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final changed = changedThemeItems(_h.origin, _spec);
    final issues = checkThemeContrast(_spec);
    final low = lowContrastItems(issues);
    final entries = _entries(changed);
    final typing = MediaQuery.viewInsetsOf(context).bottom > 0 && !_sheetOpen;

    Widget row(_Entry e) {
      switch (e.kind) {
        case _Kind.action:
          return e.action == 'accent'
              ? ThemeActionRow(key: const Key('theme-quick-accent'), icon: Icons.palette_outlined, title: '换强调色', subtitle: '按钮、链接、选中这一组一起换', onTap: () => _generate(full: false))
              : ThemeActionRow(key: const Key('theme-quick-generate'), icon: Icons.auto_awesome_outlined, title: '从主色生成整套', subtitle: '给强调色和底色倾向，算一套初稿', onTap: () => _generate(full: true));
        case _Kind.header:
          final s = e.section;
          final total = s == _kMetrics ? kMetricFields.length : kThemeItems.where((i) => i.section == s).length;
          return DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: c.border, width: c.hairline),
              ),
            ),
            child: ThemeSectionHeader(
              id: s,
              title: kThemeSectionLabels[s] ?? s,
              total: total,
              changed: changed.where((id) => id.startsWith('$s.')).length,
              expanded: _open.contains(s) || _search.text.trim().isNotEmpty || _onlyChanged,
              onTap: () => setState(() => _open.contains(s) ? _open.remove(s) : _open.add(s)),
            ),
          );
        case _Kind.metric:
          final f = e.metric!;
          return ThemeMetricRow(field: f, value: _spec.metric(f.key), changed: changed.contains('$_kMetrics.${f.key}'), readOnly: _readOnly, onChanged: (v) => _apply(_spec.withMetric(f.key, v)));
        case _Kind.color:
          final item = e.item!;
          return ColoredBox(
            color: _focus == item.id ? c.selectedBg : Colors.transparent,
            child: ThemeColorRow(
              item: item,
              spec: _spec,
              changed: changed.contains(item.id),
              low: low.contains(item.id),
              readOnly: _readOnly,
              onTap: () => _editColor(item),
              onStyle: (style) => _apply(_spec.withToken(item.key, style)),
            ),
          );
      }
    }

    return PopScope(
      canPop: !_h.dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _askLeave();
      },
      child: AppBackdrop(
        area: BackdropArea.pages,
        builder: (context, on) => Scaffold(
          backgroundColor: on ? Colors.transparent : c.bg,
          extendBodyBehindAppBar: true,
          appBar: PageBar(
            background: c.bg,
            titleText: _spec.name,
            subtitle: _readOnly ? '内置 · 只读' : (_spec.dark ? '深色主题' : '浅色主题'),
            actions: [
              // 顶栏会把这一页的操作装进一个胶囊，里面放普通的图标按钮（不要再套一层圆按钮：两个圆会叠在一起）。
              IconButton(key: const Key('theme-undo'), icon: const Icon(Icons.undo), tooltip: '撤销', onPressed: _h.canUndo ? () => setState(() => _h = _h.undo()) : null),
              IconButton(key: const Key('theme-redo'), icon: const Icon(Icons.redo), tooltip: '重做', onPressed: _h.canRedo ? () => setState(() => _h = _h.redo()) : null),
              if (!_readOnly)
                PopupMenuButton<String>(
                  key: const Key('theme-editor-more'),
                  tooltip: '更多',
                  icon: const Icon(Icons.more_horiz),
                  onSelected: (v) => switch (v) {
                    'rename' => _rename(),
                    'accent' => _generate(full: false),
                    'generate' => _generate(full: true),
                    _ => _resetAll(),
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'rename', child: Text('改名')),
                    PopupMenuItem(value: 'accent', child: Text('换强调色')),
                    PopupMenuItem(value: 'generate', child: Text('从主色生成整套')),
                    PopupMenuItem(value: 'reset', child: Text('全部恢复为起点')),
                  ],
                ),
            ],
          ),
          bottomNavigationBar: _h.dirty && !_readOnly && !typing
              ? SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(Space.x4, Space.x2, Space.x4, Space.x2),
                    child: FilledButton(key: const Key('theme-save'), onPressed: _saving ? null : _save, child: Text('保存（改了 ${changed.length} 项）')),
                  ),
                )
              : null,
          body: BelowBar(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!typing) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Space.x4),
                    child: ThemePreview(spec: _spec, kind: _kind),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(Space.x4, Space.x2, Space.x4, 0),
                    child: SegmentedButton<ThemePreviewKind>(
                      key: const Key('theme-preview-kind'),
                      showSelectedIcon: false,
                      style: const ButtonStyle(visualDensity: VisualDensity.compact),
                      segments: [for (final k in ThemePreviewKind.values) ButtonSegment(value: k, label: Text(k.label))],
                      selected: {_kind},
                      onSelectionChanged: (s) => setState(() => _kind = s.first),
                    ),
                  ),
                ],
                if (_readOnly)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(Space.x4, Space.x2, Space.x2, 0),
                    child: Row(
                      key: const Key('theme-readonly-banner'),
                      children: [
                        Icon(Icons.lock_outline, size: 16, color: c.textMuted),
                        const SizedBox(width: Space.x2),
                        Expanded(
                          child: Text('内置主题只能看，不能改。', style: t.bodySmall?.copyWith(color: c.textMuted)),
                        ),
                        TextButton(key: const Key('theme-copy-to-edit'), onPressed: _copyToEdit, child: const Text('复制一份来改')),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.x4, Space.x2, Space.x4, Space.x2),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          key: const Key('theme-search'),
                          controller: _search,
                          textInputAction: TextInputAction.search,
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: '按名字找一项，比如“按钮”“注释”',
                            prefixIcon: const Icon(Icons.search, size: 20),
                            suffixIcon: _search.text.isEmpty
                                ? null
                                : KeyboardKeep(
                                    child: IconButton(key: const Key('theme-search-clear'), icon: const Icon(Icons.close, size: 18), tooltip: '清空', onPressed: () => setState(_search.clear)),
                                  ),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: Space.x2),
                      KeyboardKeep(
                        child: FilterChip(
                          key: const Key('theme-only-changed'),
                          label: Text(changed.isEmpty ? '改过的' : '改过的 ${changed.length}'),
                          selected: _onlyChanged,
                          showCheckmark: false,
                          onSelected: (v) => setState(() => _onlyChanged = v),
                        ),
                      ),
                    ],
                  ),
                ),
                if (issues.isNotEmpty && !typing) ThemeContrastBanner(count: issues.length, onTap: () => _showIssues(issues)),
                Expanded(
                  child: entries.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(Space.x6),
                            child: Text(
                              _onlyChanged && _search.text.trim().isEmpty ? '还没有改过任何一项。' : '没有找到对得上的项。换个词试试，或者关掉“改过的”。',
                              key: const Key('theme-empty'),
                              textAlign: TextAlign.center,
                              style: t.bodyMedium?.copyWith(color: c.textMuted),
                            ),
                          ),
                        )
                      : ListView.builder(
                          key: const Key('theme-editor-list'),
                          controller: _scroll,
                          padding: const EdgeInsets.only(bottom: Space.x6),
                          itemExtent: kThemeRowHeight,
                          itemCount: entries.length,
                          itemBuilder: (context, i) => row(entries[i]),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
