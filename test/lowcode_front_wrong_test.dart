// 新的页面逻辑里“故意写错的”要在检查阶段被拦下（积木第 5 版·前端 1·下半）：
// “这一项”用在重复外面、去页面少带参数 / 参数类型不对 / 页面没了、帽子挂的控件没了、组件事件名不存在 / 挂的不是组件实例、
// 前端库用了后端的宿主接口、只给后端的库。拦下＝画布上标红（检查有错误）、导出前的检查数得出错误、导出的文件里这一页的逻辑不出。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/backend/backend_validate.dart';
import 'package:lopicode/backend/front_code.dart';
import 'package:lopicode/backend/front_doc.dart';
import 'package:lopicode/lang/lib_model.dart';
import 'package:lopicode/lowcode/front_check.dart';
import 'package:lopicode/lowcode/logic_gate.dart';
import 'package:lopicode/lowcode/model.dart';

import 'support/backend_lang_blocks.dart';
import 'support/bind_export_files.dart';
import 'support/lib_files.dart';
import 'support/lib_switches.dart';
import 'support/page_front_samples.dart';
import 'support/page_front_samples2.dart';

List<String> _pageIssues(LcDocument doc) => [for (final i in lcFrontPageIssues(doc, doc.page)) i.problem];

/// 被拦下：导出前的检查数得出错误；三种产物里这一页的逻辑都没出。
void _blocked(LcDocument doc) {
  expect(lcLogicErrorCount(doc), greaterThan(0));
  for (final kind in const ['html', 'vue', 'react']) {
    final all = exportFilesOf(doc, kind).values.join('\n');
    expect(all, contains('这一页的逻辑没有导出'), reason: kind);
    // 多页面时别的页照常出自己的逻辑，只有出错的这一页不出。
    if (doc.pages.length == 1) expect(all, isNot(contains('function lcProgram(lc, lcHost)')), reason: kind);
  }
}

/// 一页：一个不在重复里的按钮 b1、一个在重复里的按钮 rb、一段字 t1。
LcDocument _page(List<J> hats, {List<J> pages = const [], List<J> components = const [], List<J> extra = const []}) {
  final doc = LcDocument.parse(
    jsonEncode({
      'version': 3,
      'id': 'home',
      'title': 'Home',
      'root': node('root', 'page', const {}, [
        btn('b1', '外面'),
        txt('t1'),
        node(
          'row',
          'row',
          const {},
          [btn('rb', '里面')],
          {
            'repeat': {'list': fromVar('items'), 'item': 'it', 'index': 'i'},
          },
        ),
        ...extra,
      ]),
      'logic': {
        'variables': [
          {
            'name': 'items',
            'type': 'list',
            'initial': [
              {'name': '甲'},
            ],
          },
        ],
        'front': frontDoc(hats: hats),
      },
      if (components.isNotEmpty) 'components': components,
      if (pages.isNotEmpty) 'pages': pages,
    }),
  );
  for (final p in doc.pages) {
    final front = lcFrontOf(p.logic);
    if (front != null) lcFrontStore(p.logic, front);
  }
  return doc;
}

J _detail(List<J> hats) => {
  'id': 'detail',
  'title': 'Detail',
  'root': node('root', 'page', const {}, [txt('got')]),
  'logic': {'variables': <J>[], 'front': frontDoc(hats: hats)},
};

/// 详情页开工时读带来的参数 who。
J _detailReadsWho() => _detail([
  hat('h1', 'onMounted', [
    show(
      'got',
      ex(pg('oldText'), {
        'value': ex(pg('pageParam'), {'name': tx('who')}),
      }),
    ),
  ]),
]);

