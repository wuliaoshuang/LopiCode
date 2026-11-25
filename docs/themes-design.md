# 外观主题：设计说明（第 1 步“打地基”）

> 2026-11-26。这一页是给后面接着做“多套内置主题”“主题编辑器与导入导出”“背景图”的人看的，开头一段给霜霜看。

## 给霜霜的总览

这一步没有加任何新样子，做的是“让整个应用的颜色都能换”这件事的地基：

- **现在能做到的**：应用里所有界面的颜色——页面、按钮、气泡、代码高亮、终端、积木、低代码编辑器的选中框——都从“一份主题”里取，
  不再散落在各个页面里写死。换一份主题，上面这些一起变。
- **你现在能看到的变化只有一处**：设置 › 界面 › 外观 里多了“浅色主题”“深色主题”两行，点开各是一个列表。现在列表里只有
  “默认浅色”“默认深色”（就是原来的样子，一个颜色都没动）。更多主题、自己调颜色、导出给别人，是后面几步的事。
- **浅色和深色各选一套**：颜色模式还是“跟随系统 / 浅色 / 深色”三选一；另外你可以分别定“浅色时用哪套”“深色时用哪套”。
  这样跟随系统时，手机切到深色会自动换成你选的深色那套。
- **一份主题里能定的东西**：界面颜色 45 项、代码区域 12 项、代码高亮 55 类（每类一个颜色，可加粗 / 倾斜）、终端 23 项（含 16 色）、
  积木 35 项（20 类积木各一个主色 + 选中、阴影、画布等）、低代码编辑器 21 项，另有 6 个“形状与密度”的数（圆角、间距、界面字号、
  阴影强弱、分隔线粗细、有背景图时卡片的透明度）。一共 191 个颜色 + 6 个数。
- **导出的主题是一个文本文件**，别人导入时会逐项检查：格式不对、颜色写错、数字超范围都会用一句话告诉他哪里不对，不会让应用崩；
  文件内容只当数据读，不会被执行。
- **要如实说的**：圆角、间距这两个倍率目前只对“通用控件”（按钮、输入框、卡片、对话框、底部面板、菜单、设置里的行）和少数几处
  （聊天气泡、输入框、聊天里的卡片、侧边栏选中行）生效；各页面里自己摆的间距还是固定的，不会跟着变。字号倍率是全应用一起变
  （代码编辑器、看代码、终端除外，它们有自己的“代码字号”）。详见下面“形状、密度、字号”一节。

## 一、盘点：改之前颜色、圆角、字号、间距、阴影各从哪来

| 东西 | 改之前 | 现在 |
| --- | --- | --- |
| 界面颜色 | `lib/theme/tokens.dart` 的 `AppColors`（17 个语义色，浅 / 深两个常量），页面里 `context.colors.xxx` | `AppColors` 还是入口，旧 17 个名字不变，另加 28 个；值从当前主题来 |
| 原始色板 | `Palette`（`neutral900`、`primary500`…），有 30 来处被页面直接用 | `Palette` 还在，但只剩低代码“用户页面内容的默认色”在用；界面不许再直接用 |
| 提示条、on-error | `app_theme.dart` 里直接用 `Palette` | 主题的 `snackBg` / `snackText` / `onDanger` |
| 代码高亮 | `re_highlight` 自带的 Atom One 浅 / 深两张表（`lib/ui/code_langs.dart` 的 `codeThemeFor`），去掉了粗体斜体 | 主题的“代码高亮”一节，55 类 |
| 代码编辑器的底色、光标、选区、当前行、行号 | 借用界面色再现调透明度（`c.accent.withValues(alpha: 0.25)` 之类） | 主题的“代码”一节，各有自己的项 |
| 改动对比 | `lib/ui/diff_view.dart` 里 `DiffColors` 写死浅 / 深各 4 色 | 主题的“代码”一节 `diffAddBg` 等 4 项 |
| 终端 | `lib/ui/terminal_tab.dart` 里写死 16 色 × 浅深，前景 / 背景 / 光标借用界面色 | 主题的“终端”一节 |
| 积木 | `lib/blocks/block_colors.dart` 的 `BkPalette`：浅色 20 类主色写死，深色由浅色现算；高光、角标符号等 10 来处写死在画的地方 | 主题的“积木”一节；`BkPalette.fromTheme(主题)` |
| 低代码编辑器（选中框、拖柄、插入线、空容器提示…） | `lib/lowcode/canvas_*_widgets.dart` 里写死，浅深同一套 | 主题的“低代码编辑器”一节 |
| 上下文占用条的四段颜色 | `lib/ui/context_bar.dart` 直接用 `Palette` | 主题的 `chart1`–`chart4` |
| 错误提示条 | `lib/ui/error_guard.dart` 写死 | 主题的 `noticeBg` / `noticeText` |
| 阴影、遮罩 | 各处 `Colors.black.withValues(alpha: …)`、`Colors.black26`、`Color(0x0F000000)` | `context.colors.shadowOf(透明度)` / `scrimOf(透明度)`：主题定色相和强弱，各处定深浅 |
| 圆角 | `Radii` 常量（112 处） | 常量不动；`ThemeData` 层和少数共用件按主题倍率算 |
| 间距 | `Space` 常量（1288 处） | 常量不动；`ThemeData` 层（按钮、输入框、列表行的内边距）按主题倍率算 |
| 字号 | `FontSize` 常量（47 处）+ `ThemeData.textTheme` | 常量不动；应用最外层按主题倍率缩放全部文字 |
| 代码字号 | 独立设置 `ui.codeFontSize` | 不变，不并进主题 |

改之前写死的颜色共 129 处（不算 `Colors.transparent`）。现在 `lib/` 下除了主题定义文件，只剩 19 处登记过的例外
（见“守门测试”一节），都不是界面色。

## 二、主题数据放在哪、长什么样

- 新目录 **`lib/appearance/`**：纯 Dart，不碰界面库，只依赖 `lib/core/`。`lib/theme/` 改为可以依赖它。
  （`AGENTS.md` 的目录表和 `test/architecture_test.dart` 的分层表都更新了。）

| 文件 | 管什么 |
| --- | --- |
| `lib/appearance/theme_fields.dart` | **字段目录**：每一节有哪些键、中文名、分组、说明；形状与密度的范围。编辑器照着它遍历就能列出全部可调项 |
| `lib/appearance/theme_spec.dart` | `ThemeSpec`（一份主题，不可变）、`TokenStyle`（一类高亮：颜色 + 粗 + 斜） |
| `lib/appearance/theme_builtin.dart` | 内置主题表 `kBuiltinThemes`、默认浅 / 深两套、`defaultThemeFor(dark:)` |
| `lib/appearance/theme_json.dart` | 主题文件的读写和校验（导入导出第 1 版） |
| `lib/appearance/theme_contrast.dart` | 对比度计算、检查清单、默认主题的已知例外 |
| `lib/appearance/theme_store.dart` | 用户主题的存盘 |
| `lib/state/themes_state.dart` | 状态：主题库 + 两个槽的选择（Riverpod） |
| `lib/theme/tokens.dart` | `AppColors`（`context.colors`）、`context.themeSpec`、按键取色的扩展 |
| `lib/theme/app_theme.dart` | `buildThemeData(主题)`：把主题变成 `ThemeData` |
| `lib/theme/text_scale.dart` | 界面字号倍率怎么生效 |

`ThemeSpec` 的样子（“一节一张表”：每节是“键 → 颜色”，颜色是 ARGB 整数）：

