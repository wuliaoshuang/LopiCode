/// 语言核心用到的“运行时小库”函数表（设计稿 3.1、3.3、3.11）。每种语言的小库都要实现表里的每一个，**行为必须逐字节一致**
/// （`test/lang_conformance_test.dart` 让 Node / Python / Go / Java 跑同一批程序、比对输出）。
///
/// 分两张表：
/// - [kLangCoreFns]：值的规矩最底下那几样（加减乘除、等于、算不算“是”…）。第 3 版后端的小库已经有了，语言核心直接用。
/// - [kLangRtFns]：第 4 版新加的（类型、数学、文字、列表、字典、JSON、数列）。
///
/// 名字在各语言里的写法由生成器定：Node `lc.listGet`、Python `lc.list_get`、Go `lc.ListGet`、Java `LcLang.listGet`、PHP `lc_listGet`。
///
/// 统一的规矩（自定的都标了）：
/// - **位置从 0 数**；位置先“数字化”再去掉小数部分。**文字按 Unicode 码点算**（一个表情算一个字）。
/// - **读不到得空，不抛错**；**写到不存在的位置抛错**（表里 `throws` 是 true 的）。错误是各语言自己的异常（Go 是 panic），
///   消息五种语言一样；第 6 阶段的“试着做”能接住，后端接口里没接住就是 500。
/// - 参数不是要的类型：读的当成“没有”（空列表 / 空字典 / 文字化），写的抛错。
/// - “数字化”“文字化”“等于”“JSON”的规矩见第 3 版（backend_ir.dart 的 `kBeRuntimeFns` 上面那段说明），这里不重复。
library;

import 'package:lopicode/lang/types.dart';

/// 现在做到第几阶段：表里 `stage` 不超过它的函数才能生成（`stage` 是“第几阶段加进来的”）。
const int kLangStage = 2;

/// “重复”最多做这么多遍（和第 3 版后端一致）。
const int kLangRepeatLimit = 10000;

/// “数列”“重复文字”最多这么多项 / 遍（自定：免得一块积木把内存撑爆）。
const int kLangRangeLimit = 10000;

/// “从…数到…”最多数这么多遍（2^31 − 1：Java 的 int 上限；自定）。
const int kLangCountLimit = 2147483647;

/// 小库函数返回什么（静态类型的语言里就是它的返回类型）。
enum LRet {
  /// 说不准（Go `any` / Java `Object`）。
  any,
  number,
  text,

  /// 语言自己的布尔：可以直接放进“如果”的条件，不用再包一层 `truthy`。
  bool,
  list,
  dict,

  /// 语言自己的整数（只给生成器内部用：循环的遍数）。
  nativeInt,

  /// 语言自己的列表（只给生成器内部用：`for … of`）。
  nativeList,

  /// 没有返回值。
  none,
}

class LRtFn {
  const LRtFn(this.params, this.ret, this.doc, {this.throws = false, this.variadic = false, this.stage = 1, this.internal = false});

  /// 参数名（给人看的）。[variadic] 时是“每一项”的说明。
  final List<String> params;
  final LRet ret;

  /// 规矩。
  final String doc;

  /// 会不会抛错。
  final bool throws;

  /// 参数个数不定。
  final bool variadic;

  /// 第几阶段才实现：2＝要拿函数当参数的，**先占位**（名字和签名定了，小库里还没有，生成器碰到会报“未支持”）。
  final int stage;

  /// 只给生成器内部用，不对应积木。
  final bool internal;

  LType get type => switch (ret) {
    LRet.number => LType.number,
    LRet.text => LType.text,
    LRet.bool => LType.boolean,
    LRet.list || LRet.nativeList => LType.list,
    LRet.dict => LType.dict,
    LRet.none => LType.nul,
    LRet.nativeInt => LType.number,
    LRet.any => LType.any,
  };
}

