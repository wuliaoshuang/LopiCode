/// 内置主题（浅色）：高对比浅色、樱花。
///
/// 颜色是自己配的（没有照搬任何现成配色方案）：在 OKLCH 里定色相和彩度，再把明度调到对比度达标
///（正文 ≥ 4.5:1，图标 / 色块 ≥ 3:1；test/theme_contrast_test.dart 和 test/theme_builtin_test.dart 守着）。
/// 这里写的就是最终的值，要改直接改数字，改完跑那两个测试。清单和思路见 docs/themes-design.md “内置主题清单”。
library;

import 'package:lopicode/appearance/theme_fields.dart';
import 'package:lopicode/appearance/theme_spec.dart';

/// 高对比浅色（`builtin-contrast-light`，浅色）：纯白底、纯黑字、粗分隔线，所有文字对比度 7:1 以上。
///
/// 配色思路：给强光下和视力吃力时用：正文、次要文字、提示文字、强调色、每一类高亮都做到 7:1 以上（注释 5.5:1，靠斜体区分）；关键字加粗；分隔线加粗加深，圆角收小，阴影很淡——靠线而不是靠影子分层。积木压深一档，白字更清楚。
final ThemeSpec kContrastLightTheme = ThemeSpec(
  id: 'builtin-contrast-light',
  name: '高对比浅色',
  dark: false,
  builtin: true,
  ui: const {
    // 底色
    UiKey.bg: 0xFFFFFFFF,
    UiKey.canvas: 0xFFF2F2F2,
    UiKey.surface: 0xFFFFFFFF,
    UiKey.surfaceMuted: 0xFFE8E8E8,
    UiKey.codeBg: 0xFFF7F7F7,
    UiKey.cardBg: 0xFFFFFFFF,
    UiKey.inputBg: 0xFFFFFFFF,
    // 文字
    UiKey.text: 0xFF000000,
    UiKey.textMuted: 0xFF2E2E2E,
    UiKey.textFaint: 0xFF424242,
    UiKey.link: 0xFF003EB4,
    // 线
    UiKey.border: 0xFF868686,
    // 强调
    UiKey.accent: 0xFF003EB4,
    UiKey.accentSoft: 0xFFE6EFFF,
    UiKey.accentFill: 0xFF003EB4,
    UiKey.onAccent: 0xFFFAFCFF,
    UiKey.selectedBg: 0xFFE6EFFF,
    // 状态
    UiKey.danger: 0xFF94000C,
    UiKey.dangerSoft: 0xFFFFE9E6,
    UiKey.onDanger: 0xFFFAFCFF,
    UiKey.warning: 0xFF6C4300,
    UiKey.warningSoft: 0xFFFCECD9,
    UiKey.success: 0xFF005C27,
    UiKey.successSoft: 0xFFE1F5E4,
    UiKey.info: 0xFF005182,
    UiKey.infoSoft: 0xFFE1F1FF,
    UiKey.noticeBg: 0xFFFFE9E6,
    UiKey.noticeText: 0xFF94000C,
    // 导航与顶栏
    UiKey.navBg: 0xFFFFFFFF,
    UiKey.navActive: 0xFF000000,
    UiKey.navInactive: 0xFF424242,
    UiKey.barButtonBg: 0xFFFFFFFF,
    // 聊天
    UiKey.bubbleMineBg: 0xFFE6EFFF,
    UiKey.bubbleMineText: 0xFF000000,
    UiKey.bubbleAgentBg: 0xFFE8E8E8,
    UiKey.bubbleAgentText: 0xFF000000,
    // 提示条
    UiKey.snackBg: 0xFF262626,
    UiKey.snackText: 0xFFF5F5F5,
    // 遮罩与阴影
    UiKey.scrim: 0xFF090B0F,
    UiKey.shadow: 0xFF171B22,
    UiKey.backdropScrim: 0x66FFFFFF,
    // 占用条
    UiKey.chart1: 0xFF1E4798,
    UiKey.chart2: 0xFFD16B9B,
    UiKey.chart3: 0xFF876200,
    UiKey.chart4: 0xFF00A585,
  },
  code: const {
    CodeKey.bg: 0xFFF7F7F7,
    CodeKey.fg: 0xFF000000,
    CodeKey.lineNumber: 0xFF707070,
    CodeKey.lineNumberActive: 0xFF000000,
    CodeKey.currentLine: 0x80E8E8E8,
    CodeKey.selection: 0x423778F5,
    CodeKey.cursor: 0xFF003EB4,
    CodeKey.searchHit: 0x61CF9C00,
    CodeKey.diffAddBg: 0xFFD1F2D7,
    CodeKey.diffAddFg: 0xFF005E28,
    CodeKey.diffDelBg: 0xFFFFE0DB,
    CodeKey.diffDelFg: 0xFF972622,
  },
  tokens: const {
    // 注释
    'comment': TokenStyle(color: 0xFF606369, italic: true),
    'quote': TokenStyle(color: 0xFF606369, italic: true),
    // 关键字
    'keyword': TokenStyle(color: 0xFF153BB7, bold: true),
    'variable.language': TokenStyle(color: 0xFF153BB7, italic: true),
    'doctag': TokenStyle(color: 0xFF153BB7, italic: true),
    'computation-expression': TokenStyle(color: 0xFF153BB7),
    'template-tag': TokenStyle(color: 0xFF153BB7),
    // 字符串
    'string': TokenStyle(color: 0xFF940015),
    'character': TokenStyle(color: 0xFF940015),
    'code': TokenStyle(color: 0xFF940015),
    // 转义 / 正则
    'regexp': TokenStyle(color: 0xFF820A73),
    'regex': TokenStyle(color: 0xFF820A73),
    'char.escape': TokenStyle(color: 0xFF820A73),
    'selector-pseudo': TokenStyle(color: 0xFF820A73),
    // 数字 / 字面量 / 符号
    'number': TokenStyle(color: 0xFF005E15),
    'literal': TokenStyle(color: 0xFF005E15),
    'variable.constant': TokenStyle(color: 0xFF005E15),
    'symbol': TokenStyle(color: 0xFF005E15),
    'label': TokenStyle(color: 0xFF005E15),
    'selector-id': TokenStyle(color: 0xFF005E15),
    'bullet': TokenStyle(color: 0xFF005E15),
    'formula': TokenStyle(color: 0xFF005E15),
    // 类型 / 类名
    'type': TokenStyle(color: 0xFF005959),
    'title.class': TokenStyle(color: 0xFF005959),
    'title.class.inherited': TokenStyle(color: 0xFF005959, italic: true),
    'selector-class': TokenStyle(color: 0xFF005959),
    // 内置的名字
    'built_in': TokenStyle(color: 0xFF7B3600),
    // 函数名 / 定义处的名字
    'title': TokenStyle(color: 0xFF652399),
    'title.function': TokenStyle(color: 0xFF652399),
    'title.function.invoke': TokenStyle(color: 0xFF652399),
    'section': TokenStyle(color: 0xFF652399, bold: true),
    // 变量
    'variable': TokenStyle(color: 0xFF444D5E),
    'template-variable': TokenStyle(color: 0xFF444D5E),
    // 属性
    'property': TokenStyle(color: 0xFF495400),
    'attr': TokenStyle(color: 0xFF495400),
    'attribute': TokenStyle(color: 0xFF495400),
    'selector-attr': TokenStyle(color: 0xFF495400),
    // 标签名
    'name': TokenStyle(color: 0xFF153BB7),
    'selector-tag': TokenStyle(color: 0xFF153BB7),
    // 标点 / 运算符
    'operator': TokenStyle(color: 0xFF2C2E30),
    'punctuation': TokenStyle(color: 0xFF2C2E30),
    'tag': TokenStyle(color: 0xFF2C2E30),
    // 元信息
    'meta': TokenStyle(color: 0xFF454778),
    'meta.prompt': TokenStyle(color: 0xFF454778),
    // 链接
    'link': TokenStyle(color: 0xFF005182),
    // 新增
    'addition': TokenStyle(color: 0xFF005E28),
    // 删除
    'deletion': TokenStyle(color: 0xFF901114),
    'delete': TokenStyle(color: 0xFF901114),
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
    'fg': 0xFF000000,
    'bg': 0xFFF7F7F7,
    'cursor': 0xFF003EB4,
    'selection': 0x4C3778F5,
    'searchHitBg': 0xFFF5DC98,
    'searchHitBgCurrent': 0xFFFAAB3F,
    'searchHitFg': 0xFF000000,
    'black': 0xFF24272B,
    'red': 0xFF94020D,
    'green': 0xFF005E15,
    'yellow': 0xFF713F00,
    'blue': 0xFF1E41A8,
    'magenta': 0xFF781B7E,
    'cyan': 0xFF005860,
    'white': 0xFF838588,
    'brightBlack': 0xFF6A6E74,
    'brightRed': 0xFF730007,
    'brightGreen': 0xFF00480E,
    'brightYellow': 0xFF572F00,
    'brightBlue': 0xFF07239E,
    'brightMagenta': 0xFF610068,
    'brightCyan': 0xFF00434A,
    'brightWhite': 0xFF5B5D5F,
  },
  blocks: const {
    'event': 0xFF8E3C00, // 事件
    'variable': 0xFFA3004C, // 变量
    'widget': 0xFF0059A1, // 控件
    'control': 0xFF5A2DC8, // 流程
    'action': 0xFF006373, // 交互
    'network': 0xFF625A00, // 网络
    'value': 0xFF4E5969, // 直接填的值
    'operator': 0xFF006B24, // 运算
    'data': 0xFF8803A2, // 数据集合
    'request': 0xFF00694B, // 请求
    'response': 0xFFA80015, // 返回
    'unknown': 0xFF606265, // 不认识的
    'function': 0xFF00675A, // 函数
    'text': 0xFF6E5400, // 文字
    'list': 0xFF0052B5, // 列表
    'dict': 0xFF8901A1, // 字典
    'class': 0xFF4A6200, // 类
    'error': 0xFFA8000B, // 出错
    'async': 0xFF006278, // 等待
    'custom': 0xFF3E42C0, // 我的积木
    BlockKey.text: 0xFFFFFFFF,
    BlockKey.fieldBg: 0xFFFCFDFF,
    BlockKey.fieldText: 0xFF1C222B,
    BlockKey.fieldHint: 0xFF7D8390,
    BlockKey.gloss: 0xFFFFFFFF,
    BlockKey.shade: 0xFF000000,
    BlockKey.selection: 0xFFD152BB,
    BlockKey.ghost: 0x3311161F,
    BlockKey.shadow: 0x52171B22,
    BlockKey.canvas: 0xFFF2F2F2,
    BlockKey.canvasDot: 0xFFD2D2D2,
    BlockKey.error: 0xFFDE3C37,
    BlockKey.warning: 0xFFB37900,
    BlockKey.onError: 0xFFFFFFFF,
    BlockKey.onWarning: 0xFF301D00,
  },
  lowcode: const {
    LowcodeKey.selection: 0xFF2D6CE9,
    LowcodeKey.selectionText: 0xFFFFFFFF,
    LowcodeKey.handleFill: 0xFFFFFFFF,
    LowcodeKey.marginRing: 0x59ED990E,
    LowcodeKey.paddingRing: 0x594BCB71,
    LowcodeKey.dropHoverBg: 0xFFCDDFFF,
    LowcodeKey.dropHoverBorder: 0xFF2D6CE9,
    LowcodeKey.dropIdleBg: 0x0F11161F,
    LowcodeKey.dropIdleBorder: 0xFFB4B7BD,
    LowcodeKey.dropText: 0xFF66696F,
    LowcodeKey.insertBar: 0xFF2D6CE9,
    LowcodeKey.insertBarIdle: 0xFFB9D2FF,
    LowcodeKey.dropOutline: 0xFFB4B7BD,
    LowcodeKey.dragChipBg: 0xFF003AA9,
    LowcodeKey.dragChipText: 0xFFFFFFFF,
    LowcodeKey.sizeTagBg: 0xCC24272B,
    LowcodeKey.sizeTagText: 0xFFFFFFFF,
    LowcodeKey.missingBg: 0xFFFFF0D7,
    LowcodeKey.missingBorder: 0xFFCA8100,
    LowcodeKey.missingIcon: 0xFF8A5600,
    LowcodeKey.missingText: 0xFF6C4300,
  },
  metrics: const {MetricKey.radiusScale: 0.6, MetricKey.spaceScale: 1, MetricKey.fontScale: 1, MetricKey.shadowStrength: 0.4, MetricKey.dividerWidth: 1.5, MetricKey.surfaceOpacity: 0.96},
);

