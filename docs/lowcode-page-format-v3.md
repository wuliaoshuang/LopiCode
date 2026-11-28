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

## 第 3 期 B2 之后的补充说明（格式没动，只是把“留给 B2”的几处怎么用写清楚）

- 11 个新组件已经登记（`lib/lowcode/model_v3_components.dart` 的 `lcV3Specs`），不再读成“新版组件”占位。
- `slot`：内置的带插槽组件是 列表行（`left` / `right`）、顶部导航栏（`left` / `right`）、弹窗（`content` / `footer`）、标签页（每个页签的 `id` 就是插槽名）。
  子节点没写 `slot`、或者写了一个这个组件没有的名字：读的时候不改文件，画的时候算进“兜底插槽”（列表行 / 导航栏→`right`，弹窗→`content`，标签页→第一个页签）。
  编辑器插入 / 移动节点时会收拾：放进普通容器去掉 `slot`，放进带插槽的组件写上落到的那个插槽。
- 对象数组的规矩（`lcCleanV3`）：`options` 每项 `{value, label}`，`value` 不空、不重复、最长 80；`tabs` 每项 `{id, label}`，`id` 最长 24；`items`（底部导航）每项 `{icon, label, page?}`。
  上限 50 / 8 / 5。**整串都合规矩才算数**：有一项不对，这个属性按“没写”处理（文件里原样留着，不删）。
- `states`：`{"pressed" | "disabled" | "focused": {CSS 声明表}}`，只存和平时不一样的条目；别的状态名原样留着不解释。
- 网格没有新字段：就是 `style` 里的 `display: grid`、`grid-template-columns: repeat(N, 1fr)`、`column-gap`、`row-gap`，子节点 `style` 里的 `grid-column: span N`。
- “打开 / 关闭弹窗”没有新字段：是 `logic` 里一块普通的 `setProp` 积木（`node`＝弹窗 id、`prop`＝`visible`、`value`＝是 / 否）。

## 第 3 期 B3 之后的补充说明（格式没动，只是把“留给 B3”的几处怎么用写清楚）

- 插槽占位 `{"type": "slot"}` 已经登记，不再读成“新版组件”占位。它只在组件定义的树里有用；不能当定义的最外层（那样的定义读不成组件，原样留在文件里）。
  页面里出现它：不改文件，画布上标“插槽（只在组件里有用）”，导出时只留它里面的内容；从组件里复制出来粘贴进页面时自动去掉这一层。
- 插槽名（`props.name`）：不写＝默认插槽 `default`；写法 `^[A-Za-z][A-Za-z0-9_]{0,23}$`。给人看的名字用节点的 `name`（没起就是“默认插槽”/ 插槽名）。
  同一个定义里重名的占位：只有第一个算数（接内容）；编辑器写回定义时会给后面的自动换名。一个组件最多 8 个插槽（编辑器的限制，读文件不卡）。
- 定义的 `slots`：编辑器每次存盘按树里的占位节点重新算（顺序＝在树里出现的先后），`label` 取占位节点的 `name`。读的时候它只用来补“占位节点没起名字”时的显示名；
  树里已经没有的插槽，它那一项不再写回；读不懂的项原样留着。
- 实例的 `children`：每个子节点的 `slot` 说明进哪个插槽，不写＝默认插槽（定义没有默认插槽就进第一个）。
  定义里已经没有的插槽名、或者定义根本没有插槽：这些子节点留在文件里，画布不画、导出不出（Vue / React 导出记一条说明），图层面板里看得到、标着“没地方放”。
- 编辑器保证不悄悄丢：插槽改名时所有实例里的 `slot` 跟着改；“取消插槽”把各实例填的内容挪到那个实例后面；别的办法让一个“有人填着内容”的插槽消失会被拦下。

## 第 4 期 B1 之后的补充说明（多页面；版本号没动，只多了一个可选字段）

设计和理由在 `docs/blocks-v5-parts/E-editor-components.md` §10.6。

- `pages` 开始用了：除首页以外的页面，每项 `{id, title, root, logic?}`，先后就是页面的先后。首页还是最外层的 `title` / `root` / `logic`。
  页面对象上别的键不解释、原样留着。读不出来的项（不是对象、没有 `root`、`root` 不是页面、超过 30 页的）原样留着，排在读得出来的后面。
