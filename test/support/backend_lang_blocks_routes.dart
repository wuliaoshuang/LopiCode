// 新积木一致性样本的接口：每个接口走一类新积木（见 backend_lang_blocks.dart 开头的说明）。
import 'backend_lang_blocks.dart';

J _len(J x) => ex('len', {'x': x});
J _at(J of, J key) => ex('index', {'of': of, 'key': key});

/// GET /basics：新建变量 / 常量、列表和字典的字面量与读写、否则如果链、分情况。
J _basics() => route('basics', 'GET', '/basics', [
  let('xs', ls([nm(1), nm(2), nm(3)])),
  let('d', dc({'a': nm(1), 'b': tx('二')})),
  konst('k', tx('b')),
  push('xs', nm(4)),
  blk('listSet', {'xs': vr('xs'), 'i': nm(0), 'v': nm(10)}),
  blk('setItem', {'of': vr('xs'), 'key': nm(1), 'value': nm(20)}),
  blk('setItem', {'of': vr('d'), 'key': tx('c'), 'value': ls([])}),
  blk('dictSet', {'d': vr('d'), 'k': tx('z'), 'v': ex('null')}),
  let('grade', tx('')),
  iff(
    op2('>=', qn('n'), nm(90)),
    [setv('grade', tx('A'))],
    arms: [
      arm({'cond': op2('>=', qn('n'), nm(60))}, [setv('grade', tx('B'))]),
      arm({'cond': op2('>=', qn('n'), nm(0))}, [setv('grade', tx('C'))]),
    ],
    orElse: [setv('grade', tx('?'))],
  ),
  let('kind', tx('')),
  blk('switch', {'value': q('t')}, const [], [setv('kind', tx('别的'))], [
    arm({'value': tx('x')}, [setv('kind', tx('叉'))]),
    arm({'value': tx('y')}, [setv('kind', tx('歪'))]),
    // 值是算出来的；和前面重复的情况不会走到
    arm(
      {
        'value': cat([tx('x')]),
      },
      [setv('kind', tx('不会到'))],
    ),
  ]),
  // 收起“否则”的如果、没有“都不是”的分情况
  let('extra', ls([])),
  iff(op2('==', q('t'), tx('y')), [push('extra', tx('是歪'))], noElse: true),
  blk(
    'switch',
    {'value': qn('n')},
    const [],
    const [],
    [
      arm({'value': nm(95)}, [push('extra', tx('九十五'))]),
    ],
    true,
  ),
  json(
    dc({
      'xs': vr('xs'),
      'd': vr('d'),
      'first': _at(vr('xs'), nm(0)),
      'bk': _at(vr('d'), vr('k')),
      'ch': _at(tx('你好'), nm(1)),
      'grade': vr('grade'),
      'kind': vr('kind'),
      'extra': vr('extra'),
      'none': ex('listGet', {'xs': vr('xs'), 'i': nm(9)}),
      'dg': ex('dictGet', {'d': vr('d'), 'k': tx('a')}),
    }),
  ),
]);

/// GET /loops：当…时重复、一直重复＋跳出、跳过、从…数到…（负步长、步长 0、方向不对）、带序号的对每一项、对每一对（顺序）、旧的“重复”。
J _loops() => route('loops', 'GET', '/loops', [
  let('out', ls([])),
  let('i', nm(0)),
  blk('while', {'cond': op2('<', vr('i'), nm(3))}, [push('out', vr('i')), setv('i', op2('+', vr('i'), nm(1)))]),
  blk('forever', const {}, [
    blk('changeVar', {'name': 'i', 'by': nm(1)}),
    iff(op2('>=', vr('i'), nm(7)), [blk('break')], noElse: true),
    iff(op2('==', op2('%', vr('i'), nm(2)), nm(0)), [blk('continue')], noElse: true),
    push('out', cat([tx('f'), vr('i')])),
  ]),
  blk('forCount', {'name': 'j', 'from': nm(5), 'to': nm(1), 'step': nm(-2)}, [push('out', vr('j'))]),
  blk('forCount', {'name': 'z', 'from': nm(1), 'to': nm(5), 'step': nm(0)}, [push('out', tx('步长 0 不该做'))]),
  blk('forCount', {'name': 'w', 'from': nm(3), 'to': nm(1), 'step': nm(1)}, [push('out', tx('方向不对不该做'))]),
  blk('forCount', {'name': 'h', 'from': nm(0), 'to': nm(1), 'step': nm(0.5)}, [push('out', vr('h'))]),
  blk(
    'forEach',
    {
      'list': ls([tx('a'), tx('b')]),
      'item': 'item',
      'index': 'idx',
    },
    [
      push('out', cat([vr('idx'), tx(':'), vr('item')])),
    ],
  ),
  blk(
    'forPairs',
    {
      'dict': dc({'b': nm(2), 'a': nm(1), '10': tx('x'), '中': yes()}),
      'key': 'kk',
      'value': 'vv',
    },
    [
      iff(op2('==', vr('kk'), tx('a')), [blk('continue')], noElse: true),
      push('out', cat([vr('kk'), tx('='), vr('vv')])),
    ],
  ),
  blk('repeat', {'times': nm(2)}, [push('out', tx('r'))]),
  // 循环套循环：跳出只出最里面那一层
  blk(
    'forCount',
    {'name': 'p', 'from': nm(1), 'to': nm(2), 'step': nm(1)},
    [
      blk(
        'forCount',
        {'name': 'p2', 'from': nm(1), 'to': nm(9), 'step': nm(1)},
        [
          iff(op2('>', vr('p2'), vr('p')), [blk('break')], noElse: true),
          push('out', op2('*', vr('p'), vr('p2'))),
        ],
      ),
    ],
  ),
  json(vr('out')),
]);

