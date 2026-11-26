# B 分册 · 生成器落地说明（规矩版本 2）

> 积木第 5 版 · 核心 1 类型打底 · 第二段。写的是**实际落成了什么**，给后面接手的人看。设计依据：B-type-system.md 的 5、7、8、11、12 节；上一段的交接：B-impl-notes.md。

## 1. 文件

| 文件 | 干什么 |
|---|---|
| `lib/lang/gen2.dart` | 共用骨架：变量表、谁被匿名函数捕获、语句、“看是哪种情况”、函数体 |
| `lib/lang/gen2_expr.dart` | 式子：按检查器给的 `opOf` / `coercionOf` / `wantOf` 选运算和转换 |
| `lib/lang/gen2_dyn.dart` | Node / Python / PHP 共用的那一半（值不带静态类型） |
| `lib/lang/gen2_node.dart`、`gen2_python.dart`、`gen2_php.dart` | 三种脚本语言 |
| `lib/lang/gen2_go.dart`、`gen2_go_prog.dart` | Go（带原生类型） |
| `lib/lang/gen2_java.dart`、`gen2_java_prog.dart` | Java（带原生类型） |
| `lib/lang/rt2_*.dart` | 五种语言的严格小库（超过 600 行的拆成上、下两半，`*_dyn.dart` 里拼起来） |
| `lib/lang/gen2_all.dart` | 入口：`kGen2Languages`、`gen2Files(语言, 模块)` |

版本 1 的生成器（`gen_*.dart`）、小库（`rt_*.dart`）一个字没动；版本 1 的文档不会走到这里。

## 2. 值在各语言里长什么样

| 积木里的类型 | Node | Python | PHP | Go | Java |
|---|---|---|---|---|---|
| 整数 | number，每次运算后查是不是安全整数（小库 `chk`） | int | int | `int64` | `long`（泛型位、可空用 `Long`） |
| 小数 | number | float | float | `float64` | `double` / `Double` |
| 文字 | string（按码点处理） | str | string（自己按 UTF-8 拆码点，不靠 mbstring） | `string` | `String`（按码点） |
| 列表〈T〉 | Array | list | 包成对象 | `*lc.List[T]` | `ArrayList<T>` |
| 字典〈V〉 | Map | dict | 包成对象 | `lc.Dict[V]` | 按码点排序的 `TreeMap<String,V>` |
| 可空 T | null | None | null | 基本类型 / 记录 / 枚举 / 类型变量用 `*T`，本来就是引用的不变 | 盒装类型，null |
| 记录 | 生成的 class（继承 `Rec`） | 类实例 | 类实例 | struct（按值） | `record … implements Lc.Rec` |
| 枚举 | 生成的 class（继承 `Enum`，冻结） | 类实例 | 类实例 | 有名的 `int64` | `enum … implements Lc.Named` |
| 变体 | 每种情况一个 class（继承 `Variant`） | 类实例 | 类实例 | 接口＋每种情况一个 struct | 接口＋每种情况一个 record |
| 类 | class | class | class | 不可继承＝`*T_x`；可继承＝接口 `T_x`＋“体”`B_x`＋`self`（B 分册 7.3） | `static class`，创建走静态 `lcNew_<类>`，不用 Java 构造函数 |
| 函数值 | 函数 | 函数 | 闭包 | `func(...)` | `Lc.Fn0…Fn4` / `Lc.Act0…Act4`（最多 4 个参数） |
| 任意 | 原样 | 数字一律 float | 数字一律 float | `any` | `Object`（数字一律 `Double`） |

名字：Go、Java 里类型名一律写成 ASCII（Java 是 `T_<十六进制码点>`），免得编译器对中文标识符有不同意见。
Java 里被匿名函数捕获又会被改的局部变量装进 `Lc.Ref`。

## 3. 严格语义（五种语言同一句报错）

