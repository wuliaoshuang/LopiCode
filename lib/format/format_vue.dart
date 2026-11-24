// Vue 单文件组件格式化：把最外层的 <template> / <script> / <style> 三种块拆开，
// 分别交给 HTML / JS / CSS 格式化器，块之间空一行。块的顺序、块的开始标签原样保留。
// 不处理的块原样保留并在说明里讲清：lang="ts" 的脚本、scss / less / stylus 的样式、pug 模板、自定义块。
import 'package:lopicode/format/format_common.dart';
import 'package:lopicode/format/format_css.dart';
import 'package:lopicode/format/format_html.dart';
import 'package:lopicode/format/format_js.dart';
import 'package:lopicode/format/html_lexer.dart';
import 'package:lopicode/format/js_lexer.dart';

class _Block {
  _Block(this.name, this.open, this.content, this.close, this.offset);

  /// 标签名；最外层的注释是空串（整段在 [open] 里）。
  final String name;
  final String open;
  final String content;
  final String close;
  final int offset;
}

final RegExp _lang = RegExp(r'''\slang\s*=\s*["']?([^"'\s>]+)''', caseSensitive: false);

List<_Block> _split(String s) {
  final blocks = <_Block>[];
  var i = 0;
  while (i < s.length) {
    if (isSpace(s.codeUnitAt(i))) {
      i++;
      continue;
    }
    if (s.startsWith('<!--', i)) {
      final end = s.indexOf('-->', i + 4);
      if (end < 0) throw FormatProblem('第 ${lineAt(s, i)} 行的注释没有结束（少了 -->）');
      blocks.add(_Block('', s.substring(i, end + 3), '', '', i));
      i = end + 3;
      continue;
    }
    if (s[i] != '<' || !tagStartsAt(s, i) || s[i + 1] == '/' || s[i + 1] == '!' || s[i + 1] == '?') {
      throw FormatProblem('第 ${lineAt(s, i)} 行有不在 <template> / <script> / <style> 里面的内容');
    }
    final openEnd = scanTagEnd(s, i);
    final open = s.substring(i, openEnd);
    final name = tagNameAt(s, i + 1);
    if (open.endsWith('/>')) {
      blocks.add(_Block(name, open, '', '', i));
      i = openEnd;
      continue;
    }
    final closeStart = name == 'template' ? _templateEnd(s, openEnd, i) : s.indexOf('</$name', openEnd);
    if (closeStart < 0) throw FormatProblem('第 ${lineAt(s, i)} 行的 <$name> 没有对应的 </$name>');
    final closeEnd = s.indexOf('>', closeStart);
    if (closeEnd < 0) throw FormatProblem('第 ${lineAt(s, closeStart)} 行的结束标签没有写完（少了 >）');
    blocks.add(_Block(name, open, s.substring(openEnd, closeStart), s.substring(closeStart, closeEnd + 1), i));
    i = closeEnd + 1;
  }
  return blocks;
}

/// 最外层 <template> 的结束位置：里面还可以嵌 <template>，要数层数。
int _templateEnd(String s, int from, int openAt) {
  var depth = 1;
  var i = from;
  while (i < s.length) {
    final next = s.indexOf('<', i);
    if (next < 0) break;
    if (s.startsWith('<!--', next)) {
      final end = s.indexOf('-->', next + 4);
      if (end < 0) throw FormatProblem('第 ${lineAt(s, next)} 行的注释没有结束（少了 -->）');
      i = end + 3;
    } else if (s.startsWith('</template', next) && tagNameAt(s, next + 2) == 'template') {
      if (--depth == 0) return next;
      i = next + 10;
    } else if (tagStartsAt(s, next) && s[next + 1] != '/' && s[next + 1] != '!' && s[next + 1] != '?') {
      final end = scanTagEnd(s, next);
      if (tagNameAt(s, next + 1) == 'template' && !s.substring(next, end).endsWith('/>')) depth++;
      i = end;
    } else {
      i = next + 1;
    }
  }
  throw FormatProblem('第 ${lineAt(s, openAt)} 行的 <template> 没有对应的 </template>');
}

/// 这一块里面按哪种语言排：html / js / css；不排的返回 null。
String? _languageOf(_Block b) {
  final lang = _lang.firstMatch(b.open)?.group(1)?.toLowerCase();
  return switch (b.name) {
    'template' => lang == null || lang == 'html' ? 'html' : null,
    'script' => lang == null || lang == 'js' || lang == 'javascript' || lang == 'jsx' ? 'js' : null,
    'style' => lang == null || lang == 'css' ? 'css' : null,
    _ => null,
  };
}

FormatPiece _inner(String language, String content, int indent) => switch (language) {
  // 模板里的内容比 <template> 缩进一层；脚本和样式顶格写（Vue 的习惯写法）
  'html' => formatHtml(content, indent: indent, baseLevel: 1),
  'css' => formatCss(content, indent: indent),
  _ => formatJs(content, indent: indent),
};

List<String> _innerSignature(String language, String content) => switch (language) {
  'html' => htmlSignature(content),
  'css' => cssSignature(content),
  _ => jsSignature(content),
};

FormatPiece formatVue(String source, {int indent = 2}) {
  final blocks = _split(source);
  final parts = <String>[];
  final notes = <String>[];
  for (final b in blocks) {
    final verbatim = '${b.open}${b.content}${b.close}';
    final language = _languageOf(b);
    final line = lineAt(source, b.offset);
    if (b.name.isEmpty) {
      parts.add(verbatim);
    } else if (trimWs(b.content).isEmpty && b.close.isNotEmpty) {
      parts.add('${b.open}${b.close}');
    } else if (language == null) {
      parts.add(verbatim);
      final lang = _lang.firstMatch(b.open)?.group(1);
      if (b.close.isNotEmpty) notes.add(lang == null ? '<${b.name}> 块原样保留' : 'lang="$lang" 的 <${b.name}> 暂不格式化，原样保留');
    } else {
      try {
        final piece = _inner(language, b.content, indent);
        final text = trimWsRight(piece.text);
        parts.add(text.isEmpty ? '${b.open}${b.close}' : '${b.open}\n$text\n${b.close}');
        final note = piece.note;
        if (note != null) notes.add(shiftLines(note, line - 1));
      } on FormatProblem catch (e) {
        parts.add(verbatim);
        notes.add('<${b.name}> 里面没有格式化（${shiftLines(e.message, line - 1)}）');
      }
    }
  }
  return FormatPiece(parts.isEmpty ? '' : '${parts.join('\n\n')}\n', note: notes.isEmpty ? null : notes.join('；'));
}

/// 比对格式化前后用：每一块的开始标签 + 里面内容的记号序列（原样保留的块逐字比）。
List<String> vueSignature(String source) {
  final out = <String>[];
  for (final b in _split(source)) {
    out.add('B ${collapseTag(b.open)}');
    final language = _languageOf(b);
    List<String>? inner;
    if (language != null) {
      try {
        inner = _innerSignature(language, b.content);
      } on FormatProblem {
        inner = null; // 里面分不了词：那它一定是原样保留的，逐字比
      }
    }
    if (inner == null) {
      // 整块为空时，中间的空白可以去掉；别的情况逐字比
      out.add('X ${trimWs(b.content).isEmpty ? '' : b.content}');
    } else {
      out.addAll(inner.map((x) => '  $x'));
    }
    out.add('E ${b.close}');
  }
  return out;
}
