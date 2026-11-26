/// 一个程序几个模块（核心 2）：检查模块之间的事，再合成一个模块交给类型检查和生成器。
/// 设计：docs/blocks-v5-foundation-design.md 7.1 第 4 条；docs/blocks-v5-parts/A2-features-advanced.md 的模块表（M01–M22）和 10.g（含 2026-11-26 更正）；
/// 实现说明：docs/blocks-v5-parts/B-gen-notes.md 第 10 节。
///
/// 规矩（规则号 M01–M08，表在 type_issue.dart 的 [kModuleRules]）：
/// - 每个模块有不重样的名字；程序指明入口模块；只有入口模块有“程序开始时”。
/// - 模块 [LModule.uses] 里列了谁，才看得见谁的东西，而且只看得见勾了“公开”的。自己模块里的名字优先。
/// - 模块之间不许绕圈；绕了就把圈画出来（甲 → 乙 → 甲），并给固定的解法。
/// - 启动顺序：被用到的模块先准备好（它顶上的变量先赋初值），同一层按程序里写的先后；一个模块里按变量写的先后；最后跑入口的“程序开始时”。
/// - 不同模块里的顶层名字可以重样：合并时撞了名字的那几个改叫“模块名·名字”（只在合并后的程序里；没撞的不改）。
library;

import 'package:lopicode/lang/ast.dart';
import 'package:lopicode/lang/ast_util.dart';
import 'package:lopicode/lang/errors.dart';
import 'package:lopicode/lang/rename.dart';
import 'package:lopicode/lang/type_issue.dart';

/// [linkProgram] 的结果。
class LLinked {
  const LLinked(this.module, this.issues, this.order, this.names);

  /// 合好的模块；模块之间有错（[issues] 不空）＝null。
  final LModule? module;
  final List<LTypeIssue> issues;

  /// 启动顺序（模块名，先准备好的在前）。绕圈了＝空。
  final List<String> order;

  /// 改了名的顶层东西：(模块名, 原名) → 合并后的名字。
  final Map<(String, String), String> names;

  bool get hasErrors => issues.isNotEmpty;
}

bool _isPublic(LDecl d) => switch (d) {
  LVarDecl(:final isPublic) || LFuncDecl(:final isPublic) || LClassDecl(:final isPublic) || LInterfaceDecl(:final isPublic) || LTypeDecl(:final isPublic) => isPublic,
  LNativeDecl() => false,
};

/// 圈：从某个模块出发顺着“用到了谁”走回自己的那条路（没有圈＝null）。
List<String>? _cycle(Map<String, LModule> byName) {
  final state = <String, int>{}; // 1＝正在走，2＝走完了
  final path = <String>[];
  List<String>? walk(String n) {
    state[n] = 1;
    path.add(n);
    for (final u in byName[n]!.uses) {
      if (u == n || !byName.containsKey(u)) continue; // 用了自己、用了不存在的：M02 已经说过
      if (state[u] == 1) return [...path.sublist(path.indexOf(u)), u];
      if (state[u] == null) {
        final got = walk(u);
        if (got != null) return got;
      }
    }
    path.removeLast();
    state[n] = 2;
    return null;
  }

  for (final n in byName.keys) {
    if (state[n] == null) {
      final got = walk(n);
      if (got != null) return got;
    }
  }
  return null;
}

