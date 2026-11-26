// 第 3 期第 2 段：11 个新组件的登记、属性的规矩（尤其对象数组）、插槽的读法和改法。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/model_v3_components.dart';
import 'package:lopicode/lowcode/slots.dart';

LcDocument _doc(List<Object?> children, {int version = 3}) => LcDocument.parse(
  jsonEncode({
    'version': version,
    'title': 't',
    'root': {'id': 'root', 'type': 'page', 'children': children},
  }),
);

Map<String, Object?> _n(String id, String type, [Map<String, Object?> props = const {}, List<Object?> children = const [], String? slot]) => {
  'id': id,
  'type': type,
  'props': props,
  'children': children,
  'slot': ?slot,
};

void main() {
  group('登记', () {
    test('11 个新组件都登记了、都在组件盒里；带插槽的四个算容器', () {
      expect(lcV3PaletteTypes, ['icon', 'textarea', 'switch', 'checkbox', 'radio', 'select', 'listItem', 'appBar', 'bottomNav', 'tabs', 'dialog']);
      for (final t in lcV3PaletteTypes) {
        expect(lcSpecs[t], isNotNull, reason: t);
        expect(lcPaletteTypes, contains(t));
      }
      expect(
        [
          for (final t in lcV3PaletteTypes)
            if (lcSpecs[t]!.isContainer) t,
        ],
        ['listItem', 'appBar', 'tabs', 'dialog'],
      );
      expect(
        [
          for (final t in lcV3PaletteTypes)
            if (lcSpecs[t]!.slots != null) t,
        ],
        ['listItem', 'appBar', 'tabs', 'dialog'],
      );
    });

    test('新建出来的每个新组件：默认属性自己都合规矩（存了再读一个不少）', () {
      final doc = _doc(const []);
      for (final t in lcV3PaletteTypes) {
        final n = doc.newNode(t);
        doc.insert('root', n);
        expect(n.props, isNotEmpty, reason: t);
      }
      final again = LcDocument.parse(doc.encode());
      for (final n in doc.root.children) {
        expect(again.find(n.id)!.props, n.props, reason: n.type);
        expect(again.find(n.id)!.isUnknown, isFalse);
      }
    });

    test('第 2 版的文件里没有这些组件的属性：键原样留着但不生效', () {
      final doc = _doc([
        _n('a', 'text', {'checked': true, 'text': 'x'}),
      ], version: 2);
      expect(doc.find('a')!.props.containsKey('checked'), isFalse);
      expect(jsonDecode(doc.encode()).toString(), contains('checked'));
    });
  });

  group('属性的规矩', () {
    LcNode read(String type, Map<String, Object?> props) => _doc([_n('x', type, props)]).find('x')!;

    test('键只在自己那种组件上算数：开关的 checked 写在文字上不生效、原样留着', () {
      final doc = _doc([
        _n('t', 'text', {'text': 'a', 'checked': true, 'rows': 3}),
        _n('s', 'switch', {'checked': true, 'rows': 3}),
      ]);
      expect(doc.find('t')!.props, {'text': 'a'});
      expect(doc.find('s')!.props, {'checked': true});
      final out = jsonDecode(doc.encode()) as Map<String, dynamic>;
      expect((out['root'] as Map)['children'][0]['props'], {'text': 'a', 'checked': true, 'rows': 3});
    });

    test('选项（options）：整串都对才算数——空的、太多、值重复、值不是字符串、名字不是字符串都不行', () {
      List<Object?> opts(int n) => [
        for (var i = 0; i < n; i++) {'value': 'v$i'},
      ];
      expect(read('radio', {'options': opts(2)}).props['options'], hasLength(2));
      expect(read('select', {'options': opts(kLcMaxOptions)}).props['options'], hasLength(kLcMaxOptions));
      expect(read('radio', {'options': <Object?>[]}).props.containsKey('options'), isFalse);
      expect(read('radio', {'options': opts(kLcMaxOptions + 1)}).props.containsKey('options'), isFalse);
      expect(
        read('radio', {
          'options': [
            {'value': 'a'},
            {'value': 'a'},
          ],
        }).props.containsKey('options'),
        isFalse,
      );
      expect(
        read('radio', {
          'options': [
            {'value': 1},
          ],
        }).props.containsKey('options'),
        isFalse,
      );
      expect(
        read('radio', {
          'options': [
            {'value': ''},
          ],
        }).props.containsKey('options'),
        isFalse,
      );
      expect(
        read('radio', {
          'options': [
            {'value': 'a', 'label': 3},
          ],
        }).props.containsKey('options'),
        isFalse,
      );
      expect(
        read('radio', {
          'options': ['a', 'b'],
        }).props.containsKey('options'),
        isFalse,
      );
      // 对象里别的键留着
      expect(
        read('radio', {
          'options': [
            {'value': 'a', 'extra': 1},
          ],
        }).props['options'],
        [
          {'value': 'a', 'extra': 1},
        ],
      );
      // 不合规矩的整串原样留在文件里
      final doc = _doc([
        _n('x', 'radio', {
          'options': ['a'],
        }),
      ]);
      expect(jsonDecode(doc.encode()).toString(), contains('options: [a]'));
    });

    test('页签（tabs）：1–8 个，id 是字母数字下划线且不重复', () {
      expect(
        read('tabs', {
          'tabs': [
            {'id': 'a', 'label': '甲'},
            {'id': 'b'},
          ],
        }).props['tabs'],
        hasLength(2),
      );
      expect(
        read('tabs', {
          'tabs': [
            {'id': 'a'},
            {'id': 'a'},
          ],
        }).props.containsKey('tabs'),
        isFalse,
      );
      expect(
        read('tabs', {
          'tabs': [
            {'id': 'a b'},
          ],
        }).props.containsKey('tabs'),
        isFalse,
      );
      expect(
        read('tabs', {
          'tabs': [
            for (var i = 0; i <= kLcMaxTabs; i++) {'id': 't$i'},
          ],
        }).props.containsKey('tabs'),
        isFalse,
      );
      expect(read('tabs', {'current': 'a'}).props['current'], 'a');
      expect(read('tabs', {'current': 1}).props.containsKey('current'), isFalse);
    });

    test('导航项（items）：底部导航栏是对象数组（1–5 项，图标名要合写法）；列表的 items 还是文字数组', () {
      expect(
        read('bottomNav', {
          'items': [
            {'icon': 'home', 'label': '首页', 'page': 'p2'},
          ],
        }).props['items'],
        [
          {'icon': 'home', 'label': '首页', 'page': 'p2'},
        ],
      );
      expect(
        read('bottomNav', {
          'items': [
            {'icon': 'No Such'},
          ],
        }).props.containsKey('items'),
        isFalse,
      );
      expect(
        read('bottomNav', {
          'items': ['a'],
        }).props.containsKey('items'),
        isFalse,
      );
      expect(
        read('bottomNav', {
          'items': [
            for (var i = 0; i <= kLcMaxNavItems; i++) {'icon': 'home'},
          ],
        }).props.containsKey('items'),
        isFalse,
      );
      expect(read('bottomNav', {'current': 2}).props['current'], 2);
      expect(read('bottomNav', {'current': 'a'}).props.containsKey('current'), isFalse);
      expect(
        read('list', {
          'items': ['a', 'b'],
        }).props['items'],
        ['a', 'b'],
      );
    });

    test('样子（variant）：只认这种组件自己的那几个；没写或写错按第一个算', () {
      expect(lcVariantOf(read('radio', {'variant': 'button'})), 'button');
      expect(lcVariantOf(read('radio', {'variant': 'pill'})), 'dot');
      expect(lcVariantOf(read('tabs', {})), 'underline');
      expect(lcVariantOf(read('dialog', {'variant': 'confirm'})), 'confirm');
      expect(lcVariantOf(read('text', {'variant': 'x'})), '');
    });
  });

  group('插槽', () {
    LcDocument sample() => _doc([
      _n(
        'li',
        'listItem',
        {'title': 'a'},
        [_n('l1', 'text', {}, [], 'left'), _n('r1', 'text', {}, [], 'right'), _n('lost', 'text'), _n('bad', 'text', {}, [], 'nowhere'), _n('l2', 'text', {}, [], 'left')],
      ),
      _n(
        'tb',
        'tabs',
        {
          'tabs': [
            {'id': 'a', 'label': '甲'},
            {'id': 'b'},
          ],
          'current': 'b',
        },
        [_n('ta', 'text', {}, [], 'a'), _n('tb1', 'text', {}, [], 'b'), _n('tlost', 'text')],
      ),
      _n('box', 'container'),
      _n('dlg', 'dialog'),
    ]);

    test('有哪些插槽；标签页的插槽跟着页签走', () {
      final doc = sample();
      expect([for (final s in lcSlotsOf(doc.find('li')!)) '${s.name}:${s.label}'], ['left:左侧', 'right:右侧']);
      expect([for (final s in lcSlotsOf(doc.find('tb')!)) '${s.name}:${s.label}'], ['a:甲', 'b:b']);
      expect([for (final s in lcSlotsOf(doc.find('dlg')!)) s.name], ['content', 'footer']);
      expect(lcSlotsOf(doc.find('box')!), isEmpty);
      expect(lcCurrentTab(doc.find('tb')!), 'b');
    });

    test('没写插槽、写错插槽的子组件算在兜底插槽里；文件里不替它改', () {
      final doc = sample();
      final li = doc.find('li')!;
      expect([for (final c in lcSlotChildren(li, 'left')) c.id], ['l1', 'l2']);
      expect([for (final c in lcSlotChildren(li, 'right')) c.id], ['r1', 'lost', 'bad']);
      expect([for (final c in lcSlotChildren(doc.find('tb')!, 'a')) c.id], ['ta', 'tlost']);
      expect(doc.find('bad')!.slot, 'nowhere');
      expect(jsonDecode(doc.encode()).toString(), contains('slot: nowhere'));
    });

    test('放进插槽：新节点写上 slot，位置按插槽里的第几个算', () {
      final doc = sample();
      final n = doc.newNode('icon');
      expect(lcInsertAt(doc, lcSlotBoxId('li', 'left'), n, 1), isTrue);
      expect(n.slot, 'left');
      expect([for (final c in lcSlotChildren(doc.find('li')!, 'left')) c.id], ['l1', n.id, 'l2']);
      final m = doc.newNode('icon');
      expect(lcInsertAt(doc, lcSlotBoxId('li', 'left'), m, 99), isTrue);
      expect(lcSlotChildren(doc.find('li')!, 'left').last.id, m.id);
      // 空的插槽
      final d = doc.newNode('button');
      expect(lcInsertAt(doc, lcSlotBoxId('dlg', 'footer'), d, 0), isTrue);
      expect(d.slot, 'footer');
      // 不存在的插槽放不进去
      expect(lcInsertAt(doc, lcSlotBoxId('li', 'nope'), doc.newNode('text'), 0), isFalse);
      expect(lcInsertAt(doc, lcSlotBoxId('box', 'left'), doc.newNode('text'), 0), isFalse);
    });

    test('挪动：同一个插槽里换位置、换到别的插槽、挪出去（slot 去掉）、从外面挪进来', () {
      final doc = sample();
      final li = doc.find('li')!;
      // l1 挪到 left 的最后（位置按挪之前的顺序算：2＝排在 l2 后面）
      expect(lcMoveTo(doc, 'l1', lcSlotBoxId('li', 'left'), 2), isTrue);
      expect([for (final c in lcSlotChildren(li, 'left')) c.id], ['l2', 'l1']);
      // r1 换到 left 的最前
      expect(lcMoveTo(doc, 'r1', lcSlotBoxId('li', 'left'), 0), isTrue);
      expect([for (final c in lcSlotChildren(li, 'left')) c.id], ['r1', 'l2', 'l1']);
      expect(doc.find('r1')!.slot, 'left');
      // 挪到普通容器里：slot 去掉
      expect(lcMoveTo(doc, 'r1', 'box', 0), isTrue);
      expect(doc.find('r1')!.slot, isNull);
      expect(doc.parentOf('r1')!.id, 'box');
      // 从外面挪进页签
      expect(lcMoveTo(doc, 'r1', lcSlotBoxId('tb', 'b'), 0), isTrue);
      expect(doc.find('r1')!.slot, 'b');
      expect([for (final c in lcSlotChildren(doc.find('tb')!, 'b')) c.id], ['r1', 'tb1']);
      // 不能挪进自己里面
      expect(lcMoveTo(doc, 'li', lcSlotBoxId('li', 'left'), 0), isFalse);
    });

    test('普通的放进去（不指明插槽）：落进兜底插槽；放进普通容器的新节点没有 slot', () {
      final doc = sample();
      final n = doc.newNode('text');
      expect(lcInsertAt(doc, 'dlg', n), isTrue);
      expect(lcSlotOfChild(doc.find('dlg')!, n), 'content');
      final m = doc.newNode('text')..slot = 'left';
      expect(lcInsertAt(doc, 'box', m), isTrue);
      expect(m.slot, isNull);
    });

    test('删页签：里面的子组件一起删；当前页签被删了换成第一个；只剩一个不让删', () {
      final doc = sample();
      final tb = doc.find('tb')!;
      expect(lcRemoveTab(tb, 'b'), 1);
      expect(doc.find('tb1'), isNull);
      expect(tb.props['current'], 'a');
      expect(lcRemoveTab(tb, 'a'), -1);
      expect(lcRemoveTab(tb, 'zzz'), -1);
      expect(lcNewTabId(tb), 't1');
    });

    test('落点 id 的拆法', () {
      expect(lcSplitSlotId('n3'), ('n3', null));
      expect(lcSplitSlotId('n3#left'), ('n3', 'left'));
    });
  });
}
