/// 库积木“用一次”：把一块库积木连同槽里的东西变成语法树（积木第 5 版·库 1）。
///
/// 四种定义办法（[LibHow]）在这里各有一条路：调函数、调对象的方法、调类自己的方法都是拼一次调用；
/// 模板展开是把模板（语法树的文字写法）读一遍，读到 `(槽 名)` `(隐含 名)` `(设置 编号)` `(口 名)` `(放进 槽名 式子)` 就换成真东西。
/// 口里的积木是**原样放进去**的（不包成函数），所以口里的“返回”“跳出”作用在外面——这就是“原地展开”。
///
/// 任何输入都不抛异常：做不成返回一句原因（[LibApplied.problem]）。
library;

import 'package:lopicode/lang/ast.dart';
import 'package:lopicode/lang/ast_util.dart';
import 'package:lopicode/lang/custom_block.dart';
import 'package:lopicode/lang/lc_text.dart';
import 'package:lopicode/lang/lib_model.dart';
import 'package:lopicode/lang/link.dart';
import 'package:lopicode/lang/rename.dart';

/// 一次使用里，各个槽放了什么。
class LibUse {
  const LibUse({this.values = const {}, this.mouths = const {}, this.targets = const {}, this.provided = const {}});

  /// 值槽 / 只许直接填的槽：槽名 → 式子。没给的当“空”。
  final Map<String, LExpr> values;

  /// 口：槽名 → 已经翻好的语句。
  final Map<String, List<LStmt>> mouths;

  /// “放进变量”槽：槽名 → 变量名。没给＝没选变量。
  final Map<String, String> targets;

  /// 这块积木给口里递的“隐含的东西”实际叫什么：隐含名 → 变量名（口里的积木已经照这个名字翻好了）。
  /// 没给的照模板里写的名字。用 [libProvided] 先起好名字，再翻口里的积木，再来用这块积木。
  final Map<String, String> provided;
}

/// 给一块积木要递的“隐含的东西”各起一个不会撞的名字。
Map<String, String> libProvided(LibBlock b, String Function(String name) fresh) => {for (final e in b.provides.entries) e.key: fresh(e.value)};

/// 用的地方的周围：隐含的东西各叫什么、这份文档里设置项的值、起不会撞的新名字。
class LibCx {
  const LibCx({this.context = const {}, this.settings = const {}, required this.fresh});
  final Map<String, String> context;
  final Map<String, Object?> settings;

  /// 给模板里新建的名字起一个不会和用户的名字撞的新名字。
  final String Function(String name) fresh;
}

/// 用一次的结果：值型积木是一个式子（[value]），别的是几句语句（[stmts]）。
class LibApplied {
  const LibApplied({this.stmts = const [], this.value, this.problem});
  final List<LStmt> stmts;
  final LExpr? value;
  final String? problem;
}

LExpr _literal(Object? v) => v is List ? LListLit([for (final x in v) _literal(x)]) : LLit(v);

/// 设置项现在的值 → 式子（标上设置项的类型，空列表才知道是什么的列表）。
LExpr libSettingExpr(LibSetting s, Map<String, Object?> values) => LAscribe(_literal(values.containsKey(s.id) ? values[s.id] : s.defaultValue), s.type);

class _Problem implements Exception {
  const _Problem(this.what);
  final String what;
}

/// 读模板用的读入器：把五种“洞”接上。
LcReader _reader(LibLibrary lib, String where, LibUse use, LibCx cx, [Set<Object>? keep]) {
  T kept<T extends Object>(T node) {
    keep?.add(node);
    return node;
  }

  final r = LcReader(const [])..freshName = cx.fresh;
  String name(List<Object> a) => a.isNotEmpty && a[0] is String ? a[0] as String : throw _Problem('$where的模板里有一个洞没写名字');
  r.exprHole = (head, a) {
    switch (head) {
      case '槽':
        return kept(use.values[name(a)] ?? const LLit(null));
      case '隐含':
        final v = cx.context[name(a)];
        if (v == null) throw _Problem('$where要用“${name(a)}”，可是它不在给“${name(a)}”的积木下面');
        return kept(LName(v));
      case '设置':
        final s = lib.setting(name(a));
        if (s == null) throw _Problem('$where的模板里用了库里没有的设置项「${name(a)}」');
        return libSettingExpr(s, cx.settings);
    }
    return null;
  };
  r.stmtHole = (head, a) {
    switch (head) {
      case '口':
        final body = use.mouths[name(a)] ?? const <LStmt>[];
        body.forEach(kept);
        // (口 名 (收尾 语句…))：口里的积木走到头还没返回，就接着做“收尾”里的；一定会返回的就不接（免得出现执行不到的代码）。
        final tail = a.length > 1 && a[1] is List && (a[1] as List).isNotEmpty && (a[1] as List)[0] == '收尾' ? (a[1] as List).skip(1).cast<Object>() : null;
        return [...body, if (tail != null && !lAlwaysReturns(body)) ...r.stmts(tail)];
      case '放进':
        if (a.length != 2) throw _Problem('$where的模板里“放进”要写成 (放进 槽名 式子)');
        final value = r.expr(a[1]);
        final target = use.targets[name(a)];
        return [target == null ? LExprStmt(value) : LAssign(kept(LTName(target)), value)];
    }
    return null;
  };
  return r;
}

