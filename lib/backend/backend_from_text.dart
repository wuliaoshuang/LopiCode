/// 文字写法的模块 → 积木文档（内置库上画布用）。
///
/// 内置的“页面”库、“接口服务”库的模块是语言核心的文字写法（lib_page_module.dart、lib_service_module.dart）。这里把它反过来
/// 翻成一份积木文档（一个库的画布原件）：函数成了“我的积木”，记录成了“类型与类”里的类型，语句和式子成了积木。
///
/// 翻不了的地方不硬翻、不丢：落成“文字原样”块（backend_blocks_raw.dart），里面是那一句 / 那个式子的文字写法。
/// 怎么保证翻对了：翻完以后把积木文档照平常的路翻回语法树，再和原来的模块逐个函数、逐句对一遍（两边写成同一种文字来比）。
/// 对不上的那一句换成“文字原样”再对；还对不上，这个函数整个用“文字原样”。所以最后得到的文档翻回去和原来的模块一句不差，
/// 差别只有三处，都不改变意思、都如实记在 [BeFromTextResult] 里：
/// - 局部变量的名字：积木里的变量名只能是英文字母、数字、下划线，模块里用汉字起的局部名字换成了 v1、v2…；
/// - 类型的别名：积木文档里没有“别名”这种类型，用到别名的地方直接写成它代表的那个类型；
/// - 宿主接口的声明：不用写，用到哪个自动补哪个（参数名成了 p1、p2…）。
library;

import 'dart:convert';

import 'package:lopicode/backend/backend_blocks_core.dart';
import 'package:lopicode/backend/backend_blocks_lang.dart';
import 'package:lopicode/backend/backend_blocks_raw.dart';
import 'package:lopicode/backend/backend_blocks_strict.dart';
import 'package:lopicode/backend/backend_blocks_typeops.dart';
import 'package:lopicode/backend/backend_function.dart';
import 'package:lopicode/backend/backend_lower_lang.dart';
import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/backend/backend_to_service.dart';
import 'package:lopicode/blocks/block_look.dart';
import 'package:lopicode/lang/ast.dart';
import 'package:lopicode/lang/ast_util.dart';
import 'package:lopicode/lang/lc_text.dart';
import 'package:lopicode/lang/lc_write.dart';
import 'package:lopicode/lang/lib_model.dart';
import 'package:lopicode/lang/link.dart';
import 'package:lopicode/lang/rename.dart';
import 'package:lopicode/lang/types.dart';
import 'package:lopicode/lang/types_json.dart';
import 'package:lopicode/lowcode/logic_expr.dart';
import 'package:lopicode/lowcode/logic_model.dart';

part 'backend_from_text_tree.dart';

/// 一个函数翻得怎么样。
class BeFromTextFn {
  BeFromTextFn(this.name, {required this.stmts, required this.rawStmts, required this.raws, this.whole = false});
  final String name;

  /// 一共多少句（连套在里面的）。
  final int stmts;

  /// 其中整句用了“文字原样”的。
  final int rawStmts;

  /// 没翻成积木的每一处的文字（整句的、一句里的某个值的）。
  final List<String> raws;

  /// 这个函数整个用的“文字原样”（逐句对不上）。
  final bool whole;
}

class BeFromTextResult {
  BeFromTextResult({required this.doc, required this.fns, required this.aliases, required this.renamed, required this.skipped, required this.problems});

  /// 画布上的文档（一个库的画布原件）；连壳子都搭不出来时是 null（原因在 [problems]）。
  final BeDocument? doc;
  final List<BeFromTextFn> fns;

  /// 摊开了的别名：名字 → 它代表的类型（文字写法）。
  final Map<String, String> aliases;

  /// 换了名字的局部变量一共多少个。
  final int renamed;

  /// 没带过来的声明（现在的积木文档放不下的那几种），每条一句话。
  final List<String> skipped;
  final List<String> problems;

  int get stmts => fns.fold(0, (a, f) => a + f.stmts);
  int get rawStmts => fns.fold(0, (a, f) => a + f.rawStmts);
  int get rawSpots => fns.fold(0, (a, f) => a + f.raws.length);
  bool get ok => doc != null && problems.isEmpty;
}

class BeTextFn {
  BeTextFn(this.id, this.decl) : params = [for (final p in decl.params) p.name];
  final String id;
  final LFuncDecl decl;
  final List<String> params;
}

class BeFromText {
  BeFromText(this.module, {required this.id, required this.name, required this.side});
  final LModule module;
  final String id;
  final String name;
  final LibSide side;

