/// 规矩版本 2 的文档：跑一遍类型检查（lib/lang/typecheck.dart），把问题和一键修对回到积木、对回到具体哪一格上。
///
/// 全工程只有这一处跑后端文档的类型检查。两个地方用它的结果：
/// - 校验（backend_validate_types.dart → `validateBackend`）：把“错 / 警告”转成校验问题，拦住生成、运行、导出；
/// - 积木编辑器（backend_type_host.dart）：标红到式子里的位置、一键修、类型一行字。
/// 两边拿的是同一份结果（[beTypeCheckShared]），所以同一个问题不会有两种说法。
///
/// 做法照 backend_validate_lang.dart：接口、函数都按“影子模式”翻成语法树（没用到第 4 版积木的接口也翻，`always`），
/// 交给 `checkTypes`；问题的节点靠翻译时记的 `origins`（式子 → 积木文档里的那个值）找回是哪一格，找不到的退回来源表（哪一块、哪个参数）。
/// 只读不改、不抛异常（翻不出来就当没有类型问题）。规矩版本 1 的文档直接返回 null，什么都不算。
library;

import 'package:lopicode/backend/backend_core_fix.dart';
import 'package:lopicode/backend/backend_function.dart';
import 'package:lopicode/backend/backend_ir.dart' show beLangLowerOf;
import 'package:lopicode/backend/backend_lang.dart' show kBeRequestName;
import 'package:lopicode/backend/backend_lower_core.dart';
import 'package:lopicode/backend/backend_lower_func.dart';
import 'package:lopicode/backend/backend_lower_lang.dart';
import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/lang/errors.dart';
import 'package:lopicode/lang/lang.dart';
import 'package:lopicode/lang/link.dart';
import 'package:lopicode/lowcode/logic_model.dart';

/// 积木文档里的一格：哪一串、哪一块、哪个参数、参数里的哪个位置（和积木编辑器的槽位路径同一种写法）。
class BeSlotRef {
  const BeSlotRef(this.treeId, this.path, this.arg, this.exprPath);
  final String treeId;
  final LcBlockPath path;

  /// null＝整块。
  final String? arg;
  final List<Object> exprPath;
}

/// 一条类型问题，已经对回到积木上。
class BeTypeFinding {
  const BeTypeFinding(this.issue, this.at, this.fixes, {this.extra = const []});
  final LTypeIssue issue;
  final BeSlotRef at;

  /// 能在积木上做的一键修：修法＋它要包 / 要换的那一格。（要靠记录、“看是哪种情况”这些还没有积木的东西才能表达的不在里面。）
  final List<({LFix fix, BeSlotRef slot})> fixes;

  /// 核心 2 的修法（补情况、补字段、照抄签名…；见 backend_core_fix.dart）。
  final List<BeCoreFix> extra;

  /// 给人看的那句话：检查器里“这次请求”叫 req，这里换回积木上的叫法。
  String get problem => issue.message.replaceAll('“req”', '“这次请求”').replaceAll('「req」', '“这次请求”');
}

class BeTypeCheck {
  const BeTypeCheck(this.result, this.findings, this.scopes, {this.module = const LModule(), this.program});

  /// 整份文档翻成的一个模块（函数、类型、模块顶上的变量 + “程序开始时”；不含接口）。
  final LModule module;

  /// 文档里分了模块时，按模块分好的程序；没分是 null。
  final LProgram? program;
  final LTypeResult result;
  final List<BeTypeFinding> findings;

  /// 每一串在检查结果里叫什么（查变量、函数的类型用）：串的 id → 那一层的名字。
  final Map<String, String> scopes;
}

BeRoute _shell(BeFunction f) => BeRoute(id: f.id, method: 'GET', path: '/', body: f.body);

/// 在一串积木里按“是不是同一个对象”找一个值（式子的 Map、列表）在哪一格。
BeSlotRef? _find(LcBlockTree tree, Object needle) {
  BeSlotRef? out;
  List<Object>? inValue(Object? v, List<Object> at, int depth) {
    if (identical(v, needle)) return at;
    if (depth > 64 || v is List<LcBlock>) return null;
    if (v is Map) {
      for (final e in v.entries) {
        final key = e.key;
        if (key is! String || key == kLcExprBody) continue;
        final hit = inValue(e.value, [...at, key], depth + 1);
        if (hit != null) return hit;
      }
    } else if (v is List) {
      for (var i = 0; i < v.length; i++) {
        final hit = inValue(v[i], [...at, i], depth + 1);
        if (hit != null) return hit;
      }
    }
    return null;
  }

  tree.visitBlocks((b, path) {
    if (out != null) return;
    if (identical(b, needle)) {
      out = BeSlotRef(tree.id, path, null, const []);
      return;
    }
    void scan(Map<String, dynamic> args, String Function(String) name) {
      for (final e in args.entries) {
        if (out != null) return;
        final hit = inValue(e.value, const [], 0);
        if (hit != null) out = BeSlotRef(tree.id, path, name(e.key), hit);
      }
    }

    scan(b.args, (k) => k);
    for (var k = 0; k < b.arms.length; k++) {
      scan(b.arms[k].args, (n) => lcArmArg(k, n));
    }
  });
  return out;
}