- **新加一个可选字段**：最外层的 `id`＝首页的页面 id。只有“不止一页”或“首页的 id 不是 `p1`”时才写；没写按 `p1`。
  老版本应用不认识它，会当成不认识的字段原样留着。**只有一页的文件存出来没有 `id`、没有 `pages`，和以前逐字节一样。**
- 页面 id：`^[A-Za-z0-9_]{1,24}$`，全文件不重复；编辑器发的是 `p数字`。缺了、写法不对、重了的，读的时候补新的。
- 节点 id 每页各自不重复（不同页可以有同名的节点）。逻辑里的 `target`、`node` 只在本页里找。
- 新积木 `goPage`：`{"op": "goPage", "args": {"page": "<页面 id>"}}`。底部导航项的 `page` 填的也是页面 id。
  指着不存在的页面：文件照存，校验报错误，导出时跳过。
- `components`、`theme` 是整个文件（项目）的，所有页面共用。
- 最多 30 页、页名最长 30 字（编辑器的限制）。
- 存盘时自动导出的网页：首页 `index.html` / `style.css` / `logic.js`，别的页 `page-<页面 id>.html` / `.css` / `.js`。

## 第 4 期 B2 之后的补充说明（主题变量、断点；版本号没动，用的是早就留好的两个字段）

设计和理由在 `docs/blocks-v5-parts/E-editor-components.md` §10.7。

- `theme`（最外层，整个项目共用）开始用了：`{"vars": {"<变量名>": "<值>"}, "labels": {"<变量名>": "<给人看的名字>"}}`。
  `labels` 是这次**新加的可选子字段**（没写就用内置的叫法或直接显示变量名）。`theme` 里别的键不解释、原样留着。
  **一个变量都没有的文件存出来没有 `theme`，和以前逐字节一样。**
- 变量名：`^[a-z][a-z0-9-]{0,39}$`。开头决定它是哪一类、在面板里出现在哪：`color-` 颜色、`font-` 字号、`space-` 间距、`radius-` 圆角，别的算“其它”。
  值：一段不含 `{ } ; < >` 和换行的文字，最长 500；可以再引用别的变量（最多套 6 层）。最多 60 个变量，给人看的名字最长 20 字（编辑器的限制）。
- 用变量：节点 `style`（以及 `states.<状态>`、`responsive.<档>.style`）里的值写 `var(--变量名)`，也可以带后备值 `var(--变量名, 后备)`。
  指着不存在的变量：文件照存；画布上有后备值用后备值，没有就当这条没写；导出原样写出去。
- `responsive`（节点上）开始用了：`{"tablet": {"style": {…}}, "desktop": {"style": {…}}}`。
  只解释这两档的 `style`；`props` 和别的档名不解释、原样留着。空了的档、空了的 `responsive` 存盘时去掉。
  **没在平板 / 桌面档改过样式的节点没有 `responsive`，存出来和以前逐字节一样。**
- 三档固定，手机优先：不带条件的＝手机（默认）；`tablet` 从 768 宽起算，`desktop` 从 1024 起算；平板的差别在桌面上也生效，桌面的再盖在上面。
  每档只存“和下面几层不一样的那几条”。按下 / 禁用 / 聚焦的样式（`states`）不分档。
- 存盘时自动导出的网页：用到变量的项目，每个页面的 css 开头多一段 `:root { --名: 值; }`；有断点差别的页面，css 最后多 `@media (min-width: 768px)` / `(min-width: 1024px)`。
  没用变量、没用断点的页面，导出的三个文件和以前逐字节一样。

## 第 5 期 B3 之后的补充说明（状态与数据绑定；版本号没动，只多了可选字段）

设计和理由在 `docs/blocks-v5-parts/E-editor-components.md` §10.8。**没用状态和绑定的文件，存出来和以前逐字节一样。**

- 最外层新增可选 `state`：项目级状态（所有页面共用）的数组，每项和 `logic.variables` 的一项同一个写法。读不懂的项原样留在后面；空了字段去掉。
- 状态的一项（界面上一律叫“状态”，字段名 `variables` 没改）：`{"name", "type", "initial"}`，`type` 现在可以是 `text` / `number` / `bool` / `list` / `record`（后两种是这次放开的，`initial` 是 JSON 数组 / 对象）。
  可选 `derived`：一个式子（值积木的存法）——有它就是派生值，`initial` 不用。名字规矩不变。
  页面级状态就是这一页的 `logic.variables`；页面里和项目级重名时，用页面自己的。
