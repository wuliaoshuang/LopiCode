// 设计约束（外壳 · 390×844）
// - 没有底部导航。所有去处都在侧边栏里：项目切换在最上，然后是对话和各个工具，设置钉在最下。
// - 每个页面的顶栏是同一个样子：左边汉堡按钮，两行标题（大标题 + 一行弱化的副标题），右边是这一页自己的操作。
// - 侧边栏里当前所在的那一项高亮（强调色浅底 + 强调色文字），其余是普通文字。
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// 项目里能去的页面。
enum ShellDest {
  chat('Agent 对话', Icons.auto_awesome_outlined),
  files('文件', Icons.folder_outlined),
  terminal('终端', Icons.terminal),
  preview('预览', Icons.play_circle_outline),
  builder('低代码搭建', Icons.dashboard_customize_outlined),
  apk('APK 打包', Icons.android),
  runtime('运行环境', Icons.memory_outlined);

  const ShellDest(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// 外壳把“打开侧边栏”“去某一页”交给里面的页面用。
class ShellScope extends InheritedWidget {
  const ShellScope({super.key, required this.openDrawer, required this.go, required this.projectName, required super.child});
  final VoidCallback openDrawer;
  final void Function(ShellDest dest) go;
  final String projectName;

  static ShellScope? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<ShellScope>();

  @override
  bool updateShouldNotify(ShellScope old) => projectName != old.projectName;
}

/// 顶栏左边的按钮：在外壳里是汉堡按钮；单独打开的页面（能返回）是返回箭头。
Widget? shellLeading(BuildContext context) {
  final shell = ShellScope.maybeOf(context);
  if (shell != null) return _MenuButton(onPressed: shell.openDrawer);
  if (Navigator.canPop(context)) return null; // 用默认的返回按钮
  final scaffold = Scaffold.maybeOf(context);
  if (scaffold != null && scaffold.hasDrawer) return _MenuButton(onPressed: scaffold.openDrawer);
  return null;
}

class _MenuButton extends StatelessWidget {
  const _MenuButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) =>
      IconButton(tooltip: '打开侧边栏', icon: Icon(Icons.notes_rounded, color: context.colors.text), onPressed: onPressed);
}

/// 统一的顶栏：汉堡按钮 + 两行标题 + 这一页的操作。
class ShellAppBar extends StatelessWidget implements PreferredSizeWidget {
  const ShellAppBar({super.key, required this.title, this.subtitle, this.actions});
  final String title;
  final String? subtitle;
  final List<Widget>? actions;

  @override
  Size get preferredSize => const Size.fromHeight(60);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = context.colors;
    final sub = subtitle ?? ShellScope.maybeOf(context)?.projectName;
    return AppBar(
      toolbarHeight: 60,
      leading: Builder(builder: (context) => shellLeading(context) ?? const BackButton()),
      automaticallyImplyLeading: false,
      titleSpacing: 0,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: t.titleMedium?.copyWith(fontSize: FontSize.lg, fontWeight: FontWeight.w400), maxLines: 1, overflow: TextOverflow.ellipsis),
          if (sub != null && sub.isNotEmpty)
            Text(sub, style: t.bodySmall?.copyWith(color: c.textFaint), maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
      actions: [...?actions, const SizedBox(width: Space.x1)],
    );
  }
}

/// 侧边栏。没打开项目时（[session] 为空）只有“项目”和“设置”。
class AppDrawer extends StatelessWidget {
  const AppDrawer({
    super.key,
    this.project,
    this.session,
    this.current,
    this.onDest,
    this.onNewConversation,
    this.onConversation,
    required this.onProjects,
    required this.onSettings,
  });

  final Project? project;
  final ProjectSession? session;
  final ShellDest? current;
  final void Function(ShellDest dest)? onDest;
  final VoidCallback? onNewConversation;
  final void Function(String id)? onConversation;
  final VoidCallback onProjects;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final s = session;
    final busy = s?.agentBusy ?? false;
    return Drawer(
      width: 304,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 工作区切换
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.x3, Space.x3, Space.x3, Space.x2),
              child: Material(
                color: c.surfaceMuted,
                borderRadius: BorderRadius.circular(Radii.md),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onProjects,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(Space.x3, Space.x3, Space.x2, Space.x3),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(project?.name ?? 'LopiCode', style: t.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 2),
                              Text(project == null ? '还没打开工作区' : '切换工作区 · ${project!.displayDir}', style: t.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                            ],
                          ),
                        ),
                        Icon(Icons.unfold_more, size: 20, color: c.textFaint),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(Space.x3, Space.x1, Space.x3, Space.x2),
                children: [
                  if (s == null)
                    _DrawerItem(icon: Icons.folder_copy_outlined, label: '工作区', selected: true, onTap: () => Navigator.pop(context))
                  else ...[
                    for (final d in ShellDest.values.skip(1))
                      _DrawerItem(icon: d.icon, label: d.label, selected: current == d, onTap: () => onDest?.call(d)),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(Space.x3, Space.x6, Space.x3, Space.x2),
                      child: Text('对话', style: t.labelMedium),
                    ),
                    // 当前对话还是空的时候，“新对话”这一项就代表它，不另外列一行。
                    _DrawerItem(
                      icon: Icons.add_comment_outlined,
                      label: '新对话',
                      selected: current == ShellDest.chat && s.activeConversation.title.isEmpty,
                      enabled: !busy,
                      onTap: onNewConversation,
                    ),
                    for (final conv in s.topConversations)
                      if (conv.title.isNotEmpty)
                        _DrawerItem(
                          icon: conv.auto ? Icons.event_repeat : Icons.chat_bubble_outline,
                          label: conv.title,
                          selected: current == ShellDest.chat && conv.id == s.activeConversationId,
                          enabled: !busy || conv.id == s.activeConversationId,
                          onTap: () => onConversation?.call(conv.id),
                        ),
                  ],
                ],
              ),
            ),
            Divider(color: c.border),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.x3, vertical: Space.x2),
              child: _DrawerItem(icon: Icons.settings_outlined, label: '设置', selected: false, onTap: onSettings),
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  const _DrawerItem({required this.icon, required this.label, required this.selected, required this.onTap, this.enabled = true});
  final IconData icon;
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final fg = !enabled ? c.textFaint : (selected ? c.accent : c.text);
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? c.accentSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(Radii.md),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.x3, vertical: Space.x3),
            child: Row(
              children: [
                Icon(icon, size: 20, color: selected ? c.accent : (enabled ? c.textMuted : c.textFaint)),
                const SizedBox(width: Space.x3),
                Expanded(
                  child: Text(
                    label,
                    style: t.bodyMedium?.copyWith(color: fg, fontWeight: selected ? FontWeight.w600 : FontWeight.w400),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
