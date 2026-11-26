/// 核心 2 的东西怎么改（积木第 5 版·核心 2·A3）：加 / 删 / 改名类型、字段、情况、方法；模块、模块顶上的变量。
///
/// 纯数据，不碰界面、不管撤销（宿主的 `edit` 管）。每个函数：改成了返回 null；不能改返回一句给人看的原因，文档一个字不动。
/// 改名会把积木里用到这个名字的地方一起改（能确定是它的才改；见各函数的说明）。
library;

import 'package:lopicode/backend/backend_blocks.dart';
import 'package:lopicode/backend/backend_blocks_core.dart';
import 'package:lopicode/backend/backend_core.dart';
import 'package:lopicode/backend/backend_core_fix.dart';
import 'package:lopicode/backend/backend_function.dart';
import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/lang/errors.dart';
import 'package:lopicode/lang/types.dart';
import 'package:lopicode/lowcode/logic_model.dart';

/// 名字能不能用：合规矩、不和内置的错误种类重名。[taken]＝同一层里已经有的名字。
String? beCoreNameProblem(String name, Iterable<String> taken, {String what = '名字'}) {
  if (name.isEmpty) return '$what不能是空的';
  if (!beCoreNamePattern.hasMatch(name)) return '$what只能用汉字、英文字母、数字和下划线，不能用数字开头，最多 32 个字';
  if (taken.contains(name)) return '已经有一个叫「$name」的了';
  return null;
}

Set<String> _typeNames(BeDocument doc) => {...kErrBuiltinNames, for (final t in doc.core.types) t.name, for (final f in doc.functions) f.ident};

Set<String> _ids(BeDocument doc) => {for (final r in doc.routes) r.id, for (final f in doc.functions) f.id};

String _freeName(String base, Set<String> taken) {
  if (!taken.contains(base)) return base;
  var n = 2;
  while (taken.contains('$base$n')) {
    n++;
  }
  return '$base$n';
}

/// 新建一个类型（名字自动起：记录、记录2…）。满了返回 null。
BeTypeDef? beAddType(BeDocument doc, BeTypeKind kind) {
  final core = doc.core;
  if (core.types.length >= kBeMaxTypes) return null;
  final name = _freeName(kind == BeTypeKind.error ? '我的错误' : '我的${kind.label}', _typeNames(doc));
  final t = BeTypeDef(
    id: core.freeId('t', _ids(doc)),
    kind: kind,
    name: name,
    parent: kind == BeTypeKind.error ? kErrBase : null,
    fields: [if (kind == BeTypeKind.record) BeField('名字', LType.text)],
    cases: [if (kind == BeTypeKind.enumeration || kind == BeTypeKind.variant) BeCase('情况1', []), if (kind == BeTypeKind.enumeration) BeCase('情况2', [])],
  );
  core.types.add(t);
  core.moduleOf(t.id)?.owns.add(t.id);
  return t;
}

/// 所有积木串（接口、“我的积木”、类的方法、“程序开始时”）。
List<LcBlockTree> beAllTrees(BeDocument doc) => [...doc.routes, ...doc.functions, ...doc.core.trees];

/// 把文档里每一个值（积木的参数、段的参数、值里面套的值）走一遍；[blocks] 另外看每一块积木。
void _visit(BeDocument doc, void Function(Map<dynamic, dynamic> expr) expr, [void Function(LcBlock b)? blocks]) {
  void value(Object? v, int depth) {
    if (depth > kMaxExprDepth * 2 + 8 || v is List<LcBlock>) return;
    if (v is List) {
      for (final x in v) {
        value(x, depth + 1);
      }
    } else if (v is Map) {
      if (v['e'] is String) expr(v);
      for (final x in v.values) {
        value(x, depth + 1);
      }
    }
  }

  for (final tree in beAllTrees(doc)) {
    tree.visitBlocks((b, _) {
      blocks?.call(b);
      for (final v in [...b.args.values, for (final a in b.arms) ...a.args.values]) {
        value(v, 0);
      }
    });
  }
  for (final t in doc.core.types) {
    for (final f in t.fields) {
      value(f.init, 0);
    }
  }
  for (final g in doc.core.globals) {
    value(g.init, 0);
  }
}

LType _retype(LType t, String from, String to) {
  if (t.name == from) return LType.ref(to, args: t.args, nullable: t.nullable);
  return t;
}

