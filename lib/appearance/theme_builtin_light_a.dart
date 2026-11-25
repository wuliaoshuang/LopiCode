/// 内置主题（浅色）：暖纸、薄荷。
///
/// 颜色是自己配的（没有照搬任何现成配色方案）：在 OKLCH 里定色相和彩度，再把明度调到对比度达标
///（正文 ≥ 4.5:1，图标 / 色块 ≥ 3:1；test/theme_contrast_test.dart 和 test/theme_builtin_test.dart 守着）。
/// 这里写的就是最终的值，要改直接改数字，改完跑那两个测试。清单和思路见 docs/themes-design.md “内置主题清单”。
library;

import 'package:lopicode/appearance/theme_fields.dart';
import 'package:lopicode/appearance/theme_spec.dart';

/// 暖纸（`builtin-paper`，浅色）：米色纸面配墨褐字，赭红强调，像一本旧笔记本。
///
/// 配色思路：底色和文字都带一点暖黄（色相 80°），不用纯白纯黑；强调色是赭红。高亮走“墨水”路子：赭红关键字、苔绿字符串、靛蓝函数名、梅紫数字，彩度都压低。积木比默认略降彩度，贴合纸面。圆角略大、阴影略淡。
final ThemeSpec kPaperTheme = ThemeSpec(
  id: 'builtin-paper',
  name: '暖纸',
  dark: false,
  builtin: true,
  ui: const {
    // 底色
    UiKey.bg: 0xFFFAF5ED,
    UiKey.canvas: 0xFFF1ECE4,
    UiKey.surface: 0xFFFFFAF3,
    UiKey.surfaceMuted: 0xFFE7E2DA,
    UiKey.codeBg: 0xFFF1ECE4,
    UiKey.cardBg: 0xFFFFFAF3,
    UiKey.inputBg: 0xFFFFFAF3,
    // 文字
    UiKey.text: 0xFF2E2516,
    UiKey.textMuted: 0xFF584E3F,
    UiKey.textFaint: 0xFF6C6251,
    UiKey.link: 0xFFA94524,
    // 线
    UiKey.border: 0xFFDAD5CD,
    // 强调
    UiKey.accent: 0xFFA94524,
    UiKey.accentSoft: 0xFFFEE1D7,
    UiKey.accentFill: 0xFFA94524,
    UiKey.onAccent: 0xFFFDFBF9,
    UiKey.selectedBg: 0xFFFEE1D7,
    // 状态
    UiKey.danger: 0xFFB32130,
    UiKey.dangerSoft: 0xFFFFE8E7,
    UiKey.onDanger: 0xFFFDFBF9,
    UiKey.warning: 0xFF885700,
    UiKey.warningSoft: 0xFFFCECD9,
    UiKey.success: 0xFF357426,
    UiKey.successSoft: 0xFFE4F4E1,
    UiKey.info: 0xFF1666AA,
    UiKey.infoSoft: 0xFFE2F0FF,
    UiKey.noticeBg: 0xFFFFE8E7,
    UiKey.noticeText: 0xFF910C20,
    // 导航与顶栏
    UiKey.navBg: 0xFFFAF5ED,
    UiKey.navActive: 0xFF2E2516,
    UiKey.navInactive: 0xFF6C6251,
    UiKey.barButtonBg: 0xFFFFFAF3,
    // 聊天
    UiKey.bubbleMineBg: 0xFFFEE1D7,
    UiKey.bubbleMineText: 0xFF2E2517,
    UiKey.bubbleAgentBg: 0xFFE7E2DA,
    UiKey.bubbleAgentText: 0xFF2E2516,
    // 提示条
    UiKey.snackBg: 0xFF2B261D,
    UiKey.snackText: 0xFFF9F4EC,
    // 遮罩与阴影
    UiKey.scrim: 0xFF120900,
    UiKey.shadow: 0xFF241804,
    UiKey.backdropScrim: 0x66FAF5ED,
    // 占用条
    UiKey.chart1: 0xFF872700,
    UiKey.chart2: 0xFF739B33,
    UiKey.chart3: 0xFF00758D,
    UiKey.chart4: 0xFFAB7AD5,
  },
  code: const {
    CodeKey.bg: 0xFFF1ECE4,
    CodeKey.fg: 0xFF2E2517,
    CodeKey.lineNumber: 0xFF848079,
    CodeKey.lineNumberActive: 0xFF2E2516,
    CodeKey.currentLine: 0x80E7E2DA,
    CodeKey.selection: 0x42C45E3D,
    CodeKey.cursor: 0xFFA94524,
    CodeKey.searchHit: 0x61CC9D00,
    CodeKey.diffAddBg: 0xFFD7F1D1,
    CodeKey.diffAddFg: 0xFF225C13,
    CodeKey.diffDelBg: 0xFFFFDFDD,
    CodeKey.diffDelFg: 0xFF97242D,
  },
  tokens: const {
    // 注释
    'comment': TokenStyle(color: 0xFF71695C, italic: true),
    'quote': TokenStyle(color: 0xFF71695C, italic: true),
    // 关键字
    'keyword': TokenStyle(color: 0xFFA83825),
    'variable.language': TokenStyle(color: 0xFFA83825, italic: true),
    'doctag': TokenStyle(color: 0xFFA83825, italic: true),
    'computation-expression': TokenStyle(color: 0xFFA83825),
    'template-tag': TokenStyle(color: 0xFFA83825),
    // 字符串
    'string': TokenStyle(color: 0xFF46712B),
    'character': TokenStyle(color: 0xFF46712B),
    'code': TokenStyle(color: 0xFF46712B),
    // 转义 / 正则
    'regexp': TokenStyle(color: 0xFF9B3B6E),
    'regex': TokenStyle(color: 0xFF9B3B6E),
    'char.escape': TokenStyle(color: 0xFF9B3B6E),
    'selector-pseudo': TokenStyle(color: 0xFF9B3B6E),
    // 数字 / 字面量 / 符号
    'number': TokenStyle(color: 0xFF814A8D),
    'literal': TokenStyle(color: 0xFF814A8D),
    'variable.constant': TokenStyle(color: 0xFF814A8D),
    'symbol': TokenStyle(color: 0xFF814A8D),
    'label': TokenStyle(color: 0xFF814A8D),
    'selector-id': TokenStyle(color: 0xFF814A8D),
    'bullet': TokenStyle(color: 0xFF814A8D),
    'formula': TokenStyle(color: 0xFF814A8D),
    // 类型 / 类名
    'type': TokenStyle(color: 0xFF006D8F),
    'title.class': TokenStyle(color: 0xFF006D8F),
    'title.class.inherited': TokenStyle(color: 0xFF006D8F, italic: true),
    'selector-class': TokenStyle(color: 0xFF006D8F),
    // 内置的名字
    'built_in': TokenStyle(color: 0xFF835A00),
    // 函数名 / 定义处的名字
    'title': TokenStyle(color: 0xFF3463A6),
    'title.function': TokenStyle(color: 0xFF3463A6),
    'title.function.invoke': TokenStyle(color: 0xFF3463A6),
    'section': TokenStyle(color: 0xFF3463A6, bold: true),
    // 变量
    'variable': TokenStyle(color: 0xFF6C4932),
    'template-variable': TokenStyle(color: 0xFF6C4932),
    // 属性
    'property': TokenStyle(color: 0xFF097463),
    'attr': TokenStyle(color: 0xFF097463),
    'attribute': TokenStyle(color: 0xFF097463),
    'selector-attr': TokenStyle(color: 0xFF097463),
    // 标签名
    'name': TokenStyle(color: 0xFFA8353E),
    'selector-tag': TokenStyle(color: 0xFFA8353E),
    // 标点 / 运算符
    'operator': TokenStyle(color: 0xFF594E3B),
    'punctuation': TokenStyle(color: 0xFF594E3B),
    'tag': TokenStyle(color: 0xFF594E3B),
    // 元信息
    'meta': TokenStyle(color: 0xFF625E83),
    'meta.prompt': TokenStyle(color: 0xFF625E83),
    // 链接
    'link': TokenStyle(color: 0xFF1666AA),
    // 新增
    'addition': TokenStyle(color: 0xFF357426),
    // 删除
    'deletion': TokenStyle(color: 0xFFAC3037),
    'delete': TokenStyle(color: 0xFFAC3037),
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
    'fg': 0xFF2E2517,
    'bg': 0xFFF1ECE4,
    'cursor': 0xFFA94524,
    'selection': 0x4CC45E3D,
    'searchHitBg': 0xFFF3DD99,
    'searchHitBgCurrent': 0xFFF8AC3D,
    'searchHitFg': 0xFF2E2517,
    'black': 0xFF2C251A,
    'red': 0xFFA74639,
    'green': 0xFF467418,
    'yellow': 0xFF8C5F00,
    'blue': 0xFF116DAF,
    'magenta': 0xFF934989,
    'cyan': 0xFF007674,
    'white': 0xFF837D73,
    'brightBlack': 0xFF6F675A,
    'brightRed': 0xFF97271B,
    'brightGreen': 0xFF376300,
    'brightYellow': 0xFF724D00,
    'brightBlue': 0xFF005993,
    'brightMagenta': 0xFF832C78,
    'brightCyan': 0xFF006360,
    'brightWhite': 0xFF5C564D,
  },
  blocks: const {
    'event': 0xFFA24E10, // 事件
    'variable': 0xFFB23159, // 变量
    'widget': 0xFF2D69B3, // 控件
    'control': 0xFF6D4DC6, // 流程
    'action': 0xFF227486, // 交互
    'network': 0xFF706C24, // 网络
    'value': 0xFF726756, // 直接填的值
    'operator': 0xFF317A46, // 运算
    'data': 0xFF9739A5, // 数据集合
    'request': 0xFF1D7A5E, // 请求
    'response': 0xFFB4372B, // 返回
    'unknown': 0xFF6D6B67, // 不认识的
    'function': 0xFF23786D, // 函数
    'text': 0xFF7E6617, // 文字
    'list': 0xFF3665BB, // 列表
    'dict': 0xFF973BA3, // 字典
    'class': 0xFF567425, // 类
    'error': 0xFFB13B2B, // 出错
    'async': 0xFF23738C, // 等待
    'custom': 0xFF565BBF, // 我的积木
    BlockKey.text: 0xFFFFFBF6,
    BlockKey.fieldBg: 0xFFFEFDFB,
    BlockKey.fieldText: 0xFF272117,
    BlockKey.fieldHint: 0xFF8A8276,
    BlockKey.gloss: 0xFFFFFFFF,
    BlockKey.shade: 0xFF000000,
    BlockKey.selection: 0xFF3481DE,
    BlockKey.ghost: 0x331B150B,
    BlockKey.shadow: 0x52241804,
    BlockKey.canvas: 0xFFF1ECE4,
    BlockKey.canvasDot: 0xFFD1CDC5,
    BlockKey.error: 0xFFDE3C37,
    BlockKey.warning: 0xFFAF7500,
    BlockKey.onError: 0xFFFFFFFF,
    BlockKey.onWarning: 0xFF301D00,
  },
  lowcode: const {
    LowcodeKey.selection: 0xFFBB5535,
    LowcodeKey.selectionText: 0xFFFFFFFF,
    LowcodeKey.handleFill: 0xFFFFFFFF,
    LowcodeKey.marginRing: 0x59EB9A04,
    LowcodeKey.paddingRing: 0x596EC75A,
    LowcodeKey.dropHoverBg: 0xFFFFD3C5,
    LowcodeKey.dropHoverBorder: 0xFFBB5535,
    LowcodeKey.dropIdleBg: 0x0F1B150B,
    LowcodeKey.dropIdleBorder: 0xFFBBB7AF,
    LowcodeKey.dropText: 0xFF6D6861,
    LowcodeKey.insertBar: 0xFFBB5535,
    LowcodeKey.insertBarIdle: 0xFFFBC2B0,
    LowcodeKey.dropOutline: 0xFFBBB7AF,
    LowcodeKey.dragChipBg: 0xFF7F2400,
    LowcodeKey.dragChipText: 0xFFFFFFFF,
    LowcodeKey.sizeTagBg: 0xCC2C251A,
    LowcodeKey.sizeTagText: 0xFFFFFFFF,
    LowcodeKey.missingBg: 0xFFFFF0D5,
    LowcodeKey.missingBorder: 0xFFC88200,
    LowcodeKey.missingIcon: 0xFF885700,
    LowcodeKey.missingText: 0xFF6B4300,
  },
  metrics: const {MetricKey.radiusScale: 1.15, MetricKey.spaceScale: 1, MetricKey.fontScale: 1, MetricKey.shadowStrength: 0.8, MetricKey.dividerWidth: 1, MetricKey.surfaceOpacity: 0.9},
);

