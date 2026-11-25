// 按行对比两段文本，产出“增 / 删 / 不变”的行和 +N −M 统计。纯 Dart，不读盘、不带界面。
//
// 做法：先掐掉两头一样的行，中间那段用“最长公共子序列”算（表格法，够用也好懂）。
// 上限（都是自己定的，改这里要同时改 test/line_diff_test.dart）：
// - 任一侧超过 [kDiffMaxInputLines] 行或 [kDiffMaxInputChars] 字符：不比，只留一句说明；
// - 掐头去尾以后中间那段“旧行数 × 新行数”超过 [kDiffMaxCells]：不细比，整段算“先删后增”（统计仍然准确，只是不是最短的改法）；
// - 只保留改动附近 [kDiffContext] 行，隔得远的不变行不存（界面显示“省略 N 行”）；
// - 一份对比最多存 [kDiffStoreLines] 行、[kDiffStoreChars] 字符，一行最多 [kDiffStoreLineChars] 字符，多的截掉并记下截了多少行。
//
// 存盘只存精简后的对比（[FileChange.toJson]），不存前后两份全文。
import 'dart:typed_data';

/// 改动附近留几行不变的行。
const int kDiffContext = 3;

/// 任一侧超过这么多行就不比。
const int kDiffMaxInputLines = 20000;

/// 任一侧超过这么多字符就不比。
const int kDiffMaxInputChars = 1000000;

/// 中间那段“旧行数 × 新行数”的上限。
const int kDiffMaxCells = 4000000;

/// 一份对比最多存多少行。
const int kDiffStoreLines = 400;

/// 一份对比最多存多少字符。
const int kDiffStoreChars = 48000;

/// 一行最多存多少字符。
const int kDiffStoreLineChars = 400;

enum DiffOp { same, add, del }

/// 对比里的一行。行号从 1 开始；增的行没有旧行号，删的行没有新行号。
class DiffLine {
  const DiffLine(this.op, this.text, {this.oldNo, this.newNo});
  final DiffOp op;
  final String text;
  final int? oldNo;
  final int? newNo;
}

/// 连在一起的一段对比。[lines] 每行第一个字符是标记：空格＝不变，`+`＝增，`-`＝删。
class DiffHunk {
  const DiffHunk(this.oldStart, this.newStart, this.lines);

  /// 这一段第一行在旧文件 / 新文件里是第几行。
  final int oldStart;
  final int newStart;
  final List<String> lines;

  int get oldCount => lines.where((l) => !l.startsWith('+')).length;
  int get newCount => lines.where((l) => !l.startsWith('-')).length;

  /// 带行号展开。
  List<DiffLine> get rows {
    var o = oldStart, n = newStart;
    return [
      for (final l in lines)
        switch (l.isEmpty ? ' ' : l[0]) {
          '+' => DiffLine(DiffOp.add, l.substring(1), newNo: n++),
          '-' => DiffLine(DiffOp.del, l.substring(1), oldNo: o++),
          _ => DiffLine(DiffOp.same, l.isEmpty ? '' : l.substring(1), oldNo: o++, newNo: n++),
        },
    ];
  }

  Map<String, dynamic> toJson() => {'o': oldStart, 'n': newStart, 'l': lines};
}

enum ChangeKind {
  created('new', '新建'),
  modified('mod', '修改'),
  deleted('del', '删除');

  const ChangeKind(this.id, this.label);
  final String id;
  final String label;
}

/// 一个文件的一次改动（或一轮里合并后的改动）。
class FileChange {
  const FileChange({required this.path, required this.kind, this.added = 0, this.removed = 0, this.hunks = const [], this.cutLines = 0, this.note, this.before, this.after});

  /// 工作区内的相对路径。
  final String path;
  final ChangeKind kind;

  /// 增 / 删了多少行（没有对比时是 0）。
  final int added;
  final int removed;
  final List<DiffHunk> hunks;

  /// 因为太长没存下来的对比行数。
  final int cutLines;

  /// 没有对比（或者对比不完整）时的一句说明：二进制、太大、是目录……
  final String? note;

  /// 改动前后的全文。只在内存里用来算“这一轮的合并对比”，**不存盘**。
  final String? before;
  final String? after;

  bool get hasDiff => hunks.isNotEmpty;

  /// “+3 −1”；一行都没有时为空。
  String get stat => [if (added > 0) '+$added', if (removed > 0) '−$removed'].join(' ');

  /// 丢掉全文，只留精简的对比（放进聊天条目、存盘前用）。
  FileChange get slim => before == null && after == null ? this : FileChange(path: path, kind: kind, added: added, removed: removed, hunks: hunks, cutLines: cutLines, note: note);

  /// 连对比也丢掉，只留统计（一轮的清单太大时用）。
  FileChange get statsOnly => FileChange(path: path, kind: kind, added: added, removed: removed, note: hunks.isEmpty ? note : '这一轮改的文件太多，这个文件的对比没有保存');

