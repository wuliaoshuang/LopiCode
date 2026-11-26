# B · 类型系统：实现交接说明（核心 1 第一段）

写给接手的两段：**生成器那一段**（Go / Java 带原生类型的生成、16 个程序五种语言真跑）和**界面那一段**（积木上标红、一键修）。
设计在 [B-type-system.md](B-type-system.md)；这里只说**代码里实际是什么样**。分支 `v5-types`，写于 2026-11-26。

这一段只动了 `lib/lang/`（纯 Dart），外加后端文档上的一个字段、一座到 G10 的桥。没做界面，没做任何新的生成路径。

---

## 1. 文件一览

| 文件 | 是什么 |
| --- | --- |
| `lib/lang/rules.dart` | 规矩版本的常量、**新建文档用哪个版本的开关**、读存盘值 |
| `lib/lang/types.dart` | `LType`、`LKind`（类型本身） |
| `lib/lang/types_json.dart` | 类型的存盘读写 `lTypeToJson` / `lTypeFromJson` |
| `lib/lang/ast.dart`、`ast_v5.dart` | 语法树；`ast_v5.dart` 是这一期新加的节点 |
| `lib/lang/type_world.dart` | 声明表 `LTypeWorld`（记录、枚举、变体、接口、类、函数、别名）和类型之间的运算（能不能放进去、合并、代入） |
| `lib/lang/type_issue.dart` | 规则表、问题、一键修、运行时检查点、边界上的转换——**纯数据，两段都从这里拿** |
| `lib/lang/rt_v2.dart` | 版本 2 里小库函数的类型签名 |
| `lib/lang/typecheck.dart` ＋ 6 个 `typecheck_*.dart` | 检查器（推断＋T 规则），入口 `checkModuleTypes` / `checkTypes` |
| `lib/lowcode/logic_type_bridge.dart` | 槽类型 `LcType` ↔ `LType` |
| `lib/backend/backend_model.dart` | `BeDocument.rules` 字段 |
| `lib/backend/backend_templates.dart` | `backendStarterDocument(…, rules:)` 读开关 |

测试：`test/rules_v1_frozen_test.dart`（版本 1 钉子）、`test/lang_typecheck_proto_test.dart`（和原型对照）、`test/lang_typecheck_rules_test.dart`（新规则、一键修、给生成器的结果、存盘、规矩版本、桥）；`test/support/proto_lc.dart` 是把原型的 `prog.lc` 读成 Dart 语法树的小工具（写新用例很方便，可以直接用）。

---

## 2. 类型的数据结构

```dart
LType(kind, {of, args, name, nullable, waits})
```

| 类型 | 怎么表示 | `show()` 的样子 |
| --- | --- | --- |
| 整数 | `LType.integer`（`LKind.integer`） | 整数 |
| 小数 | `LType.number`（`LKind.number`，就是老的“数字”） | 小数 |
| 文字 / 是否 / 空 | `LType.text` / `LType.boolean` / `LType.nul` | 文字 / 是否 / 空 |
| 可空 | 任何类型 `nullable: true`；`t.orNull()`、`t.nonNull()` | 整数? |
| 列表〈T〉 | `LType.listOf(t)`，T 在 `of` | 列表〈整数〉 |
| 字典〈V〉 | `LType.dictOf(v)`，V 在 `of`（键恒为文字，内存里不存；存盘写两个） | 字典〈整数〉 |
| 记录 / 枚举 / 变体 / 接口 / 类 | `LKind.record / enumeration / variant / interface / object`＋`name`，类型实参在 `args` | 用户、栈〈整数〉 |
| 函数 | `LType.func([参数…, 返回])`，在 `args`；`t.params`、`t.returns`；`waits`＝要不要等（null＝不知道） | (整数, 文字) → 是否 |
| 类型变量 | `LType.variable('T')` | T |
| 任意 / 永不 | `LType.any` / `LType.never` | 任意 / 永不 |
| 还没解析的名字 | `LType.ref('用户')`——标注里写的名字，检查器按声明表换成上面某一种 | |
| 待定 | `LKind.hole`，只在推断过程中有，**结果里不会出现**，不存盘 | |

- `toString()` 是**老写法**（“数字”“（可以是空）”），版本 1 的提示语在用，不能改。给人看版本 2 的类型一律用 `show()`。
- 老的 `join` / `clashesWith` 原样保留（版本 1 的检查器 `analyze.dart` 在用）。版本 2 的合并、能不能放进去在 `LTypeWorld.join` / `ok`。
- `kLangMaxInt = 9007199254740991`：整数的范围是正负这个数。

存盘（`types_json.dart`）：`{"k": 标签, "args": […], "name": …, "nullable": true, "waits": true}`，没有的不写。标签名：`any number text bool null list dict fn object future int record enum variant interface var never`。老的 `of` 能读。坏的东西读成“任意”，不抛异常。

---

## 3. 语法树新加了什么

都在 `ast_v5.dart`，三个封闭的基类，老代码的 `switch` 里各多一个分支：

