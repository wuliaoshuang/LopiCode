/// 严格规矩（规矩版本 2）才有的三块值积木：类型检查的“一键修”要靠它们把东西包一层
/// （设计 docs/blocks-v5-parts/B-type-system.md 6.2）。
///
/// - `parseInt`：把文字变成整数，变不了就是空（结果是“整数?”，后面还要处理空）；
/// - `orElse`：是空就用另一个值；
/// - `must`：一定不是空（真是空就在运行时报错）。
///
/// 第四轮（A4）又补了八块，都是语言核心里早就有、只是没有积木的写法（写库时缺的，自带库翻成画布时“照文字原样放着”的就是它们）：
/// - `sizeOf` 有几个（小库 `size`）、`joinText` 连成文字（小库 `join`，不定个数）、`intDiv` 整除（`//`）、
///   `isTypeNamed` 是不是叫这个名字的那一类（小库 `isType`，类型名是算出来的）；
/// - `toInt` 取整、`isNumeric` 是不是数字、`urlDecode` 网址解码、`codePoints` 每个字的码点（名字就是小库的名字）。
/// 第九样“带类型参数的匿名函数”不是新的一块：是匿名函数的参数小块上能标类型了（backend_lower_lang_func.dart 的 `_lambdaParams`）。
///
/// 单独放一张表、不并进 `beLangExprSpecs`：老规矩的文档里没有它们（积木盒里不出现，一键修也只在严格规矩下有），
/// 老的生成器不认识这三个小库名字——碰到会留一行“这一段没有生成”，不会写出错的代码（lib/lang/gen.dart 的 `_rt`）。
/// 五种语言的小库实现在“带类型的生成路径”那一段（lib/lang/rt_v2.dart 的 `kLangRtV2New`）。
library;

import 'package:lopicode/lowcode/logic_blocks.dart';

const Map<String, LcExprSpec> beStrictExprSpecs = {
  'parseInt': LcExprSpec('parseInt', '变成整数', '运算', [LcArgSpec('s', '文字', LcArgKind.expr, valueType: LcType.text)], hint: '变不了（比如 "abc"）就是空，后面要处理空'),
  'orElse': LcExprSpec('orElse', '是空就用', '运算', [LcArgSpec('x', '值', LcArgKind.expr), LcArgSpec('d', '换成', LcArgKind.expr)], hint: '前面的值是空的时候，用后面这个'),
  'must': LcExprSpec('must', '一定不是空', '运算', [LcArgSpec('x', '值', LcArgKind.expr)], hint: '你保证它不是空；真是空的话运行时会报错'),
  kBeSizeOf: LcExprSpec(kBeSizeOf, '有几个', '运算', [LcArgSpec('x', '列表、文字或字典', LcArgKind.expr)], hint: '列表有几项、文字有几个字、字典有几个键；结果是整数'),
  kBeJoinText: LcExprSpec(kBeJoinText, '连成文字', '运算', [LcArgSpec('items', '内容', LcArgKind.exprList)], hint: '把几个值挨个变成文字再连起来'),
  kBeIntDiv: LcExprSpec(kBeIntDiv, '整除', '运算', [LcArgSpec('l', '被除数', LcArgKind.expr), LcArgSpec('r', '除数', LcArgKind.expr)], hint: '除完只留整数那一截（往小的方向取）；两边都要是整数'),
  kBeIsTypeNamed: LcExprSpec(kBeIsTypeNamed, '是不是叫这个名字的那一类', '运算', [
    LcArgSpec('x', '值', LcArgKind.expr),
    LcArgSpec('name', '类型名', LcArgKind.expr, valueType: LcType.text),
  ], hint: '类型名是一段文字：number、text、bool、null、list、dict 里的一个；别的名字都算“不是”'),
  'toInt': LcExprSpec('toInt', '取整', '运算', [LcArgSpec('x', '数', LcArgKind.expr)], hint: '把数变成整数（小数那一截丢掉）'),
  'isNumeric': LcExprSpec('isNumeric', '是不是数字', '运算', [LcArgSpec('x', '值', LcArgKind.expr)], hint: '是数、或者是写成数字样子的文字，就是“是”'),
  'urlDecode': LcExprSpec('urlDecode', '网址解码', '运算', [LcArgSpec('s', '文字', LcArgKind.expr, valueType: LcType.text)], hint: '把网址里 %E4%BD%A0 那样的写法变回原来的字'),
  'codePoints': LcExprSpec('codePoints', '每个字的码点', '运算', [LcArgSpec('s', '文字', LcArgKind.expr, valueType: LcType.text)], hint: '文字里每个字的编号，排成一个整数列表'),
};

