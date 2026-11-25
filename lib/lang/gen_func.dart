/// 生成器里“函数”那一部分（设计稿 3.6）：有名字的函数、调用、匿名函数（带函数体的 / 短写法）、函数当值、闭包、
/// 以及带函数的整份脚本。和语言无关的做法在这里；“这种语言里怎么写”是下面那些钩子，各语言在 gen_*.dart 里答。
///
/// 做法（自定的都写进了设计稿“实施记录·阶段 2·语言核心”）：
/// - **有名字的函数直接调用**生成原生调用 `f_名字(…)`。默认值：语言自己有默认参数的（JS / Python / PHP）写在定义上；
///   没有的（Go / Java）在调用的地方补齐。“剩下的全收”：前三种用语言自己的写法，Go / Java 在调用处包成一个列表。
/// - **函数当值**（匿名函数、“这个函数本身”）统一包一层 `fn(名字, 最少几个, 最多几个, 实现)`，调用走小库的 `call`
///   （查是不是函数、参数个数）。Go / Java 的实现一律是“收一个参数表”的函数。
/// - **带函数体的匿名函数**先在用到它的那一句前面定义成一个临时名字（`lcF3`），式子里写这个名字：
///   Python 的 lambda 只能写一个式子；其余语言这样写出来的代码也才是一行一句、缩进规矩。
///   闭包按引用抓变量，所以早一点定义和就地定义没有区别。
/// - **闭包**：Python 里层改外层变量加 `nonlocal`（模块级的加 `global`）；Java 被里层用到的变量装盒子（`Object[]`）、
///   里层的名字和外层重了就改名；PHP 生成 `use (&$x)`（模块级的 `global $x`）；JS / Go 原生。
library;

import 'package:lopicode/lang/ast.dart';
import 'package:lopicode/lang/ast_util.dart';
import 'package:lopicode/lang/gen.dart';

/// 一个函数体准备好的东西。
class LangFnPlan {
  LangFnPlan(this.scope, this.names, this.declares);
  final LangScope scope;
  final LNames names;

  /// 要在函数开头声明的名字（不含参数）。
  final List<String> declares;
}

