// 主题文件（导入导出第 1 版）的读写：往返不走样；坏数据返回一句人话，不抛异常；未知字段跳过；缺的从默认主题补。
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/appearance/theme_builtin.dart';
import 'package:lopicode/appearance/theme_fields.dart';
import 'package:lopicode/appearance/theme_json.dart';
import 'package:lopicode/appearance/theme_spec.dart';

Map<String, Object?> _file(Map<String, Object?> theme, {Object? version = 1, Object? format = 'lopicode-theme', Object? background}) => {
  'format': ?format,
  'version': ?version,
  'theme': theme,
  'background': ?background,
};

Map<String, Object?> _min({bool dark = false}) => {'name': '我的', 'dark': dark};

/// 最小的 PNG 文件头（只用来过“内容和格式对得上”的检查）。
Uint8List _png() => Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0]);

void main() {
  group('颜色的写法', () {
    test('#RRGGBB、#AARRGGBB 都认，大小写都行', () {
      expect(parseThemeColor('#102030'), 0xFF102030);
      expect(parseThemeColor('#80a0B0c0'), 0x80A0B0C0);
      expect(parseThemeColor(' #FFFFFF '), 0xFFFFFFFF);
    });

    test('别的写法都不认', () {
      for (final bad in <Object?>['102030', '#12345', '#1234567', '#GGGGGG', 'red', 'rgb(1,2,3)', '', 0xFF102030, null, true, <String>[]]) {
        expect(parseThemeColor(bad), isNull, reason: '$bad');
      }
    });

    test('写出去：不透明的省掉 FF，带透明度的写 8 位', () {
      expect(formatThemeColor(0xFF102030), '#102030');
      expect(formatThemeColor(0x80A0B0C0), '#80A0B0C0');
      expect(formatThemeColor(0x00000000), '#00000000');
    });
  });

  group('往返', () {
    for (final t in kBuiltinThemes) {
      test('${t.name}：写成文本再读回来，每一项都一样', () {
        final text = encodeThemeText(t);
        final r = decodeThemeText(text);
        expect(r.ok, isTrue, reason: r.error);
        expect(r.notes, isEmpty);
        expect(r.background, isNull);
        final back = r.theme!;
        expect(back.id, t.id);
        expect(back.name, t.name);
        expect(back.dark, t.dark);
        expect(back.builtin, isFalse, reason: '读进来的永远不是内置的');
        for (final s in kThemeColorSections.keys) {
          expect(back.section(s), t.section(s), reason: s);
        }
        expect(back.tokens, t.tokens);
        expect(back.metrics, t.metrics);
        expect(utf8.encode(text).length, lessThan(kThemeMaxBytes ~/ 8), reason: '一份主题才几 KB');
      });
    }

    test('改过的主题：颜色、粗体斜体、倍率、作者都能带过去', () {
      final t = kDefaultDarkTheme
          .copyWith(id: 'u-abc-1', name: '夜里用的', author: () => '霜霜', builtin: false)
          .withColors('ui', {UiKey.accent: 0xFF112233, UiKey.scrim: 0x80445566})
          .withColors('blocks', {BlockKey.selection: 0xFFABCDEF})
          .withToken('keyword', const TokenStyle(color: 0xFF010203, bold: true))
          .withToken('comment', const TokenStyle(italic: true))
          .withMetric(MetricKey.radiusScale, 1.5)
          .withMetric(MetricKey.fontScale, 0.9);
      final r = decodeThemeText(encodeThemeText(t));
      expect(r.ok, isTrue, reason: r.error);
      final back = r.theme!;
      expect(back.author, '霜霜');
      expect(back.ui[UiKey.accent], 0xFF112233);
      expect(back.ui[UiKey.scrim], 0x80445566);
      expect(back.blocks[BlockKey.selection], 0xFFABCDEF);
      expect(back.tokens['keyword'], const TokenStyle(color: 0xFF010203, bold: true));
      expect(back.tokens['comment'], const TokenStyle(italic: true));
      expect(back.metric(MetricKey.radiusScale), 1.5);
      expect(back.metric(MetricKey.fontScale), 0.9);
      expect(back, t.copyWith(builtin: false));
    });

    test('写出去的文件：有 format、version，颜色是 # 开头的文本，没有“内置”这种内部字段', () {
      final json = encodeTheme(kDefaultLightTheme);
      expect(json['format'], 'lopicode-theme');
      expect(json['version'], 1);
      expect(json.containsKey('background'), isFalse);
      final theme = json['theme']! as Map<String, Object?>;
      expect(theme.keys.toSet(), {'id', 'name', 'dark', 'ui', 'code', 'terminal', 'blocks', 'lowcode', 'tokens', 'metrics'});
      expect((theme['ui']! as Map)[UiKey.bg], '#FCFCFC');
      expect((theme['blocks']! as Map)[BlockKey.ghost], '#33000000');
      expect(((theme['tokens']! as Map)['keyword'] as Map)['color'], '#A626A4');
    });
  });

  group('缺的补齐、不认识的跳过', () {
    test('只有名字和明暗：其余全部从同明暗的默认主题来', () {
      for (final dark in [false, true]) {
        final r = decodeThemeJson(_file(_min(dark: dark)));
        expect(r.ok, isTrue, reason: r.error);
        final t = r.theme!;
        final base = defaultThemeFor(dark: dark);
        expect(t.name, '我的');
        expect(t.dark, dark);
        expect(t.id, '', reason: '文件里没有标识：留空，落盘时由状态层分配');
        for (final s in kThemeColorSections.keys) {
          expect(t.section(s), base.section(s), reason: s);
        }
        expect(t.tokens, base.tokens);
        expect(t.metrics, base.metrics);
      }
    });

    test('只改一个颜色：那一个变了，同一节别的还是默认的', () {
      final r = decodeThemeJson(
        _file({
          ..._min(),
          'ui': {UiKey.accent: '#FF0000'},
        }),
      );
      expect(r.ok, isTrue, reason: r.error);
      expect(r.theme!.ui[UiKey.accent], 0xFFFF0000);
      expect(r.theme!.ui[UiKey.bg], kDefaultLightTheme.ui[UiKey.bg]);
    });

    test('高亮分类可以只写一个颜色文本', () {
      final r = decodeThemeJson(
        _file({
          ..._min(),
          'tokens': {'keyword': '#123456'},
        }),
      );
      expect(r.ok, isTrue, reason: r.error);
      expect(r.theme!.tokens['keyword'], const TokenStyle(color: 0xFF123456));
    });

    test('不认识的字段、不认识的键：跳过，并在说明里告诉人跳过了几个', () {
      final r = decodeThemeJson({
        ..._file({
          ..._min(),
          'ui': {'notAKey': '#FFFFFF', UiKey.bg: '#000000'},
          'tokens': {'no-such-token': '#FFFFFF'},
          'metrics': {'gravity': 9.8},
          'futureSection': {'x': 1},
        }),
        'extra': 'ignored',
      });
      expect(r.ok, isTrue, reason: r.error);
      expect(r.theme!.ui[UiKey.bg], 0xFF000000);
      expect(r.theme!.ui.containsKey('notAKey'), isFalse);
      expect(r.notes, hasLength(1));
      expect(r.notes.single, contains('5'), reason: '三个键 + 一整节 futureSection + 最外层的 extra');
    });

    test('标识不合规矩：当作没有', () {
      for (final id in <Object?>['../etc/passwd', 'A-B', 'a b', '-abc', 'x' * 60, 42, null]) {
        final r = decodeThemeJson(_file({..._min(), 'id': ?id}));
        expect(r.ok, isTrue, reason: '$id');
        expect(r.theme!.id, '', reason: '$id');
      }
      expect(isValidThemeId('u-abc-1'), isTrue);
      expect(isValidThemeId('default-light'), isTrue);
    });

    test('名字、作者两头的空格去掉；作者是空的当作没有', () {
      final r = decodeThemeJson(_file({'name': '  海边  ', 'dark': false, 'author': '   '}));
      expect(r.theme!.name, '海边');
      expect(r.theme!.author, isNull);
    });
  });

  group('坏数据：一句人话，不抛异常', () {
    final cases = <String, (Object?, String)>{
      '不是对象': (42, '最外层'),
      '是列表': (<Object?>[], '最外层'),
      '没有 format': (_file(_min(), format: null), 'format'),
      'format 不对': (_file(_min(), format: 'vscode-theme'), 'format'),
      '没有版本': (_file(_min(), version: null), '版本'),
      '版本是文本': (_file(_min(), version: '1'), '版本'),
      '版本是 0': (_file(_min(), version: 0), '版本'),
      '版本比认得的新': (_file(_min(), version: 2), '更新版本'),
      '没有 theme': ({'format': 'lopicode-theme', 'version': 1}, 'theme'),
      'theme 不是对象': ({'format': 'lopicode-theme', 'version': 1, 'theme': 'x'}, 'theme'),
      '没说明暗': (_file({'name': 'a'}), '浅色还是深色'),
      '明暗不是真假': (_file({'name': 'a', 'dark': 'yes'}), '浅色还是深色'),
      '没有名字': (_file({'dark': false}), '名字'),
      '名字是空的': (_file({'name': '   ', 'dark': false}), '名字'),
      '名字不是文本': (_file({'name': 12, 'dark': false}), '名字'),
      '名字太长': (_file({'name': '长' * 41, 'dark': false}), '太长'),
      '作者不是文本': (_file({..._min(), 'author': 5}), '作者'),
      '作者太长': (_file({..._min(), 'author': '长' * 41}), '作者'),
      '一节不是对象': (_file({..._min(), 'ui': '#FFFFFF'}), '界面'),
      '颜色写法不对': (
        _file({
          ..._min(),
          'ui': {UiKey.bg: 'red'},
        }),
        '不是颜色',
      ),
      '颜色是数字': (
        _file({
          ..._min(),
          'terminal': {'fg': 16777215},
        }),
        '不是颜色',
      ),
      '高亮一节不是对象': (_file({..._min(), 'tokens': 3}), '代码高亮'),
      '高亮分类不是对象也不是文本': (
        _file({
          ..._min(),
          'tokens': {'keyword': 3},
        }),
        '代码高亮',
      ),
      '高亮颜色写法不对': (
        _file({
          ..._min(),
          'tokens': {
            'keyword': {'color': 'blue'},
          },
        }),
        '写法不对',
      ),
      '粗体不是真假': (
        _file({
          ..._min(),
          'tokens': {
            'keyword': {'bold': 'yes'},
          },
        }),
        '粗体',
      ),
      '倍率一节不是对象': (_file({..._min(), 'metrics': 1}), '形状与密度'),
      '倍率不是数字': (
        _file({
          ..._min(),
          'metrics': {MetricKey.radiusScale: 'big'},
        }),
        '数字',
      ),
      '倍率超出范围（大）': (
        _file({
          ..._min(),
          'metrics': {MetricKey.fontScale: 5},
        }),
        '超出了范围',
      ),
      '倍率超出范围（小）': (
        _file({
          ..._min(),
          'metrics': {MetricKey.spaceScale: 0.1},
        }),
        '超出了范围',
      ),
    };
    for (final e in cases.entries) {
      test(e.key, () {
        final r = decodeThemeJson(e.value.$1);
        expect(r.ok, isFalse);
        expect(r.theme, isNull);
        expect(r.error, contains(e.value.$2));
      });
    }

    test('每个倍率：刚好在边上能过，过一点点就不行', () {
      for (final f in kMetricFields) {
        for (final v in [f.min, f.max]) {
          final r = decodeThemeJson(
            _file({
              ..._min(),
              'metrics': {f.key: v},
            }),
          );
          expect(r.ok, isTrue, reason: '${f.key}=$v');
        }
        for (final v in [f.min - 0.01, f.max + 0.01]) {
          final r = decodeThemeJson(
            _file({
              ..._min(),
              'metrics': {f.key: v},
            }),
          );
          expect(r.ok, isFalse, reason: '${f.key}=$v');
          expect(r.error, contains(f.label));
        }
      }
    });

    test('文本：空的、不是 JSON、太大', () {
      expect(decodeThemeText('').error, contains('空的'));
      expect(decodeThemeText('   \n ').error, contains('空的'));
      expect(decodeThemeText('{"format": ').error, contains('JSON'));
      expect(decodeThemeText('<html></html>').error, contains('JSON'));
      final huge = 'x' * (kThemeImportMaxBytes + 1);
      expect(decodeThemeText(huge).error, contains('太大'));
    });

    test('文件里的内容只当数据读：带脚本样子的文本原样当名字，不会被执行', () {
      final r = decodeThemeJson(_file({'name': r'${exit(1)} <script>', 'dark': false}));
      expect(r.ok, isTrue);
      expect(r.theme!.name, r'${exit(1)} <script>');
    });
  });

  group('附带的背景图', () {
    test('带上再读回来：图、裁剪、压暗、模糊都在', () {
      final bg = ThemeBackground(mime: 'image/png', bytes: _png(), cropX: 0.1, cropY: 0.2, cropW: 0.5, cropH: 0.6, dim: 0.3, blur: 12);
      final r = decodeThemeText(encodeThemeText(kDefaultLightTheme, background: bg));
      expect(r.ok, isTrue, reason: r.error);
      expect(r.notes, isEmpty);
      final back = r.background!;
      expect(back.mime, 'image/png');
      expect(back.bytes, _png());
      expect([back.cropX, back.cropY, back.cropW, back.cropH], [0.1, 0.2, 0.5, 0.6]);
      expect(back.dim, 0.3);
      expect(back.blur, 12);
    });

    final bad = <String, Object?>{
      '不是对象': 'x',
      '格式不支持': {'mime': 'image/svg+xml', 'data': base64Encode(_png())},
      '没有数据': {'mime': 'image/png'},
      '不是 base64': {'mime': 'image/png', 'data': '***'},
      '内容和声称的格式对不上': {'mime': 'image/jpeg', 'data': base64Encode(_png())},
    };
    for (final e in bad.entries) {
      test('图没法用（${e.key}）：主题照样读进来，只是不带图，并说明原因', () {
        final r = decodeThemeJson(_file(_min(), background: e.value));
        expect(r.ok, isTrue, reason: r.error);
        expect(r.background, isNull);
        expect(r.notes.single, contains('背景图'));
      });
    }

    test('裁剪范围不合理：当作没裁；压暗、模糊超范围：收回到范围里', () {
      final r = decodeThemeJson(
        _file(
          _min(),
          background: {
            'mime': 'image/png',
            'data': base64Encode(_png()),
            'crop': {'x': 0.8, 'y': 0, 'w': 0.5, 'h': 1},
            'dim': 7,
            'blur': -3,
          },
        ),
      );
      final bg = r.background!;
      expect([bg.cropX, bg.cropY, bg.cropW, bg.cropH], [0, 0, 1, 1]);
      expect(bg.dim, 1);
      expect(bg.blur, 0);
    });
  });
}
