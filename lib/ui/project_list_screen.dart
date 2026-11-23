// 设计约束（工作区列表 · 390×844）
// - 这一页只回答一个问题：“我要打开哪个工作区”。主操作只有“添加工作区”。
// - 工作区＝一个目录：应用目录里的项目，或 Ubuntu 环境里的任意目录（如 /root/myapp）。
// - 每行一个工作区：名字（强）＋ 目录和对话数（弱）；置顶、分组、重命名、在这里新建对话、移除、删除都收进行尾菜单。
// - 置顶的排最前；有分组时按分组分段，没分组的在最上面。
// - 顶栏和别的页面一样：没打开工作区时左边是汉堡按钮；从工作区里进来切换时是返回箭头。
// - “移除”只是从列表去掉，文件不动；“删除”才会删文件，而且只对应用目录里的项目开放。
// - 没有工作区时给真正的空状态和同一个主操作，不放假数据。
import 'package:lopicode/app_services.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/templates.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/settings_screen.dart';
import 'package:lopicode/ui/shell.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';

IconData templateIcon(ProjectTemplate t) => switch (t) {
  ProjectTemplate.empty => Icons.folder_outlined,
  ProjectTemplate.web => Icons.language,
  ProjectTemplate.lowcode => Icons.dashboard_customize_outlined,
};

class ProjectListScreen extends StatefulWidget {
  const ProjectListScreen({super.key, this.onOpen, this.currentProjectId});

  /// 作为首页时：选中 / 新建工作区后交给上层打开。为空表示是从工作区里推进来的，选中后带着它返回。
  final void Function(Project project)? onOpen;

  /// 从工作区里进来切换时，当前开着的是哪个。
  final String? currentProjectId;

  @override
  State<ProjectListScreen> createState() => _ProjectListScreenState();
}

