/// 第 3 版 11 个新组件在网页类导出里的公共 CSS（网页、Vue、React 共用一份）。
///
/// 规矩：
/// - **用到哪个组件才写哪个组件的规则**；一个新组件都没用到的页面一个字节都不多（导出基准守着）。
/// - 规则一律包在 `:where()` 里，优先级是 0：每个节点自己的那条规则（`.n-xxx { … }`）不管写在前面还是后面都能盖过它。
///   （`:where()` 2021 年起各主流浏览器都支持，核对情况见 docs/api-notes.md。）
/// - 颜色是导出的网页里的默认色，和旧组件的基础样式同一套（#b1c0c8 边线、#5c6479 次要字、#058654 强调色）。
library;

import 'package:lopicode/lowcode/bind_model.dart';
import 'package:lopicode/lowcode/css_codec.dart';
import 'package:lopicode/lowcode/export_web_v3.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/model_v3_components.dart';
import 'package:lopicode/lowcode/states.dart';
import 'package:lopicode/lowcode/style_resolve.dart';

const Map<String, List<String>> _rules = {
  'icon': [':where(.lc-glyph) { display: inline-flex; flex: none; fill: currentColor; line-height: 0; }'],
  'textarea': [
    ':where(.lc-textarea) { border: 1px solid #b1c0c8; font: inherit; padding: 10px 12px; min-width: 0; resize: vertical; }',
    ':where(.lc-textarea[data-autogrow]) { field-sizing: content; resize: none; }',
    ':where(.lc-textarea:disabled) { opacity: .5; cursor: not-allowed; }',
    '.lc-field > .lc-textarea { width: 100%; margin: 0; flex: none; align-self: stretch; }',
  ],
  'switch': [
    ':where(.lc-switch) { appearance: none; -webkit-appearance: none; flex: none; position: relative; width: 44px; height: 26px; margin: 0; border-radius: 13px; background: #b1c0c8; cursor: pointer; transition: background .15s; }',
    ':where(.lc-switch)::after { content: ""; position: absolute; top: 3px; left: 3px; width: 20px; height: 20px; border-radius: 50%; background: #fff; transition: transform .15s; }',
    ':where(.lc-switch:checked) { background: #058654; }',
    ':where(.lc-switch:checked)::after { transform: translateX(18px); }',
    ':where(.lc-switch:disabled) { opacity: .5; cursor: not-allowed; }',
  ],
  'slider': [':where(.lc-slider) { flex: none; height: 28px; margin: 0; min-width: 0; accent-color: #058654; cursor: pointer; }', ':where(.lc-slider:disabled) { opacity: .5; cursor: not-allowed; }'],
  'checkbox': [
    ':where(.lc-checkbox) { display: inline-flex; align-items: center; gap: 8px; cursor: pointer; }',
    ':where(.lc-checkbox > input) { flex: none; width: 18px; height: 18px; margin: 0; accent-color: #058654; }',
    ':where(.lc-checkbox:has(input:disabled)) { opacity: .5; cursor: not-allowed; }',
  ],
  'radio': [
    ':where(.lc-radio) { display: flex; flex-direction: column; gap: 8px; }',
    ':where(.lc-radio[data-direction="row"]) { flex-direction: row; flex-wrap: wrap; gap: 16px; }',
    ':where(.lc-radio-item) { display: inline-flex; align-items: center; gap: 8px; cursor: pointer; }',
    ':where(.lc-radio-item > input) { flex: none; width: 18px; height: 18px; margin: 0; accent-color: #058654; }',
    ':where(.lc-radio-item:has(input:disabled)) { opacity: .5; cursor: not-allowed; }',
    ':where(.lc-radio[data-variant="button"]) { flex-direction: row; flex-wrap: nowrap; gap: 0; }',
    ':where(.lc-radio[data-variant="button"] > .lc-radio-item) { justify-content: center; padding: 6px 14px; border: 1px solid #b1c0c8; margin-left: -1px; }',
    ':where(.lc-radio[data-variant="button"] > .lc-radio-item:first-child) { margin-left: 0; border-radius: 8px 0 0 8px; }',
    ':where(.lc-radio[data-variant="button"] > .lc-radio-item:last-child) { border-radius: 0 8px 8px 0; }',
    ':where(.lc-radio[data-variant="button"] > .lc-radio-item > input) { position: absolute; width: 0; height: 0; opacity: 0; }',
    ':where(.lc-radio[data-variant="button"] > .lc-radio-item:has(input:checked)) { background: #058654; border-color: #058654; color: #fff; }',
  ],
  'select': [
    ':where(.lc-select) { border: 1px solid #b1c0c8; font: inherit; color: inherit; padding: 10px 12px; min-width: 0; background: #fff; }',
    ':where(.lc-select:disabled) { opacity: .5; cursor: not-allowed; }',
  ],
  'listItem': [
    ':where(.lc-listItem) { display: flex; flex-direction: row; align-items: center; gap: 12px; min-height: 48px; padding: 10px 16px; }',
    ':where(.lc-item-main) { flex: 1; min-width: 0; display: flex; flex-direction: column; }',
    ':where(.lc-item-title) { line-height: 1.5; }',
    ':where(.lc-item-sub) { font-size: 13px; line-height: 1.4; color: #5c6479; }',
    ':where(.lc-item-trailing) { flex: none; font-size: 14px; color: #5c6479; }',
    ':where(.lc-item-chevron) { flex: none; width: 20px; height: 20px; fill: #8b93a7; }',
  ],
  'appBar': [
    ':where(.lc-appBar) { position: relative; display: flex; flex-direction: row; align-items: center; gap: 8px; min-height: 56px; padding: 0 8px 0 16px; }',
    ':where(.lc-appBar[data-sticky]) { position: sticky; top: 0; z-index: 10; }',
    ':where(.lc-bar-title) { flex: 1; min-width: 0; margin: 0; font-size: 18px; font-weight: 600; line-height: 1.4; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }',
    ':where(.lc-appBar[data-variant="center"] > .lc-bar-title) { position: absolute; left: 72px; right: 72px; text-align: center; }',
    ':where(.lc-appBar[data-variant="center"] > .lc-slot-right) { margin-left: auto; }',
    ':where(.lc-bar-back) { flex: none; display: inline-flex; border: 0; background: none; color: inherit; padding: 8px; margin-left: -8px; cursor: pointer; }',
    ':where(.lc-bar-back > svg) { width: 24px; height: 24px; fill: currentColor; }',
  ],
  'bottomNav': [
    ':where(.lc-bottomNav) { display: flex; flex-direction: row; align-items: stretch; min-height: 56px; border-top: 1px solid #d3dee4; }',
    ':where(.lc-bottomNav[data-page]) { position: sticky; bottom: 0; z-index: 10; margin-top: auto; }',
    ':where(.lc-nav-item) { flex: 1; min-width: 0; display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 2px; border: 0; background: none; font: inherit; font-size: 12px; color: #5c6479; padding: 6px 0; cursor: pointer; }',
    ':where(.lc-nav-item[aria-current="page"]) { color: inherit; }',
    ':where(.lc-nav-item > svg) { width: 24px; height: 24px; fill: currentColor; }',
  ],
  'tabs': [
    ':where(.lc-tabs) { display: flex; flex-direction: column; }',
    ':where(.lc-tabs-bar) { display: flex; flex-direction: row; border-bottom: 1px solid #d3dee4; overflow-x: auto; }',
    ':where(.lc-tabs-bar > button) { flex: 1; border: 0; border-bottom: 2px solid transparent; margin-bottom: -1px; background: none; font: inherit; color: inherit; opacity: .6; padding: 10px 12px; white-space: nowrap; cursor: pointer; }',
    ':where(.lc-tabs-bar > button[aria-selected="true"]) { opacity: 1; font-weight: 600; border-bottom-color: currentColor; }',
    ':where(.lc-tabs[data-variant="pill"] > .lc-tabs-bar) { gap: 8px; border-bottom: 0; }',
    ':where(.lc-tabs[data-variant="pill"] > .lc-tabs-bar > button) { flex: none; border: 0; margin: 0; border-radius: 999px; padding: 6px 14px; }',
    ':where(.lc-tabs[data-variant="pill"] > .lc-tabs-bar > button[aria-selected="true"]) { background: rgba(0, 0, 0, .08); }',
    ':where(.lc-tabs-panel) { display: flex; flex-direction: column; padding-top: 12px; }',
    ':where(.lc-tabs-panel[hidden]) { display: none; }',
  ],
  'dialog': [
    ':where(.lc-dialog) { position: fixed; inset: 0; z-index: 1000; display: flex; flex-direction: column; align-items: center; justify-content: center; padding: 24px; }',
    ':where(.lc-dialog[hidden]) { display: none; }',
    ':where(.lc-dialog-scrim) { position: absolute; inset: 0; background: rgba(0, 0, 0, .45); }',
    ':where(.lc-dialog-panel) { position: relative; display: flex; flex-direction: column; gap: 12px; width: 100%; max-width: 320px; max-height: 100%; overflow: auto; padding: 20px; border-radius: 12px; background: #fff; color: #222435; box-shadow: 0 8px 32px rgba(0, 0, 0, .25); }',
    ':where(.lc-dialog-title) { margin: 0; font-size: 18px; font-weight: 600; line-height: 1.4; }',
    ':where(.lc-dialog-text) { margin: 0; line-height: 1.5; color: #5c6479; }',
    ':where(.lc-dialog-content) { display: flex; flex-direction: column; gap: 8px; }',
    ':where(.lc-dialog-footer) { display: flex; flex-direction: row; justify-content: flex-end; align-items: center; gap: 8px; }',
    ':where(.lc-dialog-btn) { border: 0; background: none; font: inherit; font-weight: 600; color: #058654; padding: 8px 12px; border-radius: 8px; cursor: pointer; }',
  ],
};

