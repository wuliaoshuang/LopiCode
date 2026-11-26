// 第 5 期（状态与数据绑定）的导出，不需要外部编译器的那部分：
// 没用状态和绑定的页面四种导出一个字不多；用了的页面各自多出什么；Flutter 按初值定下来并写明。
// 真编译、真跑在 lowcode_bind_run_test.dart。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/lowcode/bind_model.dart';
import 'package:lopicode/lowcode/component_model.dart';
import 'package:lopicode/lowcode/logic_variable.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/state_model.dart';

import 'support/bind_export_files.dart';
import 'support/bind_sample.dart';

void main() {
  test('只建了状态、哪儿都没绑：四种导出和没建状态时逐字节一样', () {
    final plain = LcDocument.starter('我的小站');
    final before = allExportFiles(plain);
    final withState = LcDocument.parse(plain.encode());
    lcEditProjectStates(withState, (list) => list.add(LcVariable(name: 'user', type: 'text', initial: '小塔塔')));
    final after = allExportFiles(withState);
    expect(after.keys.toList(), before.keys.toList());
    for (final k in before.keys) {
      expect(after[k], before[k], reason: '$k 变了');
    }
  });

  test('没用状态和绑定的页面：导出里没有任何绑定运行代码、没有 lc-state.js', () {
    final files = allExportFiles(LcDocument.starter('我的小站'));
    expect(files.keys.where((k) => k.contains('lc-state')), isEmpty);
    for (final e in files.entries) {
      expect(e.value, isNot(contains('lcShared')), reason: e.key);
      expect(e.value, isNot(contains('lcBind')), reason: e.key);
    }
  });

  test('带状态和绑定的两页样例：三种网页导出各自多出状态文件 / 运行代码', () {
    final files = allExportFiles(bindSample());
    expect(files.keys, containsAll(['vue/lc-state.js', 'react/lc-state.js', 'html/index.html', 'html/page-cart.html', 'html/logic.js']));
    expect(files['vue/lc-state.js'], contains('reactive('));
    expect(files['vue/Home.vue'], allOf(contains('v-model="keyword"'), contains('v-for='), contains('v-if='), contains('v-show='), contains('computed(')));
    expect(files['react/lc-state.js'], contains('lcSubscribe'));
    expect(files['react/Home.jsx'], allOf(contains('useSyncExternalStore'), contains('.map((it, i) =>'), contains('key={')));
    expect(files['html/logic.js'], contains('sessionStorage'));
  });

  test('Flutter：按初值定下来——文字换成算好的、重复按初值展开、条件不成立的不出；文件头写明', () {
    final dart = allExportFiles(bindSample())['flutter/page.dart']!;
    expect(dart, contains('状态与绑定：这一份不导出逻辑，状态不会变，所以绑定按初值定了下来'));
    expect(dart, contains("'你好，小塔塔'"));
    expect(dart, contains("'已点 0 次'"));
    expect(dart, contains("'1. 苹果 ¥3'"));
    expect(dart, contains("'2. 香蕉 ¥2'"));
    expect(dart, isNot(contains('点够三次了')), reason: '存在条件按初值不成立');
    expect(dart, isNot(contains('在搜：')), reason: '显示条件按初值不成立');
    expect(dart, contains('onPressed: null'), reason: '“提交”按初值是禁用的');
  });

  test('Flutter：列表是空的→出“空的时候”那句话；重复最多展开 200 份', () {
    final json = bindSampleJson();
    final state = (json['state']! as List).cast<Map<String, Object?>>();
    state.firstWhere((s) => s['name'] == 'cart')['initial'] = <Object?>[];
    var dart = allExportFiles(LcDocument.parse(_enc(json)))['flutter/page.dart']!;
    expect(dart, contains("'购物车是空的'"));
    expect(dart, isNot(contains('苹果')));

    state.firstWhere((s) => s['name'] == 'cart')['initial'] = [
      for (var i = 0; i < 260; i++) {'id': 'k$i', 'name': '货$i', 'price': 1},
    ];
    dart = allExportFiles(LcDocument.parse(_enc(json)))['flutter/page.dart']!;
    expect(dart, contains("'200. 货199 ¥1'"));
    expect(dart, isNot(contains('货200 ')));
  });

  test('自定义组件定义里的绑定这一版不导出：四种导出和定义里没绑时一样', () {
    LcDocument make(bool bound) {
      final doc = LcDocument.starter('我的小站');
      doc.logic.variables.add(LcVariable(name: 'who', type: 'text', initial: '小塔塔'));
      final inner = LcNode(id: 'ct', type: 'text', props: {'text': '组件里的字'});
      if (bound) lcSetData(inner, 'text', lcSrcVar('who'));
      doc.components.add(LcComponentDef(id: 'c1', name: '卡片', root: LcNode(id: 'cr', type: 'column', children: [inner])));
      doc.root.children.add(LcNode(id: 'inst', type: 'component', props: {'ref': 'c1'}));
      return doc;
    }

    final plain = allExportFiles(make(false)), bound = allExportFiles(make(true));
    expect(bound.keys.toList(), plain.keys.toList());
    for (final k in plain.keys) {
      expect(bound[k], plain[k], reason: '$k 变了');
    }
  });

  test('绑定字段写坏了：导出不崩，照没绑的出', () {
    final doc = LcDocument.starter('我的小站');
    doc.find('n1')!.more[kLcData] = {'text': 7, 'nope': {'from': 'var'}};
    doc.find('n2')!.more[kLcRepeat] = 'x';
    doc.find('n3')!.more[kLcShowIf] = [1, 2];
    final files = allExportFiles(doc);
    expect(files['html/index.html'], contains('<'));
    expect(files['flutter/page.dart'], contains('class '));
  });
}

String _enc(Map<String, Object?> json) => LcDocument.parse(_json(json)).encode();
String _json(Object? v) => const JsonEncoder().convert(v);
