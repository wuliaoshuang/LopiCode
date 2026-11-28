// 设计约束（低代码 · 画布上第 3 版的 11 个新组件 · 390×844）
// - 画出来的样子照着导出网页的公共样式（export_web_v3_css.dart）：同样的尺寸、间距、默认色。页面内容用固定浅色，不跟应用的深色模式。
// - 都只是样子：开关、勾选框、下拉点了不会变（点＝选中）。只有标签页的页签点了会切——切的是“画布上现在看哪一页”，
//   不改页面文件（一开始显示哪一页在面板里设）；选中了别的页签里的组件，会自动切到那一页。
// - 带插槽的（列表行左 / 右、导航栏左 / 右、标签页每页、弹窗内容 / 底部）：插槽由调用方画（它知道怎么画子组件、怎么量位置）；
//   空的插槽在编辑时留一个小落点（横排的是 28 见方带加号的小框，竖排的是一条“空的 · 拖组件到这里”），缩略图和导出里没有。
// - 弹窗平时不占页面的位置：页面里只留一个小标签（“弹窗 · 标题”），点它进“只看这个弹层”（canvas_dialog_widgets.dart）。
// - 禁用＝整体变淡 50%（和导出网页一致）。一行只做一件事：每个组件一个函数，互不相干。
import 'dart:math' as math;

import 'package:lopicode/lowcode/canvas_controls_widgets.dart';
import 'package:lopicode/lowcode/canvas_parts_widgets.dart';
import 'package:lopicode/lowcode/icon_set_widgets.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/model_v3_components.dart';
import 'package:lopicode/lowcode/slots.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

part 'canvas_v3_tabs_widgets.dart';

// 用户页面内容的默认色：和导出网页的公共样式一一对应（见 export_web_v3_css.dart），不是编辑器界面色。
const Color kLcPageLine = Color(0xFFB1C0C8);
const Color kLcPageSoftLine = Color(0xFFD3DEE4);
const Color kLcPageMuted = Color(0xFF5C6479);
const Color kLcPageFaint = Color(0xFF8B93A7);
const Color kLcPageAccent = Color(0xFF058654);
const Color kLcPageWhite = Color(0xFFFFFFFF);

/// 轻提示那颗小胶囊的底色（同导出网页里的 rgba(34, 36, 53, .92)）。
const Color kLcToastBg = Color(0xEB222435);
const Color kLcPagePill = Color(0x14000000);

/// 画一个插槽：[name] 插槽名，[row] 里面是不是横着排，[availW] 里面大概多宽，[end] 横排时靠右。
typedef CanvasSlotBuilder = Widget Function(String name, {required bool row, required double availW, bool end});

/// 画新组件要知道的事。
class CanvasV3 {
  const CanvasV3({
    required this.node,
    required this.textColor,
    required this.own,
    required this.radius,
    required this.bg,
    required this.side,
    required this.padded,
    required this.tightW,
    required this.boundedW,
    required this.contentW,
    required this.inert,
    required this.selected,
    required this.onSelect,
    required this.slot,
  });
  final LcNode node;

  /// 这个组件的文字颜色（自己写了用自己的，没写用继承下来的）。
  final Color textColor;

  /// 这个组件自己写的文字样式（字号、粗细…）；没写是 null。
  final TextStyle? own;
  final BorderRadius? radius;
  final Color? bg;

  /// 样式里写的边框（只看上边那条）；没写是 null。
  final BorderSide? side;

  /// 样式里写了内边距（那就不用组件自带的内边距）。
  final bool padded;

  /// 宽度是定死的（固定宽、撑满）；不是的话按内容定宽。
  final bool tightW;

  /// 父容器给的宽度有没有上限。
  final bool boundedW;
  final double contentW;

  /// 只画样子（缩略图、自定义组件实例里面）：没有落点、点不了。
  final bool inert;
  final String? selected;
  final void Function(String id) onSelect;
  final CanvasSlotBuilder slot;
}

