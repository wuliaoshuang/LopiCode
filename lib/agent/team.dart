import 'dart:io';

import 'package:lopicode/agent/agent_tools.dart';
import 'package:lopicode/core/safe_file.dart';

enum TaskStatus {
  todo('todo', '待办'),
  doing('doing', '进行中'),
  done('done', '完成');

  const TaskStatus(this.id, this.label);
  final String id;
  final String label;
  static TaskStatus? byId(Object? id) => values.where((s) => s.id == id).firstOrNull;
}

/// 任务板上的一个任务。不可变：要改走 [TeamBoard.update]，它会换一份新的。
class TeamTask {
  TeamTask({required this.id, required this.title, this.status = TaskStatus.todo, this.owner = '', List<String>? deps, List<String>? scope, this.note = ''})
    : deps = List.unmodifiable(deps ?? const []),
      scope = List.unmodifiable(scope ?? const []);
  final String id;
  final String title;
  final TaskStatus status;

  /// 负责人（成员名）。
  final String owner;

  /// 依赖的任务 ID：它们都完成了这个任务才能开始。
  final List<String> deps;

  /// 写入范围：工作区内的相对路径前缀。空＝整个工作区。
  final List<String> scope;
  final String note;

  TeamTask copyWith({String? title, TaskStatus? status, String? owner, List<String>? deps, List<String>? scope, String? note}) =>
      TeamTask(id: id, title: title ?? this.title, status: status ?? this.status, owner: owner ?? this.owner, deps: deps ?? this.deps, scope: scope ?? this.scope, note: note ?? this.note);

  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'status': status.id, 'owner': owner, 'deps': deps, 'scope': scope, 'note': note};

  static TeamTask? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'];
    if (id is! String) return null;
    List<String> strings(Object? v) => [
      for (final s in v is List ? v : const [])
        if (s is String && s.trim().isNotEmpty) s.trim(),
    ];
    return TeamTask(
      id: id,
      title: '${j['title'] ?? ''}',
      status: TaskStatus.byId(j['status']) ?? TaskStatus.todo,
      owner: '${j['owner'] ?? ''}',
      deps: strings(j['deps']),
      scope: strings(j['scope']),
      note: '${j['note'] ?? ''}',
    );
  }
}

class TeamMessage {
  TeamMessage(this.from, this.to, this.text, this.at);
  final String from;
  final String to;
  final String text;
  final DateTime at;
  Map<String, dynamic> toJson() => {'from': from, 'to': to, 'text': text, 'at': at.toIso8601String()};
}

class TeamMember {
  TeamMember(this.name, this.role);
  final String name;
  final String role;
  Map<String, dynamic> toJson() => {'name': name, 'role': role};
}

/// 任务板某一刻的样子（不可变）：界面订阅的就是它。规则类的计算（谁挡着谁、范围重叠）也在这里，
/// 这样任务板自己和界面算出来的是同一个结果。
class TeamView {
  TeamView({required List<TeamMember> members, required List<TeamTask> tasks, required List<TeamMessage> messages})
    : members = List.unmodifiable(members),
      tasks = List.unmodifiable(tasks),
      messages = List.unmodifiable(messages);

  final List<TeamMember> members;
  final List<TeamTask> tasks;
  final List<TeamMessage> messages;

  TeamTask? task(String id) => tasks.where((t) => t.id == id).firstOrNull;

  /// 还没完成的依赖。
  List<TeamTask> blockers(TeamTask t) => [
    for (final d in t.deps)
      if (task(d) case final dep? when dep.status != TaskStatus.done) dep,
  ];

  /// 范围重叠提示：两个进行中的任务、负责人不同、写入范围有交集。
  List<String> overlapWarnings() {
    final doing = tasks.where((t) => t.status == TaskStatus.doing).toList();
    final out = <String>[];
    for (var i = 0; i < doing.length; i++) {
      for (var j = i + 1; j < doing.length; j++) {
        final a = doing[i], b = doing[j];
        if (a.owner == b.owner) continue;
        if (TeamBoard.scopesOverlap(a.scope, b.scope)) {
          out.add('${a.id}（${a.owner.isEmpty ? '未指派' : a.owner}）和 ${b.id}（${b.owner.isEmpty ? '未指派' : b.owner}）的写入范围有重叠，可能互相覆盖');
        }
      }
    }
    return out;
  }
}

