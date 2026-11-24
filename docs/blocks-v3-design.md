# 积木第 3 版：拼图式积木编辑器 + 后端积木 + 语言图标（共用约定）

2026-11-24 13:57 霜霜的要求：积木“太丑、不像积木、死板、没有搭积木的感觉、不好玩”，要重做；模板不能只有前端，
后端也要用积木搭，支持主流语言；文件 / 语言图标用 material-extensions/vscode-material-icon-theme。

这一页是几个人分头做时共用的约定。改约定先改这一页。第 2 版的约定（docs/lowcode-v2-design.md）继续有效。

不许抄第三方代码或素材（Scratch、Blockly、dsh-Go 都不抄）；“拼图式积木”只学这个通用的交互概念，外形自己画。

## 已经定好的底子（提交在这一页同一个提交里）

- `lib/lowcode/logic_model.dart`：`mixin LcBlockTree`——“一串积木”的按路径操作（`blockAt / listAt / insertBlock / removeBlock /
  moveBlock / shiftBlock / visitBlocks`），带 `id`、`body`、`x`、`y`。`LcHandler with LcBlockTree`；后端的接口也混它。
  `x / y`＝这串积木在积木画布上的位置，null＝没摆过（编辑器打开时自动排，**自动排的结果不算“改动”，不落盘、不进撤销**）。
  `LcHandler.toJson` 只在不为 null 时才写 `x / y`，所以没在新编辑器里动过的旧页面，文件内容不变。
- `LcArgKind.collection`：数据集合的名字，只有后端积木用。
- 积木 / 表达式的说明类继续用 `LcBlockSpec / LcExprSpec / LcArgSpec`（`lib/lowcode/logic_blocks.dart`），前端后端共用。
  积木自己的参数（不只是表达式的 `v`）也可以是 `literalText / literalNumber`（直接存字符串 / 数字），编辑器要能就地编辑。

## 目录与归属（互不碰对方的文件）

| 谁 | 文件 | 说明 |
| --- | --- | --- |
| 积木编辑器（通用） | `lib/blocks/**`、`test/blocks_*.dart` | 不认识“前端 / 后端”，只认下面的 `BlockHost` |
| 前端接入 | `lib/lowcode/logic_*`（界面文件可以删、可以换）、`test/lowcode_logic_ui_test.dart` | 把旧的列表式编辑页换成新编辑器 |
| 后端逻辑 | `lib/backend/**`（不带界面的文件）、`test/backend_*.dart` | 模型、目录、校验、读法、各语言生成 |
| 后端界面 / 模板 | `lib/backend/*_screen.dart` 等、`lib/core/templates.dart`、新建项目页 | 最后做 |
| 图标 | `third_party/material-icon-theme/`、`assets/file_icons/`、`lib/core/file_icons*.dart`、`lib/ui/file_icon.dart`、`pubspec.yaml` 的 assets | |

`lib/blocks`、`lib/backend` 是新目录，守门测试对没列出的目录不限制层次，但“逻辑文件不依赖界面”照样管：
带界面的文件名必须以 `_widgets.dart / _view.dart / _screen.dart / _sheet.dart` 结尾。

## 积木编辑器（lib/blocks）

### 对外接口：`BlockHost`

编辑器不直接碰 `LcDocument`。前端、后端各实现一个 host（接口的最终签名由做编辑器的人定，写回这一节）：

- 目录：有哪些积木 / 表达式、分类与顺序、每类的颜色。
- 脚本：`List<LcBlockTree>`；每串的“帽子”显示什么（一段段文字 + 可点的槽位，例如“当 [按钮 提交] 被点击”“GET [/todos/:id]”），
  帽子的槽位怎么改；积木盒里有哪些帽子可以拖出来（＝新建一串）；删一串。
- 造新积木 / 新表达式（带默认参数）。
- 某种参数有哪些可选项（变量、控件、集合）。
- 校验结果（哪一串、哪条路径、哪个参数、说什么）。
- “看代码”的文字。
- 改动前后各通知一次（宿主负责撤销快照和落盘）；撤销 / 重做。

### 外形（自己用 CustomPainter 画）

- 帽子块：圆顶。语句块：上边有凹口、下边有凸起，上下能咬合。C 形块（如果 / 重复 / 等待 / 请求…）：包住里面的块，
  有“否则”的是 E 形（两个口）。表达式：小块嵌在参数槽里——是非类（条件）六边形，其余圆角胶囊。
- 按类别上色，带立体感（顶部高光、底部深色边），浅色深色主题都要好看；被拖着的块略放大带阴影。
- 文字用主题字体；触控目标不小于 40。

### 手感

