/// 后端积木校验里“语言核心”的那一半（积木第 4 版·第 1 阶段）：用到新积木的接口交给 lib/lang 的检查器看一遍，
/// 把它报的（名字看不见、跳出不在循环里、名字重复、改常量、停不下来的循环、后面的不会执行）对回到积木和槽上。
///
/// 做法：把接口按“影子模式”翻成语法树（`beLangShadow`：名字照写、旧积木读写的变量另补几句），跑 `analyzeBody`，
/// 再按语法树节点上的来源下标查回积木路径。只读不改、不抛异常（翻不出来就当没有问题，别的检查照常）。
library;

import 'package:lopicode/backend/backend_ir.dart' show beLangShadow;
import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/lang/lang.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:lopicode/lowcode/logic_validate.dart';

/// 语言核心带来的问题种类（规则 L04 / L09 / L11 / L13，见 lib/lowcode/logic_rules.dart）。
abstract final class BeLangIssueCode {
  /// “跳出循环 / 跳过这一轮”不在循环里。
  static const String outsideLoop = 'outsideLoop';

  /// 同一层里新建了两个同名的，或和“变量”里声明的重名。
  static const String duplicateName = 'duplicateName';

  /// 给常量重新赋值。
  static const String assignConst = 'assignConst';

  /// 可能停不下来的循环（警告）。
  static const String endlessLoop = 'endlessLoop';
}

/// 哪些积木的哪些参数是“新建一个名字”（直接填的文字）。
const Map<String, List<String>> kBeNewNameArgs = {
  'let': ['name'],
  'const': ['name'],
  'forCount': ['name'],
  'forEach': ['index'],
  'forPairs': ['key', 'value'],
};

const Set<String> _respondOps = {'respondJson', 'respondText'};
const Set<String> _loopOps = {'repeat', 'forEach', 'while', 'forever', 'forCount', 'forPairs'};

/// 这一串里有没有属于“外面这一层循环”的“跳出循环”（更里面的循环里的不算）。
bool _breaksOut(List<LcBlock> list, int depth) {
  if (depth > LcBlock.maxDepth) return false;
  for (final b in list) {
    if (b.op == 'break') return true;
    if (_loopOps.contains(b.op)) continue;
    if (_breaksOut(b.body, depth + 1) || _breaksOut(b.orElse, depth + 1)) return true;
    for (final a in b.arms) {
      if (_breaksOut(a.body, depth + 1)) return true;
    }
  }
  return false;
}

/// 这一串积木是不是“怎么走都会返回”（最后一定碰到“返回”积木）。
/// “如果”要每一段（含否则如果）和“否则”都返回、而且“否则”没收起来；“分情况”同理；
/// “一直重复”里没有跳出就出不来，只能靠“返回”结束，也算。
bool beAlwaysResponds(List<LcBlock> list, [int depth = 0]) {
  if (depth > LcBlock.maxDepth) return false;
  bool all(LcBlock b) => !b.noElse && beAlwaysResponds(b.orElse, depth + 1) && b.arms.every((a) => beAlwaysResponds(a.body, depth + 1));
  for (final b in list) {
    if (_respondOps.contains(b.op)) return true;
    if (b.op == 'if' && beAlwaysResponds(b.body, depth + 1) && all(b)) return true;
    if (b.op == 'switch' && b.arms.isNotEmpty && all(b)) return true;
    if (b.op == 'forever' && !_breaksOut(b.body, 0)) return true;
  }
  return false;
}

/// 检查器报的一条，已经对回到积木上。
class BeLangFinding {
  const BeLangFinding(this.code, this.isError, this.problem, this.path, this.arg, this.fix);

  /// [LcIssueCode] / [BeLangIssueCode] / `unreachable` 里的一种。
  final String code;
  final bool isError;
  final String problem;
  final LcBlockPath path;

  /// 积木的哪个参数（段参数是 `@<第几段>:<名字>`）；null＝整块。
  final String? arg;

  /// 比规则表里默认的更贴切的建议；null＝用默认的。
  final String? fix;
}

const Map<String, String> _codes = {
  'G03': LcIssueCode.unknownVar,
  'G07': LcIssueCode.tooDeep,
  'L04': BeLangIssueCode.outsideLoop,
  'L09': BeLangIssueCode.duplicateName,
  'L11': BeLangIssueCode.assignConst,
  'L13': BeLangIssueCode.endlessLoop,
  'S10': 'unreachable',
};

/// 用到新积木的接口：语言核心的检查器报了什么。没用到新积木的接口返回空表（旧的检查已经够了）。
List<BeLangFinding> beLangFindings(BeDocument doc, BeRoute route) {
  try {
    final shadow = beLangShadow(doc, route);
    if (shadow == null) return const [];
    final result = analyzeBody(shadow.stmts, outer: {for (final v in doc.variables) v.name});
    final out = <BeLangFinding>[];
    for (final i in result.issues) {
      final code = _codes[i.code];
      final at = int.tryParse(i.src?.block ?? '');
      if (code == null || at == null || at < 0 || at >= shadow.spots.length) continue;
      final spot = shadow.spots[at];
      final whole = code == 'unreachable' || code == BeLangIssueCode.outsideLoop || code == BeLangIssueCode.endlessLoop;
      out.add(BeLangFinding(code, i.isError, i.message, spot.path, whole ? null : spot.arg, code == LcIssueCode.unknownVar ? '把“新建变量”挪到用它的积木前面（同一层或更外面一层），或者换一个这里看得见的变量。' : null));
    }
    return out;
  } on Object {
    return const [];
  }
}
