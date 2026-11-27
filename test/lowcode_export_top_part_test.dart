// 第四轮 B5：Vue 3 / React 导出里，各页共用的顶部导航栏抽成一个公共部件文件（components/LcTopBar），
// 各页引用它：这一页的标题、要不要返回箭头当属性传，左右两边的按钮从插槽（React 是 left / right 属性）传。
// 核对：文件清单和各页写法；没用共用的项目导出里没有这个文件；撞名时换名字；被这一页的绑定管着的那条不抽；
// Vue 页面里不再带用不上的那份顶栏 / 底部导航通用样式；官方编译器真编译 0 错误 0 警告；
// Node + jsdom 真跑——换页以后标题、返回箭头、右边的按钮跟着这一页变，点返回箭头回上一页。
// 真编译 / 真跑的环境只在开发机上有，找不到就明确跳过。不联网。没覆盖的：真浏览器、真手机、样式表的效果（jsdom 不排版）。
@Tags(['external'])
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/lowcode/export_react.dart';
import 'package:lopicode/lowcode/export_vue.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/nav_shared.dart';
import 'package:lopicode/lowcode/top_shared.dart';

import 'support/bind_export_files.dart';
import 'support/comp_samples.dart';
import 'support/dev_tools.dart';
import 'support/pages_sample.dart';

const _entry = {'vue': 'LcApp.vue', 'react': 'LcApp.jsx'};
const _ext = {'vue': 'vue', 'react': 'jsx'};
const _label = {'vue': 'Vue 3', 'react': 'React'};

void _walk(Object? v, void Function(Map<String, dynamic> node) visit) {
  if (v is Map<String, dynamic>) {
    visit(v);
    v.values.toList().forEach((x) => _walk(x, visit));
  } else if (v is List) {
    for (final x in v) {
      _walk(x, visit);
    }
  }
}

/// 样例：首页的顶栏没有返回箭头；“商品”页有返回箭头，右边多放一个按钮“购物车”（这一页自己的）。
/// 两页的顶栏改成共用（以首页为准）；“我的”页没有顶栏。
LcDocument _shared({bool nav = false, void Function(Map<String, dynamic> json)? change}) {
  final json = jsonDecode(jsonEncode(pagesSampleJson())) as Map<String, dynamic>;
  _walk(json, (n) {
    if (n['type'] == 'appBar' && (n['props'] as Map?)?['title'] == '商品') {
      n['children'] = [
        {
          'id': 'cart',
          'type': 'button',
          'props': {'text': '购物车'},
          'slot': 'right',
        },
      ];
    }
  });
  change?.call(json);
  final doc = LcDocument.fromJson(json);
  expect(lcShareTop(doc, 'p1'), 2);
  if (nav) lcShareNav(doc, 'p1');
  // 存一遍再读：和她在手机上“改成共用 → 导出”走的是同一条路。
  return LcDocument.parse(doc.encode());
}

Map<String, String> _files(LcDocument doc, String kind) => {for (final f in (kind == 'vue' ? exportVue(doc) : exportReact(doc)).files) f.path: f.content};

