/// 整份文档 / 一个模块的检查（第 2 阶段）：有名字的函数——互相看得见、可以调排在后面的、可以递归。
///
/// - [analyzeFunctions]：查一批有名字的函数，给出每个函数“对外的样子”（[LFuncInfo]：参数个数、有没有返回值、返回类型、
///   用到了哪些宿主的东西、是不是递归的）。宿主（后端）先调它，再把 `signatures` 传给每个接口体的 `analyzeBody`。
/// - [analyzeModule]：一个模块（模块级变量 ＋ 函数 ＋“启动时”）。
///
/// 规则号见 analyze.dart 的文件头；这里另外报：`L09` 函数重名 / 函数和模块级变量重名、`L14` 没人用的函数（警告）、
/// `L15` 函数里用了只有宿主的某个地方才有的东西（后端：这次请求、“返回响应”）——要用就当参数传进来。
library;

import 'package:lopicode/lang/analyze.dart';
import 'package:lopicode/lang/ast.dart';
import 'package:lopicode/lang/ast_util.dart';
import 'package:lopicode/lang/names.dart';
import 'package:lopicode/lang/types.dart';

/// 一个有名字的函数查完的结果。
class LFuncInfo extends LFuncSig {
  const LFuncInfo(
    super.name,
    super.params, {
    super.returnsValue,
    super.returnType,
    required this.analysis,
    this.hostNames = const {},
    this.natives = const {},
    this.hostStmts = false,
    this.hostReturns = false,
    this.calls = const {},
    this.recursive = false,
  });

  final LangAnalysis analysis;

  /// 这个函数体里（连同里面的匿名函数）用到的宿主的名字（后端：“这次请求”之类）、宿主函数。
  final Set<String> hostNames;
  final Set<String> natives;

  /// 有没有宿主的语句；其中有没有“会结束这个函数”的（后端的“返回响应”）。
  final bool hostStmts;
  final bool hostReturns;

  /// 它提到的别的函数（调用、当值；含自己）。
  final Set<String> calls;

  /// 会不会（直接或绕一圈）调到自己。带内联口的定义不许递归（设计稿 5.2）——内联口是第 3 阶段的事，那时用这个字段拦。
  final bool recursive;
}

class LangFunctionsAnalysis {
  const LangFunctionsAnalysis(this.issues, this.functions);

  /// 所有函数的问题（不含“没人用的函数”，那个要等宿主说完别处用了哪些，见 [unusedIssues]）。
  final List<LIssue> issues;
  final Map<String, LFuncInfo> functions;

  /// 传给 `analyzeBody(signatures: …)`。
  Map<String, LFuncSig> get signatures => functions;

  bool get hasErrors => issues.any((i) => i.isError);

  /// 被别的函数提到过的函数。
  Set<String> get usedByFunctions => {for (final f in functions.values) ...f.calls.where((c) => c != f.name)};

  /// 没人用的函数（L14，警告）。[usedElsewhere]：函数外面（接口体、“启动时”）用到的。
  List<LIssue> unusedIssues(Set<String> usedElsewhere, {Map<String, LSrc?> where = const {}}) {
    final used = {...usedElsewhere, ...usedByFunctions};
    return [
      for (final name in functions.keys)
        if (!used.contains(name)) LIssue('L14', '函数 $name 定义了但没有人用', isError: false, src: where[name]),
    ];
  }
}

/// 哪些函数会（直接或绕一圈）调到自己。[calls]：函数 → 它提到的函数。
Set<String> lRecursiveFunctions(Map<String, Set<String>> calls) {
  final out = <String>{};
  for (final start in calls.keys) {
    final seen = <String>{};
    final todo = [...?calls[start]];
    while (todo.isNotEmpty) {
      final n = todo.removeLast();
      if (n == start) {
        out.add(start);
        break;
      }
      if (seen.add(n)) todo.addAll(calls[n] ?? const {});
    }
  }
  return out;
}

bool _hasValueReturn(List<LStmt> body) {
  var found = false;
  lWalk(body, (s) {
    if (s is LReturn && s.value != null) found = true;
  });
  return found;
}

