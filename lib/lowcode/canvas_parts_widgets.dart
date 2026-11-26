// 设计约束（低代码 · 画布上的小零件）
// - 空容器的提示：一块 48 高的浅色框，写着“空的 · 拖组件到这里”。拖动时页面里不再插任何占位（第 5 版第 1 期）。
// - 角标：贴在组件左上角的一小块字（“已隐藏”“绝对定位”），不挡选中。
// - 安静的 Flex：内容比盒子大时照样画出去（和网页里 overflow: visible 一样），不画黄黑警示条。
import 'dart:io';

import 'package:flutter/rendering.dart';
import 'package:lopicode/lowcode/image_assets.dart';
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

/// 画布上认“项目里的图片”靠它：把图片组件写的相对地址换成真实文件路径（换不了返回 null＝坏图）。
/// 搭建页把它套在搭建台外面；没套（比如只是看一眼的预览）时相对地址一律显示成坏图。
class LcImageScope extends InheritedWidget {
  const LcImageScope({super.key, required this.resolve, required super.child});
  final String? Function(String src) resolve;

  static String? Function(String src)? of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<LcImageScope>()?.resolve;

  @override
  bool updateShouldNotify(LcImageScope old) => false;
}

/// 画布上的一张图片：网址走网络，相对地址走项目里的文件；没填是占位，读不出来是坏图。
/// 填充方式（object-fit）和宽高比（aspect-ratio）照样式里写的画，和导出的网页一致。
class CanvasImage extends StatelessWidget {
  const CanvasImage({super.key, required this.src, required this.width, required this.height, required this.style, this.background});
  final String? src;
  final double? width;
  final double? height;
  final Map<String, String> style;
  final Color? background;

  /// `aspect-ratio: 16 / 9`、`1`、`1.5` → 宽 ÷ 高；写得不认识返回 null。
  static double? ratioOf(String? css) {
    final m = RegExp(r'^\s*([0-9.]+)\s*(?:/\s*([0-9.]+))?\s*$').firstMatch(css ?? '');
    if (m == null) return null;
    final a = double.tryParse(m[1]!), b = m[2] == null ? 1.0 : double.tryParse(m[2]!);
    return a == null || b == null || a <= 0 || b <= 0 ? null : a / b;
  }

  @override
  Widget build(BuildContext context) {
    final fit = switch (style['object-fit']?.trim()) {
      'contain' => BoxFit.contain,
      'fill' => BoxFit.fill,
      'none' => BoxFit.none,
      'scale-down' => BoxFit.scaleDown,
      _ => BoxFit.cover,
    };
    final ratio = height == null ? ratioOf(style['aspect-ratio']) : null;
    Widget sized(Widget child) => ratio == null
        ? child
        : SizedBox(
            width: width,
            child: AspectRatio(aspectRatio: ratio, child: child),
          );
    Widget placeholder(IconData icon) => sized(
      Container(
        height: ratio == null ? height : null,
        width: width,
        color: background ?? Palette.neutral200,
        alignment: Alignment.center,
        child: Icon(icon, color: Palette.neutral500),
      ),
    );
    final s = src;
    if (s == null) return placeholder(Icons.image_outlined);
    Widget broken(BuildContext _, Object _, StackTrace? _) => placeholder(Icons.broken_image_outlined);
    final h = ratio == null ? height : null;
    if (lcIsRemoteSrc(s)) return sized(Image.network(s, height: h, width: width, fit: fit, errorBuilder: broken));
    final path = LcImageScope.of(context)?.call(s);
    if (path == null) return placeholder(Icons.broken_image_outlined);
    return sized(Image.file(File(path), height: h, width: width, fit: fit, errorBuilder: broken));
  }
}
