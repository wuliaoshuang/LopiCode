/// 生成器的公共骨架（设计稿 4.4）：吃语法树（ast.dart），吐一种语言的代码。五种语言各有一个子类（gen_*.dart），
/// 只回答“这种语言里这个东西怎么写”。
///
/// 第 1 阶段的做法（**按建议先做，可改**）：
/// - **所有运算都走运行时小库**（设计稿“问题 1”的建议 A）：`a + b` 生成成 `lc.add(a, b)`，不生成原生运算符。慢一点、啰嗦一点，
///   但五种语言逐字节一致；以后类型推断够用了，再把能确定类型的地方换成原生写法。
/// - **Go / Java 里值一律是 `any` / `Object`**（“问题 2”的建议）：标的类型只用于校验，不进生成的代码。
/// - 变量（含常量、循环变量）**一律提到函数开头声明**，原处只赋值：没有块级作用域（设计稿 3.2），五种语言才一致。
///   常量在生成的代码里和变量一样，“不许再改”只靠校验（L11）拦。
///
/// 约定（和 lib/backend 的 `BeCodeTarget` 一样）：语句函数返回一行行代码，**不带这一层的缩进**。
library;

import 'package:lopicode/lang/ast.dart';
import 'package:lopicode/lang/ast_util.dart';
import 'package:lopicode/lang/gen_func.dart';
import 'package:lopicode/lang/gen_scope.dart';
import 'package:lopicode/lang/gen_support.dart';
import 'package:lopicode/lang/names.dart';
import 'package:lopicode/lang/rt.dart';

export 'package:lopicode/lang/gen_scope.dart';
export 'package:lopicode/lang/gen_support.dart';
export 'package:lopicode/lang/names.dart';

/// 生成器的主体：语句和式子。函数那一部分（定义、调用、匿名函数、闭包、整份脚本）在 gen_func.dart 的 [LangFuncGen] 里，
/// 两块合起来才是 [LangGen]。
abstract class LangCore {
  const LangCore({this.host = const LangHost()});

  final LangHost host;

  /// 语言 id：node / python / go / java / php。
  String get id;

  /// 能力表：特性名（[kLangFeatures]）→ 怎么支持。
  Map<String, LCap> get caps => kLangBaseCaps;

  String get indentUnit => '  ';

  /// 运行时小库里语言核心那一份的文件名（相对路径）；内容由宿主带（lib/backend 的 runtime_*_lang.dart）。
  String get runtimeFile;

  // —— 这种语言里怎么写 ——

  /// 字面量：null / bool / num / String。
  String literal(Object? value);

  /// 用户起的名字。一律加 `v_`：撞不上任何语言的关键字。
  String variable(String name) => 'v_$name';

  /// 临时值（[LNameKind.temp]）。
  String temp(String name) => 'lcT$name';

  /// 生成器自己给循环起的名字：`lcv` + 一个字母 + 编号（和第 3 版后端的 `lcI1`、`lcN1`、`lcItem1` 不会重）。
  String loopName(String letter, int n) => 'lcv$letter$n';

  /// 调值的规矩最底下的函数（[kLangCoreFns]）。
  String coreCall(String fn, List<String> args);

  /// 调第 4 版新加的小库函数（[kLangRtFns]）。
  String langCall(String fn, List<String> args);

  String comment(String text);

  /// 在函数开头声明一个变量，初始是空。
  List<String> declare(String name);

  /// 一句话的结尾（`;` 或什么都没有）。
  String get end => ';';

  /// 就地存一个不会再改的值：`const x = v;`。[type] 是它在这种语言里的类型。
  String local(LRet type, String name, String value);

  /// 代码块是不是用花括号（Python 不是）。
  bool get braces => true;
  String ifHead(String cond) => 'if ($cond)';
  String elseIfHead(String cond) => 'else if ($cond)';

  /// [cond] 是 null＝一直重复。
  String whileHead(String? cond) => 'while (${cond ?? 'true'})';

  /// 从 0 数到 n − 1 的循环头；[k] 是语言自己的整数。
  String countedHead(String k, String n);
  String get andOp => '&&';
  String get orOp => '||';

  /// 值版的“如果”：只算选中的那一边。
  String ternary(String cond, String then, String orElse) => '($cond ? $then : $orElse)';

  /// 语言自己的列表（`items` 给的）有几项、第 k 项。
  String nativeLen(String list);
  String nativeAt(String list, String k);

  /// 语言自己的整数 → 值的规矩里的数字。
  String intToNumber(String k) => k;

