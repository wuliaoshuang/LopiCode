// 守门：界面里不许再写死颜色。颜色一律从当前主题来（context.colors / context.themeSpec / BkPalette.fromTheme）。
//
// 查的是 lib/ 下所有 Dart 文件里这几种写法：`Color(0x…)`、`Colors.某色`、`Color.fromARGB / fromRGBO(…)`、
// `Palette.某色`（旧的原始色板）。主题定义文件整份放行；别的确有理由的，逐条登记在下面并写明原因。
// 登记了但已经不存在的例外也会报错（清单只许变短）。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 整份放行的文件：它们就是“定义颜色的地方”。
const _definitionFiles = {
  'lib/appearance/theme_builtin.dart': '内置主题的颜色表',
  'lib/appearance/theme_builtin_light_a.dart': '内置主题的颜色表（暖纸、薄荷）',
  'lib/appearance/theme_builtin_light_b.dart': '内置主题的颜色表（高对比浅色、樱花）',
  'lib/appearance/theme_builtin_dark_a.dart': '内置主题的颜色表（午夜蓝、暖炭）',
  'lib/appearance/theme_builtin_dark_b.dart': '内置主题的颜色表（纯黑、葡萄紫）',
  'lib/appearance/theme_fields.dart': '字段目录（注释里有颜色写法的例子）',
  'lib/appearance/theme_spec.dart': '主题数据模型',
  'lib/appearance/theme_json.dart': '主题文件的读写（文档里有颜色写法的例子）',
  'lib/appearance/theme_contrast.dart': '对比度计算（黑白是公式里的参照）',
  'lib/theme/tokens.dart': '旧的原始色板 Palette 还留在这里（低代码页面内容的默认色在用），AppColors 从主题取色',
  'lib/theme/app_theme.dart': '把主题变成 ThemeData 的地方',
};

/// 全局放行的写法。
final _alwaysOk = [
  // 透明不是一种“颜色选择”：表示“这里不画底”，换什么主题都一样。
  RegExp(r'Colors\.transparent\b'),
];

/// 逐条登记的例外：`文件` ⇒ {`这一行里包含的片段`: 原因}。
const _exceptions = <String, Map<String, String>>{
  'lib/blocks/block_colors.dart': {
    'const Color _white = Color(0xFFFFFFFF);': '积木几档颜色的算法里“往白里混 / 往黑里混”的参照，不是界面色',
    'const Color _black = Color(0xFF000000);': '同上：算法里“往黑里混”的参照',
    'Color.fromARGB(255, g, g, g)': '默认深色主色的来历（降饱和时算出来的灰），是算法不是配色',
  },
  'lib/lowcode/canvas_render_widgets.dart': {
    "textColor: _argb(s['color']) ?? Palette.neutral900,": '用户页面内容：没写文字颜色时的默认（和导出的网页一致），不是编辑器界面色',
    'colorSchemeSeed: Palette.primary700': '用户页面内容：页面里 Material 控件的种子色（和导出的 Flutter 代码一致）',
    'TextStyle(fontSize: 16, color: Palette.neutral900, height: 1.5, fontFamily: font)': '用户页面内容：正文默认色',
    "_argb(s['background-color']) ?? Colors.white, border: _border(s, scale, Palette.neutral900, false)": '用户页面内容：页面默认白底、边框默认色',
    'const [BoxShadow(color: Color(0x33000000), blurRadius: 3, offset: Offset(0, 1))]': '用户页面内容：卡片组件的默认阴影（和导出代码一致）',
    'color: bg ?? Palette.neutral200,': '用户页面内容：图片占位的底色（和导出代码一致）',
    'child: Icon(icon, color: Palette.neutral500),': '用户页面内容：图片占位的图标色',
  },
  'lib/lowcode/export_dart.dart': {
    r"String _color(String hex) => 'const Color(0xFF${hex.substring(1).toUpperCase()})';": '生成的 Flutter 代码文本，不是界面',
    'color: const Color(0xFFD3DEE4), alignment: Alignment.center': '生成的 Flutter 代码文本',
    "'boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 3, offset: Offset(0, 1))]'": '生成的 Flutter 代码文本',
  },
  'lib/lowcode/props_sheet.dart': {'Color _hex(String hex) => Color(0xFF000000 | int.parse(hex.substring(1), radix: 16));': '把用户填的颜色文本变成颜色（数据转换）'},
  'lib/lowcode/style_color_sheet.dart': {
    "slider('l', '明度'": '取色器的明度条：从黑到白是这根条本身的含义',
    'const CheckerPainter(Color(0xFFFFFFFF), Color(0xFFCFD2D6), 4)': '取色器的透明棋盘格：约定俗成的灰白格，表示“透明”',
    'color: const Color(0xFFFFFFFF),': '取色器的滑块圆点：要在任何颜色的条上都看得见',
    'const CheckerPainter(Color(0xFFFFFFFF), Color(0xFFCFD2D6))': '颜色小方块底下的透明棋盘格',
  },
  'lib/ui/preview_tab.dart': {'color: Colors.white,': '网页预览的底：网页没写背景时浏览器就是白的，跟应用主题无关'},
};

