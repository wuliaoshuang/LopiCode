/// 语法树的检查：名字解析与作用域（设计稿 3.2）、类型推断（4.3 的第一步）、校验规则（8.3）。
///
/// **纯函数、不抛异常**：任何输入都返回一个结果。规则号用设计稿的编号，本阶段有：
/// - `G03` 错误：用了这里看不见的名字（没新建过、还没新建到、循环变量出了循环）。
/// - `L01` 错误：调用的函数不存在；调的东西明摆着不是函数。
/// - `L02` 错误：参数个数对不上；参数表本身不对（“剩下的全收”不在最后、有默认值的后面跟着没有默认值的）。
/// - `L03` 错误：“返回”不在函数里（模块的“启动时”里会报）；警告：把没有返回值的函数当值用。
/// - `L04` 错误：“跳出 / 跳过”不在循环里。
/// - `L09` 错误：同一层里名字重复（同一个函数里新建两次、循环变量和外面的变量 / 外层循环变量重名、模块级变量重名、
///   函数重名、参数重名、先当外面的变量用了又新建同名的）。
/// - `L11` 错误：给常量重新赋值。
/// - `L13` 警告：可能的死循环（“一直重复”/ 条件写死成“是”的循环里没有跳出、返回、抛出）。
/// - `L14` 警告：定义了没人用的函数 / 参数。
/// - `S10` 警告：返回 / 跳出 / 跳过 / 抛出后面还有语句（死代码）。
/// - `S11` 警告：有返回值的函数有的走法没有返回值（那条走法得到空）。
///
/// 函数（第 2 阶段）：整份文档的函数用 analyze_module.dart 的 `analyzeFunctions` 查；这里的 [analyzeBody] 传进
/// `functions`／`signatures` 以后，体里调用它们也会查（L01、L02、L03）。匿名函数的体在碰到它的地方就地查。
///
/// 作用域：模块级、函数级（从“新建变量”那一块往下看得见，**没有块级**：在“如果”里新建的出了“如果”还在）、
/// 循环变量（只在那个循环里）。循环变量不许和这一层看得见的名字重名——生成的代码里声明全提到函数开头，重名会互相盖掉。
/// 函数套函数时里层看得见外层的（闭包）；里层的参数、新建的变量可以和外层的同名（盖住外层的），
/// 但不能先当外层的用了、后面又新建一个同名的。
library;

import 'package:lopicode/lang/ast.dart';
import 'package:lopicode/lang/ast_util.dart';
import 'package:lopicode/lang/names.dart';
import 'package:lopicode/lang/rt.dart';
import 'package:lopicode/lang/types.dart';

class LIssue {
  const LIssue(this.code, this.message, {this.isError = true, this.src});
  final String code;
  final String message;

  /// 错误拦“生成 / 导出 / 运行”，警告不拦。
  final bool isError;
  final LSrc? src;

  @override
  String toString() => '$code ${isError ? '错误' : '警告'}：$message${src == null ? '' : '（$src）'}';
}

/// 一段语句（一个函数体 / 一个模块）检查完的结果。
class LangAnalysis {
  LangAnalysis.raw(this.issues, this.declared, this.variableTypes, this._types, {this.usedFunctions = const {}, this.returnsValue = false, this.returnType = LType.nul, this.unusedParams = const []});

  final List<LIssue> issues;

  /// 这一段里新建的名字（变量、常量、循环变量），按第一次出现的顺序、不重复。生成器照它在函数开头统一声明。
  final List<String> declared;

  /// 每个变量推断出来的类型：所有赋给它的值的类型“合起来”，说不清的是“任意”。
  final Map<String, LType> variableTypes;

  final Map<LExpr, LType> _types;

  /// 一个式子推断出来的类型（按节点本身查，不是按内容）。没见过的节点是“任意”。
  LType typeOf(LExpr e) => _types[e] ?? LType.any;

  /// 这一段里用到的有名字的函数（调用、当值）。
  final Set<String> usedFunctions;

  /// 这一段当函数体看：有没有“返回 (值)”；返回的类型（各处返回的值“合起来”；没有带值的返回＝空）。
  final bool returnsValue;
  final LType returnType;

  /// 没用到的参数（当函数体查的时候才有）。
  final List<String> unusedParams;