  /// “从…数到…”第 k 遍的值：`a + k × s`（三个都是语言自己的数）。
  String stepValue(String a, String k, String s) => '$a + ${intToNumber(k)} * $s';

  /// 返回。`value` 是 null＝什么都不返回。
  String returnLine(String? value) => value == null ? 'return$end' : 'return $value$end';

  /// 一个完整的、能直接运行的脚本：每个模块是一个函数，按顺序各跑一遍。[bodies] 是各模块的函数体（声明＋语句，不带缩进）。
  /// 约定：运行时小库的文件和脚本放在同一个目录（各语言的文件名见 [runtimeFile] 和 lib/backend 的生成器）。
  ///
  /// [top]：放在文件顶层、各模块函数前面的代码（模块级变量、有名字的函数；Java 里是类的静态成员），不带缩进。
  String scriptSource(List<List<String>> bodies, {List<String> top = const []});

  // —— 骨架 ——

  List<String> indented(List<String> lines) => [for (final l in lines) l.isEmpty ? l : '$indentUnit$l'];

  /// 一个代码块：`head {` … `}`，或 Python 的 `head:` + 缩进（空的补 `pass`）。
  List<String> block(String head, List<String> body) => braces ? ['$head {', ...indented(body), '}'] : ['$head:', ...suite(body)];

  /// Python 的一段缩进的代码：空的（或只有注释）补一句 `pass`。
  List<String> suite(List<String> body) => indented([...body, if (body.every((l) => l.trimLeft().startsWith('#'))) 'pass']);

  /// **入口**：一段语句 → 代码片段。[ctx] 同一个函数体里的几段要共用一个（循环的临时名字才不会重）。
  /// 碰到这一阶段不支持的节点抛 [LangUnsupported]。
  ///
  /// 这一段里有匿名函数、目标语言又要给被里层函数用到的变量装“盒子”（Java）时：这些名字记进 `ctx.scope.boxed`，
  /// 宿主声明变量要用 [declareIn]。同一个函数体分几段生成的，要先把整个函数体的算好放进 `LangScope.open(boxed: …)`
  /// （后端的 `BeCodeTarget.routeBody` 就是这么做的）。
  LangFragment fragment(List<LStmt> body, {LangCtx? ctx}) {
    final c = ctx ?? LangCtx();
    if (boxesCaptured) c.scope.boxed.addAll(lCapturedNames(body, inspect: host.inspect));
    return LangFragment(lDeclaredNames(body), statements(body, c));
  }

  /// 在某一层里声明一个变量（[declare] 不知道它要不要装盒子）。
  List<String> declareIn(LangScope scope, String name) => declare(name);

  /// 被里层函数用到的变量要不要装“盒子”（只有 Java 要）。
  bool get boxesCaptured => false;

  List<String> statements(List<LStmt> list, LangCtx ctx) {
    final out = <String>[];
    final prev = LangCtx.current;
    final scope = ctx.scope;
    final outerPending = scope.pending;
    LangCtx.current = ctx;
    try {
      for (final s in list) {
        // 这一句的式子里要是有带函数体的匿名函数，它的定义先放到这一句前面。
        scope.pending = [];
        final lines = statement(s, ctx);
        out
          ..addAll(scope.pending)
          ..addAll(lines);
        // 后面的不会执行，不翻译（Java 碰到执行不到的语句编译不过）。
        if (lExits(s)) break;
      }
    } finally {
      scope.pending = outerPending;
      LangCtx.current = prev;
    }
    return out;
  }

  // —— 函数那一部分（gen_func.dart）——

  /// 读一个用户起的名字：这一层 / 外层的变量、模块级变量，或一个有名字的函数（当值用）。
  String nameExpr(String name, LSrc? src);

  /// 给一个名字赋值时，等号左边怎么写。
  String targetName(String name);
  String callExpr(LCall e);
  String lambdaExpr(LLambda e);

  /// 现在这个位置能不能直接“返回”。
  bool get canReturn;

  /// “返回”：没有值的在有的语言里要补一个空（函数一律有返回值）。
  List<String> returnStmt(LExpr? value);

