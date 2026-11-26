// 把“加主题系统之前”的颜色逐个钉住：默认浅色 / 默认深色两套内置主题必须和原来一模一样。
//
// 下面的数字都是从加主题系统之前的那次提交（da5ae2c）里抄出来的字面量：旧 AppColors.light / dark、
// 终端 16 色、改动对比四色、Atom One 高亮表（re_highlight 自带）、积木色表每一类每一档（当时跑出来的值）。
// 这里故意不引用现在的常量：现在的值被人改了，这里就会红。
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/appearance/theme_builtin.dart';
import 'package:lopicode/appearance/theme_fields.dart';
import 'package:lopicode/blocks/block_colors.dart';
import 'package:lopicode/blocks/block_host.dart';
import 'package:lopicode/theme/app_theme.dart';
import 'package:lopicode/theme/tokens.dart';
import 'package:lopicode/ui/code_langs.dart';
import 'package:lopicode/ui/diff_view.dart';
import 'package:material_ui/material_ui.dart';

const Map<String, int> _oldUiLight = {
  'bg': 0xFFFCFCFC,
  'canvas': 0xFFF3F4F6,
  'surface': 0xFFFFFFFF,
  'surfaceMuted': 0xFFE9EAEC,
  'text': 0xFF15151B,
  'textMuted': 0xFF50525B,
  'textFaint': 0xFF656870,
  'border': 0xFFE4E5E7,
  'accent': 0xFF2962CB,
  'accentSoft': 0xFFE6EEFB,
  'accentFill': 0xFF2962CB,
  'onAccent': 0xFFFFFFFF,
  'danger': 0xFFC6212F,
  'dangerSoft': 0xFFFFEBF3,
  'warning': 0xFF893300,
  'warningSoft': 0xFFFFFEEB,
  'codeBg': 0xFFF3F4F6,
};

const Map<String, int> _oldUiDark = {
  'bg': 0xFF15151B,
  'canvas': 0xFF0F0F14,
  'surface': 0xFF1E1F25,
  'surfaceMuted': 0xFF2C2D35,
  'text': 0xFFF8FAFB,
  'textMuted': 0xFFB8BEC1,
  'textFaint': 0xFF989EA4,
  'border': 0xFF3C3D45,
  'accent': 0xFF8FB4F5,
  'accentSoft': 0xFF1B2A4A,
  'accentFill': 0xFF3A72DC,
  'onAccent': 0xFFFFFFFF,
  'danger': 0xFFFE7FB6,
  'dangerSoft': 0xFF3A1420,
  'warning': 0xFFFFE068,
  'warningSoft': 0xFF3A2A0C,
  'codeBg': 0xFF1A1A21,
};

const Map<String, int> _oldAnsiLight = {
  'black': 0xFF222435,
  'red': 0xFFC6212F,
  'green': 0xFF017B43,
  'yellow': 0xFF893300,
  'blue': 0xFF1F5FBF,
  'magenta': 0xFF8A3FBF,
  'cyan': 0xFF0A7C8C,
  'white': 0xFF5C6479,
  'brightBlack': 0xFF5C6479,
  'brightRed': 0xFFAB131E,
  'brightGreen': 0xFF058654,
  'brightYellow': 0xFFA84C00,
  'brightBlue': 0xFF1F5FBF,
  'brightMagenta': 0xFF8A3FBF,
  'brightCyan': 0xFF0A7C8C,
  'brightWhite': 0xFF222435,
};

const Map<String, int> _oldAnsiDark = {
  'black': 0xFF35394C,
  'red': 0xFFFE7FB6,
  'green': 0xFF5DEEDB,
  'yellow': 0xFFFFE068,
  'blue': 0xFF8AB4F8,
  'magenta': 0xFFD7A6F5,
  'cyan': 0xFF9BFFF8,
  'white': 0xFFD3DEE4,
  'brightBlack': 0xFF707A8F,
  'brightRed': 0xFFFE7FB6,
  'brightGreen': 0xFF9BFFF8,
  'brightYellow': 0xFFFFE068,
  'brightBlue': 0xFFAECBFA,
  'brightMagenta': 0xFFE5C4FA,
  'brightCyan': 0xFFEBFFFF,
  'brightWhite': 0xFFF6FBFD,
};

