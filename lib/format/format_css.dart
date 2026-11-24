// CSS 格式化：一条声明一行、选择器后面 ` {`、冒号后一个空格、规则之间空一行。
// 做法是先把样式表拆成“规则 / 声明 / 注释 / @ 语句”的树，再照树写出来。
// 值和选择器里面只压缩空白，不改写任何内容；自定义属性（--x）的值原样保留。
import 'package:lopicode/format/format_common.dart';

sealed class _Node {
  _Node(this.nl);

  /// 它前面隔了几个换行（用来保留“原来这里空了一行”）。
  final int nl;
}

class _Comment extends _Node {
  _Comment(this.text, super.nl, {required this.sameLine});
  final String text;

  /// 跟在上一条后面、写在同一行的注释（`color: red; /* 说明 */`），排完还留在那一行。
  final bool sameLine;
}

class _Decl extends _Node {
  _Decl(this.name, this.value, super.nl);
  final String name;
  final String value;
}

/// 没有花括号的整句：`@import …;`、`@charset …;`，以及块里没有冒号的怪语句。
class _Stmt extends _Node {
  _Stmt(this.text, super.nl);
  final String text;
}

class _Rule extends _Node {
  _Rule(this.prelude, this.children, super.nl);
  final String prelude;
  final List<_Node> children;
  bool get isAt => trimWsLeft(prelude).startsWith('@');
}

class _Parser {
  _Parser(this.s);
  final String s;
  int i = 0;

  Never fail(String what, int at) => throw FormatProblem('第 ${lineAt(s, at)} 行$what');

  /// 跳过一个字符串 / 注释 / url(…)；不是这些就返回 false。
  bool _skipAtom() {
    final c = s[i];
    if (c == '"' || c == "'") {
      final start = i;
      i++;
      while (i < s.length && s[i] != c) {
        if (s[i] == '\n') fail('的引号没有结束', start);
        i += s[i] == r'\' ? 2 : 1;
      }
      if (i >= s.length) fail('的引号没有结束', start);
      i++;
      return true;
    }
    if (s.startsWith('/*', i)) {
      final end = s.indexOf('*/', i + 2);
      if (end < 0) fail('的注释没有结束（少了 */）', i);
      i = end + 2;
      return true;
    }
    if ((c == 'u' || c == 'U') && s.length >= i + 4 && s.substring(i, i + 4).toLowerCase() == 'url(') {
      var j = i + 4;
      while (j < s.length && isSpace(s.codeUnitAt(j))) {
        j++;
      }
      // 带引号的 url("…") 按普通括号 + 字符串走；不带引号的里面什么字符都可能有（; { } 等），整段跳过
      if (j < s.length && (s[j] == '"' || s[j] == "'")) return false;
      final start = i;
      i += 4;
      while (i < s.length && s[i] != ')') {
        i += s[i] == r'\' ? 2 : 1;
      }
      if (i >= s.length) fail('的 url( 没有结束', start);
      i++;
      return true;
    }
    return false;
  }

  /// 从当前位置往后走到最外层的 `;` `{` `}` 或文件结尾，停在那个字符上。
  void _scanStatement() {
    final opens = <int>[];
    while (i < s.length) {
      if (_skipAtom()) continue;
      final c = s[i];
      if (c == r'\') {
        i += 2;
        continue;
      }
      if (c == '(' || c == '[') {
        opens.add(i);
      } else if (c == ')' || c == ']') {
        if (opens.isEmpty) fail('多了一个“$c”', i);
        opens.removeLast();
      } else if (opens.isEmpty && (c == ';' || c == '{' || c == '}')) {
        return;
      }
      i++;
    }
    if (i > s.length) i = s.length;
    if (opens.isNotEmpty) fail('的括号没有闭合', opens.last);
  }

  /// 自定义属性的值可以是一整块 `{ … }`：从 `{` 走到配对的 `}`。
  void _skipBraces() {
    final start = i;
    var depth = 0;
    while (i < s.length) {
      if (_skipAtom()) continue;
      final c = s[i];
      if (c == r'\') {
        i += 2;
        continue;
      }
      if (c == '{') depth++;
      if (c == '}') depth--;
      i++;
      if (depth == 0) return;
    }
    fail('的“{”没有闭合', start);
  }

