/// 后端文档 → “接口服务”库（积木第 5 版·库 1）：严格规矩的后端文档翻成一个只用语言核心和内置库的程序，
/// 交给版本 2 的生成器出五种语言的工程。
///
/// 做法：积木照旧由 backend_lower_lang.dart 翻成语法树，只是挂上“走库”的翻法（[BeLibBridge]）——
/// 旧的“干活”积木（返回、数据集合）和旧的值（路径参数、请求内容…）不再包成 `LHost` / `LNative(旧小库名)`，
/// 而是按内置库积木上写的旧名对照（`legacy`）找到那块库积木，用库机制（`libApply`）展开。
/// 每个接口＝一顶“当收到请求”帽子；程序的顺序照 C 分册 7.7：库的准备 → 每个接口登记 → “程序开始时” → 库的“最后启动”（开端口）。
///
/// 这条路不看开关（`kLangStrictBackendGen` 关着也能直接调，测试就是这么用的）；产品里哪里调它由开关管。
/// 任何输入都不抛异常：翻不了的地方记一句原因（[BeServiceProgram.problems]）。
library;

import 'package:lopicode/backend/backend_ir.dart';
import 'package:lopicode/backend/backend_lang.dart';
import 'package:lopicode/backend/backend_lower_core.dart';
import 'package:lopicode/backend/backend_lower_func.dart';
import 'package:lopicode/backend/backend_lower_lang.dart';
import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/backend/backend_text.dart';
import 'package:lopicode/backend/lib_service.dart';
import 'package:lopicode/lang/ast.dart';
import 'package:lopicode/lang/gen.dart' show LangUnsupported;
import 'package:lopicode/lang/gen2_all.dart';
import 'package:lopicode/lang/lib_apply.dart';
import 'package:lopicode/lang/lib_model.dart';
import 'package:lopicode/lang/rt.dart';
import 'package:lopicode/lang/rules.dart';
import 'package:lopicode/lang/typecheck.dart';
import 'package:lopicode/lang/types.dart';

/// 翻出来的程序；[problems] 不空就是有地方翻不了（程序还是给，方便看是哪里）。
typedef BeServiceProgram = ({LProgram? program, List<String> problems, List<String> skipped});

/// 库里“这次请求”“路由表”这两样隐含的东西叫什么。
const String kBeServiceRequest = '请求';

/// 用户的名字只有英文字母、数字、下划线（`beNamePattern`）；库这边起的名字都带汉字，所以撞不上。
class _Fresh {
  int _n = 0;
  String call(String name) => '${name}_${++_n}';
}

class _Bridge implements BeLibBridge {
  _Bridge(this.lib, this.settings, this.fresh, this.problems, Map<String, String> base) : context = {...base};
  final LibLibrary lib;
  final Map<String, Object?> settings;
  final _Fresh fresh;
  final List<String> problems;

  /// 现在看得见的隐含的东西：名字 → 变量名。
  final Map<String, String> context;
  final Map<int, String> _temps = {};

  LibCx get _cx => LibCx(context: context, settings: settings, fresh: fresh.call);

  LExpr _bad(String why) {
    if (!problems.contains(why)) problems.add(why);
    return const LLit(null);
  }

  /// 旧名对照里按旧参数顺序排的槽：`@名字`＝那一位是隐含的东西（库自己会拿），不占槽。
  Map<String, LExpr> _values(LibBlock b, List<BeX> args) => {
    for (var i = 0; i < b.legacyArgs.length && i < args.length; i++)
      if (!b.legacyArgs[i].startsWith('@')) b.legacyArgs[i]: expr(args[i]),
  };

  @override
  LExpr expr(BeX x) {
    switch (x) {
      case BeXLang(:final expr):
        return expr;
      case BeXLit(:final value):
        return LLit(value);
      case BeXVar(:final name):
        return LName(name);
      case BeXTmp(:final slot):
        final name = _temps[slot];
        return name == null ? _bad('用到了一个还没存的临时值') : LName(name);
      case BeXReq():
        final name = context[kBeServiceRequest];
        return name == null ? _bad('“这次请求”只有在接口里才有，“我的积木”里用不了') : LName(name);
      case BeXCall(:final fn, :final args):
        final block = lib.legacy(fn);
        if (block != null) {
          if (!block.isValue) return _bad('「${block.look.name}」不是一个值');
          final got = libApply(lib, block, LibUse(values: _values(block, args)), _cx);
          final value = got.value;
          if (value == null) return _bad(got.problem ?? '「${block.look.name}」用不了');
          // 类型检查那边（backend_type_bridge.dart）把这些值都当“任意”，这里说成一样的，免得“查过了却生成不了”。
          return LAscribe(value, LType.any);
        }
        if (fn == 'obj') {
          return LAscribe(LDictLit([for (var i = 0; i + 1 < args.length; i += 2) LDictEntry(expr(args[i]), LAscribe(expr(args[i + 1]), LType.any))]), const LType.dictOf(LType.any));
        }
        if (kLangCoreFns.containsKey(fn) || kLangRtFns.containsKey(fn)) return LRt(fn, [for (final a in args) expr(a)]);
        return _bad('「$fn」还没有接到库上');
    }
  }