  /// 给宿主用：把自己一个式子的类型记进来（比如旧式子里夹着的新节点）。
  Map<LExpr, LType> get exprTypes => _types;

  bool get hasErrors => issues.any((i) => i.isError);
}

/// 一个有名字的函数对外的样子（给调用的地方查参数个数、决定调用积木是语句型 / 值型 / 是否型）。
class LFuncSig {
  const LFuncSig(this.name, this.params, {this.returnsValue = false, this.returnType = LType.any});
  final String name;
  final List<LParam> params;

  /// 函数里有没有“返回 (值)”。没有＝调用它的积木是语句型。
  final bool returnsValue;

  /// 推断出来的返回类型（说不清的是“任意”）。
  final LType returnType;

  int get minArgs => lMinArgs(params);
  int get maxArgs => lMaxArgs(params);

  /// 返回的一定是“是 / 否”＝调用它的积木可以是“是否型”。
  bool get returnsBool => returnsValue && returnType == LType.boolean;
}

/// 查的时候大家共用的东西。
class LangEnv {
  LangEnv({this.functions = const {}, this.signatures = const {}, this.globals = const {}, this.globalConsts = const {}, this.self, this.inspect});

  /// 看得见的有名字的函数、它们对外的样子（上一遍推出来的）。
  final Map<String, LFuncDecl> functions;
  final Map<String, LFuncSig> signatures;

  /// 函数外面的模块级变量（函数里看得见、可以被同名的盖住）。
  final Set<String> globals;
  final Set<String> globalConsts;

  /// 正在查的是哪个函数（自己调自己不算“有人用”）。
  final String? self;
  final LHostInspect? inspect;

  /// 提到过的函数（含自己）。
  final Set<String> refs = {};
}

/// 检查一个函数体（比如后端一个接口下面的那一串）。
/// [outer]：外面已经有、这里看得见的变量名（模块级变量、后端文档里声明的变量）；[outerConsts] 是其中的常量。
/// [inFunction] 是 false 时“返回”算错（L03）。
/// [functions]／[signatures]：这里能调的有名字的函数（第 2 阶段；[signatures] 用 `analyzeFunctions` 给的，没给就只查个数）。
LangAnalysis analyzeBody(
  List<LStmt> body, {
  Set<String> outer = const {},
  Set<String> outerConsts = const {},
  bool inFunction = true,
  Iterable<LFuncDecl> functions = const [],
  Map<String, LFuncSig> signatures = const {},
  LHostInspect? inspect,
}) {
  LangEnv env() => LangEnv(functions: {for (final f in functions) f.name: f}, signatures: signatures, inspect: inspect);
  return analyzeFunctionBody(const [], body, env, outer: outer, outerConsts: outerConsts, inFunction: inFunction, isFunction: false);
}

/// 查一个函数体（[analyzeBody]、`analyzeFunctions` 都走这里）。[env] 每一遍要一份新的。
/// [isFunction]＝这是一个真的函数（查参数表、S11、没用到的参数）；[where] 是报问题时指的地方。
LangAnalysis analyzeFunctionBody(
  List<LParam> params,
  List<LStmt> body,
  LangEnv Function() env, {
  Set<String> outer = const {},
  Set<String> outerConsts = const {},
  bool inFunction = true,
  bool isFunction = true,
  LSrc? where,
}) {
  try {
    // 第一遍：名字都当“任意”，收集每个变量被赋过哪些类型；第二遍用它定下每个式子的类型，问题只报第二遍的。
    _Analyzer pass(Map<String, LType> known) {
      final a = _Analyzer(outer, outerConsts, inFunction, known, env: env());
      if (isFunction) a.params(params, where);
      a.block(body);
      if (isFunction) a.finish(params, body, where);
      return a;
    }

    final second = pass(pass(const {}).varTypes);
    return LangAnalysis.raw(
      second.issues,
      second.declared,
      second.varTypes,
      second.types,
      usedFunctions: second.env.refs,
      returnsValue: second.valueReturn,
      returnType: second.retType ?? LType.nul,
      unusedParams: second.unusedParams,
    );
  } on Object catch (e) {
    // 不该走到这里（比如语法树套得深到栈溢出）；宁可报一条问题也不让调用方崩。
    return LangAnalysis.raw([LIssue('G07', '这一段太复杂，没法检查（$e）')], const [], const {}, Map.identity());
  }
}

