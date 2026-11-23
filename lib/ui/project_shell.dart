// 设计约束（项目外壳 · 390×844）— 2026-11-23 按霜霜的参考图改版
// - 进项目先看到的是 Agent 聊天；底部导航五项（聊天、文件、终端、低代码、打包），预览和运行环境从侧边栏去。
// - 底部导航挂在最外层 Scaffold 上：键盘弹出时，页面内容缩到键盘上方，导航原地不动（被键盘盖住），
//   所以贴着键盘的只有输入框 / 终端按键行，导航不会被顶起来。
// - 侧边栏从左边缘右滑也能拉出来；终端和低代码画布上自己有横向手势，那两页只能点汉堡按钮。
// - 切页面不丢状态：各页共用一个 ProjectSession，用 IndexedStack 保活；没去过的页面先不建。
// - 系统返回键：不在聊天页时先回聊天页，在聊天页才退出。
import 'package:lopicode/runtime/runtime_screen.dart';
import 'dart:io';

import 'package:lopicode/app_services.dart';
import 'package:lopicode/build/build_screen.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/lowcode/builder_screen.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/ui/chat_screen.dart';
import 'package:lopicode/ui/chrome.dart';
import 'package:lopicode/ui/files_tab.dart';
import 'package:lopicode/ui/preview_tab.dart';
import 'package:lopicode/ui/project_list_screen.dart';
import 'package:lopicode/ui/settings_screen.dart';
import 'package:lopicode/ui/shell.dart';
import 'package:lopicode/ui/terminal_tab.dart';
import 'package:material_ui/material_ui.dart';

class ProjectShell extends StatefulWidget {
  const ProjectShell({super.key, required this.project, this.initial = ShellDest.chat, this.session, this.onSwitchProject});
  final Project project;
  final ShellDest initial;

  /// 测试 / 截图用：注入预先准备好的会话。
  final ProjectSession? session;

  /// 在项目列表里选了别的项目（或当前项目被删了，传 null）。
  final void Function(Project? project)? onSwitchProject;

  @override
  State<ProjectShell> createState() => _ProjectShellState();
}

class _ProjectShellState extends State<ProjectShell> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  ProjectSession? _session;
  late ShellDest _dest = widget.initial;
  final Set<ShellDest> _visited = {};
  int _builderEpoch = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_session == null) {
      _session = widget.session ?? ProjectSession(AppScope.of(context), widget.project);
      _session!.addListener(_onSession);
      final app = AppScope.of(context);
      _session!.loadChat().then((_) {
        if (app.newConversationFor == widget.project.id) {
          app.newConversationFor = null;
          _session?.newConversation();
        }
      });
      AppScope.of(context).scheduler.liveSessions[widget.project.id] = _session!;
    }
    _visited.add(_dest);
  }

  @override
  void dispose() {
    _session?.removeListener(_onSession);
    final live = _session?.app.scheduler.liveSessions;
    if (live != null && identical(live[widget.project.id], _session)) live.remove(widget.project.id);
    if (widget.session == null) _session?.dispose();
    super.dispose();
  }

  void _onSession() {
    if (mounted) setState(() {});
  }

  void _go(ShellDest dest) => setState(() {
    // 低代码页每次进去都重新读文件：Agent 可能刚改过页面。
    if (dest == ShellDest.builder && _dest != ShellDest.builder) _builderEpoch++;
    _dest = dest;
    _visited.add(dest);
  });

  void _closeDrawer() => _scaffoldKey.currentState?.closeDrawer();

  Future<void> _openProjects() async {
    _closeDrawer();
    final picked = await Navigator.of(context).push<Project>(
      MaterialPageRoute(builder: (_) => ProjectListScreen(currentProjectId: widget.project.id)),
    );
    if (!mounted) return;
    if (picked != null && picked.id != widget.project.id) {
      widget.onSwitchProject?.call(picked);
    } else if (!Directory(widget.project.dir).existsSync()) {
      widget.onSwitchProject?.call(null); // 当前项目在列表里被删了
    } else {
      final app = AppScope.of(context);
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
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => SettingsScreen(workspace: widget.project)));
  }

  @override
  Widget build(BuildContext context) {
    final session = _session!;
    Widget lazy(ShellDest d, Widget Function() build) => _visited.contains(d) ? build() : const SizedBox.shrink();
    Widget page(ShellDest d, Widget body) => Scaffold(appBar: ShellAppBar(title: d.label), body: body);
    Widget build1(ShellDest d) => switch (d) {
      ShellDest.chat => ChatScreen(session: session),
      ShellDest.files => page(d, FilesTab(session: session)),
      ShellDest.terminal => page(d, TerminalTab(session: session)),
      ShellDest.builder => BuilderScreen(key: ValueKey(_builderEpoch), session: session),
      ShellDest.apk => BuildScreen(session: session),
      ShellDest.preview => page(d, PreviewTab(session: session, active: _dest == ShellDest.preview)),
      ShellDest.runtime => RuntimeScreen(projectDir: session.project.dir),
    };
    return ShellScope(
      openDrawer: () => _scaffoldKey.currentState?.openDrawer(),
      go: _go,
      projectName: widget.project.name,
      child: Scaffold(
        key: _scaffoldKey,
        // 终端里要左右滑光标、画布上要拖组件：这两页不让边缘右滑抢手势。
        drawerEnableOpenDragGesture: _dest != ShellDest.terminal && _dest != ShellDest.builder,
        drawerEdgeDragWidth: 24,
        drawer: AppDrawer(
          project: widget.project,
          session: session,
          current: _dest,
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
          onProjects: _openProjects,
          onSettings: _openSettings,
        ),
        bottomNavigationBar: IconBottomNav(
          items: shellNavItems(),
          current: _dest.inBottomNav ? _dest.index : -1,
          onTap: (i) => _go(ShellDest.bottom[i]),
        ),
        body: PopScope(
          canPop: _dest == ShellDest.chat,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _go(ShellDest.chat);
          },
          child: IndexedStack(
            index: _dest.index,
            children: [for (final d in ShellDest.values) lazy(d, () => build1(d))],
          ),
        ),
      ),
    );
  }
}
