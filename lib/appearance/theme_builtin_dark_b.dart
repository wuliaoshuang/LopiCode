/// 内置主题（深色）：纯黑、葡萄紫。
///
/// 颜色是自己配的（没有照搬任何现成配色方案）：在 OKLCH 里定色相和彩度，再把明度调到对比度达标
///（正文 ≥ 4.5:1，图标 / 色块 ≥ 3:1；test/theme_contrast_test.dart 和 test/theme_builtin_test.dart 守着）。
/// 这里写的就是最终的值，要改直接改数字，改完跑那两个测试。清单和思路见 docs/themes-design.md “内置主题清单”。
library;

import 'package:lopicode/appearance/theme_fields.dart';
import 'package:lopicode/appearance/theme_spec.dart';

/// 纯黑（`builtin-black`，深色）：纯黑的底（OLED 屏省电），中性灰阶，薄荷绿强调，紧凑。
///
/// 配色思路：页面、终端底色是真正的黑（#000000），卡片用深灰浮起来、不用阴影；灰阶不带色。强调色是薄荷绿，实心按钮是亮绿底配黑字。高亮在黑底上用得鲜一些（洋红关键字、青柠字符串、橙数字、青类型、蓝函数名）。间距收紧、圆角收小。
final ThemeSpec kBlackTheme = ThemeSpec(
  id: 'builtin-black',
  name: '纯黑',
  dark: true,
  builtin: true,
  ui: const {
    // 底色
    UiKey.bg: 0xFF000000,
    UiKey.canvas: 0xFF000000,
    UiKey.surface: 0xFF121314,
    UiKey.surfaceMuted: 0xFF212223,
    UiKey.codeBg: 0xFF0A0B0C,
    UiKey.cardBg: 0xFF121314,
    UiKey.inputBg: 0xFF121314,
    // 文字
    UiKey.text: 0xFFF3F5F8,
    UiKey.textMuted: 0xFFBCBEC0,
    UiKey.textFaint: 0xFF939598,
    UiKey.link: 0xFF52E9B2,
    // 线
    UiKey.border: 0xFF323334,
    // 强调
    UiKey.accent: 0xFF52E9B2,
    UiKey.accentSoft: 0xFF043726,
    UiKey.accentFill: 0xFF41DCA5,
    UiKey.onAccent: 0xFF11171D,
    UiKey.selectedBg: 0xFF043726,
    // 状态
    UiKey.danger: 0xFFFFA096,
    UiKey.dangerSoft: 0xFF3B1C19,
    UiKey.onDanger: 0xFF11171D,
    UiKey.warning: 0xFFF3AE58,
    UiKey.warningSoft: 0xFF362207,
    UiKey.success: 0xFF7CD591,
    UiKey.successSoft: 0xFF122D19,
    UiKey.info: 0xFF80C5FF,
    UiKey.infoSoft: 0xFF0E293D,
    UiKey.noticeBg: 0xFF3F1916,
    UiKey.noticeText: 0xFFFFBFB6,
    // 导航与顶栏
    UiKey.navBg: 0xFF000000,
    UiKey.navActive: 0xFFF3F5F8,
    UiKey.navInactive: 0xFF939598,
    UiKey.barButtonBg: 0xFF121314,
    // 聊天
    UiKey.bubbleMineBg: 0xFF043726,
    UiKey.bubbleMineText: 0xFFF3F5F8,
    UiKey.bubbleAgentBg: 0xFF212223,
    UiKey.bubbleAgentText: 0xFFF3F5F8,
    // 提示条
    UiKey.snackBg: 0xFFDCDEE1,
    UiKey.snackText: 0xFF151617,
    // 遮罩与阴影
    UiKey.scrim: 0xFF000000,
    UiKey.shadow: 0xFF000000,
    UiKey.backdropScrim: 0x80000000,
    // 占用条
    UiKey.chart1: 0xFF009E72,
    UiKey.chart2: 0xFFB3D4FF,
    UiKey.chart3: 0xFFB95A93,
    UiKey.chart4: 0xFFF2AF48,
  },
  code: const {
    CodeKey.bg: 0xFF0A0B0C,
    CodeKey.fg: 0xFFF3F5F8,
    CodeKey.lineNumber: 0xFF636566,
    CodeKey.lineNumberActive: 0xFFF3F5F8,
    CodeKey.currentLine: 0x80212223,
    CodeKey.selection: 0x420BC18D,
    CodeKey.cursor: 0xFF52E9B2,
    CodeKey.searchHit: 0x61F0BB3B,
    CodeKey.diffAddBg: 0xFF0C2E16,
    CodeKey.diffAddFg: 0xFF8FE1A1,
    CodeKey.diffDelBg: 0xFF3F1916,
    CodeKey.diffDelFg: 0xFFFFABA1,
  },
  tokens: const {
    // 注释
    'comment': TokenStyle(color: 0xFF757B82, italic: true),
    'quote': TokenStyle(color: 0xFF757B82, italic: true),
    // 关键字
    'keyword': TokenStyle(color: 0xFFFC8DE5),
    'variable.language': TokenStyle(color: 0xFFFC8DE5, italic: true),
    'doctag': TokenStyle(color: 0xFFFC8DE5, italic: true),
    'computation-expression': TokenStyle(color: 0xFFFC8DE5),
    'template-tag': TokenStyle(color: 0xFFFC8DE5),
    // 字符串
    'string': TokenStyle(color: 0xFF89D25B),
    'character': TokenStyle(color: 0xFF89D25B),
    'code': TokenStyle(color: 0xFF89D25B),
    // 转义 / 正则
    'regexp': TokenStyle(color: 0xFFC7A8FF),
    'regex': TokenStyle(color: 0xFFC7A8FF),
    'char.escape': TokenStyle(color: 0xFFC7A8FF),
    'selector-pseudo': TokenStyle(color: 0xFFC7A8FF),
    // 数字 / 字面量 / 符号
    'number': TokenStyle(color: 0xFFFFA14C),
    'literal': TokenStyle(color: 0xFFFFA14C),
    'variable.constant': TokenStyle(color: 0xFFFFA14C),
    'symbol': TokenStyle(color: 0xFFFFA14C),
    'label': TokenStyle(color: 0xFFFFA14C),
    'selector-id': TokenStyle(color: 0xFFFFA14C),
    'bullet': TokenStyle(color: 0xFFFFA14C),
    'formula': TokenStyle(color: 0xFFFFA14C),
    // 类型 / 类名
    'type': TokenStyle(color: 0xFF3FD1D9),
    'title.class': TokenStyle(color: 0xFF3FD1D9),
    'title.class.inherited': TokenStyle(color: 0xFF3FD1D9, italic: true),
    'selector-class': TokenStyle(color: 0xFF3FD1D9),
    // 内置的名字
    'built_in': TokenStyle(color: 0xFFD0BC42),
    // 函数名 / 定义处的名字
    'title': TokenStyle(color: 0xFF8BBEFF),
    'title.function': TokenStyle(color: 0xFF8BBEFF),
    'title.function.invoke': TokenStyle(color: 0xFF8BBEFF),
    'section': TokenStyle(color: 0xFF8BBEFF, bold: true),
    // 变量
    'variable': TokenStyle(color: 0xFFD1DCE8),
    'template-variable': TokenStyle(color: 0xFFD1DCE8),
    // 属性
    'property': TokenStyle(color: 0xFF5FD2BA),
    'attr': TokenStyle(color: 0xFF5FD2BA),
    'attribute': TokenStyle(color: 0xFF5FD2BA),
    'selector-attr': TokenStyle(color: 0xFF5FD2BA),
    // 标签名
    'name': TokenStyle(color: 0xFFFF9A97),
    'selector-tag': TokenStyle(color: 0xFFFF9A97),
    // 标点 / 运算符
    'operator': TokenStyle(color: 0xFFB9BEC3),
    'punctuation': TokenStyle(color: 0xFFB9BEC3),
    'tag': TokenStyle(color: 0xFFB9BEC3),
    // 元信息
    'meta': TokenStyle(color: 0xFF989DCD),
    'meta.prompt': TokenStyle(color: 0xFF989DCD),
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
    'fg': 0xFFF3F5F8,
    'bg': 0xFF000000,
    'cursor': 0xFF52E9B2,
    'selection': 0x4C0BC18D,
    'searchHitBg': 0xFF4B3B05,
    'searchHitBgCurrent': 0xFF81520A,
    'searchHitFg': 0xFFF3F5F8,
    'black': 0xFF5A6167,
    'red': 0xFFFF958D,
    'green': 0xFF75D166,
    'yellow': 0xFFD5B600,
    'blue': 0xFF8CB9FF,
    'magenta': 0xFFF28CEC,
    'cyan': 0xFF00D1D3,
    'white': 0xFFD4D8DD,
    'brightBlack': 0xFF727980,
    'brightRed': 0xFFFFBEB8,
    'brightGreen': 0xFF9AE98E,
    'brightYellow': 0xFFECD154,
    'brightBlue': 0xFFB6D3FF,
    'brightMagenta': 0xFFFFB3FA,
    'brightCyan': 0xFF16EEF0,
    'brightWhite': 0xFFF9FAFB,
  },
  blocks: const {
    'event': 0xFFA84800, // 事件
    'variable': 0xFFB9205D, // 变量
    'widget': 0xFF0D6ABB, // 控件
    'control': 0xFF684AD3, // 流程
    'action': 0xFF007688, // 交互
    'network': 0xFF746B0C, // 网络
    'value': 0xFF5F6A7B, // 直接填的值
    'operator': 0xFF2C7C3B, // 运算
    'data': 0xFF9733AF, // 数据集合
    'request': 0xFF017C59, // 请求
    'response': 0xFFBC2629, // 返回
    'unknown': 0xFF707376, // 不认识的
    'function': 0xFF0C7A6B, // 函数
    'text': 0xFF836400, // 文字
    'list': 0xFF2165C5, // 列表
    'dict': 0xFF9832AE, // 字典
    'class': 0xFF597506, // 类
    'error': 0xFFB92D28, // 出错
    'async': 0xFF00758F, // 等待
    'custom': 0xFF4E59CB, // 我的积木
    BlockKey.text: 0xFFFFFFFF,
    BlockKey.fieldBg: 0xFFD8DFE6,
    BlockKey.fieldText: 0xFF1A222B,
    BlockKey.fieldHint: 0xFF66707A,
    BlockKey.gloss: 0xFFFFFFFF,
    BlockKey.shade: 0xFF000000,
    BlockKey.selection: 0xFFF9D100,
    BlockKey.ghost: 0x38FAFCFE,
    BlockKey.shadow: 0x8A000000,
    BlockKey.canvas: 0xFF000000,
    BlockKey.canvasDot: 0xFF232425,
    BlockKey.error: 0xFFFF7266,
    BlockKey.warning: 0xFFFFBD58,
    BlockKey.onError: 0xFF250E0C,
    BlockKey.onWarning: 0xFF301D00,
  },
  lowcode: const {
    LowcodeKey.selection: 0xFF00845F,
    LowcodeKey.selectionText: 0xFFFFFFFF,
    LowcodeKey.handleFill: 0xFFFFFFFF,
    LowcodeKey.marginRing: 0x59ED990E,
    LowcodeKey.paddingRing: 0x594BCB71,
    LowcodeKey.dropHoverBg: 0xFFBAEBD4,
    LowcodeKey.dropHoverBorder: 0xFF00845F,
    LowcodeKey.dropIdleBg: 0x0F0F171F,
    LowcodeKey.dropIdleBorder: 0xFFB4B8BC,
    LowcodeKey.dropText: 0xFF65696F,
    LowcodeKey.insertBar: 0xFF00845F,
    LowcodeKey.insertBarIdle: 0xFFA6E0C6,
    LowcodeKey.dropOutline: 0xFFB4B8BC,
    LowcodeKey.dragChipBg: 0xFF00563C,
    LowcodeKey.dragChipText: 0xFFFFFFFF,
    LowcodeKey.sizeTagBg: 0xCC22272D,
    LowcodeKey.sizeTagText: 0xFFFFFFFF,
    LowcodeKey.missingBg: 0xFFFFF0D7,
    LowcodeKey.missingBorder: 0xFFCA8100,
    LowcodeKey.missingIcon: 0xFF8A5600,
    LowcodeKey.missingText: 0xFF6C4300,
  },
  metrics: const {MetricKey.radiusScale: 0.75, MetricKey.spaceScale: 0.92, MetricKey.fontScale: 1, MetricKey.shadowStrength: 0, MetricKey.dividerWidth: 1, MetricKey.surfaceOpacity: 0.8},
);