  List<_Node> parseBlock({required int depth, int openAt = -1}) {
    if (depth > kMaxDepth) fail('嵌套太深', openAt < 0 ? 0 : openAt);
    final top = openAt < 0;
    final nodes = <_Node>[];
    while (true) {
      var nl = 0;
      while (i < s.length && isSpace(s.codeUnitAt(i))) {
        if (s[i] == '\n') nl++;
        i++;
      }
      if (i >= s.length) {
        if (!top) fail('的“{”没有闭合', openAt);
        return nodes;
      }
      final c = s[i];
      if (c == '}') {
        if (top) fail('多了一个“}”', i);
        i++;
        return nodes;
      }
      if (c == ';') {
        i++; // 空语句，丢掉
        continue;
      }
      if (s.startsWith('/*', i)) {
        final start = i;
        _skipAtom();
        nodes.add(_Comment(s.substring(start, i), nl, sameLine: nl == 0 && nodes.isNotEmpty));
        continue;
      }
      final start = i;
      _scanStatement();
      var head = s.substring(start, i);
      if (i < s.length && s[i] == '{' && _isCustomProperty(head)) {
        while (i < s.length && s[i] == '{') {
          _skipBraces();
          _scanStatement();
        }
        head = s.substring(start, i);
      }
      if (i < s.length && s[i] == '{') {
        final openBrace = i;
        i++;
        nodes.add(_Rule(trimWs(head), parseBlock(depth: depth + 1, openAt: openBrace), nl));
        continue;
      }
      final ended = i < s.length && s[i] == ';';
      if (ended) i++;
      final text = trimWs(head);
      if (text.isEmpty) continue;
      if (top) {
        // 最外层只能是规则或 @ 语句；别的（比如光秃秃的声明）不是合法样式表
        if (!text.startsWith('@')) fail('这一段后面没有“{ … }”，不像一条 CSS 规则', start);
        nodes.add(_Stmt(text, nl));
        continue;
      }
      final colon = text.startsWith('@') ? -1 : _topLevelColon(text);
      if (colon < 0) {
        nodes.add(_Stmt(text, nl));
      } else {
        nodes.add(_Decl(trimWs(text.substring(0, colon)), trimWs(text.substring(colon + 1)), nl));
      }
    }
  }
}

bool _isCustomProperty(String head) {
  final t = trimWsLeft(head);
  return t.startsWith('--') && t.contains(':');
}

/// 把 [text] 切成“原样保留的一段”（字符串、注释、不带引号的 url()）和“其余字符”，依次交给 [onAtom] / [onChar]。
void _walk(String text, void Function(String atom) onAtom, void Function(String ch) onChar) {
  final p = _Parser(text);
  while (p.i < text.length) {
    final start = p.i;
    if (p._skipAtom()) {
      onAtom(text.substring(start, p.i));
    } else if (text[p.i] == r'\' && p.i + 1 < text.length) {
      onAtom(text.substring(p.i, p.i + 2));
      p.i += 2;
    } else {
      onChar(text[p.i]);
      p.i++;
    }
  }
}

int _topLevelColon(String text) {
  var depth = 0;
  var pos = 0;
  var found = -1;
  _walk(text, (atom) => pos += atom.length, (ch) {
    if (ch == '(' || ch == '[') depth++;
    if (ch == ')' || ch == ']') depth--;
    if (ch == ':' && depth == 0 && found < 0) found = pos;
    pos++;
  });
  return found;
}

/// 把连续空白压成一个空格（字符串、注释、url() 里面不动）。
String _collapse(String text) {
  final out = StringBuffer();
  var gap = false;
  void flush() {
    if (gap && out.isNotEmpty) out.write(' ');
    gap = false;
  }

  _walk(
    text,
    (atom) {
      flush();
      out.write(atom);
    },
    (ch) {
      if (isSpace(ch.codeUnitAt(0))) {
        gap = true;
      } else {
        flush();
        out.write(ch);
      }
    },
  );
  return out.toString();
}

/// 按最外层的逗号切开（括号、方括号、字符串里的逗号不算）。
List<String> _splitCommas(String text) {
  final parts = <String>[];
  final cur = StringBuffer();
  var depth = 0;
  _walk(text, cur.write, (ch) {
    if (ch == '(' || ch == '[') depth++;
    if (ch == ')' || ch == ']') depth--;
    if (ch == ',' && depth == 0) {
      parts.add(cur.toString());
      cur.clear();
    } else {
      cur.write(ch);
    }
  });
  parts.add(cur.toString());
  return parts;
}