LLinked linkProgram(LProgram p) {
  final issues = <LTypeIssue>[];
  void bad(String code, String where, String message, {LNode? node}) {
    final text = '$code $where：$message';
    if (issues.any((i) => '$i' == text)) return;
    issues.add(LTypeIssue(code, where, message, level: LTypeLevel.error, node: node, src: node?.src));
  }

  final byName = <String, LModule>{};
  for (final m in p.modules) {
    if (m.name.isEmpty) {
      bad('M01', '程序', '有一个模块还没起名字', node: m);
    } else if (byName.containsKey(m.name)) {
      bad('M01', m.name, '有两个模块都叫「${m.name}」，给其中一个换个名字', node: m);
    } else {
      byName[m.name] = m;
    }
  }
  if (!byName.containsKey(p.entry)) bad('M02', '程序', '找不到入口模块「${p.entry}」', node: p);
  for (final m in byName.values) {
    for (final u in m.uses) {
      if (u == m.name) {
        bad('M02', m.name, '模块「${m.name}」的“用到了谁”里写了它自己，去掉就行', node: m);
      } else if (!byName.containsKey(u)) {
        bad('M02', m.name, '模块「${m.name}」说用到了「$u」，但是没有叫这个名字的模块', node: m);
      }
    }
    if (byName.containsKey(p.entry) && m.name != p.entry && m.body.isNotEmpty) {
      bad('M04', m.name, '模块「${m.name}」不是入口，不能有“程序开始时”：把这些积木挪到入口模块「${p.entry}」，或者包成一个公开的函数让入口来调', node: m);
    }
  }
  final cycle = _cycle(byName);
  if (cycle != null) {
    final a = cycle.first, b = cycle[1];
    bad('M03', a, '模块绕圈了：${cycle.join(' → ')}。把「$a」和「$b」都要用的东西挪到第三个模块里，让它们都去用它', node: byName[a]);
  }
  if (issues.isNotEmpty) return LLinked(null, issues, const [], const {});

  // 启动顺序：被用到的先。
  final order = <String>[];
  void visit(String n) {
    if (order.contains(n)) return;
    for (final u in byName[n]!.uses) {
      visit(u);
    }
    order.add(n);
  }

  byName.keys.where((n) => n != p.entry).forEach(visit);
  visit(p.entry);
  // 入口永远最后：它的“程序开始时”要等所有模块准备好。别的模块用不到入口（用了就是圈，或者入口被别人用——那它也排在用它的后面不了）。
  if (order.last != p.entry) {
    final users = [
      for (final m in byName.values)
        if (m.uses.contains(p.entry)) m.name,
    ];
    bad('M03', p.entry, '入口模块「${p.entry}」不能被别的模块用（「${users.join('」「')}」用了它）：把要共用的东西挪到另一个模块里', node: byName[p.entry]);
    return LLinked(null, issues, const [], const {});
  }

  // 顶层名字：哪些撞了、合并后叫什么。
  final owners = <String, List<String>>{};
  for (final m in byName.values) {
    final seen = <String>{};
    for (final d in m.decls) {
      if (!seen.add(d.name)) {
        bad('M07', m.name, '模块「${m.name}」里有两个东西都叫「${d.name}」', node: d);
      }
      (owners[d.name] ??= []).add(m.name);
    }
  }
  final taken = {...owners.keys, ...kErrBuiltinNames};
  final names = <(String, String), String>{};
  for (final MapEntry(key: n, value: ms) in owners.entries) {
    if (ms.length < 2) continue;
    for (final m in ms) {
      var fresh = '$m·$n';
      while (!taken.add(fresh)) {
        fresh = '$fresh′';
      }
      names[(m, n)] = fresh;
    }
  }
  String finalName(String module, String n) => names[(module, n)] ?? n;

  final decls = <LDecl>[];
  var body = const <LStmt>[];
  for (final mn in order) {
    final m = byName[mn]!;
    final own = {for (final d in m.decls) d.name};
    String resolve(String n) {
      if (own.contains(n)) return finalName(mn, n);
      final all = owners[n];
      if (all == null) return n; // 不是哪个模块的顶层名字（内置的、写错的）：留给类型检查说
      final open = [
        for (final u in m.uses)
          if (byName[u]!.decls.any((d) => d.name == n && _isPublic(d))) u,
      ];
      if (open.length == 1) return finalName(open.single, n);
      if (open.length > 1) {
        bad('M07', mn, '「$n」在模块「${open.join('」「')}」里都有，分不清是哪个：给其中一个换个名字', node: m);
        return finalName(open.first, n);
      }
      final hidden = m.uses.where((u) => byName[u]!.decls.any((d) => d.name == n)).firstOrNull;
      if (hidden != null) {
        bad('M06', mn, '模块「$hidden」里的「$n」没有公开，「$mn」用不了：在「$hidden」里给它勾上“公开”', node: m);
        return finalName(hidden, n);
      }
      final elsewhere = all.where((o) => byName[o]!.decls.any((d) => d.name == n && _isPublic(d))).firstOrNull;
      if (elsewhere != null) {
        bad('M05', mn, '「$n」在模块「$elsewhere」里，「$mn」还没说用到了它：在「$mn」的“用到了谁”里加上「$elsewhere」', node: m);
        return finalName(elsewhere, n);
      }
      bad('M06', mn, '模块「${all.first}」里的「$n」没有公开，而且「$mn」也没说用到了「${all.first}」', node: m);
      return finalName(all.first, n);
    }

    final r = LRenamer(resolve);
    // 顶上的变量：初始值不能直接用到同一个模块里排在它后面的变量（那时候它还没有值）。
    final later = [for (final d in m.decls.whereType<LVarDecl>()) d.name];
    for (final d in m.decls.whereType<LVarDecl>()) {
      void look(LExpr e) {
        if (e is LName && later.contains(e.name)) {
          bad('M08', mn, e.name == d.name ? '「${d.name}」的初始值用到了它自己' : '「${d.name}」的初始值用到了排在它后面的「${e.name}」，那时候「${e.name}」还没有值：把「${e.name}」挪到前面', node: d);
        }
        if (e is! LLambda) lExprChildren(e).forEach(look);
      }

      look(d.init);
      later.remove(d.name);
    }
    decls.addAll(r.decls(m.decls));
    if (mn == p.entry) body = r.mainBody(m.body);
  }
  if (issues.isNotEmpty) return LLinked(null, issues, order, names);
  return LLinked(LModule(name: p.entry, decls: decls, body: body, src: p.src), issues, order, names);
}