```
ThemeSpec
  id        标识（内置的如 default-light；用户的由应用分配，如 u-mf3k2a-0）
  name      名字（最多 40 个字）
  author    作者（可空，最多 40 个字）
  dark      这份主题是深色的还是浅色的（一份主题只声明一种）
  version   格式版本（现在是 1）
  builtin   是不是内置的（内置的只读）
  ui        界面色        45 项
  code      代码区域      12 项
  tokens    代码高亮      55 类（TokenStyle：color 可空、bold、italic）
  terminal  终端          23 项
  blocks    积木          35 项
  lowcode   低代码编辑器  21 项
  metrics   形状与密度    6 个数
```

为什么做成“表”而不是 191 个具名字段：编辑器要把所有可调项列出来、导入要逐项校验、以后还会加项——照着字段目录遍历一遍就行，
加一项只改两个地方（字段目录 + 内置主题的值）。常用的界面色仍然有具名的入口（`context.colors.accent`），写页面时不用记键名。

### 深浅规则

- **一份主题只有一种明暗**（`dark: true / false`），不做“一份主题带浅深两套”。
- 外观模式仍是“跟随系统 / 浅色 / 深色”（`themeModeProvider`，没动）。
- 另有两个“槽”：浅色时用哪套（设置键 `ui.themeLight`，默认 `default-light`）、深色时用哪套（`ui.themeDark`，默认 `default-dark`）。
  浅色槽里只能放浅色主题，深色槽里只能放深色主题（选的时候按主题自己的明暗进对应的槽）。
- 槽里记的标识找不到了（主题被删、文件坏了）或明暗对不上：那个槽自动退回默认主题，不报错。
- 导入、缺字段补齐时，“默认值”都取**同明暗的默认主题**。

### 界面色（`ui`，45 项）

前 17 项就是原来 `AppColors` 的 17 个，名字没变。

| 键 | 名字 | 分组 | 说明 |
| --- | --- | --- | --- |
| `bg` | 主页面底色 | 底色 | 对话、文件、终端这些主页面 |
| `canvas` | 分组页面底色 | 底色 | 设置这类“卡片分组”页面，上面放卡片 |
| `surface` | 卡片 / 面板 | 底色 | 卡片、底部面板、对话框、菜单 |
| `surfaceMuted` | 浅灰块 | 底色 | 胶囊、标签、次要按钮的底 |
| `codeBg` | 代码块 / 日志底色 | 底色 | 聊天里的代码块、日志、步骤详情 |
| `cardBg` | 确认卡 / 步骤卡底色 | 底色 | 聊天里浮在消息上的确认卡、提问卡 |
| `inputBg` | 输入框底色 | 底色 | 表单输入框和聊天输入框 |
| `text` | 正文 | 文字 |  |
| `textMuted` | 次要文字 | 文字 |  |
| `textFaint` | 提示文字 | 文字 | 占位字、时间、行号这类最淡的字 |
| `link` | 链接 | 文字 | 预留：现在界面里没有单独的链接样式 |
| `border` | 边线 / 分隔线 | 线 |  |
| `accent` | 强调色（文字、图标） | 强调 |  |
| `accentSoft` | 强调色浅底 | 强调 | 标签、分段按钮选中态 |
| `accentFill` | 实心按钮底 | 强调 |  |
| `onAccent` | 实心按钮上的字 | 强调 |  |
| `selectedBg` | 选中项的底 | 强调 | 侧边栏里当前这一项 |
| `danger` | 危险（文字、图标） | 状态 |  |
| `dangerSoft` | 危险浅底 | 状态 |  |
| `onDanger` | 实心危险按钮上的字 | 状态 |  |
| `warning` | 警告（文字、图标） | 状态 |  |
| `warningSoft` | 警告浅底 | 状态 |  |
| `success` | 成功（文字、图标） | 状态 | 预留：现在只有改动对比里用绿色，那一组在“代码”里 |
| `successSoft` | 成功浅底 | 状态 | 预留 |
| `info` | 提示信息（文字、图标） | 状态 | 预留 |
| `infoSoft` | 提示信息浅底 | 状态 | 预留 |
| `noticeBg` | 出错提示条底色 | 状态 | 页面顶上“出错了”的提示条、坏掉的那一块 |
| `noticeText` | 出错提示条文字 | 状态 |  |
| `navBg` | 底部导航底色 | 导航与顶栏 |  |
| `navActive` | 底部导航选中 | 导航与顶栏 |  |
| `navInactive` | 底部导航未选中 | 导航与顶栏 |  |
| `barButtonBg` | 顶栏按钮底色 | 导航与顶栏 | 顶栏没有底色，只有悬浮的圆按钮和胶囊 |
| `bubbleMineBg` | 我的气泡底色 | 聊天 |  |
| `bubbleMineText` | 我的气泡文字 | 聊天 |  |
| `bubbleAgentBg` | Agent 气泡底色 | 聊天 |  |
| `bubbleAgentText` | Agent 气泡文字 | 聊天 |  |
| `snackBg` | 底部提示条底色 | 提示条 |  |
| `snackText` | 底部提示条文字 | 提示条 |  |
| `scrim` | 遮罩 | 遮罩与阴影 | 侧边栏、弹层后面压暗用；只取色相，深浅由各处自己定 |
| `shadow` | 阴影 | 遮罩与阴影 | 只取色相，深浅由各处自己定，再乘上“阴影强弱” |
| `backdropScrim` | 背景图上的遮罩 | 遮罩与阴影 | 有背景图时盖在图上、内容下面的一层（带透明度） |
| `chart1` | 占用条：系统提示词 | 图表 |  |
| `chart2` | 占用条：工具定义 | 图表 |  |
| `chart3` | 占用条：对话消息 | 图表 |  |
| `chart4` | 占用条：工具结果 | 图表 |  |

其中 `success`、`successSoft`、`info`、`infoSoft`、`link`、`backdropScrim` 这 6 项**现在界面里还没有地方用**，是给后面留的
（成功 / 信息提示、链接样式、背景图遮罩）。默认主题里给了合理的值，但没有被钉值测试守着。

### 代码区域（`code`，12 项）

| 键 | 名字 | 分组 | 说明 |
| --- | --- | --- | --- |
| `bg` | 代码底色 | 编辑器 |  |
| `fg` | 代码文字 | 编辑器 | 没有单独上色的字 |
| `lineNumber` | 行号 | 编辑器 |  |
| `lineNumberActive` | 当前行的行号 | 编辑器 |  |
| `currentLine` | 当前行底色 | 编辑器 | 带透明度 |
| `selection` | 选区 | 编辑器 | 带透明度 |
| `cursor` | 光标 | 编辑器 |  |
| `searchHit` | 查找命中 | 编辑器 | 带透明度 |
| `diffAddBg` | 新增行底色 | 改动对比 |  |
| `diffAddFg` | 新增行文字 | 改动对比 |  |
| `diffDelBg` | 删除行底色 | 改动对比 |  |
| `diffDelFg` | 删除行文字 | 改动对比 |  |

### 代码高亮（`tokens`，55 类）

怎么得到这 55 类的：把现在登记的全部语言（`lib/ui/code_langs.dart`，89 个规则集）的高亮规则完整走了一遍，凡是规则里会打出来的标签都收了，
再并上 Atom One 配色表里有颜色的标签。查表是**整名精确匹配**（`title.function` 不会退回 `title`），所以带点号的也各算一类。
默认主题里前 30 类有颜色（就是原来 Atom One 的颜色），后 25 类没单独上色（按普通代码文字画），和原来一样。
默认主题全部不加粗不倾斜（等宽代码里粗体会把列挤歪），主题可以按类打开。

