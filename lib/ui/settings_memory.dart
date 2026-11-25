// 设计约束（设置 › 能力 › 记忆 / 一条记忆 · 390×844）— 2026-11-25 文件记忆
// 层级（先定这个，再排版，最后上色）：
// - 最重要：两个开关。〔记忆〕让 Agent 使用记忆（默认开）；〔自动整理〕每轮结束后自动整理（默认关）——
//   它会多花钱，所以代价直接写在开关的副标题里（“每轮结束后会多花一次模型调用”），细则放组脚注。
// - 其次：记了些什么。〔全局记忆〕和〔这个项目的记忆〕分两组，组标题写明归属；一行一条：标题 + 一句摘要，点开看 / 改 / 删；
//   每组最后一行是强调色的“新增一条”。没打开工作区时项目那组只有一行灰掉的说明。
// - 最弱：〔管理〕撤销最近一次改动（右边写是哪一次）、两个红色的清空（点了先确认，清空不能撤销）。
// 一行只做一件事；说明只在副标题和组脚注里；全部用 settings_widgets.dart 的组和行，尺寸不另定。
// 一条记忆的页面：〔内容〕标题 → 正文（表单组）→ 实心“保存”；删除收在右上角菜单里。
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lopicode/agent/memory_store.dart';
import 'package:lopicode/app_services.dart';
import 'package:lopicode/core/stores.dart';
import 'package:lopicode/project_session.dart';
import 'package:lopicode/session/memory_consolidation.dart';
import 'package:lopicode/state/app_providers.dart';
import 'package:lopicode/state/memory_state.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/app_ref.dart';
import 'package:lopicode/ui/settings_widgets.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';

/// 一级页那一行右边的一句当前状态。
String memorySettingsLabel(AppServices app) => !app.memory.enabled ? '关' : (app.memory.autoConsolidate ? '开 · 自动整理' : '开');

class MemorySettingsScreen extends ConsumerStatefulWidget {
  const MemorySettingsScreen({super.key, this.session});

  /// 当前打开的工作区（项目记忆是按工作区存的）；没打开是 null。
  final ProjectSession? session;

  @override
  ConsumerState<MemorySettingsScreen> createState() => _MemorySettingsScreenState();
}

class _MemorySettingsScreenState extends ConsumerState<MemorySettingsScreen> {
  MemoryStore? _project;

  @override
  void initState() {
    super.initState();
    final app = ref.read(appServicesProvider);
    final session = widget.session;
    if (session != null) {
      try {
        _project = app.memory.project(session.project);
      } on Exception {
        _project = null; // .lopicode/memory 指到了工作区外面：不读不写
      }
    }
    // 文件可能被她手改过：进页面重新读一遍（读完会通知，页面跟着变）
    unawaited(app.memory.refresh(session?.project));
  }

  Future<void> _open(MemoryStore store, MemoryEntry? entry) => pushSettingsPage<void>(context, MemoryEntryScreen(store: store, entry: entry));

  /// 两处里最近的那一次改动。
  (MemoryStore, MemoryChange)? _latestChange(MemoryStore global) {
    (MemoryStore, MemoryChange)? best;
    for (final s in [global, ?_project]) {
      if (s.changes.isEmpty) continue;
      if (best == null || s.changes.last.at.isAfter(best.$2.at)) best = (s, s.changes.last);
    }
    return best;
  }

  Future<void> _undo(MemoryStore store) async {
    try {
      final done = await store.undoLast();
      if (mounted) showSnack(context, '已撤销：${done.describe}');
    } on MemoryException catch (e) {
      if (mounted) showSnack(context, e.message);
    }
  }

  Future<void> _clear(MemoryStore store, String what) async {
    final ok = await confirmDialog(context, title: '清空$what？', message: '$what里的 ${store.entries.length} 条都会被删除，不能撤销。', confirmLabel: '清空', danger: true);
    if (!ok) return;
    final n = await store.clear();
    if (mounted) showSnack(context, '已清空，删了 $n 条');
  }

