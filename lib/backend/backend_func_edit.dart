/// 对后端文档里“函数 / 我的积木”的改动（积木第 4 版·第 2 阶段）：新建、改参数（各处调用跟着变）、删除、包成积木。
///
/// 都是直接改 [BeDocument] 的纯逻辑，不管撤销（编辑器宿主在外面包一次 `edit`）、不抛异常。
/// 调用按函数的 id 认（`call:<id>`），实参按参数名存，所以改名只要改定义、改参数才要动各处的调用。
library;

import 'package:lopicode/backend/backend_blocks.dart';
import 'package:lopicode/backend/backend_function.dart';
import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/lang/custom_block.dart';
import 'package:lopicode/lang/custom_block_edit.dart';
import 'package:lopicode/lang/lang.dart' show LParam;
import 'package:lopicode/lowcode/logic_model.dart';

/// 文档里所有的串：接口在前，函数的定义在后。
List<LcBlockTree> beTrees(BeDocument doc) => [...doc.routes, ...doc.functions];

/// 可能用到“我的积木”的所有串：接口、别的积木，加上类的方法、“创建时”、“程序开始时”、库积木当帽子的串。
/// “用了几处”和“删积木时把调用一起拿掉”都要数全（原来只数前两样）。
List<LcBlockTree> beUseTrees(BeDocument doc) => [...doc.routes, ...doc.functions, ...doc.core.trees, ...doc.hats];

/// 把一串积木（含各个口、匿名函数的口）里每个值过一遍 `f`，返回什么就换成什么（先里后外）。
void beRewriteExprs(List<LcBlock> blocks, Object? Function(Map<String, dynamic> e) f) {
  Object? rewrite(Object? v, int depth) {
    if (depth > kMaxExprDepth * 2 + 4 || v is List<LcBlock>) return v;
    if (v is List) {
      for (var i = 0; i < v.length; i++) {
        v[i] = rewrite(v[i], depth + 1);
      }
      return v;
    }
    final e = asExpr(v);
    if (e == null) return v;
    for (final k in e.keys.toList()) {
      if (k != kLcExprBody) e[k] = rewrite(e[k], depth + 1);
    }
    return f(e);
  }

  beVisitBlocks(blocks, (b) {
    for (final args in [b.args, for (final a in b.arms) a.args]) {
      for (final k in args.keys.toList()) {
        args[k] = rewrite(args[k], 0);
      }
    }
  });
}

/// 新拿出来的调用积木，这个槽里先放什么：下拉＝选中的那一项（文字）；是否槽＝“是 / 否”；值槽＝默认值的字面量，没有默认值是空文字。
/// [rest]＝这个参数是“剩下的全收”：放一个空列表，往里加几项，调用时就多带几个值。
Object? beSlotValue(CustomBlockSlot slot, {bool rest = false}) {
  final d = slot.defaultValue;
  if (rest && slot.kind == CustomSlotKind.value) return beRestSlotValue();
  return switch (slot.kind) {
    CustomSlotKind.choice => slot.options.contains(d) ? d : (slot.options.isEmpty ? '' : slot.options.first),
    CustomSlotKind.boolean => exBool(d == true),
    _ => d is num ? exNum(d) : (d is bool ? exBool(d) : exText(d is String ? d : '')),
  };
}

/// 一次调用的全部实参（按参数名），都是默认的样子。
Map<String, dynamic> beCallArgs(BeFunction f) => {for (final p in f.params) p.name: beSlotValue(f.look.slotFor(p.name), rest: p.rest)};

LcBlock beNewCallBlock(BeFunction f) => LcBlock(op: beCallOp(f.id), args: beCallArgs(f));
Map<String, dynamic> beNewCallExpr(BeFunction f) => {'e': beCallOp(f.id), ...beCallArgs(f)};

/// 给新积木起一个不重名的名字：`新积木`、`新积木2`…
String beFreshFunctionName(BeDocument doc, [String base = '新积木']) {
  final taken = {for (final f in doc.functions) f.name};
  if (!taken.contains(base)) return base;
  for (var i = 2; ; i++) {
    if (!taken.contains('$base$i')) return '$base$i';
  }
}

