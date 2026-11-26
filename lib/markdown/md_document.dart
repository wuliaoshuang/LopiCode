// 一条消息的解析结果，和“只重新解析变了的末尾”的做法。纯逻辑。
//
// - 一条消息切成几大块（md_chunker.dart），每块解析成一个 [MdPiece]。原文没变的块直接沿用上一次的 [MdPiece]
//   **同一个对象**——界面靠“是不是同一个对象”判断要不要重排，所以流式时前面排好的块不会重建。
// - 说完了的消息：整条的解析结果按原文缓存（[mdParseCached]），滚出去再滚回来不用重新解析。
import 'dart:collection';

import 'package:lopicode/markdown/md_chunker.dart';
import 'package:lopicode/markdown/md_html.dart';
import 'package:lopicode/markdown/md_nodes.dart';
import 'package:lopicode/markdown/md_parse.dart';

/// 超过这么多字的消息不解析，整条按纯文字显示（自己定的：20 万字）。
const int kMdMaxChars = 200000;

/// 缓存里最多留这么多字的原文（自己定的：200 万字，约 4MB 内存），超了先丢最久没用的。
const int kMdCacheMaxChars = 2000000;

/// 一大块的解析结果。
class MdPiece {
  const MdPiece(this.source, this.blocks, {this.kind = MdChunkKind.markdown, this.closed = true, this.tail = false});
  final String source;
  final List<MdBlock> blocks;
  final MdChunkKind kind;
  final bool closed;

  /// 解析的时候它是“还在往外冒的最后一块”。
  final bool tail;
}

class MdDocument {
  const MdDocument(this.pieces, {this.plain = false, this.refs = ''});
  final List<MdPiece> pieces;

  /// true＝太长了没解析，整条按纯文字显示。
  final bool plain;
  final String refs;

  static const MdDocument empty = MdDocument([]);
}

/// 解析一条消息。[previous] 是这条消息上一次的结果（流式时传进来，没变的块沿用）。
MdDocument mdParseDocument(String text, {bool streaming = false, MdDocument? previous}) {
  if (text.length > kMdMaxChars) {
    return MdDocument([MdPiece(text, [MdParagraph([MdText(text)])])], plain: true);
  }
  // 整条就是一份网页：当成一个 html 代码块（可以点“预览”）
  if (looksLikeHtmlDocument(text)) {
    final old = previous?.pieces.firstOrNull;
    if (old != null && old.source == text && old.closed == !streaming) return previous!;
    return MdDocument([
      MdPiece(text, [MdCode(text.trim(), lang: 'html', closed: !streaming)], kind: MdChunkKind.fence, closed: !streaming),
    ]);
  }
  final shown = streaming ? mdTrimStreamingTail(text) : text;
  final refs = mdCollectRefDefs(shown);
  final chunks = mdSplitChunks(shown);
  final old = previous != null && !previous.plain && previous.refs == refs ? previous.pieces : const <MdPiece>[];
  final pieces = <MdPiece>[];
  for (var i = 0; i < chunks.length; i++) {
    final c = chunks[i];
    final tail = streaming && i == chunks.length - 1;
    final before = i < old.length ? old[i] : null;
    if (before != null && before.kind == c.kind && before.source == c.source && before.closed == c.closed && before.tail == tail) {
      pieces.add(before); // 原文没变：沿用同一个对象
      continue;
    }
    pieces.add(MdPiece(c.source, mdParseChunk(c, refs: refs, streamingTail: tail), kind: c.kind, closed: c.closed, tail: tail));
  }
  return MdDocument(pieces, refs: refs);
}

final LinkedHashMap<String, MdDocument> _cache = LinkedHashMap();
int _cacheChars = 0;

/// 说完了的消息：按原文缓存。
MdDocument mdParseCached(String text) {
  final hit = _cache.remove(text);
  if (hit != null) {
    _cache[text] = hit; // 挪到最新
    return hit;
  }
  final doc = mdParseDocument(text);
  _cache[text] = doc;
  _cacheChars += text.length;
  while (_cacheChars > kMdCacheMaxChars && _cache.length > 1) {
    final oldest = _cache.keys.first;
    _cache.remove(oldest);
    _cacheChars -= oldest.length;
  }
  return doc;
}

/// 测试用：清空缓存 / 看缓存里有几条。
void mdDebugClearCache() {
  _cache.clear();
  _cacheChars = 0;
}

int get mdDebugCacheSize => _cache.length;