  List<Widget> _rows(MemoryStore store, String emptyText, String addKey) => [
    if (store.entries.isEmpty) SettingsRow(icon: Icons.inbox_outlined, title: emptyText, enabled: false),
    for (final e in store.entries)
      SettingsRow(key: Key('memory-${store.scope.id}-${e.id}'), icon: Icons.sticky_note_2_outlined, title: e.title, subtitle: e.summary.isEmpty ? null : e.summary, onTap: () => _open(store, e)),
    SettingsRow(key: Key(addKey), icon: Icons.add, title: '新增一条', accent: true, onTap: () => _open(store, null)),
  ];

  @override
  Widget build(BuildContext context) {
    ref
      ..watch(settingRevProvider(SettingKeys.memoryEnabled))
      ..watch(settingRevProvider(SettingKeys.memoryAutoConsolidate))
      ..watch(memoryRevProvider);
    final app = appOf(context);
    final s = app.settings;
    final on = app.memory.enabled;
    final global = app.memory.global;
    final project = _project;
    final wsName = widget.session?.project.name;
    final latest = _latestChange(global);
    return SettingsPage(
      title: '记忆',
      listKey: const Key('memory-list'),
      children: [
        SettingsGroup(
          title: '记忆',
          footer: '记忆是普通的 Markdown 文件，一条一个，你随时能看、能改、能删。像密钥、令牌、密码的内容不会被记下来。',
          children: [
            SettingsSwitchRow(
              icon: Icons.psychology_outlined,
              title: '让 Agent 使用记忆',
              subtitle: '每轮开始时把记忆的标题和摘要告诉 Agent；你让它记住什么，它会记成一条',
              switchKey: const Key('memory-enabled'),
              value: on,
              onChanged: (v) => s.set(SettingKeys.memoryEnabled, v),
            ),
          ],
        ),
        SettingsGroup(
          title: '自动整理',
          footer:
              '开着时，一轮对话正常结束后，会另发一次请求，把这段对话里值得长期记住的内容整理进记忆（只增加和改写，不删除）。'
              '至少隔 ${kConsolidateMinInterval.inMinutes} 分钟、攒够 $kConsolidateMinMessages 条新消息才做一次；出错或被停止的那一轮不做，额度到顶时不做。'
              '这一次的用量记在那一轮里，轨迹里标着“整理记忆”。',
          children: [
            SettingsSwitchRow(
              icon: Icons.auto_fix_high_outlined,
              title: '每轮结束后自动整理',
              subtitle: '每轮结束后会多花一次模型调用',
              switchKey: const Key('memory-auto'),
              value: on && s.getBool(SettingKeys.memoryAutoConsolidate),
              onChanged: on ? (v) => s.set(SettingKeys.memoryAutoConsolidate, v) : null,
            ),
          ],
        ),
        SettingsGroup(title: '全局记忆（所有工作区都用得上）', footer: '你这个人的偏好和习惯。点一行看全文、修改或删除。', children: _rows(global, '还没有全局记忆', 'memory-add-global')),
        SettingsGroup(
          title: wsName == null ? '这个项目的记忆' : '这个项目的记忆 · $wsName',
          footer: project == null ? null : '只和这个项目有关的背景、约定、踩过的坑。文件在它的 .lopicode/memory/ 里。',
          children: project == null
              ? [SettingsRow(key: const Key('memory-no-project'), icon: Icons.folder_off_outlined, title: widget.session == null ? '打开一个工作区后，才能看它的项目记忆' : '这个工作区的项目记忆现在读不了', enabled: false)]
              : _rows(project, '这个项目还没有记忆', 'memory-add-project'),
        ),
        SettingsGroup(
          title: '管理',
          footer: '撤销只管最近的几次改动（最多 $kMemoryUndoDepth 次）；清空之后不能撤销。',
          children: [
            SettingsRow(
              key: const Key('memory-undo'),
              icon: Icons.undo,
              title: '撤销最近一次改动',
              subtitle: latest == null ? '现在没有可以撤销的' : latest.$2.describe,
              enabled: latest != null,
              trailing: const SizedBox.shrink(),
              onTap: latest == null ? null : () => _undo(latest.$1),
            ),
            SettingsRow(
              key: const Key('memory-clear-global'),
              icon: Icons.delete_sweep_outlined,
              title: '清空全局记忆',
              danger: global.entries.isNotEmpty,
              enabled: global.entries.isNotEmpty,
              onTap: global.entries.isEmpty ? null : () => _clear(global, '全局记忆'),
            ),
            if (project != null)
              SettingsRow(
                key: const Key('memory-clear-project'),
                icon: Icons.delete_sweep_outlined,
                title: '清空这个项目的记忆',
                danger: project.entries.isNotEmpty,
                enabled: project.entries.isNotEmpty,
                onTap: project.entries.isEmpty ? null : () => _clear(project, '这个项目的记忆'),
              ),
          ],
        ),
      ],
    );
  }
}

