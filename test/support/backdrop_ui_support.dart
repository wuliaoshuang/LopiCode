// 背景图片界面测试共用的小工具：往测试环境里放一张背景、抓屏幕像素、等到某个控件出现。
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/backdrop/backdrop_model.dart';
import 'package:lopicode/backdrop/backdrop_picker.dart';
import 'package:lopicode/backdrop/backdrop_store.dart';
import 'package:lopicode/backdrop/crop_math.dart';
import 'package:lopicode/core/safe_file.dart';
import 'package:lopicode/state/backdrop_state.dart';
import 'package:lopicode/ui/backdrop_images.dart';

import 'backdrop_fakes.dart';
import 'harness.dart';

BackdropNotifier backdropOf(TestEnv env) => env.services.container.read(backdropProvider.notifier);
BackdropSettings backdropStateOf(TestEnv env) => env.services.container.read(backdropProvider);
BackdropStore backdropStoreOf(TestEnv env) => env.services.container.read(backdropStoreProvider);

/// 装上假的选图（按脚本交结果），返回它好数被叫了几次。
FakeBackdropPicker useFakePicker(TestEnv env, [List<BackdropPick>? script]) {
  final picker = FakeBackdropPicker(script);
  env.services.container.read(backdropPickerProvider.notifier).use(picker);
  return picker;
}

/// 往测试环境里放好一张背景（代码画的图，走真的入库流程），并且先把图解好——之后一摆出来就有背景。
Future<ImportedBackdrop> seedBackdrop(
  WidgetTester tester,
  TestEnv env, {
  bool dark = false,
  int width = 390,
  int height = 844,
  bool scene = false,
  BackdropLook Function(BackdropLook l)? look,
  BackdropSettings Function(BackdropSettings s)? settings,
}) async {
  late ImportedBackdrop img;
  await tester.runAsync(() async {
    final n = backdropOf(env);
    await n.ready;
    final bytes = scene ? await makeScenePng(width, height) : await makePng(width, height);
    useFakePicker(env, [BackdropPicked(writePick(env.tmp, 'seed-$width-$height-${scene ? 's' : 'q'}.png', bytes))]);
    img = ((await n.pickAndImport()) as BackdropImportOk).image;
    if (settings != null) n.update(settings, persist: false);
    await n.setImage(dark: dark, image: img, crop: CropRect.full);
    if (look != null) n.updateLook(dark: dark, change: look);
    await pendingWrites();
  });
  // 解码从测试时钟这边发起，再一小步一小步等到解好
  final path = backdropStoreOf(env).imageFile(img.file).path;
  unawaited(BackdropImages.instance.load(path)); // 结果用下面的 peek 看
  for (var i = 0; i < 60 && BackdropImages.instance.peek(path) == null; i++) {
    await settle(tester, rounds: 1);
  }
  expect(BackdropImages.instance.peek(path), isNotNull, reason: '测试用的背景图没解出来');
  return img;
}

/// 抓一帧屏幕（1 倍，390×844），之后用 [pixel] 取点。
Future<ByteData> grab(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(shotKey));
  late ByteData data;
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    data = (await image.toByteData())!;
    image.dispose();
  });
  return data;
}

ui.Color pixel(ByteData data, int x, int y, {int width = 390}) {
  final i = (y * width + x) * 4;
  return ui.Color.fromARGB(data.getUint8(i + 3), data.getUint8(i), data.getUint8(i + 1), data.getUint8(i + 2));
}

int _ch(double v) => (v * 255).round();

/// 两个颜色差不多（每个通道差不超过 [tolerance]）。
Matcher nearColor(ui.Color want, {int tolerance = 8}) => predicate<ui.Color>(
  (c) => (_ch(c.r) - _ch(want.r)).abs() <= tolerance && (_ch(c.g) - _ch(want.g)).abs() <= tolerance && (_ch(c.b) - _ch(want.b)).abs() <= tolerance && (_ch(c.a) - _ch(want.a)).abs() <= tolerance,
  '接近 $want',
);

// makePng 的四块颜色
const ui.Color kRed = ui.Color(0xFFD23A3A);
const ui.Color kGreen = ui.Color(0xFF2FA35B);
const ui.Color kBlue = ui.Color(0xFF2E5FD0);
const ui.Color kYellow = ui.Color(0xFFE8B923);

/// 一直等到 [finder] 找得到（真实文件读写、图片解码要“真等”）。等不到就让断言去报错。
Future<void> pumpUntil(WidgetTester tester, Finder finder, {int tries = 40}) async {
  for (var i = 0; i < tries && finder.evaluate().isEmpty; i++) {
    await settle(tester, rounds: 1);
  }
}

/// 相对亮度和对比度（WCAG 的算法），用来判断“字读不读得清”。
double luminance(ui.Color c) => c.computeLuminance();
double contrast(ui.Color a, ui.Color b) {
  final la = luminance(a), lb = luminance(b);
  return (la > lb ? la + 0.05 : lb + 0.05) / (la > lb ? lb + 0.05 : la + 0.05);
}
