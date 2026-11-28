/// Vue 3 / React 导出里，“用了第 6 期新东西”的自定义组件怎么出成**单独的组件文件**（第四轮 B4）。
///
/// 以前（B2）：这种实例先摊开进页面再导出。现在 Vue / React 不摊开了——
/// - 组件文件自己带：属性、往外发的事件、组件自己的状态（每用一次各一份）、定义里的绑定、变体；
/// - 页面引用它：写死的属性照传、绑了状态的属性传式子、选的变体传名字、接了动作的事件挂一个处理函数。
/// 纯网页（每页一个独立的 .html，没有“组件文件”这回事）和 Flutter（事件要等页面逻辑的 Flutter 导出）仍然摊开，
/// 走的还是 export_live_doc.dart。
///
/// 这里是两种框架共用的那一半（不出代码，只把东西理好）：
/// - [lcFrameworkDoc]：给导出看的文档。实例上接的动作（`on`）落成这一页的一条处理，挂在一个**记号节点**上
///   （实例的一个子节点，`more.lcEvt`＝事件名）；页面脚本那一侧（`_page`，线 A 的接入点）一行不用改，
///   模板写到这个实例时把记号节点摘掉、换成组件上的事件监听。
/// - [LcLiveComp]：一个定义理好以后的样子——属性、变体（每组一个文字属性 `lcv_<组名>`）、自己的状态合成一张“状态表”，
///   定义里的绑定就能用页面那一套绑定生成器；变体的样式差别改写成“类名开关配样子”（B2 已有的机制）。
///
/// 事件带的数据（约定，线 A 做“当〔实例〕发出〔事件〕”时照这个接）：处理函数收到的 `event` 是
/// `{ lcEvent: 事件名, detail: { 数据名: 值… }, target: { value: 第一项数据 } }`。
/// 所以现成的“输入的内容”积木（`{e: event}`）在这种处理里读到的就是事件带的第一项数据。
library;

import 'dart:convert';

import 'package:lopicode/lowcode/bind_model.dart';
import 'package:lopicode/lowcode/comp_self_wire.dart';
import 'package:lopicode/lowcode/component_extras.dart';
import 'package:lopicode/lowcode/component_model.dart';
import 'package:lopicode/lowcode/component_ops.dart';
import 'package:lopicode/lowcode/export_bind_plan.dart';
import 'package:lopicode/lowcode/export_live_doc.dart';
import 'package:lopicode/lowcode/front_emit_bridge.dart';
import 'package:lopicode/lowcode/logic_expr.dart';
import 'package:lopicode/lowcode/logic_js_core.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:lopicode/lowcode/model.dart';

/// 记号节点上的字段：值是组件的事件名。
const String kLcEvtMark = 'lcEvt';

/// 组件文件里、页面脚本里都要的一小段：把要带出去的数据包成约定的样子。
const String kLcEvtJs = '''
// 组件往外发事件时带的东西：detail 里是带出去的数据；target.value 是第一项（页面上“输入的内容”读到的就是它）。
function lcEvt(name, detail) {
  const first = Object.keys(detail)[0];
  return { lcEvent: name, detail, target: { value: first === undefined ? "" : detail[first] } };
}''';

/// 一组变体在组件文件里是哪个属性。
String lcVariantProp(String group) => 'lcv_$group';

/// 变体落成的类名。
String lcVariantClass(LcVariant v) => 'lcv-${v.group}-${v.name}';

/// 这个实例要不要走“组件文件带新东西”这条路。
bool lcUsesLiveFile(LcComponentDef def, LcNode instance) => lcDefIsLive(def) || lcInstanceIsLive(instance);

/// 定义里哪些属性被里面的控件双向写（输入框、勾选框双向到一个属性上）。
Set<String> lcModelProps(LcComponentDef def) {
  final own = {for (final s in lcCompStates(def)) s.name};
  final out = <String>{};
  void walk(LcNode n, int depth) {
    if (depth > LcNode.maxDepth * 2) return;
    final m = lcModelOf(n);
    if (m != null && !own.contains(m) && def.prop(m) != null) out.add(m);
    for (final c in n.children) {
      walk(c, depth + 1);
    }
  }

  walk(def.root, 0);
  return out;
}

/// 实例把这个属性绑到了“一个状态本身”上（不带路径、不是式子）：返回状态名；不是返回 null。
String? lcPlainStateOf(Map<String, dynamic>? expr) => expr != null && expr['e'] == 'var' && expr['name'] is String && lcPathOf(expr['path']).isEmpty ? expr['name'] as String : null;

