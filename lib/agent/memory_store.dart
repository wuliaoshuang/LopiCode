// 文件记忆：Agent 跨对话记住的东西，就是一个目录里的普通 Markdown 文件——一条一个文件，第一行 `# 标题`，后面是正文。
// 用户看得见、改得了（设置 › 能力 › 记忆，或者直接改文件）。
//
// 两处：
// - 全局记忆：应用数据目录下的 memory/，不在任何工作区里（她这个人的偏好、习惯）；
// - 项目记忆：工作区的 .lopicode/memory/（这个项目的背景、约定、踩过的坑）。
//   .lopicode 是应用内部目录，Agent 的通用文件工具照旧碰不到它；记忆只走 memory_* 这几个专门的工具。
//
// 规矩（都在代码里，不靠提示词）：
// - 像密钥 / 令牌 / 密码的内容拒绝写入（和日志脱敏用同一套 [redactSecrets]）；
// - 单条、条数、总量都有上限；
// - 同一个目录的读写排队做（主对话和后台整理可能同时写）；
// - 每次改动（写、删）留一份“改之前的样子”，设置页可以撤销最近一次（最多留 [kMemoryUndoDepth] 步）。
import 'dart:async';
import 'dart:io';

import 'package:lopicode/core/crash_log.dart';
import 'package:lopicode/core/path_guard.dart';
import 'package:lopicode/core/project_store.dart';
import 'package:lopicode/core/safe_file.dart';
import 'package:lopicode/core/stores.dart';
import 'package:path/path.dart' as p;

/// 标题最多多少字。
const int kMemoryMaxTitleChars = 40;

/// 一条记忆的正文最多多少字。
const int kMemoryMaxBodyChars = 2000;

/// 一处（全局 / 一个项目）最多多少条。
const int kMemoryMaxEntries = 60;

/// 一处所有正文加起来最多多少字。
const int kMemoryMaxTotalChars = 40000;

/// 可以连着撤销几步。
const int kMemoryUndoDepth = 10;

/// 摘要（标题后面那句）最多多少字。
const int kMemorySummaryChars = 60;

enum MemoryScope {
  global('global', '全局记忆'),
  project('project', '项目记忆');

  const MemoryScope(this.id, this.label);
  final String id;
  final String label;

  static MemoryScope? byId(Object? id) => values.where((s) => s.id == id).firstOrNull;
}

class MemoryException implements Exception {
  MemoryException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// 一条记忆。不可变。
class MemoryEntry {
  const MemoryEntry({required this.scope, required this.id, required this.title, required this.body, required this.updatedAt});
  final MemoryScope scope;

  /// 文件名（不带 .md）。
  final String id;
  final String title;
  final String body;
  final DateTime updatedAt;

  /// 正文第一行有内容的话，截短。
  String get summary {
    final line = body.split('\n').map((l) => l.trim()).firstWhere((l) => l.isNotEmpty, orElse: () => '');
    return line.length > kMemorySummaryChars ? '${line.substring(0, kMemorySummaryChars)}…' : line;
  }
}

/// 最近的一次改动（给“撤销”用）。
class MemoryChange {
  const MemoryChange({required this.id, required this.title, required this.before, required this.after, required this.at, required this.by});

  /// 改的是哪个文件。
  final String id;
  final String title;

  /// 改之前的文件全文；null＝之前没有这条。
  final String? before;

  /// 改之后的文件全文；null＝被删掉了。
  final String? after;
  final DateTime at;

  /// 谁改的：agent（对话里的 Agent）/ auto（后台整理）/ user（她自己在设置页）。
  final String by;

  String get describe =>
      '${switch (by) {
        'auto' => '自动整理时',
        'user' => '你',
        _ => 'Agent ',
      }}${after == null ? '删除了' : (before == null ? '记下了' : '改写了')}“$title”';

  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'before': before, 'after': after, 'at': at.millisecondsSinceEpoch, 'by': by};

  static MemoryChange? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'], before = j['before'], after = j['after'], at = j['at'];
    if (id is! String || !_safeId(id) || (before != null && before is! String) || (after != null && after is! String)) return null;
    return MemoryChange(
      id: id,
      title: j['title'] is String ? j['title'] as String : id,
      before: before as String?,
      after: after as String?,
      at: DateTime.fromMillisecondsSinceEpoch(at is int ? at : 0),
      by: j['by'] is String ? j['by'] as String : 'agent',
    );
  }
}

bool _safeId(String id) => id.isNotEmpty && id.length <= 80 && !id.startsWith('.') && !RegExp(r'[/\\\u0000]').hasMatch(id);