String _prelude(_Rule rule, String padding) {
  if (rule.isAt) return _collapse(rule.prelude);
  final parts = [for (final p in _splitCommas(rule.prelude)) _collapse(p)];
  // 原来就一行一个选择器的，保持一行一个；原来挤在一行的，逗号后补一个空格
  return parts.join(rule.prelude.contains('\n') ? ',\n$padding' : ', ');
}

String _value(_Decl d, int level, int indent) {
  if (d.name.startsWith('--')) return d.value; // 自定义属性的值可以是任何东西，不碰
  if (!d.value.contains('\n')) return _collapse(d.value);
  // 多行的值（长渐变、grid-template-areas）保留换行，只把后面几行对齐
  if (d.value.contains('/*') || d.value.contains('\\\n')) return d.value;
  final lines = [
    for (final l in d.value.split('\n'))
      if (trimWs(l).isNotEmpty) _collapse(l),
  ];
  return lines.join('\n${pad(level + 1, indent)}');
}

void _print(List<_Node> nodes, int level, int indent, List<String> out) {
  final padding = pad(level, indent);
  _Node? prev; // 上一条“占一行”的东西（写在行尾的注释不算）
  for (final n in nodes) {
    if (n is _Comment && n.sameLine && prev != null) {
      out.last = '${out.last} ${n.text}'; // 接在上一行末尾
      continue;
    }
    if (prev != null) {
      final blank = prev is _Comment ? n.nl >= 2 : (n is _Rule || prev is _Rule || n.nl >= 2);
      if (blank) out.add('');
    }
    prev = n;
    switch (n) {
      case _Comment():
        out.add('$padding${reindentBlockComment(n.text, padding)}');
      case _Stmt():
        out.add('$padding${_collapse(n.text)};');
      case _Decl():
        final value = _value(n, level, indent);
        out.add('$padding${_collapse(n.name)}:${value.isEmpty ? '' : ' $value'};');
      case _Rule():
        final head = _prelude(n, padding);
        if (n.children.isEmpty) {
          out.add('$padding${head.isEmpty ? '' : '$head '}{}');
        } else {
          out.add('$padding${head.isEmpty ? '' : '$head '}{');
          _print(n.children, level + 1, indent, out);
          out.add('$padding}');
        }
    }
  }
}

FormatPiece formatCss(String source, {int indent = 2, int baseLevel = 0}) {
  final nodes = _Parser(source).parseBlock(depth: 0);
  final out = <String>[];
  _print(nodes, baseLevel, indent, out);
  return FormatPiece(out.isEmpty ? '' : '${out.join('\n')}\n');
}

void _canon(List<_Node> nodes, List<String> out) {
  for (final n in nodes) {
    switch (n) {
      case _Comment():
        out.add('C ${commentKey(n.text)}');
      case _Stmt():
        out.add('S ${_collapse(n.text)}');
      case _Decl():
        out.add('D ${_collapse(n.name)}: ${n.name.startsWith('--') ? n.value : _collapse(n.value)}');
      case _Rule():
        out.add('R ${n.isAt ? _collapse(n.prelude) : _splitCommas(n.prelude).map(_collapse).join(',')}');
        _canon(n.children, out);
        out.add('}');
    }
  }
}

/// 比对格式化前后用的两份清单：前半是不看结构的记号序列（去掉空白和分号），
/// 后半是按规则 / 声明拆开后的内容（空白压成一个）。两份都一样才算没改坏。
List<String> cssSignature(String source) {
  final flat = <String>[];
  final word = StringBuffer();
  void flush() {
    if (word.isNotEmpty) flat.add(word.toString());
    word.clear();
  }

  _walk(
    source,
    (atom) {
      flush();
      flat.add(atom.startsWith('/*') ? commentKey(atom) : atom);
    },
    (ch) {
      if (isSpace(ch.codeUnitAt(0)) || ch == ';') {
        flush();
      } else if ('{}:,()[]>+~'.contains(ch)) {
        flush();
        flat.add(ch);
      } else {
        word.write(ch);
      }
    },
  );
  flush();
  final tree = <String>[];
  _canon(_Parser(source).parseBlock(depth: 0), tree);
  return [...flat, '|', ...tree];
}
