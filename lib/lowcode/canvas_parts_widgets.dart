// 设计约束（低代码 · 画布上的小零件）
// - 空容器的提示：一块 48 高的浅色框，写着“空的 · 拖组件到这里”。拖动时页面里不再插任何占位（第 5 版第 1 期）。
// - 角标：贴在组件左上角的一小块字（“已隐藏”“绝对定位”），不挡选中。
// - 安静的 Flex：内容比盒子大时照样画出去（和网页里 overflow: visible 一样），不画黄黑警示条。
import 'package:flutter/rendering.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// 空容器里的提示。拖东西到它上面时，整块高亮由画布叠在上面画（canvas_drag_widgets.dart），这里不变。
class CanvasEmptyHint extends StatelessWidget {
  const CanvasEmptyHint({super.key});

  @override
  Widget build(BuildContext context) => Container(
    height: 48,
    constraints: const BoxConstraints(minWidth: 48),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: const Color(0x0F000000),
      borderRadius: BorderRadius.circular(Radii.sm),
      border: Border.all(color: Palette.neutral300),
    ),
    child: const Text('空的 · 拖组件到这里', style: TextStyle(fontSize: 12, color: Palette.neutral600)),
  );
}

/// 贴在组件左上角的小角标。
class CanvasBadge extends StatelessWidget {
  const CanvasBadge(this.label, {super.key});
  final String label;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: const BoxDecoration(
        color: Color(0xCC27282F),
        borderRadius: BorderRadius.only(bottomRight: Radius.circular(4)),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 10, height: 1.3, color: Colors.white, fontWeight: FontWeight.w400, decoration: TextDecoration.none, letterSpacing: 0),
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
