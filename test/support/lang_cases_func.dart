// 语言核心一致性用例（三）：函数——递归、互相递归、闭包、函数当值、匿名函数两种写法、默认参数、“剩下的全收”、
// 没有返回值的函数、提前返回、函数里用第 1 阶段的各种语句。
import 'package:lopicode/lang/lang.dart';

import 'lang_conformance.dart';

LExpr _join(List<LExpr> xs) => rt('join', xs);
LExpr _add(LExpr a, LExpr b) => bin('+', a, b);

final List<LangCase> kLangFuncCases = [
  LangCase(
    '递归：阶乘、斐波那契',
    decls: [
      fn(
        'fact',
        [p('n')],
        [
          iff(bin('<=', v('n'), n(1)), [ret(n(1))]),
          ret(bin('*', v('n'), callN('fact', [bin('-', v('n'), n(1))]))),
        ],
      ),
      fn(
        'fib',
        [p('n')],
        [
          iff(bin('<', v('n'), n(2)), [ret(v('n'))]),
          ret(_add(callN('fib', [bin('-', v('n'), n(1))]), callN('fib', [bin('-', v('n'), n(2))]))),
        ],
      ),
    ],
    [
      log(callN('fact', [n(5)])),
      log(callN('fact', [n(0)])),
      log(callN('fact', [n(10)])),
      log(callN('fib', [n(15)])),
      logJson(
        list([
          for (var i = 0; i < 8; i++) callN('fib', [n(i)]),
        ]),
      ),
    ],
    ['120', '1', '3628800', '610', '[0,1,1,2,3,5,8,13]'],
  ),
  LangCase(
    '互相递归：排在后面的函数也能调',
    decls: [
      fn(
        'isEven',
        [p('n')],
        [
          iff(bin('==', v('n'), n(0)), [ret(yes)]),
          ret(callN('isOdd', [bin('-', v('n'), n(1))])),
        ],
      ),
      fn(
        'isOdd',
        [p('n')],
        [
          iff(bin('==', v('n'), n(0)), [ret(no)]),
          ret(callN('isEven', [bin('-', v('n'), n(1))])),
        ],
      ),
    ],
    [
      logJson(callN('isEven', [n(10)])),
      logJson(callN('isOdd', [n(7)])),
      logJson(callN('isEven', [n(7)])),
      logJson(callN('isOdd', [n(0)])),
    ],
    ['true', 'true', 'false', 'false'],
  ),
  LangCase(
    '闭包：计数器（里层改外层的变量），各有各的一份',
    decls: [
      fn(
        'makeCounter',
        [p('start')],
        [
          let('count', v('start')),
          ret(lam([], [set('count', _add(v('count'), n(1))), ret(v('count'))])),
        ],
      ),
      // 里层改的是外层的参数
      fn(
        'makeAdder',
        [p('total')],
        [
          ret(lam([p('x')], [set('total', _add(v('total'), v('x'))), ret(v('total'))])),
        ],
      ),
      // 两层：最里层改最外层的变量，中间那层只是经过
      fn('deep', [], [
        let('hits', n(0)),
        let(
          'outer',
          lam([], [
            ret(lam([], [set('hits', _add(v('hits'), n(1))), ret(v('hits'))])),
          ]),
        ),
        let('inner', call(v('outer'))),
        run(call(v('inner'))),
        run(call(v('inner'))),
        ret(v('hits')),
      ]),
    ],
    [
      let('c1', callN('makeCounter', [n(10)])),
      let('c2', callN('makeCounter', [n(0)])),
      log(call(v('c1'))),
      log(call(v('c1'))),
      log(call(v('c2'))),
      log(call(v('c1'))),
      let('acc', callN('makeAdder', [n(100)])),
      run(call(v('acc'), [n(5)])),
      log(call(v('acc'), [n(20)])),
      log(callN('deep')),
      // “启动时”里的变量也能被匿名函数改
      let('sum', n(0)),
      let('bump', lam([p('x')], [set('sum', _add(v('sum'), v('x')))])),
      run(call(v('bump'), [n(3)])),
      run(call(v('bump'), [n(4)])),
      log(v('sum')),
      // 外面后来改了，里层读到的是新的（抓的是变量，不是当时的值）
      let('word', t('旧')),
      let('say', lamx([], v('word'))),
      set('word', t('新')),
      log(call(v('say'))),
    ],
    ['11', '12', '1', '13', '125', '2', '7', '新'],
  ),
  LangCase(
    '闭包：读、改模块级的变量',
    decls: [
      LVarDecl('total', n(100)),
      const LVarDecl('label', LLit('合计'), isConst: true),
      fn('addTo', [p('x')], [set('total', _add(v('total'), v('x')))]),
      fn('show', [], [
        ret(_join([v('label'), t('='), v('total')])),
      ]),
      fn('makeBump', [], [
        ret(lam([], [set('total', _add(v('total'), n(1))), ret(v('total'))])),
      ]),
      // 函数里新建的同名变量是它自己的，不动模块级的
      fn('shadow', [], [let('total', n(-1)), ret(v('total'))]),
    ],
    [
      run(callN('addTo', [n(5)])),
      log(callN('show')),
      let('b', callN('makeBump')),
      run(call(v('b'))),
      log(call(v('b'))),
      set('total', n(1)),
      log(callN('show')),
      log(callN('shadow')),
      log(v('total')),
      log(call(lamx([], _join([v('label'), v('total')])))),
    ],
    ['合计=105', '107', '合计=1', '-1', '1', '合计1'],
  ),
  LangCase(
    '函数当值：传给别的函数、存进变量 / 列表 / 字典再调用',
    decls: [
      fn('double', [p('x')], [ret(bin('*', v('x'), n(2)))]),
      fn('inc', [p('x')], [ret(_add(v('x'), n(1)))]),
      fn(
        'apply',
        [p('f'), p('x')],
        [
          ret(call(v('f'), [v('x')])),
        ],
      ),
      fn(
        'compose',
        [p('f'), p('g')],
        [
          ret(
            lamx(
              [p('x')],
              call(v('f'), [
                call(v('g'), [v('x')]),
              ]),
            ),
          ),
        ],
      ),
    ],
    [
      log(callN('apply', [v('double'), n(21)])),
      let('f', v('inc')),
      log(call(v('f'), [n(1)])),
      let(
        'fs',
        list([
          v('double'),
          v('inc'),
          lamx([p('x')], bin('-', v('x'), n(1))),
        ]),
      ),
      log(call(at(v('fs'), n(0)), [n(5)])),
      log(call(at(v('fs'), n(2)), [n(5)])),
      let('d', dict({'op': v('double')})),
      log(call(at(v('d'), t('op')), [n(4)])),
      let('h', callN('compose', [v('double'), v('inc')])),
      log(call(v('h'), [n(3)])),
      // 变量里换了一个函数
      set('f', v('double')),
      log(call(v('f'), [n(8)])),
      // 函数这种值：文字化、写成 JSON、类型、等于
      log(v('double')),
      log(lamx([], n(1))),
      logJson(v('double')),
      logJson(v('fs')),
      logJson(rt('isType', [v('double'), t('function')])),
      logJson(rt('isType', [v('h'), t('function')])),
      logJson(rt('isType', [n(1), t('function')])),
      logJson(rt('isType', [v('double'), t('dict')])),
      logJson(bin('==', v('double'), v('double'))),
      logJson(bin('==', v('double'), v('inc'))),
      logJson(bin('==', v('h'), v('h'))),
      logJson(bin('==', lamx([], n(1)), lamx([], n(1)))),
      logJson(bin('==', v('double'), t('[函数 double]'))),
      log(rt('toText', [v('f')])),
      iff(v('double'), [log(t('函数算“是”'))]),
    ],
    ['42', '2', '10', '4', '8', '8', '16', '[函数 double]', '[函数]', 'null', '[null,null,null]', 'true', 'true', 'false', 'false', 'true', 'false', 'true', 'false', 'true', '[函数 double]', '函数算“是”'],
  ),
  LangCase(
    '匿名函数：带函数体的、短写法、套着的、当场就调',
    [
      let('sq', lamx([p('x')], bin('*', v('x'), v('x')))),
      log(call(v('sq'), [n(7)])),
      let(
        'greet',
        lam(
          [p('name')],
          [
            let('s', _join([t('你好，'), v('name')])),
            ret(v('s')),
          ],
        ),
      ),
      log(call(v('greet'), [t('小明')])),
      // 柯里化：短写法套短写法
      let('add', lamx([p('a')], lamx([p('b')], _add(v('a'), v('b'))))),
      log(call(call(v('add'), [n(1)]), [n(2)])),
      // 带函数体的套带函数体的；里层的参数和外层的变量同名
      let('x', t('外')),
      let(
        'nest',
        lam(
          [p('k')],
          [
            let('base', bin('*', v('k'), n(10))),
            let('inner', lam([p('x')], [ret(_add(v('base'), v('x')))])),
            ret(call(v('inner'), [n(1)])),
          ],
        ),
      ),
      log(call(v('nest'), [n(2)])),
      log(v('x')),
      // 当场就调
      log(call(lamx([p('a'), p('b')], _join([v('a'), v('b')])), [t('左'), t('右')])),
      log(call(lam([], [ret(t('带函数体的当场调'))]))),
      // 短写法里套带函数体的
      let('mk', lamx([p('n')], lam([], [ret(bin('*', v('n'), n(2)))]))),
      log(call(call(v('mk'), [n(21)]))),
      // 放在“如果”的条件、循环里
      iff(call(lam([], [ret(yes)])), [log(t('条件里的匿名函数'))]),
      let('fs', list()),
      LForEach(list([n(1), n(2), n(3)]), 'i', [
        run(rt('listPush', [v('fs'), lamx([], v('i'))])),
      ]),
      // 没有块级作用域：三个函数抓的是同一个 i
      log(_join([call(at(v('fs'), n(0))), call(at(v('fs'), n(1))), call(at(v('fs'), n(2)))])),
      // 没有返回值的匿名函数得空
      logJson(call(lam([], [const LNote('什么都不做')]))),
      logJson(call(lam([p('q')], [ret()]), [n(1)])),
    ],
    ['49', '你好，小明', '3', '21', '外', '左右', '带函数体的当场调', '42', '条件里的匿名函数', '333', 'null', 'null'],
  ),
  LangCase(
    '默认参数：全给、少给；经过函数值调也一样',
    decls: [
      fn(
        'greet',
        [p('name'), p('greeting', or: '你好'), p('mark', or: '！')],
        [
          ret(_join([v('greeting'), t('，'), v('name'), v('mark')])),
        ],
      ),
      fn(
        'kinds',
        [p('a', or: 1.5), p('b', or: true), p('c', hasDefault: true), p('d', or: '引"号\\')],
        [
          ret(json(list([v('a'), v('b'), v('c'), v('d')]))),
        ],
      ),
    ],
    [
      log(callN('greet', [t('甲'), t('早'), t('。')])),
      log(callN('greet', [t('乙'), t('晚上好')])),
      log(callN('greet', [t('丙')])),
      log(callN('kinds')),
      log(callN('kinds', [n(0), nul])),
      let('g', v('greet')),
      log(call(v('g'), [t('丁')])),
      log(call(v('g'), [t('戊'), t('嗨'), t('~')])),
      let('plus', lamx([p('x'), p('y', or: 10)], _add(v('x'), v('y')))),
      log(call(v('plus'), [n(1)])),
      log(call(v('plus'), [n(1), n(2)])),
      let(
        'tag',
        lam(
          [p('s'), p('open', or: '<'), p('close', or: '>')],
          [
            ret(_join([v('open'), v('s'), v('close')])),
          ],
        ),
      ),
      log(call(v('tag'), [t('b')])),
      log(call(v('tag'), [t('b'), t('[')])),
    ],
    ['早，甲。', '晚上好，乙！', '你好，丙！', '[1.5,true,null,"引\\"号\\\\"]', '[0,null,null,"引\\"号\\\\"]', '你好，丁！', '嗨，戊~', '11', '3', '<b>', '[b>'],
  ),
  LangCase(
    '剩下的全收：函数里拿到的是列表',
    decls: [
      fn(
        'sum',
        [p('first'), p('more', rest: true)],
        [
          let('total', v('first')),
          LForEach(v('more'), 'x', [set('total', _add(v('total'), v('x')))]),
          ret(v('total')),
        ],
      ),
      fn(
        'pack',
        [p('xs', rest: true)],
        [
          run(rt('listPush', [v('xs'), t('尾')])),
          ret(json(v('xs'))),
        ],
      ),
      fn(
        'mix',
        [p('a'), p('b', or: 'B'), p('tail', rest: true)],
        [
          ret(_join([v('a'), v('b'), json(v('tail'))])),
        ],
      ),
    ],
    [
      log(callN('sum', [n(1)])),
      log(callN('sum', [n(1), n(2), n(3), n(4)])),
      log(callN('pack')),
      log(callN('pack', [n(1), t('a'), nul])),
      log(callN('mix', [t('x')])),
      log(callN('mix', [t('x'), t('y')])),
      log(callN('mix', [t('x'), t('y'), n(1), n(2)])),
      let('s', v('sum')),
      log(call(v('s'), [n(1), n(2), n(3)])),
      let('m', v('mix')),
      log(call(v('m'), [t('p')])),
      log(call(v('m'), [t('p'), t('q'), t('r')])),
      let(
        'count',
        lam(
          [p('xs', rest: true)],
          [
            ret(rt('size', [v('xs')])),
          ],
        ),
      ),
      log(call(v('count'))),
      log(call(v('count'), [n(1), n(2), n(3)])),
      let('tail', lamx([p('a'), p('xs', rest: true)], json(v('xs')))),
      log(call(v('tail'), [n(1)])),
      log(call(v('tail'), [n(1), n(2), t('三')])),
      logJson(
        rt('isType', [
          call(lamx([p('xs', rest: true)], v('xs'))),
          t('list'),
        ]),
      ),
    ],
    ['1', '10', '["尾"]', '[1,"a",null,"尾"]', 'xB[]', 'xy[]', 'xy[1,2]', '6', 'pB[]', 'pq["r"]', '0', '3', '[]', '[2,"三"]', 'true'],
  ),
  LangCase(
    '没有返回值的函数、提前返回',
    decls: [
      fn(
        'shout',
        [p('x')],
        [
          log(_join([v('x'), t('!')])),
        ],
      ),
      fn(
        'guard',
        [p('k')],
        [
          iff(bin('<', v('k'), n(0)), [log(t('负数，不干了')), ret()]),
          log(_join([t('处理 '), v('k')])),
        ],
      ),
      fn(
        'classify',
        [p('k')],
        [
          iff(bin('<', v('k'), n(0)), [ret(t('负'))]),
          iff(bin('==', v('k'), n(0)), [ret(t('零'))], [ret(t('正'))]),
        ],
      ),
      fn(
        'firstBig',
        [p('xs')],
        [
          LForEach(v('xs'), 'x', [
            iff(bin('>', v('x'), n(10)), [ret(v('x'))]),
          ]),
          ret(nul),
        ],
      ),
      // 从套着的循环里直接返回
      fn(
        'findPair',
        [p('want')],
        [
          LForCount('i', n(1), n(5), n(1), [
            LForCount('j', n(1), n(5), n(1), [
              iff(bin('==', bin('*', v('i'), v('j')), v('want')), [
                ret(_join([v('i'), t('×'), v('j')])),
              ]),
            ]),
          ]),
          ret(t('没有')),
        ],
      ),
      // 一上来就返回：后面的不生成（Java、Go 不许有执行不到的语句）
      fn('early', [], [ret(n(1)), log(t('不该出现')), ret(n(2))]),
      // 返回后面跟的不是“返回”：函数末尾不能再补一句“什么都不返回”（那一句也执行不到）
      fn('early2', [], [ret(n(2)), log(t('不该出现'))]),
      fn(
        'early3',
        [p('k')],
        [
          iff(v('k'), [ret(t('是'))], [ret(t('否'))]),
          log(t('不该出现')),
        ],
      ),
    ],
    [
      run(callN('shout', [t('嗨')])),
      logJson(callN('shout', [t('哦')])),
      run(callN('guard', [n(-1)])),
      run(callN('guard', [n(3)])),
      logJson(callN('guard', [n(-2)])),
      log(
        _join([
          callN('classify', [n(-5)]),
          callN('classify', [n(0)]),
          callN('classify', [n(9)]),
        ]),
      ),
      log(
        callN('firstBig', [
          list([n(1), n(50), n(99)]),
        ]),
      ),
      logJson(
        callN('firstBig', [
          list([n(1)]),
        ]),
      ),
      log(callN('findPair', [n(12)])),
      log(callN('findPair', [n(7)])),
      log(callN('findPair', [n(77)])),
      log(callN('early')),
      log(callN('early2')),
      log(
        _join([
          callN('early3', [yes]),
          callN('early3', [no]),
        ]),
      ),
      log(call(lam([], [ret(n(3)), log(t('不该出现'))]))),
    ],
    ['嗨!', '哦!', 'null', '负数，不干了', '处理 3', '负数，不干了', 'null', '负零正', '50', 'null', '3×4', '没有', '没有', '1', '2', '是否', '3'],
  ),
  LangCase(
    '函数里用第 1 阶段的各种语句',
    decls: [
      fn(
        'tour',
        [p('xs'), p('d')],
        [
          let('out', list()),
          const LNote('一段注释'),
          let('limit', n(3), isConst: true),
          // 一直重复 ＋ 跳出 / 跳过
          let('w', n(0)),
          LWhile(yes, [
            set('w', _add(v('w'), n(1))),
            iff(bin('==', v('w'), n(2)), [const LContinue()]),
            iff(bin('>', v('w'), v('limit')), [const LBreak()]),
            run(
              rt('listPush', [
                v('out'),
                _join([t('w'), v('w')]),
              ]),
            ),
          ]),
          // 数数
          LForCount('i', n(3), n(1), n(-1), [
            run(rt('listPush', [v('out'), v('i')])),
          ]),
          // 每一项（带位置）
          LForEach(v('xs'), 'x', index: 'k', [
            iff(
              bin('==', v('k'), n(0)),
              [
                run(
                  rt('listPush', [
                    v('out'),
                    _join([t('头'), v('x')]),
                  ]),
                ),
              ],
              [
                run(
                  rt('listPush', [
                    v('out'),
                    _join([v('k'), t(':'), v('x')]),
                  ]),
                ),
              ],
            ),
          ]),
          // 每一对
          LForPairs(v('d'), 'key', 'val', [
            run(
              rt('listPush', [
                v('out'),
                _join([v('key'), t('='), v('val')]),
              ]),
            ),
          ]),
          // 重复几次
          let('c', n(0)),
          LRepeat(n(4), [set('c', _add(v('c'), n(1)))]),
          // 多段的如果
          LIf(
            [
              LIfArm(bin('>', v('c'), n(10)), [set('c', t('大'))]),
              LIfArm(bin('==', v('c'), n(4)), [set('c', t('正好'))]),
            ],
            orElse: [set('c', t('小'))],
          ),
          run(rt('listPush', [v('out'), v('c')])),
          // 值版的如果、并且 / 或者、下标读写
          run(
            rt('listPush', [
              v('out'),
              LCond(LLogic('and', yes, bin('>', rt('size', [v('xs')]), n(1))), t('多'), t('少')),
            ]),
          ),
          setAt(v('out'), n(0), t('改过')),
          let('copy', dict({'a': n(1)})),
          setAt(v('copy'), t('b'), at(v('out'), n(1))),
          run(rt('listPush', [v('out'), json(v('copy'))])),
          ret(rt('listJoin', [v('out'), t(' ')])),
        ],
      ),
    ],
    [
      log(
        callN('tour', [
          list([t('甲'), t('乙')]),
          dict({'b': n(2), 'a': n(1)}),
        ]),
      ),
      log(callN('tour', [list(), dict()])),
    ],
    ['改过 w3 3 2 1 头甲 1:乙 a=1 b=2 正好 多 {"a":1,"b":"w3"}', '改过 w3 3 2 1 正好 少 {"a":1,"b":"w3"}'],
  ),
];
