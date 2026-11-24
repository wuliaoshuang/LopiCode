// JSON 格式化：只重新排缩进。键的顺序、数字的写法（1.0、大整数）、字符串里的转义都按原文照抄，
// 所以不走“解析成对象再写出来”那条路，而是按记号重排。
import 'package:lopicode/format/format_common.dart';

class _Tok {
  const _Tok(this.text, this.offset);
  final String text;
  final int offset;
}

final RegExp _number = RegExp(r'-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?');
const String _punct = '{}[]:,';

List<_Tok> _lex(String s) {
  final out = <_Tok>[];
  var i = 0;
  Never fail(String what, int at) => throw FormatProblem('第 ${lineAt(s, at)} 行$what');
  while (i < s.length) {
    final c = s.codeUnitAt(i);
    if (c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D) {
      i++;
      continue;
    }
    final ch = s[i];
    if (_punct.contains(ch)) {
      out.add(_Tok(ch, i));
      i++;
    } else if (ch == '"') {
      final start = i;
      i++;
      var closed = false;
      while (i < s.length) {
        final d = s.codeUnitAt(i);
        if (d == 0x22) {
          closed = true;
          i++;
          break;
        }
        if (d < 0x20) fail('的字符串里有换行或控制字符（引号可能没有结束）', start);
        if (d == 0x5C) {
          final e = i + 1 < s.length ? s[i + 1] : '';
          if (e == 'u') {
            final hex = i + 6 <= s.length ? s.substring(i + 2, i + 6) : '';
            if (!RegExp(r'^[0-9a-fA-F]{4}$').hasMatch(hex)) fail('的字符串里有写错的 \\u 转义', i);
            i += 6;
          } else if (e.isNotEmpty && '"\\/bfnrt'.contains(e)) {
            i += 2;
          } else {
            fail('的字符串里有 JSON 不认识的转义', i);
          }
          continue;
        }
        i++;
      }
      if (!closed) fail('的引号没有结束', start);
      out.add(_Tok(s.substring(start, i), start));
    } else if (ch == '-' || (c >= 0x30 && c <= 0x39)) {
      final m = _number.matchAsPrefix(s, i);
      if (m == null) fail('的数字写法不对', i);
      final end = m.end;
      // 数字后面紧跟着字母或数字（比如 01、1x）不是合法 JSON
      if (end < s.length && RegExp(r'[0-9A-Za-z_.+]').hasMatch(s[end])) fail('的数字写法不对', i);
      out.add(_Tok(s.substring(i, end), i));
      i = end;
    } else if (ch == '/') {
      fail('有注释，JSON 里不能写注释', i);
    } else if (ch == "'") {
      fail('用了单引号，JSON 的字符串只能用双引号', i);
    } else {
      final m = RegExp(r'[A-Za-z_$][A-Za-z0-9_$]*').matchAsPrefix(s, i);
      final word = m?.group(0);
      if (word == 'true' || word == 'false' || word == 'null') {
        out.add(_Tok(word!, i));
        i = m!.end;
      } else if (word != null) {
        fail('有不带引号的内容“${word.length > 20 ? word.substring(0, 20) : word}”', i);
      } else {
        fail('有 JSON 不认识的字符', i);
      }
    }
  }
  return out;
}

enum _Expect { value, valueOrEnd, key, keyOrEnd, colon, commaOrEnd, end }

/// 检查记号顺序是不是合法 JSON。不用递归：嵌套几万层的文件也不能把栈撑爆。
void _check(String s, List<_Tok> toks) {
  if (toks.isEmpty) throw const FormatProblem('文件里没有 JSON 内容');
  final stack = <_Tok>[];
  var expect = _Expect.value;
  Never fail(String what, _Tok t) => throw FormatProblem('第 ${lineAt(s, t.offset)} 行$what');
  void afterValue() => expect = stack.isEmpty ? _Expect.end : _Expect.commaOrEnd;
  for (final t in toks) {
    final x = t.text;
    final scalar = !(x.length == 1 && _punct.contains(x));
    switch (expect) {
      case _Expect.value || _Expect.valueOrEnd:
        // 嵌套太深的文件排出来缩进会多到离谱（几千层 × 几千格），干脆不排
        if ((x == '{' || x == '[') && stack.length >= 1000) fail('起嵌套太深（超过 1000 层）', t);
        if (x == '{') {
          stack.add(t);
          expect = _Expect.keyOrEnd;
        } else if (x == '[') {
          stack.add(t);
          expect = _Expect.valueOrEnd;
        } else if (scalar) {
          afterValue();
        } else if (x == ']' && expect == _Expect.valueOrEnd) {
          stack.removeLast();
          afterValue();
        } else if (x == ']' || x == '}') {
          fail('的“$x”前面多了一个逗号，或者少了一个值', t);
        } else {
          fail('的“$x”位置不对，这里应该是一个值', t);
        }
      case _Expect.key || _Expect.keyOrEnd:
        if (scalar && x.startsWith('"')) {
          expect = _Expect.colon;
        } else if (x == '}' && expect == _Expect.keyOrEnd) {
          stack.removeLast();
          afterValue();
        } else if (x == '}') {
          fail('的“}”前面多了一个逗号', t);
        } else {
          fail('的“$x”位置不对，这里应该是带双引号的键名', t);
        }
      case _Expect.colon:
        if (x != ':') fail('的键名后面少了冒号', t);
        expect = _Expect.value;
      case _Expect.commaOrEnd:
        final open = stack.last.text;
        if (x == ',') {
          expect = open == '{' ? _Expect.key : _Expect.value;
        } else if ((x == '}' && open == '{') || (x == ']' && open == '[')) {
          stack.removeLast();
          afterValue();
        } else if (x == '}' || x == ']') {
          fail('的“$x”和第 ${lineAt(s, stack.last.offset)} 行的“$open”对不上', t);
        } else {
          fail('的“${x.length > 20 ? x.substring(0, 20) : x}”前面少了逗号', t);
        }
      case _Expect.end:
        fail('起后面多出了内容（一个 JSON 文件只能有一个值）', t);
    }
  }
  if (stack.isNotEmpty) {
    throw FormatProblem('第 ${lineAt(s, stack.last.offset)} 行的“${stack.last.text}”没有闭合');
  }
  if (expect != _Expect.end) throw FormatProblem('第 ${lineAt(s, toks.last.offset)} 行后面的内容没写完');
}

FormatPiece formatJson(String source, {int indent = 2}) {
  final toks = _lex(source);
  _check(source, toks);
  final out = StringBuffer();
  var level = 0;
  for (var i = 0; i < toks.length; i++) {
    final x = toks[i].text;
    if (x == '{' || x == '[') {
      final next = toks[i + 1].text; // 上面检查过括号配平，一定有下一个
      if ((x == '{' && next == '}') || (x == '[' && next == ']')) {
        out.write('$x$next');
        i++;
      } else {
        level++;
        out
          ..write(x)
          ..write('\n')
          ..write(pad(level, indent));
      }
    } else if (x == '}' || x == ']') {
      level--;
      out
        ..write('\n')
        ..write(pad(level, indent))
        ..write(x);
    } else if (x == ',') {
      out
        ..write(',\n')
        ..write(pad(level, indent));
    } else if (x == ':') {
      out.write(': ');
    } else {
      out.write(x);
    }
  }
  out.write('\n');
  return FormatPiece(out.toString());
}

/// 去掉空白后的记号序列（比对格式化前后用）。
List<String> jsonSignature(String source) => [for (final t in _lex(source)) t.text];
