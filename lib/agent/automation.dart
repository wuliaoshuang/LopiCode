import 'dart:io';

import 'package:lopicode/core/safe_file.dart';

/// 时间规则。
enum RuleKind {
  once('once', '只运行一次'),
  daily('daily', '每天'),
  weekly('weekly', '每周'),
  interval('interval', '每隔一段时间');

  const RuleKind(this.id, this.label);
  final String id;
  final String label;
  static RuleKind? byId(Object? id) => values.where((k) => k.id == id).firstOrNull;
}

class AutomationException implements Exception {
  AutomationException(this.message);
  final String message;
  @override
  String toString() => message;
}

class TimeRule {
  TimeRule({required this.kind, this.hour = 9, this.minute = 0, List<int>? weekdays, this.date, this.everyMinutes = 60, required this.tzOffsetMinutes}) : weekdays = weekdays ?? [];
  final RuleKind kind;
  final int hour;
  final int minute;

  /// 每周的哪几天：1＝周一 … 7＝周日。
  final List<int> weekdays;

  /// 只运行一次的日期，`YYYY-MM-DD`。
  final String? date;
  final int everyMinutes;

  /// 时区：相对 UTC 的分钟数（北京时间是 480）。不处理夏令时。
  final int tzOffsetMinutes;

  static const int minInterval = 15;

  static String tzLabel(int offsetMinutes) {
    final sign = offsetMinutes < 0 ? '-' : '+';
    final abs = offsetMinutes.abs();
    return 'UTC$sign${abs ~/ 60}${abs % 60 == 0 ? '' : ':${(abs % 60).toString().padLeft(2, '0')}'}';
  }

  String get _hm => '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  String describe() {
    const names = ['一', '二', '三', '四', '五', '六', '日'];
    final tz = tzLabel(tzOffsetMinutes);
    return switch (kind) {
      RuleKind.once => '$date $_hm 运行一次（$tz）',
      RuleKind.daily => '每天 $_hm（$tz）',
      RuleKind.weekly => '每周${(weekdays.toList()..sort()).map((d) => names[d - 1]).join('、')} $_hm（$tz）',
      RuleKind.interval => '每隔 $everyMinutes 分钟',
    };
  }

  void validate() {
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) throw AutomationException('时间不对：要在 00:00 到 23:59 之间');
    if (tzOffsetMinutes < -720 || tzOffsetMinutes > 840) throw AutomationException('时区不对');
    switch (kind) {
      case RuleKind.once:
        if (date == null || _parseDate(date!) == null) throw AutomationException('日期要写成 2026-12-31 这样');
      case RuleKind.weekly:
        if (weekdays.isEmpty || weekdays.any((d) => d < 1 || d > 7)) throw AutomationException('每周任务至少选一天');
      case RuleKind.interval:
        if (everyMinutes < minInterval) throw AutomationException('间隔最短 $minInterval 分钟');
      case RuleKind.daily:
        break;
    }
  }

  static (int, int, int)? _parseDate(String s) {
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(s.trim());
    if (m == null) return null;
    final y = int.parse(m.group(1)!), mo = int.parse(m.group(2)!), d = int.parse(m.group(3)!);
    final check = DateTime.utc(y, mo, d);
    if (check.year != y || check.month != mo || check.day != d) return null;
    return (y, mo, d);
  }

  /// [after] 之后下一次触发的时刻（UTC）；不会再触发返回 null。
  /// [last] 是上一次运行的时刻（间隔任务用）。
  DateTime? next(DateTime after, {DateTime? last}) {
    final a = after.toUtc();
    final offset = Duration(minutes: tzOffsetMinutes);
    // “当地墙上时间”用一个 UTC 的 DateTime 表示，算完再减回偏移。
    final local = a.add(offset);
    DateTime at(DateTime day) => DateTime.utc(day.year, day.month, day.day, hour, minute).subtract(offset);
    switch (kind) {
      case RuleKind.once:
        final d = _parseDate(date ?? '');
        if (d == null) return null;
        final t = DateTime.utc(d.$1, d.$2, d.$3, hour, minute).subtract(offset);
        return t.isAfter(a) ? t : null;
      case RuleKind.daily:
        final today = at(local);
        return today.isAfter(a) ? today : at(local.add(const Duration(days: 1)));
      case RuleKind.weekly:
        for (var i = 0; i <= 7; i++) {
          final day = local.add(Duration(days: i));
          if (!weekdays.contains(day.weekday)) continue;
          final t = at(day);
          if (t.isAfter(a)) return t;
        }
        return null;
      case RuleKind.interval:
        final base = (last ?? a).toUtc().add(Duration(minutes: everyMinutes));
        return base.isAfter(a) ? base : a.add(const Duration(seconds: 1));
    }
  }

  Map<String, dynamic> toJson() => {'kind': kind.id, 'hour': hour, 'minute': minute, 'weekdays': weekdays, 'date': date, 'every': everyMinutes, 'tz': tzOffsetMinutes};

  static TimeRule? fromJson(Object? j, {int defaultTz = 480}) {
    if (j is! Map) return null;
    final kind = RuleKind.byId(j['kind']);
    if (kind == null) return null;
    var hour = j['hour'] is int ? j['hour'] as int : 9;
    var minute = j['minute'] is int ? j['minute'] as int : 0;
    // 也接受 "time": "08:30"
    final time = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch('${j['time'] ?? ''}');
    if (time != null) {
      hour = int.parse(time.group(1)!);
      minute = int.parse(time.group(2)!);
    }
    return TimeRule(
      kind: kind,
      hour: hour,
      minute: minute,
      weekdays: [
        for (final d in (j['weekdays'] as List?) ?? const [])
          if (d is int) d,
      ],
      date: j['date'] is String ? j['date'] as String : null,
      everyMinutes: j['every'] is int ? j['every'] as int : (j['every_minutes'] is int ? j['every_minutes'] as int : 60),
      tzOffsetMinutes: j['tz'] is int ? j['tz'] as int : (j['tz_offset_minutes'] is int ? j['tz_offset_minutes'] as int : defaultTz),
    );
  }
}

