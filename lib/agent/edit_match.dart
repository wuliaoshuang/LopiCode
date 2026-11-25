// edit_file 的“找原文、换新文”。纯 Dart：不读盘、不带界面，只管字符串进、字符串出。
//
// 三级匹配，依次尝试，前一级找到了（哪怕找到多处）就不再往下：
// 1. 精确匹配：原文一字不差地出现在文件里（换行符 `\n` / `\r\n` 的差别不算）；
// 2. 忽略每行首尾空白：按行比，每行去掉首尾空白以后一样（缩进、行尾空格对不上也能找到）；
// 3. 首行、末行当锚点：原文至少 [kAnchorMinLines] 行；文件里找“首行一样 … 末行一样”的一段，
//    行数和原文最多差 max(1, 原文行数 ÷ 5) 行，中间那些行和原文的相似度不低于 [kAnchorSimilarity] 才算。
//    这一级是“猜”，所以只接受唯一的一处，不支持“全部替换”。
//
// 找到多处又没要求全部替换：不改，告诉模型有几处、在哪几行。找不到：不改，给出最接近的位置。
// 第 2、3 级命中后，新文按文件里那一段真实的缩进重新对齐（模型给的缩进常常和文件对不上）。
// 文件原有的换行符（CRLF / LF）和“末尾有没有换行”保持不变。
//
// 数值都是自己定的；改这里要同时改 test/edit_match_test.dart。

/// 文件超过这么多字符不做局部修改（和 write_file 的上限一致）。
const int kEditMaxChars = 1000000;

/// 锚点匹配：中间行的相似度门槛（0–1）。
const double kAnchorSimilarity = 0.7;

/// 锚点匹配：原文至少几行。
const int kAnchorMinLines = 3;

/// 报“有多处 / 改在哪”时最多列几个位置。
const int kEditListedPlaces = 5;

/// 找不到时“最接近的一段”的相似度门槛（低于它就说没有相近的内容）。
const double kNearestSimilarity = 0.5;

/// 找不到时给模型看的那一段最多几行。
const int kNearestExcerptLines = 6;

/// 找“最接近的一行”最多扫多少行（再长只做整行相等的查找）。
const int kNearestScanLines = 3000;

enum MatchLevel {
  exact('精确匹配'),
  trimmed('忽略行首尾空白的匹配'),
  anchors('首行和末行当锚点的匹配');

  const MatchLevel(this.label);
  final String label;
}

enum EditFailKind { emptyOld, same, tooLarge, ambiguous, notFound }

sealed class EditResult {
  const EditResult();
}

class EditOk extends EditResult {
  const EditOk(this.content, this.level, this.ranges, {this.similarity});

  /// 改完的全文。
  final String content;
  final MatchLevel level;

  /// 改动落在新文件的哪几行（从 1 开始，含两头），一处一段。
  final List<(int, int)> ranges;

  /// 锚点匹配时中间行的相似度。
  final double? similarity;

  int get count => ranges.length;

  /// “第 12–15 行”“第 3 行、第 20–22 行”。
  String get where {
    String one((int, int) r) => r.$1 == r.$2 ? '第 ${r.$1} 行' : '第 ${r.$1}–${r.$2} 行';
    final shown = ranges.take(kEditListedPlaces).map(one).join('、');
    return ranges.length > kEditListedPlaces ? '$shown 等 ${ranges.length} 处' : shown;
  }
}

class EditFail extends EditResult {
  const EditFail(this.kind, this.message, {this.count = 0});
  final EditFailKind kind;

  /// 给模型看的话（不带“错误：”）。
  final String message;

  /// 找到多处时是几处。
  final int count;
}

String _lf(String s) => s.replaceAll('\r\n', '\n');

class _Line {
  _Line(this.text, this.start, this.end, this.next);

  /// 不含换行符。
  final String text;

  /// 这一行在全文里的起点、内容的终点（不含换行符）、下一行的起点（含换行符）。
  final int start;
  final int end;
  final int next;
  late final String trimmed = text.trim();
}

List<_Line> _linesOf(String content) {
  final out = <_Line>[];
  var at = 0;
  while (at < content.length) {
    final nl = content.indexOf('\n', at);
    if (nl < 0) {
      out.add(_Line(content.substring(at), at, content.length, content.length));
      break;
    }
    final end = nl > at && content.codeUnitAt(nl - 1) == 13 ? nl - 1 : nl;
    out.add(_Line(content.substring(at, end), at, end, nl + 1));
    at = nl + 1;
  }
  return out;
}

