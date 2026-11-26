// 把切好的一块原文解析成节点树。Markdown 语法交给 Dart 官方的 `markdown` 包（只用它的解析器，拿到语法树后
// 转成我们自己的节点；它自带的 HTML 输出不用）。HTML 标签走 md_html.dart 的安全清单。
//
// 和标准 Markdown 不一样的地方（自己定的，按聊天习惯；2026-11-26）：
// - 单个换行也换行。
// - 不认“下一行一排 === / --- 把上一行变成标题”的写法（聊天里 `---` 基本都是分隔线，而且流式时会来回跳）。
// - 不认“缩进 4 格就是代码块”（模型常常只是缩进了一段话）；代码块只认围栏。
// - 原始 HTML 不照单全收：清单里的排版标签才生效，其余当文字。
import 'package:lopicode/markdown/md_chunker.dart';
import 'package:lopicode/markdown/md_html.dart';
import 'package:lopicode/markdown/md_nodes.dart';
import 'package:markdown/markdown.dart' as md;

/// 解析时互相嵌套（HTML 里的 Markdown 里的 HTML……）最多几层，超过就当文字。
const int kMdMaxNesting = 6;

/// 把整个标签（和注释）当成一个整体吃掉，后面再按安全清单决定它算不算数。
class _HtmlTagSyntax extends md.InlineSyntax {
  _HtmlTagSyntax() : super('$kHtmlTagPattern|<!--[\\s\\S]*?-->', startCharacter: 0x3c);

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Element.text('htmltag', match[0]!));
    return true;
  }
}

/// 行内公式：`$…$`（两头不能挨着空白，收尾的 `$` 后面不能跟数字——免得把“$5 和 $10”当公式）和 `\(…\)`。
class _MathSyntax extends md.InlineSyntax {
  _MathSyntax() : super(r'\$(?![\s$])((?:[^$\n\\]|\\.)+?)(?<![\s\\])\$(?![0-9])|\\\((.+?)\\\)');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Element.text('math', match[1] ?? match[2] ?? ''));
    return true;
  }
}

md.Document _newDocument() => md.Document(
  encodeHtml: false,
  withDefaultBlockSyntaxes: false,
  blockSyntaxes: const [
    md.EmptyBlockSyntax(),
    md.FencedCodeBlockSyntax(),
    md.TableSyntax(),
    md.HeaderSyntax(),
    md.BlockquoteSyntax(),
    md.HorizontalRuleSyntax(),
    md.UnorderedListWithCheckboxSyntax(),
    md.OrderedListWithCheckboxSyntax(),
    md.LinkReferenceDefinitionSyntax(),
    md.ParagraphSyntax(),
  ],
  inlineSyntaxes: [_HtmlTagSyntax(), _MathSyntax(), md.StrikethroughSyntax(), md.AutolinkExtensionSyntax()],
);

/// 解析一块。[refs] 是全文里的引用式链接定义；[streamingTail]＝这是还在往外冒的最后一块。
List<MdBlock> mdParseChunk(MdChunk chunk, {String refs = '', bool streamingTail = false, int depth = 0}) {
  switch (chunk.kind) {
    case MdChunkKind.fence:
      final lang = chunk.info.split(RegExp(r'[\s{,]')).first.toLowerCase();
      return [MdCode(chunk.body, lang: lang, closed: chunk.closed)];
    case MdChunkKind.math:
      return [MdCode(chunk.body, closed: chunk.closed, math: true)];
    case MdChunkKind.html:
      return _fromHtml(parseHtmlBlocks(chunk.source), refs, depth);
    case MdChunkKind.markdown:
      return _parseMarkdown(chunk.source, refs, streamingTail: streamingTail);
  }
}

/// 解析一段文字（先切块再逐块解析）。给 HTML 块里面的内容用。
List<MdBlock> mdParseText(String text, {String refs = '', int depth = 0}) {
  if (text.trim().isEmpty) return const [];
  if (depth > kMdMaxNesting) return [MdParagraph([MdText(text.trim())])];
  return [for (final c in mdSplitChunks(_dedent(text))) ...mdParseChunk(c, refs: refs, depth: depth)];
}

/// 只按行内规则解析（表格单元格、summary、标题里的内容）。
List<MdInline> mdParseInline(String text) {
  final t = text.trim();
  if (t.isEmpty) return const [];
  try {
    return _inlines(_newDocument().parseInline(t));
  } on Object {
    return [MdText(t)]; // 解析器自己出错：退回纯文字，不让一条消息把页面弄崩
  }
}

