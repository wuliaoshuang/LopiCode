// 第四轮 B7：步进器开箱即用（不用页面接线）、纯网页“重复”里的事件带上这一项、Flutter 多认三样动作（重复几次、等一会儿、打印）。
// 前半（不依赖外部环境）：补线的规矩；导出里各写成什么；不需要补的页面导出一个字不变。
// 中间：Flutter 检入样本和导出器一致，真装进界面一步步点。
// 后半（开发机才有环境，找不到明确跳过）：三种网页导出真编译 0 错 0 警告；Node + jsdom 真跑。
// 没覆盖的：真浏览器、真手机。
@Tags(['external'])
library;

import 'dart:io';

// 导出的页面用的是 Flutter 自带的那套 Material：这里也得用它来装。
// ignore: deprecated_member_use
import 'package:flutter/material.dart' as m;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/lowcode/bind_model.dart';
import 'package:lopicode/lowcode/comp_lib_builtin.dart';
import 'package:lopicode/lowcode/comp_self_wire.dart';
import 'package:lopicode/lowcode/component_extras.dart';
import 'package:lopicode/lowcode/export_dart.dart';
import 'package:lopicode/lowcode/model.dart';

import 'generated/b7_live_page.dart';
import 'support/b7_live_sample.dart';
import 'support/bind_export_files.dart';
import 'support/builtin_p1_sample.dart';
import 'support/comp_event_samples.dart';
import 'support/comp_steps.dart';
import 'support/dev_tools.dart';

const _entry = {'html': 'index.html', 'vue': 'B7Live.vue', 'react': 'B7Live.jsx'};
const _label = {'html': '普通网页', 'vue': 'Vue 3', 'react': 'React'};

