/// 画布的缩放范围、屏宽档、“此刻怎么摆”（不带界面）。
library;

import 'dart:ui';

import 'package:flutter/foundation.dart';

const double kCanvasMinScale = 0.25;
const double kCanvasMaxScale = 3;
const List<double> kCanvasZoomSteps = [0.25, 0.5, 0.75, 1, 1.5, 2, 3];

/// 页面宽度的预设；0＝自适应（跟可视区一样宽）。
const List<int> kCanvasWidthPresets = [0, 360, 390, 768];

/// 屏宽档的叫法（顶栏小字、选择面板共用）。
String canvasWidthLabel(int preset) => preset == 0 ? '自适应' : '$preset 宽';

/// 画布此刻怎么摆：缩放比例，和页面左上角在可视区里的位置（屏幕像素）。
@immutable
class CanvasViewport {
  const CanvasViewport(this.scale, this.offset);
  final double scale;
  final Offset offset;

  @override
  bool operator ==(Object other) => other is CanvasViewport && other.scale == scale && other.offset == offset;

  @override
  int get hashCode => Object.hash(scale, offset);
}
