// 设计约束（项目外壳 · 390×844）— 2026-11-23 按霜霜的参考图改版
// - 进项目先看到的是 Agent 聊天；底部导航五项（聊天、文件、终端、搭建、打包，带短标签），预览和运行环境从侧边栏去。
// - 底部导航钉在屏幕最底部（pinned_nav_layout.dart）：五个页面一律不隐藏、不被键盘顶起，键盘直接盖在它上面；
//   页面内容的底边跟着键盘上沿走（聊天输入栏、终端按键行、编辑器都贴着键盘），键盘收起后回到导航上方。
// - 侧边栏是“把主界面向右推开”的形式（push_drawer.dart），从左边缘右滑也能拉出来；终端和低代码画布上自己有横向手势，那两页只能点汉堡按钮。
// - 切页面不丢状态：各页共用一个 ProjectSession，用 IndexedStack 保活；没去过的页面先不建。
// - 系统返回键：侧边栏开着先关它；不在聊天页时先回聊天页，在聊天页才退出。
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lopicode/backdrop/backdrop_model.dart';
import 'package:lopicode/build/build_screen.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/runtime/runtime_screen.dart';
import 'package:lopicode/state/workspace_chat.dart';
import 'package:lopicode/state/workspace_conversations.dart';
import 'package:lopicode/ui/app_backdrop.dart';
import 'package:lopicode/ui/app_ref.dart';
import 'package:lopicode/ui/builder_hub_screen.dart';
import 'package:lopicode/ui/chat_screen.dart';
import 'package:lopicode/ui/chrome.dart';
import 'package:lopicode/ui/favorites_screen.dart';
import 'package:lopicode/ui/files_tab.dart';
import 'package:lopicode/ui/pinned_nav_layout.dart';
import 'package:lopicode/ui/preview_tab.dart';
import 'package:lopicode/ui/project_list_screen.dart';
import 'package:lopicode/ui/push_drawer.dart';
import 'package:lopicode/ui/settings_screen.dart';
import 'package:lopicode/ui/shell.dart';
import 'package:lopicode/ui/terminal_tab.dart';
import 'package:material_ui/material_ui.dart';

class ProjectShell extends ConsumerStatefulWidget {
  const ProjectShell({super.key, required this.project, this.initial = ShellDest.chat, this.session, this.onSwitchProject});
  final Project project;
  final ShellDest initial;

  /// 测试 / 截图用：注入预先准备好的会话。
  final ProjectSession? session;

  /// 在项目列表里选了别的项目（或当前项目被删了，传 null）。
  final void Function(Project? project)? onSwitchProject;

  @override
  ConsumerState<ProjectShell> createState() => _ProjectShellState();
}

