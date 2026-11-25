/// 积木编辑器对模型的操作：预览用的“不改模型的副本”，和真正落到模型上的改动（都要在宿主的 edit 里调）。
///
/// 不带界面，可以直接单元测试。规矩同 block_host.dart：不留着模型对象，按“脚本 id + 路径”现找现用。
library;

import 'dart:ui';

import 'package:lopicode/blocks/block_canvas_layout.dart';
import 'package:lopicode/blocks/block_geometry.dart';
import 'package:lopicode/blocks/block_host.dart';
import 'package:lopicode/blocks/block_layout.dart';
import 'package:lopicode/lowcode/logic_blocks.dart';
import 'package:lopicode/lowcode/logic_model.dart';

// —— 预览：造一份“改过的积木列表”，原来的模型一个字都不动 ——

/// 把 `parent`（`inElse`）下面那一列换成 `change` 改过的样子，返回新的最外层列表。
/// 只有路径上的积木是新对象（浅拷贝），其余和原来共用；路径走不通就原样返回。
/// `arm >= 0`＝那块积木第几段的口。
List<LcBlock> bkEditedBody(List<LcBlock> body, LcBlockPath parent, bool inElse, void Function(List<LcBlock> list) change, {int arm = -1}) {
  List<LcBlock> rebuild(List<LcBlock> list, int depth) {
    if (depth == parent.length) {
      final copy = [...list];
      change(copy);
      return copy;
    }
    final i = parent[depth].index;
    if (i < 0 || i >= list.length) return list;
    final b = list[i];
    final last = depth == parent.length - 1;
    final childArm = last ? arm : parent[depth + 1].arm;
    final childElse = last ? inElse : parent[depth + 1].inElse;
    final inner = b.mouth(inElse: childElse, arm: childArm);
    if (inner == null) return list;
    final child = rebuild(inner, depth + 1);
    if (childArm >= 0) {
      return [...list]
        ..[i] = b.copyWith(
          arms: [...b.arms]..[childArm] = LcArm(args: b.arms[childArm].args, body: child),
        );
    }
    return [...list]..[i] = childElse ? b.copyWith(orElse: child) : b.copyWith(body: child);
  }

  return rebuild(body, 0);
}

/// 把 `path` 那块积木换成 `replace` 给的，返回新的最外层列表（预览“表达式被拿走以后”的样子用）。
List<LcBlock> bkBodyWithBlock(List<LcBlock> body, LcBlockPath path, LcBlock Function(LcBlock block) replace) {
  if (path.isEmpty) return body;
  final i = path.last.index;
  return bkEditedBody(body, path.sublist(0, path.length - 1), path.last.inElse, arm: path.last.arm, (list) {
    if (i >= 0 && i < list.length) list[i] = replace(list[i]);
  });
}

/// 一块积木的副本：参数（含各段的参数）是深拷贝（可以随便改），里面嵌的积木和原来共用。
LcBlock bkCopyArgs(LcBlock b) {
  Map<String, dynamic> copy(Map<String, dynamic> m) {
    final c = deepCopyJson(m);
    return c is Map<String, dynamic> ? c : {};
  }

  return b.copyWith(
    args: copy(b.args),
    arms: b.arms.isEmpty ? null : [for (final a in b.arms) LcArm(args: copy(a.args), body: a.body)],
  );
}

// —— 查 ——

/// 一截积木放到 `parent` 下面会不会套得太深（和 `LcBlockTree.insertBlock` 用同一条规矩）。
bool bkFitsDepth(LcBlockPath parent, List<LcBlock> blocks) => blocks.every((b) => parent.length + b.height - 1 <= LcBlock.maxDepth);

/// 一截积木连同里面的一共多少块。
int bkCountBlocks(List<LcBlock> blocks) {
  var n = 0;
  for (final b in blocks) {
    n += 1 + bkCountBlocks(b.body) + bkCountBlocks(b.orElse);
    for (final a in b.arms) {
      n += bkCountBlocks(a.body);
    }
  }
  return n;
}

