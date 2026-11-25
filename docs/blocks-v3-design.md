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

#### 第 4 版加的接口（2026-11-25，只增不改；现有两个宿主一行没动）

完整说明、存盘例子、给第三步的接法见 [blocks-v4-language-design.md](blocks-v4-language-design.md) 的“实施记录·阶段 1·编辑器”。这里只列有什么。

```dart
// 多口积木（口数可增减）——规格（lib/lowcode/logic_blocks.dart）
LcBlockSpec(..., arms: LcArmSpec('否则如果', [条件参数], min: 0, max: 16, tailOptional: true))

// 模型（lib/lowcode/logic_model.dart）
class LcArm { Map<String, dynamic> args; List<LcBlock> body; }
LcBlock.arms            // List<LcArm>，空＝老样子
LcBlock.noElse          // true＝收尾口被收起来了
lcArmArg(段号, 名字)     // '@0:cond'：段参数的地址，argValue / setArgValue / BlockIssue.arg 都认
lcStep(index, {inElse, arm})   // 路径的一步多了 arm（-1＝不在段里）

// 宿主（lib/blocks/block_host.dart），全部可覆盖、有默认实现
String? armSentence(String op);                    // 段横栏上的话：'否则如果 {cond}'、'是 {value} 时'
LcArm newArm(LcBlock block);                       // 点“＋”时新的一段长什么样
List<String> aliasesOf(BlockItemRef item);         // 搜索用的别名
List<BlockItemRef> variantsOf(BlockItemRef item);  // “一块顶多块”：下拉能变成的那几种
List<BlockItemRef> get starterItems;               // 新文档“常用”页的入门积木
BlockCategory(..., groups: [BlockGroup('读', exprs: [...]), ...])   // 第二级小标题
BlockItemRef.hat(id) / .block(op, {preset}) / .expr(kind, {preset}) // 积木盒里的一样东西

// 编辑器（lib/blocks/block_editor_view.dart）
BlockEditorView(host: ..., stars: BlockStars?)     // 加星存哪：应用里用 blockStarsOf(context, '种类')
```

颜色键补了 8 个：function / text / list / dict / classes / error / async / custom（共 20 个）。

**阶段 2（函数和“我的积木”）又加的**——完整语义、存盘例子、接法见 [blocks-v4-language-design.md](blocks-v4-language-design.md) 的“实施记录·阶段 2·编辑器”。全部有默认实现，现有两个宿主一行没动。

```dart
// 规格（lib/lowcode/logic_blocks.dart）
LcExprSpec(..., paramsArg: 'params', hasMouth: true)   // 带参数小块的值 / 带口的值；句子里用 {@params} 定小块的位置
// 模型（lib/lowcode/logic_model.dart、logic_expr.dart）
kLcExprBody = '@body'            // 带口的值里的那串积木，存在表达式对象里
LcBlock.exprMouths               // 这块积木的参数里所有“值上的口”，按出现的先后
lcExprMouthArm(k) / lcExprMouthIndex(arm)   // 路径一步的 arm <= -2 ＝ 第 k 个值上的口

// 宿主（lib/blocks/block_host.dart）
BlockHatParams? hatParams(LcBlockTree tree);            // 这串的帽子是“定义”帽子：参数表
bool setHatParams(tree, List<BlockParam> params, {renamed});
int hatParamUses(tree, String name);                    // 删参数前“有 N 处在用”
Map<String, dynamic>? paramExpr(String name);           // 参数小块拖出来变成的值
void exprParamRenamed(tree, expr, from, to);            // 匿名函数的参数改名
BlockCustomHost? get custom;                            // “我的积木”；null＝没有这一页

// 我的积木（lib/blocks/block_look.dart；外观类型直接用 lib/lang/custom_block.dart 的 CustomBlockLook）
abstract class BlockCustomHost {
  List<BlockCustom> get customs;
  String? create(CustomBlockLook look, List<String> params);
  bool update(String id, CustomBlockLook look, List<String> params, List<int?> origin);
  Object? slotValue(CustomBlockSlot slot);
  int usesOf(String id);  bool remove(String id);  String? definitionOf(String id);
  bool get canWrap;  String? wrapBlocker(tree, from);   // 接线时加的：这一截为什么包不了（默认 null＝能包）
  String? takeNotice();   // 接线时加的：上一次 update 有没有要告诉用户的话（比如“删掉的参数在别处填的 2 格内容一起丢掉了”）；取一次就清空，编辑器用自己的提示条说出来并带“撤销”（默认 null）
  List<String> outerNames(tree, from);  String? wrap(tree, from, look, params);
  List<BlockLookProblem> check(look, params, {editing});
}
bkLookSentence / bkLookArgs / bkLookBlockSpec / bkLookExprSpec   // 宿主把一块自定义积木交给编辑器画时直接用
```

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

它自己带 Scaffold、顶栏（问题、看代码）、画布、底部积木盒（手柄条右边是撤销 / 重做 / 缩放）；会占用 `host.onChanged`，离开时还回 null。
状态拆在四个 mixin 里：`BkEditorCanvas`（平移缩放、点击）、`BkEditorDrag`（拖拽）、`BkEditorEdit`（就地编辑）＋纯逻辑的 `block_drag.dart`（`BkDragSession`）、`block_ops.dart`。