- **声明** `LTypeDecl`：`LRecordDecl(name, fields, typeParams)`、`LEnumDecl(name, cases)`、`LVariantDecl(name, cases:[LVariantCase(name, fields)], typeParams)`、`LAliasDecl(name, type)`。都带 `isPublic`、`codeName`。
- **语句** `LStmtV5`：`LMatch(subject, arms:[LMatchArm(caseName, binds, body)], orElse)`——“看是哪种情况”。
- **式子** `LExprV5`：`LRecordNew(type, fields)`、`LRecordCopy(base, fields)`（复制并改）、`LEnumValue(type, name)`、`LVariantNew(type, caseName, args)`、`LCast(value, type)`（当成）、`LAscribe(value, type)`（就当它是，只给类型、不做转换）。
- 老节点加的字段：`LFuncDecl.typeParams / codeName`；`LClassDecl.typeParams / isOpen / isPublic / codeName`；`LInterfaceDecl.isPublic / codeName`；`LNew.typeArgs`；`LSuperSend.ctor(args)`（调父类的“创建时”）；`LFieldDecl.init` 可以没有。
- 泛型的约束：`LTypeParam(name, bound)`，`bound` 是 `kBoundComparable`（能比大小）、`kBoundKey`（能当字典的键）或没有。

**老的生成器遇到这些新节点会抛 `LangUnsupported`**（“…要走严格规矩的生成路径，这条路还没有接上”），不会生成出错的代码。老的检查器 `analyze.dart` 对新节点只管名字（声明了什么、用了什么），类型一律当任意。

语法树本身**没有存盘格式**——存在盘上的是积木文档（`backend.lc.json` 里的积木），由 `backend_lower_lang.dart` 翻成语法树。所以“记录、枚举、变体怎么存”等于“它们的积木长什么样”，见第 7 节。

---

## 4. 检查结果的接口

```dart
LTypeResult checkModuleTypes(LModule module);
LTypeResult checkTypes({decls, main, scripts: [LTypeScript(name, body, vars: {名字: 类型})], outer: {名字: 类型}});
```

`checkTypes` 是给“一份文档有一批声明＋若干段各自独立的脚本”用的（后端：`decls`＝“我的积木”，每个接口一个 `LTypeScript`，`outer`＝文档变量和 `req` 这类宿主给的东西）。任何输入都不抛异常。

### 4.1 界面那一段怎么用

`result.issues` 是 `List<LTypeIssue>`，按发现的先后（T12 排最后）：

| 字段 | 是什么 |
| --- | --- |
| `code` | 规则号 `T01`…`T18`；`issue.rule` 能拿到规则表里的标题、默认建议 |
| `level` | `error`（不让生成）/ `warning` / `hint` |
| `message` | 提示语原文，直接显示 |
| `where` | 在哪个函数里：“主”、函数名、“类.方法”、脚本的名字 |
| `src` | **哪块积木哪个槽**：`LSrc(script, block, slot)`。出错的节点自己带了位置就用它的，没带就用包着它的那一句的 |
| `node` | 出错的那个语法树节点 |
| `argIndex` | 是调用的第几个参数（从 0 数），不是参数的事就没有 |
| `fixes` | 一键修，`List<LFix>` |

`LSrc` 怎么对回积木：后端翻译时（`backend_lower_lang.dart` 的 `_src`）给每个节点记的是 `script`＝接口 id、`block`＝来源表 `spots` 里的序号、`slot`＝参数名。现成的对照代码是 `backend_validate_lang.dart` 的 `beMapLangIssues`（把老检查器的问题对回积木），T 规则照着写一份就行：`spots[int.parse(src.block)]` 给出积木的路径和参数。

一键修 `LFix(kind, label, target, params)`：`label` 是按钮上的字；`target` 是要改的那个节点（它的 `src` 就是要改的积木）；

| `kind` | 要做什么 | `params` |
| --- | --- | --- |
| `wrapToText` | 外面包一层“变成文字” | |
| `wrapToInt` | 外面包一层“取整” | |
| `wrapParseInt` | 外面包一层“变成整数（变不了就是空）” | |
| `wrapOrElse` | 外面包一层“是空就用 ▢” | |
| `wrapMust` | 外面包一层“一定不是空” | |
| `compareNotZero` | 换成“▢ ≠ 0” | |
| `addMatchCases` | “看是哪种情况”补上缺的情况 | `cases`：名字的列表 |
| `addMatchElse` | 加一个“其余” | |
| `addRecordFields` | 新建记录补上缺的字段 | `fields`：名字的列表 |
| `removeRecordField` | 删掉记录里没有的字段 | `field` |
| `useRecordCopy` | 改字段 → 换成“复制并改” | `field` |

设计 6.2 的七种是前七行里的 `wrapToText / wrapToInt / wrapParseInt / wrapOrElse / compareNotZero / addMatchCases / addRecordFields`；其余四种是顺手给的。一个问题可能有好几个修法（比如可空的：`wrapOrElse` 和 `wrapMust`），也可能没有。

### 4.2 生成器那一段怎么用

