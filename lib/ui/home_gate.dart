// 应用打开后先到哪：
// - 上次开着某个项目 → 直接回到那个项目的对话页。
// - 没有（第一次用、或那个项目删了）→ 项目列表（没有项目时就是空状态 + “新建项目”）。
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/stores.dart';
import 'package:lopicode/ui/app_ref.dart';
import 'package:lopicode/ui/project_list_screen.dart';
import 'package:lopicode/ui/project_shell.dart';
import 'package:material_ui/material_ui.dart';

class HomeGate extends StatefulWidget {
  const HomeGate({super.key});

  @override
  State<HomeGate> createState() => _HomeGateState();
}

class _HomeGateState extends State<HomeGate> {
  bool _loaded = false;
  Project? _project;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) _restore();
  }

  Future<void> _restore() async {
    final app = appOf(context);
    final last = app.settings.getString(SettingKeys.lastProject);
    Project? found;
    if (last.isNotEmpty) {
      try {
        found = (await app.projects.list()).where((p) => p.id == last).firstOrNull;
      } on Exception {
        found = null;
      }
    }
    if (mounted) {
      setState(() {
        _project = found;
        _loaded = true;
      });
    }
  }

  void _open(Project? project) {
    appOf(context).settings.set(SettingKeys.lastProject, project?.id);
    setState(() => _project = project);
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final project = _project;
    if (project == null) return ProjectListScreen(onOpen: _open);
    return ProjectShell(key: ValueKey(project.id), project: project, onSwitchProject: _open);
  }
}