  int get storedChars => hunks.fold(0, (sum, h) => sum + h.lines.fold(0, (s, l) => s + l.length));

  Map<String, dynamic> toJson() => {
    'p': path,
    'k': kind.id,
    if (added > 0) 'a': added,
    if (removed > 0) 'r': removed,
    if (hunks.isNotEmpty) 'h': [for (final h in hunks) h.toJson()],
    if (cutLines > 0) 'x': cutLines,
    'm': ?note,
  };

  /// 读存盘的那份。类型不对、缺字段都返回 null 或者丢掉坏的部分，不抛异常。
  static FileChange? tryParse(Object? j) {
    if (j is! Map) return null;
    final path = j['p'];
    if (path is! String || path.isEmpty) return null;
    final kind = ChangeKind.values.where((k) => k.id == j['k']).firstOrNull ?? ChangeKind.modified;
    int n(Object? v) => v is int && v > 0 ? v : 0;
    final hunks = <DiffHunk>[];
    var budget = kDiffStoreLines * 2;
    final rawHunks = j['h'];
    for (final h in rawHunks is List ? rawHunks : const []) {
      if (h is! Map || budget <= 0) continue;
      final o = h['o'], nn = h['n'], l = h['l'];
      if (o is! int || nn is! int || l is! List) continue;
      final lines = [
        for (final s in l)
          if (s is String && s.isNotEmpty && ' +-'.contains(s[0])) s,
      ].take(budget).toList();
      budget -= lines.length;
      if (lines.isNotEmpty) hunks.add(DiffHunk(o < 1 ? 1 : o, nn < 1 ? 1 : nn, lines));
    }
    final note = j['m'];
    return FileChange(path: path, kind: kind, added: n(j['a']), removed: n(j['r']), hunks: hunks, cutLines: n(j['x']), note: note is String && note.isNotEmpty ? note : null);
  }
}

/// 读一串改动（“这次改过的文件”）。不是列表就是空的；坏的项丢掉。
List<FileChange> parseFileChanges(Object? j) => [for (final e in j is List ? j : const []) ?FileChange.tryParse(e)];

/// 把文本拆成行：换行符（`\n` 或 `\r\n`）不算内容；结尾的那个换行不产生多余的空行。
List<String> splitDiffLines(String text) {
  if (text.isEmpty) return const [];
  final lines = text.split('\n');
  if (lines.last.isEmpty) lines.removeLast();
  for (var i = 0; i < lines.length; i++) {
    final l = lines[i];
    if (l.endsWith('\r')) lines[i] = l.substring(0, l.length - 1);
  }
  return lines;
}

/// 逐行对比，返回完整的操作序列（含全部不变的行）。
List<DiffLine> diffLines(List<String> a, List<String> b) {
  var head = 0;
  while (head < a.length && head < b.length && a[head] == b[head]) {
    head++;
  }
  var tail = 0;
  while (tail < a.length - head && tail < b.length - head && a[a.length - 1 - tail] == b[b.length - 1 - tail]) {
    tail++;
  }
  final out = <DiffLine>[];
  var o = 1, n = 1;
  void same(String t) => out.add(DiffLine(DiffOp.same, t, oldNo: o++, newNo: n++));
  void del(String t) => out.add(DiffLine(DiffOp.del, t, oldNo: o++));
  void add(String t) => out.add(DiffLine(DiffOp.add, t, newNo: n++));

  for (var i = 0; i < head; i++) {
    same(a[i]);
  }
  final am = a.sublist(head, a.length - tail);
  final bm = b.sublist(head, b.length - tail);
  if (am.isEmpty || bm.isEmpty || am.length * bm.length > kDiffMaxCells) {
    // 一边是空的，或者太大不细比：整段先删后增。
    am.forEach(del);
    bm.forEach(add);
  } else {
    // 把行换成编号再比，快一些。
    final ids = <String, int>{};
    final x = [for (final l in am) ids.putIfAbsent(l, () => ids.length)];
    final y = [for (final l in bm) ids.putIfAbsent(l, () => ids.length)];
    final w = y.length + 1;
    // lcs[i*w+j]＝x[i:] 和 y[j:] 的最长公共子序列长度。行数上限 2 万，Uint16 装得下。
    final lcs = Uint16List((x.length + 1) * w);
    for (var i = x.length - 1; i >= 0; i--) {
      for (var j = y.length - 1; j >= 0; j--) {
        lcs[i * w + j] = x[i] == y[j] ? lcs[(i + 1) * w + j + 1] + 1 : (lcs[(i + 1) * w + j] >= lcs[i * w + j + 1] ? lcs[(i + 1) * w + j] : lcs[i * w + j + 1]);
      }
    }
    var i = 0, j = 0;
    while (i < x.length && j < y.length) {
      if (x[i] == y[j]) {
        same(am[i]);
        i++;
        j++;
      } else if (lcs[(i + 1) * w + j] >= lcs[i * w + j + 1]) {
        del(am[i++]);
      } else {
        add(bm[j++]);
      }
    }
    while (i < x.length) {
      del(am[i++]);
    }
    while (j < y.length) {
      add(bm[j++]);
    }
  }
  for (var i = a.length - tail; i < a.length; i++) {
    same(a[i]);
  }
  return out;
}

