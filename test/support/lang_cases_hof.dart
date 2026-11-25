// 语言核心一致性用例（四）：拿函数当参数的 8 个列表操作（第 2 阶段做实的），以及出错时的样子。
import 'package:lopicode/lang/lang.dart';

import 'lang_conformance.dart';

LExpr _join(List<LExpr> xs) => rt('join', xs);
LExpr _add(LExpr a, LExpr b) => bin('+', a, b);
LExpr _nums() => list([n(3), n(1), n(2)]);
LExpr _double() => lamx([p('x')], bin('*', v('x'), n(2)));
LExpr _big() => lamx([p('x')], bin('>', v('x'), n(1)));

/// 数一数回调被调了几次：`seen` 加一，再返回 [result]。
LExpr _counting(LExpr result) => lam([p('x')], [set('seen', _add(v('seen'), n(1))), ret(result)]);

final List<LangCase> kLangHofCases = [
  LangCase(
    '八个操作：一般的样子',
    decls: [
      fn('isOdd', [p('x')], [ret(bin('==', bin('%', v('x'), n(2)), n(1)))]),
      fn('plus', [p('acc'), p('x')], [ret(_add(v('acc'), v('x')))]),
    ],
    [
      let('xs', _nums()),
      logJson(rt('listMap', [v('xs'), _double()])),
      logJson(rt('listFilter', [v('xs'), _big()])),
      logJson(
        rt('listReduce', [
          v('xs'),
          lamx([p('acc'), p('x')], _add(v('acc'), v('x'))),
          n(100),
        ]),
      ),
      logJson(rt('listFind', [v('xs'), _big()])),
      logJson(
        rt('listFind', [
          v('xs'),
          lamx([p('x')], bin('>', v('x'), n(9))),
        ]),
      ),
      logJson(rt('listEvery', [v('xs'), _big()])),
      logJson(
        rt('listEvery', [
          v('xs'),
          lamx([p('x')], bin('>', v('x'), n(0))),
        ]),
      ),
      logJson(rt('listSome', [v('xs'), _big()])),
      logJson(
        rt('listSome', [
          v('xs'),
          lamx([p('x')], bin('>', v('x'), n(9))),
        ]),
      ),
      logJson(
        rt('listSortBy', [
          v('xs'),
          lamx([p('x')], v('x')),
        ]),
      ),
      logJson(
        rt('listSortBy', [
          v('xs'),
          lamx([p('x')], bin('-', n(0), v('x'))),
        ]),
      ),
      // 每一项做一遍：没有结果；带函数体的回调改外面的变量
      let('seen', list()),
      run(
        rt('listEach', [
          v('xs'),
          lam(
            [p('x')],
            [
              run(rt('listPush', [v('seen'), v('x')])),
            ],
          ),
        ]),
      ),
      logJson(v('seen')),
      run(
        rt('listEach', [
          v('xs'),
          lamx([p('x')], v('x')),
        ]),
      ),
      // 原来的列表不变
      logJson(v('xs')),
      // 有名字的函数当回调
      logJson(rt('listFilter', [v('xs'), v('isOdd')])),
      logJson(rt('listReduce', [v('xs'), v('plus'), n(0)])),
      // 回调的结果按“算不算是”来看；合成的起点可以是任何值
      logJson(
        rt('listFilter', [
          list([n(0), t(''), t('a'), nul, n(2), list()]),
          lamx([p('x')], v('x')),
        ]),
      ),
      logJson(
        rt('listReduce', [
          v('xs'),
          lamx([p('acc'), p('x')], _join([v('acc'), v('x')])),
          t('>'),
        ]),
      ),
      logJson(
        rt('listReduce', [
          v('xs'),
          lam(
            [p('acc'), p('x')],
            [
              run(rt('listPush', [v('acc'), v('x')])),
              ret(v('acc')),
            ],
          ),
          list(),
        ]),
      ),
      // 连着用
      logJson(
        rt('listMap', [
          rt('listFilter', [v('xs'), _big()]),
          _double(),
        ]),
      ),
    ],
    ['[6,2,4]', '[3,2]', '106', '3', 'null', 'false', 'true', 'true', 'false', '[1,2,3]', '[3,2,1]', '[3,1,2]', '[3,1,2]', '[3,1]', '6', '["a",2,[]]', '">312"', '[3,1,2]', '[6,4]'],
  ),
  LangCase(
    '八个操作：空列表、不是列表（当空列表）',
    [
      for (final xs in [
        list(),
        n(5),
        t('abc'),
        nul,
        dict({'a': n(1)}),
      ]) ...[
        log(
          _join([
            json(rt('listMap', [xs, _double()])),
            json(rt('listFilter', [xs, _big()])),
            json(
              rt('listReduce', [
                xs,
                lamx([p('acc'), p('x')], _add(v('acc'), v('x'))),
                t('起点'),
              ]),
            ),
            json(rt('listFind', [xs, _big()])),
            json(rt('listEvery', [xs, _big()])),
            json(rt('listSome', [xs, _big()])),
            json(rt('listSortBy', [xs, _double()])),
          ]),
        ),
        run(rt('listEach', [xs, _big()])),
      ],
    ],
    [for (var i = 0; i < 5; i++) '[][]"起点"nulltruefalse[]'],
  ),
  LangCase(
    '都满足吗 / 有满足的吗 / 第一个满足的：碰到就停',
    [
      let('seen', n(0)),
      let('xs', list([n(1), n(2), n(3), n(4)])),
      logJson(rt('listEvery', [v('xs'), _counting(bin('<', v('x'), n(2)))])),
      log(v('seen')),
      set('seen', n(0)),
      logJson(rt('listSome', [v('xs'), _counting(bin('==', v('x'), n(3)))])),
      log(v('seen')),
      set('seen', n(0)),
      logJson(rt('listFind', [v('xs'), _counting(bin('==', v('x'), n(2)))])),
      log(v('seen')),
      set('seen', n(0)),
      logJson(rt('listEvery', [v('xs'), _counting(yes)])),
      log(v('seen')),
    ],
    ['false', '2', 'true', '3', '2', '2', 'true', '4'],
  ),
  LangCase(
    '按给分排序：数字在前、文字按码点、一样的保持先后',
    [
      let(
        'people',
        list([
          dict({'name': t('丙'), 'age': n(30)}),
          dict({'name': t('甲'), 'age': n(25)}),
          dict({'name': t('丁'), 'age': n(30)}),
          dict({'name': t('乙'), 'age': n(25)}),
        ]),
      ),
      let(
        'names',
        lamx(
          [p('ps')],
          rt('listJoin', [
            rt('listMap', [
              v('ps'),
              lamx([p('q')], at(v('q'), t('name'))),
            ]),
            t(''),
          ]),
        ),
      ),
      log(
        call(v('names'), [
          rt('listSortBy', [
            v('people'),
            lamx([p('q')], at(v('q'), t('age'))),
          ]),
        ]),
      ),
      log(
        call(v('names'), [
          rt('listSortBy', [
            v('people'),
            lamx([p('q')], at(v('q'), t('name'))),
          ]),
        ]),
      ),
      // 分一样：全都保持原来的先后
      log(
        call(v('names'), [
          rt('listSortBy', [
            v('people'),
            lamx([p('q')], n(1)),
          ]),
        ]),
      ),
      // 分有数字有别的：数字在前，其余的文字化后按码点（空 → 空文字，排最前）
      logJson(
        rt('listSortBy', [
          list([t('b'), n(10), t('a'), n(9), nul, yes, t('10'), t('😀'), t('Ａ')]),
          lamx([p('x')], v('x')),
        ]),
      ),
      // 给分函数只对每一项调一次
      let('seen', n(0)),
      logJson(
        rt('listSortBy', [
          list([n(5), n(4), n(3), n(2), n(1)]),
          _counting(v('x')),
        ]),
      ),
      log(v('seen')),
      // 原来的列表不变
      log(call(v('names'), [v('people')])),
    ],
    ['甲乙丙丁', '丁丙乙甲', '丙甲丁乙', '[9,10,null,"10","a","b",true,"Ａ","😀"]', '[1,2,3,4,5]', '5', '丙甲丁乙'],
  ),
  LangCase(
    '回调里改了原来的列表：这一趟走的还是开始时的那几项',
    [
      let('xs', list([n(1), n(2), n(3)])),
      logJson(
        rt('listMap', [
          v('xs'),
          lam(
            [p('x')],
            [
              run(rt('listPush', [v('xs'), n(0)])),
              ret(v('x')),
            ],
          ),
        ]),
      ),
      logJson(v('xs')),
      let('ys', list([n(1), n(2), n(3)])),
      run(
        rt('listEach', [
          v('ys'),
          lam(
            [p('x')],
            [
              run(rt('listPop', [v('ys')])),
            ],
          ),
        ]),
      ),
      logJson(v('ys')),
    ],
    ['[1,2,3]', '[1,2,3,0,0,0]', '[]'],
  ),
];

