// 各语言格式化器共用的小工具。纯 Dart，不依赖界面，也不依赖 lib 里别的层。

/// 格式化器内部用的“这份代码没法格式化”：带一句给人看的原因，由入口接住后原样返回原文。
class FormatProblem implements Exception {
  const FormatProblem(this.message);
  final String message;

  @override
  String toString() => message;
}

/// 一种语言的格式化器交回来的东西：[text] 是排好的文本；[note] 是“有一段原样保留了”这类补充说明。
class FormatPiece {
  const FormatPiece(this.text, {this.note});
  final String text;
  final String? note;
}

/// [offset] 在第几行（从 1 数）。只在报错时用，所以每次从头数也无妨。
int lineAt(String source, int offset) {
  var line = 1;
  final end = offset < source.length ? offset : source.length;
  for (var i = 0; i < end; i++) {
    if (source.codeUnitAt(i) == 0x0A) line++;
  }
  return line;
}

String pad(int level, int indent) => ' ' * ((level < 0 ? 0 : level) * indent);

/// 只去掉普通空白（空格、制表符、换行）。Dart 自带的 trim 会把“不换行空格”这类也去掉，
/// 而它们在 HTML / JSX 文本里是有意义的内容，不能碰。
String trimWsLeft(String s) {
  var i = 0;
  while (i < s.length && isSpace(s.codeUnitAt(i))) {
    i++;
  }
  return i == 0 ? s : s.substring(i);
}

String trimWsRight(String s) {
  var i = s.length;
  while (i > 0 && isSpace(s.codeUnitAt(i - 1))) {
    i--;
  }
  return i == s.length ? s : s.substring(0, i);
}

String trimWs(String s) => trimWsLeft(trimWsRight(s));

bool isSpace(int c) => c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D || c == 0x0C || c == 0x0B;

/// 递归太深（比如几千层嵌套）时放弃，免得把栈撑爆。
const int kMaxDepth = 200;

/// 按“括号开在哪一行”算缩进层级。
///
/// 规矩：同一行上开的几个括号只算一层（`foo(function () {` 的函数体只缩进一层）；
/// 一行以收尾括号开头时，这一行退回到“开它的那一行”的层级。
class LevelTracker {
  LevelTracker(this.base);
  final int base;
  final List<_Open> _stack = [];

  int get depth => _stack.length;

  /// 现在最里层括号里的内容该缩进到第几层。
  int get contentLevel => _stack.isEmpty ? base : _stack.last.contentLevel;

  /// 一行以 [closers] 个收尾括号开头时，这一行的层级。
  int levelAfterClosers(int closers) {
    var level = contentLevel;
    for (var k = 0; k < closers; k++) {
      final index = _stack.length - 1 - k;
      if (index < 0) break;
      level = _stack[index].lineLevel;
    }
    return level;
  }

  void open(int line, int lineLevel) {
    final shared = _stack.isNotEmpty && _stack.last.line == line;
    _stack.add(_Open(line, lineLevel, shared ? _stack.last.contentLevel : lineLevel + 1));
  }

  void close() {
    if (_stack.isNotEmpty) _stack.removeLast();
  }

  /// 把最里层换成“同一行开的另一层”：JSX 的 `<div ...>` 写完后，标签本身收尾、元素内容开始，
  /// 而 `</div>` 要和 `<div` 对齐，所以沿用标签那一行的位置。
  void reopen() {
    if (_stack.isEmpty) return;
    final old = _stack.removeLast();
    final shared = _stack.isNotEmpty && _stack.last.line == old.line;
    _stack.add(_Open(old.line, old.lineLevel, shared ? _stack.last.contentLevel : old.lineLevel + 1));
  }
}

class _Open {
  const _Open(this.line, this.lineLevel, this.contentLevel);
  final int line;
  final int lineLevel;
  final int contentLevel;
}

/// 多行块注释换缩进：只有每一行都以 `*` 开头的（文档注释那种写法）才把后面几行对齐到新缩进，
/// 别的写法（注释里画了图、贴了代码）里面一个字都不动。
String reindentBlockComment(String comment, String padding) {
  if (!comment.contains('\n')) return comment;
  final lines = comment.split('\n');
  for (var i = 1; i < lines.length; i++) {
    if (!trimWsLeft(lines[i]).startsWith('*')) return comment;
  }
  final out = StringBuffer(trimWsRight(lines.first));
  for (var i = 1; i < lines.length; i++) {
    out
      ..write('\n')
      ..write(padding)
      ..write(' ')
      ..write(trimWs(lines[i]));
  }
  return out.toString();
}

/// 比较“格式化前后是不是同一段注释”时用：每行去掉首尾空白再比（注释换缩进是允许的，换字不行）。
String commentKey(String comment) => comment.split('\n').map(trimWs).join('\n');

bool sameList(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
