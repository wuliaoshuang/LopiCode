/// 在编辑器里把绑定“按初值算一遍”：画布预览、Flutter 导出（把绑定冻成初值）用。
///
/// 规矩和导出的 JS 小工具（logic_js_core.dart 的 lcNum / lcText / lcEq）一致：算术一律按数字算（转不了的当 0，
/// 除以 0 当 0）；等于＝类型一样直接比，不一样都转成文字再比；拼文字把每段转成文字。
/// 任何输入都不抛异常：读不懂的值是 null。
library;

import 'package:lopicode/lowcode/bind_model.dart';
import 'package:lopicode/lowcode/logic_expr.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/state_model.dart';

/// 算值时的环境：这一页看得到的状态（页面的盖住项目级的）+ “重复”带出来的这一项 / 序号。
class LcBindEnv {
  LcBindEnv._(this._states, this._locals);

  /// [doc] 当前这一页看得到的状态都按初值算。
  factory LcBindEnv.of(LcDocument doc) => LcBindEnv._({for (final s in lcStatesInScope(doc)) s.name: s.variable}, const {});

  static final LcBindEnv empty = LcBindEnv._(const {}, const {});

  final Map<String, LcVariable> _states;
  final Map<String, Object?> _locals;
  final Set<String> _busy = {};

  bool get isEmpty => _states.isEmpty && _locals.isEmpty;

  /// 套一层“重复”的作用域。
  LcBindEnv scoped(Map<String, Object?> locals) => LcBindEnv._(_states, {..._locals, ...locals});

  /// 这个名字是不是“重复”带出来的。
  bool isLocal(String name) => _locals.containsKey(name);

  /// 这个名字现在有没有（重复带出来的，或者一个状态）。
  bool has(String name) => _locals.containsKey(name) || _states.containsKey(name);

  /// 读一个名字（初值；派生的现算，绕圈的当 null）。
  Object? read(String name) {
    if (_locals.containsKey(name)) return _locals[name];
    final v = _states[name];
    if (v == null) return null;
    if (!v.isDerived) return v.initial;
    if (!_busy.add(name)) return null;
    try {
      return lcEval(v.derived, this);
    } finally {
      _busy.remove(name);
    }
  }
}

num lcEvalNum(Object? v) {
  final n = switch (v) {
    final num x => x,
    final String s => num.tryParse(s.trim()),
    true => 1,
    false => 0,
    _ => null,
  };
  return n != null && n.isFinite ? n : 0;
}

String lcEvalText(Object? v) {
  if (v == null) return '';
  if (v is num) {
    if (!v.isFinite) return '$v';
    final r = double.parse(v.toDouble().toStringAsPrecision(12));
    return r == r.roundToDouble() && r.abs() < 1e15 ? '${r.round()}' : '$r';
  }
  if (v is List) return v.map(lcEvalText).join(',');
  if (v is Map) return '[object Object]';
  return '$v';
}

/// 按 JS 的“真假”看。
bool lcEvalBool(Object? v) => switch (v) {
  null || false => false,
  final num n => n != 0 && !n.isNaN,
  final String s => s.isNotEmpty,
  _ => true,
};

String _kindOf(Object? v) => v is num ? 'n' : (v is String ? 's' : (v is bool ? 'b' : (v == null ? 'u' : 'o')));

bool _eq(Object? a, Object? b) => _kindOf(a) == _kindOf(b) ? (a is List || a is Map ? identical(a, b) : a == b) : lcEvalText(a) == lcEvalText(b);