/// 把这个实例身上的记号节点摘下来：事件名 → 记号节点。模板写到实例时调用（之后实例的子节点里只剩真正填进插槽的东西）。
Map<String, LcNode> lcTakeEventMarks(LcNode instance) {
  final out = <String, LcNode>{};
  instance.children.removeWhere((c) {
    final e = c.more[kLcEvtMark];
    if (e is! String) return false;
    out[e] = c;
    return true;
  });
  return out;
}

/// 导出说明收尾：去重；“组件定义里的绑定这一版不导出”那句现在不成立了（组件文件自己带绑定），拿掉。
List<String> lcLiveNotes(List<String> notes) => [
  for (final n in {...notes})
    if (n != kNoteBindComponent) n,
];

/// React 里组件接事件的属性名：`on` + 首字母大写的事件名。
String lcReactEventAttr(String event) => 'on${event[0].toUpperCase()}${event.substring(1)}';

/// 这份文档里用了新东西的定义能不能各出一个组件文件：定义里读写的名字都得是它自己的（属性、组件自己的状态、
/// “重复”带出的项）。有哪个定义直接读了**页面的状态**（组件文件里够不着页面），整份文档就还照 B2 的做法摊开。
bool lcLiveFilesOk(LcDocument doc) => doc.components.every((d) => !lcDefIsLive(d) || _selfContained(d));

bool _selfContained(LcComponentDef def) {
  final known = <String>{for (final p in def.props) p.name, for (final s in lcCompStates(def)) s.name};
  final used = <String>{};
  void names(Object? v, int depth) {
    if (depth > kMaxExprDepth * 2 + 12) return;
    if (v is Map) {
      if ((v['e'] == 'var' || v['from'] == 'var') && v['name'] is String) used.add(v['name'] as String);
      for (final x in v.values) {
        names(x, depth + 1);
      }
    } else if (v is List) {
      for (final x in v) {
        names(x, depth + 1);
      }
    }
  }

  void walk(LcNode n, int depth) {
    if (depth > LcNode.maxDepth * 2) return;
    final r = n.more[kLcRepeat];
    if (r is Map) {
      for (final k in ['item', 'index']) {
        if (r[k] is String) known.add(r[k] as String);
      }
    }
    for (final f in [...kLcBindFields, kLcEmit]) {
      names(n.more[f], 0);
    }
    final m = lcModelOf(n);
    if (m != null) used.add(m);
    for (final c in n.children) {
      walk(c, depth + 1);
    }
  }

  walk(def.root, 0);
  for (final s in lcCompStates(def)) {
    names(s.derived, 0);
  }
  return known.containsAll(used);
}

/// 给 Vue / React 导出看的文档（见文件开头）。没有用了新东西的实例：原样返回 [doc]（旧页面逐字节不变）。
/// 出不了组件文件的（[lcLiveFilesOk] 为否）：照 B2 的做法把实例摊开。
LcDocument lcFrameworkDoc(LcDocument source) {
  final doc = lcSelfWired(source); // 步进器这类“没人接就自己记着”的先补好线
  if (!lcLiveFilesOk(doc)) return lcExportDoc(doc, allPages: true);
  final at = doc.pageIndex;
  var any = false;
  try {
    for (var i = 0; i < doc.pages.length && !any; i++) {
      any = lcTreeHasLiveInstance(doc, doc.pages[i].root);
    }
  } finally {
    doc.openPageAt(at);
  }
  if (!any) return doc;
  final copy = LcDocument.fromJson(jsonDecode(jsonEncode(doc.toJson())) as Map<String, dynamic>);
  for (var i = 0; i < copy.pages.length; i++) {
    copy.openPageAt(i);
    _markEvents(copy);
  }
  return copy..openPageAt(at);
}

