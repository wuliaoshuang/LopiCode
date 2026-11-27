// 顶部导航栏跨页共用（第四轮 B3）：文件里只有一份、各页节点只留记号和自己的那几样；样子改一页各页都变；
// 每页可以有自己的标题、返回箭头、左右按钮；“这一页不显示”；“改成共用 / 取消共用”；没用共用的文件逐字节不变。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/nav_shared.dart';
import 'package:lopicode/lowcode/top_shared.dart';

import 'support/pages_sample.dart';

LcDocument _sample() => pagesSample();

LcNode _top(LcDocument d, String page) => lcTopsIn(d.pageById(page)!.root).first;

Map<String, dynamic> _topJson(Map<String, dynamic> root) => (root['children'] as List).cast<Map<String, dynamic>>().firstWhere((c) => c['type'] == 'appBar');

void main() {
  test('没用共用顶栏的文件：读了再存，一个字节都不变；只用了共用底部导航的文件也不变', () {
    final src = const JsonEncoder.withIndent('  ').convert(_sample().toJson());
    final again = LcDocument.parse(src);
    expect(again.encode(), src);
    expect(again.sharedTop, isNull);
    final nav = _sample();
    lcShareNav(nav, 'p1');
    final navSrc = nav.encode();
    expect(navSrc.contains('topBar'), isFalse);
    expect(LcDocument.parse(navSrc).encode(), navSrc);
  });

  test('改成共用：样子只存一份；标题、返回箭头和作准的不一样的留成那一页自己的；没有顶栏的页不加', () {
    final doc = _sample();
    final plan = lcShareTopPlan(doc, 'p1')!;
    expect([for (final p in plan.replaced) p.id], ['p2']);
    expect(plan.keeps['p2'], {'title', 'back'});
    expect(plan.differs, isFalse);
    expect(lcShareTop(doc, 'p1'), 2);
    expect(lcSharedTopPageCount(doc), 2);
    expect(lcPageShowsSharedTop(doc.pageById('p3')!), isFalse);
    final json = doc.toJson();
    final shared = (json['shared'] as Map)['topBar'] as Map;
    expect((shared['props'] as Map)['title'], '首页');
    final home = _topJson(json['root'] as Map<String, dynamic>);
    expect(home.keys.toSet(), {'id', 'type', 'shared'}, reason: '作准的那一页没有自己的东西');
    final p2 = _topJson(((json['pages'] as List).first as Map)['root'] as Map<String, dynamic>);
    expect(p2['own'], ['title', 'back']);
    expect(p2['props'], {'title': '商品', 'back': true});
    final back = LcDocument.parse(jsonEncode(json));
    expect(_top(back, 'p1').props['title'], '首页');
    expect(_top(back, 'p2').props['title'], '商品');
    expect(_top(back, 'p2').props['back'], true);
    expect(_top(back, 'p2').props['width'], 'fill');
    expect(back.encode(), doc.encode(), reason: '再存一次不变');
  });

  test('在一页上改样子，别的页跟着变；自己的标题不动；共用的标题改了，没有自己标题的页跟着变', () {
    final doc = _sample();
    lcShareTop(doc, 'p1');
    lcSetPageShowsSharedTop(doc, 'p3', true);
    expect(_top(doc, 'p3').props['title'], 'Me', reason: '新加到一页上：标题先用页面的名字');
    expect(doc.pageById('p3')!.root.children.first.type, 'appBar', reason: '放在页面最前面');
    lcSetTopOwn(doc, _top(doc, 'p3'), 'title', false);
    expect(_top(doc, 'p3').props['title'], '首页', reason: '关掉“自己的标题”＝换回共用的');
    doc.openPage('p2');
    final bar = _top(doc, 'p2');
    bar.props['bg'] = '#112233';
    bar.props['variant'] = 'center';
    bar.style['height'] = '64px';
    bar.props['title'] = '全部商品'; // p2 自己的标题
    doc.toJson();
    for (final id in ['p1', 'p2', 'p3']) {
      expect(_top(doc, id).props['bg'], '#112233', reason: id);
      expect(_top(doc, id).props['variant'], 'center', reason: id);
      expect(_top(doc, id).style['height'], '64px', reason: id);
    }
    expect(
      [
        for (final id in ['p1', 'p2', 'p3']) _top(doc, id).props['title'],
      ],
      ['首页', '全部商品', '首页'],
    );
    expect(
      [
        for (final id in ['p1', 'p2', 'p3']) _top(doc, id).props['back'] == true,
      ],
      [false, true, false],
    );
    // 在首页（标题跟共用的走）改标题：p3 跟着变，p2 不变
    doc.openPage('p1');
    _top(doc, 'p1').props['title'] = '小店';
    doc.toJson();
    expect(
      [
        for (final id in ['p1', 'p2', 'p3']) _top(doc, id).props['title'],
      ],
      ['小店', '全部商品', '小店'],
    );
    final back = LcDocument.parse(doc.encode());
    expect(
      [
        for (final id in ['p1', 'p2', 'p3']) _top(back, id).props['title'],
      ],
      ['小店', '全部商品', '小店'],
    );
    expect(back.encode(), doc.encode());
  });

  test('左右按钮：共用的抄到各页、id 不变；一页用自己的以后各管各的；换回共用的', () {
    final doc = _sample();
    lcShareTop(doc, 'p1');
    final home = _top(doc, 'p1');
    final btn = doc.newNode('button')
      ..props['text'] = '搜索'
      ..more['slot'] = 'right';
    home.children.add(btn);
    doc.toJson();
    final other = _top(doc, 'p2');
    expect(other.children.single.props['text'], '搜索');
    expect(other.children.single.id, btn.id, reason: '抄到别的页 id 不变：那一页给它接的逻辑不会丢');
    expect(other.children.single.more['slot'], 'right');
    // p2 用自己的左右按钮
    doc.openPage('p2');
    lcSetTopOwn(doc, other, 'slots', true);
    other.children.single.props['text'] = '筛选';
    doc.toJson();
    expect(_top(doc, 'p1').children.single.props['text'], '搜索');
    final json = doc.toJson();
    expect((((json['shared'] as Map)['topBar'] as Map)['children'] as List).length, 1);
    expect(_topJson(json['root'] as Map<String, dynamic>).containsKey('children'), isFalse);
    expect((_topJson(((json['pages'] as List).first as Map)['root'] as Map<String, dynamic>)['children'] as List).length, 1);
    final back = LcDocument.parse(jsonEncode(json));
    expect(_top(back, 'p2').children.single.props['text'], '筛选');
    expect(_top(back, 'p1').children.single.props['text'], '搜索');
    expect(back.encode(), doc.encode());
    // 换回共用的
    lcSetTopOwn(doc, _top(doc, 'p2'), 'slots', false);
    doc.toJson();
    expect(_top(doc, 'p2').children.single.props['text'], '搜索');
    expect(lcTopOwn(_top(doc, 'p2')), {'title', 'back'});
  });

  test('这一页不显示 / 再显示；每页都不显示时那一份还留着；取消共用各页留着当时的样子', () {
    final doc = _sample();
    lcShareTop(doc, 'p1');
    expect(lcSetPageShowsSharedTop(doc, 'p1', false), isTrue);
    expect(lcSetPageShowsSharedTop(doc, 'p2', false), isTrue);
    expect(lcSharedTopPageCount(doc), 0);
    final kept = LcDocument.parse(doc.encode());
    expect(kept.sharedTop, isNotNull);
    expect(lcSetPageShowsSharedTop(kept, 'p2', true), isTrue);
    expect(_top(kept, 'p2').props['title'], '商品列表');
    expect(lcUnshareTop(kept), 1);
    final plain = LcDocument.parse(kept.encode());
    expect(plain.sharedTop, isNull);
    expect(plain.encode().contains('"shared"'), isFalse);
    expect(_top(plain, 'p2').more.containsKey('own'), isFalse);
    expect(_top(plain, 'p2').props['title'], '商品列表');
  });

  test('新放进一页的顶栏：项目里有共用的、这一页还没显示 → 就是共用的那条；容错：有记号没有那一份、那一份是坏的', () {
    final doc = _sample();
    lcShareTop(doc, 'p1');
    doc.openPage('p3');
    final n = doc.newNode('appBar');
    lcAdoptNewTop(doc, n);
    expect(lcIsSharedTop(n), isTrue);
    expect(n.props['title'], 'Me');
    // 手写的文件：节点带记号，最外层没有那一份
    final json = pagesSampleJson();
    ((json['root'] as Map)['children'] as List).cast<Map<String, Object?>>().firstWhere((c) => c['type'] == 'appBar')['shared'] = true;
    final loose = LcDocument.parse(jsonEncode(json));
    expect(loose.sharedTop, isNotNull);
    expect(_top(loose, 'p1').props['title'], '首页');
    // 那一份不是对象：当没有，照普通顶栏读
    final bad = pagesSampleJson()..['shared'] = {'topBar': 3, 'x': 1};
    final badDoc = LcDocument.parse(jsonEncode(bad));
    expect(badDoc.sharedTop, isNull);
    expect((badDoc.toJson()['shared'] as Map)['x'], 1, reason: 'shared 里别的键原样留着');
    // 那一份里的 children 有坏的：跳过坏的，不抛
    final odd = _sample();
    lcShareTop(odd, 'p1');
    odd.sharedTop!['children'] = [
      3,
      {
        'type': 'button',
        'id': 'ok',
        'props': {'text': '好'},
        'slot': 'right',
      },
      {'type': 'page', 'id': 'x'},
    ];
    final oddJson = odd.toJson();
    ((oddJson['shared'] as Map)['topBar'] as Map)['children'] = odd.sharedTop!['children'];
    final read = LcDocument.parse(jsonEncode(oddJson));
    expect(_top(read, 'p1').children.length, lessThanOrEqualTo(2));
  });
}