mixin LangFuncGen on LangCore {
  // —— 这种语言里怎么写 ——

  /// 有名字的函数 / 模块级变量在代码里叫什么。[prefix] 是模块的编号（后端只有一个模块，是空的）。
  String funcName(String prefix, String name) => 'f${prefix}_$name';
  String globalVar(String prefix, String name) => 'g${prefix}_$name';

  /// 在文件顶层声明一个模块级变量，初始是空。
  List<String> globalDecl(String code);

  /// 包成“函数值”。[impl] 是这种语言里的实现。
  String fnWrap(String name, int min, int max, String impl);

  /// 调一个函数值。
  String fnCall(String f, List<String> args);

  /// 带函数体的匿名函数先存进去的临时名字；Go / Java 的实现收到的参数表的名字。
  String fnTemp(int n) => 'lcF$n';
  String argsName(int n) => 'lcA$n';

  /// 语言自己有没有默认参数、“剩下的全收”（没有的在调用处补齐 / 包成列表）。
  bool get nativeDefaults => true;

  /// 函数值的实现是不是“收一个参数表”（Go / Java）。
  bool get argsByList => false;

  /// 短写法里能不能有“剩下的全收”的参数（Python 拿到的是元组、PHP 拿到的是数组，要先转成列表，只能用带函数体的写法）。
  bool get shortRest => true;

  /// 里层函数的名字和外层的重了要不要改名（Java 不许重）。
  bool get renamesShadows => false;
  String shadowName(String name, int depth) => variable(name);

  /// 读写装了盒子的变量。
  String boxed(String code) => code;

  /// 从参数表里取第 [i] 个参数（Go / Java）。
  String argAt(String args, int i, LParam p) => throw UnimplementedError();

  /// 一个有名字的函数。[body] 不带缩进。
  List<String> funcDecl(String fname, List<LParam> params, LangScope scope, List<String> body);

  /// 带函数体的匿名函数：定义并存进 [tmp]。[uses] 是它用到的外面的名字（PHP 要写进 `use`）；[args] 是参数表的名字。
  List<String> lambdaDef(String tmp, List<LParam> params, LangScope scope, List<String> body, List<String> uses, String args);

  /// 短写法的实现（还没包成函数值）。[code] 是那个式子。
  String lambdaShort(List<LParam> params, LangScope scope, String code, List<String> uses, String args);

  /// 同 [lambdaShort]，多给一份“里面用到的模块级变量”（已经是代码里的名字）。只有 PHP 用得着：别的语言函数里直接看得见模块级变量。
  String lambdaShortWithGlobals(List<LParam> params, LangScope scope, String code, List<String> uses, String args, List<String> globalsUsed) => lambdaShort(params, scope, code, uses, args);

  /// 有名字的函数当值用时的“实现”。
  String namedImpl(LFuncDecl f, String fname) => fname;

  /// 函数体最前面：把参数收拾成值的规矩里的样子（“剩下的全收”转成列表、Go / Java 从参数表里取出来、Java 装盒子）。
  /// [args] 是 null＝有名字的函数。
  List<String> paramPreamble(List<LParam> params, LangScope scope, String? args) => const [];

  /// 函数体最前面：声明要改的外层变量（Python）、用到的模块级变量（Python / PHP）。给的都是代码里的名字。
  List<String> closurePreamble(List<String> outerWritten, List<String> globalsWritten, List<String> globalsUsed) => const [];

  /// 函数体走到头没有“返回”时补的那一句（函数一律有返回值，没返回的得空）。
  List<String> get finalReturn => [returnLine(literal(null))];

  // —— 和语言无关的 ——

  /// 一个局部名字在代码里叫什么（不管盒子）。
  String localCode(LangScope scope, String name) => scope.rename[name] ?? variable(name);

  String _local(LangScope s, String name) {
    final a = s.alias[name];
    if (a != null) return a;
    final code = localCode(s, name);
    return s.boxed.contains(name) ? boxed(code) : code;
  }

  LangScope get _scope => LangCtx.current?.scope ?? LangScope.open();

  @override
  String nameExpr(String name, LSrc? src) {
    final scope = _scope;
    final r = scope.resolve(name);
    return switch (r.kind) {
      LangNameKind.local => _local(r.scope!, name),
      LangNameKind.module => globalVar(scope.module.prefix, name),
      LangNameKind.function => funcValue(r.func!, scope.module.prefix),
      LangNameKind.unknown => variable(name),
    };
  }

  @override
  String targetName(String name) {
    final scope = _scope;
    final r = scope.resolve(name);
    return switch (r.kind) {
      LangNameKind.local => _local(r.scope!, name),
      LangNameKind.module => globalVar(scope.module.prefix, name),
      _ => variable(name),
    };
  }

  /// 一个名字在现在这个位置的代码（给宿主用：旧语句里读写变量）。
  String varCode(String name) => targetName(name);

  @override
  bool get canReturn => _scope.returnsValue || host.allowReturn;

  @override
  List<String> returnStmt(LExpr? value) => [returnLine(value == null ? (_scope.returnsValue ? literal(null) : null) : expr(value))];

  /// 有名字的函数当值。
  String funcValue(LFuncDecl f, String prefix) => fnWrap(f.name, lMinArgs(f.params), lMaxArgs(f.params), namedImpl(f, funcName(prefix, f.name)));

  @override
  String callExpr(LCall e) {
    final callee = e.callee;
    if (callee is LName && callee.kind == LNameKind.variable) {
      final scope = _scope;
      final r = scope.resolve(callee.name);
      if (r.kind == LangNameKind.function) return _direct(r.func!, scope.module.prefix, e);
    }
    return fnCall(expr(callee), [for (final a in e.args) expr(a)]);
  }

  String _direct(LFuncDecl f, String prefix, LCall e) {
    final fixed = [
      for (final p in f.params)
        if (!p.rest) p,
    ];
    final hasRest = f.params.any((p) => p.rest);
    final min = lMinArgs(f.params);
    if (e.args.length < min) throw LangUnsupported('调用“${f.name}”少给了参数（至少要 $min 个，给了 ${e.args.length} 个）', src: e.src);
    if (!hasRest && e.args.length > fixed.length) throw LangUnsupported('调用“${f.name}”多给了参数（最多 ${fixed.length} 个，给了 ${e.args.length} 个）', src: e.src);
    final codes = [for (final a in e.args) expr(a)];
    if (nativeDefaults) return '${funcName(prefix, f.name)}(${codes.join(', ')})';
    final out = [
      ...codes.take(fixed.length),
      for (var i = codes.length; i < fixed.length; i++) literal(fixed[i].defaultValue?.value),
      if (hasRest) langCall('listOf', codes.skip(fixed.length).toList()),
    ];
    return '${funcName(prefix, f.name)}(${out.join(', ')})';
  }

  /// 能不能用短写法生成：是短写法、参数合适、里面没有套着要“先在前面定义”的匿名函数。
  bool _short(LLambda f) {
    final e = f.expr;
    if (e == null || (!shortRest && f.params.any((p) => p.rest))) return false;
    return lNames([LExprStmt(e)]).lambdas.every(_short);
  }

  @override
  String lambdaExpr(LLambda e) {
    final ctx = LangCtx.current;
    final min = lMinArgs(e.params), max = lMaxArgs(e.params);
    if (_short(e)) {
      final c = ctx ?? LangCtx();
      final args = argsName(c.next());
      final plan = planFunction(c.scope, c.scope.module, e.params, e.stmts, shortArgs: args);
      final code = _inScope(c, plan.scope, () => LangCtx.run(c, () => expr(e.expr!)));
      // 短写法里用到的模块级变量（PHP 要先写 `global`，不然读到的是一个没定义的局部变量）。
      final globals = <String>[
        for (final n in {...plan.names.writes, ...plan.names.reads})
          if (!plan.scope.locals.contains(n) && plan.scope.resolve(n).kind == LangNameKind.module) globalVar(plan.scope.module.prefix, n),
      ];
      return fnWrap('', min, max, lambdaShortWithGlobals(e.params, plan.scope, code, _uses(e, c.scope), args, globals));
    }
    if (ctx == null) throw LangUnsupported('带函数体的匿名函数只能放在一句话里（这里没有地方先定义它）', src: e.src);
    final n = ctx.next();
    final tmp = fnTemp(n), args = argsName(n);
    final parent = ctx.scope;
    final plan = planFunction(parent, parent.module, e.params, e.stmts);
    final body = functionBody(ctx, plan, e.params, e.stmts, args: args);
    parent.pending.addAll(lambdaDef(tmp, e.params, plan.scope, body, _uses(e, parent), args));
    return tmp;
  }

  /// 匿名函数用到的外面的名字，写成代码（PHP 的 `use` 要）。模块级变量、有名字的函数不算。
  List<String> _uses(LLambda e, LangScope parent) {
    final free = lFree(e.params, e.stmts, inspect: host.inspect);
    final out = <String>[];
    for (final n in free.names) {
      final r = parent.resolve(n);
      if (r.kind == LangNameKind.local) out.add(r.scope!.alias.containsKey(n) ? localCode(r.scope!, n) : localCode(r.scope!, n));
      if (r.kind == LangNameKind.unknown) out.add(variable(n));
    }
    return [...out, for (final t in free.temps) temp(t), for (final h in free.hostNames) host.name?.call(h) ?? h];
  }

  T _inScope<T>(LangCtx ctx, LangScope scope, T Function() body) {
    final prev = ctx.scope;
    ctx.scope = scope;
    try {
      return body();
    } finally {
      ctx.scope = prev;
    }
  }

  /// 给一个函数体准备作用域：它自己的名字、哪些要装盒子、哪些要改名。[parent] 是 null＝模块顶层的函数。
  /// [returnsValue] 是 false＝模块的“启动时”那一段（不是真的函数：不补“返回空”，也不替没建过的名字补声明）。
  LangFnPlan planFunction(LangScope? parent, LangModuleInfo module, List<LParam> params, List<LStmt> body, {String? shortArgs, bool returnsValue = true}) {
    final names = lNames(body, inspect: host.inspect);
    final paramNames = {for (final p in params) p.name};
    final declares = [
      for (final n in names.declared)
        if (!paramNames.contains(n)) n,
    ];
    final locals = {...paramNames, ...declares};
    if (returnsValue) {
      // 给一个哪里都没建过的名字赋值：当成这个函数自己的变量（校验会报 G03；这里只求生成的代码能编译）。
      final outside = parent ?? LangScope.function(null, module: module, locals: {});
      for (final w in names.writes) {
        if (!locals.contains(w) && outside.resolve(w).kind == LangNameKind.unknown) {
          locals.add(w);
          declares.add(w);
        }
      }
    }
    final captured = boxesCaptured && shortArgs == null ? <String>{for (final f in names.lambdas) ...lFree(f.params, f.stmts, inspect: host.inspect).names} : const <String>{};
    final depth = parent == null ? 0 : parent.depth + 1;
    return LangFnPlan(
      LangScope.function(
        parent,
        module: module,
        locals: locals,
        returnsValue: returnsValue,
        boxed: locals.intersection(captured),
        alias: shortArgs != null && argsByList ? {for (var i = 0; i < params.length; i++) params[i].name: argAt(shortArgs, i, params[i])} : const {},
        rename: renamesShadows && parent != null
            ? {
                for (final n in locals)
                  if (parent.locals.contains(n) || parent.outerHas(n)) n: shadowName(n, depth),
              }
            : const {},
      ),
      names,
      declares,
    );
  }

  /// 一个函数体的代码（不带缩进）：闭包的声明、参数的收拾、变量声明、语句、末尾补的“返回空”。
  List<String> functionBody(LangCtx ctx, LangFnPlan plan, List<LParam> params, List<LStmt> body, {String? args}) {
    final scope = plan.scope;
    final lines = _inScope(ctx, scope, () => statements(body, ctx));
    final outerWritten = <String>[], globalsWritten = <String>[], globalsUsed = <String>[];
    for (final n in {...plan.names.writes, ...plan.names.reads}) {
      if (scope.locals.contains(n)) continue;
      final r = scope.resolve(n);
      final written = plan.names.writes.contains(n);
      if (r.kind == LangNameKind.local && written) outerWritten.add(localCode(r.scope!, n));
      if (r.kind == LangNameKind.module) {
        globalsUsed.add(globalVar(scope.module.prefix, n));
        if (written) globalsWritten.add(globalVar(scope.module.prefix, n));
      }
    }
    return [
      ...closurePreamble(outerWritten, globalsWritten, globalsUsed),
      ...paramPreamble(params, scope, args),
      for (final d in plan.declares) ...declareIn(scope, d),
      ...lines,
      if (scope.returnsValue && !lAlwaysReturns(body)) ...finalReturn,
    ];
  }

  /// 一个模块顶层的函数（不带缩进）。
  List<String> functionLines(LFuncDecl f, LangModuleInfo module, {LangCtx? ctx}) {
    final c = ctx ?? LangCtx();
    final plan = planFunction(null, module, f.params, f.body);
    return funcDecl(funcName(module.prefix, f.name), f.params, plan.scope, functionBody(c, plan, f.params, f.body));
  }

  /// **给宿主的入口**：一个文档里所有有名字的函数 → 顶层代码（函数之间空一行，不带缩进）。
  /// 函数之间可以互相调用、可以调用排在后面的。碰到不支持的节点抛 [LangUnsupported]。
  List<String> moduleFunctions(Iterable<LFuncDecl> functions, {String prefix = ''}) {
    final module = LangModuleInfo.of(functions, prefix: prefix);
    final out = <String>[];
    for (final f in module.funcs.values) {
      if (out.isNotEmpty) out.add('');
      out.addAll(functionLines(f, module));
    }
    return out;
  }

  /// 完整脚本：每个模块的“启动时”是一个函数，按顺序各跑一遍。
  ///
  /// 没有函数的模块和第 1 阶段一样：模块级变量就是那个函数里的局部变量。有函数的模块：函数生成成文件顶层的函数
  /// （名字带模块编号），模块级变量生成成文件顶层的变量，函数和“启动时”都能读能改。
  String script(List<LModule> modules) {
    final bodies = <List<String>>[];
    final top = <String>[];
    for (var i = 0; i < modules.length; i++) {
      final m = modules[i];
      for (final d in m.decls) {
        if (d is! LVarDecl && d is! LFuncDecl) throw LangUnsupported(_declName(d), stage: d is LNativeDecl ? 3 : 5, src: d.src);
      }
      final vars = m.decls.whereType<LVarDecl>().toList();
      final funcs = m.decls.whereType<LFuncDecl>().toList();
      final ctx = LangCtx();
      if (funcs.isEmpty) {
        final stmts = <LStmt>[for (final d in vars) LLet(d.name, d.init, isConst: d.isConst, src: d.src), ...m.body];
        final plan = planFunction(null, const LangModuleInfo(), const [], stmts, returnsValue: false);
        bodies.add(functionBody(ctx, plan, const [], stmts));
        continue;
      }
      final module = LangModuleInfo.of(funcs, vars: {for (final d in vars) d.name}, prefix: '${i + 1}');
      for (final d in vars) {
        if (top.isNotEmpty && d == vars.first) top.add('');
        top.addAll(globalDecl(globalVar(module.prefix, d.name)));
      }
      for (final f in funcs) {
        if (top.isNotEmpty) top.add('');
        top.addAll(functionLines(f, module));
      }
      final stmts = <LStmt>[for (final d in vars) LAssign(LTName(d.name, src: d.src), d.init, src: d.src), ...m.body];
      final plan = planFunction(null, module, const [], stmts, returnsValue: false);
      bodies.add(functionBody(ctx, plan, const [], stmts));
    }
    return scriptSource(bodies, top: top);
  }

  static String _declName(LDecl d) => switch (d) {
    LClassDecl() => '类',
    LInterfaceDecl() => '接口',
    LNativeDecl() => '宿主函数的声明',
    LFuncDecl() => '函数',
    LVarDecl() => '变量',
  };
}