- **拖还是平移（2026-11-24 真机反馈第二轮改）**：原来是“手指落在积木上、移动超过 8px 就拖积木，不用长按”。真机上积木铺满画布时，想滑着看却老把积木拖走，所以改成：
  - 一根手指滑动**一律是平移画布**，起点落在积木上也一样；两指＝缩放（50%–200%，以两指中点为中心）。
  - 拖积木（单块连同它下面的、帽子＝整串、槽里的值积木）要先**按住不动 280 毫秒**（`BkEditorCanvas.longPressAfter`，自定：比一次轻点长、比系统默认的 500 毫秒短）。
    到点的一瞬间震一下（`HapticFeedback.mediumImpact`）、积木被“拿起”（110 毫秒放大到 104% 带投影；系统开了“减弱动态效果”就直接是拿起的样子），之后才跟手。
  - 按住的这 280 毫秒里手指动了超过 8px（`dragSlop`）＝这次判成平移，之后停住也不会再拿起。按住期间落下第二根手指＝缩放。
  - 长按落在哪决定做什么（“拿起”和“换成…”的分工）：直接填的槽（输入框、空槽，里面没有值积木可拿）＝弹“换成…”小卡，不拿起；
    槽里的值积木＝拿起它，拿起后没挪（不到 8px）就松手＝放回原处并弹“换成…”，挪了＝拖走；积木身上别的地方＝拿起这块积木。
  - 不到 280 毫秒就抬起、也没动＝点一下（选中 / 就地编辑 / 下拉菜单，和原来一样）。
  - 拿起以后的吸附、让位、垃圾桶、边缘自动滚动、回弹都没变。
  从积木盒拿（没改，只加了拿起时同样震一下）：按住 0.18 秒或横着拖＝拿出来；竖着滑＝滚积木盒；点一下＝快捷添加。
  积木盒里只有上下滚动一种滑动，横着拖不会和它抢；拿积木是积木盒的主操作，所以按住的时间比画布上短。
- **拖什么**：语句块带走它下面整串（到所在列表末尾），C 形连里面的；帽子＝整串脚本；表达式＝它自己（连里面嵌的）。
  拿起来以后原位滑着合拢（表达式的原槽先显示成默认值）。手上那截从原大“被拿起”放大到 104%（约 110ms，带一点过冲）、带阴影。
  积木盒里的样品一按上去就缩到 96%、略暗（按下态）。
- **吸附**：拼接点离手上那截的左上角 36 以内（画布坐标，缩放后手感一致）就吸。落点处**真的让出位置**：别的积木按“放下以后的样子”重新排，
  落点画成**和手上那块同形的剪影**（同一个轮廓，凹口凸起都在；淡淡的本色＋一圈本色描边，跟着让位淡入；表达式槽是描边高亮）。
  落点换了一个＝`HapticFeedback.selectionClick`。
- **让位是滑过去的（2026-11-24 手感打磨）**：约 150ms、`easeOutCubic`。落点之后的兄弟整块平移，外层 C 形块的口跟着长高 / 缩回（外形一起插值）；
  离开落点时同样滑着合拢；滑到一半换落点，从当时看到的位置接着走，不跳。落点阴影自己不滑。
  两头的位置由纯逻辑 `lib/blocks/block_motion.dart`（`BkMotion`）算——它不排版，只认“同一块积木”并插值；界面只给一个 0–1 的进度。
  每换一个落点只重排落点那一串（别的串沿用拖之前排好的），动画帧不排版；画的时候只画露出来的积木。
- **磁吸（自定）**：有落点时，手上那截在画面上被拉向落点一半（`BkEditorDrag.magnet = 0.5`，跟着让位的进度滑过去），一眼看出它要去哪。
  只是看的：找落点仍按手指的位置算。
- **可接位置的淡提示（自定）**：拖语句时，画布上每个能接的凸起上亮一个很淡的小白点；拖表达式时，每个能放值的槽外面一圈细线。
  “靠近的那个更亮”由落点阴影 / 槽的描边高亮承担（没有另做按距离渐变）。
- **放下**：飞向落点 120ms（`easeOutCubic`，保持 104%）＋ `lightImpact` → 到位那一刻改模型（一次 `host.edit`＝一条撤销记录）→
  画布上落下的那一段轻弹 100ms（缩放 1.04 → 0.98 → 1.0，`bkLandScale`）＋一圈白色描边闪一下淡掉；表达式落进槽里是槽的描边闪一下。合计 220ms。
  帽子（整串）不用飞，松手就在，整串轻弹。点积木盒快捷添加、工具条“复制”出来的积木也轻弹一下。
- **动画不挡手**：松手后的动画（飞向落点、弹回、缩小消失）进行中又按下去 / 又从积木盒拿，动画立刻走完——该改的模型当场改好——新的手势照常接（`settleNow`）。
  只有“删掉这一整串？”的确认框开着时不接。弹回的那 180ms 里底部还是垃圾桶区，要等它结束才换回积木盒（自定：没改）。
- **减弱动态效果**：系统开了（`MediaQuery.disableAnimations`）以后，让位、磁吸、拿起、放下、弹回、删除、轻弹、空画布箭头全部直接到终态。
  放回原处（紧贴原位上下的那个拼接点）＝没动，不产生改动。不能拖进自己里面：拿起来以后的排布里根本没有自己里面的拼接点。
- **放不下**：语句块放在空白处、表达式没放进槽里、嵌套超过上限（`LcBlock.maxDepth`）——约 180ms 晃着弹回原位（原位先滑开让出空，正好落回去）＋ `heavyImpact`＋一句人话
  （“积木要接在事件下面，不能单独放着。”）。**不做散块（自定）**：模型里语句必须在某个事件下面，导出也是这么假设的。
