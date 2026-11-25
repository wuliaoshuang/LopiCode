// 语言核心一致性用例（二之二）：第 4 版新加的小库函数——列表、字典、通用的取 / 改。

import 'lang_cases_rt_basic.dart';
import 'lang_conformance.dart';

final List<LangCase> kLangRtDataCases = [
  vals('列表：读', [
    (
      ls([
        f('listOf', []),
        f('listOf', [1, '二', null]),
      ]),
      '[[],[1,"二",null]]',
    ),
    (
      ls([
        f('listGet', [
          [1, 2, 3],
          0,
        ]),
        f('listGet', [
          [1, 2, 3],
          2.9,
        ]),
        f('listGet', [
          [1, 2, 3],
          3,
        ]),
        f('listGet', [
          [1, 2, 3],
          -1,
        ]),
        f('listGet', ['abc', 0]),
        f('listGet', [
          [1, 2, 3],
          '1',
        ]),
        f('listGet', [
          [1],
          1e30,
        ]),
      ]),
      '[1,3,null,null,null,2,null]',
    ),
    (
      ls([
        f('listContains', [
          [1, '2', null],
          2,
        ]),
        f('listContains', [
          [1, 2],
          3,
        ]),
        f('listContains', [
          [
            [1],
          ],
          [1],
        ]),
        f('listContains', [5, 5]),
        f('listContains', [
          [null],
          '',
        ]),
      ]),
      '[true,false,true,false,true]',
    ),
    (
      ls([
        f('listIndexOf', [
          [1, 2, 2],
          2,
        ]),
        f('listIndexOf', [
          [1],
          9,
        ]),
        f('listIndexOf', [[], 1]),
        f('listIndexOf', ['abc', 'a']),
        f('listIndexOf', [
          ['a', 'b'],
          'b',
        ]),
      ]),
      '[1,-1,-1,-1,1]',
    ),
    (
      ls([
        f('listSlice', [
          [1, 2, 3, 4],
          1,
          3,
        ]),
        f('listSlice', [
          [1, 2, 3],
          -5,
          99,
        ]),
        f('listSlice', [
          [1, 2, 3],
          2,
          1,
        ]),
        f('listSlice', [5, 0, 1]),
        f('listSlice', [
          [1, 2, 3],
          1.9,
          2.9,
        ]),
      ]),
      '[[2,3],[1,2,3],[],[],[2]]',
    ),
    (
      ls([
        f('listConcat', [
          [1],
          [2, 3],
        ]),
        f('listConcat', [[], []]),
        f('listConcat', [
          5,
          [1],
        ]),
        f('listConcat', [
          [1],
          'x',
        ]),
      ]),
      '[[1,2,3],[],[1],[1]]',
    ),
    (
      ls([
        f('listReverse', [
          [1, 2, 3],
        ]),
        f('listReverse', [[]]),
        f('listReverse', ['abc']),
      ]),
      '[[3,2,1],[],[]]',
    ),
    (
      ls([
        f('listSort', [
          [3, 1, 2],
        ]),
        f('listSort', [
          [10, 9, '10', 'b', 'a', 'B', '中', '😀', 'Ａ', null, true, 2.5, -1],
        ]),
        f('listSort', [[]]),
        f('listSort', [5]),
        f('listSort', [
          [
            [2],
            [1],
            {'a': 1},
          ],
        ]),
        f('listSort', [
          ['b', 'a', 'ab', ''],
        ]),
      ]),
      '[[1,2,3],[-1,2.5,9,10,null,"10","B","a","b",true,"中","Ａ","😀"],[],[],[[1],[2],{"a":1}],["","a","ab","b"]]',
    ),
    (
      ls([
        f('listJoin', [
          [
            1,
            '二',
            null,
            true,
            [3],
          ],
          '-',
        ]),
        f('listJoin', [[], ',']),
        f('listJoin', [
          [1],
          ',',
        ]),
        f('listJoin', [5, ',']),
        f('listJoin', [
          [1, 2],
          0,
        ]),
      ]),
      '["1-二--true-[3]","","1","","102"]',
    ),
    (
      ls([
        f('range', [1, 5, 2]),
        f('range', [3, 1, -1]),
        f('range', [1, 3, 0]),
        f('range', [1, 3, -1]),
        f('range', [0, 1, 0.5]),
        f('range', [2, 2, 1]),
        f('size', [
          f('range', [1, 99999, 1]),
        ]),
        f('range', ['1', '2', '1']),
      ]),
      '[[1,3,5],[3,2,1],[],[],[0,0.5,1],[2],10000,[1,2]]',
    ),
  ]),
  LangCase(
    '列表：原地改 listSet / listPush / listInsert / listRemove / listPop',
    [
      let('xs', ls([1, 2, 3])),
      run(f('listSet', [v('xs'), 0, 'a'])),
      run(f('listSet', [v('xs'), 2.9, 'c'])),
      run(
        f('listPush', [
          v('xs'),
          ls([4]),
        ]),
      ),
      run(f('listInsert', [v('xs'), 0, '头'])),
      run(f('listInsert', [v('xs'), 5, '尾'])),
      run(f('listInsert', [v('xs'), 2, '中'])),
      logJson(v('xs')),
      logJson(
        ls([
          f('listRemove', [v('xs'), 0]),
          f('listRemove', [v('xs'), 5]),
          f('listPop', [v('xs')]),
          f('listPop', [ls([])]),
          f('listPop', [5]),
        ]),
      ),
      logJson(v('xs')),
      // 把列表放进它自己的一项里也不出事（存进去的是当时的同一个列表，JSON 里不展开自己）
      let('ys', ls([])),
      run(f('listPush', [v('ys'), 1])),
      run(
        f('listPush', [
          v('ys'),
          f('copy', [v('ys')]),
        ]),
      ),
      logJson(v('ys')),
    ],
    ['["头","a","中",2,"c",[4],"尾"]', '["头","尾",[4],null,null]', '["a","中",2,"c"]', '[1,[1]]'],
  ),
  vals('字典：读', [
    (
      ls([
        f('dictOf', []),
        f('dictOf', ['b', 1, 'a', 2, 'b', 3]),
        f('dictOf', [1, 'x', null, 'y', true, 'z']),
        f('dictOf', ['只有键']),
      ]),
      '[{},{"a":2,"b":3},{"":"y","1":"x","true":"z"},{}]',
    ),
    (
      ls([
        f('dictGet', [
          {'a': 1},
          'a',
        ]),
        f('dictGet', [
          {'a': 1},
          'b',
        ]),
        f('dictGet', [
          [1],
          0,
        ]),
        f('dictGet', [
          {'1': 'x'},
          1,
        ]),
        f('dictGet', [5, 'a']),
      ]),
      '[1,null,null,"x",null]',
    ),
    (
      ls([
        f('dictHas', [
          {'a': null},
          'a',
        ]),
        f('dictHas', [
          {'a': 1},
          'b',
        ]),
        f('dictHas', [
          [1],
          0,
        ]),
        f('dictHas', [
          {'1': 1},
          1,
        ]),
      ]),
      '[true,false,false,true]',
    ),
    (
      ls([
        f('dictKeys', [
          {'b': 1, 'a': 2, '😀': 3, 'Ａ': 4, '中': 5, 'Z': 6},
        ]),
        f('dictKeys', [<String, Object?>{}]),
        f('dictKeys', [5]),
      ]),
      '[["Z","a","b","中","Ａ","😀"],[],[]]',
    ),
    (
      ls([
        f('dictValues', [
          {'b': 1, 'a': 2},
        ]),
        f('dictValues', [
          [1],
        ]),
        f('dictPairs', [
          {
            'b': 1,
            'a': [2],
          },
        ]),
        f('dictPairs', [null]),
      ]),
      '[[2,1],[],[["a",[2]],["b",1]],[]]',
    ),
    (
      ls([
        f('dictMerge', [
          {'a': 1, 'b': 2},
          {'b': 3, 'c': 4},
        ]),
        f('dictMerge', [
          5,
          {'a': 1},
        ]),
        f('dictMerge', [
          {'a': 1},
          [1],
        ]),
        f('dictMerge', [null, null]),
      ]),
      '[{"a":1,"b":3,"c":4},{"a":1},{"a":1},{}]',
    ),
  ]),
  LangCase(
    '字典：原地改 dictSet / dictRemove；合并出来的是新字典',
    [
      let('d', lx({'a': 1})),
      run(
        f('dictSet', [
          v('d'),
          'b',
          ls([2]),
        ]),
      ),
      run(f('dictSet', [v('d'), 3, '数字键'])),
      run(f('dictSet', [v('d'), 'a', null])),
      run(f('dictRemove', [v('d'), 'b'])),
      run(f('dictRemove', [v('d'), '没有'])),
      logJson(v('d')),
      let(
        'm',
        f('dictMerge', [
          v('d'),
          lx({'z': 1}),
        ]),
      ),
      run(f('dictSet', [v('m'), 'a', '改了'])),
      logJson(ls([v('d'), v('m')])),
    ],
    ['{"3":"数字键","a":null}', '[{"3":"数字键","a":null},{"3":"数字键","a":"改了","z":1}]'],
  ),
  LangCase(
    '通用的取 / 改：item、setItem',
    [
      let('xs', ls([1, 2])),
      let('d', lx({'k': 1})),
      logJson(
        ls([
          f('item', [v('xs'), 1]),
          f('item', [v('d'), 'k']),
          f('item', ['a😀', 1]),
          f('item', [5, 0]),
          f('item', [null, 'a']),
          f('item', [v('xs'), 5]),
          f('item', [true, 0]),
        ]),
      ),
      run(f('setItem', [v('xs'), 0, 'x'])),
      run(f('setItem', [v('d'), 'k', 'y'])),
      run(f('setItem', [v('d'), 'new', 'z'])),
      logJson(ls([v('xs'), v('d')])),
    ],
    ['[2,1,"😀",null,null,null,null]', '[["x",2],{"k":"y","new":"z"}]'],
  ),
];
