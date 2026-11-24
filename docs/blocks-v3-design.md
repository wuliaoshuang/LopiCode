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
- 上一步留下的（拖拽与吸附、就地编辑、列表参数加减项、放回原处等于没动、画布位置写回 x / y）已在交互那一步做完，规则见下面“手感 › 交互规则”。

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

#### 交互规则（2026-11-24 做交互时定的；带“自定”的是做的人自己拿的主意，霜霜没点过头）

编辑器整页是 `BlockEditorView`（`lib/blocks/block_editor_view.dart`），前端、后端各给一个 `BlockHost` 就能用：

```dart
BlockEditorView(
  host: myHost,                 // 必填
  title: '积木逻辑',             // 顶栏标题
  extraActions: [IconButton(…)], // 顶栏多放的入口（排在“问题”“看代码”前面），比如前端的“变量”
  focusScriptId: 'h3',          // 可选：一进来挪到这一串并选中它的帽子
  menuExtra: (arg) => …,        // 可选：某种参数的下拉菜单末尾多一项（前端用来放“新建变量…”），返回 (label, run)
  onHostChanged: () {…},        // 可选：宿主内容变了顺带说一声（外壳要刷新顶栏数字时用）
)
```

它自己带 Scaffold、顶栏（问题、看代码）、画布、底部积木盒、撤销 / 重做 / 缩放小条；会占用 `host.onChanged`，离开时还回 null。
状态拆在四个 mixin 里：`BkEditorCanvas`（平移缩放、点击）、`BkEditorDrag`（拖拽）、`BkEditorEdit`（就地编辑）＋纯逻辑的 `block_drag.dart`（`BkDragSession`）、`block_ops.dart`。

- **拖还是平移（自定）**：不用长按。手指落在积木上、移动超过 8px＝拖积木；落在空白＝平移画布；两指＝缩放（50%–200%，以两指中点为中心）。
  按住约 0.45 秒不动＝长按（在一个值上长按＝弹“换成…”）。从积木盒拿：按住 0.18 秒或横着拖＝拿出来；竖着滑＝滚积木盒；点一下＝快捷添加。
- **拖什么**：语句块带走它下面整串（到所在列表末尾），C 形连里面的；帽子＝整串脚本；表达式＝它自己（连里面嵌的）。
  拿起来以后原位立刻合拢（表达式的原槽先显示成默认值）。手上那截放大 4%、带阴影。
- **吸附**：拼接点离手上那截的左上角 36 以内（画布坐标，缩放后手感一致）就吸。落点处**真的让出位置**：别的积木按“放下以后的样子”重新排，
  落点画成灰色占位阴影（表达式槽是描边高亮）。让位是瞬间的，没有过渡动画。落点换了一个＝`HapticFeedback.selectionClick`。
- **放下**：约 150ms 回弹到位（easeOutBack）＋ `lightImpact`，动画走完才真的改模型（一次 `host.edit`＝一条撤销记录）。
  放回原处（紧贴原位上下的那个拼接点）＝没动，不产生改动。不能拖进自己里面：拿起来以后的排布里根本没有自己里面的拼接点。
- **放不下**：语句块放在空白处、表达式没放进槽里、嵌套超过上限（`LcBlock.maxDepth`）——约 180ms 晃着弹回原位＋ `heavyImpact`＋顶上一句人话
  （“积木要接在事件下面，不能单独放着。”）。**不做散块（自定）**：模型里语句必须在某个事件下面，导出也是这么假设的。
- **表达式**：拖进一个槽＝替换那里原来的值（原值丢掉，可撤销）；被拖走的槽恢复成 `host.defaultExpr`；“一串值”（`exprList`）里的一项被拖走＝少一项，只剩一项时换成默认值。
  六边形槽（要“是否”）放进不是“是否”的表达式：允许，只是落点描边变成警示色（前端翻代码时会自动转类型）。
- **删除**：拖动中积木盒的位置变成垃圾桶区（“拖到这里删除”），手指进去变红、显示会删几块，松手删除（约 160ms 缩小消失＋ `mediumImpact`）。
  删帽子＝删整串，里面有积木先确认。表达式拖进垃圾桶＝原槽恢复默认。从积木盒拿出来又放回积木盒＝不要了，没有改动。
  选中一块以后顶上的小条里也有“复制”“删除”（带子积木的删除先确认）。
