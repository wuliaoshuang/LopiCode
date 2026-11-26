/// 严格规矩（规矩版本 2）才有的三块值积木：类型检查的“一键修”要靠它们把东西包一层
/// （设计 docs/blocks-v5-parts/B-type-system.md 6.2）。
///
/// - `parseInt`：把文字变成整数，变不了就是空（结果是“整数?”，后面还要处理空）；
/// - `orElse`：是空就用另一个值；
/// - `must`：一定不是空（真是空就在运行时报错）。
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
};

/// 积木上的话。
const Map<String, String> beStrictExprSentences = {'parseInt': '把 {s} 变成整数', 'orElse': '{x} 是空就用 {d}', 'must': '一定不是空 {x}'};

/// 翻成小库调用时参数的顺序（小库名字就是积木的名字）。
const Map<String, List<String>> kBeStrictRtArgs = {
  'parseInt': ['s'],
  'orElse': ['x', 'd'],
  'must': ['x'],
};

/// 读成人话（问题列表里“第 2 块（…）”那半句用）；不是这三块返回 null。
String? describeBeStrictExpr(Object? expr, String Function(String key) sub) => switch (exprKind(expr)) {
  'parseInt' => '把 ${sub('s')} 变成整数',
  'orElse' => '${sub('x')} 是空就用 ${sub('d')}',
  'must' => '一定不是空 ${sub('x')}',
  _ => null,
};
