/// 绑定在编辑器里的样子（第 5 期）：状态都按**初值**算一遍，画布照着画；Flutter 导出也用它把绑定“冻”成初值。
///
/// - 绑了的属性换成算出来的值；文字算出来是空的，画布上显示 `{说明}`（不然看不出这里有东西）。
/// - 双向绑定的控件显示状态的初值。
/// - 样式绑定并进样式。
/// - 显示条件 / 存在条件按初值不成立：[lcCondHolds] 是 false（画布调淡加角标，照样能选中）。
/// - “重复”：[lcRepeatScopes] 给出要画的每一份的环境。
library;

import 'package:lopicode/lowcode/bind_eval.dart';
import 'package:lopicode/lowcode/bind_model.dart';
import 'package:lopicode/lowcode/model.dart';

/// [n] 把绑定换成初值以后的样子；没有绑定就是 [n] 本身（同一个对象）。[placeholder]：空文字要不要换成 `{说明}`。
LcNode lcBoundNode(LcNode n, LcBindEnv env, {bool placeholder = true}) {
  if (n.isUnknown || !lcHasBindings(n)) return n;
  Map<String, dynamic>? props;
  for (final prop in lcBoundProps(n)) {
    final spec = lcBindable(n.type, prop);
    final expr = lcDataExpr(n, prop);
    if (spec == null || expr == null) continue;
    final v = lcEval(expr, env);
    final Object shown = switch (spec.type) {
      'bool' => lcEvalBool(v),
      'list' => v is List ? [for (final x in v) lcEvalText(x)] : const <String>[],
      _ => () {
        final t = lcEvalText(v);
        return t.isEmpty && placeholder ? '{${lcDescribeExpr(expr)}}' : t;
      }(),
    };
    (props ??= {...n.props})[prop] = shown;
  }
  final model = lcModelOf(n);
  final modelProp = lcModelProp(n.type);
  if (model != null && modelProp != null && env.has(model)) {
    final v = env.read(model);
    (props ??= {...n.props})[modelProp] = modelProp == 'checked' ? lcEvalBool(v) : (n.type == 'input' || n.type == 'textarea' ? lcEvalText(v) : v);
  }
  Map<String, String>? style;
  for (final e in lcStyleBinds(n).entries) {
    final t = lcEvalText(lcEval(e.value, env));
    if (t.isNotEmpty) (style ??= {...n.style})[e.key] = t;
  }
  if (props == null && style == null) return n;
  return LcNode(
    id: n.id,
    type: n.type,
    props: props ?? n.props,
    children: n.children,
    style: style ?? n.style,
    bind: n.bind,
    name: n.name,
    locked: n.locked,
    hidden: n.hidden,
    keptProps: n.keptProps,
    more: n.more,
  )..instSlots = n.instSlots;
}

/// 显示条件、存在条件按初值成不成立（没设条件＝成立）。
bool lcCondHolds(LcNode n, LcBindEnv env) {
  final show = lcShowIfExpr(n), render = lcRenderIfExpr(n);
  return (show == null || lcEvalBool(lcEval(show, env))) && (render == null || lcEvalBool(lcEval(render, env)));
}

/// “重复”要画的每一份的环境（最多 [LcRepeat.preview] 份）。没设重复＝null；列表是空的＝空表。
/// [all]：不管“画布先画几个”，有几项给几份（Flutter 导出用）。
List<LcBindEnv>? lcRepeatScopes(LcNode n, LcBindEnv env, {bool all = false}) {
  final rep = lcRepeatOf(n);
  if (rep == null) return null;
  final list = lcEval(rep.list, env);
  if (list is! List) return const [];
  final count = all ? list.length.clamp(0, 200) : list.length.clamp(0, rep.preview);
  return [
    for (var i = 0; i < count; i++) env.scoped({rep.item: list[i], rep.index: i}),
  ];
}
