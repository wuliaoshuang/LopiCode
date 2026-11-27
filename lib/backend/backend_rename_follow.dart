/// 改名时“用到它的积木跟着改”里要查清楚的两件事（积木第 5 版·库 2 收尾）：
/// - 字段 / 方法是按名字选的。别的类型也有同名的成员时，要知道每一处“读字段 / 改字段 / 让对象做”的那个对象到底是什么类型，
///   才知道该不该跟着改——这里请类型检查器说（[beMemberSites]）。检查器说不出来的那几处不动（改完会标红，人自己换）。
/// - 模块顶上的变量也是按名字读写的。一串积木里要是自己新建了同名的变量 / 参数，那一串里的名字指的是它自己的，整串不动；
///   别的串里读写这个名字的地方都跟着改（[beRenameGlobalUses]）。
library;

import 'package:lopicode/backend/backend_blocks_lang.dart';
import 'package:lopicode/backend/backend_core.dart';
import 'package:lopicode/backend/backend_function.dart';
import 'package:lopicode/backend/backend_lower_core.dart';
import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/backend/backend_type_bridge.dart';
import 'package:lopicode/lang/ast.dart';
import 'package:lopicode/lowcode/logic_expr.dart';
import 'package:lopicode/lowcode/logic_model.dart';

/// [t] 这一家：它自己、继承它的（一层层往下）、它是接口时实现它的（和它们的子类）。
Set<String> beTypeFamily(BeCore core, BeTypeDef t) {
  final out = {t.name};
  for (var grew = true; grew;) {
    grew = false;
    for (final o in core.types) {
      if (out.contains(o.name)) continue;
      if (out.contains(o.parent) || o.interfaces.any(out.contains)) grew = out.add(o.name);
    }
  }
  return out;
}

/// 文档里“对象是 [family] 里某个类型”的成员用法：那些值（式子的 Map）和积木（“改字段”“让对象做”）。按“是不是同一个对象”比。
/// 检查做不了（老规矩的文档、翻不出来）返回空的。
Set<Object> beMemberSites(BeDocument doc, Set<String> family) {
  final seen = <(Object, LExpr)>[];
  final out = Set<Object>.identity();
  final was = beMemberTap;
  beMemberTap = (holder, receiver) => seen.add((holder, receiver));
  try {
    final check = beTypeCheck(doc);
    if (check == null) return out;
    for (final (holder, receiver) in seen) {
      final type = check.result.typeOf(receiver);
      if (type != null && family.contains(type.nonNull.name)) out.add(holder);
    }
  } finally {
    beMemberTap = was;
  }
  return out;
}

/// 这一串里有没有自己起一个叫 [name] 的东西（参数、新建的变量 / 常量、循环里的名字、段上写的名字、匿名函数的参数）。
bool _declares(LcBlockTree tree, List<String> params, String name) {
  if (params.contains(name)) return true;
  var hit = false;
  void value(Object? v, int depth) {
    if (hit || depth > kMaxExprDepth * 2 + 8 || v is List<LcBlock>) return;
    if (v is List) {
      for (final x in v) {
        value(x, depth + 1);
      }
    } else if (v is Map) {
      final ps = v['params'];
      if (ps is List && ps.contains(name)) hit = true;
      for (final x in v.values) {
        value(x, depth + 1);
      }
    }
  }

  tree.visitBlocks((b, _) {
    if (beLocalNames([LcBlock(op: b.op, args: b.args)], RegExp('^${RegExp.escape(name)}\$')).isNotEmpty) hit = true;
    // 段上直接写的名字（“接住错误，叫 e”“这种情况里的值叫 …”）也是这一串自己起的。
    for (final a in b.arms) {
      if (a.args.values.any((v) => v == name)) hit = true;
    }
    for (final v in [...b.args.values, for (final a in b.arms) ...a.args.values]) {
      value(v, 0);
    }
  });
  return hit;
}

/// 模块顶上的变量 [from] 改叫 [to]：各串里读它、写它的地方跟着改。自己起了同名东西的串整串不动。
/// [isVariableArg]＝这块积木的这个参数是不是“选一个变量”。返回 (改了几处, 有几串因为自己有同名的没动)。
({int changed, int skipped}) beRenameGlobalUses(List<LcBlockTree> trees, String from, String to, bool Function(LcBlock block, String arg) isVariableArg) {
  var changed = 0, skipped = 0;
  void value(Object? v, int depth) {
    if (depth > kMaxExprDepth * 2 + 8 || v is List<LcBlock>) return;
    if (v is List) {
      for (final x in v) {
        value(x, depth + 1);
      }
    } else if (v is Map) {
      if (v['e'] == 'var' && v['name'] == from) {
        v['name'] = to;
        changed++;
      }
      for (final x in v.values) {
        value(x, depth + 1);
      }
    }
  }

  for (final tree in trees) {
    final params = tree is BeMethod ? [for (final p in tree.params) p.name] : (tree is BeFunction ? tree.paramNames : const <String>[]);
    if (_declares(tree, params, from)) {
      var uses = false;
      tree.visitBlocks((b, _) => uses = uses || '${b.args}${[for (final a in b.arms) a.args]}'.contains(from));
      if (uses) skipped++;
      continue;
    }
    tree.visitBlocks((b, _) {
      for (final e in b.args.entries.toList()) {
        if (e.value == from && isVariableArg(b, e.key)) {
          b.args[e.key] = to;
          changed++;
        } else {
          value(e.value, 0);
        }
      }
      for (final a in b.arms) {
        for (final v in a.args.values) {
          value(v, 0);
        }
      }
    });
  }
  return (changed: changed, skipped: skipped);
}