/// 改类型的名字：继承它的、实现它的、字段 / 参数标成它的、积木里选了它的，一起改。
String? beRenameType(BeDocument doc, String id, String name) {
  final core = doc.core;
  final t = core.type(id);
  if (t == null) return '这个类型已经不在了';
  final to = name.trim();
  if (to == t.name) return null;
  final bad = beCoreNameProblem(to, _typeNames(doc));
  if (bad != null) return bad;
  final from = t.name;
  t.name = to;
  for (final o in core.types) {
    if (o.parent == from) o.parent = to;
    for (var i = 0; i < o.interfaces.length; i++) {
      if (o.interfaces[i] == from) o.interfaces[i] = to;
    }
    for (final f in [...o.fields, for (final c in o.cases) ...c.fields]) {
      f.type = _retype(f.type, from, to);
    }
    for (final m in [?o.ctor, ...o.methods]) {
      for (final p in m.params) {
        if (p.type != null) p.type = _retype(p.type!, from, to);
      }
      if (m.returns != null) m.returns = _retype(m.returns!, from, to);
    }
  }
  for (final g in core.globals) {
    if (g.type != null) g.type = _retype(g.type!, from, to);
  }
  for (final f in doc.functions) {
    for (final p in f.params) {
      if (p.type != null) p.type = _retype(p.type!, from, to);
    }
    if (f.returns != null) f.returns = _retype(f.returns!, from, to);
  }
  _visit(
    doc,
    (e) {
      if (beIsCoreExpr(e['e'])) {
        if (e['type'] == from) e['type'] = to;
        if (e['e'] == 'errNew' && e['kind'] == from) e['kind'] = to;
      }
    },
    (b) {
      if (b.op != 'try') return;
      for (final a in b.arms) {
        if (a.args['kind'] == from) a.args['kind'] = to;
      }
    },
  );
  return null;
}

/// 删一个类型。还有别的类型继承 / 实现它、或积木里还在用它，照删（那些地方会标红，人自己换）。
String? beRemoveType(BeDocument doc, String id) {
  final core = doc.core;
  final t = core.type(id);
  if (t == null) return '这个类型已经不在了';
  core.types.remove(t);
  core.publics.remove(id);
  for (final m in core.modules) {
    m.owns.remove(id);
  }
  return null;
}

/// 这个类型里已经占了的成员名字（字段、方法、情况）。
Set<String> beMemberNames(BeTypeDef t) => {for (final f in t.fields) f.name, for (final m in t.methods) m.name, for (final c in t.cases) c.name};

/// 加一个字段（[toCase] 给了＝加到变体的那种情况里）。
String? beAddField(BeDocument doc, String typeId, {String? toCase}) {
  final t = doc.core.type(typeId);
  if (t == null) return '这个类型已经不在了';
  final list = toCase == null ? t.fields : t.cases.where((c) => c.name == toCase).firstOrNull?.fields;
  if (list == null) return '这种情况已经不在了';
  if (list.length >= kBeMaxMembers) return '最多 $kBeMaxMembers 个';
  final taken = toCase == null ? beMemberNames(t) : {for (final f in list) f.name};
  list.add(BeField(_freeName('字段${list.length + 1}', taken), LType.text));
  return null;
}

/// 这个名字在所有类型里是不是只有 [t] 有（改名时才敢顺手改积木里按名字选的地方）。
bool _onlyIn(BeDocument doc, BeTypeDef t, String member) => !doc.core.types.any((o) => o != t && (beMemberNames(o).contains(member) || o.cases.any((c) => c.fields.any((f) => f.name == member))));

/// 改字段的名字。新建记录 / 错误里写着这个类型的那些字段跟着改；“读字段”“改字段”里按名字选的，只有这个名字是这个类型独有的才跟着改。
String? beRenameField(BeDocument doc, String typeId, String from, String name, {String? inCase}) {
  final t = doc.core.type(typeId);
  final list = inCase == null ? t?.fields : t?.cases.where((c) => c.name == inCase).firstOrNull?.fields;
  final f = list?.where((f) => f.name == from).firstOrNull;
  if (t == null || list == null || f == null) return '这个字段已经不在了';
  final to = name.trim();
  if (to == from) return null;
  final bad = beCoreNameProblem(to, inCase == null ? beMemberNames(t) : {for (final x in list) x.name});
  if (bad != null) return bad;
  final unique = _onlyIn(doc, t, from);
  f.name = to;
  if (inCase != null) return null;
  _visit(
    doc,
    (e) {
      final own = (e['e'] == 'recNew' && e['type'] == t.name) || (e['e'] == 'errNew' && e['kind'] == t.name);
      if (own || (unique && e['e'] == 'recCopy')) {
        final fields = e['fields'];
        if (fields is List) {
          for (final p in fields) {
            if (p is Map && p['key'] == from) p['key'] = to;
          }
        }
      }
      if (unique && e['e'] == 'getField' && e['name'] == from) e['name'] = to;
    },
    (b) {
      if (unique && b.op == 'setField' && b.args['name'] == from) b.args['name'] = to;
    },
  );
  return null;
}

