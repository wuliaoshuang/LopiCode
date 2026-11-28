import 'dart:convert';

import 'package:lopicode/lowcode/box_off.dart';
import 'package:lopicode/lowcode/export_web_v3_css.dart';
import 'package:lopicode/lowcode/icon_set.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/style_resolve.dart';

/// 格式第 3 版加的那批属性（按钮图标 / 禁用，图片说明文字，输入框类型 / 值 / 标签 / 必填 / 禁用）在网页类导出里怎么写。
/// 网页、Vue、React 三份导出共用这里的判断和 CSS，免得三处各拼一遍。
///
/// 规矩：**页面没用到这些属性，导出就一个字节都不多**（旧页面的导出不变，见 test/lowcode_export_baseline_test.dart）。

const _escAttr = HtmlEscape(HtmlEscapeMode.attribute);

/// 这个按钮带的图标（名字认识才算）。
LcIcon? lcButtonIcon(LcNode n) => n.type == 'button' ? lcIconByName(n.strProp('icon')) : null;

bool lcIsDisabled(LcNode n) => (n.type == 'button' || n.type == 'input') && n.props['disabled'] == true;

/// 输入框上面的标签文字；没有返回 null。
String? lcInputLabel(LcNode n) => n.type == 'input' || n.type == 'textarea' ? n.strProp('label') : null;

bool lcInputRequired(LcNode n) => (n.type == 'input' || n.type == 'textarea') && n.props['required'] == true;

/// 输入框的类型；文字（默认）返回 null。
String? lcInputType(LcNode n) {
  final t = n.type == 'input' ? n.strProp('inputType') : null;
  return t == null || t == 'text' ? null : t;
}

/// 图标的 SVG。[classAttr]：HTML / Vue 是 `class`，React 是 `className`。[solo]：按钮上没有字，图标右边不留空。
String lcIconSvg(LcIcon icon, {String classAttr = 'class', bool solo = false, bool jsx = false}) =>
    '<svg $classAttr="lc-icon${solo ? ' lc-icon-solo' : ''}" viewBox="0 0 24 24" aria-hidden="true"><path d="${_escAttr.convert(icon.path)}"${jsx ? ' />' : '></path>'}</svg>';

/// 带标签的输入框外面包的那一层的类名（节点自己的类还在输入框上，逻辑照样找得到它）。
String lcFieldClass(String nodeClassId) => 'lc-field $nodeClassId-field';

/// 外面那一层要接手的样式：占多宽、怎么摆、外边距（输入框自己改成撑满这一层）。
const List<String> _fieldTakes = ['width', 'min-width', 'max-width', 'flex-grow', 'flex-shrink', 'flex-basis', 'align-self', 'margin-top', 'margin-right', 'margin-bottom', 'margin-left'];

/// 带标签的输入框外面那一层的 CSS 规则；这个节点没有标签、或者没有要接手的样式时返回空串。
String lcFieldRule(LcNode n, LcNode? parent, String selector) {
  if (lcInputLabel(n) == null) return '';
  final s = resolvedStyle(n, parent);
  final body = [
    for (final k in _fieldTakes)
      if (s[k] != null) '$k: ${s[k]};',
  ].join(' ');
  return body.isEmpty || RegExp(r'[{}<>\n\r\\]|\*/|/\*').hasMatch(body) ? '' : '$selector-field { $body }';
}

/// 这棵树用到了哪些新属性，就补哪几条公共 CSS；一个都没用到返回空串。
String lcV3ExtraCss(LcNode root) {
  var icon = false, disabled = false, field = false, required = false, boxOff = false;
  void walk(LcNode n, int depth) {
    if (depth > LcNode.maxDepth * 4) return;
    icon = icon || lcButtonIcon(n) != null;
    disabled = disabled || lcIsDisabled(n);
    boxOff = boxOff || lcBoxGuarded(n);
    field = field || lcInputLabel(n) != null;
    required = required || (lcInputLabel(n) != null && lcInputRequired(n));
    for (final c in n.children) {
      walk(c, depth + 1);
    }
  }

  walk(root, 0);
  final out = StringBuffer();
  if (icon) {
    out
      ..writeln('.lc-icon { width: 1.25em; height: 1.25em; fill: currentColor; vertical-align: -0.25em; margin-right: 6px; }')
      ..writeln('.lc-icon-solo { margin-right: 0; }');
  }
  if (disabled) out.writeln('.lc-button:disabled, .lc-input:disabled { opacity: .5; cursor: not-allowed; }');
  if (boxOff) out.writeln(kLcBoxOffCss);
  if (field) {
    out
      ..writeln('.lc-field { display: flex; flex-direction: column; gap: 6px; min-width: 0; }')
      ..writeln('.lc-field > .lc-input { width: 100%; margin: 0; flex: none; align-self: stretch; }')
      ..writeln('.lc-label { font-size: 14px; line-height: 1.4; color: #5c6479; }');
  }
  if (required) out.writeln('.lc-required { color: #c62828; }');
  // 第 3 版的 11 个新组件：用到哪个写哪个（export_web_v3_css.dart）。
  out.write(lcV3ComponentsCss(root));
  return out.toString();
}
