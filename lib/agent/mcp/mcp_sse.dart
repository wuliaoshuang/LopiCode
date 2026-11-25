// SSE（text/event-stream）流的解析：把一段一段到达的字节拼成一个个事件。
//
// 规矩（按通行的 SSE 写法实现；逐条对照见 docs/api-notes.md 的“MCP”一节）：
// - 一行以 \n、\r\n 或单独的 \r 结束；数据可能在任意位置被切成几段到达（包括 \r 和 \n 之间、一个汉字的中间）。
// - 空行＝一个事件结束。`data:` 可以有多行，拼起来时中间用 \n 连；冒号后面紧跟的一个空格去掉。
// - 以冒号开头的行是注释（服务器用来保活），忽略；不认识的字段忽略。
// - 没有 data 的事件不派发；`event:` 没写就是 "message"。
// - `id:` 只记下来给上层看，这一轮不做断线续传（Last-Event-ID）。
import 'dart:async';
import 'dart:convert';

class SseEvent {
  const SseEvent(this.event, this.data, {this.id});
  final String event;
  final String data;
  final String? id;
}

/// 一个事件最多攒多少字符；超过就当成坏流报错（防止服务器一直不发空行把内存撑爆）。
const int kSseMaxEventChars = 4 * 1024 * 1024;

class SseTooLargeException implements Exception {
  @override
  String toString() => '服务器发来的单条消息太大（超过 ${kSseMaxEventChars ~/ (1024 * 1024)} MB）';
}

/// 逐段喂字节，吐出完整的事件。流结束时，最后一个没有空行收尾的事件按规矩丢弃。
Stream<SseEvent> parseSse(Stream<List<int>> bytes) async* {
  final parser = SseParser();
  // allowMalformed：坏字节换成 �，不让一个坏字节把整条流弄断。
  await for (final chunk in bytes.cast<List<int>>().transform(const Utf8Decoder(allowMalformed: true))) {
    for (final e in parser.add(chunk)) {
      yield e;
    }
  }
}

/// 可以单独测的解析器：[add] 喂一段文字，返回这段文字凑齐的事件。
class SseParser {
  final StringBuffer _line = StringBuffer();
  final List<String> _data = [];
  String _event = '';
  String? _id;
  bool _lastWasCr = false;
  bool _first = true;
  int _size = 0;

  List<SseEvent> add(String chunk) {
    final out = <SseEvent>[];
    var text = chunk;
    if (_first && text.isNotEmpty) {
      _first = false;
      if (text.codeUnitAt(0) == 0xFEFF) text = text.substring(1);
    }
    for (var i = 0; i < text.length; i++) {
      final ch = text.codeUnitAt(i);
      if (ch == 0x0A) {
        // \r\n 里的 \n：上一行已经在 \r 那里结束了
        if (_lastWasCr) {
          _lastWasCr = false;
          continue;
        }
        _endLine(out);
      } else if (ch == 0x0D) {
        _lastWasCr = true;
        _endLine(out);
      } else {
        _lastWasCr = false;
        _line.writeCharCode(ch);
        if (++_size > kSseMaxEventChars) throw SseTooLargeException();
      }
    }
    return out;
  }

  void _endLine(List<SseEvent> out) {
    final line = _line.toString();
    _line.clear();
    if (line.isEmpty) {
      if (_data.isNotEmpty) out.add(SseEvent(_event.isEmpty ? 'message' : _event, _data.join('\n'), id: _id));
      _data.clear();
      _event = '';
      _size = 0;
      return;
    }
    if (line.startsWith(':')) return;
    final colon = line.indexOf(':');
    final field = colon < 0 ? line : line.substring(0, colon);
    var value = colon < 0 ? '' : line.substring(colon + 1);
    if (value.startsWith(' ')) value = value.substring(1);
    switch (field) {
      case 'data':
        _data.add(value);
      case 'event':
        _event = value;
      case 'id':
        if (!value.contains('\u0000')) _id = value;
    }
  }
}