/// 会出错的程序：先打印 [before] 那几行，然后抛错、错误信息里有 [message]。
class LangFailCase {
  const LangFailCase(this.name, this.body, this.message, {this.decls = const []});
  final String name;
  final List<LStmt> body;
  final String message;
  final List<LDecl> decls;
}

final List<LangFailCase> kLangFailCases = [
  LangFailCase('调的不是函数', [log(t('前')), run(call(n(5)))], kLangErrors['notFunction']!),
  LangFailCase('调的是空', [
    log(t('前')),
    let('f', nul),
    run(call(v('f'), [n(1)])),
  ], kLangErrors['notFunction']!),
  LangFailCase('函数值：少给了参数', [
    log(t('前')),
    let('f', lamx([p('a'), p('b')], v('a'))),
    run(call(v('f'), [n(1)])),
  ], kLangErrors['argCount']!),
  LangFailCase('函数值：多给了参数', [
    log(t('前')),
    let('f', lam([p('a')], [ret(v('a'))])),
    run(call(v('f'), [n(1), n(2)])),
  ], kLangErrors['argCount']!),
  LangFailCase(
    '有名字的函数当值：少给了参数',
    decls: [
      fn('two', [p('a'), p('b', or: 1)], [ret(v('a'))]),
    ],
    [
      log(t('前')),
      let('f', v('two')),
      log(call(v('f'), [n(7)])),
      run(call(v('f'))),
    ],
    kLangErrors['argCount']!,
  ),
  LangFailCase('列表操作：给的不是函数', [
    log(t('前')),
    run(
      rt('listMap', [
        list([n(1)]),
        t('不是函数'),
      ]),
    ),
  ], kLangErrors['notFunction']!),
  LangFailCase('列表操作：空列表也要查是不是函数', [
    log(t('前')),
    run(rt('listEach', [list(), nul])),
  ], kLangErrors['notFunction']!),
  LangFailCase('列表操作：回调收的参数个数不对', [
    log(t('前')),
    run(
      rt('listMap', [
        list([n(1)]),
        lamx([p('a'), p('b')], v('a')),
      ]),
    ),
  ], kLangErrors['argCount']!),
  LangFailCase('回调里抛的错一路传出来', [
    log(t('前')),
    run(
      rt('listMap', [
        list([n(1), n(2)]),
        lam(
          [p('x')],
          [
            log(v('x')),
            run(rt('listPush', [n(0), v('x')])),
            ret(v('x')),
          ],
        ),
      ]),
    ),
    log(t('不该出现')),
  ], '这不是列表，改不了'),
  LangFailCase(
    '函数里抛的错一路传出来',
    decls: [
      fn('inner', [], [
        run(rt('listPush', [nul, n(1)])),
      ]),
      fn('outer', [], [ret(callN('inner'))]),
    ],
    [log(t('前')), run(callN('outer')), log(t('不该出现'))],
    '这不是列表，改不了',
  ),
];
