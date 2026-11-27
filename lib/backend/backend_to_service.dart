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

import 'package:lopicode/backend/backend_function.dart';
import 'package:lopicode/backend/backend_ir.dart';
import 'package:lopicode/backend/backend_lang.dart';
import 'package:lopicode/backend/backend_lib_doc.dart';
import 'package:lopicode/backend/backend_lower_core.dart';
import 'package:lopicode/backend/backend_lower_func.dart';
import 'package:lopicode/backend/backend_lower_lang.dart';
import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/backend/backend_text.dart';
import 'package:lopicode/backend/backend_to_service_libs.dart';
import 'package:lopicode/backend/lib_service.dart';
import 'package:lopicode/lang/ast.dart';
import 'package:lopicode/lang/ast_util.dart';
import 'package:lopicode/lang/custom_block.dart';
import 'package:lopicode/lang/gen.dart' show LangUnsupported;
import 'package:lopicode/lang/gen2_all.dart';
import 'package:lopicode/lang/lib_apply.dart';
import 'package:lopicode/lang/lib_model.dart';
import 'package:lopicode/lang/rt.dart';
import 'package:lopicode/lang/rules.dart';
import 'package:lopicode/lang/typecheck.dart';
import 'package:lopicode/lang/types.dart';
import 'package:lopicode/lowcode/logic_model.dart';

export 'package:lopicode/backend/backend_to_service_libs.dart';

part 'backend_to_service_bridge.dart';

/// 翻出来的程序；[problems] 不空就是有地方翻不了（程序还是给，方便看是哪里）。
typedef BeServiceProgram = ({LProgram? program, List<String> problems, List<String> skipped});

/// 翻译的全部结果：除了程序，还有类型检查要用的东西——文档自己的声明和入口的语句（节点就是翻译器翻出来的那些对象，
/// 没有经过合并改名，所以“哪个式子是哪一格翻来的”还对得上）、每一串积木用的翻译器、每个接口的处理函数是哪个匿名函数。
class BeServiceBuilt {
  const BeServiceBuilt({
    this.program,
    this.problems = const [],
    this.skipped = const [],
    this.decls = const [],
    this.body = const [],
    this.trees = const {},
    this.lowers = const {},
    this.names = const {},
    this.lambdas = const {},
    this.split = false,
    this.libs = const [],
    this.service = true,
    this.holes = const [],
  });
  final LProgram? program;
  final List<String> problems;
  final List<String> skipped;

  /// 文档自己的声明（函数、类型、顶上的变量），带着是哪一串（串的 id；类型是类型的 id）。
  final List<({String key, LDecl decl})> decls;

  /// 入口的语句：库的准备 → 每个接口登记 → “程序开始时” → 库的“最后启动”。
  final List<LStmt> body;
  final Map<String, LcBlockTree> trees;
  final Map<String, BeLangLower> lowers;

  /// 函数、方法、“程序开始时”这些串在检查结果里叫什么。
  final Map<String, String> names;

  /// 接口的 id → 它的处理函数（帽子展开出来的那个匿名函数）。
  final Map<String, LLambda> lambdas;

  /// 文档自己分了模块没有。
  final bool split;

  /// 程序里带上的库（带了“接口服务”的话它排第一个）。
  final List<LibLibrary> libs;

  /// 翻的时候“当成空的”那些地方（没填好的格子、没声明的集合这种），每条前面带着是哪一串。
  final List<String> holes;

  /// 带没带“接口服务”库（没带＝一个跑完就结束的程序，不开服务）。
  final bool service;
}

/// 库里“这次请求”“路由表”这两样隐含的东西叫什么。
const String kBeServiceRequest = '请求';

/// 这些定义和语句里有没有提到 [lib] 的模块里的名字（“等一会儿”这种不经积木表、直接调库里函数的）。
bool _mentions(LibLibrary lib, List<LDecl> decls, List<LStmt> body) {
  final names = {
    for (final m in lib.modules)
      for (final d in m.decls) d.name,
  };
  var hit = false;
  void expr(LExpr e) {
    if (e is LName && names.contains(e.name)) hit = true;
    if (!hit) lExprChildren(e).forEach(expr);
  }

  void stmts(List<LStmt> list) => lWalkExprs(list, expr);
  stmts(body);
  for (final d in decls) {
    switch (d) {
      case LFuncDecl():
        stmts(d.body);
      case LClassDecl():
        stmts(d.ctor?.body ?? const []);
        for (final m in d.methods) {
          stmts(m.fn.body);
        }
      default:
        break;
    }
  }
  return hit;
}

