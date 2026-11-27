/// 语法树上的小工具：“按 x 分情况”怎么搭、一串语句是不是一定出去了、新建了哪些名字、挨个走一遍。
library;

import 'package:lopicode/lang/ast.dart';

/// “按 (x) 分情况：是 (a) 时 … 是 (b) 时 … 都不是 …”——一律是一串“如果 / 否则如果”（设计稿 3.4），不生成各语言的 `switch`。
/// [subject] 只算一次，存进名叫 [temp] 的临时值（同一个函数里不许重名；后端用接口里的临时值编号）。比法是“等于”（`==`）。
List<LStmt> lSwitch(String temp, LExpr subject, List<LIfArm> cases, {List<LStmt> orElse = const [], LSrc? src}) {
  if (cases.isEmpty) return [LExprStmt(subject, src: src), ...orElse];
  return [
    LLet(temp, subject, kind: LNameKind.temp, src: src),
    LIf(
      [for (final c in cases) LIfArm(LBinary('==', LName(temp, kind: LNameKind.temp), c.cond), c.body)],
      orElse: orElse,
      src: src,
    ),
  ];
}

/// 这一串语句是不是“怎么走都出去了”（返回 / 跳出 / 跳过 / 抛出，或每一段都出去了、而且有“否则”的“如果”）。
/// 它后面的语句不会执行：生成器不翻译（Java 碰到执行不到的语句直接编译不过），校验报 S10。循环不算：可能一遍都不做。
bool lAlwaysExits(List<LStmt> list) {
  for (final s in list.reversed) {
    if (s is LNote) continue;
    return lExits(s);
  }
  return false;
}

bool lExits(LStmt s) => switch (s) {
  LReturn() || LBreak() || LContinue() || LThrow() => true,
  LHost(:final returns) => returns,
  LIf(:final arms, :final orElse) => orElse.isNotEmpty && lAlwaysExits(orElse) && arms.every((a) => lAlwaysExits(a.body)),
  _ => false,
};

/// 这一串语句是不是“怎么走都返回了”（给函数末尾要不要补一句“什么都不返回”用）：只认返回 / 抛出，跳出 / 跳过不算。
/// 从前往后看：碰到第一句“一定出去了”的就定了——它后面的语句生成器不翻译（见 [lAlwaysExits]），不能再看它们。
bool lAlwaysReturns(List<LStmt> list) {
  for (final s in list) {
    if (s is LNote) continue;
    final returns = switch (s) {
      LReturn() || LThrow() => true,
      LHost(:final returns) => returns,
      LIf(:final arms, :final orElse) => orElse.isNotEmpty && lAlwaysReturns(orElse) && arms.every((a) => lAlwaysReturns(a.body)),
      _ => false,
    };
    if (returns) return true;
    if (lExits(s)) return false;
  }
  return false;
}

/// 这一串语句里新建的名字（变量、常量、循环变量），按第一次出现的顺序、不重复。生成器照它在函数开头统一声明。
List<String> lDeclaredNames(List<LStmt> list) {
  final out = <String>[];
  void add(String? n) {
    if (n != null && !out.contains(n)) out.add(n);
  }

  void walk(List<LStmt> stmts) {
    for (final s in stmts) {
      switch (s) {
        case LLet(:final name, :final kind):
          if (kind == LNameKind.variable) add(name);
        case LIf(:final arms, :final orElse):
          for (final a in arms) {
            walk(a.body);
          }
          walk(orElse);
        case LWhile(:final body) || LRepeat(:final body):
          walk(body);
        case LForCount(:final name, :final body):
          add(name);
          walk(body);
        case LForEach(:final item, :final index, :final reuse, :final body):
          if (!reuse) add(item);
          add(index);
          walk(body);
        case LForPairs(:final key, :final value, :final body):
          add(key);
          add(value);
          walk(body);
        case LTry(:final body, :final catches, :final finallyBody):
          walk(body);
          for (final c in catches) {
            add(c.name);
            walk(c.body);
          }
          walk(finallyBody);
        case LStmtV5(:final binds, :final childBlocks):
          binds.forEach(add);
          childBlocks.forEach(walk);
        case LAssign() || LExprStmt() || LBreak() || LContinue() || LReturn() || LThrow() || LHost() || LNote():
          break;
      }
    }
  }

  walk(list);
  return out;
}

/// 把一串语句连同里面套着的语句挨个走一遍（先外后里）。[LHost] 里面是什么它不知道，不往里走。
void lWalk(List<LStmt> list, void Function(LStmt s) visit) {
  for (final s in list) {
    visit(s);
    switch (s) {
      case LIf(:final arms, :final orElse):
        for (final a in arms) {
          lWalk(a.body, visit);
        }
        lWalk(orElse, visit);
      case LWhile(:final body) || LRepeat(:final body) || LForCount(:final body) || LForEach(:final body) || LForPairs(:final body):
        lWalk(body, visit);
      case LTry(:final body, :final catches, :final finallyBody):
        lWalk(body, visit);
        for (final c in catches) {
          lWalk(c.body, visit);
        }
        lWalk(finallyBody, visit);
      case LStmtV5(:final childBlocks):
        for (final b in childBlocks) {
          lWalk(b, visit);
        }
      case LLet() || LAssign() || LExprStmt() || LBreak() || LContinue() || LReturn() || LThrow() || LHost() || LNote():
        break;
    }
  }
}