/// 这几种自己画底色、边框和内边距，外面的盒子不重复画。
const Set<String> kCanvasV3SelfBoxed = {'textarea', 'select', 'switch', 'slider'};

/// 画一个新组件；不是新组件返回 null。
Widget? canvasV3Content(BuildContext context, CanvasV3 a) {
  final n = a.node;
  final Widget? out = switch (n.type) {
    'icon' => Icon(lcIconData[n.strProp('icon')] ?? Icons.help_outline, size: (n.numProp('size') ?? 24).toDouble(), color: a.textColor),
    'textarea' => _textarea(a),
    'switch' => _switch(n),
    'slider' => _sized(a, _slider(n)),
    'checkbox' => _checkbox(a),
    'radio' => _radio(a),
    'select' => _select(a),
    'listItem' => _listItem(a),
    'appBar' => _appBar(a),
    'bottomNav' => _bottomNav(a),
    'tabs' => CanvasTabs(args: a),
    'dialog' => a.inert ? const SizedBox.shrink() : _DialogChip(title: n.strProp('title'), toast: lcIsToast(n) ? n.strProp('text') ?? '' : null),
    _ => null,
  };
  if (out == null) return null;
  final styled = a.own == null ? out : DefaultTextStyle.merge(style: a.own, child: out);
  return n.props['disabled'] == true && n.type != 'textarea' ? Opacity(opacity: 0.5, child: styled) : styled;
}

/// 没有“自然宽度”的（多行输入、下拉）：行里、或者宽度没有上限的地方给一个固定的 160（和输入框一样）。
Widget _sized(CanvasV3 a, Widget child) => !a.tightW && !a.boundedW ? SizedBox(width: 160, child: child) : child;

BoxDecoration _fieldBox(CanvasV3 a, {Color? fallbackBg}) => BoxDecoration(
  color: a.bg ?? fallbackBg,
  borderRadius: a.radius,
  border: Border.fromBorderSide(a.side ?? const BorderSide(color: kLcPageLine)),
);

Widget _textarea(CanvasV3 a) {
  final n = a.node;
  final value = n.strProp('value');
  final rows = (n.numProp('rows') ?? 3).toInt().clamp(1, 20);
  final field = Container(
    constraints: BoxConstraints(minHeight: rows * 24.0 + 20),
    padding: a.padded ? EdgeInsets.zero : const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: _fieldBox(a),
    alignment: Alignment.topLeft,
    child: Text(
      value ?? n.strProp('placeholder') ?? '',
      style: TextStyle(color: value == null ? kLcPageFaint : null, height: 1.5),
      maxLines: n.props['autoGrow'] == true ? null : rows,
      overflow: n.props['autoGrow'] == true ? null : TextOverflow.clip,
    ),
  );
  return _sized(a, canvasInputFrame(n, field));
}

Widget _switch(LcNode n) {
  final on = n.props['checked'] == true;
  return Container(
    width: 44,
    height: 26,
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(color: on ? kLcPageAccent : kLcPageLine, borderRadius: BorderRadius.circular(13)),
    alignment: on ? Alignment.centerRight : Alignment.centerLeft,
    child: const DecoratedBox(
      decoration: BoxDecoration(color: kLcPageWhite, shape: BoxShape.circle),
      child: SizedBox(width: 20, height: 20),
    ),
  );
}

