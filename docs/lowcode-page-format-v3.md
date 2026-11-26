# 页面文件格式第 3 版（page.lc.json）

2026-11-26，编辑器第 3 期（B1）定。霜霜同意的升版：**只升这一次**，把第 3–6 期要用的字段一次设计好。
代码：`lib/lowcode/model.dart`（文档、节点）、`lib/lowcode/model_props.dart`（props 的读法）、`lib/lowcode/component_model.dart`（组件定义）。

## 一句话

页面还是“一棵组件树存成一个 JSON 文件”。第 3 版比第 2 版多了三样东西：

1. 节点能起**名字**、能**锁定**、能**只在编辑器里隐藏**；按钮、图片、输入框多了几个属性。
2. 给后面几期（新组件、状态样式、多页面、主题、断点、绑定、重复、显示条件、插槽）**留好了字段名和结构**，这一版先不解释它们。
3. 一条新规矩：**看不懂的东西一律原样留着**。不认识的字段、不认识的属性、不认识的组件类型，打开不报错，存盘时照原样写回去。

## 四条规矩

| 规矩 | 怎么做到的 |
|---|---|
| 老文件照常打开 | 第 1 版（没有 `version` 或写着 1）、第 2 版的文件都直接读；读出来的样子、导出的结果和以前一个字节都不差（`test/lowcode_export_baseline_test.dart` 钉着）。 |
| 只打开不改，不许悄悄改写文件 | 编辑器只在“有改动”时才存盘（`BuilderScreen._apply` → 停手 0.4 秒存）；打开、选中、平移、缩放、开关面板都不写文件（`test/lowcode_page_format_pin_test.dart` 钉着）。 |
| 改动后保存才成为第 3 版，而且不丢东西 | 存盘永远写当前版本号。老代码存盘时会**丢掉**它看不懂的属性（比如第 1 版样例里的 `weight`、`variant`）；现在这些挪到节点的 `oldProps` 里留着。 |
| 读到比自己新的版本要明说 | `version` 大于 3：`LcDocument.isFromNewer` 为真，编辑器顶上出一条提示“这个页面是新版做的…”；存盘时**版本号不往回写**，看不懂的照样留着。 |

## 最外层

字段顺序固定：`version`、`title`、`root`、`logic`、`components`，然后是别的字段（按文件里原来的顺序）。空的不写。

| 字段 | 这一版 | 说明 |
|---|---|---|
| `version` | 用 | 整数。存盘写 3（文件本来比 3 大就写原来的数）。没写＝第 1 版。 |
| `title` | 用 | 页面标题。 |
| `root` | 用 | 根节点，`type` 必须是 `page`。 |
| `logic` | 用 | 页面逻辑（变量、事件处理），结构没变，见 `docs/lowcode-v2-design.md`。 |
| `components` | 用 | 自定义组件的定义，见下面。读不出来的定义原样留着（排在读得出来的后面）。 |
| `pages` | 留给第 4 期 | 多页面：除了第一页以外的页面，`[{id, title, root, logic?}]`。**第一页永远是最外层的 `title` / `root` / `logic`**，这样老版本应用至少能打开第一页。 |
| `theme` | 留给第 4 期 | 项目级主题变量：`{"vars": {"color-primary": "#058654", "radius-md": "8px", …}}`；节点的 `style` 里用 `var(--color-primary)` 引用（`style` 的值本来就允许写 `var()`）。 |
| 其他 | 原样留着 | 不解释。 |

断点不存进文件：固定三档——默认（手机）、平板 ≥768、桌面 ≥1024。

## 节点

字段顺序固定：`id`、`type`、`name`、`locked`、`hidden`、`props`、`style`、`bind`、（别的字段，按原来的顺序）、`children`。空的、假的不写。

| 字段 | 这一版 | 说明 |
|---|---|---|
| `id` | 用 | 页面里唯一；缺了、重了自动补 `n数字`。 |
| `type` | 用 | 组件类型，见下面“组件类型”。不认识的类型：整个节点（连它的子节点）原样留着，画布上是一块“新版组件”占位，导出时留一行注释。 |
| `name` | 用（新） | 用户起的名字，最长 40 字。图层面板显示它；没起名显示“类型 · 文字”。 |
| `locked` | 用（新） | `true`＝锁定：画布上点不中、拖不动（图层面板里能选、能解锁）。只管这个节点自己，它里面的东西照常能点。 |
| `hidden` | 用（新） | `true`＝**只在编辑器里**不画。**不影响导出**。和“样式里的隐藏”（`style` 的 `display: none`，导出后真的看不见）是两回事。 |
| `props` | 用 | 简写属性，见下面。看不懂的键、值不合规矩的键：不生效，原样留着。 |
| `style` | 用 | 这个组件自己的 CSS 声明（第 2 版就有）。 |
| `bind` | 用 | 只在组件定义里用：属性 → 组件 prop 名（第 2 版就有）。 |
| `children` | 用 | 子节点；只有容器类能有。 |
| `oldProps` | 用（新） | 第 1、2 版文件里多出来的属性（当时不算数、老代码存盘会丢）。**永远不解释**，只是留着不丢。 |
| `states` | 留给第 3 期后段 | 状态样式，只存和平时的差别：`{"pressed": {css 声明}, "disabled": {…}, "focused": {…}}`，导出成 `:active` / `:disabled` / `:focus`。 |
| `responsive` | 留给第 4 期 | 断点上的差别：`{"tablet": {"style": {…}, "props": {…}}, "desktop": {…}}`。 |
| `data` | 留给第 5 期 | 绑定：属性 → 值的来源。来源三种：`{"from": "const", "value": …}`、`{"from": "var", "name": "变量名"}`、`{"from": "expr", "expr": 积木式子}`。 |
| `repeat` | 留给第 5 期 | 重复：`{"list": 来源, "item": "这一项的名字", "index": "序号的名字", "key": 来源, "empty": [空的时候显示的节点], "preview": 画布上画几个}`。 |
| `showIf` | 留给第 5 期 | 显示条件：一个来源（真才显示）。 |
| `slot` | 留给 B2 / B3 | 这个节点放进父节点的哪个插槽（插槽名）；不写＝默认插槽。 |
| 其他 | 原样留着 | 不解释。 |

