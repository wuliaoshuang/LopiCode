// 页面逻辑的两处小缺口（积木第 5 版·第四轮·A3b 第 8 件）：
// 1 去页面：那一页把带来的参数“当成某类型用 / 标上类型”了，这边带的单个参数类型不对也要拦（以前只拦“没带”和“整个不是字典”）；
// 2 “当〔组件实例〕发出〔事件〕”：控件下拉只列组件实例，事件名从这个实例真有的事件里挑（以前是手填）。第 2 条是手指一步步点出来的。
//   LOPI_SHOTS=1 flutter test --no-pub test/lowcode_front_gaps_test.dart   # 截图写到 ../preview/front/a3b/
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/backend/front_doc.dart';
import 'package:lopicode/lowcode/front_check.dart';
import 'package:lopicode/lowcode/logic_gate.dart';
import 'package:lopicode/lowcode/model.dart';

import 'support/backend_lang_blocks.dart';
import 'support/front_ui.dart';
import 'support/harness.dart';
import 'support/lowcode_builder.dart';
import 'support/page_front_samples.dart';

J _typed(String kind, String name, String type) => ex(kind, {
  'x': ex(pg('pageParam'), {'name': tx(name)}),
  'to': type,
});

/// 详情页：开工时把带来的参数照 [reads] 读出来写到字上。
J _detail(List<J> reads) => {
  'id': 'detail',
  'title': 'Detail',
  'root': node('root', 'page', const {}, [txt('got')]),
  'logic': {
    'variables': <J>[],
    'front': frontDoc(
      hats: [
        hat('h1', 'onMounted', [for (final r in reads) show('got', toText(r))]),
      ],
    ),
  },
};

LcDocument _home(J params, J detail, {List<J> variables = const []}) {
  final doc = LcDocument.parse(
    jsonEncode({
      'version': 3,
      'id': 'home',
      'title': 'Home',
      'root': node('root', 'page', const {}, [btn('b1', '去'), txt('t1')]),
      'logic': {
        'variables': variables,
        'front': frontDoc(
          hats: [
            onClick('h1', 'b1', [
              blk(pg('goPageWith'), {'page': 'detail', 'params': params}),
            ]),
          ],
        ),
      },
      'pages': [detail],
    }),
  );
  for (final p in doc.pages) {
    final front = lcFrontOf(p.logic);
    if (front != null) lcFrontStore(p.logic, front);
  }
  return doc;
}

List<String> _issues(LcDocument doc) => [for (final i in lcFrontPageIssues(doc, doc.page)) i.problem];

const J _cardDef = {
  'id': 'c1',
  'name': '计数卡',
  'events': [
    {
      'name': 'picked',
      'label': '选中了',
      'params': [
        {'name': 'count', 'type': 'number'},
      ],
    },
    {'name': 'closed', 'label': '关掉了', 'params': <J>[]},
  ],
  'root': {
    'id': 'cr',
    'type': 'column',
    'props': <String, dynamic>{},
    'children': [
      {
        'id': 'cb',
        'type': 'button',
        'props': {'text': '选'},
      },
    ],
  },
};

