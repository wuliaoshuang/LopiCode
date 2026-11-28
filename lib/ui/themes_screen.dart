// 设计约束（设置 › 界面 › 外观 › 管理主题 · 390×844）— 2026-11-26
// - 顶上一行两段：浅色 / 深色（进来时停在全应用现在的明暗上）。两种主题各管各的：浅色时用哪套、深色时用哪套分开选。
// - 下面一组两行动作：新建主题（主操作，先问从哪套开始）· 导入主题。放在列表上面：主题多了也不用滚到底才找得到。
// - 再下面一张卡一套主题（一行一张）：左边一块小样子（底色上一张卡、一行字、一个强调色按钮）→ 名字 →
//   第二行“内置 / 我的 · 作者”→ 正在用的那套右边有“正在使用”→ 最右“⋯”。
//   点卡片＝选用，立刻生效。别的操作都在“⋯”里（底部面板，一行一个）：
//   内置：看看全部颜色、复制一份来改、导出；我的：编辑、改名、复制一份、导出、删除（要确认）。
// - 这一页只列和选；改颜色在编辑器（theme_editor_screen.dart），导出导入在 theme_export_sheet.dart / theme_import_screen.dart。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lopicode/appearance/theme_fields.dart';
import 'package:lopicode/backdrop/backdrop_model.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/state/themes_state.dart';
import 'package:lopicode/theme/breakpoints.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/app_backdrop.dart';
import 'package:lopicode/ui/settings_widgets.dart';
import 'package:lopicode/ui/theme_editor_screen.dart';
import 'package:lopicode/ui/theme_export_sheet.dart';
import 'package:lopicode/ui/theme_import_screen.dart';
import 'package:lopicode/ui/top_bar.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';

/// 一套主题的来源，管理页里统一这么写：内置 / 我的 / 我的 · 作者 某某。
String themeSourceLabel(ThemeSpec t) => t.builtin ? '内置' : (t.author == null || t.author!.isEmpty ? '我的' : '我的 · 作者 ${t.author}');

class ThemesScreen extends ConsumerStatefulWidget {
  const ThemesScreen({super.key, this.session});

  /// 现在开着的工作区（导出存文件、导入选文件用）；没有也行。
  final ProjectSession? session;

  @override
  ConsumerState<ThemesScreen> createState() => _ThemesScreenState();
}

class _ThemesScreenState extends ConsumerState<ThemesScreen> {
  /// 现在看的是深色那一段；null＝还没定（第一次搭界面时跟着全应用现在的明暗）。
  bool? _dark;

  ThemesNotifier get _themes => ref.read(themesProvider.notifier);

  Future<void> _select(ThemeSpec t) async {
    final failed = await _themes.select(t.id);
    if (mounted && failed != null) showSnack(context, failed);
  }

  Future<void> _edit(ThemeSpec t) => pushSettingsPage<void>(context, ThemeEditorScreen(theme: t));

  Future<void> _duplicate(ThemeSpec t, {String? name, bool thenEdit = true}) async {
    final r = await _themes.duplicate(t.id, name: name);
    if (!mounted) return;
    final copy = r.theme;
    if (copy == null) return showSnack(context, r.error ?? '没复制成。');
    if (thenEdit) return _edit(copy);
    showSnack(context, '复制好了：“${copy.name}”。');
  }

  Future<void> _rename(ThemeSpec t) async {
    final name = await promptDialog(context, title: '改名', initial: t.name, hint: '主题的名字', confirmLabel: '改名');
    if (name == null || !mounted) return;
    final failed = await _themes.rename(t.id, name);
    if (mounted && failed != null) showSnack(context, failed);
  }

  Future<void> _delete(ThemeSpec t, {required bool inUse}) async {
    final ok = await confirmDialog(
      context,
      title: '删除“${t.name}”？',
      message: inUse ? '这套正在用。删掉以后换回默认${t.dark ? '深色' : '浅色'}主题。删了找不回来（先导出可以留一份）。' : '删了找不回来（先导出可以留一份）。',
      confirmLabel: '删除',
      danger: true,
    );
    if (!ok || !mounted) return;
    final failed = await _themes.delete(t.id);
    if (mounted) showSnack(context, failed ?? '已删除“${t.name}”。');
  }

