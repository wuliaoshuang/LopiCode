// 后台命令：让一条命令（开发服务器、监听、长构建）在后台跑着，Agent 接着干别的。
//
// 这里是“干活的”：起进程、把输出写进日志文件、停止、记账。一个工作区一个 [BackgroundCommands]。
// 给模型用的工具在 background_tools.dart；界面看的快照在 lib/state/workspace_background.dart。
//
// 规矩：
// - 任务归属于一段（主）对话：模型只能看、停自己这段对话起的；
// - 同一个工作区同时最多 [kMaxBackgroundRunning] 个在跑；
// - 输出原样（两路合在一起）写到 `.lopicode/outputs/bg-….txt`，Agent 可以用 read_file 读、不能写不能删。
//   每个日志最多 [kMaxBackgroundLogBytes]：超了丢掉前一半、留最新的；
//   已结束的任务最多留 [kKeepEndedBackground] 条，日志合计超过 [kMaxBackgroundLogsTotal] 从最旧的删；
// - 停止走 process_tree.dart 的整树清理；命令自己结束后也凭记号把它留下的进程清掉；
// - 任务清单存在 `.lopicode/background.json`。应用被杀后重开：上次还“在跑”的标成“已中断”，
//   凭记号把可能留下的进程清掉，**不自动重跑**；
// - 工作区关掉、应用退出（[dispose]）：全部立刻结束。
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:lopicode/agent/command_output_store.dart';
import 'package:lopicode/agent/command_runner.dart';
import 'package:lopicode/agent/process_tree.dart';
import 'package:lopicode/core/path_guard.dart';
import 'package:lopicode/core/safe_file.dart';
import 'package:path/path.dart' as p;

/// 同一个工作区同时最多几个后台命令在跑。
const int kMaxBackgroundRunning = 4;

/// 已结束的任务最多留几条（连同日志）。
const int kKeepEndedBackground = 12;

/// 一个后台命令的日志文件最多多大（4 MB）；超了只留最新的一半。
const int kMaxBackgroundLogBytes = 4 * 1024 * 1024;

/// 已结束任务的日志合计最多多大（24 MB）。
const int kMaxBackgroundLogsTotal = 24 * 1024 * 1024;

/// 模型一次“接着读”最多拿到多少字节；再多只给最后这么多，并说明跳过了多少。
const int kBackgroundReadBytes = 12000;

/// 任务清单存在哪（工作区内的相对路径）。
const String kBackgroundFile = '${PathGuard.reservedDir}/background.json';

enum BackgroundStatus {
  running('在跑'),
  exited('已结束'),
  stopped('已停止'),
  interrupted('已中断');

  const BackgroundStatus(this.label);
  final String label;

  static BackgroundStatus? byName(Object? name) => values.where((s) => s.name == name).firstOrNull;
}

/// 谁停的。
abstract final class StoppedBy {
  static const user = 'user';
  static const agent = 'agent';

  /// 工作区关掉 / 应用退出。
  static const close = 'close';
}

/// 一个后台命令（不可变快照）。
class BackgroundTask {
  const BackgroundTask({
    required this.id,
    required this.convId,
    required this.command,
    required this.startedAt,
    required this.log,
    required this.tag,
    this.status = BackgroundStatus.running,
    this.endedAt,
    this.exitCode,
    this.bytes = 0,
    this.notified = false,
    this.stoppedBy,
  });

  /// 任务号（这个工作区里从 1 往上数，不重复）。
  final int id;

  /// 归属的主对话。
  final String convId;
  final String command;
  final DateTime startedAt;
  final DateTime? endedAt;
  final BackgroundStatus status;
  final int? exitCode;

  /// 日志文件（工作区内的相对路径）。
  final String log;

  /// 一共输出了多少字节（包括已经被丢掉的前面部分）。
  final int bytes;

  /// 结束这件事模型知道了没有（知道了就不再通知）。
  final bool notified;

  /// 进程记号（见 process_tree.dart）。
  final String tag;
  final String? stoppedBy;

  bool get running => status == BackgroundStatus.running;

  /// 跑了多久（还在跑就算到 [now]）。
  Duration age(DateTime now) => (endedAt ?? now).difference(startedAt);

