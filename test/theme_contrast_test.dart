// 对比度工具：算得对；内置主题不达标的项正好是登记过的那些（不多不少）。
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/appearance/theme_builtin.dart';
import 'package:lopicode/appearance/theme_contrast.dart';
import 'package:lopicode/appearance/theme_fields.dart';

void main() {
  group('对比度怎么算（WCAG 2.x）', () {
    test('黑白 21:1，同色 1:1，谁在前谁在后都一样', () {
      expect(contrastRatio(0xFF000000, 0xFFFFFFFF), closeTo(21, 0.001));
      expect(contrastRatio(0xFFFFFFFF, 0xFF000000), closeTo(21, 0.001));
      expect(contrastRatio(0xFF808080, 0xFF808080), closeTo(1, 0.0001));
    });

    test('几个公认的数', () {
      // #767676 在白底上 4.54:1（常说的“刚好过 AA 的灰”）；纯红在白底上 4.00:1；纯蓝在白底上 8.59:1。
      expect(contrastRatio(0xFF767676, 0xFFFFFFFF), closeTo(4.54, 0.01));
      expect(contrastRatio(0xFFFF0000, 0xFFFFFFFF), closeTo(4.00, 0.01));
      expect(contrastRatio(0xFF0000FF, 0xFFFFFFFF), closeTo(8.59, 0.01));
    });

    test('相对亮度：黑 0、白 1', () {
      expect(relativeLuminance(0xFF000000), 0);
      expect(relativeLuminance(0xFFFFFFFF), closeTo(1, 1e-9));
      expect(relativeLuminance(0x00FFFFFF), closeTo(1, 1e-9), reason: '只看颜色，不看透明度');
    });

    test('半透明的前景先叠到背景上再算', () {
      expect(compositeOver(0x80000000, 0xFFFFFFFF), 0xFF7F7F7F);
      expect(compositeOver(0xFF123456, 0xFFFFFFFF), 0xFF123456);
      expect(compositeOver(0x00123456, 0xFFABCDEF), 0xFFABCDEF);
      // 半透明的黑字在白底上，对比度比不透明的黑字低。
      expect(contrastRatio(0x80000000, 0xFFFFFFFF), lessThan(contrastRatio(0xFF000000, 0xFFFFFFFF)));
      expect(contrastRatio(0x80000000, 0xFFFFFFFF), closeTo(contrastRatio(0xFF7F7F7F, 0xFFFFFFFF), 0.001));
    });
  });

  group('检查清单', () {
    test('每一项的标识不重复，门槛只有 4.5 和 3 两种', () {
      final ids = kContrastChecks.map((c) => c.id).toList();
      expect(ids.toSet().length, ids.length);
      expect(kContrastChecks.map((c) => c.min).toSet(), {kContrastText, kContrastLarge});
      expect(kContrastChecks.length, greaterThan(100));
    });

    test('正文、次要文字、按钮上的字、代码文字、终端文字、积木上的字都在清单里', () {
      final ids = kContrastChecks.map((c) => c.id).toSet();
      for (final id in [
        'ui.text/ui.bg',
        'ui.text/ui.surface',
        'ui.textMuted/ui.bg',
        'ui.onAccent/ui.accentFill',
        'code.fg/code.bg',
        'terminal.fg/terminal.bg',
        'tokens.keyword/code.bg',
        'ui.snackText/ui.snackBg',
      ]) {
        expect(ids, contains(id));
      }
      for (final f in kBlockCategoryFields) {
        expect(ids, contains('blocks._text/blocks.${f.key}'), reason: '积木上的字放在“${f.label}”主色上');
      }
    });

    test('一套故意做坏的主题：查得出来，说的是人话', () {
      final bad = kDefaultLightTheme.withColors('ui', {UiKey.text: 0xFFF0F0F0});
      final issues = checkThemeContrast(bad).where((i) => i.id == 'ui.text/ui.bg').toList();
      expect(issues, hasLength(1));
      expect(issues.single.ratio, lessThan(1.5));
      expect(issues.single.min, 4.5);
      expect(issues.single.message, allOf(contains('正文'), contains('主页面底色'), contains('对比度'), contains('4.5:1')));
    });

    test('没设颜色的高亮分类不查', () {
      final ids = checkThemeContrast(kDefaultLightTheme).map((i) => i.id).toSet();
      expect(ids.contains('tokens.operator/code.bg'), isFalse);
    });
  });

  group('内置主题', () {
    for (final t in kBuiltinThemes) {
      test('${t.name}：不达标的正好是登记过的已知例外', () {
        final known = kKnownContrastGaps[t.id] ?? const <String, String>{};
        final got = checkThemeContrast(t).map((i) => i.id).toSet();
        expect(got.difference(known.keys.toSet()), isEmpty, reason: '有没登记的不达标项（新主题应该改颜色，不是往例外里加）');
        expect(known.keys.toSet().difference(got), isEmpty, reason: '登记了但其实达标了：把它从 kKnownContrastGaps 里删掉');
        expect(unexpectedContrastIssues(t), isEmpty);
        for (final why in known.values) {
          expect(why.trim(), isNotEmpty);
        }
      });
    }

    test('已知例外只属于两套默认主题（默认外观不能动，所以只登记不改）', () {
      expect(kKnownContrastGaps.keys.toSet(), {kDefaultLightThemeId, kDefaultDarkThemeId});
      expect(kKnownContrastGaps[kDefaultLightThemeId]!.length, 31);
      expect(kKnownContrastGaps[kDefaultDarkThemeId]!.length, 5);
    });

    test('默认主题里最要紧的几对是达标的', () {
      for (final t in [kDefaultLightTheme, kDefaultDarkTheme]) {
        final bad = checkThemeContrast(t).map((i) => i.id).toSet();
        for (final id in ['ui.text/ui.bg', 'ui.text/ui.surface', 'ui.textMuted/ui.bg', 'ui.onAccent/ui.accentFill', 'code.fg/code.bg', 'terminal.fg/terminal.bg', 'tokens.keyword/code.bg']) {
          expect(bad.contains(id), isFalse, reason: '${t.id} $id');
        }
        expect(bad.where((id) => id.startsWith('blocks._text/')), isEmpty, reason: '${t.id} 积木上的字');
      }
    });
  });
}
