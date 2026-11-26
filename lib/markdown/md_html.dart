// 消息里的 HTML：只认一份“排版用”的安全清单，别的一律不当标签（按纯文字原样显示）。纯文字处理，不执行任何东西。
//
// 清单（自己定的，2026-11-26）：
// - 行内：b strong i em u ins s del strike code kbd sub sup mark span font small big abbr cite q a img br
// - 块：p div center details summary table thead tbody tfoot tr th td ul ol li blockquote pre h1–h6 hr
// - 属性只留：a 的 href；img 的 src / alt；th / td 的 align；details 的 open；ol 的 start。其余属性
//   （style、class、id、on* 事件……）全部丢掉，不读也不执行。
// - `<script>` `<style>` `<iframe>` 和任何不在清单里的标签：当成普通文字显示出来（看得见源码，但不执行、不变成界面）。

/// 一个 HTML 标签（开或关）。
class HtmlTag {
  const HtmlTag(this.name, {this.closing = false, this.selfClosing = false, this.attrs = const {}, this.raw = ''});
  final String name;
  final bool closing;
  final bool selfClosing;
  final Map<String, String> attrs;
  final String raw;
}

const Set<String> kMdInlineTags = {
  'b',
  'strong',
  'i',
  'em',
  'u',
  'ins',
  's',
  'del',
  'strike',
  'code',
  'kbd',
  'sub',
  'sup',
  'mark',
  'span',
  'font',
  'small',
  'big',
  'abbr',
  'cite',
  'q',
  'a',
  'img',
  'br',
};
const Set<String> kMdBlockTags = {
  'p',
  'div',
  'center',
  'details',
  'summary',
  'table',
  'thead',
  'tbody',
  'tfoot',
  'tr',
  'th',
  'td',
  'ul',
  'ol',
  'li',
  'blockquote',
  'pre',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'hr',
};
const Set<String> kMdVoidTags = {'br', 'img', 'hr'};

/// 每种标签允许留下的属性。
const Map<String, Set<String>> kMdTagAttrs = {
  'a': {'href'},
  'img': {'src', 'alt'},
  'th': {'align'},
  'td': {'align'},
  'details': {'open'},
  'ol': {'start'},
};

/// 一个标签的写法（也用来给 Markdown 解析器“整个吃掉标签”，免得里面的网址、星号被当成语法）。
const String kHtmlTagPattern = r'''</?[a-zA-Z][a-zA-Z0-9]*(?:\s+(?:[^<>"']|"[^"]*"|'[^']*')*)?\s*/?>''';
final RegExp htmlTagRe = RegExp(kHtmlTagPattern);
final RegExp _tagHead = RegExp(r'^<(/?)([a-zA-Z][a-zA-Z0-9]*)');
final RegExp _attr = RegExp(r'''([a-zA-Z_:][-a-zA-Z0-9_:.]*)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+)))?''');

/// 解析一个标签的原文；不是标签返回 null。属性只留清单里的。
HtmlTag? parseHtmlTag(String raw) {
  final head = _tagHead.firstMatch(raw);
  if (head == null || !raw.endsWith('>')) return null;
  final name = head[2]!.toLowerCase();
  final closing = head[1] == '/';
  final keep = kMdTagAttrs[name] ?? const <String>{};
  final attrs = <String, String>{};
  if (!closing && keep.isNotEmpty) {
    final rest = raw.substring(head.end, raw.length - 1);
    for (final m in _attr.allMatches(rest)) {
      final key = m[1]!.toLowerCase();
      if (!keep.contains(key) || attrs.containsKey(key)) continue;
      attrs[key] = decodeHtmlEntities(m[2] ?? m[3] ?? m[4] ?? '');
    }
  }
  return HtmlTag(name, closing: closing, selfClosing: raw.endsWith('/>') || kMdVoidTags.contains(name), attrs: attrs, raw: raw);
}

const Map<String, String> _entities = {
  'amp': '&',
  'lt': '<',
  'gt': '>',
  'quot': '"',
  'apos': "'",
  'nbsp': '\u00A0',
  'copy': '©',
  'reg': '®',
  'trade': '™',
  'hellip': '…',
  'mdash': '—',
  'ndash': '–',
  'middot': '·',
  'times': '×',
  'larr': '←',
  'rarr': '→',
  'uarr': '↑',
  'darr': '↓',
  'laquo': '«',
  'raquo': '»',
  'ldquo': '“',
  'rdquo': '”',
  'lsquo': '‘',
  'rsquo': '’',
  'emsp': '\u2003',
  'ensp': '\u2002',
};
final RegExp _entity = RegExp(r'&(#[xX][0-9a-fA-F]{1,6}|#[0-9]{1,7}|[a-zA-Z][a-zA-Z0-9]{1,10});');