class TeamException implements Exception {
  TeamException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// 一段主对话里多个智能体共用的任务板。规则在代码里：
/// - 依赖没完成的任务不能开始；
/// - 两个“进行中”的任务、负责人不同、写入范围有重叠 → 给出重叠提示；
/// - 派给子代理的任务，子代理的文件写入被限制在任务的写入范围内（见 AgentToolbox.writeScope）。
class TeamBoard {
  TeamBoard({this.file});

  /// 存盘位置；为空只在内存里（测试用）。
  final File? file;

  static const String lead = '主智能体';
  static const int maxTasks = 60;
  static const int maxMessages = 200;

  /// 现在的样子。每次有变化都换一份新的，旧的那份不动。
  TeamView get view => _view;
  TeamView _view = TeamView(members: [TeamMember(lead, '负责拆任务、分工、汇总')], tasks: const [], messages: const []);
  List<TeamMember> get members => _view.members;
  List<TeamTask> get tasks => _view.tasks;
  List<TeamMessage> get messages => _view.messages;
  int _seq = 0;

  /// 每次有变化回调一次，带上新的样子（状态层据此换快照）。
  void Function(TeamView view)? onChanged;

  Future<void> load() async {
    final f = file;
    if (f == null) return;
    // 文件坏了：备份后当空任务板
    final j = await readJsonFile(f, accept: (j) => j is Map, label: '团队任务板');
    if (j is! Map) return;
    var members = _view.members, tasks = _view.tasks, messages = _view.messages;
    try {
      List<Object?> list(Object? v) => v is List ? v : const [];
      final seq = j['seq'];
      members = [
        for (final m in list(j['members']))
          if (m is Map)
            if (m['name'] case final String name) TeamMember(name, '${m['role'] ?? ''}'),
      ];
      if (!members.any((m) => m.name == lead)) members = [TeamMember(lead, '负责拆任务、分工、汇总'), ...members];
      tasks = [for (final t in list(j['tasks'])) ?TeamTask.fromJson(t)];
      messages = [
        for (final m in list(j['messages']))
          if (m is Map) TeamMessage('${m['from']}', '${m['to']}', '${m['text']}', DateTime.tryParse('${m['at']}') ?? DateTime.fromMillisecondsSinceEpoch(0)),
      ];
      _seq = seq is int ? seq : tasks.length;
    } catch (_) {
      // 里面某一项的形状不对（老版本）：读到哪算哪，不让任务板打不开
    }
    _view = TeamView(members: members, tasks: tasks, messages: messages);
  }

  /// 换上新的样子（没传的那部分不动），通知，存盘。
  Future<void> _commit({List<TeamMember>? members, List<TeamTask>? tasks, List<TeamMessage>? messages}) async {
    _view = TeamView(members: members ?? _view.members, tasks: tasks ?? _view.tasks, messages: messages ?? _view.messages);
    onChanged?.call(_view);
    final f = file;
    if (f == null) return;
    try {
      await writeJsonAtomic(f, {
        'seq': _seq,
        'members': [for (final m in _view.members) m.toJson()],
        'tasks': [for (final t in _view.tasks) t.toJson()],
        'messages': [for (final m in _view.messages) m.toJson()],
      });
    } on FileSystemException {
      // 存不了：这次打开期间仍然有效
    }
  }

  TeamTask? task(String id) => _view.task(id);

  /// 加上 [owner] 这个成员（已经在了或是空名字就原样返回）。
  List<TeamMember> _withMember(String owner) => owner.isEmpty || members.any((m) => m.name == owner) ? members : [...members, TeamMember(owner, '')];

  Future<void> addMember(String name, [String role = '']) async {
    final existing = members.any((m) => m.name == name);
    await _commit(
      members: existing
          ? [
              for (final m in members)
                if (m.name == name && role.isNotEmpty) TeamMember(name, role) else m,
            ]
          : [...members, TeamMember(name, role)],
    );
  }

