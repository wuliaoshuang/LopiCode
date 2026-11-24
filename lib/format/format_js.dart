// JavaScript / JSX 格式化（保守版）：按括号层级重新缩进每一行、去掉行尾空白、把连续空行压成一行，
// 再把少数“肯定安全”的空格规整一下（逗号后、等号两边、`) {` 之间等）。
// 不合并也不拆分行——JS 里换行可能有意义；字符串、模板字符串、正则、注释、JSX 文本一个字都不动。
import 'package:lopicode/format/format_common.dart';
import 'package:lopicode/format/js_lexer.dart';

// 行首是这些：这一行是上一行没写完的续行，多缩进一层
const Set<String> _leadingContinuation = {'.', '?.', '?', ':', '&&', '||', '??'};
// 上一行以这些结尾：下一行是续行
const Set<String> _trailingContinuation = {'=', '+', '-', '*', '&&', '||', '??', '=>', '?', '+=', '-=', '==', '===', '!=', '!=='};
// 两边该有空格、而且加了空格绝不会改变意思的运算符
const Set<String> _spaced = {'=', '==', '===', '!=', '!==', '=>', '&&', '||', '??', '+=', '-=', '*=', '%=', '**=', '&&=', '||=', '??=', '<=', '>=', '|=', '&=', '^=', '<<=', '>>=', '>>>='};
const Set<String> _beforeParen = {'if', 'for', 'while', 'switch', 'catch'};
const Set<String> _beforeBrace = {'else', 'try', 'finally', 'do'};
const Set<String> _afterBrace = {'else', 'catch', 'finally'};

bool _opens(JsToken t) => t.kind == JsKind.punct && (t.text == '(' || t.text == '[' || t.text == '{');
bool _closes(JsToken t) => t.kind == JsKind.punct && (t.text == ')' || t.text == ']' || t.text == '}');

class _Scope {
  _Scope({this.isSwitch = false, this.isElement = false});
  final bool isSwitch;

  /// JSX 元素的内容区（里面是文本和子标签，不套“续行”那些规则）。
  final bool isElement;
  bool caseSeen = false;
}

/// 同一行里两个记号之间放什么。[normalize] 为假时原样保留。
String _gap(JsToken? before, JsToken prev, JsToken t, bool normalize, {required bool prevStartsLine}) {
  final ws = t.ws;
  if (!normalize || prev.jsx || t.jsx || prev.isComment || t.isComment) return ws;
  var s = ws.isEmpty ? '' : ' ';
  final prevText = prev.kind == JsKind.punct ? prev.text : '';
  final text = t.kind == JsKind.punct ? t.text : '';
  if ((text == ',' || text == ';') && prevText != '(' && prevText != ',' && prevText != ';') s = '';
  if (s.isNotEmpty) return s;
  if (prevText == ',' && text != ',' && !_closes(t)) return ' ';
  // 行首的分号（不写分号风格里的 `;[1, 2].forEach`）后面不补空格
  if (prevText == ';' && text != ';' && text != ')' && !prevStartsLine) return ' ';
  if (text == '{' && (prevText == ')' || prevText == '=>' || (prev.kind == JsKind.word && _beforeBrace.contains(prev.text)))) return ' ';
  if (_spaced.contains(text) || _spaced.contains(prevText)) return ' ';
  // obj.catch(…) 里的 catch 是方法名，不是关键字
  final afterDot = before != null && (before.isPunct('.') || before.isPunct('?.'));
  if (text == '(' && prev.kind == JsKind.word && _beforeParen.contains(prev.text) && !afterDot) return ' ';
  if (prevText == '}' && t.kind == JsKind.word && _afterBrace.contains(t.text)) return ' ';
  return s;
}

