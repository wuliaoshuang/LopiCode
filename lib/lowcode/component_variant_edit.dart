/// “改一个变体的样子”的算法（不带界面）：进去时记下平时的样式、把变体的差别叠上去让她看见；
/// 她在“样式”页、“常用”页里随便改；每次写回定义时，把“现在的样式和平时不一样的那几条”记成这个变体，定义本身的样式不动。
library;

import 'dart:convert';

import 'package:lopicode/lowcode/component_extras.dart';
import 'package:lopicode/lowcode/inspector_bp_write.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/style_resolve.dart';

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

/// 记下每个节点平时那几个“落到样式上的简写属性”（“常用”页改的字号、内边距、颜色这些；节点 id → 属性表的拷贝）。
/// 变体模式里在“常用”页改了它们，也要只记成变体的差别、不能改到定义本身上。
Map<String, Map<String, dynamic>> lcSnapshotLookProps(LcNode root) {
  final out = <String, Map<String, dynamic>>{};
  _walk(
    root,
    (n) => out[n.id] = {
      for (final k in kLcStyleProps)
        if (n.props.containsKey(k)) k: jsonDecode(jsonEncode(n.props[k])),
    },
  );
  return out;
}

bool _sameLook(LcNode n, Map<String, dynamic> base) {
  for (final k in kLcStyleProps) {
    if (jsonEncode(n.props[k]) != jsonEncode(base[k])) return false;
  }
  return true;
}

void _restoreLook(LcNode n, Map<String, dynamic> base) {
  n.props.removeWhere((k, _) => kLcStyleProps.contains(k));
  n.props.addAll((jsonDecode(jsonEncode(base)) as Map).cast<String, dynamic>());
}

/// 把变体的差别叠到节点的样式上。
void lcOverlayVariant(LcNode root, LcVariant v) => _walk(root, (n) {
  final add = v.styles[n.id];
  if (add != null) n.style.addAll(add);
});

/// 现在的样子和平时不一样的那几条（只看 [base] 里有的节点；后加的节点不算变体的差别）。
/// 简写属性没动过的节点：只比 style。动过的（在“常用”页改的）：比最终算出来的样式，差出来的那几条都算变体的。
Map<String, Map<String, String>> lcVariantDiff(LcNode root, Map<String, Map<String, String>> base, [Map<String, Map<String, dynamic>> baseProps = const {}]) {
  final out = <String, Map<String, String>>{};
  void visit(LcNode n, LcNode? parent) {
    final b = base[n.id];
    if (b != null) {
      final diff = {
        for (final e in n.style.entries)
          if (b[e.key] != e.value) e.key: e.value,
      };
      final look = baseProps[n.id];
      if (look != null && !_sameLook(n, look)) {
        final plain = LcNode(id: n.id, type: n.type, props: {...n.props}, children: n.children, style: Map.of(b), bind: n.bind, more: n.more);
        _restoreLook(plain, look);
        final before = resolvedStyle(plain, parent), after = resolvedStyle(n, parent);
        for (final e in after.entries) {
          if (before[e.key] != e.value) diff[e.key] = e.value;
        }
      }
      if (diff.isNotEmpty) out[n.id] = diff;
    }
    for (final c in n.children) {
      visit(c, n);
    }
  }

  visit(root, null);
  return out;
}

/// 样子退回平时的（[base] 里没有的节点不动）。
void lcRestoreStyles(LcNode root, Map<String, Map<String, String>> base, [Map<String, Map<String, dynamic>> baseProps = const {}]) => _walk(root, (n) {
  final b = base[n.id];
  if (b == null) return;
  n.style
    ..clear()
    ..addAll(b);
  final look = baseProps[n.id];
  if (look != null) _restoreLook(n, look);
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