/// 按行处理时：拆行，去掉结尾那个换行带来的空行。
List<String> _blockLines(String text) {
  final lines = _lf(text).split('\n');
  if (lines.length > 1 && lines.last.isEmpty) lines.removeLast();
  return lines;
}

String _indentOf(String line) => line.substring(0, line.length - line.trimLeft().length);

/// 新文按文件里真实的缩进重新对齐：原文第一行（非空）的缩进换成文件里对应那一行的缩进。
List<String> _reindent(List<String> newLines, List<String> oldLines, List<_Line> fileLines, int at) {
  final k = oldLines.indexWhere((l) => l.trim().isNotEmpty);
  if (k < 0 || at + k >= fileLines.length) return newLines;
  final given = _indentOf(oldLines[k]);
  final real = _indentOf(fileLines[at + k].text);
  if (given == real) return newLines;
  return [
    for (final l in newLines)
      if (l.trim().isEmpty) l else if (l.startsWith(given)) '$real${l.substring(given.length)}' else l,
  ];
}

/// 两段文字有多像（0–1）。按字符算编辑距离；太长就退成按行比。
double textSimilarity(String a, String b) {
  if (a == b) return 1;
  if (a.isEmpty || b.isEmpty) return 0;
  if (a.length * b.length > 4000000) {
    final al = a.split('\n'), bl = b.split('\n');
    final n = al.length < bl.length ? al.length : bl.length;
    var same = 0;
    for (var i = 0; i < n; i++) {
      if (al[i] == bl[i]) same++;
    }
    return same / (al.length > bl.length ? al.length : bl.length);
  }
  var prev = List<int>.generate(b.length + 1, (i) => i);
  var cur = List<int>.filled(b.length + 1, 0);
  for (var i = 1; i <= a.length; i++) {
    cur[0] = i;
    final ca = a.codeUnitAt(i - 1);
    for (var j = 1; j <= b.length; j++) {
      final sub = prev[j - 1] + (ca == b.codeUnitAt(j - 1) ? 0 : 1);
      final del = prev[j] + 1;
      final ins = cur[j - 1] + 1;
      cur[j] = sub < del ? (sub < ins ? sub : ins) : (del < ins ? del : ins);
    }
    final t = prev;
    prev = cur;
    cur = t;
  }
  final longest = a.length > b.length ? a.length : b.length;
  return 1 - prev[b.length] / longest;
}

String _places(Iterable<int> lineNos) {
  final list = lineNos.toList();
  final shown = list.take(kEditListedPlaces).map((n) => '第 $n 行').join('、');
  return list.length > kEditListedPlaces ? '$shown……' : shown;
}

EditFail _ambiguous(int count, Iterable<int> startLines, MatchLevel level) => EditFail(
  EditFailKind.ambiguous,
  '要找的原文在文件里出现了 $count 处（${level.label}；起始位置：${_places(startLines)}），不知道该改哪一处，文件没有改动。'
  '${level == MatchLevel.anchors ? '请把 old_text 写得更完整（中间的行也照文件原样给出）。' : '请在 old_text 里多带几行上下文，让它只对得上一处；确实想全部替换就把 replace_all 设为 true。'}',
  count: count,
);

/// 在 [content] 里把 [oldText] 换成 [newText]。
EditResult applyEdit(String content, String oldText, String newText, {bool replaceAll = false}) {
  if (oldText.trim().isEmpty) {
    return const EditFail(EditFailKind.emptyOld, 'old_text 不能为空（也不能只有空白）。要新建文件或整份重写请用 write_file。');
  }
  if (content.length > kEditMaxChars) {
    return EditFail(EditFailKind.tooLarge, '文件太大（${content.length} 字符，局部修改的上限是 $kEditMaxChars），没有改动。');
  }
  if (_lf(oldText) == _lf(newText)) return const EditFail(EditFailKind.same, 'old_text 和 new_text 一样，没有需要改的。');
  final crlf = content.contains('\r\n');
  final eol = crlf ? '\r\n' : '\n';
  String toEol(String s) => crlf ? _lf(s).replaceAll('\n', '\r\n') : _lf(s);

  final result = _exact(content, oldText, toEol(newText), crlf: crlf, replaceAll: replaceAll) ?? _byLines(content, oldText, newText, eol: eol, replaceAll: replaceAll) ?? _notFound(content, oldText);
  if (result is! EditOk) return result;
  var out = result.content;
  // 文件末尾原来有没有换行，改完保持原样。
  final hadEnd = content.endsWith('\n');
  if (hadEnd && out.isNotEmpty && !out.endsWith('\n')) {
    out = '$out$eol';
  } else if (!hadEnd && out.endsWith('\n')) {
    out = out.substring(0, out.length - (out.endsWith('\r\n') ? 2 : 1));
  }
  if (out == content) return const EditFail(EditFailKind.same, '改完和原来一样，文件没有改动。');
  return EditOk(out, result.level, result.ranges, similarity: result.similarity);
}

