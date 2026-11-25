/// 一个函数体里“用到了哪些名字”：给闭包（Python 的 nonlocal、Java 的盒子、PHP 的 use）、给检查器
/// （“这段体里用到了哪些宿主值”）用。纯函数，只看语法树。
///
/// 规矩（设计稿 3.2、3.6）：一个函数体是一层作用域。“新建变量”、循环变量、参数是这一层自己的；
/// 给一个不是自己这一层的名字赋值，改的是外层的那个变量（闭包）。匿名函数是另一层，里面的名字单独算。
library;

import 'package:lopicode/lang/ast.dart';
import 'package:lopicode/lang/ast_util.dart';

/// 一句宿主的语句（[LHost]）用到的名字。语言核心看不懂宿主的语句，由宿主自己说（`LangHost.inspect`）。
class LHostUse {
  const LHostUse({this.reads = const {}, this.writes = const {}, this.declares = const {}, this.hostNames = const {}, this.lambdas = const []});

  /// 读了哪些变量、改了哪些变量、新建了哪些名字（夹在宿主语句里的新节点新建的）。
  final Set<String> reads;
  final Set<String> writes;
  final Set<String> declares;

  /// 用到的宿主的名字（比如后端的“这次请求”）。
  final Set<String> hostNames;

  /// 宿主语句里夹着的匿名函数（它们用到的外面的名字也要算）。
  final List<LLambda> lambdas;
}

typedef LHostInspect = LHostUse Function(Object payload);

/// 一个函数体自己这一层的名字（不进匿名函数里面；里面的在 [lambdas] 里另算）。
class LNames {
  LNames._();

  /// 这一层新建的名字（变量、常量、循环变量），按第一次出现的顺序。
  final List<String> declared = [];
  final Set<String> reads = {};
  final Set<String> writes = {};

  /// 读到的临时值、这一层自己存的临时值。
  final Set<String> temps = {};
  final Set<String> tempDecls = {};

  /// 用到的宿主的名字（`LNameKind.host`，以及宿主语句自己说的）。
  final Set<String> hostNames = {};

  /// 用到的宿主函数（[LNative]）的名字。
  final Set<String> natives = {};

  /// 直接套着的匿名函数。
  final List<LLambda> lambdas = [];

  /// 有没有宿主的语句；其中有没有“会结束这个函数”的（后端的“返回响应”）。
  bool hostStmts = false;
  bool hostReturns = false;
}

LNames lNames(List<LStmt> body, {LHostInspect? inspect}) {
  final out = LNames._();
  void declare(String n) {
    if (!out.declared.contains(n)) out.declared.add(n);
  }

  lDeclaredNames(body).forEach(declare);
  void expr(LExpr e) {
    // 不用递归：式子可能套得很深。
    final todo = <LExpr>[e];
    while (todo.isNotEmpty) {
      final x = todo.removeLast();
      switch (x) {
        case LName(:final name, :final kind):
          switch (kind) {
            case LNameKind.variable:
              out.reads.add(name);
            case LNameKind.temp:
              out.temps.add(name);
            case LNameKind.host:
              out.hostNames.add(name);
          }
        case LLambda():
          out.lambdas.add(x);
        case LNative(:final name):
          out.natives.add(name);
          todo.addAll(x.args);
        default:
          todo.addAll(lExprChildren(x));
      }
    }
  }

  lWalk(body, (s) {
    switch (s) {
      case LAssign(target: LTName(:final name)):
        out.writes.add(name);
      case LForEach(:final item, :final reuse):
        if (reuse) out.writes.add(item);
      case LLet(:final name, :final kind):
        if (kind == LNameKind.temp) out.tempDecls.add(name);
      case LHost(:final payload, :final returns):
        out.hostStmts = true;
        if (returns) out.hostReturns = true;
        final use = inspect?.call(payload);
        if (use != null) {
          out.reads.addAll(use.reads);
          out.writes.addAll(use.writes);
          use.declares.forEach(declare);
          out.hostNames.addAll(use.hostNames);
          out.lambdas.addAll(use.lambdas);
        }
      default:
        break;
    }
    lStmtExprs(s).forEach(expr);
  });
  return out;
}

/// 一个函数用到的、不是它自己这一层的名字（连它里面套着的匿名函数用到的一起算）。
class LFree {
  LFree._();
  final Set<String> reads = {};
  final Set<String> writes = {};
  final Set<String> temps = {};
  final Set<String> hostNames = {};
  final Set<String> natives = {};
  bool hostStmts = false;
  bool hostReturns = false;

  Set<String> get names => {...reads, ...writes};
}

LFree lFree(List<LParam> params, List<LStmt> body, {LHostInspect? inspect}) {
  final out = LFree._();
  final names = lNames(body, inspect: inspect);
  final mine = {for (final p in params) p.name, ...names.declared};
  out.reads.addAll(names.reads.difference(mine));
  out.writes.addAll(names.writes.difference(mine));
  out.temps.addAll(names.temps.difference(names.tempDecls));
  out.hostNames.addAll(names.hostNames);
  out.natives.addAll(names.natives);
  out.hostStmts = names.hostStmts;
  out.hostReturns = names.hostReturns;
  for (final f in names.lambdas) {
    final inner = lFree(f.params, f.stmts, inspect: inspect);
    out.reads.addAll(inner.reads.difference(mine));
    out.writes.addAll(inner.writes.difference(mine));
    out.temps.addAll(inner.temps.difference(names.tempDecls));
    out.hostNames.addAll(inner.hostNames);
    out.natives.addAll(inner.natives);
    out.hostStmts = out.hostStmts || inner.hostStmts;
  }
  return out;
}

/// 这一串语句里（不管套了几层匿名函数）所有匿名函数用到的外面的名字：这一层的变量里被里层函数用到的那些。
/// Java 要把它们装进“盒子”。
Set<String> lCapturedNames(List<LStmt> body, {LHostInspect? inspect}) {
  final out = <String>{};
  for (final f in lNames(body, inspect: inspect).lambdas) {
    out.addAll(lFree(f.params, f.stmts, inspect: inspect).names);
  }
  return out;
}

/// 一个式子里的匿名函数用到的外面的名字（式子单独生成时用）。
Set<String> lCapturedNamesInExpr(LExpr e, {LHostInspect? inspect}) => lCapturedNames([LExprStmt(e)], inspect: inspect);