/// 把 `&amp;` 这类写法换回字符；不认识的原样留着。
String decodeHtmlEntities(String s) {
  if (!s.contains('&')) return s;
  return s.replaceAllMapped(_entity, (m) {
    final body = m[1]!;
    if (body.startsWith('#')) {
      final hex = body[1] == 'x' || body[1] == 'X';
      final code = int.tryParse(body.substring(hex ? 2 : 1), radix: hex ? 16 : 10);
      // 0、代理区、超出范围的编号不是合法字符
      if (code == null || code == 0 || code > 0x10FFFF || (code >= 0xD800 && code <= 0xDFFF)) return m[0]!;
      return String.fromCharCode(code);
    }
    return _entities[body] ?? m[0]!;
  });
}

/// HTML 块解析出来的小树：只有清单里的块标签成为节点，其余内容（包括行内标签、不认识的标签）留在文字里，
/// 交给 Markdown 那一层按行内规则处理。
sealed class HtmlNode {
  const HtmlNode();
}

class HtmlTextNode extends HtmlNode {
  const HtmlTextNode(this.text);
  final String text;
}

class HtmlElementNode extends HtmlNode {
  HtmlElementNode(this.tag) : children = [];
  final HtmlTag tag;
  final List<HtmlNode> children;
  String get name => tag.name;

  /// 里面全部内容的原文（子标签按原样拼回去）。
  String get innerSource {
    final b = StringBuffer();
    void walk(HtmlNode n) {
      switch (n) {
        case HtmlTextNode(:final text):
          b.write(text);
        case final HtmlElementNode e:
          b.write(e.tag.raw);
          e.children.forEach(walk);
          if (!e.tag.selfClosing) b.write('</${e.name}>');
      }
    }

    children.forEach(walk);
    return b.toString();
  }
}

/// 嵌套太深的 HTML 不再往下拆（当文字显示），免得畸形内容把解析拖垮。
const int kHtmlMaxDepth = 12;

final RegExp _comment = RegExp(r'<!--[\s\S]*?(-->|$)');

/// 把一段 HTML 拆成小树。没收尾的标签自动收尾；多出来的关标签当文字。
List<HtmlNode> parseHtmlBlocks(String source) {
  final text = source.replaceAll(_comment, '');
  final root = HtmlElementNode(const HtmlTag('#root'));
  final stack = <HtmlElementNode>[root];
  var pos = 0;

  void addText(String s) {
    if (s.isEmpty) return;
    final list = stack.last.children;
    if (list.isNotEmpty && list.last is HtmlTextNode) {
      list[list.length - 1] = HtmlTextNode((list.last as HtmlTextNode).text + s);
    } else {
      list.add(HtmlTextNode(s));
    }
  }

  for (final m in htmlTagRe.allMatches(text)) {
    final tag = parseHtmlTag(m[0]!);
    final inPre = stack.last.name == 'pre';
    final isBlock = tag != null && kMdBlockTags.contains(tag.name) && !(inPre && !(tag.closing && tag.name == 'pre'));
    if (!isBlock) continue; // 留在文字里
    addText(text.substring(pos, m.start));
    pos = m.end;
    if (tag.closing) {
      final at = stack.lastIndexWhere((e) => e.name == tag.name);
      if (at <= 0) {
        addText(m[0]!); // 没有对应的开标签
      } else {
        stack.removeRange(at, stack.length);
      }
      continue;
    }
    if (stack.length > kHtmlMaxDepth) {
      addText(m[0]!);
      continue;
    }
    // <p> 里不能再套块；<li> / <tr> / <td> 遇到同级的自动收掉上一个
    final autoClose = switch (tag.name) {
      'li' => const {'li'},
      'tr' => const {'tr', 'td', 'th'},
      'td' || 'th' => const {'td', 'th'},
      'p' => const {'p'},
      _ => const <String>{},
    };
    if (autoClose.contains(stack.last.name)) {
      final at = stack.lastIndexWhere((e) => e.name == (tag.name == 'tr' ? 'tr' : stack.last.name));
      if (at > 0) stack.removeRange(at, stack.length);
    }
    final el = HtmlElementNode(tag);
    stack.last.children.add(el);
    if (!tag.selfClosing) stack.add(el);
  }
  addText(text.substring(pos));
  return root.children;
}

final RegExp _docStart = RegExp(r'^\s*(<!doctype\s+html|<html[\s>])', caseSensitive: false);

/// 一整段回复就是一份完整的网页（以 `<!doctype html>` 或 `<html>` 开头）。
bool looksLikeHtmlDocument(String text) => _docStart.hasMatch(text);