| 键 | 名字 | 分组 | 说明 |
| --- | --- | --- | --- |
| `comment` | 注释 | 常用 |  |
| `keyword` | 关键字 | 常用 |  |
| `string` | 字符串 | 常用 |  |
| `number` | 数字 | 常用 |  |
| `literal` | 字面量（true / null…） | 常用 |  |
| `type` | 类型 | 常用 |  |
| `built_in` | 内置的名字 | 常用 |  |
| `title` | 名字（定义处） | 常用 |  |
| `title.function` | 函数名 | 常用 |  |
| `title.function.invoke` | 调用的函数名 | 常用 |  |
| `title.class` | 类名 | 常用 |  |
| `title.class.inherited` | 父类名 | 常用 |  |
| `function` | 函数（整段） | 常用 |  |
| `function.dispatch` | 函数调用（整段） | 常用 |  |
| `class` | 类（整段） | 常用 |  |
| `params` | 参数 | 常用 |  |
| `variable` | 变量 | 常用 |  |
| `variable.constant` | 常量 | 常用 |  |
| `variable.language` | 语言自带的变量（this / self） | 常用 |  |
| `property` | 属性名 | 常用 |  |
| `operator` | 运算符 | 常用 |  |
| `punctuation` | 标点 | 常用 |  |
| `regexp` | 正则 | 常用 |  |
| `regex` | 正则（另一种标签） | 常用 |  |
| `char.escape` | 转义字符 | 常用 |  |
| `character` | 单个字符 | 常用 |  |
| `subst` | 字符串里的插值 | 常用 |  |
| `symbol` | 符号 | 常用 |  |
| `label` | 标号 | 常用 |  |
| `meta` | 元信息（注解、预处理） | 常用 |  |
| `meta.prompt` | 命令提示符 | 常用 |  |
| `doctag` | 文档标记（@param） | 常用 |  |
| `computation-expression` | 计算表达式（F#） | 常用 |  |
| `tag` | 标签（整段） | 网页 |  |
| `name` | 标签名 | 网页 |  |
| `attr` | 属性 | 网页 |  |
| `attribute` | 属性名（CSS、配置） | 网页 |  |
| `selector-tag` | 选择器：标签 | 网页 |  |
| `selector-id` | 选择器：#id | 网页 |  |
| `selector-class` | 选择器：.class | 网页 |  |
| `selector-attr` | 选择器：[属性] | 网页 |  |
| `selector-pseudo` | 选择器：伪类 | 网页 |  |
| `template-tag` | 模板标签 | 网页 |  |
| `template-variable` | 模板变量 | 网页 |  |
| `section` | 标题 | 文档 |  |
| `bullet` | 列表符号 | 文档 |  |
| `quote` | 引用 | 文档 |  |
| `code` | 行内代码 | 文档 |  |
| `link` | 链接 | 文档 |  |
| `emphasis` | 强调（斜体） | 文档 |  |
| `strong` | 加粗 | 文档 |  |
| `formula` | 公式 | 文档 |  |
| `addition` | 新增（diff） | 改动 |  |
| `deletion` | 删除（diff） | 改动 |  |
| `delete` | 删除（另一种标签） | 改动 |  |

### 终端（`terminal`，23 项）

| 键 | 名字 | 分组 | 说明 |
| --- | --- | --- | --- |
| `fg` | 文字 | 基本 |  |
| `bg` | 底色 | 基本 |  |
| `cursor` | 光标 | 基本 |  |
| `selection` | 选区 | 基本 | 带透明度 |
| `searchHitBg` | 查找命中底色 | 基本 |  |
| `searchHitBgCurrent` | 当前命中底色 | 基本 |  |
| `searchHitFg` | 查找命中文字 | 基本 |  |
| `black` | 黑 | 8 色 |  |
| `red` | 红 | 8 色 |  |
| `green` | 绿 | 8 色 |  |
| `yellow` | 黄 | 8 色 |  |
| `blue` | 蓝 | 8 色 |  |
| `magenta` | 品红 | 8 色 |  |
| `cyan` | 青 | 8 色 |  |
| `white` | 白 | 8 色 |  |
| `brightBlack` | 亮黑 | 亮 8 色 |  |
| `brightRed` | 亮红 | 亮 8 色 |  |
| `brightGreen` | 亮绿 | 亮 8 色 |  |
| `brightYellow` | 亮黄 | 亮 8 色 |  |
| `brightBlue` | 亮蓝 | 亮 8 色 |  |
| `brightMagenta` | 亮品红 | 亮 8 色 |  |
| `brightCyan` | 亮青 | 亮 8 色 |  |
| `brightWhite` | 亮白 | 亮 8 色 |  |

### 积木（`blocks`，35 项）

20 类积木各一个主色（键和 `BlockColorKey` 一一对应，测试守着）。每一类其余几档——顶部亮一点的、底边、槽位、嵌套时提亮的——
仍由主色按原来的算法算出来，主题不单独定。

| 键 | 名字 | 分组 | 说明 |
| --- | --- | --- | --- |
| `event` | 事件 | 分类主色 |  |
| `variable` | 变量 | 分类主色 |  |
| `widget` | 控件 | 分类主色 |  |
| `control` | 流程 | 分类主色 |  |
| `action` | 交互 | 分类主色 |  |
| `network` | 网络 | 分类主色 |  |
| `value` | 直接填的值 | 分类主色 |  |
| `operator` | 运算 | 分类主色 |  |
| `data` | 数据集合 | 分类主色 |  |
| `request` | 请求 | 分类主色 |  |
| `response` | 返回 | 分类主色 |  |
| `unknown` | 不认识的 | 分类主色 |  |
| `function` | 函数 | 分类主色 |  |
| `text` | 文字 | 分类主色 |  |
| `list` | 列表 | 分类主色 |  |
| `dict` | 字典 | 分类主色 |  |
| `class` | 类 | 分类主色 |  |
| `error` | 出错 | 分类主色 |  |
| `async` | 等待 | 分类主色 |  |
| `custom` | 我的积木 | 分类主色 |  |

另外 15 项（键以下划线开头，免得和分类撞名）：

| 键 | 名字 | 分组 | 说明 |
| --- | --- | --- | --- |
| `_text` | 积木上的字 | 积木 |  |
| `_fieldBg` | 输入框底色 | 积木 |  |
| `_fieldText` | 输入框文字 | 积木 |  |
| `_fieldHint` | 输入框提示字 | 积木 |  |
| `_gloss` | 高光 | 积木 | 积木顶上那道亮边、提示闪动；只取色相 |
| `_shade` | 压暗 | 积木 | 被挡住 / 不可用的积木上盖的那层；只取色相 |
| `_selection` | 选中描边 | 画布 |  |
| `_ghost` | 落点影子 | 画布 | 带透明度 |
| `_shadow` | 拖起来时的阴影 | 画布 | 带透明度 |
| `_canvas` | 画布底色 | 画布 |  |
| `_canvasDot` | 画布点阵 | 画布 |  |
| `_error` | 报错标记 | 问题 |  |
| `_warning` | 警告标记 | 问题 |  |
| `_onError` | 报错标记上的符号 | 问题 |  |
| `_onWarning` | 警告标记上的符号 | 问题 |  |

### 低代码编辑器（`lowcode`，21 项）