/// 查一批有名字的函数。纯函数、不抛异常。
///
/// [outer]／[outerConsts]：函数外面的模块级变量（函数里看得见、能读能改；函数自己新建的同名变量会盖住它）。
/// [inspect]：宿主的语句用到了哪些名字（没有宿主语句就不用给）。
/// [hostAllowed] 是 false（默认）时，函数里用了宿主的名字、有“会结束函数”的宿主语句报 `L15`。
LangFunctionsAnalysis analyzeFunctions(List<LFuncDecl> functions, {Set<String> outer = const {}, Set<String> outerConsts = const {}, LHostInspect? inspect, bool hostAllowed = false}) {
  final issues = <LIssue>[];
  final byName = <String, LFuncDecl>{};
  final lower = <String>{};
  for (final f in functions) {
    // PHP 的函数名不分大小写：只差大小写的两个名字在那里是同一个。哪种语言都拦，免得换了语言才出错。
    if (!lower.add(f.name.toLowerCase()) && !byName.containsKey(f.name)) {
      issues.add(LIssue('L09', '函数 ${f.name} 和另一个函数只差大小写（有的语言里函数名不分大小写），换一个名字', src: f.src));
    }
    if (byName.containsKey(f.name)) {
      issues.add(LIssue('L09', '已经有一个叫 ${f.name} 的函数了，换一个名字', src: f.src));
    } else if (outer.contains(f.name)) {
      issues.add(LIssue('L09', '已经有一个叫 ${f.name} 的变量了，函数换一个名字', src: f.src));
      byName[f.name] = f;
    } else {
      byName[f.name] = f;
    }
  }

  // 返回类型要看别的函数的返回类型：先都当“任意”查一遍，再用这一遍的结果查第二遍。
  Map<String, LangAnalysis> pass(Map<String, LFuncSig> sigs) => {
    for (final f in byName.values)
      f.name: analyzeFunctionBody(
        f.params,
        f.body,
        () => LangEnv(functions: byName, signatures: sigs, globals: outer, globalConsts: outerConsts, self: f.name, inspect: inspect),
        where: f.src,
      ),
  };
  final first = pass({for (final f in byName.values) f.name: LFuncSig(f.name, f.params, returnsValue: _hasValueReturn(f.body))});
  final done = pass({for (final f in byName.values) f.name: LFuncSig(f.name, f.params, returnsValue: first[f.name]!.returnsValue, returnType: first[f.name]!.returnType)});

  final recursive = lRecursiveFunctions({for (final e in done.entries) e.key: e.value.usedFunctions});
  final infos = <String, LFuncInfo>{};
  for (final f in byName.values) {
    final a = done[f.name]!;
    final free = lFree(f.params, f.body, inspect: inspect);
    issues.addAll(a.issues);
    if (!hostAllowed) {
      for (final h in free.hostNames) {
        issues.add(LIssue('L15', '函数 ${f.name} 里用了“$h”，它只在接口里才有；要用就当参数传进来', src: f.src));
      }
      if (free.hostReturns) issues.add(LIssue('L15', '函数 ${f.name} 里有只能放在接口里的积木（比如“返回响应”）；函数里请用“返回”', src: f.src));
    }
    infos[f.name] = LFuncInfo(
      f.name,
      f.params,
      returnsValue: a.returnsValue,
      returnType: a.returnsValue ? a.returnType : LType.nul,
      analysis: a,
      hostNames: free.hostNames,
      natives: free.natives,
      hostStmts: free.hostStmts,
      hostReturns: free.hostReturns,
      calls: a.usedFunctions,
      recursive: recursive.contains(f.name),
    );
  }
  return LangFunctionsAnalysis(issues, infos);
}

/// 一个模块查完的结果：[issues] 是全部问题；别的字段说的是“启动时”那一段（和第 1 阶段一样）。
class LangModuleAnalysis extends LangAnalysis {
  LangModuleAnalysis(super.issues, super.declared, super.variableTypes, super.types, {super.usedFunctions, required this.functions}) : super.raw();

  /// 模块里的函数。
  final Map<String, LFuncInfo> functions;
}

/// 检查一个模块：模块级变量 ＋ 函数 ＋“启动时”。
LangModuleAnalysis analyzeModule(LModule m) {
  final seen = <String>{};
  final consts = <String>{};
  final pre = <LIssue>[];
  final lets = <LStmt>[];
  for (final d in m.decls) {
    // 函数重名、函数和变量重名在 analyzeFunctions 里报。
    if (d is! LFuncDecl && !seen.add(d.name)) pre.add(LIssue('L09', '已经有一个叫 ${d.name} 的了', src: d.src));
    if (d is LVarDecl) {
      if (d.isConst) consts.add(d.name);
      // 模块级变量的初始值按声明顺序算：当成“启动时”最前面的赋值来检查（名字已经登记过，不会再报重名）。
      lets.add(LAssign(LTName(d.name, src: d.src), d.init, src: d.src));
    }
  }
  final names = {
    for (final d in m.decls)
      if (d is LVarDecl) d.name,
  };
  final decls = m.decls.whereType<LFuncDecl>().toList();
  final funcs = analyzeFunctions(decls, outer: {...seen}, outerConsts: consts);
  // 重名的只认第一个
  final callable = {for (final f in decls.reversed) f.name: f}.values.toList();
  // 初始化那几句赋值不算“给常量重新赋值”：先不把它们当常量查，再单独查“启动时”。
  final init = analyzeBody(lets, outer: names, inFunction: false, functions: callable, signatures: funcs.signatures);
  final body = analyzeBody(m.body, outer: names, outerConsts: consts, inFunction: false, functions: callable, signatures: funcs.signatures);
  final used = {...init.usedFunctions, ...body.usedFunctions};
  return LangModuleAnalysis(
    [
      ...pre,
      ...funcs.issues,
      ...init.issues,
      ...body.issues,
      ...funcs.unusedIssues(used, where: {for (final f in decls) f.name: f.src}),
    ],
    [...names, ...body.declared],
    {...init.variableTypes, ...body.variableTypes},
    Map.identity()
      ..addAll(init.exprTypes)
      ..addAll(body.exprTypes),
    usedFunctions: used,
    functions: funcs.functions,
  );
}