class _Analyzer {
  _Analyzer(this.outer, Set<String> outerConsts, this.inFunction, this.known, {required this.env, this.parent})
    : _consts = {...outerConsts},
      issues = parent?.issues ?? [],
      types = parent?.types ?? Map.identity();

  final Set<String> outer;
  final bool inFunction;
  final LangEnv env;

  /// 套在哪个函数里（匿名函数才有）。
  final _Analyzer? parent;

  /// 上一遍推出来的变量类型。
  final Map<String, LType> known;

  final List<LIssue> issues;
  final List<String> declared = [];
  final Map<String, LType> varTypes = {};
  final Map<LExpr, LType> types;

  /// 参数；这一层用到过的自己的名字；当外层的变量用过的名字。
  final Set<String> _params = {};
  final Set<String> _touched = {};
  final Set<String> _usedOuter = {};

  /// 有没有“返回 (值)”、不带值的“返回”；各处返回的值的类型合起来。
  bool valueReturn = false;
  bool bareReturn = false;
  LType? retType;
  List<String> unusedParams = const [];

  /// 函数级已经新建、现在看得见的。
  final Set<String> _visible = {};
  final Set<String> _consts;

  /// 正在里面的各层循环的循环变量。
  final List<Set<String>> _loopVars = [];
  int _loops = 0;

  /// 这一层自己看得见的；外面那些层看得见的（外层函数的、模块级的）。
  bool _seesOwn(String name) => _visible.contains(name) || outer.contains(name) || _params.contains(name) || _loopVars.any((s) => s.contains(name));
  bool _enclosing(String name) => parent != null ? parent!._sees(name) : env.globals.contains(name);
  bool _sees(String name) => _seesOwn(name) || _enclosing(name);
  bool _isConst(String name) => _seesOwn(name) ? _consts.contains(name) : (parent != null ? parent!._isConst(name) : env.globalConsts.contains(name));

  /// 用到了一个看得见的名字：记在它所在的那一层上。
  void _touch(String name) {
    if (_seesOwn(name)) {
      _touched.add(name);
    } else {
      _usedOuter.add(name);
      parent?._touch(name);
    }
  }

  void _noteOwner(String name, LType t) => _seesOwn(name) || parent == null ? _note(name, t) : parent!._noteOwner(name, t);

  /// 能不能在这一层新建 [name]；不能就报 L09。
  bool _fresh(String name, String what, LSrc? src) {
    if (_seesOwn(name)) {
      _err('L09', what, src);
      return false;
    }
    if (_usedOuter.contains(name)) {
      _err('L09', '前面已经把 $name 当外面的变量用过了，这里不能再新建一个同名的，换一个名字', src);
      return false;
    }
    return true;
  }

  /// 参数表：重名（L09）、“剩下的全收”不在最后、有默认值的后面跟着没有默认值的（L02）。
  void params(List<LParam> list, LSrc? src) {
    var seenDefault = false;
    for (var i = 0; i < list.length; i++) {
      final p = list[i];
      if (!_params.add(p.name)) _err('L09', '有两个参数都叫 ${p.name}，换一个名字', src);
      if (p.rest && i != list.length - 1) _err('L02', '“剩下的全收”的参数 ${p.name} 只能放在最后一个', src);
      if (p.rest && p.defaultValue != null) _err('L02', '“剩下的全收”的参数 ${p.name} 不能有默认值', src);
      if (!p.rest && p.defaultValue == null && seenDefault) _err('L02', '参数 ${p.name} 没有默认值，要排在有默认值的参数前面', src);
      if (p.defaultValue != null) seenDefault = true;
      _declare(p.name);
      _note(p.name, p.type ?? LType.any);
    }
  }

  /// 函数体查完以后：S11、没用到的参数（L14）。
  void finish(List<LParam> list, List<LStmt> body, LSrc? src) {
    if (valueReturn && (bareReturn || !lAlwaysReturns(body))) {
      _warn('S11', '这个函数有的走法返回了值，有的走法没有（没有的那条走法得到空）', src);
    }
    unusedParams = [
      for (final p in list)
        if (!_touched.contains(p.name)) p.name,
    ];
    for (final name in unusedParams) {
      _warn('L14', '参数 $name 没有用到', src);
    }
  }