/// 滑块：一条 4 高的轨道（走过的那段是强调色）加一个 20 见方的圆钮，整个 28 高。只是画出来，画布上不能拖。
Widget _slider(LcNode n) {
  final s = lcSliderOf(n);
  final at = ((s.value - s.min) / (s.max - s.min)).clamp(0.0, 1.0).toDouble();
  return SizedBox(
    height: 28,
    child: LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth.isFinite ? box.maxWidth : 160.0;
        final x = (w - 20) * at;
        return Stack(
          alignment: Alignment.centerLeft,
          children: [
            Container(
              height: 4,
              decoration: BoxDecoration(color: kLcPageLine, borderRadius: BorderRadius.circular(2)),
            ),
            Container(
              width: x + 10,
              height: 4,
              decoration: BoxDecoration(color: kLcPageAccent, borderRadius: BorderRadius.circular(2)),
            ),
            Positioned(
              left: x,
              child: const DecoratedBox(
                decoration: BoxDecoration(color: kLcPageAccent, shape: BoxShape.circle),
                child: SizedBox(width: 20, height: 20),
              ),
            ),
          ],
        );
      },
    ),
  );
}

/// 勾选框 / 单选的那个小方块、小圆点（18 见方）。
Widget _tick({required bool on, required bool round}) => Container(
  width: 18,
  height: 18,
  decoration: BoxDecoration(
    color: on && !round ? kLcPageAccent : null,
    shape: round ? BoxShape.circle : BoxShape.rectangle,
    borderRadius: round ? null : BorderRadius.circular(3),
    border: Border.all(color: on ? kLcPageAccent : kLcPageFaint, width: on && round ? 5 : 1.5),
  ),
  child: on && !round ? const Icon(Icons.check, size: 14, color: kLcPageWhite) : null,
);

Widget _labeled(Widget mark, String text, Color color) => QuietFlex(
  direction: Axis.horizontal,
  mainAxisSize: MainAxisSize.min,
  spacing: 8,
  children: [
    mark,
    Flexible(
      child: Text(text, style: TextStyle(color: color)),
    ),
  ],
);

Widget _checkbox(CanvasV3 a) => _labeled(_tick(on: a.node.props['checked'] == true, round: false), a.node.strProp('text') ?? '', a.textColor);

Widget _radio(CanvasV3 a) {
  final n = a.node;
  final options = lcObjects(n, 'options');
  final value = n.props['value'];
  if (lcVariantOf(n) == 'button') {
    return QuietFlex(
      direction: Axis.horizontal,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, o) in options.indexed)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: o['value'] == value ? kLcPageAccent : null,
              border: Border.all(color: o['value'] == value ? kLcPageAccent : kLcPageLine),
              borderRadius: BorderRadius.horizontal(left: Radius.circular(i == 0 ? 8 : 0), right: Radius.circular(i == options.length - 1 ? 8 : 0)),
            ),
            child: Text(lcItemLabel(o, 'value'), style: TextStyle(color: o['value'] == value ? kLcPageWhite : a.textColor)),
          ),
      ],
    );
  }
  final items = [for (final o in options) _labeled(_tick(on: o['value'] == value, round: true), lcItemLabel(o, 'value'), a.textColor)];
  return n.props['direction'] == 'row'
      ? Wrap(spacing: 16, runSpacing: 8, children: items)
      : QuietFlex(direction: Axis.vertical, mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: items);
}

Widget _select(CanvasV3 a) {
  final n = a.node;
  final value = n.props['value'];
  final picked = lcObjects(n, 'options').where((o) => o['value'] == value).firstOrNull;
  final text = Text(
    picked == null ? n.strProp('placeholder') ?? '' : lcItemLabel(picked, 'value'),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(color: picked == null ? kLcPageFaint : a.textColor, height: 1.5),
  );
  final fill = a.tightW || !a.boundedW;
  return _sized(
    a,
    Container(
      padding: a.padded ? EdgeInsets.zero : const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: _fieldBox(a, fallbackBg: kLcPageWhite),
      child: QuietFlex(
        direction: Axis.horizontal,
        mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
        spacing: 8,
        children: [
          if (fill) Expanded(child: text) else Flexible(child: text),
          const Icon(Icons.expand_more, size: 20, color: kLcPageMuted),
        ],
      ),
    ),
  );
}

/// 一格能伸的内容：宽度有上限就占满剩下的，没有就按内容。
Widget _stretch(CanvasV3 a, Widget child) => a.tightW || a.boundedW ? Expanded(child: child) : Flexible(child: child);

