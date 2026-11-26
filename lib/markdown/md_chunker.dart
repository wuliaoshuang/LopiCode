// 把一整条消息的原文切成“顶层的几大块”。纯文字处理，不解析语法细节。
//
// 为什么先切再解析：消息还在往外冒的时候，原文只在末尾变长。按块切开以后，前面的块原文没变就不用重新解析、
// 界面也不用重排，只有最后一块跟着变（见 md_document.dart）。
//
// 切法（自己定的，2026-11-26）：
// - 代码围栏（``` 或 ~~~，至少 3 个）从开到关是一整块，中间的空行不切；没收尾就一直算到文末（closed=false）。
// - `$$` 单独一行到下一个 `$$`、`\[` 单独一行到 `\]`：公式块。
// - 以排版类 HTML 块标签开头的（<details>、<table>……）：算到这个标签配平为止，中间的空行不切。
// - 其余的按空行切；但空行后面是缩进的内容，或者前后都是列表项，就并回上一块（不然松散列表的编号会断）。

enum MdChunkKind { markdown, fence, math, html }

class MdChunk {
  const MdChunk(this.kind, this.source, {this.info = '', this.body = '', this.closed = true});
  final MdChunkKind kind;

  /// 这一块的原文（缓存就认它：原文没变，解析结果就不变）。
  final String source;

  /// 围栏后面的说明（语言名）；HTML 块是开头那个标签名。
  final String info;

  /// 围栏 / 公式里面的内容（不含围栏行）。
  final String body;

  /// 围栏 / 公式 / HTML 块收尾了没有。
  final bool closed;
}

