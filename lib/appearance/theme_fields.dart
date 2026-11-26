/// 一份主题里有哪些字段：键名、给人看的叫法、分在哪一组。
///
/// 主题的数据是“一节一张表”（键 → 颜色 / 数值），这里是这些表的目录。主题编辑器照着这份目录画界面，
/// 读写文件、补默认值、对比度检查也都照它来，所以加字段只改这里一处（再给两套默认主题补上值）。
/// 纯 Dart，不依赖界面库。
library;

/// 一个颜色字段。
class ThemeField {
  const ThemeField(this.key, this.label, {this.group = '', this.note = ''});
  final String key;

  /// 给人看的名字。
  final String label;

  /// 编辑器里分组用的小标题。
  final String group;

  /// 用在哪里（一句话）。
  final String note;
}

/// 一个数值字段（形状与密度）。
class ThemeMetricField {
  const ThemeMetricField(this.key, this.label, {required this.min, required this.max, required this.fallback, this.note = ''});
  final String key;
  final String label;
  final double min;
  final double max;

  /// 文件里没有、两套默认主题里也没有时用的值。
  final double fallback;
  final String note;
}

/// 界面色的键。前 17 个就是原来 AppColors 的 17 项，名字没改。
abstract final class UiKey {
  static const bg = 'bg';
  static const canvas = 'canvas';
  static const surface = 'surface';
  static const surfaceMuted = 'surfaceMuted';
  static const text = 'text';
  static const textMuted = 'textMuted';
  static const textFaint = 'textFaint';
  static const border = 'border';
  static const accent = 'accent';
  static const accentSoft = 'accentSoft';
  static const accentFill = 'accentFill';
  static const onAccent = 'onAccent';
  static const danger = 'danger';
  static const dangerSoft = 'dangerSoft';
  static const warning = 'warning';
  static const warningSoft = 'warningSoft';
  static const codeBg = 'codeBg';
  // 下面是这次补的
  static const onDanger = 'onDanger';
  static const success = 'success';
  static const successSoft = 'successSoft';
  static const info = 'info';
  static const infoSoft = 'infoSoft';
  static const link = 'link';
  static const selectedBg = 'selectedBg';
  static const navBg = 'navBg';
  static const navActive = 'navActive';
  static const navInactive = 'navInactive';
  static const barButtonBg = 'barButtonBg';
  static const bubbleMineBg = 'bubbleMineBg';
  static const bubbleMineText = 'bubbleMineText';
  static const bubbleAgentBg = 'bubbleAgentBg';
  static const bubbleAgentText = 'bubbleAgentText';
  static const cardBg = 'cardBg';
  static const inputBg = 'inputBg';
  static const snackBg = 'snackBg';
  static const snackText = 'snackText';
  static const noticeBg = 'noticeBg';
  static const noticeText = 'noticeText';
  static const scrim = 'scrim';
  static const shadow = 'shadow';
  static const chart1 = 'chart1';
  static const chart2 = 'chart2';
  static const chart3 = 'chart3';
  static const chart4 = 'chart4';
  static const backdropScrim = 'backdropScrim';
}