const Map<String, int> _oldAtomLight = {
  'comment': 0xFFA0A1A7,
  'quote': 0xFFA0A1A7,
  'doctag': 0xFFA626A4,
  'keyword': 0xFFA626A4,
  'formula': 0xFFA626A4,
  'section': 0xFFE45649,
  'name': 0xFFE45649,
  'selector-tag': 0xFFE45649,
  'deletion': 0xFFE45649,
  'subst': 0xFFE45649,
  'literal': 0xFF0184BB,
  'string': 0xFF50A14F,
  'regexp': 0xFF50A14F,
  'addition': 0xFF50A14F,
  'attribute': 0xFF50A14F,
  'meta-string': 0xFF50A14F,
  'attr': 0xFF986801,
  'variable': 0xFF986801,
  'template-variable': 0xFF986801,
  'type': 0xFF986801,
  'selector-class': 0xFF986801,
  'selector-attr': 0xFF986801,
  'selector-pseudo': 0xFF986801,
  'number': 0xFF986801,
  'symbol': 0xFF4078F2,
  'bullet': 0xFF4078F2,
  'link': 0xFF4078F2,
  'meta': 0xFF4078F2,
  'selector-id': 0xFF4078F2,
  'title': 0xFF4078F2,
  'built_in': 0xFFC18401,
  'title.class_': 0xFFC18401,
  'class-title': 0xFFC18401,
};

const Map<String, int> _oldAtomDark = {
  'comment': 0xFF5C6370,
  'quote': 0xFF5C6370,
  'doctag': 0xFFC678DD,
  'keyword': 0xFFC678DD,
  'formula': 0xFFC678DD,
  'section': 0xFFE06C75,
  'name': 0xFFE06C75,
  'selector-tag': 0xFFE06C75,
  'deletion': 0xFFE06C75,
  'subst': 0xFFE06C75,
  'literal': 0xFF56B6C2,
  'string': 0xFF98C379,
  'regexp': 0xFF98C379,
  'addition': 0xFF98C379,
  'attribute': 0xFF98C379,
  'meta-string': 0xFF98C379,
  'attr': 0xFFD19A66,
  'variable': 0xFFD19A66,
  'template-variable': 0xFFD19A66,
  'type': 0xFFD19A66,
  'selector-class': 0xFFD19A66,
  'selector-attr': 0xFFD19A66,
  'selector-pseudo': 0xFFD19A66,
  'number': 0xFFD19A66,
  'symbol': 0xFF61AEEE,
  'bullet': 0xFF61AEEE,
  'link': 0xFF61AEEE,
  'meta': 0xFF61AEEE,
  'selector-id': 0xFF61AEEE,
  'title': 0xFF61AEEE,
  'built_in': 0xFFE6C07B,
  'title.class_': 0xFFE6C07B,
  'class-title': 0xFFE6C07B,
};