/// GET /logic：短路的并且 / 或者、值版的如果（没挑中的不算）、取负、空值、类型判断、转换、复制。
J _logic() {
  J pop() => ex('listPop', {'xs': vr('side')});
  J lg(String op, J l, J r) => ex('logic', {'l': l, 'op': op, 'r': r});
  return route('logic', 'GET', '/logic', [
    let('side', ls([nm(1), nm(2), nm(3), nm(4)])),
    let('a', lg('and', no(), op2('==', pop(), nm(4)))), // 右边不算，side 还是 4 项
    let('b', lg('or', yes(), op2('==', pop(), nm(4)))), // 右边不算
    let('c', lg('and', yes(), op2('==', pop(), nm(4)))), // 右边算了：取走 4
    let('d', lg('or', no(), op2('==', pop(), nm(4)))), // 右边算了：取走 3，不等于 4
    let('c1', ex('cond', {'cond': yes(), 'then': tx('成立'), 'orElse': pop()})), // 没挑中的不算
    let('c2', ex('cond', {'cond': q('missing'), 'then': pop(), 'orElse': tx('不成立')})),
    let('cp', ex('copy', {'x': vr('side')})),
    push('cp', tx('只加在复制品上')),
    blk('do', {'value': pop()}), // “算一下”：取走 2
    blk('note', {'text': '备注不做任何事 */ --> \n第二行'}),
    json(
      dc({
        'a': vr('a'),
        'b': vr('b'),
        'c': vr('c'),
        'd': vr('d'),
        'c1': vr('c1'),
        'c2': vr('c2'),
        'side': vr('side'),
        'cp': vr('cp'),
        'neg': ex('neg', {'x': nm(5)}),
        'negText': ex('neg', {'x': tx('2.5')}),
        'nul': ex('null'),
        'types': ls([
          for (final (x, t) in [(nm(1), 'number'), (tx('1'), 'number'), (tx(''), 'text'), (no(), 'bool'), (ex('null'), 'null'), (ls([]), 'list'), (dc({}), 'dict'), (ls([]), 'dict')])
            ex('isType', {'x': x, 'type': t}),
        ]),
        'conv': ls([
          fam('convert', 'toNumber', {'x': tx('12.5')}),
          fam('convert', 'toNumber', {'x': tx('abc')}),
          fam('convert', 'toText', {'x': nm(3)}),
          fam('convert', 'toText', {
            'x': ls([nm(1), tx('a')]),
          }),
          fam('convert', 'toBool', {'x': tx('')}),
          fam('convert', 'toBool', {'x': ls([])}),
        ]),
      }),
    ),
  ]);
}

