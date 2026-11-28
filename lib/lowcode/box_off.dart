/// 容器的“禁用”和“说明文字”（第四轮 B7）。
///
/// 只有“容器”这一种有（行、列、卡片没有）：做“整块能点的东西”（图标按钮这类封装出来的组件最外层就是容器）时用。
/// - **禁用**（`props.disabled`，能绑到“是 / 否”的状态上）：画布上变淡；三种网页里元素带 `aria-disabled="true"`、变淡、
///   点它和它里面的东西都不往下传（接在它身上的点击不会发生）；Flutter 里变淡、不接点击。
/// - **说明文字**（`props.alt`，和图片的说明文字同一个名字，能绑到文字状态上）：给读屏用的那句话。网页里是
///   `aria-label` 加 `title`（鼠标停上去也看得到）；Flutter 里是 `Tooltip`（长按看得到，读屏也读它）。
///
/// 没设这两样的容器，四种导出一个字节都不多。
library;

import 'package:lopicode/lowcode/bind_model.dart';
import 'package:lopicode/lowcode/model.dart';

const Set<String> kLcBoxOffTypes = {'container'};

bool lcBoxCanOff(LcNode n) => kLcBoxOffTypes.contains(n.type);

/// 写死的“禁用”。
bool lcBoxOff(LcNode n) => lcBoxCanOff(n) && n.props['disabled'] == true;

/// 禁用是写死的、或者绑了状态：这个容器要带“禁用着就不接点击”的那一道。
bool lcBoxGuarded(LcNode n) => lcBoxCanOff(n) && (n.props['disabled'] == true || lcDataExpr(n, 'disabled') != null);

/// 写死的说明文字（空的当没有）。
String? lcBoxLabel(LcNode n) {
  final t = lcBoxCanOff(n) ? n.strProp('alt') : null;
  return t == null || t.isEmpty ? null : t;
}

/// 这棵树里有没有要带那一道的容器。
bool lcTreeHasBoxGuard(LcNode root) {
  var found = false;
  void walk(LcNode n, int depth) {
    if (found || depth > LcNode.maxDepth * 4) return;
    found = lcBoxGuarded(n);
    for (final c in n.children) {
      walk(c, depth + 1);
    }
  }

  walk(root, 0);
  return found;
}

/// 公共样式：禁用着的容器变淡、鼠标点不到。
const String kLcBoxOffCss = '.lc-container[aria-disabled="true"] { opacity: .5; pointer-events: none; }';

/// 普通网页：接在 logic.js 末尾的一小段。抢在所有处理前面看一眼——点的地方在禁用着的容器里，就不往下传。
/// （样式里已经让鼠标点不到它；这一段管的是键盘、读屏、脚本触发的点击。）
const String kLcBoxOffGuardJs = '''
// 禁用着的容器（aria-disabled="true"）：点它和它里面的东西都不算数。
document.addEventListener("click", (event) => {
  const t = event.target;
  if (t && t.closest && t.closest('[aria-disabled="true"]')) {
    event.stopPropagation();
    event.preventDefault();
  }
}, true);
''';

/// Vue 模板里那一道（写在元素自己身上；先于它自己和它里面的点击处理）。
const String kLcBoxOffVueGuard = r''' @click.capture="$event.currentTarget.getAttribute('aria-disabled') === 'true' && $event.stopImmediatePropagation()"''';

/// React 里那一道。
const String kLcBoxOffReactGuard = ' onClickCapture={(event) => event.currentTarget.getAttribute("aria-disabled") === "true" && event.stopPropagation()}';

/// 普通网页里这个容器多出来的属性（没设就是空串）。[attr]：写一个属性（带前面的空格）。
String lcBoxHtmlAttrs(LcNode n, String Function(String name, String value) attr) {
  if (!lcBoxCanOff(n)) return '';
  final label = lcBoxLabel(n);
  return '${lcBoxOff(n) ? attr('aria-disabled', 'true') : ''}${label == null ? '' : '${attr('aria-label', label)}${attr('title', label)}'}';
}

/// Vue 模板里这个容器多出来的属性。[off] / [label]：绑了状态时的式子（没绑是 null）。
String lcBoxVueAttrs(LcNode n, {String? off, String? label, required String Function(String name, String value) attr}) {
  if (!lcBoxCanOff(n)) return '';
  final text = lcBoxLabel(n);
  final a = off != null ? ' :aria-disabled="$off"' : (lcBoxOff(n) ? ' aria-disabled="true"' : '');
  final b = label != null ? ' :aria-label="($label) || undefined" :title="($label) || undefined"' : (text == null ? '' : '${attr('aria-label', text)}${attr('title', text)}');
  return '$a$b${off != null || lcBoxOff(n) ? kLcBoxOffVueGuard : ''}';
}

/// React 里这个容器多出来的属性。
String lcBoxReactAttrs(LcNode n, {String? off, String? label, required String Function(String name, String value) attr}) {
  if (!lcBoxCanOff(n)) return '';
  final text = lcBoxLabel(n);
  final a = off != null ? ' aria-disabled={$off}' : (lcBoxOff(n) ? ' aria-disabled="true"' : '');
  final b = label != null ? ' aria-label={($label) || undefined} title={($label) || undefined}' : (text == null ? '' : '${attr('aria-label', text)}${attr('title', text)}');
  return '$a$b${off != null || lcBoxOff(n) ? kLcBoxOffReactGuard : ''}';
}

/// 展开实例以后：容器的禁用 / 说明文字要是“绑”在一个写死的值上（实例没把这个属性接到状态上），折成普通属性——
/// 这样没开禁用、没写说明文字的实例，导出里一个字都不多。
void lcBoxFoldLiterals(LcNode root, [int depth = 0]) {
  if (depth > LcNode.maxDepth * 4) return;
  if (lcBoxCanOff(root)) {
    final off = lcDataExpr(root, 'disabled'), label = lcDataExpr(root, 'alt');
    if (off != null && off['e'] == 'bool' && off['v'] is bool) {
      off['v'] == true ? root.props['disabled'] = true : root.props.remove('disabled');
      lcSetData(root, 'disabled', null);
    }
    if (label != null && label['e'] == 'text' && label['v'] is String) {
      (label['v'] as String).isEmpty ? root.props.remove('alt') : root.props['alt'] = label['v'];
      lcSetData(root, 'alt', null);
    }
  }
  for (final c in root.children) {
    lcBoxFoldLiterals(c, depth + 1);
  }
}
