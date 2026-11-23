// 设计约束（项目列表 · 390×844）
// - 这一页只回答一个问题：“我要打开哪个项目”。主操作只有“新建项目”。
// - 每行一个项目：名字（强）＋ 模板和创建日期（弱）；改名 / 删除收进行尾菜单。
// - 顶栏和别的页面一样：没打开项目时左边是汉堡按钮（侧边栏里有“设置”）；从项目里进来切换时是返回箭头。
// - 当前开着的项目在列表里标出来。
// - 没有项目时给真正的空状态和同一个主操作，不放假数据。
import 'package:lopicode/app_services.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/shell.dart';
import 'package:lopicode/ui/settings_screen.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';

IconData templateIcon(ProjectTemplate t) => switch (t) {
  ProjectTemplate.empty => Icons.folder_outlined,
  ProjectTemplate.web => Icons.language,
  ProjectTemplate.lowcode => Icons.dashboard_customize_outlined,
};

class ProjectListScreen extends StatefulWidget {
  const ProjectListScreen({super.key, this.onOpen, this.currentProjectId});

  /// 作为首页时：选中 / 新建项目后交给上层打开。为空表示是从项目里推进来的，选中后带着项目返回。
  final void Function(Project project)? onOpen;

  /// 从项目里进来切换时，当前开着的是哪个。
  final String? currentProjectId;

  @override
  State<ProjectListScreen> createState() => _ProjectListScreenState();
}

class _ProjectListScreenState extends State<ProjectListScreen> {
  List<Project>? _projects;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_projects == null && _error == null) _reload();
  }

  Future<void> _reload() async {
    try {
      final list = await AppScope.of(context).projects.list();
      if (mounted) setState(() => _projects = list);
    } on Exception catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _create() async {
    final store = AppScope.of(context).projects;
    final result = await showModalBottomSheet<(String, ProjectTemplate)>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _NewProjectSheet(),
    );
    if (result == null || !mounted) return;
    try {
      final project = await store.create(result.$1, result.$2);
      await _reload();
      if (mounted) _open(project);
    } on ProjectException catch (e) {
      if (mounted) showSnack(context, e.message);
    }
  }

  void _open(Project project) {
    final onOpen = widget.onOpen;
    if (onOpen != null) {
      onOpen(project);
    } else {
      Navigator.of(context).pop(project);
    }
  }

  Future<void> _rename(Project project) async {
    final store = AppScope.of(context).projects;
    final name = await promptDialog(context, title: '重命名项目', initial: project.name, confirmLabel: '保存');
    if (name == null || !mounted) return;
    try {
      await store.rename(project, name);
      await _reload();
    } on ProjectException catch (e) {
      if (mounted) showSnack(context, e.message);
    }
  }

  Future<void> _delete(Project project) async {
    final store = AppScope.of(context).projects;
    final ok = await confirmDialog(
      context,
      title: '删除“${project.name}”？',
      message: '项目里的所有文件和对话记录都会被删除，无法恢复。',
      confirmLabel: '删除',
      danger: true,
    );
    if (!ok) return;
    await store.delete(project);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final projects = _projects;
    return Scaffold(
      appBar: ShellAppBar(title: '项目', subtitle: projects == null || projects.isEmpty ? 'LopiCode' : '${projects.length} 个项目'),
      drawer: widget.onOpen == null
          ? null
          : AppDrawer(
              onProjects: () => Navigator.pop(context),
              onSettings: () {
                Navigator.pop(context);
                Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
              },
            ),
      floatingActionButton: projects != null && projects.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: _create,
              elevation: 2,
              shape: const StadiumBorder(),
              icon: const Icon(Icons.add),
              label: const Text('新建项目'),
            )
          : null,
      body: _error != null
          ? EmptyState(icon: Icons.error_outline, title: '读取项目失败', message: _error!)
          : projects == null
          ? const Center(child: CircularProgressIndicator())
          : projects.isEmpty
          ? EmptyState(
              icon: Icons.rocket_launch_outlined,
              title: '还没有项目',
              message: '新建一个项目，然后让 Agent 帮你写代码、\n拖拽搭页面、实时预览。',
              action: FilledButton.icon(onPressed: _create, icon: const Icon(Icons.add), label: const Text('新建项目')),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(Space.x4, Space.x2, Space.x4, 96),
              itemCount: projects.length,
              separatorBuilder: (_, _) => const SizedBox(height: Space.x3),
              itemBuilder: (context, i) => _ProjectCard(
                project: projects[i],
                current: projects[i].id == widget.currentProjectId,
                onOpen: () => _open(projects[i]),
                onRename: () => _rename(projects[i]),
                onDelete: () => _delete(projects[i]),
              ),
            ),
    );
  }
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({required this.project, required this.current, required this.onOpen, required this.onRename, required this.onDelete});
  final Project project;
  final bool current;
  final VoidCallback onOpen;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final d = project.createdAt;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.x4, Space.x3, Space.x1, Space.x3),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: c.accentSoft, borderRadius: BorderRadius.circular(Radii.md)),
                child: Icon(templateIcon(project.template), color: c.accent, size: 22),
              ),
              const SizedBox(width: Space.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(project.name, style: t.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(
                      '${current ? '当前项目 · ' : ''}${project.template.label} · ${d.year}-${_pad2(d.month)}-${_pad2(d.day)}',
                      style: t.bodySmall?.copyWith(color: current ? c.accent : null),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: '更多',
                icon: Icon(Icons.more_vert, color: c.textFaint),
                onSelected: (v) => v == 'rename' ? onRename() : onDelete(),
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'rename', child: Text('重命名')),
                  PopupMenuItem(value: 'delete', child: Text('删除', style: TextStyle(color: c.danger))),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _pad2(int n) => n.toString().padLeft(2, '0');
}

class _NewProjectSheet extends StatefulWidget {
  const _NewProjectSheet();

  @override
  State<_NewProjectSheet> createState() => _NewProjectSheetState();
}

class _NewProjectSheetState extends State<_NewProjectSheet> {
  final _name = TextEditingController();
  ProjectTemplate _template = ProjectTemplate.web;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    Navigator.pop(context, (name.isEmpty ? '我的${_template.label}' : name, _template));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, MediaQuery.viewInsetsOf(context).bottom + Space.x4),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('新建项目', style: t.titleLarge),
            const SizedBox(height: Space.x4),
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: '项目名', hintText: '不填会用模板名'),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: Space.x4),
            Text('从模板开始', style: t.labelMedium),
            const SizedBox(height: Space.x2),
            for (final tpl in ProjectTemplate.values)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.x2),
                child: InkWell(
                  borderRadius: BorderRadius.circular(Radii.md),
                  onTap: () => setState(() => _template = tpl),
                  child: Container(
                    padding: const EdgeInsets.all(Space.x3),
                    decoration: BoxDecoration(
                      color: _template == tpl ? c.accentSoft : c.surface,
                      borderRadius: BorderRadius.circular(Radii.md),
                      border: Border.all(color: _template == tpl ? c.accentFill : c.border, width: _template == tpl ? 2 : 1),
                    ),
                    child: Row(
                      children: [
                        Icon(templateIcon(tpl), color: _template == tpl ? c.accent : c.textMuted),
                        const SizedBox(width: Space.x3),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(tpl.label, style: t.titleSmall),
                              Text(tpl.description, style: t.bodySmall),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            const SizedBox(height: Space.x2),
            FilledButton(onPressed: _submit, child: const Text('创建')),
          ],
        ),
      ),
    );
  }
}
