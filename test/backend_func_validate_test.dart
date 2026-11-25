// 后端积木第 4 版·第 2 阶段：函数和“我的积木”的校验（L01/L02/L03/L09/L14/L15/S11、G03、B01–B09）接进后端页以后的样子。
// 每条规则命中和不命中、画在哪一块上；警告不拦生成；带口值里的路径每次现算。
import 'package:flutter_test/flutter_test.dart';
import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/backend/backend_validate.dart';
import 'package:lopicode/lowcode/logic_model.dart';

import 'support/backend_func_blocks.dart';
import 'support/backend_lang_blocks.dart';

BeDocument docOf(List<J> fns, List<J> body, {String path = '/x'}) => parseLangBlocksDocument({
  ...langBlocksDocumentJson([route('r1', 'GET', path, body)]),
  'functions': fns,
});
final J ok = json(dc({'ok': yes()}));

/// 校验结果：`规则 E|W 哪一串`。
List<String> found(BeDocument doc) => [
  for (final i in validateBackend(doc, languages: ['node'])) '${i.rule} ${i.isError ? 'E' : 'W'} ${i.handlerId}',
];
List<LcLogicIssue> issuesOf(BeDocument doc, String rule) => [
  for (final i in validateBackend(doc, languages: ['node']))
    if (i.rule == rule) i,
];