| 要什么 | 怎么拿 |
| --- | --- |
| 一个式子的类型 | `result.typeOf(e)`；没检查到的（它前面已经报错跳过了）是 null |
| 这个式子要放进什么类型的地方 | `result.wantOf(e)` |
| 放进去时要做的转换 | `result.coercionOf(e)` → `LCoercion(kind, from, to)`：`widen`（整数→小数）、`check`（任意→确定类型，要查）、`checkEach`（任意→列表〈T〉/字典〈T〉，逐项查）、`snapshot`（列表/字典→任意，拍快照）、`toNullable`（Go 里可空要换表示）；不用转是 null |
| 一个运算该用哪个小函数 | `result.opOf(node)`：`iadd isub imul idiv imod ineg`（整数）、`fadd fsub fmul fdiv fpow fneg`（小数）、`dadd dsub dmul ddiv dpow didiv dmod`（有一边是任意）、比大小 `ilt flt tlt dlt`（整数/小数/文字/任意；`le gt ge` 同理，共 16 个）、`eq ne`、取改 `listAt dictGet dynGet listSetAt dictSet dynSet listPush dynPush` |
| 泛型调用这一次的类型变量 | `result.typeArgsOf(call)` → `{'T': 整数, 'U': 文字}` |
| 每个函数 / 方法 /“创建时”的签名 | `result.funcs`：记号 → `LTypedSig(params, returns)`。记号：函数是名字，方法是“类.方法”，创建时是“类.创建” |
| 每个变量的类型 | `result.vars`（`LVarInfo(scope, name, type, kind)`）或 `result.variable(scope, name)`。`scope`：“主”、函数的记号、脚本名；匿名函数里的变量用 `result.lambdaScope(lambda)` 拿它那一层的名字。`kind`：`local temp param loop matchBind error global host` |
| 声明（字段顺序、情况列表、谁继承谁） | `result.world`（`records / enums / variants / interfaces / classes / funcs / aliases`） |
| 要在运行时检查的地方 | `result.checks`：`LRuntimeCheck(kind, node, type)`，见下表 |
| 能不能直接用这些结果 | `result.hasErrors` 为真就不要生成；`result.shared` 不空说明有同一个节点对象出现了两次，见第 8 节 |

运行时检查点（编号和设计第 8 节一致）：

| # | `LCheckKind` | 记在哪个节点上 | 设计里的小函数 |
| --- | --- | --- | --- |
| 1 | `anyToType` | 被转换的那个式子，`type`＝要查成的类型 | `asInt(x)` 一类 |
| 2 | `anyToContainer` | 同上，`type`＝列表〈T〉/字典〈T〉 | `asListOf(x, …)` |
| 3 | `listIndex` | 取第 i 项的式子 / 改第 i 项的那句 | `at` / `setAt` |
| 4 | `must` | “一定不是空”那个调用 | `must(x)` |
| 5 | `intOverflow` | 整数的加、减、乘、取负 | `iadd / isub / imul` |
| 6 | `divideByZero` | 整除、余、除 | `idiv / imod / fdiv` |
| 7 | `floatToInt` | “取整”那个调用 | `ftoi` |
| 8 | `dynamicArith` | 两边有任意的算术、比大小 | `dadd` 一类 |
| 9 | `downcast` | “当成 某个类”的式子，`type`＝那个类 | 各语言自己判断 |

1、2 两种和 `coercionOf` 的 `check` / `checkEach` 是同一件事的两种拿法（一个按清单、一个按式子）。

`rt_v2.dart` 的 `kLangRtV2` 是版本 2 里小库函数的签名（名字沿用 `rt.dart`）。`kLangRtV2New`＝`orElse must toInt parseInt codePoints` 是**新名字，五种语言的小库里还没有实现**。

---

## 5. 规则清单

规则表 `kTypeRules`（`type_issue.dart`）。提示语都是照设计 6.4 的口气写的整句人话；原型有的那些，文字和原型逐字相同。

| 号 | 报什么 | 级别 | 一键修 |
| --- | --- | --- | --- |
| T01 | 这里要 X，放进来的是 Y | 错 | 变成文字 / 取整 / 变成整数 |
| T02 | 可能是空，没判断就用 | 错 | 是空就用 ▢ / 一定不是空 |
| T03 | “看是哪种情况”没写全 | 错 | 补上缺的情况 / 加“其余” |
| T04 | 新建记录缺字段、多字段 | 错 | 补字段 / 删字段 |
| T05 | 泛型的条件不满足（要能比大小…） | 错 | |
| T06 | 运算的两边不对 | 错 | |
| T07 | 参数个数不对 | 错 | |
| T08 | 没有这个名字（变量、字段、方法、情况） | 错 | |
| T09 | 条件要“是/否” | 错 | ▢ ≠ 0 |
| T10 | 记录建好以后不能改 | 错 | 换成“复制并改” |
| T11 | 说实现了接口，方法没实现全 | 错 | |
| T12 | 看不出里面放什么，先当任意 | 提醒 | |
| T13 | 给别人用的函数没标全 | 警告 | |
| T14 | 往“任意”里的列表 / 字典加东西，改不到原来那份 | 警告 | |
| T15 | 这个“当成 …”永远不会成功 | 错 | |
| T16 | 整数写得太大 | 错 | |
| T17 | 继承了没勾“可以被继承”的类 | 错 | |
| T18 | 重写的方法和父类的对不上 | 错 | |

一处错只说一句：报过错的式子类型记成“永不”，后面不再连带报。

---

## 6. 规矩版本和开关