String? beRemoveField(BeDocument doc, String typeId, String name, {String? inCase}) {
  final t = doc.core.type(typeId);
  final list = inCase == null ? t?.fields : t?.cases.where((c) => c.name == inCase).firstOrNull?.fields;
  if (list == null) return '这个类型已经不在了';
  list.removeWhere((f) => f.name == name);
  return null;
}

/// 加一种情况。
String? beAddCase(BeDocument doc, String typeId) {
  final t = doc.core.type(typeId);
  if (t == null) return '这个类型已经不在了';
  if (t.cases.length >= kBeMaxMembers) return '最多 $kBeMaxMembers 种情况';
  t.cases.add(BeCase(_freeName('情况${t.cases.length + 1}', beMemberNames(t)), []));
  return null;
}

/// 改情况的名字：选了这个类型的“枚举的值”“造一种情况”跟着改；“看是哪种情况”的段，只有这个名字是这个类型独有的才跟着改。
String? beRenameCase(BeDocument doc, String typeId, String from, String name) {
  final t = doc.core.type(typeId);
  final c = t?.cases.where((c) => c.name == from).firstOrNull;
  if (t == null || c == null) return '这种情况已经不在了';
  final to = name.trim();
  if (to == from) return null;
  final bad = beCoreNameProblem(to, beMemberNames(t));
  if (bad != null) return bad;
  final unique = _onlyIn(doc, t, from);
  c.name = to;
  _visit(
    doc,
    (e) {
      if ((e['e'] == 'enumVal' || e['e'] == 'varNew') && e['type'] == t.name && e['case'] == from) e['case'] = to;
    },
    (b) {
      if (!unique || b.op != 'match') return;
      for (final a in b.arms) {
        if (a.args['case'] == from) a.args['case'] = to;
      }
    },
  );
  return null;
}

String? beRemoveCase(BeDocument doc, String typeId, String name) {
  final t = doc.core.type(typeId);
  if (t == null) return '这个类型已经不在了';
  if (t.cases.length <= 1) return '至少要留一种情况';
  t.cases.removeWhere((c) => c.name == name);
  return null;
}

/// 类的父类里，哪些方法它还能“照抄签名”来重写；接口要它实现的也算。返回 (方法, 从哪儿来的说明)。
List<(BeMethod, String)> beInheritable(BeCore core, BeTypeDef t) {
  final out = <(BeMethod, String)>[];
  final seen = {for (final m in t.methods) m.name};
  for (final c in [t, ...core.parentsOf(t)]) {
    for (final i in c.interfaces.map(core.typeNamed).nonNulls) {
      for (final m in i.methods) {
        if (seen.add(m.name)) out.add((m, '接口「${i.name}」要的'));
      }
    }
    if (c == t) continue;
    for (final m in c.methods) {
      if (!m.isStatic && seen.add(m.name)) out.add((m, '重写父类「${c.name}」的'));
    }
  }
  return out;
}

/// 加一个方法；[like] 给了＝照抄它的签名（名字、参数连默认值、交回什么）。接口的方法没有积木，只是一行签名。
BeMethod? beAddMethod(BeDocument doc, String typeId, {BeMethod? like, double? x, double? y}) {
  final core = doc.core;
  final t = core.type(typeId);
  if (t == null || (t.kind != BeTypeKind.klass && t.kind != BeTypeKind.interface) || t.methods.length >= kBeMaxMembers) return null;
  final name = like != null && !beMemberNames(t).contains(like.name) ? like.name : _freeName('方法${t.methods.length + 1}', beMemberNames(t));
  final m = BeMethod(id: core.freeId('m', _ids(doc)), name: name, params: [for (final p in like?.params ?? const <BeParam>[]) p.clone()], returns: like?.returns, x: x, y: y);
  t.methods.add(m);
  return m;
}

/// 加“创建时”。父类的“创建时”要参数的话，第一句自动放好“调父类的创建时”。
BeMethod? beAddCtor(BeDocument doc, String typeId, {double? x, double? y}) {
  final core = doc.core;
  final t = core.type(typeId);
  if (t == null || t.kind != BeTypeKind.klass || t.ctor != null) return null;
  final m = t.ctor = BeMethod(id: core.freeId('m', _ids(doc)), name: kBeCtorName, x: x, y: y);
  beEnsureSuperInit(core, t);
  return m;
}

