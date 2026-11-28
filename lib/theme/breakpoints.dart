// 设计约束（宽度分档 · 全应用只有这一处）— 2026-11-28 霜霜：“适配平板”
// - 三档，看的是**窗口宽度**（逻辑像素），不是设备类型：分屏、横竖屏切换、拖窗口都跟着变。
//   窄 ＜600（手机，样子一点不变）；中 600–839（平板竖屏、分屏）；宽 ≥840（平板横屏）。
// - 别处不许自己写 600 / 840 这些数，一律问这里。
// - 限宽（[ContentWidth]）不看档位，只看自己拿到的宽度：放在分栏的某一栏里也对。树的形状永远一样（只改两边留白），
//   所以窗口宽度变来变去时里面的页面不会被重建、不丢输入的字和滚动位置；宽度没超过上限时和没包这一层完全一样。
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// 窗口宽度的三档。
enum WidthClass {
  /// 窄：手机。
  compact,

  /// 中：平板竖屏、分屏。
  medium,

  /// 宽：平板横屏。
  expanded;

  bool get isCompact => this == compact;
  bool get isExpanded => this == expanded;
}

abstract final class Breakpoints {
  /// 到这个宽度算“中”。
  static const double medium = 600;

  /// 到这个宽度算“宽”。
  static const double expanded = 840;

  /// 一列正文（表单、设置、列表页）最宽多少。
  static const double page = 720;

  /// 对话的消息和输入栏最宽多少（一行字不横跨整个平板）。
  static const double reading = 760;

  /// 底部弹层、表单类对话框最宽多少。
  static const double sheet = 640;

  /// 左侧竖排导航的宽度。
  static const double rail = 80;

  /// 常驻在左边的侧栏（对话列表、文件树、设置清单）的宽度。
  static const double side = 300;

  static WidthClass forWidth(double width) => width >= expanded ? WidthClass.expanded : (width >= medium ? WidthClass.medium : WidthClass.compact);

  /// 当前窗口是哪一档（只订阅窗口大小，别的环境变化不会让调用方重建）。
  static WidthClass of(BuildContext context) => forWidth(MediaQuery.sizeOf(context).width);
}

/// 把内容限制在 [maxWidth] 以内并居中；拿到的宽度没超过上限时原样铺满。
class ContentWidth extends StatelessWidget {
  const ContentWidth({super.key, this.maxWidth = Breakpoints.page, required this.child});
  final double maxWidth;
  final Widget child;

  /// 在宽度 [width] 里限宽以后，两边各留多少。
  static double marginFor(double width, [double maxWidth = Breakpoints.page]) => width.isFinite ? math.max(0, (width - maxWidth) / 2) : 0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => Padding(
      padding: EdgeInsets.symmetric(horizontal: marginFor(box.maxWidth, maxWidth)),
      child: child,
    ),
  );
}
