// 自定义组件（E 块）的纯逻辑测试：存成组件、props 与绑定、展开实例、拆开、删除、导出。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/lowcode/component_editor_sheet.dart';
import 'package:lopicode/lowcode/component_model.dart';
import 'package:lopicode/lowcode/component_ops.dart';
import 'package:lopicode/lowcode/export_dart.dart';
import 'package:lopicode/lowcode/export_html.dart';
import 'package:lopicode/lowcode/logic_edit.dart';
import 'package:lopicode/lowcode/logic_js_core.dart';
import 'package:lopicode/lowcode/logic_model.dart';
import 'package:lopicode/lowcode/model.dart';

/// 起始页面：root › n1 标题、n2 说明、n3 卡片 › n4 输入框、n5 “提交”按钮。
LcDocument starter() => LcDocument.starter('小站');

/// 一个“标题卡”组件 c1：卡片 k1 › 文本 k2（text 接 title、color 接 tint）、按钮 k3（text 接 count、bg 接 tint）、图片 k4（src 接 pic）、输入框 k5（placeholder 接 title）。
LcComponentDef titleCard() => LcComponentDef(
  id: 'c1',
  name: '标题卡',
  props: [
    LcComponentProp(name: 'title', defaultValue: '默认标题'),
    LcComponentProp(name: 'count', type: 'number', defaultValue: 3),
    LcComponentProp(name: 'tint', type: 'color', defaultValue: '#112233'),
    LcComponentProp(name: 'pic'),
    LcComponentProp(name: 'on', type: 'bool', defaultValue: true),
  ],
  root: LcNode(
    id: 'k1',
    type: 'card',
    props: {'padding': 16, 'bg': '#FFFFFF', 'width': 'fill'},
    style: {'opacity': '0.9'},
    children: [
      LcNode(id: 'k2', type: 'text', props: {'text': '原文', 'color': '#222435'}, bind: {'text': 'title', 'color': 'tint'}),
      LcNode(id: 'k3', type: 'button', props: {'text': '按钮', 'bg': '#058654'}, bind: {'text': 'count', 'bg': 'tint'}),
      LcNode(id: 'k4', type: 'image', props: {'src': '', 'height': 80}, bind: {'src': 'pic'}),
      LcNode(id: 'k5', type: 'input', props: {'placeholder': '请输入'}, bind: {'placeholder': 'title'}),
    ],
  ),
);

LcNode instance(String ref, {String id = '', Map<String, dynamic>? values, Map<String, dynamic>? extra, Map<String, String>? style}) =>
    LcNode(id: id, type: 'component', props: {'ref': ref, 'values': ?values, ...?extra}, style: style);

LcDocument docWith(List<LcNode> children, List<LcComponentDef> defs) => LcDocument(
  title: 't',
  root: LcNode(id: 'root', type: 'page', children: children),
  components: defs,
);

List<String> idsOf(LcNode root) {
  final out = <String>[];
  void walk(LcNode n) {
    out.add(n.id);
    n.children.forEach(walk);
  }

  walk(root);
  return out;
}

/// 存盘再读回来还是同一份（改出来的文档必须是合法的页面文件）。
void expectRoundTrips(LcDocument doc) => expect(LcDocument.parse(doc.encode()).encode(), doc.encode());

