/// 绑定和状态的检查（第 5 期）：面板上的提示、导出说明都用它。只看、不改。
///
/// 查这些：读了不存在的名字；“重复”没给标识（错）/ 拿序号当标识（警告）；要列表的地方绑了不是列表的状态；
/// 双向绑定绑不上（控件不支持、状态不存在、是派生值、类型对不上）；同一个属性既绑了又被“改控件”积木直接改（三选一）；
/// 派生值绕圈、项目级派生值读了页面的状态。
library;

import 'package:lopicode/lowcode/bind_eval.dart';
import 'package:lopicode/lowcode/bind_model.dart';
import 'package:lopicode/lowcode/bind_refs.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/slot_gives.dart';
import 'package:lopicode/lowcode/state_model.dart';

class LcBindIssue {
  const LcBindIssue(this.message, {this.nodeId, this.warning = false});
  final String message;

  /// 出在哪个控件上；null＝出在状态表上。
  final String? nodeId;

  /// 警告（能导出、能用，只是不建议）；否则是错（这一条绑定导出后不起作用）。
  final bool warning;
}

String _label(LcNode n) => n.name.isNotEmpty ? n.name : n.spec.label;

/// 式子里“取列表的一项”“取记录的一格”以后，那一项是什么类型说不准；这里只查最外面那个名字。
List<LcBindIssue> lcCheckBindings(LcDocument doc) {
  final out = <LcBindIssue>[];
  final scope = {for (final s in lcStatesInScope(doc)) s.name: s};

  // —— 状态表 ——
  final project = lcProjectStates(doc);
  final projectNames = {for (final v in project) v.name};
  for (final v in project) {
    if (!v.isDerived) continue;
    for (final name in lcExprNames(v.derived)) {
      if (!projectNames.contains(name)) out.add(LcBindIssue('项目级派生值 ${v.name} 读了 $name：项目级的只能读项目级的状态'));
    }
  }
  bool loops(String start) {
    final seen = <String>{};
    bool go(String name) {
      final v = scope[name]?.variable;
      if (v == null || !v.isDerived) return false;
      if (!seen.add(name)) return false;
      for (final next in lcExprNames(v.derived)) {
        if (next == start || go(next)) return true;
      }
      return false;
    }

    return go(start);
  }

  for (final s in scope.values) {
    if (s.variable.isDerived && loops(s.name)) out.add(LcBindIssue('派生值 ${s.name} 绕回来用到了自己，算不出来'));
  }

  // —— 控件上的绑定 ——
  final setByBlocks = <String>{}; // “控件 id\u0000属性”：被“改控件”积木直接改的
  void blocks(List<LcBlock> list) {
    for (final b in list) {
      if (b.op == 'setProp' && b.args['node'] is String && b.args['prop'] is String) setByBlocks.add('${b.args['node']}\u0000${b.args['prop']}');
      blocks(b.body);
      blocks(b.orElse);
    }
  }

  for (final h in doc.logic.handlers) {
    blocks(h.body);
  }

  lcWalkBindings(
    doc.root,
    (site) {
      final n = site.node;
      for (final name in lcExprNames(site.expr)..addAll([if (site.expr['from'] == 'var' && site.expr['name'] is String) site.expr['name'] as String])) {
        if (!site.locals.contains(name) && !scope.containsKey(name) && !lcGivenNamesAt(doc, n.id).contains(name)) {
          out.add(LcBindIssue('${_label(n)}的“${site.what}”用到了 $name，但没有这个状态', nodeId: n.id));
        }
      }
    },
    onModel: (n, state, locals) {
      final prop = lcModelProp(n.type);
      final s = scope[state];
      if (prop == null) {
        out.add(LcBindIssue('${_label(n)}不能双向绑定（只有输入框、多行输入、开关、滑块、勾选框、单选组、下拉可以）', nodeId: n.id));
      } else if (s == null || locals.contains(state)) {
        out.add(LcBindIssue('${_label(n)}双向绑到了 $state，但没有这个状态', nodeId: n.id));
      } else if (s.variable.isDerived) {
        out.add(LcBindIssue('${_label(n)}双向绑到了派生值 $state：派生值是算出来的，不能往里写', nodeId: n.id));
      } else if (n.type == 'slider' && s.variable.type != 'number') {
        out.add(LcBindIssue('${_label(n)}要绑一个“数字”的状态，$state 是${lcStateTypeLabel(s.variable.type)}', nodeId: n.id));
      } else if (prop == 'checked' ? s.variable.type != 'bool' : (s.variable.type != 'text' && s.variable.type != 'number')) {
        out.add(LcBindIssue('${_label(n)}要绑一个“${prop == 'checked' ? '是 / 否' : '文字或数字'}”的状态，$state 是${lcStateTypeLabel(s.variable.type)}', nodeId: n.id));
      }
      if (prop != null && setByBlocks.contains('${n.id}\u0000value')) {
        out.add(LcBindIssue('${_label(n)}的内容已经双向绑到 $state，又被“改控件”积木直接改：只能留一样', nodeId: n.id));
      }
    },
  );

  String? typeOf(String name) => scope[name]?.variable.type;
  void walk(LcNode n, Set<String> outer) {
    var locals = outer;
    final rep = lcRepeatOf(n);
    if (rep != null) {
      final t = lcExprType(rep.list, (name) => outer.contains(name) ? null : typeOf(name));
      if (t != 'list' && t != 'any') out.add(LcBindIssue('${_label(n)}的“重复”要一个列表，现在绑的不是列表', nodeId: n.id));
      if (rep.key == null) {
        out.add(LcBindIssue('${_label(n)}的“重复”还没给每项的标识：没有标识，增删挪动时会认错项', nodeId: n.id));
      } else if (rep.keyIsIndex) {
        out.add(LcBindIssue('${_label(n)}的“重复”拿序号当标识：列表增删、挪动以后会认错项，最好换成每项自己不变的东西（比如 id）', nodeId: n.id, warning: true));
      }
      locals = {...outer, rep.item, rep.index};
    }
    for (final prop in lcBoundProps(n)) {
      final spec = lcBindable(n.type, prop);
      if (spec == null) {
        out.add(LcBindIssue('${_label(n)}的 $prop 不能绑定，这一条不起作用', nodeId: n.id));
        continue;
      }
      if (spec.type == 'list') {
        final t = lcExprType(lcDataExpr(n, prop), (name) => locals.contains(name) ? null : typeOf(name));
        if (t != 'list' && t != 'any') out.add(LcBindIssue('${_label(n)}的“${spec.label}”要一个列表，现在绑的不是列表', nodeId: n.id));
      }
      if (setByBlocks.contains('${n.id}\u0000$prop')) {
        out.add(LcBindIssue('${_label(n)}的“${spec.label}”已经绑定了，又被“改控件”积木直接改：只能留一样', nodeId: n.id));
      }
    }
    if (lcShowIfExpr(n) != null && setByBlocks.contains('${n.id}\u0000visible')) {
      out.add(LcBindIssue('${_label(n)}已经有显示条件了，又被“改控件”积木直接改显示 / 隐藏：只能留一样', nodeId: n.id));
    }
    if (n.type == 'component' && lcHasBindings(n) && lcBoundProps(n).isNotEmpty) {
      out.add(LcBindIssue('自定义组件的属性值这一版还不能绑定', nodeId: n.id));
    }
    for (final c in n.children) {
      walk(c, locals);
    }
  }

  walk(doc.root, const {});

  for (final def in doc.components) {
    if (lcTreeHasBindings(def.root)) out.add(LcBindIssue('组件「${def.name}」的定义里有绑定：导出成普通网页、Flutter 时照页面上的控件一样处理；导出成 Vue / React 时不起作用（组件自己的状态留给下一期）', warning: true));
  }
  return out;
}
