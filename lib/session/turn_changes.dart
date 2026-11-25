// “这次改过的文件”：一轮里每个文件从头到尾合起来改成了什么样。纯计算，不读盘、不碰状态。
//
// - 每段正在跑的对话一本账（[TurnChangeBook.begin] 开、[TurnChangeBook.end] 收）；
// - 子代理改的文件同时记进它自己那本和所有还在跑的上级那本（上级这一轮的清单里也有）；
// - 同一个文件改了好几次：只记最早的“改之前”和最新的“改之后”，收的时候比一次，得到这一轮的合并对比；
//   新建了又删掉、改了又改回去的，净效果是没变，不进清单；
// - 有一次改动拿不到全文（二进制、太大、整个目录被删）：这个文件没有合并对比，只留说明。
// - 只认 write_file / edit_file / delete_file 这三个工具报上来的改动；命令行里改的文件这里看不见。
//
// 存盘上限（自己定的，改这里要同时改 test/turn_changes_test.dart）：
// 清单最多 [kTurnFilesMax] 个文件；对比加起来超过 [kTurnFilesDiffChars] 字符后，后面的文件只存统计不存对比。
import 'package:lopicode/agent/line_diff.dart';

/// 一轮的清单最多记多少个文件。
const int kTurnFilesMax = 200;

/// 一轮的清单里，对比加起来最多存多少字符。
const int kTurnFilesDiffChars = 200000;

class _Entry {
  _Entry(this.first);

  /// 这一轮里它的第一次改动（“改之前”取它的）。
  final FileChange first;
  late FileChange last = first;

  /// 有哪一次拿不到全文。
  bool opaque = false;
  int added = 0, removed = 0;
}

class _Ledger {
  _Ledger(this.parentId);
  final String? parentId;
  final Map<String, _Entry> files = {};

  void record(FileChange c) {
    final e = files.putIfAbsent(c.path, () => _Entry(c))..last = c;
    e.added += c.added;
    e.removed += c.removed;
    final needBefore = c.kind != ChangeKind.created, needAfter = c.kind != ChangeKind.deleted;
    if ((needBefore && c.before == null) || (needAfter && c.after == null)) e.opaque = true;
  }

  List<FileChange> close() {
    final out = <FileChange>[];
    for (final MapEntry(key: path, value: e) in files.entries) {
      final existed = e.first.kind != ChangeKind.created;
      final exists = e.last.kind != ChangeKind.deleted;
      if (!existed && !exists) continue; // 新建了又删掉
      final kind = !existed ? ChangeKind.created : (!exists ? ChangeKind.deleted : ChangeKind.modified);
      if (e.opaque) {
        out.add(FileChange(path: path, kind: kind, added: e.added, removed: e.removed, note: e.last.note ?? e.first.note ?? '这个文件没有生成对比'));
        continue;
      }
      final before = existed ? e.first.before : null;
      final after = exists ? e.last.after : null;
      if (existed && exists && before == after) continue; // 改了又改回去
      out.add(diffFileChange(path, kind: kind, before: before, after: after).slim);
    }
    out.sort((a, b) => a.path.compareTo(b.path));
    return capTurnFiles(out);
  }
}

/// 按上限收紧一轮的清单。
List<FileChange> capTurnFiles(List<FileChange> files) {
  var chars = 0;
  final out = <FileChange>[];
  for (final f in files.take(kTurnFilesMax)) {
    final size = f.storedChars;
    if (chars + size > kTurnFilesDiffChars) {
      out.add(f.statsOnly);
    } else {
      chars += size;
      out.add(f.slim);
    }
  }
  return out;
}

/// 清单的合计：（文件数，增的行数，删的行数）。
({int files, int added, int removed}) totalsOfChanges(List<FileChange> files) => (files: files.length, added: files.fold(0, (s, f) => s + f.added), removed: files.fold(0, (s, f) => s + f.removed));

class TurnChangeBook {
  final Map<String, _Ledger> _open = {};

  /// 一段对话开始跑一轮。[parentId]：它的上级对话（主对话为 null）。
  void begin(String convId, {String? parentId}) => _open[convId] = _Ledger(parentId);

  /// 记一笔改动：记进这段对话和它所有还在跑的上级。
  void record(String convId, FileChange? change) {
    if (change == null) return;
    final seen = <String>{};
    String? id = convId;
    while (id != null && seen.add(id)) {
      final ledger = _open[id];
      if (ledger == null) break;
      ledger.record(change);
      id = ledger.parentId;
    }
  }

  /// 这一轮结束：交出合并后的清单（按路径排序），这本账销掉。
  List<FileChange> end(String convId) => _open.remove(convId)?.close() ?? const [];
}
