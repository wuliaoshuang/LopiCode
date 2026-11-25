// 背景图片的解码缓存和“模糊好的小图”缓存（界面层；全应用一份）。
//
// - 同一个文件只解码一次：解好的图按路径记着，各页面共用，切页面不用重新解、不闪。
//   最多记 [kMaxSources] 张（浅色、深色各一张 + 裁剪页临时的一张），多了丢最久没用的。
// - 模糊不每帧算：按“哪张图、哪块区域、多糊”预先画一张**缩小的**模糊图记着（模糊本来就没细节，
//   缩小到模糊半径约 4 像素的分辨率就够，画的时候再放大），之后每帧只是贴一张小图。
// - 被挤出缓存的图不主动 dispose（可能还有画面正用着它），交给系统回收。
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:lopicode/backdrop/crop_math.dart';

/// 模糊小图里，模糊半径最多占几个像素（越小图越小、越省，太小会看出马赛克）。
const double kBlurSigmaPixels = 4;

class BackdropImages {
  BackdropImages._();
  static final BackdropImages instance = BackdropImages._();

  static const int kMaxSources = 3;
  static const int kMaxBlurred = 6;

  final Map<String, ui.Image> _sources = {};
  final Map<String, Future<ui.Image?>> _loading = {};
  final Map<String, ui.Image> _blurred = {};

  /// 解了几次码（测试用来确认“同一张图只解一次”）。
  int decodeCount = 0;

  /// 算了几张模糊图（测试用来确认“不是每帧重算”）。
  int blurCount = 0;

  /// 已经解好的图；没解好返回 null（调用方去 [load]）。
  ui.Image? peek(String path) {
    final img = _sources.remove(path);
    if (img != null) _sources[path] = img; // 挪到最新
    return img;
  }

  /// 解码（同一个文件同时只解一次）。文件没了 / 坏了返回 null，不抛错。
  Future<ui.Image?> load(String path) {
    final have = peek(path);
    if (have != null) return Future.value(have);
    // whenComplete 的回调不能把 remove 的返回值（就是这个 Future 自己）交回去，否则它会等自己、永远完不成
    return _loading[path] ??= _decode(path).whenComplete(() {
      _loading.remove(path);
    });
  }

  Future<ui.Image?> _decode(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final ui.Image image;
      try {
        image = (await codec.getNextFrame()).image;
      } finally {
        codec.dispose();
      }
      decodeCount++;
      _sources[path] = image;
      while (_sources.length > kMaxSources) {
        _sources.remove(_sources.keys.first);
      }
      return image;
    } on Exception {
      // 文件没了或者解不开：当作没有背景（设置页会显示“图片读不出来”）
      return null;
    }
  }

  /// [source] 上 [region]（旋转 [turns] 之后的像素坐标）这一块，按屏幕上 [sigma] 逻辑像素的模糊半径糊好的小图。
  /// [shownWidth] 是这一块在屏幕上显示成多宽（逻辑像素），用来把模糊半径换算到小图上。
  ui.Image blurred({required String path, required ui.Image source, required int turns, required Rect region, required double sigma, required double shownWidth}) {
    // 小图每个像素对应屏幕上多少逻辑像素：让模糊半径在小图上约等于 kBlurSigmaPixels
    final perPixel = math.max(sigma / kBlurSigmaPixels, shownWidth / region.width);
    final w = math.max(8, (shownWidth / perPixel).round());
    final h = math.max(8, (w * region.height / region.width).round());
    final key = '$path|$turns|${region.left.round()},${region.top.round()},${region.width.round()},${region.height.round()}|${sigma.round()}|$w';
    final have = _blurred.remove(key);
    if (have != null) {
      _blurred[key] = have;
      return have;
    }
    // 第一步：把这一块缩小画出来
    final r1 = ui.PictureRecorder();
    final c1 = Canvas(r1);
    paintBackdropRegion(c1, source, turns: turns, region: region, dst: Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()));
    final p1 = r1.endRecording();
    final small = p1.toImageSync(w, h);
    p1.dispose();
    // 第二步：在小图上做模糊（边缘按最外一圈像素延伸，不发黑、不透明）
    final r2 = ui.PictureRecorder();
    final c2 = Canvas(r2);
    final s = sigma / perPixel;
    c2.drawImage(small, Offset.zero, Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: s, sigmaY: s, tileMode: TileMode.clamp));
    final p2 = r2.endRecording();
    final out = p2.toImageSync(w, h);
    p2.dispose();
    small.dispose();
    blurCount++;
    _blurred[key] = out;
    while (_blurred.length > kMaxBlurred) {
      _blurred.remove(_blurred.keys.first);
    }
    return out;
  }

  /// 文件删掉以后把它从缓存里拿掉。
  void forget(String path) {
    _sources.remove(path);
    _blurred.removeWhere((k, _) => k.startsWith('$path|'));
  }

  /// 全清（测试收尾用）。
  void clear() {
    _sources.clear();
    _blurred.clear();
    _loading.clear();
    decodeCount = 0;
    blurCount = 0;
  }
}

/// 裁剪区域换成旋转后图片上的像素矩形。
Rect cropPixels(CropRect crop, {required int rotatedWidth, required int rotatedHeight}) =>
    Rect.fromLTWH(crop.left * rotatedWidth, crop.top * rotatedHeight, math.max(1, crop.width * rotatedWidth), math.max(1, crop.height * rotatedHeight));

/// 把 [image] 顺时针转 [turns] 个 90° 之后的 [region]（像素）这一块，画进 [dst]。
void paintBackdropRegion(Canvas canvas, ui.Image image, {required int turns, required Rect region, required Rect dst, bool clip = true}) {
  final w = image.width.toDouble();
  final h = image.height.toDouble();
  canvas.save();
  if (clip) canvas.clipRect(dst);
  canvas.translate(dst.left, dst.top);
  canvas.scale(dst.width / region.width, dst.height / region.height);
  canvas.translate(-region.left, -region.top);
  switch (turns % 4) {
    case 1:
      canvas.translate(h, 0);
      canvas.rotate(math.pi / 2);
    case 2:
      canvas.translate(w, h);
      canvas.rotate(math.pi);
    case 3:
      canvas.translate(0, w);
      canvas.rotate(-math.pi / 2);
  }
  canvas.drawImage(image, Offset.zero, Paint()..filterQuality = FilterQuality.medium);
  canvas.restore();
}