  final Map<String, BeTextFn> funcs = {};
  final Set<String> classes = {};
  final Map<String, LType> aliases = {};
  final Set<String> _names = {};

  /// 模块里的变量：原来的名字 → 积木文档里的名字（汉字起的换成 g1、g2…）。
  final Map<String, String> globalNames = {};

  bool localOk(String n) => n != '_' && beNamePattern.hasMatch(n);
  bool isLocalName(String n) => _names.contains(n);

  /// 一个函数里新建的局部名字（设、常、循环自己的、接到的错误），照出现的先后。匿名函数里面的也算。
  List<String> _locals(List<LStmt> body) {
    final out = <String>[];
    void add(String? n) {
      if (n != null && !out.contains(n)) out.add(n);
    }

    void walk(List<LStmt> list) {
      lWalk(list, (s) {
        switch (s) {
          case LLet(:final name):
            add(name);
          case LForCount(:final name):
            add(name);
          case LForEach(:final item, :final index):
            add(item);
            add(index);
          case LForPairs(:final key, :final value):
            add(key);
            add(value);
          case LTry():
            for (final c in s.catches) {
              add(c.name);
            }
          default:
            break;
        }
      });
      void look(LExpr e) {
        if (e is LLambda) walk(e.stmts);
        lExprChildren(e).forEach(look);
      }

      lWalkExprs(list, look);
    }

    walk(body);
    return out;
  }

  Set<String> _lambdaParams(List<LStmt> body) {
    final out = <String>{};
    void look(LExpr e) {
      if (e is LLambda) {
        out.addAll([for (final p in e.params) p.name]);
        lWalkExprs(e.stmts, look);
      }
      lExprChildren(e).forEach(look);
    }

    lWalkExprs(body, look);
    return out;
  }

  /// 这个函数用的写法器：汉字起的局部名字换成 v1、v2…（和参数、匿名函数的参数、别的局部名字都不撞）。
  BeCanonWriter _writer(LFuncDecl d) {
    final locals = _locals(d.body);
    final lambdaParams = _lambdaParams(d.body);
    final taken = {...locals, for (final p in d.params) p.name, ...lambdaParams};
    final rename = <String, String>{};
    var n = 0;
    for (final l in locals) {
      if (localOk(l) || d.params.any((p) => p.name == l) || lambdaParams.contains(l)) continue;
      String to;
      do {
        to = 'v${++n}';
      } while (taken.contains(to));
      rename[l] = to;
      taken.add(to);
    }
    // 模块里的变量：没被这个函数自己的名字盖住的，照文档里的名字写。
    final outer = <String>[];
    for (final g in globalNames.entries) {
      if (locals.contains(g.key) || d.params.any((p) => p.name == g.key) || lambdaParams.contains(g.key)) continue;
      outer.add(g.key);
      if (g.value != g.key) rename[g.key] = g.value;
    }
    _names
      ..clear()
      ..addAll(locals)
      ..addAll(outer);
    return BeCanonWriter(rename: rename, aliases: aliases);
  }

  Map<String, dynamic> _fnJson(BeTextFn f, List<Map<String, dynamic>> body) {
    final w = BeCanonWriter(aliases: aliases);
    final t = f.decl.type;
    return {
      'id': f.id,
      'look': {'name': f.decl.name, 'shape': 'auto'},
      'params': [
        for (final p in f.decl.params) {'name': p.name, if (p.type != null) 'type': lTypeToJson(w.expand(p.type!)), if (p.defaultValue != null) 'default': p.defaultValue!.value},
      ],
      if (t != null) 'returns': lTypeToJson(w.expand(t)),
      'body': body,
    };
  }

  Map<String, dynamic> _docJson(List<Map<String, dynamic>> fns, List<Map<String, dynamic>> types, List<String> public, [List<Map<String, dynamic>> globals = const []]) => {
    'version': 5,
    'kind': 'backend',
    'name': name,
    'port': 8130,
    'language': 'node',
    'rules': 2,
    if (fns.isNotEmpty) 'functions': fns,
    'core': {if (types.isNotEmpty) 'types': types, if (globals.isNotEmpty) 'globals': globals, if (public.isNotEmpty) 'public': public},
    'library': {'id': id, 'version': '1.0.0', if (side != LibSide.backend) 'for': side.name},
  };

  BeDocument? _parse(Map<String, dynamic> json, List<String> problems) {
    final parsed = BeDocument.parse(jsonEncode(json));
    if (parsed.note != null) problems.add('翻出来的文档有读不回来的地方：${parsed.note}');
    return parsed.doc;
  }