### props（简写属性）

第 1、2 版就有的（规矩没变）：`width`（数字或 `"fill"`）、`height`、`padding`、`margin`、`radius`、`gap`、`fontSize`、`size`（数字 ≥0）；
`bg`、`color`（`#RRGGBB`）；`align`、`justify`、`textAlign`；`text`、`src`、`placeholder`（字符串）；`bold`（布尔）；`items`（字符串数组）；`ref`、`values`（只有 `component` 用）。

第 3 版加的（**只在第 3 版的文件里算数**；老文件里同名的键进 `oldProps`，不会突然生效）：

| 键 | 谁用 | 值 | 导出成什么 |
|---|---|---|---|
| `icon` | 按钮 | 内置图标的名字（`lib/lowcode/icon_set.dart`，25 个，名字同 Material Icons） | 网页 / Vue / React：按钮里一个内嵌 SVG；Flutter：`FilledButton.icon` |
| `disabled` | 按钮、输入框 | 布尔 | `disabled` 属性；Flutter：`onPressed: null` / `enabled: false` |
| `alt` | 图片 | 字符串（说明文字，给读屏和图片加载失败时用） | `alt="…"`；占位块的 `aria-label`；Flutter：`semanticLabel` |
| `inputType` | 输入框 | `text` / `password` / `number` / `email` / `tel`（不写＝文字） | `type="…"`；Flutter：`obscureText` / `keyboardType` |
| `value` | 输入框 | 字符串（默认值） | `value="…"`（React 是 `defaultValue`）；Flutter：`TextFormField(initialValue:)` |
| `label` | 输入框 | 字符串（输入框上面的标签） | 外面包一层 `<label class="lc-field">`；Flutter：`labelText` |
| `required` | 输入框 | 布尔 | `required` 属性，标签后面加 ` *` |

页面没用到这些键时，导出一个字节都不多。

## 组件类型

这一版认识的（13 个，和第 2 版一样）：`page`、`container`、`row`、`column`、`card`、`text`、`button`、`image`、`input`、`list`、`divider`、`spacer`、`component`。

**留给 B2 的 11 个新组件**（类型名和属性名在这里定死；B2 只要把它们登记进 `lcSpecs` 和 `model_props.dart`，不用再动格式——
在那之前它们是“不认识的类型”，原样留着）：

| 类型 | 中文 | props | 插槽（子节点的 `slot`） | 样子 `props.variant` |
|---|---|---|---|---|
| `icon` | 图标 | `icon`（名字）、`size`、`color` | — | — |
| `textarea` | 多行输入 | `value`、`placeholder`、`rows`（数字）、`maxLength`（数字）、`autoGrow`（布尔）、`label`、`required`、`disabled` | — | — |
| `switch` | 开关 | `checked`（布尔）、`disabled` | — | — |
| `checkbox` | 勾选框 | `checked`、`text`、`disabled` | — | — |
| `radio` | 单选组 | `value`（选中的值）、`options`（`[{"value": "a", "label": "甲"}]`）、`direction`（`row` / `column`）、`disabled` | — | `dot` 圆点 / `button` 按钮式 |
| `select` | 下拉选择 | `value`、`options`（同上）、`placeholder`、`disabled` | — | — |
| `listItem` | 列表行 | `title`、`subtitle`、`trailing`（右侧文字）、`chevron`（布尔，右箭头） | `left`、`right` | `one` 单行 / `two` 两行 |
| `appBar` | 顶部导航栏 | `title`、`back`（布尔，显示返回）、`sticky`（布尔，固定在顶） | `left`、`right` | `left` 居左 / `center` 居中 |
| `bottomNav` | 底部导航栏 | `items`（`[{"icon": "home", "label": "首页", "page": "页面 id"}]`）、`current`（第几项，从 0 数） | — | `labeled` 有字 / `iconOnly` 只有图标 |
| `tabs` | 标签页 | `tabs`（`[{"id": "t1", "label": "页签"}]`）、`current`（页签 id） | 每个页签一个，插槽名＝页签 id | `underline` 下划线 / `pill` 胶囊 |
| `dialog` | 弹窗 | `open`（布尔）、`title`、`text`、`okText`、`cancelText`、`dismissible`（布尔，点外面能不能关） | `content`、`footer` | `alert` 提示 / `confirm` 确认 |

