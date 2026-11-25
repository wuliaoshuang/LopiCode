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
import 'package:lopicode/lang/rt.dart';

/// 生成器碰到这一阶段还不支持的节点。消息是给人看的整句话。
class LangUnsupported implements Exception {
  const LangUnsupported(this.what, {this.stage, this.src});

  /// 是什么：“函数”“类”…，或一整句说明（[stage] 是 null 时）。
  final String what;

  /// 第几阶段才有。
  final int? stage;
  final LSrc? src;

  String get message => stage == null ? what : '还不支持“$what”（积木第 4 版第 $stage 阶段才有）';

  @override
  String toString() => 'LangUnsupported: $message${src == null ? '' : '（$src）'}';
}

/// 一种语言对一项语言特性的支持办法（设计稿 4.4 的“能力表”）。
enum LCap {
  /// 语言自己就有，直接生成。
  native,

  /// 语言没有，改写成别的写法（比如“从…数到…”改成按遍数的循环）。
  lowered,

  /// 交给运行时小库。
  runtime,

  /// 这种语言做不了，校验要拦。
  forbidden,

  /// 以后的阶段才做（现在生成器会抛 [LangUnsupported]）。
  later,
}

/// 能力表里的特性名。
const List<String> kLangFeatures = [
  'operators', // 加减乘除、比较
  'logic', // 并且 / 或者（短路）
  'cond', // 值版的“如果”
  'hoist', // 变量声明提到函数开头
  'const', // 常量
  'while',
  'forCount',
  'forEach',
  'forPairs',
  'repeat',
  'switch', // 按 x 分情况
  'listMutation', // 原地改列表
  'functions', // 第 2 阶段
  'closures', // 第 2 阶段
  'classes', // 第 5 阶段
  'errors', // 第 6 阶段
  'async', // 第 6 阶段
];

/// 五种语言共同的部分；各语言在自己的生成器里改不一样的几项。
const Map<String, LCap> kLangBaseCaps = {
  'operators': LCap.runtime,
  'logic': LCap.native,
  'cond': LCap.native,
  'hoist': LCap.lowered,
  'const': LCap.lowered,
  'while': LCap.native,
  'forCount': LCap.lowered,
  'forEach': LCap.lowered,
  'forPairs': LCap.lowered,
  'repeat': LCap.lowered,
  'switch': LCap.lowered,
  'listMutation': LCap.native,
  'functions': LCap.later,
  'closures': LCap.later,
  'classes': LCap.later,
  'errors': LCap.later,
  'async': LCap.later,
};

/// 宿主（比如后端）接进来的两样东西。都没有也行（纯脚本）。
class LangHost {
  const LangHost({this.call, this.stmt, this.name, this.allowReturn = true});

  /// [LNative]：调宿主的函数，参数已经写好。
  final String Function(String fn, List<String> args)? call;

  /// [LHost]：宿主自己的语句，返回一行行代码（不带缩进）。
  final List<String> Function(Object payload)? stmt;

  /// 宿主的名字（[LNameKind.host]）在这种语言里怎么写；不给就原样写。
  /// 后端的“这次请求”在语法树里统一叫 `req`，PHP 里要写成 `\$req`——靠它换。
  final String Function(String name)? name;

  /// 能不能直接写“返回”（[LReturn]）。后端的接口函数不行：那里要用“返回响应”。
  final bool allowReturn;
}

/// 一个函数体里共用的东西：给循环用的临时名字编号（同一个函数里不许重）。
class LangCtx {
  int _n = 0;
  int next() => ++_n;
}

/// 一段语句生成出来的结果。
class LangFragment {
  const LangFragment(this.declares, this.lines);

  /// 要在函数开头声明的名字（用户起的原名，没加前缀）：变量、常量、循环变量。宿主负责在函数开头写声明
  /// （[LangGen.declare]），已经声明过的（比如后端文档里的变量）要自己去掉。
  final List<String> declares;

  /// 代码，一行一项，不带这一层的缩进。
  final List<String> lines;
}