/// 葡萄紫（`builtin-grape`，深色）：带紫的深色底配兰花粉，柔和、有点梦幻。
///
/// 配色思路：灰阶明显带紫（色相 305°）；强调色是兰花粉紫，我的气泡是实心的。高亮：粉关键字、薄荷字符串、金色数字、淡紫类型、天蓝函数名、蜜桃色内置名——都是偏粉彩的亮色。圆角偏大。
final ThemeSpec kGrapeTheme = ThemeSpec(
  id: 'builtin-grape',
  name: '葡萄紫',
  dark: true,
  builtin: true,
  ui: const {
    // 底色
    UiKey.bg: 0xFF1C1425,
    UiKey.canvas: 0xFF140C1D,
    UiKey.surface: 0xFF271E30,
    UiKey.surfaceMuted: 0xFF342C3F,
    UiKey.codeBg: 0xFF170F20,
    UiKey.cardBg: 0xFF271E30,
    UiKey.inputBg: 0xFF271E30,
    // 文字
    UiKey.text: 0xFFF1EBFA,
    UiKey.textMuted: 0xFFC0BBC8,
    UiKey.textFaint: 0xFF9C97A4,
    UiKey.link: 0xFFE9A8F8,
    // 线
    UiKey.border: 0xFF473E52,
    // 强调
    UiKey.accent: 0xFFE9A8F8,
    UiKey.accentSoft: 0xFF47264F,
    UiKey.accentFill: 0xFF9558A3,
    UiKey.onAccent: 0xFFFCFBFE,
    UiKey.selectedBg: 0xFF47264F,
    // 状态
    UiKey.danger: 0xFFFF9F9F,
    UiKey.dangerSoft: 0xFF3B1C1C,
    UiKey.onDanger: 0xFF191221,
    UiKey.warning: 0xFFF3AE58,
    UiKey.warningSoft: 0xFF362207,
    UiKey.success: 0xFF7CD591,
    UiKey.successSoft: 0xFF122D19,
    UiKey.info: 0xFF76C7FF,
    UiKey.infoSoft: 0xFF0B293C,
    UiKey.noticeBg: 0xFF3F191A,
    UiKey.noticeText: 0xFFFFBEBD,
    // 导航与顶栏
    UiKey.navBg: 0xFF1C1425,
    UiKey.navActive: 0xFFE9A8F8,
    UiKey.navInactive: 0xFF9C97A4,
    UiKey.barButtonBg: 0xFF271E30,
    // 聊天
    UiKey.bubbleMineBg: 0xFF9558A3,
    UiKey.bubbleMineText: 0xFFFCFBFE,
    UiKey.bubbleAgentBg: 0xFF342C3F,
    UiKey.bubbleAgentText: 0xFFF1EBFA,
    // 提示条
    UiKey.snackBg: 0xFFE2D9EE,
    UiKey.snackText: 0xFF1A1223,
    // 遮罩与阴影
    UiKey.scrim: 0xFF000000,
    UiKey.shadow: 0xFF000000,
    UiKey.backdropScrim: 0x661C1425,
    // 占用条
    UiKey.chart1: 0xFFAB68BA,
    UiKey.chart2: 0xFFFFC1A0,
    UiKey.chart3: 0xFF4E943E,
    UiKey.chart4: 0xFF58CCFF,
  },
  code: const {
    CodeKey.bg: 0xFF170F20,
    CodeKey.fg: 0xFFF1EBF9,
    CodeKey.lineNumber: 0xFF6D647A,
    CodeKey.lineNumberActive: 0xFFF1EBFA,
    CodeKey.currentLine: 0x80342C3F,
    CodeKey.selection: 0x42C889D7,
    CodeKey.cursor: 0xFFE9A8F8,
    CodeKey.searchHit: 0x61F0BB3B,
    CodeKey.diffAddBg: 0xFF0C2E16,
    CodeKey.diffAddFg: 0xFF8FE1A1,
    CodeKey.diffDelBg: 0xFF3F191A,
    CodeKey.diffDelFg: 0xFFFFAAA9,
  },
  tokens: const {
    // 注释
    'comment': TokenStyle(color: 0xFF867A96, italic: true),
    'quote': TokenStyle(color: 0xFF867A96, italic: true),
    // 关键字
    'keyword': TokenStyle(color: 0xFFFD93C7),
    'variable.language': TokenStyle(color: 0xFFFD93C7, italic: true),
    'doctag': TokenStyle(color: 0xFFFD93C7, italic: true),
    'computation-expression': TokenStyle(color: 0xFFFD93C7),
    'template-tag': TokenStyle(color: 0xFFFD93C7),
    // 字符串
    'string': TokenStyle(color: 0xFF6ED2A0),
    'character': TokenStyle(color: 0xFF6ED2A0),
    'code': TokenStyle(color: 0xFF6ED2A0),
    // 转义 / 正则
    'regexp': TokenStyle(color: 0xFFFF9E7C),
    'regex': TokenStyle(color: 0xFFFF9E7C),
    'char.escape': TokenStyle(color: 0xFFFF9E7C),
    'selector-pseudo': TokenStyle(color: 0xFFFF9E7C),
    // 数字 / 字面量 / 符号
    'number': TokenStyle(color: 0xFFDBB658),
    'literal': TokenStyle(color: 0xFFDBB658),
    'variable.constant': TokenStyle(color: 0xFFDBB658),
    'symbol': TokenStyle(color: 0xFFDBB658),
    'label': TokenStyle(color: 0xFFDBB658),
    'selector-id': TokenStyle(color: 0xFFDBB658),
    'bullet': TokenStyle(color: 0xFFDBB658),
    'formula': TokenStyle(color: 0xFFDBB658),
    // 类型 / 类名
    'type': TokenStyle(color: 0xFFBFACFA),
    'title.class': TokenStyle(color: 0xFFBFACFA),
    'title.class.inherited': TokenStyle(color: 0xFFBFACFA, italic: true),
    'selector-class': TokenStyle(color: 0xFFBFACFA),
    // 内置的名字
    'built_in': TokenStyle(color: 0xFFF9A275),
    // 函数名 / 定义处的名字
    'title': TokenStyle(color: 0xFF6EC6F7),
    'title.function': TokenStyle(color: 0xFF6EC6F7),
    'title.function.invoke': TokenStyle(color: 0xFF6EC6F7),
    'section': TokenStyle(color: 0xFF6EC6F7, bold: true),
    // 变量
    'variable': TokenStyle(color: 0xFFDBC8EA),
    'template-variable': TokenStyle(color: 0xFFDBC8EA),
    // 属性
    'property': TokenStyle(color: 0xFF62CFCE),
    'attr': TokenStyle(color: 0xFF62CFCE),
    'attribute': TokenStyle(color: 0xFF62CFCE),
    'selector-attr': TokenStyle(color: 0xFF62CFCE),
    // 标签名
    'name': TokenStyle(color: 0xFFFD93C7),
    'selector-tag': TokenStyle(color: 0xFFFD93C7),
    // 标点 / 运算符
    'operator': TokenStyle(color: 0xFFC1BACB),
    'punctuation': TokenStyle(color: 0xFFC1BACB),
    'tag': TokenStyle(color: 0xFFC1BACB),
    // 元信息
    'meta': TokenStyle(color: 0xFFAA9DC5),
    'meta.prompt': TokenStyle(color: 0xFFAA9DC5),
    // 链接
    'link': TokenStyle(color: 0xFF6DC4FF),
    // 新增
    'addition': TokenStyle(color: 0xFF79D28D),
    // 删除
    'deletion': TokenStyle(color: 0xFFFF9A9A),
    'delete': TokenStyle(color: 0xFFFF9A9A),
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
    'fg': 0xFFF1EBF9,
    'bg': 0xFF170F20,
    'cursor': 0xFFE9A8F8,
    'selection': 0x4CC889D7,
    'searchHitBg': 0xFF4B3B05,
    'searchHitBgCurrent': 0xFF81520A,
    'searchHitFg': 0xFFF1EBF9,
    'black': 0xFF6F637E,
    'red': 0xFFFE93A6,
    'green': 0xFF67D096,
    'yellow': 0xFFDBB149,
    'blue': 0xFF95B6FF,
    'magenta': 0xFFDD9BEA,
    'cyan': 0xFF18D0D5,
    'white': 0xFFDDD1ED,
    'brightBlack': 0xFF887B98,
    'brightRed': 0xFFFFBCC6,
    'brightGreen': 0xFF91E7B4,
    'brightYellow': 0xFFF0CD79,
    'brightBlue': 0xFFBBD1FF,
    'brightMagenta': 0xFFF2B9FD,
    'brightCyan': 0xFF6BE7EB,
    'brightWhite': 0xFFFBF9FF,
  },
  blocks: const {
    'event': 0xFF8D4400, // 事件
    'variable': 0xFFA41744, // 变量
    'widget': 0xFF2259A6, // 控件
    'control': 0xFF6439B7, // 流程
    'action': 0xFF00667B, // 交互
    'network': 0xFF5F5F0C, // 网络
    'value': 0xFF5F5769, // 直接填的值
    'operator': 0xFF0F6D3A, // 运算
    'data': 0xFF8C2193, // 数据集合
    'request': 0xFF006B54, // 请求
    'response': 0xFFA52109, // 返回
    'unknown': 0xFF656467, // 不认识的
    'function': 0xFF006962, // 函数
    'text': 0xFF6D5900, // 文字
    'list': 0xFF2D54AE, // 列表
    'dict': 0xFF8C2491, // 字典
    'class': 0xFF436713, // 类
    'error': 0xFFA22709, // 出错
    'async': 0xFF076480, // 等待
    'custom': 0xFF4E49B1, // 我的积木
    BlockKey.text: 0xFFF7F3FC,
    BlockKey.fieldBg: 0xFFE0DCE5,
    BlockKey.fieldText: 0xFF241F29,
    BlockKey.fieldHint: 0xFF716C78,
    BlockKey.gloss: 0xFFFFFFFF,
    BlockKey.shade: 0xFF000000,
    BlockKey.selection: 0xFFFDCE3E,
    BlockKey.ghost: 0x38FCFBFE,
    BlockKey.shadow: 0x8A000000,
    BlockKey.canvas: 0xFF1C1425,
    BlockKey.canvasDot: 0xFF342C3F,
    BlockKey.error: 0xFFFF7266,
    BlockKey.warning: 0xFFFFBD58,
    BlockKey.onError: 0xFF250E0C,
    BlockKey.onWarning: 0xFF301D00,
  },
  lowcode: const {
    LowcodeKey.selection: 0xFF995CA7,
    LowcodeKey.selectionText: 0xFFFFFFFF,
    LowcodeKey.handleFill: 0xFFFFFFFF,
    LowcodeKey.marginRing: 0x59ED990E,
    LowcodeKey.paddingRing: 0x594BCB71,
    LowcodeKey.dropHoverBg: 0xFFF0D2F7,
    LowcodeKey.dropHoverBorder: 0xFF995CA7,
    LowcodeKey.dropIdleBg: 0x0F18141D,
    LowcodeKey.dropIdleBorder: 0xFFBCB2CA,
    LowcodeKey.dropText: 0xFF6D647A,
    LowcodeKey.insertBar: 0xFF995CA7,
    LowcodeKey.insertBarIdle: 0xFFE6C3EE,
    LowcodeKey.dropOutline: 0xFFBCB2CA,
    LowcodeKey.dragChipBg: 0xFF652A72,
    LowcodeKey.dragChipText: 0xFFFFFFFF,
    LowcodeKey.sizeTagBg: 0xCC2A2332,
    LowcodeKey.sizeTagText: 0xFFFFFFFF,
    LowcodeKey.missingBg: 0xFFFFF0D7,
    LowcodeKey.missingBorder: 0xFFCA8100,
    LowcodeKey.missingIcon: 0xFF8A5600,
    LowcodeKey.missingText: 0xFF6C4300,
  },
  metrics: const {MetricKey.radiusScale: 1.25, MetricKey.spaceScale: 1, MetricKey.fontScale: 1, MetricKey.shadowStrength: 1.1, MetricKey.dividerWidth: 1, MetricKey.surfaceOpacity: 0.84},
);
