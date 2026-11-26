// 设计约束：这里没有界面，只有“CSS 声明 → Flutter 的文字样式 / 圆角 / 边框 / 阴影”的换算，画布上各种组件的画法共用。
// 画不了的写法一律当没写，绝不报错。
import 'package:lopicode/lowcode/canvas_css.dart';
import 'package:lopicode/lowcode/canvas_parts_widgets.dart';
import 'package:lopicode/lowcode/css_color.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:material_ui/material_ui.dart';

Color? canvasArgb(String? css) {
  final v = cssColorToArgb(css);
  return v == null ? null : Color(v);
}

TextStyle? canvasTextStyle(Map<String, String> s, CssScale scale, {double? defaultHeight}) {
  final weight = cssFontWeight(s['font-weight']);
  final italic = s['font-style']?.trim().toLowerCase();
  final lines = cssDecorationLines(s);
  final none = (s['text-decoration-line'] ?? s['text-decoration'] ?? '').trim().toLowerCase() == 'none';
  final style = TextStyle(
    color: canvasArgb(s['color']),
    // 字号在外面已经换算好放进 scale 了（em 是相对父级的，这里不能再算一遍）
    fontSize: s.containsKey('font-size') ? scale.fontSize : null,
    fontWeight: weight == null ? null : FontWeight.values[(weight ~/ 100) - 1],
    fontStyle: italic == 'italic' || italic == 'oblique' ? FontStyle.italic : (italic == 'normal' ? FontStyle.normal : null),
    height: cssLineHeight(s['line-height'], scale) ?? defaultHeight,
    letterSpacing: cssPx(s['letter-spacing'], scale),
    decoration: lines.isNotEmpty
        ? TextDecoration.combine([
            if (lines.contains('underline')) TextDecoration.underline,
            if (lines.contains('line-through')) TextDecoration.lineThrough,
            if (lines.contains('overline')) TextDecoration.overline,
          ])
        : (none ? TextDecoration.none : null),
  );
  return style == const TextStyle() ? null : style;
}

TextAlign? canvasTextAlign(Map<String, String> s) => switch (s['text-align']?.trim().toLowerCase()) {
  'center' => TextAlign.center,
  'right' || 'end' => TextAlign.right,
  'left' || 'start' => TextAlign.left,
  'justify' => TextAlign.justify,
  _ => null,
};

BorderRadius? canvasRadius(Map<String, String> s, CssScale scale) {
  final r = cssRadii(s, scale);
  if (r.every((v) => v == 0)) return null;
  return BorderRadius.only(topLeft: Radius.circular(r[0]), topRight: Radius.circular(r[1]), bottomRight: Radius.circular(r[2]), bottomLeft: Radius.circular(r[3]));
}

/// [rounded]：盒子有圆角。有圆角时四边必须同色（界面库的限制），这时统一用第一条边的颜色。
Border? canvasBorder(Map<String, String> s, CssScale scale, Color textColor, bool rounded) {
  final sides = [
    for (final side in const ['top', 'right', 'bottom', 'left']) cssBorderSide(s, side, scale),
  ];
  if (sides.every((b) => b == null)) return null;
  final first = sides.firstWhere((b) => b != null)!;
  BorderSide of(CssBorderSide? b) {
    if (b == null) return BorderSide.none;
    final argb = rounded ? first.argb : b.argb;
    return BorderSide(width: b.width, color: argb == null ? textColor : Color(argb));
  }

  return Border(top: of(sides[0]), right: of(sides[1]), bottom: of(sides[2]), left: of(sides[3]));
}

List<BoxShadow>? canvasShadow(LcNode n, Map<String, String> s, CssScale scale, Color textColor) {
  if (!s.containsKey('box-shadow')) {
    // 卡片自带一层浅阴影（和导出的网页一样）。
    return n.type == 'card' ? const [BoxShadow(color: Color(0x33000000), blurRadius: 3, offset: Offset(0, 1))] : null;
  }
  final sh = cssShadow(s, scale);
  if (sh == null) return null;
  return [BoxShadow(color: sh.argb == null ? textColor : Color(sh.argb!), offset: Offset(sh.x, sh.y), blurRadius: sh.blur, spreadRadius: sh.spread)];
}

/// 画布上临时换了样式的那份节点：拖柄拖动中的临时尺寸（[resize]）、或者“看某个状态”时把状态样式并进来（[state]）。
/// 都没有就是 [shown] 本身（同一个对象：调用方靠这个判断能不能用记着的样式）。
LcNode canvasPreviewNode(LcNode shown, {(int?, int?)? resize, Map<String, String> state = const {}}) {
  if (resize == null && state.isEmpty) return shown;
  final (w, h) = resize ?? (null, null);
  return LcNode(
    id: shown.id,
    type: shown.type,
    props: shown.props,
    children: shown.children,
    raw: shown.raw,
    more: shown.more,
    style: {...shown.style, if (resize == null) ...state, if (w != null) 'width': '${w}px', if (h != null) 'height': '${h}px'},
  );
}

/// 列表组件：一项一行，前面一个圆点。
Widget canvasBullets(LcNode n, Map<String, String> s, CssScale scale) {
  final style = canvasTextStyle(s, scale, defaultHeight: 1.75);
  final items = n.props['items'];
  return QuietFlex(
    direction: Axis.vertical,
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      if (items is List)
        for (final item in items) Text('• $item', style: style, textAlign: canvasTextAlign(s)),
    ],
  );
}
