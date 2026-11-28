/// 库文档（画布上写的库，见 backend_lib_doc.dart）→ 库的落盘格式：清单 `lib.json`、模块文件 `modules/*.lc`、积木表 `blocks.json`。
/// 出来的东西和应用自带的库是同一种格式，交给同一个读入器（`libRead`）读；这里出完会自己读一遍、查一遍，查不过就不给文件。
///
/// 做法：
/// 1. 库里的函数、类、变量照平时的翻法翻成语法树（backend_to_service.dart），交给写出器（lib/lang/lc_write.dart）写成模块文件；
///    模块名前面带上库的标识（`作者段/库名` 或 `作者段/库名:模块名`），所以两个库的模块不会重名。
/// 2. 公开成积木的定义（[BeLibDef]）写成积木表里的一项。四种办法：调函数、调对象的方法、调类自己的方法、原地展开。
/// 3. “原地展开”的积木：背后那个函数的定义不进模块，而是写成模板——开头先把每个参数存成常量（`(常 参数 (槽 参数))`，
///    所以每个槽只算一次、先算槽再做里面的），后面是函数里的积木；“做口里的积木”写成 `(口 名)`，“交给用的人选的变量”写成 `(放进 结果 式子)`。
///
/// 任何输入都不抛异常：出不来就给一串原因。
library;

import 'dart:convert';

import 'package:lopicode/backend/backend_blocks_typeops.dart';
import 'package:lopicode/backend/backend_func_table.dart';
import 'package:lopicode/backend/backend_function.dart';
import 'package:lopicode/backend/backend_lib_doc.dart';
import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/backend/backend_to_service.dart';
import 'package:lopicode/backend/lib_service.dart';
import 'package:lopicode/lang/ast.dart';
import 'package:lopicode/lang/custom_block.dart';
import 'package:lopicode/lang/lc_write.dart';
import 'package:lopicode/lang/lib_model.dart';
import 'package:lopicode/lang/link.dart';
import 'package:lopicode/lang/rename.dart';
import 'package:lopicode/lang/rules.dart';
import 'package:lopicode/lang/typecheck.dart';
import 'package:lopicode/lowcode/lib_front_builtin.dart';
import 'package:lopicode/lowcode/logic_model.dart';

/// 出库文件的结果：成了是文件表（相对路径 → 内容）和读好的库；不成是一串原因。
typedef BeLibBuilt = ({Map<String, String>? files, LibLibrary? lib, List<String> problems});

/// 调对象的方法的积木上，“哪个对象”那个槽叫什么。
const String kBeLibSelfSlot = '对象';

/// 库文档的画布原件在库文件夹里叫什么（有它才能回到画布上接着改；读入器不看它）。
const String kBeLibSourceFile = 'source/backend.lc.json';

BeLibBuilt _fail(List<String> problems) => (files: null, lib: null, problems: problems);

/// 外观里的字 → 模板里的写法（花括号要写两个）。
String _escapeLook(String text) => text.replaceAll('{', '{{').replaceAll('}', '}}');

/// 积木的外观：从函数 / 方法的外观出发，去掉“不在积木上”的参数的槽，补上“放进变量”槽和口。
CustomBlockLook _look(
  CustomBlockLook base,
  List<String> params,
  bool Function(String param) onBlock, {
  required CustomBlockShape shape,
  bool into = false,
  List<String> mouths = const [],
  List<String> literal = const [],
}) {
  final out = StringBuffer();
  for (final part in parseLookTemplate(base.templateFor(params))) {
    if (!part.isSlot) {
      out.write(_escapeLook(part.text));
    } else if (!params.contains(part.text) || onBlock(part.text)) {
      out.write('{${part.text}}');
    }
  }
  var template = out.toString().replaceAll(RegExp(r' {2,}'), ' ').trim();
  if (into) template = '$template，结果放进 {$kBeLibIntoSlot}';
  for (final m in mouths) {
    template = '$template {$m}';
  }
  return CustomBlockLook(
    base.name,
    shape: shape,
    template: template,
    colorKey: base.colorKey,
    hint: base.hint,
    slots: [
      for (final s in base.slots)
        if (params.contains(s.name) && onBlock(s.name) && !literal.contains(s.name)) s,
    ],
  );
}