- **表达式**：拖进空槽 / 默认值的槽＝放进去；被拖走的槽恢复成 `host.defaultExpr`；“一串值”（`exprList`）里的一项被拖走＝少一项，只剩一项时换成默认值。
- **表达式拖进已有值的槽：原值不丢（自定，2026-11-24）**。不做散块、不做临时托盘，规则是：
  1. 从槽里拖出来的 A 放进有值 B 的槽＝**交换**：B 回到 A 原来的槽（A 原来是“一串值”里的一项时，B 插回原来的下标，项数不变）。一次改动、一条撤销记录，不提示。
  2. 把里面的一块拖出来盖住包着它的整块（落点是 A 原槽的外层）：B 里已经没有 A 的原槽，没法交换 → B 被换掉。
  3. 从积木盒拖来的新表达式盖住 B：B 被换掉。
  第 2、3 种如果 B 不是那个槽的默认值，给一条提示“原来的值被换掉了。”带**“撤销”**按钮（约 4 秒；期间又有别的改动，按钮就不再生效，免得撤错）。
  逻辑在 `BkDragSession.commit`（`swapped` / `droppedExpr`）。
  六边形槽（要“是否”）放进不是“是否”的表达式：允许，只是落点描边变成警示色（前端翻代码时会自动转类型）。
- **删除**：拖动中积木盒的位置变成垃圾桶区（“拖到这里删除”），手指进去变红、显示会删几块，松手删除（约 160ms 缩小消失＋ `mediumImpact`）。
  删帽子＝删整串，里面有积木先确认。表达式拖进垃圾桶＝原槽恢复默认。从积木盒拿出来又放回积木盒＝不要了，没有改动。
  选中一块以后顶上的小条里也有“复制”“删除”（带子积木的删除先确认）。
- **脚本位置（自定）**：旧文档没有 `x / y` 时按自动排布显示，**只看不写**（不进撤销、不落盘）。用户第一次自己摆位置（拖帽子、从积木盒拖出一个新事件）时，
  同一次改动里把当时所有自动排的脚本的位置一起写下来——从此每串都有固定位置，不会因为别的串动了而重叠。
  之后某一串因为加了积木变高，会把它正下方（水平有重叠）的串往下推同样的高度；只推不拉。点一下积木盒里的事件新建的串不带位置，排在最后。
- **积木盒面板可以上下拖**（2026-11-24 真机反馈第 7 条；`block_dock.dart` 纯逻辑 `BkDockStops`、`block_editor_dock_view.dart` 的 `BkEditorDock`）：
  - 热区：手柄条（44 高，整行）和分类那一行，竖着拖＝改高度；分类横着滑还是翻分类、积木那一片上下滑还是翻积木（手势按方向分开，不抢）。
    面板上沿贴着手指走（认出“竖着拖”之前的那一小段也补上）。
  - 三档：收起＝只剩手柄条（44＋屏幕底部系统手势条）；默认＝`paletteHeight`（248＋手势条）；全展开＝顶到状态栏下沿（盖住顶栏，手柄条在最上面，能拖回来）。
    为了能盖住顶栏，面板和“手上的积木”画在整页上面的一层；顶栏不放进 `Scaffold.appBar`，而是摆在页面最上面（提示条、SnackBar 仍在面板之上）。
  - 松手：速度 ≥ 700 像素 / 秒算甩，去甩的方向上的下一档（不跳档）；否则离某一档 ≤ 28 就吸过去，再否则停在放手的高度（任意高度都能停）。
    去某一档是 260ms、末尾略过冲（约 5%）的滑动，夹在界内；“减弱动态效果”直接到位。滑到一半按住＝从当前位置接着拖。
  - 点手柄条（按钮以外）：收起 ⇄ 默认；比默认高时点一下回默认；比默认矮（没到收起）点一下收起。
  - 撤销 / 重做 / 缩放比例在手柄条右边（各 ≥ 44×44），画布上没有常驻浮条；面板收到只剩手柄条时也在。
  - 让开画布：开始拖积木（从积木盒拿、或拖画布上的）、点积木盒快捷添加成功时，面板比默认高就滑回默认档（之后留在默认档）。
  - 垃圾桶条：拖画布上的积木时底部换成它，高度＝面板高度但不矮于 96（＋手势条）——面板收起时也有地方扔。
  - 记性：`BlockEditorView(dockMemoryKey:)` 给了名字（积木逻辑页 `logic`、后端积木页 `backend`）就在这次运行里记住停在多高，离开再回来还在；不落盘，重开应用回默认档。
  - 画布露出部分不够高时：空画布引导（< 170）先不显示；提示条（< 80）改放面板里。
- **边缘自动滚**：拖着东西停在画布露出部分的边缘 48px 以内约 0.3 秒，画布开始往那边滚，越靠边越快。
- **就地编辑**：点数字 / 文字槽＝那个槽自己变成输入框（数字键盘；回车或点别处＝填好；数字填错不关、就地说原因，这时点别处＝放弃）。
  输入框正好盖在槽上（同样的底色和胶囊形，只多一圈强调色描边，不带投影），**不压旁边的槽**：边打字积木边跟着变宽，右边的东西被推开
  （画布按“预览排布”画：`BlockLayoutEngine.fieldOverride`，只重排这一串；没提交之前模型不动）。字超过槽的最大宽度（150）时在框里横向滚；
  键盘弹出时积木盒让开、画布自动上移到槽露出来。点下拉类的槽＝贴着槽的小菜单；“是 / 否”点一下就翻。
  点空槽、长按一个直接填的槽、或长按拿起一个值积木后没挪就松手＝“换成…”小卡片（按类别分页，里面是画出来的真积木）；原来那里是拼好的表达式时，会把它包进新表达式的第一个空位里（比如给条件套一层“不是”）。
  “一串值”末尾有个小“＋”（`BkSlotLook.add`）点一下加一项；长按某一项，“换成…”卡片底下有“去掉这一项”。