/// 加一个函数（画布上多一串“定义 …”）。参数重名的只留第一个、超过上限的丢掉；值槽“先放什么”同时当参数的默认值（帽子上看得见“次数＝1”）。
BeFunction beAddFunction(BeDocument doc, CustomBlockLook look, List<String> params, {List<LcBlock>? body, double? x, double? y}) {
  final list = <BeParam>[];
  for (final raw in params) {
    final p = raw.trim();
    if (p.isEmpty || list.length >= kBeMaxParams || list.any((o) => o.name == p)) continue;
    final slot = look.slotFor(p);
    list.add(BeParam(p, defaultValue: slot.kind == CustomSlotKind.value ? slot.defaultValue : null));
  }
  final f = BeFunction(id: beFreeFunctionId({for (final t in beTrees(doc)) t.id}), look: look, params: list, body: body, x: x, y: y);
  doc.functions.add(f);
  return f;
}

bool _isUse(Map<String, dynamic> e, String id) => e['e'] == beCallOp(id) || (e['e'] == 'funcRef' && e['fn'] == id);

/// 核心 2 的串（方法、“创建时”、“程序开始时”）里用没用到这块积木。“没人用的积木”那条提醒要看它
///（原来只看接口和别的积木：只在“程序开始时”或方法里用到的积木会被说成没人用）。
bool beFunctionUsedInCore(BeDocument doc, String id) {
  var hit = false;
  for (final t in [...doc.core.trees, ...doc.hats]) {
    beVisitBlocks(t.body, (b) {
      if (b.op == beCallOp(id)) hit = true;
      beVisitExprs(b, (e) => hit = hit || _isUse(e, id));
    });
    if (hit) return true;
  }
  return false;
}

/// 这块积木在别处用了几次（调用、当值、“这块积木本身”都算；它自己的定义里自己调自己不算）。
int beFunctionUses(BeDocument doc, String id) {
  var n = 0;
  for (final t in beUseTrees(doc)) {
    if (t.id == id) continue;
    beVisitBlocks(t.body, (b) {
      if (b.op == beCallOp(id)) n++;
      beVisitExprs(b, (e) => n += _isUse(e, id) ? 1 : 0);
    });
  }
  return n;
}

void _dropCalls(List<LcBlock> list, String op, [int depth = 0]) {
  if (depth > LcBlock.maxDepth + 2) return;
  list.removeWhere((b) => b.op == op);
  for (final b in list) {
    for (final child in [b.body, b.orElse, for (final a in b.arms) a.body, ...b.exprMouths]) {
      _dropCalls(child, op, depth + 1);
    }
  }
}

/// 删掉一个函数：定义那一串、各处单独成句的调用一起拿掉；当值用的地方（含“这块积木本身”）换成一段空文字。
bool beRemoveFunction(BeDocument doc, String id) {
  final at = doc.functions.indexWhere((f) => f.id == id);
  if (at < 0) return false;
  doc.functions.removeAt(at);
  for (final t in beUseTrees(doc)) {
    _dropCalls(t.body, beCallOp(id));
    beRewriteExprs(t.body, (e) => _isUse(e, id) ? exText('') : e);
  }
  return true;
}