void main() {
  setUpAll(() async => lbFontsLoaded = await loadRealFonts());

  group('去页面：单个参数的类型', () {
    test('那一页说了每个参数要什么类型：当成 / 标上都算；说了两种的、任意的不算', () {
      final d = LcDocument.parse(
        jsonEncode({
          'version': 3,
          ..._detail([_typed('castTo', 'n', '整数'), _typed('ascribe', 'who', '文字'), _typed('castTo', 'x', '整数'), _typed('castTo', 'x', '文字'), _typed('ascribe', 'any', '任意')]),
        }),
      );
      expect(lcFrontParamTypes(lcFrontOf(d.logic)!), {'n': '整数', 'who': '文字'});
    });

    test('那一页把 n 当成整数用，这边带了文字：拦下，说得出是哪个参数、要什么类型；导出前的检查也数得出', () {
      final doc = _home(dc({'n': tx('三'), 'who': tx('塔')}), _detail([_typed('castTo', 'n', '整数'), _typed('ascribe', 'who', '文字')]));
      final issues = _issues(doc);
      expect(issues, hasLength(1));
      expect(issues.single, allOf(contains('Detail'), contains('带来的参数 n'), contains('整数')));
      expect(lcLogicErrorCount(doc), greaterThan(0));
      // 查的时候临时套的那一层没有留在文档里
      expect(jsonEncode(lcFrontOf(doc.logic)!.toJson()), isNot(contains('ascribe')));
    });

    test('带对了（整数、文字）、带的是说不准类型的（任意）：都不拦', () {
      final ok = _home(dc({'n': nm(3), 'who': tx('塔')}), _detail([_typed('castTo', 'n', '整数'), _typed('ascribe', 'who', '文字')]));
      expect(_issues(ok), isEmpty);
      expect(lcLogicErrorCount(ok), 0);
      final loose = _home(
        dc({
          'n': ex(pg('pageParam'), {'name': tx('上一页给的')}),
        }),
        _detail([_typed('castTo', 'n', '整数')]),
      );
      expect(_issues(loose), isEmpty);
    });

    test('那一页没说类型：和以前一样只查带没带', () {
      final doc = _home(
        dc({'n': tx('三')}),
        _detail([
          ex(pg('pageParam'), {'name': tx('n')}),
        ]),
      );
      expect(_issues(doc), isEmpty);
    });
  });

  testWidgets('“当组件发出事件”：控件下拉只列组件实例，事件从这个实例真有的事件里挑（一步步点）', (tester) async {
    final doc = LcDocument.parse(
      jsonEncode({
        'version': 3,
        'title': 'Front',
        'root': node('root', 'page', const {}, [
          btn('b1', '普通按钮'),
          txt('t1'),
          node('i1', 'component', {'ref': 'c1'}),
        ]),
        'logic': {'variables': <J>[], 'front': frontDoc()},
        'components': [_cardDef],
      }),
    );
    lcFrontStore(doc.logic, lcFrontOf(doc.logic)!);
    await fuOpen(tester, doc);
    // 1 积木盒“事件”页 → 把“当组件发出事件”拖到画布
    await fuDropHat(tester, 'lib:lopi/page:事件', 'hat-libhat:lib:lopi/page#onEmit', const Offset(40, 260));
    final host = fuHost(tester);
    final tree = host.doc.hats.single;
    await fuShow(tester, tree.id);
    // 2 点帽子上第一格：只有组件实例，普通按钮和文字不在里面
    expect([for (final o in host.hatSlotOptions(tree, 'node')) o.value], ['i1']);
    await tester.tapAt(fuHatSlot(tester, tree.id, 'node'));
    await tester.pumpAndSettle();
    expect(fk('bk-menu-i1'), findsOneWidget);
    expect(fk('bk-menu-b1'), findsNothing);
    expect(fk('bk-menu-t1'), findsNothing);
    await fuShot(tester, 'gaps-1-instances');
    await tester.tap(fk('bk-menu-i1'));
    await tester.pumpAndSettle();
    // 3 点第二格：这个组件定的两个事件
    expect([for (final o in host.hatSlotOptions(host.doc.hats.single, 'event')) o.value], ['picked', 'closed']);
    await tester.tapAt(fuHatSlot(tester, tree.id, 'event'));
    await tester.pumpAndSettle();
    expect(fk('bk-menu-picked'), findsOneWidget);
    expect(fk('bk-menu-closed'), findsOneWidget);
    await fuShot(tester, 'gaps-2-events');
    await tester.tap(fk('bk-menu-picked'));
    await tester.pumpAndSettle();
    expect(host.doc.hats.single.args, {'node': 'i1', 'event': 'picked'});
    expect(fuErrors(tester), isEmpty);
    await fuShot(tester, 'gaps-3-done');
  });
}