  void _err(String code, String message, LSrc? src) => issues.add(LIssue(code, message, src: src));
  void _warn(String code, String message, LSrc? src) => issues.add(LIssue(code, message, isError: false, src: src));

  void _note(String name, LType t) => varTypes[name] = varTypes.containsKey(name) ? varTypes[name]!.join(t) : t;

  void _declare(String name) {
    if (!declared.contains(name) && !outer.contains(name)) declared.add(name);
  }

  void block(List<LStmt> list) {
    var dead = false;
    for (final s in list) {
      if (dead && s is! LNote) {
        _warn('S10', '前面已经返回 / 跳出了，从这里往后的不会执行', s.src);
        dead = false; // 一串只报一次
      }
      stmt(s);
      if (lExits(s)) dead = true;
    }
  }

  /// 一个循环：[vars] 是它自己的循环变量（名字, 类型）。用列表不用字典：两个变量起了同一个名字要查得出来。
  void _loop(List<(String, LType)> vars, List<LStmt> body, LSrc? src) {
    final mine = <String>{};
    for (final (name, type) in vars) {
      if (!mine.add(name)) {
        _err('L09', '循环变量 $name 和这里已经有的名字重了，换一个名字', src);
      } else {
        _fresh(name, '循环变量 $name 和这里已经有的名字重了，换一个名字', src);
      }
      _declare(name);
      _note(name, type);
    }
    _loopVars.add(mine);
    _loops++;
    block(body);
    _loops--;
    _loopVars.removeLast();
  }

  void stmt(LStmt s) {
    switch (s) {
      case LNote() || LBreak() || LContinue():
        if (s is! LNote && _loops == 0) _err('L04', s is LBreak ? '“跳出循环”要放在循环里面' : '“跳过这一轮”要放在循环里面', s.src);
      case LLet(:final name, :final value, :final kind):
        final t = expr(value);
        if (kind != LNameKind.variable) return;
        if (_fresh(name, '这里已经有一个叫 $name 的变量了，不能再新建一次', s.src)) {
          _visible.add(name);
          if (s.isConst) _consts.add(name);
        }
        _declare(name);
        _note(name, s.type ?? t);
      case LAssign(:final target, :final value):
        final t = expr(value);
        switch (target) {
          case LTName(:final name):
            _write(name, t, target.src ?? s.src);
          case LTIndex(:final of, :final key):
            expr(of);
            expr(key);
          case LTField(:final of):
            expr(of);
        }
      case LExprStmt(expr: final e):
        // 单独成一句的调用：不拿它的结果，没有返回值也行。
        e is LCall ? types[e] = e.type ?? _call(e, asValue: false) : expr(e);
      case LIf(:final arms, :final orElse):
        for (final a in arms) {
          expr(a.cond);
          block(a.body);
        }
        block(orElse);
      case LWhile(:final cond, :final body):
        if (cond != null) expr(cond);
        if ((cond == null || _alwaysTrue(cond)) && !_canLeave(body, 0)) {
          _warn('L13', cond == null ? '“一直重复”里没有“跳出循环”或“返回”，会停不下来' : '条件写死成“是”了，里面又没有“跳出循环”或“返回”，会停不下来', s.src);
        }
        _loop(const [], body, s.src);
      case LRepeat(:final times, :final body):
        expr(times);
        _loop(const [], body, s.src);
      case LForCount(:final name, :final from, :final to, :final step, :final body):
        expr(from);
        expr(to);
        expr(step);
        _loop([(name, LType.number)], body, s.src);
      case LForEach(:final list, :final item, :final index, :final reuse, :final body):
        final t = expr(list);
        final each = t.kind == LKind.list ? (t.of ?? LType.any) : LType.any;
        if (reuse) {
          _write(item, each, s.src);
          _loop([if (index != null) (index, LType.number)], body, s.src);
        } else {
          _loop([(item, each), if (index != null) (index, LType.number)], body, s.src);
        }
      case LForPairs(:final dict, :final key, :final value, :final body):
        final t = expr(dict);
        _loop([(key, LType.text), (value, t.kind == LKind.dict ? (t.of ?? LType.any) : LType.any)], body, s.src);
      case LReturn(:final value):
        if (value != null) {
          final t = expr(value);
          valueReturn = true;
          retType = retType == null ? t : retType!.join(t);
        } else {
          bareReturn = true;
        }
        if (!inFunction) _err('L03', '“返回”要放在函数里面', s.src);
      case LThrow(:final message):
        expr(message);
      case LHost(:final payload):
        // 宿主的语句语言核心看不懂；宿主说了它用到哪些名字的话，记一下（不然参数会被当成没用到）。
        final use = env.inspect?.call(payload);
        if (use == null) break;
        for (final name in {...use.reads, ...use.writes}) {
          if (_sees(name)) {
            _touch(name);
          } else if (env.self != null && !use.declares.contains(name)) {
            // 有名字的函数里看不见接口的变量。（接口体里的旧语句由宿主自己的校验管，这里不重复报。）
            _err('G03', '变量 $name 在函数 ${env.self} 里看不见（接口的变量要当参数传进来）', s.src);
          }
        }
        for (final name in use.declares) {
          _visible.add(name);
          _declare(name);
        }
        use.lambdas.forEach(expr);
      case LTry(:final body, :final onError, :final finallyBody):
        block(body);
        block(onError);
        block(finallyBody);
      case LStmtV5(:final childExprs, :final binds, :final childBlocks):
        // 第 5 版的语句（“看是哪种情况”）：这里只管名字；类型的事归 typecheck.dart。它接出来的名字和别的变量一样算函数级的。
        childExprs.forEach(expr);
        for (final name in binds) {
          _visible.add(name);
          _declare(name);
          _note(name, LType.any);
        }
        childBlocks.forEach(block);
    }
  }

