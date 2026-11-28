/// 导出前把“用了第 6 期新东西的组件实例”化成普通页面的样子（纯网页、Flutter 两种导出用；它们本来就把实例摊开）。
///
/// 页面里没有这种实例：原样返回 [doc]（所以旧页面的导出逐字节不变）。有：返回一份**只给导出看**的文档——
/// 当前这一页的树已经展开；每个实例那一份组件状态成了这一页的状态；“组件里的按钮往外发事件、实例上接了积木”
/// 成了一条“当那个按钮被点击”的处理。别的页、主题、项目级状态都是原来的。不改 [doc]。
library;

import 'package:lopicode/lowcode/component_expand.dart';
import 'package:lopicode/lowcode/component_extras.dart';
import 'package:lopicode/lowcode/front_emit_bridge.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:lopicode/lowcode/model.dart';

/// 这棵树里有没有用了新东西的实例（定义用了，或者实例自己用了）。
bool lcTreeHasLiveInstance(LcDocument doc, LcNode root, [Set<String>? seen]) {
  // 组件互相套成圈的文档也会走到这里：看过的定义不再看第二遍。
  final visited = seen ?? <String>{};
  var any = false;
  void walk(LcNode n, int depth) {
    if (any || depth > LcNode.maxDepth * 2) return;
    if (n.type == 'component') {
      final ref = n.props['ref'];
      final def = ref is String ? doc.component(ref) : null;
      if (def != null && (lcInstanceIsLive(n) || lcDefIsLive(def) || (visited.add(def.id) && lcTreeHasLiveInstance(doc, def.root, visited)))) any = true;
    }
    for (final c in n.children) {
      walk(c, depth + 1);
    }
  }

  walk(root, 0);
  return any;
}

/// 当前这一页展开以后多出来的东西。
class LcLivePage {
  LcLivePage(this.tree, this.states, this.handlers);
  final LcNode tree;
  final List<LcVariable> states;
  final List<LcHandler> handlers;
}

LcLivePage lcLivePage(LcDocument doc) {
  final x = LcExpander(doc);
  // 新的页面逻辑：实例上的 `on` 不作数；接了帽子“当〔实例〕发出〔事件〕”的事件落成转发记号。
  if (doc.logic.front != null) {
    final hats = lcFrontEmitHats(doc.logic);
    x.pageHandlers = (inst) => lcEmitBridgeHandlers(hats, inst.id);
  }
  final tree = x.outer(doc.root);
  final taken = {for (final h in doc.logic.handlers) h.id};
  var n = 1;
  final handlers = <LcHandler>[];
  for (final s in x.synth) {
    while (taken.contains('hc$n')) {
      n++;
    }
    taken.add('hc$n');
    handlers.add(LcHandler(id: 'hc$n', event: s.event, target: s.nodeId, body: [for (final b in s.body) b.clone()]));
  }
  return LcLivePage(tree, x.hoisted, handlers);
}

final Expando<LcDocument> _sourceOf = Expando('lcExportSource');
final Expando<Set<String>> _synthOf = Expando('lcExportSynth');

/// [lcExportDoc] 交回的文档里，这一页的处理中哪几条是“组件里的控件往外发事件、实例上接了动作”合成出来的（处理的 id）。
/// 不是它化出来的逻辑＝空的。Flutter 导出只把这几条翻成代码（页面自己的积木逻辑它一直不导出）。
Set<String> lcSynthHandlerIds(LcLogic logic) => _synthOf[logic] ?? const {};

/// [lcExportDoc] 交回的文档是从哪份文档化出来的（不是它化出来的就交回自己）。
/// 新的页面逻辑“对着页面的检查”要对着原来的页面查：摊开以后实例已经不是实例了，帽子“当〔实例〕发出〔事件〕”会被误判成挂错了地方。
LcDocument lcExportSource(LcDocument doc) => _sourceOf[doc] ?? doc;

/// 导出看的文档（见文件开头）。[allPages]：每一页都这样处理（Flutter 导出一次出所有页）；不然只处理当前这一页。
LcDocument lcExportDoc(LcDocument doc, {bool allPages = false}) {
  final at = doc.pageIndex;
  final pages = <LcPage>[];
  var changed = false;
  try {
    for (var i = 0; i < doc.pages.length; i++) {
      final p = doc.pages[i];
      if ((!allPages && i != at) || !lcTreeHasLiveInstance(doc, p.root)) {
        pages.add(p);
        continue;
      }
      doc.openPageAt(i);
      final live = lcLivePage(doc);
      final own = {for (final v in p.logic.variables) v.name};
      final logic = LcLogic(
        variables: [
          ...p.logic.variables,
          for (final v in live.states)
            if (!own.contains(v.name)) v,
        ],
        handlers: [...p.logic.handlers, ...live.handlers],
        // 新的页面逻辑和它用上的库要带着（不带的话这一页就被当成旧逻辑、只剩一堆空壳处理）。
        uses: p.logic.uses,
        front: p.logic.front,
      )..loaded = p.logic.loaded;
      _synthOf[logic] = {for (final h in live.handlers) h.id};
      pages.add(LcPage(id: p.id, title: p.title, root: live.tree, logic: logic, more: p.more));
      changed = true;
    }
  } finally {
    doc.openPageAt(at);
  }
  if (!changed) return doc;
  final first = pages.first;
  final out = LcDocument(
    title: first.title,
    root: first.root,
    logic: first.logic,
    pageId: first.id,
    pages: pages.skip(1).toList(),
    components: doc.components,
    keptComponents: doc.keptComponents,
    fileVersion: doc.fileVersion,
    more: doc.more,
    sharedNav: doc.sharedNav,
    sharedTop: doc.sharedTop,
  )..openPageAt(at);
  _sourceOf[out] = doc;
  return out;
}