class _ProjectShellState extends ConsumerState<ProjectShell> {
  final _drawer = PushDrawerController();
  ProjectSession? _session;
  late ShellDest _dest = widget.initial;
  final Set<ShellDest> _visited = {};
  int _builderEpoch = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_session == null) {
      _session = widget.session ?? ProjectSession(appOf(context), widget.project);
      final app = appOf(context);
      _session!.loadChat().then((_) {
        if (app.newConversationFor == widget.project.id) {
          app.newConversationFor = null;
          _session?.newConversation();
        }
      });
      appOf(context).scheduler.liveSessions[widget.project.id] = _session!;
    }
    _visited.add(_dest);
  }

  @override
  void dispose() {
    final live = _session?.app.scheduler.liveSessions;
    if (live != null && identical(live[widget.project.id], _session)) live.remove(widget.project.id);
    if (widget.session == null) _session?.dispose();
    _drawer.dispose();
    super.dispose();
  }

  void _onSession() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _drawer.addListener(_onSession); // 开合变了要重算“返回键先做什么”
  }

  void _go(ShellDest dest) => setState(() {
    // 低代码页每次进去都重新读文件：Agent 可能刚改过页面。
    if (dest == ShellDest.builder && _dest != ShellDest.builder) _builderEpoch++;
    _dest = dest;
    _visited.add(dest);
  });

  void _closeDrawer() => _drawer.close();

  Future<void> _openProjects() async {
    _closeDrawer();
    final picked = await Navigator.of(context).push<Project>(MaterialPageRoute(builder: (_) => ProjectListScreen(currentProjectId: widget.project.id)));
    if (!mounted) return;
    if (picked != null && picked.id != widget.project.id) {
      widget.onSwitchProject?.call(picked);
    } else if (!Directory(widget.project.dir).existsSync()) {
      widget.onSwitchProject?.call(null); // 当前项目在列表里被删了
    } else {
      final app = appOf(context);
      if (app.newConversationFor == widget.project.id) {
        app.newConversationFor = null;
        await _session?.newConversation();
        _go(ShellDest.chat);
      }
      // 当前工作区被从列表移除了：回到工作区列表。
      final still = (await app.projects.list()).any((p) => p.id == widget.project.id);
      if (!mounted) return;
      if (!still) {
        widget.onSwitchProject?.call(null);
      } else {
        setState(() {}); // 可能改了名
      }
    }
  }

  void _openSettings() {
    _closeDrawer();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsScreen(workspace: widget.project, session: _session),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = _session!;
    // 顶栏标题、侧边栏的对话列表、当前对话忙不忙：变了就重画
    ref.watch(conversationsProvider(session));
    ref.watch(activeChatProvider(session).select((v) => v.busy));
    Widget lazy(ShellDest d, Widget Function() build) => _visited.contains(d) ? build() : const SizedBox.shrink();
    // 文件、终端、预览的正文不是能滚的一列（页签条 + 编辑器 / 终端 / 网页）：整块摆在悬浮顶栏下沿之下，不钻到按钮下面。
    Widget page(ShellDest d, Widget body) => AppBackdrop(
      area: BackdropArea.pages,
      builder: (context, on) => Scaffold(
        backgroundColor: on ? Colors.transparent : null,
        extendBodyBehindAppBar: true,
        appBar: ShellAppBar(title: d.label),
        body: body,
      ),
    );
    Widget build1(ShellDest d) => switch (d) {
      ShellDest.chat => ChatScreen(session: session),
      ShellDest.files => page(d, BelowBar(child: FilesTab(session: session))),
      ShellDest.terminal => page(d, BelowBar(child: TerminalTab(session: session))),
      ShellDest.builder => BuilderHubScreen(key: ValueKey(_builderEpoch), session: session),
      ShellDest.apk => BuildScreen(session: session),
      ShellDest.preview => page(
        d,
        BelowBar(
          child: PreviewTab(session: session, active: _dest == ShellDest.preview),
        ),
      ),
      ShellDest.runtime => RuntimeScreen(projectDir: session.project.dir),
    };
    return ShellScope(
      openDrawer: _drawer.open,
      go: _go,
      projectName: widget.project.name,
      child: PopScope(
        // 返回键：侧边栏开着先关它；不在聊天页先回聊天页；都不是才退出。
        canPop: _dest == ShellDest.chat && !_drawer.isOpen,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          if (_drawer.isOpen) {
            _closeDrawer();
          } else {
            _go(ShellDest.chat);
          }
        },
        child: PushDrawer(
          controller: _drawer,
          handleBack: false,
          // 终端里要左右滑光标、画布上要拖组件：这两页不让边缘右滑抢手势。
          edgeDragEnabled: _dest != ShellDest.terminal && _dest != ShellDest.builder,
          drawer: AppDrawer(
            project: widget.project,
            session: session,
            current: _dest,
            onClose: _closeDrawer,
            onDest: (d) {
              _closeDrawer();
              _go(d);
            },
            onNewConversation: () async {
              _closeDrawer();
              await session.newConversation();
              _go(ShellDest.chat);
            },
            onConversation: (id) async {
              _closeDrawer();
              await session.selectConversation(id);
              _go(ShellDest.chat);
            },
            onFavorites: () {
              _closeDrawer();
              openFavorites(context, session, goChat: () => _go(ShellDest.chat));
            },
            onProjects: _openProjects,
            onSettings: _openSettings,
          ),
          // 底部导航和页面在同一层里，所以会跟着主界面一起被推走；导航钉在屏幕底，键盘盖在它上面（pinned_nav_layout.dart）。
          child: PinnedNavLayout(
            navHeight: IconBottomNav.kHeight,
            nav: IconBottomNav(items: shellNavItems(), current: _dest.inBottomNav ? _dest.index : -1, onTap: (i) => _go(ShellDest.bottom[i])),
            body: IndexedStack(index: _dest.index, children: [for (final d in ShellDest.values) lazy(d, () => build1(d))]),
          ),
        ),
      ),
    );
  }
}