/// 语法树里的一个节点 → 积木文档里的哪一格；说不出来返回 null。
BeSlotRef? _slotOf(LcBlockTree tree, BeLangLower lower, LNode? node) {
  final o = node is LExpr ? lower.origins[node] : null;
  if (o == null) return null;
  final value = o.value;
  if (value is Map) {
    final hit = _find(tree, value);
    if (hit != null) return hit;
  }
  final holder = o.holder, key = o.key;
  if (holder == null || key == null) return null;
  final home = _find(tree, holder);
  if (home == null) return null;
  // 放在积木上的：key 就是参数名；放在式子 / 列表里的：往里再走一步。
  if (home.arg == null) return key is String ? BeSlotRef(tree.id, home.path, key, const []) : null;
  return BeSlotRef(tree.id, home.path, home.arg, [...home.exprPath, key]);
}

/// 把那一格里的东西包一层就行的修法（backend_type_fix.dart）；别的五种（补情况、补字段…）在 backend_core_fix.dart。
const Set<LFixKind> kBeBlockFixKinds = {LFixKind.wrapToText, LFixKind.wrapToInt, LFixKind.wrapParseInt, LFixKind.wrapOrElse, LFixKind.wrapMust, LFixKind.compareNotZero};

BeSpot _spot(BeSlotRef r) => (treeId: r.treeId, path: r.path, arg: r.arg, exprPath: r.exprPath);

