// 设计约束（低代码 · 画布里的“页面” · 390×844）
// - 每个组件按它的“最终样式”（resolvedStyle：简写属性 + 自己的 style）画，画不了的样式忽略，绝不报错。
// - 没有 style 的旧页面，画出来和第 1 版一模一样（默认对齐、间距、按钮 / 输入框的样子都不变）。
// - 页面内容用固定的浅色主题：它是“用户页面”的样子，不跟随应用的深色模式。
// - 组件本身不响应点击（按钮、输入框只是样子）：点＝选中，长按 280 毫秒＝拿起来拖（手势在 lift_gesture_widgets.dart）。
// - 拖动时这里什么都不变（不插占位、不撑开）；落点的蓝线由画布叠在上面画。正在拖的那个组件只是变淡。
// - 每个组件的最终样式一次重搭里只算一遍（_Ctx.styles 记着），父容器数“要放大的子项”和画子项用的是同一份。
import 'dart:math' as math;

import 'package:lopicode/lowcode/canvas_component_widgets.dart';
import 'package:lopicode/lowcode/canvas_css.dart';
import 'package:lopicode/lowcode/canvas_parts_widgets.dart';
import 'package:lopicode/lowcode/component_ops.dart';
import 'package:lopicode/lowcode/css_color.dart';
import 'package:lopicode/lowcode/lift_gesture_widgets.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/palette_widgets.dart';
import 'package:lopicode/lowcode/style_resolve.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// 拖柄拖动中的临时尺寸：只影响画布怎么画，不动页面数据（松手才真的写进去）。
class CanvasResizePreview {
  const CanvasResizePreview(this.nodeId, this.width, this.height);
  final String nodeId;
  final int? width;
  final int? height;
}

/// 画一个子组件时，从父容器那里知道的事。
class _Ctx {
  const _Ctx({
    required this.parent,
    required this.flow,
    required this.boundedW,
    required this.boundedH,
    required this.availW,
    required this.availH,
    required this.scale,
    required this.growCount,
    required this.textColor,
    required this.buttonText,
    required this.styles,
  });
  final LcNode parent;
  final CssFlow flow;

  /// 父容器给的宽 / 高是不是有上限。没有上限时不能“撑满”，不然排版会报错。
  final bool boundedW;
  final bool boundedH;

  /// 父容器内容区的宽高（估的），百分比尺寸参照它；高度不知道是 null。
  final double availW;
  final double? availH;
  final CssScale scale;

  /// 父容器里有几个子项要“放大占满”，用来估每个能分到多宽。
  final int growCount;

  /// 继承下来的文字颜色（边框、阴影没写颜色时用它，CSS 的 currentcolor）。
  final Color textColor;

  /// 设了字号的按钮，文字的基础样式沿用应用主题里的（第 1 版就是这样，换掉的话旧页面的按钮会变样）。
  final TextStyle? buttonText;

  /// 这一次重搭里已经算过的最终样式（按组件对象记）：同一个组件不算第二遍。
  final Map<LcNode, Map<String, String>> styles;

  Map<String, String> styleOf(LcNode n, LcNode? parent) => styles[n] ??= resolvedStyle(n, parent);
}

Color? _argb(String? css) {
  final v = cssColorToArgb(css);
  return v == null ? null : Color(v);
}

bool _has(Map<String, String> s, String prefix) => s.keys.any((k) => k.startsWith(prefix));

bool _hasRadius(Map<String, String> s) => s.keys.any((k) => k.startsWith('border-') && k.endsWith('-radius'));

/// 画布里的那块“页面”。
class CanvasPage extends StatelessWidget {
  const CanvasPage({
    super.key,
    required this.doc,
    required this.pageWidth,
    required this.minHeight,
    required this.selected,
    required this.onSelect,
    required this.boxKey,
    this.movingId,
    this.onLift,
    this.onLiftMove,
    this.onLiftDrop,
    this.onLiftCancel,
    this.preview,
    this.inert = false,
  });