/// 双引号字符串字面量：`"`、`\` 和 [escape] 里的字符加反斜杠；换行 / 回车 / 制表写 `\n` `\r` `\t`；其余控制字符、DEL、U+0085、
/// U+2028、U+2029、U+FEFF 交给 [unicode]。不成对的代理项换成 U+FFFD。中文、表情原样保留。
String langQuoted(String s, {String escape = '', String Function(int codePoint)? unicode}) {
  final u = unicode ?? (int c) => '\\u${c.toRadixString(16).padLeft(4, '0')}';
  final out = StringBuffer('"');
  for (var i = 0; i < s.length; i++) {
    var r = s.codeUnitAt(i);
    if (r >= 0xD800 && r <= 0xDBFF && i + 1 < s.length && s.codeUnitAt(i + 1) >= 0xDC00 && s.codeUnitAt(i + 1) <= 0xDFFF) {
      out.write(s.substring(i, i + 2));
      i++;
      continue;
    }
    if (r >= 0xD800 && r <= 0xDFFF) r = 0xFFFD;
    final ch = String.fromCharCode(r);
    if (r == 0x22 || r == 0x5c || (escape.isNotEmpty && escape.contains(ch))) {
      out.write('\\$ch');
    } else if (r == 0x0a) {
      out.write(r'\n');
    } else if (r == 0x0d) {
      out.write(r'\r');
    } else if (r == 0x09) {
      out.write(r'\t');
    } else if (r < 0x20 || r == 0x7f || r == 0x85 || r == 0x2028 || r == 0x2029 || r == 0xfeff) {
      out.write(u(r));
    } else {
      out.write(ch);
    }
  }
  out.write('"');
  return out.toString();
}

/// 数字字面量：不是有限的数当 0；整数不带小数点（[dotZero] 时补 `.0`，给整数和小数分家的语言用）；其余用最短写法。
String langNumber(num v, {bool dotZero = false}) {
  if (!v.isFinite) return dotZero ? '0.0' : '0';
  final text = v is int || (v == v.roundToDouble() && v.abs() < 1e15) ? '${v.round()}' : '$v';
  return dotZero && !text.contains(RegExp('[.eE]')) ? '$text.0' : text;
}

/// 收拾成能放进一行注释的内容：去掉换行类 / 控制字符，拆开 `*/` 和 `</`，过长截断。
String langComment(String s, [int limit = 160]) {
  var out = s.replaceAll(RegExp('[\\x00-\\x1f\\x7f\u0085\u2028\u2029\ufeff\ud800-\udfff]+'), ' ').replaceAll('*/', '* /').replaceAll('</', '< /').trim();
  final runes = out.runes.toList();
  if (runes.length > limit) out = '${String.fromCharCodes(runes.take(limit))}…';
  return out.replaceAll('*/', '* /');
}

abstract class LangGen {
  const LangGen({this.host = const LangHost()});

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
  String scriptSource(List<List<String>> bodies);

  // —— 骨架 ——

  List<String> indented(List<String> lines) => [for (final l in lines) l.isEmpty ? l : '$indentUnit$l'];

  /// 一个代码块：`head {` … `}`，或 Python 的 `head:` + 缩进（空的补 `pass`）。
  List<String> block(String head, List<String> body) => braces ? ['$head {', ...indented(body), '}'] : ['$head:', ...suite(body)];

  /// Python 的一段缩进的代码：空的（或只有注释）补一句 `pass`。
  List<String> suite(List<String> body) => indented([...body, if (body.every((l) => l.trimLeft().startsWith('#'))) 'pass']);

  /// 完整脚本：每个模块一个函数。
  String script(List<LModule> modules) {
    final bodies = <List<String>>[];
    for (final m in modules) {
      if (m.decls.any((d) => d is! LVarDecl)) {
        final d = m.decls.firstWhere((d) => d is! LVarDecl);
        throw LangUnsupported(_declName(d), stage: _declStage(d), src: d.src);
      }
      final stmts = <LStmt>[for (final d in m.decls.whereType<LVarDecl>()) LLet(d.name, d.init, isConst: d.isConst, src: d.src), ...m.body];
      final f = fragment(stmts);
      bodies.add([for (final n in f.declares) ...declare(n), ...f.lines]);
    }
    return scriptSource(bodies);
  }

  static String _declName(LDecl d) => switch (d) {
    LFuncDecl() => '函数',
    LClassDecl() => '类',
    LInterfaceDecl() => '接口',
    LNativeDecl() => '宿主函数的声明',
    LVarDecl() => '变量',
  };