/// 改方法的名字（“对象的方法”“让对象做”里按名字选的，只有这个名字是这个类型独有的才跟着改）。
String? beRenameMethod(BeDocument doc, String treeId, String name) {
  final t = doc.core.types.where((t) => t.methods.any((m) => m.id == treeId)).firstOrNull;
  final m = t?.methods.where((m) => m.id == treeId).firstOrNull;
  if (t == null || m == null) return '这个方法已经不在了';
  final to = name.trim();
  if (to == m.name) return null;
  final bad = beCoreNameProblem(to, beMemberNames(t));
  if (bad != null) return bad;
  final from = m.name;
  final unique = _onlyIn(doc, t, from) && !doc.core.types.any((o) => o != t && o.parent == t.name);
  m.name = to;
  if (!unique) return null;
  _visit(
    doc,
    (e) {
      if (e['e'] == 'callMethod' && e['name'] == from) e['name'] = to;
    },
    (b) {
      if (b.op == 'callMethodStmt' && b.args['name'] == from) b.args['name'] = to;
    },
  );
  return null;
}

/// 给方法 / “创建时”加一个参数（名字自动起：p1、p2…）。
String? beAddParam(BeDocument doc, String treeId) {
  final m = beMethodById(doc, treeId);
  if (m == null) return '这个方法已经不在了';
  if (m.params.length >= kBeMaxParams) return '参数最多 $kBeMaxParams 个';
  m.params.add(BeParam(_freeName('p${m.params.length + 1}', {for (final p in m.params) p.name})));
  return null;
}

/// 接口里的方法只是一行签名，不算一串积木：按 id 找它。
BeMethod? _signature(BeDocument doc, String id) => doc.core.types.expand((t) => t.methods).where((m) => m.id == id).firstOrNull;

/// 方法 / “创建时”（接口的方法签名也算）。
BeMethod? beMethodById(BeDocument doc, String id) => doc.core.tree(id) ?? _signature(doc, id);

/// 改参数的名字；这个方法里读它的地方一起改。
String? beRenameParam(BeDocument doc, String treeId, String from, String name) {
  final m = beMethodById(doc, treeId);
  final p = m?.params.where((p) => p.name == from).firstOrNull;
  if (m == null || p == null) return '这个参数已经不在了';
  final to = name.trim();
  if (to == from) return null;
  if (!beNamePattern.hasMatch(to) || beParamNameReserved(to)) return '参数名要用英文字母、数字、下划线，不能用数字开头';
  if (m.params.any((x) => x.name == to)) return '已经有一个叫「$to」的参数了';
  p.name = to;
  void value(Object? v, int depth) {
    if (depth > kMaxExprDepth * 2 + 8 || v is List<LcBlock>) return;
    if (v is List) {
      for (final x in v) {
        value(x, depth + 1);
      }
    } else if (v is Map) {
      if ((v['e'] == 'param' || v['e'] == 'var') && v['name'] == from) v['name'] = to;
      for (final x in v.values) {
        value(x, depth + 1);
      }
    }
  }

  m.visitBlocks((b, _) {
    for (final v in [...b.args.values, for (final a in b.arms) ...a.args.values]) {
      value(v, 0);
    }
  });
  return null;
}

/// 删一串：方法、“创建时”、“程序开始时”。删了返回 true。
bool beRemoveCoreTree(BeDocument doc, String treeId) {
  final core = doc.core;
  if (core.main?.id == treeId) {
    core.main = null;
    return true;
  }
  for (final t in core.types) {
    if (t.ctor?.id == treeId) {
      t.ctor = null;
      return true;
    }
    final before = t.methods.length;
    t.methods.removeWhere((m) => m.id == treeId);
    if (t.methods.length != before) return true;
  }
  return false;
}

/// 设父类（null＝不继承）。子类有“创建时”、父类的“创建时”要参数：自动放好“调父类的创建时”。
String? beSetParent(BeDocument doc, String typeId, String? parent) {
  final core = doc.core;
  final t = core.type(typeId);
  if (t == null) return '这个类型已经不在了';
  if (parent != null) {
    final up = core.typeNamed(parent);
    if (up == null && !langIsBuiltinError(parent)) return '没有叫「$parent」的类';
    if (up != null && (up == t || core.parentsOf(up).contains(t))) return '「$parent」本来就是从「${t.name}」继承来的，不能绕成一圈';
  }
  t.parent = parent;
  beEnsureSuperInit(core, t);
  return null;
}