  List<String> statement(LStmt s, LangCtx ctx) {
    switch (s) {
      case LNote(:final text):
        return [comment(text)];
      case LLet(:final name, :final value, :final kind):
        return switch (kind) {
          LNameKind.variable => ['${targetName(name)} = ${expr(value)}$end'],
          LNameKind.temp => [local(LRet.any, temp(name), expr(value))],
          LNameKind.host => throw LangUnsupported('不能新建宿主的名字 $name', src: s.src),
        };
      case LAssign(:final target, :final value):
        return switch (target) {
          LTName(:final name) => ['${targetName(name)} = ${expr(value)}$end'],
          LTIndex(:final of, :final key) => [
            '${langCall('setItem', [expr(of), expr(key), expr(value)])}$end',
          ],
          LTField() => throw LangUnsupported('对象的字段', stage: 5, src: s.src),
        };
      case LExprStmt(expr: final e):
        // 只有“调用”能单独成一句（Go、Java 的规矩）；别的包一层没有副作用的 isNull。
        final isCall = e is LCall || e is LRt || e is LNative || e is LBinary || e is LUnary || e is LIndex || e is LListLit || e is LDictLit;
        return [
          '${isCall ? _raw(e) : coreCall('isNull', [expr(e)])}$end',
        ];
      case LIf(:final arms, :final orElse):
        if (arms.isEmpty) return statements(orElse, ctx);
        final out = <String>[];
        for (var i = 0; i < arms.length; i++) {
          final head = i == 0 ? ifHead(condition(arms[i].cond)) : elseIfHead(condition(arms[i].cond));
          final body = statements(arms[i].body, ctx);
          if (braces) {
            out.add(i == 0 ? '$head {' : '} $head {');
            out.addAll(indented(body));
          } else {
            out.add('$head:');
            out.addAll(suite(body));
          }
        }
        if (orElse.isNotEmpty) {
          final body = statements(orElse, ctx);
          out.add(braces ? '} else {' : 'else:');
          out.addAll(braces ? indented(body) : suite(body));
        }
        if (braces) out.add('}');
        return out;
      case LWhile(:final cond, :final body):
        return block(whileHead(cond == null ? null : condition(cond)), statements(body, ctx));
      case LRepeat(:final times, :final body):
        final n = ctx.next();
        return [
          local(LRet.nativeInt, loopName('N', n), coreCall('times', [expr(times)])),
          ...block(countedHead(loopName('K', n), loopName('N', n)), statements(body, ctx)),
        ];
      case LForCount(:final name, :final from, :final to, :final step, :final body):
        final n = ctx.next();
        final a = loopName('A', n), b = loopName('B', n), st = loopName('S', n), k = loopName('K', n);
        return [
          local(LRet.number, a, langCall('toNumber', [expr(from)])),
          local(LRet.number, b, langCall('toNumber', [expr(to)])),
          local(LRet.number, st, langCall('toNumber', [expr(step)])),
          local(LRet.nativeInt, loopName('N', n), langCall('countSteps', [a, b, st])),
          ...block(countedHead(k, loopName('N', n)), ['${targetName(name)} = ${stepValue(a, k, st)}$end', ...statements(body, ctx)]),
        ];
      case LForEach(:final list, :final item, :final index, :final body):
        final n = ctx.next();
        final l = loopName('L', n), k = loopName('K', n);
        return [
          local(LRet.nativeList, l, coreCall('items', [expr(list)])),
          ...block(countedHead(k, nativeLen(l)), ['${targetName(item)} = ${nativeAt(l, k)}$end', if (index != null) '${targetName(index)} = ${intToNumber(k)}$end', ...statements(body, ctx)]),
        ];
      case LForPairs(:final dict, :final key, :final value, :final body):
        final n = ctx.next();
        final d = loopName('D', n), l = loopName('L', n), k = loopName('K', n);
        return [
          local(LRet.any, d, expr(dict)),
          local(
            LRet.nativeList,
            l,
            coreCall('items', [
              langCall('dictKeys', [d]),
            ]),
          ),
          ...block(countedHead(k, nativeLen(l)), [
            '${targetName(key)} = ${nativeAt(l, k)}$end',
            '${targetName(value)} = ${langCall('dictGet', [d, targetName(key)])}$end',
            ...statements(body, ctx),
          ]),
        ];
      case LBreak():
        return ['break$end'];
      case LContinue():
        return ['continue$end'];
      case LReturn(:final value):
        if (!canReturn) throw LangUnsupported('这里不能直接“返回”，要用宿主自己的返回（后端接口里是“返回响应”）', src: s.src);
        return returnStmt(value);
      case LHost(:final payload):
        final f = host.stmt;
        if (f == null) throw LangUnsupported('这里有一句宿主的语句，但没有接宿主', src: s.src);
        return f(payload);
      case LThrow():
        throw LangUnsupported('抛出错误', stage: 6, src: s.src);
      case LTry():
        throw LangUnsupported('试着做 / 出错了', stage: 6, src: s.src);
      case LStmtV5():
        throw LangUnsupported('“看是哪种情况”（要走严格规矩的生成路径，这条路还没有接上）', src: s.src);
    }
  }

