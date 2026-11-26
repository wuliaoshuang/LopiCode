// 自定义组件的插槽（第 3 期第 3 段）：读写、展开、定义那一头的操作、已有实例里的内容不丢。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/lowcode/component_editing.dart';
import 'package:lopicode/lowcode/component_expand.dart';
import 'package:lopicode/lowcode/component_ops.dart';
import 'package:lopicode/lowcode/component_slots.dart';
import 'package:lopicode/lowcode/editor_clipboard.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/multi_select.dart';
import 'package:lopicode/lowcode/slots.dart';

import 'support/slot_sample.dart';

List<String> _ids(Iterable<LcNode> nodes) => [for (final n in nodes) n.id];

List<String> _texts(LcNode root) {
  final out = <String>[];
  void walk(LcNode n) {
    final t = n.strProp('text');
    if (t != null) out.add(t);
    n.children.forEach(walk);
  }

  walk(root);
  return out;
}

void main() {
  group('读写', () {
    test('样例页读进来再写出去一字不差；定义的插槽按占位节点算', () {
      final text = const JsonEncoder.withIndent('  ').convert(slotCardJson());
      final doc = LcDocument.parse(text);
      expect(jsonDecode(doc.encode()), slotCardJson());
      final def = doc.component('c1')!;
      expect([for (final s in def.slots) (s.name, s.label, s.row)], [('default', '内容', false), ('footer', '底部按钮', true)]);
      final a = doc.find('a')!;
      expect(a.hasSlots && a.isContainer, isTrue);
      expect(_ids(lcSlotChildren(a, 'default')), ['p1', 'p2']);
      expect(_ids(lcSlotChildren(a, 'footer')), ['b1', 'b2']);
      expect(lcFallbackSlot(a), 'default');
    });

    test('占位节点没起名字：名字用文件 slots 里写的，再不然“默认插槽”/ 插槽名；slots 里读不懂的项原样留着', () {
      final json = slotCardJson();
      final def = (json['components']! as List).single as Map<String, Object?>;
      (((def['root']! as Map)['children'] as List)[1]['children'] as List)[0].remove('name');
      (((def['root']! as Map)['children'] as List)[2]['children'] as List)[0].remove('name');
      def['slots'] = [
        {'name': 'footer', 'label': '按钮区'},
        {'name': 'gone', 'label': '没有了的'},
        'x',
      ];
      final doc = LcDocument.parse(jsonEncode(json));
      expect([for (final s in doc.component('c1')!.slots) (s.name, s.label)], [('default', '默认插槽'), ('footer', '按钮区')]);
      final out = (jsonDecode(doc.encode())['components'] as List).single['slots'];
      expect(out, [
        {'name': 'default', 'label': '默认插槽'},
        {'name': 'footer', 'label': '按钮区'},
        'x',
      ], reason: '定义里已经没有占位节点的那一项（gone）不再写；读不懂的原样留着');
    });

    test('最外层是插槽的定义读不成组件（原样留在文件里）；没有插槽的定义，实例带的子节点留着', () {
      final json = slotCardJson();
      final def = (json['components']! as List).single as Map<String, Object?>;
      def['root'] = {'id': 'k1', 'type': 'slot'};
      final doc = LcDocument.parse(jsonEncode(json));
      expect(doc.component('c1'), isNull);
      expect(jsonDecode(doc.encode())['components'], json['components']);
      expect(_ids(doc.find('a')!.children), ['p1', 'p2', 'b1', 'b2'], reason: '定义读不出来，填的内容也不丢');
      expect(lcHomelessContent(doc, doc.find('a')!), 4);
    });
  });

  group('展开', () {
    test('导出用：填了的用填的（保留页面里的 id），没填的用默认内容；占位节点不留', () {
      final doc = slotCardPage();
      final tree = expandedTree(doc);
      final a = tree.children[1], b = tree.children[2];
      expect((a.id, a.type), ('a', 'card'));
      expect(_texts(a), ['草莓蛋糕', '新鲜草莓，当天现做', '¥ 68', '立即购买', '收藏']);
      expect(_ids(a.children[1].children), ['p1', 'p2']);
      expect(_ids(a.children[2].children), ['b1', 'b2']);
      expect(_texts(b), ['商品名', '暂无介绍', '加入购物车']);
      expect(_ids(b.children[1].children), ['b__k5']);
      var slots = 0;
      void walk(LcNode n) {
        if (n.type == 'slot' || n.slot != null) slots++;
        n.children.forEach(walk);
      }

      walk(tree);
      expect(slots, 0, reason: '展开后没有占位节点，内容也不带 slot 字段');
      expect(doc.find('p2')!.slot, 'default', reason: '不改文档');
    });

    test('画布用：留记号（host / filled），填进去的就是页面里的原节点', () {
      final doc = slotCardPage();
      final a = expandInstance(doc, doc.find('a')!, markers: true)!;
      final m = a.children[1].children.single;
      expect((m.type, m.props['host'], m.props['filled'], m.name), ('slot', 'a', true, '内容'));
      expect(identical(m.children.first, doc.find('p1')), isTrue);
      final b = expandInstance(doc, doc.find('b')!, markers: true)!;
      final mb = b.children[2].children.single;
      expect((mb.props['name'], mb.props['host'], mb.props['filled']), ('footer', 'b', null));
      expect(_texts(mb), ['加入购物车']);
    });

    test('卡片里再放一张卡片不算循环；同名的占位只有第一个接内容', () {
      final doc = slotCardPage();
      final inner = doc.newNode('component')..props['ref'] = 'c1';
      expect(lcInsertAt(doc, lcSlotBoxId('a', 'default'), inner), isTrue);
      expect(inner.slot, 'default');
      final a = expandedTree(doc).children[1];
      expect(_texts(a), containsAllInOrder(['¥ 68', '商品名', '暂无介绍', '加入购物车', '立即购买']));
      // 同名占位
      final def = doc.component('c1')!;
      def.root.children.add(
        LcNode(
          id: 'k9',
          type: 'slot',
          children: [
            LcNode(id: 'k10', type: 'text', props: {'text': '第二个默认'}),
          ],
        ),
      );
      expect(def.slots.length, 2);
      final again = expandedTree(doc).children[1];
      expect(_texts(again).where((t) => t == '¥ 68').length, 1);
      expect(_texts(again).last, '第二个默认');
    });

    test('拆开：填的内容接在插槽的位置上，还是原来那几个节点；连逻辑认的 id 都不变', () {
      final doc = slotCardPage();
      final p1 = doc.find('p1')!;
      expect(detachInstance(doc, 'a').ok, isTrue);
      final a = doc.find('a')!;
      expect(a.type, 'card');
      expect(identical(doc.find('p1'), p1), isTrue);
      expect(_ids(a.children[1].children), ['p1', 'p2']);
      expect(_ids(a.children[2].children), ['b1', 'b2']);
      expect(doc.find('p2')!.slot, isNull);
      expect(LcDocument.parse(doc.encode()).encode(), doc.encode());
    });

    test('页面里误放的占位节点：导出时只留它里面的内容', () {
      final doc = slotCardPage();
      doc.root.children.add(
        LcNode(
          id: 'stray',
          type: 'slot',
          children: [
            LcNode(id: 'in', type: 'text', props: {'text': '里面的'}),
          ],
        ),
      );
      final tree = expandedTree(doc);
      expect(_ids(tree.children), ['head', 'a', 'b', 'in']);
    });
  });

  group('定义那一头', () {
    LcDocument editing(LcDocument doc) => componentEditingDocument(doc, 'c1')!;

    test('设成插槽：容器不变，原来的内容成了默认内容；名字、默认插槽、重名、上限', () {
      final doc = LcDocument.starter('x');
      final box = doc.newNode('column');
      doc.insert(doc.root.id, box);
      doc.insert(box.id, doc.newNode('text'));
      final save = saveAsComponent(doc, box.id, '盒子');
      final id = save.componentId!;
      final e = componentEditingDocument(doc, id)!;
      final top = e.root.children.single;
      expect(canMakeSlot(e, top.id), isNull);
      expect(canMakeSlot(e, top.children.single.id), contains('只有容器'));
      final r = makeSlot(e, top.id, label: '内容', asDefault: true);
      expect(r.ok, isTrue);
      final slot = e.find(r.nodeId!)!;
      expect((slot.type, slot.name, slot.props.containsKey('name'), slot.children.single.type), ('slot', '内容', false, 'text'));
      expect(top.children.single, same(slot));
      expect(canMakeSlot(e, top.id), contains('已经是插槽'));
      expect(applyComponentEditing(doc, id, e).ok, isTrue);
      expect([for (final s in doc.component(id)!.slots) (s.name, s.label)], [('default', '内容')]);
      expect((jsonDecode(doc.encode())['components'] as List).single['slots'], [
        {'name': 'default', 'label': '内容'},
      ]);
      expect(doc.find(save.nodeId!)!.hasSlots, isTrue, reason: '页面上的实例马上认得新插槽');
      // 起名
      expect(slotNameFor('footer', {'default'}, asDefault: false), 'footer');
      expect(slotNameFor('底部', {'default', 's1'}, asDefault: false), 's2');
      expect(slotNameFor('default', {}, asDefault: false), 's1');
      expect(slotLabelProblem(e, '内容', asDefault: false), contains('已经有一个叫'));
      expect(slotLabelProblem(e, '', asDefault: false), '给插槽起个名字');
      expect(slotLabelProblem(e, '别的', asDefault: true), '这个组件已经有默认插槽了');
      expect(slotLabelProblem(e, '内容', asDefault: true, slotNodeId: slot.id), isNull);
    });

    test('最外层不能是插槽；重名的占位（复制出来的）写回时自动换名', () {
      final doc = slotCardPage();
      final e = editing(doc);
      final copyId = e.duplicate('k7')!;
      expect(applyComponentEditing(doc, 'c1', e).ok, isTrue);
      expect([for (final s in doc.component('c1')!.slots) (s.name, s.label)], [('default', '内容'), ('footer', '底部按钮'), ('s1', '底部按钮 2')]);
      expect(lcSlotNameOf(e.find(copyId)!), 's1');
      final bad = LcDocument(
        title: '',
        root: LcNode(
          id: kComponentEditRootId,
          type: 'page',
          children: [LcNode(id: 'k1', type: 'slot')],
        ),
      );
      expect(applyComponentEditing(doc, 'c1', bad).error, contains('最外层不能是插槽'));
    });

    test('改名：实例里填的内容跟着改（没写 slot 的也写上）；撤销回去再跟着改回来', () {
      final doc = slotCardPage();
      final e = editing(doc);
      final before = e.encode();
      expect(renameSlot(e, 'k7', label: '操作', asDefault: false).componentId, 's1');
      expect(renameSlot(e, 'k4', label: 'body', asDefault: false).componentId, 'body');
      expect(applyComponentEditing(doc, 'c1', e).ok, isTrue);
      expect([for (final c in doc.find('a')!.children) c.slot], ['body', 'body', 's1', 's1']);
      expect(_texts(expandedTree(doc).children[1]), ['草莓蛋糕', '新鲜草莓，当天现做', '¥ 68', '立即购买', '收藏']);
      // 只改给人看的名字：代码里的名字不动
      expect(renameSlot(e, 'k7', label: '操作区', asDefault: false).componentId, 's1');
      // 撤销＝把改之前的临时文档写回去
      expect(applyComponentEditing(doc, 'c1', LcDocument.parse(before)).ok, isTrue);
      expect([for (final c in doc.find('a')!.children) c.slot], ['default', 'default', 'footer', 'footer']);
    });

    test('取消插槽：先数得出有几处填了；内容挪到实例后面、先后不变，不删', () {
      final doc = slotCardPage();
      expect(slotFillCount(doc, 'c1', 'footer'), (instances: 1, nodes: 2));
      expect(slotFillCount(doc, 'c1', 'default'), (instances: 1, nodes: 2));
      final e = editing(doc);
      expect(unwrapSlot(e, 'k7').ok, isTrue);
      expect(_ids(e.find('k6')!.children), ['k8'], reason: '默认内容留在原位');
      // 不先挪内容直接写回：拦下
      final blocked = applyComponentEditing(doc, 'c1', e);
      expect(blocked.error, allOf(contains('底部按钮'), contains('1 个实例'), contains('取消插槽')));
      expect(doc.component('c1')!.slots.length, 2, reason: '拦下时什么都没改');
      expect(evictSlotContent(doc, 'c1', 'footer'), 2);
      expect(applyComponentEditing(doc, 'c1', e).ok, isTrue);
      expect(_ids(doc.root.children), ['head', 'a', 'b1', 'b2', 'b']);
      expect(doc.find('b1')!.slot, isNull);
      expect(_ids(doc.find('a')!.children), ['p1', 'p2']);
    });

    test('删掉占位节点、或者连它外面的容器一起删：有实例填着东西就不让；没人填就可以', () {
      final doc = slotCardPage();
      final e = editing(doc);
      e.remove('k6');
      expect(applyComponentEditing(doc, 'c1', e).error, contains('没地方放'));
      doc.remove('b1');
      doc.remove('b2');
      expect(applyComponentEditing(doc, 'c1', e).ok, isTrue);
      expect([for (final s in doc.component('c1')!.slots) s.name], ['default']);
    });

    test('实例是另一个组件的最外层时取消插槽：外面包一层容器接住内容', () {
      final doc = slotCardPage();
      final wrap = LcDocument.parse(
        jsonEncode(
          slotCardJson()
            ..['components'] = [
              ...(slotCardJson()['components']! as List),
              {
                'id': 'c2',
                'name': 'Outer',
                'root': {
                  'id': 'k1',
                  'type': 'component',
                  'props': {'ref': 'c1'},
                  'children': [
                    {
                      'id': 'k2',
                      'type': 'text',
                      'props': {'text': '外层填的'},
                    },
                  ],
                },
              },
            ],
        ),
      );
      expect(doc.components.length, 1);
      expect(evictSlotContent(wrap, 'c1', 'default'), 3);
      final root = wrap.component('c2')!.root;
      expect(root.type, 'container');
      expect(_ids(root.children), ['k1', 'k2']);
    });

    test('删组件：拆开留着时填的内容还在；数得出有几处填了东西', () {
      final doc = slotCardPage();
      expect(componentFillCount(doc, 'c1'), (instances: 1, nodes: 4));
      expect(deleteComponent(doc, 'c1', instances: LcDeleteInstances.detach).ok, isTrue);
      expect(_texts(doc.root), containsAllInOrder(['草莓蛋糕', '新鲜草莓，当天现做', '¥ 68', '立即购买', '收藏', '商品名', '暂无介绍', '加入购物车']));
      expect(doc.find('p1'), isNotNull);
    });
  });

  group('别的路子', () {
    test('多选：同一个实例里，同一个插槽的才算同一层', () {
      final doc = slotCardPage();
      final ids = <String>{};
      expect(lcMultiToggle(doc, ids, 'p1'), isNull);
      expect(lcMultiToggle(doc, ids, 'p2'), isNull);
      expect(lcMultiToggle(doc, ids, 'b1'), kLcMultiSameLevelOnly);
      expect(ids, {'p1', 'p2'});
    });

    test('复制粘贴：实例连同填的内容一起带走；占位节点贴进页面时拿掉、内容留下', () {
      lcClipboardClear();
      final doc = slotCardPage();
      expect(lcClipboardCopy(doc, 'a'), isTrue);
      final pasted = doc.find(lcClipboardPasteAfter(doc, 'a')!)!;
      expect(_texts(pasted), ['新鲜草莓，当天现做', '¥ 68', '立即购买', '收藏']);
      expect([for (final c in pasted.children) c.slot], [null, 'default', 'footer', 'footer']);
      expect(doc.components.length, 1, reason: '一样的定义不重复带');
      final e = componentEditingDocument(doc, 'c1')!;
      expect(lcClipboardCopy(e, 'k3'), isTrue);
      final id = lcClipboardPaste(doc, doc.root.id)!;
      expect(_ids(doc.find(id)!.children).length, 1);
      expect(doc.find(id)!.children.single.type, 'text');
      // 贴回组件编辑页：占位留着，重名的写回时换名
      final back = e.find(lcClipboardPasteAfter(e, 'k3')!)!;
      expect(back.children.single.type, 'slot');
      expect(applyComponentEditing(doc, 'c1', e).ok, isTrue);
      expect(doc.component('c1')!.slots.length, 3);
      lcClipboardClear();
    });

    test('重复一份、包成容器、存成组件：实例带的内容都跟着；里面有弹窗的不能存成组件', () {
      final doc = slotCardPage();
      final copy = doc.find(doc.duplicate('a')!)!;
      expect(copy.children.length, 4);
      expect(copy.hasSlots, isTrue);
      final box = doc.find(wrapInContainer(doc, 'b1')!)!;
      expect((box.slot, doc.parentOf(box.id)!.id), ('footer', 'a'));
      final dialog = doc.newNode('dialog');
      doc.insert(doc.root.id, dialog);
      expect(canSaveAsComponent(doc, dialog.id), '弹窗是整页的东西，不能存成组件');
      final outer = doc.newNode('column');
      doc.insert(doc.root.id, outer);
      doc.move(dialog.id, outer.id, 0);
      expect(canSaveAsComponent(doc, outer.id), allOf(contains('1 个弹窗'), contains('先把弹窗拖到外面')));
      expect(saveAsComponent(doc, outer.id, '带弹窗').ok, isFalse);
    });

    test('往实例里放东西：指明插槽就进那个插槽，没指明跟前一个兄弟；拖出来 slot 去掉', () {
      final doc = slotCardPage();
      final t = doc.newNode('text');
      expect(lcInsertAt(doc, lcSlotBoxId('b', 'footer'), t), isTrue);
      expect((t.slot, doc.parentOf(t.id)!.id), ('footer', 'b'));
      expect(lcInsertAt(doc, lcSlotBoxId('b', 'nope'), doc.newNode('text')), isFalse);
      expect(lcMoveTo(doc, 'b1', doc.root.id, 0), isTrue);
      expect(doc.find('b1')!.slot, isNull);
      expect(lcMoveTo(doc, 'b1', lcSlotBoxId('a', 'default'), 0), isTrue);
      expect(_ids(lcSlotChildren(doc.find('a')!, 'default')), ['b1', 'p1', 'p2']);
    });
  });
}