- 节点上的绑定字段（全部可缺省；写坏了的当没写，原样留着）：
  - `data`: `{"<属性名>": <来源>}` 文字和属性。来源是 `{"from":"var","name":"…","path":[…]}` 或 `{"from":"expr","expr":<式子>}`。
  - `showIf`: 来源。显示条件（不成立时看不见，东西还在）。
  - `renderIf`: 来源。存在条件（不成立时真的没有）。这次新加的可选字段。
  - `repeat`: `{"list": 来源, "item": "这一项的名字", "index": "第几个的名字", "key": 来源, "empty": "列表是空的时候的一句话", "preview": 画布先画几份}`。
    **和原来写的不一样**：`empty` 原写“节点数组”，实际做成一句文字。`preview` 1–5，缺省 3。
  - `classIf`: `[{"name": "类名", "when": 来源}]`。这次新加。
  - `styles`: `{"<CSS 属性名>": 来源}`。这次新加。
  - `model`: `"状态名"`。双向（只有输入框、多行输入、开关、勾选框、单选组、下拉认）。这次新加。
- 自己定的数：类名最长 48 个字符、重复里的名字最长 32 个字符；一层最多 64 个状态；式子最深 64 层；Flutter 导出重复最多展开 200 份。


## 第四轮 B1 之后的补充说明（底部导航跨页共用、“常用”页分屏宽；版本号没动，只多了可选字段）

设计和理由在 `docs/blocks-v5-parts/E-editor-components.md` §10.9。**没用这些的文件，存出来和以前逐字节一样。**

- 最外层新增可选 `shared`：`{"bottomNav": {"props": {…}, "style": {…}, "states": {…}, "responsive": {…}, "data": …}}`。
  这是跨页共用的那一条底部导航栏**唯一的一份**内容：`props`（导航项 `items`、样子 `variant`、颜色…，**不含** `current`）、`style`，
  以及 `states` / `responsive` / `data` / `showIf` / `renderIf` / `classIf` / `styles`（有才写）。`shared` 里别的键不解释、原样留着。
  `shared.bottomNav` 不是对象、或它的 `props` 不是对象：整个当看不懂，原样留着。
- 节点新增可选 `shared: true`（只有 `bottomNav` 认）：这个节点显示的是共用的那一条。文件里它**只写自己的记号**（`id`、`type`、`name`、`locked`、`hidden`、`shared`、`slot`），
  不写 `props` / `style` / `states` 这些——读的时候从最外层那一份填上。哪一页的树里有这样的节点，哪一页就显示共用导航；没有＝这一页不显示。
- “当前项”不存：导航项的 `page` 指着哪一页，在那一页上就亮哪一项；没有哪一项指着这一页就亮第一项。
- 容错：有节点带 `shared: true` 却没有最外层那一份——取第一个自己带着 `props` 的这种节点当那一份（都没带就用默认的三项）；
  有最外层那一份却没有哪一页在用——留着不删；没有最外层那一份时节点上的 `shared` 存盘时去掉。
- 老版本应用打开这种文件：不认识 `shared`，原样留着；它看到的是“没写属性的底部导航栏”（显示成默认的三项）。首页别的内容不受影响。

## 第四轮 B2 之后的补充说明（组件的事件、变体、状态，类名开关的样子，组件库；版本号没动，只多了可选字段）

老版本应用打开带这些字段的文件：不认识的字段原样留着、存盘时原样写回（组件定义、节点、文档三处都有“没读懂的字段原样带着”的 `more`），不会丢；只是那些功能不起作用。

**组件定义上多的（都可选）**