- **快捷添加**：点积木盒里的语句块＝加到选中积木后面；没选中就加到最后一串的末尾。点事件＝新建一串。点表达式只提示“按住它，拖到槽里”。
- **提示条**：一句人话，贴在积木盒上沿之上，不盖画布顶上那串的帽子（面板高到画布放不下时改放在面板里分类那一行下面）；键盘弹出时页面整体上移，它在键盘上面。
  平时约 2.4 秒消失；带“撤销”的约 4 秒。
- **空画布引导**：画布正中一句话＋一个往上走的箭头（出现时动两下就停，不一直动；没有事件却去点语句积木被提醒时再动两下）。开始拖 / 有了第一串就消失。
- **双击空白（自定）**：0.3 秒内在同一处点两下空白＝回到 100%、回到起始位置。选中描边改成细线＋淡光晕。
- **问题**：有问题的积木上直接有标记（画法、点法见下面“校验规则表”一节）；顶栏“问题”带数量，点一条＝画布移过去（必要时调缩放）、选中、描边闪一下（约 0.9 秒淡掉）。
- 这一步给接口加的东西：`BlockHost.argChanged`（参数改了以后宿主顺手联动别的参数）、`BlockHost.newListItem`、`BkSlotLook.add`、
  `layoutScript(tree, body:)`（换一份积木排预览）、`layoutBlockCanvas(…, bodies:, hide:, origins:)`、`BkPaintState.ghostRange / slotColor / flash`。
- 手感打磨加的（都是追加，`BlockHost` 和 `BlockEditorView` 的参数没动）：`layoutBlockCanvas(…, layouts:)`（已排好的串直接用）、
  `BlockLayoutEngine.fieldOverride / scriptLayouts`、`BkPaintState.ghostAlpha / clip / pose / pulse / pulseRange / pulseSlot`、`block_motion.dart`、
  `block_editor_fx_view.dart`（提示条、空画布引导、就地输入框）。
- 截图里浮层外面的粗黑边不是代码画的：`flutter_test` 默认开着 `debugDisableShadows`，把 `Material(elevation:)` 的投影画成一圈实心描边（宽度＝elevation×2）。
  `bk3-*` 截图在用例里临时关掉这个开关，按真机的柔和投影画。

## 后端积木（lib/backend）

### 文件：`backend.lc.json`

```jsonc
{ "version": 1, "kind": "backend", "name": "…", "port": 8080, "language": "node",
  "variables":   [ { "name": "n", "type": "number", "initial": 0 } ],     // 每次请求开始时重置成初始值
  "collections": [ { "name": "todos" } ],                                  // 数据集合：一条是一个对象，自动带数字 id
  "routes": [ { "id": "r1", "method": "GET", "path": "/todos/:id", "x": 24, "y": 24, "body": [ 积木… ] } ] }
```

版本：只用第 3 版的积木写 1；用到第 4 版·第 1 阶段的积木写 2；有“我的积木”（顶层 `functions`）或用到第 2 阶段的积木写 3。旧文档读进再写出字节不变。

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
| `if` | `cond`(表达式) ＋ `body` ＋ `else` | 如果…否则…；第 4 版起中间可以加“否则如果”段（存在积木的 arms 里，每段一个 cond），“否则”可以收起来（noElse） |
| `repeat` | `times`(表达式) ＋ `body` | 重复 N 次（运行时封顶 10000 次） |
| `forEach` | `list`(表达式), `item`(变量名), `index`(直接填的文字，可空：序号放进这个新名字，从 0 数；第 4 版加的) ＋ `body` | 列表的每一项轮流放进变量；不是列表就一遍也不做 |
| `log` | `value`(表达式) | 写一行到服务的标准输出 |
| `fetch` | `url`(表达式), `method`(GET/POST), `data`(表达式，可空，POST 时当 JSON 提交), `into`(变量名，可空) ＋ `body`(成功后) ＋ `else`(失败后) | 请求别的网址，最多等 10 秒；2xx 算成功，响应文字放进变量 |
| `let` | `name`(直接填的文字), `value`(表达式) | 新建变量：在这个接口里新建一个变量，名字自己起；后面的积木都能读、能改 |
| `const` | `name`(直接填的文字), `value`(表达式) | 新建常量：和变量一样，但新建以后不许再改 |
| `do` | `value`(表达式) | 算一下：只为了效果算一个式子，结果不要（比如“取走最后一项”） |
| `switch` | `value`(表达式) ＋ 段(arms) ＋ `else` | 分情况：看一个值等于哪一种情况，就做哪一段；只做第一个对上的 |
| `while` | `cond`(表达式) ＋ `body` | 当…时重复：条件成立就一直做，每做完一遍再看一次条件 |
| `forever` | `body` | 一直重复：一直做下去，直到里面碰到“跳出循环”或“返回” |
| `forCount` | `name`(直接填的文字), `from`(表达式), `to`(表达式), `step`(表达式) ＋ `body` | 从…数到…：含两头；每次加负数就是倒着数；每次加 0 或方向不对就一遍也不做 |
| `forPairs` | `dict`(表达式), `key`(直接填的文字), `value`(直接填的文字) ＋ `body` | 对字典的每一对：按键的顺序（从小到大）一对一对来 |
| `break` | （无） | 跳出循环：马上结束最里面那个循环 |
| `continue` | （无） | 跳过这一轮：这一遍剩下的不做了，直接开始下一遍 |
| `note` | `text`(直接填的文字，可空) | 备注：给自己看的一句话，不做任何事（会变成代码里的注释） |
| `listPush` | `xs`(表达式), `v`(表达式) | 列表末尾加一项：直接改这个列表 |
| `listInsert` | `xs`(表达式), `i`(表达式), `v`(表达式) | 列表里插入一项：位置从 0 数；插在这个位置前面，位置等于项数＝加在末尾 |
| `listSet` | `xs`(表达式), `i`(表达式), `v`(表达式) | 改列表的一项：位置从 0 数；没有这一项会出错 |
| `listRemove` | `xs`(表达式), `i`(表达式) | 删列表的一项：位置从 0 数；没有这一项会出错 |
| `setItem` | `of`(表达式), `key`(表达式), `value`(表达式) | 改某一项 / 某个键：列表填位置（从 0 数），字典填键 |
| `dictSet` | `d`(表达式), `k`(表达式), `v`(表达式) | 设字典的一个键：直接改这个字典；没有这个键就加上 |
| `dictRemove` | `d`(表达式), `k`(表达式) | 删字典的一个键：没有这个键就什么都不做 |
| `return` | `value`(表达式) | 返回：结束这个函数，把一个值交回给调用它的地方（第 4 版·第 2 阶段；只能放在“定义”下面或匿名函数里） |
| `returnNothing` | （无） | 直接结束：不带值地结束这个函数 |
| `callValueStmt` | `fn`(表达式), `args`(一串表达式) | 调用函数：调用一个放在变量 / 参数里的函数，结果不要 |
| `listEach` | `xs`(表达式), `fn`(表达式) | 每一项都做一下：把列表的每一项依次交给函数 |
<!-- be-ops:end -->

