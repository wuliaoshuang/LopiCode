/// 展开实例时第 6 期新东西怎么落地（事件、变体、组件自己的状态、实例属性绑到页面状态上、定义里的绑定）。
/// 只有“用了新东西”的定义 / 实例才走这里（[lcDefIsLive] / [lcInstanceIsLive]）；别的照原来的路展开，结果和以前一个字不差。
///
/// 办法（纯粹是把树改写一遍，所以画布、纯网页导出、Flutter 导出现成的绑定机制直接能用）：
/// - **定义里的绑定读到组件的属性**：换成这个实例给的东西——实例把属性绑到页面状态上的，换成那个式子；写死的，换成那个值。
///   老写法（`bind`：属性 → 组件属性名）遇到“实例把这个属性绑到了状态上”时，改写成一条普通的绑定。
/// - **定义里的绑定读到组件自己的状态**：每个实例一份——名字换成 `<实例 id>__<状态名>`，这份状态记在 [LcExpander.hoisted] 里，
///   由调用的人（导出、画布算初值）当成这一页多出来的状态。
/// - **双向**绑到组件属性上：实例把这个属性绑到一个状态本身时，就双向到那个状态；不然只是初值。
/// - **变体**：选中的变体的样式差别叠在定义的样式上。
/// - **往外发**：定义里某个控件的事件往外发成组件的事件，实例上给那个事件接了积木的——记进 [LcExpander.synth]，
///   由导出的人合成一条“当这个控件被点击”的处理。
library;

import 'package:lopicode/lowcode/bind_model.dart';
import 'package:lopicode/lowcode/bind_refs.dart';
import 'package:lopicode/lowcode/box_off.dart';
import 'package:lopicode/lowcode/component_extras.dart';
import 'package:lopicode/lowcode/component_model.dart';
import 'package:lopicode/lowcode/component_ops.dart';
import 'package:lopicode/lowcode/logic_expr.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/slot_gives.dart';

/// 展开出来的一条事件处理：[nodeId] 这个控件的 [event]（click / input）发生时做 [body]。
class LcSynthHandler {
  const LcSynthHandler(this.nodeId, this.event, this.body);
  final String nodeId;
  final String event;
  final List<LcBlock> body;
}

/// 组件自己的状态在页面上叫什么（每个实例一份）。
String lcHoistedName(String instanceId, String state) => '${instanceId}__$state';

void _reads(Object? v, List<Map<Object?, Object?>> out, [int depth = 0]) {
  if (depth > kMaxExprDepth * 2 + 8) return;
  if (v is Map) {
    if ((v['e'] == 'var' || v['from'] == 'var') && v['name'] is String) out.add(v);
    for (final x in v.values) {
      _reads(x, out, depth + 1);
    }
  } else if (v is List) {
    for (final x in v) {
      _reads(x, out, depth + 1);
    }
  }
}

Map<String, dynamic> _literal(Object v) => switch (v) {
  final num n => exNum(n),
  final bool b => exBool(b),
  _ => exText(componentValueText(v)),
};

/// 一个实例展开时的作用域。
class LcLiveScope {
  LcLiveScope(this.def, this.instance, this.values, this.handlers)
    : variants = lcVariants(def),
      picked = lcInstanceVariants(def, instance),
      stateNames = {for (final s in lcCompStates(def)) s.name: lcHoistedName(instance.id, s.name)},
      propExprs = {for (final p in def.props) p.name: ?lcDataExpr(instance, p.name)};

  final LcComponentDef def;
  final LcNode instance;
  final Map<String, Object> values;

  /// 组件的事件 → 实例（或更外面一层）给它接的积木。
  final Map<String, List<LcBlock>> handlers;
  final List<LcVariant> variants;
  final Map<String, String> picked;
  final Map<String, String> stateNames;

  /// 实例把哪些属性绑到了外面的式子上（已经是外面那一层的写法）。
  final Map<String, Map<String, dynamic>> propExprs;

  /// 写死的列表属性没有“字面量”的写法：当成这个实例多出来的一个状态（名字 `<实例 id>__p_<属性名>`）。
  final Map<String, LcVariable> _listProps = {};

  Map<String, dynamic> _valueOf(String prop) {
    if (propExprs[prop] != null) return copyExpr(propExprs[prop])!;
    final v = values[prop] ?? '';
    if (v is! List) return _literal(v);
    final name = lcHoistedName(instance.id, 'p_$prop');
    _listProps.putIfAbsent(prop, () => LcVariable(name: name, type: 'list', initial: v));
    return exVar(name);
  }

  void _rewriteRead(Map<Object?, Object?> m) {
    final name = m['name'] as String;
    final hoisted = stateNames[name];
    if (hoisted != null) {
      m['name'] = hoisted;
      return;
    }
    if (def.prop(name) == null) return;
    final r = _valueOf(name);
    final path = lcPathOf(m['path']);
    if (r['e'] == 'var' && r['name'] is String) {
      final full = [...lcPathOf(r['path']), ...path];
      m['name'] = r['name'];
      full.isEmpty ? m.remove('path') : m['path'] = full;
      return;
    }
    final src = m['from'] == 'var';
    m.clear();
    if (src) {
      m['from'] = 'expr';
      m['expr'] = r;
    } else {
      m.addAll(r);
    }
  }

