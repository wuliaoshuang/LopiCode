// 主题界面用到的两个小状态（lib/state/theme_hooks.dart）和导入时读文件的那一步。
//   flutter test test/theme_hooks_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/appearance/theme_json.dart';
import 'package:lopicode/core/path_guard.dart';
import 'package:lopicode/core/safe_file.dart';
import 'package:lopicode/state/app_providers.dart';
import 'package:lopicode/state/backdrop_state.dart';
import 'package:lopicode/state/theme_hooks.dart';
import 'package:lopicode/ui/theme_import_screen.dart';
import 'package:riverpod/riverpod.dart';

import 'support/harness.dart';

void main() {
  group('最近用过的颜色', () {
    late TestEnv env;
    late ProviderContainer box;
    setUp(() async {
      env = await TestEnv.create();
      box = ProviderContainer(overrides: [appServicesProvider.overrideWithValue(env.services)]);
    });
    tearDown(() async {
      box.dispose();
      await env.dispose();
    });

    test('一开始是空的；记一个放最前面；重复的挪到最前不重复；最多 12 个', () {
      expect(box.read(recentColorsProvider), isEmpty);
      final n = box.read(recentColorsProvider.notifier);
      n.remember(0xFF112233);
      n.remember(0x80445566);
      expect(box.read(recentColorsProvider), [0x80445566, 0xFF112233]);
      n.remember(0xFF112233);
      expect(box.read(recentColorsProvider), [0xFF112233, 0x80445566]);
      for (var i = 0; i < 20; i++) {
        n.remember(0xFF000000 + i);
      }
      final now = box.read(recentColorsProvider);
      expect(now.length, kRecentColorsMax);
      expect(now.first, 0xFF000000 + 19);
      expect(now, isNot(contains(0xFF112233)), reason: '最早的被挤掉');
    });

    test('存进设置文件，换一个容器（等于重开应用）还在；设置里是坏内容时不崩、跳过坏的', () async {
      box.read(recentColorsProvider.notifier)
        ..remember(0xFF112233)
        ..remember(0x80445566);
      await pendingWrites();
      expect(env.services.settings.getString(kRecentColorsKey, ''), '#80445566,#FF112233');
      final again = ProviderContainer(overrides: [appServicesProvider.overrideWithValue(env.services)]);
      addTearDown(again.dispose);
      expect(again.read(recentColorsProvider), [0x80445566, 0xFF112233]);

      await env.services.settings.set(kRecentColorsKey, '乱写的,#12,#FFABCDEF,,#FFABCDEF,#GG000000, #FF010203 ');
      expect(box.read(recentColorsProvider), [0xFFABCDEF, 0xFF010203]);
    });

    // 2026-11-26 合并背景图片功能后接上了（原来这里断言的是“没接上”）；细的用例在 test/theme_background_fields_test.dart。
    test('背景图的对接口已经接上；还没设背景图时说“没有图”', () async {
      final bridge = box.read(themeBackgroundBridgeProvider);
      expect(bridge, isNotNull);
      await box.read(backdropProvider.notifier).ready;
      expect(box.read(themeBackgroundBridgeProvider)!.hasImage(dark: false), isFalse);
      expect(box.read(themeBackgroundBridgeProvider)!.hasImage(dark: true), isFalse);
    });
  });

  group('导入时从工作区读文件', () {
    late Directory dir;
    late PathGuard guard;
    setUp(() {
      dir = Directory.systemTemp.createTempSync('lopi_theme_file_');
      guard = PathGuard(dir.path);
    });
    tearDown(() => dir.deleteSync(recursive: true));

    Future<String> why(String relative) async {
      try {
        await readThemeFile(guard, relative);
      } on FormatException catch (e) {
        return e.message;
      }
      return '';
    }

    test('只列 .json，主题文件排前面', () {
      expect(themeFileCandidates(['a.txt', 'package.json', 'exports/主题-海边.lopitheme.json', 'lib/x.dart', 'B.JSON']), ['exports/主题-海边.lopitheme.json', 'package.json', 'B.JSON']);
    });

    test('读得出来的原样返回', () async {
      File('${dir.path}/a.json').writeAsStringSync('{"你好": 1}');
      expect(await readThemeFile(guard, 'a.json'), '{"你好": 1}');
    });

    test('不存在、不是文本、太大、越出工作区：各有一句原因，不抛别的异常', () async {
      expect(await why('没有.json'), startsWith('读不了这个文件'));
      File('${dir.path}/bin.json').writeAsBytesSync([0xFF, 0xFE, 0x00, 0x80, 0xC3]);
      expect(await why('bin.json'), contains('不是文本'));
      final big = File('${dir.path}/big.json').openSync(mode: FileMode.write);
      big.truncateSync(kThemeImportMaxBytes + 1);
      big.closeSync();
      expect(await why('big.json'), allOf(contains('超过了能收的'), contains('MB')));
      expect(await why('../outside.json'), isNotEmpty);
    });
  });
}