- 常量：`kLangRulesLoose = 1`、`kLangRulesStrict = 2`、`kLangRulesLatest`、字段名 `kLangRulesField = 'rules'`，都在 `lib/lang/rules.dart`。
- 文档上：`BeDocument.rules`（整数）。存盘在最外层 `"rules": 2`；**是 1 就不写**，所以旧文档存出来和以前一个字节不差。读：没有、不是整数、小于 1 都当 1；比 2 大的原样留着。`clone()` 带着。
- **开关**：`kLangRulesForNewDocs`（`lib/lang/rules.dart`）。新建后端积木文档唯一的入口 `backendStarterDocument(name, {language, port, rules = kLangRulesForNewDocs})` 读它；界面层（`lib/ui/backend_screen.dart` 两处）不用改。
- **现在开关是 1。** 原因：严格规矩的生成路径还没有。现在就把新文档标成 2，它实际还是按老规矩检查、生成；等生成路径接上，这些“版本 2”的文档行为又变一次——正好违反版本号要保证的事。
- **谁来翻成 2**：生成器那一段，在“版本 2 的后端文档真的走严格检查＋严格生成”接上的同一个提交里，把这一行改成 `kLangRulesStrict`。
- **翻成 2 以后哪些现有断言会坏**：我临时翻过去跑了全量测试，结果见本节末尾的表。
- 版本 1 的文档：不调用 `checkTypes`，校验结果、五种语言的生成结果逐字不变。钉子是 `test/rules_v1_frozen_test.dart`（4 份样本文档 × 5 种语言每个生成文件的指纹、`validateBackend` 逐条原文、7 组语言核心用例的生成指纹和检查结果，记录在 `test/golden/rules_v1_frozen.txt`）。这份记录是**在动产品代码之前**生成的。只有真的要改版本 1 的行为才能重出（`LOPI_GOLDEN_WRITE=1 flutter test test/rules_v1_frozen_test.dart`）。
- “升级到严格规矩”（1 → 2）的动作和“哪些地方行为会变”的清单：没做，见第 7 节。

翻成 2 时要跟着改的现有断言：

**一条都没有。** 做法：把开关临时改成 2，跑了全部测试文件（2026-11-26，机器很挤，分三批跑完：前 2781 个测试一批、其余文件两批），之后改回 1。结果：

- 和规矩版本有关的失败：0。原因是版本 2 的文档只比版本 1 多存一个 `"rules": 2` 字段，检查和生成都还没分叉；现有测试里比对“新建文档存出来的全文”的地方没有。
- 出现过两处和这次改动无关的失败，都是机器太挤造成的：`test/terminal_setup_test.dart` 的“失败不退回本机 shell”（等一个子进程的退出码没等到）、`test/workspace_state_test.dart` 一例 30 秒超时。开关是 1 时它们的情况见汇报。

所以到时候要改的不是“现有断言”，而是**接上严格检查和生成以后新出现的差别**：`test/rules_v1_frozen_test.dart` 里“入门样本”已经写死 `rules: kLangRulesLoose`，不受开关影响；其他用 `backendStarterDocument(…)` 不带 `rules` 的测试（后端编辑器、生成、对照测试）到时候会变成在测版本 2，哪些要钉回版本 1、哪些要改成版本 2 的期望，由接上的那一段逐条定、逐条记。

---

## 7. 这一段没做、留给后面的（按接手的人分）

### 给生成器那一段

1. **版本 2 的生成路径整个没有。** 现有五个生成器只认老节点、只走小库；遇到新节点抛 `LangUnsupported`。要做的是：拿 `LTypeResult` 生成带类型的代码（Go、Java 用原生类型，JS、Python、PHP 照旧但换成严格的小函数）。
2. **严格的小函数五种语言都还没有**：`iadd isub imul idiv imod fdiv ftoi`、`asInt` 一类、`asListOf`、`at / setAt`、`must`、`dadd` 一类、“等于”不再把 1 和 "1" 当一样的 `eq`，以及 `kLangRtV2New` 的五个新名字。原型 `docs/blocks-v5-prototypes/types/` 里每种语言有手写的参考实现和错误文字（设计第 8 节说 Node、Python、Go、Java 实测逐字节一致）。
3. **把检查接进后端校验**：`validateBackend` 对 `doc.rules >= 2` 的文档调用 `checkTypes`，把 `LTypeIssue` 对回积木（照 `beMapLangIssues`）。这一步和上面两步要一起上，所以没在这一段做——只接检查不接生成，版本 2 的文档会“报的是严格的错、跑的是宽松的代码”。
4. **老积木翻出来的语法树在严格规矩下会怎样，没试过。** `backend_lower_lang.dart` 翻出来的数字字面量是整数还是小数、请求里读出来的东西是不是都算任意、老的小库调用（`LRt`）在 `kLangRtV2` 里有没有签名——接第 3 步时要逐个看。没有签名的 `LRt` 名字，检查器现在按“参数任意、结果任意”处理，不报错。
5. 三个程序在生成层面缺的东西（类型层面都做了、推断结果和原型一致）：
   - **p08 类**：继承、`isOpen`、调父类的创建时、重写的检查都有；生成要等核心 2“类与接口的真实现”（Go 里的类怎么落，设计 7.3）。
   - **p11 错误**：“试着做 / 出错时 / 最后”的类型流有了，接到的错误变量**暂时按“文字”算**；核心 2 有了错误对象要换（`typecheck_stmt.dart` 里 `LTry` 那一处，`LVarKind.error`）。
   - **p14 泛型类**：`栈〈T〉` 的推断、`LNew.typeArgs`、`typeArgsOf` 有了；生成（Go 的泛型类型、Java 的擦除）没有。
6. 函数类型的“要不要等”（`LType.waits`）只有字段和存盘，没有推断、没有拦截——核心 3。

### 给界面那一段

1. 标红和一键修的界面。数据在 4.1。
2. **记录、枚举、变体、“看是哪种情况”、“当成”这些还没有积木**——没有积木的 `op`、没有存盘写法、编辑器里摆不出来。现在只能用代码搭语法树（测试就是这么做的）。它们的积木长什么样属于编辑器 / 库 1 的设计，这一段没有替他们定。
3. 类型标注的界面（给变量、参数标类型）和 390 宽上类型怎么显示（设计 6.3）。显示用 `LType.show()`。
4. “升级到严格规矩”的按钮和“哪些地方行为会变”的清单。数据上只要把 `doc.rules` 改成 2 再存。
5. 前端逻辑积木（`logic.js` 那一套）没有规矩版本字段——这一段只给后端文档加了。页面文件要加的话照 `BeDocument.rules` 的做法（是 1 不写）。

