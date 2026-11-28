/// 插槽内容拿到组件里的数据（第四轮 B8；格式见 docs/blocks-v5-parts/E-editor-components.md §10.16、docs/lowcode-page-format-v3.md）。
///
/// - **定义这一头**：组件定义里的插槽占位节点（`type: slot`）上多一个字段 `gives`：`{名字: 来源}`。
///   来源就是绑定的来源（bind_model.dart），在**定义里那个位置**算：能读组件的属性、组件自己的状态，
///   占位放在“重复”里面时还能读那一层的“这一项”“第几项”。名字的规矩同“这一项”的名字（[kLcLocalName]）。
/// - **用的这一头**：页面上填进这个插槽的内容（连同它里面的控件）的绑定里，直接按名字读（`{"from": "var", "name": 名字}`）。
///   名字先找内容自己这边“重复”带出来的，再找**插槽给的**，然后才是这一页的状态、项目级状态
///   （和线 A“这一项”的找法一个次序：离得近的先）。
/// - **怎么落地**：展开实例时（component_expand.dart）把内容拷一份，读到这些名字的地方换成插槽给的式子
///   （式子已经按这个实例改写过：属性换成实例给的值、组件状态换成这个实例那一份）。纯粹是改写树，
///   所以摊开来导出的两种（普通网页、Flutter）现成的绑定机制直接能用。
/// - 这一版**不管**的：事件积木里读这些名字（页面逻辑的“这一项”一类只认“重复”）；双向绑定绑到插槽给的名字上；
///   Vue / React 导出（它们的组件是真的组件，要走作用域插槽 / 函数子节点，另做）；画布上内容不跟着变（画布不摊开内容）。
library;

import 'package:lopicode/lowcode/bind_model.dart';
import 'package:lopicode/lowcode/bind_refs.dart';
import 'package:lopicode/lowcode/component_ops.dart';
import 'package:lopicode/lowcode/logic_expr.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/slots.dart';

/// 占位节点上的字段名。
const String kLcGives = 'gives';

/// 一个插槽最多给几样。
const int kLcGivesMax = 8;

/// 这个插槽占位给外面的数据：名字 → 值式子（拷出来的）。写得不对的那几条不算。
Map<String, Map<String, dynamic>> lcSlotGives(LcNode slot) {
  final raw = slot.type == 'slot' ? slot.more[kLcGives] : null;
  final out = <String, Map<String, dynamic>>{};
  if (raw is! Map) return out;
  for (final e in raw.entries) {
    final name = e.key;
    if (name is! String || !kLcLocalName.hasMatch(name) || out.length >= kLcGivesMax) continue;
    final expr = lcSrcExprOf(e.value);
    if (expr != null) out[name] = copyExpr(expr)!;
  }
  return out;
}

/// 设 / 去掉一样（[src] 是 null＝去掉）。名字不合规矩、不是插槽占位、已经满了：不改，返回 false。
bool lcSetSlotGive(LcNode slot, String name, Map<String, dynamic>? src) {
  if (slot.type != 'slot' || !kLcLocalName.hasMatch(name)) return false;
  final raw = slot.more[kLcGives];
  final now = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
  if (src == null) {
    if (now.remove(name) == null) return false;
  } else {
    if (lcSrcExprOf(src) == null || (!now.containsKey(name) && now.length >= kLcGivesMax)) return false;
    now[name] = src;
  }
  now.isEmpty ? slot.more.remove(kLcGives) : slot.more[kLcGives] = now;
  return true;
}

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

/// 填进插槽的一块内容拷一份，绑定里读到 [gives] 里名字的地方换成那个式子。内容里用不到这些名字：原样交回（不拷）。
LcNode lcWithGiven(LcNode content, Map<String, Map<String, dynamic>> gives) {
  if (gives.isEmpty) return content;
  var uses = false;
  lcWalkBindings(content, (site) {
    final found = <Map<Object?, Object?>>[];
    _reads(site.expr, found);
    uses = uses || found.any((m) => gives.containsKey(m['name']) && !site.locals.contains(m['name']));
  });
  if (!uses) return content;
  final copy = copyLcTree(content);
  lcWalkBindings(copy, (site) {
    final found = <Map<Object?, Object?>>[];
    _reads(site.expr, found);
    for (final m in found) {
      final name = m['name'];
      final g = gives[name];
      if (g == null || site.locals.contains(name)) continue;
      final r = copyExpr(g)!;
      final path = lcPathOf(m['path']);
      if (r['e'] == 'var' && r['name'] is String) {
        final full = [...lcPathOf(r['path']), ...path];
        m['name'] = r['name'];
        full.isEmpty ? m.remove('path') : m['path'] = full;
        continue;
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
  });
  return copy;
}

/// 页面上 [nodeId] 这个控件读得到哪些“插槽给的”名字（给检查、挑选单用）：它在哪个实例的哪个插槽里，那个插槽给了什么。
/// 套了几层的，里层的盖住外层同名的。不在任何插槽里返回空表。
Set<String> lcGivenNamesAt(LcDocument doc, String nodeId) {
  final out = <String>{};
  LcNode? child = doc.find(nodeId);
  for (var guard = 0; child != null && guard <= LcNode.maxDepth * 4; guard++) {
    final parent = doc.parentOf(child.id);
    if (parent == null) break;
    if (parent.type == 'component') {
      final ref = parent.props['ref'];
      final def = ref is String ? doc.component(ref) : null;
      if (def != null) {
        final names = [for (final s in def.slots) s.name];
        final fallback = names.isEmpty ? null : (names.contains(kLcDefaultSlot) ? kLcDefaultSlot : names.first);
        final mine = names.contains(child.slot) ? child.slot : fallback;
        void walk(LcNode n) {
          if (n.type == 'slot' && lcSlotNameOf(n) == mine) out.addAll(lcSlotGives(n).keys);
          n.children.forEach(walk);
        }

        walk(def.root);
      }
    }
    child = parent;
  }
  return out;
}