/// 内容里是不是有像密钥 / 令牌 / 密码的东西（和日志脱敏同一套规则：会被抹掉的就算）。
bool looksLikeSecret(String text) => redactSecrets(text) != text;

/// 标题 → 文件名：去掉文件名里不能有的符号和空白。
String memoryFileStem(String title) {
  var s = title.trim().replaceAll(RegExp(r'[/\\:*?"<>|\s\u0000-\u001f]+'), '-');
  s = s.replaceAll(RegExp(r'^[.\-]+|-+$'), '');
  if (s.length > kMemoryMaxTitleChars) s = s.substring(0, kMemoryMaxTitleChars);
  return s.isEmpty ? '记忆' : s;
}

/// 同一个目录的操作排队做。按目录记，不按对象记：同一个目录可能有不止一个 [MemoryStore]。
final Map<String, Future<void>> _locks = {};

/// 一个目录的记忆。
class MemoryStore {
  MemoryStore(String dir, this.scope, {this.onChanged}) : dir = p.normalize(p.absolute(dir));

  final String dir;
  final MemoryScope scope;

  /// 记忆变了（写、删、清空、撤销、重新扫描到了外面改的内容）。
  final void Function()? onChanged;

  /// 最近一次读到的全部记忆，按标题排。拼系统提示词时用它（不读盘）。
  List<MemoryEntry> get entries => _entries;
  List<MemoryEntry> _entries = const [];

  /// 最近的改动，新的在后。
  List<MemoryChange> get changes => _changes;
  List<MemoryChange> _changes = const [];

  bool _undoLoaded = false;

  File _fileOf(String id) => File(p.join(dir, '$id.md'));
  File get _undoFile => File(p.join(dir, 'undo.json'));

  Future<T> _locked<T>(Future<T> Function() body) {
    final previous = _locks[dir] ?? Future<void>.value();
    final done = Completer<void>();
    _locks[dir] = done.future;
    return previous.then((_) => body()).whenComplete(() {
      done.complete();
      if (identical(_locks[dir], done.future)) _locks.remove(dir);
    });
  }

  static String _encode(String title, String body) => '# $title\n\n${body.trim()}\n';

  static ({String? title, String body}) _decode(String text) {
    final lines = text.replaceAll('\r\n', '\n').split('\n');
    final first = lines.indexWhere((l) => l.trim().isNotEmpty);
    if (first >= 0 && lines[first].startsWith('# ')) {
      return (title: lines[first].substring(2).trim(), body: lines.skip(first + 1).join('\n').trim());
    }
    return (title: null, body: text.trim());
  }

  Future<List<MemoryEntry>> _scan() async {
    final root = Directory(dir);
    final out = <MemoryEntry>[];
    try {
      if (!await root.exists()) return out;
      await for (final e in root.list(followLinks: false)) {
        if (e is! File || !e.path.endsWith('.md')) continue;
        final id = p.basenameWithoutExtension(e.path);
        if (!_safeId(id)) continue;
        try {
          // 手改的文件可能很大：只读前面一段，免得一条把提示词撑爆。
          if (await e.length() > kMemoryMaxBodyChars * 8) continue;
          final parsed = _decode(await e.readAsString());
          if (parsed.body.isEmpty && parsed.title == null) continue;
          final title = parsed.title == null || parsed.title!.isEmpty ? id : parsed.title!;
          out.add(MemoryEntry(scope: scope, id: id, title: title, body: parsed.body, updatedAt: await e.lastModified()));
        } on Exception {
          // 读不了 / 不是文本：跳过这一条，别的照常
        }
      }
    } on FileSystemException {
      // 目录读不了：当作没有
    }
    out.sort((a, b) => a.title.compareTo(b.title));
    return out;
  }

  void _publish(List<MemoryEntry> next, {bool force = false}) {
    final same =
        !force &&
        next.length == _entries.length &&
        [for (var i = 0; i < next.length; i++) next[i].id == _entries[i].id && next[i].title == _entries[i].title && next[i].body == _entries[i].body].every((x) => x);
    _entries = List.unmodifiable(next);
    if (!same) onChanged?.call();
  }

  Future<void> _loadUndo() async {
    if (_undoLoaded) return;
    _undoLoaded = true;
    // 文件坏了：readJsonFile 备份后返回 null，这里当作没有可撤销的。
    final decoded = await readJsonFile(_undoFile, accept: (j) => j is List, label: '记忆的撤销记录');
    _changes = List.unmodifiable([for (final c in decoded is List ? decoded : const []) ?MemoryChange.fromJson(c)]);
  }

  Future<void> _remember(MemoryChange change) async {
    await _loadUndo();
    final next = [..._changes, change];
    _changes = List.unmodifiable(next.length > kMemoryUndoDepth ? next.sublist(next.length - kMemoryUndoDepth) : next);
    await _saveUndo();
  }