const List<ThemeField> kUiFields = [
  ThemeField(UiKey.bg, '主页面底色', group: '底色', note: '对话、文件、终端这些主页面'),
  ThemeField(UiKey.canvas, '分组页面底色', group: '底色', note: '设置这类“卡片分组”页面，上面放卡片'),
  ThemeField(UiKey.surface, '卡片 / 面板', group: '底色', note: '卡片、底部面板、对话框、菜单'),
  ThemeField(UiKey.surfaceMuted, '浅灰块', group: '底色', note: '胶囊、标签、次要按钮的底'),
  ThemeField(UiKey.codeBg, '代码块 / 日志底色', group: '底色', note: '聊天里的代码块、日志、步骤详情'),
  ThemeField(UiKey.cardBg, '确认卡 / 步骤卡底色', group: '底色', note: '聊天里浮在消息上的确认卡、提问卡'),
  ThemeField(UiKey.inputBg, '输入框底色', group: '底色', note: '表单输入框和聊天输入框'),
  ThemeField(UiKey.text, '正文', group: '文字'),
  ThemeField(UiKey.textMuted, '次要文字', group: '文字'),
  ThemeField(UiKey.textFaint, '提示文字', group: '文字', note: '占位字、时间、行号这类最淡的字'),
  ThemeField(UiKey.link, '链接', group: '文字', note: '预留：现在界面里没有单独的链接样式'),
  ThemeField(UiKey.border, '边线 / 分隔线', group: '线'),
  ThemeField(UiKey.accent, '强调色（文字、图标）', group: '强调'),
  ThemeField(UiKey.accentSoft, '强调色浅底', group: '强调', note: '标签、分段按钮选中态'),
  ThemeField(UiKey.accentFill, '实心按钮底', group: '强调'),
  ThemeField(UiKey.onAccent, '实心按钮上的字', group: '强调'),
  ThemeField(UiKey.selectedBg, '选中项的底', group: '强调', note: '侧边栏里当前这一项'),
  ThemeField(UiKey.danger, '危险（文字、图标）', group: '状态'),
  ThemeField(UiKey.dangerSoft, '危险浅底', group: '状态'),
  ThemeField(UiKey.onDanger, '实心危险按钮上的字', group: '状态'),
  ThemeField(UiKey.warning, '警告（文字、图标）', group: '状态'),
  ThemeField(UiKey.warningSoft, '警告浅底', group: '状态'),
  ThemeField(UiKey.success, '成功（文字、图标）', group: '状态', note: '预留：现在只有改动对比里用绿色，那一组在“代码”里'),
  ThemeField(UiKey.successSoft, '成功浅底', group: '状态', note: '预留'),
  ThemeField(UiKey.info, '提示信息（文字、图标）', group: '状态', note: '预留'),
  ThemeField(UiKey.infoSoft, '提示信息浅底', group: '状态', note: '预留'),
  ThemeField(UiKey.noticeBg, '出错提示条底色', group: '状态', note: '页面顶上“出错了”的提示条、坏掉的那一块'),
  ThemeField(UiKey.noticeText, '出错提示条文字', group: '状态'),
  ThemeField(UiKey.navBg, '底部导航底色', group: '导航与顶栏'),
  ThemeField(UiKey.navActive, '底部导航选中', group: '导航与顶栏'),
  ThemeField(UiKey.navInactive, '底部导航未选中', group: '导航与顶栏'),
  ThemeField(UiKey.barButtonBg, '顶栏按钮底色', group: '导航与顶栏', note: '顶栏没有底色，只有悬浮的圆按钮和胶囊'),
  ThemeField(UiKey.bubbleMineBg, '我的气泡底色', group: '聊天'),
  ThemeField(UiKey.bubbleMineText, '我的气泡文字', group: '聊天'),
  ThemeField(UiKey.bubbleAgentBg, 'Agent 气泡底色', group: '聊天'),
  ThemeField(UiKey.bubbleAgentText, 'Agent 气泡文字', group: '聊天'),
  ThemeField(UiKey.snackBg, '底部提示条底色', group: '提示条'),
  ThemeField(UiKey.snackText, '底部提示条文字', group: '提示条'),
  ThemeField(UiKey.scrim, '遮罩', group: '遮罩与阴影', note: '侧边栏、弹层后面压暗用；只取色相，深浅由各处自己定'),
  ThemeField(UiKey.shadow, '阴影', group: '遮罩与阴影', note: '只取色相，深浅由各处自己定，再乘上“阴影强弱”'),
  ThemeField(UiKey.backdropScrim, '背景图上的遮罩', group: '遮罩与阴影', note: '有背景图时盖在图上、内容下面的一层（带透明度）'),
  ThemeField(UiKey.chart1, '占用条：系统提示词', group: '图表'),
  ThemeField(UiKey.chart2, '占用条：工具定义', group: '图表'),
  ThemeField(UiKey.chart3, '占用条：对话消息', group: '图表'),
  ThemeField(UiKey.chart4, '占用条：工具结果', group: '图表'),
];

