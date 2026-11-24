/// 一个节点的“最终样式”：第 1 版的简写属性翻出来的 CSS 声明，被节点自己的 `style` 盖掉之后的结果。
/// 画布、HTML / Vue / React 导出都用这里的函数，保证几处看到的样式是同一份。
library;

import 'package:lopicode/lowcode/css_codec.dart';
import 'package:lopicode/lowcode/model.dart';

String _n(num v) => v == v.roundToDouble() ? '${v.round()}' : '$v';

const Map<String, String> _alignItems = {'start': 'flex-start', 'center': 'center', 'end': 'flex-end', 'stretch': 'stretch'};
const Map<String, String> _justifyContent = {'start': 'flex-start', 'center': 'center', 'end': 'flex-end', 'between': 'space-between'};

/// 这个节点是不是靠简写属性“撑满”的：`width: "fill"`，或者是行里没给固定宽度的容器类组件
/// （行里的容器平分剩余空间，和导出的 Flutter 代码规则一致）。
bool _fills(LcNode n, LcNode? parent) {
  final width = n.props['width'];
  return width == 'fill' || (parent?.type == 'row' && n.isContainer && width is! num);
}

/// 第 1 版的简写属性（width / height / padding / margin / bg / color / radius / fontSize / bold / textAlign /
/// gap / align / justify，间隔的 size）翻成规范写法的声明表。[parent] 是父节点（根节点传 null），
/// 因为“撑满”和间隔在行里、列里的写法不一样。
///
/// 语义和第 1 版 HTML 导出逐条相同，只是写成拆开的单项：
/// `flex: 1` ＝ `flex-grow: 1; flex-shrink: 1; flex-basis: 0%`，`padding: 8px` ＝ 四条 `padding-*`，
/// `background: #fff` ＝ `background-color: #fff`。
Map<String, String> legacyStyle(LcNode n, LcNode? parent) {
  final inRow = parent?.type == 'row';
  final r = <String, String>{};
  void all(String shorthand, String value) {
    for (final name in cssLonghands(shorthand)) {
      r[name] = value;
    }
  }

  if (n.type == 'spacer') {
    final size = '${_n(n.numProp('size') ?? 16)}px';
    r['flex-grow'] = '0';
    r['flex-shrink'] = '0';
    r['flex-basis'] = size;
    r[inRow ? 'width' : 'height'] = size;
    return r;
  }
  final width = n.props['width'];
  if (_fills(n, parent)) {
    if (inRow) {
      r['flex-grow'] = '1';
      r['flex-shrink'] = '1';
      r['flex-basis'] = '0%';
      r['min-width'] = '0';
    } else {
      r['align-self'] = 'stretch';
    }
  } else if (width is num) {
    r['width'] = '${_n(width)}px';
  }
  final height = n.numProp('height');
  if (height != null) r['height'] = '${_n(height)}px';
  final padding = n.numProp('padding');
  if (padding != null) all('padding', '${_n(padding)}px');
  final margin = n.numProp('margin');
  if (margin != null) all('margin', '${_n(margin)}px');
  final bg = n.strProp('bg');
  if (bg != null) r['background-color'] = bg.toLowerCase();
  final color = n.strProp('color');
  if (color != null) r['color'] = color.toLowerCase();
  final radius = n.numProp('radius');
  if (radius != null) all('border-radius', '${_n(radius)}px');
  final fontSize = n.numProp('fontSize');
  if (fontSize != null) r['font-size'] = '${_n(fontSize)}px';
  if (n.props['bold'] == true) r['font-weight'] = '600';
  final textAlign = n.strProp('textAlign');
  if (textAlign != null) r['text-align'] = textAlign;
  if (n.isContainer) {
    final gap = n.numProp('gap');
    if (gap != null) all('gap', '${_n(gap)}px');
    final a = _alignItems[n.strProp('align')];
    if (a != null) r['align-items'] = a;
    final j = _justifyContent[n.strProp('justify')];
    if (j != null) r['justify-content'] = j;
  }
  return r;
}

/// 最终样式：[legacyStyle] 被 `n.style` 盖掉后的结果（规范写法）。
///
/// 盖的规矩：
/// 1. 同名的条目，`style` 里的赢。`style` 里要是有没拆开的简写（Agent 或手改文件写进来的 `border: 1px solid red`），
///    先按规范写法拆开再盖；拆不了的简写（`margin: var(--m)`）会把它管的单项一并盖掉。
/// 2. **`style` 里写了 `width` 或 `flex` / `flex-basis`，就不再“撑满”**：简写属性翻出来的
///    `flex: 1; min-width: 0`（在行里）或 `align-self: stretch`（在列里）整组去掉，
///    只留 `style` 自己写了的那几条。不去掉的话，行里 `flex-basis: 0%` 会压过 `width`，用户设的宽度不生效。
/// 3. 间隔（spacer）同理：它靠 `flex: 0 0 Npx` 定大小，`style` 里写了主轴方向的尺寸
///    （行里是 `width`，否则是 `height`）时，`flex-basis` 改成 `auto`，让写的尺寸生效（照样不放大不缩小）。
Map<String, String> resolvedStyle(LcNode n, LcNode? parent) {
  final legacy = legacyStyle(n, parent);
  if (n.style.isEmpty) return legacy;
  final own = canonicalDeclarations(n.style);
  final inRow = parent?.type == 'row';
  if (n.type == 'spacer') {
    if (own.containsKey(inRow ? 'width' : 'height')) legacy['flex-basis'] = 'auto';
  } else if (_fills(n, parent) && (own.containsKey('width') || own.containsKey('flex') || own.containsKey('flex-basis'))) {
    for (final name in const ['flex-grow', 'flex-shrink', 'flex-basis', 'min-width', 'align-self']) {
      legacy.remove(name);
    }
  }
  return mergeDeclarations(legacy, own);
}

/// 节点最终样式的 CSS 声明，写在一行里（`a: b; c: d;`），简写已合并。没有任何声明时返回空串。
String nodeCssDeclarations(LcNode n, LcNode? parent) => declarationsToCss(resolvedStyle(n, parent), multiline: false);

/// 节点的 CSS 选择器：`.n-节点id`（HTML 导出给每个节点的 class）。
String nodeCssSelector(LcNode n) => '.n-${n.id}';

/// 节点的一整条 CSS 规则：`.n-b1 { padding: 12px; color: #fff; }`。没有任何声明时返回空串（不要输出空规则）。
/// [selector] 不给就用 [nodeCssSelector]；Vue / React 导出想用别的类名时自己传。
String nodeCssRule(LcNode n, LcNode? parent, {String? selector}) {
  final body = nodeCssDeclarations(n, parent);
  return body.isEmpty ? '' : '${selector ?? nodeCssSelector(n)} { $body }';
}
