# 低代码第 2 版：数据约定与分工

2026-11-24 霜霜要求把低代码搭建扩充成：样式可视化编辑 + CSS 翻译、画布化、积木式逻辑、Vue / React 导出、自定义组件、
文件编辑器补强与代码格式化。这一页是各块共用的“数据长什么样、谁提供什么函数”，改约定要先改这一页。

不许抄第三方代码或素材（dsh-Go 是 AGPL；Blockly 等积木库也不抄），全部自己写。不嵌网页版积木库，运行时不联网。

## 页面文件（`page.lowcode.json`）

```jsonc
{
  "version": 2,              // 第 1 版没有下面这些新字段，照样能读
  "title": "…",
  "root": { /* 节点，type 必须是 page */ },
  "logic": { "variables": [...], "handlers": [...] },   // 可省略
  "components": [ { "id": "c1", "name": "…", "props": [...], "root": {…} } ]   // 可省略
}
```

读取规矩：**新字段一律容错**——类型不对、缺字段的逐条跳过，不许让整页打不开（`test/lowcode_v2_model_test.dart`）。
老字段（`root` 结构）不合法仍然抛 `FormatException`，和第 1 版一样。

### 节点

```jsonc
{ "id": "n3", "type": "button",
  "props": { "text": "提交", "padding": 12 },          // 第 1 版的简写属性，继续有效
  "style": { "margin-top": "8px", "border-top-width": "1px" },   // 新：这个节点自己的 CSS 声明
  "bind":  { "text": "title" } }                        // 新：只在组件定义里用，属性 → 组件 prop 名
```

- `style`：键是小写连字符的 CSS 属性名，值是字符串。**存的是“规范写法”：能拆成单边的一律拆开存**
  （`margin: 8px 4px` 存成四条 `margin-top/right/bottom/left`；`border`、`border-radius`、`padding`、`inset`、`flex`、`gap` 同理），
  这样可视化控件改“上边距”只动一条。导出 CSS 时再合并回简写。认不出的属性原样留在同一张表里（＝“自定义 CSS”），不丢。
- 值里不许有 `{ } ; < >` 和换行（模型读的时候就丢掉这种条目），免得导出的 CSS / Vue 文件被截断。
- **最终样式 ＝ 简写属性翻出来的声明，被 `style` 里同名的盖掉**（`resolvedStyle`）。画布、HTML / Vue / React 导出都用它。
- `type: "component"`：自定义组件的实例，`props.ref` 是组件 id，`props.values` 是这次传的 prop 值（字符串 / 数字 / 布尔）。

### 逻辑（`logic`）

```jsonc
{ "variables": [ { "name": "count", "type": "number", "initial": 0 } ],        // type: text / number / bool
  "handlers":  [ { "id": "h1", "event": "click", "target": "n3", "body": [ 积木… ] } ] }   // event: click / input / load（load 没有 target）
```

积木：`{ "op": "…", "args": { … }, "body": [ … ], "else": [ … ] }`。参数里要“值”的地方放**表达式对象** `{ "e": "…", … }`。

| op | args | 说明 |
| --- | --- | --- |
| `setVar` | `name`, `value`(表达式) | 设置变量 |
| `changeVar` | `name`, `by`(表达式) | 数字变量加上一个数 |
| `setProp` | `node`(节点 id), `prop`, `value`(表达式) | 改控件：`prop` ∈ text / value / visible / bg / color / src / placeholder |
| `if` | `cond`(表达式) ＋ `body` ＋ `else` | 如果…否则… |
| `repeat` | `times`(表达式) ＋ `body` | 重复 N 次（生成的代码里封顶 10000 次） |
| `alert` | `message`(表达式) | 弹提示 |
| `navigate` | `url`(表达式) | 跳转网址 |
| `fetch` | `url`(表达式), `method`(GET/POST), `into`(变量名，可空) ＋ `body`(成功后) ＋ `else`(失败后) | 请求网址，结果文本放进变量 |
| `log` | `value`(表达式) | 写到控制台 |
| `wait` | `ms`(表达式) ＋ `body` | 等一会儿再做 |

表达式（`e`）：`text{v}`、`num{v}`、`bool{v}`、`var{name}`、`prop{node, prop}`（读控件的 text / value / visible）、
`event{}`（input 事件里＝输入框当前内容）、`bin{op, l, r}`（`+ - * / %`、`== != < <= > >=`、`and or`）、`not{x}`、`join{items:[…]}`（拼成文字）。

认不出的 `op` / `e` 读的时候**保留**（数据不丢），界面上显示成“不认识的积木”，翻代码时变成一行注释。

### 自定义组件（`components`）

`props`：`[{ "name": "title", "type": "text", "default": "…" }]`，type ∈ text / number / color / bool。
`root`：一棵节点树（不能是 page），节点 id 在组件内部唯一，和页面节点互不相干。组件定义里不能再放自己（不许递归）。

## 谁提供什么（文件归属）

| 块 | 文件 | 对外函数 |
| --- | --- | --- |
| 模型 | `lib/lowcode/model.dart`、`logic_model.dart`、`component_model.dart` | 上面的数据类 |
| A 样式 | `lib/lowcode/style_model.dart`、`css_codec.dart`、`style_resolve.dart`，改 `export_html.dart` | `parseDeclarations(css)`、`declarationsToCss(map)`、`legacyStyle(node, parent)`、`resolvedStyle(node, parent)`、`LcStyle` 带类型的读写 |
| C 逻辑 | `lib/lowcode/logic_blocks.dart`（积木目录与校验）、`logic_js.dart`（翻 JavaScript）、`logic_text.dart`（积木的中文读法） | `exportLogicJs(doc)`、`validateLogic(doc)` |
| F 格式化 | `lib/format/*.dart`，改 `lib/ui/code_editor.dart`、`code_highlight.dart`、`files_tab.dart` | `formatCode(source, language)` |
| B 画布 | `lib/lowcode/canvas_*.dart`、`style_*_sheet.dart` 等界面文件，把渲染从 `builder_screen.dart` 挪出来 | — |
| C 界面 | `lib/lowcode/logic_screen.dart` 等 | — |
| D 框架导出 | `lib/lowcode/export_vue.dart`、`export_react.dart` | `exportVue(doc)`、`exportReact(doc)` |
| E 组件 | `lib/lowcode/component_ops.dart`、界面文件 | 存成组件、展开实例 |