- **脚本位置（自定）**：旧文档没有 `x / y` 时按自动排布显示，**只看不写**（不进撤销、不落盘）。用户第一次自己摆位置（拖帽子、从积木盒拖出一个新事件）时，
  同一次改动里把当时所有自动排的脚本的位置一起写下来——从此每串都有固定位置，不会因为别的串动了而重叠。
  之后某一串因为加了积木变高，会把它正下方（水平有重叠）的串往下推同样的高度；只推不拉。点一下积木盒里的事件新建的串不带位置，排在最后。
- **边缘自动滚**：拖着东西停在画布露出部分的边缘 48px 以内约 0.3 秒，画布开始往那边滚，越靠边越快。
- **就地编辑**：点数字 / 文字槽＝贴着槽的输入框（数字键盘；回车或点别处＝填好；数字填错不关、就地说原因，这时点别处＝放弃）；
  键盘弹出时积木盒让开、画布自动上移到槽露出来。点下拉类的槽＝贴着槽的小菜单；“是 / 否”点一下就翻。
  点空槽或长按一个值＝“换成…”小卡片（按类别分页，里面是画出来的真积木）；原来那里是拼好的表达式时，会把它包进新表达式的第一个空位里（比如给条件套一层“不是”）。
  “一串值”末尾有个小“＋”（`BkSlotLook.add`）点一下加一项；长按某一项，“换成…”卡片底下有“去掉这一项”。
- **快捷添加**：点积木盒里的语句块＝加到选中积木后面；没选中就加到最后一串的末尾。点事件＝新建一串。点表达式只提示“按住它，拖到槽里”。
- **问题**：有问题的积木右上角带红 / 黄点；顶栏“问题”带数量，点一条＝画布移过去、选中、描边闪一下（约 0.9 秒淡掉）。
- 这一步给接口加的东西：`BlockHost.argChanged`（参数改了以后宿主顺手联动别的参数）、`BlockHost.newListItem`、`BkSlotLook.add`、
  `layoutScript(tree, body:)`（换一份积木排预览）、`layoutBlockCanvas(…, bodies:, hide:, origins:)`、`BkPaintState.ghostRange / slotColor / flash`。

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

### 积木（op）与表达式（e）——最终的表（`lib/backend/backend_blocks.dart`，`test/backend_model_test.dart` 核对两边一致）

积木盒分类：返回、数据、变量、流程、调试、网络。表达式分类：直接填、请求、数据、变量、运算、对象。

<!-- be-ops:start -->
| op | args | 说明 |
| --- | --- | --- |
| `respondJson` | `status`(表达式), `value`(表达式) | 返回数据（JSON），这个接口到此结束 |
| `respondText` | `status`(表达式), `value`(表达式) | 返回纯文字，这个接口到此结束 |
| `dbInsert` | `collection`(集合名), `value`(表达式), `into`(变量名，可空) | 往集合里加一条（值要是对象，自动带 `id`），加好的那条可以放进变量 |
| `dbUpdate` | `collection`, `id`(表达式), `value`(表达式) | 只改给出的字段；`id` 不许改；找不到就不动 |
| `dbDelete` | `collection`, `id`(表达式) | 删一条；找不到就不动 |
| `setVar` | `name`(变量名), `value`(表达式) | 设置变量（什么值都能放，不按声明的类型转换） |
| `changeVar` | `name`(变量名), `by`(表达式) | 变量加上一个数（两边先转数字） |
| `if` | `cond`(表达式) ＋ `body` ＋ `else` | 如果…否则… |
| `repeat` | `times`(表达式) ＋ `body` | 重复 N 次（运行时封顶 10000 次） |
| `forEach` | `list`(表达式), `item`(变量名) ＋ `body` | 列表的每一项轮流放进变量；不是列表就一遍也不做 |
| `log` | `value`(表达式) | 写一行到服务的标准输出 |
| `fetch` | `url`(表达式), `method`(GET/POST), `data`(表达式，可空，POST 时当 JSON 提交), `into`(变量名，可空) ＋ `body`(成功后) ＋ `else`(失败后) | 请求别的网址，最多等 10 秒；2xx 算成功，响应文字放进变量 |
<!-- be-ops:end -->

