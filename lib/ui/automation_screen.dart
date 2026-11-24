// 设计约束（自动化任务 · 390×844）
// - 列表页最上面一条如实说明：只有 App 开着时才会触发，错过的不补跑。主操作只有“新建任务”。
// - 一行一个任务：名字（强）＋ 时间规则和下一次触发（弱）＋ 右边开关。点行进详情。
// - 详情页：规则摘要 → 完整指令 → 三个操作（一行一个：立即运行 / 修改 / 删除收进菜单）→ 运行历史。
// - 编辑页从上到下一行一件事：任务名 → 指令 → 工作区 → 多久一次 → 具体时间 → 时区 → 运行权限 → 保存。
// - 保存前必须过一张单独的确认卡，上面是完整指令和实际触发时间。这张卡跟权限档位无关。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lopicode/agent/agent_tools.dart';
import 'package:lopicode/agent/automation.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/session/automation_tools.dart';
import 'package:lopicode/state/automations_state.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/app_ref.dart';
import 'package:lopicode/ui/chat_panels.dart';
import 'package:lopicode/ui/chrome.dart';
import 'package:lopicode/ui/widgets.dart';
import 'package:material_ui/material_ui.dart';

const String kAutomationHonesty = '只有 LopiCode 正在运行（开着或刚切到后台、没被系统清掉）时才会触发。到点时 App 没在运行，那一次只记为“错过”，不会补跑。';

class AutomationListScreen extends ConsumerStatefulWidget {
  const AutomationListScreen({super.key, this.workspace});
  final Project? workspace;

  @override
  ConsumerState<AutomationListScreen> createState() => _AutomationListScreenState();
}

class _AutomationListScreenState extends ConsumerState<AutomationListScreen> {
  /// null＝工作区列表还没读完（这时不能说“已不在”）。
  Map<String, String>? _names;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    appOf(context).projects.list().then((list) {
      if (mounted) setState(() => _names = {for (final p in list) p.id: p.name});
    }, onError: (_) {});
  }

  Future<void> _new() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AutomationEditScreen(workspace: widget.workspace)));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final autos = ref.watch(automationsProvider);
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final items = autos.items;
    final now = DateTime.now();
    return Scaffold(
      backgroundColor: context.colors.canvas,
      extendBodyBehindAppBar: true,
      appBar: PageBar(background: context.colors.canvas, title: const Text('自动化任务')),
      floatingActionButton: items.isEmpty ? null : FloatingActionButton.extended(onPressed: _new, elevation: 2, shape: const StadiumBorder(), icon: const Icon(Icons.add), label: const Text('新建任务')),
      body: SectionedList(
        bottom: 96,
        children: [
          const InfoBanner(kAutomationHonesty, tone: BannerTone.warning, margin: EdgeInsets.fromLTRB(Space.x4, Space.x3, Space.x4, Space.x2)),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: Space.x8),
              child: EmptyState(
                icon: Icons.event_repeat,
                title: '还没有自动化任务',
                message: '到时间后，在指定的工作区里自动开一段对话执行你写好的指令。\n也可以在对话里直接让 Agent 帮你安排。',
                action: FilledButton.icon(onPressed: _new, icon: const Icon(Icons.add), label: const Text('新建任务')),
              ),
            ),
          for (final a in items)
            ListTile(
              key: Key('automation-${a.id}'),
              title: Text(a.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                [
                  a.rule.describe(),
                  _names == null ? '工作区：读取中…' : (_names![a.workspaceId] == null ? '工作区已不在' : '工作区：${_names![a.workspaceId]}'),
                  if (autos.isRunning(a.id)) '正在运行' else if (!a.enabled) '已停用' else if (a.nextRun(now) case final next?) '下一次 ${formatLocalTime(next, a.rule.tzOffsetMinutes)}' else '不会再触发',
                ].join('\n'),
                style: t.bodySmall?.copyWith(color: a.enabled ? null : c.textFaint),
              ),
              isThreeLine: true,
              trailing: Switch(value: a.enabled, onChanged: (v) => ref.read(automationsProvider.notifier).setEnabled(a.id, v)),
              onTap: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => AutomationDetailScreen(id: a.id, workspaceName: _names?[a.workspaceId], workspaceKnown: _names != null),
                  ),
                );
                if (mounted) setState(() {});
              },
            ),
        ],
      ),
    );
  }
}

class AutomationDetailScreen extends ConsumerStatefulWidget {
  const AutomationDetailScreen({super.key, required this.id, this.workspaceName, this.workspaceKnown = true});
  final bool workspaceKnown;
  final String id;
  final String? workspaceName;

