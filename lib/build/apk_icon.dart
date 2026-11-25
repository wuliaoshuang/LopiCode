// 把用户选的一张图变成安装包要的五张图标：解码 → 居中裁成正方形 → 缩成 48 / 72 / 96 / 144 / 192 的 PNG。
// 用引擎自带的解码和绘制（dart:ui），不加依赖。纯逻辑（不 import 界面库）。
//
// 自定的门槛：原图短边至少 [kIconMinSide] 像素（最大的一张图标就是 192，比它小的图放大了会糊）。
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:lopicode/build/local_pack_form.dart';

const int kIconMinSide = 192;

/// 图不能用的原因（[message] 是直接给用户看的大白话）。
class ApkIconException implements Exception {
  const ApkIconException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// 返回 边长 → PNG。解码失败、图太小抛 [ApkIconException]。
Future<Map<int, Uint8List>> makeApkIcons(Uint8List source) async {
  if (source.isEmpty) throw const ApkIconException('这个文件是空的，换一张图试试。');
  ui.Image image;
  try {
    final codec = await ui.instantiateImageCodec(source);
    image = (await codec.getNextFrame()).image;
    codec.dispose();
  } catch (_) {
    // 引擎解不了：不是图片，或者是它不认识的格式。
    throw const ApkIconException('这张图打不开：可能不是图片，或者格式不支持。换一张 PNG 或 JPG 试试。');
  }
  try {
    final side = image.width < image.height ? image.width : image.height;
    if (side < kIconMinSide) {
      throw ApkIconException('这张图太小了（${image.width}×${image.height}）。图标至少要 $kIconMinSide×$kIconMinSide，换一张大一点的。');
    }
    final src = ui.Rect.fromLTWH((image.width - side) / 2, (image.height - side) / 2, side.toDouble(), side.toDouble());
    final out = <int, Uint8List>{};
    for (final size in kApkIconSizes) {
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder).drawImageRect(image, src, ui.Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()), ui.Paint()..filterQuality = ui.FilterQuality.high);
      final picture = recorder.endRecording();
      final scaled = await picture.toImage(size, size);
      picture.dispose();
      final data = await scaled.toByteData(format: ui.ImageByteFormat.png);
      scaled.dispose();
      if (data == null) throw const ApkIconException('这张图处理不了，换一张试试。');
      out[size] = data.buffer.asUint8List();
    }
    return out;
  } finally {
    image.dispose();
  }
}