/// 代码区域（编辑器、看代码、改动对比）的键。
abstract final class CodeKey {
  static const bg = 'bg';
  static const fg = 'fg';
  static const lineNumber = 'lineNumber';
  static const lineNumberActive = 'lineNumberActive';
  static const currentLine = 'currentLine';
  static const selection = 'selection';
  static const cursor = 'cursor';
  static const searchHit = 'searchHit';
  static const diffAddBg = 'diffAddBg';
  static const diffAddFg = 'diffAddFg';
  static const diffDelBg = 'diffDelBg';
  static const diffDelFg = 'diffDelFg';
}

const List<ThemeField> kCodeFields = [
  ThemeField(CodeKey.bg, '代码底色', group: '编辑器'),
  ThemeField(CodeKey.fg, '代码文字', group: '编辑器', note: '没有单独上色的字'),
  ThemeField(CodeKey.lineNumber, '行号', group: '编辑器'),
  ThemeField(CodeKey.lineNumberActive, '当前行的行号', group: '编辑器'),
  ThemeField(CodeKey.currentLine, '当前行底色', group: '编辑器', note: '带透明度'),
  ThemeField(CodeKey.selection, '选区', group: '编辑器', note: '带透明度'),
  ThemeField(CodeKey.cursor, '光标', group: '编辑器'),
  ThemeField(CodeKey.searchHit, '查找命中', group: '编辑器', note: '带透明度'),
  ThemeField(CodeKey.diffAddBg, '新增行底色', group: '改动对比'),
  ThemeField(CodeKey.diffAddFg, '新增行文字', group: '改动对比'),
  ThemeField(CodeKey.diffDelBg, '删除行底色', group: '改动对比'),
  ThemeField(CodeKey.diffDelFg, '删除行文字', group: '改动对比'),
];

/// 代码高亮的分类（就是高亮规则给每段代码打的标签）。来历见 docs/themes-design.md 的“高亮分类”一节：
/// 把现在登记的全部语言的规则走了一遍，凡是出现过的标签都在这里。
const List<ThemeField> kTokenFields = [
  ThemeField('comment', '注释', group: '常用'),
  ThemeField('keyword', '关键字', group: '常用'),
  ThemeField('string', '字符串', group: '常用'),
  ThemeField('number', '数字', group: '常用'),
  ThemeField('literal', '字面量（true / null…）', group: '常用'),
  ThemeField('type', '类型', group: '常用'),
  ThemeField('built_in', '内置的名字', group: '常用'),
  ThemeField('title', '名字（定义处）', group: '常用'),
  ThemeField('title.function', '函数名', group: '常用'),
  ThemeField('title.function.invoke', '调用的函数名', group: '常用'),
  ThemeField('title.class', '类名', group: '常用'),
  ThemeField('title.class.inherited', '父类名', group: '常用'),
  ThemeField('function', '函数（整段）', group: '常用'),
  ThemeField('function.dispatch', '函数调用（整段）', group: '常用'),
  ThemeField('class', '类（整段）', group: '常用'),
  ThemeField('params', '参数', group: '常用'),
  ThemeField('variable', '变量', group: '常用'),
  ThemeField('variable.constant', '常量', group: '常用'),
  ThemeField('variable.language', '语言自带的变量（this / self）', group: '常用'),
  ThemeField('property', '属性名', group: '常用'),
  ThemeField('operator', '运算符', group: '常用'),
  ThemeField('punctuation', '标点', group: '常用'),
  ThemeField('regexp', '正则', group: '常用'),
  ThemeField('regex', '正则（另一种标签）', group: '常用'),
  ThemeField('char.escape', '转义字符', group: '常用'),
  ThemeField('character', '单个字符', group: '常用'),
  ThemeField('subst', '字符串里的插值', group: '常用'),
  ThemeField('symbol', '符号', group: '常用'),
  ThemeField('label', '标号', group: '常用'),
  ThemeField('meta', '元信息（注解、预处理）', group: '常用'),
  ThemeField('meta.prompt', '命令提示符', group: '常用'),
  ThemeField('doctag', '文档标记（@param）', group: '常用'),
  ThemeField('computation-expression', '计算表达式（F#）', group: '常用'),
  ThemeField('tag', '标签（整段）', group: '网页'),
  ThemeField('name', '标签名', group: '网页'),
  ThemeField('attr', '属性', group: '网页'),
  ThemeField('attribute', '属性名（CSS、配置）', group: '网页'),
  ThemeField('selector-tag', '选择器：标签', group: '网页'),
  ThemeField('selector-id', '选择器：#id', group: '网页'),
  ThemeField('selector-class', '选择器：.class', group: '网页'),
  ThemeField('selector-attr', '选择器：[属性]', group: '网页'),
  ThemeField('selector-pseudo', '选择器：伪类', group: '网页'),
  ThemeField('template-tag', '模板标签', group: '网页'),
  ThemeField('template-variable', '模板变量', group: '网页'),
  ThemeField('section', '标题', group: '文档'),
  ThemeField('bullet', '列表符号', group: '文档'),
  ThemeField('quote', '引用', group: '文档'),
  ThemeField('code', '行内代码', group: '文档'),
  ThemeField('link', '链接', group: '文档'),
  ThemeField('emphasis', '强调（斜体）', group: '文档'),
  ThemeField('strong', '加粗', group: '文档'),
  ThemeField('formula', '公式', group: '文档'),
  ThemeField('addition', '新增（diff）', group: '改动'),
  ThemeField('deletion', '删除（diff）', group: '改动'),
  ThemeField('delete', '删除（另一种标签）', group: '改动'),
];

