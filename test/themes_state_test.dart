// 主题库的状态（ThemesNotifier）：列出、选用、新建、复制、保存、改名、删除、导入、导出，和“现在生效的主题”。
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/appearance/theme_builtin.dart';
import 'package:lopicode/appearance/theme_fields.dart';
import 'package:lopicode/appearance/theme_json.dart';
import 'package:lopicode/appearance/theme_spec.dart';
import 'package:lopicode/appearance/theme_store.dart';
import 'package:lopicode/core/safe_file.dart';
import 'package:lopicode/core/stores.dart';
import 'package:lopicode/state/themes_state.dart';
import 'package:lopicode/state/ui_prefs.dart';
import 'package:path/path.dart' as p;
import 'package:riverpod/riverpod.dart';

import 'support/harness.dart';

void main() {
  late TestEnv env;
  late ProviderContainer c;
  late ThemesNotifier n;
  late Directory dir;

  setUp(() async {
    env = await TestEnv.create();
    c = env.services.container;
    n = c.read(themesProvider.notifier);
    dir = Directory(p.join(env.tmp.path, 'themes'));
  });
  tearDown(() => env.dispose());

  ThemesView view() => c.read(themesProvider);
  List<String> filesOnDisk() => dir.existsSync() ? ([for (final e in dir.listSync()) p.basename(e.path)]..sort()) : [];

  group('一开始', () {
    test('只有内置的（两套默认排最前）；两个槽都是默认；不建目录', () {
      expect(view().builtin.map((t) => t.id), kBuiltinThemes.map((t) => t.id));
      expect(view().builtin.take(2).map((t) => t.id), [kDefaultLightThemeId, kDefaultDarkThemeId]);
      expect(view().user, isEmpty);
      expect(view().lightId, kDefaultLightThemeId);
      expect(view().darkId, kDefaultDarkThemeId);
      expect(view().light, same(kDefaultLightTheme));
      expect(view().dark, same(kDefaultDarkTheme));
      expect(dir.existsSync(), isFalse);
      expect(c.read(lightThemeProvider), same(kDefaultLightTheme));
      expect(c.read(darkThemeProvider), same(kDefaultDarkTheme));
    });

    test('list：按明暗分开列，内置的在前', () async {
      await n.create(dark: false, name: '甲');
      await n.create(dark: true, name: '乙');
      // 内置的不止两套了：这一种明暗的内置主题全在前面（默认那套打头），自己的排在后面。
      Iterable<String> builtinNames(bool dark) => kBuiltinThemes.where((t) => t.dark == dark).map((t) => t.name);
      expect(n.list(dark: false).map((t) => t.name), [...builtinNames(false), '甲']);
      expect(n.list(dark: true).map((t) => t.name), [...builtinNames(true), '乙']);
      expect(n.list(dark: false).first.name, '默认浅色');
      expect(n.list(dark: true).first.name, '默认深色');
    });
  });

  group('新建、复制', () {
    test('create：从同明暗的默认主题复制一份，落盘，不自动选用', () async {
      final r = await n.create(dark: true);
      expect(r.ok, isTrue, reason: r.error);
      final t = r.theme!;
      expect(t.dark, isTrue);
      expect(t.builtin, isFalse);
      expect(t.name, '我的深色主题');
      expect(isValidThemeId(t.id), isTrue);
      expect(t.id, startsWith('u-'));
      expect(t.ui, kDefaultDarkTheme.ui);
      expect(view().user.single, t);
      expect(view().darkId, kDefaultDarkThemeId, reason: '新建不等于选用');
      expect(filesOnDisk(), ['${t.id}.json']);
      final onDisk = jsonDecode(File(p.join(dir.path, '${t.id}.json')).readAsStringSync()) as Map<String, Object?>;
      expect(onDisk['format'], 'lopicode-theme');
      expect((onDisk['theme']! as Map)['name'], '我的深色主题');
    });

    test('名字撞了自动加 2、3；标识各不相同', () async {
      final a = await n.create(dark: false);
      final b = await n.create(dark: false);
      final d = await n.create(dark: false);
      expect([a, b, d].map((r) => r.theme!.name), ['我的浅色主题', '我的浅色主题 2', '我的浅色主题 3']);
      expect({a.theme!.id, b.theme!.id, d.theme!.id}.length, 3);
    });

    test('duplicate：内置的也能复制；副本是自己的、可以改', () async {
      final r = await n.duplicate(kDefaultLightThemeId);
      expect(r.ok, isTrue, reason: r.error);
      expect(r.theme!.name, '默认浅色 副本');
      expect(r.theme!.builtin, isFalse);
      expect(r.theme!.dark, isFalse);
      final again = await n.duplicate(r.theme!.id, name: '海边');
      expect(again.theme!.name, '海边');
      expect(view().user, hasLength(2));
      expect((await n.duplicate('no-such')).error, contains('找不到'));
    });

    test('名字不合规矩：说人话，不落盘', () async {
      expect((await n.create(dark: false, name: '   ')).error, contains('名字'));
      expect((await n.create(dark: false, name: '长' * 41)).error, contains('太长'));
      expect(filesOnDisk(), isEmpty);
    });

    test('最多 $kMaxUserThemes 套', () async {
      for (var i = 0; i < kMaxUserThemes; i++) {
        final r = await n.create(dark: i.isEven, name: '第 $i 套');
        expect(r.ok, isTrue, reason: r.error);
      }
      final over = await n.create(dark: false, name: '多出来的');
      expect(over.ok, isFalse);
      expect(over.error, contains('$kMaxUserThemes'));
      expect(view().user, hasLength(kMaxUserThemes));
      expect((await n.importText(encodeThemeText(kDefaultLightTheme))).ok, isFalse, reason: '导入也算在上限里');
    });
  });

  group('选用', () {
    test('select：浅色的进浅色槽、深色的进深色槽，存进设置', () async {
      final light = (await n.create(dark: false, name: '白天')).theme!;
      final dark = (await n.create(dark: true, name: '夜里')).theme!;
      expect(await n.select(light.id), isNull);
      expect(await n.select(dark.id), isNull);
      expect(view().light, light);
      expect(view().dark, dark);
      expect(c.read(lightThemeProvider), light);
      expect(c.read(darkThemeProvider), dark);
      expect(env.services.settings.getString(SettingKeys.themeLight), light.id);
      expect(env.services.settings.getString(SettingKeys.themeDark), dark.id);
      expect(await n.select(kDefaultLightThemeId), isNull);
      expect(view().light, same(kDefaultLightTheme));
      expect(view().dark, dark, reason: '换浅色那套不影响深色槽');
    });

    test('找不到的标识：说一句原因，槽不变', () async {
      expect(await n.select('nope'), contains('找不到'));
      expect(view().lightId, kDefaultLightThemeId);
    });

    test('设置文件里记的标识指向一套不在了的主题、或者明暗对不上：退回默认', () async {
      await env.services.settings.set(SettingKeys.themeLight, 'u-gone-0');
      await env.services.settings.set(SettingKeys.themeDark, kDefaultLightThemeId);
      expect(view().lightId, 'u-gone-0');
      expect(view().light, same(kDefaultLightTheme));
      expect(view().dark, same(kDefaultDarkTheme), reason: '深色槽里不能放一套浅色主题');
    });

    test('切主题只通知该通知的：换深色那套，浅色的订阅者不动', () async {
      final dark = (await n.create(dark: true, name: '夜里')).theme!;
      var lightHits = 0, darkHits = 0;
      final s1 = c.listen(lightThemeProvider, (_, _) => lightHits++);
      final s2 = c.listen(darkThemeProvider, (_, _) => darkHits++);
      addTearDown(s1.close);
      addTearDown(s2.close);
      await n.select(dark.id);
      c.read(darkThemeProvider);
      c.read(lightThemeProvider);
      expect(darkHits, 1);
      expect(lightHits, 0);
    });
  });

  group('现在生效的主题（跟着外观模式走）', () {
    test('浅色 / 深色 / 跟随系统', () async {
      final light = (await n.create(dark: false, name: '白天')).theme!;
      final dark = (await n.create(dark: true, name: '夜里')).theme!;
      await n.select(light.id);
      await n.select(dark.id);
      await c.read(themeModeProvider.notifier).set(AppThemeMode.system);
      expect(c.read(activeThemeProvider(false)), light);
      expect(c.read(activeThemeProvider(true)), dark);
      await c.read(themeModeProvider.notifier).set(AppThemeMode.light);
      expect(c.read(activeThemeProvider(true)), light, reason: '选了浅色：系统是深色也用浅色那套');
      await c.read(themeModeProvider.notifier).set(AppThemeMode.dark);
      expect(c.read(activeThemeProvider(false)), dark);
    });
  });

  group('保存、改名', () {
    test('save：改了颜色存回去，标识不变，正在用的话界面拿到的是新的', () async {
      final t = (await n.create(dark: false, name: '白天')).theme!;
      await n.select(t.id);
      final next = t.withColors('ui', {UiKey.accent: 0xFF123456}).withMetric(MetricKey.radiusScale, 1.5);
      expect(await n.save(next), isNull);
      expect(view().user.single.ui[UiKey.accent], 0xFF123456);
      expect(c.read(lightThemeProvider).ui[UiKey.accent], 0xFF123456);
      expect(c.read(lightThemeProvider).metric(MetricKey.radiusScale), 1.5);
      expect(filesOnDisk(), ['${t.id}.json']);
      // 重新读盘：还在。
      final again = ThemeStore(dir);
      await again.load();
      expect(again.byId(t.id)!.ui[UiKey.accent], 0xFF123456);
    });

    test('save 的规矩：内置的不能直接改；明暗不许换；名字要合规矩；倍率要在范围里', () async {
      expect(await n.save(kDefaultLightTheme.withColors('ui', {UiKey.accent: 0xFF000000})), contains('复制一份'));
      final t = (await n.create(dark: false, name: '白天')).theme!;
      expect(await n.save(t.copyWith(dark: true)), contains('深色'));
      expect(await n.save(t.copyWith(name: '')), contains('名字'));
      expect(await n.save(t.withMetric(MetricKey.fontScale, 9)), contains('超出了范围'));
      expect(view().user.single, t, reason: '没存上的都不该改到库里');
    });

    test('rename：改名；重名、空名、内置的都不行', () async {
      final a = (await n.create(dark: false, name: '甲')).theme!;
      final b = (await n.create(dark: false, name: '乙')).theme!;
      expect(await n.rename(a.id, ' 丙 '), isNull);
      expect(view().byId(a.id)!.name, '丙');
      expect(await n.rename(b.id, '丙'), contains('已经有'));
      expect(await n.rename(b.id, '默认浅色'), contains('已经有'));
      expect(await n.rename(b.id, '  '), contains('名字'));
      expect(await n.rename(kDefaultDarkThemeId, '别的'), contains('内置'));
      expect(await n.rename(b.id, '乙'), isNull, reason: '改成自己现在的名字不算重名');
    });
  });

  group('删除', () {
    test('删掉没在用的：文件没了，槽不动', () async {
      final t = (await n.create(dark: false, name: '白天')).theme!;
      expect(await n.delete(t.id), isNull);
      expect(view().user, isEmpty);
      expect(filesOnDisk(), isEmpty);
      expect(view().lightId, kDefaultLightThemeId);
    });

    test('删掉正在用的：那个槽退回默认，另一个槽不动', () async {
      final light = (await n.create(dark: false, name: '白天')).theme!;
      final dark = (await n.create(dark: true, name: '夜里')).theme!;
      await n.select(light.id);
      await n.select(dark.id);
      expect(await n.delete(light.id), isNull);
      expect(view().lightId, kDefaultLightThemeId);
      expect(c.read(lightThemeProvider), same(kDefaultLightTheme));
      expect(env.services.settings.getString(SettingKeys.themeLight), kDefaultLightThemeId);
      expect(view().dark, dark);
    });

    test('内置的、不存在的：删不了', () async {
      expect(await n.delete(kDefaultLightThemeId), contains('内置'));
      expect(await n.delete('nope'), isNotNull);
      expect(view().builtin, hasLength(kBuiltinThemes.length));
    });
  });

  group('导入、导出', () {
    test('导出再导入：内容一样，但永远当一套新的存（新标识、不盖掉原来的），不自动选用', () async {
      final t = (await n.create(dark: true, name: '夜里')).theme!;
      await n.save(t.withColors('terminal', {'red': 0xFFAA0000}).withToken('keyword', const TokenStyle(color: 0xFF00AA00, italic: true)));
      final text = n.exportText(t.id)!;
      final r = await n.importText(text);
      expect(r.ok, isTrue, reason: r.error);
      final got = r.theme!;
      expect(got.id, isNot(t.id));
      expect(got.name, '夜里 2', reason: '重名自动加 2');
      expect(got.terminal['red'], 0xFFAA0000);
      expect(got.tokens['keyword'], const TokenStyle(color: 0xFF00AA00, italic: true));
      expect(view().user, hasLength(2));
      expect(view().darkId, kDefaultDarkThemeId);
      expect(filesOnDisk(), hasLength(2));
    });

    test('内置主题也能导出；导出的文件里不带“内置”，导入后是自己的', () async {
      final text = n.exportText(kDefaultLightThemeId)!;
      final r = await n.importText(text);
      expect(r.ok, isTrue, reason: r.error);
      expect(r.theme!.builtin, isFalse);
      expect(r.theme!.id, isNot(kDefaultLightThemeId));
      expect(r.theme!.name, '默认浅色 2');
      expect(n.exportText('nope'), isNull);
    });

    test('坏文件：返回原因，什么都不存', () async {
      for (final text in [
        '',
        '不是 JSON',
        '{"format":"x"}',
        jsonEncode({'format': 'lopicode-theme', 'version': 99, 'theme': <String, Object?>{}}),
      ]) {
        final r = await n.importText(text);
        expect(r.ok, isFalse, reason: text);
        expect(r.error, isNotEmpty);
      }
      expect(view().user, isEmpty);
      expect(filesOnDisk(), isEmpty);
    });

    test('文件里附带的背景图：交回给调用的人（这里不落盘）；带不带图由导出的人定', () async {
      final png = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0];
      final withBg = n.exportText(
        kDefaultDarkThemeId,
        background: ThemeBackground(mime: 'image/png', bytes: Uint8List.fromList(png), dim: 0.2),
      )!;
      final r = await n.importText(withBg);
      expect(r.ok, isTrue, reason: r.error);
      expect(r.background!.bytes, png);
      expect(r.background!.dim, 0.2);
      expect(filesOnDisk(), hasLength(1));
      expect(File(p.join(dir.path, filesOnDisk().single)).readAsStringSync().contains('background'), isFalse, reason: '主题文件里不存图');
    });

    test('未知字段：照样导入，并把“跳过了几个”带回来', () async {
      final json = encodeTheme(kDefaultLightTheme);
      (json['theme']! as Map<String, Object?>)['fromTheFuture'] = 1;
      final r = await n.importText(jsonEncode(json));
      expect(r.ok, isTrue, reason: r.error);
      expect(r.notes.single, contains('跳过'));
    });
  });

  group('重启以后', () {
    test('用户主题和两个槽的选择都还在', () async {
      final t = (await n.create(dark: true, name: '夜里')).theme!;
      await n.select(t.id);
      await pendingWrites();
      final settings = SettingsStore(File(p.join(env.tmp.path, 'settings.json')));
      await settings.load();
      expect(settings.getString(SettingKeys.themeDark), t.id);
      final store = ThemeStore(dir);
      await store.load();
      expect(store.user.single.name, '夜里');
      expect(store.user.single.id, t.id);
    });

    test('themes 目录里混进了坏文件、名字不合规矩的文件：跳过，别的照常', () async {
      final good = (await n.create(dark: false, name: '好的')).theme!;
      File(p.join(dir.path, 'u-broken-1.json')).writeAsStringSync('{"format": "lopicode-theme", "ver');
      File(p.join(dir.path, 'Not A Theme.json')).writeAsStringSync(encodeThemeText(kDefaultLightTheme));
      File(p.join(dir.path, 'readme.txt')).writeAsStringSync('hi');
      final store = ThemeStore(dir);
      await store.load();
      expect(store.user.map((t) => t.id), [good.id]);
    });
  });
}
