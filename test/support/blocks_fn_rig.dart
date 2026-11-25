// 第 2 阶段（函数、带口的值、我的积木）界面测试的台子：FakeFnHost + 现成的几串样例 + 找参数小块坐标的帮手。
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/blocks/block_geometry.dart';
import 'package:lopicode/blocks/block_host.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:material_ui/material_ui.dart';

import 'blocks_fake_fn_host.dart';
import 'blocks_fake_host.dart';
import 'blocks_fake_rig.dart';

Finder k(String key) => find.byKey(ValueKey(key));

/// 定义 [问好] (名字) (次数＝1) (…其余)：{ 重复 (次数) 次 { 说 (名字) } }
FakeScript fxGreetDef({double x = 0, double y = 0}) => fakeDef(
  's1',
  'greet',
  const CustomBlockLook('问好', template: '向 {名字} 问好 {次数} 次', slots: [CustomBlockSlot('名字'), CustomBlockSlot('次数', defaultValue: 1)]),
  const [BlockParam('名字'), BlockParam('次数', defaultValue: 1)],
  body: [
    LcBlock(op: 'repeat', args: {'times': fxParam('次数')}, body: [LcBlock(op: 'say', args: {'text': fxParam('名字')})]),
  ],
  x: x,
  y: y,
);

/// 把 (分数) 设为 (把 (空列表) 的每一项变一下 (函数 (x) { 说 (x) ; 返回 (x × 2) }))
LcBlock fxMapBlock({List<LcBlock>? body, List<String> params = const ['x']}) => LcBlock(
  op: 'set',
  args: {
    'name': '分数',
    'value': fxListMap(
      fxExpr('listNew'),
      fxFn(
        params,
        body ??
            [
              fxSay('一项'),
              LcBlock(op: 'return', args: {'value': fxExpr('arith', {'l': fxParam('x'), 'op': '*', 'r': fxNum(2)})}),
            ],
      ),
    ),
  },
);

/// 某一串帽子上的参数小块上写的字。
List<String> chipsOf(FnRig rig, String scriptId) => [for (final c in rig.chips(scriptId)) c.text];

/// 三种调用外观各一块（语句 / 值 / 是否）的定义，加一串把它们都用上的。
List<FakeScript> fxThreeLooks() => [
  FakeScript(
    'use',
    body: [
      LcBlock(op: 'del', args: {'集合': fxVar('分数'), 'id': fxNum(7)}),
      LcBlock(op: 'say', args: {'text': fxExpr('twice', {'数': fxNum(21)})}),
      LcBlock(op: 'if', args: {'cond': fxExpr('big', {'a': fxVar('分数'), 'b': fxNum(60)})}, body: [fxSay('及格')], noElse: true),
    ],
    x: 0,
    y: 0,
  ),
  fakeDef('d1', 'del', const CustomBlockLook('删一条', shape: CustomBlockShape.statement, template: '把 {集合} 里编号是 {id} 的那条删掉', colorKey: BlockColorKey.list, hint: '按编号删掉一条记录'), const [BlockParam('集合'), BlockParam('id')], x: 0, y: 420),
  fakeDef('d2', 'twice', const CustomBlockLook('两倍', shape: CustomBlockShape.value, template: '{数} 的两倍', colorKey: BlockColorKey.operator), const [BlockParam('数')], x: 0, y: 520),
  fakeDef('d3', 'big', const CustomBlockLook('比它大', shape: CustomBlockShape.boolean, template: '{a} 比 {b} 大'), const [BlockParam('a'), BlockParam('b')], x: 0, y: 620),
];

class FnRig extends FakeRig {
  FnRig(List<FakeScript> scripts, {bool wrappable = true}) : super.on(FakeFnHost(scripts: scripts, wrappable: wrappable));

  FakeFnHost get fn => host as FakeFnHost;
  FakeScript script(String id) => fn.fakeScripts.firstWhere((s) => s.id == id);

  Offset at(String scriptId, Offset inScript) {
    final p = s.layout.placed(scriptId)!;
    return s.globalOf(s.toView(p.origin + inScript));
  }

  /// 某一串里所有的参数小块 / “＋”（帽子上的 `owner == null`；值上的给那块积木的路径）。
  List<BkSlot> chips(String scriptId, {LcBlockPath? owner, BkSlotLook look = BkSlotLook.param}) => [
    for (final (b, x) in s.layout.placed(scriptId)!.layout.allSlots)
      if (x.look == look && x.param != null && (owner == null ? b.isHat : (!b.isHat && bkSameBlockPath(b.path, owner)))) x,
  ];

  Offset chip(String scriptId, int index, {LcBlockPath? owner}) => at(scriptId, chips(scriptId, owner: owner)[index].rect.center);
  Offset chipAdd(String scriptId, {LcBlockPath? owner}) => at(scriptId, chips(scriptId, owner: owner, look: BkSlotLook.add).single.rect.center);

  /// 某块积木头上的把手（任意一串）。
  Offset gripIn(String scriptId, LcBlockPath path) => at(scriptId, s.layout.placed(scriptId)!.layout.blockAt(path)!.head.centerLeft + const Offset(7, 0));

  /// 正在拖的时候：某个值槽的落点（按所在积木、参数名、槽里的路径找）。
  Offset exprSnap(String scriptId, LcBlockPath block, String arg, [BkExprPath path = const []]) {
    final p = s.drag!.base.placed(scriptId)!;
    final x = p.layout.snaps.firstWhere((x) => x.kind == BkSnapKind.expr && bkSameBlockPath(x.parent, block) && x.arg == arg && bkSameExprPath(x.exprPath, path));
    return s.globalOf(s.toView(p.origin + x.rect.centerLeft - Offset(6, s.drag!.probeY) + s.grabOffset));
  }

  /// 正在拖的时候：某个口里的落点（任意一串；`arm <= -2` 是值上的口）。
  Offset snapIn(String scriptId, LcBlockPath parent, int index, {int arm = -1, bool inElse = false}) {
    final p = s.drag!.base.placed(scriptId)!;
    final x = p.layout.snaps.firstWhere((x) => x.kind == BkSnapKind.statement && bkSameBlockPath(x.parent, parent) && x.arm == arm && (arm != -1 || x.inElse == inElse) && x.index == index);
    return s.globalOf(s.toView(p.origin + x.anchor + s.grabOffset));
  }
}
