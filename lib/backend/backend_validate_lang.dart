/// 后端积木校验里“语言核心”的那一半（积木第 4 版·第 1 阶段）：用到新积木的接口交给 lib/lang 的检查器看一遍，
/// 把它报的（名字看不见、跳出不在循环里、名字重复、改常量、停不下来的循环、后面的不会执行）对回到积木和槽上。
///
/// 做法：把接口按“影子模式”翻成语法树（`beLangShadow`：名字照写、旧积木读写的变量另补几句），跑 `analyzeBody`，
/// 再按语法树节点上的来源下标查回积木路径。只读不改、不抛异常（翻不出来就当没有问题，别的检查照常）。
library;

import 'package:lopicode/backend/backend_blocks_func.dart';
import 'package:lopicode/backend/backend_func_table.dart';
import 'package:lopicode/backend/backend_ir.dart' show beLangLowerOf;
import 'package:lopicode/backend/backend_lang.dart';
import 'package:lopicode/backend/backend_lower_lang.dart';
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
  const BeLangFinding(this.code, this.isError, this.problem, this.path, this.arg, this.fix, {this.exprPath});

  /// [LcIssueCode] / [BeLangIssueCode] / `unreachable` 里的一种。
  final String code;
  final bool isError;
  final String problem;
  final LcBlockPath path;

  /// 积木的哪个参数（段参数是 `@<第几段>:<名字>`）；null＝整块。
  final String? arg;

  /// 在那个参数里的哪个位置（和积木编辑器的槽位路径同一种写法）；null＝不知道，按整个参数算。只有类型检查的问题带。
  final List<Object>? exprPath;

  /// 比规则表里默认的更贴切的建议；null＝用默认的。
  final String? fix;
}

const Map<String, String> _codes = {
  'G03': LcIssueCode.unknownVar,
  'G07': LcIssueCode.tooDeep,
  'L01': 'unknownFunction',
  'L02': 'badCall',
  'L03': 'badReturn',
  'L04': BeLangIssueCode.outsideLoop,
  'L09': BeLangIssueCode.duplicateName,
  'L11': BeLangIssueCode.assignConst,
  'L13': BeLangIssueCode.endlessLoop,
  'L14': 'unusedFunction',
  'L15': 'hostInFunction',
  'S10': 'unreachable',
  'S11': 'noRespond',
};

/// 检查器报的问题 → 对回到积木上。[spots] 是翻译时记的来源表；问题没带“哪一块”的（整个函数的问题）记在帽子上（空路径）。
/// [script] 给了就只要这一串的（一批函数一起查，问题是混在一起的）。
List<BeLangFinding> beMapLangIssues(Iterable<LIssue> issues, List<BeLangSpot> spots, {String? script}) {
  final out = <BeLangFinding>[];
  for (final i in issues) {
    final code = _codes[i.code];
    if (code == null || (script != null && i.src?.script != script)) continue;
    // “不交回结果的积木被当值用”由 backend_validate.dart 自己报（旧积木的格子里的值检查器看不到，那边看得全）。
    if (i.code == 'L03' && !i.isError) continue;
    // 语法树里“这次请求”叫 req、自定义积木叫“函数 名字”，给人看要换回人话（前面已经写了是哪块积木）。
    final problem = i.message
        .replaceAll('“req”', '“这次请求”（请求里的参数、请求头、请求内容这些）')
        .replaceAllMapped(RegExp(r'^函数 \S+ (?=定义了|里|和)'), (_) => '这块积木')
        .replaceAll('这个函数', '这块积木')
        .replaceAll('另一个函数', '另一块积木')
        .replaceAllMapped(RegExp(r'已经有一个叫 (.+) 的函数了'), (m) => '已经有一块叫“${m[1]}”的积木了')
        .replaceAll('“返回”要放在函数里面', '“返回 (值)”只能放在“定义”下面或匿名函数里');
    final block = i.src?.block;
    if (block == null) {
      if (script != null) out.add(BeLangFinding(code, i.isError, problem, const [], null, null));
      continue;
    }
    final at = int.tryParse(block);
    if (at == null || at < 0 || at >= spots.length) continue;
    final spot = spots[at];
    final whole = code == 'unreachable' || code == BeLangIssueCode.outsideLoop || code == BeLangIssueCode.endlessLoop || code == 'badReturn' || code == 'noRespond';
    out.add(BeLangFinding(code, i.isError, problem, spot.path, whole ? null : spot.arg, code == LcIssueCode.unknownVar ? '把“新建变量”挪到用它的积木前面（同一层或更外面一层），或者换一个这里看得见的变量。' : null));
  }
  return out;
}

/// 用到新积木的接口：语言核心的检查器报了什么。没用到新积木的接口返回空表（旧的检查已经够了）。
/// [table]＝文档里的“我的积木”（接口里调它们时要查个数、查在不在）；[used] 给了就把这个接口用到的函数记进去。
List<BeLangFinding> beLangFindings(BeDocument doc, BeRoute route, {BeFuncTable? table, Set<String>? used}) {
  try {
    final lang = beLangLowerOf(doc, route, shadow: true);
    if (lang == null) return const [];
    final stmts = lang.stmts(route.body, const [], 0);
    final functions = table == null || table.isEmpty ? const <LFuncDecl>[] : [for (final f in table.lowered) f.decl];
    // “返回 (值)”直接放在接口里是错的（接口要用“返回响应”）；匿名函数里的不算。
    final result = analyzeBody(
      stmts,
      outer: {for (final v in doc.variables) v.name},
      inFunction: false,
      functions: functions,
      signatures: functions.isEmpty ? const {} : table!.analysis.signatures,
      inspect: functions.isEmpty && !beBlocksUseFunc(route.body) ? null : beHostInspect,
    );
    used?.addAll(result.usedFunctions);
    return beMapLangIssues(result.issues, lang.spots);
  } on Object {
    return const [];
  }
}