只管编辑器自己的界面色。**用户页面内容本身的颜色**（页面默认白底、默认文字色、卡片默认阴影、图片占位）和**导出代码里的颜色**不归主题管，没动。

| 键 | 名字 | 分组 | 说明 |
| --- | --- | --- | --- |
| `selection` | 选中框 | 选中 | 选中框、名字标签的底、拖柄的边 |
| `selectionText` | 名字标签文字 | 选中 |  |
| `handleFill` | 拖柄填充 | 选中 |  |
| `marginRing` | 外边距示意 | 选中 | 带透明度 |
| `paddingRing` | 内边距示意 | 选中 | 带透明度 |
| `dropHoverBg` | 空容器（拖到上面）底色 | 拖放 |  |
| `dropHoverBorder` | 空容器（拖到上面）边 | 拖放 |  |
| `dropIdleBg` | 空容器底色 | 拖放 | 带透明度 |
| `dropIdleBorder` | 空容器边 | 拖放 |  |
| `dropText` | 空容器提示字 | 拖放 |  |
| `insertBar` | 插入线（对准时） | 拖放 |  |
| `insertBarIdle` | 插入线 | 拖放 |  |
| `dropOutline` | 可放进去的容器的描边 | 拖放 |  |
| `dragChipBg` | 拖着的小牌子底色 | 拖放 |  |
| `dragChipText` | 拖着的小牌子文字 | 拖放 |  |
| `sizeTagBg` | 尺寸标签底色 | 标注 | 带透明度 |
| `sizeTagText` | 尺寸标签文字 | 标注 |  |
| `missingBg` | “组件不见了”占位底色 | 标注 |  |
| `missingBorder` | “组件不见了”占位边 | 标注 |  |
| `missingIcon` | “组件不见了”图标 | 标注 |  |
| `missingText` | “组件不见了”文字 | 标注 |  |

### 形状、密度、字号（`metrics`，6 个数）

| 键 | 名字 | 范围 | 默认 | 说明 |
| --- | --- | --- | --- | --- |
| `radiusScale` | 圆角 | 0–2 | 1 | 倍率：0＝方角，越大越圆 |
| `spaceScale` | 间距密度 | 0.75–1.25 | 1 | 倍率：小于 1 紧凑，大于 1 宽松 |
| `fontScale` | 界面字号 | 0.85–1.3 | 1 | 倍率；代码字号是另一个独立设置 |
| `shadowStrength` | 阴影强弱 | 0–2 | 1 | 倍率：0＝没有阴影 |
| `dividerWidth` | 分隔线粗细 | 0.5–2 | 1 | 逻辑像素 |
| `surfaceOpacity` | 有背景图时卡片的不透明度 | 0.3–1 | 0.88 | 现在没有地方用，给背景图那一步留的 |

**选的方案和原因。** `Space`（1288 处）、`Radii`（112 处）、`FontSize`（47 处）是编译期常量，几百个文件在用，其中很多写在 `const` 里。
全部改成“随主题变”要动上千行，而且同时有三路人在改这些文件，合并风险很大。所以这一步：

- **常量名和值都不动。**
- **界面字号**：在应用最外层把系统的文字缩放再乘上主题的倍率（`lib/theme/text_scale.dart` 的 `ThemeTextScale`，接在 `lib/app.dart`）。
  **全应用的文字都跟着变**，不用逐处改。代码编辑器、看代码（`CodeView`）、终端在自己外面包了一层 `SystemTextScale` 把倍率拿掉，
  所以**不跟着变**（它们听“代码字号”设置）。倍率是 1（默认）时两层都不存在，和原来完全一样。
  要如实说的一点：聊天里的改动对比、步骤详情里的命令输出、后台日志这些“小一号的等宽字”是普通文字，**会跟着界面字号变**
  （它们的基准仍是代码字号小一号，再乘倍率）。
- **圆角、间距、分隔线粗细**：在 `buildThemeData` 里按倍率算——所以**通用控件会跟着变**：按钮、输入框、卡片、对话框、底部面板、
  弹出菜单、分段按钮、提示条的圆角；按钮 / 输入框 / 列表行的内边距；分隔线和各种边框的粗细。
  另外这几处共用件直接用了 `context.colors.radius(…)` / `.hairline`，也会跟着变：聊天气泡、聊天输入框、聊天里的卡片、
  顶栏的悬浮按钮边框、侧边栏选中行。
- **不会跟着变的**：各页面里直接写 `Space.x4`、`Radii.md` 的地方（绝大多数页面自己摆的间距、设置分组卡片的圆角、积木的形状等）。
  以后要让某一处跟着变，把那一处的 `Radii.md` 换成 `context.colors.radius(Radii.md)`、`Space.x4` 换成 `context.colors.space(Space.x4)` 就行，
  可以一处一处慢慢迁，不用一次改完。
- **阴影强弱**：所有阴影都走 `context.colors.shadowOf(透明度)`，倍率乘在透明度上，全应用生效（`Material` 控件自带的 elevation 阴影颜色
  也是从这里给的）。

## 三、存盘

- **选了哪套**：设置文件里的两个键 `ui.themeLight`、`ui.themeDark`（和别的设置一样走 `SettingsStore`）。
- **用户主题**：应用数据目录（设置文件所在的目录）下 `themes/`，每套一个 `<标识>.json`，内容就是导出文件的格式（不带背景图）。
  写用 `writeJsonAtomic`，读用 `readJsonFile`（坏文件另存一份 `.bad-时间戳`、跳过这一套，不崩）。
- 标识只能是小写字母、数字、短横线，最多 48 个字符（`^[a-z0-9][a-z0-9-]{0,47}$`），所以文件名不可能跑到 `themes/` 外面去。
  文件里写的标识和文件名对不上时以文件名为准。
- 上限：用户主题最多 50 套；一份主题最多 256KB（实际一份才几 KB）；名字、作者各最多 40 个字。
- 内置主题不落盘，在代码里。

## 四、导入导出文件格式（第 1 版）

一个 UTF-8 的 JSON 文本文件，建议扩展名 `.lopitheme.json`：

```json
{
  "format": "lopicode-theme",
  "version": 1,
  "theme": {
    "id": "u-mf3k2a-0",
    "name": "海边",
    "author": "霜霜",
    "dark": false,
    "ui":       { "bg": "#FCFCFC", "accent": "#2962CB", "scrim": "#000000" },
    "code":     { "bg": "#F3F4F6", "selection": "#402962CB" },
    "tokens":   { "keyword": { "color": "#A626A4", "bold": false, "italic": false }, "comment": "#A0A1A7" },
    "terminal": { "fg": "#15151B", "red": "#C6212F" },
    "blocks":   { "control": "#6B4BD8", "_selection": "#FFC53D" },
    "lowcode":  { "selection": "#2962CB" },
    "metrics":  { "radiusScale": 1, "fontScale": 1 }
  },
  "background": {
    "mime": "image/jpeg",
    "data": "（图片的 base64）",
    "crop": { "x": 0, "y": 0, "w": 1, "h": 1 },
    "dim": 0.2,
    "blur": 0
  }
}
```

规则：