| 字段 | 写法 | 说明 |
|---|---|---|
| `events` | `[{name, label, params?: [{name, type}]}]` | 组件对外发的事件。最多 12 个；一个事件最多带 6 项数据 |
| `variants` | `[{name, label, group?, groupLabel?, style?, nodes?: {<节点 id>: {style}}}]` | 变体。`style` 是最外层节点多出来／换掉的 CSS；`nodes` 是里面各节点的。没写 `group` 算 `variant` 组（叫“样子”）。最多 4 组、每组 8 个 |
| `state` | 和页面的 `logic.variables` 一个写法 | 组件自己的状态，每个实例一份。最多 24 个 |
| `lib` | `{id, name, version, component}` | 这个定义是从哪个组件库装进来的（`component` 是它在库里的 id）。带这一笔的定义在编辑器里只读 |

属性（`props`）的类型多了 `list`（默认空列表）。

**定义里的节点上多的**：`emit: {"click" 或 "input": {event: <组件事件名>, args?: {<数据名>: 来源}}}`——这个控件的这个动作往外发组件的哪个事件。

**页面上的组件实例多的**

| 字段 | 写法 | 说明 |
|---|---|---|
| `variant` | `{<组>: <变体名>}` | 每组选了哪个 |
| `on` | `{<事件名>: [积木…]}` | 这个事件发生时做什么（积木的写法和页面逻辑里的一样） |
| `data` | `{<属性名>: 来源}` | 属性绑页面状态（来源的写法和别处的 `data` 一样） |

**类名开关**：`classIf` 里每一项多一个可选的 `style: {<CSS 属性>: 值}`——这条类名成立时的样子。

**文档上多的**：`compLibs: {<库标识>: {name, version, author, components: [组件 id]}}`——这个项目自己做了哪些库、每个库里放了哪些组件（“再存一版”时用）。

### 组件库在项目里怎么放

- 每个库一个文件夹 `components/作者段/库名/`：
  - `lib.json`：`{kind: "lopicode-complib", format: 1, id, name, version, author, side: "frontend", components: [{id, name}], images?: [路径], missing?: [没带上的图片路径]}`；
  - `components.json`：`{components: [组件定义…], themeVars?: {<变量名>: 值}}`；
  - `images.json`（有图片才有）：`{<项目里的相对路径>: <base64>}`。
- 登记表 `components/libs.json`：`{format: 1, libs: [{id, version, from, sum}]}`。`from`：`project`＝在这个项目里存的，`file`＝从文件导入的；`sum` 是三个文件内容的 sha256。和积木库的 `blocks/libs.json` 是并列的两张，互不相干。
- 导出文件：`exports/组件库-名字-版本.lopilib`，就是上面三个文件打成的 zip（和积木库同一种包、同一套防护）。
- 装进文档：库里的定义拷进 `components`，id 换成 `lib_<库标识里的非字母数字换成下划线>_<原 id>`，带上 `lib` 那一笔；库带的主题变量项目里没有的补进 `theme.vars`，已有的不动；库带的图片写进项目里原来的路径，已有同名文件的不动。
- 导入时拦下的：没有清单或清单不是 JSON；`kind` 不对（是积木库会单独说）；缺 `id`／`name`／`version`；标识、版本号写法不对；作者段是 `lopi`、`local`；`side` 不是 `frontend`（B2 那一版写的 `front` 也认）；带 `native/`（手写代码）；一个组件都没有、超过 64 个、有读不懂的、id 重复；用到库里没有的组件；组件互相套成圈；图片路径不对劲；项目里已有同标识同版本、内容却不一样的库；以及打包层的全部防护（超大小、文件太多、路径往外跳、不是压缩包、内容不是文字）。

## 第四轮 B3 之后的补充说明（顶部导航跨页共用；版本号没动，只多了可选字段）

- 最外层的 `shared` 里新增可选 `topBar`：`{"props": {…}, "style": {…}, "states": {…}, "responsive": {…}, "data": …, "children": […]}`。
  它是跨页共用的那一条顶部导航栏**唯一的一份**：样子、样式，外加“默认的”标题（`props.title`）、返回箭头（`props.back`）、
  左右两边放的控件（`children`，每个带 `slot: "left"` / `"right"`）。
  `shared.topBar` 不是对象、或它的 `props` 不是对象：整个当看不懂，原样留着。`children` 里读不出来的项跳过。
