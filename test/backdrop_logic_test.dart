// 背景图片的逻辑测试：裁剪数学、文件头、入库与清理、选图通道（假通道）、设置状态。
// 图片都是代码生成的小图；绝不拉起真的系统选择器。
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/backdrop/backdrop_model.dart';
import 'package:lopicode/backdrop/backdrop_picker.dart';
import 'package:lopicode/backdrop/backdrop_store.dart';
import 'package:lopicode/backdrop/crop_math.dart';
import 'package:lopicode/core/safe_file.dart';
import 'package:lopicode/core/stores.dart';
import 'package:lopicode/state/app_providers.dart';
import 'package:lopicode/state/backdrop_state.dart';
import 'package:lopicode/ui/backdrop_images.dart';
import 'package:path/path.dart' as p;
import 'package:riverpod/riverpod.dart';

import 'support/backdrop_fakes.dart';

const double kEps = 1e-9;

void expectInside(CropRect r) {
  expect(r.left, greaterThanOrEqualTo(-kEps));
  expect(r.top, greaterThanOrEqualTo(-kEps));
  expect(r.right, lessThanOrEqualTo(1 + kEps));
  expect(r.bottom, lessThanOrEqualTo(1 + kEps));
  expect(r.width, greaterThan(0));
  expect(r.height, greaterThan(0));
}

/// 区域在图片上的像素宽高比。
double pixelAspect(CropRect r, double w, double h) => (r.width * w) / (r.height * h);