/// HTML 里的内容常常整体缩进着写：去掉公共缩进。
String _dedent(String text) {
  final lines = text.split('\n');
  int? min;
  for (final l in lines) {
    if (l.trim().isEmpty) continue;
    final n = l.length - l.trimLeft().length;
    if (min == null || n < min) min = n;
  }
  if (min == null || min == 0) return text;
  return [for (final l in lines) l.length >= min ? l.substring(min) : l.trimLeft()].join('\n');
}

List<MdBlock> _parseMarkdown(String source, String refs, {bool streamingTail = false}) {
  List<md.Node> nodes;
  try {
    nodes = _newDocument().parse(refs.isEmpty ? source : '$source\n\n$refs');
  } on Object {
    return [MdParagraph([MdText(source)])]; // 同上：解析器出错就按纯文字
  }
  final blocks = _blocks(nodes);
  if (streamingTail && blocks.isNotEmpty) {
    // 嵌在列表 / 引用里的围栏还没收尾：标成“开着的”
    final last = _deepLast(blocks.last);
    if (last is MdCode && _fenceCount(source).isOdd) {
      return _replaceDeepLast(blocks, MdCode(last.code, lang: last.lang, closed: false));
    }
  }
  return blocks;
}

int _fenceCount(String source) => RegExp(r'^[ \t>]*(`{3,}|~{3,})', multiLine: true).allMatches(source).length;

MdBlock _deepLast(MdBlock b) => switch (b) {
  MdQuote(:final children) when children.isNotEmpty => _deepLast(children.last),
  MdList(:final items) when items.isNotEmpty && items.last.children.isNotEmpty => _deepLast(items.last.children.last),
  _ => b,
};

List<MdBlock> _replaceDeepLast(List<MdBlock> blocks, MdBlock to) {
  MdBlock swap(MdBlock b) => switch (b) {
    MdQuote(:final children) when children.isNotEmpty => MdQuote([...children.take(children.length - 1), swap(children.last)]),
    MdList(:final items, :final ordered, :final start) when items.isNotEmpty && items.last.children.isNotEmpty => MdList(
      [
        ...items.take(items.length - 1),
        MdListItem([...items.last.children.take(items.last.children.length - 1), swap(items.last.children.last)], checked: items.last.checked),
      ],
      ordered: ordered,
      start: start,
    ),
    _ => to,
  };
  return [...blocks.take(blocks.length - 1), swap(blocks.last)];
}

const Set<String> _blockTags = {'p', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'blockquote', 'ul', 'ol', 'pre', 'hr', 'table'};

bool _isBlock(md.Node n) => n is md.Element && _blockTags.contains(n.tag);

/// 块和行内混在一起的一串节点（列表项里常见）：连续的行内内容凑成一段。
List<MdBlock> _blocks(List<md.Node> nodes) {
  final out = <MdBlock>[];
  final loose = <md.Node>[];
  void flush() {
    if (loose.isEmpty) return;
    final inl = _inlines(loose);
    if (mdPlainText(inl).trim().isNotEmpty || inl.any((n) => n is MdImage)) out.add(MdParagraph(inl));
    loose.clear();
  }

  for (final n in nodes) {
    if (!_isBlock(n)) {
      loose.add(n);
      continue;
    }
    flush();
    final e = n as md.Element;
    final kids = e.children ?? const <md.Node>[];
    switch (e.tag) {
      case 'p':
        out.add(MdParagraph(_inlines(kids)));
      case 'blockquote':
        out.add(MdQuote(_blocks(kids)));
      case 'ul' || 'ol':
        out.add(MdList([for (final li in kids.whereType<md.Element>()) _listItem(li)], ordered: e.tag == 'ol', start: int.tryParse(e.attributes['start'] ?? '') ?? 1));
      case 'pre':
        final code = kids.whereType<md.Element>().firstOrNull;
        final cls = code?.attributes['class'] ?? '';
        var text = e.textContent;
        if (text.endsWith('\n')) text = text.substring(0, text.length - 1);
        out.add(MdCode(text, lang: cls.startsWith('language-') ? cls.substring(9).toLowerCase() : ''));
      case 'hr':
        out.add(const MdRule());
      case 'table':
        out.add(_table(e));
      default:
        out.add(MdHeading(int.parse(e.tag.substring(1)), _inlines(kids)));
    }
  }
  flush();
  return out;
}

