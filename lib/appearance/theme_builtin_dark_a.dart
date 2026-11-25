/// 内置主题（深色）：午夜蓝、暖炭。
///
/// 颜色是自己配的（没有照搬任何现成配色方案）：在 OKLCH 里定色相和彩度，再把明度调到对比度达标
///（正文 ≥ 4.5:1，图标 / 色块 ≥ 3:1；test/theme_contrast_test.dart 和 test/theme_builtin_test.dart 守着）。
/// 这里写的就是最终的值，要改直接改数字，改完跑那两个测试。清单和思路见 docs/themes-design.md “内置主题清单”。
library;

import 'package:lopicode/appearance/theme_fields.dart';
import 'package:lopicode/appearance/theme_spec.dart';

/// 午夜蓝（`builtin-midnight`，深色）：深海军蓝的底配天蓝强调，冷静、专注。
///
/// 配色思路：灰阶明显带蓝（色相 262°），代码区比页面更暗一档，像“凹”进去；强调色是天蓝，我的气泡是实心蓝。高亮：蓝紫关键字、青绿字符串、暖黄函数名、橙数字、粉色内置名——冷底上用几个暖色把重点挑出来。阴影加重一点。
final ThemeSpec kMidnightTheme = ThemeSpec(
  id: 'builtin-midnight',
  name: '午夜蓝',
  dark: true,
  builtin: true,
  ui: const {
    // 底色
    UiKey.bg: 0xFF0E1624,
    UiKey.canvas: 0xFF070E1B,
    UiKey.surface: 0xFF19202F,
    UiKey.surfaceMuted: 0xFF262E3D,
    UiKey.codeBg: 0xFF0A111F,
    UiKey.cardBg: 0xFF19202F,
    UiKey.inputBg: 0xFF19202F,
    // 文字
    UiKey.text: 0xFFE9EFF9,
    UiKey.textMuted: 0xFFB8BEC8,
    UiKey.textFaint: 0xFF9399A2,
    UiKey.link: 0xFF76C7FF,
    // 线
    UiKey.border: 0xFF374050,
    // 强调
    UiKey.accent: 0xFF76C7FF,
    UiKey.accentSoft: 0xFF043753,
    UiKey.accentFill: 0xFF0079B2,
    UiKey.onAccent: 0xFFFAFCFF,
    UiKey.selectedBg: 0xFF043753,
    // 状态
    UiKey.danger: 0xFFFFA096,
    UiKey.dangerSoft: 0xFF3B1C19,
    UiKey.onDanger: 0xFF0E1624,
    UiKey.warning: 0xFFF3AE58,
    UiKey.warningSoft: 0xFF362207,
    UiKey.success: 0xFF7CD591,
    UiKey.successSoft: 0xFF122D19,
    UiKey.info: 0xFF80C5FF,
    UiKey.infoSoft: 0xFF0E293D,
    UiKey.noticeBg: 0xFF3F1916,
    UiKey.noticeText: 0xFFFFBFB6,
    // 导航与顶栏
    UiKey.navBg: 0xFF0E1624,
    UiKey.navActive: 0xFF76C7FF,
    UiKey.navInactive: 0xFF9399A2,
    UiKey.barButtonBg: 0xFF19202F,
    // 聊天
    UiKey.bubbleMineBg: 0xFF0079B2,
    UiKey.bubbleMineText: 0xFFFAFCFF,
    UiKey.bubbleAgentBg: 0xFF262E3D,
    UiKey.bubbleAgentText: 0xFFE9EFF9,
    // 提示条
    UiKey.snackBg: 0xFFD3DFF3,
    UiKey.snackText: 0xFF0E1624,
    // 遮罩与阴影
    UiKey.scrim: 0xFF000000,
    UiKey.shadow: 0xFF000000,
    UiKey.backdropScrim: 0x660E1624,
    // 占用条
    UiKey.chart1: 0xFF0A8FD1,
    UiKey.chart2: 0xFFFFB3F8,
    UiKey.chart3: 0xFFBB6802,
    UiKey.chart4: 0xFF75D78D,
  },
  code: const {
    CodeKey.bg: 0xFF0A111F,
    CodeKey.fg: 0xFFE9EFF9,
    CodeKey.lineNumber: 0xFF5E6879,
    CodeKey.lineNumberActive: 0xFFE9EFF9,
    CodeKey.currentLine: 0x80262E3D,
    CodeKey.selection: 0x424BAEED,
    CodeKey.cursor: 0xFF75C7FF,
    CodeKey.searchHit: 0x61F0BB3B,
    CodeKey.diffAddBg: 0xFF0C2E16,
    CodeKey.diffAddFg: 0xFF8FE1A1,
    CodeKey.diffDelBg: 0xFF3F1916,
    CodeKey.diffDelFg: 0xFFFFABA1,
  },
  tokens: const {
    // 注释
    'comment': TokenStyle(color: 0xFF717E96, italic: true),
    'quote': TokenStyle(color: 0xFF717E96, italic: true),
    // 关键字
    'keyword': TokenStyle(color: 0xFFB9AEFF),
    'variable.language': TokenStyle(color: 0xFFB9AEFF, italic: true),
    'doctag': TokenStyle(color: 0xFFB9AEFF, italic: true),
    'computation-expression': TokenStyle(color: 0xFFB9AEFF),
    'template-tag': TokenStyle(color: 0xFFB9AEFF),
    // 字符串
    'string': TokenStyle(color: 0xFF65D3A7),
    'character': TokenStyle(color: 0xFF65D3A7),
    'code': TokenStyle(color: 0xFF65D3A7),
    // 转义 / 正则
    'regexp': TokenStyle(color: 0xFFF997C6),
    'regex': TokenStyle(color: 0xFFF997C6),
    'char.escape': TokenStyle(color: 0xFFF997C6),
    'selector-pseudo': TokenStyle(color: 0xFFF997C6),
    // 数字 / 字面量 / 符号
    'number': TokenStyle(color: 0xFFF3A768),
    'literal': TokenStyle(color: 0xFFF3A768),
    'variable.constant': TokenStyle(color: 0xFFF3A768),
    'symbol': TokenStyle(color: 0xFFF3A768),
    'label': TokenStyle(color: 0xFFF3A768),
    'selector-id': TokenStyle(color: 0xFFF3A768),
    'bullet': TokenStyle(color: 0xFFF3A768),
    'formula': TokenStyle(color: 0xFFF3A768),
    // 类型 / 类名
    'type': TokenStyle(color: 0xFF53CFDC),
    'title.class': TokenStyle(color: 0xFF53CFDC),
    'title.class.inherited': TokenStyle(color: 0xFF53CFDC, italic: true),
    'selector-class': TokenStyle(color: 0xFF53CFDC),
    // 内置的名字
    'built_in': TokenStyle(color: 0xFFEA9DD9),
    // 函数名 / 定义处的名字
    'title': TokenStyle(color: 0xFFD3BA59),
    'title.function': TokenStyle(color: 0xFFD3BA59),
    'title.function.invoke': TokenStyle(color: 0xFFD3BA59),
    'section': TokenStyle(color: 0xFFD3BA59, bold: true),
    // 变量
    'variable': TokenStyle(color: 0xFFB9D4F1),
    'template-variable': TokenStyle(color: 0xFFB9D4F1),
    // 属性
    'property': TokenStyle(color: 0xFF7AC4F3),
    'attr': TokenStyle(color: 0xFF7AC4F3),
    'attribute': TokenStyle(color: 0xFF7AC4F3),
    'selector-attr': TokenStyle(color: 0xFF7AC4F3),
    // 标签名
    'name': TokenStyle(color: 0xFFFF9B93),
    'selector-tag': TokenStyle(color: 0xFFFF9B93),
    // 标点 / 运算符
    'operator': TokenStyle(color: 0xFFB7BECB),
    'punctuation': TokenStyle(color: 0xFFB7BECB),
    'tag': TokenStyle(color: 0xFFB7BECB),
    // 元信息
    'meta': TokenStyle(color: 0xFF99A7CE),
    'meta.prompt': TokenStyle(color: 0xFF99A7CE),
    // 链接
    'link': TokenStyle(color: 0xFF79C2FF),
    // 新增
    'addition': TokenStyle(color: 0xFF79D28D),
    // 删除
    'deletion': TokenStyle(color: 0xFFFF9B90),
    'delete': TokenStyle(color: 0xFFFF9B90),
    // 不单独上色（跟代码文字一个色）
    'function': TokenStyle(),
    'function.dispatch': TokenStyle(),
    'class': TokenStyle(),
    'params': TokenStyle(),
    'subst': TokenStyle(),
    'emphasis': TokenStyle(italic: true),
    'strong': TokenStyle(bold: true),
  },
  terminal: const {
    'fg': 0xFFE9EFF9,
    'bg': 0xFF0A111F,
    'cursor': 0xFF75C7FF,
    'selection': 0x4C4BAEED,
    'searchHitBg': 0xFF4B3B05,
    'searchHitBgCurrent': 0xFF81520A,
    'searchHitFg': 0xFFE9EFF9,
    'black': 0xFF5B687F,
    'red': 0xFFFF9499,
    'green': 0xFF5BD19F,
    'yellow': 0xFFD6B449,
    'blue': 0xFF7ABDFF,
    'magenta': 0xFFDB9CEC,
    'cyan': 0xFF1CCEE0,
    'white': 0xFFCBD8EF,
    'brightBlack': 0xFF738098,
    'brightRed': 0xFFFFBDBF,
    'brightGreen': 0xFF89E8BC,
    'brightYellow': 0xFFECCF79,
    'brightBlue': 0xFFADD6FF,
    'brightMagenta': 0xFFF0BAFF,
    'brightCyan': 0xFF6CE6F4,
    'brightWhite': 0xFFF7FAFF,
  },
  blocks: const {
    'event': 0xFF9E4B18, // 事件
    'variable': 0xFFAC305B, // 变量
    'widget': 0xFF2368AD, // 控件
    'control': 0xFF654DC3, // 流程
    'action': 0xFF1F7281, // 交互
    'network': 0xFF6F6821, // 网络
    'value': 0xFF5D6678, // 直接填的值
    'operator': 0xFF367640, // 运算
    'data': 0xFF9039A5, // 数据集合
    'request': 0xFF227759, // 请求
    'response': 0xFFAF3431, // 返回
    'unknown': 0xFF686A6E, // 不认识的
    'function': 0xFF257568, // 函数
    'text': 0xFF7D6217, // 文字
    'list': 0xFF2C64B5, // 列表
    'dict': 0xFF903BA2, // 字典
    'class': 0xFF587020, // 类
    'error': 0xFFAD3831, // 出错
    'async': 0xFF207187, // 等待
    'custom': 0xFF4E5ABB, // 我的积木
    BlockKey.text: 0xFFF1F5FC,
    BlockKey.fieldBg: 0xFFDADEE6,
    BlockKey.fieldText: 0xFF1C222B,
    BlockKey.fieldHint: 0xFF686F7B,
    BlockKey.gloss: 0xFFFFFFFF,
    BlockKey.shade: 0xFF000000,
    BlockKey.selection: 0xFFFAD03E,
    BlockKey.ghost: 0x38FAFCFF,
    BlockKey.shadow: 0x8A000000,
    BlockKey.canvas: 0xFF0E1624,
    BlockKey.canvasDot: 0xFF272F3E,
    BlockKey.error: 0xFFFF7266,
    BlockKey.warning: 0xFFFFBD58,
    BlockKey.onError: 0xFF250E0C,
    BlockKey.onWarning: 0xFF301D00,
  },
  lowcode: const {
    LowcodeKey.selection: 0xFF007AB4,
    LowcodeKey.selectionText: 0xFFFFFFFF,
    LowcodeKey.handleFill: 0xFFFFFFFF,
    LowcodeKey.marginRing: 0x59ED990E,
    LowcodeKey.paddingRing: 0x594BCB71,
    LowcodeKey.dropHoverBg: 0xFFBEE4FF,
    LowcodeKey.dropHoverBorder: 0xFF007AB4,
    LowcodeKey.dropIdleBg: 0x0F11161F,
    LowcodeKey.dropIdleBorder: 0xFFADB8CB,
    LowcodeKey.dropText: 0xFF60697B,
    LowcodeKey.insertBar: 0xFF007AB4,
    LowcodeKey.insertBarIdle: 0xFFA8D8FB,
    LowcodeKey.dropOutline: 0xFFADB8CB,
    LowcodeKey.dragChipBg: 0xFF004D74,
    LowcodeKey.dragChipText: 0xFFFFFFFF,
    LowcodeKey.sizeTagBg: 0xCC1E2735,
    LowcodeKey.sizeTagText: 0xFFFFFFFF,
    LowcodeKey.missingBg: 0xFFFFF0D7,
    LowcodeKey.missingBorder: 0xFFCA8100,
    LowcodeKey.missingIcon: 0xFF8A5600,
    LowcodeKey.missingText: 0xFF6C4300,
  },
  metrics: const {MetricKey.radiusScale: 1, MetricKey.spaceScale: 1, MetricKey.fontScale: 1, MetricKey.shadowStrength: 1.2, MetricKey.dividerWidth: 1, MetricKey.surfaceOpacity: 0.84},
);

