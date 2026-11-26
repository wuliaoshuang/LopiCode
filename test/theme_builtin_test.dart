// 内置主题（两套默认之外的那几套）：数量、明暗都有、每一节认真配过，对比度不靠登记例外。
//
// 通用清单（正文 4.5:1、图标和色块 3:1）在 test/theme_contrast_test.dart 里对每套内置主题都查；这里补的是
// “代码高亮 / 终端 16 色 / 积木 / 低代码编辑器”几块更细的要求，以及“各套之间真的不一样”。
//
// 口径（和任务要求的出入都写在这里）：
// - 高亮：凡是上了色的分类，在代码底色上 ≥ 4.5:1——**注释也按 4.5:1**（没有用“注释可放宽到 3:1”那一条），
//   “退后”靠的是它正好贴着 4.5:1 而别的类更高，外加斜体。
// - 终端：16 色在终端底色上 ≥ 3:1（“黑 / 亮黑”在深色底上、“白 / 亮白”在浅色底上也不例外：按惯例它们被调成看得见的灰）；
//   六个彩色和它们的亮色是当字用的，≥ 4.5:1。
// - 积木：字在 20 类主色上 ≥ 4.5:1；在由主色算出来的其余几档（顶部亮一点的、槽位、嵌套时提亮的）上 ≥ 3:1
//   （默认主题的口径是“4.5:1 上下”，嵌套提亮那一档本来就会低一点）。
// - 积木盒里挨着的两页色相至少差 40°（原 block_colors.dart 里写的原则；blocks_palette_v4_test 对默认主题查的是 25°）。
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/appearance/theme_builtin.dart';
import 'package:lopicode/appearance/theme_contrast.dart';
import 'package:lopicode/appearance/theme_fields.dart';
import 'package:lopicode/appearance/theme_spec.dart';
import 'package:lopicode/blocks/block_colors.dart';
import 'package:lopicode/blocks/block_host.dart';

/// 两套默认之外的内置主题。
final List<ThemeSpec> _extra = [
  for (final t in kBuiltinThemes)
    if (t.id != kDefaultLightThemeId && t.id != kDefaultDarkThemeId) t,
];

/// HSL 的色相（0–360）和饱和度（0–1）。
(double, double) _hueSat(int argb) {
  final r = ((argb >> 16) & 0xFF) / 255, g = ((argb >> 8) & 0xFF) / 255, b = (argb & 0xFF) / 255;
  final mx = math.max(r, math.max(g, b)), mn = math.min(r, math.min(g, b));
  if (mx == mn) return (0, 0);
  final d = mx - mn, l = (mx + mn) / 2;
  final s = d / (1 - (2 * l - 1).abs());
  final h = mx == r
      ? ((g - b) / d) % 6
      : mx == g
      ? (b - r) / d + 2
      : (r - g) / d + 4;
  return ((h * 60) % 360, s);
}

double _hueGap(int a, int b) {
  final d = (_hueSat(a).$1 - _hueSat(b).$1).abs();
  return d > 180 ? 360 - d : d;
}

/// 两个颜色差多远（RGB 里的距离，0–441）：只用来判断“是不是同一个色”。
double _dist(int a, int b) {
  num sq(int shift) => math.pow(((a >> shift) & 0xFF) - ((b >> shift) & 0xFF), 2);
  return math.sqrt(sq(16) + sq(8) + sq(0));
}

const _ansi = ['red', 'green', 'yellow', 'blue', 'magenta', 'cyan'];
String _bright(String k) => 'bright${k[0].toUpperCase()}${k.substring(1)}';

/// 积木盒里各页的顺序（设计稿 9.1，和 blocks_palette_v4_test 里的一样）。
const _paletteOrder = [
  BlockColorKey.variable,
  BlockColorKey.operator,
  BlockColorKey.control,
  BlockColorKey.function,
  BlockColorKey.text,
  BlockColorKey.list,
  BlockColorKey.dict,
  BlockColorKey.classes,
  BlockColorKey.error,
  BlockColorKey.async,
  BlockColorKey.custom,
];

