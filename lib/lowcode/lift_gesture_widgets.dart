// 设计约束（低代码 · “长按拿起来”的手势，画布上的组件和组件盒里的格子共用）
// - 手感和积木画布（lib/blocks/block_editor_canvas_view.dart）对齐：按住不动满 280 毫秒＝拿起；
//   拿起之前手指挪动超过 8 像素＝不是长按（让给平移 / 滚动）。两个数直接引用积木画布的常量，那边改了这边跟着变。
// - 拿起以后手指怎么动都归这次拖动，直到松手 / 被系统打断。
// - 震动也照积木画布：拿起中等、经过一个新的可放位置轻（选择那一下）、放下轻、丢进删除区重。
//   用 Flutter 自带的 HapticFeedback，不等它返回；系统关了“触摸反馈”时它自己不响。
import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:lopicode/blocks/block_editor_canvas_view.dart';
import 'package:material_ui/material_ui.dart';

/// 按住多久算长按（＝积木画布的）。
const Duration kLcLiftAfter = BkEditorCanvas.longPressAfter;

/// 手指挪了多远就不算长按了（＝积木画布的）。
const double kLcLiftSlop = BkEditorCanvas.dragSlop;

/// 搭建页拖动时的几种震动。
abstract final class LcHaptics {
  static void lift() => unawaited(HapticFeedback.mediumImpact()); // 不等：震动只是手感，成不成都不影响拖动
  static void overTarget() => unawaited(HapticFeedback.selectionClick()); // 同上
  static void drop() => unawaited(HapticFeedback.lightImpact()); // 同上
  static void delete() => unawaited(HapticFeedback.heavyImpact()); // 同上
}

/// 长按拿起 → 跟手 → 松手。位置都是屏幕坐标。
class LcLiftRecognizer extends PrimaryPointerGestureRecognizer {
  LcLiftRecognizer({super.debugOwner}) : super(deadline: kLcLiftAfter, preAcceptSlopTolerance: kLcLiftSlop, postAcceptSlopTolerance: null);

  void Function(Offset global)? onLift;
  void Function(Offset global)? onMove;
  void Function()? onDrop;
  void Function()? onCancel;

  bool _lifted = false;
  Offset _last = Offset.zero;

  @override
  void didExceedDeadline() {
    // 按够了：这次手势归我（画布的平移、列表的滚动都让开）。
    resolve(GestureDisposition.accepted);
    _lifted = true;
    _last = initialPosition?.global ?? _last;
    onLift?.call(_last);
  }

  @override
  void handlePrimaryPointer(PointerEvent event) {
    if (!_lifted) {
      // 还没按够就松手：不是长按（是点一下，交给别的手势）。
      if (event is PointerUpEvent) resolve(GestureDisposition.rejected);
      return;
    }
    if (event is PointerMoveEvent) {
      _last = event.position;
      onMove?.call(_last);
    } else if (event is PointerUpEvent) {
      _lifted = false;
      onDrop?.call();
    } else if (event is PointerCancelEvent) {
      _lifted = false;
      onCancel?.call();
    }
  }

  @override
  void rejectGesture(int pointer) {
    if (_lifted) {
      _lifted = false;
      onCancel?.call();
    }
    super.rejectGesture(pointer);
  }

  @override
  void dispose() {
    if (_lifted) {
      _lifted = false;
      onCancel?.call();
    }
    super.dispose();
  }

  @override
  String get debugDescription => 'lc-lift';
}

/// 给 [child] 加上“长按拿起来”。点一下之类的别的手势照常交给 [child] 里面 / 外面的控件。
class LcLiftDetector extends StatelessWidget {
  const LcLiftDetector({super.key, required this.onLift, required this.onMove, required this.onDrop, required this.onCancel, required this.child, this.behavior});

  final void Function(Offset global) onLift;
  final void Function(Offset global) onMove;
  final VoidCallback onDrop;
  final VoidCallback onCancel;
  final HitTestBehavior? behavior;
  final Widget child;

  @override
  Widget build(BuildContext context) => RawGestureDetector(
    behavior: behavior,
    gestures: {
      LcLiftRecognizer: GestureRecognizerFactoryWithHandlers<LcLiftRecognizer>(
        () => LcLiftRecognizer(debugOwner: this),
        (r) => r
          ..onLift = onLift
          ..onMove = onMove
          ..onDrop = onDrop
          ..onCancel = onCancel,
      ),
    },
    child: child,
  );
}
