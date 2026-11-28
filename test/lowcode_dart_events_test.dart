// 第四轮 B6：Flutter 导出跟上——组件事件接的动作写到控件身上（步进器加减、图标按钮、可选标签条点得动）、
// 变体生效（网格选列数、图标按钮的样子）、竖着的滚动区真的能滚、链接有下划线；导不出的写在文件开头。
// 检入的样本和导出器当前输出逐字节一致，样本真装进界面点一遍。
import 'dart:io';

// 导出的页面用的是 Flutter 自带的那套 Material（别人的工程里没有我们的 material_ui）：这里也得用它来装。
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/lowcode/comp_lib_builtin.dart';
import 'package:lopicode/lowcode/export_dart.dart';
import 'package:lopicode/lowcode/model.dart';

import 'generated/builtin_p1_page.dart';
import 'generated/comp_event_page.dart';
import 'support/builtin_p1_sample.dart';
import 'support/comp_event_samples.dart';
import 'support/comp_samples.dart';
import 'support/page_front_samples.dart';

Future<void> _show(WidgetTester tester, Widget page, [double width = 390]) async {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: page));
  await tester.pump();
  expect(tester.takeException(), isNull);
}

/// 一页、一个状态 n、一个内置组件的实例（[more] 是实例上另带的东西）。
LcDocument _one(String builtin, {Map<String, Object?> more = const {}, List<Object?> children = const [], bool bound = true, List<Object?> extra = const []}) {
  final doc = LcDocument.fromJson(
    <String, Object?>{
      'version': 3,
      'title': 'One',
      'logic': {
        'variables': [
          {'name': 'n', 'type': 'number', 'initial': 0},
        ],
      },
      'root': cn('root', 'page', {}, [
        if (bound)
          cn(
            'nText',
            'text',
            {'text': ''},
            [],
            {
              'data': {'text': cFrom('n')},
            },
          ),
        cn('x', 'component', {'ref': lcBuiltinDefId(builtin)}, children, more),
        ...extra,
      ]),
    }.cast<String, dynamic>(),
  );
  lcEnsureBuiltin(doc, lcBuiltinDefId(builtin));
  return LcDocument.parse(doc.encode());
}

Map<String, Object?> _on(String event, List<Object?> body) => {
  'on': {event: body},
};