  /// 给变量赋值。
  void _write(String name, LType t, LSrc? src) {
    if (!_sees(name)) {
      _err('G03', '变量 $name 在这里看不见（还没有新建，或者是别的循环里的）', src);
    } else {
      if (_isConst(name)) _err('L11', '$name 是常量，新建以后不能再改', src);
      _touch(name);
    }
    _noteOwner(name, t);
  }

  void _argCount(List<LParam> list, int given, String what, LSrc? src) {
    final min = lMinArgs(list), max = lMaxArgs(list);
    if (given >= min && (max < 0 || given <= max)) return;
    final want = max < 0 ? '至少 $min 个' : (min == max ? '$min 个' : '$min 到 $max 个');
    _err('L02', '$what要 $want参数，这里给了 $given 个', src);
  }

  /// 一次调用。[asValue]＝拿它的结果当值用。
  LType _call(LCall e, {required bool asValue}) {
    final callee = e.callee;
    _all(e.args);
    if (callee is LName && callee.kind == LNameKind.variable && !_sees(callee.name)) {
      final name = callee.name;
      final f = env.functions[name];
      if (f == null) {
        _err('L01', '没有叫 $name 的函数（被删了，或者名字不对）', e.src ?? callee.src);
        return LType.any;
      }
      env.refs.add(name);
      types[callee] = const LType(LKind.fn);
      _argCount(f.params, e.args.length, '函数 $name ', e.src ?? callee.src);
      final sig = env.signatures[name];
      if (sig == null) return LType.any;
      if (!sig.returnsValue) {
        if (asValue) _warn('L03', '函数 $name 没有返回值，拿它当值用会得到空', e.src ?? callee.src);
        return LType.nul;
      }
      return sig.returnType;
    }
    expr(callee);
    if (callee is LLambda) {
      _argCount(callee.params, e.args.length, '这个匿名函数', e.src);
    } else if (callee is LLit || callee is LListLit || callee is LDictLit) {
      _err('L01', '这不是函数，不能调用', e.src ?? callee.src);
    }
    return LType.any;
  }

  /// 匿名函数：它的体是另一层，就地查。
  LType _lambda(LLambda e) {
    final body = e.stmts;
    final child = _Analyzer(const {}, const {}, true, const {}, env: env, parent: this)
      ..params(e.params, e.src)
      ..block(body);
    child.finish(e.params, body, e.src);
    return const LType(LKind.fn);
  }