/// 一个式子直接套着的子式子。
List<LExpr> lExprChildren(LExpr e) => switch (e) {
  LLit() || LName() || LThis() || LLambda() => const [],
  LSpawn(:final body) => [
    for (final s in body)
      if (s is LReturn && s.value != null) s.value!,
  ],
  LListLit(:final items) => items,
  LDictLit(:final entries) => [
    for (final x in entries) ...[x.key, x.value],
  ],
  LField(:final of) => [of],
  LIndex(:final of, :final key) => [of, key],
  LUnary(:final x) || LIsA(:final x) || LAwait(:final x) => [x],
  LBinary(:final l, :final r) || LLogic(:final l, :final r) => [l, r],
  LCond(:final cond, :final then, :final orElse) => [cond, then, orElse],
  LCall(:final callee, :final args) => [callee, ...args],
  LSend(:final obj, :final args) => [obj, ...args],
  LSuperSend(:final args) || LNew(:final args) || LRt(:final args) || LNative(:final args) => args,
  LExprV5(:final childExprs) => childExprs,
};

/// 一条语句自己（不算套着的语句）直接带的式子。
List<LExpr> lStmtExprs(LStmt s) => switch (s) {
  LLet(:final value) => [value],
  LAssign(:final target, :final value) => [
    ...switch (target) {
      LTName() => const <LExpr>[],
      LTIndex(:final of, :final key) => [of, key],
      LTField(:final of) => [of],
    },
    value,
  ],
  LExprStmt(:final expr) => [expr],
  LIf(:final arms) => [for (final a in arms) a.cond],
  LWhile(:final cond) => [?cond],
  LForCount(:final from, :final to, :final step) => [from, to, step],
  LForEach(:final list) => [list],
  LForPairs(:final dict) => [dict],
  LRepeat(:final times) => [times],
  LReturn(:final value) => [?value],
  LThrow(:final message) => [message],
  LBreak() || LContinue() || LTry() || LHost() || LNote() => const [],
  LStmtV5(:final childExprs) => childExprs,
};

/// 把一串语句里所有的式子（连同套着的语句里的）挨个交给 [visit]（只给最外层的，子式子用 [lExprChildren] 往里走）。
void lWalkExprs(List<LStmt> list, void Function(LExpr e) visit) {
  lWalk(list, (s) => lStmtExprs(s).forEach(visit));
}

/// 调这个函数最少、最多给几个参数（最多是 -1＝不限：最后一个参数是“剩下的全收”）。
int lMinArgs(List<LParam> params) => params.where((p) => !p.rest && p.defaultValue == null).length;
int lMaxArgs(List<LParam> params) => params.any((p) => p.rest) ? -1 : params.length;

/// 类里“每个对象自己的”和“类本身的”（勾了“属于类本身”的）成员分开看。
extension LClassParts on LClassDecl {
  Iterable<LFieldDecl> get ownFields => fields.where((f) => !f.isStatic);
  Iterable<LMethodDecl> get ownMethods => methods.where((m) => !m.isStatic);
}

/// 类本身的成员在整个程序里的名字：`类名.成员名`。
String lStaticName(String cls, String member) => '$cls.$member';

/// 类本身的成员降成模块级的声明（核心 2）：字段 → 变量，方法 → 函数，名字是 [lStaticName]。检查器和五种语言的生成器
/// 都照这个来（Go 没有“类本身的成员”，别的语言里它们的初始化时机各不相同——统一成模块级变量，初值按声明顺序算）。
/// 函数体、初值是原来的节点（检查结果按节点对象记）。
List<LDecl> lStaticDecls(LClassDecl d) => [
  for (final f in d.fields)
    if (f.isStatic) LVarDecl(lStaticName(d.name, f.name), f.init ?? const LLit(null), src: d.src, type: f.type),
  for (final m in d.methods)
    if (m.isStatic) LFuncDecl(lStaticName(d.name, m.fn.name), m.fn.params, m.fn.body, typeParams: m.fn.typeParams, waits: m.fn.waits, src: m.fn.src ?? d.src, type: m.fn.type),
];

/// 展开出来的语句没有来处的（库积木展开的）：最外面那几句补上“是哪一块积木”。有来处的不动。
List<LStmt> lStampSrc(List<LStmt> list, LSrc src) => [
  for (final s in list)
    if (s.src != null)
      s
    else
      switch (s) {
        LReturn(:final value) => LReturn(value, src: src),
        LExprStmt(:final expr) => LExprStmt(expr, src: src),
        LAssign(:final target, :final value) => LAssign(target, value, src: src),
        LLet(:final name, :final value, :final isConst, :final kind, :final type) => LLet(name, value, isConst: isConst, kind: kind, src: src, type: type),
        LIf(:final arms, :final orElse) => LIf(arms, orElse: orElse, src: src),
        _ => s,
      },
];
