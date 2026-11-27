/// 导出前把“用了第 6 期新东西的组件实例”化成普通页面的样子（纯网页、Flutter 两种导出用；它们本来就把实例摊开）。
///
/// 页面里没有这种实例：原样返回 [doc]（所以旧页面的导出逐字节不变）。有：返回一份**只给导出看**的文档——
/// 当前这一页的树已经展开；每个实例那一份组件状态成了这一页的状态；“组件里的按钮往外发事件、实例上接了积木”
/// 成了一条“当那个按钮被点击”的处理。别的页、主题、项目级状态都是原来的。不改 [doc]。
library;

import 'package:lopicode/lowcode/component_expand.dart';
import 'package:lopicode/lowcode/component_extras.dart';
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
      );
      pages.add(LcPage(id: p.id, title: p.title, root: live.tree, logic: logic, more: p.more));
      changed = true;
    }
  } finally {
    doc.openPageAt(at);
  }
  if (!changed) return doc;
  final first = pages.first;
  return LcDocument(
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
}