/// 严格规矩的后端文档 → 程序（库的模块 + 文档自己的模块）。版本 1 的文档不归这里管，返回没有程序。
BeServiceProgram beServiceProgram(BeDocument doc) {
  final out = beServiceBuild(doc);
  return (program: out.program, problems: out.problems, skipped: out.skipped);
}

LLambda? _firstLambda(List<LStmt> stmts) {
  LLambda? hit;
  void look(LExpr e) {
    if (hit != null) return;
    if (e is LLambda) {
      hit = e;
    } else {
      lExprChildren(e).forEach(look);
    }
  }

  lWalkExprs(stmts, look);
  return hit;
}

/// 翻译。[shadow]＝给类型检查用的影子模式：名字不管新建没新建都照写（检查器才报得出“看不见”），写坏了的接口也照翻。
/// 生成用的（不带影子）和检查用的是同一套翻法、同一个库，只差这一点。
BeServiceBuilt beServiceBuild(BeDocument doc, {bool shadow = false}) {
  final problems = <String>[], skipped = <String>[];
  if (!langRulesStrict(doc.rules)) return const BeServiceBuilt(problems: ['这份文档照的是规矩版本 1，不走库']);
  final lib = beServiceLibrary();
  if (lib.problems.isNotEmpty) return BeServiceBuilt(problems: ['内置库“接口服务”读不了：${lib.problems.first}']);
  try {
    final core = doc.core;
    final fresh = _Fresh();
    final flags = _Flags();
    final settings = beServiceSettings(doc);
    final userLibs = beUsedLibs(doc, problems);
    final allProvides = {...lib.provides, for (final l in userLibs) ...l.provides};
    final cx = LibCx(context: allProvides, settings: settings, fresh: fresh.call);
    final trees = <String, LcBlockTree>{};
    final lowers = <String, BeLangLower>{};
    final names = <String, String>{};
    final lambdas = <String, LLambda>{};
    BeLangLower? lowerOf(LcBlockTree? tree, BeRoute shell, {required bool inFunction, Map<String, String> more = const {}}) {
      final lower = beLangLowerOf(doc, shell, shadow: shadow, inFunction: inFunction, all: true);
      if (lower == null) return null;
      lower
        ..typed = true
        ..pure = true
        ..core = core
        ..bridge = _Bridge(doc, flags, lib, settings, fresh, problems, {...allProvides, ...more});
      if (tree != null) {
        trees[tree.id] = tree;
        lowers[tree.id] = lower;
      }
      return lower;
    }

    final decls = <({String key, LDecl decl})>[];
    for (final f in doc.functions) {
      // 库里公开成积木的函数：来源是“隐含的东西”的参数，在这个函数里就是那样东西。
      final def = beLibDefOfFunction(doc.library, f);
      final more = {
        if (def != null)
          for (final e in def.params.entries)
            if (e.value.from == BeLibFrom.context && e.value.key.isNotEmpty) e.value.key: beIdent(e.key),
      };
      final lower = lowerOf(
        f,
        BeRoute(id: f.id, method: 'GET', path: '/', body: f.body),
        inFunction: true,
        more: more,
      );
      if (lower == null) continue;
      names[f.id] = f.ident;
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
      final values = lowerOf(null, BeRoute(id: '', method: 'GET', path: '/'), inFunction: true);
      final unit = beCoreUnit(
        doc,
        body: (m, owner) {
          names[m.id] = owner == null ? '程序开始时' : '${owner.name}.${m.name}';
          return lowerOf(m, BeRoute(id: m.id, method: 'GET', path: '/', body: m.body), inFunction: true)?.stmts(m.body, const [], 0) ?? const [];
        },
        value: (v) => values?.value(v) ?? const LLit(null),
      );
      decls.addAll(unit.decls);
      main = unit.main;
    }

    final hat = lib.block('onRequest');
    if (hat == null) return const BeServiceBuilt(problems: ['内置库里没有“当收到请求”']);
    if (doc.routes.isNotEmpty) flags.service = true;
    final routes = <LStmt>[];
    for (final r in doc.routes) {
      final title = describeBeRoute(r);
      final badMethod = !kBeMethods.contains(r.method), badPath = parseBePath(r.path) == null;
      if (badMethod) skipped.add('$title：请求方式不认识');
      if (!badMethod && badPath) skipped.add('$title：路径格式不对');
      if ((badMethod || badPath) && !shadow) continue;
      final provided = libProvided(hat, fresh.call);
      final lower = lowerOf(r, r, inFunction: false, more: provided);
      if (lower == null) continue;
      final body = <LStmt>[
        // 文档里声明的变量：每次请求都从初始值开始（和版本 1 一样）；里面放什么说不准，当“任意”。
        for (final v in doc.variables)
          if (!lower.locals.containsKey(v.name)) LLet(v.name, LAscribe(LLit(beInitialValue(v)), LType.any)),
        ...lower.stmts(r.body, const [], 0),
      ];
      final got = libApply(lib, hat, LibUse(values: {'method': LLit(badMethod ? 'GET' : r.method), 'path': LLit(badPath ? '/' : r.path)}, mouths: {'body': body}, provided: provided), cx);
      if (got.problem != null) {
        problems.add('$title：${got.problem}');
        continue;
      }
      final lambda = _firstLambda(got.stmts);
      if (lambda != null) lambdas[r.id] = lambda;
      routes.addAll(got.stmts);
    }

    // 以库的帽子积木开头的那些串：帽子展开出来的语句排在接口后面、“程序开始时”前面。
    for (final h in doc.hats) {
      final ref = beLibOpOf(h.op);
      final l = ref == null || doc.use(ref.lib) == null ? null : userLibs.where((x) => x.id == ref.lib).firstOrNull;
      final block = l?.block(ref!.block);
      if (l == null || block == null) {
        problems.add('有一串积木的帽子是库「${ref?.lib ?? ''}」的，可是这个库（或这块积木）找不到');
        continue;
      }
      final provided = libProvided(block, fresh.call);
      final lower = lowerOf(
        h,
        BeRoute(id: h.id, method: 'GET', path: '/', body: h.body),
        inFunction: true,
        more: provided,
      );
      if (lower == null) continue;
      names[h.id] = block.look.name;
      final body = lower.stmts(h.body, const [], 0);
      final values = <String, LExpr>{};
      String? mouth;
      for (final part in parseLookTemplate(block.look.template)) {
        if (!part.isSlot) continue;
        final v = h.args[part.text];
        switch (block.kindOf(part.text)) {
          case LibSlotKind.mouth:
            mouth ??= part.text;
          case LibSlotKind.assign:
            break;
          case LibSlotKind.literal || LibSlotKind.value:
            values[part.text] = v is String || v is num || v is bool ? LLit(v) : lower.value(v);
        }
      }
      final got = libApply(l, block, LibUse(values: values, mouths: {?mouth: body}, provided: provided), LibCx(context: allProvides, settings: beLibSettingsOf(doc, l), fresh: fresh.call));
      if (got.problem != null) {
        problems.add('${block.look.name}：${got.problem}');
        continue;
      }
      final lambda = _firstLambda(got.stmts);
      if (lambda != null) lambdas[h.id] = lambda;
      routes.addAll(got.stmts);
    }

    // 带不带“接口服务”：没碰库的文档照旧一定带；用了库的文档，有接口、用了它的积木、或者哪个库靠着它才带。
    if (doc.usesLibs && !flags.service) flags.service = _mentions(lib, [for (final d in decls) d.decl], [...routes, ...main]);
    final service = !doc.usesLibs || flags.service || userLibs.any((l) => l.requires.contains(kBeServiceLibId));
    final libs = [if (service) lib, ...userLibs];
    final inits = <LStmt>[], starts = <LStmt>[];
    for (final l in libs) {
      final lcx = LibCx(context: allProvides, settings: beLibSettingsOf(doc, l), fresh: fresh.call);
      final init = libMoment(l, l.init, lcx), start = libMoment(l, l.start, lcx);
      for (final p in [init.problem, start.problem]) {
        if (p != null) problems.add(p);
      }
      inits.addAll(init.stmts);
      starts.addAll(start.stmts);
    }
    final body = [...inits, ...routes, ...main, ...starts];
    final own = beCoreProgram(core, decls, body);
    final entry = own?.modules.where((m) => m.name == own.entry).firstOrNull ?? LModule(name: 'main', decls: [for (final d in decls) d.decl], body: body);
    final linked = libProgram(libs, entry);
    final program = own == null
        ? linked
        : LProgram([
            for (final l in libs) ...l.modules,
            for (final m in own.modules)
              if (m.name != own.entry) m,
            linked.modules.last,
          ], entry: own.entry);
    return BeServiceBuilt(
      program: program,
      problems: problems,
      skipped: skipped,
      decls: decls,
      body: body,
      trees: trees,
      lowers: lowers,
      names: names,
      lambdas: lambdas,
      split: own != null,
      libs: libs,
      service: service,
      holes: [
        for (final e in lowers.entries)
          for (final n in e.value.host.swapNotes([])) '${names[e.key] ?? e.key}：$n',
      ],
    );
  } on Object catch (e) {
    return BeServiceBuilt(problems: [...problems, '积木翻不成语法树（$e）'], skipped: skipped);
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