---

## 8. 拿不准的边界（单列）

1. **结果是按“节点对象”记的。** 同一个节点对象在树里出现两次（Dart 里 `const LLit(1)` 写两处就是同一个对象），`typeOf / wantOf / coercionOf / opOf` 只能记住一处。`result.shared` 会把这样的节点列出来（空、是/否、文字的字面量不算，它们记串了也没后果）。现在的翻译器每次都新建节点，实际不会撞；但生成器那一段如果自己做“降级”时复用节点，要留意。空列表 `[]` 的“里面放什么”已经按“节点＋所在的那一句”分开记，不会串。
2. **版本 1 里要不要给类型提示。** 设计原来说“版本 1 照样检查、给提示”，任务说“版本 1 不跑新规则、校验结果逐字不变”。照任务做了，设计文档已改。以后想给版本 1 的用户看类型提示，得另开一个不进校验结果的通道。
3. **T14 只认“标成任意的变量”这一种。** 把列表传给一个参数是任意的函数、函数里再加东西，这种不报（函数不知道传进来的是不是快照）。
4. **T13 的“给别人用”**现在看的是 `LFuncDecl.isPublic`。等库的格式定了（库 1），“进了库的我的积木”要不要自动算 `isPublic`，由那边定。记录、枚举这些类型的“没标全”没什么可查的（字段必须带类型），所以 T13 只查函数。
5. **T11 只查方法有没有、参数个数、返回类型**，和原型一样；参数类型不查。T18（重写）查得更严（参数类型也查）。两条的严格程度不一样，是照原型和设计各自的说法做的。
6. **“重复 i 从 a 到 b”**：三个数都是整数循环变量才是整数。原型一律当整数。
7. **推断反复算的遍数**：最多 12 遍，`result.passes` 是实际算了几遍；到 12 遍还不稳就用最后一遍的结果。12 是我定的数。
8. **整数和小数比大小**（`1 < 2.5`）允许，整数那边记一个 `widen`。文字和数字比大小是 T06。**“等于 / 不等于”两边是什么类型都不报**（和原型一样）：两边类型不同就是“不相等”，这靠生成器用严格的 `eq` 来保证（“1 和 "1" 不再一样”是运行时的事，不是检查器拦的）。要不要对“两边类型确定且不同”的等于给一条警告，设计里没说，没加。
9. **宿主自己的语句**（`LHost`，比如后端的“返回响应”）检查器整句跳过，里面的值不查。宿主给的变量的类型由调用的人通过 `outer` / `LTypeScript.vars` 传进来；宿主绑定的签名从哪来（设计 GAP-B-6）没定。

## 界面那一段做完以后的说明（2026-11-26，分支 v5-typeui）

和设计 6.2、6.3 对不上的地方（设计文档那两节没改字，以这里为准）：

1. **没有“底部说明条”。** 现有的问题展示是：积木角标＋点角标出的小卡、顶栏“问题”按钮开的列表、选中积木时上方的小条。类型问题全部走这一套；“类型一行字”放在选中小条的下面一行（`lib/blocks/block_type_line_view.dart`）。
2. **一键修 11 种**：语法树上 11 种都能执行（`lib/lang/type_fix.dart`）。积木上现在能做 6 种（`lib/backend/backend_type_fix.dart`）：变成文字、取整、变成整数、是空就用、一定不是空、换成“≠ 0”。另外 5 种（补上漏掉的情况、加“其他情况”、补上缺的字段、去掉多余的字段、改成“复制并改”）要靠记录和“看是哪种情况”的积木，这些积木排在后面；现在的后端积木也翻不出会报这 5 种的语法树，所以界面上不会出现点不了的按钮。那批积木做出来时，在 `kBeBlockFixKinds` 和 `beApplyTypeFix` 里补上。
3. **三块新积木**（只在严格规矩的文档的积木盒“运算”页最后）：`parseInt`「把 … 变成整数」、`orElse`「… 是空就用 …」、`must`「一定不是空 …」。它们是一键修的落点，没有它们“变成整数”“是空就用”“一定不是空”修完没法显示。生成代码那一侧要认这三种（`kBeStrictRtArgs`）。
4. **查类型时老的“运算 / 比较”“不是”翻成语言核心的式子**（`backend_lower_lang.dart` 里 `typed` 为真时）。不这样的话 `"12" * 2` 查不出来、`x * 2` 的类型也推不出来。只影响查类型，不影响生成。
5. **标注存在哪**：参数 `params[i].type`、函数 `returns`、“新建变量 / 常量”积木的 `args.type`（都用 10.1 的写法；没标不写这个键）。
6. **变量名只能是英文**（现有规矩），所以设计里的例子 `总和：整数` 在后端积木里实际是 `total：整数`；“我的积木”的名字可以是中文。
7. **临时的桥** `lib/backend/backend_type_bridge.dart`：对严格规矩的文档跑类型检查并把问题对回哪一块、哪一格。合并时换成接进 `validateBackend` 的正式版本；`lib/backend/backend_type_host.dart` 只用它的 `beTypeCheck`、`BeTypeCheck`、`BeTypeFinding`、`BeSlotRef` 四个名字。换的时候注意：正式版本如果自己把 T 规则放进 `validateBackend` 的结果，`withTypeIssues` 要去掉重复的。
8. **有类型错误时不生成**：这一段只在界面宿主层算进了错误数（顶栏说“N 个错误，没更新”）；`backend_project.dart` 生成那一层的拦截归接 `validateBackend` 的那一位。