/// 樱花（`builtin-sakura`，浅色）：带粉的白底配玫瑰色，很圆，积木是粉彩色配深色字。
///
/// 配色思路：灰阶带一点粉（色相 350°）；强调色是玫瑰红，危险色往橙红偏开免得和强调色混。高亮：玫瑰关键字、青绿字符串、紫数字、蓝类型、绿函数名。这一套的积木和别的都不一样——粉彩色的底配深梅色的字，像糖果。圆角最大。
final ThemeSpec kSakuraTheme = ThemeSpec(
  id: 'builtin-sakura',
  name: '樱花',
  dark: false,
  builtin: true,
  ui: const {
    // 底色
    UiKey.bg: 0xFFFFF6FA,
    UiKey.canvas: 0xFFF8EEF2,
    UiKey.surface: 0xFFFFFDFE,
    UiKey.surfaceMuted: 0xFFEEE4E8,
    UiKey.codeBg: 0xFFF8EEF2,
    UiKey.cardBg: 0xFFFFFDFE,
    UiKey.inputBg: 0xFFFFFDFE,
    // 文字
    UiKey.text: 0xFF36222B,
    UiKey.textMuted: 0xFF624B55,
    UiKey.textFaint: 0xFF775F6A,
    UiKey.link: 0xFFAC3668,
    // 线
    UiKey.border: 0xFFE0D6DA,
    // 强调
    UiKey.accent: 0xFFAC3668,
    UiKey.accentSoft: 0xFFFFE0E9,
    UiKey.accentFill: 0xFFAC3668,
    UiKey.onAccent: 0xFFFEFBFC,
    UiKey.selectedBg: 0xFFFFE0E9,
    // 状态
    UiKey.danger: 0xFFB61D00,
    UiKey.dangerSoft: 0xFFFFE9E4,
    UiKey.onDanger: 0xFFFEFBFC,
    UiKey.warning: 0xFF835A00,
    UiKey.warningSoft: 0xFFFAEDD9,
    UiKey.success: 0xFF007742,
    UiKey.successSoft: 0xFFE0F5E6,
    UiKey.info: 0xFF1666AA,
    UiKey.infoSoft: 0xFFE2F0FF,
    UiKey.noticeBg: 0xFFFFE9E4,
    UiKey.noticeText: 0xFF901500,
    // 导航与顶栏
    UiKey.navBg: 0xFFFFF6FA,
    UiKey.navActive: 0xFFAC3668,
    UiKey.navInactive: 0xFF775F6A,
    UiKey.barButtonBg: 0xFFFFFDFE,
    // 聊天
    UiKey.bubbleMineBg: 0xFFFFE0E9,
    UiKey.bubbleMineText: 0xFF36222B,
    UiKey.bubbleAgentBg: 0xFFEEE4E8,
    UiKey.bubbleAgentText: 0xFF36222B,
    // 提示条
    UiKey.snackBg: 0xFF2E2328,
    UiKey.snackText: 0xFFFCF2F6,
    // 遮罩与阴影
    UiKey.scrim: 0xFF15050D,
    UiKey.shadow: 0xFF28131D,
    UiKey.backdropScrim: 0x66FFF6FA,
    // 占用条
    UiKey.chart1: 0xFF84204D,
    UiKey.chart2: 0xFFB38B00,
    UiKey.chart3: 0xFF007B69,
    UiKey.chart4: 0xFF6D8DE8,
  },
  code: const {
    CodeKey.bg: 0xFFF8EEF2,
    CodeKey.fg: 0xFF36222B,
    CodeKey.lineNumber: 0xFF898084,
    CodeKey.lineNumberActive: 0xFF36222B,
    CodeKey.currentLine: 0x80EEE4E8,
    CodeKey.selection: 0x42C84F80,
    CodeKey.cursor: 0xFFAC3668,
    CodeKey.searchHit: 0x61C4A100,
    CodeKey.diffAddBg: 0xFFCFF2DA,
    CodeKey.diffAddFg: 0xFF005D33,
    CodeKey.diffDelBg: 0xFFFFE0D9,
    CodeKey.diffDelFg: 0xFF972815,
  },
  tokens: const {
    // 注释
    'comment': TokenStyle(color: 0xFF78686F, italic: true),
    'quote': TokenStyle(color: 0xFF78686F, italic: true),
    // 关键字
    'keyword': TokenStyle(color: 0xFFA92963),
    'variable.language': TokenStyle(color: 0xFFA92963, italic: true),
    'doctag': TokenStyle(color: 0xFFA92963, italic: true),
    'computation-expression': TokenStyle(color: 0xFFA92963),
    'template-tag': TokenStyle(color: 0xFFA92963),
    // 字符串
    'string': TokenStyle(color: 0xFF00736E),
    'character': TokenStyle(color: 0xFF00736E),
    'code': TokenStyle(color: 0xFF00736E),
    // 转义 / 正则
    'regexp': TokenStyle(color: 0xFFAC3037),
    'regex': TokenStyle(color: 0xFFAC3037),
    'char.escape': TokenStyle(color: 0xFFAC3037),
    'selector-pseudo': TokenStyle(color: 0xFFAC3037),
    // 数字 / 字面量 / 符号
    'number': TokenStyle(color: 0xFF714CA6),
    'literal': TokenStyle(color: 0xFF714CA6),
    'variable.constant': TokenStyle(color: 0xFF714CA6),
    'symbol': TokenStyle(color: 0xFF714CA6),
    'label': TokenStyle(color: 0xFF714CA6),
    'selector-id': TokenStyle(color: 0xFF714CA6),
    'bullet': TokenStyle(color: 0xFF714CA6),
    'formula': TokenStyle(color: 0xFF714CA6),
    // 类型 / 类名
    'type': TokenStyle(color: 0xFF0B67A9),
    'title.class': TokenStyle(color: 0xFF0B67A9),
    'title.class.inherited': TokenStyle(color: 0xFF0B67A9, italic: true),
    'selector-class': TokenStyle(color: 0xFF0B67A9),
    // 内置的名字
    'built_in': TokenStyle(color: 0xFF9A4900),
    // 函数名 / 定义处的名字
    'title': TokenStyle(color: 0xFF21763C),
    'title.function': TokenStyle(color: 0xFF21763C),
    'title.function.invoke': TokenStyle(color: 0xFF21763C),
    'section': TokenStyle(color: 0xFF21763C, bold: true),
    // 变量
    'variable': TokenStyle(color: 0xFF684756),
    'template-variable': TokenStyle(color: 0xFF684756),
    // 属性
    'property': TokenStyle(color: 0xFF73630A),
    'attr': TokenStyle(color: 0xFF73630A),
    'attribute': TokenStyle(color: 0xFF73630A),
    'selector-attr': TokenStyle(color: 0xFF73630A),
    // 标签名
    'name': TokenStyle(color: 0xFFA92963),
    'selector-tag': TokenStyle(color: 0xFFA92963),
    // 标点 / 运算符
    'operator': TokenStyle(color: 0xFF644A56),
    'punctuation': TokenStyle(color: 0xFF644A56),
    'tag': TokenStyle(color: 0xFF644A56),
    // 元信息
    'meta': TokenStyle(color: 0xFF685C81),
    'meta.prompt': TokenStyle(color: 0xFF685C81),
    // 链接
    'link': TokenStyle(color: 0xFF1666AA),
    // 新增
    'addition': TokenStyle(color: 0xFF007742),
    // 删除
    'deletion': TokenStyle(color: 0xFFAB331F),
    'delete': TokenStyle(color: 0xFFAB331F),
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
    'fg': 0xFF36222B,
    'bg': 0xFFF8EEF2,
    'cursor': 0xFFAC3668,
    'selection': 0x4CC84F80,
    'searchHitBg': 0xFFEEDF99,
    'searchHitBgCurrent': 0xFFF2B036,
    'searchHitFg': 0xFF36222B,
    'black': 0xFF2F2228,
    'red': 0xFFA93F55,
    'green': 0xFF007C4E,
    'yellow': 0xFF896100,
    'blue': 0xFF3C65B9,
    'magenta': 0xFF994486,
    'cyan': 0xFF007784,
    'white': 0xFF8A7E83,
    'brightBlack': 0xFF75666C,
    'brightRed': 0xFF991A3F,
    'brightGreen': 0xFF00663F,
    'brightYellow': 0xFF704E00,
    'brightBlue': 0xFF214DAD,
    'brightMagenta': 0xFF892575,
    'brightCyan': 0xFF00616C,
    'brightWhite': 0xFF62565B,
  },
  blocks: const {
    'event': 0xFFF7C0A5, // 事件
    'variable': 0xFFFEB7C7, // 变量
    'widget': 0xFFABD2FE, // 控件
    'control': 0xFFCAC6FF, // 流程
    'action': 0xFFACD6E0, // 交互
    'network': 0xFFD3D0A8, // 网络
    'value': 0xFFD6CACF, // 直接填的值
    'operator': 0xFFB4D9B7, // 运算
    'data': 0xFFE6BCF1, // 数据集合
    'request': 0xFFADDAC5, // 请求
    'response': 0xFFFFBAB2, // 返回
    'unknown': 0xFFC7C2C4, // 不认识的
    'function': 0xFFAED8CF, // 函数
    'text': 0xFFDDCCA5, // 文字
    'list': 0xFFB0D0FF, // 列表
    'dict': 0xFFE7BCF1, // 字典
    'class': 0xFFC4D6A8, // 类
    'error': 0xFFFFBAB0, // 出错
    'async': 0xFFACD6E4, // 等待
    'custom': 0xFFCBC6FF, // 我的积木
    BlockKey.text: 0xFF442032,
    BlockKey.fieldBg: 0xFFFFFDFE,
    BlockKey.fieldText: 0xFF291E23,
    BlockKey.fieldHint: 0xFF8E7F85,
    BlockKey.gloss: 0xFFFFFFFF,
    BlockKey.shade: 0xFF000000,
    BlockKey.selection: 0xFFDF4C8A,
    BlockKey.ghost: 0x331D1217,
    BlockKey.shadow: 0x5228131D,
    BlockKey.canvas: 0xFFF8EEF2,
    BlockKey.canvasDot: 0xFFD8CFD3,
    BlockKey.error: 0xFFDE3C37,
    BlockKey.warning: 0xFFB27800,
    BlockKey.onError: 0xFFFFFFFF,
    BlockKey.onWarning: 0xFF301D00,
  },
  lowcode: const {
    LowcodeKey.selection: 0xFFBF4879,
    LowcodeKey.selectionText: 0xFFFFFFFF,
    LowcodeKey.handleFill: 0xFFFFFFFF,
    LowcodeKey.marginRing: 0x59E39F00,
    LowcodeKey.paddingRing: 0x5933CC7D,
    LowcodeKey.dropHoverBg: 0xFFFFCFDE,
    LowcodeKey.dropHoverBorder: 0xFFBF4879,
    LowcodeKey.dropIdleBg: 0x0F1D1217,
    LowcodeKey.dropIdleBorder: 0xFFBEB4B8,
    LowcodeKey.dropText: 0xFF6F666A,
    LowcodeKey.insertBar: 0xFFBF4879,
    LowcodeKey.insertBarIdle: 0xFFF8BED1,
    LowcodeKey.dropOutline: 0xFFBEB4B8,
    LowcodeKey.dragChipBg: 0xFF840447,
    LowcodeKey.dragChipText: 0xFFFFFFFF,
    LowcodeKey.sizeTagBg: 0xCC2F2228,
    LowcodeKey.sizeTagText: 0xFFFFFFFF,
    LowcodeKey.missingBg: 0xFFFDF1D4,
    LowcodeKey.missingBorder: 0xFFC08600,
    LowcodeKey.missingIcon: 0xFF835A00,
    LowcodeKey.missingText: 0xFF674600,
  },
  metrics: const {MetricKey.radiusScale: 1.6, MetricKey.spaceScale: 1.05, MetricKey.fontScale: 1, MetricKey.shadowStrength: 0.8, MetricKey.dividerWidth: 1, MetricKey.surfaceOpacity: 0.85},
);