  BackgroundTask copyWith({BackgroundStatus? status, DateTime? endedAt, int? exitCode, int? bytes, bool? notified, String? stoppedBy}) => BackgroundTask(
    id: id,
    convId: convId,
    command: command,
    startedAt: startedAt,
    log: log,
    tag: tag,
    status: status ?? this.status,
    endedAt: endedAt ?? this.endedAt,
    exitCode: exitCode ?? this.exitCode,
    bytes: bytes ?? this.bytes,
    notified: notified ?? this.notified,
    stoppedBy: stoppedBy ?? this.stoppedBy,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'conv': convId,
    'command': command,
    'startedAt': startedAt.toUtc().toIso8601String(),
    'endedAt': endedAt?.toUtc().toIso8601String(),
    'status': status.name,
    'exitCode': exitCode,
    'log': log,
    'bytes': bytes,
    'notified': notified,
    'tag': tag,
    'stoppedBy': stoppedBy,
  };

  /// 读不懂（旧版本 / 坏数据）返回 null，不抛。
  static BackgroundTask? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'], conv = j['conv'], command = j['command'], log = j['log'], started = j['startedAt'], ended = j['endedAt'];
    final status = BackgroundStatus.byName(j['status']);
    final startedAt = started is String ? DateTime.tryParse(started) : null;
    if (id is! int || id < 1 || conv is! String || command is! String || log is! String || status == null || startedAt == null) return null;
    if (!isCommandOutputPath(log) || !p.basename(log).startsWith('bg-')) return null;
    final code = j['exitCode'], bytes = j['bytes'], tag = j['tag'], by = j['stoppedBy'];
    return BackgroundTask(
      id: id,
      convId: conv,
      command: command,
      startedAt: startedAt.toLocal(),
      endedAt: ended is String ? DateTime.tryParse(ended)?.toLocal() : null,
      status: status,
      exitCode: code is int ? code : null,
      log: log,
      bytes: bytes is int && bytes >= 0 ? bytes : 0,
      notified: j['notified'] == true,
      tag: tag is String ? tag : '',
      stoppedBy: by is String ? by : null,
    );
  }
}

/// 起不了后台命令的原因（给模型看的人话）。
class BackgroundCommandError implements Exception {
  BackgroundCommandError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// 读到的一段输出。
class BackgroundOutput {
  const BackgroundOutput(this.task, this.text, {this.skipped = 0});
  final BackgroundTask task;
  final String text;

  /// 前面有多少字节没给（输出太多只给了最后一段，或者早先的已经被丢掉）。
  final int skipped;
}

class _Live {
  _Live(this.started, this.raf);
  final StartedCommand started;
  final RandomAccessFile raf;

  /// 日志文件开头对应“总输出”的第几个字节（丢过前面的以后不是 0）。
  int base = 0;
  int size = 0;
  int get written => base + size;
  bool closed = false;
  String? stoppedBy;
  Future<void>? stopping;
  final Completer<void> done = Completer<void>();
}

/// 一段字节末尾“完整的 UTF-8”有多长：最后一个字符只来了一半就先不算它。
int completeUtf8Length(List<int> bytes) {
  var i = bytes.length - 1;
  var back = 0;
  while (i >= 0 && back < 3 && (bytes[i] & 0xC0) == 0x80) {
    i--;
    back++;
  }
  if (i < 0) return bytes.length;
  final lead = bytes[i];
  final need = lead >= 0xF0
      ? 3
      : lead >= 0xE0
      ? 2
      : lead >= 0xC0
      ? 1
      : 0;
  return need > back ? i : bytes.length;
}

class BackgroundCommands {
  BackgroundCommands(this.guard);
  final PathGuard guard;

  /// 清单或某个任务的输出量变了。
  void Function()? onChanged;

  /// 一个任务结束了（自己退出 / 被停）。
  void Function(BackgroundTask task)? onEnded;

  final List<BackgroundTask> _tasks = [];
  final Map<int, _Live> _live = {};
  final Map<int, int> _cursor = {};
  int _next = 1;
  int _starting = 0;
  bool _disposed = false;
  Future<void>? _loading;
  Timer? _tick;

  bool get disposed => _disposed;

  /// 全部任务，按任务号从小到大。
  List<BackgroundTask> get tasks => List.unmodifiable(_tasks);
  List<BackgroundTask> of(String convId) => [..._tasks.where((t) => t.convId == convId)];
  BackgroundTask? byId(int id) => _tasks.where((t) => t.id == id).firstOrNull;
  int get runningCount => _tasks.where((t) => t.running).length;

  File get _file => File(guard.resolve(kBackgroundFile, allowReserved: true));
  File _logOf(BackgroundTask t) => File(guard.resolve(t.log, allowReserved: true));