/// 参数表变了：定义的参数、外观（模板、槽表）、函数体里读参数的地方、各处调用的槽一起跟着变。
/// [origin]`[i]`＝新参数 i 原来是第几个旧参数（null＝新加的）；没被指到的旧参数＝删了。
/// [lookIsNew]＝[look] 已经是按新参数表写好的（“编辑积木”页交回来的），不用再按改名去改它。
/// 返回各处调用里一共丢掉了几格内容（给界面提示）。
int beReshapeFunction(BeDocument doc, BeFunction f, CustomBlockLook look, List<BeParam> params, List<int?> origin, {bool lookIsNew = false}) {
  final old = [for (final p in f.params) p.clone()];
  LParam lp(BeParam p) => LParam(p.name, rest: p.rest);
  final oldL = [for (final p in old) lp(p)], newL = [for (final p in params) lp(p)];
  final nextLook = lookIsNew ? look : remapLook(look, oldParams: oldL, newParams: newL, origin: origin);
  f.look = nextLook;
  f.params
    ..clear()
    ..addAll(params);
  final renames = <String, String>{
    for (final (i, p) in params.indexed)
      if (i < origin.length && origin[i] != null && origin[i]! >= 0 && origin[i]! < old.length && old[origin[i]!].name != p.name) old[origin[i]!].name: p.name,
  };
  if (renames.isNotEmpty) beRenameParams(f.body, renames);

  var dropped = 0;
  final wasRest = {for (final p in old) p.name: p.rest};
  Map<String, dynamic> remap(Map<String, dynamic> args) {
    final r = remapCallArgsByName<Object?>(
      oldParams: oldL,
      newParams: newL,
      origin: origin,
      args: {
        for (final p in old)
          if (args.containsKey(p.name)) p.name: args[p.name],
      },
      fill: (p) => beSlotValue(nextLook.slotFor(p.name), rest: p.rest),
    );
    // 丢掉的那一格要是本来就空着（空文字、空列表）就不算“丢了内容”。
    dropped += r.dropped.where((d) => !_blank(d.value.value)).length;
    final out = <String, dynamic>{for (final e in r.args) e.key: e.value};
    // 普通参数变成“剩下的全收”（或反过来）：槽里的东西换个装法，内容不丢。
    for (final p in params) {
      final before = old.where((o) => out.containsKey(p.name) && (renames[o.name] ?? o.name) == p.name).firstOrNull;
      if (before == null || wasRest[before.name] == p.rest) continue;
      final v = out[p.name];
      if (p.rest && exprKind(v) != 'listLit') {
        out[p.name] = {
          'e': 'listLit',
          'items': [if (!_blank(v)) v],
        };
      } else if (!p.rest && exprKind(v) == 'listLit') {
        final items = exprField(v, 'items');
        final first = items is List && items.isNotEmpty ? items.first : null;
        if (items is List && items.length > 1) dropped += items.length - 1;
        out[p.name] = first ?? beSlotValue(nextLook.slotFor(p.name));
      }
    }
    return out;
  }

  final op = beCallOp(f.id);
  for (final t in beTrees(doc)) {
    beVisitBlocks(t.body, (b) {
      if (b.op != op) return;
      final next = remap(b.args);
      b.args
        ..clear()
        ..addAll(next);
    });
    beRewriteExprs(t.body, (e) {
      if (e['e'] != op) return e;
      final next = remap({...e}..remove('e'));
      e
        ..removeWhere((k, _) => k != 'e')
        ..addAll(next);
      return e;
    });
  }
  return dropped;
}

bool _blank(Object? v) {
  if (v == null || v == '') return true;
  if (exprKind(v) == 'text') return (exprString(v, 'v') ?? '').isEmpty;
  if (exprKind(v) == 'listLit') {
    final items = exprField(v, 'items');
    return items is! List || items.isEmpty;
  }
  return false;
}

/// 把一串积木里读参数的地方按 [renames]（旧名 → 新名）改掉。不进匿名函数自己又起了同名参数的地方——那里读的是它自己的。
void beRenameParams(List<LcBlock> blocks, Map<String, String> renames) {
  beRewriteExprs(blocks, (e) {
    final to = e['e'] == 'param' ? renames[e['name']] : null;
    if (to != null) e['name'] = to;
    return e;
  });
}

// —— 包成积木 ——

const Set<String> _loopOps = {'repeat', 'forEach', 'while', 'forever', 'forCount', 'forPairs'};

/// 从 [from] 这块往下相连的那一截（和它所在的那个列表）；路径不对返回 null。
({List<LcBlock> list, int index})? beTailAt(LcBlockTree tree, LcBlockPath from) {
  if (from.isEmpty) return null;
  final list = tree.listAt(from.sublist(0, from.length - 1), inElse: from.last.inElse, arm: from.last.arm);
  if (list == null || from.last.index < 0 || from.last.index >= list.length) return null;
  return (list: list, index: from.last.index);
}

bool _strayJump(List<LcBlock> list, int depth) {
  if (depth > LcBlock.maxDepth + 2) return false;
  for (final b in list) {
    if (b.op == 'break' || b.op == 'continue') return true;
    if (_loopOps.contains(b.op)) continue;
    if (_strayJump(b.body, depth + 1) || _strayJump(b.orElse, depth + 1) || b.arms.any((a) => _strayJump(a.body, depth + 1))) return true;
  }
  return false;
}

