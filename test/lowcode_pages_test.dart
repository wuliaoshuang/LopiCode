// 第 4 期·多页面：模型、存盘格式、“去页面”积木、自定义组件属于项目（不带界面；界面在 lowcode_pages_ui_test.dart）。
// 设计见 docs/blocks-v5-parts/E-editor-components.md §10.6。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/lowcode/component_ops.dart';
import 'package:lopicode/lowcode/component_slots.dart';
import 'package:lopicode/lowcode/logic_blocks.dart';
import 'package:lopicode/lowcode/logic_text.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/quick_actions.dart';
import 'package:lopicode/lowcode/slots.dart';

import 'support/pages_sample.dart';
import 'support/sample_doc.dart';
import 'support/slot_sample.dart';
import 'support/v3_components_sample.dart';
import 'support/v3_sample.dart';

Map<String, dynamic> json(String s) => jsonDecode(s) as Map<String, dynamic>;

void main() {
  group('旧的单页面工程', () {
    final olds = <String, String>{
      for (final f in ['page-v1.lc.json', 'page-v2.lc.json', 'page-v1.saved-v3.lc.json', 'page-v2.saved-v3.lc.json']) f: File('test/fixtures/lowcode/$f').readAsStringSync(),
      '各种组件的样本': sample().encode(),
      '第 3 版新属性的样本': v3Sample().encode(),
      '带底部导航的首页': v3HomePage().encode(),
      '带插槽的商品卡片': slotCardPage().encode(),
      '新建页面的默认内容': LcDocument.starter('我的页面').encode(),
    };

    test('打开就是一页；存出来没有 id、没有 pages，字段的先后也没变', () {
      for (final e in olds.entries) {
        final doc = LcDocument.parse(e.value);
        expect(doc.pages.length, 1, reason: e.key);
        expect(doc.page.id, kLcFirstPageId, reason: e.key);
        expect(doc.isMultiPage, isFalse);
        final out = json(doc.encode());
        expect(out.containsKey('id'), isFalse, reason: e.key);
        expect(out.containsKey('pages'), isFalse, reason: e.key);
        expect(out.keys.take(3).toList(), ['version', 'title', 'root'], reason: e.key);
      }
    });

    test('已经是第 3 版的文件：打开再存逐字节一样（多页面没有往里多写一个字）', () {
      for (final name in ['page-v1.saved-v3.lc.json', 'page-v2.saved-v3.lc.json']) {
        expect(LcDocument.parse(olds[name]!).encode(), olds[name]!.trimRight(), reason: name);
      }
      for (final e in olds.entries) {
        final once = LcDocument.parse(e.value).encode();
        expect(LcDocument.parse(once).encode(), once, reason: e.key);
      }
    });

    test('加一页再删掉：存出来和没加过逐字节一样（标题、组件树、逻辑、组件定义、不认识的字段都还在）', () {
      for (final e in olds.entries) {
        final before = LcDocument.parse(e.value).encode();
        final doc = LcDocument.parse(e.value);
        final id = doc.addPage('临时页')!;
        expect(json(doc.encode())['pages'], hasLength(1));
        expect(json(doc.encode())['id'], kLcFirstPageId, reason: '有别的页时首页的 id 要写出来');
        expect(doc.removePage(id), isTrue);
        expect(doc.encode(), before, reason: e.key);
      }
    });

    test('老版本应用留下的、读不出来的 pages 项原样留着；多页面的项和它们并存', () {
      final src = {
        'version': 3,
        'title': '首页',
        'root': {'id': 'root', 'type': 'page'},
        'pages': [
          {'id': 'p2', 'title': '没有 root 的'},
          42,
          {
            'id': 'p3',
            'title': '好的',
            'root': {'id': 'root', 'type': 'page'},
            'future': {'x': 1},
          },
          {
            'id': 'p4',
            'title': '根不是页面',
            'root': {'id': 'a', 'type': 'text'},
          },
        ],
      };
      final doc = LcDocument.parse(jsonEncode(src));
      expect([for (final p in doc.pages) p.id], ['p1', 'p3']);
      expect(doc.keptPages, hasLength(3));
      final out = json(doc.encode());
      // 读得出来的排前面，读不出来的原样跟在后面；页面对象上不认识的字段还在。
      expect(out['pages'], [(src['pages']! as List)[2], (src['pages']! as List)[0], 42, (src['pages']! as List)[3]]);
      expect(LcDocument.parse(doc.encode()).encode(), doc.encode());
    });
  });

  group('多页面的模型', () {
    test('读写：首页在最外层，别的页在 pages 里；打开再存一字不差', () {
      final doc = pagesSample();
      expect([for (final p in doc.pages) '${p.id}:${p.title}'], ['p1:Home', 'p2:商品列表', 'p3:Me']);
      expect(doc.pageIndex, 0);
      expect(doc.title, 'Home');
      // 组件定义存盘时会补上插槽的名字（第 3 期的规矩），别的和写进去的一字不差。
      for (final k in ['version', 'id', 'title', 'root', 'logic', 'pages']) {
        expect(json(doc.encode())[k], pagesSampleJson()[k], reason: k);
      }
      expect(json(doc.encode()).keys.toList(), ['version', 'id', 'title', 'root', 'logic', 'components', 'pages']);
      expect(LcDocument.parse(doc.encode()).encode(), doc.encode());
    });

    test('换页：title / root / logic、查找、插入都跟着当前页走；换页本身不改内容', () {
      final doc = pagesSample();
      final before = doc.encode();
      expect(doc.openPage('p2'), isTrue);
      expect(doc.title, '商品列表');
      expect(doc.find('item')!.type, 'listItem');
      expect(doc.find('toList'), isNull, reason: '首页的按钮不在这一页');
      expect(doc.logic.handlers.single.target, 'item');
      expect(doc.encode(), before);
      expect(doc.openPage('nope'), isFalse);
      expect(doc.pageIndex, 1);
      // 在第二页里加东西：只进第二页。
      final added = doc.newNode('button');
      expect(doc.insert('root', added), isTrue);
      final out = json(doc.encode());
      expect(jsonEncode(out['root']), isNot(contains(added.id)));
      expect(jsonEncode((out['pages'] as List)[0]), contains(added.id));
      // 新节点的 id 全项目往上接，不和别的页里已有的撞。
      doc.openPage('p1');
      expect(doc.find(added.id), isNull);
    });

    test('每页里节点 id 各算各的：两页都有 root / nav / bar，互不干扰；页内重复的才会被改', () {
      final doc = pagesSample();
      for (final p in doc.pages) {
        expect(p.root.id, 'root');
      }
      final src = pagesSampleJson();
      ((src['pages']! as List)[0] as Map)['root'] = {
        'id': 'root',
        'type': 'page',
        'children': [
          {'id': 'a', 'type': 'text'},
          {'id': 'a', 'type': 'text'},
        ],
      };
      final fixed = LcDocument.parse(jsonEncode(src))..openPage('p2');
      expect(fixed.root.children.map((c) => c.id).toSet().length, 2);
      expect(fixed.root.children.first.id, 'a');
    });

    test('页面 id：缺了、写法不对、重了都补成 p数字，写得对的不动', () {
      final src = pagesSampleJson();
      (src['pages']! as List)
        ..add({
          'id': 'p2',
          'title': '重了',
          'root': {'id': 'root', 'type': 'page'},
        })
        ..add({
          'id': '有 空格',
          'title': '写法不对',
          'root': {'id': 'root', 'type': 'page'},
        })
        ..add({
          'title': '没写',
          'root': {'id': 'root', 'type': 'page'},
        });
      final doc = LcDocument.parse(jsonEncode(src));
      expect([for (final p in doc.pages) p.id], ['p1', 'p2', 'p3', 'p4', 'p5', 'p6']);
      expect([for (final p in doc.pages) p.title], ['Home', '商品列表', 'Me', '重了', '写法不对', '没写']);
    });

    test('新建 / 改名 / 复制 / 删除 / 排序 / 设为首页', () {
      final doc = pagesSample();
      final id = doc.addPage()!;
      expect(id, 'p4');
      expect(doc.pageById(id)!.title, '页面 4');
      expect(doc.pageById(id)!.root.children, isEmpty);
      expect(doc.pageIndex, 0, reason: '新建不换页，换不换由界面定');

      expect(doc.renamePage(id, '  关于\n我们  '), isTrue);
      expect(doc.pageTitle(id), '关于 我们');
      expect(doc.renamePage(id, '关于 我们'), isFalse, reason: '没变');
      expect(doc.renamePage(id, '   '), isTrue);
      expect(doc.pageTitle(id), '未命名页面');
      expect(doc.renamePage('nope', 'x'), isFalse);
      doc.renamePage(id, '字' * 80);
      expect(doc.pageTitle(id)!.runes.length, kLcMaxPageTitle);

      // 复制：紧跟在原来那页后面，组件树和逻辑照抄，是各自独立的一份。
      final copy = doc.duplicatePage('p2')!;
      expect([for (final p in doc.pages) p.id], ['p1', 'p2', copy, 'p3', 'p4']);
      expect(doc.pageTitle(copy), '商品列表 副本');
      final a = doc.pageById('p2')!, b = doc.pageById(copy)!;
      expect(jsonEncode(b.root.toJson()), jsonEncode(a.root.toJson()));
      expect(jsonEncode(b.logic.toJson()), jsonEncode(a.logic.toJson()));
      b.root.children.clear();
      expect(a.root.children, isNotEmpty);

      // 排序和设为首页：当前在编辑的那页不变。
      doc.openPage('p3');
      expect(doc.movePage('p4', 1), isTrue);
      expect([for (final p in doc.pages) p.id], ['p1', 'p4', 'p2', copy, 'p3']);
      expect(doc.page.id, 'p3');
      expect(doc.setHomePage('p3'), isTrue);
      expect(doc.pages.first.id, 'p3');
      expect(doc.page.id, 'p3');
      expect(json(doc.encode())['id'], 'p3');
      expect(json(doc.encode())['title'], 'Me');
      expect(doc.setHomePage('p3'), isFalse, reason: '已经是首页');

      // 删除：删的是当前页时落到原位置上的那一页；只剩一页时不能删。
      expect(doc.removePage('p3'), isTrue);
      expect(doc.page.id, 'p1');
      expect(doc.removePage('nope'), isFalse);
      for (final p in [...doc.pages.skip(1)]) {
        expect(doc.removePage(p.id), isTrue);
      }
      expect(doc.pages.single.id, 'p1');
      expect(doc.removePage('p1'), isFalse);
    });

    test('最多 $kLcMaxPages 页：满了不能再加、不能再复制；文件里多出来的原样留着', () {
      final doc = LcDocument.starter('a');
      while (doc.canAddPage) {
        doc.addPage();
      }
      expect(doc.pages.length, kLcMaxPages);
      expect(doc.addPage(), isNull);
      expect(doc.duplicatePage('p1'), isNull);
      final src = json(doc.encode());
      (src['pages'] as List).add({
        'id': 'extra',
        'title': '第 31 页',
        'root': {'id': 'root', 'type': 'page'},
      });
      final again = LcDocument.parse(jsonEncode(src));
      expect(again.pages.length, kLcMaxPages);
      expect(json(again.encode())['pages'], src['pages']);
    });

    test('撤销 / 重做：加页、删页、改名都能退回去', () {
      final doc = pagesSample();
      final history = LcHistory(doc);
      final first = doc.encode();
      doc.removePage('p2');
      history.record(doc);
      doc.renamePage('p3', '我');
      history.record(doc);
      expect(history.undo()!.pageTitle('p3'), 'Me');
      final back = history.undo()!;
      expect(back.encode(), first);
      expect(history.redo()!.pageById('p2'), isNull);
    });

    test('撤销 / 重做拿回来的文档开在“那一步所在的页”上；只换页不算一步', () {
      final doc = pagesSample();
      final history = LcHistory(doc);
      doc.openPage('p2');
      history.record(doc);
      expect(history.canUndo, isFalse, reason: '只是换了页');
      doc.insert('root', doc.newNode('text')); // 在第二页上改
      history.record(doc);
      doc.openPage('p3');
      final made = doc.addPage()!; // 在第三页时新建了一页，并换过去
      doc.openPage(made);
      history.record(doc);
      // 退“新建页面”：那一页没了，开在上一步所在的页（第二页）。
      expect(history.undo()!.page.id, 'p2');
      // 再退：退的是第二页上的修改，开在第二页。
      final back = history.undo()!;
      expect(back.page.id, 'p2');
      expect(back.encode(), pagesSample().encode());
      expect(history.redo()!.page.id, 'p2');
      expect(history.redo()!.page.id, made);
    });
  });

  group('“去页面”积木', () {
    test('读成人话、校验、新积木的默认值', () {
      final doc = pagesSample();
      final block = doc.logic.handlers.first.body.single;
      expect(block.op, kLcGoPageOp);
      expect(describeBlock(block, doc), '去页面 「商品列表」');
      expect(validateLogic(doc), isEmpty);
      expect(newBlock(kLcGoPageOp, doc).args, {'page': 'p2'}, reason: '默认挑第一个“别的页”');
      expect(newBlock(kLcGoPageOp, LcDocument.starter('x')).args, {'page': 'p1'}, reason: '只有一页时填它自己');
      expect(newBlock(kLcGoPageOp).args, {'page': ''});

      // 没选 / 页面删掉了：都是错误，说得出是哪一块的哪个参数。
      block.args['page'] = '';
      expect([for (final i in validateLogic(doc)) (i.code, i.isError, i.arg)], [(LcIssueCode.missingArg, true, 'page')]);
      block.args['page'] = 'p2';
      doc.removePage('p2');
      expect([for (final i in validateLogic(doc)) (i.code, i.isError, i.arg)], [(LcIssueCode.pageNotFound, true, 'page')]);
      expect(describeBlock(block, doc), '去页面 「已经删掉的页面」');
      block.args['page'] = 7;
      expect([for (final i in validateLogic(doc)) i.code], [LcIssueCode.badArg]);
    });

    test('删页面不连带删积木和导航项：留着、数得出来有几处指着它', () {
      final doc = pagesSample();
      // 指着“我的”的：首页两块积木 + 三页的底部导航各一项，但“我的”自己那页的不算。
      expect(doc.pageRefCount('p3'), 4);
      expect(doc.pageRefCount('p1'), 4);
      expect(doc.pageRefCount('nope'), 0);
      doc.removePage('p3');
      expect(doc.logic.handlers.length, 3);
      expect(jsonEncode(doc.root.toJson()), contains('"page":"p3"'));
    });

    test('快捷操作：“点击时去页面”存下来就是帽子下面一块 goPage；项目里没有的页面设不上', () {
      final doc = pagesSample();
      expect(kLcQuickActions.first, kLcGoPageQuick);
      expect(lcQuickValue(doc, 'toList', kLcGoPageQuick), 'p2');
      expect(lcQuickValue(doc, 'check', kLcGoPageQuick), isNull, reason: '写在“如果”里面的不算快捷操作');
      expect(lcSetQuick(doc, 'hello', kLcGoPageQuick, 'nope'), isFalse);
      expect(lcSetQuick(doc, 'hello', kLcGoPageQuick, 'p3'), isTrue);
      final h = doc.logic.handlersFor('hello').single;
      expect(h.toJson()['body'], [
        {
          'op': 'goPage',
          'args': {'page': 'p3'},
        },
      ]);
      expect(lcSetQuick(doc, 'hello', kLcGoPageQuick, 'p3'), isFalse, reason: '没变');
      expect(lcSetQuick(doc, 'hello', kLcGoPageQuick, 'p2'), isTrue);
      expect(doc.logic.handlersFor('hello').single.body.single.args['page'], 'p2');
      expect(lcSetQuick(doc, 'hello', kLcGoPageQuick, ''), isTrue);
      expect(doc.logic.handlersFor('hello'), isEmpty);
      // 存了再读还认得。
      final again = LcDocument.parse(doc.encode());
      expect(lcQuickValue(again, 'more', kLcGoPageQuick), 'p3');
    });
  });

  group('自定义组件属于项目（所有页面共用）', () {
    test('每一页的实例都认得定义的插槽；用了几处按所有页面数', () {
      final doc = pagesSample();
      expect(doc.components.single.id, 'c1');
      expect(componentUseCount(doc, 'c1'), 2);
      doc.openPage('p2');
      expect(doc.find('card')!.instSlots.map((s) => s.name), [kLcDefaultSlot]);
      expect(doc.component('c1'), isNotNull, reason: '换到别的页，组件还是那一个');
    });

    test('删组件定义：别的页里的实例一起处理（拒绝时数得对；连实例删时每页都删、各清各页的逻辑）', () {
      final doc = pagesSample();
      doc.openPage('p3');
      final refused = deleteComponent(doc, 'c1');
      expect(refused.ok, isFalse);
      expect(refused.uses, 2);

      // 给第二页那个实例挂一串逻辑，看删的时候清的是不是那一页的。
      doc.pageById('p2')!.logic.addHandler('click', target: 'card');
      expect(deleteComponent(doc, 'c1', instances: LcDeleteInstances.remove).ok, isTrue);
      for (final p in doc.pages) {
        expect(jsonEncode(p.root.toJson()), isNot(contains('"component"')), reason: p.title);
      }
      expect(doc.pageById('p2')!.logic.handlers.map((h) => h.target), ['item']);
      expect(doc.pageById('p1')!.logic.handlers.length, 3, reason: '首页的逻辑没挂在实例上，不该动');
    });

    test('删组件定义、选“拆开”：每一页的实例都拆成普通控件', () {
      final doc = pagesSample();
      expect(deleteComponent(doc, 'c1', instances: LcDeleteInstances.detach).ok, isTrue);
      final home = jsonEncode(doc.pageById('p1')!.root.toJson()), list = jsonEncode(doc.pageById('p2')!.root.toJson());
      expect(home, allOf(contains('今日推荐'), contains('草莓蛋糕'), isNot(contains('"component"'))));
      expect(list, allOf(contains('蛋糕'), contains('（空的）'), isNot(contains('"component"'))));
    });

    test('插槽改名 / 取消插槽：扫所有页面里的实例', () {
      final doc = pagesSample();
      // 先让第二页的实例也填上内容。
      doc.openPage('p2');
      expect(doc.insert('card', doc.newNode('text')), isTrue);
      doc.openPage('p3'); // 人在第三页：照样要管到前两页
      expect(slotFillCount(doc, 'c1', kLcDefaultSlot), (instances: 2, nodes: 2));
      expect(renameSlotsInInstances(doc, 'c1', {kLcDefaultSlot: 'body'}), 2);
      for (final id in ['p1', 'p2']) {
        expect(doc.pageById(id)!.root.children.firstWhere((n) => n.type == 'component').children.single.slot, 'body', reason: id);
      }
      // 取消插槽：两页里填的内容都挪到各自实例的后面。
      final fresh = pagesSample()..openPage('p3');
      expect(evictSlotContent(fresh, 'c1', kLcDefaultSlot), 1);
      final home = fresh.pageById('p1')!.root.children;
      final at = home.indexWhere((n) => n.type == 'component');
      expect(home[at].children, isEmpty);
      expect(home[at + 1].id, 'cardText');
    });
  });
}