  List<LStmt> _use(LibBlock block, BeXCall call, {String? into}) {
    final target = block.slotKinds.entries.where((e) => e.value == LibSlotKind.assign).firstOrNull?.key;
    final got = libApply(lib, block, LibUse(values: _values(block, call.args), targets: {if (into != null && target != null) target: into}), _cx);
    if (got.problem != null) {
      _bad(got.problem!);
      return const [];
    }
    final value = got.value;
    if (value == null) return got.stmts;
    return [into == null ? LExprStmt(value) : LAssign(LTName(into), LAscribe(value, LType.any))];
  }

  @override
  List<LStmt>? mouthBlock(String legacyFn, List<LExpr> args, {Map<String, List<LStmt>> mouths = const {}, String? into}) {
    final block = lib.legacy(legacyFn);
    if (block == null) return null;
    final target = block.slotKinds.entries.where((e) => e.value == LibSlotKind.assign).firstOrNull?.key;
    final values = {
      for (var i = 0; i < block.legacyArgs.length && i < args.length; i++)
        if (!block.legacyArgs[i].startsWith('@')) block.legacyArgs[i]: args[i],
    };
    final got = libApply(lib, block, LibUse(values: values, mouths: mouths, targets: {if (into != null && target != null) target: into}), _cx);
    if (got.problem != null) _bad(got.problem!);
    return got.stmts;
  }

  @override
  List<LStmt> stmts(List<BeS> list) => [for (final s in list) ..._one(s)];

  List<LStmt> _one(BeS s) {
    switch (s) {
      case BeSLang(:final stmts):
        return stmts;
      case BeSNote(:final text):
        return [LNote(text)];
      case BeSSet(:final name, :final value):
        final block = value is BeXCall ? lib.legacy(value.fn) : null;
        if (block != null && !block.isValue) return _use(block, value as BeXCall, into: name);
        return [LAssign(LTName(name), expr(value))];
      case BeSLet(:final slot, :final value):
        final name = _temps[slot] = fresh('临时');
        return [LLet(name, expr(value))];
      case BeSDo(:final call):
        final block = lib.legacy(call.fn);
        return block != null ? _use(block, call) : [LExprStmt(expr(call))];
      case BeSReturn(:final response):
        final block = lib.legacy(response.fn);
        if (block == null) {
          _bad('「${response.fn}」还没有接到库上');
          return const [];
        }
        return _use(block, response);
      case BeSIf(:final cond, :final then, :final orElse):
        return [
          LIf([LIfArm(expr(cond), stmts(then))], orElse: stmts(orElse)),
        ];
      default:
        _bad('有一块旧积木还没有接到库上');
        return const [];
    }
  }
}

/// 这份文档里库的设置项各是什么值（旧文档顶层的键 → 设置项，照库里写的 `legacyKey`）。
Map<String, Object?> beServiceSettings(BeDocument doc) => {
  'port': doc.port,
  'collections': [for (final c in doc.collections) c.name],
};