void main() {
  group('校验', () {
    test('样本文档没有错误；警告不拦生成', () {
      final doc = funcBlocksDocument();
      expect(backendErrors(doc), isEmpty);
      final warn = docOf(
        [
          fnDef('f1', '甲', [par('a')], [ret(nm(1))]),
          fnDef('f2', '乙', [], []),
        ],
        [
          json(call('f1', {'a': nm(1)})),
        ],
      );
      expect(found(warn), ['L14 W f1', 'L14 W f2']);
      expect(issuesOf(warn, 'L14').map((i) => i.problem), ['参数 a 没有用到', '这块积木定义了但没有人用']);
      expect(backendErrors(warn), isEmpty);
    });

    test('L01：调用 / “这块积木本身”指向的定义不在了 → 错误，画在那一块上', () {
      final doc = docOf([], [callS('f9'), let('v', call('f8')), json(ref('f7'))]);
      final l01 = issuesOf(doc, 'L01');
      expect([for (final i in l01) (i.isError, i.handlerId, i.path.single.index, i.arg)], [(true, 'r1', 0, null), (true, 'r1', 1, 'value'), (true, 'r1', 2, 'value')]);
      expect(l01.first.problem, contains('已经不在了'));
      expect(l01.first.advice, isNotEmpty);
      expect(issuesOf(docOf([fnDef('f9', '甲', [], [])], [callS('f9'), ok]), 'L01'), isEmpty);
    });

    test('L02：“剩下的全收”不是最后一个 → 错误，画在定义的帽子上', () {
      final doc = docOf(
        [
          fnDef(
            'f1',
            '甲',
            [par('a'), par('r', rest: true), par('b')],
            [
              ret(cat([pm('a'), pm('b'), pm('r')])),
            ],
          ),
        ],
        [
          json(call('f1', {'a': nm(1), 'b': nm(2)})),
        ],
      );
      final i = issuesOf(doc, 'L02').single;
      expect((i.isError, i.handlerId, i.path.length), (true, 'f1', 0));
      expect(i.problem, contains('只能放在最后一个'));
      expect(issuesOf(funcBlocksDocument(), 'L02'), isEmpty);
    });

    test('L03：接口里直接放“返回 (值)”→ 错误；匿名函数里的不算；把不交回结果的积木当值用 → 警告（旧积木的格子里也查得到）', () {
      final doc = docOf(
        [
          fnDef('f1', '甲', [], [
            blk('log', {'value': nm(1)}),
          ]),
        ],
        [
          let('g', lam([], [ret(nm(1))])),
          let('v', call('f1')),
          json(call('f1')),
          ret(nm(1)),
        ],
      );
      final l03 = issuesOf(doc, 'L03');
      expect([for (final i in l03) (i.isError, i.path.single.index)], [(false, 1), (false, 2), (true, 3)]);
      expect(l03.first.problem, contains('不交回结果'));
      expect(l03.last.problem, contains('只能放在“定义”下面或匿名函数里'));
      expect(
        issuesOf(
          docOf(
            [
              fnDef('f1', '甲', [], [ret(nm(1))]),
            ],
            [json(call('f1'))],
          ),
          'L03',
        ),
        isEmpty,
      );
      expect(issuesOf(docOf([fnDef('f1', '甲', [], [])], [callS('f1'), ok]), 'L03'), isEmpty, reason: '单独成句不算当值用');
    });

    test('L09：定义里新建了两个同名的变量、和参数重名；两块积木重名（含只差大小写）；匿名函数的参数重名', () {
      final doc = docOf(
        [
          fnDef(
            'f1',
            '甲',
            [par('a')],
            [
              let('x', nm(1)),
              let('x', nm(2)),
              let('a', nm(3)),
              ret(cat([vr('x'), pm('a')])),
            ],
          ),
          fnDef('f2', '甲', [], []),
          fnDef('f3', 'A b', [], []),
          fnDef('f4', 'a_B', [], []),
        ],
        [
          callS('f1', {'a': nm(1)}),
          callS('f2'),
          callS('f3'),
          callS('f4'),
          let('h', lam(['x', 'x'], [ret(pm('x'))])),
          ok,
        ],
      );
      expect([
        for (final i in issuesOf(doc, 'L09')) (i.handlerId, i.path.isEmpty ? -1 : i.path.first.index, i.isError),
      ], containsAll([('f1', 1, true), ('f1', 2, true), ('f2', -1, true), ('f4', -1, true), ('r1', 4, true)]));
      expect(issuesOf(funcBlocksDocument(), 'L09'), isEmpty);
    });

    test('L15：定义 / 匿名函数里放了“返回响应”“请求别的网址”→ 错误，画在那一块上；定义里读了请求 → 错误，画在帽子上', () {
      final doc = docOf(
        [
          fnDef('f1', '甲', [], [
            blk('fetch', {'url': tx('http://a.b/c'), 'method': 'GET'}),
            json(nm(1)),
          ]),
          fnDef('f2', '乙', [], [
            blk('log', {'value': q('n')}),
          ]),
        ],
        [
          let('g', lam([], [json(nm(2))])),
          callS('f1'),
          callS('f2'),
          ok,
        ],
      );
      final l15 = issuesOf(doc, 'L15');
      expect([for (final i in l15) (i.handlerId, i.path.length, i.isError)], containsAll([('r1', 2, true), ('f1', 1, true), ('f2', 0, true)]));
      expect(l15.where((i) => i.handlerId == 'f1'), hasLength(2));
      expect(l15.firstWhere((i) => i.handlerId == 'f2').problem, allOf(contains('这次请求'), isNot(contains('req'))));
      expect(l15.firstWhere((i) => i.handlerId == 'r1').problem, contains('匿名函数'));
      // 接口里的匿名函数读请求没问题（它看得见外面的请求）。
      expect(
        issuesOf(
          docOf([], [
            let('g', lam([], [ret(q('n'))])),
            json(callV(vr('g'), [])),
          ]),
          'L15',
        ),
        isEmpty,
      );
    });

    test('S11：有的走法交回了值、有的没有 → 警告；G03：定义里用了接口的变量、读了没有的参数 → 错误', () {
      final doc = docOf(
        [
          fnDef(
            'f1',
            '甲',
            [par('a')],
            [
              iff(pm('a'), [ret(nm(1))], noElse: true),
            ],
          ),
          fnDef('f2', '乙', [], [
            setv('total', nm(1)),
            ret(cat([vr('total'), pm('zz')])),
          ]),
        ],
        [
          json(
            ls([
              call('f1', {'a': nm(1)}),
              call('f2'),
            ]),
          ),
        ],
      );
      final s11 = issuesOf(doc, 'S11').single;
      expect((s11.isError, s11.handlerId), (false, 'f1'));
      final g03 = issuesOf(doc, 'G03');
      expect([for (final i in g03) (i.handlerId, i.path.single.index, i.isError)], [('f2', 0, true), ('f2', 1, true), ('f2', 1, true)]);
      expect(g03.first.problem, contains('自定义积木里看不见'));
      expect(g03.last.problem, contains('没有叫“zz”的参数'));
    });

    test('B01–B09：外观不对画在定义的帽子上；B09 是警告，其余是错误', () {
      J look(String id, Map<String, Object?> l, [List<J> params = const [], List<J> body = const []]) => {'id': id, 'look': l, 'params': params, 'body': body};
      final doc = docOf(
        [
          look('f1', {'name': '甲', 'template': '做 {a} {zz} {a}'}, [par('a'), par('b')], [
            blk('log', {
              'value': cat([pm('a'), pm('b')]),
            }),
          ]),
          look('f2', {'name': '乙', 'shape': 'value'}),
          look('f3', {'name': '丙', 'shape': 'cap'}),
          look(
            'f4',
            {
              'name': '丁',
              'slots': [
                {'name': 'm', 'kind': 'choice', 'options': <String>[]},
              ],
            },
            [par('m')],
            [
              blk('log', {'value': pm('m')}),
            ],
          ),
        ],
        [
          callS('f1', {'a': nm(1), 'b': nm(1)}),
          let('v', call('f2')),
          callS('f3'),
          callS('f4', {'m': ''}),
          ok,
        ],
      );
      final got = {
        for (final i in validateBackend(doc, languages: ['node']))
          if (i.rule.startsWith('B')) '${i.rule} ${i.isError ? 'E' : 'W'} ${i.handlerId} ${i.path.length}',
      };
      expect(got, containsAll(['B02 E f1 0', 'B03 E f1 0', 'B04 E f1 0', 'B09 W f2 0', 'B08 E f3 0', 'B06 E f4 0']));
      expect({
        for (final i in validateBackend(funcBlocksDocument(), languages: ['node']))
          if (i.rule.startsWith('B')) i.rule,
      }, isEmpty);
    });

    test('调用时没给的参数：有默认值 / 是“剩下的全收”不报；没有默认值的照样报“还没填”', () {
      final doc = docOf(
        [
          fnDef(
            'f1',
            '甲',
            [par('a'), par('b', def: 1), par('r', rest: true)],
            [
              ret(cat([pm('a'), pm('b'), pm('r')])),
            ],
          ),
        ],
        [
          callS('f1'),
          json(call('f1', {'a': nm(1)})),
        ],
      );
      final g01 = issuesOf(doc, 'G01');
      expect([for (final i in g01) (i.path.single.index, i.arg)], [(0, 'a')]);
    });

    test('路径现算：匿名函数口里的问题带着口的序号（arm <= -2）；前面多一个匿名函数，序号跟着变', () {
      J bad() => lam([], [blk('break')]);
      final one = docOf([], [
        blk('do', {
          'value': ls([bad()]),
        }),
        ok,
      ]);
      final two = docOf([], [
        blk('do', {
          'value': ls([
            lam([], [ret(nm(1))]),
            bad(),
          ]),
        }),
        ok,
      ]);
      final a = issuesOf(one, 'L04').single, b = issuesOf(two, 'L04').single;
      expect((a.path.last.arm, b.path.last.arm), (lcExprMouthArm(0), lcExprMouthArm(1)));
      expect(one.route('r1')!.blockAt(a.path)!.op, 'break');
      expect(two.route('r1')!.blockAt(b.path)!.op, 'break');
      expect(a.where, contains('匿名函数里'));
    });
  });
}
