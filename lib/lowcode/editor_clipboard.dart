/// 搭建页自己的剪贴板（长按菜单的“复制 / 粘贴到它后面”）和“包成容器”。
///
/// - 只在这次运行的内存里：跨容器、跨页面、跨项目都能贴，关掉应用就没了。不进页面文件，也不碰系统剪贴板。
/// - 复制的是整棵子树的一份快照；里面用到的自定义组件（连同它们又用到的）一起带上。
/// - 粘贴时：子树里的编号全部重新编；带来的自定义组件，这一页里已经有内容一模一样的就直接用，没有的补进来
///   （编号撞了换一个，名字撞了加序号）。
/// - 积木逻辑不跟着复制（和“重复一份”一样）：逻辑是挂在原来那个组件上的。
library;

import 'dart:convert';

import 'package:lopicode/lowcode/component_model.dart';
import 'package:lopicode/lowcode/component_ops.dart';
import 'package:lopicode/lowcode/model.dart';

class _Clip {
  _Clip(this.nodes, this.defs);

  /// 一棵或几棵子树的 JSON（多选复制时是几棵，按页面上的先后）。
  final List<String> nodes;

  /// 用到的自定义组件定义的 JSON（被依赖的在前）。
  final List<String> defs;
}

_Clip? _clip;

/// 剪贴板里有没有东西。
bool get lcClipboardHasContent => _clip != null;

/// 剪贴板里那棵子树有没有用到自定义组件。
bool get lcClipboardHasInstances => _clip?.defs.isNotEmpty ?? false;

/// 测试用：清空。
void lcClipboardClear() => _clip = null;

void _walk(LcNode n, void Function(LcNode n) visit) {
  visit(n);
  for (final c in n.children) {
    _walk(c, visit);
  }
}

/// 复制一个组件（连同里面的）。页面本身不能复制；找不到返回 false。
bool lcClipboardCopy(LcDocument doc, String nodeId) => lcClipboardCopyMany(doc, [nodeId]);

/// 剪贴板里有几个组件（多选复制的是几个）。
int get lcClipboardCount => _clip?.nodes.length ?? 0;

/// 一次复制几个组件（多选）：粘贴时按 [nodeIds] 的顺序挨着贴。里面有页面本身或找不到的，整次不复制。
bool lcClipboardCopyMany(LcDocument doc, List<String> nodeIds) {
  final nodes = [for (final id in nodeIds) doc.find(id)];
  if (nodes.isEmpty || nodes.any((n) => n == null || n.type == 'page')) return false;
  final defs = <String, LcComponentDef>{};
  void collect(LcNode root) => _walk(root, (n) {
    final ref = n.type == 'component' ? n.strProp('ref') : null;
    if (ref == null || defs.containsKey(ref)) return;
    for (final d in doc.components) {
      if (d.id == ref) {
        collect(d.root); // 先收它用到的，被依赖的排前面
        defs[ref] = d;
        break;
      }
    }
  });
  for (final n in nodes) {
    collect(n!);
  }
  _clip = _Clip([for (final n in nodes) jsonEncode(n!.toJson())], [for (final d in defs.values) jsonEncode(d.toJson())]);
  return true;
}

/// 把剪贴板里的东西贴进 [doc]：[parentId] 的第 [index] 个位置（不给＝放最后）。返回新组件的编号
/// （剪贴板里是几个时，返回第一个的）；贴不了返回 null。
String? lcClipboardPaste(LcDocument doc, String parentId, [int? index]) => lcClipboardPasteAll(doc, parentId, index).firstOrNull;

/// 同 [lcClipboardPaste]，返回贴进来的每一个的编号（按先后）；贴不了是空的。
List<String> lcClipboardPasteAll(LcDocument doc, String parentId, [int? index]) {
  final clip = _clip;
  if (clip == null) return const [];
  final parent = doc.find(parentId);
  if (parent == null || !parent.isContainer) return const [];
  final trees = <LcNode>[];
  try {
    for (final raw in clip.nodes) {
      trees.add(LcNode.fromJson(jsonDecode(raw) as Map<String, dynamic>, 0, version: LcDocument.currentVersion));
    }
  } on FormatException {
    return const [];
  }
  // 带来的自定义组件：一样的直接用，没有的补上。
  final remap = <String, String>{};
  void retarget(LcNode root) => _walk(root, (n) {
    final ref = n.type == 'component' ? n.strProp('ref') : null;
    if (ref != null && remap.containsKey(ref)) n.props['ref'] = remap[ref];
  });
  for (final raw in clip.defs) {
    final def = LcComponentDef.tryParse(jsonDecode(raw));
    if (def == null) continue;
    final oldId = def.id;
    retarget(def.root);
    // “一样”只看内容（可配置的属性＋里面的控件），不看编号和名字：上次贴进来时编号、名字可能已经换过。
    String content(LcComponentDef d) => jsonEncode((Map.of(d.toJson())..remove('id'))..remove('name'));
    final same = doc.components.where((d) => content(d) == content(def)).firstOrNull;
    if (same != null) {
      remap[oldId] = same.id;
      continue;
    }
    if (doc.components.any((d) => d.id == def.id)) {
      var i = 1;
      while (doc.components.any((d) => d.id == 'c$i')) {
        i++;
      }
      def.id = 'c$i';
    }
    def.name = uniqueComponentName(doc, def.name);
    doc.components.add(def);
    remap[oldId] = def.id;
  }
  var at = index ?? parent.children.length;
  final ids = <String>[];
  for (final tree in trees) {
    retarget(tree);
    _walk(tree, (n) => n.id = ''); // 编号让文档重新发
    if (!doc.insert(parentId, tree, at)) continue;
    ids.add(tree.id);
    at++;
  }
  return ids;
}

/// 贴在某个组件的后面（和它同一层）。
String? lcClipboardPasteAfter(LcDocument doc, String nodeId) {
  final parent = doc.parentOf(nodeId), node = doc.find(nodeId);
  if (parent == null || node == null) return null;
  return lcClipboardPaste(doc, parent.id, parent.children.indexOf(node) + 1);
}

/// 把一个组件包进一个新的容器里（容器放在它原来的位置）。返回新容器的编号；包不了（页面本身、找不到）返回 null。
String? wrapInContainer(LcDocument doc, String nodeId) {
  final parent = doc.parentOf(nodeId), node = doc.find(nodeId);
  if (parent == null || node == null) return null;
  final box = doc.newNode('container');
  // 新容器不带自己的内边距和间距：包上以后页面看起来不变，要留白再自己加。
  box.props
    ..remove('padding')
    ..remove('gap');
  // 原来占满一行的照样占满；原来随内容宽的，容器也随内容宽。
  if (node.props['width'] != 'fill' && !node.isContainer) box.props.remove('width');
  box.slot = node.slot; // 包的是插槽里的组件：容器顶替它留在那个插槽里
  if (!doc.insert(parent.id, box, parent.children.indexOf(node))) return null;
  if (!doc.move(nodeId, box.id, 0)) {
    doc.remove(box.id);
    return null;
  }
  return box.id;
}