  /// 只画样子的页面（拖动时手指下面的缩略图、测试）：不能点、不能拖。
  const CanvasPage.still({super.key, required this.doc, required this.pageWidth, this.minHeight = 0})
    : selected = null,
      movingId = null,
      onSelect = _ignoreSelect,
      onLift = null,
      onLiftMove = null,
      onLiftDrop = null,
      onLiftCancel = null,
      boxKey = _stillKeys,
      preview = null,
      inert = true;

  static void _ignoreSelect(String _) {}

  // 只画样子的页面不需要量位置：每个组件给一把用完就丢的 key。
  static GlobalKey _stillKeys(String _) => GlobalKey();

  /// 一共重搭了几次（测试用：平移 / 缩放时不该涨）。
  @visibleForTesting
  static int debugBuilds = 0;

  final LcDocument doc;
  final double pageWidth;

  /// 页面至少这么高，背景不会只盖到内容那么高。
  final double minHeight;
  final String? selected;

  /// 正在被拖着挪的那个组件：留在原地、变淡。
  final String? movingId;
  final void Function(String id) onSelect;

  /// 长按一个组件拿起来了 / 手指在动 / 松手 / 被打断（位置是屏幕坐标）。
  final void Function(LcDrag drag, Offset global)? onLift;
  final void Function(Offset global)? onLiftMove;
  final VoidCallback? onLiftDrop;
  final VoidCallback? onLiftCancel;

  /// 每个组件“边框盒”的定位用的 key（选中框、拖柄靠它量位置）。
  final GlobalKey Function(String id) boxKey;
  final CanvasResizePreview? preview;

  /// true＝只画样子：不能点、不能拖、没有插入位。自定义组件实例里面的内容用它画（整块只能当一个东西选中）。
  final bool inert;

  CanvasPage _inertCopy() => CanvasPage(doc: doc, pageWidth: pageWidth, minHeight: minHeight, selected: null, onSelect: (_) {}, boxKey: boxKey, inert: true);

  @override
  Widget build(BuildContext context) {
    debugBuilds++;
    final root = doc.root;
    final s = resolvedStyle(root, null);
    final base = CssScale(pageWidth: pageWidth, pageHeight: minHeight);
    final scale = base.withFont(cssSizePx(s['font-size'], base) ?? 16);
    final border = cssBorderWidths(s, scale);
    final padding = cssEdges(s, 'padding', scale, percentOf: pageWidth) + border;
    final font = Theme.of(context).textTheme.bodyMedium?.fontFamily;
    final ctx = _Ctx(
      parent: root,
      flow: cssFlow(s, rowByDefault: false),
      boundedW: true,
      boundedH: false,
      availW: math.max(0, pageWidth - padding.horizontal),
      availH: null,
      scale: scale,
      growCount: 0,
      textColor: _argb(s['color']) ?? Palette.neutral900,
      buttonText: Theme.of(context).textTheme.labelLarge,
      styles: Map.identity(),
    );
    final page = Container(
      key: boxKey(root.id),
      width: pageWidth,
      constraints: BoxConstraints(minHeight: minHeight),
      decoration: BoxDecoration(color: _argb(s['background-color']) ?? Colors.white, border: _border(s, scale, Palette.neutral900, false)),
      foregroundDecoration: selected == root.id ? BoxDecoration(border: Border.all(color: context.themeSpec.lowcodeColor(LowcodeKey.selection), width: 2)) : null,
      padding: EdgeInsets.fromLTRB(padding.left, padding.top, padding.right, padding.bottom),
      child: _flex(context, root, s, ctx, tightW: true, tightH: false),
    );
    return Theme(
      // 页面内容用自己的一套 Material 外观（不跟应用主题走）；只把应用主题的颜色表带进去，给选中框、插入位这些编辑器界面色用。
      data: ThemeData(useMaterial3: true, colorSchemeSeed: Palette.primary700, fontFamily: font, extensions: [AppColors.resolve(context)]),
      child: Builder(
        builder: (context) => DefaultTextStyle(
          style: TextStyle(fontSize: 16, color: Palette.neutral900, height: 1.5, fontFamily: font).merge(_textStyle(s, scale)),
          textAlign: _textAlign(s),
          // 单独一层：平移 / 缩放只挪这一层，不把几百个组件重画一遍。
          child: RepaintBoundary(
            child: inert ? page : GestureDetector(key: const ValueKey('lowcode-page'), onTap: () => onSelect(root.id), child: page),
          ),
        ),
      ),
    );
  }