MdListItem _listItem(md.Element li) {
  bool? checked;
  bool isBox(md.Node n) => n is md.Element && n.tag == 'input';
  List<md.Node> strip(List<md.Node> nodes) {
    final out = <md.Node>[];
    for (final n in nodes) {
      if (isBox(n)) {
        checked ??= (n as md.Element).attributes.containsKey('checked');
        continue;
      }
      // 松散列表：勾选框被放进了第一段里
      if (checked == null && n is md.Element && n.tag == 'p' && (n.children?.isNotEmpty ?? false) && isBox(n.children!.first)) {
        checked = (n.children!.first as md.Element).attributes.containsKey('checked');
        out.add(md.Element('p', n.children!.sublist(1)));
        continue;
      }
      out.add(n);
    }
    return out;
  }

  final kids = strip(li.children ?? const []);
  return MdListItem(_blocks(kids), checked: checked);
}

MdTable _table(md.Element table) {
  List<List<MdInline>> header = const [];
  final rows = <List<List<MdInline>>>[];
  final aligns = <MdAlign>[];
  for (final section in table.children?.whereType<md.Element>() ?? const <md.Element>[]) {
    for (final tr in section.children?.whereType<md.Element>() ?? const <md.Element>[]) {
      final cells = tr.children?.whereType<md.Element>().toList() ?? const <md.Element>[];
      final row = [for (final c in cells) _inlines(c.children ?? const [])];
      if (section.tag == 'thead') {
        header = row;
        for (final c in cells) {
          aligns.add(_alignOf('${c.attributes['align'] ?? ''} ${c.attributes['style'] ?? ''}'));
        }
      } else {
        rows.add(row);
      }
    }
  }
  return MdTable(header: header, rows: rows, aligns: aligns);
}

MdAlign _alignOf(String s) => s.contains('center')
    ? MdAlign.center
    : s.contains('right')
    ? MdAlign.right
    : MdAlign.left;

class _Frame {
  _Frame(this.tag);
  final HtmlTag? tag;
  final List<MdInline> out = [];
}

List<MdInline> _inlines(List<md.Node> nodes) {
  final stack = <_Frame>[_Frame(null)];
  void add(MdInline n) {
    final out = stack.last.out;
    if (n is MdText && out.isNotEmpty && out.last is MdText) {
      out[out.length - 1] = MdText((out.last as MdText).text + n.text);
    } else {
      out.add(n);
    }
  }

  void pop() {
    final f = stack.removeLast();
    for (final n in _wrap(f.tag!, f.out)) {
      add(n);
    }
  }

  for (final n in nodes) {
    if (n is md.Text) {
      add(MdText(n.text));
      continue;
    }
    if (n is! md.Element) {
      add(MdText(n.textContent));
      continue;
    }
    final kids = n.children ?? const <md.Node>[];
    switch (n.tag) {
      case 'htmltag':
        final raw = n.textContent;
        if (raw.startsWith('<!--')) break; // 注释：不显示
        final tag = parseHtmlTag(raw);
        if (tag == null || !kMdInlineTags.contains(tag.name)) {
          add(MdText(raw)); // 不在清单里：当文字
        } else if (tag.name == 'br') {
          add(const MdBreak());
        } else if (tag.name == 'img') {
          final src = tag.attrs['src'] ?? '';
          if (src.isNotEmpty) add(MdImage(src, tag.attrs['alt'] ?? ''));
        } else if (tag.closing) {
          final at = stack.lastIndexWhere((f) => f.tag?.name == tag.name);
          if (at <= 0) {
            add(MdText(raw)); // 没有对应的开标签
          } else {
            while (stack.length > at) {
              pop();
            }
          }
        } else if (!tag.selfClosing) {
          stack.add(_Frame(tag));
        }
      case 'strong':
        add(MdStyled(MdStyle.bold, _inlines(kids)));
      case 'em':
        add(MdStyled(MdStyle.italic, _inlines(kids)));
      case 'del':
        add(MdStyled(MdStyle.strike, _inlines(kids)));
      case 'code':
        add(MdInlineCode(n.textContent));
      case 'math':
        add(MdInlineCode(n.textContent, math: true));
      case 'a':
        final href = n.attributes['href'] ?? '';
        final inner = _inlines(kids);
        if (href.isEmpty) {
          inner.forEach(add);
        } else {
          add(MdLink(href, inner));
        }
      case 'img':
        final src = n.attributes['src'] ?? '';
        if (src.isNotEmpty) add(MdImage(src, n.attributes['alt'] ?? n.textContent));
      case 'br':
        add(const MdBreak());
      case 'input':
        break;
      default:
        _inlines(kids).forEach(add);
    }
  }
  while (stack.length > 1) {
    pop(); // 没收尾的标签：算到这一段结束
  }
  return stack.first.out;
}