  /// 积木文档照平常的路翻回语法树以后，每个函数的每一句写成对照用的文字（注释不算）。翻不回去返回 null。
  Map<String, List<String>>? _lowered(BeDocument doc, List<String> problems) {
    final built = beServiceBuild(doc);
    final program = built.program;
    if (program == null) {
      problems.addAll(built.problems);
      return null;
    }
    final theirs = {for (final l in built.libs) ...l.moduleNames};
    final plain = LRenamer((n) => n.contains(kLQualifiedMark) ? n.substring(n.indexOf(kLQualifiedMark) + 1) : n);
    final w = BeCanonWriter();
    final out = <String, List<String>>{};
    for (final mod in program.modules) {
      if (theirs.contains(mod.name)) continue;
      for (final d in plain.decls(mod.decls)) {
        if (d is LFuncDecl) out[d.name] = [for (final s in d.body) ?_text(() => w.stmt(s, ''))];
      }
    }
    return out;
  }

  String? _text(String? Function() write) {
    try {
      return write();
    } on Object catch (e) {
      return '（写不出来：$e）';
    }
  }

  BeFromTextResult run() {
    final problems = <String>[], skipped = <String>[], types = <Map<String, dynamic>>[], public = <String>[];
    final fnDecls = <LFuncDecl>[];
    final varDecls = <LVarDecl>[];
    var tn = 0;
    for (final d in module.decls) {
      switch (d) {
        case LAliasDecl():
          aliases[d.name] = d.target;
        case LFuncDecl():
          fnDecls.add(d);
        case LVarDecl():
          varDecls.add(d);
        case LNativeDecl():
          break;
        case LRecordDecl() when d.typeParams.isEmpty:
          classes.add(d.name);
          final tid = 't${++tn}';
          types.add({'id': tid, 'kind': 'record', 'name': d.name, 'fields': const <Object>[], '@fields': d.fields});
          if (d.isPublic) public.add(tid);
        default:
          skipped.add('「${d.name}」（这种声明现在的积木文档放不下，没带过来）');
      }
    }
    final head = BeCanonWriter(aliases: aliases);
    for (final t in types) {
      final fields = t.remove('@fields') as List<LTypedField>;
      t['fields'] = [
        for (final f in fields) {'name': f.name, 'type': lTypeToJson(head.expand(f.type))},
      ];
    }
    for (final (i, d) in fnDecls.indexed) {
      funcs[d.name] = BeTextFn('f${i + 1}', d);
      if (d.isPublic) public.add('f${i + 1}');
    }

    // 模块里的变量：进文档的“变量”（汉字起的名字换成 g1、g2…）；初始值翻不成积木的不带过来。
    final globals = <Map<String, dynamic>>[];
    final fnNames = {for (final d in fnDecls) d.name};
    var gn = 0;
    for (final d in varDecls) {
      var to = d.name;
      if (!localOk(to)) {
        do {
          to = 'g${++gn}';
        } while (fnNames.contains(to) || varDecls.any((x) => x.name == to));
      }
      final t = _Tree(this, BeCanonWriter(aliases: aliases), const {});
      final init = t.expr(d.init);
      if (t.raws.isNotEmpty) {
        skipped.add('「${d.name}」（模块里的变量，初始值没有对应的积木，没带过来）');
        continue;
      }
      globalNames[d.name] = to;
      globals.add({'name': to, 'init': init, if (d.isConst) 'const': true, if (d.type != null) 'type': lTypeToJson(head.expand(d.type!))});
      if (d.isPublic) public.add('g:$to');
    }

    // 第一遍：能翻的都翻。
    final writers = <String, BeCanonWriter>{}, want = <String, List<String>>{}, bodies = <String, List<Map<String, dynamic>>>{};
    final trees = <String, _Tree>{};
    var renamed = 0;
    for (final f in funcs.values) {
      final w = writers[f.decl.name] = _writer(f.decl);
      renamed += w.rename.length;
      final real = [
        for (final s in f.decl.body)
          if (s is! LNote) s,
      ];
      want[f.decl.name] = [for (final s in real) _text(() => w.stmt(s, '')) ?? ''];
      final t = trees[f.decl.name] = _Tree(this, w, {...f.params});
      bodies[f.decl.name] = t.stmts(real);
    }
    Map<String, dynamic> docOf() => _docJson([for (final f in funcs.values) _fnJson(f, bodies[f.decl.name]!)], types, public, globals);

    // 翻回去逐句对：头一回对不上的那一句换成文字原样；第二回还对不上的函数整个换；第三回还有对不上的＝报出来。
    final whole = <String>{};
    List<LStmt> realOf(BeTextFn f) => [
      for (final s in f.decl.body)
        if (s is! LNote) s,
    ];
    void allRaw(BeTextFn f) {
      final t = _Tree(this, writers[f.decl.name]!, {...f.params});
      whole.add(f.decl.name);
      bodies[f.decl.name] = [for (final s in realOf(f)) t.rawStmt(s)];
    }

    Map<String, List<String>>? back(List<String> notes) {
      final doc = _parse(docOf(), notes);
      return doc == null ? null : _lowered(doc, notes);
    }

    bool same(String n, Map<String, List<String>>? got) {
      final have = got?[n], wanted = want[n]!;
      if (have == null || have.length != wanted.length) return false;
      for (var i = 0; i < wanted.length; i++) {
        if (have[i] != wanted[i]) return false;
      }
      return true;
    }

    final first = back([]);
    for (final f in funcs.values) {
      final n = f.decl.name;
      final have = first?[n], wanted = want[n]!;
      if (have == null || have.length != wanted.length) {
        allRaw(f);
        continue;
      }
      final real = realOf(f);
      final t = _Tree(this, writers[n]!, {...f.params});
      for (var i = 0; i < wanted.length; i++) {
        if (have[i] != wanted[i]) bodies[n]![i] = t.rawStmt(real[i]);
      }
    }
    final second = back([]);
    for (final f in funcs.values) {
      if (!same(f.decl.name, second)) allRaw(f);
    }
    final third = back(problems);
    final bad = [
      for (final f in funcs.values)
        if (!same(f.decl.name, third)) f.decl.name,
    ];
    if (bad.isNotEmpty) problems.add('有 ${bad.length} 个函数翻回去和原来的对不上：${bad.join('、')}');

    // 数一数。
    final fns = <BeFromTextFn>[];
    for (final f in funcs.values) {
      final n = f.decl.name;
      var count = 0, rawStmts = 0;
      final raws = <String>[];
      late final void Function(List<dynamic> list) blocks;
      void value(Object? v) {
        if (v is Map) {
          if (v['e'] == kBeRawExpr) {
            raws.add('${v['src']}');
            return;
          }
          final body = v[kLcExprBody];
          if (body is List) blocks(body);
          for (final e in v.entries) {
            if (e.key != kLcExprBody) value(e.value);
          }
        } else if (v is List) {
          v.forEach(value);
        }
      }

      blocks = (list) {
        for (final b in list.cast<Map<String, dynamic>>()) {
          count++;
          if (b['op'] == kBeRawStmt) {
            rawStmts++;
            raws.add('${(b['args'] as Map)['src']}');
            continue;
          }
          value(b['args']);
          for (final key in const ['body', 'else']) {
            if (b[key] is List) blocks(b[key] as List);
          }
          if (b['arms'] is List) {
            for (final a in (b['arms'] as List).cast<Map<String, dynamic>>()) {
              value(a['args']);
              if (a['body'] is List) blocks(a['body'] as List);
            }
          }
        }
      };

      blocks(bodies[n]!);
      fns.add(BeFromTextFn(n, stmts: whole.contains(n) ? trees[n]!.stmtCount : count, rawStmts: whole.contains(n) ? trees[n]!.stmtCount : rawStmts, raws: raws, whole: whole.contains(n)));
    }
    final doc = _parse(docOf(), problems);
    return BeFromTextResult(doc: doc, fns: fns, aliases: {for (final e in aliases.entries) e.key: lcTypeText(head.expand(e.value)) ?? '？'}, renamed: renamed, skipped: skipped, problems: problems);
  }
}

/// 一个模块（文字写法）→ 画布上的库文档。
BeFromTextResult beFromText(String moduleText, {required String id, required String name, required LibSide side}) {
  final LModule module;
  try {
    final text = moduleText.trimLeft();
    // 库的模块文件外面包着一层（模块 名字 …）；也认不包的。
    module = RegExp(r'^(;[^\n]*\n\s*)*\(模块\s').hasMatch(text) ? lcProgram(moduleText).modules.single : lcModule(moduleText);
  } on Object catch (e) {
    return BeFromTextResult(doc: null, fns: const [], aliases: const {}, renamed: 0, skipped: const [], problems: [lcProblemText(e)]);
  }
  return BeFromText(module, id: id, name: name, side: side).run();
}
