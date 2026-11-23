// 设计约束（智能体团队 · 390×844）
// - 三栏：成员 / 任务 / 消息，用顶部标签切换，一栏只看一样东西。
// - 任务栏按“待办 → 进行中 → 完成”分三段；一行一个任务：标题（强）＋ 负责人、依赖、写入范围（弱）。
//   改状态、删除收进行尾菜单。写入范围重叠时在最上面用警告条说清是哪两个任务。
// - 主操作只有一个：“新建任务”（在任务栏）。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lopicode/agent/team.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/state/team_state.dart';
import 'package:lopicode/state/workspace_conversations.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/chrome.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';

class TeamScreen extends ConsumerStatefulWidget {
  const TeamScreen({super.key, required this.session});
  final ProjectSession session;

  @override
  ConsumerState<TeamScreen> createState() => _TeamScreenState();
}

class _TeamScreenState extends ConsumerState<TeamScreen> {
  /// 进来时所在对话的主对话：看的就是它的任务板（团队没开时也能看，只是 Agent 没有任务板工具）。
  late final TeamKey _key = (widget.session, widget.session.rootOf(widget.session.activeConversation).id);

  TeamNotifier get _team => ref.read(teamProvider(_key).notifier);

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } on TeamException catch (e) {
      if (mounted) showSnack(context, e.message);
    }
  }

  Future<void> _newTask() async {
    final result = await showModalBottomSheet<({String title, String owner, List<String> deps, List<String> scope})>(context: context, isScrollControlled: true, builder: (_) => const _TaskSheet());
    if (result == null) return;
    await _run(() async {
      await _team.createTask(title: result.title, owner: result.owner, deps: result.deps, scope: result.scope);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    // 任务板变了、对话目录变了（子代理来去）：重画
    ref.watch(conversationsProvider(widget.session));
    final board = ref.watch(teamProvider(_key));
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: context.colors.canvas,
        appBar: PageBar(
          background: context.colors.canvas,
          title: const Text('智能体团队'),
          bottom: const TabBar(
            tabs: [
              Tab(text: '成员'),
              Tab(text: '任务'),
              Tab(text: '消息'),
            ],
          ),
        ),
        body: board == null
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: [
                  // 成员
                  ListView(
                    padding: const EdgeInsets.symmetric(vertical: Space.x2),
                    children: [
                      for (final m in board.members)
                        ListTile(
                          leading: Icon(m.name == TeamBoard.lead ? Icons.star_outline : Icons.smart_toy_outlined, color: c.accent),
                          title: Text(m.name),
                          subtitle: Text(
                            [if (m.role.isNotEmpty) m.role, '负责 ${board.tasks.where((x) => x.owner == m.name && x.status != TaskStatus.done).length} 个未完成任务'].join(' · '),
                            style: t.bodySmall,
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.all(Space.x4),
                        child: Text('成员是主智能体派出的子代理，派出时自动加进来。', style: t.bodySmall),
                      ),
                    ],
                  ),
                  // 任务
                  ListView(
                    padding: const EdgeInsets.only(bottom: Space.x8),
                    children: [
                      for (final w in board.overlapWarnings()) InfoBanner(w, tone: BannerTone.warning, margin: const EdgeInsets.fromLTRB(Space.x4, Space.x3, Space.x4, 0)),
                      if (board.tasks.isEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(Space.x4, Space.x6, Space.x4, Space.x2),
                          child: Text('任务板还是空的。让主智能体拆任务，或者自己新建。', style: t.bodyMedium?.copyWith(color: c.textMuted)),
                        ),
                      for (final status in TaskStatus.values)
                        if (board.tasks.any((x) => x.status == status)) ...[
                          SectionLabel('${status.label}（${board.tasks.where((x) => x.status == status).length}）'),
                          for (final task in board.tasks.where((x) => x.status == status))
                            ListTile(
                              key: Key('task-${task.id}'),
                              title: Text('${task.id}  ${task.title}', maxLines: 2, overflow: TextOverflow.ellipsis),
                              subtitle: Text(
                                [
                                  '负责人：${task.owner.isEmpty ? '还没人' : task.owner}',
                                  if (task.deps.isNotEmpty) '依赖：${task.deps.join('、')}${board.blockers(task).isEmpty ? '' : '（还没完成）'}',
                                  '写入范围：${task.scope.isEmpty ? '不限' : task.scope.join('、')}',
                                  if (task.note.isNotEmpty) '备注：${task.note}',
                                ].join('\n'),
                                style: t.bodySmall,
                              ),
                              trailing: PopupMenuButton<String>(
                                tooltip: '更多',
                                icon: Icon(Icons.more_vert, color: c.textFaint),
                                onSelected: (v) => _run(() async {
                                  if (v == 'delete') {
                                    await _team.removeTask(task.id);
                                  } else {
                                    if (TaskStatus.byId(v) case final status?) await _team.setStatus(task.id, status);
                                  }
                                }),
                                itemBuilder: (_) => [
                                  for (final s in TaskStatus.values)
                                    if (s != task.status) PopupMenuItem(value: s.id, child: Text('改为${s.label}')),
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: Text('删除', style: TextStyle(color: c.danger)),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      Padding(
                        padding: const EdgeInsets.fromLTRB(Space.x4, Space.x4, Space.x4, 0),
                        child: FilledButton.icon(key: const Key('team-new-task'), onPressed: _newTask, icon: const Icon(Icons.add, size: 18), label: const Text('新建任务')),
                      ),
                    ],
                  ),
                  // 消息
                  board.messages.isEmpty
                      ? const EmptyState(icon: Icons.forum_outlined, title: '还没有消息', message: '智能体之间互相留的话会出现在这里。')
                      : ListView(
                          padding: const EdgeInsets.all(Space.x4),
                          children: [
                            for (final m in board.messages.reversed)
                              Padding(
                                padding: const EdgeInsets.only(bottom: Space.x3),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('${m.from} → ${m.to.isEmpty ? '所有人' : m.to} · ${_hm(m.at)}', style: t.bodySmall?.copyWith(color: c.accent)),
                                    const SizedBox(height: 2),
                                    SelectableText(m.text, style: t.bodyMedium),
                                  ],
                                ),
                              ),
                          ],
                        ),
                ],
              ),
      ),
    );
  }

  static String _hm(DateTime at) {
    final l = at.toLocal();
    return '${l.month}-${l.day} ${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }
}

class _TaskSheet extends StatefulWidget {
  const _TaskSheet();

  @override
  State<_TaskSheet> createState() => _TaskSheetState();
}

class _TaskSheetState extends State<_TaskSheet> {
  final _title = TextEditingController();
  final _owner = TextEditingController();
  final _deps = TextEditingController();
  final _scope = TextEditingController();

  @override
  void dispose() {
    _title.dispose();
    _owner.dispose();
    _deps.dispose();
    _scope.dispose();
    super.dispose();
  }

  static List<String> _split(String s) => [
    for (final part in s.split(RegExp(r'[,，、\s]+')))
      if (part.trim().isNotEmpty) part.trim(),
  ];

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, MediaQuery.viewInsetsOf(context).bottom + Space.x4),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('新建任务', style: t.titleLarge),
              const SizedBox(height: Space.x4),
              TextField(
                key: const Key('task-title'),
                controller: _title,
                decoration: const InputDecoration(labelText: '要做什么'),
              ),
              const SizedBox(height: Space.x3),
              TextField(
                controller: _owner,
                decoration: const InputDecoration(labelText: '负责人（可不填）', hintText: '成员的名字'),
              ),
              const SizedBox(height: Space.x3),
              TextField(
                controller: _deps,
                decoration: const InputDecoration(labelText: '依赖哪些任务（可不填）', hintText: '任务编号，如 t1、t2'),
              ),
              const SizedBox(height: Space.x3),
              TextField(
                key: const Key('task-scope'),
                controller: _scope,
                decoration: const InputDecoration(labelText: '写入范围（可不填）', hintText: '能改的文件或文件夹，如 src/、index.html', helperText: '不填＝不限。填了以后，负责它的子代理只能改这些位置'),
              ),
              const SizedBox(height: Space.x4),
              FilledButton(
                key: const Key('task-save'),
                onPressed: () {
                  if (_title.text.trim().isEmpty) return;
                  Navigator.pop(context, (title: _title.text.trim(), owner: _owner.text.trim(), deps: _split(_deps.text), scope: _split(_scope.text)));
                },
                child: const Text('创建'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