class AutomationRun {
  AutomationRun(this.at, this.status, this.summary);
  final DateTime at;

  /// ok / failed / missed / skipped
  final String status;
  final String summary;

  String get statusLabel => switch (status) {
    'ok' => '完成',
    'failed' => '失败',
    'missed' => '错过',
    _ => '跳过',
  };

  Map<String, dynamic> toJson() => {'at': at.toUtc().toIso8601String(), 'status': status, 'summary': summary};
}

/// 一个自动化任务。不可变：要改走 [AutomationStore] 的方法，它会换一份新的。
class Automation {
  Automation({
    required this.id,
    required this.title,
    required this.instruction,
    required this.workspaceId,
    required this.rule,
    this.permission = 'workspace',
    this.enabled = true,
    DateTime? createdAt,
    this.lastRunAt,
    List<AutomationRun>? history,
  }) : createdAt = createdAt ?? DateTime.now().toUtc(),
       history = List.unmodifiable(history ?? const []);
  final String id;
  final String title;
  final String instruction;
  final String workspaceId;
  final TimeRule rule;

  /// 运行时的权限档位（没人在场，需要确认的操作一律按拒绝处理，除非是“完全权限”）。
  final String permission;
  final bool enabled;
  final DateTime createdAt;
  final DateTime? lastRunAt;

  /// 运行历史，新的在前。
  final List<AutomationRun> history;

  Automation copyWith({String? title, String? instruction, String? workspaceId, TimeRule? rule, String? permission, bool? enabled, DateTime? lastRunAt, List<AutomationRun>? history}) => Automation(
    id: id,
    title: title ?? this.title,
    instruction: instruction ?? this.instruction,
    workspaceId: workspaceId ?? this.workspaceId,
    rule: rule ?? this.rule,
    permission: permission ?? this.permission,
    enabled: enabled ?? this.enabled,
    createdAt: createdAt,
    lastRunAt: lastRunAt ?? this.lastRunAt,
    history: history ?? this.history,
  );

  /// 下一次触发时刻（UTC）。已经过点的那一次不算（那一次由 [AutomationStore.pending] 处理）。
  DateTime? nextRun(DateTime now) {
    if (!enabled) return null;
    final base = lastRunAt ?? createdAt;
    final t = rule.next(base, last: base);
    if (t == null) return null;
    return t.isAfter(now.toUtc()) ? t : rule.next(now, last: now);
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'instruction': instruction,
    'workspace': workspaceId,
    'rule': rule.toJson(),
    'permission': permission,
    'enabled': enabled,
    'createdAt': createdAt.toIso8601String(),
    'lastRunAt': lastRunAt?.toIso8601String(),
    'history': [for (final r in history) r.toJson()],
  };

  static Automation? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'];
    if (id is! String) return null;
    final rule = TimeRule.fromJson(j['rule']);
    if (rule == null) return null;
    final history = j['history'];
    return Automation(
      id: id,
      title: '${j['title'] ?? ''}',
      instruction: '${j['instruction'] ?? ''}',
      workspaceId: '${j['workspace'] ?? ''}',
      rule: rule,
      permission: '${j['permission'] ?? 'workspace'}',
      enabled: j['enabled'] != false,
      createdAt: DateTime.tryParse('${j['createdAt']}')?.toUtc(),
      lastRunAt: DateTime.tryParse('${j['lastRunAt']}')?.toUtc(),
      history: [
        for (final r in history is List ? history : const [])
          if (r is Map) AutomationRun(DateTime.tryParse('${r['at']}')?.toUtc() ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true), '${r['status']}', '${r['summary'] ?? ''}'),
      ],
    );
  }
}

/// 自动化任务的仓库（一个 JSON 文件）。只负责存和算时间，不负责跑。
class AutomationStore {
  AutomationStore(this.file);
  final File file;
  static const int maxHistory = 30;
  static const int maxTasks = 50;

  /// 现有的任务（列表不可改；每次增删改都换一份新的）。
  List<Automation> get items => _items;
  List<Automation> _items = const [];