- 顶部导航栏节点（`appBar`）新增可选 `shared: true`：这个节点显示的是共用的那一条。还可以带可选 `own`
  （`["title", "back", "slots"]` 的子集）：这一页自己说了算的是哪几样。文件里这个节点只写自己的记号（`id`、名字、锁定…）、
  `shared`、`own`，以及 `own` 里那几样的值——`props.title`、`props.back`、`children`；别的都不写，读的时候从最外层那一份填上。
- 有节点带 `shared: true` 却没有最外层那一份（手写的、Agent 写的）：取第一个自己带着整套 props 的这种节点当那一份，都没有就用默认的。
- 最外层没有 `shared.topBar` 时，节点上的 `shared` / `own` 不算数，存盘时去掉（比如把共用的那条粘贴进了另一个项目）。
- 没用共用顶栏的文件：没有这些字段，存出来和以前逐字节一样。规矩和同步点见 `lib/lowcode/top_shared.dart`。

组件库清单（`lopilib.json`）的 `side` 写成 `frontend`（和积木库同一个写法）；第四轮 B2 写的 `front` 读的时候照样认。

## 第四轮 B4 之后的补充说明（版本号没动，没有新字段）

- 事件带的数据用的还是 B2 就有的字段：定义上 `events[].params`、定义里节点上 `emit.<click|input>.args`。B4 只是在面板上给了入口（一个事件配一项）。
- 实例的 `on.<事件名>` 里，积木参数可以是 `{"e": "event"}`（“事件带来的值”＝事件带的第一项数据）。快捷动作“把一个状态设成事件带来的值”存的是 `{"op": "setVar", "args": {"name": <状态名>, "value": {"e": "event"}}}`。
- 导出时临时加的记号节点（`<实例 id>__on_<事件名>`，`lcEvt` 字段）只在给导出看的那份拷贝里，不存盘。

## 第四轮 B5 之后的补充说明（版本号没动）

- 新组件类型 `slider`（滑块）：`props.value`、`min`、`max`、`step` 都是数（不写＝50 / 0 / 100 / 1；最大不比最小大时当成“最小 + 1”；一步不大于 0 时当成 1），`disabled` 是 是/否。
  写错类型的这四个值存盘时丢掉。别的控件上的 `value` 还是一段文字，不受影响。可以 `model` 双向绑到数字状态。
- 状态样式分屏宽：`responsive.<tablet|desktop>.states.<pressed|disabled|focused>` 是一份 CSS 声明表，意思是“这一档上这个状态的样子和更窄的屏上不一样的那几条”。
  和同一档的 `style` 并排放；不认识的状态名、值不是字符串的条目原样留着。没用的文件没有这个字段。
- 内置组件库装进来的定义和别的库装进来的一样带 `lib: {id: "lopi/builtin", name: "内置组件库", version: "1.0.0"}`，定义 id 是 `lib_lopi_builtin_<名字>`。
- 没用这些新东西的旧文件：存出来和以前逐字节一样。


## 第四轮 B8 之后的补充说明（版本号没动，只多了可选字段）

- 节点上新增可选 `emptyOf: "<另一个节点的 id>"`：只给编辑器看的记号，意思是“这个容器是那个被重复的控件在列表为空时显示的那一块”。
  它自己就是一个带存在条件（`renderIf`：那张列表有 0 项）的普通容器，紧跟在被重复的控件后面；导出不看这个字段。规矩见 `lib/lowcode/repeat_empty.dart`。
  `repeat.empty`（一句文字）照旧可用；用了那一块以后编辑器会把这句话搬进去并去掉 `repeat.empty`。
- 弹窗（`dialog`）的 `props.variant` 多一个值 `toast`（轻提示）：只用 `props.text`（那句话）、`props.seconds`（几秒后消失，1–5 的整数，不写＝2）、`props.open`；
  标题、按钮文字、`dismissible`、子节点在这种样子下都不画、不导出。`seconds` 是新键，只在 `dialog` 上算数。
- 组件定义里的插槽占位节点（`type: "slot"`）新增可选 `gives: {名字: 来源}`：这个插槽给填进来的内容的数据。来源在定义里那个位置算；
  内容的绑定里按名字读。名字不合规矩、来源读不懂的那几条不算数（原样留着）；最多 8 样。规矩见 `lib/lowcode/slot_gives.dart`。
- 没用这些新东西的旧文件：存出来和以前逐字节一样；四种导出也一样。
