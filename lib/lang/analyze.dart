/// 语法树的检查：名字解析与作用域（设计稿 3.2）、类型推断（4.3 的第一步）、校验规则（8.3）。
///
/// **纯函数、不抛异常**：任何输入都返回一个结果。规则号用设计稿的编号，本阶段有：
/// - `G03` 错误：用了这里看不见的名字（没新建过、还没新建到、循环变量出了循环）。
/// - `L03` 错误：“返回”不在函数里（只在 [analyzeModule] 的“启动时”里会报）。
/// - `L04` 错误：“跳出 / 跳过”不在循环里。
/// - `L09` 错误：同一层里名字重复（同一个函数里新建两次、循环变量和外面的变量 / 外层循环变量重名、模块级变量重名）。
/// - `L11` 错误：给常量重新赋值。
/// - `L13` 警告：可能的死循环（“一直重复”/ 条件写死成“是”的循环里没有跳出、返回、抛出）。
/// - `S10` 警告：返回 / 跳出 / 跳过 / 抛出后面还有语句（死代码）。
///
/// 作用域只有三层：模块级、函数级（从“新建变量”那一块往下看得见，**没有块级**：在“如果”里新建的出了“如果”还在）、
/// 循环变量（只在那个循环里）。循环变量不许和看得见的名字重名——生成的代码里声明全提到函数开头，重名会互相盖掉。
library;

import 'package:lopicode/lang/ast.dart';
import 'package:lopicode/lang/ast_util.dart';
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
  LangAnalysis._(this.issues, this.declared, this.variableTypes, this._types);

  final List<LIssue> issues;

  /// 这一段里新建的名字（变量、常量、循环变量），按第一次出现的顺序、不重复。生成器照它在函数开头统一声明。
  final List<String> declared;

  /// 每个变量推断出来的类型：所有赋给它的值的类型“合起来”，说不清的是“任意”。
  final Map<String, LType> variableTypes;

  final Map<LExpr, LType> _types;

  /// 一个式子推断出来的类型（按节点本身查，不是按内容）。没见过的节点是“任意”。
  LType typeOf(LExpr e) => _types[e] ?? LType.any;

  bool get hasErrors => issues.any((i) => i.isError);
}

/// 检查一个函数体（比如后端一个接口下面的那一串）。
/// [outer]：外面已经有、这里看得见的变量名（模块级变量、后端文档里声明的变量）；[outerConsts] 是其中的常量。
/// [inFunction] 是 false 时“返回”算错（L03）。
LangAnalysis analyzeBody(List<LStmt> body, {Set<String> outer = const {}, Set<String> outerConsts = const {}, bool inFunction = true}) {
  try {
    // 第一遍：名字都当“任意”，收集每个变量被赋过哪些类型；第二遍用它定下每个式子的类型，问题只报第二遍的。
    final first = _Analyzer(outer, outerConsts, inFunction, const {})..block(body);
    final second = _Analyzer(outer, outerConsts, inFunction, first.varTypes)..block(body);
    return LangAnalysis._(second.issues, second.declared, second.varTypes, second.types);
  } on Object catch (e) {
    // 不该走到这里（比如语法树套得深到栈溢出）；宁可报一条问题也不让调用方崩。
    return LangAnalysis._([LIssue('G07', '这一段太复杂，没法检查（$e）')], const [], const {}, Map.identity());
  }
}

/// 检查一个模块：模块级变量 + “启动时”。函数 / 类的内部第 2 阶段再接进来。
LangAnalysis analyzeModule(LModule m) {
  final seen = <String>{};
  final consts = <String>{};
  final pre = <LIssue>[];
  final lets = <LStmt>[];
  for (final d in m.decls) {
    if (!seen.add(d.name)) pre.add(LIssue('L09', '已经有一个叫 ${d.name} 的了', src: d.src));
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
  // 初始化那几句赋值不算“给常量重新赋值”：先不把它们当常量查，再单独查“启动时”。
  final init = analyzeBody(lets, outer: names, inFunction: false);
  final body = analyzeBody(m.body, outer: names, outerConsts: consts, inFunction: false);
  return LangAnalysis._(
    [...pre, ...init.issues, ...body.issues],
    [...names, ...body.declared],
    {...init.variableTypes, ...body.variableTypes},
    Map.identity()
      ..addAll(init._types)
      ..addAll(body._types),
  );
}

class _Analyzer {
  _Analyzer(this.outer, Set<String> outerConsts, this.inFunction, this.known) : _consts = {...outerConsts};

  final Set<String> outer;
  final bool inFunction;

  /// 上一遍推出来的变量类型。
  final Map<String, LType> known;

  final List<LIssue> issues = [];
  final List<String> declared = [];
  final Map<String, LType> varTypes = {};
  final Map<LExpr, LType> types = Map.identity();

  /// 函数级已经新建、现在看得见的。
  final Set<String> _visible = {};
  final Set<String> _consts;

  /// 正在里面的各层循环的循环变量。
  final List<Set<String>> _loopVars = [];
  int _loops = 0;

  bool _sees(String name) => _visible.contains(name) || outer.contains(name) || _loopVars.any((s) => s.contains(name));

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
      if (_sees(name) || !mine.add(name)) {
        _err('L09', '循环变量 $name 和这里已经有的名字重了，换一个名字', src);
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
        if (_sees(name)) {
          _err('L09', '这里已经有一个叫 $name 的变量了，不能再新建一次', s.src);
        } else {
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
        expr(e);
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
        if (value != null) expr(value);
        if (!inFunction) _err('L03', '“返回”要放在函数里面', s.src);
      case LThrow(:final message):
        expr(message);
      case LHost():
        break;
      case LTry(:final body, :final onError, :final finallyBody):
        block(body);
        block(onError);
        block(finallyBody);
    }
  }

  /// 给变量赋值。
  void _write(String name, LType t, LSrc? src) {
    if (!_sees(name)) {
      _err('G03', '变量 $name 在这里看不见（还没有新建，或者是别的循环里的）', src);
    } else if (_consts.contains(name)) {
      _err('L11', '$name 是常量，新建以后不能再改', src);
    }
    _note(name, t);
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
        if (!_sees(name)) _err('G03', '变量 $name 在这里看不见（还没有新建，或者是别的循环里的）', e.src);
        return known[name] ?? LType.any;
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
      case LCall(:final callee, :final args):
        expr(callee);
        _all(args);
        return LType.any;
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
        return const LType(LKind.fn);
      case LThis() || LSpawn():
        return LType.any;
    }
  }
}