// 每类：fill fillTop edge deep text fieldBg fieldText fieldHint nested.fill nested.fillTop
const Map<String, List<int>> _oldBkLight = {
  'event': [0xFFB4500B, 0xFFBC6223, 0xFF7E3808, 0xFF904009, 0xFFFFFFFF, 0xFFFFFFFF, 0xFF1F2128, 0xFF7A808C, 0xFFC06C32, 0xFFC67B47],
  'variable': [0xFFD03A6F, 0xFFD54E7D, 0xFF92294E, 0xFFA62E59, 0xFFFFFFFF, 0xFFFFFFFF, 0xFF1F2128, 0xFF7A808C, 0xFFD85A86, 0xFFDB6A92],
  'widget': [0xFF1B72C4, 0xFF3280CA, 0xFF135089, 0xFF165B9D, 0xFFFFFFFF, 0xFFFFFFFF, 0xFF1F2128, 0xFF7A808C, 0xFF3F89CD, 0xFF5394D2],
  'control': [0xFF6B4BD8, 0xFF7A5DDC, 0xFF4B3597, 0xFF563CAD, 0xFFFFFFFF, 0xFFFFFFFF, 0xFF1F2128, 0xFF7A808C, 0xFF8368DE, 0xFF8F77E2],
  'action': [0xFF0B7C8E, 0xFF238999, 0xFF085763, 0xFF096372, 0xFFFFFFFF, 0xFFFFFFFF, 0xFF1F2128, 0xFF7A808C, 0xFF3291A0, 0xFF479CAA],
  'network': [0xFF756C0E, 0xFF837B26, 0xFF524C0A, 0xFF5E560B, 0xFFFFFFFF, 0xFFFFFFFF, 0xFF1F2128, 0xFF7A808C, 0xFF8B8435, 0xFF979049],
  'value': [0xFF5B677A, 0xFF6B7687, 0xFF404855, 0xFF495262, 0xFFFFFFFF, 0xFFFFFFFF, 0xFF1F2128, 0xFF7A808C, 0xFF757F8F, 0xFF838C9A],
  'operator': [0xFF287838, 0xFF3E864C, 0xFF1C5427, 0xFF20602D, 0xFFFFFFFF, 0xFFFFFFFF, 0xFF1F2128, 0xFF7A808C, 0xFF4A8E58, 0xFF5C9969],
  'data': [0xFFA63DBF, 0xFFAF50C5, 0xFF742B86, 0xFF853199, 0xFFFFFFFF, 0xFFFFFFFF, 0xFF1F2128, 0xFF7A808C, 0xFFB45CC9, 0xFFBC6CCF],
  'request': [0xFF0A7F5C, 0xFF238C6C, 0xFF075940, 0xFF08664A, 0xFFFFFFFF, 0xFFFFFFFF, 0xFF1F2128, 0xFF7A808C, 0xFF319376, 0xFF469E84],
  'response': [0xFFC53030, 0xFFCB4545, 0xFF8A2222, 0xFF9E2626, 0xFFFFFFFF, 0xFFFFFFFF, 0xFF1F2128, 0xFF7A808C, 0xFFCE5151, 0xFFD36363],
  'unknown': [0xFF636B73, 0xFF737A81, 0xFF454B51, 0xFF4F565C, 0xFFFFFFFF, 0xFFFFFFFF, 0xFF1F2128, 0xFF7A808C, 0xFF7C8389, 0xFF898F95],
  'function': [0xFF0F7B6C, 0xFF27887B, 0xFF0B564C, 0xFF0C6256, 0xFFFFFFFF, 0xFFFFFFFF, 0xFF1F2128, 0xFF7A808C, 0xFF359084, 0xFF4A9B90],
  'text': [0xFF8A6A00, 0xFF96791A, 0xFF614A00, 0xFF6E5500, 0xFFFFFFFF, 0xFFFFFFFF, 0xFF1F2128, 0xFF7A808C, 0xFF9D8229, 0xFFA78E3E],
  'list': [0xFF2468C8, 0xFF3A77CE, 0xFF19498C, 0xFF1D53A0, 0xFFFFFFFF, 0xFFFFFFFF, 0xFF1F2128, 0xFF7A808C, 0xFF4780D1, 0xFF598DD5],
  'dict': [0xFFA23BB8, 0xFFAB4FBF, 0xFF712981, 0xFF822F93, 0xFFFFFFFF, 0xFFFFFFFF, 0xFF1F2128, 0xFF7A808C, 0xFFB15AC3, 0xFFB96BC9],
  'class': [0xFF5E7A12, 0xFF6E872A, 0xFF42550D, 0xFF4B620E, 0xFFFFFFFF, 0xFFFFFFFF, 0xFF1F2128, 0xFF7A808C, 0xFF788F38, 0xFF859A4C],
  'error': [0xFFC2362F, 0xFFC84A44, 0xFF882621, 0xFF9B2B26, 0xFFFFFFFF, 0xFFFFFFFF, 0xFF1F2128, 0xFF7A808C, 0xFFCC5650, 0xFFD16762],
  'async': [0xFF0B7A94, 0xFF23879F, 0xFF085568, 0xFF096276, 0xFFFFFFFF, 0xFFFFFFFF, 0xFF1F2128, 0xFF7A808C, 0xFF328FA5, 0xFF479AAE],
  'custom': [0xFF4C56C8, 0xFF5E67CE, 0xFF353C8C, 0xFF3D45A0, 0xFFFFFFFF, 0xFFFFFFFF, 0xFF1F2128, 0xFF7A808C, 0xFF6971D1, 0xFF787FD5],
};

