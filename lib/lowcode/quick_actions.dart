/// “快捷动作”：不用进积木编辑器，在“事件”页直接定“点击时做一件最常见的事”
/// （设计见 docs/blocks-v5-parts/E-editor-components.md §11.2）。
///
/// - 它**不是另一套东西**：存下来的就是一串普通积木——“当 这个组件 被点击”下面挂一块 `navigate` / `alert`，
///   进积木编辑器能看到、能改。这里只认“帽子下面正好一块、参数是一段写死的文字”的那种；她在积木里改复杂了，
///   这里就不再把它当快捷动作（那一串还在，从上面“点击时 N 块积木”进去看）。
/// - 现在有五样：去页面、打开网址、弹出提示、打开弹窗、关闭弹窗。
///   “去页面”存的是一块 `goPage`，填的是页面 id（选项目里的哪一页）；
///   弹窗那两样存的是“改控件 某个弹窗 的 显示 改成 是 / 否”（`setProp`），填的是“选页面里的哪个弹窗”。
library;

import 'package:lopicode/lowcode/logic_expr.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/model_v3_components.dart';

class LcQuickAction {
  const LcQuickAction(this.op, this.arg, this.label, this.hint, {this.dialogShown, this.picksPage = false});

  /// 用的是哪块积木、填的东西放在它的哪个参数上。
  final String op;
  final String arg;
  final String label;
  final String hint;

  /// 不是 null＝这是“打开（true）/ 关闭（false）弹窗”：填的是弹窗的 id，不是一段文字。
  final bool? dialogShown;

  bool get picksDialog => dialogShown != null;

  /// 这是“去页面”：填的是页面 id，不是一段文字。
  final bool picksPage;

  /// 填的是“选一样东西”（弹窗 / 页面）的 id，不是让人打字。
  bool get picksId => picksDialog || picksPage;

  /// 界面上认它用的名字（两样弹窗动作用的是同一块积木，光看 [op] 分不开）。
  String get id => switch (dialogShown) {
    null => op,
    true => 'openDialog',
    false => 'closeDialog',
  };
}

/// “点击时去页面”。
const LcQuickAction kLcGoPageQuick = LcQuickAction(kLcGoPageOp, 'page', '点击时去页面', '选一个页面', picksPage: true);

const List<LcQuickAction> kLcQuickActions = [
  kLcGoPageQuick,
  LcQuickAction('navigate', 'url', '点击时打开网址', 'https://…'),
  LcQuickAction('alert', 'message', '点击时弹出提示', '提示里写什么'),
  LcQuickAction('setProp', 'node', '点击时打开弹窗', '选一个弹窗', dialogShown: true),
  LcQuickAction('setProp', 'node', '点击时关闭弹窗', '选一个弹窗', dialogShown: false),
];

/// 页面里的弹窗（按在页面里的先后）。
List<LcNode> lcDialogsOf(LcDocument doc) {
  final out = <LcNode>[];
  void walk(LcNode n) {
    if (n.type == 'dialog') out.add(n);
    n.children.forEach(walk);
  }

  walk(doc.root);
  return out;
}

/// 弹窗在界面上叫什么：标题；没写标题就叫“弹窗”。
String lcDialogName(LcNode dialog) => lcIsToast(dialog) ? '轻提示“${dialog.strProp('text') ?? ''}”' : (dialog.strProp('title') ?? '弹窗');

/// 这种组件有没有快捷动作（能被“点击”的才有；页面本身没有）。
bool lcHasQuickActions(LcNode n) => n.type != 'page' && !n.isUnknown;

String? _literal(Object? expr) => expr is Map && expr['e'] == 'text' && expr['v'] is String ? expr['v'] as String : null;

/// 这块积木在这个快捷动作里填的是什么；它不是这个快捷动作的样子返回 null。
String? _valueOf(LcBlock b, LcQuickAction a) {
  if (b.op != a.op || b.body.isNotEmpty || b.orElse.isNotEmpty) return null;
  if (a.picksPage) return b.args[a.arg] is String && (b.args[a.arg] as String).isNotEmpty ? b.args[a.arg] as String : null;
  if (!a.picksDialog) return _literal(b.args[a.arg]);
  final id = b.args[a.arg], v = b.args['value'];
  return id is String && id.isNotEmpty && b.args['prop'] == 'visible' && v is Map && v['e'] == 'bool' && v['v'] == a.dialogShown ? id : null;
}

