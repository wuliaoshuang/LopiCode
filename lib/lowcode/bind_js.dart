/// 把绑定的值式子翻成一句 JavaScript（三种网页导出共用；“名字怎么读”每种导出不一样，由 [LcBindResolve] 说）。
///
/// 规矩和积木的值一样（logic_js_core.dart）：算术先过 `lcNum`，拼文字先过 `lcText`，等于用 `lcEq` 或 `===`。
/// 所以用了绑定的导出文件里一定要带 `lcJsRuntime`，另加这里的 [lcBindJsRuntime]。
/// 安全：模型里来的字符串只通过 `jsString` 进代码；读不懂的翻成 `null /* 原因 */`，永远是合法的表达式。
library;

import 'package:lopicode/lowcode/bind_model.dart';
import 'package:lopicode/lowcode/logic_expr.dart';
import 'package:lopicode/lowcode/logic_js_core.dart';

/// 一个名字怎么读：返回（代码，类型）；不认识的名字返回 null。
typedef LcBindResolve = JsExpr? Function(String name);

/// 绑定多用到的两个小工具（每份用了绑定的导出都带）。
const String lcBindJsRuntime = r'''
// 当成列表用：不是列表的（还没取到数据、填错了）当成空列表。
function lcList(v) {
  return Array.isArray(v) ? v : [];
}

// 列表有几项。
function lcLen(v) {
  return Array.isArray(v) ? v.length : 0;
}
''';

JsExpr _hole(String why) => JsExpr('null /* ${jsComment(why)} */', LcType.any);

JsExpr _num(JsExpr e) => e.type == LcType.number ? e : JsExpr('lcNum(${e.code})', LcType.number);
JsExpr _bool(JsExpr e) => e.type == LcType.boolean ? e : JsExpr('!!${e.wrapped}', LcType.boolean);

/// 转成文字（已经是文字的不动）。
JsExpr lcBindText(JsExpr e) => e.type == LcType.text ? e : JsExpr('lcText(${e.code})', LcType.text);

/// 转成“是 / 否”。
JsExpr lcBindBool(JsExpr e) => _bool(e);

String _numLiteral(num v) => v is int || (v == v.roundToDouble() && v.abs() < 1e15) ? '${v.round()}' : '$v';

/// 翻一个值式子。
JsExpr lcBindJs(Object? e, LcBindResolve resolve, [int depth = 0]) {
  if (depth >= kMaxExprDepth) return _hole('值套得太深，这里当成空的');
  JsExpr sub(String key) => lcBindJs(exprField(e, key), resolve, depth + 1);
  final kind = exprKind(e);
  switch (kind) {
    case null:
      return _hole('这里还没填');
    case 'text':
      final v = exprString(e, 'v');
      return v == null ? _hole('文字没填') : JsExpr(jsString(v), LcType.text);
    case 'num':
      final v = exprNum(e, 'v');
      if (v == null || !v.isFinite) return _hole('数字没填');
      return JsExpr(_numLiteral(v), LcType.number, atomic: v >= 0);
    case 'bool':
      final v = exprBool(e, 'v');
      return v == null ? _hole('“是 / 否”没填') : JsExpr('$v', LcType.boolean);
    case 'var':
      final name = exprString(e, 'name');
      final base = name == null ? null : resolve(name);
      if (base == null) return _hole('找不到 ${name ?? ''}');
      final path = lcPathOf(exprField(e, 'path'));
      if (path.isEmpty) return base;
      return JsExpr('${base.wrapped}${[for (final p in path) '?.[${jsString(p)}]'].join()}', LcType.any);
    case 'len':
      return JsExpr('lcLen(${sub('x').code})', LcType.number);
    case 'not':
      return JsExpr('!${sub('x').wrapped}', LcType.boolean);
    case 'join':
      final items = exprField(e, 'items');
      final parts = [
        if (items is List)
          for (final item in items) lcBindText(lcBindJs(item, resolve, depth + 1)),
      ];
      if (parts.isEmpty) return const JsExpr('""', LcType.text);
      if (parts.length == 1) return parts.single;
      return JsExpr([for (final p in parts) p.wrapped].join(' + '), LcType.text, atomic: false);
    case 'bin':
      final op = exprString(e, 'op');
      final l = sub('l'), r = sub('r');
      if (kArithmeticOps.contains(op)) {
        final code = '${_num(l).wrapped} $op ${_num(r).wrapped}';
        if (op == '/' || op == '%') return JsExpr('lcNum($code)', LcType.number);
        return JsExpr(code, LcType.number, atomic: false);
      }
      switch (op) {
        case '<' || '<=' || '>' || '>=':
          return JsExpr('${_num(l).wrapped} $op ${_num(r).wrapped}', LcType.boolean, atomic: false);
        case '==' || '!=':
          if (l.type == r.type && const [LcType.text, LcType.number, LcType.boolean].contains(l.type)) {
            return JsExpr('${l.wrapped} ${op == '==' ? '===' : '!=='} ${r.wrapped}', LcType.boolean, atomic: false);
          }
          return JsExpr('${op == '==' ? '' : '!'}lcEq(${l.code}, ${r.code})', LcType.boolean);
        case 'and' || 'or':
          return JsExpr('${_bool(l).wrapped} ${op == 'and' ? '&&' : '||'} ${_bool(r).wrapped}', LcType.boolean, atomic: false);
      }
      return _hole('不认识的运算 ${op ?? ''}');
    default:
      return _hole('不认识的值 $kind');
  }
}

/// 状态的类型在式子里算什么类型（列表、记录算 any）。
String lcBindTypeOf(String stateType) => const [LcType.text, LcType.number, LcType.boolean].contains(stateType) ? stateType : LcType.any;

/// CSS 属性名写成 JS 的样式键：`background-color` → `backgroundColor`。
String lcCssCamel(String prop) => prop.replaceAllMapped(RegExp('-([a-z])'), (m) => m[1]!.toUpperCase());
