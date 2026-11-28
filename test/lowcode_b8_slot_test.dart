// 第四轮 B8：插槽内容拿到组件里的数据（格式见 lib/lowcode/slot_gives.dart、E 分册 §10.16）。
// 做到的：格式（定义里插槽占位上的 gives）、展开时改写、检查不误报、普通网页真编译真跑、Flutter 导出的代码里读得到。
// 没做的：编辑器里设 gives 的界面、绑定挑选单里列出这些名字、Vue / React 导出、画布上内容跟着变、事件积木里读这些名字。
@Tags(['external'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/lowcode/bind_check.dart';
import 'package:lopicode/lowcode/bind_model.dart';
import 'package:lopicode/lowcode/component_expand.dart';
import 'package:lopicode/lowcode/export_dart.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/slot_gives.dart';

import 'support/b8_slot_sample.dart';
import 'support/bind_export_files.dart';
import 'support/comp_samples.dart';
import 'support/dev_tools.dart';

LcNode _slot(LcDocument doc, String name) {
  LcNode? hit;
  void walk(LcNode n) {
    if (n.type == 'slot' && (n.strProp('name') ?? 'default') == name) hit = n;
    n.children.forEach(walk);
  }

  walk(doc.component('lst')!.root);
  return hit!;
}

void main() {
  group('格式', () {
    test('读：名字 → 式子；名字不合规矩、式子读不懂的不算；最多 8 样', () {
      final doc = b8SlotDoc();
      expect(lcSlotGives(_slot(doc, 'default')).keys.toList(), ['thing', 'no', 'head']);
      expect(lcSlotGives(_slot(doc, 'foot')), {
        'chosen': {'e': 'var', 'name': 'picked'},
      });
      final s = _slot(doc, 'foot');
      s.more[kLcGives] = {'好名字': cFrom('picked'), '1x': cFrom('picked'), 'ok': 3, 'fine': cFrom('picked')};
      expect(lcSlotGives(s).keys.toList(), ['fine']);
      expect(lcSlotGives(doc.root), isEmpty, reason: '不是插槽占位');
    });

    test('写：设、改、去掉；名字不合规矩 / 不是占位 / 满了不改；去光了字段也没了；存盘再读还在', () {
      final doc = b8SlotDoc();
      final s = _slot(doc, 'foot');
      expect(lcSetSlotGive(s, 'more', lcSrcVar('title')), isTrue);
      expect(lcSetSlotGive(s, '9bad', lcSrcVar('title')), isFalse);
      expect(lcSetSlotGive(doc.root, 'x', lcSrcVar('title')), isFalse);
      expect(lcSlotGives(_slot(LcDocument.parse(doc.encode()), 'foot')).keys.toSet(), {'chosen', 'more'});
      for (var i = 0; i < 6; i++) {
        expect(lcSetSlotGive(s, 'k$i', lcSrcVar('title')), isTrue);
      }
      expect(lcSetSlotGive(s, 'k9', lcSrcVar('title')), isFalse, reason: '最多 $kLcGivesMax 样');
      for (final k in lcSlotGives(s).keys.toList()) {
        expect(lcSetSlotGive(s, k, null), isTrue);
      }
      expect(s.more.containsKey(kLcGives), isFalse);
      expect(lcSetSlotGive(s, 'chosen', null), isFalse);
    });

    test('页面上哪个控件读得到哪些名字：在哪个插槽里就是哪个插槽给的；不在插槽里没有', () {
      final doc = b8SlotDoc();
      expect(lcGivenNamesAt(doc, 'fill'), {'thing', 'no', 'head'});
      expect(lcGivenNamesAt(doc, 'tail'), {'chosen'});
      expect(lcGivenNamesAt(doc, 'rename'), isEmpty);
    });

    test('检查：读插槽给的名字不报“没有这个状态”；读一个谁也没给的名字照报', () {
      final doc = b8SlotDoc();
      // 别的说明（比如“定义里有绑定的组件导出成 Vue / React 时不起作用”）照旧，这里只看有没有误报“没有这个状态”。
      expect(lcCheckBindings(doc).map((i) => i.message).join('\n'), isNot(contains('没有这个状态')));
      lcSetData(doc.find('tail')!, 'text', lcSrcVar('thing')); // thing 是另一个插槽给的
      expect(lcCheckBindings(doc).map((i) => i.message).join(), contains('用到了 thing，但没有这个状态'));
    });
  });

  group('展开', () {
    test('内容里的名字换成插槽给的式子：这一项 / 第几项留着那一层“重复”的名字；标题换成实例给的值；页面状态照旧读；组件状态换成这个实例那一份', () {
      final doc = b8SlotDoc();
      final ex = LcExpander(doc);
      final root = ex.outer(doc.root);
      LcNode? find(LcNode n, String id) => n.id == id ? n : n.children.map((c) => find(c, id)).whereType<LcNode>().firstOrNull;
      final fill = find(root, 'fill')!;
      expect(lcDataExpr(fill, 'text'), {
        'e': 'join',
        'items': [
          {'e': 'var', 'name': 'shop'},
          {'e': 'text', 'v': '·'},
          {'e': 'text', 'v': '清单甲'},
          {'e': 'text', 'v': '第'},
          {
            'e': 'bin',
            'op': '+',
            'l': {'e': 'var', 'name': 'i'},
            'r': {'e': 'num', 'v': 1},
          },
          {'e': 'text', 'v': '个：'},
          {'e': 'var', 'name': 'it'},
        ],
      });
      expect(lcDataExpr(find(root, 'tail')!, 'text')!['items'][1], {'e': 'var', 'name': 'a__picked'});
      // 她的页面文件一个字没动
      expect(lcDataExpr(doc.find('fill')!, 'text')!['items'][2], {'e': 'var', 'name': 'head'});
      // 没填内容的那个实例：用默认内容
      expect(find(root, 'b__dflt')?.props['text'], '（没填）');
    });

    test('内容自己这边“重复”带出来的同名的：指的是它自己的，不换', () {
      final doc = b8SlotDoc();
      final fill = doc.find('fill')!;
      fill.more['repeat'] = {'list': cFrom('shopList'), 'item': 'thing', 'index': 'k'};
      final out = lcWithGiven(fill, {
        'thing': {'e': 'var', 'name': 'it'},
        'head': {'e': 'text', 'v': '甲'},
      });
      final items = lcDataExpr(out, 'text')!['items'] as List;
      expect(items.last, {'e': 'var', 'name': 'thing'});
      expect(items[2], {'e': 'text', 'v': '甲'});
    });

    test('内容里用不到这些名字：原样交回，不拷', () {
      final doc = b8SlotDoc();
      final n = doc.find('rename')!;
      expect(identical(lcWithGiven(n, {'head': cText('x').cast<String, dynamic>()}), n), isTrue);
    });
  });

  test('没用这个功能的页面：导出一个字不变（展开走的还是原来那条路）', () {
    for (final defs in [
      [productCardDef()],
      [loginFormDef()],
      [tagBarDef()],
    ]) {
      final doc = compUserDoc(defs);
      expect(doc.encode(), isNot(contains('"gives"')));
    }
  });

  test('Flutter 导出：内容那行字读的是“这一项”“第几项”和页面状态', () {
    final dart = exportDart(b8SlotDoc(), className: 'B8SlotPage');
    expect(dart, contains('s_shop'));
    expect(dart, contains("'个：'"));
    expect(dart, isNot(contains('s_head')));
    expect(dart, isNot(contains('s_thing')));
  });

  group('普通网页真编译真跑', () {
    test('真编译 0 错误 0 警告', () async {
      final r = await compileExport('compile_html.mjs', exportFilesOf(b8SlotDoc(), 'html'), 'index.html');
      expect(r.errors, isEmpty, reason: r.raw);
      expect(r.warnings, isEmpty, reason: r.raw);
      expect(r.ok, isTrue);
    }, skip: skipWithoutDom);

    test('真跑：每一行写着“页面状态·标题 第几个：这一项”；改了页面状态跟着变', () async {
      final steps = b8SlotSteps();
      final files = exportFilesOf(b8SlotDoc(), 'html');
      final r = await runInDom('html', files, 'index.html', steps);
      expect(r.errors, isEmpty, reason: '${files['index.html']}\n${files['logic.js']}');
      expect(r.warnings, isEmpty);
      expect(r.done, steps.length);
      expect(r.ok, isTrue);
    }, skip: skipWithoutDom);
  });
}