/// 值的规矩最底下的函数（宿主的小库必须有；第 3 版后端的 `kBeRuntimeFns` 里都有，`test/lang_rt_test.dart` 核对）。
const Map<String, LRtFn> kLangCoreFns = {
  'add': LRtFn(['a', 'b'], LRet.number, '两边数字化后相加；结果不是有限的数 → 0'),
  'sub': LRtFn(['a', 'b'], LRet.number, '相减'),
  'mul': LRtFn(['a', 'b'], LRet.number, '相乘'),
  'div': LRtFn(['a', 'b'], LRet.number, '相除；除以 0 → 0'),
  'mod': LRtFn(['a', 'b'], LRet.number, '取余，符号跟被除数；除以 0 → 0'),
  'eq': LRtFn(['a', 'b'], LRet.bool, '等于：类型一样直接比（列表 / 字典比 JSON）；不一样都文字化再比'),
  'ne': LRtFn(['a', 'b'], LRet.bool, '不等于'),
  'lt': LRtFn(['a', 'b'], LRet.bool, '两边数字化后 a < b'),
  'le': LRtFn(['a', 'b'], LRet.bool, 'a <= b'),
  'gt': LRtFn(['a', 'b'], LRet.bool, 'a > b'),
  'ge': LRtFn(['a', 'b'], LRet.bool, 'a >= b'),
  'isNot': LRtFn(['x'], LRet.bool, 'x 不算“是”'),
  'truthy': LRtFn(['x'], LRet.bool, '算不算“是”：空、否、0、空文字算“否”，其余（含空列表、空字典）算“是”'),
  'join': LRtFn(['项'], LRet.text, '每项文字化后连起来', variadic: true),
  'size': LRtFn(['x'], LRet.number, '列表的项数 / 文字的字数（按码点）/ 字典的键数；其余 0'),
  'isNull': LRtFn(['x'], LRet.bool, 'x 是空'),
  'now': LRtFn([], LRet.text, '现在的世界标准时间，形如 2026-11-24T06:00:00Z'),
  'log': LRtFn(['x'], LRet.none, '把 x 文字化后写一行到标准输出（“打印一行”）'),
  'times': LRtFn(['x'], LRet.nativeInt, '数字化后去掉小数部分，夹在 0 到 $kLangRepeatLimit 之间', internal: true),
  'items': LRtFn(['x'], LRet.nativeList, 'x 是列表就是它当时的样子（一份拷贝），否则空列表', internal: true),
};

