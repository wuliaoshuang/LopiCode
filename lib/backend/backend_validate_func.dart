/// 后端积木校验里“函数 / 我的积木”的那一半（积木第 4 版·第 2 阶段）。
///
/// - 定义本身：外观（语言核心的 `validateLook`，规则 B01–B09）、参数名。
/// - 定义里面：语言核心的检查器对这一批函数说的（L01 / L02 / L03 / L09 / L14 / L15 / S11 / G03…），对回到积木上。
/// - 放错地方的积木：“返回响应”“请求别的网址”只能直接放在接口里。
///
/// 都是只读的纯函数，不抛异常。问题怎么变成 `LcLogicIssue` 在 backend_validate.dart。
library;

import 'package:lopicode/backend/backend_blocks_func.dart';
import 'package:lopicode/backend/backend_func_table.dart';
import 'package:lopicode/backend/backend_function.dart';
import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/backend/backend_validate_lang.dart';
import 'package:lopicode/blocks/block_look.dart';
import 'package:lopicode/lang/lang.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:lopicode/lowcode/logic_validate.dart';

/// 函数带来的问题种类（规则编号见 lib/lowcode/logic_rules.dart）。
abstract final class BeFuncIssueCode {
  /// L01 调用的积木 / 函数不在了；调的东西明摆着不是函数。
  static const String unknownFunction = 'unknownFunction';

  /// L02 调用时给的值个数不对；参数表本身不对。
  static const String badCall = 'badCall';

  /// L03 “返回”放错了地方；没有返回值的积木被当成值用（警告）。
  static const String badReturn = 'badReturn';

  /// L14 没人用的积木、没用到的参数（警告）。
  static const String unusedFunction = 'unusedFunction';

  /// L15 自定义积木 / 匿名函数里用了只有接口里才有的东西。
  static const String hostInFunction = 'hostInFunction';

  /// 外观的问题：`look01`–`look09` 对应规则 B01–B09。
  static String look(String rule) => 'look${rule.replaceFirst('B', '')}';
}

/// 定义帽子上的一个问题。
class BeFuncHeadProblem {
  const BeFuncHeadProblem(this.code, this.problem, {this.isError = true, this.arg, this.fix});
  final String code;
  final String problem;
  final bool isError;

  /// 帽子上的哪一格（`name`＝名字）；null＝整个帽子。
  final String? arg;
  final String? fix;
}

/// 这一串里（定义的参数 + 所有匿名函数的参数）出现过的参数名。读一个不在里面的参数一定是错的；
/// 在里面但那个位置看不见的（比如在匿名函数外面读它的参数）由语言核心的检查器报。
Set<String> beTreeParamNames(LcBlockTree tree) {
  final out = <String>{if (tree is BeFunction) ...tree.paramNames};
  beVisitBlocks(
    tree.body,
    (b) => beVisitExprs(b, (e) {
      final ps = e['params'];
      if ((e['e'] == 'lambda' || e['e'] == 'lambdaExpr') && ps is List) out.addAll(ps.whereType<String>());
    }),
  );
  return out;
}

/// 定义本身的问题：外观（B01–B09）和参数名。
List<BeFuncHeadProblem> beFuncHeadProblems(BeFunction f, BeFuncTable table) {
  final out = <BeFuncHeadProblem>[];
  final names = f.paramNames;
  final why = bkParamNameProblems(names);
  final idents = <String>{};
  for (var i = 0; i < names.length; i++) {
    final n = names[i];
    if (beParamNameReserved(n)) {
      out.add(BeFuncHeadProblem(LcIssueCode.badArg, '参数不能叫“$n”（这个名字积木自己要用）', fix: '点帽子上的这个参数，换个名字。'));
    } else if (why[i] != null) {
      out.add(BeFuncHeadProblem(LcIssueCode.badArg, '参数“$n”：${why[i]}', fix: '点帽子上的这个参数，换个名字。'));
    } else if (!idents.add(beIdent(n).toLowerCase())) {
      out.add(BeFuncHeadProblem(BeLangIssueCode.duplicateName, '参数“$n”和前面的参数写进代码以后是同一个名字（符号、空格、大小写在代码里不算数）', fix: '点帽子上的这个参数，换个差别大一点的名字。'));
    }
  }
  final info = table.infoOf(f);
  for (final p in validateLook(f.look, names, hasValue: info?.returnsValue)) {
    out.add(
      BeFuncHeadProblem(
        BeFuncIssueCode.look(p.code),
        p.slot == null ? p.message : '参数“${p.slot}”：${p.message}',
        isError: p.isError,
        arg: p.code == 'B01' ? 'name' : null,
        fix: p.code == 'B01' ? '点帽子上的名字，填一个。' : null,
      ),
    );
  }
  return out;
}