/// GET /math：取整族、绝对值、平方根、最大最小、乘方、余数、随机数（只看范围）。
J _math() => route('math', 'GET', '/math', [
  let('r', ex('random', {'a': nm(3), 'b': nm(5)})),
  json(
    ls([
      fam('round', 'round', {'x': nm(2.5)}),
      fam('round', 'round', {'x': nm(-2.5)}),
      fam('round', 'floor', {'x': nm(-1.2)}),
      fam('round', 'ceil', {'x': nm(1.2)}),
      fam('math', 'abs', {'x': nm(-3.5)}),
      fam('math', 'sqrt', {'x': nm(16)}),
      fam('math', 'sqrt', {'x': nm(-4)}),
      fam('minmax', 'max', {'a': nm(2), 'b': qn('n')}),
      fam('minmax', 'min', {'a': nm(2), 'b': qn('n')}),
      ex('pow', {'a': nm(2), 'b': nm(10)}),
      ex('pow', {'a': nm(-8), 'b': nm(0.5)}),
      op2('%', nm(7), nm(3)),
      op2('%', nm(-7), nm(3)),
      ex('logic', {'l': op2('>=', vr('r'), nm(3)), 'op': 'and', 'r': op2('<=', vr('r'), nm(5))}),
      op2('==', vr('r'), fam('round', 'round', {'x': vr('r')})),
      ex('random', {'a': nm(4), 'b': nm(4)}),
    ]),
  ),
]);

/// GET /text：文字各族。
J _text() {
  final s = q('s');
  return route('text', 'GET', '/text', [
    json(
      dc({
        'charAt': ls([
          ex('charAt', {'s': s, 'i': nm(1)}),
          ex('charAt', {'s': s, 'i': nm(99)}),
        ]),
        'substring': ex('substring', {'s': s, 'from': nm(1), 'to': nm(3)}),
        'indexOf': ls([
          ex('indexOf', {'sub': tx('b'), 's': s}),
          ex('indexOf', {'sub': tx('zz'), 's': s}),
        ]),
        'has': ls([
          for (final fn in ['contains', 'startsWith', 'endsWith']) fam('textHas', fn, {'s': s, 'sub': tx('ab')}),
        ]),
        'replace': ex('replace', {'s': s, 'from': tx('b'), 'to': tx('[B]')}),
        'case': ls([
          for (final fn in ['trim', 'upper', 'lower'])
            fam('textCase', fn, {
              's': cat([tx('  '), s, tx('\t')]),
            }),
        ]),
        'repeat': ex('repeatText', {'s': tx('哈'), 'n': nm(3)}),
        'split': ex('split', {'s': s, 'sep': tx('b')}),
        'chars': ex('split', {'s': tx('a😀中'), 'sep': tx('')}),
        'template': ex('template', {
          's': tx('你好，{name}！{n} 岁，{没有} 原样'),
          'dict': dc({'name': s, 'n': nm(3)}),
        }),
        'len': _len(s),
        'toJson': ex('toJson', {
          'x': dc({
            'b': ls([nm(1), tx('二'), ex('null')]),
            'a': yes(),
          }),
        }),
        'fromJson': ex('fromJson', {'s': tx('{"k":[1,2,{"深":null}],"a":1.5}')}),
        'badJson': ex('fromJson', {'s': tx('{坏的')}),
      }),
    ),
  ]);
}

/// GET /lists：列表各族。
J _lists() => route('lists', 'GET', '/lists', [
  let('xs', ls([nm(3), tx('b'), nm(1), tx('a'), nm(2)])),
  blk('listInsert', {'xs': vr('xs'), 'i': nm(0), 'v': tx('头')}),
  blk('listInsert', {'xs': vr('xs'), 'i': _len(vr('xs')), 'v': tx('尾')}),
  blk('listRemove', {'xs': vr('xs'), 'i': nm(1)}),
  let('popped', ex('listPop', {'xs': vr('xs')})),
  json(
    dc({
      'xs': vr('xs'),
      'popped': vr('popped'),
      'range': ex('range', {'a': nm(1), 'b': nm(10), 'step': nm(4)}),
      'rangeDown': ex('range', {'a': nm(3), 'b': nm(1), 'step': nm(-1)}),
      'rangeZero': ex('range', {'a': nm(1), 'b': nm(3), 'step': nm(0)}),
      'get': ex('listGet', {'xs': vr('xs'), 'i': nm(1)}),
      'contains': ls([
        ex('listContains', {'xs': vr('xs'), 'v': tx('a')}),
        ex('listContains', {'xs': vr('xs'), 'v': tx('zz')}),
      ]),
      'indexOf': ls([
        ex('listIndexOf', {'v': nm(1), 'xs': vr('xs')}),
        ex('listIndexOf', {'v': tx('zz'), 'xs': vr('xs')}),
      ]),
      'slice': ex('listSlice', {'xs': vr('xs'), 'from': nm(1), 'to': nm(3)}),
      'concat': ex('listConcat', {
        'a': ls([nm(1)]),
        'b': ls([tx('二'), ls([])]),
      }),
      'reverse': fam('listOrder', 'listReverse', {'xs': vr('xs')}),
      'sort': fam('listOrder', 'listSort', {'xs': vr('xs')}),
      'join': ex('listJoin', {'xs': vr('xs'), 'sep': tx('-')}),
      'len': _len(vr('xs')),
    }),
  ),
]);