- 颜色写成 `#RRGGBB`（不透明）或 `#AARRGGBB`（带透明度），大小写都行。别的写法（颜色名、`rgb()`、数字）一律不认。
- 高亮分类可以写成一个对象（`color` 可以是 `null`＝不单独上色，`bold`、`italic`），也可以只写一个颜色文本。
- **必须有的**：`format`、`version`、`theme.name`、`theme.dark`。其余都可以不写。
- **缺的字段**从同明暗的默认主题补；**不认识的字段**跳过，并告诉用户“跳过了几个这个版本不认识的字段”。
- `version` 比应用认得的新：拒绝，并说明“这是更新版本的应用导出的”。
- `metrics` 里的数超出范围：拒绝，并说明是哪一项、范围是多少。
- 大小：整个文件最多 12MB（为了能带图）；主题本身最多 256KB；背景图最多 8MB。
- `id` 只是个参考：**导入永远当一套新主题存**，由应用分配新标识，不会盖掉已有的；名字重了自动在后面加“ 2”“ 3”。
- 导入后**不自动选用**，由界面决定要不要问用户。
- `background` 这一节是可选的（由导出的人决定带不带）。图没法用（格式不支持、不是合法的 base64、内容和声称的格式对不上、太大）
  时**只丢掉图**，主题照常导入，并说明原因。裁剪范围不合理当作没裁；压暗、模糊超范围收回到范围里。
- 文件内容只当数据读，没有任何会被执行的东西。
- 坏文件返回一句人话的原因（`ThemeDecodeResult.error`），不抛异常。`test/theme_json_test.dart` 里有 30 多种坏法的用例。

## 五、对比度

`lib/appearance/theme_contrast.dart`，纯 Dart，按 WCAG 2.x 的公式算：

- `contrastRatio(前景, 背景)`：1–21。前景带透明度的话先叠到背景上再算。
- `checkThemeContrast(主题)`：照清单 `kContrastChecks` 查一遍，返回不达标的项（`ContrastIssue`：哪一对、实际多少、要求多少、一句人话）。
- 门槛两档：**正文和小字 ≥ 4.5:1**；**图标、大字、描边、色块 ≥ 3:1**。
- 清单现在 150 来项，大致是：正文 / 次要文字 / 最淡文字放在各种底色上；按钮上的字；危险、警告的字放在各自的浅底上；
  提示条；气泡；底部导航；代码文字、行号、每一类有颜色的高亮放在代码底色上；改动对比；终端前景和 16 色放在终端底色上；
  积木上的字放在每一类主色上；输入框里的字；积木画布上的选中描边、报错、警告标记；低代码编辑器的标签。
  没设颜色的高亮分类不查（它和代码文字同色）。

**默认主题达不到的项**。默认外观一个颜色都不能动，所以这些只登记（`kKnownContrastGaps`）不修；`test/theme_contrast_test.dart`
守着“不达标的正好是登记过的这些，不多不少”。**新加的内置主题不应该往例外里加东西**，应该改颜色。

默认浅色（31 项）：

| 哪一对 | 实际 | 要求 |
| --- | --- | --- |
| “界面 › 占用条：工具定义”放在“界面 › 卡片 / 面板”上 | 1.80:1 | 3:1 |
| “界面 › 占用条：工具结果”放在“界面 › 卡片 / 面板”上 | 1.72:1 | 3:1 |
| “代码高亮 › 注释”放在“代码 › 代码底色”上 | 2.34:1 | 4.5:1 |
| “代码高亮 › 字符串”放在“代码 › 代码底色”上 | 2.91:1 | 4.5:1 |
| “代码高亮 › 数字”放在“代码 › 代码底色”上 | 4.42:1 | 4.5:1 |
| “代码高亮 › 字面量（true / null…）”放在“代码 › 代码底色”上 | 3.80:1 | 4.5:1 |
| “代码高亮 › 类型”放在“代码 › 代码底色”上 | 4.42:1 | 4.5:1 |
| “代码高亮 › 内置的名字”放在“代码 › 代码底色”上 | 2.91:1 | 4.5:1 |
| “代码高亮 › 名字（定义处）”放在“代码 › 代码底色”上 | 3.68:1 | 4.5:1 |
| “代码高亮 › 变量”放在“代码 › 代码底色”上 | 4.42:1 | 4.5:1 |
| “代码高亮 › 正则”放在“代码 › 代码底色”上 | 2.91:1 | 4.5:1 |
| “代码高亮 › 字符串里的插值”放在“代码 › 代码底色”上 | 3.33:1 | 4.5:1 |
| “代码高亮 › 符号”放在“代码 › 代码底色”上 | 3.68:1 | 4.5:1 |
| “代码高亮 › 元信息（注解、预处理）”放在“代码 › 代码底色”上 | 3.68:1 | 4.5:1 |
| “代码高亮 › 标签名”放在“代码 › 代码底色”上 | 3.33:1 | 4.5:1 |
| “代码高亮 › 属性”放在“代码 › 代码底色”上 | 4.42:1 | 4.5:1 |
| “代码高亮 › 属性名（CSS、配置）”放在“代码 › 代码底色”上 | 2.91:1 | 4.5:1 |
| “代码高亮 › 选择器：标签”放在“代码 › 代码底色”上 | 3.33:1 | 4.5:1 |
| “代码高亮 › 选择器：#id”放在“代码 › 代码底色”上 | 3.68:1 | 4.5:1 |
| “代码高亮 › 选择器：.class”放在“代码 › 代码底色”上 | 4.42:1 | 4.5:1 |
| “代码高亮 › 选择器：[属性]”放在“代码 › 代码底色”上 | 4.42:1 | 4.5:1 |
| “代码高亮 › 选择器：伪类”放在“代码 › 代码底色”上 | 4.42:1 | 4.5:1 |
| “代码高亮 › 模板变量”放在“代码 › 代码底色”上 | 4.42:1 | 4.5:1 |
| “代码高亮 › 标题”放在“代码 › 代码底色”上 | 3.33:1 | 4.5:1 |
| “代码高亮 › 列表符号”放在“代码 › 代码底色”上 | 3.68:1 | 4.5:1 |
| “代码高亮 › 引用”放在“代码 › 代码底色”上 | 2.34:1 | 4.5:1 |
| “代码高亮 › 链接”放在“代码 › 代码底色”上 | 3.68:1 | 4.5:1 |
| “代码高亮 › 新增（diff）”放在“代码 › 代码底色”上 | 2.91:1 | 4.5:1 |
| “代码高亮 › 删除（diff）”放在“代码 › 代码底色”上 | 3.33:1 | 4.5:1 |
| “积木 › 选中描边”放在“积木 › 画布底色”上 | 1.43:1 | 3:1 |
| “积木 › 警告标记”放在“积木 › 画布底色”上 | 1.94:1 | 3:1 |

默认深色（5 项）：

| 哪一对 | 实际 | 要求 |
| --- | --- | --- |
| “界面 › 占用条：对话消息”放在“界面 › 卡片 / 面板”上 | 2.89:1 | 3:1 |
| “代码高亮 › 注释”放在“代码 › 代码底色”上 | 2.86:1 | 4.5:1 |
| “代码高亮 › 引用”放在“代码 › 代码底色”上 | 2.86:1 | 4.5:1 |
| “终端 › 黑”放在“终端 › 底色”上 | 1.52:1 | 3:1 |
| “积木 › 报错标记上的符号”放在“积木 › 报错标记”上 | 2.78:1 | 3:1 |

说明：浅色那 27 项高亮是 Atom One Light 配色本身偏淡（它原本配的是更白的底）；占用条的色块是装饰，旁边有文字图例；
终端 16 色里的“黑”在深色底上本来就贴近底色；积木画布上的选中描边、警告标记靠形状也认得出。
最要紧的几对——正文、次要文字、按钮上的字、代码文字、终端文字、关键字、积木上的字——两套默认都达标。

## 六、背景图（由背景图那一步补细节）