  // ───────────── 文字样式 ─────────────

  static TextStyle? _textStyle(Map<String, String> s, CssScale scale, {double? defaultHeight}) {
    final weight = cssFontWeight(s['font-weight']);
    final italic = s['font-style']?.trim().toLowerCase();
    final lines = cssDecorationLines(s);
    final none = (s['text-decoration-line'] ?? s['text-decoration'] ?? '').trim().toLowerCase() == 'none';
    final style = TextStyle(
      color: _argb(s['color']),
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

  static TextAlign? _textAlign(Map<String, String> s) => switch (s['text-align']?.trim().toLowerCase()) {
    'center' => TextAlign.center,
    'right' || 'end' => TextAlign.right,
    'left' || 'start' => TextAlign.left,
    'justify' => TextAlign.justify,
    _ => null,
  };

  // ───────────── 盒子：边框、圆角、阴影 ─────────────

  static BorderRadius? _radius(Map<String, String> s, CssScale scale) {
    final r = cssRadii(s, scale);
    if (r.every((v) => v == 0)) return null;
    return BorderRadius.only(topLeft: Radius.circular(r[0]), topRight: Radius.circular(r[1]), bottomRight: Radius.circular(r[2]), bottomLeft: Radius.circular(r[3]));
  }

  /// [rounded]：盒子有圆角。有圆角时四边必须同色（界面库的限制），这时统一用第一条边的颜色。
  static Border? _border(Map<String, String> s, CssScale scale, Color textColor, bool rounded) {
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

  static List<BoxShadow>? _shadow(LcNode n, Map<String, String> s, CssScale scale, Color textColor) {
    if (!s.containsKey('box-shadow')) {
      // 卡片自带一层浅阴影（和导出的网页一样）。
      return n.type == 'card' ? const [BoxShadow(color: Color(0x33000000), blurRadius: 3, offset: Offset(0, 1))] : null;
    }
    final sh = cssShadow(s, scale);
    if (sh == null) return null;
    return [BoxShadow(color: sh.argb == null ? textColor : Color(sh.argb!), offset: Offset(sh.x, sh.y), blurRadius: sh.blur, spreadRadius: sh.spread)];
  }

  // ───────────── 容器里的子项 ─────────────

  /// 把容器的子项排出来。[tightW] / [tightH]：容器自己的宽 / 高是不是定死的（决定“拉伸”要不要先量内容）。
  Widget _flex(BuildContext context, LcNode n, Map<String, String> s, _Ctx inner, {required bool tightW, required bool tightH}) {
    final flow = inner.flow;
    final scale = inner.scale;
    final mainGap = cssSizePx(s[flow.row ? 'column-gap' : 'row-gap'], scale, percentOf: inner.availW) ?? 0;
    final crossGap = cssSizePx(s[flow.row ? 'row-gap' : 'column-gap'], scale, percentOf: inner.availW) ?? 0;
    final align = cssAlign(s['align-items']) ?? (n.type == 'row' ? CssAlign.center : CssAlign.start);
    final justify = cssJustify(s['justify-content']) ?? CssJustify.start;
    if (n.children.isEmpty) {
      return inert ? const SizedBox.shrink() : const CanvasEmptyHint();
    }
    // 子项之间的间距由容器自己留（拖动时也不往里插东西），这样“两端对齐”之类的分布才准。
    final children = [for (final c in n.children) _node(context, c, inner)];
    final spacing = mainGap;
    final textDirection = flow.row && flow.reverse ? TextDirection.rtl : null;
    final verticalDirection = !flow.row && flow.reverse ? VerticalDirection.up : VerticalDirection.down;
    if (flow.wrap) {
      return Wrap(
        direction: flow.row ? Axis.horizontal : Axis.vertical,
        spacing: spacing,
        runSpacing: crossGap,
        alignment: switch (justify) {
          CssJustify.start => WrapAlignment.start,
          CssJustify.center => WrapAlignment.center,
          CssJustify.end => WrapAlignment.end,
          CssJustify.between => WrapAlignment.spaceBetween,
          CssJustify.around => WrapAlignment.spaceAround,
          CssJustify.evenly => WrapAlignment.spaceEvenly,
        },
        crossAxisAlignment: switch (align) {
          CssAlign.center => WrapCrossAlignment.center,
          CssAlign.end => WrapCrossAlignment.end,
          _ => WrapCrossAlignment.start,
        },
        textDirection: textDirection,
        verticalDirection: verticalDirection,
        children: children,
      );
    }
    // “拉伸”要求交叉方向的尺寸是定的：行的高度通常跟着内容走，这时先量出最高的子项再拉伸；
    // 列在宽度没有上限时同理。（第 1 版这里直接拉伸，行里一选“拉伸”画布就报错。）
    final stretch = align == CssAlign.stretch;
    final measure = stretch && (flow.row ? !tightH : !inner.boundedW && !tightW);
    final flex = QuietFlex(
      direction: flow.row ? Axis.horizontal : Axis.vertical,
      mainAxisSize: flow.row ? MainAxisSize.max : MainAxisSize.min,
      crossAxisAlignment: switch (align) {
        CssAlign.start => CrossAxisAlignment.start,
        CssAlign.center => CrossAxisAlignment.center,
        CssAlign.end => CrossAxisAlignment.end,
        CssAlign.stretch => CrossAxisAlignment.stretch,
      },
      mainAxisAlignment: switch (justify) {
        CssJustify.start => MainAxisAlignment.start,
        CssJustify.center => MainAxisAlignment.center,
        CssJustify.end => MainAxisAlignment.end,
        CssJustify.between => MainAxisAlignment.spaceBetween,
        CssJustify.around => MainAxisAlignment.spaceAround,
        CssJustify.evenly => MainAxisAlignment.spaceEvenly,
      },
      textDirection: textDirection,
      verticalDirection: verticalDirection,
      spacing: spacing,
      children: children,
    );
    if (!measure) return flex;
    return flow.row ? IntrinsicHeight(child: flex) : IntrinsicWidth(child: flex);
  }

  // ───────────── 一个组件 ─────────────

  Widget _node(BuildContext context, LcNode node, _Ctx ctx) {
    final parent = ctx.parent;
    // 拖柄拖动中：把临时尺寸当成这个组件自己的样式来算，“撑满”之类的规则才会跟着让路。
    final p = preview;
    // 自定义组件的实例：按展开后的内容画（最外层沿用实例的 id，所以选中框、拖柄照常认得它）。
    // 展开不了、或者已经在别的实例里面了（inert）就不展开，下面画占位。
    final instance = node.type == 'component' && !inert;
    final shown = instance ? expandInstance(doc, node) ?? node : node;
    final n = p != null && p.nodeId == node.id
        ? LcNode(
            id: shown.id,
            type: shown.type,
            props: shown.props,
            children: shown.children,
            style: {...shown.style, if (p.width != null) 'width': '${p.width}px', if (p.height != null) 'height': '${p.height}px'},
          )
        : shown;
    // 没被改过的组件用这一轮记着的那份（父容器数“要放大的子项”时已经算过了）；展开的实例、拖柄预览是临时造的，现算。
    final s = identical(n, node) ? ctx.styleOf(n, parent) : resolvedStyle(n, parent);
    final scale = ctx.scale.withFont(cssSizePx(s['font-size'], ctx.scale) ?? ctx.scale.fontSize);
    final textColor = _argb(s['color']) ?? ctx.textColor;
    final inRow = ctx.flow.row;
    final wrap = ctx.flow.wrap;
    final size = cssBoxSize(s, scale, availWidth: ctx.availW, availHeight: ctx.availH);
    final margin = cssEdges(s, 'margin', scale, percentOf: ctx.availW);
    final border = cssBorderWidths(s, scale);
    final padding = cssEdges(s, 'padding', scale, percentOf: ctx.availW);
    final grow = cssNumber(s['flex-grow']) ?? 0;
    final self = cssAlign(s['align-self']);
    final position = s['position']?.trim().toLowerCase();
    final hidden = s['display']?.trim().toLowerCase() == 'none';

    // 在父容器里怎么占位。和导出规则一致：行里撑满的组件、没给固定宽度的容器平分剩余空间；自适应的文本可以被压窄。
    final expanded = grow > 0 && !wrap && (inRow ? ctx.boundedW : ctx.boundedH);
    final flexible = !expanded && !wrap && inRow && ctx.boundedW && n.type == 'text' && size.width == null;
    final stretchW = !inRow && !wrap && self == CssAlign.stretch && size.width == null && ctx.boundedW;
    final stretchH = inRow && self == CssAlign.stretch && size.height == null && ctx.boundedH && !wrap && ctx.availH != null;
    final tightW = size.width != null || stretchW || (expanded && inRow);
    final tightH = size.height != null || stretchH || (expanded && !inRow);
    // 父容器给不给上限：竖排给宽度上限、横排给高度上限；换行的容器正好反过来（只在排的那个方向给）。
    final boundedW = tightW || flexible || size.maxWidth != null || (inRow == wrap && ctx.boundedW);
    final boundedH = tightH || size.maxHeight != null || (inRow != wrap && ctx.boundedH);
    var outerW = size.width ?? (expanded && inRow ? ctx.availW / math.max(1, ctx.growCount) : ctx.availW - margin.horizontal);
    if (size.maxWidth != null) outerW = math.min(outerW, size.maxWidth!);
    final contentW = math.max(0.0, outerW - border.horizontal - padding.horizontal);
    final contentH = size.height == null ? null : math.max(0.0, size.height! - border.vertical - padding.vertical);

    final radius = _radius(s, scale);
    final bg = _argb(s['background-color']);
    final own = _textStyle(s, scale);
    // 哪些样式由里面的控件自己画（按钮的底色、输入框的边框…），外面的盒子就不重复画。
    var paintBg = true, paintBorder = true, usePadding = true;
    Widget content;
    switch (n.type) {
      case 'container' || 'column' || 'card' || 'row':
        final flow = cssFlow(s, rowByDefault: n.type == 'row');
        var grows = 0;
        for (final c in n.children) {
          if ((cssNumber(ctx.styleOf(c, n)['flex-grow']) ?? 0) > 0) grows++;
        }
        final inner = _Ctx(
          parent: n,
          flow: flow,
          boundedW: boundedW,
          boundedH: boundedH,
          availW: contentW,
          availH: contentH,
          scale: scale,
          growCount: grows,
          textColor: textColor,
          buttonText: ctx.buttonText,
          styles: ctx.styles,
        );
        content = (instance ? _inertCopy() : this)._flex(context, n, s, inner, tightW: tightW, tightH: tightH);
        final align = _textAlign(s);
        if (own != null || align != null) content = DefaultTextStyle.merge(style: own, textAlign: align, child: content);
      case 'text':
        final lines = int.tryParse(s['-webkit-line-clamp'] ?? '');
        content = Text(
          n.strProp('text') ?? '',
          textAlign: _textAlign(s),
          style: _textStyle(s, scale, defaultHeight: 1.5),
          maxLines: lines != null && lines > 0 ? lines : null,
          overflow: lines != null && lines > 0 ? TextOverflow.ellipsis : null,
        );
      case 'button':
        paintBg = paintBorder = usePadding = false;
        final side = cssBorderSide(s, 'top', scale);
        final line = side == null ? BorderSide.none : BorderSide(width: side.width, color: side.argb == null ? textColor : Color(side.argb!));
        content = FilledButton(
          onPressed: () {},
          style: FilledButton.styleFrom(
            backgroundColor: bg,
            foregroundColor: _argb(s['color']),
            padding: _has(s, 'padding-') ? EdgeInsets.fromLTRB(padding.left, padding.top, padding.right, padding.bottom) : null,
            shape: _hasRadius(s) ? RoundedRectangleBorder(borderRadius: radius ?? BorderRadius.zero, side: line) : (side == null ? null : StadiumBorder(side: line)),
            // 只改写了的那几项：整个替换 textStyle 会丢掉主题里的字体和字重
            textStyle: own == null ? null : (s.containsKey('font-size') ? ctx.buttonText : Theme.of(context).textTheme.labelLarge)?.merge(own),
          ),
          child: Text(n.strProp('text') ?? '', textAlign: _textAlign(s)),
        );
      case 'image':
        paintBg = false;
        final w = size.width ?? (stretchW ? double.infinity : null);
        content = ClipRRect(
          borderRadius: radius ?? BorderRadius.zero,
          child: CanvasImage(src: n.strProp('src'), width: w, height: size.height, style: s, background: bg),
        );
      case 'input':
        paintBg = paintBorder = usePadding = false;
        final side = cssBorderSide(s, 'top', scale);
        final shape = OutlineInputBorder(
          borderRadius: _hasRadius(s) ? radius ?? BorderRadius.zero : BorderRadius.circular(4),
          borderSide: side == null ? const BorderSide() : BorderSide(width: side.width, color: side.argb == null ? textColor : Color(side.argb!)),
        );
        final field = TextField(
          enabled: false,
          style: own,
          decoration: InputDecoration(
            hintText: n.strProp('placeholder') ?? '',
            border: shape,
            disabledBorder: side == null ? null : shape,
            filled: bg != null,
            fillColor: bg,
            contentPadding: _has(s, 'padding-') ? EdgeInsets.fromLTRB(padding.left, padding.top, padding.right, padding.bottom) : null,
          ),
        );
        // 输入框自己没有“自然宽度”：行里、或者宽度没有上限的地方，给它一个固定的 160。
        content = !tightW && (inRow || !boundedW) ? SizedBox(width: math.min(160, size.maxWidth ?? 160), child: field) : field;
      case 'list':
        final style = _textStyle(s, scale, defaultHeight: 1.75);
        final items = n.props['items'];
        content = QuietFlex(
          direction: Axis.vertical,
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (items is List)
              for (final item in items) Text('• $item', style: style, textAlign: _textAlign(s)),
          ],
        );
      case 'divider':
        paintBorder = false;
        final line = cssBorderSide(s, 'top', scale);
        final color = line?.argb == null ? null : Color(line!.argb!);
        content = inRow
            ? SizedBox(
                height: size.height ?? 24,
                child: VerticalDivider(width: line?.width ?? 1, thickness: line?.width, color: color),
              )
            : Divider(height: line?.width ?? 1, thickness: line?.width, color: color);
      case 'spacer':
        content = const SizedBox.shrink();
      case 'component':
        final ref = n.strProp('ref');
        content = CanvasComponentPlaceholder(name: ref == null ? null : doc.component(ref)?.name);
      default:
        content = const SizedBox.shrink();
    }

    // 边框盒：尺寸 → 底色 / 边框 / 圆角 / 阴影 → 裁剪 → 内边距 → 内容。哪一层没有就不套。
    final inset = (usePadding ? padding : CssEdges.zero) + (paintBorder ? border : CssEdges.zero);
    Widget box = content;
    if (!inset.isZero) box = Padding(padding: EdgeInsets.fromLTRB(inset.left, inset.top, inset.right, inset.bottom), child: box);
    if (cssClips(s)) box = ClipRRect(borderRadius: radius ?? BorderRadius.zero, child: box);
    final shadow = _shadow(n, s, scale, textColor);
    final edge = paintBorder ? _border(s, scale, textColor, radius != null) : null;
    if ((paintBg && bg != null) || edge != null || shadow != null || (paintBg && radius != null)) {
      box = DecoratedBox(
        decoration: BoxDecoration(color: paintBg ? bg : null, border: edge, borderRadius: radius, boxShadow: shadow),
        child: box,
      );
    }
    var w = size.width, h = size.height;
    if (w != null) w = math.max(size.minWidth ?? 0, math.min(w, size.maxWidth ?? double.infinity));
    if (h != null) h = math.max(size.minHeight ?? 0, math.min(h, size.maxHeight ?? double.infinity));
    if (w != null || h != null || stretchW || stretchH) {
      box = SizedBox(width: w ?? (stretchW ? double.infinity : null), height: h ?? (stretchH ? double.infinity : null), child: box);
    }
    final limits = BoxConstraints(
      minWidth: w == null ? size.minWidth ?? 0 : 0,
      maxWidth: w == null ? math.max(size.maxWidth ?? double.infinity, size.minWidth ?? 0) : double.infinity,
      minHeight: h == null ? size.minHeight ?? 0 : 0,
      maxHeight: h == null ? math.max(size.maxHeight ?? double.infinity, size.minHeight ?? 0) : double.infinity,
    );
    if (limits != const BoxConstraints()) box = ConstrainedBox(constraints: limits, child: box);
    // 实例里面的内容不单独定位（选中框只认实例本身）。
    if (!inert) box = KeyedSubtree(key: boxKey(n.id), child: box);

    // 角标：隐藏的、脱离文档流的组件画布上照样占位（不然选不中），用角标说明。
    final badge = hidden ? '已隐藏' : (position == 'absolute' || position == 'fixed' ? '绝对定位' : (position == 'sticky' ? '粘性定位' : null));
    final opacity = cssOpacity(s['opacity']) * (hidden ? 0.35 : 1);
    if (opacity < 1) box = Opacity(opacity: opacity, child: box);
    if (badge != null) {
      box = Stack(
        fit: StackFit.passthrough,
        clipBehavior: Clip.none,
        children: [
          box,
          // 往上探出去一点：贴着左上角放会盖住文字开头
          Positioned(left: 0, top: -9, child: CanvasBadge(badge)),
        ],
      );
    }
    if (!margin.isZero) box = Padding(padding: EdgeInsets.fromLTRB(margin.left, margin.top, margin.right, margin.bottom), child: box);

    // 选中框和拖柄由画布叠在上面画；这里只管点选和长按拖动。
    // 实例整块只当一个东西：里面的内容一律不接手势（点哪儿选中的都是实例）。
    final droppable = n.isContainer && !instance;
    Widget wrapped = inert
        ? box
        : GestureDetector(
            key: ValueKey('lowcode-node-${n.id}'),
            behavior: HitTestBehavior.opaque,
            onTap: () => onSelect(n.id),
            child: droppable ? box : IgnorePointer(child: box),
          );
    if (!inert) {
      // 变淡包在“长按拿起”里面：拖动中这一层不能换位置，不然手势会被打断。
      wrapped = _liftable(node, node.id == movingId ? Opacity(opacity: 0.35, child: wrapped) : wrapped);
    }
    if (position == 'relative') {
      final shift = cssRelativeShift(s, scale, availWidth: ctx.availW, availHeight: ctx.availH);
      if (shift.dx != 0 || shift.dy != 0) wrapped = Transform.translate(offset: Offset(shift.dx, shift.dy), child: wrapped);
    }
    // 单个子项的交叉方向对齐：只在竖排的容器里做得到（横排里忽略）。
    if (!inRow && !wrap && ctx.boundedW && self != null && self != CssAlign.stretch && !tightW) {
      wrapped = Align(
        alignment: Alignment(switch (self) {
          CssAlign.center => 0,
          CssAlign.end => 1,
          _ => -1,
        }, -1),
        child: wrapped,
      );
    }
    // key 放在最外层：拖动开始时兄弟之间会插进插入位，靠 key 认回原来的组件，拖动才不会断。
    final key = ValueKey('lc-item-${n.id}');
    if (expanded) return Expanded(key: key, flex: grow.round().clamp(1, 1000), child: wrapped);
    if (flexible) return Flexible(key: key, child: wrapped);
    return KeyedSubtree(key: key, child: wrapped);
  }

  Widget _liftable(LcNode n, Widget child) {
    final lift = onLift;
    if (lift == null) return child;
    return LcLiftDetector(onLift: (at) => lift(LcDrag.move(n.id), at), onMove: (at) => onLiftMove?.call(at), onDrop: () => onLiftDrop?.call(), onCancel: () => onLiftCancel?.call(), child: child);
  }
}