  // ── 读写清单 ─────────────────────────────────────────
  /// 把上次的清单读出来（只读一次）。上次还“在跑”的标成“已中断”。
  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    final decoded = await readJsonFile(_file, accept: (j) => j is Map, label: '后台命令清单');
    if (_disposed || decoded is! Map) return;
    final next = decoded['next'];
    final list = decoded['tasks'];
    var changed = false;
    for (final j in list is List ? list : const []) {
      var task = BackgroundTask.fromJson(j);
      if (task == null || _tasks.any((t) => t.id == task!.id)) continue;
      if (task.running) {
        // 应用上次是被关掉 / 被系统回收的：命令没法接着管了。留下的进程凭记号清掉，不重跑。
        killTaggedProcesses(task.tag);
        task = task.copyWith(status: BackgroundStatus.interrupted, notified: false);
        changed = true;
      }
      _tasks.add(task);
    }
    _tasks.sort((a, b) => a.id.compareTo(b.id));
    final top = _tasks.isEmpty ? 0 : _tasks.last.id;
    _next = next is int && next > top ? next : top + 1;
    if (changed) await _save();
    if (_tasks.isNotEmpty) onChanged?.call();
  }

  Future<void> _save() async {
    try {
      await writeJsonAtomic(_file, {
        'next': _next,
        'tasks': [for (final t in _tasks) t.toJson()],
      });
    } on FileSystemException {
      // 存不了（磁盘满）：任务照跑，只是重开后不记得它
    } on PathGuardException {
      // 同上
    }
  }

  void _replace(int id, BackgroundTask Function(BackgroundTask t) change) {
    final i = _tasks.indexWhere((t) => t.id == id);
    if (i >= 0) _tasks[i] = change(_tasks[i]);
  }

  // ── 启动 ─────────────────────────────────────────────
  /// 起一个后台命令，进程起来就返回。到上限、工作区已关抛 [BackgroundCommandError]；进程起不来抛 [ProcessException]。
  Future<BackgroundTask> start(String convId, String command, HasBackgroundStart runner) async {
    await load();
    if (_disposed) throw BackgroundCommandError('工作区已经关闭，没有启动');
    if (runningCount + _starting >= kMaxBackgroundRunning) {
      throw BackgroundCommandError('已经有 $kMaxBackgroundRunning 个后台命令在跑（上限 $kMaxBackgroundRunning 个），这一条没有启动。先等一个结束，或者停掉一个不用的');
    }
    _starting++;
    final id = _next++;
    final tag = newCommandTag();
    final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(RegExp('[^0-9]'), '').substring(0, 14);
    final rel = '$kOutputsDir/bg-$stamp-$id.txt';
    final StartedCommand started;
    final RandomAccessFile raf;
    try {
      final file = File(guard.resolve(rel, allowReserved: true));
      try {
        file.parent.createSync(recursive: true);
        raf = file.openSync(mode: FileMode.write);
      } on FileSystemException catch (e) {
        throw BackgroundCommandError('建不了日志文件（${e.osError?.message ?? e.message}），没有启动');
      }
      try {
        started = await runner.startBackground(command, workingDirectory: guard.root, tag: tag);
      } on ProcessException {
        raf.closeSync();
        _deleteQuietly(file);
        rethrow;
      }
    } finally {
      _starting--;
    }
    closeCommandStdin(started.process);
    final live = _Live(started, raf);
    final task = BackgroundTask(id: id, convId: convId, command: command, startedAt: DateTime.now(), log: rel, tag: tag);
    void take(List<int> data) => _append(live, data);
    // 先把“读完了”的 Future 拿到手再等退出码（和 runAndCollect 同一个道理）。
    final out = started.process.stdout.listen(take, onError: (_) {});
    final err = started.process.stderr.listen(take, onError: (_) {});
    final Future<void> drained = Future.wait([out.asFuture<void>(), err.asFuture<void>()]).then((_) {});
    if (_disposed) {
      // 起到一半工作区关了：不留它
      started.tree.killNow();
      unawaited(_watch(id, live, out, err, drained));
      throw BackgroundCommandError('工作区已经关闭，没有启动');
    }
    _tasks.add(task);
    _live[id] = live;
    unawaited(_watch(id, live, out, err, drained));
    await _save();
    onChanged?.call();
    return task;
  }

