// 主题编辑器的逻辑（不带界面）：颜色换算、手输颜色的宽松读法、可改项清单、撤销 / 重做、
// 换强调色、从主色生成整套、修对比度、导出文件落盘。
//   flutter test test/theme_editor_logic_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/appearance/theme_builtin.dart';
import 'package:lopicode/appearance/theme_color_math.dart';
import 'package:lopicode/appearance/theme_contrast.dart';
import 'package:lopicode/appearance/theme_edit_model.dart';
import 'package:lopicode/appearance/theme_export_file.dart';
import 'package:lopicode/appearance/theme_fields.dart';
import 'package:lopicode/appearance/theme_generate.dart';
import 'package:lopicode/appearance/theme_json.dart';
import 'package:lopicode/appearance/theme_spec.dart';
import 'package:lopicode/core/path_guard.dart';

void main() {
  group('颜色换算', () {
    test('HSV / HSL 来回换，颜色不变（差不超过 1/255）', () {
      for (final c in [0xFF2962CB, 0xFFE45649, 0xFF000000, 0xFFFFFFFF, 0xFF808080, 0xFF15151B, 0xFFFFC53D, 0xFF00FF00, 0xFFFF00FF]) {
        final hsv = argbToHsv(c);
        final hsl = argbToHsl(c);
        for (final back in [hsvToArgb(hsv.h, hsv.s, hsv.v), hslToArgb(hsl.h, hsl.s, hsl.l)]) {
          for (final shift in [16, 8, 0]) {
            expect((((back >> shift) & 0xFF) - ((c >> shift) & 0xFF)).abs(), lessThanOrEqualTo(1), reason: c.toRadixString(16));
          }
        }
      }
      expect(hsvToArgb(210, 0.5, 0.5, alpha: 0x40) >> 24, 0x40);
    });

    test('手输颜色的宽松读法', () {
      expect(parseLooseColor('#2962CB'), 0xFF2962CB);
      expect(parseLooseColor('2962cb'), 0xFF2962CB);
      expect(parseLooseColor('  # 29 62 CB '), 0xFF2962CB);
      expect(parseLooseColor('＃2962CB'), 0xFF2962CB, reason: '全角井号');
      expect(parseLooseColor('#abc'), 0xFFAABBCC);
      expect(parseLooseColor('#402962CB'), 0x402962CB);
      expect(parseLooseColor('0x402962cb'), 0x402962CB);
      expect(parseLooseColor('rgb(41, 98, 203)'), 0xFF2962CB);
      expect(parseLooseColor('rgba(41,98,203,0.5)'), 0x802962CB);
      for (final bad in ['', '#', '#12', '#12345', '#1234567', '#GGGGGG', 'red', 'rgb(300,0,0)', 'rgba(1,2,3,2)', '#123456789']) {
        expect(parseLooseColor(bad), isNull, reason: bad);
      }
    });

    test('ensureContrast：只动亮度、动到够为止；本来够的、半透明的不动', () {
      const bg = 0xFFFFFFFF;
      final fixed = ensureContrast(0xFFA0A1A7, [bg], 4.5);
      expect(contrastRatio(fixed, bg), greaterThanOrEqualTo(4.495));
      expect(argbToHsl(fixed).l, lessThan(argbToHsl(0xFFA0A1A7).l));
      expect(ensureContrast(0xFF15151B, [bg], 4.5), 0xFF15151B);
      expect(ensureContrast(0x40A0A1A7, [bg], 4.5), 0x40A0A1A7);
      // 同时放在两种底上：两边都要够。
      final both = ensureContrast(0xFF7090C0, [0xFFFFFFFF, 0xFFE0E0E0], 4.5);
      expect(contrastRatio(both, 0xFFFFFFFF), greaterThanOrEqualTo(4.495));
      expect(contrastRatio(both, 0xFFE0E0E0), greaterThanOrEqualTo(4.495));
      // 底是中灰：怎么调都不够 4.5 的话退到黑或白。
      expect([0xFF000000, 0xFFFFFFFF], contains(ensureContrast(0xFF777777, [0xFF777777, 0xFF888888], 7)));
      expect(bestOn(0xFF2962CB), 0xFFFFFFFF);
      expect(bestOn(0xFFFFE068), 0xFF000000);
    });
  });

  group('可改项清单', () {
    test('191 个颜色项，标识不重复；各节的数和字段目录对得上', () {
      expect(kThemeItems.length, 191);
      expect({for (final i in kThemeItems) i.id}.length, 191);
      int n(String s) => kThemeItems.where((i) => i.section == s).length;
      expect([n('ui'), n('code'), n('tokens'), n('terminal'), n('blocks'), n('lowcode')], [45, 12, 55, 23, 35, 21]);
      expect(kMetricFields.length, 6);
      for (final i in kThemeItems) {
        expect(i.label, isNotEmpty, reason: i.id);
      }
    });

    test('读写一项；高亮分类可以设成“不单独上色”；哪些项能带透明度', () {
      final item = themeItemById('ui.accent')!;
      final t = setItemColor(kDefaultLightTheme, item, 0xFF123456);
      expect(itemColor(t, item), 0xFF123456);
      final kw = themeItemById('tokens.keyword')!;
      final t2 = setItemColor(kDefaultLightTheme.withToken('keyword', const TokenStyle(color: 0xFF112233, bold: true)), kw, null);
      expect(itemColor(t2, kw), isNull);
      expect(t2.tokens['keyword']!.bold, isTrue, reason: '只清颜色，粗体还在');
      expect(itemAllowsAlpha(themeItemById('code.selection')!), isTrue);
      expect(itemAllowsAlpha(themeItemById('ui.backdropScrim')!), isTrue);
      expect(itemAllowsAlpha(themeItemById('ui.text')!), isFalse);
      expect(itemDefaultColor(item, dark: true), kDefaultDarkTheme.ui[UiKey.accent]);
    });

    test('改过的项；对比度最吃紧的一对；步进', () {
      final t = kDefaultLightTheme.withColors('ui', {UiKey.text: 0xFF333333}).withToken('keyword', const TokenStyle(color: 0xFFA626A4, italic: true)).withMetric(MetricKey.radiusScale, 1.5);
      expect(changedThemeItems(kDefaultLightTheme, t), {'ui.text', 'tokens.keyword', 'metrics.radiusScale'});
      expect(changedThemeItems(kDefaultLightTheme, kDefaultLightTheme), isEmpty);

      final worst = worstContrastOf(kDefaultLightTheme, 'tokens.comment')!;
      expect(worst.ok, isFalse);
      expect(worst.asFg, isTrue);
      expect(worst.other, '代码 › 代码底色');
      expect(worstContrastOf(kDefaultLightTheme, 'ui.text')!.ok, isTrue);
      expect(worstContrastOf(kDefaultLightTheme, 'ui.accentFill')!.asFg, isFalse, reason: '它在清单里是当底用的');
      expect(worstContrastOf(kDefaultLightTheme, 'ui.scrim'), isNull);
      expect(lowContrastItems(checkThemeContrast(kDefaultDarkTheme)), containsAll(['tokens.comment', 'terminal.black']));

      final radius = kMetricFields.firstWhere((f) => f.key == MetricKey.radiusScale);
      expect(bumpMetric(radius, 1, 1), 1.1);
      expect(bumpMetric(radius, 2, 1), 2, reason: '到头不再走');
      expect(bumpMetric(radius, 0, -1), 0);
      final opacity = kMetricFields.firstWhere((f) => f.key == MetricKey.surfaceOpacity);
      expect(bumpMetric(opacity, 0.88, 1), 0.93);
      expect(formatMetric(1), '1.0');
      expect(formatMetric(0.88), '0.88');
    });
  });

  group('撤销 / 重做', () {
    ThemeSpec bg(ThemeSpec t, int c) => t.withColors('ui', {UiKey.bg: c});

    test('一步一步撤销、重做；新的改动清掉重做', () {
      var h = ThemeHistory(kDefaultLightTheme);
      expect([h.canUndo, h.canRedo, h.dirty], [false, false, false]);
      h = h.apply(bg(h.current, 0xFF111111));
      h = h.apply(bg(h.current, 0xFF222222));
      expect(h.dirty, isTrue);
      h = h.undo();
      expect(h.current.ui[UiKey.bg], 0xFF111111);
      h = h.undo();
      expect(h.current, kDefaultLightTheme);
      expect(h.dirty, isFalse);
      expect(h.undo().current, kDefaultLightTheme, reason: '没得撤了就不动');
      h = h.redo().redo();
      expect(h.current.ui[UiKey.bg], 0xFF222222);
      h = h.undo().apply(bg(h.current, 0xFF333333));
      expect(h.canRedo, isFalse);
    });

    test('同一个标记的连续改动并成一步；没变化不记', () {
      var h = ThemeHistory(kDefaultLightTheme);
      for (final c in [0xFF111111, 0xFF222222, 0xFF333333]) {
        h = h.apply(bg(h.current, c), tag: 'drag-1');
      }
      h = h.apply(bg(h.current, 0xFF444444), tag: 'drag-2');
      h = h.apply(h.current);
      h = h.undo();
      expect(h.current.ui[UiKey.bg], 0xFF333333);
      h = h.undo();
      expect(h.current, kDefaultLightTheme);
    });

    test('全部恢复为起点可以撤销，名字不丢；保存后起点换成现在这份', () {
      var h = ThemeHistory(kDefaultLightTheme.copyWith(id: 'u-1', name: '海边', builtin: false));
      h = h.apply(bg(h.current, 0xFF111111)).renamed('山里');
      expect(h.current.name, '山里');
      expect(h.dirty, isTrue);
      h = h.reset();
      expect(h.dirty, isFalse);
      expect(h.current.name, '山里');
      h = h.undo();
      expect(h.current.ui[UiKey.bg], 0xFF111111);
      h = h.saved();
      expect(h.dirty, isFalse);
      expect(h.canUndo, isTrue);
    });

    test('最多记 100 步', () {
      var h = ThemeHistory(kDefaultLightTheme);
      for (var i = 0; i < 130; i++) {
        h = h.apply(bg(h.current, 0xFF000000 + i));
      }
      var steps = 0;
      while (h.canUndo) {
        h = h.undo();
        steps++;
      }
      expect(steps, ThemeHistory.maxSteps);
    });
  });

  group('快捷生成', () {
    const accents = [0xFFE0457B, 0xFF00A86B, 0xFFFFD000, 0xFF101010, 0xFFFFFFFF, 0xFF7C4DFF, 0xFF2962CB, 0xFF808080];

    test('换强调色：这一组重算、同色的跟着换（透明度不变）、别的不动；强调色相关的对比度都够', () {
      for (final base in [kDefaultLightTheme, kDefaultDarkTheme]) {
        for (final accent in accents) {
          final t = reaccentTheme(base, accent);
          final why = '${base.id} ${accent.toRadixString(16)}';
          if (!sameRgb(accent, base.ui[UiKey.accentFill]!)) expect(t.ui[UiKey.accentFill], isNot(base.ui[UiKey.accentFill]), reason: why);
          expect(t.ui[UiKey.link], t.ui[UiKey.accent], reason: '链接原来和强调色同色，跟着走：$why');
          expect(t.code[CodeKey.cursor], t.ui[UiKey.accent], reason: why);
          expect(t.code[CodeKey.selection]! >> 24, base.code[CodeKey.selection]! >> 24, reason: '选区的透明度不变');
          expect(sameRgb(t.code[CodeKey.selection]!, t.ui[UiKey.accent]!), isTrue, reason: why);
          expect(t.ui[UiKey.selectedBg], t.ui[UiKey.accentSoft]);
          expect(t.ui[UiKey.danger], base.ui[UiKey.danger], reason: '无关的不动');
          expect(t.tokens, base.tokens);
          expect(t.blocks, base.blocks);
          final issues = checkThemeContrast(t).map((i) => i.id).toSet();
          for (final id in ['ui.accent/ui.bg', 'ui.accent/ui.surface', 'ui.accent/ui.accentSoft', 'ui.accent/ui.selectedBg', 'ui.onAccent/ui.accentFill', 'ui.link/ui.bg']) {
            expect(issues, isNot(contains(id)), reason: '$why：$id');
          }
          expect(decodeThemeJson(encodeTheme(t)).ok, isTrue);
        }
      }
    });

    test('换强调色：中等深浅的颜色（青绿、橙）配白字并把按钮底压深；很浅的（黄）才配黑字', () {
      for (final accent in [0xFF00897B, 0xFFE8590C]) {
        final t = reaccentTheme(kDefaultLightTheme, accent);
        expect(t.ui[UiKey.onAccent], 0xFFFFFFFF, reason: accent.toRadixString(16));
        expect(contrastRatio(0xFFFFFFFF, t.ui[UiKey.accentFill]!), greaterThanOrEqualTo(4.49));
      }
      final yellow = reaccentTheme(kDefaultLightTheme, 0xFFFFE068);
      expect(yellow.ui[UiKey.onAccent], 0xFF000000);
      expect(yellow.ui[UiKey.accentFill], 0xFFFFE068, reason: '本来就够，不动');
    });

    test('从主色生成整套：每一套都过格式校验、对比度全部达标；底色带上了倾向；深浅关系没乱', () {
      const tints = [0xFF3355FF, 0xFFFF8800, 0xFF00AA88, 0xFF808080, 0xFFFF0066];
      for (final dark in [false, true]) {
        for (final tint in tints) {
          for (final accent in accents) {
            final t = generateTheme(dark: dark, tint: tint, accent: accent);
            final why = '${dark ? '深' : '浅'} 底 ${tint.toRadixString(16)} 强调 ${accent.toRadixString(16)}';
            final back = decodeThemeJson(encodeTheme(t));
            expect(back.ok, isTrue, reason: '$why：${back.error}');
            expect(back.notes, isEmpty, reason: why);
            expect(checkThemeContrast(t), isEmpty, reason: why);
            expect(t.dark, dark);
            for (final item in kThemeItems) {
              expect(itemColor(t, item) != null || item.isToken, isTrue, reason: '${item.id} 缺了');
            }
            // 深浅关系：浅色主题正文比底色暗，深色反过来。
            final text = relativeLuminance(t.ui[UiKey.text]!), bg = relativeLuminance(t.ui[UiKey.bg]!);
            expect(dark ? text > bg : text < bg, isTrue, reason: why);
          }
        }
      }
      // 灰的底色倾向 → 底色是纯灰；有颜色的 → 底色的色相跟着它。
      final gray = generateTheme(dark: false, tint: 0xFF808080, accent: 0xFF2962CB);
      expect(argbToHsl(gray.ui[UiKey.canvas]!).s, lessThan(0.01));
      final warm = generateTheme(dark: true, tint: 0xFFFF8800, accent: 0xFF2962CB);
      final hsl = argbToHsl(warm.ui[UiKey.bg]!);
      expect(hsl.s, greaterThan(0.1));
      expect((hsl.h - argbToHsv(0xFFFF8800).h).abs(), lessThan(8));
      expect(argbToHsl(warm.ui[UiKey.bg]!).l, closeTo(argbToHsl(kDefaultDarkTheme.ui[UiKey.bg]!).l, 0.02), reason: '亮度照默认主题的骨架');
    });

    test('生成时沿用外壳的标识、名字、作者和形状与密度', () {
      final shell = kDefaultDarkTheme.copyWith(id: 'u-abc', name: '夜航', author: () => '霜霜', builtin: false).withMetric(MetricKey.radiusScale, 1.6);
      final t = generateTheme(dark: true, tint: 0xFF3355FF, accent: 0xFFE0457B, shell: shell);
      expect([t.id, t.name, t.author, t.builtin], ['u-abc', '夜航', '霜霜', false]);
      expect(t.metric(MetricKey.radiusScale), 1.6);
    });

    test('修对比度：两套默认主题的已知不达标项都能调到达标，色相不变；可以只修指定的几项', () {
      for (final base in [kDefaultLightTheme, kDefaultDarkTheme]) {
        expect(checkThemeContrast(base), isNotEmpty);
        final t = repairContrast(base);
        expect(checkThemeContrast(t), isEmpty, reason: base.id);
        final before = argbToHsl(base.tokens['comment']!.color!), after = argbToHsl(t.tokens['comment']!.color!);
        expect((before.h - after.h).abs(), lessThan(3));
        expect(t.ui[UiKey.text], base.ui[UiKey.text], reason: '本来就够的不动');
      }
      final one = repairContrast(kDefaultLightTheme, only: {'tokens.comment/code.bg'});
      expect(one.tokens['comment'], isNot(kDefaultLightTheme.tokens['comment']));
      expect(one.tokens['string'], kDefaultLightTheme.tokens['string']);
    });
  });

  group('导出文件', () {
    test('文件名：去掉不能用的字符、太长截短、空名字有兜底', () {
      expect(themeFileStem('海边'), '海边');
      expect(themeFileStem('  a/b\\c:d*e?"f<g>h|i  '), 'abcdefghi');
      expect(themeFileStem('我的 深色 主题'), '我的-深色-主题');
      expect(themeFileStem('../..'), '主题');
      expect(themeFileStem('///'), '主题');
      expect(themeFileStem('很' * 60).runes.length, 24);
      expect(formatThemeBytes(1536), '1.5 KB');
      expect(formatThemeBytes(3 * 1024 * 1024), '3.0 MB');
    });

    test('写进工作区的 exports/；同一秒再写一份不盖掉上一份；写出来的能原样读回', () async {
      final tmp = Directory.systemTemp.createTempSync('lopi_theme_export_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final guard = PathGuard(tmp.path);
      final theme = kDefaultDarkTheme.copyWith(id: 'u-1', name: '夜/航', builtin: false);
      final text = encodeThemeText(theme);
      final now = DateTime(2026, 11, 26, 4, 5, 6);
      final a = await writeThemeExport(guard, text, name: theme.name, now: now);
      final b = await writeThemeExport(guard, text, name: theme.name, now: now);
      expect(a, 'exports/主题-夜航-20261126-040506.lopitheme.json');
      expect(b, 'exports/主题-夜航-20261126-040506-2.lopitheme.json');
      final read = decodeThemeText(File(guard.resolve(a)).readAsStringSync());
      expect(read.ok, isTrue);
      expect(read.theme, theme);
      expect(themeTextBytes(text), File(guard.resolve(a)).lengthSync());
    });
  });
}