/// 看 / 改 / 删一条记忆；[entry] 为 null 是新增。
class MemoryEntryScreen extends StatefulWidget {
  const MemoryEntryScreen({super.key, required this.store, this.entry});
  final MemoryStore store;
  final MemoryEntry? entry;

  @override
  State<MemoryEntryScreen> createState() => _MemoryEntryScreenState();
}

class _MemoryEntryScreenState extends State<MemoryEntryScreen> {
  late final _title = TextEditingController(text: widget.entry?.title ?? '');
  late final _body = TextEditingController(text: widget.entry?.body ?? '');
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await widget.store.write(_title.text, _body.text, by: 'user', replaceId: widget.entry?.id);
      if (mounted) Navigator.pop(context);
    } on MemoryException catch (e) {
      if (mounted) showSnack(context, e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final entry = widget.entry;
    if (entry == null) return;
    final ok = await confirmDialog(context, title: '删除“${entry.title}”？', message: '删掉以后 Agent 就不记得这一条了。删错了可以在记忆页“撤销最近一次改动”。', confirmLabel: '删除', danger: true);
    if (!ok) return;
    try {
      await widget.store.delete(entry.id, by: 'user');
      if (mounted) Navigator.pop(context);
    } on MemoryException catch (e) {
      if (mounted) showSnack(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final c = context.colors;
    return SettingsPage(
      title: entry == null ? '新增记忆' : '记忆',
      subtitle: widget.store.scope.label,
      actions: [
        if (entry != null)
          PopupMenuButton<String>(
            key: const Key('memory-entry-menu'),
            tooltip: '更多',
            onSelected: (_) => _delete(),
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'delete',
                child: Text('删除这一条', style: TextStyle(color: c.danger)),
              ),
            ],
          ),
      ],
      children: [
        SettingsGroup(
          title: '内容',
          footer: '${entry == null ? '' : '文件：${entry.id}.md。'}一条只写一件事，正文最多 $kMemoryMaxBodyChars 字。不要写密钥和密码——像密钥的内容存不进去。',
          padded: true,
          children: [
            TextField(
              key: const Key('memory-title'),
              controller: _title,
              maxLength: kMemoryMaxTitleChars,
              decoration: const InputDecoration(labelText: '标题', hintText: '一眼能看出记的是什么', counterText: ''),
            ),
            const SizedBox(height: Space.x3),
            TextField(
              key: const Key('memory-body'),
              controller: _body,
              minLines: 6,
              maxLines: 14,
              decoration: const InputDecoration(labelText: '正文', hintText: '比如：回答用简体中文，先给结论再解释', alignLabelWithHint: true),
            ),
          ],
        ),
        FilledButton(key: const Key('memory-save'), onPressed: _saving ? null : _save, child: const Text('保存')),
      ],
    );
  }
}
