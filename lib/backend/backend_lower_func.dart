/// 文档里的函数（“我的积木”的定义）怎么翻成语法树（积木第 4 版·第 2 阶段的“接线”）。
///
/// 每个函数＝一个 `LFuncDecl`：名字、参数名先过一遍 `beIdent`（用户起的名字常是中文、可能带空格），函数体和接口体走同一个翻译器
/// （backend_lower_lang.dart），只是“在函数里”：看不见文档里声明的变量（它们是每个接口各一份的），旧的“干活”积木照旧包成宿主语句。
/// 调用、匿名函数、“返回”这些新积木本身怎么翻在 backend_lower_lang.dart 里。
library;

import 'package:lopicode/backend/backend_function.dart';
import 'package:lopicode/backend/backend_ir.dart';
import 'package:lopicode/backend/backend_lower_lang.dart';
import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/lang/ast.dart';

/// 一个函数翻好的样子，连同“语法树节点 → 积木”的来源表（校验用）。
class BeLoweredFunction {
  const BeLoweredFunction(this.function, this.decl, this.spots);
  final BeFunction function;
  final LFuncDecl decl;
  final List<BeLangSpot> spots;
}

/// 函数的定义借接口的翻译器用：给它套一个不会被生成的壳。
BeRoute _shell(BeFunction f) => BeRoute(id: f.id, method: 'GET', path: '/', body: f.body);

/// [typed]＝带上标的类型（只有规矩版本 2 的类型检查要；老规矩的检查和生成不看类型，不带，结果和以前一样）。
List<LParam> beLangParams(BeFunction f, {bool typed = false}) => [
  for (final p in f.params) LParam(beIdent(p.name), defaultValue: p.defaultValue == null ? null : LLit(p.defaultValue), rest: p.rest, type: typed ? p.type : null),
];

/// 把文档里的函数全部翻出来。[shadow]＝给校验用的影子模式。任何输入都不抛异常。
List<BeLoweredFunction> beLowerFunctionsWithSpots(BeDocument doc, {bool shadow = false}) {
  final out = <BeLoweredFunction>[];
  for (final f in doc.functions) {
    final lower = beLangLowerOf(doc, _shell(f), shadow: shadow, inFunction: true);
    if (lower == null) continue;
    final body = lower.stmts(f.body, const [], 0);
    out.add(BeLoweredFunction(f, LFuncDecl(f.ident, beLangParams(f), body, src: LSrc(script: f.id)), lower.spots));
  }
  return out;
}

/// 生成用：文档里的函数 → 语法树（没有函数是空表，生成结果和以前一个字不差）。
List<LFuncDecl> beLowerFunctions(BeDocument doc) => doc.functions.isEmpty ? const [] : [for (final f in beLowerFunctionsWithSpots(doc)) f.decl];

/// 给校验 / 测试用：用到第 4 版积木的接口翻成语法树（影子模式，见 backend_lower_lang.dart）。没用到的返回 null。
({List<LStmt> stmts, List<BeLangSpot> spots, Map<String, bool> locals})? beLangShadow(BeDocument doc, BeRoute route) {
  final lang = beLangLowerOf(doc, route, shadow: true);
  if (lang == null) return null;
  return (stmts: lang.stmts(route.body, const [], 0), spots: lang.spots, locals: lang.locals);
}