<!-- be-exprs:start -->
表达式（`e`）：`text{v}`、`num{v}`、`bool{v}`、`var{name}`、`bin{l, op, r}`（运算符同前端）、`not{x}`、`join{items:[…]}`、
`pathParam{name}`、`query{name}`、`bodyField{name}`、`body{}`、`header{name}`（`name` 都是直接填的文字，读不到是空）、
`dbAll{collection}`、`dbGet{collection, id}`、`dbFind{collection, key, value}`（字段 `key` 等于 `value` 的那些）、`dbCount{collection}`、
`len{x}`、`isNull{x}`、`now{}`（世界标准时间的文字 `2026-11-24T06:00:00Z`）、
`obj{fields:[…]}`、`pair{key, value}`、`field{of, key}`（`key` 是直接填的文字）。

第 4 版·第 1 阶段加的（语言核心；带 `fn` 的是“一块顶多块”，`fn` 的值就是运行时小库的函数名；位置都从 0 数）：
`neg{x}`（取负）、
`round{x, fn}`（取整）、
`math{x, fn}`（绝对值 / 平方根）、
`minmax{a, b, fn}`（最大 / 最小）、
`pow{a, b}`（乘方）、
`random{a, b}`（随机整数）、
`logic{l, op, r}`（并且 / 或者）、
`cond{cond, then, orElse}`（看条件挑一个值）、
`null{}`（空值）、
`isType{x, type}`（是不是某种类型）、
`convert{x, fn}`（转换类型）、
`copy{x}`（复制一份）、
`charAt{s, i}`（第几个字）、
`substring{s, from, to}`（截一段文字）、
`indexOf{sub, s}`（在文字里的位置）、
`textHas{s, fn, sub}`（文字里有没有）、
`replace{s, from, to}`（替换文字）、
`textCase{s, fn}`（去空白 / 转大小写）、
`repeatText{s, n}`（文字重复几遍）、
`split{s, sep}`（把文字切开）、
`template{s, dict}`（填模板）、
`toJson{x}`（写成 JSON 文字）、
`fromJson{s}`（读 JSON 文字）、
`listLit{items}`（列表）、
`range{a, b, step}`（一串数）、
`index{of, key}`（取某一项 / 某个键）、
`listGet{xs, i}`（列表的第几项）、
`listPop{xs}`（取走最后一项）、
`listContains{xs, v}`（列表里有没有）、
`listIndexOf{v, xs}`（在列表里的位置）、
`listSlice{xs, from, to}`（截一段列表）、
`listConcat{a, b}`（两个列表接起来）、
`listOrder{xs, fn}`（倒过来 / 排序）、
`listJoin{xs, sep}`（把列表连成文字）、
`dictGet{d, k}`（字典里某个键的值）、
`dictHas{d, k}`（字典里有没有这个键）、
`dictPart{d, fn}`（所有的键 / 值）、
`dictMerge{a, b}`（两个字典合起来）。

第 4 版·第 2 阶段加的（函数和“我的积木”）：
`param{name}`（读一个参数）、
`lambda{}`（匿名函数：参数名存在 `params` 里，里面的积木存在 `@body` 里）、
`lambdaExpr{body}`（短函数：参数名存在 `params` 里，`body` 是一个式子）、
`funcRef{fn}`（“我的积木”本身当成值，`fn` 是函数的 id）、
`callValue{fn, args}`（调用放在变量 / 参数里的函数，得到返回值）、
`listMap{xs, fn}`（每一项变一下）、
`listFilter{xs, fn}`（挑出符合的）、
`listReduce{xs, fn, init}`（累起来）、
`listFind{xs, fn}`（找第一个符合的）、
`listEvery{xs, fn}`（是不是每一项都符合）、
`listSome{xs, fn}`（有没有一项符合）、
`listSortBy{xs, fn}`（按算出来的分排序）。
<!-- be-exprs:end -->

