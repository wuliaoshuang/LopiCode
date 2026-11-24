// HTML 格式化：按标签嵌套重新缩进。只在两种地方换行——原来就有换行的地方，和块级标签的边上
// （那里的空白不影响显示）；行内元素和文本不拆行，文本里同一行的空白不动。
// <pre> / <textarea> / <title> 的内容一个字节都不动；<script> / <style> 的内容交给 JS / CSS 格式化器，
// 它们处理不了就原样保留那一段。属性不重排、不改引号。
// 省略结束标签的写法（<p>、<li> 不闭合）这里不处理：遇到就整体放弃并说明。
import 'package:lopicode/format/format_common.dart';
import 'package:lopicode/format/format_css.dart';
import 'package:lopicode/format/format_js.dart';
import 'package:lopicode/format/format_json.dart';
import 'package:lopicode/format/html_lexer.dart';
import 'package:lopicode/format/js_lexer.dart';

bool _block(HtmlToken t) => kBlockTags.contains(t.name);

/// 配对开始 / 结束标签，顺便记下“直接子元素里有没有块级元素”。配不上就报错。
void _link(String s, List<HtmlToken> tokens) {
  final stack = <HtmlToken>[];
  for (final t in tokens) {
    if ((t.kind == HtmlKind.open || t.kind == HtmlKind.raw) && _block(t) && stack.isNotEmpty) stack.last.hasBlockChild = true;
    if (t.kind == HtmlKind.open && !t.leaf) {
      if (stack.length >= kMaxDepth * 5) throw FormatProblem('第 ${lineAt(s, t.offset)} 行起标签嵌套太深');
      stack.add(t);
    } else if (t.kind == HtmlKind.close) {
      if (stack.isEmpty) throw FormatProblem('第 ${lineAt(s, t.offset)} 行的 </${t.name}> 前面没有对应的 <${t.name}>');
      final open = stack.removeLast();
      if (open.name != t.name) {
        throw FormatProblem('第 ${lineAt(s, t.offset)} 行的 </${t.name}> 和第 ${lineAt(s, open.offset)} 行的 <${open.name}> 对不上（省略结束标签的写法这里不处理）');
      }
      t.hasBlockChild = open.hasBlockChild;
    }
  }
  if (stack.isNotEmpty) {
    throw FormatProblem('第 ${lineAt(s, stack.last.offset)} 行的 <${stack.last.name}> 没有闭合（省略结束标签的写法这里不处理）');
  }
}

/// [prev] 和 [t] 之间是不是一定要换行。只在块级标签的边上才会是真。
bool _forced(HtmlToken prev, HtmlToken t) {
  if (t.kind == HtmlKind.doctype || prev.kind == HtmlKind.doctype) return true;
  if ((t.kind == HtmlKind.open || t.kind == HtmlKind.raw) && _block(t)) return true;
  if ((prev.kind == HtmlKind.close || prev.kind == HtmlKind.raw || (prev.kind == HtmlKind.open && prev.leaf)) && _block(prev)) return true;
  if (prev.kind == HtmlKind.open && !prev.leaf && _block(prev) && prev.hasBlockChild) return true;
  if (t.kind == HtmlKind.close && _block(t) && t.hasBlockChild) return true;
  return false;
}

String _tagText(String tag, int lineLevel, int indent) {
  if (!tag.contains('\n') || quoteSpansLines(tag)) return tag;
  // 属性写了好几行：后面几行对齐到标签的下一层，单独一行的 > 和标签对齐
  final lines = tag.split('\n');
  final out = StringBuffer(trimWsRight(lines.first));
  for (var i = 1; i < lines.length; i++) {
    final line = trimWs(lines[i]);
    if (line.isEmpty) continue;
    out.write('\n${pad(line == '>' || line == '/>' ? lineLevel : lineLevel + 1, indent)}$line');
  }
  return out.toString();
}

final RegExp _typeAttr = RegExp(r'''\stype\s*=\s*["']?([^"'\s>]+)''', caseSensitive: false);
final RegExp _langAttr = RegExp(r'''\slang\s*=\s*["']?([^"'\s>]+)''', caseSensitive: false);

/// <script> / <style> 里面是哪种语言：js / json / css；不认识的（模板、TypeScript、scss…）返回 null，原样保留。
String? embeddedLanguage(String name, String openTag) {
  final type = _typeAttr.firstMatch(openTag)?.group(1)?.toLowerCase();
  final lang = _langAttr.firstMatch(openTag)?.group(1)?.toLowerCase();
  if (name == 'style') {
    return (type == null || type == 'text/css') && (lang == null || lang == 'css') ? 'css' : null;
  }
  if (name != 'script') return null;
  if (lang != null && lang != 'js' && lang != 'javascript' && lang != 'jsx') return null;
  if (type == null || type == 'module' || type == 'text/javascript' || type == 'application/javascript') return 'js';
  if (type.endsWith('json') || type == 'importmap') return 'json';
  return null;
}

FormatPiece formatEmbedded(String language, String content, int indent, int baseLevel) {
  if (language == 'css') return formatCss(content, indent: indent, baseLevel: baseLevel);
  if (language == 'js') return formatJs(content, indent: indent, baseLevel: baseLevel);
  // JSON 的字符串里不会有换行，整体往里推几格是安全的
  final padding = pad(baseLevel, indent);
  final lines = formatJson(content, indent: indent).text.split('\n');
  return FormatPiece([for (final l in lines) l.isEmpty ? l : '$padding$l'].join('\n'));
}

List<String> embeddedSignature(String language, String content) => switch (language) {
  'css' => cssSignature(content),
  'js' => jsSignature(content),
  _ => jsonSignature(content),
};