/// 算一个值式子。
Object? lcEval(Object? e, LcBindEnv env, [int depth = 0]) {
  if (depth >= kMaxExprDepth) return null;
  Object? sub(String key) => lcEval(exprField(e, key), env, depth + 1);
  switch (exprKind(e)) {
    case 'text':
      return exprString(e, 'v');
    case 'num':
      return exprNum(e, 'v');
    case 'bool':
      return exprBool(e, 'v');
    case 'var':
      final name = exprString(e, 'name');
      Object? v = name == null ? null : env.read(name);
      for (final p in lcPathOf(exprField(e, 'path'))) {
        v = v is Map ? v[p] : (v is List && int.tryParse(p) != null && int.parse(p) >= 0 && int.parse(p) < v.length ? v[int.parse(p)] : null);
      }
      return v;
    case 'len':
      final x = sub('x');
      return x is List ? x.length : 0;
    case 'not':
      return !lcEvalBool(sub('x'));
    case 'join':
      final items = exprField(e, 'items');
      return [
        if (items is List)
          for (final i in items) lcEvalText(lcEval(i, env, depth + 1)),
      ].join();
    case 'bin':
      final op = exprString(e, 'op');
      final l = sub('l'), r = sub('r');
      switch (op) {
        case '+':
          return lcEvalNum(l) + lcEvalNum(r);
        case '-':
          return lcEvalNum(l) - lcEvalNum(r);
        case '*':
          return lcEvalNum(l) * lcEvalNum(r);
        case '/':
          final d = lcEvalNum(r);
          return d == 0 ? 0 : lcEvalNum(lcEvalNum(l) / d);
        case '%':
          final d = lcEvalNum(r);
          return d == 0 ? 0 : lcEvalNum(lcEvalNum(l).remainder(d));
        case '<':
          return lcEvalNum(l) < lcEvalNum(r);
        case '<=':
          return lcEvalNum(l) <= lcEvalNum(r);
        case '>':
          return lcEvalNum(l) > lcEvalNum(r);
        case '>=':
          return lcEvalNum(l) >= lcEvalNum(r);
        case '==':
          return _eq(l, r);
        case '!=':
          return !_eq(l, r);
        case 'and':
          return lcEvalBool(l) && lcEvalBool(r);
        case 'or':
          return lcEvalBool(l) || lcEvalBool(r);
      }
  }
  return null;
}

/// 式子里读到的名字（含嵌在里面的）。
Set<String> lcExprNames(Object? e, [int depth = 0]) {
  final out = <String>{};
  void walk(Object? v, int d) {
    if (d > kMaxExprDepth * 2) return;
    if (v is Map) {
      if (v['e'] == 'var' && v['name'] is String) out.add(v['name'] as String);
      for (final x in v.values) {
        walk(x, d + 1);
      }
    } else if (v is List) {
      for (final x in v) {
        walk(x, d + 1);
      }
    }
  }

  walk(e, depth);
  return out;
}

/// 式子大概是什么类型（text / number / bool / list / record / any）。[typeOf]：一个名字的类型，不知道给 null。
String lcExprType(Object? e, String? Function(String name) typeOf) {
  switch (exprKind(e)) {
    case 'text' || 'join':
      return LcType.text;
    case 'num' || 'len':
      return LcType.number;
    case 'bool' || 'not':
      return LcType.boolean;
    case 'bin':
      final op = exprString(e, 'op');
      return kArithmeticOps.contains(op) ? LcType.number : LcType.boolean;
    case 'var':
      if (lcPathOf(exprField(e, 'path')).isNotEmpty) return LcType.any;
      final name = exprString(e, 'name');
      return (name == null ? null : typeOf(name)) ?? LcType.any;
  }
  return LcType.any;
}

/// 式子用一句人话说出来（面板的“药丸”上用）。
String lcDescribeExpr(Object? e, [int depth = 0]) {
  if (depth > 6) return '…';
  String sub(String key) => lcDescribeExpr(exprField(e, key), depth + 1);
  switch (exprKind(e)) {
    case 'text':
      return '“${exprString(e, 'v') ?? ''}”';
    case 'num':
      return lcEvalText(exprNum(e, 'v'));
    case 'bool':
      return exprBool(e, 'v') == true ? '是' : '否';
    case 'var':
      return [exprString(e, 'name') ?? '?', ...lcPathOf(exprField(e, 'path'))].join('.');
    case 'len':
      return '${sub('x')} 的项数';
    case 'not':
      return '不是 ${sub('x')}';
    case 'join':
      final items = exprField(e, 'items');
      return [
        if (items is List)
          for (final i in items) exprKind(i) == 'text' ? (exprString(i, 'v') ?? '') : '{${lcDescribeExpr(i, depth + 1)}}',
      ].join();
    case 'bin':
      final op = switch (exprString(e, 'op')) {
        '==' => '＝',
        '!=' => '≠',
        'and' => '并且',
        'or' => '或者',
        final String o => o,
        null => '?',
      };
      return '${sub('l')} $op ${sub('r')}';
  }
  return '（读不懂的式子）';
}