  void _rewrite(Object? expr, Set<String> locals) {
    final found = <Map<Object?, Object?>>[];
    _reads(expr, found);
    for (final m in found) {
      if (!locals.contains(m['name'])) _rewriteRead(m);
    }
  }

  /// 定义的树拷一份、按这个实例改写好（绑定里的名字、双向、老写法的 `bind`）。
  LcNode root() {
    final copy = copyLcTree(def.root);
    lcWalkBindings(
      copy,
      (site) => _rewrite(site.expr, site.locals),
      onModel: (n, state, locals) {
        if (locals.contains(state)) return;
        final hoisted = stateNames[state];
        if (hoisted != null) return lcSetModel(n, hoisted);
        if (def.prop(state) == null) return;
        final e = propExprs[state];
        if (e != null && e['e'] == 'var' && e['name'] is String && lcPathOf(e['path']).isEmpty) return lcSetModel(n, e['name'] as String);
        // 没接到一个状态本身上：只是初值。
        lcSetModel(n, null);
        final prop = lcModelProp(n.type);
        if (prop == null || e != null) return;
        if (n.type == 'slider') {
          if (values[state] is num) n.props[prop] = values[state]; // 滑块的值是数
        } else {
          n.props[prop] = prop == 'checked' ? values[state] == true : componentValueText(values[state]);
        }
      },
    );
    void emitArgs(LcNode n) {
      final raw = n.more[kLcEmit];
      if (raw is Map) _rewrite(raw, const {});
      // 老写法接到的属性，实例把它绑到了状态上：改成一条普通绑定（颜色走样式绑定）。
      for (final attr in n.bind.keys.toList()) {
        final e = propExprs[n.bind[attr]];
        if (e == null || !lcAttrFitsType(attr, n.type)) continue;
        n.bind.remove(attr);
        final src = lcSrcExpr(copyExpr(e)!);
        if (attr == 'bg' || attr == 'color') {
          lcSetStyleBind(n, attr == 'bg' ? 'background-color' : 'color', src);
        } else {
          lcSetData(n, attr, src);
        }
      }
      n.children.forEach(emitArgs);
    }

    emitArgs(copy);
    // 插槽给外面的数据（slot_gives.dart）：式子在定义里算，一样按这个实例改写；占位外面那层“重复”带出来的名字不动。
    void gives(LcNode n, Set<String> locals) {
      final rep = lcRepeatOf(n);
      final inner = rep == null ? locals : {...locals, rep.item, rep.index};
      if (n.type == 'slot' && n.more[kLcGives] is Map) _rewrite(n.more[kLcGives], inner);
      for (final c in n.children) {
        gives(c, inner);
      }
    }

    gives(copy, const {});
    lcBoxFoldLiterals(copy);
    return copy;
  }

  /// 这个实例那一份状态（名字已经换好；派生值的式子里的名字也换好）。
  List<LcVariable> states() => [
    ..._listProps.values,
    for (final s in lcCompStates(def))
      () {
        final v = s.clone()..name = stateNames[s.name]!;
        if (v.derived != null) _rewrite(v.derived, const {});
        return v;
      }(),
  ];

  /// 选中的变体给定义里这个节点叠的样式。
  Map<String, String> variantStyle(String nodeId) => lcVariantStyleFor(variants, picked, nodeId);

  /// 定义里套着的另一个实例：它那个组件的事件在这里接到谁身上（往外转发的，接到外面那一层给的积木上）。
  Map<String, List<LcBlock>> forwarded(LcNode inner) => {for (final e in lcEmitsOf(inner).entries) e.key: ?handlers[e.value.event]};
}

/// 往外发时带的第一项数据（按事件声明的先后；没声明的照存的先后）的式子；没带数据返回 null。
Map<String, dynamic>? lcFirstEmitArg(LcComponentDef def, LcEmit emit) {
  for (final p in lcCompEvent(def, emit.event)?.params ?? const <LcCompEventParam>[]) {
    if (emit.args.containsKey(p.name)) return lcSrcExprOf(emit.args[p.name]);
  }
  return emit.args.isEmpty ? null : lcSrcExprOf(emit.args.values.first);
}

/// 把一串积木里读“事件带来的值”（`{e: event}`）的地方换成 [data]（没有就换成空字）。交回的是拷出来的一份。
List<LcBlock> lcWithEventData(List<LcBlock> body, Map<String, dynamic>? data) {
  Object? swap(Object? v, int depth) {
    if (depth > kMaxExprDepth * 2 + 8) return v;
    if (v is Map) {
      if (v['e'] == 'event') return data == null ? exText('') : copyExpr(data);
      return <String, dynamic>{for (final e in v.entries) '${e.key}': swap(e.value, depth + 1)};
    }
    return v is List ? [for (final x in v) swap(x, depth + 1)] : v;
  }

  LcBlock one(LcBlock b) {
    final c = b.clone();
    for (final k in c.args.keys.toList()) {
      c.args[k] = swap(c.args[k], 0);
    }
    final inner = lcWithEventData(c.body, data), other = lcWithEventData(c.orElse, data);
    c.body
      ..clear()
      ..addAll(inner);
    c.orElse
      ..clear()
      ..addAll(other);
    return c;
  }

  return [for (final b in body) one(b)];
}