/// 一个槽位的说明：`path` 为空＝积木自己的参数；否则看它所在的那个表达式。找不到返回 null。
LcArgSpec? bkArgSpecAt(BlockHost host, LcBlock block, String arg, BkExprPath path) {
  var at = path;
  // 列表里的一项：说明在列表那个参数上。
  if (at.isNotEmpty && at.last is int) at = at.sublist(0, at.length - 1);
  if (at.isEmpty) return host.blockSpec(block.op)?.arg(arg);
  final name = at.last;
  final owner = bkExprAt(block, arg, at.sublist(0, at.length - 1));
  final kind = exprKind(owner);
  return name is String && kind != null ? host.exprSpec(kind)?.arg(name) : null;
}

/// 槽位所在的那个表达式（积木自己的参数返回 null）。
Map<String, dynamic>? bkOwnerExpr(LcBlock block, String arg, BkExprPath path) {
  var at = path;
  if (at.isNotEmpty && at.last is int) at = at.sublist(0, at.length - 1);
  if (at.isEmpty) return null;
  return asExpr(bkExprAt(block, arg, at.sublist(0, at.length - 1)));
}

// —— 改（都要在宿主的 edit 里调）——

/// 给槽位放一个值（字面量或表达式）。
bool bkSetSlotValue(LcBlock block, String arg, BkExprPath path, Object? value) => bkSetExprAt(block, arg, path, value);

/// 一个槽“空着”时该放什么：普通槽是宿主给的默认值；“一串值”里的一项是宿主给的新的一项。
Map<String, dynamic> bkDefaultExprAt(BlockHost host, LcBlock block, String arg, BkExprPath path) {
  final spec = bkArgSpecAt(host, block, arg, path);
  if (path.isNotEmpty && path.last is int) {
    final owner = bkOwnerExpr(block, arg, path);
    return owner != null && spec != null ? host.newListItem(owner, spec) : defaultExprFor(LcType.any);
  }
  return spec == null ? defaultExprFor(LcType.any) : host.defaultExpr(spec);
}

/// 把一个表达式从它的槽里拿走，返回拿走的那个（不是表达式返回 null，什么都不改）。
/// 普通槽放回宿主给的默认值；“一串值”里的一项直接去掉（只剩一项时不去掉，换成默认值）。
Map<String, dynamic>? bkTakeExpr(BlockHost host, LcBlock block, String arg, BkExprPath path) {
  final taken = asExpr(bkExprAt(block, arg, path));
  if (taken == null) return null;
  final empty = bkDefaultExprAt(host, block, arg, path);
  if (path.isNotEmpty && path.last is int) {
    final list = bkExprAt(block, arg, path.sublist(0, path.length - 1));
    final i = path.last as int;
    if (list is! List || i < 0 || i >= list.length) return null;
    if (list.length > 1) {
      list.removeAt(i);
    } else {
      list[i] = empty;
    }
    return taken;
  }
  return bkSetExprAt(block, arg, path, empty) ? taken : null;
}

// —— 多口积木：加一段、删一段、收起 / 加回收尾口（都要在宿主的 edit 里调）——

/// 这块积木还能不能再加一段（规格说它有段，而且没到上限）。
bool bkCanAddArm(BlockHost host, LcBlock block) {
  final spec = host.blockSpec(block.op)?.arms;
  return spec != null && block.arms.length < spec.max && block.arms.length < LcBlock.maxArms;
}

/// 收尾口现在是不是被收起来了、可以加回来。
bool bkCanShowTail(BlockHost host, LcBlock block) {
  final spec = host.blockSpec(block.op);
  return spec != null && spec.hasElse && spec.arms?.tailOptional == true && block.noElse && block.orElse.isEmpty;
}

/// 在末尾加一段（参数由宿主填默认值）。返回新的一段是第几段；加不了返回 -1。
int bkAddArm(BlockHost host, LcBlock block) {
  if (!bkCanAddArm(host, block)) return -1;
  block.arms.add(host.newArm(block));
  return block.arms.length - 1;
}