/// 原地展开的积木，定义里用到的库里的函数、类、模块级变量都算公开：展开以后那几句是在用的人的程序里跑的，得看得见它们。
void _publishUsed(BeDocument doc, BeFunction f) {
  final core = doc.core;
  void value(Object? v, int depth) {
    if (depth > 64) return;
    if (v is List) {
      for (final x in v) {
        value(x, depth + 1);
      }
      return;
    }
    if (v is! Map) return;
    final e = v['e'];
    if (e is String) {
      final callee = beCallId(e);
      if (callee != null) core.publics.add(callee);
      if (e == 'funcRef' && v['fn'] is String) core.publics.add(v['fn'] as String);
      if (e == 'var' && v['name'] is String) {
        final g = core.global(v['name'] as String);
        if (g != null) core.publics.add(g.key);
      }
    }
    for (final key in const ['type', 'kind']) {
      final name = v[key];
      final t = name is String ? core.types.where((t) => t.name == name).firstOrNull : null;
      if (t != null) core.publics.add(t.id);
    }
    for (final x in v.values) {
      value(x, depth + 1);
    }
  }

  f.visitBlocks((b, _) {
    final callee = beCallId(b.op);
    if (callee != null) core.publics.add(callee);
    final name = b.args['name'];
    final g = name is String ? core.global(name) : null;
    if (g != null) core.publics.add(g.key);
    value(b.args, 0);
    for (final a in b.arms) {
      value(a.args, 0);
    }
  });
}

/// 有没有哪里把这个函数当普通函数调了（`call:<id>`）；返回那几处所在的串的名字。
List<String> _callers(BeDocument doc, String fnId) {
  final op = beCallOp(fnId);
  final out = <String>[];
  bool inValue(Object? v, int depth) {
    if (depth > 64) return false;
    if (v is Map) return v['e'] == op || v['fn'] == fnId && v['e'] == 'funcRef' || v.values.any((x) => inValue(x, depth + 1));
    if (v is List) return v.any((x) => inValue(x, depth + 1));
    return false;
  }

  void tree(LcBlockTree t, String name) {
    var hit = false;
    t.visitBlocks((b, _) {
      if (b.op == op || inValue(b.args, 0) || b.arms.any((a) => inValue(a.args, 0))) hit = true;
    });
    if (hit) out.add(name);
  }

  for (final f in doc.functions) {
    tree(f, f.name);
  }
  for (final t in doc.core.types) {
    for (final m in t.trees) {
      tree(m, '${t.name}.${m.name}');
    }
  }
  return out;
}

/// 库文档 → 库文件。
BeLibBuilt beLibFiles(BeDocument source) {
  final info = source.library;
  if (info == null) return _fail(const ['这份文档不是一个库']);
  final problems = <String>[];
  if (!langRulesStrict(source.rules)) problems.add('库只能照严格规矩写');
  if (!kLibIdPattern.hasMatch(info.id)) problems.add('库的标识要写成“作者段/库名”（小写字母、数字、连字符，字母开头）');
  if (beLibAuthorReserved(info.id.split('/').first)) problems.add('作者段 lopi、local 是应用自己留着用的，换一个');
  if (source.routes.isNotEmpty) problems.add('库里不能有接口（“当收到请求”那种串）：接口写在用这个库的文档里');
  if (source.hats.isNotEmpty) problems.add('库里不能有以别的库的帽子开头的串');
  if ((source.core.main?.body ?? const []).isNotEmpty) problems.add('库里不能有“程序开始时”：要在启动时做的事包成一个公开的函数，让用它的文档来调');
  if (problems.isNotEmpty) return _fail(problems);
  try {
    return _build(source, info, problems);
  } on LcWriteProblem catch (e) {
    return _fail([...problems, e.what]);
  } on Object catch (e) {
    return _fail([...problems, '库存不了（$e）']);
  }
}