String _mark(DiffLine l) {
  final text = l.text.length > kDiffStoreLineChars ? '${l.text.substring(0, kDiffStoreLineChars)}…' : l.text;
  return switch (l.op) {
    DiffOp.add => '+$text',
    DiffOp.del => '-$text',
    DiffOp.same => ' $text',
  };
}

/// 只留改动附近的行，切成一段一段；超过存储上限就截断。返回（段，被截掉的行数）。
(List<DiffHunk>, int) hunksOf(List<DiffLine> ops, {int context = kDiffContext, int maxLines = kDiffStoreLines, int maxChars = kDiffStoreChars}) {
  final keep = List<bool>.filled(ops.length, false);
  for (var i = 0; i < ops.length; i++) {
    if (ops[i].op == DiffOp.same) continue;
    final from = i - context < 0 ? 0 : i - context;
    final to = i + context >= ops.length ? ops.length - 1 : i + context;
    for (var k = from; k <= to; k++) {
      keep[k] = true;
    }
  }
  final hunks = <DiffHunk>[];
  var lines = 0, chars = 0, cut = 0;
  var i = 0;
  while (i < ops.length) {
    if (!keep[i]) {
      i++;
      continue;
    }
    var j = i;
    while (j < ops.length && keep[j]) {
      j++;
    }
    final first = ops[i];
    // 这一段第一行的旧 / 新行号：自己没有的那一侧，往后找最近的一个；都没有就按“接在后面”算。
    int startOf(int? Function(DiffLine) pick, int Function() fallback) {
      for (var k = i; k < ops.length; k++) {
        final v = pick(ops[k]);
        if (v != null) return v;
      }
      return fallback();
    }

    final oldStart = first.oldNo ?? startOf((l) => l.oldNo, () => ops.where((l) => l.oldNo != null).length + 1);
    final newStart = first.newNo ?? startOf((l) => l.newNo, () => ops.where((l) => l.newNo != null).length + 1);
    final marked = <String>[];
    for (var k = i; k < j; k++) {
      final m = _mark(ops[k]);
      if (lines >= maxLines || chars + m.length > maxChars) {
        cut++;
        continue;
      }
      marked.add(m);
      lines++;
      chars += m.length;
    }
    if (marked.isNotEmpty) hunks.add(DiffHunk(oldStart, newStart, marked));
    i = j;
  }
  return (hunks, cut);
}

/// 算一个文件的改动。
///
/// [before]＝null：改之前没有这个文件（新建）；[after]＝null：改完文件没了（删除）。
/// [opaque] 不为空：有一侧没法按文本比（二进制、太大、是目录），只留这句说明。
FileChange diffFileChange(String path, {required ChangeKind kind, required String? before, required String? after, String? opaque}) {
  if (opaque != null) return FileChange(path: path, kind: kind, note: opaque, before: before, after: after);
  final a = before ?? '', b = after ?? '';
  if (a.length > kDiffMaxInputChars || b.length > kDiffMaxInputChars) {
    return FileChange(path: path, kind: kind, note: '文件太大（超过 $kDiffMaxInputChars 字符），没有生成对比');
  }
  final al = splitDiffLines(a), bl = splitDiffLines(b);
  if (al.length > kDiffMaxInputLines || bl.length > kDiffMaxInputLines) {
    return FileChange(path: path, kind: kind, note: '文件太长（超过 $kDiffMaxInputLines 行），没有生成对比', before: before, after: after);
  }
  final ops = diffLines(al, bl);
  final added = ops.where((l) => l.op == DiffOp.add).length;
  final removed = ops.where((l) => l.op == DiffOp.del).length;
  final (hunks, cut) = hunksOf(ops);
  String? note;
  if (added == 0 && removed == 0) {
    note = switch (kind) {
      ChangeKind.created => '新建了一个空文件',
      ChangeKind.deleted => '删除了一个空文件',
      ChangeKind.modified => a == b ? '内容没有变化' : '只有换行符或文件末尾的换行变了',
    };
  } else if (cut > 0) {
    note = '对比太长，只保存了前 $kDiffStoreLines 行左右，还有 $cut 行没有显示';
  }
  return FileChange(path: path, kind: kind, added: added, removed: removed, hunks: hunks, cutLines: cut, note: note, before: before, after: after);
}
