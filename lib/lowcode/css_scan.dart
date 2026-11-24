/// CSS 文本的最底层扫描：去注释、按分号切声明、按空白切值、识别 `!important`。
///
/// 为什么自己扫而不用正则一把切：值里的括号和引号里可以有分号、冒号、空格
/// （`url(data:image/png;base64,…)`、`calc(1px + 2px)`、`"a; b"`），正则切会把一条声明切成几条假的。
/// 这里所有函数对任何输入都不抛异常：括号、引号不配平时，就当它一直延续到结尾。
library;

const int _quote1 = 0x27; // '
const int _quote2 = 0x22; // "
const int _backslash = 0x5C;

/// 去掉 `/* … */` 注释（引号里的不算注释）。没收尾的注释一直删到结尾。
String stripCssComments(String css) {
  if (!css.contains('/*')) return css;
  final out = StringBuffer();
  var quote = 0;
  var i = 0;
  while (i < css.length) {
    final c = css.codeUnitAt(i);
    if (quote != 0) {
      out.writeCharCode(c);
      if (c == _backslash && i + 1 < css.length) {
        out.writeCharCode(css.codeUnitAt(i + 1));
        i += 2;
        continue;
      }
      if (c == quote) quote = 0;
      i++;
      continue;
    }
    if (c == _quote1 || c == _quote2) {
      quote = c;
      out.writeCharCode(c);
      i++;
      continue;
    }
    if (c == 0x2F && i + 1 < css.length && css.codeUnitAt(i + 1) == 0x2A) {
      final end = css.indexOf('*/', i + 2);
      // 注释在 CSS 里相当于一个空白，留一个空格免得两边的词粘在一起。
      out.write(' ');
      i = end < 0 ? css.length : end + 2;
      continue;
    }
    out.writeCharCode(c);
    i++;
  }
  return out.toString();
}

/// 取出要解析的声明部分：有 `选择器 { … }` 就取第一对花括号里面的，没有就是整段。
/// [rest] 是第一条规则后面剩下的文字（调用方用来告诉用户“后面的没读”）。
({String body, String rest}) cssRuleBody(String css) {
  final open = _indexOfTopLevel(css, 0x7B, 0);
  if (open < 0) return (body: css, rest: '');
  var depth = 0;
  var quote = 0;
  for (var i = open; i < css.length; i++) {
    final c = css.codeUnitAt(i);
    if (quote != 0) {
      if (c == _backslash) {
        i++;
      } else if (c == quote) {
        quote = 0;
      }
      continue;
    }
    if (c == _quote1 || c == _quote2) {
      quote = c;
    } else if (c == 0x7B) {
      depth++;
    } else if (c == 0x7D) {
      depth--;
      if (depth == 0) return (body: css.substring(open + 1, i), rest: css.substring(i + 1));
    }
  }
  return (body: css.substring(open + 1), rest: '');
}

int _indexOfTopLevel(String s, int target, int from) {
  var quote = 0;
  for (var i = from; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    if (quote != 0) {
      if (c == _backslash) {
        i++;
      } else if (c == quote) {
        quote = 0;
      }
      continue;
    }
    if (c == _quote1 || c == _quote2) {
      quote = c;
    } else if (c == target) {
      return i;
    }
  }
  return -1;
}

/// 按“最外层”的 [separator] 切开：括号里、引号里的不算。空段也返回（调用方自己丢）。
List<String> splitTopLevel(String text, String separator) {
  assert(separator.length == 1, '分隔符只能是一个字符');
  final sep = separator.codeUnitAt(0);
  final parts = <String>[];
  var depth = 0;
  var quote = 0;
  var start = 0;
  for (var i = 0; i < text.length; i++) {
    final c = text.codeUnitAt(i);
    if (quote != 0) {
      if (c == _backslash) {
        i++;
      } else if (c == quote) {
        quote = 0;
      }
      continue;
    }
    if (c == _quote1 || c == _quote2) {
      quote = c;
    } else if (c == 0x28) {
      depth++;
    } else if (c == 0x29) {
      if (depth > 0) depth--;
    } else if (c == sep && depth == 0) {
      parts.add(text.substring(start, i));
      start = i + 1;
    }
  }
  parts.add(text.substring(start));
  return parts;
}

bool _isSpace(int c) => c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D || c == 0x0C;

/// 把值按最外层的空白切成一个个词：`1px solid rgb(0, 0, 0)` → `[1px, solid, rgb(0, 0, 0)]`。
List<String> cssTokens(String value) {
  final tokens = <String>[];
  var depth = 0;
  var quote = 0;
  var start = -1;
  for (var i = 0; i < value.length; i++) {
    final c = value.codeUnitAt(i);
    if (quote != 0) {
      if (c == _backslash) {
        i++;
      } else if (c == quote) {
        quote = 0;
      }
      continue;
    }
    if (_isSpace(c) && depth == 0) {
      if (start >= 0) tokens.add(value.substring(start, i));
      start = -1;
      continue;
    }
    if (start < 0) start = i;
    if (c == _quote1 || c == _quote2) {
      quote = c;
    } else if (c == 0x28) {
      depth++;
    } else if (c == 0x29) {
      if (depth > 0) depth--;
    }
  }
  if (start >= 0) tokens.add(value.substring(start));
  return tokens;
}

/// 引号外面的换行、制表符、连续空白收成一个空格（在 CSS 里意思一样）；引号里面的原样留着。
/// 这样多行写的值（比如几层阴影分几行）不会因为“值里不许有换行”被整条丢掉。
String collapseCssSpace(String value) {
  final out = StringBuffer();
  var quote = 0;
  var pendingSpace = false;
  for (var i = 0; i < value.length; i++) {
    final c = value.codeUnitAt(i);
    if (quote != 0) {
      out.writeCharCode(c);
      if (c == _backslash && i + 1 < value.length) {
        out.writeCharCode(value.codeUnitAt(++i));
      } else if (c == quote) {
        quote = 0;
      }
      continue;
    }
    if (_isSpace(c)) {
      pendingSpace = out.isNotEmpty;
      continue;
    }
    if (pendingSpace) out.write(' ');
    pendingSpace = false;
    if (c == _quote1 || c == _quote2) quote = c;
    out.writeCharCode(c);
  }
  return out.toString();
}

final RegExp _importantSuffix = RegExp(r'\s*!\s*important\s*$', caseSensitive: false);

/// 把值拆成“值本身”和“带不带 `!important`”。
({String value, bool important}) splitImportant(String value) {
  final m = _importantSuffix.firstMatch(value);
  if (m == null) return (value: value.trim(), important: false);
  return (value: value.substring(0, m.start).trim(), important: true);
}

/// 和 [splitImportant] 相反。`!important` 统一写成前面带一个空格的样子，这样拆开再合并的结果是稳定的。
String withImportant(String value, bool important) => important ? '$value !important' : value;

/// 对所有属性都有效的关键字：出现在简写里时，各个单项都取这个关键字。
const Set<String> cssWideKeywords = {'inherit', 'initial', 'unset', 'revert', 'revert-layer'};

bool isCssWideKeyword(String value) => cssWideKeywords.contains(value.toLowerCase());

final RegExp _number = RegExp(r'^[+-]?(\d+\.?\d*|\.\d+)$');

/// 是不是一个不带单位的数字（`1`、`0.5`、`-2`）。
bool isCssNumber(String token) => _number.hasMatch(token);