FormatPiece formatHtml(String source, {int indent = 2, int baseLevel = 0}) {
  final tokens = lexHtml(source);
  _link(source, tokens);
  final out = StringBuffer();
  final notes = <String>[];
  final tracker = LevelTracker(baseLevel);
  var atLineStart = true;
  var blank = false;
  var wrote = false;
  var line = 0;
  var lineLevel = baseLevel;

  bool breaks(int i) => i > 0 && (tokens[i].nl > 0 || _forced(tokens[i - 1], tokens[i]));

  for (var i = 0; i < tokens.length; i++) {
    final t = tokens[i];
    if (breaks(i)) {
      atLineStart = true;
      if (t.nl >= 2) blank = true;
    }
    var text = t.text;
    if (t.kind == HtmlKind.text) {
      // 换行处的空白不算数：行首行尾的去掉（只会发生在原来就换行的地方或块级标签边上）
      if (atLineStart) text = trimWsLeft(text);
      if (i + 1 >= tokens.length || breaks(i + 1)) text = trimWsRight(text);
      if (text.isEmpty) continue;
    }
    if (atLineStart) {
      var closers = 0;
      for (var j = i; j < tokens.length && tokens[j].kind == HtmlKind.close && (j == i || !breaks(j)); j++) {
        closers++;
      }
      lineLevel = tracker.levelAfterClosers(closers);
      if (wrote) out.write(blank ? '\n\n' : '\n');
      out.write(pad(lineLevel, indent));
      line++;
      atLineStart = false;
      blank = false;
    }
    wrote = true;
    switch (t.kind) {
      case HtmlKind.text || HtmlKind.doctype:
        out.write(text);
      case HtmlKind.comment:
        out.write(trimWsRight(text));
      case HtmlKind.close:
        out.write(text);
        tracker.close();
      case HtmlKind.open:
        out.write(_tagText(text, lineLevel, indent));
        if (!t.leaf) tracker.open(line, lineLevel);
      case HtmlKind.raw:
        final language = embeddedLanguage(t.name, text);
        // 内容里本来就有“</script”“</style”字样的（后面没跟 > 所以没被当成结束标签）：不排，
        // 免得排完多出一个空格、它真成了结束标签
        if (language == null || t.content.toLowerCase().contains('</${t.name}')) {
          out.write('$text${t.content}${t.closeText}');
        } else if (trimWs(t.content).isEmpty) {
          out.write('${_tagText(text, lineLevel, indent)}${t.closeText}');
        } else {
          try {
            final inner = trimWsRight(formatEmbedded(language, t.content, indent, lineLevel + 1).text);
            final open = _tagText(text, lineLevel, indent);
            out.write(inner.isEmpty ? '$open${t.closeText}' : '$open\n$inner\n${pad(lineLevel, indent)}${t.closeText}');
          } on FormatProblem catch (e) {
            // 里面的代码排不了：这一段原样保留，别的照常排
            out.write('$text${t.content}${t.closeText}');
            notes.add('第 ${lineAt(source, t.offset)} 行的 <${t.name}> 里面没有格式化（${shiftLines(e.message, lineAt(source, t.offset) - 1)}）');
          }
        }
    }
  }
  if (wrote) out.write('\n');
  return FormatPiece(out.toString(), note: notes.isEmpty ? null : notes.join('；'));
}

/// 把“第 N 行”里的行号加上 [by]（内嵌代码的行号换算成整个文件里的行号）。
String shiftLines(String message, int by) => message.replaceAllMapped(RegExp(r'第 (\d+) 行'), (m) => '第 ${int.parse(m.group(1)!) + by} 行');

final RegExp _spaces = RegExp(r'[ \t\n\r\f\v]+');

/// 比对格式化前后用：标签、文本里的词、注释，以及“这里有没有空白”。
/// 块级标签边上的空白不影响显示，不参与比对；别处的空白有和没有不一样，必须对得上。
List<String> htmlSignature(String source) {
  final tokens = lexHtml(source);
  final items = <String>[];
  final blockish = <bool>[];
  const gap = ' ';
  void add(String item, {bool block = false}) {
    if (item == gap && (items.isEmpty || items.last == gap)) return;
    items.add(item);
    blockish.add(block);
  }

  for (final t in tokens) {
    if (t.nl > 0) add(gap);
    switch (t.kind) {
      case HtmlKind.text:
        final words = t.text.split(_spaces);
        for (var k = 0; k < words.length; k++) {
          if (k > 0) add(gap);
          if (words[k].isNotEmpty) add('W ${words[k]}');
        }
      case HtmlKind.comment:
        add('C ${trimWsRight(t.text)}');
      case HtmlKind.doctype:
        add('D ${t.text}', block: true);
      case HtmlKind.open || HtmlKind.close:
        add('T ${collapseTag(t.text)}', block: _block(t));
      case HtmlKind.raw:
        final language = embeddedLanguage(t.name, t.text);
        List<String>? inner;
        if (language != null) {
          try {
            inner = embeddedSignature(language, t.content);
          } on FormatProblem {
            inner = null; // 里面的代码分不了词：那它一定是原样保留的，逐字比
          }
        }
        if (inner == null) {
          add('X ${t.text}${t.content}${t.closeText}', block: _block(t));
        } else {
          add('S ${collapseTag(t.text)}', block: true);
          for (final x in inner) {
            add('  $x', block: true);
          }
          add('E ${t.closeText}', block: true);
        }
    }
  }
  // 去掉块级标签边上、文件开头结尾的“空白”标记
  final out = <String>[];
  for (var i = 0; i < items.length; i++) {
    if (items[i] == gap) {
      final edge = i == 0 || i == items.length - 1;
      if (edge || blockish[i - 1] || blockish[i + 1]) continue;
    }
    out.add(items[i]);
  }
  return out;
}