- 第 4 版·第 2 阶段：文档顶层多一个 `functions`（“我的积木”的定义，非空才写；用到了版本升到 3）。调用一块“我的积木”不在上面两张表里——
  它的 op / e 是 `call:` 加函数的 id（单独成句是积木、要返回值是表达式），参数按参数名存，规格跟着每份文档里的定义走（`lib/backend/backend_func_table.dart`）。
  完整的存盘格式和取舍见 [blocks-v4-language-design.md](blocks-v4-language-design.md) 的“实施记录·阶段 2·接线”。

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
| Go | `net/http`；值是 `any`，数字一律 `float64`，列表是 `*lc.List`（积木第 4 版阶段 1 从 `[]any` 改的，为了“原地改列表”是同一个）；JSON 编码自己写（解析用 `encoding/json` 再按规矩收拾）；生成 `go.mod`（模块名写死 `lcbackend`、`go 1.18`） | 能（`~/workspace/tools/gosdk/go/bin/go` 1.25）——**已做，一致性测试通过**，生成物是 gofmt 规范格式、`go vet` 通过 |
| Java | `java.net.ServerSocket` 上自己读 HTTP（JSON 也自己带一个小实现）；值是 `Object`，数字一律 `Double`；`javac` 直接编译，不用 Maven / Gradle | 能（`~/workspace/tools/jdk`，JDK 21）——**已做，一致性测试通过** |
| PHP | 自带开发服务器 `php -S 0.0.0.0:端口 server.php` 的路由脚本；值是 null / bool / float / string / `LcList`（列表；积木第 4 版阶段 1 从 PHP 数组改成对象，为了“原地改列表”是同一个）/ `LcObj`（对象）；JSON 解析自己写 | 不能（本机没有 php）——**已做，只做了结构检查，未实际运行**（`verified: false`） |
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

## 校验规则表（积木的语法检查，2026-11-24）

两套积木共用一个校验结果类型 `LcLogicIssue`、一张规则表 `lib/lowcode/logic_rules.dart`（`kLcRules`）。
每条问题带：规则编号（`rule`）、级别、人话原因（`problem`）、建议（`advice`）、在哪（`handlerId` + `path` + `arg` + `exprPath`，精确到积木上的哪一格）。
编号一旦发出去不改、不复用。G＝两套都有，P＝只有页面逻辑，S＝只有后端，B＝自定义积木的外观（第 4 版·第 2 阶段），L＝语言核心的检查（第 4 版·第 1 阶段加的，现在只有后端的新积木用到，编号照 `lib/lang` 的检查表）。

**定级原则（两套一致）**：运行起来一定不是想要的结果＝**错误**（拦生成）；能跑、但多半不是本意＝**警告**（不拦）；类型说不准的一律不报。

| 编号 | 规则 | 页面逻辑 | 后端 | 说明 |
| --- | --- | --- | --- | --- |
| G01 | 必填的格子空着（条件、数值、文字、控件、变量、集合…） | 错误 | 错误 | 可选的格子（如“结果放进变量”）空着不报 |
| G02 | 格子里的值不对（固定选项里没有这一项等） | 错误 | 错误 | |
| G03 | 用了没有声明 / 已经删掉的变量 | 错误 | 错误 | |
| G04 | 变量名非法 / 重名 / 类型不认识 | 错误 | 错误 | 各语言的保留字不用报：生成时变量一律带前缀（后端 `v_名字`），撞不上 |
| G05 | 不认识的积木 | 警告 | 警告 | 生成时跳过它（老文档 / 新版本做的） |
| G06 | 不认识的值 | 警告 | 警告 | 生成时当空值 |
| G07 | 套得太深 | 错误 | 错误 | |
| G08 | 不能嵌积木的地方放了积木 | 警告 | 警告 | |
| G09 | “加上”用在不是数字的变量上 | 错误 | 警告 | 沿用原来各自的级别 |
| G10 | 值的类型对不上 | 见下 | 见下 | 数字格里直接填了不是数字的文字＝错误；数字格里放“是 / 否”、条件格里放数字 / 文字、“等于 / 不等于”一边“是 / 否”一边不是＝警告；`any`（没声明类型的变量、请求里读来的东西、输入的内容）不报 |
| G11 | 事件下面是空的 | 警告 | — | 帽子自己还有别的问题时先不提这条。后端的空接口归 S11 |
| G12 | 重复的次数不对 | 负数＝错误；小数、超过 10000＝警告 | 同左 | 只查直接填的数；运行时会夹在 0–10000 |
| G13 | 除以 / 取余常量 0 | 警告 | 警告 | 运行时结果是 0，不会崩 |
| G14 | 网址没填或不像网址 | 跳转：空 / 不像＝警告；请求：空＝错误，其余＝警告 | 空＝错误；没填完 / 不是 http(s) 完整网址＝警告 | 只查直接填的文字；拼出来的不查。后端运行时本来就只请求 http / https |
| P01 | 控件已经不在页面里 | 错误 | — | |
| P02 | 事件没选控件 | 错误 | — | |
| P03 | “内容变化”挂在不是输入框的控件上 | 警告 | — | |
| P04 | 不认识的事件 | 错误 | — | |
| P05 | “输入的内容”用在不是输入事件的地方 | 错误 | — | |
| P06 | 控件没有这个属性 | 警告 | — | |
| P07 | 同一个控件的同一个事件有两串 | 警告 | — | 允许：两串都会执行（按先后），所以只提醒 |
| S01 | 端口不在 1–65535 | — | 错误 | |
| S02 | 选的语言没有生成器 | — | 警告 | |
| S03 | 集合名非法 / 重名 | — | 错误 | 集合名在生成的代码里是字符串，不会撞保留字 |
| S04 | 用了没有的集合 | — | 错误 | |
| S05 | 请求方式不认识 | — | 错误 | |
| S06 | 路径非法（不以 / 开头、有空格或非法字符、参数名非法 / 重复） | — | 错误 | |
| S07 | 方式 + 路径重复（`/users/:id` 和 `/users/:name` 也算同一个） | — | 错误 | |
| S08 | 被前面的接口挡住（如 `/todos/:id` 排在 `/todos/count` 前面） | — | 警告 | |
| S09 | 取了路径里没有的参数 | — | 错误 | |
| S10 | “返回”后面还有积木（死代码） | — | 警告 | |
| S11 | 有的走法没有“返回” | — | 警告 | 保守的走法分析：“如果 / 否则”两边都返回才算返回，循环里的返回不算。定成警告是因为运行时没有返回就回 204 空响应，不会挂住；一块“返回”都没有的接口当作有意回 204，不提示 |
| S12 | 对象的字段不对（放了不是字段的东西、“一个字段”放在对象外面＝错误；字段名重复＝警告，后面的盖掉前面的） | — | 见左 | 字段名空着按 G01 报（错误） |
| S13 | 状态码直接填的数不是 200–599 的整数 | — | 警告 | 运行时不在 200–599 一律当 200（1xx 也是），所以范围是 200–599 而不是 100–599 |
| L04 | “跳出循环 / 跳过这一轮”不在循环里 | — | 错误 | 画在这块积木上。“重复 N 次”“对每一项”“当…时重复”“一直重复”“从…数到…”“对每一对”里面都算在循环里 |
| L01 | 调用的积木 / 函数不存在（定义被删了，或“这块积木本身”指向一块不在的积木） | — | 错误 | 画在那块调用上（第 4 版·第 2 阶段，下同） |
| L02 | 参数表不对：参数名空着 / 重名 / 用了保留的名字、“剩下的全收”不是最后一个、读了这里没有的参数 | — | 错误 | 画在定义的帽子上，或读参数的那一格上 |
| L03 | “返回”用错了地方：接口里（不在匿名函数里）放了“返回 (值)”＝错误；把一块不交回结果的积木当值用＝警告（得到的是空） | — | 见左 | 接口里要用“返回响应” |
| L09 | 同一个接口里新建了两个同名的变量 / 常量（也包括和“变量”里声明的、和循环自己起的名字重名） | — | 错误 | 画在后面那块的名字格上。一个接口里只有一层：在“如果”里新建的，出了“如果”还在；所以两个分支各新建一个同名的也算重名 |
| L11 | 给“新建常量”建出来的名字重新赋值 | — | 错误 | 画在“把变量设为”那块的变量格上 |
| L13 | “一直重复”或条件写死成“是”的“当…时重复”，里面既没有“跳出循环”也没有“返回” | — | 警告 | 画在循环那块上。能生成、能跑，但这个接口永远不回应 |
| L14 | 没人用的自定义积木 / 没用到的参数 | — | 警告 | 画在定义的帽子上；能生成、能跑 |
| L15 | 自定义积木 / 匿名函数里放了“返回响应”“请求别的网址”，或读了请求（路径参数、网址参数、请求内容、请求头） | — | 错误 | 画在那一块上。函数不在哪个接口里跑：要用就在接口里读出来当参数传进去 |
| B01–B09 | 自定义积木的外观不对：没有名字（B01）、话里的槽不是参数（B02）、参数没有槽（B03）、同一个参数出现两次（B04）、槽的设置和参数对不上（B05）、下拉选项不对（B06）、先放的内容和槽的种类对不上（B07）、用了还不能用的外观（B08）＝错误；样子和定义对不上（B09，比如声明成“值”却不交回结果）＝警告 | — | 见左 | B＝自定义积木外观（`lib/lang/custom_block.dart` 的 `validateLook`）；画在定义的帽子上。“新建 / 编辑积木”页里当场就查，所以正常操作碰不到错误级的，主要防手改文件和 Agent 写入 |