9. **（2026-11-26 合并对接后）** 第 7、8 条已经落定：桥不再是临时的，`validateBackend` 用的就是它的结果，界面上不重复；
   生成那一层除了“有类型错误不生成”，严格规矩的文档现在整个不生成、菜单里的“升级到严格规矩…”默认不出现。详见 B-gen-notes.md 第 7 节。


## 核心 2 第 1 段以后的说明（2026-11-26，分支 v5r2-core）：错误对象、模块

语法树（`ast.dart`）：

- 新：`LCatch(body, kind, name)`——“出错时”的一节；`LProgram(modules, entry)`——几个模块的程序。
- 改：`LTry` 加 `handlers`（`List<LCatch>?`）和统一读法 `catches`：`handlers == null` 是老写法（`errorName / errorClass / onError` 当成一节兜底）；`[]` 是只有“最后”；有几项就是几节。`LThrow` 加 `value`（就是 `message`；版本 2 里可以是错误对象）。`LModule.uses / LVarDecl.isPublic` 等原来就有的字段现在真的有人看了。
- 所有走树的地方（`ast_util.dart`、`type_fix.dart`、`gen2.dart`、Java 的 `_completes`）都改成读 `catches`。规矩版本 1 的 `analyze.dart`、`gen.dart` 没动（它们只认老写法的字段）。
- 语法树还是没有存盘格式；新节点里没有带类型的部分，所以 `types_json.dart` 没有要加的。积木文档里“出错时”的各节、模块清单怎么存，是积木那一层（第 3 段）的事。

检查（规则表 `kTypeRules` 加了 T19–T21；模块的 M01–M08 在 `kModuleRules`）：

| 号 | 报什么 |
|---|---|
| T19 | 抛出的不是一句话也不是错误；“出错时”接的种类不存在或者不是错误；想改错误的“种类” |
| T20 | 自己的声明叫了内置错误的名字（错误、找不到、类型不对、数值不对、超时、取消了、读写失败） |
| T21 | 这一节“出错时”永远轮不到（前面有一节接得更粗或者一样） |

- 错误变量 `LVarKind.error` 的类型从“文字”改成错误类；读错误对象上没有的字段报 T08；把错误当文字用报 T01（要读“消息”）；抛“可能是空的错误”报 T02。
- `LTypeResult.prelude`（内置错误类的声明）、`LTypeResult.usesErrors`（生成器据此决定带不带它们）。
- 给第 3 段（积木、一键修）：新规则都还没有一键修；T01“把错误当文字用”最自然的修法是“读它的消息”，可以加一种 `LFixKind`。积木翻语法树时每一节“出错时”的错误变量可以同名（检查器按节收窄）。

## 核心 2 第 2 段以后的说明（2026-11-26，分支 v5r2-core）：类与接口

语法树：**没有加新节点，也没有加新字段。** 原来就有、这一段才真的用上的：

| 节点 / 字段 | 现在的意思 |
|---|---|
| `LClassDecl(name, parent, interfaces, fields, ctor, methods, typeParams, isOpen, isPublic)` | 类。`isOpen`＝可以被继承 |
| `LFieldDecl(name, init, type, isPrivate, isStatic)` | `isPrivate`＝内部（本类和子类里面能用）；`isStatic`＝属于类本身 |
| `LMethodDecl(fn, isStatic, isAbstract)` | `isStatic`＝类本身的方法（里面没有“我自己”）；`isAbstract` 还没用 |
| `LInterfaceDecl(name, methods: [LSignature(name, params, returns)])` | 接口；`LSignature.params` 里的默认值有意义（调用处补） |
| `LParam(name, type, defaultValue: LLit?)` | 默认值只能是直接写的值 |
| `LNew`、`LSend`、`LSuperSend`（`.ctor`）、`LThis`、`LIsA`、`LField`、`LTField`、`LCast` | 新建、让对象做、调父类的、我自己、是不是、读字段、改字段、转成 |
| `LSend(LName(类名), …)`、`LField(LName(类名), …)`、`LTField(LName(类名), …)` | 类本身的方法 / 字段（名字没被变量、函数挡住时） |
| `LNativeDecl(name, params, type)`、`LNative(name, args)` | 宿主接口的声明、调用 |

`ast_util.dart` 加了：`LClassParts.ownFields / ownMethods`（不算类本身的）、`lStaticName(类, 成员)`、`lStaticDecls(类)`（类本身的成员变成 `LVarDecl` / `LFuncDecl`）。

检查（`kTypeRules` 加了 T22–T28；T11、T18 加严，T08 多了几种说法）：