// 每类：fill fillTop edge deep text fieldBg fieldText fieldHint nested.fill nested.fillTop
const Map<String, List<int>> _oldBkDark = {
  'event': [0xFF95440C, 0xFF9D511D, 0xFF5D2A08, 0xFF6E3309, 0xFFF4F5F7, 0xFFE4E6EB, 0xFF1F2128, 0xFF7A808C, 0xFFA66233, 0xFFAC6D41],
  'variable': [0xFFAD335E, 0xFFB24169, 0xFF6B203A, 0xFF802646, 0xFFF4F5F7, 0xFFE4E6EB, 0xFF1F2128, 0xFF7A808C, 0xFFBA5478, 0xFFBF6081],
  'widget': [0xFF1A60A2, 0xFF2A6BA9, 0xFF103C65, 0xFF134778, 0xFFF4F5F7, 0xFFE4E6EB, 0xFF1F2128, 0xFF7A808C, 0xFF3E79B1, 0xFF4C83B7],
  'control': [0xFF5A40B2, 0xFF654DB7, 0xFF38286E, 0xFF422F84, 0xFFF4F5F7, 0xFFE4E6EB, 0xFF1F2128, 0xFF7A808C, 0xFF745EBE, 0xFF7E6AC3],
  'action': [0xFF0D6877, 0xFF1E7380, 0xFF08414A, 0xFF094D58, 0xFFF4F5F7, 0xFFE4E6EB, 0xFF1F2128, 0xFF7A808C, 0xFF33808D, 0xFF428995],
  'network': [0xFF625B0F, 0xFF6D661F, 0xFF3D3809, 0xFF49430B, 0xFFF4F5F7, 0xFFE4E6EB, 0xFF1F2128, 0xFF7A808C, 0xFF7B7535, 0xFF847F43],
  'value': [0xFF4D5666, 0xFF596271, 0xFF30363F, 0xFF39404B, 0xFFF4F5F7, 0xFFE4E6EB, 0xFF1F2128, 0xFF7A808C, 0xFF69717E, 0xFF747B87],
  'operator': [0xFF246431, 0xFF336F3F, 0xFF163E1E, 0xFF1A4A24, 0xFFF4F5F7, 0xFFE4E6EB, 0xFF1F2128, 0xFF7A808C, 0xFF477D52, 0xFF54865E],
  'data': [0xFF8A359E, 0xFF9243A5, 0xFF562162, 0xFF662775, 0xFFF4F5F7, 0xFFE4E6EB, 0xFF1F2128, 0xFF7A808C, 0xFF9D55AE, 0xFFA461B3],
  'request': [0xFF0C6B4E, 0xFF1D755B, 0xFF074230, 0xFF094F3A, 0xFFF4F5F7, 0xFFE4E6EB, 0xFF1F2128, 0xFF7A808C, 0xFF33826A, 0xFF418B75],
  'response': [0xFFA32A2A, 0xFFA93939, 0xFF651A1A, 0xFF781F1F, 0xFFF4F5F7, 0xFFE4E6EB, 0xFF1F2128, 0xFF7A808C, 0xFFB24C4C, 0xFFB75959],
  'unknown': [0xFF545A60, 0xFF60666C, 0xFF34383C, 0xFF3E4347, 0xFFF4F5F7, 0xFFE4E6EB, 0xFF1F2128, 0xFF7A808C, 0xFF6F747A, 0xFF797E83],
  'function': [0xFF10675B, 0xFF207266, 0xFF0A4038, 0xFF0C4C43, 0xFFF4F5F7, 0xFFE4E6EB, 0xFF1F2128, 0xFF7A808C, 0xFF367F75, 0xFF44887F],
  'text': [0xFF735904, 0xFF7D6515, 0xFF483702, 0xFF554203, 0xFFF4F5F7, 0xFFE4E6EB, 0xFF1F2128, 0xFF7A808C, 0xFF8A742C, 0xFF927E3B],
  'list': [0xFF2058A5, 0xFF3063AC, 0xFF143667, 0xFF18417A, 0xFFF4F5F7, 0xFFE4E6EB, 0xFF1F2128, 0xFF7A808C, 0xFF4472B4, 0xFF517CB9],
  'dict': [0xFF863398, 0xFF8F419F, 0xFF53205E, 0xFF642671, 0xFFF4F5F7, 0xFFE4E6EB, 0xFF1F2128, 0xFF7A808C, 0xFF9A54A9, 0xFFA160AF],
  'class': [0xFF506712, 0xFF5C7123, 0xFF32400B, 0xFF3B4C0E, 0xFFF4F5F7, 0xFFE4E6EB, 0xFF1F2128, 0xFF7A808C, 0xFF6C7F38, 0xFF768846],
  'error': [0xFFA02F29, 0xFFA73E38, 0xFF631D1A, 0xFF77231F, 0xFFF4F5F7, 0xFFE4E6EB, 0xFF1F2128, 0xFF7A808C, 0xFFB0504C, 0xFFB55C58],
  'async': [0xFF0D677C, 0xFF1E7185, 0xFF08404D, 0xFF094C5B, 0xFFF4F5F7, 0xFFE4E6EB, 0xFF1F2128, 0xFF7A808C, 0xFF337F91, 0xFF428898],
  'custom': [0xFF4049A5, 0xFF4E55AB, 0xFF282D66, 0xFF30367A, 0xFFF4F5F7, 0xFFE4E6EB, 0xFF1F2128, 0xFF7A808C, 0xFF5F66B3, 0xFF6A70B9],
};