**原有规则在第 4 版新积木上怎么算**：G01 必填格——新积木每个格子都查（“对每一项”的“序号叫”、备注的字可以空）；G02 不认识的积木照旧；
G03——读、改一个名字时，它得是文档里的变量，或者这个接口里**前面**已经新建过的名字（新建变量 / 常量、循环自己起的名字），否则报在那个格子上；
G08 套得太深照旧；G10——要数字的格子里直接放了固定文字＝错误，条件格里放了固定的数字 / 文字＝警告，说不准类型的不报；
S10——“返回”“跳出循环”“跳过这一轮”后面同一串里的积木都算做不到；S11——“如果…否则如果…否则”每一段都返回才算返回，“分情况”要有“都不是”并且每段都返回，
“一直重复”里没有“跳出循环”的算“不会走到后面”。每条都带规则号、原因、建议三段（`kLcRules`）。

没有做成规则的一样（**无条件的无限循环**原来也在这里，第 4 版有了“一直重复”以后做成了 L13）：**没接在帽子下面的散块**（每块积木都属于某个事件 / 接口）。

**什么时候查**：每次改动（`BlockHost.revision` 变了）当场重查，内容没变不查（拖动、平移、缩放都不查）。
`BlockHost.issues` 永远是照现在的内容查的（问题列表、拦截用）；画布画标记用 `liveIssues`：连着两遍都超过 8 毫秒时，
连续改动期间先画上一次的结果，停手 180 毫秒后再查并重画（`BlockIssueCache`）。实测耗时：200 块积木校验一遍：页面逻辑约 2.1 ms、后端约 1.9–2.1 ms（开发机 1.5 核、预热后 50 遍取平均；没预热、机器满载时测到过约 10 ms；真机未测）

**画在积木上**（`lib/blocks/block_issue_view.dart`，颜色取积木调色板的 `error` / `warning`＝主题的危险 / 警告色）：
- 错误：沿积木轮廓一圈 2px 细红线 + 右上角红色圆角标；警告：只有右上角黄色三角角标，不描边。角标里都是“!”，形状也不同，不只靠颜色。
- 有问题的那一格外面一圈同色虚线。
- 和别的描边分得开：选中是细线 + 淡光晕（选中色），吸附是整块高亮，问题是红 / 黄 + 角标。
- 点角标＝选中那块、贴着角标弹小卡（每条：原因、建议、规则编号；多条都列）。选中积木时工具条上还是只写最要紧的一条。

