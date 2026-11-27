// 第四轮 B2：组件的事件、变体、自己的状态、实例属性绑定——模型和“摊开”那一路（纯网页、Flutter）不需要外部编译器的部分。
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/lowcode/component_expand.dart';
import 'package:lopicode/lowcode/component_extras.dart';
import 'package:lopicode/lowcode/component_ops.dart';
import 'package:lopicode/lowcode/export_live_doc.dart';
import 'package:lopicode/lowcode/model.dart';

import 'support/bind_export_files.dart';
import 'support/comp_samples.dart';

void main() {
  test('读定义：事件、两组变体、自己的状态都读得出来；存回去字段不丢', () {
    final doc = compUserDoc([productCardDef()]);
    final def = doc.component('c1')!;
    expect([for (final e in lcCompEvents(def)) '${e.name}/${e.label}/${e.params.length}'], ['addCart/点了加入购物车/1']);
    expect(lcVariantGroups(def), {'kind': '样子', 'size': '大小'});
    expect([for (final s in lcCompStates(def)) s.name], ['liked']);
    expect(lcDefIsLive(def), isTrue);
    final again = compUserDoc([def.toJson()]);
    expect(again.component('c1')!.toJson(), def.toJson());
  });

  test('摊开：属性绑定换成页面的状态 / 写死的值；每个实例一份状态；变体样式叠上；事件成了处理', () {
    final doc = compUserDoc([productCardDef()]);
    final x = LcExpander(doc);
    final tree = x.outer(doc.root);
    final p1 = tree.children.firstWhere((n) => n.id == 'p1');
    expect(p1.style['background-color'], '#FFF3E0');
    final name = p1.children.firstWhere((n) => n.id == 'p1__name');
    expect(name.more['data'], {
      'text': {'from': 'var', 'name': 'apple'},
    });
    expect(name.style['font-size'], '22px');
    final p2 = tree.children.firstWhere((n) => n.id == 'p2');
    expect(p2.style.containsKey('background-color'), isFalse);
    expect(p2.children.firstWhere((n) => n.id == 'p2__name').more['data'], {
      'text': {
        'from': 'expr',
        'expr': {'e': 'text', 'v': '香蕉'},
      },
    });
    expect([for (final v in x.hoisted) v.name], ['p1__liked', 'p2__liked']);
    expect(p1.children.firstWhere((n) => n.id == 'p1__fav').more['model'], {'state': 'p1__liked'});
    expect([for (final s in x.synth) '${s.nodeId}/${s.event}/${s.body.single.op}'], ['p1__buy/click/changeVar', 'p2__buy/click/changeVar']);
    // 插槽照旧：填了的用填的，没填的用默认内容。
    expect(p1.children.first.id, 'p1img');
    expect(p2.children.first.id, 'p2__picText');
  });

  test('导出看的文档：不改原文档；没有新东西的文档原样返回', () {
    final doc = compUserDoc([productCardDef()]);
    final before = doc.encode();
    final view = lcExportDoc(doc);
    expect(identical(view, doc), isFalse);
    expect(doc.encode(), before);
    expect([for (final v in view.logic.variables) v.name], containsAll(['cart', 'p1__liked', 'p2__liked']));
    expect(view.logic.handlers.where((h) => h.target == 'p1__buy'), hasLength(1));
    final plain = compUserDoc([]);
    expect(identical(lcExportDoc(plain), plain), isTrue);
  });

  test('三种形状：纯网页和 Flutter 导出都出得来，里面有该有的东西', () {
    final files = allExportFiles(compUserDoc([productCardDef(), loginFormDef(), tagBarDef()]));
    final html = files['html/index.html']!, js = files['html/logic.js']!, css = files['html/style.css']!, dart = files['flutter/page.dart']!;
    expect(html, allOf(contains('n-p1__buy'), contains('n-login__userIn'), contains('n-tags__chip')));
    expect(js, allOf(contains('p1__liked'), contains('"p1__buy", "click"'), contains('"tags__clear", "click"')));
    expect(css, contains('#FFF3E0'));
    expect(dart, allOf(contains('s_p1__liked'), contains('s_tagList')));
  });
  test('拆开用了新东西的实例：它那一份状态落成页面状态、接的事件落成页面处理（指向拆出来的那个按钮），再导出不出错', () {
    final doc = compUserDoc([productCardDef()]);
    final before = doc.logic.handlers.length;
    expect(detachInstance(doc, 'p1').error, isNull);
    expect(doc.find('p1')!.type, isNot('component'));
    expect(doc.logic.variables.map((v) => v.name), contains('p1__liked'));
    expect(doc.logic.handlers.length, before + 1);
    final h = doc.logic.handlers.last;
    expect(h.event, 'click');
    expect(doc.find(h.target!)?.type, 'button', reason: '处理要指向拆出来以后的新编号');
    // 另一张卡片还是实例，照旧。
    expect(doc.find('p2')!.type, 'component');
    final files = allExportFiles(doc);
    expect(files['html/index.html'], contains('加入购物车'));
    expect(files['html/logic.js'], contains('p1__liked'));
    // 存盘再读回来还是这样。
    final again = LcDocument.parse(doc.encode());
    expect(again.logic.handlers.length, before + 1);
  });
}