- 自由画布：可平移、双指缩放；每串脚本可以摆在任意位置。
- 积木盒：贴在底部（或侧边），按类别分页；从盒里**拖出来**放到画布。
- 拖动：块跟手；一串里从某块往下可以整串拖走；可以跨脚本拖；靠近可拼位置时出现落点阴影并吸附；
  放下有回弹动画 + `HapticFeedback`；拖到垃圾桶或拖回积木盒＝删除。
- 表达式块也能拖进 / 拖出参数槽。
- 参数：点槽位**就地**编辑（数字、文字直接输入；下拉、选控件、选变量用贴着槽位的小菜单），不要一层层弹整页。
- 保留：校验问题列表、看代码、变量面板、撤销重做。

## 后端积木（lib/backend）

### 文件：`backend.lc.json`

```jsonc
{ "version": 1, "kind": "backend", "name": "…", "port": 8080, "language": "node",
  "variables":   [ { "name": "n", "type": "number", "initial": 0 } ],     // 每次请求开始时重置成初始值
  "collections": [ { "name": "todos" } ],                                  // 数据集合：一条是一个对象，自动带数字 id
  "routes": [ { "id": "r1", "method": "GET", "path": "/todos/:id", "x": 24, "y": 24, "body": [ 积木… ] } ] }
```

读取一律容错（坏的逐条跳过，整份打不开时返回空白文档 + 说明，不许抛异常让应用崩）。路径参数写 `:名字`。

### 值的规矩（所有语言必须一致，靠“各语言跑同一份模型、响应逐字节相同”的测试守着）

- 值就是 JSON 值：空、是否、数字、文字、列表、对象。
- 算术先转数字（转不了当 0，除以 0 得 0）；整数输出不带小数点（`3` 不是 `3.0`）；拼文字只用“拼接”。
- “等于”两边类型不同时转成文字再比。条件判断：空、false、0、空文字算“否”，其余算“是”。
- 一个接口跑完没有“返回”积木时，回 204 空响应。“返回”之后的积木不再执行。
- 集合：存在内存里（进程重启就没了）；`id` 从 1 递增；找不到的 id 读出来是空。

### 积木（op）与表达式（e）——最少要有这些，名字由做的人定并写回这里

- 复用前端语义的：`setVar`、`changeVar`、`if`、`repeat`、`log`，表达式 `text / num / bool / var / bin / not / join`。
- 请求：`pathParam{name}`、`query{name}`、`bodyField{name}`、`body{}`、`header{name}`。
- 返回：`respondJson{status, value}`、`respondText{status, value}`。
- 数据：`dbInsert{collection, value, into?}`、`dbUpdate{collection, id, value}`、`dbDelete{collection, id}`；
  表达式 `dbAll{collection}`、`dbGet{collection, id}`、`dbCount{collection}`。
- 造值：`obj{fields:[{key, value}]}`、`field{of, key}`、`len{x}`、`isNull{x}`；`forEach{list, item}` ＋ body。
- 外部请求 `fetch`：可以只生成代码，不参加一致性测试。

### 各语言生成

每种语言生成一个**不用装任何第三方包**就能启动的小工程（只用该语言标准库）＋ README（怎么启动）。这样手机上不用联网装依赖，
也能在本机真跑来验证。框架版（Express / FastAPI / Spring Boot）是加分项，放最后，API 写法没对着官方文档核对的记进 docs/api-notes.md 标“未核对”。

| 语言 | 用什么 | 本机能不能真跑 |
| --- | --- | --- |
| Node.js | `node:http` | 能（node 24） |
| Python | `http.server` | 能（python 3.12） |
| Go | `net/http` | 能（`~/workspace/tools/gosdk/go/bin/go` 1.25） |
| Java | JDK 自带 `com.sun.net.httpserver`（JSON 自己带一个小实现） | 能（`~/workspace/tools/jdk`，JDK 21） |
| PHP | 内置服务器 `php -S` 的路由脚本 | 不能（本机没有 php）——只做结构检查，标“未实际运行” |
| C# / Ruby / Kotlin / Rust | 有余力再加 | 不能，同上 |

测试里起服务只许绑 `127.0.0.1` 的随机端口；本机没有对应工具时该用例跳过并打印原因，不许联网、不许装包。

## 协作规矩（共用一个工作目录）

- 提交只 `git add 自己的文件`（写明路径），**不许 `git add -A` / `git add .` / `git commit -a`**；提交前 `git status` 看一眼没带别人的。
- 排版只排自己的文件（照 `tool/check.sh` 里排版那一步用的命令和参数，换成自己的文件路径）；不许对整个工程跑 `tool/check.sh --fix`。
- 全量 `tool/check.sh` 只由协调者跑。自己只跑自己的测试文件和 `flutter analyze`（别人的半成品报错不用管，报给协调者）。
- 截图各用各的文件名前缀，只删自己的；截图不进仓库。
- `docs/provider-presets-research.md` 有一份别人的未提交改动，不要动、不要提交。
