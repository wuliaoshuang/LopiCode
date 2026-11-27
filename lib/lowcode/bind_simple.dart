/// 面板里填绑定的三种简单办法（第 5 期）和它们的存法之间的来回翻译。存法不变（来源 var / expr），
/// 以后“前端 1”接上值积木的小画布，存的还是同一种东西。
///
/// - 用一个值：`user`、`it.name` → 来源 var。
/// - 拼一段文字：`你好，{user}，共 {cartCount} 件` → join；花括号里是名字，可带 `.格子`，`名字.项数`＝列表有几项。
/// - 简单比较：左边一个值、一个比法、右边一个数 / 一段文字 / 另一个值 → bin；“是 / 不是”→ 直接用 / not。
library;

import 'package:lopicode/lowcode/bind_model.dart';
import 'package:lopicode/lowcode/logic_expr.dart';
import 'package:lopicode/lowcode/model.dart';

/// “项数”这个词（写在名字后面＝列表有几项）。
const String kLcLenWord = '项数';

final RegExp _ref = RegExp(r'^[A-Za-z_\u4e00-\u9fff][A-Za-z0-9_\u4e00-\u9fff]*(\.[A-Za-z0-9_\u4e00-\u9fff]+)*$');

/// `user` / `it.name` / `cart.项数` → 值式子；写得不对返回 null。
Map<String, dynamic>? lcRefExpr(String text) {
  final t = text.trim();
  if (!_ref.hasMatch(t)) return null;
  final parts = t.split('.');
  final len = parts.length > 1 && parts.last == kLcLenWord;
  final read = exRead(parts.first, parts.sublist(1, len ? parts.length - 1 : parts.length));
  return len ? exLen(read) : read;
}

/// 值式子 → `user` / `it.name` / `cart.项数`；不是这种简单的返回 null。
String? lcRefText(Object? e) {
  switch (exprKind(e)) {
    case 'var':
      final name = exprString(e, 'name');
      return name == null ? null : [name, ...lcPathOf(exprField(e, 'path'))].join('.');
    case 'len':
      final inner = lcRefText(exprField(e, 'x'));
      return inner == null ? null : '$inner.$kLcLenWord';
  }
  return null;
}

/// 一段带 `{名字}` 的文字 → 来源。没有花括号＝写死的文字（返回 null：等于没绑）；花括号里写错了，[onBad] 报是哪一段。
Map<String, dynamic>? lcTemplateSource(String text, {void Function(String bad)? onBad}) {
  final items = <Map<String, dynamic>>[];
  var any = false, at = 0;
  for (final m in RegExp(r'\{([^{}]*)\}').allMatches(text)) {
    if (m.start > at) items.add({'e': 'text', 'v': text.substring(at, m.start)});
    final ref = lcRefExpr(m[1]!);
    if (ref == null) {
      onBad?.call(m[0]!);
      return null;
    }
    items.add(ref);
    any = true;
    at = m.end;
  }
  if (!any) return null;
  if (at < text.length) items.add({'e': 'text', 'v': text.substring(at)});
  // 只有一个名字、前后没有别的字：就是“用一个值”。
  if (items.length == 1 && exprKind(items.single) == 'var') {
    return lcSrcVar(exprString(items.single, 'name')!, lcPathOf(exprField(items.single, 'path')));
  }
  return lcSrcExpr({'e': 'join', 'items': items});
}

/// 式子 → 带 `{名字}` 的文字；不是“拼文字”这种的返回 null。
String? lcTemplateText(Object? e) {
  final single = lcRefText(e);
  if (single != null) return '{$single}';
  if (exprKind(e) != 'join') return null;
  final items = exprField(e, 'items');
  if (items is! List) return null;
  final b = StringBuffer();
  for (final i in items) {
    if (exprKind(i) == 'text') {
      final v = exprString(i, 'v') ?? '';
      if (v.contains('{') || v.contains('}')) return null;
      b.write(v);
    } else {
      final r = lcRefText(i);
      if (r == null) return null;
      b.write('{$r}');
    }
  }
  return b.toString();
}