/// 终端的键。
const List<ThemeField> kTerminalFields = [
  ThemeField('fg', '文字', group: '基本'),
  ThemeField('bg', '底色', group: '基本'),
  ThemeField('cursor', '光标', group: '基本'),
  ThemeField('selection', '选区', group: '基本', note: '带透明度'),
  ThemeField('searchHitBg', '查找命中底色', group: '基本'),
  ThemeField('searchHitBgCurrent', '当前命中底色', group: '基本'),
  ThemeField('searchHitFg', '查找命中文字', group: '基本'),
  ThemeField('black', '黑', group: '8 色'),
  ThemeField('red', '红', group: '8 色'),
  ThemeField('green', '绿', group: '8 色'),
  ThemeField('yellow', '黄', group: '8 色'),
  ThemeField('blue', '蓝', group: '8 色'),
  ThemeField('magenta', '品红', group: '8 色'),
  ThemeField('cyan', '青', group: '8 色'),
  ThemeField('white', '白', group: '8 色'),
  ThemeField('brightBlack', '亮黑', group: '亮 8 色'),
  ThemeField('brightRed', '亮红', group: '亮 8 色'),
  ThemeField('brightGreen', '亮绿', group: '亮 8 色'),
  ThemeField('brightYellow', '亮黄', group: '亮 8 色'),
  ThemeField('brightBlue', '亮蓝', group: '亮 8 色'),
  ThemeField('brightMagenta', '亮品红', group: '亮 8 色'),
  ThemeField('brightCyan', '亮青', group: '亮 8 色'),
  ThemeField('brightWhite', '亮白', group: '亮 8 色'),
];

/// 积木每一类的主色的键（和 lib/blocks/block_host.dart 的 BlockColorKey 一一对应，有测试守着）。
const List<ThemeField> kBlockCategoryFields = [
  ThemeField('event', '事件', group: '分类主色'),
  ThemeField('variable', '变量', group: '分类主色'),
  ThemeField('widget', '控件', group: '分类主色'),
  ThemeField('control', '流程', group: '分类主色'),
  ThemeField('action', '交互', group: '分类主色'),
  ThemeField('network', '网络', group: '分类主色'),
  ThemeField('value', '直接填的值', group: '分类主色'),
  ThemeField('operator', '运算', group: '分类主色'),
  ThemeField('data', '数据集合', group: '分类主色'),
  ThemeField('request', '请求', group: '分类主色'),
  ThemeField('response', '返回', group: '分类主色'),
  ThemeField('unknown', '不认识的', group: '分类主色'),
  ThemeField('function', '函数', group: '分类主色'),
  ThemeField('text', '文字', group: '分类主色'),
  ThemeField('list', '列表', group: '分类主色'),
  ThemeField('dict', '字典', group: '分类主色'),
  ThemeField('class', '类', group: '分类主色'),
  ThemeField('error', '出错', group: '分类主色'),
  ThemeField('async', '等待', group: '分类主色'),
  ThemeField('custom', '我的积木', group: '分类主色'),
];