void main() {
  if (skipWithoutDom != false) {
    // ignore: avoid_print 跳过的原因要在测试输出里看得见
    print('【跳过】共用顶栏公共部件的真编译 / 真跑：$skipWithoutDom');
  }

  test('样例对不对：两页共用；“商品”页自己的是标题、返回箭头、左右按钮', () {
    final doc = _shared();
    expect(doc.sharedTop, isNotNull);
    expect(lcTopOwn(lcSharedTopsIn(doc.pages[0].root).single), isEmpty);
    expect(lcTopOwn(lcSharedTopsIn(doc.pages[1].root).single), {'title', 'back', 'slots'});
    expect(lcSharedTopsIn(doc.pages[2].root), isEmpty);
  });

  for (final kind in ['vue', 'react']) {
    final ext = _ext[kind]!;
    group('${_label[kind]}：共用的顶部导航栏', () {
      test('多出一个公共部件文件；两页都引用它、各传各的标题 / 返回箭头 / 右边按钮，页面里不再各写一遍', () {
        final files = _files(_shared(), kind);
        final part = files['components/LcTopBar.$ext'];
        expect(part, isNotNull, reason: '${files.keys}');
        expect('<header'.allMatches(part!).length, 1);
        expect(part, contains('lc-bar-back'));
        expect(part, contains('lc-bar-title'));
        expect(part, contains(kind == 'vue' ? '{{ title }}' : '{title}'));
        expect(part, contains(kind == 'vue' ? 'v-if="back"' : '{back ? ('));
        expect(part, contains(kind == 'vue' ? '<slot name="right" />' : '{right ? <div className="lc-slot lc-slot-right">{right}</div> : null}'));
        expect(part, isNot(contains('LCTOPTITLEMARK')));
        final home = files['Home.$ext']!, goods = files['LcPage.$ext']!, me = files['Me.$ext']!;
        for (final src in [home, goods]) {
          expect(src, contains('import LcTopBar from "./components/LcTopBar.$ext";'));
          expect(src, isNot(contains('<header')), reason: '页面里还写着一份顶栏');
          expect('<LcTopBar '.allMatches(src).length, 1);
        }
        expect(me, isNot(contains('LcTopBar')), reason: '“我的”页没有顶栏');
        expect(home, contains(kind == 'vue' ? 'title="首页" />' : 'title={"首页"} />'));
        expect(goods, contains(kind == 'vue' ? 'title="商品" back>' : 'title={"商品"} back'));
        expect(goods, contains(kind == 'vue' ? '<template #right>' : 'right={'));
        expect(goods, contains('购物车'));
        expect(goods, isNot(contains(kind == 'vue' ? '<template #left>' : 'left={')));
      });

      test('没用共用的项目：没有这个文件，各页照旧自己写一份', () {
        final files = _files(pagesSample(), kind);
        expect(files.keys.where((k) => k.contains('LcTopBar')), isEmpty);
        expect(files['Home.$ext'], contains('<header'));
      });

      test('项目里已经有叫 LcTopBar 的自定义组件：公共部件换个名字，两样都在', () {
        final files = _files(_shared(change: (json) => ((json['components'] as List).first as Map)['name'] = 'LcTopBar'), kind);
        expect(files.keys, contains('components/LcTopBar.$ext'));
        expect(files.keys, contains('components/LcTopBar2.$ext'));
        expect(files['components/LcTopBar2.$ext'], contains('<header'));
        expect(files['Home.$ext'], contains('<LcTopBar2 '));
      });

      test('共用的那条顶栏绑了状态（绑定是各页共用的那一份里的）：不抽，各页照旧自己写，没有部件文件', () {
        final doc = _shared();
        final json = doc.toJson();
        json['logic'] = {
          ...?(json['logic'] as Map<String, dynamic>?),
          'variables': [
            {'name': 'who', 'type': 'text', 'initial': '小店'},
          ],
        };
        ((json['shared'] as Map)['topBar'] as Map)['data'] = {'title': cFrom('who')};
        final files = _files(LcDocument.parse(jsonEncode(json)), kind);
        expect(files['LcPage.$ext'], contains('<header'));
        expect(files['Home.$ext'], contains('<header'));
        expect(files.keys.where((k) => k.contains('LcTopBar')), isEmpty);
      });

      test('真编译：0 错误 0 警告（顶栏、底部导航都共用），首页标题在、没有返回箭头', () async {
        for (final nav in [false, true]) {
          final r = await compileExport('compile_$kind.mjs', _files(_shared(nav: nav), kind), _entry[kind]!);
          expect(r.errors, isEmpty, reason: r.raw);
          expect(r.warnings, isEmpty, reason: r.raw);
          expect(r.ok, isTrue, reason: r.raw);
          expect('lc-bar-title'.allMatches(r.html).length, 1, reason: r.html);
          expect(r.html, contains('首页'));
          expect(r.html, isNot(contains('lc-bar-back')));
        }
      }, skip: skipWithoutDom);

      test('真跑：换页以后标题、返回箭头、右边按钮跟着这一页变；没顶栏的页没有', () async {
        final steps = <Map<String, Object?>>[
          {'op': 'count', 'sel': 'header.lc-appBar', 'is': 1},
          {'op': 'text', 'sel': '.lc-bar-title', 'is': '首页'},
          {'op': 'count', 'sel': '.lc-bar-back', 'is': 0},
          {'op': 'count', 'sel': '.lc-slot-right', 'is': 0},
          {'op': 'click', 'sel': '.lc-nav-item', 'at': 1},
          {'op': 'hash', 'is': '#/p2'},
          {'op': 'count', 'sel': 'header.lc-appBar', 'is': 1},
          {'op': 'text', 'sel': '.lc-bar-title', 'is': '商品'},
          {'op': 'count', 'sel': '.lc-bar-back', 'is': 1},
          {'op': 'count', 'sel': '.lc-slot-right', 'is': 1},
          {'op': 'text', 'sel': '.lc-slot-right .n-cart', 'is': '购物车'},
          {'op': 'count', 'sel': '.lc-slot-left', 'is': 0},
          {'op': 'page', 'hash': '#/p3'},
          {'op': 'count', 'sel': 'header.lc-appBar', 'is': 0},
          {'op': 'page', 'hash': '#/p1'},
          {'op': 'text', 'sel': '.lc-bar-title', 'is': '首页'},
          {'op': 'count', 'sel': '.lc-bar-back', 'is': 0},
        ];
        final r = await runInDom(kind, exportFilesOf(_shared(nav: true), kind), _entry[kind]!, steps);
        expect(r.errors, isEmpty);
        expect(r.warnings, isEmpty);
        expect(r.ok, isTrue);
        expect(r.done, steps.length);
      }, skip: skipWithoutDom);
    });
  }

  test('Vue：抽出去以后，页面样式里不再带顶栏 / 底部导航那一类的通用规则；部件文件里有；这条顶栏自己的样式还在页面里', () {
    final files = _files(_shared(nav: true), 'vue');
    final home = files['Home.vue']!;
    expect(home, isNot(contains('.lc-appBar')));
    expect(home, isNot(contains('.lc-bottomNav')));
    expect(home, contains('.n-bar'), reason: '这条顶栏自己的样式规则留在页面里，经 class 落到部件最外层');
    expect(files['components/LcTopBar.vue'], contains(':where(.lc-appBar)'));
    expect(files['components/LcTopBar.vue'], contains(':where(.lc-slot)'));
    expect(files['components/LcBottomNav.vue'], contains('.lc-bottomNav'));
    // 没共用的：页面里照旧带着
    expect(_files(pagesSample(), 'vue')['Home.vue'], contains('.lc-appBar'));
  });
}