/// 这个函数的定义里，语言核心的检查器报了什么（含“没人用”）。[used]＝各个接口用到的函数。
List<BeLangFinding> beFuncFindings(BeFuncTable table, BeFunction f, Set<String> used) {
  try {
    final lowered = table.lowered.where((l) => identical(l.function, f)).firstOrNull;
    if (lowered == null) return const [];
    final issues = <LIssue>[
      // “函数里有只能放在接口里的积木”不要整个函数报一条：backend_validate.dart 已经指到具体那一块上了。
      for (final i in table.analysis.issues)
        if (!(i.code == 'L15' && i.message.contains('只能放在接口里的积木'))) i,
      ...table.analysis.unusedIssues(used, where: {for (final l in table.lowered) l.decl.name: l.decl.src}),
    ];
    return beMapLangIssues(issues, lowered.spots, script: f.id);
  } on Object {
    return const [];
  }
}

/// 把一块不交回结果的自定义积木当值用（L03 警告）：返回问题；不是这种情况返回 null。
String? beCallNoValueProblem(BeFuncTable table, String? kind) {
  final f = table.doc.function(beCallId(kind) ?? '');
  final info = f == null ? null : table.infoOf(f);
  return f == null || info == null || info.returnsValue ? null : '「${f.name}」不交回结果（它的定义里没有“返回 (值)”），拿它当值用会得到空';
}

const Set<String> _respondOps = {'respondJson', 'respondText'};

/// 只能直接放在接口里的积木放进了函数 / 匿名函数：返回（问题，怎么改）；没问题返回 null。
(String, String)? beHostOnlyProblem(String op, {required bool inFunction, required bool inLambda}) {
  if (!inFunction && !inLambda) return null;
  final where = inLambda ? '匿名函数' : '自定义积木';
  if (_respondOps.contains(op)) {
    return ('“返回响应”不能放在$where里：它在这里结束不了接口', '在这里用“返回 (值)”把结果交出去，回到接口里再接“返回响应”。');
  }
  if (op == 'fetch') {
    return ('“请求别的网址”不能放在$where里：它要停下来等对方回话，只有接口里能等', '把这块留在接口里，请求回来的结果当参数传进去。');
  }
  return null;
}

/// 第 2 阶段的值自己的问题：返回（问题种类，问题，怎么改）；没问题返回 null。[params]＝这一串里出现过的参数名。
(String, String, String?)? beFuncExprProblem(BeDocument doc, String? kind, Map<Object?, Object?> expr, Set<String> params) {
  switch (kind) {
    case 'funcRef':
      final id = expr['fn'];
      if (id is String && id.isNotEmpty && doc.function(id) == null) {
        return (BeFuncIssueCode.unknownFunction, '这里指的那块自定义积木已经不在了', '点这一格，重新选一块积木。');
      }
    case 'param':
      final name = expr['name'];
      if (name is String && name.isNotEmpty && !params.contains(name)) {
        return (LcIssueCode.unknownVar, '这里没有叫“$name”的参数', '点这一格换一个参数；或者到帽子 / 匿名函数上加一个叫这个名字的参数。');
      }
    case 'lambda' || 'lambdaExpr':
      final raw = expr['params'];
      if (raw is! List) return (LcIssueCode.badArg, '匿名函数的参数表坏了', '删掉这个匿名函数，重新拖一个出来。');
      final seen = <String>{};
      for (final p in raw) {
        if (p is! String || p.trim().isEmpty) return (LcIssueCode.badArg, '匿名函数有一个参数没有名字', '点那个参数小块，给它起个名字。');
        if (beParamNameReserved(p)) return (LcIssueCode.badArg, '参数不能叫“$p”（这个名字积木自己要用）', '点那个参数小块，换个名字。');
        if (!seen.add(beIdent(p).toLowerCase())) return (BeLangIssueCode.duplicateName, '匿名函数有两个参数叫“$p”（符号、空格、大小写在代码里不算数）', '点其中一个参数小块，换个名字。');
      }
  }
  return null;
}
