// 第 5 期（状态与数据绑定）的导出，不需要外部编译器的那部分：
// 没用状态和绑定的页面四种导出一个字不多；用了的页面各自多出什么；Flutter 导出成会跟着状态变的代码并写明。
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
  test('只有页面级的普通变量、哪儿都没绑：走老路，不多出状态文件和绑定运行代码', () {
    final doc = LcDocument.starter('我的小站');
    doc.logic.variables.add(LcVariable(name: 'n', type: 'number', initial: 0));
    final files = allExportFiles(LcDocument.parse(doc.encode()));
    expect(files.keys.where((k) => k.contains('lc-state')), isEmpty);
    for (final e in files.entries) {
      expect(e.value, isNot(contains('lcShared')), reason: e.key);
    }
  });

  test('建了项目级状态（还没绑）：Vue / React 多出 lc-state.js——积木随时可能读写它', () {
    final doc = LcDocument.starter('我的小站');
    lcEditProjectStates(doc, (list) => list.add(LcVariable(name: 'user', type: 'text', initial: '小塔塔')));
    final files = allExportFiles(doc);
    expect(files.keys, containsAll(['vue/lc-state.js', 'react/lc-state.js']));
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

  // 第四轮 B1 起 Flutter 导出不再把绑定按初值冻住：导出的是会跟着状态变的界面（真渲染、改状态在 lowcode_dart_live_test.dart）。
  test('Flutter：绑定导出成会跟着状态变的代码——状态是字段，文字读状态，重复是 for，条件是 if；文件头写明', () {
    final dart = allExportFiles(bindSample())['flutter/page.dart']!;
    expect(dart, contains('// 状态与绑定：状态是页面 State 类里 s_ 开头的字段'));
    expect(dart, isNot(contains('按初值定了下来')));
    expect(dart, contains('Object? s_count = 0;'));
    expect(dart, contains("static Object? user = '小塔塔';"), reason: '项目级状态在 LcAppState 里');
    expect(dart, contains("_lcText('你好，') + _lcText(LcAppState.user)"));
    expect(dart, isNot(contains("'你好，小塔塔'")), reason: '不再写死算好的文字');
    expect(dart, contains('for (final (v_i, v_it) in _lcList(LcAppState.cart).indexed)'), reason: '重复');
    expect(dart, contains("if (_lcBool((_lcNum(s_count) >= _lcNum(3)))) Text(\n                    '点够三次了'"), reason: '存在条件：条件写进代码，不是按初值去掉');
    expect(dart, contains('if (_lcBool(!_lcEq(s_keyword, \'\'))) Text('), reason: '显示条件');
    expect(dart, contains('(_lcBool(!_lcBool(s_agree)) ? '), reason: '“提交”的禁用跟着 agree 变：禁用的、没禁用的各一份');
    expect(dart, contains('onPressed: null'));
  });

  test('Flutter：列表是空的→出“空的时候”那句话（运行时判断）；重复不再有 200 份的上限', () {
    final json = bindSampleJson();
    final state = (json['state']! as List).cast<Map<String, Object?>>();
    state.firstWhere((s) => s['name'] == 'cart')['initial'] = <Object?>[];
    var dart = allExportFiles(LcDocument.parse(_enc(json)))['flutter/page.dart']!;
    expect(dart, contains("if (_lcList(LcAppState.cart).isEmpty) Text('购物车是空的')"));
    expect(dart, isNot(contains('苹果')));
    expect(dart, contains('static Object? cart = <Object?>[];'));

    state.firstWhere((s) => s['name'] == 'cart')['initial'] = [
      for (var i = 0; i < 260; i++) {'id': 'k$i', 'name': '货$i', 'price': 1},
    ];
    dart = allExportFiles(LcDocument.parse(_enc(json)))['flutter/page.dart']!;
    expect(dart, contains("'name': '货259'"), reason: '初值原样写进状态，有几项运行时就画几项');
    expect('for (final (v_i, v_it)'.allMatches(dart).length, 1, reason: '重复只写一份模板');
  });

  test('自定义组件定义里的绑定：四种导出都起作用（第四轮 B2 起 Vue / React 也把这种实例摊开进页面）', () {
    LcDocument make(bool bound) {
      final doc = LcDocument.starter('我的小站');
      doc.logic.variables.add(LcVariable(name: 'who', type: 'text', initial: '小塔塔'));
      final inner = LcNode(id: 'ct', type: 'text', props: {'text': '组件里的字'});
      if (bound) lcSetData(inner, 'text', lcSrcVar('who'));
      doc.components.add(
        LcComponentDef(
          id: 'c1',
          name: '卡片',
          root: LcNode(id: 'cr', type: 'column', children: [inner]),
        ),
      );
      doc.root.children.add(LcNode(id: 'inst', type: 'component', props: {'ref': 'c1'}));
      return doc;
    }

    final plain = allExportFiles(make(false)), bound = allExportFiles(make(true));
    final changed = [
      for (final k in bound.keys)
        if (bound[k] != plain[k]) k,
    ];
    expect(changed, ['html/index.html', 'html/logic.js', 'vue/LcPage.vue', 'react/LcPage.jsx', 'flutter/page.dart'], reason: '变了的文件');
    expect(bound['vue/LcPage.vue'], contains('小塔塔'));
    expect(bound['react/LcPage.jsx'], contains('小塔塔'));
    expect(bound['html/index.html'], contains('小塔塔'));
    expect(bound['flutter/page.dart'], contains("'小塔塔'"));
  });

  test('绑定字段写坏了：导出不崩，照没绑的出', () {
    final doc = LcDocument.starter('我的小站');
    doc.find('n1')!.more[kLcData] = {
      'text': 7,
      'nope': {'from': 'var'},
    };
    doc.find('n2')!.more[kLcRepeat] = 'x';
    doc.find('n3')!.more[kLcShowIf] = [1, 2];
    final files = allExportFiles(doc);
    expect(files['html/index.html'], contains('<'));
    expect(files['flutter/page.dart'], contains('class '));
  });
}

String _enc(Map<String, Object?> json) => LcDocument.parse(_json(json)).encode();
String _json(Object? v) => const JsonEncoder().convert(v);
