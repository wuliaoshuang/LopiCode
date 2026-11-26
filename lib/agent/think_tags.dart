// 正文里的 `<think>…</think>`：很多中转站 / 本机模型不走单独的思考字段，而是把思考直接写在回复开头的标签里。
// 这里把它从正文里剥出来，交给“思考”那条路（显示成“思考了 N 秒”，不进正文）。纯计算，不带界面。
//
// 规矩（2026-11-26 自定；这种写法没有哪家的官方文档可对，见 docs/api-notes.md）：
// - 只认**回复最开头**的标签（前面只许有空白）：`<think>` 或 `<thinking>`，不分大小写。
//   正文中间出现的不动——模型可能正在讲这个标签本身，剥掉反而丢字。
// - 配对的收尾是 `</think>` / `</thinking>`（和开头用的那个对应）。收尾后面紧跟的空行去掉。
// - 一直没等到收尾（回复断了、模型没写）：标签后面的全部算思考，正文是空的；不把半截思考漏进正文。
// - 流式：标签可能被切成几块到达。还分不清是不是标签的那一小截先按住不发，分清了再发，所以正文里不会闪一下 `<thi`。

import 'package:lopicode/agent/chat_client.dart';

/// 一次 [ThinkTagSplitter.add] / [ThinkTagSplitter.close] 分出来的两部分（都可能是空串）。
typedef ThinkSplit = ({String text, String thinking});

const List<String> _openTags = ['<think>', '<thinking>'];

class ThinkTagSplitter {
  // 0＝还在回复开头（没见到非空白）；1＝在标签里；2＝正文（之后原样放行）
  int _state = 0;
  String _held = '';
  String _close = '';
  bool _trimNext = false;

  /// 这次回复里有没有剥出过标签里的思考。
  bool get sawTag => _sawTag;
  bool _sawTag = false;

  /// 喂一块正文增量，返回现在能确定的部分。
  ThinkSplit add(String chunk) {
    final text = StringBuffer();
    final thinking = StringBuffer();
    var rest = chunk;
    while (rest.isNotEmpty) {
      if (_state == 2) {
        if (_trimNext) {
          rest = rest.replaceFirst(RegExp(r'^[\r\n]+'), '');
          if (rest.isEmpty) break; // 只来了换行：下一块接着去
          _trimNext = false;
        }
        text.write(rest);
        break;
      }
      if (_state == 0) {
        _held += rest;
        rest = '';
        final body = _held.trimLeft();
        final lower = body.toLowerCase();
        final open = _openTags.where(lower.startsWith).firstOrNull;
        if (open != null) {
          _state = 1;
          _sawTag = true;
          _close = '</${open.substring(1)}';
          rest = body.substring(open.length);
          _held = '';
        } else if (body.isEmpty || _openTags.any((t) => t.startsWith(lower))) {
          break; // 还分不清：按住
        } else {
          _state = 2;
          rest = _held;
          _held = '';
        }
        continue;
      }
      // 在标签里：找收尾；末尾可能是半截收尾，按住
      _held += rest;
      rest = '';
      final at = _held.toLowerCase().indexOf(_close);
      if (at >= 0) {
        thinking.write(_held.substring(0, at));
        rest = _held.substring(at + _close.length);
        _held = '';
        _state = 2;
        _trimNext = true;
        continue;
      }
      var keep = 0;
      final lower = _held.toLowerCase();
      for (var n = _close.length - 1; n > 0; n--) {
        if (lower.endsWith(_close.substring(0, n))) {
          keep = n;
          break;
        }
      }
      thinking.write(_held.substring(0, _held.length - keep));
      _held = _held.substring(_held.length - keep);
    }
    return (text: text.toString(), thinking: thinking.toString());
  }

  /// 回复结束：把按住的那一小截交出来（在标签里的算思考，在开头的算正文）。
  ThinkSplit close() {
    final held = _held;
    _held = '';
    if (_state == 1) return (text: '', thinking: held);
    final ThinkSplit out = (text: _state == 0 ? held : '', thinking: '');
    _state = 2;
    return out;
  }
}

/// 一整段正文一次分好（旧存档里连标签一起存下来的回复，显示时用）。
ThinkSplit splitThinkTags(String content) {
  final s = ThinkTagSplitter();
  final a = s.add(content);
  final b = s.close();
  if (!s.sawTag) return (text: content, thinking: '');
  return (text: a.text + b.text, thinking: (a.thinking + b.thinking).trim());
}

/// 给一次请求的增量流套上标签剥离：正文开头标签里的字改从 [ChatDelta.reasoning] 出来（标上 [ChatDelta.reasoningFromTag]）。
/// 接口自己给的思考字段、工具调用、用量原样放行。
Stream<ChatDelta> stripThinkTags(Stream<ChatDelta> source) async* {
  final split = ThinkTagSplitter();
  await for (final d in source) {
    final content = d.content;
    if (content == null || content.isEmpty) {
      yield d;
      continue;
    }
    final part = split.add(content);
    final own = d.reasoning ?? '';
    yield ChatDelta(
      content: part.text.isEmpty ? null : part.text,
      reasoning: own.isEmpty && part.thinking.isEmpty ? d.reasoning : own + part.thinking,
      reasoningFromTag: part.thinking.isNotEmpty,
      toolCalls: d.toolCalls,
      finishReason: d.finishReason,
      raw: d.raw,
      usage: d.usage,
    );
  }
  final rest = split.close();
  if (rest.text.isNotEmpty || rest.thinking.isNotEmpty) {
    yield ChatDelta(content: rest.text.isEmpty ? null : rest.text, reasoning: rest.thinking.isEmpty ? null : rest.thinking, reasoningFromTag: rest.thinking.isNotEmpty);
  }
}