/// 比法：存的记号 → 给人看的叫法。`is` / `not` 不要右边。
const Map<String, String> kLcCompareOps = {'is': '是', 'not': '不是', '==': '等于', '!=': '不等于', '>': '大于', '>=': '不小于', '<': '小于', '<=': '不大于'};

/// 一条简单比较。
class LcCompare {
  const LcCompare(this.left, this.op, [this.right = '']);

  /// 左边：`user` / `it.price` / `cart.项数`。
  final String left;
  final String op;

  /// 右边：一个数、一段文字，或者 `{名字}`。
  final String right;

  /// 翻成来源；写得不对返回 null。
  Map<String, dynamic>? toSource() {
    final l = lcRefExpr(left);
    if (l == null || !kLcCompareOps.containsKey(op)) return null;
    if (op == 'is') return exprKind(l) == 'var' ? lcSrcVar(exprString(l, 'name')!, lcPathOf(exprField(l, 'path'))) : lcSrcExpr(l);
    if (op == 'not') return lcSrcExpr({'e': 'not', 'x': l});
    final r = right.trim();
    final Map<String, dynamic>? rhs;
    if (r.startsWith('{') && r.endsWith('}')) {
      rhs = lcRefExpr(r.substring(1, r.length - 1));
    } else {
      final n = num.tryParse(r);
      rhs = n != null && n.isFinite ? {'e': 'num', 'v': n} : {'e': 'text', 'v': right};
    }
    return rhs == null ? null : lcSrcExpr({'e': 'bin', 'op': op, 'l': l, 'r': rhs});
  }

  /// 式子 → 简单比较；不是这种的返回 null。
  static LcCompare? of(Object? e) {
    final direct = lcRefText(e);
    if (direct != null) return LcCompare(direct, 'is');
    if (exprKind(e) == 'not') {
      final x = lcRefText(exprField(e, 'x'));
      return x == null ? null : LcCompare(x, 'not');
    }
    if (exprKind(e) != 'bin') return null;
    final op = exprString(e, 'op');
    final l = lcRefText(exprField(e, 'l'));
    final r = exprField(e, 'r');
    if (l == null || op == null || !kLcCompareOps.containsKey(op) || op == 'is' || op == 'not') return null;
    final rightRef = lcRefText(r);
    final String? right = switch (exprKind(r)) {
      'num' => '${exprNum(r, 'v') ?? 0}'.replaceFirst(RegExp(r'\.0$'), ''),
      'text' => exprString(r, 'v') ?? '',
      _ => rightRef == null ? null : '{$rightRef}',
    };
    return right == null ? null : LcCompare(l, op, right);
  }
}

/// 一个“重复”带出来的名字。
class LcLocal {
  const LcLocal(this.name, this.label, {required this.isIndex, this.sample});
  final String name;
  final String label;
  final bool isIndex;

  /// 列表初值的第一项（面板拿它列出有哪些格子可以选）；没有是 null。
  final Object? sample;
}

/// 节点 [id] 外面（含它自己，[self] 为 true 时）套着的“重复”带出来的名字，从外到里。找不到这个节点返回空表。
List<LcLocal> lcLocalsAt(LcNode root, String id, {bool self = true, Object? Function(Map<String, dynamic> list)? firstOf}) {
  List<LcLocal>? walk(LcNode n, List<LcLocal> scope, int depth) {
    if (depth > 64) return null;
    final rep = lcCanWrapBind(n) ? lcRepeatOf(n) : null;
    final inner = rep == null ? scope : [...scope, LcLocal(rep.item, '这一项', isIndex: false, sample: firstOf?.call(rep.list)), LcLocal(rep.index, '第几个（从 0 数）', isIndex: true)];
    if (n.id == id) return self ? inner : scope;
    for (final c in n.children) {
      final hit = walk(c, inner, depth + 1);
      if (hit != null) return hit;
    }
    return null;
  }

  return walk(root, const [], 0) ?? const [];
}
