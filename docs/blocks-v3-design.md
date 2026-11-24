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

### 对外接口：`BlockHost`（已定，`lib/blocks/block_host.dart`）

编辑器不直接碰 `LcDocument`。前端、后端各 `extends BlockHost`。前端的实现是 `lib/lowcode/logic_block_host.dart` 的
`LogicBlockHost`，后端照着它写。带“可覆盖”的有默认实现。

```dart
abstract class BlockHost {
  // 目录
  List<BlockCategory> get categories;        // 积木盒的分页：id / label / colorKey / hats / blocks(op) / exprs(e)
  LcBlockSpec? blockSpec(String op);          // 不认识返回 null（画成“不认识的积木”）
  LcExprSpec? exprSpec(String kind);
  String blockColorKey(String op);            // 可覆盖：默认＝它在哪一页就用哪页的颜色
  String exprColorKey(String kind);           // 可覆盖
  String? blockSentence(String op);           // 可覆盖：积木上的话，`把 {name} 设为 {value}`；null＝通用排法
  String? exprSentence(String kind);          // 可覆盖：`{l} {op} {r}`
  bool isBooleanExpr(Map<String, dynamic> e); // 可覆盖：是 / 否类 → 六边形

  // 脚本
  List<LcBlockTree> get scripts;              // 每次重新取，不要留着
  LcBlockTree? script(String id);
  BlockHat hatOf(LcBlockTree tree);           // 帽子：BlockHatPart.text('当') / BlockHatPart.slot('target', '按钮“提交”')
  String hatSlotValue(LcBlockTree tree, String slotId);
  List<BlockOption> hatSlotOptions(LcBlockTree tree, String slotId);
  bool setHatSlot(LcBlockTree tree, String slotId, String value);          // 在 edit 里调
  LcBlockTree? addScript(String templateId, {double? x, double? y});       // 在 edit 里调；templateId＝BlockHatTemplate.id
  bool removeScript(String id);                                            // 在 edit 里调

  // 造新的
  LcBlock newBlock(String op);
  Map<String, dynamic> newExpr(String kind);
  Map<String, dynamic> defaultExpr(LcArgSpec arg);   // 可覆盖：表达式槽被拖空后放回什么

  // 参数
  List<BlockOption> options(LcArgSpec arg, {LcBlockTree? tree, LcBlock? block, Map<String, dynamic>? expr});
  String optionLabel(LcArgSpec arg, String value);   // 可覆盖：值显示成什么字

  // 校验与代码
  List<BlockIssue> get issues;               // message / isError / scriptId / path（空＝帽子）/ arg
  String get codeText;
  String get codeLanguage;                   // “JavaScript”“Python”…

  // 改动、撤销、通知
  void edit(void Function() change);         // 一次＝一条撤销记录＝一次落盘；宿主先记快照、跑 change、落盘、revision+1、调 onChanged
  bool get canUndo; bool get canRedo; void undo(); void redo();
  int get revision;                          // 内容每变一次加一，编辑器据此重排
  void Function()? onChanged;                // 只有一个位置，谁显示宿主谁占，离开时置 null
}
```

三条用法规矩：

1. **不要跨一次改动留着 `LcBlockTree` / `LcBlock` 对象**（撤销重做后宿主可能整份换对象）。记“脚本 id + 路径”，用时从 `host.script(id)` 重新找。
2. **所有改动都包在 `host.edit(() { … })` 里**；`change` 里用 `host.scripts / script` 拿到的就是可以直接改的对象。自动排布的位置不是改动，不许写回。
3. 颜色只给“哪一类”（`BlockColorKey`：event / variable / widget / control / action / network / value / operator / data / request / response / unknown），
   具体颜色、明暗两套在 `lib/blocks/block_colors.dart`。后端要新的类别先在那里加键。

积木上的话用模板（`{参数名}`）：模板里没提到的参数会自动接在后面；有 body 的积木，第一个口的叫法写在模板末尾（“如果 {cond} 那么”），
第二个口的叫法（`elseLabel`）画在两个口之间的横栏上。表达式只有一个直接填的参数（文字 / 数字 / 是否）时画成“光杆”输入框，不包彩色外壳。

### 几何与拼接（给做拖拽的人，`lib/blocks/block_geometry.dart`、`block_layout.dart`、`block_canvas_layout.dart`）

- `BlockLayoutEngine(host, measure)`：`layoutScript(tree)`（帽子 + 整串）、`layoutStack(blocks, parent:, inElse:, startIndex:)`（拖在手上的一截 / 样品，
  路径照原位置算）、`layoutExpr(expr)`（单独一个表达式，结果在 `loose`）、`layoutHat(hat)`。界面里用 `BkKit.of(context).engine(host)`。
- `BkScriptLayout`：`blocks`（帽子在前，先外后里）、`snaps`、`size`、`blockAt(path)`、`hitTest(点) → BkHit(block, slot, expr)`、
  `nearestSnap(点, kind:, maxDistance: 36, exclude: 被拖积木的路径)`、`allSlots`。坐标是这一串自己的（左上为原点）。
- `BkSnap`：语句（`parent / inElse / index / anchor / width`，正好是 `tree.insertBlock(parent, b, inElse:, index:)` 的参数；
  `anchor`＝被拖块的左上角该去的地方）；表达式（`parent`＝积木路径、`arg`、`exprPath`、`rect`、`hex`，配 `bkExprAt / bkSetExprAt(block, arg, exprPath, 值)`）。
  `exprPath` 每一步是字段名或列表下标：`['l']`、`['items', 1]`；空表＝参数本身。
- `layoutBlockCanvas(host, engine) → BkCanvasLayout`：`scripts`（`BkPlaced`: id / origin / layout / auto）、`extent`、`hitTest(画布点)`、
  `nearestSnap(画布点, kind:, excludeScript:, exclude:)`（返回的 `anchor` 是画布坐标）。
- 画：`BkScriptPainter.paint(canvas, layout, BkPaintState(selected:, selectedHat:, selectedSlot:, lifted:, ghost:, errors:, warnings:))`；
  控件 `BkLayoutView`（任意排版结果）、`BlockScriptView`（一串）、`BlockCanvasView`（只读画布，`BlockCanvasViewState.layout / selection / select`）、
  `BlockPaletteView`（积木盒，`onPick(BlockPaletteItem)`，样品自带排版可直接当拖影）。
- 尺寸都在 `BkMetrics`：单块最宽 320、最矮 40；凹口离左 14、宽 24、深 5；C 形胳膊宽 14、空口高 30、横栏 26、底条 16；帽子圆顶 13。
- 还没做（留给交互那一步）：拖拽与吸附、就地编辑、`join` 这类列表参数的“加一项 / 删一项”、放回原处等于没动的判断、画布位置写回 x / y。

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