/// 会被当成“HTML 块”整块处理的标签（开在一行开头时）。
const Set<String> kMdHtmlBlockTags = {'details', 'table', 'p', 'div', 'center', 'ul', 'ol', 'blockquote', 'pre', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6'};

final RegExp _fenceOpen = RegExp(r'^ {0,3}(`{3,}|~{3,})(.*)$');
final RegExp _listMarker = RegExp(r'^ {0,3}([-*+]|\d{1,9}[.)])( |\t|$)');
final RegExp _htmlOpen = RegExp(r'^ {0,3}<([a-zA-Z][a-zA-Z0-9]*)(\s[^<>]*)?>');
final RegExp _refDef = RegExp(r'^ {0,3}\[[^\]\n]+\]:\s*\S+');

/// 还在往外冒时，末尾这种“只有半截记号”的一行先不显示：它一会儿可能变成列表、分隔线、围栏、标题或表格，
/// 先画出来会来回跳。
final RegExp _danglingMarker = RegExp(r'^[ \t]*([-=*_~`#>|+:$\\\[]+|\d{1,9}[.)]?)[ \t]*$');

/// 流式时把末尾半截记号行去掉（整条只有这一行时不去，免得什么都不显示）。
String mdTrimStreamingTail(String text) {
  final at = text.lastIndexOf('\n');
  if (at < 0) return text;
  final last = text.substring(at + 1);
  if (last.isEmpty || !_danglingMarker.hasMatch(last)) return text;
  return text.substring(0, at + 1);
}

/// 全文里的“引用式链接定义”（`[名字]: 网址`），围栏外的。切块以后每块单独解析，要把它们补给每一块。
String mdCollectRefDefs(String text) {
  if (!text.contains(']:')) return '';
  final out = <String>[];
  String? fence;
  for (final line in text.split('\n')) {
    final m = _fenceOpen.firstMatch(line);
    if (fence != null) {
      if (m != null && m[1]!.startsWith(fence) && m[2]!.trim().isEmpty) fence = null;
      continue;
    }
    if (m != null) {
      fence = m[1];
      continue;
    }
    if (_refDef.hasMatch(line)) out.add(line.trim());
  }
  return out.join('\n');
}

List<MdChunk> mdSplitChunks(String text) {
  final lines = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
  final chunks = <MdChunk>[];
  final cur = <String>[];
  var curHasList = false;
  // 列表 / 引用里面缩进着的围栏：开着的时候中间的空行不切
  String? nested;

  void flush() {
    while (cur.isNotEmpty && cur.last.trim().isEmpty) {
      cur.removeLast();
    }
    if (cur.isNotEmpty) chunks.add(MdChunk(MdChunkKind.markdown, cur.join('\n')));
    cur.clear();
    curHasList = false;
    nested = null;
  }

  var i = 0;
  while (i < lines.length) {
    final line = lines[i];
    final trimmed = line.trim();

    final inner = RegExp(r'^[ \t>]*(`{3,}|~{3,})(.*)$').firstMatch(line);
    if (nested != null) {
      if (inner != null && inner[1]!.startsWith(nested!) && inner[2]!.trim().isEmpty) nested = null;
      cur.add(line);
      i++;
      continue;
    }
    if (cur.isNotEmpty && inner != null && (line.startsWith('  ') || line.startsWith('\t') || line.trimLeft().startsWith('>'))) {
      nested = inner[1];
      cur.add(line);
      i++;
      continue;
    }

    // 顶层的代码围栏（不在列表 / 引用的缩进里）
    final fence = _fenceOpen.firstMatch(line);
    final indentedInList = curHasList && (line.startsWith('  ') || line.startsWith('\t'));
    if (fence != null && !indentedInList && !(fence[1]!.startsWith('`') && fence[2]!.contains('`'))) {
      flush();
      final mark = fence[1]!;
      final body = <String>[];
      var closed = false;
      var j = i + 1;
      for (; j < lines.length; j++) {
        final t = lines[j].trim();
        if (t.length >= mark.length && t.startsWith(mark) && t.split('').every((ch) => ch == mark[0])) {
          closed = true;
          break;
        }
        body.add(lines[j]);
      }
      final end = closed ? j + 1 : lines.length;
      chunks.add(MdChunk(MdChunkKind.fence, lines.sublist(i, end).join('\n'), info: fence[2]!.trim(), body: body.join('\n'), closed: closed));
      i = end;
      continue;
    }

    // 公式块
    if (cur.isEmpty && (trimmed == r'$$' || trimmed == r'\[')) {
      final endMark = trimmed == r'$$' ? r'$$' : r'\]';
      final body = <String>[];
      var closed = false;
      var j = i + 1;
      for (; j < lines.length; j++) {
        if (lines[j].trim() == endMark) {
          closed = true;
          break;
        }
        body.add(lines[j]);
      }
      final end = closed ? j + 1 : lines.length;
      chunks.add(MdChunk(MdChunkKind.math, lines.sublist(i, end).join('\n'), body: body.join('\n'), closed: closed));
      i = end;
      continue;
    }

    // HTML 块
    final html = cur.isEmpty ? _htmlOpen.firstMatch(line) : null;
    if (html != null && kMdHtmlBlockTags.contains(html[1]!.toLowerCase())) {
      final tag = html[1]!.toLowerCase();
      final open = RegExp('<$tag(\\s[^<>]*)?>', caseSensitive: false);
      final close = RegExp('</$tag\\s*>', caseSensitive: false);
      var depth = 0;
      var closed = false;
      var j = i;
      for (; j < lines.length; j++) {
        depth += open.allMatches(lines[j]).length - close.allMatches(lines[j]).length;
        if (depth <= 0) {
          closed = true;
          break;
        }
      }
      final end = closed ? j + 1 : lines.length;
      chunks.add(MdChunk(MdChunkKind.html, lines.sublist(i, end).join('\n'), info: tag, closed: closed));
      i = end;
      continue;
    }

    if (trimmed.isEmpty) {
      if (cur.isEmpty) {
        i++;
        continue;
      }
      // 往后找第一行不空的，看它是不是接着上一块
      var j = i + 1;
      while (j < lines.length && lines[j].trim().isEmpty) {
        j++;
      }
      final next = j < lines.length ? lines[j] : null;
      final continues = next != null && curHasList && (next.startsWith('  ') || next.startsWith('\t') || _listMarker.hasMatch(next));
      if (continues) {
        cur.add('');
        i = j;
      } else {
        flush();
        i = j;
      }
      continue;
    }

    if (_listMarker.hasMatch(line)) curHasList = true;
    cur.add(line);
    i++;
  }
  flush();
  return chunks;
}