**问题列表**（`showBlockIssues`）：标题“N 个问题”，一句总述；先“错误”后“警告”两段，段里按事件 / 接口分组；点能定位的一条＝关列表、跳过去、闪一下。没有问题＝“没有发现问题”。

**有错误时（两套一个规矩）**：有“错误”级问题就不生成新代码，上一次生成的原样留着；界面统一写“有 N 个错误，代码没有更新”（`blockErrorsHeadline`）并给“查看问题”。只有警告照常。
- 后端：`regenerateBackend` 一个文件都不写，返回 `blocked: true`（`backend.lc.json` 照常保存）；页面副标题（顶栏窄，用短说法“N 个错误，没更新”）、底部提示（刚出错时一次）；“运行”“代码生成情况”被拦下，弹说明 + “查看问题”。
- 页面逻辑：`saveLowcodePage` 照常写 `page.lc.json` / `index.html` / `style.css`，`logic.js` 不动（`lib/lowcode/logic_gate.dart`）；积木逻辑页标题下一行短说明；Vue / React 导出被拦下并说去哪修。
- “看代码”有错误时注明下面只是预览。
- Agent 工具：`backend_update_blocks` 有错误拒绝保存并列出问题（原有行为）；`lowcode_update_page` 照常保存，把校验问题（带规则编号和建议）接在工具结果后面，并说明 logic.js 没有更新。

**老文档**：校验只读不改；缺字段、类型不对、不认识的积木都只是标出来。

## 悬浮顶栏（全应用一套，2026-11-24 霜霜两轮真机反馈）

第一轮只给“搭建”相关页面做了沉浸式顶栏（`immersive_bar.dart`）；第二轮她要求**所有页面的顶栏都是“添加渠道”页那个高度，按钮和信息悬浮在页面上**。
两套并成了一套，`immersive_bar.dart` 已删。

- 部件都在 `lib/ui/top_bar.dart`：`PageBar`（顶栏）、`BarScrim`（渐隐遮罩）、`BelowBar`（不能滚的正文）、`BarExtra`（顶栏下面固定的那一条多高）。
  外壳里的页面用 `ShellAppBar`（`lib/ui/shell.dart`，PageBar + 汉堡按钮 + 工作区名）。
- 高度 **64**（`PageBar.kHeight`，不含状态栏）：左圆按钮 44，离左 16、上下各 10；标题左对齐 14 号 + 一行小字；右边圆按钮或操作胶囊。
- 顶栏没有底色、分隔线、阴影，状态栏透明、图标颜色跟主题。每个 Scaffold 都 `extendBodyBehindAppBar: true`，内容从屏幕 y=0 铺起。
- **内容要留多少**只从 `PageBar.insetOf(context)` 取（状态栏 + 64 + `BarExtra`）。能滚的内容把它加进顶部内边距，滚动时从顶栏下面穿过；
  终端、编辑器、预览、带页签的页面这类不能滚过去的正文包一层 `BelowBar`，整块从顶栏下沿开始。
- **可读性**：全应用同一种——`BarScrim`，页面底色的渐隐遮罩：状态栏段实色，标题段 98%，从按钮下沿附近淡出，顶栏下沿再往下 20 全透明。
  它不接手指。标题不加胶囊（画布页上一轮的贴左小胶囊也去掉了）。
- 顶栏空白处不接手指：落在那里等于落在下面的内容 / 画布上。
- 画布类页面拿 `PageBar.insetOf` 当“上面看不见的一段”：
  - 积木画布（`BlockEditorViewState.coveredTop`）：`pan` 为零时画布原点在顶栏下沿（`viewOrigin`）；`jumpTo`、缩放中心、
    拖到边缘自动滚、就地输入框、选中工具条、空画布引导都按露出来的那一段算。`pan` 的含义没变（相对起始位置）。
  - 低代码画布（`CanvasView.topInset`）：页面顶边起始在顶栏下沿、往下拖不过它；“适应屏幕”回到那里；往上滚时页面从顶栏下面滑过去。
- 低代码画布的“怎么看”小工具是浮在画布**底部**的两个小胶囊，页面底边最低停在它们上沿（`kCanvasToolsInset = 56`）；拖组件时它们让开。
- 积木编辑器的顶栏放在自己的 Stack 里（不进 `Scaffold.appBar`）：积木盒面板全展开时要盖住顶栏（上限是状态栏下沿），往下拖回来顶栏又露出来。
- “页面 | 后端”切换条（两样都有的项目）排在顶栏**下面**一行（顶栏的位置全应用一致）；它占的 48 经 `BarExtra` 告诉里面的页面，遮罩也盖到它下面。
- 测试：`test/topbar_unified_test.dart`（全应用守门）、`test/topbar_test.dart`、`test/immersive_bar_test.dart`（画布类页面，无安全区 + 状态栏 30 / 手势条 20 各一组）。

## 协作规矩（共用一个工作目录）

- 提交只 `git add 自己的文件`（写明路径），**不许 `git add -A` / `git add .` / `git commit -a`**；提交前 `git status` 看一眼没带别人的。
- 排版只排自己的文件（照 `tool/check.sh` 里排版那一步用的命令和参数，换成自己的文件路径）；不许对整个工程跑 `tool/check.sh --fix`。
- 全量 `tool/check.sh` 只由协调者跑。自己只跑自己的测试文件和 `flutter analyze`（别人的半成品报错不用管，报给协调者）。
- 截图各用各的文件名前缀，只删自己的；截图不进仓库。
- `docs/provider-presets-research.md` 有一份别人的未提交改动，不要动、不要提交。
