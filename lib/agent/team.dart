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

class TeamTask {
  TeamTask({required this.id, required this.title, this.status = TaskStatus.todo, this.owner = '', List<String>? deps, List<String>? scope, this.note = ''})
    : deps = deps ?? [],
      scope = scope ?? [];
  final String id;
  String title;
  TaskStatus status;

  /// 负责人（成员名）。
  String owner;

  /// 依赖的任务 ID：它们都完成了这个任务才能开始。
  List<String> deps;

  /// 写入范围：工作区内的相对路径前缀。空＝整个工作区。
  List<String> scope;
  String note;

  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'status': status.id, 'owner': owner, 'deps': deps, 'scope': scope, 'note': note};

  static TeamTask? fromJson(Object? j) {
    if (j is! Map || j['id'] is! String) return null;
    List<String> strings(Object? v) => [
      for (final s in v is List ? v : const [])
        if (s is String && s.trim().isNotEmpty) s.trim(),
    ];
    return TeamTask(
      id: j['id'] as String,
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
  String role;
  Map<String, dynamic> toJson() => {'name': name, 'role': role};
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

  final List<TeamMember> members = [TeamMember(lead, '负责拆任务、分工、汇总')];
  final List<TeamTask> tasks = [];
  final List<TeamMessage> messages = [];
  int _seq = 0;

  /// 每次有变化 +1（界面监听）。
  void Function()? onChanged;

  Future<void> load() async {
    final f = file;
    if (f == null) return;
    // 文件坏了：备份后当空任务板
    final j = await readJsonFile(f, accept: (j) => j is Map, label: '团队任务板');
    if (j is! Map) return;
    try {
      members
        ..clear()
        ..addAll([
          for (final m in j['members'] is List ? j['members'] as List : const [])
            if (m is Map && m['name'] is String) TeamMember(m['name'] as String, '${m['role'] ?? ''}'),
        ]);
      if (!members.any((m) => m.name == lead)) members.insert(0, TeamMember(lead, '负责拆任务、分工、汇总'));
      tasks
        ..clear()
        ..addAll([
          for (final t in j['tasks'] is List ? j['tasks'] as List : const [])
            ?TeamTask.fromJson(t),
        ]);
      messages
        ..clear()
        ..addAll([
          for (final m in j['messages'] is List ? j['messages'] as List : const [])
            if (m is Map)
              TeamMessage('${m['from']}', '${m['to']}', '${m['text']}', DateTime.tryParse('${m['at']}') ?? DateTime.fromMillisecondsSinceEpoch(0)),
        ]);
      _seq = j['seq'] is int ? j['seq'] as int : tasks.length;
    } catch (_) {
      // 里面某一项的形状不对（老版本）：读到哪算哪，不让任务板打不开
    }
  }

  Future<void> _changed() async {
    onChanged?.call();
    final f = file;
    if (f == null) return;
    try {
      await writeJsonAtomic(f, {
        'seq': _seq,
        'members': [for (final m in members) m.toJson()],
        'tasks': [for (final t in tasks) t.toJson()],
        'messages': [for (final m in messages) m.toJson()],
      });
    } on FileSystemException {
      // 存不了：这次打开期间仍然有效
    }
  }

  TeamTask? task(String id) => tasks.where((t) => t.id == id).firstOrNull;

  Future<void> addMember(String name, [String role = '']) async {
    final existing = members.where((m) => m.name == name).firstOrNull;
    if (existing != null) {
      if (role.isNotEmpty) existing.role = role;
    } else {
      members.add(TeamMember(name, role));
    }
    await _changed();
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
    tasks.add(t);
    if (t.owner.isNotEmpty && !members.any((m) => m.name == t.owner)) members.add(TeamMember(t.owner, ''));
    await _changed();
    return t;
  }

  /// 还没完成的依赖。
  List<TeamTask> blockers(TeamTask t) => [
    for (final d in t.deps)
      if (task(d) case final dep? when dep.status != TaskStatus.done) dep,
  ];

  Future<TeamTask> update(String id, {TaskStatus? status, String? owner, String? note, String? title, List<String>? scope, List<String>? deps}) async {
    final t = task(id);
    if (t == null) throw TeamException('没有编号为 $id 的任务');
    if (deps != null) {
      for (final d in deps) {
        if (d == id) throw TeamException('任务不能依赖自己');
        if (task(d) == null) throw TeamException('依赖的任务 $d 不存在');
      }
      t.deps = [...deps];
    }
    if (status == TaskStatus.doing && t.status != TaskStatus.doing) {
      final blocked = blockers(t);
      if (blocked.isNotEmpty) {
        throw TeamException('任务 $id 还不能开始：它依赖的 ${blocked.map((b) => '${b.id}（${b.title}）').join('、')} 还没完成');
      }
    }
    if (title != null && title.trim().isNotEmpty) t.title = title.trim();
    if (owner != null) {
      t.owner = owner.trim();
      if (t.owner.isNotEmpty && !members.any((m) => m.name == t.owner)) members.add(TeamMember(t.owner, ''));
    }
    if (scope != null) t.scope = _cleanScope(scope);
    if (note != null) t.note = note.trim();
    if (status != null) t.status = status;
    await _changed();
    return t;
  }

  Future<void> remove(String id) async {
    tasks.removeWhere((t) => t.id == id);
    for (final t in tasks) {
      t.deps.remove(id);
    }
    await _changed();
  }

  Future<void> post(String from, String to, String text) async {
    if (text.trim().isEmpty) throw TeamException('留言不能为空');
    messages.add(TeamMessage(from, to.trim().isEmpty ? '全体' : to.trim(), text.trim(), DateTime.now()));
    if (messages.length > maxMessages) messages.removeRange(0, messages.length - maxMessages);
    await _changed();
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
  List<String> overlapWarnings() {
    final doing = tasks.where((t) => t.status == TaskStatus.doing).toList();
    final out = <String>[];
    for (var i = 0; i < doing.length; i++) {
      for (var j = i + 1; j < doing.length; j++) {
        final a = doing[i], b = doing[j];
        if (a.owner == b.owner) continue;
        if (scopesOverlap(a.scope, b.scope)) {
          out.add('${a.id}（${a.owner.isEmpty ? '未指派' : a.owner}）和 ${b.id}（${b.owner.isEmpty ? '未指派' : b.owner}）的写入范围有重叠，可能互相覆盖');
        }
      }
    }
    return out;
  }

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
        'status': {'type': 'string', 'enum': ['todo', 'doing', 'done'], 'description': '待办 / 进行中 / 完成'},
        'owner': {'type': 'string', 'description': '负责人的名字'},
        'depends_on': {'type': 'array', 'items': {'type': 'string'}, 'description': '依赖的任务编号'},
        'write_scope': {'type': 'array', 'items': {'type': 'string'}, 'description': '允许改动的目录或文件（工作区内相对路径）；省略表示整个工作区'},
        'note': {'type': 'string', 'description': '备注 / 进展'},
      }),
      kind: ToolKind.other,
      run: (args) async {
        try {
          final id = args['id'];
          final TeamTask t;
          if (id is String && id.trim().isNotEmpty) {
            t = await update(
              id.trim(),
              status: TaskStatus.byId(args['status']),
              // 没写负责人就开工：开工的人自己负责。
              owner: args['owner'] is String
                  ? args['owner'] as String
                  : (TaskStatus.byId(args['status']) == TaskStatus.doing && (task(id.trim())?.owner.isEmpty ?? false) ? self : null),
              note: args['note'] is String ? args['note'] as String : null,
              title: args['title'] is String ? args['title'] as String : null,
              scope: args['write_scope'] is List ? _strings(args['write_scope']) : null,
              deps: args['depends_on'] is List ? _strings(args['depends_on']) : null,
            );
          } else {
            t = await create(
              title: '${args['title'] ?? ''}',
              owner: args['owner'] is String ? args['owner'] as String : '',
              deps: _strings(args['depends_on']),
              scope: _strings(args['write_scope']),
            );
            final status = TaskStatus.byId(args['status']);
            if (status != null && status != TaskStatus.todo) {
              await update(t.id, status: status, owner: status == TaskStatus.doing && t.owner.isEmpty ? self : null);
            }
          }
          final warnings = overlapWarnings();
          return ToolOutcome('任务 ${t.id}「${t.title}」：${t.status.label}，负责人 ${t.owner.isEmpty ? '未指派' : t.owner}。'
              '${warnings.isEmpty ? '' : '\n⚠ 范围重叠：${warnings.join('；')}'}');
        } on TeamException catch (e) {
          return ToolOutcome('错误：${e.message}', ok: false);
        }
      },
    ),
    ExtraTool(
      spec: toolSpec('team_message', '给团队成员留言（写在任务板的留言栏，所有成员下次看任务板时能看到）。', {
        'to': {'type': 'string', 'description': '收件人的名字；省略表示全体'},
        'text': {'type': 'string', 'description': '留言内容'},
      }, ['text']),
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