/// 第 1 级。没找到返回 null。
EditResult? _exact(String content, String oldText, String replacement, {required bool crlf, required bool replaceAll}) {
  // 换行符的差别不算：文件是 CRLF 就把原文也换成 CRLF 再找。
  final variants = <String>{oldText, _lf(oldText), if (crlf) _lf(oldText).replaceAll('\n', '\r\n')};
  for (final needle in variants) {
    final hits = <int>[];
    for (var at = content.indexOf(needle); at >= 0; at = content.indexOf(needle, at + needle.length)) {
      hits.add(at);
    }
    if (hits.isEmpty) continue;
    int lineAt(int offset) => '\n'.allMatches(content.substring(0, offset)).length + 1;
    if (hits.length > 1 && !replaceAll) return _ambiguous(hits.length, hits.take(kEditListedPlaces).map(lineAt), MatchLevel.exact);
    final out = StringBuffer();
    final ranges = <(int, int)>[];
    final span = '\n'.allMatches(replacement.endsWith('\n') ? replacement.substring(0, replacement.length - 1) : replacement).length;
    var from = 0, line = 1;
    for (final at in hits) {
      final between = content.substring(from, at);
      out.write(between);
      line += '\n'.allMatches(between).length;
      ranges.add((line, line + span));
      out.write(replacement);
      line += '\n'.allMatches(replacement).length;
      from = at + needle.length;
    }
    out.write(content.substring(from));
    return EditOk(out.toString(), MatchLevel.exact, ranges);
  }
  return null;
}

/// 第 2、3 级（按行）。没找到返回 null。
EditResult? _byLines(String content, String oldText, String newText, {required String eol, required bool replaceAll}) {
  final file = _linesOf(content);
  final old = _blockLines(oldText);
  final oldTrim = [for (final l in old) l.trim()];
  final fresh = _lf(newText).isEmpty ? const <String>[] : _blockLines(newText);
  if (file.isEmpty) return null;

  // 第 2 级：每行去掉首尾空白以后一样。
  final windows = <(int, int)>[]; // (起始行下标, 行数)
  for (var i = 0; i + old.length <= file.length; i++) {
    var ok = true;
    for (var k = 0; k < old.length; k++) {
      if (file[i + k].trimmed != oldTrim[k]) {
        ok = false;
        break;
      }
    }
    if (ok) {
      windows.add((i, old.length));
      i += old.length - 1; // 不重叠
    }
  }
  if (windows.isNotEmpty) {
    if (windows.length > 1 && !replaceAll) return _ambiguous(windows.length, windows.map((w) => w.$1 + 1), MatchLevel.trimmed);
    return _replaceWindows(content, file, windows, old, fresh, eol, MatchLevel.trimmed);
  }

  // 第 3 级：首行、末行当锚点。
  if (old.length < kAnchorMinLines || oldTrim.first.isEmpty || oldTrim.last.isEmpty) return null;
  final tol = old.length ~/ 5 < 1 ? 1 : old.length ~/ 5;
  final want = oldTrim.sublist(1, old.length - 1).join('\n');
  final found = <(int, int, double)>[];
  for (var i = 0; i < file.length; i++) {
    if (file[i].trimmed != oldTrim.first) continue;
    (int, double)? best;
    final lo = i + old.length - 1 - tol < i + 1 ? i + 1 : i + old.length - 1 - tol;
    for (var j = lo; j <= i + old.length - 1 + tol && j < file.length; j++) {
      if (file[j].trimmed != oldTrim.last) continue;
      final got = [for (var k = i + 1; k < j; k++) file[k].trimmed].join('\n');
      final s = textSimilarity(want, got);
      if (s >= kAnchorSimilarity && (best == null || s > best.$2)) best = (j, s);
    }
    if (best != null) found.add((i, best.$1 - i + 1, best.$2));
  }
  if (found.isEmpty) return null;
  if (found.length > 1) return _ambiguous(found.length, found.map((w) => w.$1 + 1), MatchLevel.anchors);
  final only = found.single;
  final r = _replaceWindows(content, file, [(only.$1, only.$2)], old, fresh, eol, MatchLevel.anchors);
  return EditOk(r.content, r.level, r.ranges, similarity: only.$3);
}