// —— 模块顶上的变量 ——

String? beAddGlobal(BeDocument doc) {
  final core = doc.core;
  if (core.globals.length >= kBeMaxMembers) return '最多 $kBeMaxMembers 个';
  final taken = {for (final g in core.globals) g.name, for (final v in doc.variables) v.name};
  var n = core.globals.length + 1;
  while (taken.contains('v$n')) {
    n++;
  }
  final g = BeGlobal('v$n', {'e': 'num', 'v': 0});
  core.globals.add(g);
  core.moduleOf(g.key)?.owns.add(g.key);
  return null;
}

void _rekey(BeCore core, String from, String to) {
  if (core.publics.remove(from)) core.publics.add(to);
  for (final m in core.modules) {
    if (m.owns.remove(from)) m.owns.add(to);
  }
}

/// 改模块顶上变量的名字（要能当变量名：英文字母、数字、下划线）。积木里读、写这个名字的地方不跟着改——
/// 分不清那是它还是哪一串里同名的局部变量；改完会标红，人自己换。
String? beRenameGlobal(BeDocument doc, String from, String name) {
  final core = doc.core;
  final g = core.global(from);
  if (g == null) return '这个变量已经不在了';
  final to = name.trim();
  if (to == from) return null;
  if (!beNamePattern.hasMatch(to)) return '变量的名字只能用英文字母、数字和下划线，不能用数字开头，最多 32 个字符';
  if (core.global(to) != null || doc.variable(to) != null) return '已经有一个叫「$to」的了';
  final was = g.key;
  g.name = to;
  _rekey(core, was, g.key);
  return null;
}

void beRemoveGlobal(BeDocument doc, String name) {
  final core = doc.core;
  core.globals.removeWhere((g) => g.name == name);
  _rekey(core, 'g:$name', '');
  core.publics.remove('');
  for (final m in core.modules) {
    m.owns.remove('');
  }
}

// —— 模块 ——

/// 文档里能归到模块里的东西：(键, 给人看的名字, 是哪一种)。
List<({String key, String name, String what})> beModuleItems(BeDocument doc) => [
  for (final t in doc.core.types) (key: t.id, name: t.name, what: t.kind.label),
  for (final f in doc.functions) (key: f.id, name: f.name, what: '我的积木'),
  for (final g in doc.core.globals) (key: g.key, name: g.name, what: g.isConst ? '常量' : '变量'),
];

/// 新建一个模块。第一次建的时候，文档里原有的东西都归到它名下，它就是入口。
String? beAddModule(BeDocument doc) {
  final core = doc.core;
  if (core.modules.length >= kBeMaxModules) return '最多 $kBeMaxModules 个模块';
  final m = BeModule(_freeName(core.modules.isEmpty ? '主模块' : '模块${core.modules.length + 1}', {for (final m in core.modules) m.name}));
  if (core.modules.isEmpty) {
    m.owns.addAll([for (final i in beModuleItems(doc)) i.key]);
    core.entry = m.name;
  }
  core.modules.add(m);
  return null;
}

String? beRenameModule(BeDocument doc, String from, String name) {
  final core = doc.core;
  final m = core.module(from);
  if (m == null) return '这个模块已经不在了';
  final to = name.trim();
  if (to == from) return null;
  final bad = beCoreNameProblem(to, {for (final m in core.modules) m.name}, what: '模块的名字');
  if (bad != null) return bad;
  m.name = to;
  if (core.entry == from) core.entry = to;
  for (final o in core.modules) {
    for (var i = 0; i < o.uses.length; i++) {
      if (o.uses[i] == from) o.uses[i] = to;
    }
  }
  return null;
}

/// 删一个模块：它名下的东西归回入口模块。入口模块只有在它是最后一个时才能删。
String? beRemoveModule(BeDocument doc, String name) {
  final core = doc.core;
  final m = core.module(name);
  if (m == null) return '这个模块已经不在了';
  if (core.modules.length > 1 && core.entryModule == m) return '入口模块不能删：先把别的模块设成入口';
  core.modules.remove(m);
  for (final o in core.modules) {
    o.uses.remove(name);
  }
  core.entryModule?.owns.addAll(m.owns);
  if (core.modules.isEmpty) core.entry = null;
  return null;
}

/// 把一样东西挪到 [module] 里。
void beMoveToModule(BeDocument doc, String key, String module) {
  final core = doc.core;
  if (core.module(module) == null) return;
  for (final m in core.modules) {
    m.name == module ? m.owns.add(key) : m.owns.remove(key);
  }
}
