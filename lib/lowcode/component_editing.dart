/// “编辑组件的内容”用的临时文档：怎么造、怎么写回定义（不带界面；界面在 component_editor_sheet.dart）。
library;

import 'package:lopicode/lowcode/comp_lib_builtin.dart';
import 'package:lopicode/lowcode/component_extras.dart';
import 'package:lopicode/lowcode/component_model.dart';
import 'package:lopicode/lowcode/component_ops.dart';
import 'package:lopicode/lowcode/component_slots.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/slots.dart';

/// “编辑组件”用的临时页面的根 id。带下划线：定义里的节点 id 只有字母数字，不会和它撞。
const String kComponentEditRootId = 'page_';

void _walk(LcNode n, void Function(LcNode n) visit) {
  visit(n);
  for (final c in n.children) {
    _walk(c, visit);
  }
}

/// 组件里的绑定能读到的东西：属性（一个属性一个同名的状态，初值＝默认值）＋组件自己的状态。
List<LcVariable> componentScopeVariables(LcComponentDef def) {
  final props = {for (final p in def.props) p.name};
  return [
    for (final p in def.props)
      LcVariable(
        name: p.name,
        type: switch (p.type) {
          'number' => 'number',
          'bool' => 'bool',
          'list' => 'list',
          _ => 'text',
        },
        initial: p.defaultValue,
      ),
    for (final s in lcCompStates(def))
      if (!props.contains(s.name)) LcVariable(name: s.name, type: s.type, initial: s.initial, derived: s.derived),
  ];
}

/// 造一份只在“编辑组件”时用的临时文档：一张空白页，里面只放这个组件的内容（拷贝）。
/// 搭建页现成的画布、属性、样式面板都能直接作用在它上面；改完用 [applyComponentEditing] 写回去。
/// 临时文档里带着别的组件定义（拷贝，供里面套的实例显示、供组件栏列出），会造成循环的那些不带。
LcDocument? componentEditingDocument(LcDocument doc, String componentId) {
  final def = doc.component(componentId);
  if (def == null) return null;
  return LcDocument(
    title: def.name,
    root: LcNode(id: kComponentEditRootId, type: 'page', props: Map.of(lcSpecs['page']!.defaults), children: [copyLcTree(def.root)]),
    // 这一页的“页面级状态”＝组件的属性（按默认值，只是给绑定挑、给画布算初值用）＋组件自己的状态。
    logic: LcLogic(variables: componentScopeVariables(def)),
    components: [
      for (final c in doc.components)
        if (c.id != componentId && !wouldCycle(doc, componentId, c.id))
          LcComponentDef(
            id: c.id,
            name: c.name,
            props: [for (final p in c.props) LcComponentProp(name: p.name, type: p.type, defaultValue: p.defaultValue)],
            keptProps: c.keptProps,
            more: c.more,
            slotLabels: Map.of(c.slotLabels),
            keptSlots: c.keptSlots,
            root: copyLcTree(c.root),
          ),
    ],
    // 主题变量、项目级状态也带上（只读：画布和面板要认得它们；写回定义时不看）。
  )..more.addAll({if (doc.more['theme'] != null) 'theme': doc.more['theme'], if (doc.more['state'] != null) 'state': doc.more['state']});
}

/// 把“编辑组件”的临时文档写回定义：定义的 id、名字、props 都不动，所以实例不会断开。
/// 临时页面里必须正好有一个最外层控件；接到已经不存在的 prop 上的绑定顺手清掉。失败时 [doc] 什么都不改。
///
/// 插槽（见 component_slots.dart）：
/// - 重名的占位节点（复制、粘贴出来的）先在 [editing] 里换成新名字；
/// - 同一个占位节点的插槽名变了：已有实例里填的内容跟着改名；
/// - 一个插槽没了、而有实例在里面填着东西：不让改，返回原因（“取消插槽”那条路会先把内容挪出来，不走到这儿）。
const String kNoDialogInComponent = '弹窗是整页的东西，不能放进组件里。请回到页面上加弹窗。';

LcOpResult applyComponentEditing(LcDocument doc, String componentId, LcDocument editing) {
  final def = doc.component(componentId);
  if (def == null) return const LcOpResult.fail('这个组件已经不存在了');
  if (editing.root.children.length != 1) return const LcOpResult.fail('组件最外层只能有一个控件');
  if (editing.root.children.single.type == 'slot') return const LcOpResult.fail('组件最外层不能是插槽。让最外层是一个容器，再把它的内容设成插槽。');
  // 弹窗是整页的东西：不管从哪条路进来的（点、拖、粘贴），组件里都不能有。
  var hasDialog = false;
  _walk(editing.root, (n) => hasDialog = hasDialog || n.type == 'dialog');
  if (hasDialog) return const LcOpResult.fail(kNoDialogInComponent);
  dedupeSlots(editing.root.children.single);
  final root = copyLcTree(editing.root.children.single);
  var cycle = false;
  final seen = <String>{};
  var next = 1;
  _walk(root, (n) {
    final ref = n.props['ref'];
    if (n.type == 'component' && ref is String && wouldCycle(doc, componentId, ref)) cycle = true;
    // 定义里的 id 只能是字母数字、互不重复（临时文档里新加的节点是 n数字，本来就合规矩；这里防万一）。
    if (!RegExp(r'^[A-Za-z0-9]+$').hasMatch(n.id) || !seen.add(n.id)) {
      while (!seen.add('e$next')) {
        next++;
      }
      n.id = 'e$next';
    }
    n.bind.removeWhere((attr, name) {
      final p = def.prop(name);
      return p == null || !bindablePropsFor(n.type).contains(attr) || !propTypeFitsAttr(p.type, attr);
    });
  });
  if (cycle) return const LcOpResult.fail('组件里不能放它自己（或者里面用到了它的组件）');
  // 插槽：按占位节点的 id 对上改之前的，看谁改了名、谁没了。
  final before = {for (final s in slotNodesIn(def.root).reversed) s.id: lcSlotNameOf(s)};
  final after = {for (final s in slotNodesIn(root).reversed) s.id: lcSlotNameOf(s)};
  final renames = <String, String>{
    for (final e in before.entries)
      if (after[e.key] != null && after[e.key] != e.value) e.value: after[e.key]!,
  };
  final lost = before.values.toSet().difference({...after.values, ...renames.keys});
  final blocked = slotLossBlock(doc, componentId, lost, const {});
  if (blocked != null) return LcOpResult.fail(blocked);
  renameSlotsInInstances(doc, componentId, renames);
  def.root = root;
  // 组件里用到了内置组件库里的组件、而文档里还没有那个定义：这时候装进来。
  _walk(root, (n) => lcEnsureBuiltin(doc, n.type == 'component' && n.props['ref'] is String ? n.props['ref'] as String : null));
  // 临时页面里不是属性的那些状态＝组件自己的状态（每个实例一份）。
  final propNames = {for (final p in def.props) p.name};
  lcSetCompStates(def, [
    for (final v in editing.logic.variables)
      if (!propNames.contains(v.name)) v,
  ]);
  lcLinkInstances(doc);
  return LcOpResult.ok(componentId: componentId);
}
