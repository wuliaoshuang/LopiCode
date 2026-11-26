// 主题导出文件 `background` 一节后加的四个可选字段（fit、tile、maskColor、brightness），
// 以及主题 ↔ 背景图片的对接口（lib/state/theme_hooks.dart 的 themeBackgroundBridgeProvider）。
//   flutter test test/theme_background_fields_test.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/appearance/theme_builtin.dart';
import 'package:lopicode/appearance/theme_fields.dart';
import 'package:lopicode/appearance/theme_json.dart';
import 'package:lopicode/backdrop/backdrop_model.dart';
import 'package:lopicode/backdrop/backdrop_picker.dart';
import 'package:lopicode/backdrop/crop_math.dart';
import 'package:lopicode/core/safe_file.dart';
import 'package:lopicode/core/stores.dart';
import 'package:lopicode/state/app_providers.dart';
import 'package:lopicode/state/backdrop_state.dart';
import 'package:lopicode/state/theme_hooks.dart';
import 'package:path/path.dart' as p;
import 'package:riverpod/riverpod.dart';

import 'support/backdrop_fakes.dart';

// 1×1 的 PNG。
const _png = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

String _file(Map<String, Object?> background) => jsonEncode({...encodeTheme(kDefaultLightTheme.copyWith(builtin: false, name: '带图的')), 'background': background});