| 号 | 报什么 |
|---|---|
| T22 | 在类的外面读 / 改内部的字段（连类本身的内部字段） |
| T23 | 新建接口；拿接口当父类；拿类写在“实现了”里 |
| T24 | 继承绕圈（提示语把圈画出来） |
| T25 | 在对象上调类本身的方法；在类名上调对象的方法、读对象的字段；在类本身的方法里、类的外面用“我自己” |
| T26 | 有默认值的参数后面跟着没默认值的；默认值放不进参数的类型 |
| T27 | “调父类的创建时”不在子类“创建时”的第一句、调了两次、写在方法里；父类的“创建时”要参数而子类没调 |
| T28 | 类里字段、方法、类本身的成员重名；子类的字段和父类的字段重名 |
| T11（加严） | 实现接口的方法：参数的类型、返回的类型、默认值都要和接口说的一模一样 |
| T18（加严） | 重写的方法：同上，和父类的一模一样 |
| T08（多的说法） | “没有叫「x」的类或接口”（是不是）；“「类」这个类本身没有「x」这个方法 / 这一项”；“没有叫「x」的接口” |

- 类本身的方法在结果里是一条普通的函数签名，名字“类名.方法名”；类本身的字段是一个全局变量，名字“类名.字段名”（`LTypeResult.vars` 里作用域是“主”）。
- 节点上的记号：`opOf(节点) == 'static:类名.成员名'`＝这一句用的是类本身的成员（生成器、以后的积木层都看这个）。
- 宿主接口：有声明就按声明查参数；声明本身和 `kHostV2` 对不对得上是生成器查的（检查器不知道目标有哪些宿主接口——以后前端、后端的清单不一样）。

原型里的名字 → 现在的名字（A4 搬“小框架”时用）：

| 原型（02-web-framework） | 现在 |
|---|---|
| `native log.error (值)` | `sys.print(文字, "err")`（值先用“连”变成文字） |
| `native time.ms ()` | `time.now()` |
| `native store.get (名字)` | `store.read(名字)` |
| `native store.update (名字 函数)` | `store.update(名字, 函数)`（函数要标成 (任意) → 任意） |
| `native url.decode (文字)` | 小库 `urlDecode` |
| `native http.serve (端口 函数)`、`native time.sleep`、`spawn`、`await` | 核心 2 第 4 段做了明着标的最小版：`http.serve(端口, 主机, 函数)`、`time.sleep`、`LSpawn`、`LAwait`（B-gen-notes 第 12 节）；完整的换算表在 `test/fixtures/framework/README.md` |
| `static-method`、`(send 类名 方法 …)` | `LMethodDecl(isStatic: true)`、`LSend(LName(类名), …)` |
| `private-field` | `LFieldDecl(isPrivate: true)` |

## 核心 2 第 3 段以后的说明（2026-11-26，分支 v5r2-core）：积木文档里怎么存、怎么翻、一键修

### 积木文档里怎么存（backend.lc.json）

- 核心 2 的东西全放在文档顶上的一个键 **`core`** 里；`core` 是空的就不写这个键。所以没用到的文档读进来再写出去**一个字节不差**（`test/backend_core_samples_test.dart` 和 `test/backend_func_model_test.dart` 里的“旧文档字节不变”钉着）。
- 文档版本号沿用“用到才升”：有 `core`、或者哪一串里用到了核心 2 的积木 / 值 → 写 **4**；拿掉又回到 3 / 2 / 1。读的时候不看版本号，只看内容。
- `core` 里：

  | 键 | 内容 |
  |---|---|
  | `types` | 一个类型一项：`{id, kind, name, fields?, cases?, parent?, interfaces?, open?, ctor?, methods?}`。`kind` 是 `record / enum / variant / error / class / interface` |
  | 字段 | `{name, type, private?, static?, init?}`；`type` 用 `types_json.dart` 的写法，`init` 是一个值（积木的表达式） |
  | 情况 | `{name, fields?}`（枚举的没有 `fields`） |
  | 方法、`ctor` | `{id, name, params?, returns?, static?, x?, y?, body?}`；`params` 和“我的积木”的参数同一种写法（`{name, default?, type?}`）；接口的方法没有 `body`，只是一行签名 |
  | `globals` | 模块顶上的变量：`{name, init?, const?, type?}` |
  | `modules` | `{name, uses?, owns?}`；`owns` 里是键：类型的 id、“我的积木”的 id、变量是 `g:名字`。一个模块都没有＝整份文档是一个模块 |
  | `entry` | 入口模块的名字 |
  | `public` | 公开的东西的键（同 `owns`） |
  | `main` | “程序开始时”那一串：`{x?, y?, body}`，id 固定是 `main` |

- 新积木（都只在规矩版本 2 的文档里认；版本 1 的文档里出现＝不认识的积木，照旧原样留着、标出来）：
  - 语句：`try`（多段：每段 `{kind, name}`，`kind` 是错误种类的名字或 `@any`；收尾口＝“最后总要”，`noElse` 表示没有）、`throw {value}`、`match {value}`（每段 `{case, binds}`；`case` 是情况的名字，或 `@null / @some`（可空的值）、`@is:number|text|bool|list|dict`（“任意”的值）；`binds` 是逗号隔开的变量名；收尾口＝“其他情况”）、`setField {of, name, value}`、`callMethodStmt {of, name, args}`、`superInit {args}`、`superCallStmt {name, args}`。
  - 值：`errNew {kind, message, fields}`、`getField {of, name}`、`recNew {type, fields}`、`recCopy {of, fields}`、`enumVal {type, case}`、`varNew {type, case, args}`、`classNew {type, args}`、`callMethod {of, name, args}`、`superCall {name, args}`、`this`、`isA {x, type}`、`classRef {type}`。`fields` 是一串 `{e:'pair', key, value}`。
- 坏内容不崩：`core` 不是对象、里面的表不是表、条目不是对象、名字不合规矩、类型写错、id 缺了重了、超过上限（类型 64、每个类型的成员 32、模块 16、“出错时”8 节）——都是丢掉坏的那一项，别的照读（`test/safe_file_test.dart` 里“核心 2”那一条）。