void main() {
  group('存成组件', () {
    test('子树变成新定义，原位置换成实例（沿用原来的 id），展开后和原来一样', () {
      final doc = starter();
      final before = doc.find('n3')!.clone();
      final r = saveAsComponent(doc, 'n3', '  表单卡  ');
      expect(r.ok, isTrue);
      expect(r.nodeId, 'n3');
      expect(r.componentId, 'c1');
      final def = doc.component('c1')!;
      expect(def.name, '表单卡');
      expect(def.props, isEmpty);
      expect(idsOf(def.root), ['k1', 'k2', 'k3'], reason: '定义里的 id 重新编号、互不重复');
      final inst = doc.find('n3')!;
      expect(inst.type, 'component');
      expect(inst.props, {'ref': 'c1'});
      expect(doc.find('n4'), isNull, reason: '里面的控件搬进定义了，页面里不该再有');
      final ex = expandInstance(doc, inst)!;
      expect(ex.id, 'n3');
      expect(ex.type, before.type);
      expect(ex.props, before.props);
      expect([for (final c in ex.children) c.type], [for (final c in before.children) c.type]);
      expect([for (final c in ex.children) c.props], [for (final c in before.children) c.props]);
      expectRoundTrips(doc);
    });

    test('名字：空的、太长的拒绝；重名自动加序号；id 不和已有定义撞', () {
      final doc = starter();
      expect(saveAsComponent(doc, 'n3', '   ').error, contains('不能为空'));
      expect(saveAsComponent(doc, 'n3', '字' * 31).error, contains('最多 30'));
      expect(doc.components, isEmpty);
      expect(doc.find('n3')!.type, 'card', reason: '失败时什么都不改');
      expect(saveAsComponent(doc, 'n3', '字' * 30).ok, isTrue);
      expect(saveAsComponent(doc, 'n1', '字' * 30).ok, isTrue);
      expect(doc.components[1].name, '${'字' * 28} 2');
      expect(doc.components[1].name.runes.length, lessThanOrEqualTo(kComponentNameMax));
      expect(doc.components.map((c) => c.id), ['c1', 'c2']);
      doc.components.removeAt(0);
      expect(saveAsComponent(doc, 'n2', '卡').componentId, 'c1', reason: '空出来的 id 可以再用');
    });

    test('页面根、不存在的、已经是实例的不能存', () {
      final doc = starter();
      expect(saveAsComponent(doc, 'root', 'x').error, contains('整个页面'));
      expect(saveAsComponent(doc, 'nope', 'x').error, contains('找不到'));
      saveAsComponent(doc, 'n3', '卡');
      expect(saveAsComponent(doc, 'n3', 'x').error, contains('已经是'));
      expect(canSaveAsComponent(doc, 'n1'), isNull);
    });

    test('子树里有积木逻辑在用的控件：拒绝并说明，文档不变', () {
      final doc = starter();
      doc.logic.handlers.add(LcHandler(id: 'h1', event: 'click', target: 'n5'));
      final snapshot = doc.encode();
      final r = saveAsComponent(doc, 'n3', '卡');
      expect(r.ok, isFalse);
      expect(r.error, contains('积木逻辑'));
      expect(r.error, contains('1 处'));
      expect(doc.encode(), snapshot);
      // 去掉逻辑以后就能存了。
      doc.logic.removeNodeRefs('n5');
      expect(saveAsComponent(doc, 'n3', '卡').ok, isTrue);
    });

    test('子树里本来就有别的组件的实例：可以存（套着用），展开两层', () {
      final doc = docWith(
        [
          LcNode(
            id: 'n1',
            type: 'column',
            children: [
              instance('c1', id: 'n2', values: {'title': '甲'}),
            ],
          ),
        ],
        [titleCard()],
      );
      expect(saveAsComponent(doc, 'n1', '外壳').ok, isTrue);
      final ex = expandInstance(doc, doc.find('n1')!)!;
      expect(ex.type, 'column');
      expect(ex.children.single.type, 'card');
      expect(ex.children.single.children.first.props['text'], '甲');
      expect(idsOf(ex).toSet().length, idsOf(ex).length);
      expect(componentUseCount(doc, 'c1'), 1, reason: '定义里的实例也算一次');
    });
  });

  group('展开实例', () {
    test('没传值用默认值；传了用传的；数字显示成文字不带 .0', () {
      final doc = docWith(
        [
          instance('c1', id: 'a'),
          instance('c1', id: 'b', values: {'title': '你好', 'count': 7.0, 'tint': '#abcdef', 'pic': 'https://x.test/p.png'}),
        ],
        [titleCard()],
      );
      final a = expandInstance(doc, doc.find('a')!)!;
      expect(a.children[0].props['text'], '默认标题');
      expect(a.children[0].props['color'], '#112233');
      expect(a.children[1].props['text'], '3');
      expect(a.children[1].props['bg'], '#112233');
      expect(a.children[2].props['src'], '');
      expect(a.children[3].props['placeholder'], '默认标题');
      final b = expandInstance(doc, doc.find('b')!)!;
      expect(b.children[0].props['text'], '你好');
      expect(b.children[0].props['color'], '#ABCDEF');
      expect(b.children[1].props['text'], '7');
      expect(b.children[2].props['src'], 'https://x.test/p.png');
      // 展开不改文档：定义里还是原来的内容和绑定。
      expect(doc.component('c1')!.root.children[0].props['text'], '原文');
      expect(doc.component('c1')!.root.children[0].bind, {'text': 'title', 'color': 'tint'});
      expect(b.children[0].bind, isEmpty);
    });

    test('值的类型不对用默认值', () {
      final inst = instance('c1', id: 'a');
      // 绕过读文件时的清理，直接塞怪值。
      inst.props['values'] = {'title': 5, 'count': 'many', 'tint': 'red', 'pic': true, 'on': 'yes', 'ghost': 1};
      final doc = docWith([inst], [titleCard()]);
      final a = expandInstance(doc, inst)!;
      expect(a.children[0].props['text'], '默认标题');
      expect(a.children[0].props['color'], '#112233');
      expect(a.children[1].props['text'], '3');
      expect(instanceValues(doc.component('c1')!, inst), {'title': '默认标题', 'count': 3, 'tint': '#112233', 'pic': '', 'on': true});
      inst.props['values'] = 'not a map';
      expect(expandInstance(doc, inst)!.children[0].props['text'], '默认标题');
      inst.props['values'] = {'count': double.nan};
      expect(expandInstance(doc, inst)!.children[1].props['text'], '3');
    });

    test('id：最外层是实例的 id，里面是 实例id__内部id，全页唯一、能拼进选择器', () {
      final doc = docWith([instance('c1', id: 'a'), instance('c1', id: 'b'), LcNode(id: 'a__k2', type: 'text')], [titleCard()]);
      final a = expandInstance(doc, doc.find('a')!)!;
      final b = expandInstance(doc, doc.find('b')!)!;
      expect(idsOf(b), ['b', 'b__k2', 'b__k3', 'b__k4', 'b__k5']);
      expect(idsOf(a), ['a', 'a__k2_', 'a__k3', 'a__k4', 'a__k5'], reason: '页面里已经有一个叫 a__k2 的节点，要避开');
      final all = [...idsOf(expandedTree(doc))];
      expect(all.toSet().length, all.length);
      expect(all.every(isSafeNodeId), isTrue);
    });

    test('实例自己的宽度、外边距、style 盖在最外层', () {
      final doc = docWith(
        [
          instance('c1', id: 'a', extra: {'width': 200, 'margin': 4}, style: {'opacity': '0.5', 'height': '90px'}),
        ],
        [titleCard()],
      );
      final a = expandInstance(doc, doc.find('a')!)!;
      expect(a.props['width'], 200);
      expect(a.props['margin'], 4);
      expect(a.props['padding'], 16);
      expect(a.style, {'opacity': '0.5', 'height': '90px'});
      expect(doc.component('c1')!.root.style, {'opacity': '0.9'});
      expect(doc.component('c1')!.root.props['width'], 'fill');
    });

    test('定义不存在、没填 ref、不是实例：返回 null', () {
      final doc = docWith([instance('nope', id: 'a'), LcNode(id: 'b', type: 'component'), LcNode(id: 'c', type: 'text')], [titleCard()]);
      expect(expandInstance(doc, doc.find('a')!), isNull);
      expect(expandInstance(doc, doc.find('b')!), isNull);
      expect(expandInstance(doc, doc.find('c')!), isNull);
      expect(componentLabel(doc, doc.find('a')!), '组件');
    });

    test('循环（A 含 B、B 含 A；自己含自己）：不死循环，绕回来的那一层留成占位', () {
      final a = LcComponentDef(
        id: 'ca',
        name: 'A',
        root: LcNode(
          id: 'k1',
          type: 'column',
          children: [
            LcNode(id: 'k2', type: 'text', props: {'text': 'A 的字'}),
            instance('cb', id: 'k3'),
          ],
        ),
      );
      final b = LcComponentDef(
        id: 'cb',
        name: 'B',
        root: LcNode(
          id: 'k1',
          type: 'column',
          children: [instance('ca', id: 'k2')],
        ),
      );
      final self = LcComponentDef(
        id: 'cs',
        name: 'S',
        root: instance('cs', id: 'k1'),
      );
      final doc = docWith([instance('ca', id: 'x'), instance('cs', id: 'y')], [a, b, self]);
      final x = expandInstance(doc, doc.find('x')!)!;
      expect(x.children[0].props['text'], 'A 的字');
      final inner = x.children[1];
      expect(inner.type, 'column', reason: 'B 展开了');
      expect(inner.children.single.type, 'component', reason: 'B 里的 A 绕回来了：不展开');
      expect(inner.children.single.children, isEmpty);
      expect(expandInstance(doc, doc.find('y')!), isNull, reason: '最外层就是自己：整个展不开');
      expect(wouldCycle(doc, 'ca', 'cb'), isTrue);
      expect(wouldCycle(doc, 'ca', 'ca'), isTrue);
      expect(wouldCycle(doc, 'ca', 'cs'), isFalse);
      expect(wouldCycle(doc, 'ca', 'nope'), isFalse);
      // 导出也不死循环。
      expect(exportHtml(doc).html, contains('<!-- 这里是一个自定义组件'));
      expect(exportDart(doc), contains('SizedBox.shrink()'));
    });

    test('套得很深 / 成倍膨胀：有上限，不会卡死', () {
      // c0 里放两个 c1，c1 里放两个 c2 … 一共 40 层：照实展开是 2^40 个节点。
      final defs = [
        for (var i = 0; i < 40; i++)
          LcComponentDef(
            id: 'd$i',
            name: 'D$i',
            root: LcNode(
              id: 'k1',
              type: 'column',
              children: [
                instance('d${i + 1}', id: 'k2'),
                instance('d${i + 1}', id: 'k3'),
              ],
            ),
          ),
      ];
      final doc = docWith([instance('d0', id: 'x')], defs);
      final watch = Stopwatch()..start();
      final ex = expandInstance(doc, doc.find('x')!)!;
      expect(idsOf(ex).length, lessThanOrEqualTo(kComponentExpandBudget + 600));
      expect(watch.elapsedMilliseconds, lessThan(3000));
      var depth = 0;
      for (LcNode? n = ex; n != null && n.type != 'component'; n = n.children.isEmpty ? null : n.children.first) {
        depth++;
      }
      expect(depth, lessThanOrEqualTo(kComponentNestMax));
    });

    test('expandedTree：没有实例时就是原来的根（同一个对象）', () {
      final doc = starter();
      expect(identical(expandedTree(doc), doc.root), isTrue);
    });
  });

  group('props 与绑定', () {
    test('加属性：名字不合规矩、重名、类型不认识都拒绝；默认值按类型收', () {
      final doc = docWith([], [titleCard()]);
      expect(addComponentProp(doc, 'c1', '1abc', 'text').error, contains('英文字母'));
      expect(addComponentProp(doc, 'c1', '标题', 'text').error, contains('英文字母'));
      expect(addComponentProp(doc, 'c1', 'title', 'text').error, contains('已经有'));
      expect(addComponentProp(doc, 'c1', 'x', 'date').error, contains('类型'));
      expect(addComponentProp(doc, 'nope', 'x', 'text').error, contains('不存在'));
      expect(doc.component('c1')!.props.length, 5);
      expect(addComponentProp(doc, 'c1', 'price', 'number', 'abc').ok, isTrue);
      expect(doc.component('c1')!.prop('price')!.defaultValue, 0);
      expect(addComponentProp(doc, 'c1', 'c2', 'color', '#aabbcc').ok, isTrue);
      expect(doc.component('c1')!.prop('c2')!.defaultValue, '#AABBCC');
      expectRoundTrips(doc);
    });

    test('改名：定义里的绑定和所有实例传的值一起改（包括别的定义里的实例）', () {
      final host = LcComponentDef(
        id: 'c2',
        name: '外壳',
        root: LcNode(
          id: 'k1',
          type: 'column',
          children: [
            instance('c1', id: 'k2', values: {'title': '壳里的'}),
          ],
        ),
      );
      final doc = docWith(
        [
          instance('c1', id: 'a', values: {'title': '甲', 'count': 9}),
          instance('c1', id: 'b'),
        ],
        [titleCard(), host],
      );
      expect(renameComponentProp(doc, 'c1', 'title', 'count').error, contains('已经有'));
      expect(renameComponentProp(doc, 'c1', 'title', 'bad name').error, contains('英文字母'));
      expect(renameComponentProp(doc, 'c1', 'ghost', 'x').error, contains('找不到'));
      expect(renameComponentProp(doc, 'c1', 'title', 'heading').ok, isTrue);
      final def = doc.component('c1')!;
      expect(def.prop('title'), isNull);
      expect(def.root.children[0].bind, {'text': 'heading', 'color': 'tint'});
      expect(def.root.children[3].bind, {'placeholder': 'heading'});
      expect(doc.find('a')!.props['values'], {'heading': '甲', 'count': 9});
      expect(doc.find('b')!.props.containsKey('values'), isFalse);
      expect(doc.component('c2')!.root.children.single.props['values'], {'heading': '壳里的'});
      expect(expandInstance(doc, doc.find('a')!)!.children[0].props['text'], '甲');
      expectRoundTrips(doc);
    });

    test('删属性：绑定解开（回到控件自己的内容），实例传的值清掉', () {
      final doc = docWith(
        [
          instance('c1', id: 'a', values: {'title': '甲'}),
          instance('c1', id: 'b', values: {'title': '乙', 'count': 2}),
        ],
        [titleCard()],
      );
      expect(removeComponentProp(doc, 'c1', 'title').ok, isTrue);
      final def = doc.component('c1')!;
      expect(def.root.children[0].bind, {'color': 'tint'});
      expect(def.root.children[3].bind, isEmpty);
      expect(doc.find('a')!.props.containsKey('values'), isFalse, reason: '空了的 values 整个去掉');
      expect(doc.find('b')!.props['values'], {'count': 2});
      expect(expandInstance(doc, doc.find('a')!)!.children[0].props['text'], '原文');
      expect(removeComponentProp(doc, 'c1', 'title').error, contains('找不到'));
    });

    test('改类型：默认值换成新类型的；接不上的绑定解开；类型不对的实例值清掉', () {
      final doc = docWith(
        [
          instance('c1', id: 'a', values: {'tint': '#FF0000', 'count': 5}),
        ],
        [titleCard()],
      );
      expect(setComponentPropType(doc, 'c1', 'tint', 'text').ok, isTrue);
      final def = doc.component('c1')!;
      expect(def.prop('tint')!.defaultValue, '#112233', reason: '颜色本来就是字符串，改成文字可以沿用');
      expect(def.root.children[0].bind, {'text': 'title'}, reason: '文字颜色不能接文字类型的属性');
      expect(def.root.children[1].bind, {'text': 'count'});
      expect(doc.find('a')!.props['values'], {'tint': '#FF0000', 'count': 5});
      expect(setComponentPropType(doc, 'c1', 'count', 'bool').ok, isTrue);
      expect(def.prop('count')!.defaultValue, false);
      expect(def.root.children[1].bind, {'text': 'count'}, reason: '文字类的属性什么类型都能接');
      expect(doc.find('a')!.props['values'], {'tint': '#FF0000'});
      expect(expandInstance(doc, doc.find('a')!)!.children[1].props['text'], 'false');
      expect(setComponentPropType(doc, 'c1', 'count', 'date').error, contains('类型'));
    });

    test('改默认值：类型不对拒绝；改完所有没传值的实例跟着变', () {
      final doc = docWith(
        [
          instance('c1', id: 'a'),
          instance('c1', id: 'b', values: {'title': '乙'}),
        ],
        [titleCard()],
      );
      expect(setComponentPropDefault(doc, 'c1', 'count', 'x').error, contains('对不上'));
      expect(setComponentPropDefault(doc, 'c1', 'tint', 'blue').error, contains('对不上'));
      expect(setComponentPropDefault(doc, 'c1', 'title', '新默认').ok, isTrue);
      expect(expandInstance(doc, doc.find('a')!)!.children[0].props['text'], '新默认');
      expect(expandInstance(doc, doc.find('b')!)!.children[0].props['text'], '乙');
    });

    test('绑定 / 解绑：只能接这类控件有的属性；颜色只能接颜色', () {
      final doc = docWith([], [titleCard()]);
      expect(bindablePropsFor('text'), ['text', 'bg', 'color']);
      expect(bindablePropsFor('button'), ['text', 'bg', 'color']);
      expect(bindablePropsFor('image'), ['src']);
      expect(bindablePropsFor('input'), ['placeholder']);
      expect(bindablePropsFor('card'), ['bg']);
      expect(bindablePropsFor('divider'), isEmpty);
      expect(bindablePropsFor('component'), isEmpty);
      expect(bindablePropsFor('page'), isEmpty);
      expect(bindablePropsFor('nope'), isEmpty);
      expect(bindComponentProp(doc, 'c1', 'k4', 'text', 'title').error, contains('没有这一项'));
      expect(bindComponentProp(doc, 'c1', 'k2', 'bg', 'title').error, contains('颜色'));
      expect(bindComponentProp(doc, 'c1', 'k2', 'bg', 'ghost').error, contains('找不到'));
      expect(bindComponentProp(doc, 'c1', 'zz', 'text', 'title').error, contains('找不到'));
      expect(bindComponentProp(doc, 'c1', 'k2', 'bg', 'tint').ok, isTrue);
      expect(doc.component('c1')!.root.children[0].bind['bg'], 'tint');
      expect(bindComponentProp(doc, 'c1', 'k2', 'bg', null).ok, isTrue);
      expect(doc.component('c1')!.root.children[0].bind.containsKey('bg'), isFalse);
      expectRoundTrips(doc);
    });

    test('改实例的值 / 恢复默认：只动这一个实例', () {
      final doc = docWith([instance('c1', id: 'a'), instance('c1', id: 'b')], [titleCard()]);
      expect(setInstanceValue(doc, 'a', 'title', 5).error, contains('对不上'));
      expect(setInstanceValue(doc, 'a', 'ghost', 'x').error, contains('找不到'));
      expect(setInstanceValue(doc, 'a', 'title', '甲').ok, isTrue);
      expect(setInstanceValue(doc, 'a', 'tint', '#ff0000').ok, isTrue);
      expect(doc.find('a')!.props['values'], {'title': '甲', 'tint': '#FF0000'});
      final def = doc.component('c1')!;
      expect(instanceOverrides(def, doc.find('a')!, 'title'), isTrue);
      expect(instanceOverrides(def, doc.find('b')!, 'title'), isFalse);
      expect(expandInstance(doc, doc.find('b')!)!.children[0].props['text'], '默认标题');
      expect(setInstanceValue(doc, 'a', 'title', null).ok, isTrue);
      expect(setInstanceValue(doc, 'a', 'tint', null).ok, isTrue);
      expect(doc.find('a')!.props.containsKey('values'), isFalse);
      expectRoundTrips(doc);
    });

    test('组件改名：空、太长、和别的重名都拒绝', () {
      final doc = docWith([], [
        titleCard(),
        LcComponentDef(
          id: 'c2',
          name: '另一个',
          root: LcNode(id: 'k1', type: 'text'),
        ),
      ]);
      expect(renameComponent(doc, 'c1', ' ').error, contains('不能为空'));
      expect(renameComponent(doc, 'c1', '另一个').error, contains('已经有'));
      expect(renameComponent(doc, 'c1', '标题卡').ok, isTrue, reason: '改成自己现在的名字不算重名');
      expect(renameComponent(doc, 'c1', ' 新名字 ').ok, isTrue);
      expect(doc.component('c1')!.name, '新名字');
    });
  });

  group('插入 / 拆开 / 删除', () {
    test('插入实例：选中容器加进去；选中别的加在后面；没选加到末尾', () {
      final doc = starter()..components.add(titleCard());
      final inCard = insertInstance(doc, 'c1', nearId: 'n3');
      expect(doc.parentOf(inCard.nodeId!)!.id, 'n3');
      final after = insertInstance(doc, 'c1', nearId: 'n1');
      expect(doc.root.children[1].id, after.nodeId);
      final last = insertInstance(doc, 'c1');
      expect(doc.root.children.last.id, last.nodeId);
      expect(insertInstance(doc, 'nope').error, contains('不存在'));
      expect(componentUseCount(doc, 'c1'), 3);
      expect(idsOf(doc.root).toSet().length, idsOf(doc.root).length);
      expectRoundTrips(doc);
    });

    test('拆开：换成套好值的普通控件，最外层沿用 id，里面发新 id，不带绑定', () {
      final doc = starter()..components.add(titleCard());
      final id = insertInstance(doc, 'c1', nearId: 'n1').nodeId!;
      setInstanceValue(doc, id, 'title', '拆我');
      expect(detachInstance(doc, id).ok, isTrue);
      final n = doc.find(id)!;
      expect(n.type, 'card');
      expect(n.children[0].props['text'], '拆我');
      expect(n.children[1].props['text'], '3');
      void noBind(LcNode x) {
        expect(x.bind, isEmpty);
        x.children.forEach(noBind);
      }

      noBind(n);
      final ids = idsOf(doc.root);
      expect(ids.toSet().length, ids.length);
      expect(ids.every((i) => RegExp(r'^[A-Za-z0-9_]+$').hasMatch(i) && !i.contains('__')), isTrue);
      expect(componentUseCount(doc, 'c1'), 0);
      expect(doc.component('c1'), isNotNull, reason: '拆开不删定义');
      expect(detachInstance(doc, 'n1').error, contains('不是组件'));
      expectRoundTrips(doc);
    });

    test('拆开只拆一层：里面套的别的组件还是实例；定义没了拆不了', () {
      final outer = LcComponentDef(
        id: 'c2',
        name: '外壳',
        root: LcNode(
          id: 'k1',
          type: 'column',
          children: [
            instance('c1', id: 'k2', values: {'title': '里面'}),
          ],
        ),
      );
      final doc = docWith([instance('c2', id: 'a'), instance('gone', id: 'b')], [titleCard(), outer]);
      expect(detachInstance(doc, 'a').ok, isTrue);
      final inner = doc.find('a')!.children.single;
      expect(inner.type, 'component');
      expect(inner.props['ref'], 'c1');
      expect(inner.props['values'], {'title': '里面'});
      expect(detachInstance(doc, 'b').error, contains('不存在'));
      expect(doc.find('b')!.type, 'component');
    });

    test('删除：没人用直接删；有人用默认拒绝并给出次数', () {
      final doc = docWith(
        [instance('c1', id: 'a'), instance('c1', id: 'b')],
        [
          titleCard(),
          LcComponentDef(
            id: 'c2',
            name: '闲着',
            root: LcNode(id: 'k1', type: 'text'),
          ),
        ],
      );
      expect(deleteComponent(doc, 'c2').ok, isTrue);
      expect(doc.component('c2'), isNull);
      final r = deleteComponent(doc, 'c1');
      expect(r.ok, isFalse);
      expect(r.uses, 2);
      expect(r.error, contains('2 处'));
      expect(doc.component('c1'), isNotNull);
      expect(deleteComponent(doc, 'nope').error, contains('不存在'));
    });

    test('删除 · 连实例一起删：页面里的实例和挂在它们上面的逻辑一起没了', () {
      final doc = docWith(
        [
          LcNode(id: 'keep', type: 'text'),
          instance('c1', id: 'a'),
          LcNode(
            id: 'box',
            type: 'column',
            children: [instance('c1', id: 'b')],
          ),
        ],
        [titleCard()],
      );
      doc.logic.handlers.add(LcHandler(id: 'h1', event: 'click', target: 'a'));
      expect(deleteComponent(doc, 'c1', instances: LcDeleteInstances.remove).ok, isTrue);
      expect(doc.components, isEmpty);
      expect(idsOf(doc.root), ['root', 'keep', 'box']);
      expect(doc.logic.handlers, isEmpty);
      expectRoundTrips(doc);
    });

    test('删除 · 先拆开再删：实例变成普通控件留着，值照旧', () {
      final doc = docWith(
        [
          instance('c1', id: 'a', values: {'title': '留下'}),
          instance('c1', id: 'b'),
        ],
        [titleCard()],
      );
      expect(deleteComponent(doc, 'c1', instances: LcDeleteInstances.detach).ok, isTrue);
      expect(doc.components, isEmpty);
      expect(doc.find('a')!.type, 'card');
      expect(doc.find('a')!.children[0].props['text'], '留下');
      expect(doc.find('b')!.children[0].props['text'], '默认标题');
      final ids = idsOf(doc.root);
      expect(ids.toSet().length, ids.length);
      expectRoundTrips(doc);
    });

    test('删除时别的组件定义里也在用：里面的实例同样处理；最外层就是它的换成空容器', () {
      LcDocument make() => docWith(
        [instance('c2', id: 'a'), instance('c3', id: 'b')],
        [
          titleCard(),
          LcComponentDef(
            id: 'c2',
            name: '外壳',
            root: LcNode(
              id: 'k1',
              type: 'column',
              children: [
                LcNode(id: 'k2', type: 'text'),
                instance('c1', id: 'k3'),
              ],
            ),
          ),
          LcComponentDef(
            id: 'c3',
            name: '别名',
            root: instance('c1', id: 'k1'),
          ),
        ],
      );
      var doc = make();
      expect(componentUseCount(doc, 'c1'), 2);
      expect(deleteComponent(doc, 'c1', instances: LcDeleteInstances.remove).ok, isTrue);
      expect(idsOf(doc.component('c2')!.root), ['k1', 'k2']);
      expect(doc.component('c3')!.root.type, 'container');
      expect(expandInstance(doc, doc.find('b')!)!.type, 'container');
      expectRoundTrips(doc);

      doc = make();
      expect(deleteComponent(doc, 'c1', instances: LcDeleteInstances.detach).ok, isTrue);
      final c2 = doc.component('c2')!.root;
      expect(c2.children[1].type, 'card');
      expect(idsOf(c2).toSet().length, idsOf(c2).length);
      expect(idsOf(c2).every((i) => RegExp(r'^[A-Za-z0-9]+$').hasMatch(i)), isTrue, reason: '定义里的 id 只能是字母数字');
      expect(doc.component('c3')!.root.type, 'card');
      expectRoundTrips(doc);
    });
  });

  group('编辑组件内容（临时文档）', () {
    test('造临时文档 → 改 → 写回：id、名字、props 不动，实例跟着变', () {
      final doc = docWith(
        [
          instance('c1', id: 'a', values: {'title': '甲'}),
        ],
        [titleCard()],
      );
      final temp = componentEditingDocument(doc, 'c1')!;
      expect(temp.root.id, kComponentEditRootId);
      expect(idsOf(temp.root.children.single), ['k1', 'k2', 'k3', 'k4', 'k5']);
      final added = temp.newNode('text')..props['text'] = '新加的';
      temp.insert('k1', added);
      temp.find('k3')!.style['margin-top'] = '8px';
      temp.remove('k4');
      expect(applyComponentEditing(doc, 'c1', temp).ok, isTrue);
      final def = doc.component('c1')!;
      expect(def.id, 'c1');
      expect(def.name, '标题卡');
      expect(def.props.length, 5);
      expect(def.root.children.map((n) => n.type), ['text', 'button', 'input', 'text']);
      expect(def.root.children[0].bind, {'text': 'title', 'color': 'tint'}, reason: '绑定留着');
      final ex = expandInstance(doc, doc.find('a')!)!;
      expect(ex.children[0].props['text'], '甲');
      expect(ex.children[3].props['text'], '新加的');
      expect(ex.children[1].style['margin-top'], '8px');
      // 临时文档和定义互不相干：再改临时文档不影响定义。
      temp.find('k2')!.props['text'] = '又改了';
      expect(def.root.children[0].props['text'], '原文');
      expectRoundTrips(doc);
    });

    test('最外层必须正好一个；不能把会绕回自己的组件放进来；定义没了', () {
      final host = LcComponentDef(
        id: 'c2',
        name: '外壳',
        root: LcNode(
          id: 'k1',
          type: 'column',
          children: [instance('c1', id: 'k2')],
        ),
      );
      final doc = docWith([], [titleCard(), host]);
      final temp = componentEditingDocument(doc, 'c1')!;
      expect(temp.components.map((c) => c.id), isEmpty, reason: 'c2 里用到了 c1，放进 c1 会循环：临时文档里不带它');
      final snapshot = doc.encode();
      temp.insert(kComponentEditRootId, temp.newNode('text'));
      expect(applyComponentEditing(doc, 'c1', temp).error, contains('只能有一个'));
      temp.root.children.removeLast();
      temp.insert('k1', temp.newNode('component')..props['ref'] = 'c2');
      expect(applyComponentEditing(doc, 'c1', temp).error, contains('不能放它自己'));
      temp.root.children.clear();
      expect(applyComponentEditing(doc, 'c1', temp).error, contains('只能有一个'));
      expect(doc.encode(), snapshot, reason: '失败时什么都不改');
      expect(componentEditingDocument(doc, 'nope'), isNull);
      expect(applyComponentEditing(doc, 'nope', temp).error, contains('不存在'));
      expect(componentEditingDocument(doc, 'c2')!.components.map((c) => c.id), ['c1']);
    });
  });

  group('旧文档与怪数据', () {
    test('没有 components 字段的旧文档：照常读、照常导出、组件操作都不抛', () {
      final doc = LcDocument.parse('{"title":"旧","root":{"id":"root","type":"page","children":[{"id":"n1","type":"text","props":{"text":"你好"}}]}}');
      expect(doc.components, isEmpty);
      expect(componentUseCount(doc, 'c1'), 0);
      expect(deleteComponent(doc, 'c1').ok, isFalse);
      expect(identical(expandedTree(doc), doc.root), isTrue);
      expect(saveAsComponent(doc, 'n1', '字').ok, isTrue);
      expect(jsonDecode(doc.encode())['components'], hasLength(1));
    });

    test('文件里的怪组件数据：读得进来，展开 / 导出 / 各种操作都不抛异常', () {
      final doc = LcDocument.parse(
        jsonEncode({
          'title': 't',
          'root': {
            'id': 'root',
            'type': 'page',
            'children': [
              {
                'id': 'a',
                'type': 'component',
                'props': {
                  'ref': 'c1',
                  'values': {'title': 12, 'extra': true, 'n': 'x'},
                },
              },
              {
                'id': 'b',
                'type': 'component',
                'props': {'ref': 'has space', 'values': 'oops'},
              },
              {'id': 'c', 'type': 'component'},
            ],
          },
          'components': [
            {
              'id': 'c1',
              'name': '怪',
              'props': [
                {'name': 'title', 'type': 'text', 'default': 9},
                {'name': 'n', 'type': 'number', 'default': 'NaN'},
                {'name': 'title', 'type': 'bool'},
                {'name': '9bad'},
                'junk',
              ],
              'root': {
                'id': 'x',
                'type': 'column',
                'children': [
                  {
                    'id': 'x',
                    'type': 'text',
                    'props': {'text': 'T'},
                    'bind': {'text': 'ghost', 'color': 'title', 'bg': 5, 'fontSize': 'n'},
                  },
                  {
                    'id': 'y',
                    'type': 'image',
                    'bind': {'text': 'title', 'src': 'n'},
                  },
                ],
              },
            },
            {'id': 'c2', 'name': '坏的', 'root': 'nope'},
            42,
          ],
        }),
      );
      expect(doc.components.length, 1);
      final a = expandInstance(doc, doc.find('a')!)!;
      expect(a.children[0].props['text'], 'T', reason: '接到不存在的属性上：当作没接');
      expect(a.children[0].props.containsKey('color'), isFalse, reason: '文字属性的值不是颜色：不套');
      expect(a.children[1].props['src'], '0', reason: '数字接到图片地址上：显示成文字');
      expect(expandInstance(doc, doc.find('b')!), isNull);
      expect(expandInstance(doc, doc.find('c')!), isNull);
      expect(() => exportHtml(doc), returnsNormally);
      expect(() => exportDart(doc), returnsNormally);
      for (final id in ['a', 'b', 'c']) {
        expect(() => detachInstance(doc, id), returnsNormally);
        expect(() => setInstanceValue(doc, id, 'title', 'x'), returnsNormally);
      }
      expect(() => deleteComponent(doc, 'c1', instances: LcDeleteInstances.detach), returnsNormally);
      expectRoundTrips(doc);
    });
  });

  group('导出', () {
    LcDocument sample() => docWith(
      [
        LcNode(id: 'n1', type: 'text', props: {'text': '页面标题'}),
        instance('c1', id: 'n2', values: {'title': '甲', 'pic': 'https://x.test/a.png?a=1&b=2'}),
        instance('c1', id: 'n3', extra: {'margin': 4}, style: {'opacity': '0.5'}),
      ],
      [titleCard()],
    );

    test('HTML / CSS：实例输出展开后的子树，class 和规则用展开后的 id', () {
      final out = exportHtml(sample());
      expect(
        out.html,
        contains('''
    <div class="lc-card n-n2">
      <p class="lc-text n-n2__k2">甲</p>
      <button type="button" class="lc-button n-n2__k3">3</button>
      <img class="lc-image n-n2__k4" src="https://x.test/a.png?a=1&amp;b=2" alt="">
      <input class="lc-input n-n2__k5" placeholder="甲">
    </div>
    <div class="lc-card n-n3">
      <p class="lc-text n-n3__k2">默认标题</p>
      <button type="button" class="lc-button n-n3__k3">3</button>
      <div class="lc-image n-n3__k4" role="img" aria-label="图片占位"></div>
      <input class="lc-input n-n3__k5" placeholder="默认标题">
    </div>
'''),
      );
      expect(out.html, isNot(contains('lc-component')));
      expect(out.css, contains('.n-n2 { align-self: stretch; padding: 16px; background: #ffffff; opacity: 0.9; }'));
      expect(out.css, contains('.n-n3 { align-self: stretch; padding: 16px; margin: 4px; background: #ffffff; opacity: 0.5; }'));
      expect(out.css, contains('.n-n2__k2 { color: #112233; }'));
      expect(out.css, contains('.n-n3__k3 { background: #112233; }'));
      expect(out.css, contains('.n-n2__k4 { height: 80px; }'));
      expect('{'.allMatches(out.css).length, '}'.allMatches(out.css).length);
    });

    test('没有任何 component 的页面：和不经过展开时逐字节相同', () {
      final doc = starter();
      final withDefs = LcDocument.parse(doc.encode())..components.add(titleCard());
      final a = exportHtml(doc);
      final b = exportHtml(withDefs);
      // 页面里没用到的定义不影响导出；和改之前的输出比对（固定快照的开头几行 + 全文一致）。
      expect(b.html, a.html);
      expect(b.css, a.css);
      expect(a.html, contains('<main class="lc-page n-root">\n    <p class="lc-text n-n1">小站</p>'));
      expect(a.html, isNot(contains('<!--')));
      expect(exportDart(withDefs), exportDart(doc));
    });

    test('绑定值里的 < " & </script> 被转义', () {
      final doc = docWith(
        [
          instance('c1', id: 'n1', values: {'title': '<b>"x"</b></script><script>alert(1)</script>&', 'pic': 'a"b<c>.png'}),
        ],
        [titleCard()],
      );
      final html = exportHtml(doc).html;
      expect(html, contains('<p class="lc-text n-n1__k2">&lt;b&gt;"x"&lt;/b&gt;&lt;/script&gt;&lt;script&gt;alert(1)&lt;/script&gt;&amp;</p>'));
      expect(html, contains('placeholder="&lt;b&gt;&quot;x&quot;&lt;/b&gt;&lt;/script&gt;&lt;script&gt;alert(1)&lt;/script&gt;&amp;"'));
      expect(html, contains('src="a&quot;b&lt;c&gt;.png"'));
      expect(html, isNot(contains('<script>alert')));
      expect(RegExp('</script>').allMatches(html).length, 0);
    });

    test('定义不存在：输出一行注释 + 空盒子占位，样式规则还在', () {
      final doc = docWith([
        instance('gone', id: 'n1', extra: {'margin': 4}),
      ], []);
      final out = exportHtml(doc);
      expect(out.html, contains('    <!-- 这里是一个自定义组件，内容没有导出：找不到它的定义，或者它绕回来用到了自己 -->\n    <div class="lc-component n-n1">\n    </div>'));
      expect(out.css, contains('.n-n1 { margin: 4px; }'));
    });

    test('挂在实例上的点击逻辑：导出后还能找到那个元素（最外层沿用实例的 id）', () {
      final doc = sample();
      doc.logic.handlers.add(LcHandler(id: 'h1', event: 'click', target: 'n2'));
      final out = exportHtml(doc);
      expect(out.js, contains('n2'));
      expect(out.html, contains('class="lc-card n-n2"'));
    });

    test('Flutter 导出：实例按展开后的内容生成', () {
      final code = exportDart(sample());
      expect(code, contains("'甲'"));
      expect(code, contains("'默认标题'"));
      expect(code, contains("Image.network('https://x.test/a.png?a=1&b=2'"));
      expect(code, contains('const Color(0xFF112233)'));
      expect('('.allMatches(code).length, ')'.allMatches(code).length);
    });
  });
}
