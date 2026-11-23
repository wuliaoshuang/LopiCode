import 'dart:convert';

import 'package:lopicode/lowcode/model.dart';

class LcHtmlExport {
  const LcHtmlExport(this.html, this.css);
  final String html;
  final String css;
}

const _esc = HtmlEscape(HtmlEscapeMode.element);
const _escAttr = HtmlEscape(HtmlEscapeMode.attribute);

const String _baseCss = '''/* 由 LopiCode 低代码搭建器生成，重新导出会覆盖本文件 */
* { box-sizing: border-box; }
body {
  margin: 0;
  font-family: system-ui, -apple-system, "PingFang SC", "Noto Sans SC", sans-serif;
  color: #222435;
}
.lc-page, .lc-container, .lc-column, .lc-card { display: flex; flex-direction: column; }
.lc-row { display: flex; flex-direction: row; }
.lc-page { min-height: 100vh; }
.lc-card { box-shadow: 0 1px 3px rgba(0, 0, 0, .2); }
.lc-text { margin: 0; line-height: 1.5; }
.lc-button { border: 0; cursor: pointer; font: inherit; }
.lc-input { border: 1px solid #b1c0c8; font: inherit; padding: 10px 12px; min-width: 0; }
.lc-image { display: block; max-width: 100%; object-fit: cover; background: #d3dee4; }
.lc-list { margin: 0; padding-left: 20px; line-height: 1.75; }
.lc-divider { border: 0; border-top: 1px solid #d3dee4; margin: 0; align-self: stretch; }
''';

/// 把页面导出成 `index.html` + `style.css` 两个文件的内容。
LcHtmlExport exportHtml(LcDocument doc) {
  final css = StringBuffer(_baseCss);
  final body = StringBuffer();

  void walk(LcNode n, LcNode? parent, int depth) {
    final pad = '  ' * (depth + 1);
    final cls = 'lc-${n.type} n-${n.id}';
    final rules = _rules(n, parent);
    if (rules.isNotEmpty) {
      css.writeln('.n-${n.id} { ${rules.join(' ')} }');
    }
    switch (n.type) {
      case 'text':
        body.writeln('$pad<p class="$cls">${_esc.convert(n.strProp('text') ?? '')}</p>');
      case 'button':
        body.writeln('$pad<button type="button" class="$cls">${_esc.convert(n.strProp('text') ?? '')}</button>');
      case 'image':
        final src = n.strProp('src');
        body.writeln(src == null ? '$pad<div class="$cls" role="img" aria-label="图片占位"></div>' : '$pad<img class="$cls" src="${_escAttr.convert(src)}" alt="">');
      case 'input':
        body.writeln('$pad<input class="$cls" placeholder="${_escAttr.convert(n.strProp('placeholder') ?? '')}">');
      case 'list':
        body.writeln('$pad<ul class="$cls">');
        for (final item in (n.props['items'] as List?) ?? const []) {
          body.writeln('$pad  <li>${_esc.convert('$item')}</li>');
        }
        body.writeln('$pad</ul>');
      case 'divider':
        body.writeln('$pad<hr class="$cls">');
      case 'spacer':
        body.writeln('$pad<div class="$cls"></div>');
      default:
        final tag = n.type == 'page' ? 'main' : 'div';
        body.writeln('$pad<$tag class="$cls">');
        for (final c in n.children) {
          walk(c, n, depth + 1);
        }
        body.writeln('$pad</$tag>');
    }
  }

  walk(doc.root, null, 0);

  final html =
      '''<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${_esc.convert(doc.title)}</title>
  <link rel="stylesheet" href="style.css">
</head>
<body>
$body</body>
</html>
''';
  return LcHtmlExport(html, css.toString());
}

String _n(num v) => v == v.roundToDouble() ? '${v.round()}' : '$v';

List<String> _rules(LcNode n, LcNode? parent) {
  final r = <String>[];
  if (n.type == 'spacer') {
    final size = _n(n.numProp('size') ?? 16);
    return ['flex: 0 0 ${size}px;', if (parent?.type == 'row') 'width: ${size}px;' else 'height: ${size}px;'];
  }
  final width = n.props['width'];
  // 行里的容器类组件：没给固定宽度就平分剩余空间（和导出的 Flutter 代码规则一致）。
  if (width == 'fill' || (parent?.type == 'row' && n.isContainer && width is! num)) {
    r.add(parent?.type == 'row' ? 'flex: 1; min-width: 0;' : 'align-self: stretch;');
  } else if (width is num) {
    r.add('width: ${_n(width)}px;');
  }
  final height = n.numProp('height');
  if (height != null) r.add('height: ${_n(height)}px;');
  final padding = n.numProp('padding');
  if (padding != null) r.add('padding: ${_n(padding)}px;');
  final margin = n.numProp('margin');
  if (margin != null) r.add('margin: ${_n(margin)}px;');
  final bg = n.strProp('bg');
  if (bg != null) r.add('background: ${bg.toLowerCase()};');
  final color = n.strProp('color');
  if (color != null) r.add('color: ${color.toLowerCase()};');
  final radius = n.numProp('radius');
  if (radius != null) r.add('border-radius: ${_n(radius)}px;');
  final fontSize = n.numProp('fontSize');
  if (fontSize != null) r.add('font-size: ${_n(fontSize)}px;');
  if (n.props['bold'] == true) r.add('font-weight: 600;');
  final textAlign = n.strProp('textAlign');
  if (textAlign != null) r.add('text-align: $textAlign;');
  if (n.isContainer) {
    final gap = n.numProp('gap');
    if (gap != null) r.add('gap: ${_n(gap)}px;');
    const align = {'start': 'flex-start', 'center': 'center', 'end': 'flex-end', 'stretch': 'stretch'};
    const justify = {'start': 'flex-start', 'center': 'center', 'end': 'flex-end', 'between': 'space-between'};
    final a = n.strProp('align');
    if (a != null) r.add('align-items: ${align[a]};');
    final j = n.strProp('justify');
    if (j != null) r.add('justify-content: ${justify[j]};');
  }
  return r;
}