  Future<void> _saveUndo() async {
    try {
      await writeJsonAtomic(_undoFile, [for (final c in _changes) c.toJson()]);
    } on FileSystemException {
      // 记不下撤销记录不影响记忆本身
    }
  }

  /// 重新从盘上读一遍（外面可能手改过文件）。读不了也不抛。
  Future<List<MemoryEntry>> load() => _locked(() async {
    await _loadUndo();
    _publish(await _scan());
    return _entries;
  });

  MemoryEntry? _find(List<MemoryEntry> list, String key) {
    final k = key.trim();
    final lower = k.toLowerCase();
    return list.where((e) => e.title == k).firstOrNull ?? list.where((e) => e.id == k).firstOrNull ?? list.where((e) => e.title.toLowerCase() == lower).firstOrNull;
  }

  /// 按标题（或文件名）找一条；没有是 null。用的是最近一次读到的内容。
  MemoryEntry? find(String key) => _find(_entries, key);

  static String cleanTitle(String raw) {
    final title = raw.replaceAll(RegExp(r'\s+'), ' ').trim().replaceFirst(RegExp(r'^#+\s*'), '');
    if (title.isEmpty) throw MemoryException('标题不能为空');
    if (title.length > kMemoryMaxTitleChars) throw MemoryException('标题太长（${title.length} 字，最多 $kMemoryMaxTitleChars 字）');
    return title;
  }

  /// 新增或改写一条：同标题的就改写，没有就新增。[replaceId] 给了就是“改这一条”（标题可以一起改）。
  /// 不合规（空、太长、像密钥、超过条数 / 总量上限）抛 [MemoryException]，什么都不写。
  Future<({MemoryEntry entry, bool created})> write(String rawTitle, String rawBody, {String by = 'agent', String? replaceId}) => _locked(() async {
    final title = cleanTitle(rawTitle);
    final body = rawBody.replaceAll('\r\n', '\n').trim();
    if (body.isEmpty) throw MemoryException('正文不能为空');
    if (body.length > kMemoryMaxBodyChars) throw MemoryException('正文太长（${body.length} 字，一条最多 $kMemoryMaxBodyChars 字）。写短一点，或者拆成几条');
    if (looksLikeSecret('$title\n$body')) {
      throw MemoryException('内容里有像密钥、令牌或密码的东西，没有写入。记忆里不能存这些；如果确实不是密钥，换一种不带“key: 值”“token=值”样子的说法');
    }
    final current = await _scan();
    final old = replaceId == null ? _find(current, title) : current.where((e) => e.id == replaceId).firstOrNull;
    if (replaceId != null && old == null) throw MemoryException('要改的这条记忆已经不在了');
    final clash = current.where((e) => e.title == title && e.id != old?.id).firstOrNull;
    if (clash != null) throw MemoryException('已经有一条叫“$title”的记忆了，换个标题');
    if (old == null && current.length >= kMemoryMaxEntries) throw MemoryException('${scope.label}已经有 $kMemoryMaxEntries 条，到上限了。先删掉或合并几条再记');
    final total = current.fold<int>(0, (n, e) => n + (e.id == old?.id ? 0 : e.body.length)) + body.length;
    if (total > kMemoryMaxTotalChars) throw MemoryException('${scope.label}加起来会超过 $kMemoryMaxTotalChars 字的上限。先删掉或精简几条再记');

    var id = old?.id ?? memoryFileStem(title);
    if (old == null) {
      final stem = id;
      for (var n = 2; current.any((e) => e.id == id) || await _fileOf(id).exists(); n++) {
        id = '$stem-$n';
      }
    }
    final file = _fileOf(id);
    String? before;
    try {
      if (await file.exists()) before = await file.readAsString();
    } on Exception {
      before = null;
    }
    final text = _encode(title, body);
    try {
      await writeStringAtomic(file, text);
    } on FileSystemException catch (e) {
      throw MemoryException('没写进去：${e.osError?.message ?? e.message}');
    }
    await _remember(MemoryChange(id: id, title: title, before: before, after: text, at: DateTime.now(), by: by));
    _publish(await _scan(), force: true);
    final entry = _entries.where((e) => e.id == id).firstOrNull ?? MemoryEntry(scope: scope, id: id, title: title, body: body, updatedAt: DateTime.now());
    return (entry: entry, created: old == null);
  });

