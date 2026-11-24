// JavaScript / JSX 分词。格式化只动记号之间的空白，所以这里最要紧的是把“不能碰的整段”认准：
// 字符串、模板字符串（连同里面的 ${ }）、正则、注释、JSX 文本。
import 'package:lopicode/format/format_common.dart';

enum JsKind {
  word,
  number,
  string,

  /// 整个模板字符串是一个记号（从开头的反引号到结尾的反引号，里面的 ${ } 也包在内），一个字节都不动。
  template,
  regex,
  lineComment,
  blockComment,
  punct,

  /// JSX：`<`（开始标签的开头）
  jsxOpen,

  /// JSX：开始标签结尾的 `>`
  jsxOpenEnd,

  /// JSX：`/>`
  jsxSelfEnd,

  /// JSX：`</`
  jsxClose,

  /// JSX：结束标签结尾的 `>`
  jsxCloseEnd,
  jsxName,
  jsxEq,
  jsxString,

  /// JSX 文本，按行切开：一行一个记号（行首行尾的空白在 JSX 里本来就不算数，已经去掉）
  jsxText,
}

class JsToken {
  JsToken(this.kind, this.text, this.offset, this.nl, this.ws, {this.jsx = false, this.ctrl = false});
  final JsKind kind;
  final String text;
  final int offset;

  /// 它前面隔了几个换行；0 表示和上一个记号在同一行。
  final int nl;

  /// 和上一个记号在同一行时，两者之间原来的空白。
  final String ws;

  /// JSX 里的记号（含 JSX 里包表达式的花括号）：它两边的空白可能有意义，不规整。
  final bool jsx;

  /// 这个 `)` 收的是 if / for / while 的条件。
  final bool ctrl;

  bool get isComment => kind == JsKind.lineComment || kind == JsKind.blockComment;
  bool isPunct(String p) => kind == JsKind.punct && text == p;
  bool isWord(String w) => kind == JsKind.word && text == w;
}

const Set<String> _regexAfterWord = {'return', 'typeof', 'instanceof', 'in', 'of', 'new', 'delete', 'void', 'throw', 'case', 'do', 'else', 'yield', 'await'};
const Set<String> _ctrlWords = {'if', 'while', 'for', 'with'};
// 从长到短排，取能匹配上的最长的一个
const List<String> _puncts = [
  '>>>=', '...', '===', '!==', '**=', '<<=', '>>=', '>>>', '&&=', '||=', '??=', //
  '=>', '==', '!=', '<=', '>=', '&&', '||', '??', '?.', '++', '--', '+=', '-=', '*=', '/=', '%=', '&=', '|=', '^=', '<<', '>>', '**',
];

bool _identStart(int c) => (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) || c == 0x5F || c == 0x24 || c > 0x7F;
bool _identPart(int c) => _identStart(c) || (c >= 0x30 && c <= 0x39);
bool _digit(int c) => c >= 0x30 && c <= 0x39;

class _Bracket {
  _Bracket(this.text, this.offset, this.ctrl);
  final String text;
  final int offset;
  final bool ctrl;
}

class JsLexer {
  JsLexer(this.s);
  final String s;
  final List<JsToken> tokens = [];
  int _i = 0;
  int _nl = 0;
  String _ws = '';
  final List<_Bracket> _brackets = [];

  /// 现在这个位置能不能开始一个表达式（决定 `/` 是正则还是除号、`<` 是不是 JSX）。
  bool _exprPos = true;
  int _depth = 0;

  Never _fail(String what, int at) => throw FormatProblem('第 ${lineAt(s, at)} 行$what');

  List<JsToken> run() {
    if (s.startsWith('#!')) {
      final end = s.indexOf('\n');
      _i = end < 0 ? s.length : end;
      _emit(JsKind.lineComment, 0);
    }
    _code(nested: false);
    return tokens;
  }

  void _emit(JsKind kind, int start, {String? text, bool jsx = false, bool ctrl = false}) {
    final value = text ?? s.substring(start, _i);
    tokens.add(JsToken(kind, kind == JsKind.lineComment ? trimWsRight(value) : value, start, _nl, _nl > 0 ? '' : _ws, jsx: jsx, ctrl: ctrl));
    _nl = 0;
    _ws = '';
  }