EditOk _replaceWindows(String content, List<_Line> file, List<(int, int)> windows, List<String> old, List<String> fresh, String eol, MatchLevel level) {
  final out = StringBuffer();
  final ranges = <(int, int)>[];
  var from = 0, delta = 0;
  for (final (at, len) in windows) {
    final lines = _reindent(fresh, old, file, at);
    final last = file[at + len - 1];
    out.write(content.substring(from, file[at].start));
    if (lines.isEmpty) {
      from = last.next; // 整段删掉，连同它的换行
    } else {
      out.write(lines.join(eol));
      from = last.end; // 最后一行原来的换行符留着
    }
    final start = at + delta + 1;
    ranges.add((start, start + (lines.isEmpty ? 0 : lines.length - 1)));
    delta += lines.length - len;
  }
  out.write(content.substring(from));
  return EditOk(out.toString(), level, ranges);
}

String _cut(String s, int max) => s.length > max ? '${s.substring(0, max)}…' : s;

String _excerpt(List<_Line> file, int at, int count) {
  final n = count > kNearestExcerptLines ? kNearestExcerptLines : (count < 1 ? 1 : count);
  return [for (var i = at; i < at + n && i < file.length; i++) '${i + 1}| ${_cut(file[i].text, 200)}'].join('\n');
}

/// 三级都没找到：告诉模型最接近的是哪一段。
EditFail _notFound(String content, String oldText) {
  const head = '在文件里没有找到 old_text（精确匹配、忽略行首尾空白、首末行锚点都试过），文件没有改动。';
  const tail = '请对照文件现在的内容重新给出 old_text（必要时先用 read_file 再读一遍）。';
  final file = _linesOf(content);
  final old = _blockLines(oldText);
  final first = old.indexWhere((l) => l.trim().isNotEmpty);
  if (file.isEmpty || first < 0) return const EditFail(EditFailKind.notFound, '$head文件是空的。');
  final probe = old[first].trim();
  // 先找整行相等的：能说清“从哪一行开始对不上”。
  final same = file.indexWhere((l) => l.trimmed == probe);
  if (same >= 0) {
    var k = 1;
    while (first + k < old.length && same + k < file.length && file[same + k].trimmed == old[first + k].trim()) {
      k++;
    }
    final diverge = first + k < old.length ? '从 old_text 的第 ${first + k + 1} 行起和文件第 ${same + k + 1} 行对不上' : '但整段对不上';
    return EditFail(EditFailKind.notFound, '$head\nold_text 的第 ${first + 1} 行在文件第 ${same + 1} 行能找到，$diverge。文件里这一段是：\n${_excerpt(file, same, old.length - first)}\n$tail');
  }
  if (file.length <= kNearestScanLines) {
    var best = -1;
    var bestScore = 0.0;
    final p = _cut(probe, 120);
    for (var i = 0; i < file.length; i++) {
      if (file[i].trimmed.isEmpty) continue;
      final s = textSimilarity(p, _cut(file[i].trimmed, 120));
      if (s > bestScore) {
        bestScore = s;
        best = i;
      }
    }
    if (best >= 0 && bestScore >= kNearestSimilarity) {
      return EditFail(EditFailKind.notFound, '$head\n最接近的是文件第 ${best + 1} 行附近（和 old_text 第 ${first + 1} 行有 ${(bestScore * 100).round()}% 像）：\n${_excerpt(file, best, old.length - first)}\n$tail');
    }
  }
  return const EditFail(EditFailKind.notFound, '$head文件里也没有和它相近的内容。$tail');
}
