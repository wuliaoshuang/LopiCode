// 设计约束（低代码 · 画布上的小零件）
// - 插入位：平时不占地方（子项之间的间距由容器自己留）；拖动时才出现，悬停时变成加粗的色条。
// - 角标：贴在组件左上角的一小块字（“已隐藏”“绝对定位”），不挡选中。
// - 安静的 Flex：内容比盒子大时照样画出去（和网页里 overflow: visible 一样），不画黄黑警示条。
import 'package:flutter/rendering.dart';
import 'package:lopicode/lowcode/palette_widgets.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// 一个插入位。
class CanvasSlot extends StatelessWidget {
  const CanvasSlot({
    super.key,
    required this.parentId,
    required this.index,
    required this.vertical,
    required this.idle,
    required this.dragging,
    required this.onDrop,
    required this.canDrop,
    this.emptyHint = false,
  });

  final String parentId;
  final int index;

  /// true = 竖条（在行里）。
  final bool vertical;

  /// 不拖动时占的尺寸（＝容器的间距）。
  final double idle;
  final bool dragging;
  final bool emptyHint;
  final void Function(LcDrag, String, int) onDrop;
  final bool Function(LcDrag, String) canDrop;

  @override
  Widget build(BuildContext context) {
    return DragTarget<LcDrag>(
      onWillAcceptWithDetails: (d) => canDrop(d.data, parentId),
      onAcceptWithDetails: (d) => onDrop(d.data, parentId, index),
      builder: (context, candidates, _) {
        final hover = candidates.isNotEmpty;
        final ui = context.themeSpec;
        if (emptyHint) {
          return Container(
            height: 48,
            constraints: const BoxConstraints(minWidth: 48),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: ui.lowcodeColor(hover ? LowcodeKey.dropHoverBg : LowcodeKey.dropIdleBg),
              borderRadius: BorderRadius.circular(Radii.sm),
              border: Border.all(color: ui.lowcodeColor(hover ? LowcodeKey.dropHoverBorder : LowcodeKey.dropIdleBorder)),
            ),
            child: Text(hover ? '松手放进来' : '空的 · 拖组件到这里', style: TextStyle(fontSize: 12, color: ui.lowcodeColor(LowcodeKey.dropText))),
          );
        }
        final size = dragging ? (idle < 20 ? 20.0 : idle) : idle;
        final bar = AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: vertical ? size : null,
          height: vertical ? null : size,
          constraints: vertical ? const BoxConstraints(minHeight: 24) : null,
          alignment: Alignment.center,
          child: dragging
              ? Container(
                  width: vertical ? (hover ? 6 : 2) : double.infinity,
                  height: vertical ? double.infinity : (hover ? 6 : 2),
                  constraints: vertical ? const BoxConstraints(minHeight: 24, maxHeight: 64) : null,
                  decoration: BoxDecoration(color: ui.lowcodeColor(hover ? LowcodeKey.insertBar : LowcodeKey.insertBarIdle), borderRadius: BorderRadius.circular(3)),
                )
              : null,
        );
        return bar;
      },
    );
  }
}

/// 贴在组件左上角的小角标。
class CanvasBadge extends StatelessWidget {
  const CanvasBadge(this.label, {super.key});
  final String label;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: context.themeSpec.lowcodeColor(LowcodeKey.sizeTagBg),
        borderRadius: const BorderRadius.only(bottomRight: Radius.circular(4)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, height: 1.3, color: context.themeSpec.lowcodeColor(LowcodeKey.sizeTagText), fontWeight: FontWeight.w400, decoration: TextDecoration.none, letterSpacing: 0),
      ),
    ),
  );
}

/// 和 [Flex] 一样排版，但内容超出时不报“溢出”、不画警示条：
/// 用户给组件设了固定宽高（或拖小了）以后内容放不下是正常情况，网页里默认也是照样画出去。
class QuietFlex extends Flex {
  const QuietFlex({
    super.key,
    required super.direction,
    super.mainAxisAlignment,
    super.mainAxisSize,
    super.crossAxisAlignment,
    super.textDirection,
    super.verticalDirection,
    super.spacing,
    super.children,
  });

  @override
  RenderFlex createRenderObject(BuildContext context) => _RenderQuietFlex(
    direction: direction,
    mainAxisAlignment: mainAxisAlignment,
    mainAxisSize: mainAxisSize,
    crossAxisAlignment: crossAxisAlignment,
    textDirection: getEffectiveTextDirection(context),
    verticalDirection: verticalDirection,
    textBaseline: textBaseline,
    clipBehavior: clipBehavior,
    spacing: spacing,
  );
}

class _RenderQuietFlex extends RenderFlex {
  _RenderQuietFlex({
    super.direction,
    super.mainAxisAlignment,
    super.mainAxisSize,
    super.crossAxisAlignment,
    super.textDirection,
    super.verticalDirection,
    super.textBaseline,
    super.clipBehavior,
    super.spacing,
  });

  // 父类在这里发现溢出会画警示条并记一条错误；这里只管把子项画出来。
  @override
  void paint(PaintingContext context, Offset offset) => defaultPaint(context, offset);
}