<!-- be-exprs:start -->
表达式（`e`）：`text{v}`、`num{v}`、`bool{v}`、`var{name}`、`bin{l, op, r}`（运算符同前端）、`not{x}`、`join{items:[…]}`、
`pathParam{name}`、`query{name}`、`bodyField{name}`、`body{}`、`header{name}`（`name` 都是直接填的文字，读不到是空）、
`dbAll{collection}`、`dbGet{collection, id}`、`dbFind{collection, key, value}`（字段 `key` 等于 `value` 的那些）、`dbCount{collection}`、
`len{x}`、`isNull{x}`、`now{}`（世界标准时间的文字 `2026-11-24T06:00:00Z`）、
`obj{fields:[…]}`、`pair{key, value}`、`field{of, key}`（`key` 是直接填的文字）。
<!-- be-exprs:end -->

- `obj` 的 `fields` 是一串 `pair`：`{"e":"obj","fields":[{"e":"pair","key":"title","value":{…}}]}`。这样“一串值”的参数种类（`exprList`）够用，
  不用给 `LcArgKind` 加新种类；编辑器往 `fields` 里加一项时用 `newBeListItem('obj', 'fields')`。`pair` 只能出现在 `obj` 里，不单独挑（`beExprSpecsIn` 不列它）。
- 比设计时多加的两个：`dbFind`（做“只看已完成的”这类筛选）和 `now`（记创建时间）。没有再多加。
- 变量：`type` 只决定初始值，运行时什么值都能放（`dbInsert` 的 `into`、`forEach` 的 `item` 放的是对象）。每次请求开始时重置。
- 校验（`validateBackend`）沿用前端的 `LcLogicIssue`（`handlerId`＝接口 id），后端特有的问题种类在 `BeIssueCode`。
- 新建积木 / 表达式：`newBeBlock(op, doc)`、`newBeExpr(kind, doc, route)`；中文读法：`describeBeBlock / describeBeExpr / describeBeRoute`。

### 值的规矩的细则（实现时定的，写死在一致性测试里）

- **数字的写法**：整数且绝对值小于 1e15 → 不带小数点；否则保留 12 位有效数字（正好一半时远离 0，`0.1 + 0.2` 写成 `0.3`）、去掉末尾的 0，
  指数在 -7 到 14 之间写普通小数，其余写 `1.5e-10`、`1e21`（不带加号）。
- **文字转数字**：去掉两头的空格 / 制表 / 换行后是十进制写法（`-1.5`、`.5`、`1e3`）才算，其余（`0x10`、全角数字、`Infinity`、空文字）当 0；是→1，否→0。
- **JSON 输出**：对象的键按 Unicode 码点排序（不是按写入顺序——这样每种语言都能做到一样）；不加空格；
  文字只转义 `"`、`\`、U+0000–U+001F。
- **转成文字**：空→空文字，是 / 否→`true` / `false`，列表 / 对象→它的 JSON。“等于”：类型一样直接比（列表 / 对象比 JSON），不一样都转文字再比。
- **请求**：路径按 `/` 切段再逐段做百分号解码，空段忽略（`/todos/` ＝ `/todos`）；解码失败（`%zz`、不是合法 UTF-8）原样保留；
  网址参数里 `+` 当空格、重名取第一个；请求内容不是合法 UTF-8 / JSON（含带 BOM、`NaN`）当成空；超出范围的数当 0；
  不成对的代理项换成 U+FFFD；请求内容最多 1MB（超过回 413）。请求内容的 JSON 里列表 / 对象最多套 64 层，超过整份当成空
  （各语言自带的上限差得很远，所以定一个统一的）。请求头的值去掉两头的空格 / 制表，中间的留着。
- **请求别的网址**：只许 `http://` / `https://` 开头；主机那一段带 `@`（用户名密码）的不请求；发出去之前把网址按 UTF-8 做百分号转义——
  字母、数字和 ``-._~:/?#[]@!$&'()*+,;=`` 原样，后面跟着两位十六进制的 `%` 原样，其余每个字节写成 `%XX`
  （各语言自己的处理不一样：有的自动转空格和中文，有的直接报错，所以统一在小库里做）。
  对方的响应按 UTF-8 读，坏的地方换成 U+FFFD，开头的 BOM（U+FEFF）去掉一个。
- **不在规矩里的**（各语言的 HTTP 库各管各的，没法统一，一致性测试不测）：`GET / POST / PUT / PATCH / DELETE / OPTIONS / HEAD` 之外的请求方式
  （Node 回 400、Python 回 501、Go 和 Java 回 405）；`HEAD` 都只回响应头；分块传输的请求内容（Node、Go 能读，Python、Java 当成没有内容）。
