/// 状态“哪里在用”、改名、删除（第 5 期）。绑定里的名字和积木里的名字一起管。
///
/// 范围：
/// - 页面级状态只在它那一页里找：这一页控件上的绑定、这一页的积木、这一页别的派生值。
/// - 项目级状态在**所有页面**和**所有自定义组件的定义**里找；哪一页自己有同名的状态，那一页里的同名引用指的是页面那个，不算、不改。
/// - “重复”里带出来的这一项 / 序号如果和状态重名，重复里面的那个名字指的是这一项，不算、不改。
library;

import 'package:lopicode/lowcode/bind_model.dart';
import 'package:lopicode/lowcode/logic_edit.dart';
import 'package:lopicode/lowcode/logic_expr.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/state_model.dart';

/// 一处绑定里的式子。[expr] 是文档里那份（能原地改）；[locals] 是这里被“重复”占用的名字。
class LcBindSite {
  const LcBindSite(this.node, this.what, this.expr, this.locals);
  final LcNode node;

  /// 是哪一种绑定（给人看的：`文字`、`显示条件`、`重复的列表`…）。
  final String what;
  final Map<Object?, Object?> expr;
  final Set<String> locals;
}

Map<Object?, Object?>? _rawExpr(Object? src) {
  if (src is! Map) return null;
  if (src['from'] == 'var' && src['name'] is String) return src; // 用一个值：这个对象自己当成一个“读名字”的式子来改
  final e = src['expr'];
  return src['from'] == 'expr' && e is Map ? e : null;
}

/// 走一遍这棵树上所有的绑定。双向绑定单独回调（[onModel]：节点、状态名、这里被占用的名字）。
void lcWalkBindings(LcNode root, void Function(LcBindSite site) visit, {void Function(LcNode n, String state, Set<String> locals)? onModel}) {
  void walk(LcNode n, Set<String> outer, int depth) {
    if (depth > 64) return;
    var locals = outer;
    final repeat = n.more[kLcRepeat];
    final rep = lcRepeatOf(n);
    if (repeat is Map && rep != null) {
      final list = _rawExpr(repeat['list']);
      if (list != null) visit(LcBindSite(n, '重复的列表', list, outer));
      locals = {...outer, rep.item, rep.index};
      final key = _rawExpr(repeat['key']);
      if (key != null) visit(LcBindSite(n, '重复的标识', key, locals));
    }
    final data = n.more[kLcData];
    if (data is Map) {
      for (final e in data.entries) {
        final x = _rawExpr(e.value);
        if (x != null) visit(LcBindSite(n, lcBindable(n.type, '${e.key}')?.label ?? '${e.key}', x, locals));
      }
    }
    final show = _rawExpr(n.more[kLcShowIf]);
    if (show != null) visit(LcBindSite(n, '显示条件', show, locals));
    final render = _rawExpr(n.more[kLcRenderIf]);
    if (render != null) visit(LcBindSite(n, '存在条件', render, locals));
    final cls = n.more[kLcClassIf];
    if (cls is List) {
      for (final item in cls) {
        final x = item is Map ? _rawExpr(item['when']) : null;
        if (x != null) visit(LcBindSite(n, '类名 ${item is Map ? item['name'] : ''}', x, locals));
      }
    }
    final styles = n.more[kLcStyles];
    if (styles is Map) {
      for (final e in styles.entries) {
        final x = _rawExpr(e.value);
        if (x != null) visit(LcBindSite(n, '样式 ${e.key}', x, locals));
      }
    }
    final model = lcModelOf(n);
    if (model != null) onModel?.call(n, model, locals);
    for (final c in n.children) {
      walk(c, locals, depth + 1);
    }
  }

  walk(root, const {}, 0);
}

/// 式子里（含嵌着的）每个“读名字”的地方。来源写成“用一个值”的，那个来源对象自己也算一个。
void _visitReads(Object? v, void Function(Map<Object?, Object?> read) visit, [int depth = 0]) {
  if (depth > kMaxExprDepth * 2) return;
  if (v is Map) {
    if ((v['e'] == 'var' || v['from'] == 'var') && v['name'] is String) visit(v);
    for (final x in v.values) {
      _visitReads(x, visit, depth + 1);
    }
  } else if (v is List) {
    for (final x in v) {
      _visitReads(x, visit, depth + 1);
    }
  }
}

/// 一处在用。
class LcStateUse {
  const LcStateUse(this.where, this.what);

