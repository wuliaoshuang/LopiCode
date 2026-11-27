/// Flutter 导出怎么对待状态与绑定（第 5 期）：如实处理，局限写在导出文件的开头。
///
/// Flutter 这一份一直不导出积木逻辑（按钮的 onPressed 是空的），所以状态不会变。绑定在这里按**初值**定下来：
/// - 绑了的文字 / 属性：写初值算出来的结果。
/// - 重复：按初值的列表展开成几份（最多 200 份）；列表是空的写“列表是空的时候”那句文字（没设就什么都不出）。
/// - 显示条件、存在条件：按初值不成立的那一块不出。
/// - 输入框双向：显示状态的初值，改了不会写回去。
/// - 类名开关、样式绑定：Flutter 导出本来就不读样式，不导出。
/// 没用绑定的页面这一步什么都不做，导出结果和以前逐字节一样。
library;

import 'package:lopicode/lowcode/bind_eval.dart';
import 'package:lopicode/lowcode/bind_model.dart';
import 'package:lopicode/lowcode/bind_preview.dart';
import 'package:lopicode/lowcode/model.dart';

LcNode _with(LcNode n, List<LcNode> kids) =>
    LcNode(id: n.id, type: n.type, props: n.props, children: kids, style: n.style, bind: n.bind, name: n.name, locked: n.locked, hidden: n.hidden, keptProps: n.keptProps, more: n.more, raw: n.raw)
      ..instSlots = n.instSlots;

/// 导出 Flutter 用的树：绑定按初值定下来。这棵树上没有绑定就返回 [root] 本身。[doc] 要停在这一页上。
LcNode dartBoundTree(LcNode root, LcDocument doc) {
  if (!lcTreeHasBindings(root)) return root;
  List<LcNode> walk(LcNode n, LcBindEnv env, int depth) {
    if (depth > 64) return [n];
    LcNode one(LcBindEnv e) {
      final shown = lcBoundNode(n, e, placeholder: false);
      return _with(shown, [for (final c in n.children) ...walk(c, e, depth + 1)]);
    }

    if (!lcCanWrapBind(n)) return [one(env)];
    final scopes = lcRepeatScopes(n, env, all: true);
    if (scopes == null) return lcCondHolds(n, env) ? [one(env)] : const [];
    if (scopes.isEmpty) {
      final empty = lcRepeatOf(n)?.empty;
      return [
        if (empty != null) LcNode(id: '${n.id}-empty', type: 'text', props: {'text': empty}),
      ];
    }
    return [
      for (final e in scopes)
        if (lcCondHolds(n, e)) one(e),
    ];
  }

  final out = walk(root, LcBindEnv.of(doc), 0);
  return out.length == 1 ? out.single : root;
}

/// 导出文件开头的说明（项目里哪儿都没用绑定时是空串）。
String dartBindHeader(LcDocument doc) {
  final used = doc.pages.any((p) => lcTreeHasBindings(p.root)) || doc.components.any((c) => lcTreeHasBindings(c.root));
  return used ? '// 状态与绑定：这一份不导出逻辑，状态不会变，所以绑定按初值定了下来（重复按初值的列表展开、条件不成立的不出、输入框不写回）。要会动的界面请导出成网页 / Vue / React。\n' : '';
}
