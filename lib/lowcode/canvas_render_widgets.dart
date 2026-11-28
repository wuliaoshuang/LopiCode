// 设计约束（低代码 · 画布里的“页面” · 390×844）
// - 每个组件按它的“最终样式”（resolvedStyle：简写属性 + 自己的 style）画，画不了的样式忽略，绝不报错。
// - 没有 style 的旧页面，画出来和第 1 版一模一样（默认对齐、间距、按钮 / 输入框的样子都不变）。
// - 页面内容用固定的浅色主题：它是“用户页面”的样子，不跟随应用的深色模式。
// - 组件本身不响应点击（按钮、输入框只是样子）：点＝选中，长按 280 毫秒＝拿起来拖（手势在 lift_gesture_widgets.dart）。
// - 拖动时这里什么都不变（不插占位、不撑开）；落点的蓝线由画布叠在上面画。正在拖的那个组件只是变淡。
// - 每个组件的最终样式一次重搭里只算一遍（_Ctx.styles 记着），父容器数“要放大的子项”和画子项用的是同一份。
import 'dart:math' as math;

import 'package:lopicode/lowcode/bind_eval.dart';
import 'package:lopicode/lowcode/bind_preview.dart';
import 'package:lopicode/lowcode/box_off.dart';
import 'package:lopicode/lowcode/canvas_component_widgets.dart';
import 'package:lopicode/lowcode/canvas_controls_widgets.dart';
import 'package:lopicode/lowcode/canvas_css.dart';
import 'package:lopicode/lowcode/canvas_dialog_widgets.dart';
import 'package:lopicode/lowcode/canvas_grid_widgets.dart';
import 'package:lopicode/lowcode/canvas_parts_widgets.dart';
import 'package:lopicode/lowcode/canvas_style_widgets.dart';
import 'package:lopicode/lowcode/canvas_v3_widgets.dart';
import 'package:lopicode/lowcode/component_editing.dart';
import 'package:lopicode/lowcode/component_ops.dart';
import 'package:lopicode/lowcode/lift_gesture_widgets.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/palette_widgets.dart';
import 'package:lopicode/lowcode/responsive.dart';
import 'package:lopicode/lowcode/slots.dart';
import 'package:lopicode/lowcode/states_bp.dart';
import 'package:lopicode/lowcode/style_resolve.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