- **响应**：状态码取整后不在 200–599 里当 200；204 / 304 不带内容也不带 Content-Type；JSON 是 `application/json; charset=utf-8`，
  文字是 `text/plain; charset=utf-8`；都带 `Access-Control-Allow-Origin: *`，`OPTIONS` 一律回 204（跨域预检）。
- **路由**：按声明顺序匹配，先对上的先用（所以 `/todos/count` 要排在 `/todos/:id` 前面，校验会提示）；
  地址没对上 404 `{"error":"没有这个接口"}`，地址对了方式不对 405，接口里出错 500。
- **集合**：`id` 从 1 递增、删了不回收；往里加的不是对象就当空对象；读出来的记录是“当时的样子”（之后改集合不影响已经读出来的）。

### 各语言生成

每种语言生成一个**不用装任何第三方包**就能启动的小工程（只用该语言标准库）＋ README（怎么启动）。这样手机上不用联网装依赖，
也能在本机真跑来验证。框架版（Express / FastAPI / Spring Boot）是加分项，放最后，API 写法没对着官方文档核对的记进 docs/api-notes.md 标“未核对”。

架构（`lib/backend/`）：积木先翻成**与语言无关的中间形式**（`backend_ir.dart` 的 `lowerBackend`）——所有运算都是对“运行时小库”的一次函数调用
（`add(a, b)`、`dbGet("todos", id)`…，函数表是 `kBeRuntimeFns`，每个函数的规矩写在表里），语句只有七种（赋值、存临时值、调函数、如果、重复、逐项、返回）。
值的规矩全在小库里，翻译这一层没有优先级和类型转换的问题。

**加一种语言要写三样**（照 `target_node.dart` ＋ `runtime_node.dart` 抄一份改）：

1. 运行时小库（一个字符串常量）：实现 `kBeRuntimeFns` 的每个函数，外加 `collection / route / start`。
2. 一个 `BeCodeTarget` 子类（约 100 行）：字面量怎么写、变量叫什么、调小库函数怎么写、七种语句怎么写、路由文件怎么拼。
3. 在 `backend_targets.dart` 的 `backendTargets` 里加一行；在 `test/backend_conformance_test.dart` 的 `_languages` 里加一行。
   同一份样本模型和请求脚本（`test/support/backend_conformance.dart`）就会对着它跑；需要先编译的语言在生成器的 `buildCommands` 里写。
   工具不在 PATH 里、或者要额外的环境变量（Go 的缓存目录、不许联网）时，在 `toolchainFor` 里加一段。
4. 在 `test/backend_codegen_test.dart` 的 `_expectedFiles` 里登记文件清单；在 `test/backend_codegen_langs_test.dart` 里加这种语言的结构检查
   （字面量、转义、小库有没有漏函数）。本机跑不了的语言 `verified` 写 false——README 顶部会自动写明“还没有实际运行过”。

`BackendTarget` 上给“跟别人不一样”的语言留的口子：`startCommandFor(端口)`（端口要写在命令里的，如 `php -S`）、`portFromEnv`、
`dataInMemory`（集合是不是存在内存里）、`notes`（README 里多写几条说明）。

生成的文件：入口（`server.js` / `server.py` / `main.go` / `Main.java`，积木翻出来的，每块积木上面一行中文注释）＋小库（每份都一样）＋ `README.md`。
端口读环境变量 `PORT`（没有用文档里的 `port`），`HOST` 默认 `0.0.0.0`；启动后打印一行 `后端已启动：http://主机:端口`（测试靠它知道端口）。

