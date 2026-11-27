/// 把自定义组件的实例展开成普通控件的子树（画布、网页 / Flutter 导出、“拆开”都用它）。不改文档。
///
/// - 展开后最外层节点的 id 就是实例自己的 id；里面的节点是 `<实例 id>__<定义里的 id>`，全页唯一。
/// - 插槽（定义里 `type: slot` 的占位节点）：实例的子节点按各自的 `slot` 分到各个插槽里
///   （没写、或者写的插槽定义里没有：算在兜底插槽——有默认插槽就是它，没有就是第一个）；
///   占位的位置换成填进来的内容，一个都没填就用占位节点自己的子节点（默认内容）。
///   同名的占位出现了两次（文件是手改的）：填进来的内容只放在第一个那里，后面的照默认内容画。
///   定义里一个插槽都没有，实例却带着子节点：这些子节点没地方放，展开结果里没有它们（文件里留着，图层面板看得到）。
/// - 三种用法：
///   · 导出（默认）：内容直接接在占位的位置上，占位节点本身不留；填进来的内容里的实例也一起展开。
///   · 画布（[markers]）：占位的位置留一个 `slot` 节点当记号，`props.host` 是实例的 id、`props.filled` 说明里面是不是填进来的；
///     填进来的内容就是页面里的原节点（不拷贝、不展开），画布拿它们按普通组件画，所以能选中、能改、能拖。
///   · 拆开（[deep] 为 false）：只拆这一层，里面套的实例原样留着；填进来的内容原样接过去（就是原来那几个节点）。
library;

import 'package:lopicode/lowcode/bind_model.dart';
import 'package:lopicode/lowcode/component_expand_live.dart';
import 'package:lopicode/lowcode/component_extras.dart';
import 'package:lopicode/lowcode/component_model.dart';
import 'package:lopicode/lowcode/component_ops.dart';
import 'package:lopicode/lowcode/front_emit_bridge.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/slots.dart';

final RegExp _hex = RegExp(r'^#[0-9a-fA-F]{6}$');

class LcExpander {
  LcExpander(this.doc, {this.deep = true, this.markers = false}) {
    // 页面里本来就长得像“展开后的 id”的节点（带 __ 的）要避开。绝大多数页面一个都没有。
    void scan(LcNode n) {
      if (n.id.contains('__')) taken.add(n.id);
      n.children.forEach(scan);
    }

    scan(doc.root);
  }

  final LcDocument doc;

  /// false＝只展开一层：里面套的别的组件实例原样留着（拆开实例时用）。
  final bool deep;

  /// true＝插槽的位置留记号（画布用）。
  final bool markers;
  final Set<String> taken = {};
  final Set<String> visiting = {};
  int budget = kComponentExpandBudget;

  /// 展开时冒出来的“每个实例一份”的组件状态（名字已经换成 `<实例 id>__<状态名>`），见 component_expand_live.dart。
  final List<LcVariable> hoisted = [];

  /// 展开时冒出来的事件处理（组件里的控件往外发事件、实例上给那个事件接了积木）。
  final List<LcSynthHandler> synth = [];

  /// 页面上的实例“这个事件接到的积木”从哪来：不给就用实例自己的 `on`。新的页面逻辑给的是转发记号（front_emit_bridge.dart）。
  Map<String, List<LcBlock>> Function(LcNode instance)? pageHandlers;

  /// 页面上（不在任何定义里）的一棵子树：里面的实例都展开，别的照原样（有子节点的拷一层壳）。
  LcNode outer(LcNode n) {
    if (n.type == 'component') return expand(n) ?? n;
    if (n.children.isEmpty) return n;
    return LcNode(
      id: n.id,
      type: n.type,
      props: n.props,
      style: n.style,
      bind: n.bind,
      name: n.name,
      locked: n.locked,
      hidden: n.hidden,
      keptProps: n.keptProps,
      more: n.more,
      // 页面里误放的插槽占位（它只在组件定义里有用）：只留它里面的内容。
      children: [
        for (final c in n.children)
          if (c.type == 'slot') ...[for (final x in c.children) outer(x)] else outer(c),
      ],
      raw: n.raw,
    )..instSlots = n.instSlots;
  }

