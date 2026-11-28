/// 组件“开箱即用”（第四轮 B7）：定义上声明了 `hold`（`{prop, event}`）的组件——现在是内置组件库的步进器——
/// 放进页面以后不用接线就能用。
///
/// 组件里不能放逻辑，所以步进器是“受控”的：点加减只往外发“改了”（带着新值），页面得自己把“值”绑到一个状态、再给“改了”
/// 接“把这个状态设成事件带来的值”。这里在**导出前**替她把这两步补上（只改给导出看的那一份，她的页面文件一个字不动）：
/// - 实例没给这个事件接动作、“值”也没绑：给这一页添一个状态 `<实例 id>__<属性名>`（初值＝实例上填的值），值绑到它，事件写回它。
///   每个实例各一份。
/// - 实例没给这个事件接动作、“值”绑到了一个状态本身：事件写回那个状态（等于双向）。
/// - 给事件接了动作的：一概不动（她自己说了算）。
/// 不补的（照旧要自己接）：走新页面逻辑的页面（实例上的动作在那里不作数，事件要接帽子，归页面逻辑管）；放在“重复”里的实例
/// （每一份该各记各的，一个状态记不下）；组件里面套着的实例；“值”绑在拼出来、比出来的式子上的。
library;

import 'dart:convert';

import 'package:lopicode/lowcode/bind_model.dart';
import 'package:lopicode/lowcode/component_extras.dart';
import 'package:lopicode/lowcode/component_model.dart';
import 'package:lopicode/lowcode/logic_js_core.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/state_model.dart';

/// 定义上的字段名。
const String kLcHold = 'hold';

/// 这个定义声明的“没人接就自己记着”：哪个属性、哪个事件。没声明、写得不对返回 null。
({String prop, String event})? lcHoldOf(LcComponentDef def) {
  final raw = def.more[kLcHold];
  if (raw is! Map) return null;
  final prop = raw['prop'], event = raw['event'];
  if (prop is! String || event is! String || def.prop(prop) == null || lcCompEvent(def, event) == null) return null;
  return (prop: prop, event: event);
}

/// 自己记着时那个状态叫什么。
String lcHeldName(String instanceId, String prop) => '${instanceId}__$prop';

LcVariable? _state(LcDocument doc, String name) {
  for (final s in lcStatesInScope(doc)) {
    if (s.name == name) return s.variable;
  }
  return null;
}

typedef _Todo = ({LcNode inst, String prop, String event, String? toState});

List<_Todo> _todos(LcDocument doc) {
  final out = <_Todo>[];
  if (doc.logic.front != null) return out;
  void walk(LcNode n, bool repeated, int depth) {
    if (depth > LcNode.maxDepth * 2) return;
    final inRepeat = repeated || lcRepeatOf(n) != null;
    if (n.type == 'component' && !inRepeat && isSafeNodeId(n.id)) {
      final ref = n.props['ref'];
      final def = ref is String ? doc.component(ref) : null;
      final hold = def == null ? null : lcHoldOf(def);
      if (hold != null && lcOnOf(n)[hold.event] == null) {
        final e = lcDataExpr(n, hold.prop);
        if (e == null) {
          if (LcVariable.namePattern.hasMatch(lcHeldName(n.id, hold.prop))) out.add((inst: n, prop: hold.prop, event: hold.event, toState: null));
        } else if (e['e'] == 'var' && e['name'] is String && lcPathOf(e['path']).isEmpty) {
          final name = e['name'] as String;
          final v = _state(doc, name);
          if (v != null && !v.isDerived) out.add((inst: n, prop: hold.prop, event: hold.event, toState: name));
        }
      }
    }
    for (final c in n.children) {
      walk(c, inRepeat, depth + 1);
    }
  }

  walk(doc.root, false, 0);
  return out;
}

final Expando<({String sig, LcDocument wired})> _hereCache = Expando('lcSelfWiredHere');

/// 画布用的：只看**现在这一页**，该补线的补上（画布和导出看到的是同一份状态，步进器的数跟着它自己记的那个状态走）。
/// 没有要补的原样交回 [doc]。整份拷文档很贵，所以记着上一次的结果：这一页要补的线、页面里的状态都没变就直接用
/// （画布只拿它算“状态现在是多少”，别的改动不影响）。不改 [doc]、不换页。
LcDocument lcSelfWiredHere(LcDocument doc) {
  final todos = _todos(doc);
  if (todos.isEmpty) return doc;
  final sig = jsonEncode([
    doc.pageIndex,
    for (final t in todos) [t.inst.id, t.inst.props['ref'], t.prop, t.event, t.toState, t.inst.props['values']],
    for (final s in lcStatesInScope(doc)) s.variable.toJson(),
  ]);
  final hit = _hereCache[doc];
  if (hit != null && hit.sig == sig) return hit.wired;
  final wired = lcSelfWired(doc);
  _hereCache[doc] = (sig: sig, wired: wired);
  return wired;
}

/// 测试用：[lcSelfWired] 一共真的拷了几次文档。
int lcSelfWiredCopies = 0;

/// 给导出看的文档：该补线的补上。没有要补的原样交回 [doc]（所以别的页面导出一个字不变）。不改 [doc]。
LcDocument lcSelfWired(LcDocument doc) {
  final at = doc.pageIndex;
  var any = false;
  try {
    for (var i = 0; i < doc.pages.length && !any; i++) {
      doc.openPageAt(i);
      any = _todos(doc).isNotEmpty;
    }
  } finally {
    doc.openPageAt(at);
  }
  if (!any) return doc;
  lcSelfWiredCopies++;
  final copy = LcDocument.fromJson(jsonDecode(jsonEncode(doc.toJson())) as Map<String, dynamic>);
  for (var i = 0; i < copy.pages.length; i++) {
    copy.openPageAt(i);
    for (final t in _todos(copy)) {
      var name = t.toState;
      if (name == null) {
        name = lcHeldName(t.inst.id, t.prop);
        if (_state(copy, name) != null) continue; // 名字被占了：不硬来
        final ref = t.inst.props['ref'];
        final def = copy.component(ref as String)!;
        final values = t.inst.props['values'];
        final given = values is Map ? values[t.prop] : null;
        final p = def.prop(t.prop)!;
        final initial = given ?? p.defaultValue;
        copy.logic.variables.add(LcVariable(name: name, type: initial is num ? 'number' : (initial is bool ? 'bool' : 'text'), initial: initial));
        lcSetData(t.inst, t.prop, {'from': 'var', 'name': name});
      }
      lcSetOn(t.inst, t.event, [
        LcBlock(
          op: 'setVar',
          args: {
            'name': name,
            'value': {'e': 'event'},
          },
        ),
      ]);
    }
  }
  return copy..openPageAt(at);
}