/// 薄荷（`builtin-mint`，浅色）：清凉的薄荷白配森林绿，圆润、留白多。
///
/// 配色思路：灰阶带一点青绿（色相 165°）；强调色是森林绿，底部导航选中也用它。高亮用冷色做主（紫关键字、绿字符串、蓝类型、青函数名），橙色的数字和珊瑚色的标签做点缀。圆角最大的一档之一，间距略松。
final ThemeSpec kMintTheme = ThemeSpec(
  id: 'builtin-mint',
  name: '薄荷',
  dark: false,
  builtin: true,
  ui: const {
    // 底色
    UiKey.bg: 0xFFF4FCF8,
    UiKey.canvas: 0xFFEBF3EF,
    UiKey.surface: 0xFFFCFFFD,
    UiKey.surfaceMuted: 0xFFE2EAE6,
    UiKey.codeBg: 0xFFEBF3EF,
    UiKey.cardBg: 0xFFFCFFFD,
    UiKey.inputBg: 0xFFFCFFFD,
    // 文字
    UiKey.text: 0xFF18251F,
    UiKey.textMuted: 0xFF42514A,
    UiKey.textFaint: 0xFF5A6A62,
    UiKey.link: 0xFF00794A,
    // 线
    UiKey.border: 0xFFD5DDD9,
    // 强调
    UiKey.accent: 0xFF00794A,
    UiKey.accentSoft: 0xFFD9F3E2,
    UiKey.accentFill: 0xFF067D4D,
    UiKey.onAccent: 0xFFF9FDFB,
    UiKey.selectedBg: 0xFFD9F3E2,
    // 状态
    UiKey.danger: 0xFFB02B27,
    UiKey.dangerSoft: 0xFFFFE9E6,
    UiKey.onDanger: 0xFFF9FDFB,
    UiKey.warning: 0xFF865900,
    UiKey.warningSoft: 0xFFFBECD9,
    UiKey.success: 0xFF137738,
    UiKey.successSoft: 0xFFE1F5E4,
    UiKey.info: 0xFF006A9D,
    UiKey.infoSoft: 0xFFDFF1FF,
    UiKey.noticeBg: 0xFFFFE9E6,
    UiKey.noticeText: 0xFF8E1818,
    // 导航与顶栏
    UiKey.navBg: 0xFFF4FCF8,
    UiKey.navActive: 0xFF00794A,
    UiKey.navInactive: 0xFF5A6A62,
    UiKey.barButtonBg: 0xFFFCFFFD,
    // 聊天
    UiKey.bubbleMineBg: 0xFFD9F3E2,
    UiKey.bubbleMineText: 0xFF18251F,
    UiKey.bubbleAgentBg: 0xFFE2EAE6,
    UiKey.bubbleAgentText: 0xFF18251F,
    // 提示条
    UiKey.snackBg: 0xFF202925,
    UiKey.snackText: 0xFFEFF7F3,
    // 遮罩与阴影
    UiKey.scrim: 0xFF010F08,
    UiKey.shadow: 0xFF082016,
    UiKey.backdropScrim: 0x66F4FCF8,
    // 占用条
    UiKey.chart1: 0xFF005D38,
    UiKey.chart2: 0xFF3F96E2,
    UiKey.chart3: 0xFF9A4485,
    UiKey.chart4: 0xFFCB8016,
  },
  code: const {
    CodeKey.bg: 0xFFEBF3EF,
    CodeKey.fg: 0xFF18251F,
    CodeKey.lineNumber: 0xFF7E8581,
    CodeKey.lineNumberActive: 0xFF18251F,
    CodeKey.currentLine: 0x80E2EAE6,
    CodeKey.selection: 0x42309564,
    CodeKey.cursor: 0xFF00794A,
    CodeKey.searchHit: 0x61C89F00,
    CodeKey.diffAddBg: 0xFFD1F2D7,
    CodeKey.diffAddFg: 0xFF005E28,
    CodeKey.diffDelBg: 0xFFFFE0DB,
    CodeKey.diffDelFg: 0xFF972622,
  },
  tokens: const {
    // 注释
    'comment': TokenStyle(color: 0xFF616F69, italic: true),
    'quote': TokenStyle(color: 0xFF616F69, italic: true),
    // 关键字
    'keyword': TokenStyle(color: 0xFF724AAB),
    'variable.language': TokenStyle(color: 0xFF724AAB, italic: true),
    'doctag': TokenStyle(color: 0xFF724AAB, italic: true),
    'computation-expression': TokenStyle(color: 0xFF724AAB),
    'template-tag': TokenStyle(color: 0xFF724AAB),
    // 字符串
    'string': TokenStyle(color: 0xFF21763C),
    'character': TokenStyle(color: 0xFF21763C),
    'code': TokenStyle(color: 0xFF21763C),
    // 转义 / 正则
    'regexp': TokenStyle(color: 0xFFA7391E),
    'regex': TokenStyle(color: 0xFFA7391E),
    'char.escape': TokenStyle(color: 0xFFA7391E),
    'selector-pseudo': TokenStyle(color: 0xFFA7391E),
    // 数字 / 字面量 / 符号
    'number': TokenStyle(color: 0xFF964D09),
    'literal': TokenStyle(color: 0xFF964D09),
    'variable.constant': TokenStyle(color: 0xFF964D09),
    'symbol': TokenStyle(color: 0xFF964D09),
    'label': TokenStyle(color: 0xFF964D09),
    'selector-id': TokenStyle(color: 0xFF964D09),
    'bullet': TokenStyle(color: 0xFF964D09),
    'formula': TokenStyle(color: 0xFF964D09),
    // 类型 / 类名
    'type': TokenStyle(color: 0xFF0068A5),
    'title.class': TokenStyle(color: 0xFF0068A5),
    'title.class.inherited': TokenStyle(color: 0xFF0068A5, italic: true),
    'selector-class': TokenStyle(color: 0xFF0068A5),
    // 内置的名字
    'built_in': TokenStyle(color: 0xFF983C75),
    // 函数名 / 定义处的名字
    'title': TokenStyle(color: 0xFF007176),
    'title.function': TokenStyle(color: 0xFF007176),
    'title.function.invoke': TokenStyle(color: 0xFF007176),
    'section': TokenStyle(color: 0xFF007176, bold: true),
    // 变量
    'variable': TokenStyle(color: 0xFF405D50),
    'template-variable': TokenStyle(color: 0xFF405D50),
    // 属性
    'property': TokenStyle(color: 0xFF687116),
    'attr': TokenStyle(color: 0xFF687116),
    'attribute': TokenStyle(color: 0xFF687116),
    'selector-attr': TokenStyle(color: 0xFF687116),
    // 标签名
    'name': TokenStyle(color: 0xFFA6344C),
    'selector-tag': TokenStyle(color: 0xFFA6344C),
    // 标点 / 运算符
    'operator': TokenStyle(color: 0xFF405249),
    'punctuation': TokenStyle(color: 0xFF405249),
    'tag': TokenStyle(color: 0xFF405249),
    // 元信息
    'meta': TokenStyle(color: 0xFF66672D),
    'meta.prompt': TokenStyle(color: 0xFF66672D),
    // 链接
    'link': TokenStyle(color: 0xFF006A9D),
    // 新增
    'addition': TokenStyle(color: 0xFF137738),
    // 删除
    'deletion': TokenStyle(color: 0xFFAC312C),
    'delete': TokenStyle(color: 0xFFAC312C),
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
    'fg': 0xFF18251F,
    'bg': 0xFFEBF3EF,
    'cursor': 0xFF00794A,
    'selection': 0x4C309564,
    'searchHitBg': 0xFFF0DE99,
    'searchHitBgCurrent': 0xFFF5AE39,
    'searchHitFg': 0xFF18251F,
    'black': 0xFF1D2A24,
    'red': 0xFFAB4048,
    'green': 0xFF007D41,
    'yellow': 0xFF915C00,
    'blue': 0xFF0070A8,
    'magenta': 0xFF894B9D,
    'cyan': 0xFF007973,
    'white': 0xFF79837E,
    'brightBlack': 0xFF606E67,
    'brightRed': 0xFF9B1B2F,
    'brightGreen': 0xFF006734,
    'brightYellow': 0xFF764A00,
    'brightBlue': 0xFF005B8A,
    'brightMagenta': 0xFF772F8F,
    'brightCyan': 0xFF00635D,
    'brightWhite': 0xFF525C57,
  },
  blocks: const {
    'event': 0xFFAF4D15, // 事件
    'variable': 0xFFBD2E67, // 变量
    'widget': 0xFF1371BF, // 控件
    'control': 0xFF6A52DA, // 流程
    'action': 0xFF137C8C, // 交互
    'network': 0xFF7B701B, // 网络
    'value': 0xFF5E7369, // 直接填的值
    'operator': 0xFF367D3C, // 运算
    'data': 0xFF9B3BB9, // 数据集合
    'request': 0xFF1E805C, // 请求
    'response': 0xFFC13237, // 返回
    'unknown': 0xFF6B6F6D, // 不认识的
    'function': 0xFF207E6D, // 函数
    'text': 0xFF8B690B, // 文字
    'list': 0xFF236DC8, // 列表
    'dict': 0xFF9C3CB6, // 字典
    'class': 0xFF607710, // 类
    'error': 0xFFBE3735, // 出错
    'async': 0xFF137B92, // 等待
    'custom': 0xFF5061D0, // 我的积木
    BlockKey.text: 0xFFFAFFFD,
    BlockKey.fieldBg: 0xFFFCFEFD,
    BlockKey.fieldText: 0xFF19251F,
    BlockKey.fieldHint: 0xFF78867F,
    BlockKey.gloss: 0xFFFFFFFF,
    BlockKey.shade: 0xFF000000,
    BlockKey.selection: 0xFFD355A4,
    BlockKey.ghost: 0x330D1914,
    BlockKey.shadow: 0x52082016,
    BlockKey.canvas: 0xFFEBF3EF,
    BlockKey.canvasDot: 0xFFCCD3D0,
    BlockKey.error: 0xFFDE3C37,
    BlockKey.warning: 0xFFB27800,
    BlockKey.onError: 0xFFFFFFFF,
    BlockKey.onWarning: 0xFF301D00,
  },
  lowcode: const {
    LowcodeKey.selection: 0xFF178454,
    LowcodeKey.selectionText: 0xFFFFFFFF,
    LowcodeKey.handleFill: 0xFFFFFFFF,
    LowcodeKey.marginRing: 0x59E79D00,
    LowcodeKey.paddingRing: 0x594BCB71,
    LowcodeKey.dropHoverBg: 0xFFBEEBCF,
    LowcodeKey.dropHoverBorder: 0xFF178454,
    LowcodeKey.dropIdleBg: 0x0F0D1914,
    LowcodeKey.dropIdleBorder: 0xFFB2B9B6,
    LowcodeKey.dropText: 0xFF646B67,
    LowcodeKey.insertBar: 0xFF178454,
    LowcodeKey.insertBarIdle: 0xFFABE0C0,
    LowcodeKey.dropOutline: 0xFFB2B9B6,
    LowcodeKey.dragChipBg: 0xFF005633,
    LowcodeKey.dragChipText: 0xFFFFFFFF,
    LowcodeKey.sizeTagBg: 0xCC1D2A24,
    LowcodeKey.sizeTagText: 0xFFFFFFFF,
    LowcodeKey.missingBg: 0xFFFEF0D4,
    LowcodeKey.missingBorder: 0xFFC38400,
    LowcodeKey.missingIcon: 0xFF865900,
    LowcodeKey.missingText: 0xFF694500,
  },
  metrics: const {MetricKey.radiusScale: 1.35, MetricKey.spaceScale: 1.05, MetricKey.fontScale: 1, MetricKey.shadowStrength: 0.9, MetricKey.dividerWidth: 1, MetricKey.surfaceOpacity: 0.86},
);