/// 轻提示（弹窗的“轻提示”样子）：贴着屏幕下方的一颗深色小胶囊，不挡点击；淡入 → 停着 → 淡出是一段动画，放完由页面收起来。
const List<String> _toastRules = [
  '.lc-dialog[data-variant="toast"] { inset: auto 0 72px 0; padding: 0 24px; pointer-events: none; animation: lc-toast 2s ease both; }',
  '.lc-dialog[data-variant="toast"][hidden] { display: none; }',
  ':where(.lc-toast-text) { margin: 0; max-width: 100%; padding: 10px 16px; border-radius: 8px; background: rgba(34, 36, 53, .92); color: #fff; font-size: 14px; line-height: 1.4; }',
  '@keyframes lc-toast { 0% { opacity: 0; transform: translateY(8px); } 12% { opacity: 1; transform: none; } 85% { opacity: 1; } 100% { opacity: 0; } }',
];

/// 插槽那一层（列表行、顶部导航栏用）。
const String _slotRule = ':where(.lc-slot) { flex: none; display: flex; flex-direction: row; align-items: center; gap: 8px; }';

final RegExp _px = RegExp(r'^(\d+(\.\d+)?)px$');

/// 页面级的栏要往外伸多少（把页面的内边距抵掉）：`-12px`；内边距是 0 或者不是 px 写的返回 null（不伸）。
String? _neg(Map<String, String> pageStyle, String side) {
  final m = _px.firstMatch(pageStyle['padding-$side'] ?? '');
  return m == null || double.parse(m.group(1)!) == 0 ? null : '-${m.group(1)}px';
}