  static int _declStage(LDecl d) => switch (d) {
    LFuncDecl() => 2,
    LNativeDecl() => 3,
    _ => 5,
  };

  /// **入口**：一段语句 → 代码片段。[ctx] 同一个函数体里的几段要共用一个（循环的临时名字才不会重）。
  /// 碰到这一阶段不支持的节点抛 [LangUnsupported]。
  LangFragment fragment(List<LStmt> body, {LangCtx? ctx}) => LangFragment(lDeclaredNames(body), statements(body, ctx ?? LangCtx()));

  List<String> statements(List<LStmt> list, LangCtx ctx) {
    final out = <String>[];
    for (final s in list) {
      out.addAll(statement(s, ctx));
      // 后面的不会执行，不翻译（Java 碰到执行不到的语句编译不过）。
      if (lExits(s)) break;
    }
    return out;
  }

  List<String> statement(LStmt s, LangCtx ctx) {
    switch (s) {
      case LNote(:final text):
        return [comment(text)];
      case LLet(:final name, :final value, :final kind):
        return switch (kind) {
          LNameKind.variable => ['${variable(name)} = ${expr(value)}$end'],
          LNameKind.temp => [local(LRet.any, temp(name), expr(value))],
          LNameKind.host => throw LangUnsupported('不能新建宿主的名字 $name', src: s.src),
        };
      case LAssign(:final target, :final value):
        return switch (target) {
          LTName(:final name) => ['${variable(name)} = ${expr(value)}$end'],
          LTIndex(:final of, :final key) => [
            '${langCall('setItem', [expr(of), expr(key), expr(value)])}$end',
          ],
          LTField() => throw LangUnsupported('对象的字段', stage: 5, src: s.src),
        };
      case LExprStmt(expr: final e):
        // 只有“调用”能单独成一句（Go、Java 的规矩）；别的包一层没有副作用的 isNull。
        final isCall = e is LRt || e is LNative || e is LBinary || e is LUnary || e is LIndex || e is LListLit || e is LDictLit;
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
          ...block(countedHead(k, loopName('N', n)), ['${variable(name)} = ${stepValue(a, k, st)}$end', ...statements(body, ctx)]),
        ];
      case LForEach(:final list, :final item, :final index, :final body):
        final n = ctx.next();
        final l = loopName('L', n), k = loopName('K', n);
        return [
          local(LRet.nativeList, l, coreCall('items', [expr(list)])),
          ...block(countedHead(k, nativeLen(l)), ['${variable(item)} = ${nativeAt(l, k)}$end', if (index != null) '${variable(index)} = ${intToNumber(k)}$end', ...statements(body, ctx)]),
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
            '${variable(key)} = ${nativeAt(l, k)}$end',
            '${variable(value)} = ${langCall('dictGet', [d, variable(key)])}$end',
            ...statements(body, ctx),
          ]),
        ];
      case LBreak():
        return ['break$end'];
      case LContinue():
        return ['continue$end'];
      case LReturn(:final value):
        if (!host.allowReturn) throw LangUnsupported('这里不能直接“返回”，要用宿主自己的返回（后端接口里是“返回响应”）', src: s.src);
        return [returnLine(value == null ? null : expr(value))];
      case LHost(:final payload):
        final f = host.stmt;
        if (f == null) throw LangUnsupported('这里有一句宿主的语句，但没有接宿主', src: s.src);
        return f(payload);
      case LThrow():
        throw LangUnsupported('抛出错误', stage: 6, src: s.src);
      case LTry():
        throw LangUnsupported('试着做 / 出错了', stage: 6, src: s.src);
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
      if (lang.stage > 1) throw LangUnsupported('小库函数 $fn（要拿函数当参数）', stage: lang.stage, src: src);
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
          LNameKind.variable => variable(name),
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
      case LCall() || LLambda():
        throw LangUnsupported('函数', stage: 2, src: e.src);
      case LField() || LSend() || LSuperSend() || LNew() || LIsA() || LThis():
        throw LangUnsupported('类和对象', stage: 5, src: e.src);
      case LAwait() || LSpawn():
        throw LangUnsupported('异步', stage: 6, src: e.src);
    }
  }
}