  static List<String> _cleanScope(List<String> scope) => [
    for (final s in scope)
      if (s.trim().isNotEmpty && !s.contains('..') && !s.trim().startsWith('/')) s.trim().replaceAll(RegExp(r'/+$'), ''),
  ];

  Future<TeamTask> create({required String title, String owner = '', List<String> deps = const [], List<String> scope = const []}) async {
    if (title.trim().isEmpty) throw TeamException('任务标题不能为空');
    if (tasks.length >= maxTasks) throw TeamException('任务板最多 $maxTasks 个任务');
    for (final d in deps) {
      if (task(d) == null) throw TeamException('依赖的任务 $d 不存在');
    }
    final t = TeamTask(id: 't${++_seq}', title: title.trim(), owner: owner.trim(), deps: [...deps], scope: _cleanScope(scope));
    await _commit(tasks: [...tasks, t], members: _withMember(t.owner));
    return t;
  }

  /// 还没完成的依赖。
  List<TeamTask> blockers(TeamTask t) => _view.blockers(t);

  /// 改一个任务，返回改好的那一份。校验不过就抛错，**什么都不改**。
  Future<TeamTask> update(String id, {TaskStatus? status, String? owner, String? note, String? title, List<String>? scope, List<String>? deps}) async {
    final old = task(id);
    if (old == null) throw TeamException('没有编号为 $id 的任务');
    if (deps != null) {
      for (final d in deps) {
        if (d == id) throw TeamException('任务不能依赖自己');
        if (task(d) == null) throw TeamException('依赖的任务 $d 不存在');
      }
    }
    final t = old.copyWith(
      deps: deps,
      title: title != null && title.trim().isNotEmpty ? title.trim() : null,
      owner: owner?.trim(),
      scope: scope == null ? null : _cleanScope(scope),
      note: note?.trim(),
      status: status,
    );
    if (status == TaskStatus.doing && old.status != TaskStatus.doing) {
      final blocked = blockers(t);
      if (blocked.isNotEmpty) {
        throw TeamException('任务 $id 还不能开始：它依赖的 ${blocked.map((b) => '${b.id}（${b.title}）').join('、')} 还没完成');
      }
    }
    await _commit(tasks: [for (final x in tasks) x.id == id ? t : x], members: _withMember(t.owner));
    return t;
  }

  Future<void> remove(String id) async {
    await _commit(
      tasks: [
        for (final t in tasks)
          if (t.id != id) t.deps.contains(id) ? t.copyWith(deps: [...t.deps.where((d) => d != id)]) : t,
      ],
    );
  }

  Future<void> post(String from, String to, String text) async {
    if (text.trim().isEmpty) throw TeamException('留言不能为空');
    final all = [...messages, TeamMessage(from, to.trim().isEmpty ? '全体' : to.trim(), text.trim(), DateTime.now())];
    await _commit(messages: all.length > maxMessages ? all.sublist(all.length - maxMessages) : all);
  }

  static bool scopesOverlap(List<String> a, List<String> b) {
    if (a.isEmpty || b.isEmpty) return true; // 空＝整个工作区
    for (final x in a) {
      for (final y in b) {
        if (x == y || x.startsWith('$y/') || y.startsWith('$x/') || x == '.' || y == '.') return true;
      }
    }
    return false;
  }

  /// 范围重叠提示：两个进行中的任务、负责人不同、写入范围有交集。
  List<String> overlapWarnings() => _view.overlapWarnings();

  String describe() {
    if (tasks.isEmpty) return '任务板是空的。';
    final out = StringBuffer();
    for (final s in TaskStatus.values) {
      final list = tasks.where((t) => t.status == s).toList();
      if (list.isEmpty) continue;
      out.writeln('【${s.label}】');
      for (final t in list) {
        out.writeln(
          '- ${t.id} ${t.title}｜负责人：${t.owner.isEmpty ? '未指派' : t.owner}'
          '${t.deps.isEmpty ? '' : '｜依赖：${t.deps.join('、')}'}'
          '｜写入范围：${t.scope.isEmpty ? '整个工作区' : t.scope.join('、')}'
          '${t.note.isEmpty ? '' : '｜备注：${t.note}'}',
        );
      }
    }
    final warnings = overlapWarnings();
    if (warnings.isNotEmpty) out.writeln('⚠ 范围重叠：\n${warnings.map((w) => '- $w').join('\n')}');
    if (messages.isNotEmpty) {
      out.writeln('【最近留言】');
      for (final m in messages.skip(messages.length > 8 ? messages.length - 8 : 0)) {
        out.writeln('- ${m.from} → ${m.to}：${m.text}');
      }
    }
    return out.toString().trim();
  }

