// 设计约束（项目内 · 390×844）
// - 底部五个页签对应她要的几件事：文件（写代码）· Agent · 终端 · 预览 · 工具（低代码、APK 打包、项目设置）。
// - 顶栏只放项目名和返回；每个页签自己的操作放在页签内部，不往顶栏堆。
// - 切页签不丢状态：五个页签共用一个 ProjectSession，用 IndexedStack 保活。
import 'package:lopicode/app_services.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/ui/agent_tab.dart';
import 'package:lopicode/ui/files_tab.dart';
import 'package:lopicode/ui/preview_tab.dart';
import 'package:lopicode/ui/terminal_tab.dart';
import 'package:lopicode/ui/tools_tab.dart';
import 'package:material_ui/material_ui.dart';

class ProjectShell extends StatefulWidget {
  const ProjectShell({super.key, required this.project, this.initialTab = 0, this.session});
  final Project project;
  final int initialTab;

  /// 测试 / 截图用：注入预先准备好的会话。
  final ProjectSession? session;

  @override
  State<ProjectShell> createState() => _ProjectShellState();
}

class _ProjectShellState extends State<ProjectShell> {
  ProjectSession? _session;
  late int _tab = widget.initialTab;
  final Set<int> _visited = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _session ??= widget.session ?? ProjectSession(AppScope.of(context), widget.project);
    _visited.add(_tab);
  }

  @override
  void dispose() {
    if (widget.session == null) _session?.dispose();
    super.dispose();
  }

  void _go(int tab) => setState(() {
    _tab = tab;
    _visited.add(tab);
  });

  @override
  Widget build(BuildContext context) {
    final session = _session!;
    // 没打开过的页签先不建（预览的 WebView、终端的 shell 都是用到才启动）。
    Widget lazy(int i, Widget Function() build) => _visited.contains(i) ? build() : const SizedBox.shrink();
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Text(widget.project.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: IndexedStack(
        index: _tab,
        children: [
          lazy(0, () => FilesTab(session: session)),
          lazy(1, () => AgentTab(session: session)),
          lazy(2, () => TerminalTab(session: session)),
          lazy(3, () => PreviewTab(session: session, active: _tab == 3)),
          lazy(4, () => ToolsTab(session: session, onOpenPreview: () => _go(3))),
        ],
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(border: Border(top: BorderSide(color: Theme.of(context).dividerTheme.color!))),
        child: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: _go,
          destinations: const [
            NavigationDestination(icon: Icon(Icons.folder_outlined), selectedIcon: Icon(Icons.folder), label: '文件'),
            NavigationDestination(icon: Icon(Icons.auto_awesome_outlined), selectedIcon: Icon(Icons.auto_awesome), label: 'Agent'),
            NavigationDestination(icon: Icon(Icons.terminal), label: '终端'),
            NavigationDestination(icon: Icon(Icons.play_circle_outline), selectedIcon: Icon(Icons.play_circle), label: '预览'),
            NavigationDestination(icon: Icon(Icons.handyman_outlined), selectedIcon: Icon(Icons.handyman), label: '工具'),
          ],
        ),
      ),
    );
  }
}