List<MdInline> _wrap(HtmlTag tag, List<MdInline> kids) {
  MdInline styled(MdStyle s) => MdStyled(s, kids);
  return switch (tag.name) {
    'b' || 'strong' => [styled(MdStyle.bold)],
    'i' || 'em' || 'cite' => [styled(MdStyle.italic)],
    'u' || 'ins' => [styled(MdStyle.underline)],
    's' || 'del' || 'strike' => [styled(MdStyle.strike)],
    'kbd' => [styled(MdStyle.kbd)],
    'sub' => [styled(MdStyle.sub)],
    'sup' => [styled(MdStyle.sup)],
    'mark' => [styled(MdStyle.mark)],
    'code' => [MdInlineCode(mdPlainText(kids))],
    'q' => [const MdText('“'), ...kids, const MdText('”')],
    'a' => (tag.attrs['href'] ?? '').isEmpty ? kids : [MdLink(tag.attrs['href']!, kids)],
    _ => kids, // span / font / small / big / abbr：只留内容
  };
}

final RegExp _anyTag = RegExp(kHtmlTagPattern);

List<MdBlock> _fromHtml(List<HtmlNode> nodes, String refs, int depth) {
  final out = <MdBlock>[];
  List<MdBlock> kidsOf(HtmlElementNode e) => _fromHtml(e.children, refs, depth + 1);
  for (final n in nodes) {
    switch (n) {
      case HtmlTextNode(:final text):
        out.addAll(mdParseText(text, refs: refs, depth: depth + 1));
      case final HtmlElementNode e:
        switch (e.name) {
          case 'details':
            final summary = e.children.whereType<HtmlElementNode>().where((c) => c.name == 'summary').firstOrNull;
            final rest = [
              for (final c in e.children)
                if (!identical(c, summary)) c,
            ];
            out.add(MdDetails(summary == null ? const [MdText('详情')] : mdParseInline(summary.innerSource), _fromHtml(rest, refs, depth + 1), open: e.tag.attrs.containsKey('open')));
          case 'table':
            out.add(_htmlTable(e));
          case 'ul' || 'ol':
            final items = <MdListItem>[];
            for (final c in e.children) {
              if (c is HtmlElementNode && c.name == 'li') {
                items.add(MdListItem(kidsOf(c)));
              } else if (c is HtmlElementNode || (c is HtmlTextNode && c.text.trim().isNotEmpty)) {
                items.add(MdListItem(_fromHtml([c], refs, depth + 1)));
              }
            }
            if (items.isNotEmpty) out.add(MdList(items, ordered: e.name == 'ol', start: int.tryParse(e.tag.attrs['start'] ?? '') ?? 1));
          case 'blockquote':
            out.add(MdQuote(kidsOf(e)));
          case 'pre':
            var code = decodeHtmlEntities(e.innerSource.replaceAll(_anyTag, ''));
            if (code.startsWith('\n')) code = code.substring(1);
            if (code.endsWith('\n')) code = code.substring(0, code.length - 1);
            out.add(MdCode(code));
          case 'hr':
            out.add(const MdRule());
          case 'h1' || 'h2' || 'h3' || 'h4' || 'h5' || 'h6':
            out.add(MdHeading(int.parse(e.name.substring(1)), mdParseInline(e.innerSource)));
          default:
            // p / div / center，以及落单的 summary / li / tr / td……：只留内容
            out.addAll(kidsOf(e));
        }
    }
  }
  return out;
}

MdTable _htmlTable(HtmlElementNode table) {
  final rows = <List<List<MdInline>>>[];
  List<List<MdInline>> header = const [];
  final aligns = <MdAlign>[];
  void walk(HtmlElementNode e, {required bool inHead}) {
    for (final c in e.children.whereType<HtmlElementNode>()) {
      if (c.name == 'tr') {
        final cells = c.children.whereType<HtmlElementNode>().where((x) => x.name == 'td' || x.name == 'th').toList();
        final row = [for (final x in cells) mdParseInline(x.innerSource)];
        final isHead = header.isEmpty && rows.isEmpty && (inHead || (cells.isNotEmpty && cells.every((x) => x.name == 'th')));
        if (isHead) {
          header = row;
        } else {
          rows.add(row);
        }
        if (aligns.isEmpty) aligns.addAll([for (final x in cells) _alignOf(x.tag.attrs['align'] ?? '')]);
      } else if (c.name == 'thead' || c.name == 'tbody' || c.name == 'tfoot') {
        walk(c, inHead: c.name == 'thead');
      }
    }
  }

  walk(table, inHead: false);
  return MdTable(header: header, rows: rows, aligns: aligns);
}