| 语言 | 用什么 | 本机能不能真跑 |
| --- | --- | --- |
| Node.js | `node:http` | 能（node 24）——**已做，一致性测试通过** |
| Python | `http.server` | 能（python 3.12）——**已做，一致性测试通过** |
| Go | `net/http`；值是 `any`，数字一律 `float64`；JSON 编码自己写（解析用 `encoding/json` 再按规矩收拾）；生成 `go.mod`（模块名写死 `lcbackend`、`go 1.18`） | 能（`~/workspace/tools/gosdk/go/bin/go` 1.25）——**已做，一致性测试通过**，生成物是 gofmt 规范格式、`go vet` 通过 |
| Java | `java.net.ServerSocket` 上自己读 HTTP（JSON 也自己带一个小实现）；值是 `Object`，数字一律 `Double`；`javac` 直接编译，不用 Maven / Gradle | 能（`~/workspace/tools/jdk`，JDK 21）——**已做，一致性测试通过** |
| PHP | 自带开发服务器 `php -S 0.0.0.0:端口 server.php` 的路由脚本；值是 null / bool / float / string / 数组（列表）/ `LcObj`（对象）；JSON 解析自己写 | 不能（本机没有 php）——**已做，只做了结构检查，未实际运行**（`verified: false`） |
| C# / Ruby / Kotlin / Rust、框架版（Express / FastAPI / Flask） | 没做 | —— |

实现时定的几件事：

- **Go**：`net/http` 碰到地址里写法不对的百分号（`/a/%zz`）会自己回 400，到不了我们的代码；小库在连接上包了一层，先看请求行、
  把写法不对的 `%` 换成 `%25` 再交给 `net/http`，原样的地址另外记着（为此关掉了连接复用：一个连接只处理一个请求）。
  数字字面量都带小数点（`200.0`），不然在 Go 里是整数；变量声明后跟一行 `_ = v_x`（Go 不许有没用到的变量）。
  编译要缓存目录：测试里把 `GOCACHE`、`GOPATH` 指到工程的 `.tmp` 下，`GOPROXY=off`、`GOFLAGS=-mod=mod`、`GOTOOLCHAIN=local`（不联网）。
- **Java**：原计划用 JDK 自带的 `com.sun.net.httpserver`，实测它同样拒掉 `%zz`、还把开头的 `//` 当成主机名，所以改成自己在 `ServerSocket` 上读请求
  （一个连接一个请求，只认 `Content-Length`）。注释里的 `\u` 要拆开（Java 在分词之前就把 `\u000a` 换成换行，注释后半截会变成代码）；
  太长的文字拆成几段用 `String.join` 拼（单个字符串常量上限 65535 字节）；标准输出 / 错误固定按 UTF-8 写。
  “请求别的网址”的 10 秒是“连接 10 秒 + 读 10 秒”各算各的，不是总共 10 秒（`HttpURLConnection` 没有总时限）。

- **PHP（和别的语言不一样的地方）**：PHP 每来一个请求都把 `server.php` 从头跑一遍，内存里留不住东西，所以**集合存在工程目录下的 `lc_data.json`**
  （别的语言存在内存里、重启就没了；PHP 版重启数据还在）。一次请求里第一次用到集合时打开文件加独占锁（`flock`），请求结束有改动才写回、再放锁——
  所以同一时间只有一个请求能用集合；文件里的数字写 17 位有效数字（读回来一位不差）；文件坏了当成没有数据。
  端口写在启动命令里（不读 `PORT` / `HOST`），启动后不打印“后端已启动”。数字字面量都带小数点（PHP 里 `1 === 1.0` 是假）；
  文字里的 `$` 加反斜杠；注释里的 `?>` 拆开（`//` 注释碰到它就结束）。对象不用 `stdClass` 也不用 `json_decode`
  （分不清 `{}` 和 `[]`、键以 NUL 开头会报错、半个表情符号的转义会整份失败），自己写了解析。
  **整份 PHP 代码没有运行过**，一致性测试没有覆盖它；`BackendTarget.startCommand` 没有端口参数，PHP 的这个值固定写 8080，要带端口的地方用 `startCommandFor(端口)`。

测试里起服务只许绑 `127.0.0.1` 的随机端口；本机没有对应工具时该用例跳过并打印原因，不许联网、不许装包。

## 协作规矩（共用一个工作目录）

- 提交只 `git add 自己的文件`（写明路径），**不许 `git add -A` / `git add .` / `git commit -a`**；提交前 `git status` 看一眼没带别人的。
- 排版只排自己的文件（照 `tool/check.sh` 里排版那一步用的命令和参数，换成自己的文件路径）；不许对整个工程跑 `tool/check.sh --fix`。
- 全量 `tool/check.sh` 只由协调者跑。自己只跑自己的测试文件和 `flutter analyze`（别人的半成品报错不用管，报给协调者）。
- 截图各用各的文件名前缀，只删自己的；截图不进仓库。
- `docs/provider-presets-research.md` 有一份别人的未提交改动，不要动、不要提交。