  @override
  ConsumerState<AutomationDetailScreen> createState() => _AutomationDetailScreenState();
}

class _AutomationDetailScreenState extends ConsumerState<AutomationDetailScreen> {
  Future<void> _runNow(Automation a) async {
    final app = appOf(context);
    final ok = await confirmDialog(context, title: '现在运行一次？', message: '会马上在工作区里开一段对话执行这条指令，会消耗模型费用。不影响原来的时间安排。', confirmLabel: '运行');
    if (!ok) return;
    if (mounted) showSnack(context, '已开始运行，结果会出现在下面的运行历史里');
    await app.scheduler.runNow(a);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final autos = ref.watch(automationsProvider);
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final a = autos.byId(widget.id);
    if (a == null) {
      return Scaffold(
        backgroundColor: context.colors.canvas,
        extendBodyBehindAppBar: true,
        appBar: PageBar(background: context.colors.canvas, title: const Text('自动化任务')),
        body: const BelowBar(
          child: EmptyState(icon: Icons.event_busy, title: '这个任务已经删除', message: ''),
        ),
      );
    }
    final next = a.nextRun(DateTime.now());
    final running = autos.isRunning(a.id);
    return Scaffold(
      backgroundColor: context.colors.canvas,
      extendBodyBehindAppBar: true,
      appBar: PageBar(
        background: context.colors.canvas,
        title: Text(a.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          PopupMenuButton<String>(
            tooltip: '更多',
            onSelected: (_) async {
              final ok = await confirmDialog(context, title: '删除任务“${a.title}”？', message: '任务和它的运行历史会被删除。它以前跑出来的对话不受影响。', confirmLabel: '删除', danger: true);
              if (!ok) return;
              await ref.read(automationsProvider.notifier).remove(a.id);
              if (context.mounted) Navigator.pop(context);
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'delete',
                child: Text('删除任务', style: TextStyle(color: c.danger)),
              ),
            ],
          ),
        ],
      ),
      body: SectionedList(
        inner: const EdgeInsets.all(Space.x4),
        children: [
          Text(a.rule.describe(), style: t.titleMedium),
          const SizedBox(height: Space.x1),
          Text(
            '工作区：${widget.workspaceName ?? (widget.workspaceKnown ? '已不在' : '读取中…')} · 权限：${PermissionLevel.byId(a.permission).label}\n'
            '${!a.enabled
                ? '已停用'
                : next == null
                ? '不会再触发'
                : '下一次：${formatLocalTime(next, a.rule.tzOffsetMinutes)}'}',
            style: t.bodySmall?.copyWith(height: 1.6),
          ),
          const SizedBox(height: Space.x3),
          const InfoBanner(kAutomationHonesty, tone: BannerTone.warning),
          const SizedBox(height: Space.x4),
          Text('完整指令', style: t.labelMedium),
          const SizedBox(height: Space.x2),
          Container(
            padding: const EdgeInsets.all(Space.x3),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(Radii.md),
              border: Border.all(color: c.border),
            ),
            child: SelectableText(a.instruction, style: t.bodyMedium),
          ),
          const SizedBox(height: Space.x4),
          FilledButton(
            key: const Key('automation-edit'),
            onPressed: () async {
              await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AutomationEditScreen(existing: a)));
              if (mounted) setState(() {});
            },
            child: const Text('修改'),
          ),
          const SizedBox(height: Space.x2),
          OutlinedButton(onPressed: running ? null : () => _runNow(a), child: Text(running ? '正在运行…' : '立即运行一次')),
          const SizedBox(height: Space.x6),
          Text('运行历史（最近 ${AutomationStore.maxHistory} 次）', style: t.labelMedium),
          const SizedBox(height: Space.x2),
          if (a.history.isEmpty) Text('还没有运行过。', style: t.bodySmall),
          for (final r in a.history)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.x3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${formatLocalTime(r.at, a.rule.tzOffsetMinutes)} · ${r.statusLabel}',
                    style: t.bodySmall?.copyWith(
                      color: switch (r.status) {
                        'ok' => c.accent,
                        'failed' => c.danger,
                        _ => c.warning,
                      },
                    ),
                  ),
                  Text(
                    r.summary,
                    style: t.bodySmall?.copyWith(color: c.text),
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class AutomationEditScreen extends ConsumerStatefulWidget {
  const AutomationEditScreen({super.key, this.existing, this.workspace});
  final Automation? existing;
  final Project? workspace;

  @override
  ConsumerState<AutomationEditScreen> createState() => _AutomationEditScreenState();
}

class _AutomationEditScreenState extends ConsumerState<AutomationEditScreen> {
  final _title = TextEditingController();
  final _instruction = TextEditingController();
  final _time = TextEditingController(text: '09:00');
  final _date = TextEditingController();
  final _every = TextEditingController(text: '60');
  RuleKind _kind = RuleKind.daily;
  Set<int> _weekdays = {1, 2, 3, 4, 5};
  int _tz = deviceTzOffset;
  PermissionLevel _permission = PermissionLevel.workspace;
  String? _workspaceId;
  List<Project> _workspaces = const [];

  static const _weekdayNames = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  void initState() {
    super.initState();
    final a = widget.existing;
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    _date.text = '${tomorrow.year}-${_two(tomorrow.month)}-${_two(tomorrow.day)}';
    if (a != null) {
      _title.text = a.title;
      _instruction.text = a.instruction;
      _kind = a.rule.kind;
      _time.text = '${_two(a.rule.hour)}:${_two(a.rule.minute)}';
      if (a.rule.date != null) _date.text = a.rule.date!;
      _every.text = '${a.rule.everyMinutes}';
      if (a.rule.weekdays.isNotEmpty) _weekdays = {...a.rule.weekdays};
      _tz = a.rule.tzOffsetMinutes;
      _permission = PermissionLevel.byId(a.permission);
      _workspaceId = a.workspaceId;
    } else {
      _workspaceId = widget.workspace?.id;
    }
  }

  static String _two(int v) => v.toString().padLeft(2, '0');

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    appOf(context).projects.list().then((list) {
      if (mounted) {
        setState(() {
          _workspaces = list;
          if (!list.any((p) => p.id == _workspaceId)) _workspaceId = list.firstOrNull?.id;
        });
      }
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _title.dispose();
    _instruction.dispose();
    _time.dispose();
    _date.dispose();
    _every.dispose();
    super.dispose();
  }

  List<int> get _tzChoices => {
    deviceTzOffset,
    _tz,
    for (var h = -12; h <= 14; h++) h * 60,
    330, // 印度
  }.toList()..sort();

  Future<void> _pickTime() async {
    final parts = _time.text.split(':');
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: int.tryParse(parts.first) ?? 9, minute: parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0),
      builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true), child: child!),
    );
    if (picked != null && mounted) setState(() => _time.text = '${_two(picked.hour)}:${_two(picked.minute)}');
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365 * 2)),
      initialDate: DateTime.tryParse(_date.text) ?? now,
    );
    if (picked != null && mounted) setState(() => _date.text = '${picked.year}-${_two(picked.month)}-${_two(picked.day)}');
  }

  Future<void> _save() async {
    final ws = _workspaces.where((p) => p.id == _workspaceId).firstOrNull;
    if (ws == null) {
      showSnack(context, '先选一个工作区');
      return;
    }
    final rule = TimeRule.fromJson({
      'kind': _kind.id,
      'time': _time.text.trim(),
      'date': _date.text.trim(),
      'weekdays': _weekdays.toList()..sort(),
      'every_minutes': int.tryParse(_every.text.trim()) ?? 0,
      'tz_offset_minutes': _tz,
    }, defaultTz: _tz);
    try {
      if (rule == null) throw AutomationException('时间规则不对');
      AutomationStore.validate(title: _title.text, instruction: _instruction.text, rule: rule);
      final next = rule.next(DateTime.now());
      if (next == null) throw AutomationException('这个时间已经过去了，不会再触发');
      if (_permission == PermissionLevel.full && widget.existing?.permission != 'full' && !await confirmFullPermission(context)) return;
      if (!mounted) return;
      // 单独的确认卡：完整指令 + 实际触发时间。
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(widget.existing == null ? '确认新建自动化任务' : '确认修改自动化任务'),
          content: SingleChildScrollView(
            child: SelectableText(
              automationCardText(title: _title.text.trim(), instruction: _instruction.text.trim(), rule: rule, next: next, workspace: ws.name, permission: _permission),
              key: const Key('automation-confirm-text'),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('再改改')),
            FilledButton(key: const Key('automation-confirm'), onPressed: () => Navigator.pop(context, true), child: const Text('确认保存')),
          ],
        ),
      );
      if (ok != true) return;
      await ref.read(automationsProvider.notifier).upsert(id: widget.existing?.id, title: _title.text, instruction: _instruction.text, workspaceId: ws.id, rule: rule, permission: _permission.id);
      if (mounted) Navigator.pop(context);
    } on AutomationException catch (e) {
      if (mounted) showSnack(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: context.colors.canvas,
      extendBodyBehindAppBar: true,
      appBar: PageBar(background: context.colors.canvas, title: Text(widget.existing == null ? '新建自动化任务' : '修改自动化任务')),
      body: SectionedList(
        inner: const EdgeInsets.all(Space.x4),
        children: [
          TextField(
            key: const Key('automation-title'),
            controller: _title,
            decoration: const InputDecoration(labelText: '任务名', hintText: '如：每天早上检查依赖更新'),
          ),
          const SizedBox(height: Space.x3),
          TextField(
            key: const Key('automation-instruction'),
            controller: _instruction,
            minLines: 4,
            maxLines: 10,
            decoration: const InputDecoration(labelText: '指令', hintText: '到时间后要 Agent 做什么。那时是一段全新的对话，要写全。', alignLabelWithHint: true),
          ),
          const SizedBox(height: Space.x3),
          DropdownButtonFormField<String>(
            key: ValueKey('ws-$_workspaceId-${_workspaces.length}'),
            initialValue: _workspaces.any((p) => p.id == _workspaceId) ? _workspaceId : null,
            isExpanded: true,
            decoration: const InputDecoration(labelText: '在哪个工作区里运行'),
            items: [
              for (final p in _workspaces)
                DropdownMenuItem(
                  value: p.id,
                  child: Text(p.name, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (v) => setState(() => _workspaceId = v),
          ),
          const SizedBox(height: Space.x3),
          DropdownButtonFormField<RuleKind>(
            key: const Key('automation-kind'),
            initialValue: _kind,
            decoration: const InputDecoration(labelText: '多久一次'),
            items: [for (final k in RuleKind.values) DropdownMenuItem(value: k, child: Text(k.label))],
            onChanged: (v) => setState(() => _kind = v ?? _kind),
          ),
          const SizedBox(height: Space.x3),
          if (_kind == RuleKind.once)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.x3),
              child: TextField(
                controller: _date,
                readOnly: true,
                onTap: _pickDate,
                decoration: const InputDecoration(labelText: '哪一天', suffixIcon: Icon(Icons.calendar_today_outlined, size: 18)),
              ),
            ),
          if (_kind == RuleKind.weekly) ...[
            Text('星期几', style: t.labelMedium),
            const SizedBox(height: Space.x2),
            Wrap(
              spacing: Space.x1,
              children: [
                for (var d = 1; d <= 7; d++)
                  FilterChip(label: Text(_weekdayNames[d - 1]), showCheckmark: false, selected: _weekdays.contains(d), onSelected: (v) => setState(() => v ? _weekdays.add(d) : _weekdays.remove(d))),
              ],
            ),
            const SizedBox(height: Space.x3),
          ],
          if (_kind == RuleKind.interval)
            TextField(
              controller: _every,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '每隔多少分钟', suffixText: '分钟', helperText: '最短 ${TimeRule.minInterval} 分钟'),
            )
          else
            TextField(
              key: const Key('automation-time'),
              controller: _time,
              readOnly: true,
              onTap: _pickTime,
              decoration: const InputDecoration(labelText: '几点（24 小时制）', suffixIcon: Icon(Icons.schedule, size: 18)),
            ),
          const SizedBox(height: Space.x3),
          DropdownButtonFormField<int>(
            initialValue: _tz,
            decoration: const InputDecoration(labelText: '时区', helperText: '固定的时差，不会自动调夏令时'),
            items: [for (final o in _tzChoices) DropdownMenuItem(value: o, child: Text('${TimeRule.tzLabel(o)}${o == deviceTzOffset ? '（手机当前时区）' : ''}'))],
            onChanged: (v) => setState(() => _tz = v ?? _tz),
          ),
          const SizedBox(height: Space.x3),
          DropdownButtonFormField<PermissionLevel>(
            initialValue: _permission,
            decoration: const InputDecoration(labelText: '运行时的权限', helperText: '运行时没人在场：需要你点确认的操作会被自动拒绝'),
            items: [for (final l in PermissionLevel.values) DropdownMenuItem(value: l, child: Text(l.label))],
            onChanged: (v) => setState(() => _permission = v ?? _permission),
          ),
          const SizedBox(height: Space.x4),
          const InfoBanner(kAutomationHonesty, tone: BannerTone.warning),
          const SizedBox(height: Space.x4),
          FilledButton(key: const Key('automation-save'), onPressed: _save, child: const Text('下一步：核对并确认')),
        ],
      ),
    );
  }
}