void main() {
  // 中途包：带手写代码的库的启用、自己的库直接用宿主接口默认都关着（rules.dart）；这里测的是开着时的样子，每条先打开、测完改回默认。
  libSwitchesOn();
  test('“这一项”“第几项”“这一项的…”用在不是重复出来的控件的事件里：拦下；用在重复里的照常', () {
    for (final e in [
      ex(pg('eventItem')),
      ex(pg('eventIndex')),
      ex(pg('eventItemField'), {'key': tx('name')}),
    ]) {
      final bad = _page([
        onClick('h1', 'b1', [
          show('t1', ex(pg('oldText'), {'value': e})),
        ]),
      ]);
      expect(_pageIssues(bad).single, contains('只能用在“重复”出来的控件的事件里'));
      _blocked(bad);
      final good = _page([
        onClick('h1', 'rb', [
          show('t1', ex(pg('oldText'), {'value': e})),
        ]),
      ]);
      expect(_pageIssues(good), isEmpty);
      expect(lcLogicErrorCount(good), 0);
    }
    // 页面一放上就做的帽子里也不行
    final mounted = _page([
      hat('h1', 'onMounted', [
        show('t1', ex(pg('oldText'), {'value': ex(pg('eventIndex'))})),
      ]),
    ]);
    expect(lcLogicErrorCount(mounted), greaterThan(0));
  });

  test('去页面：那一页要读的参数没带、带少了：拦下；带齐了照常', () {
    final plain = _page(
      [
        onClick('h1', 'b1', [
          blk(pg('goPage'), {'page': 'detail'}),
        ]),
      ],
      pages: [_detailReadsWho()],
    );
    expect(_pageIssues(plain).single, allOf(contains('Detail'), contains('who'), contains('没带')));
    _blocked(plain);

    final less = _page(
      [
        onClick('h1', 'b1', [
          blk(pg('goPageWith'), {
            'page': 'detail',
            'params': dc({'n': nm(1)}),
          }),
        ]),
      ],
      pages: [_detailReadsWho()],
    );
    expect(_pageIssues(less).single, contains('who'));
    _blocked(less);

    final full = _page(
      [
        onClick('h1', 'b1', [
          blk(pg('goPageWith'), {
            'page': 'detail',
            'params': dc({'who': tx('塔')}),
          }),
        ]),
      ],
      pages: [_detailReadsWho()],
    );
    expect(_pageIssues(full), isEmpty);
    expect(lcLogicErrorCount(full), 0);
  });

  test('去页面：参数不是字典（递了一个数字）——类型检查拦下', () {
    final doc = _page(
      [
        onClick('h1', 'b1', [
          blk(pg('goPageWith'), {'page': 'detail', 'params': nm(3)}),
        ]),
      ],
      pages: [_detail(const [])],
    );
    final front = lcFrontOf(doc.logic)!;
    final problems = [...validateBackend(front).where((i) => i.isError).map((i) => i.problem), ...lcFrontProgram(front).problems];
    expect(problems, isNotEmpty);
    _blocked(doc);
  });

  test('去页面：要去的页面已经删掉：拦下', () {
    final doc = _page([
      onClick('h1', 'b1', [
        blk(pg('goPage'), {'page': 'gone'}),
      ]),
    ]);
    expect(lcLogicErrorCount(doc), greaterThan(0));
    _blocked(doc);
  });

  test('帽子挂的控件不在这一页了：拦下', () {
    final doc = _page([
      onClick('h1', 'nope', [show('t1', tx('x'))]),
    ]);
    expect(_pageIssues(doc).single, contains('不在这一页了'));
    _blocked(doc);
  });

  group('组件事件（按线 B 第 6 期的格式：定义上的 events、定义里控件的 emit）', () {
    final def = {
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
      ],
      'root': node('cr', 'column', const {}, [
        node(
          'cb',
          'button',
          {'text': '选'},
          const [],
          {
            'emit': {
              'click': {
                'event': 'picked',
                'args': {'count': fromVar('n')},
              },
            },
          },
        ),
      ]),
    };
    final inst = node('i1', 'component', {'ref': 'c1'});
    J emitHat(String nodeId, String event, [List<J> body = const []]) => hat('h1', 'onEmit', body, args: {'node': nodeId, 'event': event});

    test('事件名对得上：没有问题；“事件带来的…”用在它下面也没有问题', () {
      final doc = _page(
        [
          emitHat('i1', 'picked', [
            show(
              't1',
              ex(pg('oldText'), {
                'value': ex(pg('emitData'), {'name': tx('count')}),
              }),
            ),
          ]),
        ],
        components: [def],
        extra: [inst],
      );
      expect(doc.component('c1'), isNotNull);
      expect(lcComponentEvents(doc.component('c1')!), {'picked'});
      expect(_pageIssues(doc), isEmpty);
      expect(lcLogicErrorCount(doc), 0);
      // 存出来再读回来，定义上的 events、控件上的 emit 都还在（这一版不认识的字段原样带着）
      final again = LcDocument.parse(doc.encode());
      expect(lcComponentEvents(again.component('c1')!), {'picked'});
    });

    test('事件名不存在：拦下，并说出它有哪些事件', () {
      final doc = _page([emitHat('i1', 'closed')], components: [def], extra: [inst]);
      expect(_pageIssues(doc).single, allOf(contains('计数卡'), contains('closed'), contains('picked')));
      _blocked(doc);
    });

    test('挂的不是组件实例：拦下', () {
      final doc = _page([emitHat('b1', 'picked')], components: [def], extra: [inst]);
      expect(_pageIssues(doc).single, contains('不是组件实例'));
      _blocked(doc);
    });

    test('“事件带来的…”用在别的帽子下面：拦下', () {
      final doc = _page(
        [
          onClick('h1', 'b1', [
            show(
              't1',
              ex(pg('oldText'), {
                'value': ex(pg('emitData'), {'name': tx('count')}),
              }),
            ),
          ]),
        ],
        components: [def],
        extra: [inst],
      );
      expect(_pageIssues(doc).single, contains('只能用在'));
      _blocked(doc);
    });
  });

  test('只给前端的库用了后端才有的宿主接口：读库这一步就拒绝；硬启用也出不了代码', () {
    final bad = badFrontKit();
    expect(bad.ok, isFalse);
    expect(bad.problems.single, contains('后端的宿主接口'));
    final doc = withLibs(
      frontPage(
        [btn('b1', '看'), txt('t1')],
        const [],
        frontDoc(
          uses: [
            {'id': 'test/bad-front'},
          ],
          hats: [
            onClick('h1', 'b1', [
              show('t1', ex('lib:test/bad-front#peek', {'name': tx('HOME')})),
            ]),
          ],
        ),
      ),
      [bad],
    );
    _blocked(doc);
  });

  test('新的页面逻辑启用只给后端的库：拦下', () {
    final backend = libRead(libFilesFromDir('test/fixtures/libs/demo-kit'), builtin: false);
    expect(backend.side, LibSide.backend);
    final doc = withLibs(
      frontPage(
        [btn('b1', '看'), txt('t1')],
        const [],
        frontDoc(
          uses: [
            {'id': 'demo/kit'},
          ],
          hats: [
            onClick('h1', 'b1', [show('t1', tx('x'))]),
          ],
        ),
      ),
      [backend],
    );
    _blocked(doc);
  });
}
