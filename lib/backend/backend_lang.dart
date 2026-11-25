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

bool beUsesLang(BeProgram program) => program.routes.any((r) => beBodyUsesLang(r.body));

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