  static bool _alwaysTrue(LExpr e) => e is LLit && (e.value == true || (e.value is num && e.value != 0) || (e.value is String && e.value != ''));

  /// 这个循环体里有没有能出去的路：本层的“跳出”，或任何一层的“返回 / 抛出”。
  static bool _canLeave(List<LStmt> body, int depth) {
    for (final s in body) {
      final found = switch (s) {
        LBreak() => depth == 0,
        LReturn() || LThrow() => true,
        LHost(:final returns) => returns,
        LIf(:final arms, :final orElse) => arms.any((a) => _canLeave(a.body, depth)) || _canLeave(orElse, depth),
        LWhile(:final body) || LRepeat(:final body) || LForCount(:final body) || LForEach(:final body) || LForPairs(:final body) => _canLeave(body, depth + 1),
        LTry(:final body, :final onError, :final finallyBody) => _canLeave(body, depth) || _canLeave(onError, depth) || _canLeave(finallyBody, depth),
        _ => false,
      };
      if (found) return true;
    }
    return false;
  }

  LType expr(LExpr e) {
    final t = e.type ?? _infer(e);
    types[e] = t;
    return t;
  }

  LType _all(List<LExpr> list) {
    LType? t;
    for (final x in list) {
      final each = expr(x);
      t = t == null ? each : t.join(each);
    }
    return t ?? LType.any;
  }

  LType _infer(LExpr e) {
    switch (e) {
      case LLit(:final value):
        return switch (value) {
          null => LType.nul,
          bool() => LType.boolean,
          num() => LType.number,
          String() => LType.text,
          _ => LType.any,
        };
      case LListLit(:final items):
        return LType(LKind.list, of: items.isEmpty ? null : _all(items));
      case LDictLit(:final entries):
        for (final p in entries) {
          expr(p.key);
        }
        return LType(LKind.dict, of: entries.isEmpty ? null : _all([for (final p in entries) p.value]));
      case LName(:final name, :final kind):
        if (kind != LNameKind.variable) return LType.any;
        if (_sees(name)) {
          _touch(name);
          return _seesOwn(name) ? (known[name] ?? LType.any) : LType.any;
        }
        if (env.functions.containsKey(name)) {
          // 函数本身当值
          env.refs.add(name);
          return const LType(LKind.fn);
        }
        _err('G03', '变量 $name 在这里看不见（还没有新建，或者是别的循环里的）', e.src);
        return LType.any;
      case LIndex(:final of, :final key):
        final t = expr(of);
        expr(key);
        return t.kind == LKind.list || t.kind == LKind.dict ? (t.of ?? LType.any) : LType.any;
      case LUnary(:final op, :final x):
        expr(x);
        return op == 'not' ? LType.boolean : LType.number;
      case LBinary(:final op, :final l, :final r):
        expr(l);
        expr(r);
        return kLangRtFns[kLangBinaryFns[op]]?.type ?? kLangCoreFns[kLangBinaryFns[op]]?.type ?? LType.any;
      case LLogic(:final l, :final r):
        expr(l);
        expr(r);
        return LType.boolean;
      case LCond(:final cond, :final then, :final orElse):
        expr(cond);
        return expr(then).join(expr(orElse));
      case LRt(:final fn, :final args):
        _all(args);
        return kLangRtFns[fn]?.type ?? kLangCoreFns[fn]?.type ?? LType.any;
      case LNative(:final args) || LSuperSend(:final args) || LNew(:final args):
        _all(args);
        return LType.any;
      case LCall():
        return _call(e, asValue: true);
      case LSend(:final obj, :final args):
        expr(obj);
        _all(args);
        return LType.any;
      case LField(:final of) || LAwait(x: final of):
        expr(of);
        return LType.any;
      case LIsA(:final x):
        expr(x);
        return LType.boolean;
      case LLambda():
        return _lambda(e);
      case LThis() || LSpawn():
        return LType.any;
      case LExprV5(:final childExprs):
        // 第 5 版的式子（记录、枚举、变体、当成〈类型〉）：这里只管名字，类型归 typecheck.dart。
        _all(childExprs);
        return LType.any;
    }
  }
}