  void _append(_Live live, List<int> data) {
    if (live.closed || data.isEmpty) return;
    try {
      live.raf.writeFromSync(data);
      live.size += data.length;
      if (live.size > kMaxBackgroundLogBytes) {
        // 太大了：只留最新的一半。读的人按“总输出的第几个字节”记位置，所以丢掉前面不影响“接着读”。
        const keep = kMaxBackgroundLogBytes ~/ 2;
        live.raf.setPositionSync(live.size - keep);
        final tail = live.raf.readSync(keep);
        live.raf
          ..truncateSync(0)
          ..setPositionSync(0)
          ..writeFromSync(tail);
        live.base += live.size - tail.length;
        live.size = tail.length;
      }
    } on FileSystemException {
      live.closed = true; // 写不进去了（磁盘满）：不再写，命令照跑
    }
    _tick ??= Timer(const Duration(milliseconds: 400), () {
      _tick = null;
      if (_disposed) return;
      _syncBytes();
      onChanged?.call();
    });
  }

  void _syncBytes() {
    for (final e in _live.entries) {
      _replace(e.key, (t) => t.bytes == e.value.written ? t : t.copyWith(bytes: e.value.written));
    }
  }

  Future<void> _watch(int id, _Live live, StreamSubscription<List<int>> out, StreamSubscription<List<int>> err, Future<void> drained) async {
    final code = await live.started.process.exitCode;
    // 主进程结束了输出却没读完：它留下的进程还攥着管道。最多再等一小会儿。
    await drained.timeout(kOutputDrainGrace, onTimeout: () {});
    await out.cancel();
    await err.cancel();
    final tag = byId(id)?.tag;
    // 结束了就不该再留东西：它留在后面的进程凭记号清掉（PRoot 里 --kill-on-exit 本来就会这么做，本机 shell 靠这里）。
    if (tag != null && tag.isNotEmpty) killTaggedProcesses(tag);
    live.closed = true;
    try {
      live.raf.closeSync();
    } on FileSystemException {
      // 已经关了
    }
    try {
      await live.started.onExit?.call();
    } on Exception {
      // 收尾（放掉保活）失败不影响记账
    }
    _live.remove(id);
    if (_disposed || byId(id) == null) {
      live.done.complete();
      return;
    }
    final by = live.stoppedBy;
    _replace(
      id,
      (t) => t.copyWith(
        status: by == null ? BackgroundStatus.exited : BackgroundStatus.stopped,
        exitCode: code,
        endedAt: DateTime.now(),
        bytes: live.written,
        stoppedBy: by,
        notified: by == StoppedBy.agent,
      ),
    );
    await _prune();
    await _save();
    live.done.complete();
    if (_disposed) return;
    onChanged?.call();
    final ended = byId(id);
    if (ended != null) onEnded?.call(ended);
  }

  // ── 停止 ─────────────────────────────────────────────
  /// 停掉一个任务（整棵进程树），等它收完尾。已经不在跑就原样返回；没有这个任务返回 null。
  Future<BackgroundTask?> stop(int id, {required String by}) async {
    final live = _live[id];
    if (live == null) return byId(id);
    live.stoppedBy ??= by;
    await (live.stopping ??= live.started.tree.terminate(exited: live.started.process.exitCode, grace: kStopGrace));
    await live.done.future.timeout(const Duration(seconds: 5), onTimeout: () {});
    return byId(id);
  }

  /// 这段对话删掉了：它的任务停掉，记录和日志一起删。
  Future<void> dropConversation(String convId) async {
    final mine = of(convId);
    if (mine.isEmpty) return;
    for (final t in mine) {
      _live.remove(t.id)?.started.tree.killNow();
      _cursor.remove(t.id);
      _deleteQuietly(_logOf(t));
    }
    _tasks.removeWhere((t) => t.convId == convId);
    await _save();
    onChanged?.call();
  }