/// 这一截里读写了哪些“外面的名字”：不是这一截自己新建的变量、参数。`writes` 是被改的那些。
({List<String> reads, Set<String> writes, Set<String> params}) _outer(BeDocument doc, List<LcBlock> tail) {
  final own = beLocalNames(tail, beNamePattern);
  final ownParams = <String>{};
  final reads = <String>[], writes = <String>{}, params = <String>{};
  void read(Object? name) {
    if (name is String && name.isNotEmpty && !own.containsKey(name) && !reads.contains(name)) reads.add(name);
  }

  beVisitBlocks(tail, (b) {
    beVisitExprs(b, (e) {
      final ps = e['params'];
      if ((e['e'] == 'lambda' || e['e'] == 'lambdaExpr') && ps is List) ownParams.addAll(ps.whereType<String>());
    });
  });
  beVisitBlocks(tail, (b) {
    final spec = beBlockSpecs[b.op];
    for (final a in spec?.args ?? const <LcArgSpec>[]) {
      final v = b.args[a.name];
      if (a.kind == LcArgKind.variable && v is String && v.isNotEmpty && !own.containsKey(v)) {
        read(v);
        writes.add(v);
      }
    }
    beVisitExprs(b, (e) {
      if (e['e'] == 'var') read(e['name']);
      final p = e['name'];
      if (e['e'] == 'param' && p is String && !ownParams.contains(p)) {
        read(p);
        params.add(p);
      }
    });
  });
  return (reads: reads, writes: writes, params: params);
}

/// 这一截为什么包不了；能包返回 null。包成积木以后这几块是在另一个函数里跑的，所以：
/// 不能有“返回响应”“请求别的网址”（只有接口里能用）、不能有“返回”（它要结束的是外面那个函数）、
/// 不能有管外面循环的“跳出 / 跳过”、不能改外面的变量（改的是传进去的那一份，外面看不到）。
String? beWrapBlocker(BeDocument doc, LcBlockTree tree, LcBlockPath from) {
  final at = beTailAt(tree, from);
  if (at == null) return '这一段包不了';
  final tail = at.list.sublist(at.index);
  if (doc.functions.length >= kBeMaxFunctions) return '自定义积木已经有 $kBeMaxFunctions 块了，先删掉几块不用的';
  String? found;
  beVisitBlocks(tail, (b) {
    found ??= switch (b.op) {
      'respondJson' || 'respondText' => '这一段里有“返回响应”，它只能留在接口里。从它上面那块开始包，或者先把它拖开',
      'fetch' => '这一段里有“请求别的网址”，它只能留在接口里。先把它拖开再包',
      'return' || 'returnNothing' => '这一段里有“返回”，包进去以后它结束的就不是原来那个函数了。先把它拖开再包',
      _ => null,
    };
  });
  if (found != null) return found;
  if (_strayJump(tail, 0)) return '这一段里有管外面循环的“跳出 / 跳过”，包进去就找不到那个循环了。连循环一起包，或者先把它拖开';
  final outer = _outer(doc, tail);
  if (outer.writes.isNotEmpty) return '这一段改了外面的变量 ${outer.writes.first}，包成积木以后外面就看不到这个改动了。先把改它的那块拖开再包';
  if (outer.reads.length > kBeMaxParams) return '这一段用到了 ${outer.reads.length} 个外面的变量，一块积木最多 $kBeMaxParams 个参数。少包几块试试';
  return null;
}

/// “包成积木”：这一截用到了哪些外面的变量 / 参数（它们会变成新积木的参数），按第一次出现的顺序。
List<String> beWrapOuterNames(BeDocument doc, LcBlockTree tree, LcBlockPath from) {
  final at = beTailAt(tree, from);
  return at == null ? const [] : _outer(doc, at.list.sublist(at.index)).reads;
}

/// “包成积木”：把这一截搬进一个新定义，原处换成一次调用（槽里填同名的外面的变量 / 参数）。包不了返回 null（什么都不改）。
BeFunction? beWrapTail(BeDocument doc, LcBlockTree tree, LcBlockPath from, CustomBlockLook look, List<String> params) {
  if (beWrapBlocker(doc, tree, from) != null) return null;
  final at = beTailAt(tree, from);
  if (at == null) return null;
  final tail = at.list.sublist(at.index);
  final outer = _outer(doc, tail);
  if (outer.reads.any((n) => !params.contains(n))) return null;
  final f = beAddFunction(doc, look.copyWith(shape: CustomBlockShape.statement), params, body: tail);
  at.list.removeRange(at.index, at.list.length);
  // 定义里：读外面变量的地方改成读参数。
  beRewriteExprs(f.body, (e) => e['e'] == 'var' && params.contains(e['name']) ? beParam('${e['name']}') : e);
  at.list.add(
    LcBlock(
      op: beCallOp(f.id),
      args: {for (final p in f.params) p.name: outer.params.contains(p.name) ? beParam(p.name) : (outer.reads.contains(p.name) ? exVar(p.name) : beSlotValue(f.look.slotFor(p.name)))},
    ),
  );
  return f;
}