这一步只留了位置，没有做任何背景图的界面和存储：

- **主题本身不带图。** 背景图是独立的全局外观设置（另一位在做，存在外观设置里）。
- 导出文件里可以选择性附带一张图：`background` 一节的结构见上面第四节；模型是 `ThemeBackground`（`mime`、`bytes`、
  `cropX/Y/W/H` 占原图的比例、`dim` 0–1、`blur` 0–40）。`ThemesNotifier.exportText(id, background: …)` 带上，
  `importText` 读到后**原样交回**（`ThemeOpResult.background`），不落盘——存到哪、要不要启用由背景图那边决定。
- 主题里给背景图留的三项：`ui.backdropScrim`（盖在图上、内容下面的遮罩色，带透明度）、`metrics.surfaceOpacity`
  （有图时卡片的不透明度）、`ui.scrim`。前两项现在没有地方用。
- `crop` / `dim` / `blur` 这几个字段是我按常见做法先定的，**背景图那边如果需要别的字段（比如对齐方式、平铺），可以在第 1 版里加**：
  读的时候不认识的字段会被跳过，不会让旧文件读不了。

## 七、给后续开发者：怎么用

### 怎么加一套内置主题

1. 在 `lib/appearance/theme_builtin.dart` 里新写一个 `ThemeSpec`（文件头有步骤说明）。最省事的写法是从默认主题改：
   `kDefaultDarkTheme.copyWith(id: 'ocean-dark', name: '深海').withColors('ui', {…}).withColors('blocks', {…}).withToken('keyword', …)`。
2. 把它加进 `kBuiltinThemes`。标识不能和别的重复，`builtin` 要是 `true`。
3. 跑 `test/theme_defaults_pin_test.dart`（每一节的键齐不齐）和 `test/theme_contrast_test.dart`（对比度）。新主题不达标就改颜色，
   不要往 `kKnownContrastGaps` 里加。
4. 别的什么都不用改：设置里的列表、选用、导出都是照 `kBuiltinThemes` 走的。

### 怎么取色（写界面时）

| 要什么 | 怎么取 |
| --- | --- |
| 界面色 | `final c = context.colors;` 然后 `c.accent`、`c.bubbleMineBg`、`c.navActive`…（45 项都有具名字段） |
| 阴影 / 遮罩 | `c.shadowOf(0.12)`、`c.scrimOf(0.2)`（参数是透明度） |
| 圆角 / 间距 / 细线（要跟着主题变时） | `c.radius(Radii.md)`、`c.space(Space.x4)`、`c.hairline` |
| 当前主题本身 | `context.themeSpec` |
| 代码区域 | `context.themeSpec.codeColor(CodeKey.bg)` |
| 代码高亮表 | `codeThemeFor(theme: context.themeSpec)`；一段代码上色 `highlightCode(代码, 语言, theme: …, base: …)` |
| 改动对比 | `DiffColors.of(context)` |
| 终端 | `context.themeSpec.terminalColor('red')`（键见 `kTerminalFields`） |
| 积木 | `BkKit.of(context).palette` 或 `BkPalette.fromTheme(context.themeSpec)`；一类的几档 `palette.tone('control')` |
| 低代码编辑器 | `context.themeSpec.lowcodeColor(LowcodeKey.selection)` |
| 不在应用主题里的地方（错误兜底页等） | `AppColors.resolve(context)`（拿不到就按明暗退回默认主题） |
| 测试、没有 context 的地方 | `AppColors.light / dark`、`BkPalette.of(dark:)`、`DiffColors.light / dark`、`codeThemeFor(dark:)`（都是默认主题的） |

主题里没有合适的项：在 `theme_fields.dart` 加一项（键、中文名、分组），在 `theme_builtin.dart` 给每套内置主题填值，
需要具名入口就在 `AppColors` 里加一个字段。**不要**在页面里写死颜色——`test/theme_guard_test.dart` 会拦。

### 状态（`lib/state/themes_state.dart`）

- `themesProvider` → `ThemesView`：`builtin`、`user`、`all`、`byId(id)`、`choices(dark:)`、`lightId` / `darkId`、`light` / `dark`（已经处理了回退）。
- `ThemesNotifier`（`ref.read(themesProvider.notifier)`）：

| 方法 | 做什么 | 返回 |
| --- | --- | --- |
| `list(dark:)` | 某种明暗下能选的主题（内置在前） | `List<ThemeSpec>` |
| `select(id)` | 选用（按主题自己的明暗进对应的槽） | 失败原因或 `null` |
| `create(dark:, name:)` | 新建：从同明暗的默认主题复制一份 | `ThemeOpResult` |
| `duplicate(id, name:)` | 复制一份来改（内置主题要改就走这个） | `ThemeOpResult` |
| `save(主题)` | 保存改动（只能存用户主题；标识和明暗不许变；会过一遍和导入相同的校验） | 失败原因或 `null` |
| `rename(id, 名字)` | 改名（不许和别的主题重名） | 失败原因或 `null` |
| `delete(id)` | 删除；正在用的被删，那个槽退回默认 | 失败原因或 `null` |
| `importText(文本)` | 导入：校验过了才落盘，永远当新的存，不自动选用 | `ThemeOpResult`（含 `background`、`notes`） |
| `exportText(id, background:)` | 导出成文本 | 文本或 `null` |

- `lightThemeProvider` / `darkThemeProvider`：两个槽里生效的主题，只有那一套真的换了 / 改了才通知。`lib/app.dart` 订阅的就是这两个。
- `activeThemeProvider(系统是不是深色)`：现在生效的那一套（按外观模式三选一算）。
- 编辑器做实时预览的建议：编辑时每改一下就 `save`（文件很小），正在用的主题一存，全应用立刻跟着变；
  `ThemeData` 按主题对象缓存，同一份主题不会重算。

### 读写和检查（纯函数）

- `encodeThemeText(主题, background:)` / `encodeTheme(…)`：写。
- `decodeThemeText(文本)` / `decodeThemeJson(对象)` → `ThemeDecodeResult`（`ok`、`theme`、`error`、`notes`、`background`）：读 + 校验。
- `parseThemeColor('#RRGGBB')`、`formatThemeColor(整数)`、`isValidThemeId(id)`。
- `checkThemeContrast(主题)`、`unexpectedContrastIssues(主题)`（去掉已知例外后的）、`contrastRatio(前景, 背景)`。
- 改主题：`主题.withColors('ui', {键: 颜色})`、`.withToken('keyword', TokenStyle(…))`、`.withMetric(MetricKey.radiusScale, 1.5)`、`.copyWith(name: …)`。

### 兼容入口（没删，免得别的分支和几十个测试要跟着改）

- `buildAppTheme(Brightness, {fontFamily})`：还在，等于“用默认主题调 `buildThemeData`”。真正吃主题的是 `buildThemeData(ThemeSpec, {fontFamily})`。
- `AppColors.light / dark`、`DiffColors.light / dark`、`BkPalette.of(dark:)` / `.light` / `.darkTheme`、`codeThemeFor(dark:)`、
  `highlightCode(…, dark:)`、`contextSegmentsOf(…, dark:)`：都还在，给的是默认主题的值。**界面里不要用这些**，用上面“怎么取色”的写法，
  否则换了主题那一处不会跟着变。

## 八、守着默认外观的测试