/// 一眼要能分开的几类高亮。
const _mainTokens = ['comment', 'keyword', 'string', 'number', 'type', 'title.function', 'built_in', 'attr'];

void main() {
  group('内置主题清单', () {
    test('两套默认之外至少 6 套，浅色深色各至少 3 套；两套默认排在最前', () {
      expect(_extra.length, greaterThanOrEqualTo(6));
      expect(_extra.where((t) => !t.dark).length, greaterThanOrEqualTo(3));
      expect(_extra.where((t) => t.dark).length, greaterThanOrEqualTo(3));
      expect(kBuiltinThemes.take(2).map((t) => t.id), [kDefaultLightThemeId, kDefaultDarkThemeId]);
    });

    test('标识以 builtin- 开头、合规、不重复；名字是中文、不重复、不超过 40 个字；都标了“内置”', () {
      final valid = RegExp(r'^[a-z0-9][a-z0-9-]{0,47}$');
      for (final t in _extra) {
        expect(t.id, startsWith('builtin-'));
        expect(valid.hasMatch(t.id), isTrue, reason: t.id);
        expect(t.builtin, isTrue, reason: t.id);
        expect(t.name.trim(), isNotEmpty);
        expect(t.name.length, lessThanOrEqualTo(40));
        expect(RegExp(r'[\u4e00-\u9fff]').hasMatch(t.name), isTrue, reason: '${t.id} 的名字要是中文');
      }
      expect(kBuiltinThemes.map((t) => t.name).toSet().length, kBuiltinThemes.length);
      expect(kBuiltinThemes.map((t) => t.id).toSet().length, kBuiltinThemes.length);
    });

    test('各套真的不一样：页面底色、强调色、关键字色、积木画布两两不同；不是“只换了强调色”', () {
      for (var i = 0; i < kBuiltinThemes.length; i++) {
        for (var j = i + 1; j < kBuiltinThemes.length; j++) {
          final a = kBuiltinThemes[i], b = kBuiltinThemes[j];
          final why = '${a.id} 和 ${b.id}';
          expect(a.ui[UiKey.accent], isNot(b.ui[UiKey.accent]), reason: '$why 强调色');
          expect(a.tokens['keyword']!.color, isNot(b.tokens['keyword']!.color), reason: '$why 关键字');
          if (a.dark != b.dark) continue;
          // 同一种明暗的两套：五节里每一节都得有不少值不一样。
          for (final s in kThemeColorSections.keys) {
            final sa = a.section(s), sb = b.section(s);
            final diff = sa.keys.where((k) => sa[k] != sb[k]).length;
            expect(diff, greaterThan(sa.length ~/ 2), reason: '$why 的“${kThemeSectionLabels[s]}”一节只有 $diff 项不一样');
          }
          final tokDiff = a.tokens.keys.where((k) => a.tokens[k] != b.tokens[k]).length;
          expect(tokDiff, greaterThan(25), reason: '$why 的高亮只有 $tokDiff 类不一样');
        }
      }
    });
  });

  for (final t in _extra) {
    group('${t.name}（${t.id}）', () {
      final codeBg = t.code[CodeKey.bg]!;
      final termBg = t.terminal['bg']!;

      test('通用清单全过，一条例外都没登记', () {
        expect(checkThemeContrast(t).map((i) => i.toString()).toList(), isEmpty);
        expect(kKnownContrastGaps.containsKey(t.id), isFalse, reason: '新主题不登记例外，不达标就改颜色');
      });

      test('界面：底色分得出层次，分隔线看得见，文字三级由深到浅', () {
        final ui = t.ui;
        double l(String k) => relativeLuminance(ui[k]!);
        // 文字三级：正文最醒目，次要其次，提示最淡（都已在通用清单里过了 4.5:1）。
        final bg = ui[UiKey.bg]!;
        expect(contrastRatio(ui[UiKey.text]!, bg), greaterThan(contrastRatio(ui[UiKey.textMuted]!, bg)));
        expect(contrastRatio(ui[UiKey.textMuted]!, bg), greaterThan(contrastRatio(ui[UiKey.textFaint]!, bg)));
        // 卡片和它下面的分组页面底色、浅灰块和卡片：看得出是两层。
        expect(ui[UiKey.surface], isNot(ui[UiKey.canvas]));
        expect(ui[UiKey.surfaceMuted], isNot(ui[UiKey.surface]));
        expect(contrastRatio(ui[UiKey.surface]!, ui[UiKey.canvas]!), greaterThan(1.04), reason: '卡片要从分组页面底色上浮出来');
        // 分隔线在卡片和页面上都看得见（不要求 3:1：它是装饰线，不是文字）。
        expect(contrastRatio(ui[UiKey.border]!, ui[UiKey.surface]!), greaterThan(1.2));
        expect(contrastRatio(ui[UiKey.border]!, ui[UiKey.bg]!), greaterThan(1.15));
        // 明暗没有标反。
        expect(l(UiKey.bg) < 0.2, t.dark, reason: '主题标的明暗要和页面底色对得上');
        expect(l(UiKey.text) > 0.5, t.dark);
        // 危险色和强调色别混（色相差开，或者其中一个不是彩色）。
        final accentSat = _hueSat(ui[UiKey.accent]!).$2;
        if (accentSat > 0.25) expect(_hueGap(ui[UiKey.accent]!, ui[UiKey.danger]!), greaterThanOrEqualTo(20), reason: '强调色和危险色太像');
        // 四段占用条两两分得开。
        final charts = [
          for (final k in [UiKey.chart1, UiKey.chart2, UiKey.chart3, UiKey.chart4]) ui[k]!,
        ];
        for (var i = 0; i < 4; i++) {
          for (var j = i + 1; j < 4; j++) {
            expect(_dist(charts[i], charts[j]), greaterThan(60), reason: '占用条第 ${i + 1}、${j + 1} 段');
          }
        }
      });

      test('代码高亮：上了色的每一类在代码底色上 ≥ 4.5:1（注释也是）', () {
        for (final f in kTokenFields) {
          final c = t.tokens[f.key]!.color;
          if (c == null) continue;
          expect(contrastRatio(c, codeBg), greaterThanOrEqualTo(4.5), reason: '“${f.label}”');
          expect((c >> 24) & 0xFF, 0xFF, reason: '“${f.label}”不该带透明度');
        }
      });

      test('代码高亮：常用的类都配了色；主要几类一眼分得开；注释退后但可读', () {
        const mustColor = [
          'comment', 'keyword', 'string', 'number', 'literal', 'type', 'built_in', 'title', 'title.function', 'title.class', 'variable', 'property', //
          'regexp', 'char.escape', 'symbol', 'meta', 'doctag', 'name', 'attr', 'attribute', 'selector-tag', 'selector-id', 'selector-class', 'section', 'link', 'addition', 'deletion',
        ];
        for (final k in mustColor) {
          expect(t.tokens[k]!.color, isNotNull, reason: '“$k”要有自己的颜色');
        }
        expect(t.tokens.values.where((s) => s.color != null).length, greaterThanOrEqualTo(45), reason: '55 类里至少 45 类单独上色');
        // 没单独上色的那几类是有意的：“整段”类上色会把里面没标签的字全染掉；强调 / 加粗用字形表示。
        expect(t.tokens['emphasis']!.italic, isTrue);
        expect(t.tokens['strong']!.bold, isTrue);
        for (final k in ['function', 'function.dispatch', 'class', 'params', 'subst']) {
          expect(t.tokens[k]!.isPlain, isTrue, reason: '“$k”是整段的标签，跟代码文字一个色');
        }
        for (var i = 0; i < _mainTokens.length; i++) {
          for (var j = i + 1; j < _mainTokens.length; j++) {
            final a = t.tokens[_mainTokens[i]]!.color!, b = t.tokens[_mainTokens[j]]!.color!;
            expect(_dist(a, b), greaterThan(40), reason: '“${_mainTokens[i]}”和“${_mainTokens[j]}”太像');
          }
        }
        final fg = t.code[CodeKey.fg]!;
        for (final k in ['keyword', 'string', 'number', 'type', 'title.function']) {
          expect(_dist(t.tokens[k]!.color!, fg), greaterThan(40), reason: '“$k”和普通代码文字太像，等于没上色');
        }
        // 注释：比代码文字淡（退后），是斜体，对比度是所有上色分类里最低的那一档。
        final comment = contrastRatio(t.tokens['comment']!.color!, codeBg);
        expect(comment, lessThan(contrastRatio(fg, codeBg)));
        expect(t.tokens['comment']!.italic, isTrue);
        for (final k in ['keyword', 'string', 'number', 'type', 'title.function']) {
          expect(comment, lessThanOrEqualTo(contrastRatio(t.tokens[k]!.color!, codeBg) + 0.4), reason: '注释不该比“$k”还醒目');
        }
      });

      test('代码区域：文字、行号、光标、选区、当前行、查找命中、改动对比', () {
        final fg = t.code[CodeKey.fg]!;
        expect(contrastRatio(fg, codeBg), greaterThanOrEqualTo(7), reason: '代码文字要比“刚好能读”更清楚');
        // 行号比代码文字淡，当前行的行号更醒目。
        expect(contrastRatio(t.code[CodeKey.lineNumber]!, codeBg), lessThan(contrastRatio(t.code[CodeKey.lineNumberActive]!, codeBg)));
        // 选区、当前行、查找命中是半透明的：盖上去以后代码文字仍然 ≥ 4.5:1，而且看得出盖了一层。
        for (final k in [CodeKey.selection, CodeKey.currentLine, CodeKey.searchHit]) {
          final a = (t.code[k]! >> 24) & 0xFF;
          expect(a, inExclusiveRange(0, 255), reason: '$k 要带透明度');
          final under = compositeOver(t.code[k]!, codeBg);
          expect(contrastRatio(fg, under), greaterThanOrEqualTo(4.5), reason: '$k 盖上去以后的代码文字');
          expect(under, isNot(codeBg), reason: '$k 盖上去要看得出来');
        }
        expect(contrastRatio(compositeOver(t.code[CodeKey.selection]!, codeBg), codeBg), greaterThan(1.12), reason: '选区');
        // 新增是绿的、删除是红的（色相没配反），底色看得出区别。
        final add = _hueSat(t.code[CodeKey.diffAddFg]!).$1, del = _hueSat(t.code[CodeKey.diffDelFg]!).$1;
        expect(add, inInclusiveRange(70, 180), reason: '新增行的字是绿色系');
        expect(del < 40 || del > 330, isTrue, reason: '删除行的字是红色系');
        expect(_dist(t.code[CodeKey.diffAddBg]!, t.code[CodeKey.diffDelBg]!), greaterThan(20));
      });

      test('终端：16 色在终端底色上都看得清（彩色当字用 ≥ 4.5:1，黑白灰 ≥ 3:1）；红是红、绿是绿', () {
        expect(contrastRatio(t.terminal['fg']!, termBg), greaterThanOrEqualTo(7));
        for (final k in _ansi) {
          expect(contrastRatio(t.terminal[k]!, termBg), greaterThanOrEqualTo(4.5), reason: k);
          expect(contrastRatio(t.terminal[_bright(k)]!, termBg), greaterThanOrEqualTo(4.5), reason: _bright(k));
        }
        for (final k in ['black', 'white', 'brightBlack', 'brightWhite']) {
          expect(contrastRatio(t.terminal[k]!, termBg), greaterThanOrEqualTo(3), reason: k);
        }
        // 色相落在各自该在的范围里：程序输出靠这个表达含义（红＝错、绿＝成）。
        const ranges = {'red': (340.0, 30.0), 'green': (80.0, 170.0), 'yellow': (25.0, 75.0), 'blue': (200.0, 260.0), 'magenta': (270.0, 340.0), 'cyan': (165.0, 215.0)};
        for (final e in ranges.entries) {
          for (final k in [e.key, _bright(e.key)]) {
            final h = _hueSat(t.terminal[k]!).$1;
            final (lo, hi) = e.value;
            expect(lo <= hi ? (h >= lo && h <= hi) : (h >= lo || h <= hi), isTrue, reason: '$k 的色相 ${h.toStringAsFixed(0)}° 不在 $lo–$hi');
          }
        }
        // 六个彩色两两分得开。
        for (var i = 0; i < _ansi.length; i++) {
          for (var j = i + 1; j < _ansi.length; j++) {
            expect(_dist(t.terminal[_ansi[i]]!, t.terminal[_ansi[j]]!), greaterThan(45), reason: '${_ansi[i]} 和 ${_ansi[j]}');
          }
        }
        // 查找命中：两种底上字都读得清，当前命中和别的命中分得开。
        for (final k in ['searchHitBg', 'searchHitBgCurrent']) {
          expect(contrastRatio(t.terminal['searchHitFg']!, t.terminal[k]!), greaterThanOrEqualTo(4.5), reason: k);
        }
        expect(_dist(t.terminal['searchHitBg']!, t.terminal['searchHitBgCurrent']!), greaterThan(25));
        expect((t.terminal['selection']! >> 24) & 0xFF, inExclusiveRange(0, 255));
        expect(contrastRatio(t.terminal['fg']!, compositeOver(t.terminal['selection']!, termBg)), greaterThanOrEqualTo(4.5));
      });

      test('积木：字在 20 类主色上 ≥ 4.5:1，在算出来的其余几档上 ≥ 3:1；每类都从画布上分得出来', () {
        final p = BkPalette.fromTheme(t);
        final text = t.blocks[BlockKey.text]!;
        final canvas = t.blocks[BlockKey.canvas]!;
        for (final key in BlockColorKey.all) {
          final tone = p.tone(key);
          expect(tone.fill.toARGB32(), t.blocks[key], reason: key);
          expect(contrastRatio(text, tone.fill.toARGB32()), greaterThanOrEqualTo(4.5), reason: '$key：字和主色');
          for (final (name, c) in [('顶部', tone.fillTop), ('槽位', tone.deep), ('嵌套', tone.nested.fill), ('嵌套顶部', tone.nested.fillTop)]) {
            expect(contrastRatio(text, c.toARGB32()), greaterThanOrEqualTo(3), reason: '$key：字和$name那一档');
          }
          // 积木本体或它的底边，至少有一个从画布上看得出来。
          final vsCanvas = math.max(contrastRatio(tone.fill.toARGB32(), canvas), contrastRatio(tone.edge.toARGB32(), canvas));
          expect(vsCanvas, greaterThanOrEqualTo(1.5), reason: '$key：积木和画布');
        }
        expect({for (final key in BlockColorKey.all) t.blocks[key]}, hasLength(BlockColorKey.all.length), reason: '20 类没有两类同色');
        expect(contrastRatio(t.blocks[BlockKey.fieldText]!, t.blocks[BlockKey.fieldBg]!), greaterThanOrEqualTo(7), reason: '输入框里的字');
        // 输入框的底要和积木本体分得开（不然看不出哪里能填）。
        for (final key in BlockColorKey.all) {
          expect(contrastRatio(t.blocks[BlockKey.fieldBg]!, t.blocks[key]!), greaterThanOrEqualTo(1.5), reason: '$key：输入框和积木');
        }
      });

      test('积木：积木盒里挨着的两页色相至少差 40°；每一类的色系和默认主题一致（流程永远是紫的）', () {
        for (var i = 1; i < _paletteOrder.length; i++) {
          final a = _paletteOrder[i - 1], b = _paletteOrder[i];
          expect(_hueGap(t.blocks[a]!, t.blocks[b]!), greaterThanOrEqualTo(40), reason: '$a 和 $b 挨着');
        }
        // 换主题换的是“调子”（深浅、鲜不鲜），不是“哪一类是什么颜色”——用户是靠颜色认分类的。
        for (final key in BlockColorKey.all) {
          final base = kDefaultLightTheme.blocks[key]!;
          if (_hueSat(base).$2 < 0.2) continue; // “直接填的值”“不认识的”本来就是灰的
          expect(_hueGap(t.blocks[key]!, base), lessThanOrEqualTo(30), reason: '$key 的色相离默认太远');
        }
        // 两类灰的仍然是灰的，而且彼此分得开。
        for (final key in [BlockColorKey.value, BlockColorKey.unknown]) {
          expect(_hueSat(t.blocks[key]!).$2, lessThan(0.3), reason: '$key 应该是偏灰的');
        }
      });

      test('积木画布：选中描边、报错、警告标记 ≥ 3:1；点阵淡淡的；深色主题的积木不刺眼', () {
        final canvas = t.blocks[BlockKey.canvas]!;
        for (final k in [BlockKey.selection, BlockKey.error, BlockKey.warning]) {
          expect(contrastRatio(t.blocks[k]!, canvas), greaterThanOrEqualTo(3), reason: k);
        }
        final dot = contrastRatio(t.blocks[BlockKey.canvasDot]!, canvas);
        expect(dot, inInclusiveRange(1.1, 2.2), reason: '点阵要看得见但不抢眼');
        expect(_hueGap(t.blocks[BlockKey.error]!, t.blocks[BlockKey.warning]!), greaterThanOrEqualTo(25), reason: '报错和警告要分得开');
        if (t.dark) {
          for (final key in BlockColorKey.all) {
            expect(relativeLuminance(t.blocks[key]!), lessThan(0.3), reason: '$key 在深色主题里太亮');
          }
        }
      });

      test('低代码编辑器：选中框、插入线、拖柄在白色页面上清楚（用户页面默认白底），标签上的字读得清', () {
        const page = 0xFFFFFFFF;
        final lc = t.lowcode;
        for (final k in [LowcodeKey.selection, LowcodeKey.insertBar, LowcodeKey.dropHoverBorder, LowcodeKey.missingBorder]) {
          expect(contrastRatio(lc[k]!, page), greaterThanOrEqualTo(3), reason: '$k 放在白色页面上');
        }
        expect(contrastRatio(lc[LowcodeKey.dropText]!, page), greaterThanOrEqualTo(4.5));
        // 选中框在编辑器自己的底色（页面四周）上也看得见。
        expect(contrastRatio(lc[LowcodeKey.selection]!, t.ui[UiKey.canvas]!), greaterThanOrEqualTo(t.dark ? 2.5 : 3));
        // 拖柄是“白芯 + 选中色的边”：芯和边分得开。
        expect(contrastRatio(lc[LowcodeKey.handleFill]!, lc[LowcodeKey.selection]!), greaterThanOrEqualTo(3));
        // 外边距、内边距示意是两种不同的半透明色。
        for (final k in [LowcodeKey.marginRing, LowcodeKey.paddingRing, LowcodeKey.dropIdleBg, LowcodeKey.sizeTagBg]) {
          expect((lc[k]! >> 24) & 0xFF, inExclusiveRange(0, 255), reason: '$k 要带透明度');
        }
        expect(_hueGap(lc[LowcodeKey.marginRing]!, lc[LowcodeKey.paddingRing]!), greaterThanOrEqualTo(40));
        // 插入线：对准时比没对准时醒目。
        expect(contrastRatio(lc[LowcodeKey.insertBar]!, page), greaterThan(contrastRatio(lc[LowcodeKey.insertBarIdle]!, page)));
      });

      test('形状与密度：有自己的性格，但不夸张（390×844 上不挤坏）', () {
        expect(t.metric(MetricKey.radiusScale), inInclusiveRange(0.5, 1.75));
        expect(t.metric(MetricKey.spaceScale), inInclusiveRange(0.9, 1.1));
        expect(t.metric(MetricKey.fontScale), inInclusiveRange(0.95, 1.1));
        expect(t.metric(MetricKey.dividerWidth), inInclusiveRange(1, 1.5));
        expect(t.metric(MetricKey.surfaceOpacity), inInclusiveRange(0.75, 1));
      });
    });
  }

  test('形状与密度：各套不全一样（至少 4 种不同的圆角）', () {
    expect(_extra.map((t) => t.metric(MetricKey.radiusScale)).toSet().length, greaterThanOrEqualTo(4));
    expect(_extra.any((t) => t.metric(MetricKey.spaceScale) != 1), isTrue);
    expect(_extra.any((t) => t.metric(MetricKey.shadowStrength) != 1), isTrue);
  });
}