part 'canvas_render_slots.dart';

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
    this.overlayId,
    this.statePreview,
    this.live,
    this.bp,
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
      overlayId = null,
      statePreview = null,
      live = null,
      bp = null,
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

  /// “只看这个弹层”：正在编辑的那个弹窗（页面里别的不画）。
  final String? overlayId;

  /// 正在预览哪个组件的哪种状态样式（按下 / 禁用 / 聚焦）。
  final ({String nodeId, String state})? statePreview;

  /// 只画样子的这一份是替哪张活页面画的（实例里填进插槽的内容交回给它画，见 canvas_render_slots.dart）。
  final CanvasPage? live;

  /// 按哪一档屏宽画（null＝手机；见 responsive.dart）。
  final String? bp;

  CanvasPage _inertCopy() => CanvasPage(doc: doc, pageWidth: pageWidth, minHeight: minHeight, selected: null, onSelect: (_) {}, boxKey: boxKey, inert: true, live: inert ? live : this, bp: bp);

  @override
  Widget build(BuildContext context) {
    debugBuilds++;
    final env = LcViewEnv.of(doc, bp);
    final root = lcViewNode(doc.root, env);
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
      textColor: canvasArgb(s['color']) ?? Palette.neutral900,
      buttonText: Theme.of(context).textTheme.labelLarge,
      styles: Map.identity(),
      env: env,
    );
    final dialog = overlayId == null ? null : doc.find(overlayId!);
    final page = dialog != null && dialog.type == 'dialog'
        ? canvasDialogStage(
            context,
            node: dialog,
            pageWidth: pageWidth,
            minHeight: minHeight,
            pageColor: canvasArgb(s['background-color']) ?? Colors.white,
            pageKey: boxKey(root.id),
            panelKey: boxKey(dialog.id),
            inert: inert,
            onSelect: () => onSelect(dialog.id),
            slot: (name, {required row, required availW, end = false}) => _slot(context, dialog, ctx, name, row: row, availW: availW, end: end),
          )
        : Container(
            key: boxKey(root.id),
            width: pageWidth,
            constraints: BoxConstraints(minHeight: minHeight),
            decoration: BoxDecoration(color: canvasArgb(s['background-color']) ?? Colors.white, border: canvasBorder(s, scale, Palette.neutral900, false)),
            foregroundDecoration: selected == root.id ? BoxDecoration(border: Border.all(color: context.themeSpec.lowcodeColor(LowcodeKey.selection), width: 2)) : null,
            padding: EdgeInsets.fromLTRB(padding.left, padding.top, padding.right, padding.bottom),
            child: _flex(context, root, s, ctx, tightW: true, tightH: false),
          );
    return Theme(
      // 页面内容用自己的一套 Material 外观（不跟应用主题走）；只把应用主题的颜色表带进去，给选中框、插入位这些编辑器界面色用。
      data: ThemeData(useMaterial3: true, colorSchemeSeed: Palette.primary700, fontFamily: font, extensions: [AppColors.resolve(context)]),
      child: Builder(
        builder: (context) => DefaultTextStyle(
          style: TextStyle(fontSize: 16, color: Palette.neutral900, height: 1.5, fontFamily: font).merge(canvasTextStyle(s, scale)),
          textAlign: canvasTextAlign(s),
          // 单独一层：平移 / 缩放只挪这一层，不把几百个组件重画一遍。
          child: RepaintBoundary(
            child: inert ? page : GestureDetector(key: const ValueKey('lowcode-page'), onTap: () => onSelect(root.id), child: page),
          ),
        ),
      ),
    );
  }

  // ───────────── 容器里的子项 ─────────────

  /// 把容器的子项排出来。[tightW] / [tightH]：容器自己的宽 / 高是不是定死的（决定“拉伸”要不要先量内容）。
  Widget _flex(BuildContext context, LcNode n, Map<String, String> s, _Ctx inner, {required bool tightW, required bool tightH, List<LcNode>? only}) {
    final flow = inner.flow;
    final scale = inner.scale;
    final mainGap = cssSizePx(s[flow.row ? 'column-gap' : 'row-gap'], scale, percentOf: inner.availW) ?? 0;
    final crossGap = cssSizePx(s[flow.row ? 'row-gap' : 'column-gap'], scale, percentOf: inner.availW) ?? 0;
    final align = cssAlign(s['align-items']) ?? (n.type == 'row' ? CssAlign.center : CssAlign.start);
    final justify = cssJustify(s['justify-content']) ?? CssJustify.start;
    final kids = [
      for (final c in only ?? n.children)
        // 实例里面条件不成立的：反正点不中，不画也不占位（和导出来的样子一致）；页面上、组件编辑里的照旧调淡带角标。
        if (!c.hidden && !(inert && inner.env.bind != null && !lcCondHolds(c, inner.env.bind!))) c,
    ];
    if ((only ?? n.children).isEmpty) {
      return inert ? const SizedBox.shrink() : const CanvasEmptyHint();
    }
    // 网格：等宽的几列，一行行排下去（canvas_grid_widgets.dart）。格子里的组件按“竖排容器里的子项”画，宽度就是一格。
    final grid = only == null ? canvasGridOf(s, scale, inner.availW) : null;
    if (grid != null) {
      final cell = _Ctx(
        parent: n,
        flow: const CssFlow(row: false, reverse: false, wrap: false),
        boundedW: true,
        boundedH: false,
        availW: grid.columnWidth,
        availH: null,
        scale: scale,
        growCount: 0,
        textColor: inner.textColor,
        buttonText: inner.buttonText,
        styles: inner.styles,
        env: inner.env,
      );
      return canvasGrid(grid, [
        for (final c in kids)
          for (final w in _items(context, n, s, cell, c)) (span: canvasGridSpan(inner.styleOf(c, n)), child: w),
      ]);
    }
    // 子项之间的间距由容器自己留（拖动时也不往里插东西），这样“两端对齐”之类的分布才准。
    // “编辑器里隐藏”的（图层面板的眼睛）不画、不占位；导出不受影响。
    final children = [for (final c in kids) ..._items(context, n, s, inner, c)];
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

  /// [copy]：“重复”画出来的第几份（0＝活的那一份）；[badge]：绑定给的角标。
  Widget _node(BuildContext context, LcNode node, _Ctx ctx, {int copy = 0, String? badge}) {
    final parent = ctx.parent;
    // 拖柄拖动中：把临时尺寸当成这个组件自己的样式来算，“撑满”之类的规则才会跟着让路。
    final p = preview;
    // 自定义组件的实例：按展开后的内容画（最外层沿用实例的 id，所以选中框、拖柄照常认得它）。
    // 展开不了、或者已经在别的实例里面了（inert）就不展开，下面画占位。
    final instance = node.type == 'component' && !inert;
    final shown = instance ? expandInstance(doc, node, markers: true) ?? node : node;
    // 主题变量换成值、现在这一档屏宽的差别并进来（都没有时还是原来那个对象）。
    final n = canvasPreviewNode(
      lcViewNode(shown, ctx.env),
      resize: p != null && p.nodeId == node.id ? (p.width, p.height) : null,
      state: statePreview?.nodeId == node.id ? lcSubstMap(lcStateStyleAt(node, statePreview!.state, ctx.env.bp), ctx.env.vars) : const {},
    );
    // 没被改过的组件用这一轮记着的那份（父容器数“要放大的子项”时已经算过了）；展开的实例、拖柄预览是临时造的，现算。
    final s = identical(n, node) ? ctx.styleOf(n, parent) : resolvedStyle(n, parent);
    final scale = ctx.scale.withFont(cssSizePx(s['font-size'], ctx.scale) ?? ctx.scale.fontSize);
    final textColor = canvasArgb(s['color']) ?? ctx.textColor;
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
    // 显示条件 / 存在条件按初值不成立：照样占位（不然选不中），调淡加角标。
    final condOff = ctx.env.bind != null && !lcCondHolds(node, ctx.env.bind!);

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

    final radius = canvasRadius(s, scale);
    final bg = canvasArgb(s['background-color']);
    final own = canvasTextStyle(s, scale);
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
          env: ctx.env,
        );
        content = (instance ? _inertCopy() : this)._flex(context, n, s, inner, tightW: tightW, tightH: tightH);
        final align = canvasTextAlign(s);
        if (own != null || align != null) content = DefaultTextStyle.merge(style: own, textAlign: align, child: content);
      case 'text':
        final lines = int.tryParse(s['-webkit-line-clamp'] ?? '');
        content = Text(
          n.strProp('text') ?? '',
          textAlign: canvasTextAlign(s),
          style: canvasTextStyle(s, scale, defaultHeight: 1.5),
          maxLines: lines != null && lines > 0 ? lines : null,
          overflow: lines != null && lines > 0 ? TextOverflow.ellipsis : null,
        );
      case 'button':
        paintBg = paintBorder = usePadding = false;
        final side = cssBorderSide(s, 'top', scale);
        final line = side == null ? BorderSide.none : BorderSide(width: side.width, color: side.argb == null ? textColor : Color(side.argb!));
        content = canvasButton(
          n,
          textAlign: canvasTextAlign(s),
          style: FilledButton.styleFrom(
            backgroundColor: bg,
            foregroundColor: canvasArgb(s['color']),
            padding: _has(s, 'padding-') ? EdgeInsets.fromLTRB(padding.left, padding.top, padding.right, padding.bottom) : null,
            shape: _hasRadius(s) ? RoundedRectangleBorder(borderRadius: radius ?? BorderRadius.zero, side: line) : (side == null ? null : StadiumBorder(side: line)),
            // 只改写了的那几项：整个替换 textStyle 会丢掉主题里的字体和字重
            textStyle: own == null ? null : (s.containsKey('font-size') ? ctx.buttonText : Theme.of(context).textTheme.labelLarge)?.merge(own),
          ),
        );
      case 'image':
        paintBg = false;
        final w = size.width ?? (stretchW ? double.infinity : null);
        content = ClipRRect(
          borderRadius: radius ?? BorderRadius.zero,
          child: CanvasImage(src: n.strProp('src'), width: w, height: size.height, style: s, background: bg),
        );
      case LcNode.unknownType:
        content = CanvasUnknownPlaceholder(typeName: n.fileType);
      case 'input':
        paintBg = paintBorder = usePadding = false;
        final side = cssBorderSide(s, 'top', scale);
        final shape = OutlineInputBorder(
          borderRadius: _hasRadius(s) ? radius ?? BorderRadius.zero : BorderRadius.circular(4),
          borderSide: side == null ? const BorderSide() : BorderSide(width: side.width, color: side.argb == null ? textColor : Color(side.argb!)),
        );
        final value = canvasInputValue(n);
        final field = TextField(
          enabled: false,
          controller: value == null ? null : TextEditingController(text: value),
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
        final framed = canvasInputFrame(n, field);
        content = !tightW && (inRow || !boundedW) ? SizedBox(width: math.min(160, size.maxWidth ?? 160), child: framed) : framed;
      case 'list':
        content = canvasBullets(n, s, scale);
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
        final side = cssBorderSide(s, 'top', scale);
        final v3 = canvasV3Content(
          context,
          CanvasV3(
            node: n,
            textColor: textColor,
            own: own,
            radius: radius,
            bg: bg,
            side: side == null ? null : BorderSide(width: side.width, color: side.argb == null ? textColor : Color(side.argb!)),
            padded: _has(s, 'padding-'),
            tightW: tightW,
            boundedW: boundedW && !inRow,
            contentW: contentW,
            inert: inert || instance,
            selected: selected,
            onSelect: onSelect,
            slot: (name, {required row, required availW, end = false}) =>
                (instance ? _inertCopy() : this)._slot(context, n, ctx, name, row: row, availW: availW, end: end, scale: scale, textColor: textColor),
          ),
        );
        if (kCanvasV3SelfBoxed.contains(n.type)) paintBg = paintBorder = usePadding = false;
        content = v3 ?? const SizedBox.shrink();
    }

    // 边框盒：尺寸 → 底色 / 边框 / 圆角 / 阴影 → 裁剪 → 内边距 → 内容。哪一层没有就不套。
    final inset = (usePadding ? padding : CssEdges.zero) + (paintBorder ? border : CssEdges.zero);
    Widget box = content;
    if (!inset.isZero) box = Padding(padding: EdgeInsets.fromLTRB(inset.left, inset.top, inset.right, inset.bottom), child: box);
    if (cssClips(s)) box = ClipRRect(borderRadius: radius ?? BorderRadius.zero, child: box);
    final shadow = canvasShadow(n, s, scale, textColor);
    final edge = paintBorder ? canvasBorder(s, scale, textColor, radius != null) : null;
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
    final tag = hidden ? '已隐藏' : (condOff ? '条件不成立' : (position == 'absolute' || position == 'fixed' ? '绝对定位' : (position == 'sticky' ? '粘性定位' : badge)));
    final opacity = cssOpacity(s['opacity']) * (hidden || condOff ? 0.35 : 1) * (copy > 0 ? 0.5 : 1) * (lcBoxOff(n) ? 0.5 : 1);
    if (opacity < 1) box = Opacity(opacity: opacity, child: box);
    if (tag != null) box = canvasBadged(box, tag);
    if (!margin.isZero) box = Padding(padding: EdgeInsets.fromLTRB(margin.left, margin.top, margin.right, margin.bottom), child: box);

    // 选中框和拖柄由画布叠在上面画；这里只管点选和长按拖动。
    // 实例整块只当一个东西：里面的内容不接手势（点哪儿选中的都是实例）；只有填进它插槽里的东西是活的。
    final droppable = n.isContainer && (!instance || node.hasSlots) && n.type != 'dialog';
    // 锁着的：点不中、拖不动（点它等于点它外面那一层）；它里面的东西照常能点。
    Widget wrapped = inert
        ? box
        : node.locked
        ? KeyedSubtree(
            key: ValueKey('lowcode-node-${n.id}'),
            child: droppable ? box : IgnorePointer(child: box),
          )
        : GestureDetector(
            key: ValueKey('lowcode-node-${n.id}'),
            behavior: HitTestBehavior.opaque,
            onTap: () => onSelect(n.id),
            child: droppable ? box : IgnorePointer(child: box),
          );
    if (!inert && !node.locked) {
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
    final key = ValueKey(copy == 0 ? 'lc-item-${n.id}' : 'lc-item-${n.id}#$copy');
    if (expanded) return Expanded(key: key, flex: grow.round().clamp(1, 1000), child: wrapped);
    if (flexible) return Flexible(key: key, child: wrapped);
    return KeyedSubtree(key: key, child: wrapped);
  }
}