  /// 跳过空白并记下来，等下一个记号出来时一起结算。可能连着调几次（中间没出记号），所以是累加，不是覆盖。
  void _skipWs() {
    final start = _i;
    var lineStart = -1;
    while (_i < s.length && isSpace(s.codeUnitAt(_i))) {
      if (s.codeUnitAt(_i) == 0x0A) {
        _nl++;
        lineStart = _i + 1;
      }
      _i++;
    }
    _ws = lineStart >= 0 ? s.substring(lineStart, _i) : _ws + s.substring(start, _i);
  }

  /// 读一段代码。[nested] 为真时读到一个“不是这段里开的 `}`”就停（停在它上面，不吃掉）：
  /// 模板字符串的 `${ }` 和 JSX 的 `{ }` 都这么读。
  void _code({required bool nested}) {
    if (++_depth > kMaxDepth) _fail('嵌套太深', _i);
    final base = _brackets.length;
    final openedAt = _i;
    while (true) {
      _skipWs();
      if (_i >= s.length) {
        if (_brackets.length > base) _fail('的“${_brackets.last.text}”没有闭合', _brackets.last.offset);
        if (nested) _fail('的“{”没有闭合', openedAt > 0 ? openedAt - 1 : 0);
        break;
      }
      final start = _i;
      final c = s.codeUnitAt(_i);
      final ch = s[_i];
      final next = _i + 1 < s.length ? s.codeUnitAt(_i + 1) : 0;
      if (ch == '/' && next == 0x2F) {
        final end = s.indexOf('\n', _i);
        _i = end < 0 ? s.length : end;
        _emit(JsKind.lineComment, start);
      } else if (ch == '/' && next == 0x2A) {
        final end = s.indexOf('*/', _i + 2);
        if (end < 0) _fail('的注释没有结束（少了 */）', start);
        _i = end + 2;
        _emit(JsKind.blockComment, start);
      } else if (ch == '/' && _exprPos) {
        _regex();
      } else if (ch == '"' || ch == "'") {
        _string(ch);
        _emit(JsKind.string, start);
        _exprPos = false;
      } else if (ch == '`') {
        _template();
        _emit(JsKind.template, start);
        _exprPos = false;
      } else if (_digit(c) || (ch == '.' && _digit(next))) {
        _number();
        _emit(JsKind.number, start);
        _exprPos = false;
      } else if (_identStart(c) || ch == r'\' || (ch == '#' && _identStart(next))) {
        _i++;
        while (_i < s.length && (_identPart(s.codeUnitAt(_i)) || s[_i] == r'\')) {
          _i++;
        }
        _emit(JsKind.word, start);
        // obj.return 这种属性名不是关键字
        final afterDot = tokens.length >= 2 && (tokens[tokens.length - 2].isPunct('.') || tokens[tokens.length - 2].isPunct('?.'));
        _exprPos = !afterDot && _regexAfterWord.contains(tokens.last.text);
      } else if (ch == '<' && _exprPos && (_identStart(next) || next == 0x3E)) {
        _jsxElement();
        _exprPos = false;
      } else if (ch == '(' || ch == '[' || ch == '{') {
        if (_brackets.length >= 1000) _fail('起括号嵌套太深（超过 1000 层）', start);
        final prev = _lastCode();
        _brackets.add(_Bracket(ch, start, ch == '(' && prev != null && prev.kind == JsKind.word && _ctrlWords.contains(prev.text)));
        _i++;
        _emit(JsKind.punct, start);
        _exprPos = true;
      } else if (ch == ')' || ch == ']' || ch == '}') {
        if (_brackets.length == base) {
          if (nested && ch == '}') break;
          _fail('的“$ch”前面没有对应的开头', start);
        }
        final open = _brackets.removeLast();
        final want = open.text == '(' ? ')' : (open.text == '[' ? ']' : '}');
        if (ch != want) _fail('的“$ch”和第 ${lineAt(s, open.offset)} 行的“${open.text}”对不上', start);
        _i++;
        _emit(JsKind.punct, start, ctrl: open.ctrl);
        _exprPos = open.ctrl;
      } else {
        var text = ch;
        for (final p in _puncts) {
          if (s.startsWith(p, _i)) {
            text = p;
            break;
          }
        }
        // a?.5:1 里的 ?. 其实是 ? 和 .5
        if (text == '?.' && _i + 2 < s.length && _digit(s.codeUnitAt(_i + 2))) text = '?';
        _i += text.length;
        _emit(JsKind.punct, start);
        _exprPos = text != '++' && text != '--';
      }
    }
    _depth--;
  }

  JsToken? _lastCode() {
    for (var k = tokens.length - 1; k >= 0; k--) {
      if (!tokens[k].isComment) return tokens[k];
    }
    return null;
  }

  void _string(String quote) {
    final start = _i;
    _i++;
    while (_i < s.length && s[_i] != quote) {
      if (s[_i] == '\n') _fail('的引号没有结束', start);
      _i += s[_i] == r'\' ? 2 : 1;
    }
    if (_i >= s.length) _fail('的引号没有结束', start);
    _i++;
  }

  void _number() {
    final start = _i;
    while (_i < s.length) {
      final c = s.codeUnitAt(_i);
      if (_identPart(c) || s[_i] == '.') {
        _i++;
        // 1e+5 / 1e-5 的正负号是数字的一部分（十六进制的 0xE 不是）
        final lower = s.substring(start, _i).toLowerCase();
        if (lower.endsWith('e') && !lower.startsWith('0x') && _i + 1 < s.length && (s[_i] == '+' || s[_i] == '-') && _digit(s.codeUnitAt(_i + 1))) _i++;
      } else {
        break;
      }
    }
  }

  void _regex() {
    final start = _i;
    _i++;
    var inClass = false;
    while (true) {
      if (_i >= s.length || s[_i] == '\n') _fail('的正则表达式没有结束', start);
      final ch = s[_i];
      if (ch == r'\') {
        _i += 2;
        continue;
      }
      if (ch == '[') inClass = true;
      if (ch == ']') inClass = false;
      _i++;
      if (ch == '/' && !inClass) break;
    }
    while (_i < s.length && _identPart(s.codeUnitAt(_i))) {
      _i++;
    }
    _emit(JsKind.regex, start);
    _exprPos = false;
  }

  /// 走过整个模板字符串。`${ }` 里的代码也要正经分词才知道它在哪结束，但分出来的记号不留。
  void _template() {
    final start = _i;
    _i++;
    while (true) {
      if (_i >= s.length) _fail('的模板字符串没有结束（少了反引号）', start);
      final ch = s[_i];
      if (ch == r'\') {
        _i += 2;
      } else if (ch == '`') {
        _i++;
        return;
      } else if (ch == r'$' && _i + 1 < s.length && s[_i + 1] == '{') {
        _i += 2;
        final keep = tokens.length;
        final nl = _nl;
        final ws = _ws;
        _exprPos = true;
        _code(nested: true);
        tokens.length = keep;
        _nl = nl;
        _ws = ws;
        _i++; // 停在的那个 }
      } else {
        _i++;
      }
    }
  }

  String _jsxName() {
    final start = _i;
    while (_i < s.length && (_identPart(s.codeUnitAt(_i)) || s[_i] == '-' || s[_i] == '.' || s[_i] == ':')) {
      _i++;
    }
    return s.substring(start, _i);
  }

  void _jsxBraces() {
    final start = _i;
    _brackets.add(_Bracket('{', start, false));
    _i++;
    _emit(JsKind.punct, start, jsx: true);
    _exprPos = true;
    _code(nested: true);
    // _code 停在配对的 } 上；先把它前面的空白结算给这个记号
    _brackets.removeLast();
    final close = _i;
    _i++;
    _emit(JsKind.punct, close, jsx: true);
  }

  void _jsxElement() {
    if (++_depth > kMaxDepth) _fail('嵌套太深', _i);
    final open = _i;
    _i++;
    _emit(JsKind.jsxOpen, open, jsx: true);
    final name = _jsxName();
    if (name.isNotEmpty) _emit(JsKind.jsxName, _i - name.length, jsx: true);
    // 属性
    while (true) {
      _skipWs();
      if (_i >= s.length) _fail('的标签 <$name 没有写完', open);
      final start = _i;
      final ch = s[_i];
      if (s.startsWith('/>', _i)) {
        _i += 2;
        _emit(JsKind.jsxSelfEnd, start, jsx: true);
        _depth--;
        return;
      }
      if (ch == '>') {
        _i++;
        _emit(JsKind.jsxOpenEnd, start, jsx: true);
        break;
      }
      if (ch == '{') {
        _jsxBraces();
        continue;
      }
      final attr = _jsxName();
      if (attr.isEmpty) _fail('的标签 <$name 里有看不懂的写法', start);
      _emit(JsKind.jsxName, start, jsx: true);
      _skipWs();
      if (_i < s.length && s[_i] == '=') {
        _i++;
        _emit(JsKind.jsxEq, _i - 1, jsx: true);
        _skipWs();
        if (_i >= s.length) _fail('的标签 <$name 没有写完', open);
        final v = _i;
        if (s[_i] == '"' || s[_i] == "'") {
          final end = s.indexOf(s[_i], _i + 1); // JSX 属性的字符串里没有转义
          if (end < 0) _fail('的引号没有结束', v);
          _i = end + 1;
          _emit(JsKind.jsxString, v, jsx: true);
        } else if (s[_i] == '{') {
          _jsxBraces();
        } else if (s[_i] == '<') {
          _jsxElement();
        } else {
          _fail('的属性 $attr 后面的值看不懂', v);
        }
      }
    }
    // 子内容
    while (true) {
      final start = _i;
      while (_i < s.length && s[_i] != '<' && s[_i] != '{') {
        _i++;
      }
      _jsxText(start, _i);
      if (_i >= s.length) _fail('的标签 <$name> 没有闭合', open);
      if (s[_i] == '{') {
        _jsxBraces();
      } else if (s.startsWith('</', _i)) {
        final close = _i;
        _i += 2;
        _emit(JsKind.jsxClose, close, jsx: true);
        _skipWs();
        final closeName = _jsxName();
        if (closeName != name) _fail('的 </$closeName> 和第 ${lineAt(s, open)} 行的 <$name> 对不上', close);
        if (closeName.isNotEmpty) _emit(JsKind.jsxName, _i - closeName.length, jsx: true);
        _skipWs();
        if (_i >= s.length || s[_i] != '>') _fail('的 </$name 没有写完', close);
        _i++;
        _emit(JsKind.jsxCloseEnd, _i - 1, jsx: true);
        _depth--;
        return;
      } else {
        _jsxElement();
      }
    }
  }

  /// JSX 文本按行切成记号。JSX 的规矩：带换行的文本，每行行首行尾的空白和空行都不算数，
  /// 所以换行处可以放心重排缩进；同一行里的空白（包括挨着标签的那一个空格）有意义，原样留着。
  void _jsxText(int start, int end) {
    final lines = s.substring(start, end).split('\n');
    var offset = start;
    for (var k = 0; k < lines.length; k++) {
      var line = lines[k];
      if (k > 0) {
        _nl++;
        line = trimWsLeft(line);
      }
      if (k < lines.length - 1) line = trimWsRight(line);
      if (line.isNotEmpty) _emit(JsKind.jsxText, offset, text: line, jsx: true);
      offset += lines[k].length + 1;
    }
  }
}

/// 比对格式化前后用：记号序列（去掉记号之间的空白），外加“这里原来换没换行”。
/// JS 里换行可能有意义（不写分号的代码靠换行断句），所以格式化不许合并或拆开行。
List<String> jsSignature(String source) {
  final tokens = JsLexer(source).run();
  final out = <String>[];
  for (var i = 0; i < tokens.length; i++) {
    final t = tokens[i];
    if (i > 0 && t.nl > 0) out.add('\n');
    out.add('${t.kind.index} ${t.kind == JsKind.blockComment ? commentKey(t.text) : t.text}');
  }
  return out;
}
