// 设计约束（推开式侧边栏 · 390×844）— 2026-11-23 照霜霜给的参考图
// - 侧边栏不是“盖一层遮罩再抽出来”：它平铺在最底下，打开时把整个主界面（连同底部导航）向右推走，
//   主界面像一张卡片：左上、左下是大圆角，上面盖一层半透明遮罩，右边只露出一条。
// - 跟手：从左边缘右滑打开；打开后在任何地方左滑、或点右边露出的主界面关闭。
// - 打开时先收键盘；打开期间主界面里的东西点不到（点它只会关侧边栏）。
// - 侧边栏本身没有阴影、没有抽屉感，底色就是页面底色。
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// 侧边栏的开关。外面拿着它调 [open] / [close]，开合状态变化时通知。
class PushDrawerController extends ChangeNotifier {
  _PushDrawerState? _state;
  bool _isOpen = false;

  /// 侧边栏是不是开着（包括正在打开 / 正在被拖动）。
  bool get isOpen => _isOpen;

  void open() => _state?._animateTo(1);
  void close() => _state?._animateTo(0);

  void _setOpen(bool value) {
    if (_isOpen == value) return;
    _isOpen = value;
    notifyListeners();
  }
}

/// 让里面的页面能打开侧边栏（顶栏的汉堡按钮用）。
class PushDrawerScope extends InheritedWidget {
  const PushDrawerScope({super.key, required this.controller, required super.child});
  final PushDrawerController controller;

  static PushDrawerController? maybeOf(BuildContext context) => context.getInheritedWidgetOfExactType<PushDrawerScope>()?.controller;

  @override
  bool updateShouldNotify(PushDrawerScope old) => controller != old.controller;
}

class PushDrawer extends StatefulWidget {
  const PushDrawer({super.key, required this.drawer, required this.child, this.controller, this.edgeDragEnabled = true, this.handleBack = true});

  /// 右边露出的那一条主界面的宽度。
  static const double kPeek = 82;

  /// 侧边栏最宽这么多（平板上不至于铺满）。
  static const double kMaxWidth = 360;

  /// 主界面被推走后左上、左下的圆角。
  static const double kRadius = 36;

  /// 从左边缘多宽的范围内右滑算“拉出侧边栏”。
  static const double kEdge = 24;

  /// 侧边栏打开后占的宽度（也就是主界面被推走的距离）。
  static double slideFor(double screenWidth) => math.max(0, math.min(screenWidth - kPeek, kMaxWidth));

  final Widget drawer;
  final Widget child;
  final PushDrawerController? controller;

  /// 能不能从左边缘右滑拉出来（终端、低代码画布上有自己的横向手势，那两页关掉）。
  final bool edgeDragEnabled;

  /// 系统返回键先关侧边栏。外面自己接管返回键时传 false。
  final bool handleBack;

  @override
  State<PushDrawer> createState() => _PushDrawerState();
}

class _PushDrawerState extends State<PushDrawer> with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 260));
  PushDrawerController? _ownController;
  PushDrawerController get _controller => widget.controller ?? (_ownController ??= PushDrawerController());
  double _slide = 300;

  @override
  void initState() {
    super.initState();
    _controller._state = this;
    _anim.addListener(_onTick);
  }

  @override
  void didUpdateWidget(PushDrawer old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller?._state = null;
      _controller._state = this;
    }
  }

  @override
  void dispose() {
    if (_controller._state == this) _controller._state = null;
    _ownController?.dispose();
    _anim.dispose();
    super.dispose();
  }

  void _onTick() => _controller._setOpen(_anim.value > 0);

  void _dismissKeyboard() => FocusManager.instance.primaryFocus?.unfocus();

  void _animateTo(double target) {
    if (!mounted) return;
    if (target > 0) _dismissKeyboard();
    _anim.animateTo(target, curve: Curves.easeOutCubic);
  }

  bool _allowDrag(double dx) => _anim.value > 0 || (widget.edgeDragEnabled && dx <= PushDrawer.kEdge);

  void _dragCancel() => _animateTo(_anim.value >= 0.5 ? 1 : 0);

  void _dragStart(DragStartDetails _) {
    _anim.stop();
    _dismissKeyboard();
  }

  void _dragUpdate(DragUpdateDetails d) {
    if (_slide <= 0) return;
    _anim.value = (_anim.value + (d.primaryDelta ?? 0) / _slide).clamp(0.0, 1.0);
  }

  void _dragEnd(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    if (v.abs() > 320) {
      _animateTo(v > 0 ? 1 : 0);
    } else {
      _animateTo(_anim.value >= 0.5 ? 1 : 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final c = context.colors;
    return PushDrawerScope(
      controller: _controller,
      child: LayoutBuilder(
        builder: (context, box) {
          _slide = PushDrawer.slideFor(box.maxWidth);
          return RawGestureDetector(
            behavior: HitTestBehavior.translucent,
            gestures: {
              _SideDragRecognizer: GestureRecognizerFactoryWithHandlers<_SideDragRecognizer>(_SideDragRecognizer.new, (r) {
                r.allow = _allowDrag;
                r.onStart = _dragStart;
                r.onUpdate = _dragUpdate;
                r.onEnd = _dragEnd;
                r.onCancel = _dragCancel;
              }),
            },
            child: AnimatedBuilder(
              animation: _anim,
              // 主界面只建一次，动画只改位移、圆角和遮罩。
              child: widget.child,
              builder: (context, main) {
                final v = _anim.value;
                final open = v > 0;
                final radius = BorderRadius.horizontal(left: Radius.circular(PushDrawer.kRadius * v));
                // 结构固定（开没开都是同一棵树），主界面不会因为开合被重建、丢状态。
                final front = Stack(
                  fit: StackFit.expand,
                  children: [
                    // 打开期间主界面不接手势、不进无障碍树。
                    ExcludeSemantics(
                      excluding: open,
                      child: IgnorePointer(ignoring: open, child: main),
                    ),
                    if (open)
                      Semantics(
                        button: true,
                        label: '关闭侧边栏',
                        child: GestureDetector(
                          key: const ValueKey('push-drawer-scrim'),
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _animateTo(0),
                          child: ColoredBox(color: Colors.black.withValues(alpha: (dark ? 0.45 : 0.2) * v)),
                        ),
                      ),
                  ],
                );
                final card = Transform.translate(
                  key: const ValueKey('push-drawer-main'),
                  offset: Offset(_slide * v, 0),
                  child: ClipRRect(key: const ValueKey('push-drawer-clip'), borderRadius: radius, child: front),
                );
                final stack = Stack(
                  fit: StackFit.expand,
                  children: [
                    if (open)
                      Positioned(
                        left: 0,
                        top: 0,
                        bottom: 0,
                        width: _slide,
                        child: ColoredBox(color: c.bg, child: widget.drawer),
                      ),
                    card,
                  ],
                );
                return ColoredBox(
                  color: c.bg,
                  child: widget.handleBack
                      ? PopScope(
                          canPop: !open,
                          onPopInvokedWithResult: (didPop, _) {
                            if (!didPop) _animateTo(0);
                          },
                          child: stack,
                        )
                      : stack,
                );
              },
            ),
          );
        },
      ),
    );
  }
}

/// 只认“允许的起点”的横向拖动：侧边栏开着时哪里都行，关着时只认左边缘。
class _SideDragRecognizer extends HorizontalDragGestureRecognizer {
  bool Function(double dx) allow = (_) => false;

  @override
  bool isPointerAllowed(PointerEvent event) => allow(event.position.dx) && super.isPointerAllowed(event);
}