void _markEvents(LcDocument doc) {
  // 新的页面逻辑（中途包·组件事件对接）：实例上的 `on` 不作数，接了帽子“当〔实例〕发出〔事件〕”的事件各落一条转发记号。
  final front = doc.logic.front != null;
  final hats = lcFrontEmitHats(doc.logic);
  void walk(LcNode n, int depth) {
    if (depth > LcNode.maxDepth * 2) return;
    // 先走子节点（填进插槽的东西里也可能有实例），再给自己加记号：免得走到刚加的记号节点上。
    for (final c in [...n.children]) {
      walk(c, depth + 1);
    }
    if (n.type != 'component' || !isSafeNodeId(n.id)) return;
    final ref = n.props['ref'];
    final def = ref is String ? doc.component(ref) : null;
    if (def == null) return;
    if (front) {
      for (final event in hats[n.id] ?? const <String>{}) {
        final e = lcCompEvent(def, event);
        final h = e == null ? null : doc.logic.addHandler(e.params.isEmpty ? 'click' : 'input', target: '${n.id}__on_$event');
        if (e == null || h == null) continue;
        h.body.add(lcEmitBridgeBlock(n.id, event));
        n.children.add(LcNode(id: '${n.id}__on_$event', type: 'spacer', name: '${def.name}·${e.label}', more: {kLcEvtMark: event}));
      }
      return;
    }
    lcOnOf(n).forEach((event, body) {
      final e = lcCompEvent(def, event);
      if (e == null) return;
      // 带数据的事件落成“输入内容变化时”的处理：这样处理里“输入的内容”读到的就是事件带的第一项数据。
      final h = doc.logic.addHandler(e.params.isEmpty ? 'click' : 'input', target: '${n.id}__on_$event');
      if (h == null) return;
      h.body.addAll([for (final b in body) b.clone()]);
      n.children.add(LcNode(id: '${n.id}__on_$event', type: 'spacer', name: '${def.name}·${e.label}', more: {kLcEvtMark: event}));
    });
  }

  walk(doc.root, 0);
}

/// 一个用了新东西的定义，理成组件文件要的样子。
class LcLiveComp {
  LcLiveComp._(this.def, this.root, this.plan, this.propVars, this.variantGroups, this.own, this.modelProps);

  factory LcLiveComp(LcDocument doc, LcComponentDef def) {
    final root = copyLcTree(def.root);
    final variants = lcVariants(def);
    final own = lcCompStates(def);
    final taken = {for (final s in own) s.name};
    // 变体：每组一个文字属性；样式差别写成“这个属性等于这个变体名时成立的类名”，带着样子。
    final groups = <String>[];
    final byId = <String, LcNode>{};
    void index(LcNode n) {
      byId[n.id] = n;
      n.children.forEach(index);
    }

    index(root);
    for (final v in variants) {
      if (taken.contains(lcVariantProp(v.group)) || def.prop(lcVariantProp(v.group)) != null) continue;
      if (!groups.contains(v.group)) groups.add(v.group);
      v.styles.forEach((id, style) {
        final n = byId[id];
        if (n == null || !lcCanWrapBind(n) || style.isEmpty) return;
        final raw = n.more[kLcClassIf];
        n.more[kLcClassIf] = [
          if (raw is List) ...raw,
          {
            'name': lcVariantClass(v),
            'when': lcSrcExpr({'e': 'bin', 'op': '==', 'l': exVar(lcVariantProp(v.group)), 'r': exText(v.name)}),
            'style': style,
          },
        ];
      });
    }
    final propVars = <LcVariable>[
      for (final p in def.props)
        if (!taken.contains(p.name)) LcVariable(name: p.name, type: p.type == 'color' ? 'text' : p.type, initial: p.defaultValue),
      for (final g in groups) LcVariable(name: lcVariantProp(g), type: 'text', initial: ''),
    ];
    final scope = LcDocument(
      title: def.name,
      root: root,
      logic: LcLogic(variables: [...propVars, ...own]),
      components: doc.components,
    );
    return LcLiveComp._(def, root, LcBindPlan.forced(scope), propVars, groups, own, lcModelProps(def));
  }

  final LcComponentDef def;

  /// 定义的树（拷的一份，变体已经改写进去）。
  final LcNode root;

  /// 这张“状态表”里：属性、变体属性、组件自己的状态。
  final LcBindPlan plan;

  /// 属性和变体属性（当成只读的状态）。
  final List<LcVariable> propVars;
  final List<String> variantGroups;

  /// 组件自己的状态（含派生值）。
  final List<LcVariable> own;

  /// 被里面的控件双向写的属性。
  final Set<String> modelProps;

  /// 定义里一个控件的事件往外发时带的数据：数据名 → 来源（按事件声明的先后；事件没声明的照存的先后）。
  List<MapEntry<String, Object?>> argsOf(LcEmit emit) {
    final order = [for (final p in lcCompEvent(def, emit.event)?.params ?? const <LcCompEventParam>[]) p.name];
    return [
      for (final name in order)
        if (emit.args.containsKey(name)) MapEntry(name, emit.args[name]),
      for (final e in emit.args.entries)
        if (!order.contains(e.key)) e,
    ];
  }
}
