// HTML 分词：标签、文本、注释、<!DOCTYPE>，以及“里面不是 HTML”的整块元素（script / style / pre / textarea / title）。
// 属性原样留在标签文本里，不拆开、不改引号。
import 'package:lopicode/format/format_common.dart';

enum HtmlKind {
  /// 文本，按行切开：一行一个记号（换行两边的空白已去掉，同一行里的空白原样留着）
  text,
  comment,

  /// `<!DOCTYPE …>`、`<?xml …?>`、`<![CDATA[ … ]]>`
  doctype,
  open,
  close,

  /// 整块元素：[HtmlToken.text] 是开始标签，[HtmlToken.content] 是里面的原文，[HtmlToken.closeText] 是结束标签
  raw,
}

class HtmlToken {
  HtmlToken(this.kind, this.text, this.offset, this.nl, {this.name = '', this.content = '', this.closeText = ''});
  final HtmlKind kind;
  final String text;
  final int offset;

  /// 它前面隔了几个换行；0 表示和上一个记号在同一行。
  final int nl;

  /// 标签名（小写）。
  final String name;
  final String content;
  final String closeText;

  /// 不会有结束标签的：`<br>` 这类空元素，或写成 `<x />` 的。
  bool leaf = false;

  /// 直接子元素里有块级元素（配对时算出来，开始和结束标签上都记）。
  bool hasBlockChild = false;
}

const Set<String> kVoidTags = {'area', 'base', 'br', 'col', 'embed', 'hr', 'img', 'input', 'link', 'meta', 'param', 'source', 'track', 'wbr'};
const Set<String> kRawTags = {'script', 'style', 'pre', 'textarea', 'title'};

/// 块级元素：它们前后的空白不影响显示，可以放心换行。没列在这里的（行内元素、不认识的标签、Vue 组件）
/// 一律当行内处理：只在原来就有换行的地方换行。
const Set<String> kBlockTags = {
  'address', 'article', 'aside', 'base', 'blockquote', 'body', 'caption', 'col', 'colgroup', 'dd', 'details', 'dialog', 'div', 'dl', 'dt', //
  'fieldset', 'figcaption', 'figure', 'footer', 'form', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'head', 'header', 'hgroup', 'hr', 'html', 'li', 'link', 'main', //
  'meta', 'nav', 'noscript', 'ol', 'optgroup', 'option', 'p', 'pre', 'script', 'section', 'style', 'summary', 'table', 'tbody', 'td', 'tfoot', 'th', 'thead', 'title', 'tr', 'ul',
};

bool _letter(int c) => (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A);
bool _nameChar(int c) => _letter(c) || (c >= 0x30 && c <= 0x39) || c == 0x2D || c == 0x5F || c == 0x3A || c == 0x2E;

/// [i] 指着 `<`：返回这个标签结尾的 `>` 后面的位置。属性值的引号里可以有 `>`。
int scanTagEnd(String s, int i) {
  var j = i + 1;
  while (j < s.length) {
    final c = s[j];
    if (c == '"' || c == "'") {
      final end = s.indexOf(c, j + 1);
      if (end < 0) throw FormatProblem('第 ${lineAt(s, j)} 行的引号没有结束');
      j = end + 1;
    } else if (c == '>') {
      return j + 1;
    } else {
      j++;
    }
  }
  throw FormatProblem('第 ${lineAt(s, i)} 行的标签没有写完（少了 >）');
}

/// 位置 [i] 的 `<` 是不是一个标签 / 注释的开头（`a < b` 里的不是）。
bool tagStartsAt(String s, int i) {
  if (i + 1 >= s.length) return false;
  final c = s.codeUnitAt(i + 1);
  if (_letter(c) || c == 0x21 || c == 0x3F) return true;
  return c == 0x2F && i + 2 < s.length && _letter(s.codeUnitAt(i + 2));
}

String tagNameAt(String s, int i) {
  var j = i;
  while (j < s.length && _nameChar(s.codeUnitAt(j))) {
    j++;
  }
  return s.substring(i, j);
}

