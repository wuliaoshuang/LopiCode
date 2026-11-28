// 设计约束（低代码 · 数字框“长按住再左右拖＝加减” · 390×844 · 第四轮 B8）
// - 手势：手指在数字框上**长按住**（系统的长按时间），不松手左右拖：每拖 [kNumberDragPx] 像素一步，往右加、往左减。
//   只在长按成立以后才接手，所以不和面板上下滚、页签左右翻抢（那两样在长按成立前就已经赢了）；点一下照旧是进去打字。
// - 反馈：长按成立时轻震一下；框上方浮一个小气泡写着现在的数（在手指上面，不被挡住）；松手、被系统打断都收起。
// - 正在打字（输入框有焦点）时这一层拿掉：光标、选字、长按粘贴归输入框管。禁用的不拖。
// - 不直接改模型：每变一步把新值交给回调（由用它的人决定怎么并成一步撤销）。
// - 颜色只用主题色；气泡不接手势。
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:lopicode/lowcode/style_controls_widgets.dart' show fmtNum;
import 'package:lopicode/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// 长按数字框以后，手指每横着挪这么多像素加减一步。
const double kNumberDragPx = 8;

/// 盖在一个数字输入框上，给它加“长按住再左右拖＝加减”。[child] 就是那个输入框，[focusNode] 是它的焦点。
class NumberDragArea extends StatefulWidget {
  const NumberDragArea({
    super.key,
    required this.id,
    required this.focusNode,
    required this.value,
    required this.onChanged,
    required this.child,
    this.enabled = true,
    this.step = 1,
    this.min,
    this.max,
    this.integer = false,
  });

  /// 测试定位：这一层是 `lc-num-<id>-touch`，气泡是 `lc-num-<id>-drag`。
  final String id;
  final FocusNode focusNode;

  /// 现在的数（还没有值时传“从几算起”）。
  final double value;
  final ValueChanged<double> onChanged;
  final Widget child;
  final bool enabled;
  final double step;
  final double? min;
  final double? max;
  final bool integer;

  @override
  State<NumberDragArea> createState() => _NumberDragAreaState();
}

class _NumberDragAreaState extends State<NumberDragArea> {
  final LayerLink _link = LayerLink();
  final OverlayPortalController _bubble = OverlayPortalController();
  double? _base;
  double _now = 0;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocus);
  }

  @override
  void didUpdateWidget(NumberDragArea old) {
    super.didUpdateWidget(old);
    if (old.focusNode != widget.focusNode) {
      old.focusNode.removeListener(_onFocus);
      widget.focusNode.addListener(_onFocus);
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocus);
    super.dispose();
  }

  void _onFocus() {
    if (mounted) setState(() {}); // 打字时把这一层拿掉、离开时放回
  }

  void _start() {
    _base = widget.value;
    _now = widget.value;
    unawaited(HapticFeedback.selectionClick()); // 不等：只是手感
    _bubble.show();
    setState(() {});
  }

  void _move(double dx) {
    final base = _base;
    if (base == null) return;
    var next = double.parse((base + (dx / kNumberDragPx).truncate() * widget.step).toStringAsFixed(2));
    if (widget.min != null && next < widget.min!) next = widget.min!;
    if (widget.max != null && next > widget.max!) next = widget.max!;
    if (widget.integer) next = next.roundToDouble();
    if (next == _now) return;
    setState(() => _now = next);
    widget.onChanged(next);
  }

  void _end() {
    if (_base == null) return;
    _base = null;
    _bubble.hide();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _bubble,
        overlayChildBuilder: (context) => Positioned(
          left: 0,
          top: 0,
          child: CompositedTransformFollower(
            link: _link,
            showWhenUnlinked: false,
            targetAnchor: Alignment.topCenter,
            followerAnchor: Alignment.bottomCenter,
            offset: const Offset(0, -Space.x2),
            child: IgnorePointer(
              child: Container(
                key: Key('lc-num-${widget.id}-drag'),
                padding: const EdgeInsets.symmetric(horizontal: Space.x3, vertical: Space.x1),
                decoration: BoxDecoration(color: c.accentFill, borderRadius: BorderRadius.circular(Radii.md)),
                child: Text('‹ ${fmtNum(_now)} ›', style: t.titleSmall?.copyWith(color: c.onAccent)),
              ),
            ),
          ),
        ),
        child: Stack(
          children: [
            widget.child,
            if (widget.enabled && !widget.focusNode.hasFocus)
              Positioned.fill(
                child: GestureDetector(
                  key: Key('lc-num-${widget.id}-touch'),
                  behavior: HitTestBehavior.opaque,
                  excludeFromSemantics: true,
                  onTap: widget.focusNode.requestFocus,
                  onLongPressStart: (_) => _start(),
                  onLongPressMoveUpdate: (d) => _move(d.offsetFromOrigin.dx),
                  onLongPressEnd: (_) => _end(),
                  onLongPressCancel: _end,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