/// 严格规矩的后端文档 → 程序（库的模块 + 文档自己的模块）。版本 1 的文档不归这里管，返回没有程序。
BeServiceProgram beServiceProgram(BeDocument doc) {
  final problems = <String>[], skipped = <String>[];
  if (!langRulesStrict(doc.rules)) return (program: null, problems: ['这份文档照的是规矩版本 1，不走库'], skipped: skipped);
  final lib = beServiceLibrary();
  if (lib.problems.isNotEmpty) return (program: null, problems: ['内置库“接口服务”读不了：${lib.problems.first}'], skipped: skipped);
  try {
    final core = doc.core;
    final fresh = _Fresh();
    final settings = beServiceSettings(doc);
    final cx = LibCx(context: lib.provides, settings: settings, fresh: fresh.call);
    BeLangLower? lowerOf(BeRoute shell, {required bool inFunction, Map<String, String> more = const {}}) {
      final lower = beLangLowerOf(doc, shell, inFunction: inFunction, all: true);
      lower
        ?..typed = true
        ..pure = true
        ..core = core
        ..bridge = _Bridge(lib, settings, fresh, problems, {...lib.provides, ...more});
      return lower;
    }

    final decls = <({String key, LDecl decl})>[];
    for (final f in doc.functions) {
      final lower = lowerOf(BeRoute(id: f.id, method: 'GET', path: '/', body: f.body), inFunction: true);
      if (lower == null) continue;
      decls.add((
        key: f.id,
        decl: LFuncDecl(
          f.ident,
          beLangParams(f, typed: true),
          lower.stmts(f.body, const [], 0),
          isPublic: core.publics.contains(f.id),
          src: LSrc(script: f.id),
          type: f.returns,
        ),
      ));
    }
    var main = const <LStmt>[];
    if (!core.isEmpty) {
      final values = lowerOf(BeRoute(id: '', method: 'GET', path: '/'), inFunction: true);
      final unit = beCoreUnit(
        doc,
        body: (m, owner) => lowerOf(BeRoute(id: m.id, method: 'GET', path: '/', body: m.body), inFunction: true)?.stmts(m.body, const [], 0) ?? const [],
        value: (v) => values?.value(v) ?? const LLit(null),
      );
      decls.addAll(unit.decls);
      main = unit.main;
    }

    final hat = lib.block('onRequest');
    if (hat == null) return (program: null, problems: ['内置库里没有“当收到请求”'], skipped: skipped);
    final routes = <LStmt>[];
    for (final r in doc.routes) {
      final title = describeBeRoute(r);
      if (!kBeMethods.contains(r.method)) {
        skipped.add('$title：请求方式不认识');
        continue;
      }
      if (parseBePath(r.path) == null) {
        skipped.add('$title：路径格式不对');
        continue;
      }
      final provided = libProvided(hat, fresh.call);
      final lower = lowerOf(r, inFunction: false, more: provided);
      if (lower == null) continue;
      final body = <LStmt>[
        // 文档里声明的变量：每次请求都从初始值开始（和版本 1 一样）；里面放什么说不准，当“任意”。
        for (final v in doc.variables)
          if (!lower.locals.containsKey(v.name)) LLet(v.name, LAscribe(LLit(beInitialValue(v)), LType.any)),
        ...lower.stmts(r.body, const [], 0),
      ];
      final got = libApply(lib, hat, LibUse(values: {'method': LLit(r.method), 'path': LLit(r.path)}, mouths: {'body': body}, provided: provided), cx);
      if (got.problem != null) {
        problems.add('$title：${got.problem}');
        continue;
      }
      routes.addAll(got.stmts);
    }

    final init = libMoment(lib, lib.init, cx), start = libMoment(lib, lib.start, cx);
    for (final p in [init.problem, start.problem]) {
      if (p != null) problems.add(p);
    }
    final body = [...init.stmts, ...routes, ...main, ...start.stmts];
    final own = beCoreProgram(core, decls, body);
    final entry = own?.modules.where((m) => m.name == own.entry).firstOrNull ?? LModule(name: 'main', decls: [for (final d in decls) d.decl], body: body);
    final linked = libProgram([lib], entry);
    final program = own == null
        ? linked
        : LProgram([
            ...lib.modules,
            for (final m in own.modules)
              if (m.name != own.entry) m,
            linked.modules.last,
          ], entry: own.entry);
    return (program: program, problems: problems, skipped: skipped);
  } on Object catch (e) {
    return (program: null, problems: [...problems, '积木翻不成语法树（$e）'], skipped: skipped);
  }
}

/// 出工程的结果：成了是文件表（第一个是主文件），不成是一句原因。
typedef BeServiceGen = ({Map<String, String>? files, String? problem});

/// 严格规矩的后端文档 → 那种语言的整套文件。任何输入都不抛异常。
BeServiceGen beServiceGenerate(BeDocument doc, String language) {
  if (!kGen2Languages.contains(language)) return (files: null, problem: '这种语言还没有生成器');
  final out = beServiceProgram(doc);
  final program = out.program;
  if (program == null || out.problems.isNotEmpty) return (files: null, problem: out.problems.firstOrNull ?? '积木翻不成语法树');
  try {
    final (linked, checked) = checkProgramTypes(program);
    if (linked.issues.isNotEmpty) return (files: null, problem: linked.issues.first.message);
    final errors = checked?.errors ?? const [];
    if (errors.isNotEmpty) return (files: null, problem: '${errors.first.where}：${errors.first.message}');
    return (files: gen2ProgramFiles(language, program), problem: null);
  } on LangUnsupported catch (e) {
    return (files: null, problem: e.what);
  } on Object catch (e) {
    return (files: null, problem: '$e');
  }
}