void main() {
  group('background 一节的四个可选字段', () {
    test('写出去再读回来一样；没给的字段不写进文件', () {
      final bytes = base64Decode(_png);
      final full = ThemeBackground(mime: 'image/png', bytes: bytes, dim: 0.35, blur: 12, fit: 'tile', tile: 40, maskFollowsTheme: false, maskColor: 0x1B2A4A, brightness: -20);
      final json = encodeThemeBackground(full);
      expect((json['fit'], json['tile'], json['maskColor'], json['brightness']), ('tile', 40, '#1B2A4A', -20));
      final back = decodeThemeText(encodeThemeText(kDefaultLightTheme.copyWith(builtin: false), background: full));
      expect(back.ok, isTrue, reason: back.error);
      final b = back.background!;
      expect((b.fit, b.tile, b.maskFollowsTheme, b.maskColor, b.brightness), ('tile', 40, false, 0x1B2A4A, -20));
      expect((b.dim, b.blur), (0.35, 12.0));

      final follow = encodeThemeBackground(ThemeBackground(mime: 'image/png', bytes: bytes, maskFollowsTheme: true));
      expect(follow['maskColor'], 'theme');
      final (fb, _) = decodeThemeBackground(follow);
      expect((fb!.maskFollowsTheme, fb.maskColor), (true, null));

      final plain = encodeThemeBackground(ThemeBackground(mime: 'image/png', bytes: bytes));
      expect(plain.keys.toSet(), {'mime', 'data', 'crop', 'dim', 'blur'}, reason: '没给的可选字段不出现在文件里');
    });

    test('老文件（没有这四个字段）照常能导入，四项都是“没写”', () {
      final r = decodeThemeText(_file({'mime': 'image/png', 'data': _png, 'dim': 0.3, 'blur': 8}));
      expect(r.ok, isTrue, reason: r.error);
      expect(r.notes, isEmpty);
      final b = r.background!;
      expect((b.fit, b.tile, b.maskFollowsTheme, b.maskColor, b.brightness), (null, null, null, null, null));
      expect((b.dim, b.blur), (0.3, 8.0));
    });

    test('不认识的字段忽略，不影响图', () {
      final r = decodeThemeText(_file({'mime': 'image/png', 'data': _png, 'turns': 0, 'sticker': 'x', 'fit': 'contain'}));
      expect(r.background, isNotNull, reason: r.notes.join());
      expect(r.background!.fit, 'contain');
    });

    test('取值不对：整张图不用并说原因，主题本身照常导入', () {
      final bad = <String, Object?>{'fit': 'stretch', 'tile': 5, 'maskColor': '#12', 'brightness': 101};
      final words = {'fit': '适配方式', 'tile': '平铺大小', 'maskColor': '遮罩颜色', 'brightness': '亮度'};
      for (final e in bad.entries) {
        final r = decodeThemeText(_file({'mime': 'image/png', 'data': _png, e.key: e.value}));
        expect(r.ok, isTrue, reason: '${e.key}: 主题本身应该还能导入');
        expect(r.background, isNull, reason: '${e.key}=${e.value} 应该被拒');
        expect(r.notes.join(), contains(words[e.key]), reason: e.key);
      }
      for (final v in <Object?>[101, 9, 40.5, '40', null]) {
        expect(decodeThemeBackground({'mime': 'image/png', 'data': _png, 'tile': v}).$1, isNull, reason: 'tile=$v');
      }
      for (final v in <Object?>[-101, 0.5, 'x', null]) {
        expect(decodeThemeBackground({'mime': 'image/png', 'data': _png, 'brightness': v}).$1, isNull, reason: 'brightness=$v');
      }
      for (final v in <Object?>['#FF112233', 'red', 0x112233, null]) {
        expect(decodeThemeBackground({'mime': 'image/png', 'data': _png, 'maskColor': v}).$1, isNull, reason: 'maskColor=$v');
      }
      // 边界值是合法的
      final (ok, why) = decodeThemeBackground({'mime': 'image/png', 'data': _png, 'tile': 10, 'brightness': -100, 'maskColor': '#000000', 'fit': 'cover'});
      expect(ok, isNotNull, reason: why);
      expect((ok!.tile, ok.brightness, ok.maskColor, ok.maskFollowsTheme), (10, -100, 0, false));
    });
  });

  group('主题 ↔ 背景图片的对接口', () {
    late Directory tmp;
    late FakeBackdropPicker picker;

    ProviderContainer open(String name) {
      final c = ProviderContainer(overrides: [settingsStoreProvider.overrideWithValue(SettingsStore(File(p.join(tmp.path, name, 'settings.json'))))]);
      c.read(backdropPickerProvider.notifier).use(picker);
      addTearDown(c.dispose);
      return c;
    }

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('lopi_thbg_');
      picker = FakeBackdropPicker();
    });
    tearDown(() async {
      await pendingWrites();
      tmp.deleteSync(recursive: true);
    });

    Future<void> seed(ProviderContainer c, Uint8List bytes, {bool dark = false}) async {
      final n = c.read(backdropProvider.notifier);
      await n.ready;
      picker.script.add(BackdropPicked(writePick(tmp, 'pick-${bytes.length}.png', bytes)));
      final img = ((await n.pickAndImport()) as BackdropImportOk).image;
      if (dark) await n.setDarkSeparate(true);
      await n.setImage(dark: dark, image: img, crop: const CropRect(0.1, 0.2, 0.3, 0.4));
    }

    test('接上了：没图时说没有；有图时按浅色 / 深色各自回答', () async {
      final c = open('a');
      expect(c.read(themeBackgroundBridgeProvider), isNotNull);
      await c.read(backdropProvider.notifier).ready;
      expect(c.read(themeBackgroundBridgeProvider)!.hasImage(dark: false), isFalse);
      final none = await c.read(themeBackgroundBridgeProvider)!.export(dark: false);
      expect(none.data, isNull);
      expect(none.error, contains('没有背景图片'));

      await seed(c, await makePng(40, 30));
      expect(c.read(themeBackgroundBridgeProvider)!.hasImage(dark: false), isTrue);
      expect(c.read(themeBackgroundBridgeProvider)!.hasImage(dark: true), isTrue, reason: '深色没单独设置时用的也是这一张');
      await c.read(backdropProvider.notifier).setDarkSeparate(true);
      c.read(backdropProvider.notifier).updateLook(dark: true, change: (l) => l.withoutImage());
      expect(c.read(themeBackgroundBridgeProvider)!.hasImage(dark: true), isFalse, reason: '深色单独设置、又没图');
    });

    test('导出的那一节能直接进主题文件；另一台设备导入后图、裁剪、适配、平铺、遮罩色、亮度都一样', () async {
      final a = open('a');
      await seed(a, await makePng(80, 60));
      a
          .read(backdropProvider.notifier)
          .updateLook(dark: false, change: (l) => l.copyWith(maskOpacity: 35, blur: 12, brightness: -20, fit: BackdropFit.tile, tilePercent: 40, maskFollowsTheme: false, maskColor: 0xFF1B2A4A));
      final got = await a.read(themeBackgroundBridgeProvider)!.export(dark: false);
      expect(got.error, isNull);
      final section = got.data!;
      expect((section['fit'], section['tile'], section['maskColor'], section['brightness']), ('tile', 40, '#1B2A4A', -20));
      expect(section.containsKey('turns'), isFalse, reason: '主题格式里没有 turns（旋转已经画进图里）');
      // 放进文件再读：主题这边的检查过得去
      final text = _file(section);
      final decoded = decodeThemeText(text);
      expect(decoded.background, isNotNull, reason: decoded.notes.join());

      final b = open('b');
      await b.read(backdropProvider.notifier).ready;
      final raw = (jsonDecode(text) as Map)['background'] as Map;
      expect(await b.read(themeBackgroundBridgeProvider)!.import({for (final e in raw.entries) '${e.key}': e.value}, dark: false), isNull);
      final mine = a.read(backdropProvider).light, theirs = b.read(backdropProvider).light;
      expect(theirs.file, mine.file, reason: '同样的内容，同样的文件名');
      expect((theirs.fit, theirs.tilePercent, theirs.maskFollowsTheme, theirs.maskColor, theirs.brightness), (BackdropFit.tile, 40, false, 0xFF1B2A4A, -20));
      expect((theirs.maskOpacity, theirs.blur), (35, 12));
      expect(theirs.crop.left, closeTo(0.1, 1e-9));
      expect(theirs.crop.height, closeTo(0.4, 1e-9));
      expect(b.read(backdropProvider).enabled, isTrue);
      expect(b.read(backdropProvider).darkSeparate, isFalse);
    });

    test('“跟随主题”的遮罩导出成 theme，导入后还是跟随主题', () async {
      final a = open('a');
      await seed(a, await makePng(20, 20));
      final section = (await a.read(themeBackgroundBridgeProvider)!.export(dark: false)).data!;
      expect(section['maskColor'], 'theme');
      final b = open('b');
      await b.read(backdropProvider.notifier).ready;
      b.read(backdropProvider.notifier).updateLook(dark: false, change: (l) => l.copyWith(maskFollowsTheme: false, maskColor: 0xFF3A1420));
      expect(await b.read(themeBackgroundBridgeProvider)!.import(section, dark: false), isNull);
      expect(b.read(backdropProvider).light.maskFollowsTheme, isTrue);
    });

    test('老文件（没有四个新字段）：这四项保持导入方原样；模糊超过 30 收到 30', () async {
      final b = open('b');
      await b.read(backdropProvider.notifier).ready;
      b.read(backdropProvider.notifier).updateLook(dark: false, change: (l) => l.copyWith(fit: BackdropFit.contain, tilePercent: 70, maskFollowsTheme: false, maskColor: 0xFF12302A, brightness: 15));
      final png = base64Encode(await makePng(24, 24));
      expect(await b.read(themeBackgroundBridgeProvider)!.import({'mime': 'image/png', 'data': png, 'dim': 0.5, 'blur': 40}, dark: false), isNull);
      final l = b.read(backdropProvider).light;
      expect(l.hasImage, isTrue);
      expect((l.fit, l.tilePercent, l.maskFollowsTheme, l.maskColor, l.brightness), (BackdropFit.contain, 70, false, 0xFF12302A, 15));
      expect((l.maskOpacity, l.blur), (50, kBackdropBlurMax));
    });

    test('深色主题带的图放到深色那一份，并打开“深色单独设置”；浅色那份不动', () async {
      final b = open('b');
      await seed(b, await makePng(30, 30));
      final before = b.read(backdropProvider).light;
      final png = base64Encode(await makePng(26, 26));
      expect(await b.read(themeBackgroundBridgeProvider)!.import({'mime': 'image/png', 'data': png}, dark: true), isNull);
      final s = b.read(backdropProvider);
      expect(s.darkSeparate, isTrue);
      expect(s.dark.hasImage, isTrue);
      expect(s.dark.file, isNot(before.file));
      expect(s.light, before);
    });

    test('导出只带问的那一边：深色单独设置时 dark:true 带深色那张', () async {
      final a = open('a');
      await seed(a, await makePng(30, 30));
      await seed(a, await makePng(50, 20), dark: true);
      final bridge = a.read(themeBackgroundBridgeProvider)!;
      final light = (await bridge.export(dark: false)).data!, dark = (await bridge.export(dark: true)).data!;
      expect(light['data'], isNot(dark['data']));
      expect(base64Decode(dark['data']! as String), await a.read(backdropStoreProvider).imageFile(a.read(backdropProvider).dark.file!).readAsBytes());
    });

    test('文件里的图有问题：说明原因，原来的背景不动', () async {
      final b = open('b');
      await seed(b, await makePng(30, 30));
      final before = b.read(backdropProvider);
      final bridge = b.read(themeBackgroundBridgeProvider)!;
      expect(await bridge.import({'mime': 'image/png', 'data': '不是 base64'}, dark: false), contains('base64'));
      expect(await bridge.import({'mime': 'image/png', 'data': _png, 'tile': 500}, dark: false), contains('平铺'));
      expect(await bridge.import({'mime': 'image/jpeg', 'data': _png}, dark: false), isNotNull);
      expect(b.read(backdropProvider), before);
    });
  });

  group('表面不透明度：滑杆说了算，没动过用主题的数', () {
    test('没动过＝空；用主题的数；动过以后用滑杆的；“跟随主题”回到空', () {
      const s = BackdropSettings(loaded: true);
      expect(s.surfaceOverride, isNull);
      final themeOpacity = kDefaultLightTheme.metric(MetricKey.surfaceOpacity);
      expect(themeOpacity, 0.88);
      expect(s.surfaceAlpha(themeOpacity), 0.88);
      expect(s.surfaceShown(themeOpacity), 90, reason: '滑杆一步 5：0.88 凑到 90');
      expect(s.surfaceShown(0.3), kBackdropSurfaceMin, reason: '主题给的比滑杆下限还低时，滑杆停在下限（实际用的还是主题的数）');
      expect(s.surfaceAlpha(0.3), 0.3);
      final moved = s.copyWith(surfaceOpacity: 70);
      expect((moved.surfaceOverride, moved.surfaceAlpha(themeOpacity), moved.surfaceShown(themeOpacity)), (70, 0.7, 70));
      expect(moved.copyWith(enabled: false).surfaceOverride, 70, reason: '改别的不丢');
      expect(moved.copyWith(surfaceFromTheme: true).surfaceOverride, isNull);
    });

    test('存盘：没动过不写这一项，读回来还是空；动过的原样读回', () {
      const s = BackdropSettings(loaded: true);
      expect(s.toJson().containsKey('surfaceOpacity'), isFalse);
      expect(BackdropSettings.fromJson(s.toJson()).surfaceOverride, isNull);
      final moved = s.copyWith(surfaceOpacity: 55);
      expect(BackdropSettings.fromJson(jsonDecode(jsonEncode(moved.toJson()))), moved);
      expect(BackdropSettings.fromJson({'surfaceOpacity': '乱写'}).surfaceOverride, isNull, reason: '类型不对当没动过');
    });
  });
}
