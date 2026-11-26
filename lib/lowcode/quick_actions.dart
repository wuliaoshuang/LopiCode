/// “快捷动作”：不用进积木编辑器，在“事件”页直接定“点击时做一件最常见的事”
/// （设计见 docs/blocks-v5-parts/E-editor-components.md §11.2）。
///
/// - 它**不是另一套东西**：存下来的就是一串普通积木——“当 这个组件 被点击”下面挂一块 `navigate` / `alert`，
///   进积木编辑器能看到、能改。这里只认“帽子下面正好一块、参数是一段写死的文字”的那种；她在积木里改复杂了，
///   这里就不再把它当快捷动作（那一串还在，从上面“点击时 N 块积木”进去看）。
/// - 现在有两样：打开网址、弹出提示。设计里的“去页面”“打开 / 关闭弹窗”要等有了多页面和弹窗组件，到时候往 [kLcQuickActions] 里加。
library;

import 'package:lopicode/lowcode/logic_expr.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:lopicode/lowcode/model.dart';

class LcQuickAction {
  const LcQuickAction(this.op, this.arg, this.label, this.hint);

  /// 用的是哪块积木、写死的文字填在它的哪个参数上。
  final String op;
  final String arg;
  final String label;
  final String hint;
}

const List<LcQuickAction> kLcQuickActions = [LcQuickAction('navigate', 'url', '点击时打开网址', 'https://…'), LcQuickAction('alert', 'message', '点击时弹出提示', '提示里写什么')];

/// 这种组件有没有快捷动作（能被“点击”的才有；页面本身没有）。
bool lcHasQuickActions(LcNode n) => n.type != 'page' && !n.isUnknown;

String? _literal(Object? expr) => expr is Map && expr['e'] == 'text' && expr['v'] is String ? expr['v'] as String : null;

/// 这个组件上算作这个快捷动作的那一串逻辑；没有返回 null。
LcHandler? lcQuickHandler(LcDocument doc, String nodeId, LcQuickAction a) {
  for (final h in doc.logic.handlersFor(nodeId)) {
    if (h.event != 'click' || h.body.length != 1) continue;
    final b = h.body.single;
    if (b.op == a.op && b.body.isEmpty && b.orElse.isEmpty && _literal(b.args[a.arg]) != null) return h;
  }
  return null;
}

/// 现在填的是什么；没设返回 null。
String? lcQuickValue(LcDocument doc, String nodeId, LcQuickAction a) {
  final h = lcQuickHandler(doc, nodeId, a);
  return h == null ? null : _literal(h.body.single.args[a.arg]);
}

/// 设 / 改 / 去掉一个快捷动作。[value] 是 null 或空＝去掉（只去掉这一串，别的逻辑不动）。返回改没改。
bool lcSetQuick(LcDocument doc, String nodeId, LcQuickAction a, String? value) {
  final node = doc.find(nodeId);
  if (node == null || !lcHasQuickActions(node)) return false;
  final old = lcQuickHandler(doc, nodeId, a);
  final v = value?.trim() ?? '';
  if (v.isEmpty) return old != null && doc.logic.removeHandler(old.id);
  if (old != null) {
    if (_literal(old.body.single.args[a.arg]) == v) return false;
    old.body.single.args[a.arg] = exText(v);
    return true;
  }
  final h = doc.logic.addHandler('click', target: nodeId);
  if (h == null) return false;
  h.body.add(LcBlock(op: a.op, args: {a.arg: exText(v)}));
  return true;
}