类型不对、除以 0、整数超范围、位置越界、空值直接用、小数变不成整数：都报错，句子五种语言逐字相同
（比如 `除以 0`、`整数超出范围`、`位置 5 超出了列表的范围（共 3 项）`、`这里的值是空，不能直接用`）。
没被“试着做”接住的错，最后打印 `出错：<那句话>`。整除向 0 取整；“等于”不偷偷转换；文字比大小按码点。
`log` 先攒着，`run(main)` 最后一次写出。

9 种运行时检查点：检查器在 `checks` / `coercionOf` 里标出来的位置，生成器在那儿调小库的 `asInt` / `asText` / `must` / `at` 等；
检查器已经证明用不着的地方不加。

## 4. 借了核心 2 的哪些最小部分（为了 p08、p11、p14 能跑）

- p08（类）：字段和默认值、“创建时”、方法、单继承、调父类的创建和方法、“是不是”。接口只做了声明和“实现了”的标记。
- p11（错误）：只按“一句文字消息”抛和接（各语言小库里的 `LcError`）。**没做**错误对象体系（错误种类、带数据、原因链）。
- p14（泛型类）：带类型变量的类和它的方法。
- 还没有（遇到会明说“还没有”，不会生成错代码）：Go、Java 里“继承一个带类型变量的类”；Go 里“方法自己再带类型变量”（Go 语言本身不允许）。

## 5. 和后端（服务器积木）的关系——现在接到哪

- 校验：`validateBackend` 对规矩版本 2 的文档多跑一遍类型检查（`lib/backend/backend_validate_types.dart`），问题对回积木。版本 1 的文档不进。
- 生成：**后端文档的生成还走版本 1 的生成器**。版本 2 的生成器遇到宿主语句（返回响应、数据集合…）、宿主名字（“这次请求”）、
  原生小段会抛“还不能”。要接上，得先定宿主绑定的签名（设计 GAP-B-6），并让服务器小库的值和严格小库的值对得上
  （PHP 的列表 / 字典一边是数组一边是对象；Go 一边是 `any` 一边是原生类型；Java 一边 `Double` 一边 `long`）。这属于“库 1”的事。
- 所以开关 `kLangRulesForNewDocs` 这一段**没有翻成 2**：翻了的话新文档会“按严格规矩查、按老规矩跑”，两头对不上。

### 5.1 翻开关前还差什么（2026-11-26 实测）

把现有四份样本文档改成版本 2 过一遍校验（`test/backend_validate_types_test.dart` 钉着）：

- 新建文档的默认内容（入门样本）、一致性样本、“我的积木”样本：一条不多。
- 第 4 版新积木样本：多出 10 条错（T01 八条、T06 一条、T07 一条）。大多是样本故意混着放类型（整数列表里加文字 / 小数、
  字典的键用整数、给文字取负、把文字放进要列表或字典的格子），严格规矩下本来就该报。有一条是老积木和版本 2 的签名对不上：
  “数列 从 到 步长”老积木传 3 个参数，版本 2 的签名只有 2 个 → 这块积木在版本 2 下一拖出来就报错（T07）。
- 老积木会翻出来、但版本 2 签名表（`kLangRtV2`）里还没有的小库函数：abs、max、min、random、copy、template、toNumber、toText、
  toBool、isType、listInsert、listRemove、listSort、listEach、dictMerge、dictPairs、dictRemove。检查器对它们按“参数任意、结果任意”，
  不会误报；版本 2 的生成器遇到会明说“还没有”。其中 abs / max / min 和带步长的数列要“整数进整数出、小数进小数出”，
  现在的签名表一个名字只能写一种参数，表达不了——得先定是拆成两个名字还是给签名表加“数字”这种约束（设计上没写）。

## 6. 验收

`test/lang_gen2_proto_test.dart`（标了 `external`）：16 个程序 × 五种语言生成、真编译、真跑，和 `expect.txt` 逐字节比；
4 组错例在检查阶段拦下。Java 用 `javac -Xlint:all -Werror`。缺编译器的语言跳过并打印原因。
TypeScript 生成器不属于核心 1（总设计 8.2 分期表），没有做。
