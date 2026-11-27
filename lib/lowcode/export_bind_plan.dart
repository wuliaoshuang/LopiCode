/// 导出时“这一页要不要走状态与绑定那条路”（第 5 期），以及三种网页导出共用的小工具。
///
/// 走不走：这一页的控件上有绑定、项目里有项目级状态、或者这一页有派生值 / 列表 / 记录类型的状态——三样占一样就走。
/// 都没有的页面（所有旧页面）不走，导出的文件和以前逐字节一样。
library;

import 'package:lopicode/lowcode/bind_eval.dart';
import 'package:lopicode/lowcode/bind_js.dart';
import 'package:lopicode/lowcode/bind_model.dart';
import 'package:lopicode/lowcode/bind_preview.dart';
import 'package:lopicode/lowcode/export_web_v3.dart';
import 'package:lopicode/lowcode/logic_expr.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/state_model.dart';

const String kNoteBindings = '这一页用了状态和数据绑定：状态改了，绑了它的地方自己跟着变。';
const String kNoteBindRepeatEvents = '“重复”出来的每一份里，按钮的事件处理是同一个：处理里还拿不到“是哪一项”（下一期做）。';
const String kNoteBindComponent = '自定义组件的定义里的绑定这一版不导出（组件自己的状态留给下一期）。';

class LcBindPlan {
  LcBindPlan._(this.doc, this.states, this.env);

  /// 不走绑定那条路返回 null。[tree]＝这一页展开以后的树。
  static LcBindPlan? of(LcDocument doc, LcNode tree) {
    final project = lcProjectStates(doc);
    final own = doc.logic.variables;
    final wide = own.any((v) => v.isDerived || !LcVariable.types.contains(v.type));
    if (project.isEmpty && !wide && !lcTreeHasBindings(tree)) return null;
    final seen = <String>{};
    final states = [
      for (final s in lcStatesInScope(doc))
        if (seen.add(s.name)) s,
    ];
    return LcBindPlan._(doc, states, LcBindEnv.of(doc));
  }

  /// 不管用没用绑定都给一份（组件文件用：没有绑定的定义也要按这张表读属性）。
  static LcBindPlan forced(LcDocument doc) {
    final seen = <String>{};
    return LcBindPlan._(doc, [
      for (final s in lcStatesInScope(doc))
        if (seen.add(s.name)) s,
    ], LcBindEnv.of(doc));
  }

  final LcDocument doc;

  /// 这一页看得到的状态（页面的在前；重名只留第一个）。
  final List<LcStateRef> states;

  /// 按初值算（导出的初始界面用）。
  final LcBindEnv env;

  LcStateRef? state(String name) {
    for (final s in states) {
      if (s.name == name) return s;
    }
    return null;
  }

  /// 给积木翻译用：先找这一页的，再找项目级的。
  LcVariable? lookup(String name) => state(name)?.variable;

  Iterable<LcStateRef> get plain => states.where((s) => !s.variable.isDerived);
  Iterable<LcStateRef> get derived => states.where((s) => s.variable.isDerived);
  bool get hasProject => states.any((s) => s.project);

  /// 初始界面上这个节点的样子（绑定按初值算好）。在“重复”里面的不算（那里的值每一份不一样）。
  LcNode shown(LcNode n, {required bool inRepeat}) => inRepeat ? n : lcBoundNode(n, env, placeholder: false);

  /// 初始界面上要不要先藏起来（显示 / 存在条件按初值不成立，或者是“重复”的样板）。
  bool startsHidden(LcNode n, {required bool inRepeat}) {
    if (!lcCanWrapBind(n)) return false;
    if (lcRepeatOf(n) != null) return true;
    return !inRepeat && !lcCondHolds(n, env);
  }
}

/// 状态的类型在 JS 式子里算什么（派生的、列表、记录都当“不确定”，用的时候再转）。
String lcStateJsType(LcVariable v) => v.isDerived ? LcType.any : lcBindTypeOf(v.type);

// —— 第 3 版组件（元素树）上的绑定 ——

const String _mark = '\u0002';

/// 把绑了的文字属性换成记号的副本（元素树建出来以后靠记号认出“这段文字是哪个属性的”）。没有这种绑定返回 [n] 本身。
LcNode lcSentinelNode(LcNode n) {
  final props = [
    for (final p in lcBoundProps(n))
      if (lcBindable(n.type, p)?.type == 'text') p,
  ];
  if (props.isEmpty) return n;
  return LcNode(
    id: n.id,
    type: n.type,
    props: {...n.props, for (final p in props) p: '$_mark$p$_mark'},
    children: n.children,
    style: n.style,
    bind: n.bind,
    name: n.name,
    locked: n.locked,
    hidden: n.hidden,
    keptProps: n.keptProps,
    more: n.more,
  )..instSlots = n.instSlots;
}

/// 这段文字是不是记号；是的话返回属性名。
String? lcSentinelProp(String? text) => text != null && text.length > 2 && text.startsWith(_mark) && text.endsWith(_mark) ? text.substring(1, text.length - 1) : null;

/// 走一遍这个组件自己的元素（不进子组件）。
void lcVisitEl(LcEl root, void Function(LcEl e) visit) {
  visit(root);
  for (final k in root.kids) {
    if (k is LcEl) lcVisitEl(k, visit);
  }
}

/// 这个元素是不是“能填能点的那个控件本身”（禁用、提示文字、双向都落在它上面）。
bool lcIsControlEl(LcEl e) => e.tag == 'input' || e.tag == 'textarea' || e.tag == 'select';

/// 第 3 版组件带绑定时的元素树：按带记号的副本建，再把“贴着页面边”这种要认原节点的属性补回来。
LcEl? lcBoundWebElement(LcNode n, LcWebCtx ctx) {
  final plain = lcWebElement(n, ctx);
  final marked = lcSentinelNode(n);
  if (plain == null || identical(marked, n)) return plain;
  final el = lcWebElement(marked, ctx);
  if (el != null && plain.attrs.containsKey('data-page')) el.attrs['data-page'] = plain.attrs['data-page'];
  return el;
}
