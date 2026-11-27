/// 第 3 版的中间形式（backend_ir.dart）和积木第 4 版的语法树（lib/lang）之间的桥。
///
/// 取舍（**按稳妥的办法先做，可改**）：两条路并存——旧积木照旧翻成 `BeS` / `BeX`、由各语言的 `BeCodeTarget` 写代码
/// （生成的文本一个字都没变）；新积木翻成 lib/lang 的语法树，包在 [BeSLang] / [BeXLang] 里夹进同一串语句，由 lib/lang 的生成器写代码。
/// 两边可以互相套：
/// - 新节点里面要放旧语句：用 [beHostStmts] 包成 `LHost`；要放旧式子：用 [beToLangExpr] 转成语法树的式子。
/// - 旧语句（如果 / 重复…）里面放新节点：直接把 [BeSLang] 放进它的语句表；旧式子里放新式子：[BeXLang]。
library;

import 'package:lopicode/backend/backend_ir.dart';
import 'package:lopicode/lang/ast.dart';
import 'package:lopicode/lang/ast_util.dart';
import 'package:lopicode/lang/gen_scope.dart';
import 'package:lopicode/lang/names.dart';
import 'package:lopicode/lowcode/logic_model.dart';

/// “这次请求”在生成的代码里叫什么。五种语言的 `BeCodeTarget.request` 都是它（有测试守着）；翻译这一层和语言无关，所以写死在这里。
const String kBeRequestName = 'req';

/// 旧式子 → 语法树的式子。[request] 是“这次请求”在生成的代码里叫什么（`BeCodeTarget.request`）。
/// 调小库函数变成 `LNative`（宿主函数）：生成时交回给后端的 `call`，写法和旧路一样。
LExpr beToLangExpr(BeX x, {required String request}) => switch (x) {
  BeXLang(:final expr) => expr,
  BeXLit(:final value) => LLit(value),
  BeXVar(:final name) => LName(name),
  BeXTmp(:final slot) => LName('$slot', kind: LNameKind.temp),
  BeXReq() => LName(request, kind: LNameKind.host),
  BeXCall(:final fn, :final args) => LNative(fn, [for (final a in args) beToLangExpr(a, request: request)]),
};

/// “走库”的翻法（积木第 5 版·库 1，见 backend_to_service.dart）：旧式子、旧的“干活”语句不再包成 `LNative` / `LHost`，
/// 而是换成内置库的积木展开出来的语法树。翻译器上挂了它（`BeLangLower.bridge`）才走；没挂一切照旧。
abstract interface class BeLibBridge {
  LExpr expr(BeX x);
  List<LStmt> stmts(List<BeS> list);

  /// 带口的旧积木（现在只有“请求别的网址”）：按旧名找到库积木，[args] 照旧小库的参数顺序，口里的语句已经翻好。
  /// 库里没有这块积木＝null。
  List<LStmt>? mouthBlock(String legacyFn, List<LExpr> args, {Map<String, List<LStmt>> mouths = const {}, String? into});

  /// 用户库的积木（op 是 `lib:库标识#编号`），和库的定义画布上那两块“做口里的积木”“交给用的人选的变量”。不是这些＝null。
  /// [value]＝把这块积木的某个槽翻成式子；[inner]＝把它的口（第一个口 / [inElse]＝第二个口）里的积木翻成语句。
  List<LStmt>? libBlock(LcBlock b, LExpr Function(String slot) value, List<LStmt> Function(List<LcBlock> list, {bool inElse}) inner, {required bool shadow});

  /// 用户库的值型积木（`{"e": "lib:…#…"}`）。[raw]＝槽里原样存的东西。不是库积木＝null。
  LExpr? libExpr(String kind, LExpr Function(String slot) value, Object? Function(String slot) raw);
}

/// 旧语句 → 可以放进新节点里的语句：新节点原样摊开，别的包成 `LHost`（生成时交回给后端照旧路写）。
List<LStmt> beHostStmts(List<BeS> list) => [
  for (final s in list)
    if (s is BeSLang) ...s.stmts else LHost(s, returns: beAlwaysReturns([s])),
];

/// 把一串旧语句连同里面夹着的新节点、新节点里夹着的旧语句，全部走一遍。
void _walk(List<BeS> list, {void Function(BeSLang s)? onLang, void Function(BeX x)? onExpr}) {
  void lang(List<LStmt> stmts) => lWalk(stmts, (s) {
    if (s is LHost && s.payload is BeS) _walk([s.payload as BeS], onLang: onLang, onExpr: onExpr);
  });
  for (final s in list) {
    switch (s) {
      case BeSLang():
        onLang?.call(s);
        lang(s.stmts);
      case BeSNote():
        break;
      case BeSSet(:final value) || BeSLet(:final value):
        onExpr?.call(value);
      case BeSDo(:final call):
        onExpr?.call(call);
      case BeSReturn(:final response):
        onExpr?.call(response);
      case BeSIf(:final cond, :final then, :final orElse):
        onExpr?.call(cond);
        _walk(then, onLang: onLang, onExpr: onExpr);
        _walk(orElse, onLang: onLang, onExpr: onExpr);
      case BeSRepeat(:final times, :final body):
        onExpr?.call(times);
        _walk(body, onLang: onLang, onExpr: onExpr);
      case BeSForEach(list: final l, :final body):
        onExpr?.call(l);
        _walk(body, onLang: onLang, onExpr: onExpr);
    }
  }
}

