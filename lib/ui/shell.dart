// 设计约束（外壳 · 390×844）— 2026-11-23 按霜霜的参考图改版
// - 底部导航五项、图标配短标签：聊天、文件、终端、搭建、打包。选中 = 强调色实心，未选中 = 弱化描边。
//   键盘弹出时导航留在键盘下面，不会被顶起来（外层 Scaffold 负责，见 project_shell.dart）。
// - 侧边栏（左上汉堡按钮打开；形式是把主界面向右推开，见 push_drawer.dart）只放底部导航里没有的东西：工作区切换在最上，然后是预览、运行环境、对话列表，设置钉在最下。
// - 每个页面的顶部是同一个样子：左边悬浮的白色圆按钮（汉堡 / 返回），标题居中，右边是这一页自己的操作（白色胶囊）。
// - 侧边栏里当前所在的那一项高亮（强调色浅底 + 强调色文字），其余是普通文字。
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/chrome.dart';
import 'package:lopicode/ui/push_drawer.dart';
import 'package:material_ui/material_ui.dart';

/// 项目里能去的页面。前五个在底部导航里，其余在侧边栏里。
enum ShellDest {
  chat('Agent 聊天', Icons.chat_bubble_outline, Icons.chat_bubble),
  files('文件', Icons.folder_outlined, Icons.folder),
  terminal('终端', Icons.terminal, Icons.terminal),
  builder('低代码', Icons.dashboard_customize_outlined, Icons.dashboard_customize),
  apk('打包', Icons.inventory_2_outlined, Icons.inventory_2),
  preview('预览', Icons.play_circle_outline, Icons.play_circle),
  runtime('运行环境', Icons.memory_outlined, Icons.memory);

  const ShellDest(this.label, this.icon, this.selectedIcon);
  final String label;
  final IconData icon;
  final IconData selectedIcon;

  /// 底部导航里的五项。
  static const List<ShellDest> bottom = [chat, files, terminal, builder, apk];

  /// 只在侧边栏里的页面。
  static const List<ShellDest> drawerOnly = [preview, runtime];

  bool get inBottomNav => index < 5;
}

/// 底部导航的五个图标（终端的那个是自己画的，才有成对的描边 / 实心）。
List<BottomNavItem> shellNavItems() => [
  for (final d in ShellDest.bottom)
    BottomNavItem(
      label: switch (d) {
        ShellDest.chat => '聊天',
        ShellDest.builder => '搭建',
        _ => d.label,
      },
      icon: d == ShellDest.terminal ? const TerminalGlyph(filled: false) : Icon(d.icon),
      selectedIcon: d == ShellDest.terminal ? const TerminalGlyph(filled: true) : Icon(d.selectedIcon),
    ),
];

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
  if (Navigator.canPop(context)) {
    return RoundIconButton(icon: Icons.arrow_back_ios_new_rounded, tooltip: '返回', onPressed: () => Navigator.maybePop(context));
  }
  final drawer = PushDrawerScope.maybeOf(context);
  if (drawer != null) return _MenuButton(onPressed: drawer.open);
  return null;
}

class _MenuButton extends StatelessWidget {
  const _MenuButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => RoundIconButton(tooltip: '打开侧边栏', icon: Icons.drag_handle_rounded, onPressed: onPressed);
}

/// 统一的顶部：左圆按钮（汉堡 / 返回）+ 居中的两行标题 + 这一页的操作。
class ShellAppBar extends StatelessWidget implements PreferredSizeWidget {
  const ShellAppBar({super.key, required this.title, this.subtitle, this.actions, this.fade = false, this.background, this.pill = false});
  final String title;
  final String? subtitle;
  final List<Widget>? actions;

  /// 内容从顶栏下面滚过去并渐隐（对话页）。
  final bool fade;
  final Color? background;

  /// 标题装进一个白色小胶囊（对话页，对应参考图顶部正中的名字胶囊）。
  final bool pill;

  @override
  Size get preferredSize => const Size.fromHeight(PageBar.kHeight);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = context.colors;
    final sub = subtitle ?? ShellScope.maybeOf(context)?.projectName;
    Widget middle = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: (pill ? t.titleSmall : t.titleLarge)?.copyWith(fontWeight: pill ? FontWeight.w600 : FontWeight.w400),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (sub != null && sub.isNotEmpty)
          Text(
            sub,
            style: t.bodySmall?.copyWith(color: c.textFaint, height: 1.25),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
      ],
    );
    if (pill) {
      middle = Container(
        height: RoundIconButton.kSize,
        padding: const EdgeInsets.symmetric(horizontal: Space.x4),
        decoration: floatingDecoration(c, radius: BorderRadius.circular(RoundIconButton.kSize / 2)),
        child: Center(widthFactor: 1, child: middle),
      );
    }
    return PageBar(
      leading: Builder(builder: (context) => shellLeading(context) ?? const SizedBox.shrink()),
      title: middle,
      actions: actions,
      fade: fade,
      background: background,
    );
  }
}

/// 侧边栏。没打开项目时（[session] 为空）只有“项目”和“设置”。
class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key, this.project, this.session, this.current, this.onDest, this.onNewConversation, this.onConversation, this.onClose, required this.onProjects, required this.onSettings});

  final Project? project;
  final ProjectSession? session;
  final ShellDest? current;
  final void Function(ShellDest dest)? onDest;
  final VoidCallback? onNewConversation;
  final void Function(String id)? onConversation;
  final VoidCallback onProjects;
  final VoidCallback onSettings;

  /// 只收起侧边栏（没打开工作区时点“工作区”那一项）。
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final s = session;
    final busy = s?.agentBusy ?? false;
    // 平铺在主界面底下的一整块（见 push_drawer.dart），没有阴影、没有圆角。
    return Material(
      color: c.bg,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 工作区切换
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.x3, Space.x3, Space.x3, Space.x2),
              child: Material(
                color: c.surfaceMuted,
                borderRadius: BorderRadius.circular(Radii.bubble),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onProjects,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(Space.x4, Space.x3, Space.x3, Space.x3),
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
                    _DrawerItem(icon: Icons.folder_copy_outlined, label: '工作区', selected: true, onTap: onClose)
                  else ...[
                    for (final d in ShellDest.drawerOnly) _DrawerItem(icon: d.icon, label: d.label, selected: current == d, onTap: () => onDest?.call(d)),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(Space.x3, Space.x6, Space.x3, Space.x2),
                      child: Text('对话', style: t.labelMedium),
                    ),
                    // 当前对话还是空的时候，“新对话”这一项就代表它，不另外列一行。
                    _DrawerItem(icon: Icons.add_comment_outlined, label: '新对话', selected: current == ShellDest.chat && s.activeConversation.title.isEmpty, enabled: !busy, onTap: onNewConversation),
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
        borderRadius: BorderRadius.circular(Radii.lg),
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
