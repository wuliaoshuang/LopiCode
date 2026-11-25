// 背景图片和主题导入导出的对接（lib/backdrop/backdrop_theme_bridge.dart）、外观页那一行的状态文字。
// 图片都是代码生成的小图。
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/backdrop/backdrop_model.dart';
import 'package:lopicode/backdrop/backdrop_picker.dart';
import 'package:lopicode/backdrop/backdrop_store.dart';
import 'package:lopicode/backdrop/backdrop_theme_bridge.dart';
import 'package:lopicode/backdrop/crop_math.dart';
import 'package:lopicode/core/safe_file.dart';
import 'package:lopicode/core/stores.dart';
import 'package:lopicode/state/app_providers.dart';
import 'package:lopicode/state/backdrop_state.dart';
import 'package:path/path.dart' as p;
import 'package:riverpod/riverpod.dart';

import 'support/backdrop_fakes.dart';

/// 一张全是随机噪点的 PNG（压不动，用来凑“太大”）。
Future<Uint8List> makeNoisePng(int width, int height) async {
  final rnd = math.Random(7);
  final pixels = Uint8List(width * height * 4);
  for (var i = 0; i < pixels.length; i++) {
    pixels[i] = i % 4 == 3 ? 255 : rnd.nextInt(256);
  }
  final buf = await ui.ImmutableBuffer.fromUint8List(pixels);
  final desc = ui.ImageDescriptor.raw(buf, width: width, height: height, pixelFormat: ui.PixelFormat.rgba8888);
  final codec = await desc.instantiateCodec();
  final img = (await codec.getNextFrame()).image;
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  img.dispose();
  codec.dispose();
  desc.dispose();
  buf.dispose();
  return data!.buffer.asUint8List();
}

void expectCrop(CropRect a, CropRect b) {
  expect(a.left, closeTo(b.left, 1e-9));
  expect(a.top, closeTo(b.top, 1e-9));
  expect(a.width, closeTo(b.width, 1e-9));
  expect(a.height, closeTo(b.height, 1e-9));
}