void main() {
  const phone = 390 / 844;

  group('裁剪数学', () {
    for (final (name, w, h) in [('横图', 1600.0, 900.0), ('竖图', 900.0, 1600.0), ('方图', 1000.0, 1000.0), ('很宽的全景', 4000.0, 500.0), ('很窄的长图', 300.0, 3000.0), ('正好是屏幕比例', 390.0, 844.0)]) {
      test('$name：一开始居中、最大、比例对', () {
        final m = CropMath(imageWidth: w, imageHeight: h, aspect: phone);
        final r = m.initial();
        expectInside(r);
        expect(pixelAspect(r, w, h), closeTo(phone, 1e-6));
        expect(r.centerX, closeTo(0.5, 1e-9));
        expect(r.centerY, closeTo(0.5, 1e-9));
        // 最大：至少有一个方向顶满
        expect(r.width > 1 - 1e-9 || r.height > 1 - 1e-9, isTrue);
        expect(m.zoomOf(r), closeTo(1, 1e-9));
      });

      test('$name：往四个方向拖过头都停在边上，大小不变', () {
        final m = CropMath(imageWidth: w, imageHeight: h, aspect: phone);
        final start = m.zoomTo(m.initial(), 2);
        for (final (dx, dy) in [(-5.0, 0.0), (5.0, 0.0), (0.0, -5.0), (0.0, 5.0), (9.0, 9.0), (-9.0, -9.0)]) {
          final r = m.pan(start, dx, dy);
          expectInside(r);
          expect(r.width, closeTo(start.width, 1e-12));
          expect(r.height, closeTo(start.height, 1e-12));
          if (dx < 0) expect(r.left, closeTo(0, 1e-12));
          if (dx > 0) expect(r.right, closeTo(1, 1e-12));
          if (dy < 0) expect(r.top, closeTo(0, 1e-12));
          if (dy > 0) expect(r.bottom, closeTo(1, 1e-12));
        }
      });

      test('$name：缩放夹在 1–$kCropMaxZoom 倍，比例一直对', () {
        final m = CropMath(imageWidth: w, imageHeight: h, aspect: phone);
        final init = m.initial();
        expect(m.zoomTo(init, 0.2), init);
        final most = m.zoomTo(init, 999);
        expect(m.zoomOf(most), closeTo(kCropMaxZoom, 1e-9));
        expectInside(most);
        for (final z in [1.0, 1.5, 3.0, 8.0]) {
          final r = m.zoomTo(init, z);
          expectInside(r);
          expect(pixelAspect(r, w, h), closeTo(phone, 1e-6));
          expect(m.zoomOf(r), closeTo(z, 1e-9));
        }
        // 连着捏：倍数相乘；非法的比例（0、负数、NaN）当作没动
        var r = m.zoomBy(init, 2);
        r = m.zoomBy(r, 1.5);
        expect(m.zoomOf(r), closeTo(3, 1e-9));
        expect(m.zoomBy(r, 0), r);
        expect(m.zoomBy(r, double.nan), r);
      });
    }

    test('围绕焦点缩放：焦点下的那个点在选框里的相对位置不变', () {
      final m = CropMath(imageWidth: 2000, imageHeight: 3000, aspect: phone);
      final r0 = m.zoomTo(m.initial(), 2);
      final fx = r0.left + r0.width * 0.25, fy = r0.top + r0.height * 0.7;
      final r1 = m.zoomTo(r0, 4, focalX: fx, focalY: fy);
      expect((fx - r1.left) / r1.width, closeTo(0.25, 1e-9));
      expect((fy - r1.top) / r1.height, closeTo(0.7, 1e-9));
      // 缩小回去时碰到边：还是合法的
      final back = m.zoomTo(m.pan(r1, -9, -9), 1, focalX: 0, focalY: 0);
      expectInside(back);
      expect(m.zoomOf(back), closeTo(1, 1e-9));
      expect(back.width, closeTo(m.initial().width, 1e-9));
      expect(back.left, closeTo(0, 1e-9), reason: '横向还有余量：焦点在左上角，就贴着左边');
    });

    test('换了屏幕比例再打开（refit）：比例收对、中心尽量不动、不出图', () {
      final old = CropMath(imageWidth: 3000, imageHeight: 2000, aspect: phone);
      final saved = old.pan(old.zoomTo(old.initial(), 3), 0.2, 0.1);
      for (final aspect in [9 / 16, 3 / 4, 1.0, 9 / 21]) {
        final m = CropMath(imageWidth: 3000, imageHeight: 2000, aspect: aspect);
        final r = m.refit(saved);
        expectInside(r);
        expect(pixelAspect(r, 3000, 2000), closeTo(aspect, 1e-6));
        expect(r.centerX, closeTo(saved.centerX, 0.2));
        expect(m.zoomOf(r), inInclusiveRange(1, kCropMaxZoom));
      }
      // 同一个比例：原样
      final same = old.refit(saved);
      expect(same.left, closeTo(saved.left, 1e-9));
      expect(same.width, closeTo(saved.width, 1e-9));
      // 整张图（刚入库 / 存盘坏了回退的）：收成居中最大
      expect(old.refit(CropRect.full).width, closeTo(old.initial().width, 1e-9));
    });

    test('非法输入不崩：宽高是 0、比例是 0 / NaN', () {
      final m = CropMath(imageWidth: 0, imageHeight: -5, aspect: double.nan);
      expectInside(m.initial());
      expectInside(m.zoomTo(m.initial(), double.infinity));
    });

    test('CropRect 存取：坏数据回整张图', () {
      const r = CropRect(0.1, 0.2, 0.3, 0.4);
      expect(CropRect.fromJson(r.toJson()), r);
      for (final bad in <Object?>[
        null,
        3,
        'x',
        <String, dynamic>{},
        {'l': 0, 't': 0, 'w': 0, 'h': 1},
        {'l': 0.9, 't': 0, 'w': 0.5, 'h': 1},
        {'l': double.nan, 't': 0, 'w': 1, 'h': 1},
        {'l': '0', 't': 0, 'w': 1, 'h': 1},
      ]) {
        expect(CropRect.fromJson(bad), CropRect.full, reason: '$bad');
      }
    });
  });

  group('设置模型', () {
    test('默认：没读完、没有图，哪里都不显示；默认只铺聊天页，四个“透出”都关', () {
      const s = BackdropSettings();
      expect(s.loaded, isFalse);
      for (final a in BackdropArea.values) {
        expect(s.showsOn(a, dark: false), isFalse);
      }
      expect(s.onChat, isTrue);
      expect(s.onPages, isFalse);
      expect([s.terminal, s.code, s.blocks, s.lowcode], everyElement(isFalse));
    });

    test('showsOn：要“读完 + 开着 + 有图 + 这个范围开着”四样都满足', () {
      const look = BackdropLook(file: 'a.png', width: 10, height: 10);
      const s = BackdropSettings(light: look, loaded: true);
      expect(s.showsOn(BackdropArea.chat, dark: false), isTrue);
      expect(s.showsOn(BackdropArea.chat, dark: true), isTrue, reason: '深色没单独设置时共用浅色那张');
      expect(s.showsOn(BackdropArea.pages, dark: false), isFalse);
      expect(s.copyWith(enabled: false).showsOn(BackdropArea.chat, dark: false), isFalse);
      expect(s.copyWith(loaded: false).showsOn(BackdropArea.chat, dark: false), isFalse);
      expect(s.withArea(BackdropArea.terminal, true).showsOn(BackdropArea.terminal, dark: false), isTrue);
      // 深色单独设置、但深色那份没图：深色下不显示
      final sep = s.copyWith(darkSeparate: true);
      expect(sep.showsOn(BackdropArea.chat, dark: true), isFalse);
      expect(sep.showsOn(BackdropArea.chat, dark: false), isTrue);
    });

    test('copyWith 把数值夹回范围；旋转后宽高互换', () {
      const look = BackdropLook(file: 'a.png', width: 300, height: 200);
      final l = look.copyWith(maskOpacity: 500, blur: -3, brightness: 999, tilePercent: 1, turns: 5);
      expect(l.maskOpacity, 100);
      expect(l.blur, 0);
      expect(l.brightness, kBackdropBrightnessRange);
      expect(l.tilePercent, kBackdropTileMin);
      expect(l.turns, 1);
      expect((l.rotatedWidth, l.rotatedHeight), (200, 300));
      expect(const BackdropSettings().copyWith(surfaceOpacity: 0).surfaceOpacity, kBackdropSurfaceMin);
      // 去掉图：效果参数留着
      final gone = l.withoutImage();
      expect(gone.hasImage, isFalse);
      expect(gone.maskOpacity, 100);
    });
  });

  group('文件头', () {
    test('认得 JPG / PNG / WebP / GIF，别的不认', () async {
      expect(sniffBackdropFormat(kTinyJpg), BackdropFormat.jpg);
      expect(sniffBackdropFormat(await makePng(4, 4)), BackdropFormat.png);
      expect(sniffBackdropFormat(kTinyWebp), BackdropFormat.webp);
      expect(sniffBackdropFormat(kGifHeader), BackdropFormat.gif);
      expect(sniffBackdropFormat(const []), isNull);
      expect(sniffBackdropFormat('<svg xmlns="http://www.w3.org/2000/svg"/>'.codeUnits), isNull);
      expect(sniffBackdropFormat('RIFF____WAVE'.codeUnits), isNull);
      expect(sniffBackdropFormat(const [0xFF, 0xD8]), isNull);
    });
  });

  group('解码缓存（BackdropImages）', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('lopi_bgi_'));
    tearDown(() {
      BackdropImages.instance.clear();
      tmp.deleteSync(recursive: true);
    });

    test('第一次 load 会完成（回归：以前它等自己、永远不回来）；同时叫两次只解一次；之后直接拿缓存', () async {
      final path = writePick(tmp, 'a.png', await makePng(40, 30));
      final images = BackdropImages.instance;
      expect(images.peek(path), isNull);
      final both = await Future.wait([images.load(path), images.load(path)]).timeout(const Duration(seconds: 20));
      expect(both[0], isNotNull);
      expect(identical(both[0], both[1]), isTrue);
      expect((both[0]!.width, both[0]!.height), (40, 30));
      expect(images.decodeCount, 1);
      expect(images.peek(path), same(both[0]));
      expect(await images.load(path).timeout(const Duration(seconds: 5)), same(both[0]));
      expect(images.decodeCount, 1);
      images.forget(path);
      expect(images.peek(path), isNull);
    });

    test('文件没了 / 不是图片：回 null，不抛错，也不卡住', () async {
      final images = BackdropImages.instance;
      expect(await images.load(p.join(tmp.path, 'nope.png')).timeout(const Duration(seconds: 20)), isNull);
      final bad = writePick(tmp, 'bad.png', 'not an image'.codeUnits);
      expect(await images.load(bad).timeout(const Duration(seconds: 20)), isNull);
      // 失败以后还能再试（没有卡在“正在解”）
      expect(await images.load(bad).timeout(const Duration(seconds: 20)), isNull);
    });

    test('最多记 ${BackdropImages.kMaxSources} 张，多了丢最久没用的', () async {
      final images = BackdropImages.instance;
      final paths = [for (var i = 0; i < BackdropImages.kMaxSources + 1; i++) writePick(tmp, 'i$i.png', await makePng(8 + i, 8))];
      for (final path in paths) {
        await images.load(path).timeout(const Duration(seconds: 20));
      }
      expect(images.peek(paths.first), isNull);
      expect(images.peek(paths.last), isNotNull);
    });
  });

  group('入库与清理', () {
    late Directory tmp;
    late BackdropStore store;
    setUp(() {
      tmp = Directory.systemTemp.createTempSync('lopi_bg_');
      store = BackdropStore(p.join(tmp.path, 'appearance'));
    });
    tearDown(() async {
      await pendingWrites();
      tmp.deleteSync(recursive: true);
    });

    Future<String> failure(String name, List<int> bytes) async {
      try {
        await store.importFile(File(writePick(tmp, name, bytes)));
      } on BackdropImportException catch (e) {
        return e.message;
      }
      fail('应该入库失败');
    }

    test('PNG / JPG / WebP：原样搬进私有目录，文件名带内容哈希，缓存副本删掉', () async {
      for (final (name, bytes, ext, w, h) in [('a.png', await makePng(40, 30), 'png', 40, 30), ('b.jpg', kTinyJpg, 'jpg', 8, 6), ('c.webp', kTinyWebp, 'webp', 8, 6)]) {
        final src = File(writePick(tmp, name, bytes));
        final got = await store.importFile(src);
        expect(got.file, matches(RegExp('^bg-[0-9a-f]{16}\\.$ext\$')));
        expect((got.width, got.height), (w, h));
        expect(store.imageFile(got.file).readAsBytesSync(), bytes);
        expect(p.isWithin(store.imageDir.path, store.imageFile(got.file).path), isTrue);
        expect(src.existsSync(), isFalse, reason: '缓存副本用完要删');
      }
    });

    test('同一张图入库两次：同一个文件名，不多占地方', () async {
      final bytes = await makePng(20, 20);
      final a = await store.importFile(File(writePick(tmp, 'a.png', bytes)));
      final b = await store.importFile(File(writePick(tmp, 'b.png', bytes)));
      expect(a.file, b.file);
      expect(store.imageDir.listSync(), hasLength(1));
    });

    test('长边超过 $kBackdropMaxSide：缩到 $kBackdropMaxSide 再存成 PNG，比例不变', () async {
      final got = await store.importFile(File(writePick(tmp, 'big.png', await makePng(3200, 1600))));
      expect((got.width, got.height), (kBackdropMaxSide, kBackdropMaxSide ~/ 2));
      expect(got.file, endsWith('.png'));
      expect(sniffBackdropFormat(store.imageFile(got.file).readAsBytesSync()), BackdropFormat.png);
    });

    test('超过 ${kBackdropMaxFileBytes ~/ (1024 * 1024)}MB：不收，说清多大、上限多少', () async {
      final big = Uint8List(kBackdropMaxFileBytes + 1)..setAll(0, await makePng(4, 4));
      final msg = await failure('huge.png', big);
      expect(msg, contains('太大'));
      expect(msg, contains('20MB'));
      expect(store.imageDir.existsSync(), isFalse);
    });

    test('坏文件头 / GIF / 空文件 / 文件头对但内容坏了 / 文件不见了：各有各的人话，什么都不留', () async {
      expect(await failure('x.png', 'hello world, not an image'.codeUnits), contains('不是能用的图片'));
      expect(await failure('x.gif', kGifHeader), contains('GIF'));
      expect(await failure('empty.png', const []), contains('空的'));
      final png = await makePng(16, 16);
      expect(await failure('broken.png', png.sublist(0, 30)), contains('解不开'));
      expect(await failure('broken.jpg', [0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3, 4, 5]), contains('解不开'));
      try {
        await store.importFile(File(p.join(tmp.path, 'cache', 'missing.png')));
        fail('应该失败');
      } on BackdropImportException catch (e) {
        expect(e.message, contains('不见了'));
      }
      expect(store.imageDir.existsSync() ? store.imageDir.listSync() : const <FileSystemEntity>[], isEmpty);
      expect(Directory(p.join(tmp.path, 'cache')).listSync(), isEmpty, reason: '失败了缓存副本也要删');
    });

    test('存不进去（目录的位置被一个文件占了）：报人话，不抛别的异常', () async {
      File(store.imageDir.path)
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('挡路的文件');
      expect(await failure('a.png', await makePng(8, 8)), contains('存不下'));
    });

    test('清理：只留还在用的，旧图和半截的临时文件都删', () async {
      final a = await store.importFile(File(writePick(tmp, 'a.png', await makePng(10, 10))));
      final b = await store.importFile(File(writePick(tmp, 'b.png', await makePng(12, 10))));
      File(p.join(store.imageDir.path, 'bg-half.png.tmp')).writeAsStringSync('半截');
      await store.cleanup({b.file});
      expect([for (final e in store.imageDir.listSync()) p.basename(e.path)], [b.file]);
      expect(store.imageFile(a.file).existsSync(), isFalse);
      await store.cleanup({});
      expect(store.imageDir.listSync(), isEmpty);
      // 目录不存在也不崩
      await BackdropStore(p.join(tmp.path, 'nowhere')).cleanup({});
    });
  });

  group('选图通道（假通道，不拉起系统选择器）', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    tearDown(() => messenger.setMockMethodCallHandler(ChannelBackdropPicker.channel, null));

    Future<BackdropPick> pickWith(Future<Object?> Function(MethodCall call) handler) {
      messenger.setMockMethodCallHandler(ChannelBackdropPicker.channel, handler);
      return const ChannelBackdropPicker().pick();
    }

    test('成功：拿到缓存路径；把两个上限告诉原生那头', () async {
      MethodCall? seen;
      final r = await pickWith((call) async {
        seen = call;
        return {'status': 'ok', 'path': '/cache/backdrop_pick/pick-1.jpg'};
      });
      expect(r, isA<BackdropPicked>().having((e) => e.path, 'path', '/cache/backdrop_pick/pick-1.jpg'));
      expect(seen!.method, 'pickImage');
      expect(seen!.arguments, {'maxBytes': kBackdropMaxFileBytes, 'maxSide': kBackdropMaxSide});
    });

    test('取消', () async {
      expect(await pickWith((_) async => {'status': 'cancelled'}), isA<BackdropPickCancelled>());
    });

    test('各种失败代号都换成人话；不认识的代号也有交代', () async {
      for (final (code, word) in [('too_large', '太大'), ('unsupported', 'JPG'), ('read_failed', '读不出'), ('no_picker', '找不到'), ('no_space', '存储空间'), ('busy', '还没结束'), ('weird', 'weird')]) {
        final r = await pickWith((_) async => throw PlatformException(code: code, message: 'java.io.IOException: secret/path'));
        expect(r, isA<BackdropPickFailed>());
        final msg = (r as BackdropPickFailed).message;
        expect(msg, contains(word));
        expect(msg, isNot(contains('java.io')), reason: '系统的原始报错不直接给用户看');
      }
    });

    test('交回来的东西不对（null、没有路径、状态不认识）：算失败，不崩', () async {
      for (final bad in <Object?>[
        null,
        'x',
        <String, Object?>{},
        {'status': 'ok'},
        {'status': 'ok', 'path': ''},
        {'status': 'ok', 'path': 5},
        {'status': '???', 'path': '/a'},
      ]) {
        expect(await pickWith((_) async => bad), isA<BackdropPickFailed>(), reason: '$bad');
      }
    });

    test('这个平台没有通道（桌面、测试）：说明只支持安卓', () async {
      messenger.setMockMethodCallHandler(ChannelBackdropPicker.channel, null);
      final r = await const ChannelBackdropPicker().pick();
      expect(r, isA<BackdropPickFailed>().having((e) => e.message, 'message', contains('安卓')));
    });
  });

  group('设置状态（BackdropNotifier）', () {
    late Directory tmp;
    late ProviderContainer container;
    late FakeBackdropPicker picker;

    ProviderContainer open() {
      final c = ProviderContainer(overrides: [settingsStoreProvider.overrideWithValue(SettingsStore(File(p.join(tmp.path, 'settings.json'))))]);
      c.read(backdropPickerProvider.notifier).use(picker);
      return c;
    }

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('lopi_bgs_');
      picker = FakeBackdropPicker();
      container = open();
    });
    tearDown(() async {
      container.dispose();
      await pendingWrites();
      tmp.deleteSync(recursive: true);
    });

    BackdropNotifier n() => container.read(backdropProvider.notifier);
    BackdropSettings s() => container.read(backdropProvider);
    BackdropStore store() => container.read(backdropStoreProvider);

    Future<ImportedBackdrop> pickOne(int w, int h) async {
      picker.script.add(BackdropPicked(writePick(tmp, 'pick-$w.png', await makePng(w, h))));
      final r = await n().pickAndImport();
      return (r as BackdropImportOk).image;
    }

    test('读完之前的修改不受理；读完是默认值', () async {
      expect(s().loaded, isFalse);
      n().update((x) => x.copyWith(onPages: true));
      expect(s().onPages, isFalse);
      await n().ready;
      expect(s().loaded, isTrue);
      expect(s().light.hasImage, isFalse);
      expect(store().settingsFile.existsSync(), isFalse, reason: '没改过就不建文件');
    });

    test('选图成功 → 入库但设置不变；确认后才用上并存盘；重开还在', () async {
      await n().ready;
      final img = await pickOne(60, 80);
      expect(picker.calls, 1);
      expect(s().light.hasImage, isFalse, reason: '裁剪页确认之前不改设置');
      expect(store().imageFile(img.file).existsSync(), isTrue);
      await n().setImage(dark: false, image: img, crop: const CropRect(0.1, 0.1, 0.5, 0.5), turns: 1);
      expect(s().light.file, img.file);
      expect(s().light.turns, 1);
      expect(s().showsOn(BackdropArea.chat, dark: false), isTrue);

      container.dispose();
      await pendingWrites();
      container = open();
      await n().ready;
      expect(s().light.file, img.file);
      expect(s().light.crop, const CropRect(0.1, 0.1, 0.5, 0.5));
    });

    test('取消 / 失败 / 超大 / 坏文件头：设置不变，什么文件都不留', () async {
      await n().ready;
      picker.script.addAll([
        const BackdropPickCancelled(),
        const BackdropPickFailed('读不出这张图'),
        BackdropPicked(writePick(tmp, 'bad.png', 'not an image'.codeUnits)),
        BackdropPicked(writePick(tmp, 'huge.png', Uint8List(kBackdropMaxFileBytes + 1)..setAll(0, await makePng(4, 4)))),
      ]);
      expect(await n().pickAndImport(), isA<BackdropImportCancelled>());
      expect(await n().pickAndImport(), isA<BackdropImportFailed>().having((e) => e.message, 'message', '读不出这张图'));
      expect(await n().pickAndImport(), isA<BackdropImportFailed>().having((e) => e.message, 'message', contains('不是能用的图片')));
      expect(await n().pickAndImport(), isA<BackdropImportFailed>().having((e) => e.message, 'message', contains('太大')));
      expect(s(), const BackdropSettings(loaded: true));
      expect(store().imageDir.existsSync() ? store().imageDir.listSync() : const <FileSystemEntity>[], isEmpty);
      expect(Directory(p.join(tmp.path, 'cache')).listSync(), isEmpty);
    });

    test('选了图但裁剪页退出来（discard）：刚入库的删掉，原来的图不动', () async {
      await n().ready;
      final first = await pickOne(30, 30);
      await n().setImage(dark: false, image: first, crop: CropRect.full);
      final second = await pickOne(31, 30);
      expect(store().imageFile(second.file).existsSync(), isTrue);
      await n().discard();
      expect(store().imageFile(second.file).existsSync(), isFalse);
      expect(store().imageFile(first.file).existsSync(), isTrue);
      expect(s().light.file, first.file);
    });

    test('换一张：旧文件清掉，效果参数留着', () async {
      await n().ready;
      final first = await pickOne(30, 30);
      await n().setImage(dark: false, image: first, crop: CropRect.full);
      n().updateLook(dark: false, change: (l) => l.copyWith(blur: 10, maskOpacity: 30));
      final second = await pickOne(50, 20);
      await n().setImage(dark: false, image: second, crop: const CropRect(0, 0, 0.5, 1));
      expect(store().imageFile(first.file).existsSync(), isFalse);
      expect(s().light.file, second.file);
      expect((s().light.blur, s().light.maskOpacity), (10, 30));
      expect((s().light.width, s().light.height), (50, 20));
    });

    test('重新裁剪：只换区域和旋转，图不动', () async {
      await n().ready;
      final img = await pickOne(30, 30);
      await n().setImage(dark: false, image: img, crop: CropRect.full);
      await n().setCrop(dark: false, crop: const CropRect(0.2, 0.2, 0.4, 0.4), turns: 3);
      expect(s().light.file, img.file);
      expect(s().light.crop, const CropRect(0.2, 0.2, 0.4, 0.4));
      expect(s().light.turns, 3);
    });

    test('移除：删文件、设置里没有图了；效果参数留着', () async {
      await n().ready;
      final img = await pickOne(30, 30);
      await n().setImage(dark: false, image: img, crop: CropRect.full);
      n().updateLook(dark: false, change: (l) => l.copyWith(brightness: -20));
      await n().removeImage(dark: false);
      expect(s().light.hasImage, isFalse);
      expect(s().light.brightness, -20);
      expect(store().imageFile(img.file).existsSync(), isFalse);
      expect(s().showsOn(BackdropArea.chat, dark: false), isFalse);
    });

    test('深色单独设置：第一次打开抄浅色那份（同一个文件）；各改各的；移除一份不删另一份还在用的文件', () async {
      await n().ready;
      final img = await pickOne(30, 30);
      await n().setImage(dark: false, image: img, crop: CropRect.full);
      await n().setDarkSeparate(true);
      expect(s().dark.file, img.file);
      n().updateLook(dark: true, change: (l) => l.copyWith(brightness: -40));
      expect(s().light.brightness, 0);
      expect(s().lookFor(dark: true).brightness, -40);
      expect(s().lookFor(dark: false).brightness, 0);
      await n().removeImage(dark: true);
      expect(store().imageFile(img.file).existsSync(), isTrue, reason: '浅色那份还在用');
      // 深色另选一张，再关掉“单独设置”：深色那份留着（下次打开还在），但显示用浅色的
      final dark = await pickOne(20, 40);
      await n().setImage(dark: true, image: dark, crop: CropRect.full);
      await n().setDarkSeparate(false);
      expect(s().lookFor(dark: true).file, img.file);
      expect(store().imageFile(dark.file).existsSync(), isTrue);
    });

    test('滑杆拖动过程中（persist: false）不写盘，commit 才写', () async {
      await n().ready;
      n().update((x) => x.copyWith(surfaceOpacity: 70), persist: false);
      await pendingWrites();
      expect(store().settingsFile.existsSync(), isFalse);
      expect(s().surfaceOpacity, 70);
      await n().commit();
      expect((await store().load()).surfaceOpacity, 70);
    });

    test('设置里记着的图片文件不在了：读出来当作没有图，不崩', () async {
      await n().ready;
      final img = await pickOne(30, 30);
      await n().setImage(dark: false, image: img, crop: CropRect.full);
      final file = store().imageFile(img.file);
      container.dispose();
      await pendingWrites();
      file.deleteSync();
      container = open();
      await n().ready;
      expect(s().light.hasImage, isFalse);
      expect(s().loaded, isTrue);
    });

    test('存盘文件是坏的：回默认值，照常能用', () async {
      BackdropStore(p.join(tmp.path, 'appearance')).settingsFile
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('{"enabled": tru');
      container.dispose();
      container = open();
      await n().ready;
      expect(s(), const BackdropSettings(loaded: true));
      n().update((x) => x.copyWith(onPages: true));
      expect(s().onPages, isTrue);
    });

    test('同时点两次选图：第二次不拉起选择器', () async {
      await n().ready;
      picker.script.add(const BackdropPickCancelled());
      final a = n().pickAndImport();
      final b = await n().pickAndImport();
      expect(b, isA<BackdropImportFailed>());
      expect(await a, isA<BackdropImportCancelled>());
      expect(picker.calls, 1);
    });
  });
}
