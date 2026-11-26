import 'dart:convert';

import 'package:lopicode/lowcode/component_ops.dart';
import 'package:lopicode/lowcode/export_v3_fields.dart';
import 'package:lopicode/lowcode/logic_js.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/style_resolve.dart';

// 别的导出（Vue / React）要某个节点的 CSS 时用这几个函数，不要自己再拼一遍。
export 'package:lopicode/lowcode/style_resolve.dart' show nodeCssDeclarations, nodeCssRule, nodeCssSelector;

class LcHtmlExport {
  const LcHtmlExport(this.html, this.css, [this.js = '']);
  final String html;
  final String css;

  /// `logic.js` 的内容；页面没有逻辑时是空字符串（这时不生成文件，网页里也不引用它）。
  final String js;
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

/// 页面逻辑导出成的脚本文件名。
const String kLowcodeLogicFile = 'logic.js';

/// 我们生成的 logic.js 的第一行都以它开头；用来认“这是不是我们导出的文件”。
const String kLowcodeLogicMarker = '// 由 LopiCode 低代码搭建器生成';

/// 把页面导出成 `index.html` + `style.css`（有逻辑时再加 `logic.js`）的内容。
LcHtmlExport exportHtml(LcDocument doc) {
  final css = StringBuffer(_baseCss);
  final body = StringBuffer();

  void walk(LcNode n, LcNode? parent, int depth) {
    final pad = '  ' * (depth + 1);
    final cls = 'lc-${n.type} n-${n.id}';
    // 每个节点一条规则，内容是它的最终样式（简写属性 + 自己的 style，见 style_resolve.dart）。
    final rule = nodeCssRule(n, parent);
    if (rule.isNotEmpty) css.writeln(rule);
    switch (n.type) {
      case 'text':
        body.writeln('$pad<p class="$cls">${_esc.convert(n.strProp('text') ?? '')}</p>');
      case 'button':
        final text = n.strProp('text') ?? '';
        final icon = lcButtonIcon(n);
        body.writeln('$pad<button type="button" class="$cls"${lcIsDisabled(n) ? ' disabled' : ''}>${icon == null ? '' : lcIconSvg(icon, solo: text.isEmpty)}${_esc.convert(text)}</button>');
      case 'image':
        final src = n.strProp('src');
        final alt = n.strProp('alt');
        body.writeln(
          src == null
              ? '$pad<div class="$cls" role="img" aria-label="${alt == null ? '图片占位' : _escAttr.convert(alt)}"></div>'
              : '$pad<img class="$cls" src="${_escAttr.convert(src)}" alt="${alt == null ? '' : _escAttr.convert(alt)}">',
        );
      case 'input':
        final type = lcInputType(n), value = n.strProp('value'), label = lcInputLabel(n);
        final input =
            '<input class="$cls"${type == null ? '' : ' type="$type"'} placeholder="${_escAttr.convert(n.strProp('placeholder') ?? '')}"'
            '${value == null ? '' : ' value="${_escAttr.convert(value)}"'}${lcInputRequired(n) ? ' required' : ''}${lcIsDisabled(n) ? ' disabled' : ''}>';
        if (label == null) {
          body.writeln('$pad$input');
        } else {
          final fieldRule = lcFieldRule(n, parent, nodeCssSelector(n));
          if (fieldRule.isNotEmpty) css.writeln(fieldRule);
          body.writeln('$pad<label class="${lcFieldClass('n-${n.id}')}">');
          body.writeln('$pad  <span class="lc-label">${_esc.convert(label)}${lcInputRequired(n) ? '<span class="lc-required" aria-hidden="true"> *</span>' : ''}</span>');
          body.writeln('$pad  $input');
          body.writeln('$pad</label>');
        }
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
      case LcNode.unknownType:
        // 这一版不认识的组件（新版应用做的页面里才有）：内容导不出来，留一行注释说明。
        body.writeln('$pad<!-- 这里有一个新版应用加的组件，这一版导不出来 -->');
      case 'component':
        // 自定义组件的实例在下面 expandedTree 里已经展开成普通控件了；还能走到这儿的是展开不了的
        // （定义被删了，或者组件绕回来用到了自己）：留一行注释说明，再留一个空盒子占位（它的样式规则还在）。
        body.writeln('$pad<!-- 这里是一个自定义组件，内容没有导出：找不到它的定义，或者它绕回来用到了自己 -->');
        body.writeln('$pad<div class="$cls">');
        body.writeln('$pad</div>');
      default:
        final tag = n.type == 'page' ? 'main' : 'div';
        body.writeln('$pad<$tag class="$cls">');
        for (final c in n.children) {
          walk(c, n, depth + 1);
        }
        body.writeln('$pad</$tag>');
    }
  }

  // 实例展开后最外层沿用实例的 id、里面是“实例id__内部id”，所以 class 和 CSS 规则全页不重复。
  final tree = expandedTree(doc);
  walk(tree, null, 0);
  // 第 3 版加的属性要的公共样式：用到了才写（没用到的页面一个字节都不多）。
  css.write(lcV3ExtraCss(tree));
  final js = exportLogicJs(doc);
  // 没有逻辑的页面一个字节都不多（和第 1 版导出的一样）。
  final script = js.isEmpty ? '' : '  <script src="$kLowcodeLogicFile" defer></script>\n';

  final html =
      '''<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${_esc.convert(doc.title)}</title>
  <link rel="stylesheet" href="style.css">
$script</head>
<body>
$body</body>
</html>
''';
  return LcHtmlExport(html, css.toString(), js);
}