  static List<String> _strings(Object? v) => [
    for (final s in v is List ? v : const [])
      if (s is String) s,
  ];

  /// 任务板的三个工具。[self] 是调用者在团队里的名字。
  List<ExtraTool> tools(String self) => [
    ExtraTool(spec: toolSpec('team_board', '查看团队任务板：全部任务（状态、负责人、依赖、写入范围）、范围重叠提示和最近留言。', {}), kind: ToolKind.read, run: (_) async => ToolOutcome(describe())),
    ExtraTool(
      spec: toolSpec('team_task', '在任务板上新建任务（不给 id）或更新任务（给 id）。依赖没完成的任务不能改成进行中。', {
        'id': {'type': 'string', 'description': '要更新的任务编号，如 t1；新建时省略'},
        'title': {'type': 'string', 'description': '任务标题（新建时必填）'},
        'status': {
          'type': 'string',
          'enum': ['todo', 'doing', 'done'],
          'description': '待办 / 进行中 / 完成',
        },
        'owner': {'type': 'string', 'description': '负责人的名字'},
        'depends_on': {
          'type': 'array',
          'items': {'type': 'string'},
          'description': '依赖的任务编号',
        },
        'write_scope': {
          'type': 'array',
          'items': {'type': 'string'},
          'description': '允许改动的目录或文件（工作区内相对路径）；省略表示整个工作区',
        },
        'note': {'type': 'string', 'description': '备注 / 进展'},
      }),
      kind: ToolKind.other,
      run: (args) async {
        try {
          final id = args['id'];
          TeamTask t;
          if (id is String && id.trim().isNotEmpty) {
            t = await update(
              id.trim(),
              status: TaskStatus.byId(args['status']),
              // 没写负责人就开工：开工的人自己负责。
              owner: args['owner'] is String ? args['owner'] as String : (TaskStatus.byId(args['status']) == TaskStatus.doing && (task(id.trim())?.owner.isEmpty ?? false) ? self : null),
              note: args['note'] is String ? args['note'] as String : null,
              title: args['title'] is String ? args['title'] as String : null,
              scope: args['write_scope'] is List ? _strings(args['write_scope']) : null,
              deps: args['depends_on'] is List ? _strings(args['depends_on']) : null,
            );
          } else {
            t = await create(title: '${args['title'] ?? ''}', owner: args['owner'] is String ? args['owner'] as String : '', deps: _strings(args['depends_on']), scope: _strings(args['write_scope']));
            final status = TaskStatus.byId(args['status']);
            if (status != null && status != TaskStatus.todo) {
              t = await update(t.id, status: status, owner: status == TaskStatus.doing && t.owner.isEmpty ? self : null);
            }
          }
          final warnings = overlapWarnings();
          return ToolOutcome(
            '任务 ${t.id}「${t.title}」：${t.status.label}，负责人 ${t.owner.isEmpty ? '未指派' : t.owner}。'
            '${warnings.isEmpty ? '' : '\n⚠ 范围重叠：${warnings.join('；')}'}',
          );
        } on TeamException catch (e) {
          return ToolOutcome('错误：${e.message}', ok: false);
        }
      },
    ),
    ExtraTool(
      spec: toolSpec(
        'team_message',
        '给团队成员留言（写在任务板的留言栏，所有成员下次看任务板时能看到）。',
        {
          'to': {'type': 'string', 'description': '收件人的名字；省略表示全体'},
          'text': {'type': 'string', 'description': '留言内容'},
        },
        ['text'],
      ),
      kind: ToolKind.other,
      run: (args) async {
        try {
          await post(self, args['to'] is String ? args['to'] as String : '', '${args['text'] ?? ''}');
          return ToolOutcome('已留言。');
        } on TeamException catch (e) {
          return ToolOutcome('错误：${e.message}', ok: false);
        }
      },
    ),
  ];
}