final _patterns = [RegExp(r'\bColor\(0x[0-9A-Fa-f]+'), RegExp(r'\bColors\.[a-zA-Z0-9]+'), RegExp(r'\bColor\.from(ARGB|RGBO)\('), RegExp(r'\bPalette\.[a-zA-Z0-9]+')];

bool _isComment(String line) => line.trimLeft().startsWith('//');

void main() {
  final files = [
    for (final e in Directory('lib').listSync(recursive: true))
      if (e is File && e.path.endsWith('.dart')) e.path.replaceAll('\\', '/'),
  ]..sort();

  test('lib 下不许写死颜色（主题定义文件和登记的例外除外）', () {
    final bad = <String>[];
    final used = <String>{};
    for (final f in files) {
      if (_definitionFiles.containsKey(f)) continue;
      final allowed = _exceptions[f] ?? const <String, String>{};
      final lines = File(f).readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        var line = lines[i];
        if (_isComment(line)) continue;
        for (final ok in _alwaysOk) {
          line = line.replaceAll(ok, '');
        }
        if (!_patterns.any((p) => p.hasMatch(line))) continue;
        final hit = allowed.keys.where((frag) => lines[i].contains(frag)).toList();
        if (hit.isEmpty) {
          bad.add('$f:${i + 1}: ${lines[i].trim()}');
        } else {
          used.addAll(hit.map((h) => '$f\n$h'));
        }
      }
    }
    expect(
      bad,
      isEmpty,
      reason:
          '这些地方写死了颜色。改成从主题取：界面色 context.colors.xxx；代码 / 终端 / 积木 / 低代码编辑器色 context.themeSpec.codeColor(…) 等'
          '（见 docs/themes-design.md “怎么取色”）。主题里没有合适的项就加一项。\n${bad.join('\n')}',
    );
    final stale = [
      for (final e in _exceptions.entries)
        for (final frag in e.value.keys)
          if (!used.contains('${e.key}\n$frag')) '${e.key}: $frag',
    ];
    expect(stale, isEmpty, reason: '这些例外已经不成立了（那一行没了或改了），从 _exceptions 里删掉：\n${stale.join('\n')}');
  });

  test('放行清单里的文件都还在，每条例外都写了原因', () {
    for (final f in [..._definitionFiles.keys, ..._exceptions.keys]) {
      expect(File(f).existsSync(), isTrue, reason: '$f 不在了，从清单里删掉');
    }
    for (final why in [..._definitionFiles.values, for (final m in _exceptions.values) ...m.values]) {
      expect(why.trim().length, greaterThan(4));
    }
  });

  test('这条守门自己是管用的：写死的颜色认得出来，透明和注释放过', () {
    bool flagged(String line) {
      if (_isComment(line)) return false;
      var l = line;
      for (final ok in _alwaysOk) {
        l = l.replaceAll(ok, '');
      }
      return _patterns.any((p) => p.hasMatch(l));
    }

    expect(flagged('color: const Color(0xFF112233),'), isTrue);
    expect(flagged('color: Colors.white,'), isTrue);
    expect(flagged('color: Colors.black.withValues(alpha: 0.2),'), isTrue);
    expect(flagged('color: Color.fromARGB(255, 1, 2, 3),'), isTrue);
    expect(flagged('color: Color.fromRGBO(1, 2, 3, 1),'), isTrue);
    expect(flagged('color: Palette.primary500,'), isTrue);
    expect(flagged('color: Colors.transparent,'), isFalse);
    expect(flagged('color: selected ? Colors.transparent : Colors.red,'), isTrue);
    expect(flagged('// 原来是 Color(0xFF112233)'), isFalse);
    expect(flagged('color: c.accent,'), isFalse);
    expect(flagged('final x = BkPalette.fromTheme(t); final y = AppColors.light; final d = DiffColors.of(context);'), isFalse);
    expect(flagged('Color(theme.ui[key]!)'), isFalse);
  });
}