/// 这个组件上算作这个快捷动作的那一串逻辑；没有返回 null。
LcHandler? lcQuickHandler(LcDocument doc, String nodeId, LcQuickAction a) {
  for (final h in doc.logic.handlersFor(nodeId)) {
    if (h.event != 'click' || h.body.length != 1) continue;
    if (_valueOf(h.body.single, a) != null) return h;
  }
  return null;
}

/// 现在填的是什么；没设返回 null。
String? lcQuickValue(LcDocument doc, String nodeId, LcQuickAction a) {
  final h = lcQuickHandler(doc, nodeId, a);
  return h == null ? null : _valueOf(h.body.single, a);
}

/// 设 / 改 / 去掉一个快捷动作。[value] 是 null 或空＝去掉（只去掉这一串，别的逻辑不动）。返回改没改。
/// 弹窗动作的 [value] 是弹窗的 id：页面里没有这个弹窗就不改。“去页面”的 [value] 是页面 id：项目里没有这一页就不改。
bool lcSetQuick(LcDocument doc, String nodeId, LcQuickAction a, String? value) {
  final node = doc.find(nodeId);
  if (node == null || !lcHasQuickActions(node)) return false;
  final old = lcQuickHandler(doc, nodeId, a);
  final v = value?.trim() ?? '';
  if (v.isEmpty) return old != null && doc.logic.removeHandler(old.id);
  if (a.picksDialog && doc.find(v)?.type != 'dialog') return false;
  if (a.picksPage && doc.pageById(v) == null) return false;
  if (old != null) {
    if (_valueOf(old.body.single, a) == v) return false;
    old.body.single.args[a.arg] = a.picksId ? v : exText(v);
    return true;
  }
  final h = doc.logic.addHandler('click', target: nodeId);
  if (h == null) return false;
  h.body.add(switch (a) {
    _ when a.picksPage => LcBlock(op: a.op, args: {a.arg: v}),
    _ when a.picksDialog => LcBlock(op: a.op, args: {a.arg: v, 'prop': 'visible', 'value': exBool(a.dialogShown!)}),
    _ => LcBlock(op: a.op, args: {a.arg: exText(v)}),
  });
  return true;
}

// —— 给组件事件用的（第四轮 B2）：同一批快捷动作，只是不挂在“点击”的帽子下，而是存在实例的 `on` 里 ——

/// “让一个数字状态加 1”：只给组件事件用（页面上的点击要这个就进积木）。填的是状态名。
const LcQuickAction kLcBumpQuick = LcQuickAction('changeVar', 'name', '让一个数字加 1', '选一个数字状态');

/// “把一个状态设成事件带来的值”：只给**带数据**的组件事件用（第四轮 B4）。填的是状态名；
/// 值是事件带的第一项数据（存成现成的“输入的内容”那个值积木，约定见 export_comp_files.dart 开头）。
const LcQuickAction kLcTakeQuick = LcQuickAction('setVar', 'name', '把一个状态设成事件带来的值', '选一个状态');

/// 这块积木在这个快捷动作里填的是什么；不是这个快捷动作的样子返回 null。
String? lcQuickBlockValue(LcBlock b, LcQuickAction a) {
  if (identical(a, kLcTakeQuick)) {
    final v = b.args['value'];
    return b.op == a.op && b.body.isEmpty && b.args['name'] is String && v is Map && v['e'] == 'event' ? b.args['name'] as String : null;
  }
  if (!identical(a, kLcBumpQuick)) return _valueOf(b, a);
  final by = b.args['by'];
  return b.op == a.op && b.args['name'] is String && by is Map && by['e'] == 'num' && by['v'] == 1 ? b.args['name'] as String : null;
}

/// 造这个快捷动作的那一块积木。
LcBlock lcQuickBlock(LcQuickAction a, String v) => switch (a) {
  _ when identical(a, kLcTakeQuick) => LcBlock(op: a.op, args: {a.arg: v, 'value': exEvent()}),
  _ when identical(a, kLcBumpQuick) => LcBlock(op: a.op, args: {a.arg: v, 'by': exNum(1)}),
  _ when a.picksPage => LcBlock(op: a.op, args: {a.arg: v}),
  _ when a.picksDialog => LcBlock(op: a.op, args: {a.arg: v, 'prop': 'visible', 'value': exBool(a.dialogShown!)}),
  _ => LcBlock(op: a.op, args: {a.arg: exText(v)}),
};