const String kBeSizeOf = 'sizeOf';
const String kBeJoinText = 'joinText';
const String kBeIntDiv = 'intDiv';
const String kBeIsTypeNamed = 'isTypeNamed';

/// 结果是“是 / 否”的那几块（画成六角的）。
const Set<String> kBeStrictBoolKinds = {'isNumeric', kBeIsTypeNamed};

/// 积木盒里的两组（“运算”页，严格规矩才有；见 backend_type_host.dart 的 `beStrictOperatorCategory`）。
const List<String> kBeStrictTextKinds = [kBeJoinText, kBeSizeOf, 'codePoints', 'urlDecode'];
const List<String> kBeStrictNumberKinds = [kBeIntDiv, 'toInt', 'isNumeric', kBeIsTypeNamed];

/// 积木上的话。
const Map<String, String> beStrictExprSentences = {
  'parseInt': '把 {s} 变成整数',
  'orElse': '{x} 是空就用 {d}',
  'must': '一定不是空 {x}',
  kBeSizeOf: '{x} 有几个',
  kBeJoinText: '连成文字 {items}',
  kBeIntDiv: '{l} 整除 {r}',
  kBeIsTypeNamed: '{x} 是叫 {name} 的那一类',
  'toInt': '{x} 取整',
  'isNumeric': '{x} 是数字',
  'urlDecode': '网址解码 {s}',
  'codePoints': '{s} 每个字的码点',
};

/// 搜索用的别名。
const Map<String, List<String>> beStrictAliases = {
  'expr:$kBeSizeOf': ['长度', '个数', '几项', '几个字', 'length', 'size', 'count'],
  'expr:$kBeJoinText': ['拼接', '拼成文字', '连起来', 'join', 'concat'],
  'expr:$kBeIntDiv': ['整除', '除', '商', 'div', '//'],
  'expr:$kBeIsTypeNamed': ['类型', '是不是', 'typeof', 'isType'],
  'expr:toInt': ['取整', '整数', '去掉小数', 'int', 'trunc'],
  'expr:isNumeric': ['数字', '是不是数', 'isNaN', 'numeric'],
  'expr:urlDecode': ['网址', '解码', 'decodeURIComponent', 'url'],
  'expr:codePoints': ['码点', '字符', '拆开', 'unicode', 'charCode'],
};

/// 积木盒里拖出来的新的一块：要包的那一格先空着，等人放东西进去。
Map<String, dynamic>? newBeStrictExpr(String kind) => switch (kind) {
  'parseInt' => {'e': kind, 's': exText('12')},
  'orElse' => {'e': kind, 'x': null, 'd': exNum(0)},
  'must' => {'e': kind, 'x': null},
  kBeSizeOf || 'toInt' || 'isNumeric' => {'e': kind, 'x': null},
  kBeJoinText => {
    'e': kind,
    'items': <dynamic>[exText(''), exText('')],
  },
  kBeIntDiv => {'e': kind, 'l': null, 'r': exNum(2)},
  kBeIsTypeNamed => {'e': kind, 'x': null, 'name': exText('text')},
  'urlDecode' => {'e': kind, 's': exText('%E4%BD%A0')},
  'codePoints' => {'e': kind, 's': exText('你好')},
  _ => null,
};

/// 翻成小库调用时参数的顺序（小库名字就是积木的名字）。
const Map<String, List<String>> kBeStrictRtArgs = {
  'parseInt': ['s'],
  'orElse': ['x', 'd'],
  'must': ['x'],
  'toInt': ['x'],
  'isNumeric': ['x'],
  'urlDecode': ['s'],
  'codePoints': ['s'],
};

/// 读成人话（问题列表里“第 2 块（…）”那半句用）；不是这三块返回 null。
String? describeBeStrictExpr(Object? expr, String Function(String key) sub) => switch (exprKind(expr)) {
  'parseInt' => '把 ${sub('s')} 变成整数',
  'orElse' => '${sub('x')} 是空就用 ${sub('d')}',
  'must' => '一定不是空 ${sub('x')}',
  kBeSizeOf => '${sub('x')} 有几个',
  kBeJoinText => '连成文字（${(expr as Map)['items'] is List ? ((expr)['items'] as List).length : 0} 段）',
  kBeIntDiv => '${sub('l')} 整除 ${sub('r')}',
  kBeIsTypeNamed => '${sub('x')} 是叫 ${sub('name')} 的那一类',
  'toInt' => '${sub('x')} 取整',
  'isNumeric' => '${sub('x')} 是数字',
  'urlDecode' => '网址解码 ${sub('s')}',
  'codePoints' => '${sub('s')} 每个字的码点',
  _ => null,
};