  /// 在哪儿：`首页 · 文字`、`组件「卡片」 · 按钮`、`首页 · 积木`。
  final String where;

  /// 用在什么上：`文字`、`显示条件`、`积木里 3 处`、`派生值 total`。
  final String what;
}

String _nodeLabel(LcNode n) => n.name.isNotEmpty ? n.name : n.spec.label;

void _scanTree(LcNode root, String name, String place, List<LcStateUse> out, {void Function(Map<Object?, Object?> read)? change, void Function(LcNode n)? changeModel}) {
  lcWalkBindings(
    root,
    (site) {
      if (site.locals.contains(name)) return;
      var hit = false;
      _visitReads(site.expr, (read) {
        if (read['name'] != name) return;
        hit = true;
        change?.call(read);
      });
      if (hit) out.add(LcStateUse('$place · ${_nodeLabel(site.node)}', site.what));
    },
    onModel: (n, state, locals) {
      if (state != name) return;
      out.add(LcStateUse('$place · ${_nodeLabel(n)}', '双向绑定'));
      changeModel?.call(n);
    },
  );
}

void _scanDerived(Iterable<LcVariable> vars, String name, String place, List<LcStateUse> out, {void Function(Map<Object?, Object?> read)? change}) {
  for (final v in vars) {
    if (!v.isDerived || v.name == name) continue;
    var hit = false;
    _visitReads(v.derived, (read) {
      if (read['name'] != name) return;
      hit = true;
      change?.call(read);
    });
    if (hit) out.add(LcStateUse(place, '派生值 ${v.name}'));
  }
}

List<LcStateUse> _scan(LcDocument doc, String name, {required bool project, String? newName}) {
  final out = <LcStateUse>[];
  final change = newName == null ? null : (Map<Object?, Object?> read) => read['name'] = newName;
  final changeModel = newName == null ? null : (LcNode n) => lcSetModel(n, newName);
  void page(LcPage p) {
    final place = p.title.isEmpty ? '页面' : p.title;
    _scanTree(p.root, name, place, out, change: change, changeModel: changeModel);
    _scanDerived(p.logic.variables, name, place, out, change: change);
    final refs = p.logic.variableRefCount(name);
    if (refs > 0) out.add(LcStateUse(place, '积木里 $refs 处'));
    if (newName != null) p.logic.renameVariableRefs(name, newName);
  }

  if (!project) {
    page(doc.page);
    return out;
  }
  for (final p in doc.pages) {
    if (p.logic.variable(name) == null) page(p);
  }
  for (final def in doc.components) {
    _scanTree(def.root, name, '组件「${def.name}」', out, change: change, changeModel: changeModel);
  }
  if (newName == null) {
    _scanDerived(lcProjectStates(doc), name, '项目级状态', out);
  }
  return out;
}

/// 哪里在用这个状态。[project]：找的是项目级的那个（否则是当前页的）。
List<LcStateUse> lcStateUses(LcDocument doc, String name, {required bool project}) => _scan(doc, name, project: project);

/// 改名，用到它的地方一起改。新名字不合规矩、和同一层别的状态重名、或者没有这个状态：什么都不改，返回 false。
bool lcRenameState(LcDocument doc, String oldName, String newName, {required bool project}) {
  if (!LcVariable.namePattern.hasMatch(newName)) return false;
  if (oldName == newName) return true;
  if (!project) {
    final v = doc.logic.variable(oldName);
    if (v == null || doc.logic.variable(newName) != null) return false;
    _scan(doc, oldName, project: false, newName: newName);
    v.name = newName;
    return true;
  }
  final all = lcProjectStates(doc);
  if (!all.any((v) => v.name == oldName) || all.any((v) => v.name == newName)) return false;
  _scan(doc, oldName, project: true, newName: newName);
  lcEditProjectStates(doc, (list) {
    for (final v in list) {
      if (v.name == oldName) v.name = newName;
      if (v.isDerived) {
        _visitReads(v.derived, (read) {
          if (read['name'] == oldName) read['name'] = newName;
        });
      }
    }
  });
  return true;
}

/// 删掉一个状态。用到它的地方**不动**（检查会把它们标出来，由人决定怎么改）。返回是否删了。
bool lcRemoveState(LcDocument doc, String name, {required bool project}) {
  if (!project) return doc.logic.removeVariable(name);
  var removed = false;
  lcEditProjectStates(doc, (list) {
    final before = list.length;
    list.removeWhere((v) => v.name == name);
    removed = list.length != before;
  });
  return removed;
}