FormatPiece formatJs(String source, {int indent = 2, int baseLevel = 0}) {
  final tokens = JsLexer(source).run();
  final out = StringBuffer();
  final tracker = LevelTracker(baseLevel);
  final scopes = <_Scope>[];
  var line = 0;
  var lineLevel = baseLevel;
  var normalize = true;
  var lastParenWasSwitch = false;
  final parenIsSwitch = <bool>[];

  bool startsLine(int i) => i == 0 || tokens[i].nl > 0;

  for (var i = 0; i < tokens.length; i++) {
    final t = tokens[i];
    if (startsLine(i)) {
      // 这一行以几个收尾括号开头
      var closers = 0;
      for (var j = i; j < tokens.length && (j == i || tokens[j].nl == 0); j++) {
        final k = tokens[j].kind;
        if (_closes(tokens[j]) || k == JsKind.jsxSelfEnd || k == JsKind.jsxClose) {
          closers++;
        } else if (k == JsKind.jsxOpenEnd) {
          closers++; // 它后面紧接着开了元素内容，不能再往下数
          break;
        } else {
          break;
        }
      }
      var level = tracker.levelAfterClosers(closers);
      final scope = scopes.isEmpty ? null : scopes.last;
      if (closers == 0 && scope != null && scope.isSwitch) {
        // switch 里：case / default 和花括号内容齐平，它们下面的语句再缩一层
        var label = t;
        for (var j = i; j < tokens.length && tokens[j].isComment; j++) {
          if (j + 1 < tokens.length) label = tokens[j + 1];
        }
        final isLabel = label.isWord('case') || label.isWord('default');
        if (isLabel) {
          if (!t.isComment) scope.caseSeen = true;
        } else if (scope.caseSeen && !(t.isComment && _closes(label))) {
          level++;
        }
      }
      if (closers == 0 && !(scope?.isElement ?? false)) {
        JsToken? before;
        for (var j = i - 1; j >= 0; j--) {
          if (!tokens[j].isComment) {
            before = tokens[j];
            break;
          }
        }
        final leading = t.kind == JsKind.punct && _leadingContinuation.contains(t.text);
        final trailing =
            before != null &&
            !before.jsx &&
            ((before.kind == JsKind.punct && (_trailingContinuation.contains(before.text) || (before.text == ')' && before.ctrl))) || before.isWord('else') || before.isWord('do')) &&
            !t.isPunct('{');
        if (leading || trailing) level++;
      }
      // 这一行有除号（也可能是没认出来的正则）：只换缩进，行内空白不动
      normalize = true;
      for (var j = i; j < tokens.length && (j == i || tokens[j].nl == 0); j++) {
        if (tokens[j].isPunct('/') || tokens[j].isPunct('/=')) normalize = false;
      }
      if (i > 0) out.write(t.nl >= 2 ? '\n\n' : '\n');
      out.write(pad(level, indent));
      line++;
      lineLevel = level;
    } else {
      out.write(_gap(i >= 2 ? tokens[i - 2] : null, tokens[i - 1], t, normalize, prevStartsLine: startsLine(i - 1)));
    }
    out.write(t.kind == JsKind.blockComment && startsLine(i) ? reindentBlockComment(t.text, pad(lineLevel, indent)) : t.text);

    if (_opens(t)) {
      final before = i > 0 ? tokens[i - 1] : null;
      if (t.text == '(') parenIsSwitch.add(before != null && before.isWord('switch'));
      tracker.open(line, lineLevel);
      scopes.add(_Scope(isSwitch: t.text == '{' && before != null && before.isPunct(')') && lastParenWasSwitch));
    } else if (_closes(t)) {
      if (t.text == ')') lastParenWasSwitch = parenIsSwitch.isNotEmpty && parenIsSwitch.removeLast();
      tracker.close();
      if (scopes.isNotEmpty) scopes.removeLast();
    } else if (t.kind == JsKind.jsxOpen) {
      tracker.open(line, lineLevel);
      scopes.add(_Scope());
    } else if (t.kind == JsKind.jsxSelfEnd || t.kind == JsKind.jsxClose) {
      tracker.close();
      if (scopes.isNotEmpty) scopes.removeLast();
    } else if (t.kind == JsKind.jsxOpenEnd) {
      tracker.reopen();
      if (scopes.isNotEmpty) scopes.removeLast();
      scopes.add(_Scope(isElement: true));
    }
  }
  if (tokens.isNotEmpty) out.write('\n');
  return FormatPiece(out.toString());
}