bool _showSlot(CanvasV3 a, String name) => !a.inert || lcSlotChildren(a.node, name).isNotEmpty;

Widget _listItem(CanvasV3 a) {
  final n = a.node;
  final sub = lcVariantOf(n) == 'two' ? n.strProp('subtitle') : null;
  final trailing = n.strProp('trailing');
  final row = QuietFlex(
    direction: Axis.horizontal,
    mainAxisSize: a.tightW || a.boundedW ? MainAxisSize.max : MainAxisSize.min,
    spacing: 12,
    children: [
      if (_showSlot(a, 'left')) a.slot('left', row: true, availW: a.contentW / 3),
      _stretch(
        a,
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(n.strProp('title') ?? '', style: const TextStyle(height: 1.5)),
            if (sub != null) Text(sub, style: const TextStyle(fontSize: 13, height: 1.4, color: kLcPageMuted)),
          ],
        ),
      ),
      if (trailing != null) Text(trailing, style: const TextStyle(fontSize: 14, color: kLcPageMuted)),
      if (_showSlot(a, 'right')) a.slot('right', row: true, availW: a.contentW / 3),
      if (n.props['chevron'] == true) const Icon(Icons.chevron_right, size: 20, color: kLcPageFaint),
    ],
  );
  return ConstrainedBox(
    constraints: BoxConstraints(minHeight: a.padded ? 48 : 28),
    child: a.padded ? row : Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), child: row),
  );
}

Widget _appBar(CanvasV3 a) {
  final n = a.node;
  final center = lcVariantOf(n) == 'center';
  final title = Text(
    n.strProp('title') ?? '',
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    textAlign: center ? TextAlign.center : TextAlign.start,
    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, height: 1.4, color: a.textColor),
  );
  final sides = QuietFlex(
    direction: Axis.horizontal,
    spacing: 8,
    children: [
      if (n.props['back'] == true)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Icon(Icons.arrow_back, size: 24, color: a.textColor),
        ),
      if (_showSlot(a, 'left')) a.slot('left', row: true, availW: a.contentW / 3),
      if (center) const Spacer() else Expanded(child: title),
      if (_showSlot(a, 'right')) a.slot('right', row: true, availW: a.contentW / 3, end: true),
    ],
  );
  final bar = ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 56),
    child: center
        ? Stack(
            alignment: Alignment.center,
            children: [
              sides,
              Positioned(left: 72, right: 72, child: title),
            ],
          )
        : sides,
  );
  final body = a.padded ? bar : Padding(padding: const EdgeInsets.only(left: 16, right: 8), child: bar);
  // 导航栏要一个有上限的宽度（标题要占满剩下的）；放在没有上限的地方给一个手机宽。
  return a.tightW || a.boundedW ? body : SizedBox(width: math.max(a.contentW, 240), child: body);
}

Widget _bottomNav(CanvasV3 a) {
  final n = a.node;
  final items = lcObjects(n, 'items');
  final current = n.numProp('current') ?? 0;
  final labeled = lcVariantOf(n) == 'labeled';
  final bar = Container(
    constraints: const BoxConstraints(minHeight: 56),
    decoration: const BoxDecoration(
      border: Border(top: BorderSide(color: kLcPageSoftLine)),
    ),
    child: Row(
      children: [
        for (final (i, item) in items.indexed)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                spacing: 2,
                children: [
                  Icon(lcIconData[item['icon']] ?? Icons.help_outline, size: 24, color: i == current ? a.textColor : kLcPageMuted),
                  if (labeled)
                    Text(
                      lcItemLabel(item, 'icon'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, height: 1.3, color: i == current ? a.textColor : kLcPageMuted),
                    ),
                ],
              ),
            ),
          ),
      ],
    ),
  );
  return a.tightW || a.boundedW ? bar : SizedBox(width: math.max(a.contentW, 240), child: bar);
}