  /// 工作区关掉 / 应用退出：全部立刻结束，不等。
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _tick?.cancel();
    _tick = null;
    final now = DateTime.now();
    var changed = false;
    for (final e in _live.entries) {
      e.value.started.tree.killNow();
      _replace(e.key, (t) => t.copyWith(status: BackgroundStatus.stopped, endedAt: now, bytes: e.value.written, stoppedBy: StoppedBy.close, notified: false));
      changed = true;
    }
    onChanged = null;
    onEnded = null;
    // 来不及等：存不上也没关系，重开时还“在跑”的会被标成“已中断”。
    if (changed) unawaited(_save());
  }

  // ── 读输出 ───────────────────────────────────────────
  /// 日志文件现在盖住“总输出”的哪一段：（开头是第几个字节，文件多长）。
  (int, int) _extent(BackgroundTask t) {
    final live = _live[t.id];
    if (live != null) return (live.base, live.size);
    try {
      final length = _logOf(t).lengthSync();
      return (t.bytes > length ? t.bytes - length : 0, length);
    } on FileSystemException {
      return (t.bytes, 0); // 日志已经被清理掉
    }
  }

  Uint8List _range(BackgroundTask t, int offset, int length) {
    if (length <= 0) return Uint8List(0);
    try {
      final raf = _logOf(t).openSync();
      try {
        raf.setPositionSync(offset);
        return raf.readSync(length);
      } finally {
        raf.closeSync();
      }
    } on FileSystemException {
      return Uint8List(0);
    }
  }

  static int _skipBrokenStart(List<int> bytes) {
    var i = 0;
    while (i < bytes.length && i < 3 && (bytes[i] & 0xC0) == 0x80) {
      i++;
    }
    return i;
  }

  /// 模型“接着读”：从它上次读到的地方起的新输出，读完把位置往后挪。没有这个任务返回 null。
  BackgroundOutput? readNew(int id) {
    final task = byId(id);
    if (task == null) return null;
    final (base, size) = _extent(task);
    final end = base + size;
    var cursor = _cursor[id] ?? 0;
    if (cursor > end) cursor = base;
    final from = cursor < base ? base : cursor;
    final over = end - from - kBackgroundReadBytes;
    final start = over > 0 ? from + over : from;
    final bytes = _range(task, start - base, end - start);
    final lead = start > cursor ? _skipBrokenStart(bytes) : 0;
    final length = task.running ? completeUtf8Length(bytes) : bytes.length;
    _cursor[id] = start + (length < lead ? lead : length);
    return BackgroundOutput(task, length <= lead ? '' : const Utf8Decoder(allowMalformed: true).convert(bytes, lead, length), skipped: start - cursor);
  }

  /// 最后 [lines] 行（不挪“接着读”的位置）。最多往回看 [maxBytes]。
  String tail(int id, {int lines = 20, int maxBytes = 64 * 1024}) {
    final task = byId(id);
    if (task == null) return '';
    final (_, size) = _extent(task);
    final from = size > maxBytes ? size - maxBytes : 0;
    final bytes = _range(task, from, size - from);
    var text = const Utf8Decoder(allowMalformed: true).convert(bytes, from > 0 ? _skipBrokenStart(bytes) : 0);
    if (from > 0 && text.contains('\n')) text = text.substring(text.indexOf('\n') + 1); // 第一行多半只剩半截
    final all = const LineSplitter().convert(text);
    return (all.length > lines ? all.sublist(all.length - lines) : all).join('\n');
  }

  // ── 通知 ─────────────────────────────────────────────
  /// 这段对话里“结束了但模型还不知道”的任务。
  List<BackgroundTask> unnotified(String convId) => [..._tasks.where((t) => t.convId == convId && !t.running && !t.notified)];

  /// 记下“模型知道了 / 又不知道了”（通知交出去后请求失败会还回来）。
  void setNotified(Iterable<int> ids, {bool value = true}) {
    var changed = false;
    for (final id in ids) {
      final t = byId(id);
      if (t == null || t.running || t.notified == value) continue;
      _replace(id, (t) => t.copyWith(notified: value));
      changed = true;
    }
    if (!changed) return;
    unawaited(_save());
    onChanged?.call();
  }

  // ── 清理 ─────────────────────────────────────────────
  void _deleteQuietly(File file) {
    try {
      if (file.existsSync()) file.deleteSync();
    } on FileSystemException {
      // 删不掉：下次再清
    }
  }

  int _sizeOf(BackgroundTask t) {
    try {
      return _logOf(t).lengthSync();
    } on FileSystemException {
      return 0;
    }
  }

  /// 已结束的只留最近 [kKeepEndedBackground] 条，日志合计不超过 [kMaxBackgroundLogsTotal]；最新结束的那条总是留着。
  Future<void> _prune() async {
    final ended = [..._tasks.where((t) => !t.running)]..sort((a, b) => b.id.compareTo(a.id));
    var total = 0;
    for (var i = 0; i < ended.length; i++) {
      total += _sizeOf(ended[i]);
      if (i > 0 && (i >= kKeepEndedBackground || total > kMaxBackgroundLogsTotal)) {
        _deleteQuietly(_logOf(ended[i]));
        _cursor.remove(ended[i].id);
        _tasks.remove(ended[i]);
      }
    }
  }
}