/// 这个节点在 Vue 页面里已经写成“引用公共部件”了（export_shared_parts.dart 记的）：页面样式里不用再带它那一类的通用规则。
final Expando<bool> lcPartExtracted = Expando<bool>('lcPartExtracted');

/// 这棵树用到了哪些新组件，就写哪些的公共 CSS；一个都没用到返回空串。[root] 是页面时顺带写“页面级的栏”贴边的规则。
String lcV3ComponentsCss(LcNode root) {
  final used = <String>{};
  final toastSeconds = <int>{};
  void walk(LcNode n, int depth) {
    if (depth > LcNode.maxDepth * 4) return;
    // Vue 页面里已经写成“引用公共部件”的导航：它那一类的通用规则在部件文件里，页面这份用不上（样式只在本文件生效）。
    if (lcWebV3Types.contains(n.type) && !(depth > 0 && lcPartExtracted[n] == true)) used.add(n.type);
    if (lcIsToast(n)) toastSeconds.add(lcToastSeconds(n));
    for (final c in n.children) {
      walk(c, depth + 1);
    }
  }

  walk(root, 0);
  if (used.isEmpty) return '';
  final out = StringBuffer();
  // 旧组件的 box-sizing 在基础样式里点了名；新组件在这儿补（连同它们里面自带的小元素）。
  final classes = [
    for (final t in _rules.keys)
      if (used.contains(t)) '.${lcTypeClass(t)}',
  ];
  out.writeln(':where(${classes.join(', ')}, ${classes.map((c) => '$c *').join(', ')}) { box-sizing: border-box; }');
  for (final type in _rules.keys) {
    if (!used.contains(type)) continue;
    _rules[type]!.forEach(out.writeln);
  }
  if (used.contains('listItem') || used.contains('appBar')) out.writeln(_slotRule);
  // 轻提示：页面里有才写（没有的页面一个字不多）。
  if (toastSeconds.isNotEmpty) {
    _toastRules.forEach(out.writeln);
    for (final sec in toastSeconds.toList()..sort()) {
      if (sec != 2) out.writeln('.lc-dialog[data-variant="toast"][data-seconds="$sec"] { animation-duration: ${sec}s; }');
    }
  }
  if (root.type == 'page') {
    final page = resolvedStyle(root, null);
    final id = RegExp(r'^[A-Za-z0-9_]+$');
    for (final c in root.children) {
      if (!lcIsPageBar(root, c) || !id.hasMatch(c.id)) continue;
      final l = _neg(page, 'left'), r = _neg(page, 'right');
      final edge = _neg(page, c.type == 'appBar' ? 'top' : 'bottom');
      final body = [if (l != null) 'margin-left: $l;', if (r != null) 'margin-right: $r;', if (edge != null) 'margin-${c.type == 'appBar' ? 'top' : 'bottom'}: $edge;'];
      if (body.isNotEmpty) out.writeln('.n-${c.id} { ${body.join(' ')} }');
    }
  }
  return out.toString();
}

/// 状态样式（节点的 `states`）的 CSS 规则，一种状态一条；没有返回空表。读法见 states.dart。
List<String> lcStateRules(LcNode n, String selector) {
  final out = <String>[];
  for (final state in kLcStateNames) {
    final decl = lcStateStyle(n, state);
    if (decl.isEmpty) continue;
    final body = declarationsToCss(canonicalDeclarations(decl), multiline: false);
    if (body.isEmpty || RegExp(r'[{}<>\n\r\\]|\*/|/\*').hasMatch(body)) continue;
    out.add('$selector${kLcStatePseudo[state]} { $body }');
  }
  // 类名开关配的样子：`.控件.类名 { … }`（没配的不写）。
  for (final c in lcClassIfOf(n)) {
    if (c.style.isEmpty) continue;
    final body = declarationsToCss(canonicalDeclarations(c.style), multiline: false);
    if (body.isEmpty || RegExp(r'[{}<>\n\r\\]|\*/|/\*').hasMatch(body)) continue;
    out.add('$selector.${c.name} { $body }');
  }
  return out;
}