void main() {
  test('检入的样本和导出器当前的输出逐字节一致', () {
    const hint = '导出器改了：运行 dart run tool/gen_sample_export.dart 重新生成';
    expect(File('test/generated/builtin_p1_page.dart').readAsStringSync(), exportDart(builtinP1Doc(), className: 'BuiltinP1Page'), reason: hint);
    expect(File('test/generated/comp_event_page.dart').readAsStringSync(), exportDart(compEventDoc(), className: 'CompEventPage'), reason: hint);
  });

  group('六个内置组件的样例页真装进界面', () {
    testWidgets('步进器：加减点得动，页面状态跟着变，到边上按钮禁用', (tester) async {
      await _show(tester, const BuiltinP1Page());
      expect(find.text('数量 3'), findsOneWidget);
      await tester.tap(find.text('+'));
      await tester.pump();
      expect(find.text('数量 5'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, '+')).onPressed, isNull, reason: '到最大了，加号禁用');
      await tester.tap(find.text('−'));
      await tester.pump();
      await tester.tap(find.text('−'));
      await tester.pump();
      expect(find.text('数量 1'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, '−')).onPressed, isNull, reason: '到最小了，减号禁用');
      expect(tester.state<BuiltinP1PageState>(find.byType(BuiltinP1Page)).s_n, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('图标按钮：点了页面上的数加 1；选的“描边”样子生效（底色透明）', (tester) async {
      await _show(tester, const BuiltinP1Page());
      expect(find.text('点了 0 次'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.star));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.star));
      await tester.pump();
      expect(find.text('点了 2 次'), findsOneWidget);
      final box = tester.widget<Container>(find.ancestor(of: find.byIcon(Icons.star), matching: find.byType(Container)).first);
      expect((box.decoration! as BoxDecoration).color, const Color(0x00000000));
    });

    testWidgets('网格：选了 3 列，三个格子排在同一行；滚动区是一个能滚的框；链接有下划线，点了去“更多”页', (tester) async {
      await _show(tester, const BuiltinP1Page());
      final ys = {
        for (final i in [1, 2, 3]) tester.getTopLeft(find.text('格 $i')).dy,
      };
      expect(ys, hasLength(1), reason: '三列：三个格子在同一行');
      final xs = [
        for (final i in [1, 2, 3]) tester.getTopLeft(find.text('格 $i')).dx,
      ];
      expect(xs[0] < xs[1] && xs[1] < xs[2], isTrue);
      // 页面本身是一个能滚的，滚动区是第二个：它在 200 高的框里。
      final inner = find.ancestor(of: find.text('滚动区里的字'), matching: find.byType(SingleChildScrollView));
      expect(inner, findsNWidgets(2));
      expect(tester.getSize(inner.first).height, 200);
      expect(tester.widget<Text>(find.text('去更多')).style!.decoration, TextDecoration.underline);
      await tester.tap(find.text('去更多'));
      await tester.pumpAndSettle();
      expect(find.text('这是更多页'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('平板宽（800）也装得进去', (tester) async {
      await _show(tester, const BuiltinP1Page(), 800);
      expect(find.text('数量 3'), findsOneWidget);
    });
  });

  group('事件带数据', () {
    testWidgets('加量按钮：带的是组件属性；两个实例各带各的', (tester) async {
      await _show(tester, const CompEventPage());
      expect(find.text('拿到 0'), findsOneWidget);
      await tester.tap(find.text('加').first);
      await tester.pump();
      expect(find.text('拿到 5'), findsOneWidget);
      await tester.tap(find.text('加').last);
      await tester.pump();
      expect(find.text('拿到 7'), findsOneWidget);
    });

    testWidgets('可选标签条：带的是“重复”带出的那一项——点哪个，页面状态就是哪个', (tester) async {
      await _show(tester, const CompEventPage());
      expect(find.text('现在选的：蔬菜'), findsOneWidget);
      await tester.tap(find.text('零食'));
      await tester.pump();
      expect(find.text('现在选的：零食'), findsOneWidget);
      await tester.tap(find.text('水果'));
      await tester.pump();
      expect(find.text('现在选的：水果'), findsOneWidget);
      expect(tester.state<CompEventPageState>(find.byType(CompEventPage)).s_cur, '水果');
      expect(tester.takeException(), isNull);
    });
  });

  group('导出的文字', () {
    test('网格：不选是 2 列，选“4 列”是 4 列', () {
      List<Object?> cells() => [
        for (final i in [1, 2]) cn('g$i', 'text', {'text': '格 $i'}),
      ];
      expect(exportDart(_one('grid', children: cells())), contains('// 网格：2 列等宽'));
      final four = exportDart(
        _one(
          'grid',
          children: cells(),
          more: {
            'variant': {'cols': 'c4'},
          },
        ),
      );
      expect(four, contains('// 网格：4 列等宽'));
      expect(four, isNot(contains('// 网格：2 列等宽')));
    });

    test('页面上一个绑定都没有，只放了一个选了变体的图标按钮：变体照样生效（走会动的那一路）', () {
      final code = exportDart(
        _one(
          'iconButton',
          bound: false,
          more: {
            'variant': {'look': 'plain'},
          },
        ),
      );
      expect(code, contains('Color(0x00000000)'));
      expect(code, isNot(contains('Color(0xFFEEF3F5)')), reason: '原来的灰底被变体换掉了');
    });

    test('弹提示、打开弹窗、如果：都写到控件身上，用到的小函数带进文件', () {
      final code = exportDart(
        _one(
          'iconButton',
          more: _on('tap', [
            {
              'op': 'if',
              'args': {'cond': cBin('<', cVar('n'), cNum(3))},
              'body': [
                {
                  'op': 'changeVar',
                  'args': {'name': 'n', 'by': cNum(1)},
                },
              ],
              'else': [
                {
                  'op': 'alert',
                  'args': {'message': cText("够了 'x' \$y")},
                },
                {
                  'op': 'setProp',
                  'args': {
                    'node': 'dlg',
                    'prop': 'visible',
                    'value': {'e': 'bool', 'v': true},
                  },
                },
              ],
            },
          ]),
          extra: [
            cn('dlg', 'dialog', {'title': '提示', 'text': '到 3 了'}),
          ],
        ),
      );
      expect(code, contains('onTap: () { if (_lcBool((_lcNum(s_n) < _lcNum(3)))) { update(() => s_n = _lcNum((_lcNum(s_n) + _lcNum(1)))); } else { _lcAlert(context, _lcText('));
      expect(code, contains(r"'够了 \'x\' \$y'"));
      expect(code, contains('showDialog_dlg(context); }'));
      expect(code, contains('void _lcAlert(BuildContext context, String message)'));
      expect(code, contains('组件事件接的动作导出了'));
    });

    test('导不出的积木（打开网址）：整条不导出，文件开头说一句；只有一页时“去页面”也一样', () {
      for (final body in [
        [
          {
            'op': 'changeVar',
            'args': {'name': 'n', 'by': cNum(1)},
          },
          {
            'op': 'navigate',
            'args': {'url': cText('https://example.com')},
          },
        ],
        [
          {
            'op': 'goPage',
            'args': {'page': 'nowhere'},
          },
        ],
      ]) {
        final code = exportDart(_one('iconButton', more: _on('tap', body)));
        expect(code, contains('有的组件事件接的动作'));
        expect(code, isNot(contains('onTap:')));
        expect(code, isNot(contains('s_n = _lcNum((')), reason: '半条也不导出');
      }
    });

    test('横着滚的滚动区：导不出成能滚的，文件开头说一句', () {
      final code = exportDart(
        _one(
          'scroll',
          children: [
            cn('s1', 'text', {'text': '字'}),
          ],
          more: {
            'variant': {'dir': 'row'},
          },
        ),
      );
      expect(code, contains('横着滚的'));
      expect(RegExp('SingleChildScrollView').allMatches(code).length, 1, reason: '只有页面自己那一个');
    });

    test('页面自己的积木逻辑照旧不导出（按钮还是空的）', () {
      final code = exportDart(compUserDoc([productCardDef()]));
      // rename 那个按钮的处理是页面自己的：不导出。
      expect(code, isNot(contains("s_apple = _lcText('红苹果')")));
      expect(code, contains('onPressed: () {}'));
      // 卡片里的“加入购物车”是组件事件接的动作：导出了。
      expect(code, contains('update(() => s_cart = _lcNum((_lcNum(s_cart) + _lcNum(1))))'));
      expect(code, contains('update(() => s_cart = _lcNum((_lcNum(s_cart) + _lcNum(10))))'));
    });

    test('走新页面逻辑的页面：导出不报错，文件开头写明逻辑不导出；旧页面没有这句', () {
      final code = exportDart(frontSampleCore());
      expect(code, contains(kDartFrontNote));
      expect(code, contains('class '));
      expect(exportDart(builtinP1Doc()), isNot(contains('新的页面逻辑')));
    });
  });
}