  /// 任务清单或运行记录变了（状态层据此换快照）。
  final List<void Function()> changeListeners = [];

  void _setItems(Iterable<Automation> next) {
    _items = List.unmodifiable(next);
    for (final listener in List.of(changeListeners)) {
      listener();
    }
  }

  /// 把 [id] 那个任务换成 [change] 算出来的新一份并存盘；任务已经不在了返回 null（什么都不做）。
  Future<Automation?> _update(String id, Automation Function(Automation a) change) async {
    final old = byId(id);
    if (old == null) return null;
    final next = change(old);
    _setItems([for (final a in _items) a.id == id ? next : a]);
    await save();
    return next;
  }

  Future<void> load() async {
    final loaded = <Automation>[];
    // 文件坏了：备份后当没有任务
    final j = await readJsonFile(file, accept: (j) => j is List, label: '自动化任务');
    if (j is List) {
      for (final a in j) {
        try {
          final item = Automation.fromJson(a);
          if (item != null) loaded.add(item);
        } catch (_) {
          // 单条读不懂（老版本字段不对）：跳过这一条，不连累别的
        }
      }
    }
    _setItems(loaded);
  }

  Future<void> save() async {
    try {
      await writeJsonAtomic(file, [for (final a in items) a.toJson()]);
    } on FileSystemException {
      // 存不了：这次打开期间仍然有效
    }
  }

  Automation? byId(String? id) => items.where((a) => a.id == id).firstOrNull;

  static void validate({required String title, required String instruction, required TimeRule rule}) {
    if (title.trim().isEmpty) throw AutomationException('任务名不能为空');
    if (instruction.trim().isEmpty) throw AutomationException('指令不能为空');
    if (instruction.length > 4000) throw AutomationException('指令太长（最多 4000 字）');
    rule.validate();
  }

  /// 新建或修改，返回存好的那一份。**调用前必须已经让用户在确认卡上点过头**（见 automation_tools.dart / 自动化页面）。
  Future<Automation> upsert({
    String? id,
    required String title,
    required String instruction,
    required String workspaceId,
    required TimeRule rule,
    String permission = 'workspace',
    DateTime? now,
  }) async {
    validate(title: title, instruction: instruction, rule: rule);
    final at = (now ?? DateTime.now()).toUtc();
    final old = byId(id);
    if (old != null) {
      // 改了规则：从现在起重新算，之前错过的不补。
      final next = old.copyWith(title: title.trim(), instruction: instruction.trim(), workspaceId: workspaceId, rule: rule, permission: permission, lastRunAt: at);
      _setItems([for (final a in _items) a.id == old.id ? next : a]);
      await save();
      return next;
    }
    if (items.length >= maxTasks) throw AutomationException('自动化任务最多 $maxTasks 个');
    var newId = 'a${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
    while (byId(newId) != null) {
      newId = '${newId}x';
    }
    final a = Automation(id: newId, title: title.trim(), instruction: instruction.trim(), workspaceId: workspaceId, rule: rule, permission: permission, createdAt: at);
    _setItems([..._items, a]);
    await save();
    return a;
  }

  Future<void> remove(String id) async {
    _setItems(_items.where((a) => a.id != id));
    await save();
  }

  /// 开 / 关一个任务。重新开启：从现在起算。
  Future<Automation?> setEnabled(String id, bool on, {DateTime? now}) => _update(id, (a) => a.copyWith(enabled: on, lastRunAt: on ? (now ?? DateTime.now()).toUtc() : null));

  /// 到点了、马上要跑：先把时间推进到 [startedAt]（跑的过程很长也不会被下一次检查重复触发）；只运行一次的顺手停用。
  Future<Automation?> markStarted(String id, DateTime startedAt) => _update(id, (a) => a.copyWith(lastRunAt: startedAt.toUtc(), enabled: a.rule.kind == RuleKind.once ? false : null));

  /// 记一笔运行结果（最多留 [maxHistory] 笔）。[advance] 为 true 时顺便把时间推进到这一笔。
  Future<Automation?> record(String id, AutomationRun run, {bool advance = true}) => _update(
    id,
    (a) => a.copyWith(history: [run, ...a.history].take(maxHistory).toList(), lastRunAt: advance ? run.at.toUtc() : null, enabled: a.rule.kind == RuleKind.once && advance ? false : null),
  );

  /// 现在该处理的任务：到点的（[due]）和错过的（[missed]，早就过点了，App 当时没在运行）。
  /// 过点不超过 [grace] 的算到点，照常运行；超过的只记一笔“错过”，不补跑。
  ({List<Automation> due, List<Automation> missed}) pending(DateTime now, {Duration grace = const Duration(minutes: 5)}) {
    final due = <Automation>[], missed = <Automation>[];
    final n = now.toUtc();
    for (final a in items) {
      if (!a.enabled) continue;
      final base = a.lastRunAt ?? a.createdAt;
      final t = a.rule.next(base, last: base);
      if (t == null || t.isAfter(n)) continue;
      (n.difference(t) <= grace ? due : missed).add(a);
    }
    return (due: due, missed: missed);
  }
}