bool _hasLangExpr(BeX x) => switch (x) {
  BeXLang() => true,
  BeXCall(:final args) => args.any(_hasLangExpr),
  _ => false,
};

/// 这一串语句里有没有用到积木第 4 版的节点（用到了，生成的工程要多带语言核心的小库）。
bool beBodyUsesLang(List<BeS> body) {
  var used = false;
  _walk(body, onLang: (_) => used = true, onExpr: (x) => used = used || _hasLangExpr(x));
  return used;
}

bool beUsesLang(BeProgram program) => program.functions.isNotEmpty || program.routes.any((r) => beBodyUsesLang(r.body));

/// **给第三步的入口**：给翻好的后端加上文档级的函数（“我的积木”的定义）。
///
/// 生成时每个函数变成各语言的顶层函数（Java 是 `Main` 里的静态方法），排在接口前面；每个接口体、每个函数体里都能调它们，
/// 函数之间可以互相调、可以调排在后面的。函数里看不见接口的变量、“这次请求”（要用就当参数传进来）。
/// 函数体里也可以夹旧语句（[beHostStmts]）。生成前先用 `analyzeFunctions`、`analyzeBody(functions: …)` 检查。
/// [functions] 是空的时候原样返回，生成结果一个字不变。
BeProgram beWithFunctions(BeProgram program, List<LFuncDecl> functions) =>
    functions.isEmpty ? program : BeProgram(name: program.name, port: program.port, collections: program.collections, routes: program.routes, skipped: program.skipped, functions: functions);

/// 一句旧语句用到了哪些名字（给闭包、给检查器用）：读 / 改了哪些变量，用没用“这次请求”，里面夹着的新节点新建了什么。
/// 传给 `LangHost.inspect`、`analyzeFunctions(inspect: …)`、`analyzeBody(inspect: …)`。
LHostUse beHostInspect(Object payload) {
  if (payload is! BeS) return const LHostUse();
  final reads = <String>{}, writes = <String>{}, declares = <String>{}, hostNames = <String>{};
  final lambdas = <LLambda>[];
  void names(List<LStmt> stmts) {
    final n = lNames(stmts, inspect: beHostInspect);
    reads.addAll(n.reads);
    writes.addAll(n.writes);
    declares.addAll(n.declared);
    hostNames.addAll(n.hostNames);
    lambdas.addAll(n.lambdas);
  }

  void expr(BeX x) {
    switch (x) {
      case BeXLang(:final expr):
        names([LExprStmt(expr)]);
      case BeXVar(:final name):
        reads.add(name);
      case BeXReq():
        hostNames.add(kBeRequestName);
      case BeXCall(:final args):
        args.forEach(expr);
      case BeXLit() || BeXTmp():
        break;
    }
  }

  void stmts(List<BeS> list) {
    for (final s in list) {
      switch (s) {
        case BeSLang(stmts: final inner):
          names(inner);
        case BeSNote():
          break;
        case BeSSet(:final name, :final value):
          writes.add(name);
          expr(value);
        case BeSLet(:final value):
          expr(value);
        case BeSDo(:final call):
          expr(call);
        case BeSReturn(:final response):
          expr(response);
        case BeSIf(:final cond, :final then, :final orElse):
          expr(cond);
          stmts(then);
          stmts(orElse);
        case BeSRepeat(:final times, :final body):
          expr(times);
          stmts(body);
        case BeSForEach(list: final l, :final item, :final body):
          expr(l);
          writes.add(item);
          stmts(body);
      }
    }
  }

  stmts([payload]);
  return LHostUse(reads: reads, writes: writes, declares: declares, hostNames: hostNames, lambdas: lambdas);
}

/// 一个接口函数体的作用域：能调哪些函数、自己有哪些变量、哪些变量被里面的匿名函数用到了（Java 要给它们装盒子）。
LangScope beRouteScope(BeRouteProgram r, List<LFuncDecl> functions) {
  final captured = <String>{};
  void expr(BeX x) {
    if (x is BeXLang) captured.addAll(lCapturedNamesInExpr(x.expr, inspect: beHostInspect));
    if (x is BeXCall) x.args.forEach(expr);
  }

  _walk(
    r.body,
    onLang: (s) => captured.addAll(lCapturedNames(s.stmts, inspect: beHostInspect)),
    onExpr: expr,
  );
  final locals = {for (final v in r.variables) v.name, ...beLangDeclares(r.body)};
  return LangScope.open(module: LangModuleInfo.of(functions), locals: locals, boxed: locals.intersection(captured));
}

/// 这一串语句里的新节点新建了哪些名字（变量、常量、循环变量），按第一次出现的顺序。接口函数开头要统一声明它们。
List<String> beLangDeclares(List<BeS> body) {
  final out = <String>[];
  _walk(
    body,
    onLang: (s) {
      for (final n in lDeclaredNames(s.stmts)) {
        if (!out.contains(n)) out.add(n);
      }
    },
  );
  return out;
}