BeLibBuilt _build(BeDocument source, BeLibInfo info, List<String> problems) {
  // 公开成积木的定义，背后的函数 / 类一定得是公开的。
  final doc = source.clone();
  final core = doc.core;
  final seen = <String>{};
  for (final d in info.blocks) {
    if (!seen.add(d.id)) problems.add('积木编号「${d.id}」用了两次');
    if (d.how == LibHow.call || d.how == LibHow.expand) {
      final f = doc.function(d.fn);
      if (f == null) {
        problems.add('积木「${d.id}」背后的函数已经不在了');
      } else if (d.how == LibHow.call) {
        core.publics.add(f.id);
      } else {
        core.publics.remove(f.id);
        _publishUsed(doc, f);
        final callers = _callers(doc, f.id);
        if (callers.contains(f.name)) {
          problems.add('积木「${f.name}」是原地展开的，它的定义里又用了它自己（递归展开）：这样永远展不完。改成“调函数”的办法，或者把重复的部分换成循环');
        } else if (callers.isNotEmpty) {
          problems.add('积木「${f.name}」是原地展开的，不能在库里当函数来调（${callers.join('、')} 里调了它）。要在库里用，另写一个普通函数');
        }
      }
    } else {
      final t = core.type(d.typeId);
      final m = t?.methods.where((m) => m.id == d.method).firstOrNull;
      if (t == null || m == null) {
        problems.add('积木「${d.id}」背后的类或方法已经不在了');
      } else {
        core.publics.add(t.id);
        if ((d.how == LibHow.static) != m.isStatic) problems.add('积木「${d.id}」：方法「${m.name}」${m.isStatic ? '是类自己的方法，办法要选“调类自己的方法”' : '要有对象才能调，办法要选“调对象的方法”'}');
      }
    }
  }
  final names = <String>{};
  for (final f in doc.functions) {
    if (!names.add(f.ident)) problems.add('库里有两个函数都叫「${f.name}」（重名）：给其中一个换个名字');
  }
  if (problems.isNotEmpty) return _fail(problems);

  final built = beServiceBuild(doc);
  final program = built.program;
  if (program == null || built.problems.isNotEmpty) return _fail([...problems, ...built.problems, if (program == null && built.problems.isEmpty) '积木翻不成语法树']);
  if (built.holes.isNotEmpty) return _fail([for (final h in built.holes.toSet()) '有没填好的地方（$h）']);
  final theirs = {for (final l in built.libs) ...l.moduleNames};
  final own = [
    for (final m in program.modules)
      if (!theirs.contains(m.name)) m,
  ];
  String rename(String m) => m == program.entry ? info.id : '${info.id}:$m';
  final ownNames = {for (final m in own) m.name};
  final expandFns = {
    for (final d in info.blocks)
      if (d.how == LibHow.expand) doc.function(d.fn)!.ident: d,
  };

  // 库里用了别的库的积木：展开出来的名字带着“是哪个模块的”记号（lQualified），落盘前去掉——库的模块靠“用到了谁”去找它们。
  final plain = LRenamer((n) => n.contains(kLQualifiedMark) ? n.substring(n.indexOf(kLQualifiedMark) + 1) : n);
  final files = <String, String>{};
  final moduleEntries = <Map<String, String>>[];
  final moduleOf = <String, String>{};
  final types = <Map<String, String>>[];
  final writer = LcWriter();
  var n = 0;
  for (final m in own) {
    final decls = plain.decls([
      for (final d in m.decls)
        if (!(d is LFuncDecl && expandFns.containsKey(d.name))) d,
    ]);
    for (final d in m.decls) {
      moduleOf[d.name] = rename(m.name);
    }
    if (decls.isEmpty) continue;
    final name = rename(m.name);
    for (final d in decls) {
      final public = switch (d) {
        LClassDecl() => d.isPublic,
        LInterfaceDecl() => d.isPublic,
        LTypeDecl() => d.isPublic,
        _ => false,
      };
      if (public) types.add({'name': d.name, 'module': name});
    }
    final uses = [
      for (final u in m.uses)
        if (ownNames.contains(u)) rename(u) else u,
    ];
    final file = 'modules/m${++n}.lc';
    files[file] = writer.module(LModule(name: name, uses: uses, decls: decls));
    moduleEntries.add({'file': file, 'name': name});
  }
  if (moduleEntries.isEmpty) {
    // 只有原地展开的积木、没有别的定义：留一个空模块，积木表才有地方挂。
    files['modules/m1.lc'] = writer.module(LModule(name: info.id));
    moduleEntries.add({'file': 'modules/m1.lc', 'name': info.id});
  }

  final table = BeFuncTable(doc);
  final blocks = <Map<String, Object?>>[];
  for (final d in info.blocks) {
    final got = _block(doc, info, d, table, built, moduleOf, problems, plain);
    if (got != null) blocks.add(got);
  }
  if (problems.isNotEmpty) return _fail(problems);

  final requires = [
    if (built.service) kBeServiceLibId,
    for (final l in built.libs)
      // 自带库里，自动带上的（“页面”）不用写；要用才用的那五个前端库要写，用这个库的文档才知道得把它们也用上。
      if (!l.builtin || lcIsFrontOptional(l.id)) l.id,
  ];
  files[kLibManifestFile] = const JsonEncoder.withIndent('  ').convert({
    'kind': kLibKind,
    'format': kLibFormat,
    'id': info.id,
    'name': doc.name,
    'version': info.version,
    if (info.author.isNotEmpty) 'author': info.author,
    if (info.summary.isNotEmpty) 'summary': info.summary,
    'rules': 2,
    if (info.side != LibSide.backend) 'for': info.side.name,
    'native': {'allowed': false},
    // 库里“调宿主接口”用到的接口，一个不落地写明（读库的时候会对）。
    if (beHostsUsed(doc).isNotEmpty) 'hosts': beHostsUsed(doc)..sort(),
    if (requires.isNotEmpty) 'requires': requires,
    'modules': moduleEntries,
    'blocks': ['blocks.json'],
    if (types.isNotEmpty) 'types': types,
    if (info.settings.isNotEmpty) 'settings': [for (final s in info.settings) beLibSettingToJson(s)],
    if (info.originId.isNotEmpty) 'origin': {'id': info.originId, 'version': info.originVersion},
  });
  files['blocks.json'] = const JsonEncoder.withIndent('  ').convert({'blocks': blocks});

  // 自己读一遍、和它靠的库放在一起查一遍：查不过就不给。
  final lib = libRead(files, builtin: false);
  if (!lib.ok) return _fail(lib.problems);
  final checked = beLibCheckWith(lib, built.libs);
  if (checked.isNotEmpty) return _fail(checked);
  return (files: files, lib: lib, problems: const []);
}

