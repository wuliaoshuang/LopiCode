/// “改一个变体的样子”的算法（不带界面）：进去时记下平时的样式、把变体的差别叠上去让她看见；
/// 她在“样式”页里随便改；每次写回定义时，把“现在的样式和平时不一样的那几条”记成这个变体，定义本身的样式不动。
library;

import 'package:lopicode/lowcode/component_extras.dart';
import 'package:lopicode/lowcode/model.dart';

void _walk(LcNode n, void Function(LcNode n) visit) {
  visit(n);
  for (final c in n.children) {
    _walk(c, visit);
  }
}

/// 记下每个节点平时的样式（节点 id → CSS 声明表的拷贝）。
Map<String, Map<String, String>> lcSnapshotStyles(LcNode root) {
  final out = <String, Map<String, String>>{};
  _walk(root, (n) => out[n.id] = Map.of(n.style));
  return out;
}

/// 把变体的差别叠到节点的样式上。
void lcOverlayVariant(LcNode root, LcVariant v) => _walk(root, (n) {
  final add = v.styles[n.id];
  if (add != null) n.style.addAll(add);
});

/// 现在的样式和 [base] 不一样的那几条（只看 [base] 里有的节点；后加的节点不算变体的差别）。
Map<String, Map<String, String>> lcVariantDiff(LcNode root, Map<String, Map<String, String>> base) {
  final out = <String, Map<String, String>>{};
  _walk(root, (n) {
    final b = base[n.id];
    if (b == null) return;
    final diff = {
      for (final e in n.style.entries)
        if (b[e.key] != e.value) e.key: e.value,
    };
    if (diff.isNotEmpty) out[n.id] = diff;
  });
  return out;
}

/// 样式退回 [base]（[base] 里没有的节点不动）。
void lcRestoreStyles(LcNode root, Map<String, Map<String, String>> base) => _walk(root, (n) {
  final b = base[n.id];
  if (b == null) return;
  n.style
    ..clear()
    ..addAll(b);
});

/// 把差别写进定义里的那个变体（[key]＝`组/名字`）。找不到这个变体就不动。
void lcSaveVariantStyles(LcDocument doc, String componentId, String key, Map<String, Map<String, String>> diff) {
  final def = doc.component(componentId);
  if (def == null) return;
  final list = lcVariants(def);
  for (final v in list) {
    if (v.key != key) continue;
    v.styles
      ..clear()
      ..addAll(diff);
    lcSetVariants(def, list);
    return;
  }
}