/// 第 4 版新加的小库函数。
const Map<String, LRtFn> kLangRtFns = {
  // —— 类型 ——
  'isType': LRtFn(['x', '类型名'], LRet.bool, '类型名是 number / text / bool / null / list / dict 之一，x 是不是这种；别的名字 → 否（函数、类以后加）'),
  'toNumber': LRtFn(['x'], LRet.number, '数字化'),
  'toText': LRtFn(['x'], LRet.text, '文字化'),
  'toBool': LRtFn(['x'], LRet.bool, '算不算“是”'),
  'copy': LRtFn(['x'], LRet.any, '复制一份（列表 / 字典连里面的一起复制，改复制品不影响原来的）'),
  // —— 数学 ——
  'pow': LRtFn(['a', 'b'], LRet.number, '乘方；结果不是有限的数（含负数开方）→ 0'),
  'round': LRtFn(['x'], LRet.number, '四舍五入到整数，**正好一半时远离 0**（2.5 → 3，-2.5 → -3）'),
  'floor': LRtFn(['x'], LRet.number, '向下取整'),
  'ceil': LRtFn(['x'], LRet.number, '向上取整'),
  'abs': LRtFn(['x'], LRet.number, '绝对值'),
  'sqrt': LRtFn(['x'], LRet.number, '平方根；负数 → 0'),
  'max': LRtFn(['a', 'b'], LRet.number, '两个数里大的'),
  'min': LRtFn(['a', 'b'], LRet.number, '两个数里小的'),
  'random': LRtFn(['a', 'b'], LRet.number, '含两头的随机整数：两边数字化后去掉小数部分，在小的和大的之间（含）随机取一个'),
  // —— 文字（参数先文字化）——
  'charAt': LRtFn(['s', 'i'], LRet.any, '第 i 个字（一个码点）；没有 → 空'),
  'substring': LRtFn(['s', 'from', 'to'], LRet.text, '从第 from 个字到第 to 个字**之前**（不含 to）；越界的夹回来，from ≥ to → 空文字'),
  'contains': LRtFn(['s', 'sub'], LRet.bool, 's 里有没有 sub（空文字算有）'),
  'startsWith': LRtFn(['s', 'p'], LRet.bool, '以 p 开头吗'),
  'endsWith': LRtFn(['s', 'p'], LRet.bool, '以 p 结尾吗'),
  'indexOf': LRtFn(['s', 'sub'], LRet.number, 'sub 第一次出现的位置（按码点）；找不到 → -1；sub 是空文字 → 0'),
  'replace': LRtFn(['s', 'from', 'to'], LRet.text, '把所有 from 换成 to（从左到右、不重叠）；from 是空文字 → 原样'),
  'split': LRtFn(['s', 'sep'], LRet.list, '按 sep 切开（两头和连着的 sep 之间是空文字，都留着）；sep 是空文字 → 一个字一项；s 是空文字：sep 不空 → [""]，sep 空 → []'),
  'trim': LRtFn(['s'], LRet.text, '去掉两头的空格 / 制表 / 回车 / 换行（只这四种，自定：各语言“空白”的范围不一样）'),
  'upper': LRtFn(['s'], LRet.text, '转大写：**只转 a–z**（自定：各语言的 Unicode 大小写表不一样，é、ß、İ 这些各家结果不同）'),
  'lower': LRtFn(['s'], LRet.text, '转小写：只转 A–Z'),
  'repeatText': LRtFn(['s', 'n'], LRet.text, '重复 n 遍；n 数字化取整，夹在 0 到 $kLangRangeLimit 之间'),
  'template': LRtFn(['s', '字典'], LRet.text, '把 s 里的 {键} 换成字典里那个键的值（文字化）；字典里没有这个键、或花括号没配上 → 原样留着（自定）。键里不能有花括号'),
  // —— 列表 ——
  'listOf': LRtFn(['项'], LRet.list, '新列表', variadic: true),
  'listGet': LRtFn(['xs', 'i'], LRet.any, '第 i 项；没有、xs 不是列表 → 空'),
  'listSet': LRtFn(['xs', 'i', 'v'], LRet.none, '改第 i 项；没有这一项、xs 不是列表 → 抛错', throws: true),
  'listPush': LRtFn(['xs', 'v'], LRet.none, '末尾加一项（原地改）；xs 不是列表 → 抛错', throws: true),
  'listInsert': LRtFn(['xs', 'i', 'v'], LRet.none, '在第 i 项前插入（i 等于项数＝加在末尾）；i 不在 0 到项数之间、xs 不是列表 → 抛错', throws: true),
  'listRemove': LRtFn(['xs', 'i'], LRet.any, '删第 i 项，返回删掉的那项；没有这一项、xs 不是列表 → 抛错', throws: true),
  'listPop': LRtFn(['xs'], LRet.any, '取走最后一项；列表是空的、xs 不是列表 → 空（不抛错）'),
  'listContains': LRtFn(['xs', 'v'], LRet.bool, '有没有“等于” v 的项'),
  'listIndexOf': LRtFn(['xs', 'v'], LRet.number, '第一个“等于” v 的项的位置；没有 → -1'),
  'listSlice': LRtFn(['xs', 'from', 'to'], LRet.list, '新列表：从第 from 项到第 to 项之前；越界的夹回来'),
  'listConcat': LRtFn(['a', 'b'], LRet.list, '新列表：a 的项接上 b 的项（不是列表的当空列表）'),
  'listReverse': LRtFn(['xs'], LRet.list, '新列表：倒过来'),
  'listSort': LRtFn(['xs'], LRet.list, '新列表：从小到大。数字排在前面、按大小；其余的文字化后按码点；一样的保持原来的先后（自定）'),
  'listJoin': LRtFn(['xs', 'sep'], LRet.text, '每项文字化，用 sep 连起来'),
  'range': LRtFn(['a', 'b', 'step'], LRet.list, '数列：从 a 起每次加 step，到 b 为止（含两头）；规矩同“从…数到…”，最多 $kLangRangeLimit 项'),
  // —— 列表：要拿函数当参数的（第 2 阶段加的）。fn 不是函数、参数个数对不上 → 抛错；xs 不是列表 → 当空列表 ——
  'listSortBy': LRtFn(['xs', 'fn'], LRet.list, '新列表：按 fn(项) 给的分从小到大（分怎么比同 listSort；一样的保持原来的先后）', stage: 2, throws: true),
  'listMap': LRtFn(['xs', 'fn'], LRet.list, '新列表：每一项换成 fn(项)', stage: 2, throws: true),
  'listFilter': LRtFn(['xs', 'fn'], LRet.list, '新列表：只留 fn(项) 算“是”的', stage: 2, throws: true),
  'listReduce': LRtFn(['xs', 'fn', 'init'], LRet.any, '合成一个值：从 init 起，按顺序 累计 = fn(累计, 项)（空列表 → init）', stage: 2, throws: true),
  'listFind': LRtFn(['xs', 'fn'], LRet.any, '第一个 fn(项) 算“是”的项；没有 → 空', stage: 2, throws: true),
  'listEvery': LRtFn(['xs', 'fn'], LRet.bool, '每一项 fn(项) 都算“是”吗（空列表 → 是）；碰到第一个“否”就停', stage: 2, throws: true),
  'listSome': LRtFn(['xs', 'fn'], LRet.bool, '有一项 fn(项) 算“是”吗（空列表 → 否）；碰到第一个“是”就停', stage: 2, throws: true),
  'listEach': LRtFn(['xs', 'fn'], LRet.none, '按顺序每一项调一次 fn(项)', stage: 2, throws: true),
  // —— 字典（键先文字化）——
  'dictOf': LRtFn(['键, 值'], LRet.dict, '新字典：键 1, 值 1, 键 2, 值 2…；键重复时后面的盖掉前面的；最后落单的一个键（没有值）丢掉', variadic: true),
  'dictGet': LRtFn(['d', 'k'], LRet.any, '那个键的值；没有、d 不是字典 → 空'),
  'dictSet': LRtFn(['d', 'k', 'v'], LRet.none, '设一个键（原地改）；d 不是字典 → 抛错', throws: true),
  'dictRemove': LRtFn(['d', 'k'], LRet.none, '删一个键（没有就不动）；d 不是字典 → 抛错', throws: true),
  'dictHas': LRtFn(['d', 'k'], LRet.bool, '有这个键吗'),
  'dictKeys': LRtFn(['d'], LRet.list, '所有的键，按 Unicode 码点从小到大'),
  'dictValues': LRtFn(['d'], LRet.list, '所有的值，按键的顺序'),
  'dictPairs': LRtFn(['d'], LRet.list, '所有的“键值对”，每一对是 [键, 值] 这样的两项列表，按键的顺序'),
  'dictMerge': LRtFn(['a', 'b'], LRet.dict, '新字典：a 的键加上 b 的键，重复的用 b 的（不是字典的当空字典）'),
  // —— 列表 / 字典 / 文字通用 ——
  'item': LRtFn(['x', 'k'], LRet.any, 'x 是列表 → listGet；字典 → dictGet；文字 → charAt；其余 → 空'),
  'setItem': LRtFn(['x', 'k', 'v'], LRet.none, 'x 是列表 → listSet；字典 → dictSet；其余 → 抛错', throws: true),
  // —— JSON ——
  'toJson': LRtFn(['x'], LRet.text, '写成 JSON 文字（键按码点排、不加空格）'),
  'fromJson': LRtFn(['s'], LRet.any, '从 JSON 文字解析；不是合法的 JSON（含带 BOM、NaN）、套了超过 64 层 → 空'),
  // —— 生成器内部用 ——
  'countSteps': LRtFn(['from', 'to', 'step'], LRet.nativeInt, '“从…数到…”要做几遍：step 是 0、方向不对 → 0；否则 ⌊(to − from) ÷ step + 1e-9⌋ + 1，最多 $kLangCountLimit', internal: true),
};

/// 小库抛错时的消息（五种语言一样）。
const Map<String, String> kLangErrors = {
  'notList': '这不是列表，改不了',
  'notDict': '这不是字典，改不了',
  'noItem': '列表里没有这个位置',
  'notIndexable': '这个值不能按位置或键来改',
  'notFunction': '这不是函数，不能调用',
  'argCount': '调用函数时给的参数个数对不上',
};

/// 二元运算符 → 小库函数。
const Map<String, String> kLangBinaryFns = {'+': 'add', '-': 'sub', '*': 'mul', '/': 'div', '%': 'mod', '**': 'pow', '==': 'eq', '!=': 'ne', '<': 'lt', '<=': 'le', '>': 'gt', '>=': 'ge'};

/// “是这种类型吗”认的类型名。
const List<String> kLangTypeNames = ['number', 'text', 'bool', 'null', 'list', 'dict', 'function'];