  /// [content]：已经处理好的、要填进插槽的子节点；不给就用 [inst] 自己的子节点。
  /// [handlers]：这个实例那个组件的事件接到的积木；不给就用实例自己的 `on`（页面上的实例）。
  LcNode? expand(LcNode inst, [int depth = 0, List<LcNode>? content, Map<String, List<LcBlock>>? handlers]) {
    final ref = inst.type == 'component' ? inst.props['ref'] : null;
    final def = ref is String ? doc.component(ref) : null;
    // 定义没了、套得太深、绕回自己：这一层不展开。
    if (def == null || depth >= kComponentNestMax || visiting.contains(def.id) || budget <= 0) return null;
    // 填进来的内容属于外面那一层，先处理好（这时还没进这个定义：内容里再用到同一个组件不算循环）。
    final filled = content ?? (markers || !deep ? inst.children : [for (final c in inst.children) outer(c)]);
    final names = [for (final s in def.slots) s.name];
    final fallback = names.isEmpty ? null : (names.contains(kLcDefaultSlot) ? kLcDefaultSlot : names.first);
    String? slotOf(LcNode c) => names.contains(c.slot) ? c.slot : fallback;
    final placedSlots = <String>{};
    visiting.add(def.id);
    final values = instanceValues(def, inst);
    final rootId = inst.id;
    // 第 6 期的新东西（事件、变体、组件状态、绑定）：用了才走这条路；没用的和以前一个字不差。
    final live = lcDefIsLive(def) || lcInstanceIsLive(inst) ? LcLiveScope(def, inst, values, handlers ?? pageHandlers?.call(inst) ?? lcOnOf(inst)) : null;

    String mint(LcNode src) {
      var id = '${rootId}__${src.id}';
      while (taken.contains(id)) {
        id = '${id}_';
      }
      return id;
    }

    // 填进来的 / 默认的内容接到占位的位置上：它们在父节点里算哪个插槽，跟着占位节点走（占位可能放在里面另一个实例的插槽里）。
    LcNode seated(LcNode n, String? slot) {
      if (n.slot == slot) return n;
      if (!deep) return n..slot = slot; // 拆开：就是要改这几个节点本身
      return LcNode(
          id: n.id,
          type: n.type,
          props: n.props,
          style: n.style,
          bind: n.bind,
          name: n.name,
          locked: n.locked,
          hidden: n.hidden,
          keptProps: n.keptProps,
          more: {...n.more},
          children: n.children,
          raw: n.raw,
        )
        ..slot = slot
        ..instSlots = n.instSlots;
    }

    List<LcNode> build(LcNode src, bool isRoot) {
      budget--;
      if (src.type == 'slot') {
        final name = lcSlotNameOf(src);
        final mine = placedSlots.add(name)
            ? [
                for (final c in filled)
                  if (slotOf(c) == name) c,
              ]
            : const <LcNode>[];
        final inside = mine.isNotEmpty
            ? mine
            : [
                for (final c in src.children)
                  if (budget > 0) ...build(c, false),
              ];
        if (!markers) return [for (final c in inside) seated(c, src.slot)];
        return [
          LcNode(id: mint(src), type: 'slot', name: src.name, props: {'name': name, 'host': rootId, if (mine.isNotEmpty) 'filled': true}, children: inside)..slot = src.slot,
        ];
      }
      final id = isRoot ? rootId : mint(src);
      if (src.type == 'component') {
        final placed = LcNode(id: id, type: 'component', props: cloneLcProps(src.props), style: Map.of(src.style))..slot = src.slot;
        // 里面套的实例自己的设置（选的变体、绑的属性——已经改写成外面这一层的写法）照带。
        for (final k in const [kLcVariant, kLcData]) {
          if (live != null && src.more[k] != null) placed.more[k] = src.more[k];
        }
        // 定义里的实例也可以带着填好的内容（都是这个定义里的节点，按这个定义的规矩造出来）。
        final inner = [
          for (final c in src.children)
            if (budget > 0) ...build(c, false),
        ];
        return [(deep ? expand(placed, depth + 1, inner, live?.forwarded(src) ?? const {}) : null) ?? (placed..children.addAll(inner))];
      }
      final props = cloneLcProps(src.props);
      src.bind.forEach((attr, name) {
        final p = def.prop(name);
        if (p == null || !lcAttrFitsType(attr, src.type)) return;
        final v = values[name];
        if (attr == 'bg' || attr == 'color') {
          // 颜色必须是 #RRGGBB；不是就留着控件自己原来的颜色。
          if (v is String && _hex.hasMatch(v)) props[attr] = v.toUpperCase();
        } else {
          props[attr] = componentValueText(v);
        }
      });
      if (live != null) {
        for (final e in lcEmitsOf(src).entries) {
          final body = live.handlers[e.value.event];
          // 摊开以后没有“事件对象”了：处理里读“事件带来的值”的地方，换成那一项数据的式子。
          if (body != null && body.isNotEmpty) synth.add(LcSynthHandler(id, e.key, lcIsEmitBridge(body) ? lcEmitBridgeWithData(body, e.value) : lcWithEventData(body, lcFirstEmitArg(def, e.value))));
        }
      }
      // 节点上别的东西（在哪个插槽里、状态样式…）照带；名字、锁定、编辑器里隐藏是定义自己的事，不带到页面上。
      return [
        LcNode(
          id: id,
          type: src.type,
          props: props,
          style: live == null ? Map.of(src.style) : {...src.style, ...live.variantStyle(src.id)},
          keptProps: src.keptProps,
          more: {...src.more}..remove(live == null ? '' : kLcEmit),
          raw: src.raw,
          children: [
            for (final c in src.children)
              if (budget > 0) ...build(c, false),
          ],
        ),
      ];
    }

    final root = build(live?.root() ?? def.root, true).first;
    if (live != null) hoisted.addAll(live.states());
    visiting.remove(def.id);
    // 实例自己的摆放（宽度、外边距、样式、在父节点的哪个插槽里）盖在最外层。
    for (final key in const ['width', 'margin']) {
      if (inst.props.containsKey(key)) root.props[key] = inst.props[key];
    }
    root.style.addAll(inst.style);
    root.slot = inst.slot;
    return root;
  }
}

/// 一个实例里，有几个子节点现在没地方放（它的定义没有插槽了，或者定义找不到了）。
int lcHomelessContent(LcDocument doc, LcNode instance) {
  if (instance.type != 'component' || instance.children.isEmpty) return 0;
  final ref = instance.props['ref'];
  final LcComponentDef? def = ref is String ? doc.component(ref) : null;
  return def == null || def.slots.isEmpty ? instance.children.length : 0;
}