/// 暖炭（`builtin-ember`，深色）：暖灰炭色的底配琥珀色，像炉火边，夜里不刺眼。
///
/// 配色思路：灰阶带暖（色相 55°），文字是奶油色不是纯白；强调色是琥珀，实心按钮是亮琥珀底配深色字。高亮以暖色为主（琥珀关键字、沙黄类型、玫瑰数字），用鼠尾草绿的字符串和雾蓝的函数名做冷暖对比，蓝光少。积木降彩度压暗，圆角略小。
final ThemeSpec kEmberTheme = ThemeSpec(
  id: 'builtin-ember',
  name: '暖炭',
  dark: true,
  builtin: true,
  ui: const {
    // 底色
    UiKey.bg: 0xFF1E1814,
    UiKey.canvas: 0xFF16100D,
    UiKey.surface: 0xFF29231F,
    UiKey.surfaceMuted: 0xFF37302C,
    UiKey.codeBg: 0xFF191410,
    UiKey.cardBg: 0xFF29231F,
    UiKey.inputBg: 0xFF29231F,
    // 文字
    UiKey.text: 0xFFF9E7DC,
    UiKey.textMuted: 0xFFCBBAAF,
    UiKey.textFaint: 0xFFA9988E,
    UiKey.link: 0xFFFEB354,
    // 线
    UiKey.border: 0xFF49423E,
    // 强调
    UiKey.accent: 0xFFFEB354,
    UiKey.accentSoft: 0xFF492F0E,
    UiKey.accentFill: 0xFFF0A646,
    UiKey.onAccent: 0xFF211208,
    UiKey.selectedBg: 0xFF492F0E,
    // 状态
    UiKey.danger: 0xFFFFA098,
    UiKey.dangerSoft: 0xFF3B1C1A,
    UiKey.onDanger: 0xFF211208,
    UiKey.warning: 0xFFDABC43,
    UiKey.warningSoft: 0xFF2E2605,
    UiKey.success: 0xFF90D281,
    UiKey.successSoft: 0xFF192C14,
    UiKey.info: 0xFF69CAFF,
    UiKey.infoSoft: 0xFF072A3B,
    UiKey.noticeBg: 0xFF3F1917,
    UiKey.noticeText: 0xFFFFBEB8,
    // 导航与顶栏
    UiKey.navBg: 0xFF1E1814,
    UiKey.navActive: 0xFFFEB354,
    UiKey.navInactive: 0xFFA9988E,
    UiKey.barButtonBg: 0xFF29231F,
    // 聊天
    UiKey.bubbleMineBg: 0xFF492F0E,
    UiKey.bubbleMineText: 0xFFF9E7DC,
    UiKey.bubbleAgentBg: 0xFF37302C,
    UiKey.bubbleAgentText: 0xFFF9E7DC,
    // 提示条
    UiKey.snackBg: 0xFFE8DBD3,
    UiKey.snackText: 0xFF1A1511,
    // 遮罩与阴影
    UiKey.scrim: 0xFF000000,
    UiKey.shadow: 0xFF000000,
    UiKey.backdropScrim: 0x661E1814,
    // 占用条
    UiKey.chart1: 0xFFB97500,
    UiKey.chart2: 0xFF73EDB1,
    UiKey.chart3: 0xFF3284D0,
    UiKey.chart4: 0xFFF999DA,
  },
  code: const {
    CodeKey.bg: 0xFF191410,
    CodeKey.fg: 0xFFF9E7DC,
    CodeKey.lineNumber: 0xFF706864,
    CodeKey.lineNumberActive: 0xFFF9E7DC,
    CodeKey.currentLine: 0x8037302C,
    CodeKey.selection: 0x42DC932E,
    CodeKey.cursor: 0xFFFEB354,
    CodeKey.searchHit: 0x61CACC4A,
    CodeKey.diffAddBg: 0xFF152D10,
    CodeKey.diffAddFg: 0xFFA0DE93,
    CodeKey.diffDelBg: 0xFF3F1917,
    CodeKey.diffDelFg: 0xFFFFABA3,
  },
  tokens: const {
    // 注释
    'comment': TokenStyle(color: 0xFF8C7E75, italic: true),
    'quote': TokenStyle(color: 0xFF8C7E75, italic: true),
    // 关键字
    'keyword': TokenStyle(color: 0xFFFFA15C),
    'variable.language': TokenStyle(color: 0xFFFFA15C, italic: true),
    'doctag': TokenStyle(color: 0xFFFFA15C, italic: true),
    'computation-expression': TokenStyle(color: 0xFFFFA15C),
    'template-tag': TokenStyle(color: 0xFFFFA15C),
    // 字符串
    'string': TokenStyle(color: 0xFF9FC988),
    'character': TokenStyle(color: 0xFF9FC988),
    'code': TokenStyle(color: 0xFF9FC988),
    // 转义 / 正则
    'regexp': TokenStyle(color: 0xFFF59AC5),
    'regex': TokenStyle(color: 0xFFF59AC5),
    'char.escape': TokenStyle(color: 0xFFF59AC5),
    'selector-pseudo': TokenStyle(color: 0xFFF59AC5),
    // 数字 / 字面量 / 符号
    'number': TokenStyle(color: 0xFFFF99A1),
    'literal': TokenStyle(color: 0xFFFF99A1),
    'variable.constant': TokenStyle(color: 0xFFFF99A1),
    'symbol': TokenStyle(color: 0xFFFF99A1),
    'label': TokenStyle(color: 0xFFFF99A1),
    'selector-id': TokenStyle(color: 0xFFFF99A1),
    'bullet': TokenStyle(color: 0xFFFF99A1),
    'formula': TokenStyle(color: 0xFFFF99A1),
    // 类型 / 类名
    'type': TokenStyle(color: 0xFFCDBB64),
    'title.class': TokenStyle(color: 0xFFCDBB64),
    'title.class.inherited': TokenStyle(color: 0xFFCDBB64, italic: true),
    'selector-class': TokenStyle(color: 0xFFCDBB64),
    // 内置的名字
    'built_in': TokenStyle(color: 0xFFD5A8DF),
    // 函数名 / 定义处的名字
    'title': TokenStyle(color: 0xFF7FC4EC),
    'title.function': TokenStyle(color: 0xFF7FC4EC),
    'title.function.invoke': TokenStyle(color: 0xFF7FC4EC),
    'section': TokenStyle(color: 0xFF7FC4EC, bold: true),
    // 变量
    'variable': TokenStyle(color: 0xFFDFCAB2),
    'template-variable': TokenStyle(color: 0xFFDFCAB2),
    // 属性
    'property': TokenStyle(color: 0xFF7CCCC1),
    'attr': TokenStyle(color: 0xFF7CCCC1),
    'attribute': TokenStyle(color: 0xFF7CCCC1),
    'selector-attr': TokenStyle(color: 0xFF7CCCC1),
    // 标签名
    'name': TokenStyle(color: 0xFFFF9E7C),
    'selector-tag': TokenStyle(color: 0xFFFF9E7C),
    // 标点 / 运算符
    'operator': TokenStyle(color: 0xFFCEB9AC),
    'punctuation': TokenStyle(color: 0xFFCEB9AC),
    'tag': TokenStyle(color: 0xFFCEB9AC),
    // 元信息
    'meta': TokenStyle(color: 0xFFB99B83),
    'meta.prompt': TokenStyle(color: 0xFFB99B83),
    // 链接
    'link': TokenStyle(color: 0xFF5FC7FF),
    // 新增
    'addition': TokenStyle(color: 0xFF8CCF7E),
    // 删除
    'deletion': TokenStyle(color: 0xFFFF9B93),
    'delete': TokenStyle(color: 0xFFFF9B93),
    // 不单独上色（跟代码文字一个色）
    'function': TokenStyle(),
    'function.dispatch': TokenStyle(),
    'class': TokenStyle(),
    'params': TokenStyle(),
    'subst': TokenStyle(),
    'emphasis': TokenStyle(italic: true),
    'strong': TokenStyle(bold: true),
  },
  terminal: const {
    'fg': 0xFFF9E7DC,
    'bg': 0xFF191410,
    'cursor': 0xFFFEB354,
    'selection': 0x4CDC932E,
    'searchHitBg': 0xFF3C4110,
    'searchHitBgCurrent': 0xFF6F5C00,
    'searchHitFg': 0xFFF9E7DC,
    'black': 0xFF75675E,
    'red': 0xFFFA9A85,
    'green': 0xFF99C877,
    'yellow': 0xFFE0AE57,
    'blue': 0xFF6BC1FD,
    'magenta': 0xFFE79AD6,
    'cyan': 0xFF3ED0C8,
    'white': 0xFFE1D5CD,
    'brightBlack': 0xFF8E7F76,
    'brightRed': 0xFFFFBFB1,
    'brightGreen': 0xFFB7E09A,
    'brightYellow': 0xFFF5C982,
    'brightBlue': 0xFFA4D8FF,
    'brightMagenta': 0xFFFBB8EC,
    'brightCyan': 0xFF79E7E0,
    'brightWhite': 0xFFFDF9F6,
  },
  blocks: const {
    'event': 0xFF8F4714, // 事件
    'variable': 0xFF9E2E4F, // 变量
    'widget': 0xFF2A5E9E, // 控件
    'control': 0xFF6146AF, // 流程
    'action': 0xFF226877, // 交互
    'network': 0xFF636023, // 网络
    'value': 0xFF6B594E, // 直接填的值
    'operator': 0xFF2E6D3F, // 运算
    'data': 0xFF863592, // 数据集合
    'request': 0xFF1E6D55, // 请求
    'response': 0xFF9F3329, // 返回
    'unknown': 0xFF6A6764, // 不认识的
    'function': 0xFF236B61, // 函数
    'text': 0xFF705B19, // 文字
    'list': 0xFF315BA5, // 列表
    'dict': 0xFF863690, // 字典
    'class': 0xFF4E6824, // 类
    'error': 0xFF9D3729, // 出错
    'async': 0xFF23677C, // 等待
    'custom': 0xFF4D52A9, // 我的积木
    BlockKey.text: 0xFFF9F1E3,
    BlockKey.fieldBg: 0xFFE5DCD7,
    BlockKey.fieldText: 0xFF291F18,
    BlockKey.fieldHint: 0xFF786C64,
    BlockKey.gloss: 0xFFFFFFFF,
    BlockKey.shade: 0xFF000000,
    BlockKey.selection: 0xFFFFCD44,
    BlockKey.ghost: 0x38FEFBF9,
    BlockKey.shadow: 0x8A000000,
    BlockKey.canvas: 0xFF1E1814,
    BlockKey.canvasDot: 0xFF37302C,
    BlockKey.error: 0xFFFF7266,
    BlockKey.warning: 0xFFFFBD58,
    BlockKey.onError: 0xFF250E0C,
    BlockKey.onWarning: 0xFF301D00,
  },
  lowcode: const {
    LowcodeKey.selection: 0xFFA16500,
    LowcodeKey.selectionText: 0xFFFFFFFF,
    LowcodeKey.handleFill: 0xFFFFFFFF,
    LowcodeKey.marginRing: 0x59CDAC00,
    LowcodeKey.paddingRing: 0x596EC75A,
    LowcodeKey.dropHoverBg: 0xFFF8D8B4,
    LowcodeKey.dropHoverBorder: 0xFFA16500,
    LowcodeKey.dropIdleBg: 0x0F1D140D,
    LowcodeKey.dropIdleBorder: 0xFFBEB6B0,
    LowcodeKey.dropText: 0xFF6F6762,
    LowcodeKey.insertBar: 0xFFA16500,
    LowcodeKey.insertBarIdle: 0xFFEFCA9F,
    LowcodeKey.dropOutline: 0xFFBEB6B0,
    LowcodeKey.dragChipBg: 0xFF653E00,
    LowcodeKey.dragChipText: 0xFFFFFFFF,
    LowcodeKey.sizeTagBg: 0xCC2F241C,
    LowcodeKey.sizeTagText: 0xFFFFFFFF,
    LowcodeKey.missingBg: 0xFFF5F4D5,
    LowcodeKey.missingBorder: 0xFFAB8F00,
    LowcodeKey.missingIcon: 0xFF766200,
    LowcodeKey.missingText: 0xFF5C4C00,
  },
  metrics: const {MetricKey.radiusScale: 0.9, MetricKey.spaceScale: 1, MetricKey.fontScale: 1, MetricKey.shadowStrength: 1, MetricKey.dividerWidth: 1, MetricKey.surfaceOpacity: 0.86},
);