void main() {
  test('裁剪区域在“旋转后”和“原图”之间换算：四个方向来回不变；转 90° 后左上那一块在原图的左下', () {
    const r = CropRect(0.1, 0.2, 0.3, 0.4);
    for (var t = 0; t < 4; t++) {
      expectCrop(cropFromOriginal(cropToOriginal(r, t), t), r);
      final o = cropToOriginal(r, t);
      expect(o.left >= 0 && o.top >= 0 && o.right <= 1 + 1e-9 && o.bottom <= 1 + 1e-9, isTrue);
    }
    expectCrop(cropToOriginal(r, 0), r);
    // 顺时针转 90°：原图的左下角到了左上角
    expectCrop(cropToOriginal(const CropRect(0, 0, 0.25, 0.5), 1), const CropRect(0, 0.75, 0.5, 0.25));
    expectCrop(cropToOriginal(const CropRect(0, 0, 0.25, 0.5), 2), const CropRect(0.75, 0.5, 0.25, 0.5));
    // 逆时针转 90°（转三次）：原图的右上角到了左上角
    expectCrop(cropToOriginal(const CropRect(0, 0, 0.25, 0.5), 3), const CropRect(0.5, 0, 0.5, 0.25));
  });

  group('和主题导入导出对接', () {
    late Directory tmp;
    late ProviderContainer container;
    late FakeBackdropPicker picker;

    ProviderContainer open(String name) {
      final c = ProviderContainer(overrides: [settingsStoreProvider.overrideWithValue(SettingsStore(File(p.join(tmp.path, name, 'settings.json'))))]);
      c.read(backdropPickerProvider.notifier).use(picker);
      return c;
    }

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('lopi_bgt_');
      picker = FakeBackdropPicker();
      container = open('a');
    });
    tearDown(() async {
      container.dispose();
      await pendingWrites();
      tmp.deleteSync(recursive: true);
    });

    BackdropNotifier n() => container.read(backdropProvider.notifier);
    BackdropSettings s() => container.read(backdropProvider);
    BackdropStore store() => container.read(backdropStoreProvider);
    List<String> files(ProviderContainer c) {
      final d = c.read(backdropStoreProvider).imageDir;
      return d.existsSync() ? [for (final e in d.listSync()) p.basename(e.path)] : [];
    }

    Future<void> seed(Uint8List bytes, {CropRect crop = const CropRect(0.25, 0, 0.5, 1), int turns = 0}) async {
      await n().ready;
      picker.script.add(BackdropPicked(writePick(tmp, 'pick.png', bytes)));
      final img = ((await n().pickAndImport()) as BackdropImportOk).image;
      await n().setImage(dark: false, image: img, crop: crop, turns: turns);
    }

    test('没有图：导出说明带不上', () async {
      final r = await n().exportForTheme(dark: false);
      expect(r.data, isNull);
      expect(r.error, contains('没有背景图片'));
    });

    test('导出：字段照主题那边的名字；没转过的图原样带上；另一台设备导入后图、裁剪、效果都一样', () async {
      await seed(await makePng(80, 60), crop: const CropRect(0.1, 0.2, 0.3, 0.4));
      n().updateLook(dark: false, change: (l) => l.copyWith(maskOpacity: 35, blur: 12, brightness: -20, fit: BackdropFit.tile, tilePercent: 40, maskFollowsTheme: false, maskColor: 0xFF1B2A4A));
      final r = await n().exportForTheme(dark: false);
      expect(r.error, isNull);
      expect(r.notes, isEmpty);
      final d = r.data!;
      expect(d['mime'], 'image/png');
      expect(d['bytes'], isA<Uint8List>());
      expect(d['bytes'], await store().imageFile(s().light.file!).readAsBytes(), reason: '没转过、没超限：文件原样带上');
      expectCrop(CropRect(d['cropX']! as double, d['cropY']! as double, d['cropW']! as double, d['cropH']! as double), const CropRect(0.1, 0.2, 0.3, 0.4));
      expect(d['dim'], 0.35);
      expect(d['blur'], 12.0);
      expect((d['turns'], d['fit'], d['tile'], d['maskColor'], d['brightness']), (0, 'tile', 40, 0x1B2A4A, -20));

      final other = open('b');
      addTearDown(other.dispose);
      expect(await other.read(backdropProvider.notifier).applyThemeBackground(d), isNull);
      final got = other.read(backdropProvider);
      expect(got.enabled, isTrue);
      expect(got.light.file, s().light.file, reason: '同样的内容，同样的文件名');
      expectCrop(got.light.crop, s().light.crop);
      expect(got.light.copyWith(crop: s().light.crop), s().light);
      expect(files(other), [got.light.file], reason: '只留入库好的那一张，临时文件不留');
      expect(other.read(backdropStatusProvider), '已启用');
      // 重开还在
      await pendingWrites();
      final again = open('b');
      addTearDown(again.dispose);
      await again.read(backdropProvider.notifier).ready;
      expect(again.read(backdropProvider).light.file, got.light.file);
    });

    test('转过的图：导出时把旋转画进图里（主题那边没有“转了几个 90°”这一项），只认主题那几个字段的一方导入后看到的也是转好的样子', () async {
      // 80×60，顺时针转 90° 以后是 60×80：原来左下的蓝到了左上，左上的红到了右上
      await seed(await makePng(80, 60), crop: const CropRect(0.1, 0.2, 0.3, 0.4), turns: 1);
      final r = await n().exportForTheme(dark: false);
      expect(r.error, isNull);
      expect(r.notes, isEmpty);
      final d = r.data!;
      expect((d['mime'], d['turns']), ('image/png', 0));
      expectCrop(CropRect(d['cropX']! as double, d['cropY']! as double, d['cropW']! as double, d['cropH']! as double), const CropRect(0.1, 0.2, 0.3, 0.4));
      final codec = await ui.instantiateImageCodec(d['bytes']! as Uint8List);
      final img = (await codec.getNextFrame()).image;
      codec.dispose();
      expect((img.width, img.height), (60, 80));
      final px = (await img.toByteData())!;
      int rgb(int x, int y) => (px.getUint8((y * 60 + x) * 4) << 16) | (px.getUint8((y * 60 + x) * 4 + 1) << 8) | px.getUint8((y * 60 + x) * 4 + 2);
      expect((rgb(5, 5), rgb(54, 5), rgb(5, 74), rgb(54, 74)), (0x2E5FD0, 0xD23A3A, 0xE8B923, 0x2FA35B), reason: '左上蓝、右上红、左下黄、右下绿');
      img.dispose();

      // 只带主题格式里有的那几项（主题文件现在就是这样存的）
      final other = open('b');
      addTearDown(other.dispose);
      final slim = {
        for (final k in const ['mime', 'bytes', 'cropX', 'cropY', 'cropW', 'cropH', 'dim', 'blur']) k: d[k],
      };
      expect(await other.read(backdropProvider.notifier).applyThemeBackground(slim), isNull);
      final got = other.read(backdropProvider).light;
      expect((got.width, got.height, got.turns), (60, 80, 0));
      expect((got.rotatedWidth, got.rotatedHeight), (s().light.rotatedWidth, s().light.rotatedHeight));
      expectCrop(got.crop, s().light.crop);
    });

    test('只带主题那边认识的字段（mime、bytes、crop、dim、blur）也能导入：其余保持原样；模糊、压暗超范围收回来；裁剪不合理当没裁', () async {
      await n().ready;
      n().updateLook(dark: false, change: (l) => l.copyWith(brightness: 15, fit: BackdropFit.contain));
      expect(await n().applyThemeBackground({'mime': 'image/png', 'bytes': await makePng(40, 30), 'cropX': 0.5, 'cropY': 0.5, 'cropW': 0.9, 'cropH': 0.2, 'dim': 3, 'blur': 40}), isNull);
      final l = s().light;
      expect((l.width, l.height, l.turns), (40, 30, 0));
      expect(l.crop, CropRect.full);
      expect((l.maskOpacity, l.blur), (100, kBackdropBlurMax));
      expect((l.brightness, l.fit, l.maskFollowsTheme), (15, BackdropFit.contain, true));
      // List<int>（不是 Uint8List）也收；裁剪合理就照用
      expect(await n().applyThemeBackground({'bytes': List<int>.of(await makePng(20, 20)), 'cropX': 0.5, 'cropY': 0.25, 'cropW': 0.5, 'cropH': 0.5}), isNull);
      expectCrop(s().light.crop, const CropRect(0.5, 0.25, 0.5, 0.5));
      expect(files(container), [s().light.file], reason: '上一张被换掉后清理了');
    });

    test('放到深色那一份：打开“深色单独设置”，浅色的不动', () async {
      await seed(await makePng(30, 30));
      final light = s().light;
      expect(await n().applyThemeBackground({'mime': 'image/jpeg', 'bytes': kTinyJpg, 'dim': 0.8}, dark: true), isNull);
      expect(s().darkSeparate, isTrue);
      expect(s().light, light);
      expect(s().dark.file, endsWith('.jpg'));
      expect(s().dark.maskOpacity, 80);
      expect(files(container).toSet(), {light.file, s().dark.file});
    });

    test('导入的图用不了（空、太大、不是图片、GIF、和写的格式对不上、内容坏了、bytes 不是字节）：说明原因，原来的背景不动，不留文件', () async {
      await seed(await makePng(30, 30));
      final before = s();
      final cases = <(Map<Object?, Object?>, String)>[
        ({'mime': 'image/png', 'bytes': Uint8List(0)}, '空的'),
        ({'mime': 'image/png'}, '空的'),
        ({'mime': 'image/png', 'bytes': 'abc'}, '空的'),
        ({'mime': 'image/png', 'bytes': Uint8List(kThemeBackdropMaxBytes + 1)}, '太大'),
        ({'mime': 'image/png', 'bytes': Uint8List.fromList(List.filled(64, 7))}, '不是 JPG、PNG 或 WebP'),
        ({'mime': 'image/gif', 'bytes': kGifHeader}, '不是 JPG、PNG 或 WebP'),
        ({'mime': 'image/jpeg', 'bytes': await makePng(8, 8)}, '对不上'),
        ({'mime': 'image/png', 'bytes': Uint8List.fromList((await makePng(8, 8)).sublist(0, 24))}, '解不开'),
      ];
      for (final (data, expected) in cases) {
        final msg = await n().applyThemeBackground(data);
        expect(msg, contains(expected), reason: '$data');
        expect(s(), before);
        expect(files(container), [before.light.file]);
      }
    });

    test('图超过上限：缩小长边重新存成 PNG 带上并说明；怎么缩都放不下就说明原因、不带图', () async {
      final noise = await makeNoisePng(300, 200);
      expect(noise.length, greaterThan(150 * 1024));
      await seed(noise);
      final look = s().light;
      final ok = await exportBackdropForTheme(store(), look, maxBytes: 60 * 1024, shrinkSides: const [400, 250, 100]);
      expect(ok.error, isNull);
      expect(ok.notes.single, contains('缩小到了长边 100 像素'));
      final bytes = ok.data!['bytes']! as Uint8List;
      expect(bytes.length, lessThanOrEqualTo(60 * 1024));
      expect(ok.data!['mime'], 'image/png');
      final codec = await ui.instantiateImageCodec(bytes);
      final img = (await codec.getNextFrame()).image;
      expect((img.width, img.height), (100, 67));
      img.dispose();
      codec.dispose();
      expect(ok.data!['cropW'], 0.5, reason: '裁剪是比例，不受缩小影响');

      final no = await exportBackdropForTheme(store(), look, maxBytes: 200, shrinkSides: const [100]);
      expect(no.data, isNull);
      expect(no.error, allOf(contains('太大'), contains('不带图')));
      // 正式的上限下这张小图原样带上
      final plain = await n().exportForTheme(dark: false);
      expect(plain.data!['bytes'], noise);
    });

    test('图片文件不见了：导出说明读不出来，不抛错', () async {
      await seed(await makePng(30, 30));
      store().imageFile(s().light.file!).deleteSync();
      final r = await n().exportForTheme(dark: false);
      expect(r.data, isNull);
      expect(r.error, contains('读不出来'));
    });

    test('外观页那一行的状态文字：未设置 / 已启用 / 已关闭', () async {
      expect(container.read(backdropStatusProvider), '未设置', reason: '还没读完');
      await n().ready;
      expect(container.read(backdropStatusProvider), '未设置');
      await seed(await makePng(30, 30));
      expect(container.read(backdropStatusProvider), '已启用');
      n().update((x) => x.copyWith(enabled: false));
      expect(container.read(backdropStatusProvider), '已关闭');
      await n().removeImage(dark: false);
      expect(container.read(backdropStatusProvider), '未设置');
    });
  });
}