/// GET /dicts：字典各族；旧的“字典的字段”和新的读法混用。
J _dicts() => route('dicts', 'GET', '/dicts', [
  let('d', dc({'b': nm(2), 'a': nm(1)})),
  blk('dictSet', {'d': vr('d'), 'k': nm(10), 'v': tx('十')}),
  blk('dictSet', {'d': vr('d'), 'k': tx('gone'), 'v': nm(0)}),
  blk('dictRemove', {'d': vr('d'), 'k': tx('gone')}),
  blk('dictRemove', {'d': vr('d'), 'k': tx('本来就没有')}),
  json(
    dc({
      'd': vr('d'),
      'get': ls([
        ex('dictGet', {'d': vr('d'), 'k': tx('a')}),
        ex('dictGet', {'d': vr('d'), 'k': nm(10)}),
        ex('dictGet', {'d': vr('d'), 'k': tx('没有')}),
      ]),
      'field': ex('field', {'of': vr('d'), 'key': 'b'}),
      'has': ls([
        ex('dictHas', {'d': vr('d'), 'k': tx('a')}),
        ex('dictHas', {'d': vr('d'), 'k': tx('gone')}),
      ]),
      'keys': fam('dictPart', 'dictKeys', {'d': vr('d')}),
      'values': fam('dictPart', 'dictValues', {'d': vr('d')}),
      'pairs': fam('dictPart', 'dictPairs', {'d': vr('d')}),
      'merge': ex('dictMerge', {
        'a': vr('d'),
        'b': dc({'a': tx('盖掉'), 'z': ex('null')}),
      }),
      'len': _len(vr('d')),
    }),
  ),
]);

/// POST /mix/:id：新旧积木互相套——旧“如果”里放新循环、新循环里放“返回”和数据集合积木、旧“对每一项”里放新积木、
/// 文档里声明的变量和这个接口里新建的变量一起用。
J _mix() => route('mix', 'POST', '/mix/:id', [
  // 旧“如果”（带“否则”）里套新的“当…时重复”，循环里提前“返回”
  iff(
    op2('==', ex('pathParam', {'name': 'id'}), tx('early')),
    [
      let('n', nm(0)),
      blk(
        'while',
        {'cond': yes()},
        [
          setv('n', op2('+', vr('n'), nm(1))),
          iff(op2('>=', vr('n'), nm(3)), [
            text(cat([tx('第 '), vr('n'), tx(' 遍就返回')]), 201),
          ]),
        ],
      ),
    ],
    orElse: [setv('total', nm(100))],
  ),
  // 新循环里放数据集合积木，结果放进文档变量；循环变量进了旧积木的参数
  blk(
    'forCount',
    {
      'name': 'i',
      'from': nm(1),
      'to': ex('bodyField', {'name': 'count'}),
      'step': nm(1),
    },
    [
      blk('dbInsert', {
        'collection': 'notes',
        'value': dc({
          'n': vr('i'),
          'tag': ex('pathParam', {'name': 'id'}),
        }),
        'into': 'saved',
      }),
      blk('changeVar', {'name': 'total', 'by': vr('i')}),
    ],
  ),
  // 旧“对每一项”（不带序号）里放新积木
  let('ids', ls([])),
  blk(
    'forEach',
    {
      'list': ex('dbAll', {'collection': 'notes'}),
      'item': 'item',
    },
    [
      push('ids', ex('field', {'of': vr('item'), 'key': 'n'})),
      iff(op2('>=', _len(vr('ids')), nm(3)), [blk('break')], noElse: true),
    ],
  ),
  blk('log', {
    'value': cat([tx('mix '), vr('total')]),
  }),
  json(
    dc({
      'total': vr('total'),
      'ids': vr('ids'),
      'last': ex('field', {'of': vr('saved'), 'key': 'n'}),
      'count': ex('dbCount', {'collection': 'notes'}),
    }),
  ),
]);

/// GET /oops：小库抛错（改列表里没有的位置）→ 500，各语言一样。
J _oops() => route('oops', 'GET', '/oops', [
  let('xs', ls([nm(1)])),
  blk('listSet', {'xs': vr('xs'), 'i': nm(5), 'v': nm(0)}),
  json(vr('xs')),
]);

List<J> langBlocksRoutes() => [_basics(), _loops(), _logic(), _math(), _text(), _lists(), _dicts(), _mix(), _oops()];