  /// 当条件用：已经是语言自己的布尔就直接用，否则包一层 `truthy`。
  String condition(LExpr e) => _isNativeBool(e) ? _raw(e) : coreCall('truthy', [expr(e)]);

  bool _isNativeBool(LExpr e) => switch (e) {
    LLogic() => true,
    LUnary(:final op) => op == 'not',
    LBinary(:final op) => _fn(kLangBinaryFns[op])?.ret == LRet.bool,
    LRt(:final fn) => _fn(fn)?.ret == LRet.bool,
    _ => false,
  };

  static LRtFn? _fn(String? name) => name == null ? null : kLangRtFns[name] ?? kLangCoreFns[name];

  /// 一个式子的代码（当值用）。
  String expr(LExpr e) {
    if (e is LRt && _fn(e.fn)?.ret == LRet.none) {
      throw LangUnsupported('“${e.fn}”没有返回值，不能当值用', src: e.src);
    }
    return _raw(e);
  }

  String _rt(String fn, List<String> args, LSrc? src) {
    final lang = kLangRtFns[fn];
    if (lang != null) {
      if (lang.stage > kLangStage) throw LangUnsupported('小库函数 $fn', stage: lang.stage, src: src);
      return langCall(fn, args);
    }
    if (kLangCoreFns.containsKey(fn)) return coreCall(fn, args);
    throw LangUnsupported('语言核心的小库里没有 $fn 这个函数（宿主的函数请用 LNative）', src: src);
  }

  String _raw(LExpr e) {
    switch (e) {
      case LLit(:final value):
        return literal(value);
      case LListLit(:final items):
        return langCall('listOf', [for (final x in items) expr(x)]);
      case LDictLit(:final entries):
        return langCall('dictOf', [
          for (final p in entries) ...[expr(p.key), expr(p.value)],
        ]);
      case LName(:final name, :final kind):
        return switch (kind) {
          LNameKind.variable => nameExpr(name, e.src),
          LNameKind.temp => temp(name),
          LNameKind.host => host.name?.call(name) ?? name,
        };
      case LIndex(:final of, :final key):
        return langCall('item', [expr(of), expr(key)]);
      case LUnary(:final op, :final x):
        return switch (op) {
          'not' => coreCall('isNot', [expr(x)]),
          'neg' => coreCall('sub', [literal(0), expr(x)]),
          _ => throw LangUnsupported('不认识的一元运算 $op', src: e.src),
        };
      case LBinary(:final op, :final l, :final r):
        final fn = kLangBinaryFns[op];
        if (fn == null) throw LangUnsupported('不认识的运算 $op', src: e.src);
        return _rt(fn, [expr(l), expr(r)], e.src);
      case LLogic(:final op, :final l, :final r):
        if (op != 'and' && op != 'or') throw LangUnsupported('不认识的逻辑运算 $op', src: e.src);
        return '(${condition(l)} ${op == 'and' ? andOp : orOp} ${condition(r)})';
      case LCond(:final cond, :final then, :final orElse):
        return ternary(condition(cond), expr(then), expr(orElse));
      case LRt(:final fn, :final args):
        return _rt(fn, [for (final a in args) expr(a)], e.src);
      case LNative(:final name, :final args):
        final f = host.call;
        if (f == null) throw LangUnsupported('宿主函数 $name', stage: 3, src: e.src);
        return f(name, [for (final a in args) expr(a)]);
      case LCall():
        return callExpr(e);
      case LLambda():
        return lambdaExpr(e);
      case LField() || LSend() || LSuperSend() || LNew() || LIsA() || LThis():
        throw LangUnsupported('类和对象', stage: 5, src: e.src);
      case LAwait() || LSpawn():
        throw LangUnsupported('异步', stage: 6, src: e.src);
      case LExprV5():
        throw LangUnsupported('记录 / 枚举 / 变体 / 当成〈类型〉（要走严格规矩的生成路径，这条路还没有接上）', src: e.src);
    }
  }
}

/// 一种语言的生成器＝主体（[LangCore]）＋函数那一部分（[LangFuncGen]）。
abstract class LangGen extends LangCore with LangFuncGen {
  const LangGen({super.host});
}