  /// 删一条（按标题或文件名）。没有这条抛 [MemoryException]。
  Future<MemoryEntry> delete(String key, {String by = 'agent'}) => _locked(() async {
    final old = _find(await _scan(), key);
    if (old == null) throw MemoryException('${scope.label}里没有叫“${key.trim()}”的这一条');
    final file = _fileOf(old.id);
    String? before;
    try {
      before = await file.readAsString();
      await file.delete();
    } on FileSystemException catch (e) {
      throw MemoryException('没删掉：${e.osError?.message ?? e.message}');
    }
    await _remember(MemoryChange(id: old.id, title: old.title, before: before, after: null, at: DateTime.now(), by: by));
    _publish(await _scan(), force: true);
    return old;
  });

  /// 清空这一处的全部记忆（撤销记录一起清：清空不能撤销）。返回删了几条。
  Future<int> clear() => _locked(() async {
    final all = await _scan();
    var n = 0;
    for (final e in all) {
      try {
        await _fileOf(e.id).delete();
        n++;
      } on FileSystemException {
        // 这一条删不掉：留着，别的照删
      }
    }
    _undoLoaded = true;
    _changes = const [];
    try {
      if (await _undoFile.exists()) await _undoFile.delete();
    } on FileSystemException {
      // 删不掉就留着
    }
    _publish(await _scan(), force: true);
    return n;
  });

  /// 撤销最近一次改动：把那个文件放回改之前的样子。
  /// 那之后文件又被改过（和我们写进去的不一样了）就不动它，抛 [MemoryException]，这一步撤销记录作废。
  Future<MemoryChange> undoLast() => _locked(() async {
    await _loadUndo();
    if (_changes.isEmpty) throw MemoryException('没有可以撤销的改动');
    final last = _changes.last;
    _changes = List.unmodifiable(_changes.sublist(0, _changes.length - 1));
    await _saveUndo();
    final file = _fileOf(last.id);
    String? now;
    try {
      if (await file.exists()) now = await file.readAsString();
    } on Exception {
      now = null;
    }
    if (now != last.after) throw MemoryException('“${last.title}”在那之后又被改过，没有动它');
    try {
      final before = last.before;
      if (before == null) {
        if (await file.exists()) await file.delete();
      } else {
        await writeStringAtomic(file, before);
      }
    } on FileSystemException catch (e) {
      throw MemoryException('没撤销成：${e.osError?.message ?? e.message}');
    }
    _publish(await _scan(), force: true);
    return last;
  });
}

/// 全应用的记忆入口：全局那一处 + 每个工作区各一处，外加两个开关。
class AppMemory {
  AppMemory(this.settings, String globalDir) {
    global = MemoryStore(globalDir, MemoryScope.global, onChanged: _changed);
  }

  final SettingsStore settings;
  late final MemoryStore global;
  final Map<String, MemoryStore> _projects = {};

  /// 文件记忆总开关（默认开）。关掉：提示词里不带记忆、记忆工具不出现、不做后台整理。
  bool get enabled => settings.getBool(SettingKeys.memoryEnabled, true);

  /// 每轮结束后自动整理（默认关——每次多花一次模型调用）。
  bool get autoConsolidate => enabled && settings.getBool(SettingKeys.memoryAutoConsolidate);

  /// 某个工作区的项目记忆（同一个工作区始终是同一个对象）。
  /// 路径过一遍 [PathGuard]：.lopicode/memory 被换成指到工作区外面的符号链接时直接报错。
  MemoryStore project(Project project) {
    final dir = project.guard.resolve('${PathGuard.reservedDir}/memory', allowReserved: true);
    return _projects.putIfAbsent(dir, () => MemoryStore(dir, MemoryScope.project, onChanged: _changed));
  }

  /// 把全局和这个工作区的记忆从盘上重新读一遍（每轮开始前做一次）。
  Future<void> refresh(Project? project) async {
    await global.load();
    if (project != null) {
      try {
        await this.project(project).load();
      } on PathGuardException catch (e) {
        CrashLog.instance.note('项目记忆读不了：${e.message}', source: '记忆');
      }
    }
  }

  /// 记忆变了（状态层据此通知界面）。
  final List<void Function()> changeListeners = [];

  void _changed() {
    for (final listener in List.of(changeListeners)) {
      listener();
    }
  }

  // ── 后台整理用的两样（放在这里是为了测试能换掉时钟、能等它做完）──────────
  /// 现在几点（测试里可以换）。
  DateTime Function() now = DateTime.now;

  final Set<Future<void>> _background = {};

  /// 记一个正在后台跑的整理。
  void track(Future<void> work) {
    _background.add(work);
    unawaited(work.whenComplete(() => _background.remove(work)));
  }

  /// 等后台的整理都做完（测试、退出前用）。
  Future<void> idle() async {
    while (_background.isNotEmpty) {
      await Future.wait(_background.toList());
    }
  }
}