注意两处和现有键的关系：`items` 在 `list` 上是字符串数组，在 `bottomNav` 上是对象数组——`model_props.dart` 的读法是按类型分的（函数第一个参数就是类型），B2 登记时按类型判断即可；
`options` / `tabs` 这种对象数组，值的规矩由 B2 写进 `_clean`。

**留给 B3 的**：

| 东西 | 结构 |
|---|---|
| 插槽占位（只在组件定义里） | 节点 `{"type": "slot", "props": {"name": "插槽名"}, "children": [默认内容]}`；`name` 不写＝默认插槽。 |
| 往实例的插槽里放东西 | 实例节点（`type: "component"`）可以有 `children`，每个子节点用 `slot` 说明进哪个插槽。 |

## 组件定义（`components` 里的每一项）

字段顺序：`id`、`name`、`props`、`root`，然后是别的字段。

| 字段 | 这一版 | 说明 |
|---|---|---|
| `id`、`name`、`root` | 用 | 和第 2 版一样。`root` 是不认识的类型时整个定义原样留着（界面里看不到它）。 |
| `props` | 用 | `[{name, type, default}]`，`type` 这一版认 `text` / `number` / `color` / `bool`。类型不认识的那一项原样留着（以前会被当成文字硬读，现在不会了）。 |
| `props[].type` 的新值 | 留给第 6 期 | `option`（另带 `options`）、`image`、`list`、`record`、`any`。 |
| `slots` | 留给 B3 | `[{"name": "插槽名", "label": "给人看的名字"}]`；默认插槽的 `name` 是 `default`。 |
| `events` | 留给第 6 期 | 组件对外发的事件：`[{"name": "tap", "label": "点了", "params": [{name, type}]}]`。 |
| `variants` | 留给第 6 期 | 变体：`[{"name": "大号", "props": {…}, "style": {…}}]`。 |
| `state`、`logic` | 留给第 6 期 | 组件自己的变量和逻辑，结构同页面的 `logic.variables` / `logic`。 |
| 其他 | 原样留着 | 不解释。 |

## 第 1、2 版怎么读成第 3 版

| 老文件里的东西 | 读进来 | 存出去 |
|---|---|---|
| 没有 `version` / `version: 1` / `version: 2` | 记下原来的版本（`LcDocument.fileVersion`） | `version: 3` |
| 认识的属性、`style`、`bind`、`logic`、`components` | 和以前完全一样 | 和以前完全一样 |
| 不认识的属性（如 `weight`、`variant`、实例上的 `title`） | 不生效（和以前一样） | 以前：丢掉。现在：留在这个节点的 `oldProps` 里 |
| 碰巧和第 3 版新属性同名的键（如第 1 版样例里输入框的 `label`） | **不生效**（不然老页面的样子和导出会变） | 留在 `oldProps` 里 |
| 节点上别的字段 | 不解释 | 原样留着 |
| 不认识的组件类型 | 以前：整页打不开（报“未知的组件类型”）。现在：能打开，那一块是占位 | 原样留着 |

Agent 用 `lowcode_update_page` 写页面时没写 `version` 的，按第 3 版读（它写的是新内容，不是老文件）；文件里现有的、它没带回来的最外层字段（包括不认识的）沿用。 原来的文件要是比这一版新（版本号更大），版本号不往回写，回话里会带上“这个页面是新版做的”那句（`lib/lowcode/newer_notice.dart`，和搭建页顶上那一条是同一句）。

## 改了哪些老断言

`test/lowcode_page_format_pin_test.dart` 里 5 处（老的基准文件 `*.saved.lc.json` 没动、没重新生成）：

1. `LcDocument.currentVersion` 是 2 → 是 3。
2. 第 1 版文件存出来 `version` 是 2 → 是 3。
3. “打开再存和 `.saved.lc.json` 一字不差” → 和新的 `.saved-v3.lc.json` 一字不差；另加一条：第 3 版存出来的去掉版本号和 `oldProps` 后，和老的 `.saved.lc.json` 一字不差。
4. 节点字段只许 `id / type / props / style / bind / children` → 多允许 `oldProps`。
5. 第 2 版文件经界面编辑后 `version` 是 2 → 是 3。

别处 2 处：`test/lowcode_v2_model_test.dart` 第 1 版文件存出来的版本号 2 → 3；`test/lowcode_test.dart`“坏输入被拒绝”里不认识的类型原来要报错，现在是读成“不认识的组件”原样留着（没写类型的还是报错）。

## 这一版自己定的数

- 名字最长 40 字。
- 内置图标 25 个，名字同 Material Icons（画布和 Flutter 导出用的就是 Flutter 自带的同名图标）。网页类导出里的 SVG 路径是照 Material Icons 的形状写的，**没有逐个和官方文件核对**（见 docs/api-notes.md）。
- 组件嵌套上限还是 24 层（没变）。