LExpr _argExpr(LibLibrary lib, LibBlock b, LibArg a, LibUse use, LibCx cx) {
  switch (a) {
    case LibArgSlot(:final slot):
      return use.values[slot] ?? const LLit(null);
    case LibArgContext(:final name):
      final v = cx.context[name];
      if (v == null) throw _Problem('积木「${b.look.name}」要用“$name”，可是它不在给“$name”的积木下面');
      return LName(v);
    case LibArgSetting(:final id):
      final s = lib.setting(id);
      if (s == null) throw _Problem('积木「${b.look.name}」用了库里没有的设置项「$id」');
      return libSettingExpr(s, cx.settings);
    case LibArgPreset(:final value):
      return LLit(value);
  }
}

/// 库里的一个顶层名字 → 指明了模块的名字（先看这块积木自己的模块，再看库里别的模块公开的）；不是库里的名字原样返回。
String _owner(LibLibrary lib, LibBlock b, String name) {
  bool has(LModule m) => m.decls.any((d) => d.name == name);
  final own = lib.modules.where((m) => m.name == b.module).firstOrNull;
  if (own != null && has(own)) return lQualified(own.name, name);
  final other = lib.modules.where(has).firstOrNull;
  return other == null ? name : lQualified(other.name, name);
}

/// 把一块库积木用一次。
LibApplied libApply(LibLibrary lib, LibBlock b, LibUse use, LibCx cx) {
  try {
    if (b.how == LibHow.expand) {
      final forms = lcParse(b.expand);
      final keep = Set<Object>.identity();
      final r = _reader(lib, '积木「${b.look.name}」', use, cx, keep);
      for (final e in b.provides.entries) {
        r.renames[e.value] = use.provided[e.key] ?? e.value;
      }
      // 用户的库：模板里提到的库里的名字都指明是哪个模块的（用的人自己有同名的函数、两个库有同名的东西，都不会认错）。
      final q = lib.builtin ? null : LRenamer((n) => _owner(lib, b, n), keep: keep);
      if (b.isValue) {
        if (forms.length != 1) return LibApplied(problem: '积木「${b.look.name}」是值型的，模板要正好是一个式子');
        final value = r.expr(forms.single);
        return LibApplied(value: q == null ? value : q.expr(value));
      }
      final stmts = r.stmts(forms);
      return LibApplied(stmts: q == null ? stmts : q.mainBody(stmts));
    }
    String of(String name) => lib.builtin ? name : _owner(lib, b, name);
    final args = [for (final a in b.args) _argExpr(lib, b, a, use, cx)];
    final LExpr call;
    switch (b.how) {
      case LibHow.method:
        if (args.isEmpty) return LibApplied(problem: '积木「${b.look.name}」调的是对象的方法，实参表的第一项要是那个对象');
        call = LSend(args.first, b.of, args.sublist(1));
      case LibHow.static:
        final parts = b.of.split('.');
        if (parts.length != 2) return LibApplied(problem: '积木「${b.look.name}」要调的「${b.of}」要写成 类名.方法名');
        call = LSend(LName(of(parts[0])), parts[1], args);
      case LibHow.call || LibHow.expand:
        call = LCall(LName(of(b.of)), args);
    }
    if (b.isValue) return LibApplied(value: call);
    final target = b.into == null ? null : use.targets[b.into];
    return LibApplied(stmts: [if (target != null) LAssign(LTName(target), call) else if (b.shape == CustomBlockShape.cap) LReturn(call) else LExprStmt(call)]);
  } on _Problem catch (e) {
    return LibApplied(problem: e.what);
  } on Object catch (e) {
    return LibApplied(problem: '积木「${b.look.name}」的模板读不了：${lcProblemText(e)}');
  }
}

/// 库的“启动时”模板（[LibLibrary.init] / [LibLibrary.start]）→ 语句。模板里新建的名字**不改名**（init 新建的东西要递给后面用）。
({List<LStmt> stmts, String? problem}) libMoment(LibLibrary lib, String template, LibCx cx) {
  if (template.trim().isEmpty) return (stmts: const [], problem: null);
  try {
    final r = _reader(lib, '库「${lib.name}」启动时', const LibUse(), cx)..freshName = null;
    return (stmts: r.stmts(lcParse(template)), problem: null);
  } on _Problem catch (e) {
    return (stmts: const [], problem: e.what);
  } on Object catch (e) {
    return (stmts: const [], problem: '库「${lib.name}」启动时的模板读不了：${lcProblemText(e)}');
  }
}

/// 用了几个库的入口模块 ＋ 这些库的模块 → 一个程序（库的模块排前面；入口模块的“用到了谁”补上库的模块名）。
LProgram libProgram(List<LibLibrary> libs, LModule entry) {
  final names = [for (final l in libs) ...l.moduleNames];
  return LProgram([
    for (final l in libs) ...l.modules,
    LModule(name: entry.name, uses: {...entry.uses, ...names}.toList(), decls: entry.decls, body: entry.body, src: entry.src),
  ], entry: entry.name);
}