  Future<void> _more(ThemeSpec t, {required bool inUse}) async {
    final c = context.colors;
    final act = await showModalBottomSheet<String>(
      context: context,
      builder: (context) {
        Widget row(String id, IconData icon, String label, {bool danger = false}) => ListTile(
          key: Key('themes-act-$id'),
          leading: Icon(icon, color: danger ? c.danger : c.textMuted),
          title: Text(label, style: danger ? TextStyle(color: c.danger) : null),
          onTap: () => Navigator.pop(context, id),
        );
        return SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x2),
                child: Text(t.name, style: Theme.of(context).textTheme.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              if (t.builtin) ...[
                row('view', Icons.visibility_outlined, '看看全部颜色'),
                row('copy-edit', Icons.edit_outlined, '复制一份来改'),
                row('export', Icons.ios_share_outlined, '导出'),
              ] else ...[
                row('edit', Icons.edit_outlined, '编辑'),
                row('rename', Icons.drive_file_rename_outline, '改名'),
                row('copy', Icons.copy_outlined, '复制一份'),
                row('export', Icons.ios_share_outlined, '导出'),
                row('delete', Icons.delete_outline, '删除', danger: true),
              ],
            ],
          ),
        );
      },
    );
    if (!mounted || act == null) return;
    switch (act) {
      case 'view' || 'edit':
        await _edit(t);
      case 'copy-edit':
        await _duplicate(t);
      case 'copy':
        await _duplicate(t, thenEdit: false);
      case 'rename':
        await _rename(t);
      case 'export':
        await showThemeExportSheet(context, theme: t, session: widget.session);
      case 'delete':
        await _delete(t, inUse: inUse);
    }
  }

  /// 新建：先问从哪套开始，复制一份，直接进编辑器。
  Future<void> _create(bool dark, List<ThemeSpec> choices) async {
    final from = await showModalBottomSheet<ThemeSpec>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x1),
                child: Text('新建${dark ? '深色' : '浅色'}主题：从哪套开始？', style: Theme.of(context).textTheme.titleMedium),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x2),
                child: Text('会复制一份出来给你改，原来那套不动。', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.colors.textMuted)),
              ),
              Flexible(
                child: ListView(
                  key: const Key('themes-from-list'),
                  shrinkWrap: true,
                  children: [
                    for (final t in choices)
                      ListTile(
                        key: Key('themes-from-${t.id}'),
                        leading: ThemeMiniLook(theme: t, width: 48, height: 34),
                        title: Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(themeSourceLabel(t)),
                        onTap: () => Navigator.pop(context, t),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (from == null || !mounted) return;
    await _duplicate(from, name: dark ? '我的深色主题' : '我的浅色主题');
  }

  Future<void> _import() async {
    final added = await pushSettingsPage<ThemeSpec>(context, ThemeImportScreen(session: widget.session));
    // 加进来的那套在哪一段，就切到哪一段让她看见。
    if (added != null && mounted) setState(() => _dark = added.dark);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final view = ref.watch(themesProvider);
    final dark = _dark ?? context.themeSpec.dark;
    final choices = view.choices(dark: dark);
    final current = dark ? view.dark : view.light;
    return AppBackdrop(
      area: BackdropArea.pages,
      builder: (context, on) => Scaffold(
        backgroundColor: on ? Colors.transparent : c.canvas,
        extendBodyBehindAppBar: true,
        appBar: PageBar(background: c.canvas, titleText: '管理主题'),
        body: ContentWidth(
          child: SingleChildScrollView(
            key: const Key('themes-list'),
            padding: EdgeInsets.fromLTRB(Space.x4, PageBar.insetOf(context) + Space.x2, Space.x4, Space.x8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                SegmentedButton<bool>(
                  key: const Key('themes-brightness'),
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: false, label: Text('浅色'), icon: Icon(Icons.light_mode_outlined, size: 18)),
                    ButtonSegment(value: true, label: Text('深色'), icon: Icon(Icons.dark_mode_outlined, size: 18)),
                  ],
                  selected: {dark},
                  onSelectionChanged: (s) => setState(() => _dark = s.first),
                ),
                const SizedBox(height: Space.x4),
                SettingsGroup(
                  iconRows: true,
                  children: [
                    SettingsRow(key: const Key('themes-new'), icon: Icons.add, title: '新建主题', subtitle: '从一套现有的开始改', accent: true, onTap: () => _create(dark, choices)),
                    SettingsRow(key: const Key('themes-import'), icon: Icons.file_download_outlined, title: '导入主题', subtitle: '粘贴别人给的主题文本，或从工作区选文件', onTap: _import),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.x1, 0, Space.x1, Space.x2),
                  child: Text(dark ? '颜色模式是深色（或跟随系统且手机是深色）时用选中的这套。点一张卡就换上。' : '颜色模式是浅色（或跟随系统且手机是浅色）时用选中的这套。点一张卡就换上。', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: c.textMuted)),
                ),
                for (final t in choices)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Space.x2),
                    child: _ThemeCard(
                      theme: t,
                      inUse: t.id == current.id,
                      onTap: () => _select(t),
                      onMore: () => _more(t, inUse: t.id == current.id),
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

class _ThemeCard extends StatelessWidget {
  const _ThemeCard({required this.theme, required this.inUse, required this.onTap, required this.onMore});
  final ThemeSpec theme;
  final bool inUse;
  final VoidCallback onTap;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final radius = BorderRadius.circular(c.radius(Radii.md));
    return Semantics(
      button: true,
      selected: inUse,
      child: Material(
        color: c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: inUse ? c.accent : c.border, width: inUse ? 1.5 : c.hairline),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: Key('themes-card-${theme.id}'),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Space.x3, Space.x3, 0, Space.x3),
            child: Row(
              children: [
                ThemeMiniLook(theme: theme),
                const SizedBox(width: Space.x3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(theme.name, style: t.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Text(
                        themeSourceLabel(theme),
                        key: Key('themes-source-${theme.id}'),
                        style: t.bodySmall?.copyWith(color: c.textMuted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (inUse)
                  Container(
                    key: Key('themes-inuse-${theme.id}'),
                    padding: const EdgeInsets.symmetric(horizontal: Space.x2, vertical: 2),
                    decoration: BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(Radii.sm)),
                    child: Text('正在使用', style: t.labelSmall?.copyWith(color: c.accent)),
                  ),
                IconButton(key: Key('themes-more-${theme.id}'), icon: const Icon(Icons.more_horiz), tooltip: '更多', onPressed: onMore),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 一套主题的小样子：底色上一张卡，卡里一行字、一行淡字、一个强调色小按钮；右边一条是代码底色和三种积木色。
class ThemeMiniLook extends StatelessWidget {
  const ThemeMiniLook({super.key, required this.theme, this.width = 84, this.height = 56});
  final ThemeSpec theme;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final u = height / 56;
    Widget bar(Color color, double w, double h) => Container(
      width: w * u,
      height: h * u,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(h * u / 2)),
    );
    return ExcludeSemantics(
      child: Container(
        key: Key('theme-mini-${theme.id}'),
        width: width,
        height: height,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: theme.uiColor(UiKey.canvas),
          borderRadius: BorderRadius.circular(Radii.sm),
          border: Border.all(color: c.border, width: c.hairline),
        ),
        child: Row(
          children: [
            Expanded(
              child: Container(
                margin: EdgeInsets.all(6 * u),
                padding: EdgeInsets.all(5 * u),
                decoration: BoxDecoration(
                  color: theme.uiColor(UiKey.surface),
                  borderRadius: BorderRadius.circular(4 * u),
                  border: Border.all(color: theme.uiColor(UiKey.border), width: 0.5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [bar(theme.uiColor(UiKey.text), 30, 4), bar(theme.uiColor(UiKey.textFaint), 20, 4), bar(theme.uiColor(UiKey.accentFill), 22, 8)],
                ),
              ),
            ),
            Container(
              width: 20 * u,
              color: theme.codeColor(CodeKey.bg),
              padding: EdgeInsets.symmetric(vertical: 8 * u),
              child: Column(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [for (final f in kBlockCategoryFields.take(3)) bar(theme.blockColor(f.key), 10, 8)]),
            ),
          ],
        ),
      ),
    );
  }
}