/// 删掉第 `arm` 段（连同里面的积木）。已经是最少的段数、或没有这一段：不删，返回 false。
bool bkRemoveArm(BlockHost host, LcBlock block, int arm) {
  final spec = host.blockSpec(block.op)?.arms;
  if (spec == null || arm < 0 || arm >= block.arms.length || block.arms.length <= spec.min) return false;
  block.arms.removeAt(arm);
  return true;
}

/// 把收尾口收起来（里面的积木一起删掉）/ 加回来。规格没说它可有可无：不动，返回 false。
bool bkSetTail(BlockHost host, LcBlock block, {required bool shown}) {
  final spec = host.blockSpec(block.op);
  if (spec == null || !spec.hasElse || spec.arms?.tailOptional != true) return false;
  if (shown == !block.noElse && (shown || block.orElse.isEmpty)) return false;
  if (!shown) block.orElse.clear();
  block.noElse = !shown;
  return true;
}

/// 两个值是不是一模一样（按 JSON 内容比）。
bool bkSameJson(Object? a, Object? b) {
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final k in a.keys) {
      if (!b.containsKey(k) || !bkSameJson(a[k], b[k])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!bkSameJson(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

/// 往“一串值”的末尾加一项。`path` 指到那个列表（例：`['items']`）。
bool bkAddListItem(BlockHost host, LcBlock block, String arg, BkExprPath path) {
  final list = bkExprAt(block, arg, path);
  if (list is! List || path.isEmpty) return false;
  final owner = asExpr(bkExprAt(block, arg, path.sublist(0, path.length - 1)));
  final name = path.last;
  final spec = owner == null || name is! String ? null : host.exprSpec(exprKind(owner) ?? '')?.arg(name);
  list.add(owner != null && spec != null ? host.newListItem(owner, spec) : defaultExprFor(LcType.any));
  return true;
}

/// 把模型里还没有位置的脚本（自动排的）按现在看到的位置写下来。
/// 用户第一次自己摆脚本（拖帽子、拖出新的一串）时调：从此每一串都有自己的位置，不会因为别的串动了而重叠。
void bkFreezeAuto(BlockHost host, BkCanvasLayout layout) {
  for (final p in layout.scripts) {
    if (!p.auto) continue;
    host.script(p.id)
      ?..x = p.origin.dx
      ..y = p.origin.dy;
  }
}

/// 一串变高以后，把它正下方那些摆过位置的脚本往下推同样的高度，免得压在一起。
/// `before` 是改之前的排布。自动排的脚本不用管（它们本来就跟着排）。只往下推，变矮了不往上收。
void bkPushDown(BlockHost host, BlockLayoutEngine engine, BkCanvasLayout before, String scriptId) {
  final old = before.placed(scriptId);
  final tree = host.script(scriptId);
  if (old == null || tree == null) return;
  final grow = engine.layoutScript(tree).size.height - old.bounds.height;
  if (grow <= 0) return;
  for (final p in before.scripts) {
    if (p.id == scriptId || p.auto) continue;
    final below = p.origin.dy >= old.bounds.bottom - 1;
    final overlaps = p.bounds.left < old.bounds.right && p.bounds.right > old.bounds.left;
    final t = host.script(p.id);
    final y = t?.y;
    if (below && overlaps && y != null) t!.y = y + grow;
  }
}

/// 预览时用：和 [bkPushDown] 同一条规矩，只是返回“每串该摆在哪”，不写模型。
Map<String, Offset> bkPushedOrigins(BkCanvasLayout before, String scriptId, double newHeight) {
  final origins = {for (final p in before.scripts) p.id: p.origin};
  final old = before.placed(scriptId);
  if (old == null) return origins;
  final grow = newHeight - old.bounds.height;
  if (grow <= 0) return origins;
  for (final p in before.scripts) {
    if (p.id == scriptId) continue;
    if (p.origin.dy >= old.bounds.bottom - 1 && p.bounds.left < old.bounds.right && p.bounds.right > old.bounds.left) origins[p.id] = p.origin.translate(0, grow);
  }
  return origins;
}