- `test/theme_defaults_pin_test.dart`：把改之前的值当字面量抄进测试，逐项比对——旧 `AppColors.light / dark` 17 项、新加语义项
  替换掉的那些旧值、提示条和 on-error、终端 16 色和前景 / 背景 / 光标 / 选区、代码区域、改动对比、Atom One 高亮表 30 类、
  积木 20 类 × 10 档 × 浅深、低代码 21 项、6 个倍率。
- 截图逐张比对：见这一步的汇报。
- **一个要知道的细节**：默认深色的积木主色原来是“浅色主色压暗”现算出来的带小数的值，主题里存的是取整后的整数。
  直接用整数去算其余几档，个别档会差 1/255。所以 `block_colors.dart` 里做了处理：主题里某一类的主色还等于默认深色的值时，
  用原来没取整的数接着算（和原来逐位一样）；改过了就用主题里的值。

## 九、守门测试

`test/theme_guard_test.dart`：`lib/` 下不许出现 `Color(0x…)`、`Colors.某色`、`Color.fromARGB / fromRGBO`、`Palette.某色`。

- 整份放行：`lib/appearance/` 下 5 个定义文件、`lib/theme/tokens.dart`、`lib/theme/app_theme.dart`。
- 全局放行：`Colors.transparent`（表示“这里不画底”，不是一种颜色选择）。
- 逐条登记的例外（每条写了原因；那一行没了测试会提醒删掉）：
  - `lib/blocks/block_colors.dart` 3 处：算几档颜色时“往白里混 / 往黑里混”的参照、降饱和时算出来的灰（是算法不是配色）。
  - `lib/lowcode/canvas_render_widgets.dart` 7 处：用户页面内容的默认色（页面白底、默认文字色、Material 种子色、卡片默认阴影、图片占位）。
  - `lib/lowcode/export_dart.dart` 3 处：生成的 Flutter 代码文本。
  - `lib/lowcode/props_sheet.dart` 1 处：把用户填的颜色文本变成颜色。
  - `lib/lowcode/style_color_sheet.dart` 4 处：取色器的明度条（黑到白）、透明棋盘格、滑块圆点。
  - `lib/ui/preview_tab.dart` 1 处：网页预览的白底（网页没写背景时浏览器就是白的）。

## 十、主题编辑器与导入导出界面（2026-11-26）

### 页面结构（都在 `lib/ui/`）

| 页面 / 面板 | 文件 | 从哪进 | 做什么 |
| --- | --- | --- | --- |
| 外观页〔主题〕一组 | `settings_theme.dart` | 设置 › 界面 › 外观 | 三行：浅色主题、深色主题（快速选，原来就有）、管理主题 |
| 背景图挂载点 | `appearance_background_entry.dart` | 外观页，〔主题〕和〔代码字号〕之间 | `buildAppearanceBackgroundEntry` 返回 null＝不显示；接背景图时只改这一行 |
| 管理主题 | `themes_screen.dart` | 外观 › 管理主题 | 浅色 / 深色两段；一张卡一套（小样子、名字、内置 / 我的、正在使用）；点卡片选用；新建、导入；“⋯”里是编辑、改名、复制、导出、删除 |
| 主题编辑器 | `theme_editor_screen.dart`（行在 `theme_editor_rows.dart`） | 管理主题 › ⋯ › 编辑；新建后直接进 | 顶上固定预览 + 列表；见下 |
| 四种预览 | `theme_preview.dart` | 编辑器、导入预览 | 界面 / 代码 / 积木 / 终端，用传进去的那份主题画，不碰全应用 |
| 取色面板 | `theme_color_sheet.dart`（芯在 `theme_color_picker.dart`） | 编辑器里点一个颜色行 | 饱和×明度方块、色相条、透明度条、十六进制、三组色块、恢复默认值、对比度 |
| 快捷生成 | `theme_generate_sheet.dart` | 编辑器列表最上面两行，或“⋯” | 换强调色 / 从主色生成整套 |
| 导出 | `theme_export_sheet.dart` | 管理主题 › ⋯ › 导出 | 复制到剪贴板、存到工作区 `exports/` |
| 导入、导入预览 | `theme_import_screen.dart` | 管理主题 › 导入主题 | 粘贴 / 从工作区选文件 → 检查 → 预览 → 加入 |

不带界面的那一半在 `lib/appearance/`：`theme_color_math.dart`（颜色换算、宽松的颜色写法）、`theme_edit_model.dart`（可改项清单、改过哪些、撤销重做）、
`theme_generate.dart`（下面的算法）、`theme_export_file.dart`（导出落盘）。状态只加了 `lib/state/theme_hooks.dart`（背景图对接口、最近用过的颜色）。

### 编辑器的规矩

- **预览用草稿画，保存后才生效。** 编辑器手里是一份 `ThemeHistory`（起点、现在、撤销 / 重做各一摞，最多 100 步，不可变）。
  预览、每一行的色块都读“现在”；全应用读的是主题库里存着的那份，点“保存”（`ThemesNotifier.save`）才换。没有“应用看看”：
  要先看全应用的效果就保存，不满意再撤销、再保存。
- 列表一行一项、行高一律 56（`kThemeRowHeight`），所以“跳到某一项”直接算位置，191 项也只排看得见的几行。
  分组：快捷生成（2 行动作）、形状与密度 6、界面 45、代码 12、代码高亮 55、终端 23、积木 35、低代码编辑器 21。默认只展开“界面”。
- 搜索按名字、说明、分组小标题、所在的节、键名找；“改过的”只留和起点不一样的项。两个筛选开着时所有组摊开。
- 取色面板开着的这一段、快捷生成面板开着的这一段，在撤销里各算一步（`ThemeHistory.apply` 的 `tag`）。
- 高亮分类可以“不单独上色”（跟着代码文字的颜色），可以开关粗体 / 斜体。
- 能带透明度的项：两套默认主题里它本来就是半透明的，或者说明里写了“带透明度”（`itemAllowsAlpha`）。别的项写了透明度也按不透明的用，并说明。
- “恢复默认值”＝同明暗默认主题里这一项的值。“全部恢复为起点”＝回到这次打开（或上次保存）时的样子，这一步也能撤销。
- 改名立刻存（`ThemesNotifier.rename`），不把没保存的颜色带进去，也不进撤销历史。
- 有没保存的改动时离开要问：保存并离开 / 不保存 / 继续编辑。
- 内置主题进来是只读：能看每一项，改不了；顶上有“复制一份来改”，点了换成副本的编辑器。
- 对比度：每次改动都重跑 `checkThemeContrast`。不达标的检查里“字”那一项的行旁边有记号；顶上“N 项对比度偏低”点开是列表，
  点一条跳到那一项；列表底下有“自动调到达标”（`repairContrast`）。**只提示，不拦保存。**
  注意：默认浅色主题自己有 31 项已知缺口（第五节），所以从它复制出来的主题一打开就会提示 31 项。

### 颜色选择器

- HSV：一块“饱和（横）× 明度（纵）”的方块（高 132）+ 一根色相条 + 一根透明度条（可拖区域高 36，按下就跟手）。选它是因为手机上拖一个面比拖三根条顺手。
- 颜色拖成灰 / 黑以后色相算不出来，面板自己记着色相，把手不乱跳；在灰色上拖色相会给 0.5 的饱和 / 明度，让它真的变色。
- 十六进制输入容错（`parseLooseColor`）：`#RGB`、`#RRGGBB`、`#AARRGGBB`，井号可以不写、可以是全角 `＃`，前后空格、`0x` 开头、`rgb(…)` / `rgba(…)` 都认。
  看不懂时在框下面说一句，不动颜色、不清她打的字。