/// 积木里不属于某一类的颜色。键名前面带 `_`，免得和分类名撞上。
abstract final class BlockKey {
  static const selection = '_selection';
  static const ghost = '_ghost';
  static const shadow = '_shadow';
  static const canvas = '_canvas';
  static const canvasDot = '_canvasDot';
  static const error = '_error';
  static const warning = '_warning';
  static const onError = '_onError';
  static const onWarning = '_onWarning';
  static const text = '_text';
  static const fieldBg = '_fieldBg';
  static const fieldText = '_fieldText';
  static const fieldHint = '_fieldHint';
  static const gloss = '_gloss';
  static const shade = '_shade';
}

const List<ThemeField> kBlockExtraFields = [
  ThemeField(BlockKey.text, '积木上的字', group: '积木'),
  ThemeField(BlockKey.fieldBg, '输入框底色', group: '积木'),
  ThemeField(BlockKey.fieldText, '输入框文字', group: '积木'),
  ThemeField(BlockKey.fieldHint, '输入框提示字', group: '积木'),
  ThemeField(BlockKey.gloss, '高光', group: '积木', note: '积木顶上那道亮边、提示闪动；只取色相'),
  ThemeField(BlockKey.shade, '压暗', group: '积木', note: '被挡住 / 不可用的积木上盖的那层；只取色相'),
  ThemeField(BlockKey.selection, '选中描边', group: '画布'),
  ThemeField(BlockKey.ghost, '落点影子', group: '画布', note: '带透明度'),
  ThemeField(BlockKey.shadow, '拖起来时的阴影', group: '画布', note: '带透明度'),
  ThemeField(BlockKey.canvas, '画布底色', group: '画布'),
  ThemeField(BlockKey.canvasDot, '画布点阵', group: '画布'),
  ThemeField(BlockKey.error, '报错标记', group: '问题'),
  ThemeField(BlockKey.warning, '警告标记', group: '问题'),
  ThemeField(BlockKey.onError, '报错标记上的符号', group: '问题'),
  ThemeField(BlockKey.onWarning, '警告标记上的符号', group: '问题'),
];

const List<ThemeField> kBlockFields = [...kBlockCategoryFields, ...kBlockExtraFields];

/// 低代码编辑器自己的界面色（不是用户页面内容的颜色）。
abstract final class LowcodeKey {
  static const selection = 'selection';
  static const selectionText = 'selectionText';
  static const handleFill = 'handleFill';
  static const marginRing = 'marginRing';
  static const paddingRing = 'paddingRing';
  static const dropHoverBg = 'dropHoverBg';
  static const dropHoverBorder = 'dropHoverBorder';
  static const dropIdleBg = 'dropIdleBg';
  static const dropIdleBorder = 'dropIdleBorder';
  static const dropText = 'dropText';
  static const insertBar = 'insertBar';
  static const insertBarIdle = 'insertBarIdle';
  static const dropOutline = 'dropOutline';
  static const sizeTagBg = 'sizeTagBg';
  static const sizeTagText = 'sizeTagText';
  static const dragChipBg = 'dragChipBg';
  static const dragChipText = 'dragChipText';
  static const missingBg = 'missingBg';
  static const missingBorder = 'missingBorder';
  static const missingIcon = 'missingIcon';
  static const missingText = 'missingText';
}