class _ProjectListScreenState extends State<ProjectListScreen> {
  List<Project>? _projects;
  List<Project> _hidden = const [];
  Map<String, int> _counts = {};
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_projects == null && _error == null) _reload();
  }

  Future<void> _reload() async {
    try {
      final store = AppScope.of(context).projects;
      final list = await store.list();
      final hidden = await store.list(hidden: true);
      final counts = {for (final p in list) p.id: await ProjectStore.conversationCount(p)};
      if (mounted) {
        setState(() {
          _projects = list;
          _hidden = hidden;
          _counts = counts;
        });
      }
    } on Exception catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } on ProjectException catch (e) {
      if (mounted) showSnack(context, e.message);
    }
    await _reload();
  }

  Future<void> _add() async {
    final choice = await showModalBottomSheet<String>(context: context, builder: (_) => _AddSheet(hasHidden: _hidden.isNotEmpty));
    if (choice == null || !mounted) return;
    if (choice == 'new') await _create();
    if (choice == 'linux') await _addLinux();
    if (choice == 'restore') await _restore();
  }

  Future<void> _create() async {
    final store = AppScope.of(context).projects;
    final result = await showModalBottomSheet<(String, ProjectTemplate)>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _NewProjectSheet(),
    );
    if (result == null || !mounted) return;
    await _guard(() async {
      final project = await store.create(result.$1, result.$2);
      await _reload();
      if (mounted) _open(project);
    });
  }

  Future<void> _addLinux() async {
    final store = AppScope.of(context).projects;
    final path = await promptDialog(context, title: '添加 Ubuntu 里的目录', hint: '完整路径，如 /root/myapp', confirmLabel: '添加');
    if (path == null || path.trim().isEmpty || !mounted) return;
    await _guard(() async {
      final project = await store.addLinux(path);
      await _reload();
      if (mounted) _open(project);
    });
  }

  Future<void> _restore() async {
    final store = AppScope.of(context).projects;
    final picked = await showModalBottomSheet<Project>(
      context: context,
      builder: (context) => SafeArea(
        top: false,
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x2),
              child: Text('加回已移除的项目', style: Theme.of(context).textTheme.titleLarge),
            ),
            for (final p in _hidden)
              ListTile(leading: Icon(templateIcon(p.template)), title: Text(p.name), subtitle: Text(p.displayDir), onTap: () => Navigator.pop(context, p)),
          ],
        ),
      ),
    );
    if (picked != null) await _guard(() => store.restoreToList(picked));
  }

  void _open(Project project, {bool newConversation = false}) {
    if (newConversation) AppScope.of(context).newConversationFor = project.id;
    final onOpen = widget.onOpen;
    if (onOpen != null) {
      onOpen(project);
    } else {
      Navigator.of(context).pop(project);
    }
  }

  Future<void> _rename(Project project) async {
    final store = AppScope.of(context).projects;
    final name = await promptDialog(context, title: '重命名工作区', initial: project.name, confirmLabel: '保存');
    if (name == null || !mounted) return;
    await _guard(() => store.rename(project, name));
  }

  Future<void> _group(Project project) async {
    final store = AppScope.of(context).projects;
    final name = await promptDialog(context, title: '放进哪个分组', initial: project.group, hint: '分组名；留空＝不分组', confirmLabel: '保存');
    if (name == null || !mounted) return;
    await _guard(() => store.setGroup(project, name));
  }

  Future<void> _remove(Project project) async {
    final store = AppScope.of(context).projects;
    final ok = await confirmDialog(
      context,
      title: '把“${project.name}”从列表移除？',
      message: project.isLinux ? '只是从列表里去掉，${project.linuxPath} 里的文件和对话记录都还在。以后可以用同一个路径再加回来。' : '只是从列表里去掉，文件和对话记录都还在。以后可以在“添加工作区 → 加回已移除的项目”里找回来。',
      confirmLabel: '移除',
    );
    if (ok) await _guard(() => store.removeFromList(project));
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
    if (ok) await _guard(() => store.delete(project));
  }

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context).projects;
    final projects = _projects;
    final groups = <String>[
      if (projects != null && projects.any((p) => p.group.isEmpty)) '',
      ...{
        for (final p in projects ?? const <Project>[])
          if (p.group.isNotEmpty) p.group,
      }.toList()..sort(),
    ];
    return Scaffold(
      appBar: ShellAppBar(title: '工作区', subtitle: projects == null || projects.isEmpty ? 'LopiCode' : '${projects.length} 个工作区'),
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
              onPressed: _add,
              elevation: 2,
              shape: const StadiumBorder(),
              icon: const Icon(Icons.add),
              label: const Text('添加工作区'),
            )
          : null,
      body: _error != null
          ? EmptyState(icon: Icons.error_outline, title: '读取工作区失败', message: _error!)
          : projects == null
          ? const Center(child: CircularProgressIndicator())
          : projects.isEmpty
          ? EmptyState(
              icon: Icons.rocket_launch_outlined,
              title: '还没有工作区',
              message: '工作区就是一个放代码的目录。添加一个，\n然后让 Agent 帮你写代码、拖拽搭页面、实时预览。',
              action: FilledButton.icon(onPressed: _add, icon: const Icon(Icons.add), label: const Text('添加工作区')),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(Space.x4, Space.x2, Space.x4, 96),
              children: [
                for (final g in groups) ...[
                  if (g.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(0, Space.x4, 0, Space.x2),
                      child: Text(g, style: Theme.of(context).textTheme.labelMedium),
                    ),
                  for (final p in projects.where((p) => p.group == g))
                    Padding(
                      padding: const EdgeInsets.only(bottom: Space.x3),
                      child: _ProjectCard(
                        project: p,
                        count: _counts[p.id] ?? 0,
                        current: p.id == widget.currentProjectId,
                        onOpen: () => _open(p),
                        onAction: (v) {
                          switch (v) {
                            case 'chat':
                              _open(p, newConversation: true);
                            case 'pin':
                              _guard(() => store.setPinned(p, !p.pinned));
                            case 'group':
                              _group(p);
                            case 'rename':
                              _rename(p);
                            case 'remove':
                              _remove(p);
                            case 'delete':
                              _delete(p);
                          }
                        },
                      ),
                    ),
                ],
              ],
            ),
    );
  }
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({required this.project, required this.count, required this.current, required this.onOpen, required this.onAction});
  final Project project;
  final int count;
  final bool current;
  final VoidCallback onOpen;
  final void Function(String action) onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
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
                child: Icon(project.isLinux ? Icons.terminal : templateIcon(project.template), color: c.accent, size: 22),
              ),
              const SizedBox(width: Space.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(child: Text(project.name, style: t.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis)),
                        if (project.pinned)
                          Padding(
                            padding: const EdgeInsets.only(left: Space.x1),
                            child: Icon(Icons.push_pin, size: 14, color: c.accent, semanticLabel: '已置顶'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(project.displayDir, style: t.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(
                      '${current ? '当前工作区 · ' : ''}${project.isLinux ? 'Ubuntu 目录' : project.template.label} · ${count == 0 ? '还没有对话' : '$count 段对话'}',
                      style: t.bodySmall?.copyWith(color: current ? c.accent : null),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: '更多',
                icon: Icon(Icons.more_vert, color: c.textFaint),
                onSelected: onAction,
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'chat', child: Text('在这里新建对话')),
                  PopupMenuItem(value: 'pin', child: Text(project.pinned ? '取消置顶' : '置顶')),
                  const PopupMenuItem(value: 'group', child: Text('分组…')),
                  const PopupMenuItem(value: 'rename', child: Text('重命名')),
                  const PopupMenuItem(value: 'remove', child: Text('从列表移除')),
                  if (!project.isLinux) PopupMenuItem(value: 'delete', child: Text('删除', style: TextStyle(color: c.danger))),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddSheet extends StatelessWidget {
  const _AddSheet({required this.hasHidden});
  final bool hasHidden;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    Widget option(String value, IconData icon, String title, String subtitle) => ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle, style: t.bodySmall),
      onTap: () => Navigator.pop(context, value),
    );
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x2),
            child: Text('添加工作区', style: t.titleLarge),
          ),
          option('new', Icons.create_new_folder_outlined, '新建项目', '在应用目录里建一个新项目，可以从模板开始'),
          option('linux', Icons.terminal, 'Ubuntu 里的目录', '把运行环境里的某个目录当工作区，如 /root/myapp'),
          if (hasHidden) option('restore', Icons.restore, '加回已移除的项目', '以前从列表移除、文件还在的项目'),
          const SizedBox(height: Space.x2),
        ],
      ),
    );
  }
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
