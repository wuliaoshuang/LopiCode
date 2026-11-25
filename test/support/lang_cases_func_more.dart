// 语言核心一致性用例（三·补充）：函数里容易出岔子的写法——变量里的匿名函数自己调自己、三层同名变量、
// 循环变量被抓住、匿名函数放在循环 / “否则如果”的条件里、闭包改带默认值的参数。
import 'package:lopicode/lang/lang.dart';

import 'lang_conformance.dart';

LExpr _join(List<LExpr> xs) => rt('join', xs);
LExpr _add(LExpr a, LExpr b) => bin('+', a, b);
LExpr _sub1(LExpr a) => bin('-', a, n(1));

final List<LangCase> kLangFuncMoreCases = [
  LangCase(
    '补充：变量里的匿名函数自己调自己、两个互相调',
    [
      let('fact', nul),
      set(
        'fact',
        lam(
          [p('n')],
          [
            iff(bin('<=', v('n'), n(1)), [ret(n(1))]),
            ret(bin('*', v('n'), call(v('fact'), [_sub1(v('n'))]))),
          ],
        ),
      ),
      log(call(v('fact'), [n(6)])),
      let('ping', nul),
      let('pong', nul),
      set(
        'ping',
        lam(
          [p('k')],
          [
            iff(bin('<=', v('k'), n(0)), [ret(t('完'))]),
            ret(
              _join([
                t('乒'),
                call(v('pong'), [_sub1(v('k'))]),
              ]),
            ),
          ],
        ),
      ),
      set(
        'pong',
        lam(
          [p('k')],
          [
            iff(bin('<=', v('k'), n(0)), [ret(t('完'))]),
            ret(
              _join([
                t('乓'),
                call(v('ping'), [_sub1(v('k'))]),
              ]),
            ),
          ],
        ),
      ),
      log(call(v('ping'), [n(3)])),
    ],
    ['720', '乒乓乒完'],
  ),
  LangCase(
    '补充：三层套着，同名的变量各是各的；里层改外层带默认值的参数',
    [
      let('x', n(1)),
      let(
        'f',
        lam([], [
          let('x', n(2)),
          let('g', lam([], [let('x', n(3)), ret(v('x'))])),
          ret(_join([call(v('g')), v('x')])),
        ]),
      ),
      log(_join([call(v('f')), v('x')])),
      let(
        'h',
        lam(
          [p('x', or: 5)],
          [
            let('inc', lam([], [set('x', _add(v('x'), n(1)))])),
            run(call(v('inc'))),
            run(call(v('inc'))),
            ret(v('x')),
          ],
        ),
      ),
      log(call(v('h'))),
      log(call(v('h'), [n(10)])),
      log(v('x')),
    ],
    ['321', '7', '12', '1'],
  ),
  LangCase(
    '补充：循环变量被匿名函数抓住（数数、逐对、逐项带序号）',
    [
      let('out', list()),
      LForCount('i', n(1), n(3), n(1), [
        run(rt('listPush', [v('out'), lamx([], bin('*', v('i'), n(10)))])),
      ]),
      log(_join([call(at(v('out'), n(0))), t(','), call(at(v('out'), n(2)))])),
      let('seen', list()),
      let(
        'note',
        lam(
          [p('s')],
          [
            run(rt('listPush', [v('seen'), v('s')])),
          ],
        ),
      ),
      LForPairs(dict({'a': n(1), 'b': n(2)}), 'k', 'val', [
        run(
          call(
            lam([], [
              run(
                call(v('note'), [
                  _join([v('k'), t('='), v('val')]),
                ]),
              ),
            ]),
          ),
        ),
      ]),
      LForEach(list([t('甲'), t('乙')]), 'it', [
        run(
          call(v('note'), [
            call(lamx([], _join([v('idx'), v('it')]))),
          ]),
        ),
      ], index: 'idx'),
      logJson(v('seen')),
    ],
    ['30,30', '["a=1","b=2","0甲","1乙"]'],
  ),
  LangCase(
    '补充：带函数体的匿名函数放在循环、“否则如果”的条件里',
    [
      let('c', n(0)),
      let('next', lam([], [set('c', _add(v('c'), n(1))), ret(v('c'))])),
      LWhile(bin('<', call(lam([], [ret(call(v('next')))])), n(4)), [run(call(v('next')))]),
      log(v('c')),
      LIf(
        [
          LIfArm(bin('>', v('c'), n(10)), [log(t('大'))]),
          LIfArm(call(lam([p('q')], [ret(bin('==', v('q'), n(5)))]), [v('c')]), [log(t('正好'))]),
        ],
        orElse: [log(t('别的'))],
      ),
    ],
    ['5', '正好'],
  ),
  LangCase(
    '补充：有名字的函数里闭包改带默认值的参数；递归里用列表操作；函数放字典里',
    decls: [
      fn(
        'acc',
        [p('start', or: 100), p('more', rest: true)],
        [
          run(
            rt('listEach', [
              v('more'),
              lam([p('m')], [set('start', _add(v('start'), v('m')))]),
            ]),
          ),
          ret(v('start')),
        ],
      ),
      fn(
        'walk',
        [p('node')],
        [
          iff(rt('isType', [v('node'), t('list')]), [
            ret(
              rt('listReduce', [
                v('node'),
                lamx([p('a'), p('x')], _add(v('a'), callN('walk', [v('x')]))),
                n(0),
              ]),
            ),
          ]),
          ret(v('node')),
        ],
      ),
    ],
    [
      log(callN('acc')),
      log(callN('acc', [n(1)])),
      log(callN('acc', [n(1), n(2), n(3)])),
      let('g', v('acc')),
      log(call(v('g'), [n(10), n(5)])),
      log(
        callN('walk', [
          list([
            n(1),
            list([
              n(2),
              list([n(3), n(4)]),
            ]),
            n(5),
          ]),
        ]),
      ),
      let(
        'ops',
        dict({
          'twice': lamx(
            [p('f'), p('x')],
            call(v('f'), [
              call(v('f'), [v('x')]),
            ]),
          ),
        }),
      ),
      log(
        call(at(v('ops'), t('twice')), [
          lamx([p('z')], bin('*', v('z'), n(3))),
          n(2),
        ]),
      ),
    ],
    ['100', '1', '6', '15', '15', '18'],
  ),
];