/// 标签文本里引号外面的连续空白压成一个空格（比对用：多行属性换缩进是允许的）。
String collapseTag(String tag) {
  final out = StringBuffer();
  String? quote;
  var gap = false;
  for (var i = 0; i < tag.length; i++) {
    final c = tag[i];
    if (quote != null) {
      out.write(c);
      if (c == quote) quote = null;
    } else if (isSpace(c.codeUnitAt(0))) {
      gap = true;
    } else {
      if (gap) out.write(' ');
      gap = false;
      out.write(c);
      if (c == '"' || c == "'") quote = c;
    }
  }
  return out.toString();
}

/// 标签里有没有跨行的引号（有的话整个标签原样保留）。
bool quoteSpansLines(String tag) {
  String? quote;
  for (var i = 0; i < tag.length; i++) {
    final c = tag[i];
    if (quote != null) {
      if (c == quote) quote = null;
      if (c == '\n') return true;
    } else if (c == '"' || c == "'") {
      quote = c;
    }
  }
  return false;
}

List<HtmlToken> lexHtml(String s) {
  final out = <HtmlToken>[];
  var i = 0;
  var nl = 0;
  void add(HtmlToken t) {
    out.add(t);
    nl = 0;
  }

  while (i < s.length) {
    if (s.startsWith('<!--', i)) {
      final end = s.indexOf('-->', i + 4);
      if (end < 0) throw FormatProblem('第 ${lineAt(s, i)} 行的注释没有结束（少了 -->）');
      add(HtmlToken(HtmlKind.comment, s.substring(i, end + 3), i, nl));
      i = end + 3;
    } else if (s.startsWith('<!', i) || s.startsWith('<?', i)) {
      final cdata = s.startsWith('<![CDATA[', i);
      final end = cdata ? s.indexOf(']]>', i) : s.indexOf('>', i);
      if (end < 0) throw FormatProblem('第 ${lineAt(s, i)} 行的“${s.substring(i, i + 2)}”没有结束');
      final stop = end + (cdata ? 3 : 1);
      add(HtmlToken(HtmlKind.doctype, s.substring(i, stop), i, nl));
      i = stop;
    } else if (s[i] == '<' && tagStartsAt(s, i) && s[i + 1] == '/') {
      final end = s.indexOf('>', i);
      if (end < 0) throw FormatProblem('第 ${lineAt(s, i)} 行的结束标签没有写完（少了 >）');
      add(HtmlToken(HtmlKind.close, s.substring(i, end + 1), i, nl, name: tagNameAt(s, i + 2).toLowerCase()));
      i = end + 1;
    } else if (s[i] == '<' && tagStartsAt(s, i)) {
      final end = scanTagEnd(s, i);
      final text = s.substring(i, end);
      final name = tagNameAt(s, i + 1).toLowerCase();
      final selfClosing = text.endsWith('/>');
      if (kRawTags.contains(name) && !selfClosing) {
        final m = RegExp('</$name(?=[\\s>/])', caseSensitive: false).allMatches(s, end).firstOrNull;
        if (m == null) throw FormatProblem('第 ${lineAt(s, i)} 行的 <$name> 没有对应的 </$name>');
        final closeEnd = s.indexOf('>', m.start);
        if (closeEnd < 0) throw FormatProblem('第 ${lineAt(s, m.start)} 行的结束标签没有写完（少了 >）');
        add(HtmlToken(HtmlKind.raw, text, i, nl, name: name, content: s.substring(end, m.start), closeText: s.substring(m.start, closeEnd + 1)));
        i = closeEnd + 1;
      } else {
        add(HtmlToken(HtmlKind.open, text, i, nl, name: name)..leaf = selfClosing || kVoidTags.contains(name));
        i = end;
      }
    } else {
      // 文本：一直到下一个标签。{{ … }}（Vue 等模板的插值）里的 < 不算标签。
      var j = i;
      while (j < s.length) {
        if (s[j] == '<' && tagStartsAt(s, j)) break;
        if (s.startsWith('{{', j)) {
          final end = s.indexOf('}}', j + 2);
          if (end >= 0) {
            j = end + 2;
            continue;
          }
        }
        j++;
      }
      final lines = s.substring(i, j).split('\n');
      var offset = i;
      for (var k = 0; k < lines.length; k++) {
        var line = lines[k];
        if (k > 0) {
          nl++;
          line = trimWsLeft(line);
        }
        if (k < lines.length - 1) line = trimWsRight(line);
        if (line.isNotEmpty) add(HtmlToken(HtmlKind.text, line, offset, nl));
        offset += lines[k].length + 1;
      }
      i = j;
    }
  }
  return out;
}