/// 规矩版本 2 的文档跑类型检查；版本 1 返回 null。
/// [pure]＝只出语言核心的东西（“看代码”用，见 backend_core_gen.dart）；平时查类型不用给。
BeTypeCheck? beTypeCheck(BeDocument doc, {bool pure = false}) {
  if (!langRulesStrict(doc.rules)) return null;
  try {
    final core = doc.core;
    final trees = <String, LcBlockTree>{};
    final lowers = <String, BeLangLower>{};
    final decls = <({String key, LDecl decl})>[];
    final scripts = <LTypeScript>[];
    final scopes = <String, String>{};
    BeLangLower? lowerOf(LcBlockTree tree, BeRoute shell, {required bool inFunction}) {
      final lower = beLangLowerOf(doc, shell, shadow: true, inFunction: inFunction, all: !inFunction);
      if (lower == null) return null;
      lower
        ..typed = true
        ..pure = pure
        ..core = core;
      trees[tree.id] = tree;
      lowers[tree.id] = lower;
      return lower;
    }

    for (final f in doc.functions) {
      final lower = lowerOf(f, _shell(f), inFunction: true);
      if (lower == null) continue;
      scopes[f.id] = f.ident;
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
    // 核心 2：类型、模块顶上的变量、“程序开始时”。
    var main = const <LStmt>[];
    if (!core.isEmpty) {
      final values = beLangLowerOf(doc, BeRoute(id: '', method: 'GET', path: '/'), shadow: true, inFunction: true);
      values
        ?..typed = true
        ..pure = pure
        ..core = core;
      final unit = beCoreUnit(
        doc,
        body: (m, owner) {
          final lower = lowerOf(m, BeRoute(id: m.id, method: 'GET', path: '/', body: m.body), inFunction: true);
          scopes[m.id] = owner == null ? '程序开始时' : '${owner.name}.${m.name}';
          return lower?.stmts(m.body, const [], 0) ?? const [];
        },
        value: (v) => values?.value(v) ?? const LLit(null),
      );
      decls.addAll(unit.decls);
      main = unit.main;
    }
    // 文档里声明的变量、“这次请求”：里面放什么说不准，一律当“任意”。
    final outer = <String, LType>{for (final v in doc.variables) v.name: LType.any, kBeRequestName: LType.any};
    for (final r in doc.routes) {
      final lower = lowerOf(r, r, inFunction: false);
      if (lower == null) continue;
      final name = '接口 ${r.id}';
      scopes[r.id] = name;
      scripts.add(LTypeScript(name, lower.stmts(r.body, const [], 0)));
    }
    final result = checkTypes(decls: [for (final d in decls) d.decl], main: main, scripts: scripts, outer: outer);
    final findings = <BeTypeFinding>[];
    // 模块之间的事（M01–M08）：按模块分好再查一遍；问题不在哪块积木上，记在整份文档名下。
    final program = beCoreProgram(core, decls, main);
    if (program != null) {
      for (final i in linkProgram(program).issues) {
        findings.add(BeTypeFinding(i, const BeSlotRef('', [], null, []), const [], extra: beCoreExtraFixes(doc, i, treeId: '')));
      }
    }
    for (final i in result.issues) {
      // 变量、函数的名字找不到：老规则（G03 / L01）已经报了，说法也更贴着积木，不重复。字段、方法、情况找不到的照报。
      final node = i.node;
      if (i.code == 'T08' && (node is LName || node is LCall || node is LAssign || node == null || i.message.endsWith('」的变量'))) continue;
      final id = i.src?.script ?? scopes.entries.where((e) => e.value == i.where).firstOrNull?.key;
      final tree = trees[id], lower = lowers[id];
      if (tree == null || lower == null) {
        // 类一级的问题（继承、实现接口…）：不在哪块积木上，记在那个类型名下。
        if (id == null || core.type(id) == null) continue;
        findings.add(BeTypeFinding(i, BeSlotRef(id, const [], null, const []), const [], extra: beCoreExtraFixes(doc, i, treeId: id)));
        continue;
      }
      BeSlotRef? blockOf(LNode? n) {
        final k = int.tryParse(n?.src?.block ?? '');
        final spot = k != null && k >= 0 && k < lower.spots.length ? lower.spots[k] : null;
        return spot == null ? null : BeSlotRef(tree.id, spot.path, null, const []);
      }

      var at = _slotOf(tree, lower, i.node);
      if (at == null) {
        final n = int.tryParse(i.src?.block ?? '');
        final spot = n != null && n >= 0 && n < lower.spots.length ? lower.spots[n] : null;
        at = BeSlotRef(tree.id, spot?.path ?? const [], spot?.arg, const []);
      }
      final fixes = <({LFix fix, BeSlotRef slot})>[];
      final extra = <BeCoreFix>[];
      for (final f in i.fixes) {
        final slot = _slotOf(tree, lower, f.target);
        if (kBeBlockFixKinds.contains(f.kind)) {
          if (slot != null && slot.arg != null) fixes.add((fix: f, slot: slot));
          continue;
        }
        final block = blockOf(f.target);
        final fix = beCoreFixOf(f, block: block == null ? null : _spot(block), slot: slot == null || slot.arg == null ? null : _spot(slot));
        if (fix != null) extra.add(fix);
      }
      final got = node is LExpr ? result.typeOf(node) : null;
      final gotError = got != null && got.name != null && (langIsBuiltinError(got.name) || core.errorKinds.contains(got.name));
      final block = blockOf(i.node) ?? (at.path.isEmpty ? null : BeSlotRef(tree.id, at.path, null, const []));
      extra.addAll(beCoreExtraFixes(doc, i, treeId: tree.id, slot: at.arg == null ? null : _spot(at), block: block == null ? null : _spot(block), gotError: gotError));
      findings.add(BeTypeFinding(i, at, fixes, extra: extra));
    }
    // “看是哪种情况”看可空的值 / “任意”的值：列全了没有在这里查（见 beMatchGap）。
    for (final tree in trees.values) {
      tree.visitBlocks((b, path) {
        final at = BeSlotRef(tree.id, path, null, const []);
        final gap = beMatchGap(b, _spot(at));
        if (gap != null) findings.add(BeTypeFinding(LTypeIssue('T03', scopes[tree.id] ?? '', gap.$1, level: LTypeLevel.error), at, const [], extra: gap.$2));
      });
    }
    return BeTypeCheck(
      result,
      findings,
      scopes,
      module: LModule(decls: [for (final d in decls) d.decl], body: main),
      program: program,
    );
  } on Object {
    return null;
  }
}

BeDocument? _sharedDoc;
String? _sharedKey;
BeTypeCheck? _shared;

/// 和 [beTypeCheck] 一样，但文档内容没变就给上一次的结果（只记最近一份）。
/// 校验一份文档时每个接口、每块“我的积木”都要问一遍，编辑器紧接着还要再问一遍——都落在同一次检查上。
BeTypeCheck? beTypeCheckShared(BeDocument doc) {
  if (!langRulesStrict(doc.rules)) return null;
  final key = doc.encode();
  if (identical(_sharedDoc, doc) && _sharedKey == key) return _shared;
  final check = beTypeCheck(doc);
  _sharedDoc = doc;
  _sharedKey = key;
  return _shared = check;
}