void main() {
  if (skipWithoutDom != false) {
    // ignore: avoid_print 跳过的原因要在测试输出里看得见
    print('【跳过】B7 样例的真编译 / 真跑：$skipWithoutDom');
  }

  group('步进器开箱即用：导出前补线', () {
    test('步进器的定义声明了“没人接就自己记着”', () {
      final doc = b7LiveDoc();
      final def = doc.component(lcBuiltinDefId('stepper'))!;
      final hold = lcHoldOf(def);
      expect(hold?.prop, 'value');
      expect(hold?.event, 'change');
      expect(lcHoldOf(doc.component('c6')!), isNull, reason: '别的组件没有');
    });

    test('没接线的：添一个状态（初值＝实例上填的值）、值绑上去、“改了”写回；每个实例各一个', () {
      final src = b7LiveDoc();
      final before = src.encode();
      final doc = lcSelfWired(src);
      expect(identical(doc, src), isFalse);
      expect(src.encode(), before, reason: '她的页面文件不动');
      final v = doc.logic.variables.firstWhere((x) => x.name == 'st1__value');
      expect(v.type, 'number');
      expect(v.initial, 3);
      final st1 = doc.find('st1')!;
      expect(lcDataExpr(st1, 'value'), {'e': 'var', 'name': 'st1__value'});
      expect(lcOnOf(st1)['change']!.single.op, 'setVar');
      expect(lcOnOf(st1)['change']!.single.args['name'], 'st1__value');
    });

    test('值绑了状态、没接“改了”的：写回那个状态，不添新状态', () {
      final doc = lcSelfWired(b7LiveDoc());
      expect(doc.logic.variables.any((x) => x.name == 'st2__value'), isFalse);
      expect(lcOnOf(doc.find('st2')!)['change']!.single.args['name'], 'n');
    });

    test('自己接了“改了”的：一概不动', () {
      final doc = lcSelfWired(b7LiveDoc());
      expect(doc.logic.variables.any((x) => x.name == 'st3__value'), isFalse);
      expect(lcOnOf(doc.find('st3')!)['change']!.single.args['name'], 'got');
      expect(lcDataExpr(doc.find('st3')!, 'value'), isNull);
    });

    test('不需要补的页面：交回原来那一份（导出一个字不变）', () {
      final a = builtinP1Doc(), b = compEventDoc();
      expect(identical(lcSelfWired(a), a), isTrue);
      expect(identical(lcSelfWired(b), b), isTrue);
    });

    test('放在“重复”里的步进器、值绑在式子上的：不补（照旧要自己接）', () {
      final src = b7LiveDoc();
      final st1 = src.find('st1')!;
      st1.more['repeat'] = {
        'list': {'from': 'var', 'name': 'tagList'},
        'item': 'it',
        'index': 'i',
      };
      final st2 = src.find('st2')!;
      st2.more['data'] = {
        'value': {
          'from': 'expr',
          'expr': {
            'e': 'bin',
            'op': '+',
            'l': {'e': 'var', 'name': 'n'},
            'r': {'e': 'num', 'v': 1},
          },
        },
      };
      final doc = lcSelfWired(LcDocument.parse(src.encode()));
      expect(lcOnOf(doc.find('st1')!)['change'], isNull);
      expect(lcOnOf(doc.find('st2')!)['change'], isNull);
    });
  });

  group('导出里各写成什么', () {
    test('纯网页：“重复”里的处理开头找到是哪一份，读的是那一份带的这一项；说明里不再说“拿不到是哪一项”', () {
      final all = allExportFiles(b7LiveDoc());
      final js = all['html/logic.js']!;
      expect(js, contains('const lcS = lcScopeAt(event);'));
      expect(js, contains('state.cur = lcText(lcS.it);'));
      expect(js, contains('el.lcS = sc;'));
      expect(js, contains('function lcScopeAt(event)'));
      expect(js, isNot(contains('没有声明的变量')));
      for (final k in all.keys.where((k) => k.startsWith('html/'))) {
        expect(all[k], isNot(contains('拿不到“是哪一项”')), reason: k);
      }
    });

    test('纯网页：处理不在“重复”里的页面，脚本里没有多出这几句', () {
      final js = allExportFiles(builtinP1Doc())['html/logic.js']!;
      expect(js, isNot(contains('lcScopeAt')));
      expect(js, isNot(contains('el.lcS')));
    });

    test('Flutter：重复几次、等一会儿、打印都写出来了；检入样本和导出器一致', () {
      final dart = exportDart(b7LiveDoc(), className: 'B7LivePage');
      expect(dart, contains('for (var lcI1 = 0, lcN1 = _lcNum('));
      expect(dart, contains('Future<void>.delayed(Duration(milliseconds: '));
      expect(dart, contains('if (!context.mounted) return;'));
      expect(dart, contains('debugPrint('));
      expect(dart, contains('s_st1__value'), reason: '没接线的步进器自己的状态');
      expect(dart, isNot(contains('没有导出，那个控件点了没反应')));
      expect(File('test/generated/b7_live_page.dart').readAsStringSync(), dart, reason: '导出器改了：运行 dart run tool/gen_sample_export.dart 重新生成');
    });
  });

  testWidgets('Flutter 真装进界面：没接线的步进器能加减；绑了状态的写回；标签点哪个选哪个；重复 3 次、等完再改', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final printed = <String>[];
    final old = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) => printed.add(message ?? '');
    addTearDown(() => debugPrint = old);
    await tester.pumpWidget(const m.MaterialApp(home: B7LivePage()));
    await tester.pump();
    expect(tester.takeException(), isNull);
    final plus = find.text('+'), minus = find.text('−');
    expect(plus, findsNWidgets(3));
    // st1：3 → 4 → 5（到最大，再点不动）→ 4
    expect(find.text('3'), findsOneWidget);
    await tester.tap(plus.at(0));
    await tester.pump();
    expect(find.text('4'), findsOneWidget);
    await tester.tap(plus.at(0));
    await tester.pump();
    expect(find.text('5'), findsOneWidget);
    await tester.tap(plus.at(0), warnIfMissed: false);
    await tester.pump();
    expect(find.text('5'), findsOneWidget, reason: '到最大了：加号禁用');
    await tester.tap(minus.at(0));
    await tester.pump();
    expect(find.text('4'), findsOneWidget);
    // st2：写回状态 n
    expect(find.text('数量 2'), findsOneWidget);
    await tester.tap(plus.at(1));
    await tester.pump();
    expect(find.text('数量 3'), findsOneWidget);
    // st3：自己接的线
    await tester.tap(plus.at(2));
    await tester.pump();
    expect(find.text('带来的是 8'), findsOneWidget);
    expect(find.text('7'), findsOneWidget, reason: '她自己接了线、没让数字跟着走：不替她记');
    // 标签条
    await tester.tap(find.text('零食'));
    await tester.pump();
    expect(find.text('现在选的：零食'), findsOneWidget);
    // 重复 3 次（一次加 5）、等 30 毫秒、打印
    expect(find.text('还没等'), findsOneWidget);
    await tester.tap(find.text('加'));
    await tester.pump();
    expect(find.text('k=15'), findsOneWidget);
    expect(find.text('还没等'), findsOneWidget, reason: '还没等完');
    expect(printed, contains('15'));
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.text('等完了'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Flutter：等着的时候页面关了，等完不再做（不报错）', (tester) async {
    await tester.pumpWidget(const m.MaterialApp(home: B7LivePage()));
    await tester.pump();
    await tester.tap(find.text('加'));
    await tester.pump();
    await tester.pumpWidget(const m.MaterialApp(home: SizedBox()));
    await tester.pump(const Duration(milliseconds: 80));
    expect(tester.takeException(), isNull);
  });

  group('三种网页导出真编译真跑', () {
    for (final kind in ['html', 'vue', 'react']) {
      final steps = kind == 'html' ? b7LiveSteps() : compFileSteps(b7LiveSteps(), b7LiveDefs());
      test('${_label[kind]}：真编译 0 错误 0 警告', () async {
        final r = await compileExport('compile_$kind.mjs', exportFilesOf(b7LiveDoc(), kind), _entry[kind]!);
        expect(r.errors, isEmpty, reason: r.raw);
        expect(r.warnings, isEmpty, reason: r.raw);
        expect(r.ok, isTrue);
      }, skip: skipWithoutDom);

      test('${_label[kind]}：真跑——步进器不接线能用；点哪个标签选哪个；重复 3 次、等完再改', () async {
        final r = await runInDom(kind, exportFilesOf(b7LiveDoc(), kind), _entry[kind]!, steps);
        expect(r.errors, isEmpty);
        expect(r.warnings, isEmpty);
        expect(r.done, steps.length);
        expect(r.ok, isTrue);
      }, skip: skipWithoutDom);
    }
  });
}