const List<ThemeField> kLowcodeFields = [
  ThemeField(LowcodeKey.selection, '选中框', group: '选中', note: '选中框、名字标签的底、拖柄的边'),
  ThemeField(LowcodeKey.selectionText, '名字标签文字', group: '选中'),
  ThemeField(LowcodeKey.handleFill, '拖柄填充', group: '选中'),
  ThemeField(LowcodeKey.marginRing, '外边距示意', group: '选中', note: '带透明度'),
  ThemeField(LowcodeKey.paddingRing, '内边距示意', group: '选中', note: '带透明度'),
  ThemeField(LowcodeKey.dropHoverBg, '空容器（拖到上面）底色', group: '拖放'),
  ThemeField(LowcodeKey.dropHoverBorder, '空容器（拖到上面）边', group: '拖放'),
  ThemeField(LowcodeKey.dropIdleBg, '空容器底色', group: '拖放', note: '带透明度'),
  ThemeField(LowcodeKey.dropIdleBorder, '空容器边', group: '拖放'),
  ThemeField(LowcodeKey.dropText, '空容器提示字', group: '拖放'),
  ThemeField(LowcodeKey.insertBar, '插入线（对准时）', group: '拖放'),
  ThemeField(LowcodeKey.insertBarIdle, '插入线', group: '拖放'),
  ThemeField(LowcodeKey.dropOutline, '可放进去的容器的描边', group: '拖放'),
  ThemeField(LowcodeKey.dragChipBg, '拖着的小牌子底色', group: '拖放'),
  ThemeField(LowcodeKey.dragChipText, '拖着的小牌子文字', group: '拖放'),
  ThemeField(LowcodeKey.sizeTagBg, '尺寸标签底色', group: '标注', note: '带透明度'),
  ThemeField(LowcodeKey.sizeTagText, '尺寸标签文字', group: '标注'),
  ThemeField(LowcodeKey.missingBg, '“组件不见了”占位底色', group: '标注'),
  ThemeField(LowcodeKey.missingBorder, '“组件不见了”占位边', group: '标注'),
  ThemeField(LowcodeKey.missingIcon, '“组件不见了”图标', group: '标注'),
  ThemeField(LowcodeKey.missingText, '“组件不见了”文字', group: '标注'),
];

/// 形状与密度的键。
abstract final class MetricKey {
  static const radiusScale = 'radiusScale';
  static const spaceScale = 'spaceScale';
  static const fontScale = 'fontScale';
  static const shadowStrength = 'shadowStrength';
  static const dividerWidth = 'dividerWidth';
  static const surfaceOpacity = 'surfaceOpacity';
}

const List<ThemeMetricField> kMetricFields = [
  ThemeMetricField(MetricKey.radiusScale, '圆角', min: 0, max: 2, fallback: 1, note: '倍率：0＝方角，1＝默认，越大越圆'),
  ThemeMetricField(MetricKey.spaceScale, '间距密度', min: 0.75, max: 1.25, fallback: 1, note: '倍率：小于 1 紧凑，大于 1 宽松'),
  ThemeMetricField(MetricKey.fontScale, '界面字号', min: 0.85, max: 1.3, fallback: 1, note: '倍率；代码字号是另一个独立设置，不跟它走'),
  ThemeMetricField(MetricKey.shadowStrength, '阴影强弱', min: 0, max: 2, fallback: 1, note: '倍率：0＝没有阴影'),
  ThemeMetricField(MetricKey.dividerWidth, '分隔线粗细', min: 0.5, max: 2, fallback: 1, note: '逻辑像素'),
  ThemeMetricField(MetricKey.surfaceOpacity, '有背景图时卡片的不透明度', min: 0.3, max: 1, fallback: 0.88, note: '只在选了背景图时起作用'),
];

/// 各节的名字（文件里的键）→ 字段目录。
const Map<String, List<ThemeField>> kThemeColorSections = {'ui': kUiFields, 'code': kCodeFields, 'terminal': kTerminalFields, 'blocks': kBlockFields, 'lowcode': kLowcodeFields};

/// 各节给人看的名字。
const Map<String, String> kThemeSectionLabels = {'ui': '界面', 'code': '代码', 'tokens': '代码高亮', 'terminal': '终端', 'blocks': '积木', 'lowcode': '低代码编辑器', 'metrics': '形状与密度'};