String _hex(int v) => '0x${v.toRadixString(16).padLeft(8, '0').toUpperCase()}';
int _withAlpha(int rgb, int alpha) => (alpha << 24) | (rgb & 0xFFFFFF);

void main() {
  for (final dark in [false, true]) {
    final name = dark ? '默认深色' : '默认浅色';
    final ThemeSpec t = dark ? kDefaultDarkTheme : kDefaultLightTheme;
    final oldUi = dark ? _oldUiDark : _oldUiLight;
    final colors = dark ? AppColors.dark : AppColors.light;

    group('$name 和原来一样', () {
      test('标识、明暗、内置', () {
        expect(t.id, dark ? 'default-dark' : 'default-light');
        expect(t.dark, dark);
        expect(t.builtin, isTrue);
        expect(defaultThemeFor(dark: dark), same(t));
        expect(colors.spec, same(t));
      });

      test('界面色：原来的 17 项逐个相等（主题里的值，和 context.colors 拿到的值）', () {
        expect(oldUi.length, 17);
        for (final e in oldUi.entries) {
          expect(_hex(t.ui[e.key]!), _hex(e.value), reason: 'ui.${e.key}');
        }
        final got = <String, Color>{
          'bg': colors.bg,
          'canvas': colors.canvas,
          'surface': colors.surface,
          'surfaceMuted': colors.surfaceMuted,
          'text': colors.text,
          'textMuted': colors.textMuted,
          'textFaint': colors.textFaint,
          'border': colors.border,
          'accent': colors.accent,
          'accentSoft': colors.accentSoft,
          'accentFill': colors.accentFill,
          'onAccent': colors.onAccent,
          'danger': colors.danger,
          'dangerSoft': colors.dangerSoft,
          'warning': colors.warning,
          'warningSoft': colors.warningSoft,
          'codeBg': colors.codeBg,
        };
        expect(got.keys.toSet(), oldUi.keys.toSet());
        for (final e in got.entries) {
          expect(_hex(e.value.toARGB32()), _hex(oldUi[e.key]!), reason: 'context.colors.${e.key}');
        }
      });

      test('界面色：新加的语义项等于它们替换掉的那个旧值', () {
        final ui = t.ui;
        // 原来直接借用别的语义色的地方：新项默认就是那个色。
        final same = <String, String>{
          UiKey.selectedBg: 'accentSoft', // 侧边栏选中行
          UiKey.navBg: 'bg', // 底部导航
          UiKey.navActive: 'text',
          UiKey.navInactive: 'textFaint',
          UiKey.barButtonBg: 'surface', // 顶栏悬浮按钮
          UiKey.bubbleMineBg: 'accentSoft', // 我的气泡
          UiKey.bubbleMineText: 'text',
          UiKey.bubbleAgentBg: 'surfaceMuted', // Agent 气泡
          UiKey.bubbleAgentText: 'text',
          UiKey.cardBg: 'surface', // 聊天里的卡片
          UiKey.inputBg: 'surface', // 输入框
        };
        for (final e in same.entries) {
          expect(_hex(ui[e.key]!), _hex(oldUi[e.value]!), reason: 'ui.${e.key} 应该等于原来的 ${e.value}');
        }
        // 原来写死的字面量。
        final literal = dark
            ? <String, int>{
                UiKey.onDanger: 0xFF15151B, // ColorScheme.onError = Palette.neutral950
                UiKey.snackBg: 0xFFD8DCDF, // Palette.neutral200
                UiKey.snackText: 0xFF15151B, // Palette.neutral950
                UiKey.noticeBg: 0xFF3A1D22, // error_guard.dart
                UiKey.noticeText: 0xFFFFB3C7,
                UiKey.chart1: 0xFF4E99E4, // context_bar.dart：primary400
                UiKey.chart2: 0xFFADE5FF, // primary200
                UiKey.chart3: 0xFFA84C00, // warning700
                UiKey.chart4: 0xFFFFE068, // warning300
                UiKey.scrim: 0xFF000000,
                UiKey.shadow: 0xFF000000,
              }
            : <String, int>{
                UiKey.onDanger: 0xFFFFFFFF, // ColorScheme.onError = 白
                UiKey.snackBg: 0xFF27282F, // Palette.neutral900
                UiKey.snackText: 0xFFF8FAFB, // Palette.neutral100
                UiKey.noticeBg: 0xFFFFEBF3,
                UiKey.noticeText: 0xFFAB131E,
                UiKey.chart1: 0xFF12359E, // primary700
                UiKey.chart2: 0xFF78CBF7, // primary300
                UiKey.chart3: 0xFFA84C00, // warning700
                UiKey.chart4: 0xFFF7BC2E, // warning400
                UiKey.scrim: 0xFF000000,
                UiKey.shadow: 0xFF000000,
              };
        for (final e in literal.entries) {
          expect(_hex(ui[e.key]!), _hex(e.value), reason: 'ui.${e.key}');
        }
      });

      test('ThemeData：提示条、on-error、输入框底色和原来一样；buildAppTheme 就是默认主题', () {
        final theme = buildAppTheme(dark ? Brightness.dark : Brightness.light);
        expect(theme.extension<AppColors>()!.spec, same(t));
        expect(buildThemeData(t), same(buildThemeData(t)), reason: '同一份主题只造一次 ThemeData');
        expect(_hex(theme.colorScheme.onError.toARGB32()), dark ? '0xFF15151B' : '0xFFFFFFFF');
        expect(_hex(theme.snackBarTheme.backgroundColor!.toARGB32()), dark ? '0xFFD8DCDF' : '0xFF27282F');
        expect(_hex(theme.snackBarTheme.contentTextStyle!.color!.toARGB32()), dark ? '0xFF15151B' : '0xFFF8FAFB');
        expect(_hex(theme.inputDecorationTheme.fillColor!.toARGB32()), _hex(oldUi['surface']!));
        expect(_hex(theme.scaffoldBackgroundColor.toARGB32()), _hex(oldUi['bg']!));
        expect(theme.brightness, dark ? Brightness.dark : Brightness.light);
      });

      test('终端：16 色逐个相等；前景 / 背景 / 光标 / 选区 / 查找命中等于原来借用的那几个色', () {
        final old = dark ? _oldAnsiDark : _oldAnsiLight;
        expect(old.length, 16);
        for (final e in old.entries) {
          expect(_hex(t.terminal[e.key]!), _hex(e.value), reason: 'terminal.${e.key}');
        }
        expect(_hex(t.terminal['fg']!), _hex(oldUi['text']!));
        expect(_hex(t.terminal['bg']!), _hex(oldUi['codeBg']!));
        expect(_hex(t.terminal['cursor']!), _hex(oldUi['accent']!));
        // 原来是 accent.withValues(alpha: 0.3)：0.3 × 255 = 76.5，存成 0x4D。
        expect(_hex(t.terminal['selection']!), _hex(_withAlpha(oldUi['accent']!, 0x4D)));
        expect(_hex(t.terminal['searchHitBg']!), _hex(oldUi['warningSoft']!));
        expect(_hex(t.terminal['searchHitBgCurrent']!), _hex(oldUi['warning']!));
        expect(_hex(t.terminal['searchHitFg']!), _hex(oldUi['text']!));
      });

      test('代码：底色 / 文字 / 行号 / 当前行 / 选区 / 光标 / 查找命中 / 改动对比', () {
        final code = t.code;
        expect(_hex(code[CodeKey.bg]!), _hex(oldUi['codeBg']!));
        expect(_hex(code[CodeKey.fg]!), _hex(oldUi['text']!));
        expect(_hex(code[CodeKey.lineNumber]!), _hex(oldUi['textFaint']!));
        expect(_hex(code[CodeKey.lineNumberActive]!), _hex(oldUi['text']!));
        expect(_hex(code[CodeKey.cursor]!), _hex(oldUi['accent']!));
        // 原来：surfaceMuted 50%、accent 25%、warning 30%。
        expect(_hex(code[CodeKey.currentLine]!), _hex(_withAlpha(oldUi['surfaceMuted']!, 0x80)));
        expect(_hex(code[CodeKey.selection]!), _hex(_withAlpha(oldUi['accent']!, 0x40)));
        expect(_hex(code[CodeKey.searchHit]!), _hex(_withAlpha(oldUi['warning']!, 0x4D)));
        final d = dark ? DiffColors.dark : DiffColors.light;
        final want = dark ? const [0xFF12301C, 0xFF7FD18F, 0xFF3A1518, 0xFFF2A0A0] : const [0xFFE3F3E7, 0xFF1A6E2E, 0xFFFCE8E8, 0xFFB3261E];
        expect([d.addBg, d.addFg, d.delBg, d.delFg].map((c) => _hex(c.toARGB32())).toList(), want.map(_hex).toList());
      });

      test('代码高亮：和原来的 Atom One 表逐项相等，全部不加粗不倾斜', () {
        final old = {...(dark ? _oldAtomDark : _oldAtomLight)};
        // 这三个键在原表里有，但高亮规则从来不会打出这几个标签（查表是整名精确匹配），所以主题里没收。
        for (final dead in const ['meta-string', 'title.class_', 'class-title']) {
          expect(old.remove(dead), isNotNull, reason: dead);
        }
        expect(old.length, 30);
        final now = codeThemeFor(dark: dark);
        expect(now.keys.toSet(), old.keys.toSet(), reason: '有颜色的分类应该正好是原来那 30 个');
        for (final e in old.entries) {
          final style = now[e.key]!;
          expect(_hex(style.color!.toARGB32()), _hex(e.value), reason: 'tokens.${e.key}');
          expect(style.fontWeight, FontWeight.w400, reason: e.key);
          expect(style.fontStyle, FontStyle.normal, reason: e.key);
        }
        expect(codeThemeFor(theme: t), same(now));
        // 没上色的分类：主题里登记着，但什么都没设。
        for (final f in kTokenFields) {
          final s = t.tokens[f.key];
          expect(s, isNotNull, reason: '主题里应该有 ${f.key} 这一项');
          expect(s!.isPlain, !old.containsKey(f.key), reason: f.key);
        }
      });

      test('积木：每一类每一档都和原来算出来的一样', () {
        final old = dark ? _oldBkDark : _oldBkLight;
        final p = BkPalette.of(dark: dark);
        expect(BkPalette.fromTheme(t), same(p));
        expect(p.dark, dark);
        expect(old.keys.toSet(), BlockColorKey.all.toSet());
        for (final e in old.entries) {
          final tone = p.tone(e.key);
          final got = [tone.fill, tone.fillTop, tone.edge, tone.deep, tone.text, tone.fieldBg, tone.fieldText, tone.fieldHint, tone.nested.fill, tone.nested.fillTop];
          expect(got.map((c) => _hex(c.toARGB32())).toList(), e.value.map(_hex).toList(), reason: '积木 ${e.key}');
          expect(_hex(t.blocks[e.key]!), _hex(e.value.first), reason: '主题里存的主色 ${e.key}');
        }
        final extras = dark
            ? const [0xFFFFD866, 0x38FFFFFF, 0x8A000000, 0xFF15151B, 0xFF2B2C34, 0xFFFF6B6B, 0xFFFFC53D]
            : const [0xFFFFC53D, 0x33000000, 0x52000000, 0xFFF3F4F6, 0xFFD5D8DD, 0xFFE03131, 0xFFF59F00];
        expect([p.selection, p.ghost, p.shadow, p.canvas, p.canvasDot, p.error, p.warning].map((c) => _hex(c.toARGB32())).toList(), extras.map(_hex).toList());
        // 原来写死在画的地方的：角标里的符号（错误＝白，警告＝深棕）、高光＝白、压暗＝黑。
        expect([p.onError, p.onWarning, p.gloss, p.shade].map((c) => _hex(c.toARGB32())).toList(), ['0xFFFFFFFF', '0xFF3D2A00', '0xFFFFFFFF', '0xFF000000']);
      });

      test('低代码编辑器界面色：和原来写死的一样（浅色深色原来就是同一套）', () {
        const old = <String, int>{
          LowcodeKey.selection: 0xFF2962CB, // Palette.primary500
          LowcodeKey.selectionText: 0xFFFFFFFF,
          LowcodeKey.handleFill: 0xFFFFFFFF,
          LowcodeKey.marginRing: 0x59FF9800,
          LowcodeKey.paddingRing: 0x5934C759,
          LowcodeKey.dropHoverBg: 0xFFADE5FF, // primary200
          LowcodeKey.dropHoverBorder: 0xFF2962CB,
          LowcodeKey.dropIdleBg: 0x0F000000,
          LowcodeKey.dropIdleBorder: 0xFFB8BEC1, // neutral300
          LowcodeKey.dropText: 0xFF656870, // neutral600
          LowcodeKey.insertBar: 0xFF2962CB,
          LowcodeKey.insertBarIdle: 0xFFADE5FF,
          LowcodeKey.dropOutline: 0xFFB8BEC1,
          LowcodeKey.sizeTagBg: 0xCC27282F,
          LowcodeKey.sizeTagText: 0xFFFFFFFF,
          LowcodeKey.dragChipBg: 0xFF12359E, // primary700
          LowcodeKey.dragChipText: 0xFFFFFFFF,
          LowcodeKey.missingBg: 0xFFFFF4E0,
          LowcodeKey.missingBorder: 0xFFD98A0B,
          LowcodeKey.missingIcon: 0xFF9A5B00,
          LowcodeKey.missingText: 0xFF7A4700,
        };
        expect(t.lowcode.keys.toSet(), old.keys.toSet());
        for (final e in old.entries) {
          expect(_hex(t.lowcode[e.key]!), _hex(e.value), reason: 'lowcode.${e.key}');
        }
      });

      test('形状与密度：圆角 / 间距 / 字号 / 阴影倍率都是 1，分隔线 1 像素', () {
        expect(t.metric(MetricKey.radiusScale), 1);
        expect(t.metric(MetricKey.spaceScale), 1);
        expect(t.metric(MetricKey.fontScale), 1);
        expect(t.metric(MetricKey.shadowStrength), 1);
        expect(t.metric(MetricKey.dividerWidth), 1);
        expect(colors.radius(Radii.md), Radii.md);
        expect(colors.space(Space.x4), Space.x4);
        expect(colors.hairline, 1);
      });
    });
  }

  group('字段目录和内置主题对得上', () {
    test('积木分类的键就是 BlockColorKey.all', () {
      expect(kBlockCategoryFields.map((f) => f.key).toSet(), BlockColorKey.all.toSet());
      expect(kBlockCategoryFields.length, BlockColorKey.all.length);
    });

    test('每一节的键不重复', () {
      for (final e in {...kThemeColorSections, 'tokens': kTokenFields}.entries) {
        final keys = e.value.map((f) => f.key).toList();
        expect(keys.toSet().length, keys.length, reason: e.key);
      }
      final m = kMetricFields.map((f) => f.key).toList();
      expect(m.toSet().length, m.length);
    });

    test('每套内置主题：每一节的键正好是字段目录里的那些，不多不少', () {
      expect(kBuiltinThemes.map((t) => t.id).toSet().length, kBuiltinThemes.length, reason: '内置主题的标识不能重复');
      for (final t in kBuiltinThemes) {
        expect(t.builtin, isTrue, reason: t.id);
        for (final e in kThemeColorSections.entries) {
          expect(t.section(e.key).keys.toSet(), e.value.map((f) => f.key).toSet(), reason: '${t.id} 的 ${e.key}');
        }
        expect(t.tokens.keys.toSet(), kTokenFields.map((f) => f.key).toSet(), reason: '${t.id} 的 tokens');
        expect(t.metrics.keys.toSet(), kMetricFields.map((f) => f.key).toSet(), reason: '${t.id} 的 metrics');
        for (final f in kMetricFields) {
          expect(t.metrics[f.key]!, inInclusiveRange(f.min, f.max), reason: '${t.id} 的 ${f.key}');
        }
      }
    });

    test('字段个数（改了要同步 docs/themes-design.md）', () {
      expect(kUiFields.length, 45);
      expect(kCodeFields.length, 12);
      expect(kTokenFields.length, 55);
      expect(kTerminalFields.length, 23);
      expect(kBlockFields.length, 35);
      expect(kLowcodeFields.length, 21);
      expect(kMetricFields.length, 6);
    });
  });
}