### 怎么翻成语法树

- `backend_lower_core.dart`：`beCoreProgram(doc)` 把整份文档翻成 `LProgram`（没有模块时是一个模块）；类型 → 记录 / 枚举 / 变体 / 类 / 接口的声明；**自定义错误种类翻成“父类是错误的类”**，新建时参数顺序是 消息＋各字段（从最上面的父类往下）。
- “看是哪种情况”：看枚举 / 变体时翻成 `LMatch`（没列全由类型检查报 T03）；看可空的值、“任意”的值时翻成一段段“如果”（`== 空`、`是不是 某类型`），带出的东西是“一定有”“当成某类型”——这两种**列没列全由积木层自己查**（`beMatchGap`），也记成 T03，带“补上少的情况”“加一个其他情况”两种修法。
- 翻的时候每个节点都新造（不共用 `const` 节点）：类型检查的结果是按“是不是同一个节点”记的，共用会互相盖掉（Go 里出过把“可空的整数”当成指针再判空的错代码，就是这个原因）。
- “调父类的创建时”前面不插说明用的注释节点：它必须是“创建时”的第一句，插了就必报 T27。

### 能看代码

`backend_core_gen.dart`：`beIsCoreProgram(doc)`＝**严格规矩＋没有接口（路由）＋有“程序开始时”**。是的话，“看代码”走 `gen2ProgramFiles`，五种语言都出；“打印”翻成小库的 `log`。只管“看”：不写文件、不启动。含接口的严格文档还是原来那一行说明。`kLangStrictBackendGen`、`kStrictRulesUpgradeEnabled` 都没动、没读新的含义。

### 一键修：这一段接上的

| 哪条 | 修法（按钮上的字） | 做什么 |
|---|---|---|
| T03 没列全 | 补上漏掉的情况 / 加一个“其他情况” | 给“看是哪种情况”加段（带出的东西按字段名起变量名）/ 打开收尾口 |
| T04 记录少字段 | 补上… | 按字段的类型放一个默认值 |
| T04 记录多字段 | 删掉「字段名」 | 删掉那一对 |
| T06 改记录的字段 | 改成“复制并改” | 只在“把 (某个变量) 的字段改成 …”时能修：换成“把那个变量设为 复制它并改” |
| T01 错误当文字 | 读它的消息 | 外面套“… 的 消息” |
| T05 要数字（“绝对值 / 较大的…”这类要数字的积木里放了别的） | 变成数字 | 给那块积木里不是数字的每一格外面套“变成数字” |
| T17 | 给父类勾上“可以被继承” | |
| T18 / T11 | 照抄上面的签名 / 加上这个方法 | 名字、参数（连默认值）、交回什么都照父类 / 接口的来；已有的方法只换签名，积木留着 |
| T21 | 删掉这一节 | 另外，“试着做”“看是哪种情况”的段可以在积木上往上挪 / 往下挪 |
| T27 | 在第一句放上“调父类的创建时” / 挪到第一句 | 参数先按父类“创建时”的个数放空槽 |
| M05 | 在「乙」里勾上用到了「甲」 | |
| M06 | 把「名」设成公开（需要的话顺手勾上“用到了谁”） | |
| M08 | 把「后面那个」挪到「前面这个」前面 | |

接不了的，和理由：

| 哪条 | 为什么没有一键修 |
|---|---|
| T19（抛出的不是话也不是错误；接的种类不存在） | 不知道人想抛什么 / 想接哪一种——要人自己选；种类的下拉里已经只列得出能选的 |
| T20（起了内置错误的名字） | 要人起一个新名字；改名的面板里直接拦着，积木文档里出不来 |
| T22（在类外面碰内部的字段） | 两种改法（去掉“内部”、或者在类里加一个方法）意思差得远，不替人选 |
| T23（新建接口、拿接口当父类…） | 下拉里已经不列接口；只有手改文件才出得来，修法是换一个类，要人选 |
| T24（继承绕圈） | 断哪一条边要人定；选父类的时候已经拦着 |
| T25（对象上调类本身的方法…） | 两头都可能是写错的那一头 |
| T26（有默认值的参数后面跟着没默认值的） | 是挪顺序还是补默认值，要人定 |
| T28（成员重名） | 要人起新名字；面板里加、改名时已经拦着 |
| M01（模块重名、没名字）、M07（两个东西重名） | 要人起新名字；面板里已经拦着 |
| M02（入口不存在、用到了不存在的模块） | 面板里只能从现有的模块里选，出不来 |
| M03（模块绕圈） | 提示语已经说了怎么拆，拆法要人定 |
| M04（不是入口的模块有“程序开始时”） | 积木文档里“程序开始时”只有一串、永远算在入口模块里，出不来 |

补两点：
- 没分模块的文档也查 M08（顶上的变量初始值用到了排在它后面的）：只要顶上的变量不止一个，就把整份文档当一个模块过一遍 `linkProgram`，只留 M08。
- “没有叫「x」的变量”（T08）老规则（G03 / L01）已经报了，类型检查那条不再重复报；字段、方法、情况、类型找不到的 T08 照报。

### 这一段没做成积木界面的

“要等的事”（明着标“要等”、`LSpawn`、`LAwait`）没有做成积木：下一轮（核心 3）要改成自动推，现在做界面会返工。语言层那一套原样留着。
