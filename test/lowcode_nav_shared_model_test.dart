// 底部导航跨页真共用（第四轮 B1）：文件里只有一份、各页节点只留记号；改一页各页都变；
// “这一页不显示”；当前项自动算；“改成共用 / 取消共用”；没用共用的文件逐字节不变。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/model_v3_components.dart';
import 'package:lopicode/lowcode/nav_shared.dart';

import 'support/pages_sample.dart';

LcDocument _sample() => LcDocument.fromJson(jsonDecode(jsonEncode(pagesSampleJson())) as Map<String, dynamic>);

LcNode _navOf(LcPage p) => lcNavsIn(p.root).first;

void main() {
  test('没用共用导航的文件：读了再存，一个字节都不变（没有 shared 字段）', () {
    final src = const JsonEncoder.withIndent('  ').convert(_sample().toJson());
    final again = LcDocument.parse(src);
    expect(again.encode(), src);
    expect(src.contains('"shared"'), isFalse);
    expect(again.sharedNav, isNull);
  });

  test('改成共用：文件里只有最外层一份，各页节点只剩记号；读回来各页内容齐全、当前项各亮各的', () {
    final doc = _sample();
    expect(lcNavsAllSame(doc), isTrue, reason: '样例三页的导航只有“当前项”不同，算一样');
    expect(lcShareNav(doc, 'p1'), 3);
    final json = doc.toJson();
    final shared = (json['shared'] as Map)['bottomNav'] as Map;
    expect((shared['props'] as Map).containsKey('current'), isFalse);
    expect(((shared['props'] as Map)['items'] as List).length, 3);
    Map<String, dynamic> navJson(Map<String, dynamic> root) => (root['children'] as List).cast<Map<String, dynamic>>().firstWhere((c) => c['type'] == 'bottomNav');
    for (final root in [json['root'], for (final p in json['pages'] as List) (p as Map)['root']]) {
      final n = navJson(root as Map<String, dynamic>);
      expect(n.keys.toSet(), {'id', 'type', 'shared'});
    }
    final back = LcDocument.parse(jsonEncode(json));
    expect([for (final p in back.pages) _navOf(p).props['current']], [0, 1, 2]);
    expect(lcObjects(_navOf(back.pages[2]), 'items').length, 3);
    expect(back.encode(), doc.encode(), reason: '再存一次不变');
  });

  test('在一页上改，别的页跟着变（不用点同步）：名字、图标、顺序、增删、样子、样式', () {
    final doc = _sample()..openPage('p2');
    lcShareNav(doc, 'p2');
    final nav = _navOf(doc.page);
    final items = [for (final m in lcObjects(nav, 'items')) Map<String, dynamic>.of(m)];
    items[0]['label'] = '主页';
    items[0]['icon'] = 'star';
    nav.props['items'] = [items[2], items[0]]; // 换了顺序、删了一项
    nav.props['variant'] = 'iconOnly';
    nav.style['height'] = '72px';
    nav.more['states'] = {
      'pressed': {'opacity': '0.5'},
    };
    doc.toJson(); // 记撤销 / 存盘都会走这里
    for (final p in doc.pages) {
      final n = _navOf(p);
      expect([for (final m in lcObjects(n, 'items')) m['label']], ['我的', '主页'], reason: p.id);
      expect(n.props['variant'], 'iconOnly');
      expect(n.style['height'], '72px');
      expect(n.more['states'], isNotNull);
    }
    // 当前项：p1→第 2 项（主页指着 p1），p3→第 1 项，p2 没有哪一项指着它→第 1 项
    expect([for (final p in doc.pages) _navOf(p).props['current']], [1, 0, 0]);
  });

  test('这一页不显示 / 再显示；每页都不显示时那一份还留着', () {
    final doc = _sample();
    lcShareNav(doc, 'p1');
    expect(lcSetPageShowsSharedNav(doc, 'p2', false), isTrue);
    expect(lcSetPageShowsSharedNav(doc, 'p2', false), isFalse);
    expect(lcPageShowsSharedNav(doc.pages[1]), isFalse);
    expect(lcSharedNavPageCount(doc), 2);
    var back = LcDocument.parse(doc.encode());
    expect(lcNavsIn(back.pages[1].root), isEmpty);
    for (final p in doc.pages) {
      lcSetPageShowsSharedNav(doc, p.id, false);
    }
    back = LcDocument.parse(doc.encode());
    expect(back.sharedNav, isNotNull);
    expect(lcSetPageShowsSharedNav(back, 'p3', true), isTrue);
    final n = back.pages[2].root.children.last;
    expect(lcIsSharedNav(n), isTrue);
    expect(n.props['current'], 2);
    expect(lcObjects(n, 'items').length, 3);
  });

  test('改成共用：各页不一样时以挑的那一页为准，别的被换掉；导航项指着却没有导航的页加上', () {
    final doc = _sample();
    _navOf(doc.pages[1]).props['items'] = [
      {'icon': 'star', 'label': '只有一项', 'page': 'p2'},
    ];
    lcNavsIn(doc.pages[2].root).first; // p3 有
    doc.pages[2].root.children.removeWhere((c) => c.type == 'bottomNav');
    expect(lcNavsAllSame(doc), isFalse);
    final plan = lcShareNavPlan(doc, 'p1')!;
    expect([for (final p in plan.replaced) p.id], ['p2']);
    expect([for (final p in plan.added) p.id], ['p3']);
    expect(plan.differs, isTrue);
    expect(lcShareNav(doc, 'p1'), 3);
    doc.toJson();
    expect(lcObjects(_navOf(doc.pages[1]), 'items').length, 3);
    expect(_navOf(doc.pages[2]).props['current'], 2);
    expect(lcShareNavPlan(doc, 'nope'), isNull);
  });

  test('取消共用：各页留着当时的样子，变回各管各的，文件里没有 shared', () {
    final doc = _sample();
    final before = doc.encode();
    lcShareNav(doc, 'p1');
    doc.toJson();
    expect(lcUnshareNav(doc), 3);
    expect(jsonDecode(doc.encode()), jsonDecode(before), reason: '样例各页本来一样，绕一圈内容回到原样（只有“当前项”这个键的先后可能不同）');
  });

  test('新放的导航栏：已有共用的、这页还没显示→就是共用那条；多页面里的第一条→从一开始就共用；单页面→自己的一条', () {
    final doc = _sample();
    lcShareNav(doc, 'p1');
    lcSetPageShowsSharedNav(doc, 'p1', false);
    final a = doc.newNode('bottomNav');
    lcAdoptNewNav(doc, a);
    expect(lcIsSharedNav(a), isTrue);
    expect(lcObjects(a, 'items').first['page'], 'p1');

    final multi = LcDocument.starter('甲')..addPage('乙');
    final b = multi.newNode('bottomNav');
    lcAdoptNewNav(multi, b);
    expect(lcIsSharedNav(b), isTrue);
    expect(multi.sharedNav, isNotNull);

    final single = LcDocument.starter('甲');
    final c = single.newNode('bottomNav');
    lcAdoptNewNav(single, c);
    expect(lcIsSharedNav(c), isFalse);
    expect(single.sharedNav, isNull);
  });

  test('容错：节点带 shared 却没有最外层那一份→取带 props 的那条；最外层写坏了→原样留着不崩；记号粘进没有共用的项目→不算数', () {
    final json = jsonDecode(jsonEncode(pagesSampleJson())) as Map<String, dynamic>;
    void mark(Map<String, dynamic> root, {bool strip = false}) {
      final n = (root['children'] as List).cast<Map<String, dynamic>>().firstWhere((c) => c['type'] == 'bottomNav');
      n['shared'] = true;
      if (strip) n.remove('props');
    }

    mark(json['root'] as Map<String, dynamic>, strip: true);
    mark(((json['pages'] as List)[0] as Map)['root'] as Map<String, dynamic>);
    final doc = LcDocument.fromJson(json);
    expect(doc.sharedNav, isNotNull);
    expect(lcObjects(_navOf(doc.pages[0]), 'items').length, 3);

    final bad = jsonDecode(jsonEncode(pagesSampleJson())) as Map<String, dynamic>..['shared'] = {'bottomNav': 7, 'other': 1};
    final d2 = LcDocument.fromJson(bad);
    expect(d2.sharedNav, isNull);
    expect((d2.toJson()['shared'] as Map)['other'], 1);
    expect((d2.toJson()['shared'] as Map)['bottomNav'], 7);

    final d3 = _sample();
    _navOf(d3.page).more['shared'] = true;
    expect(d3.toJson().containsKey('shared'), isFalse);
    expect(lcIsSharedNav(_navOf(d3.page)), isFalse);

    final kept = jsonDecode(jsonEncode(pagesSampleJson())) as Map<String, dynamic>
      ..['shared'] = {
        'bottomNav': {
          'props': {'items': <Object?>[]},
        },
        'future': {'x': 1},
      };
    final d4 = LcDocument.fromJson(kept);
    expect((d4.toJson()['shared'] as Map)['future'], {'x': 1}, reason: 'shared 里看不懂的键原样留着');
  });

  test('撤销用的快照：读回来和原来一样（共用的内容没丢）', () {
    final doc = _sample();
    lcShareNav(doc, 'p1');
    final h = LcHistory(doc);
    _navOf(doc.page).props['bg'] = '#000000';
    h.record(doc);
    final undone = h.undo()!;
    expect(_navOf(undone.pages[1]).props['bg'], isNot('#000000'));
    final redone = h.redo()!;
    expect(_navOf(redone.pages[1]).props['bg'], '#000000');
  });
}