- 色块三组：主题里已有的（按用得多少排，最多 16 个，不看透明度）、常用色（16 个：一排灰阶一排彩色）、最近用过（最多 12 个，
  存在设置键 `ui.themeRecentColors`，跨主题、跨次打开都记着；关面板时记最后定下来的那个颜色）。
- 面板上方写这一项和它最吃紧的那个搭档的对比度（数值、达标 / 偏低、至少多少）。

### 快捷生成的算法（`lib/appearance/theme_generate.dart`）

**换强调色** `reaccentTheme(主题, 新强调色)`：
1. 实心按钮底＝新强调色本身；上面的字取黑白里对比度高的；还不到 4.5:1 就只挪按钮底的亮度（色相不变）直到够。
2. 强调色浅底＝新强调色混进卡片色：浅色主题混 12%，深色主题混 28%（`kAccentSoftMixLight` / `Dark`）。选中项的底同它。
3. 强调色（文字、图标）＝新强调色只调亮度，直到在主页面底色、卡片、浅底三种底上都 ≥ 4.5:1。
4. 界面、代码、终端、低代码编辑器四节里，凡是原来和旧强调色 / 旧实心底 / 旧浅底 / 旧选中底同色（不看透明度）的项跟着换成对应的新颜色，
   各自的透明度不变。这样开关、光标、选区、导航选中这些“借用强调色”的地方一起走，别的颜色不动。积木不动（积木的颜色是分类的意思）。

**从主色生成整套** `generateTheme(明暗, 底色倾向, 强调色, 外壳)`：
1. 拿同明暗的默认主题当骨架——深浅关系（谁比谁亮多少）是调好的，不重新发明。标识、名字、作者、6 个数用外壳（正在编辑的那套）的。
2. 骨架里的“中性色”（HSL 饱和度 < 0.25，或者近黑近白）亮度不动，色相换成底色倾向的色相，饱和度＝底色倾向自己的鲜艳程度（HSV 饱和）
   × 一个按亮度分的系数：很亮的 0.55、很暗的 0.35、中间的 0.2（`kTintOnLight` / `Dark` / `Mid`）。所以选灰色当底色倾向＝不染色。
   不染的：遮罩、阴影、实心按钮和危险按钮上的字、低代码编辑器整节、积木里除了画布和画布点阵以外的全部（积木分类色、状态色保持原样好认）。
3. 用上面的“换强调色”把强调色这一组换掉。
4. 跑一遍“调到达标”，保证算出来的初稿没有新的对比度问题。

**调到达标** `repairContrast(主题)`：对每个不达标的检查，只动“字”那一项的亮度（色相、饱和不变），而且要让它在自己出现的每一种底上都够
（免得修好一对弄坏另一对）；积木上的字是所有分类共用的，所以这几对改成动分类主色。半透明的颜色不动。最多四轮。调不动的留着，如实报还剩几项。

### 导出

- 文本就是第四节的格式（`encodeTheme`，两格缩进）；导出时 `builtin` 一律按 false 写（内置主题导出去也是一套普通主题）。
- 两个去处：复制到剪贴板；存成文件——工作区的 `exports/主题-〈名字〉-YYYYMMDD-HHMMSS.lopitheme.json`（和“整段对话导出”“消息存成文件”同一个目录，
  在“文件”页能看到；同一秒重名加 `-2`、`-3`，不盖掉上一份；名字里不能进文件名的字符去掉，最多 24 个字）。
  现在开着工作区就存它里面；没开着就从工作区列表里挑一个（只有一个就直接用）；一个工作区都没有时只能复制，并说明原因。
- 面板上写大小；存好以后写存在哪个工作区的哪个路径。一套主题不带图约 12–14 KB。
- “附带背景图”只在 `themeBackgroundBridgeProvider` 不是 null 且 `hasImage()` 为真时出现。打开后向背景图那边要一个 `background` 对象并进文本；
  带上以后超过 12MB（`kThemeImportMaxBytes`，导入能收的上限）就不带并说明；取不出来也说明原因。
- 不调系统分享面板，不加插件，不联网。

### 导入

- 两条路：粘贴文本（有“从剪贴板粘贴”按钮）；从工作区文件里选（和 @ 文件同一套扫描 `scanMentionFiles`，只列 `.json`，`.lopitheme.json` 排前面）。
  文件超过 12MB、不是文本、读不了，各有一句原因；从文件读进来的内容不塞进输入框，只显示一行“哪个文件、多大”。
- 检查就是地基的 `decodeThemeText`（严格校验，第四节）。没过就在输入框下面显示它给的那句话，不往下走。**只读数据，不执行任何东西，不联网。**
- 过了进“导入预览”：名字、作者、明暗、四种预览、对比度检查结果（都达标，或 N 项偏低 + 前 3 条，可展开）、检查时的提示（`notes`）、带没带背景图。
  三个按钮：加入并立即使用（`importText` + `select`）、加入我的主题（只 `importText`）、取消。加入时用原文再走一遍 `importText`（它自己再校验一遍、
  永远新建、重名自动改名）；改了名会在提示里说。加进来以后回到管理页，并切到那套所在的明暗段。
- 带背景图的文件：背景图那部分没接上时只说明“带了图，这个版本用不了”，照样加入颜色；接上了有一个勾选“同时使用附带的背景图”（默认勾），
  加入时把文件里 `background` 一节原样交给 `ThemeBackgroundBridge.import`，失败原因写进提示。

### 给合并的人

- 外观页的背景图入口：改 `lib/ui/appearance_background_entry.dart` 里 `buildAppearanceBackgroundEntry` 那一行，让它返回背景图的设置入口（一组 `SettingsGroup`）。
- “附带背景图”和导入时的图：改 `lib/state/theme_hooks.dart` 里 `themeBackgroundBridgeProvider` 那一行，返回一个 `ThemeBackgroundBridge`
  （`hasImage`、`export` 返回可直接放进 `background` 一节的 Map、`import` 收文件里那一节的 Map）。
- 新增内置主题不用改这里任何东西：管理页、“新建主题从哪套开始”、编辑器都从 `themesProvider` 和字段目录读。

### 这一节里自己定的数

| 数 | 值 | 在哪 |
| --- | --- | --- |
| 预览块高度 | 232 | `kThemePreviewHeight` |
| 列表行高 | 56 | `kThemeRowHeight` |
| 撤销最多几步 | 100 | `ThemeHistory.maxSteps` |
| 数值每步 | 圆角 0.1、阴影 0.1、分隔线 0.5、其余 0.05 | `metricStep` |
| 取色面板最高占屏 | 60% | `theme_color_sheet.dart` |
| 方块高 / 条的可拖高度 / 色块边长 | 132 / 36 / 36 | `theme_color_picker.dart` |
| 主题里已有的颜色最多列 | 16 | `kThemeOwnColorsMax` |
| 常用色 | 16 个 | `kThemeCommonColors` |
| 最近用过最多记 | 12 | `kRecentColorsMax` |
| 强调色浅底混多少 | 浅 12%、深 28% | `kAccentSoftMixLight` / `Dark` |
| 算不算中性色的饱和度线 | 0.25 | `kNeutralSaturation` |
| 底色倾向的染色系数 | 亮 0.55、暗 0.35、中 0.2 | `kTintOnLight` / `Dark` / `Mid` |
| 调到达标最多几轮 | 4 | `repairContrast` |
| 导出文件名里名字最多 | 24 个字 | `themeFileStem` |
| 导入预览先列几条对比度问题 | 3 | `theme_import_screen.dart` |