/// 一个库和它靠的库（[others]）放在一起：模块之间的规矩、类型检查。返回问题（空＝没问题）。
List<String> beLibCheckWith(LibLibrary lib, List<LibLibrary> others) {
  final deps = [
    for (final l in others)
      if (l.id != lib.id) l,
  ];
  final all = [...deps, lib];
  final (linked, checked) = checkProgramTypes(
    LProgram([
      for (final l in all) ...l.modules,
      LModule(name: 'main', uses: [for (final l in all) ...l.moduleNames]),
    ], entry: 'main'),
  );
  return [
    for (final i in linked.issues) i.message,
    if (checked != null)
      for (final i in checked.errors) '${i.where}：${i.message}',
  ];
}

Object _arg(String param, BeLibParam? p) => switch (p?.from) {
  BeLibFrom.context => {'context': p!.key},
  BeLibFrom.setting => {'setting': p!.key},
  BeLibFrom.preset => {'preset': p!.value},
  _ => param,
};

Map<String, Object?>? _block(BeDocument doc, BeLibInfo info, BeLibDef d, BeFuncTable table, BeServiceBuilt built, Map<String, String> moduleOf, List<String> problems, LRenamer plain) {
  void bad(String why) => problems.add('积木「${d.look?.name ?? d.id}」：$why');
  final List<BeParam> params;
  final CustomBlockLook base;
  final String of, module;
  CustomBlockShape shape;
  BeFunction? fn;
  var self = false;
  if (d.how == LibHow.call || d.how == LibHow.expand) {
    fn = doc.function(d.fn)!;
    params = fn.params;
    base = d.look ?? fn.look;
    of = fn.ident;
    module = moduleOf[fn.ident] ?? info.id;
    shape = d.shape ?? (d.how == LibHow.expand ? CustomBlockShape.statement : table.shapeOf(fn));
  } else {
    final t = doc.core.type(d.typeId)!;
    final m = t.methods.firstWhere((m) => m.id == d.method);
    params = m.params;
    self = d.how == LibHow.method;
    base =
        d.look ??
        CustomBlockLook('${t.name}.${m.name}', template: '${self ? '{$kBeLibSelfSlot} ' : '${_escapeLook(t.name)} '}${_escapeLook(m.name)}${[for (final p in m.params) ' {${p.name}}'].join()}');
    of = self ? m.name : '${t.name}.${m.name}';
    module = moduleOf[t.name] ?? info.id;
    shape = d.shape ?? (m.returns == null || m.returns!.isNul ? CustomBlockShape.statement : CustomBlockShape.value);
  }
  final isValue = shape == CustomBlockShape.value || shape == CustomBlockShape.boolean;
  if (d.into && isValue) shape = CustomBlockShape.statement;
  if (d.how == LibHow.expand && (isValue || shape == CustomBlockShape.auto)) {
    bad('原地展开的积木只能是语句、帽子或收尾型；要一个值，办法选“调函数”');
    return null;
  }
  if (d.how != LibHow.expand && (d.mouths.isNotEmpty || d.provides.isNotEmpty || shape == CustomBlockShape.hat)) {
    bad('带口、带帽子、给口里递东西的积木，办法要选“原地展开”');
    return null;
  }
  final names = [for (final p in params) p.name];
  for (final p in params) {
    if (p.rest) bad('参数「${p.name}」是“剩下的全收”，公开成积木的定义不能有这种参数');
  }
  for (final k in d.params.keys) {
    if (!names.contains(k)) bad('“参数从哪来”里写了定义没有的参数「$k」');
  }
  final reserved = {if (d.into) kBeLibIntoSlot, if (self) kBeLibSelfSlot, ...d.mouths};
  for (final r in reserved) {
    if (names.contains(r)) bad('参数不能叫「$r」（积木上已经有一个叫这个名字的槽）');
  }
  if (d.mouths.toSet().length != d.mouths.length) bad('两个口不能同名');
  final needs = <String>{};
  for (final p in params) {
    final from = d.params[p.name];
    if (from?.from == BeLibFrom.context) {
      if (from!.key.isEmpty) bad('参数「${p.name}」说是隐含的东西，可是没写是哪样');
      needs.add(from.key);
    }
    if (from?.from == BeLibFrom.setting && info.settings.every((s) => s.id != from!.key)) bad('参数「${p.name}」说用设置项「${from!.key}」，库里没有这个设置项');
  }
  bool onBlock(String p) => d.params[p]?.onBlock ?? true;
  final literal = [
    for (final p in names)
      if (d.params[p]?.from == BeLibFrom.literal) p,
  ];
  final look = _look(
    base,
    [if (self) kBeLibSelfSlot, ...names],
    (p) => p == kBeLibSelfSlot || onBlock(p),
    shape: shape,
    into: d.into,
    mouths: d.how == LibHow.expand ? d.mouths : const [],
    literal: literal,
  );
  // 外观上要有每一个“在积木上”的参数的槽。
  final slots = {
    for (final p in parseLookTemplate(look.template))
      if (p.isSlot) p.text,
  };
  for (final p in [if (self) kBeLibSelfSlot, ...names.where(onBlock)]) {
    if (!slots.contains(p)) bad('积木的文字里没有参数「$p」的槽（写成 {$p}）');
  }
  final seen = <String>{};
  for (final p in parseLookTemplate(look.template)) {
    if (p.isSlot && !seen.add(p.text)) bad('积木的文字里「${p.text}」这个槽写了两次，只留一个');
  }
  final out = <String, Object?>{
    'id': d.id,
    'module': module,
    'how': d.how.name,
    'look': look.toJson(),
    if (needs.isNotEmpty) 'needs': needs.toList(),
    'slotKinds': {
      for (final p in literal) p: LibSlotKind.literal.name,
      if (d.into) kBeLibIntoSlot: LibSlotKind.assign.name,
      if (d.how == LibHow.expand)
        for (final m in d.mouths) m: LibSlotKind.mouth.name,
    },
  };
  if (d.how != LibHow.expand) {
    out['of'] = of;
    out['args'] = [if (self) kBeLibSelfSlot, for (final p in names) _arg(p, d.params[p])];
    if (d.into) out['into'] = kBeLibIntoSlot;
    return out;
  }
  // 原地展开：函数的定义写成模板。
  final found = built.decls.where((x) => x.key == fn!.id).firstOrNull?.decl;
  final decl = found == null ? null : plain.decl(found);
  if (decl is! LFuncDecl) {
    bad('它的定义翻不出来');
    return null;
  }
  late final LcWriter w;
  w = LcWriter(
    stmtHook: (s) {
      final e = s is LExprStmt ? s.expr : null;
      if (e is! LNative) return null;
      if (e.name == kBeLibMouthMark) {
        final arg = e.args.firstOrNull;
        final name = arg is LLit && arg.value is String ? arg.value as String : '';
        if (!d.mouths.contains(name)) throw LcWriteProblem('积木「${look.name}」的定义里有一块“做口里的积木”，指的口「$name」这块积木上没有');
        return '(口 ${w.token(name)})';
      }
      if (e.name == kBeLibPutMark) {
        if (!d.into) throw LcWriteProblem('积木「${look.name}」的定义里用了“交给用的人选的变量”，可是这块积木没有打开“放进变量”那个槽');
        return '(放进 $kBeLibIntoSlot ${w.expr(e.args.first)})';
      }
      return null;
    },
  );
  final lines = <String>[];
  for (final p in params) {
    final from = d.params[p.name];
    final value = switch (from?.from) {
      BeLibFrom.context => '(隐含 ${w.token(from!.key)})',
      BeLibFrom.setting => '(设置 ${w.token(from!.key)})',
      BeLibFrom.preset => lcWriteLiteral(from!.value),
      _ => '(槽 ${w.token(p.name)})',
    };
    final t = p.type;
    lines.add('(常 ${w.name(beIdent(p.name))}${t == null ? '' : ' ${w.type(t)}'} $value)');
  }
  final body = w.block(decl.body, '').trim();
  if (body.isNotEmpty) lines.add(body);
  out['expand'] = lines.join('\n');
  if (d.provides.isNotEmpty) out['provides'] = d.provides;
  return out;
}
