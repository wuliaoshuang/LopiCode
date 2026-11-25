// “积木第 4 版·第 2 阶段”（函数和“我的积木”）的一致性样本：一份后端积木文档（backend.lc.json 里存的那种结构），
// 顶层带 functions（定义），接口里用调用积木、匿名函数、8 个拿函数当参数的列表操作；后面是一串请求和写死的预期响应。
// test/backend_func_blocks_test.dart 用它生成四种语言的后端真跑。
import 'dart:convert';

import 'package:lopicode/backend/backend_func_edit.dart';
import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/lang/custom_block.dart';
import 'package:lopicode/lowcode/logic_model.dart';

import 'backend_lang_blocks.dart';

// —— 写法 ——
J pm(String name) => ex('param', {'name': name});
J fnDef(String id, String name, List<J> params, List<J> body, {String shape = 'auto'}) => {
  'id': id,
  'look': {'name': name, 'shape': shape},
  'params': params,
  'body': body,
};
J par(String name, {Object? def, bool rest = false}) => {'name': name, 'default': ?def, if (rest) 'rest': true};
J call(String id, [J args = const {}]) => ex('call:$id', args);
J callS(String id, [J args = const {}]) => blk('call:$id', args);
J lam(List<String> params, List<J> body) => ex('lambda', {'params': params, '@body': body});
J arrow(List<String> params, J body) => ex('lambdaExpr', {'params': params, 'body': body});
J ref(String id) => ex('funcRef', {'fn': id});
J callV(J fn, List<J> args) => ex('callValue', {'fn': fn, 'args': args});
J ret(J value) => blk('return', {'value': value});
J hof(String kind, J xs, J fn, [J? init]) => ex(kind, {'xs': xs, 'fn': fn, 'init': ?init});

List<J> funcBlocksFunctions() => [
  fnDef('f1', '加倍', [par('x')], [ret(op2('*', pm('x'), nm(2)))]),
  fnDef('f2', '是偶数', [par('n')], [ret(op2('==', op2('%', pm('n'), nm(2)), nm(0)))]),
  fnDef(
    'f3',
    '打招呼',
    [par('谁', def: '世界'), par('语气', def: '！')],
    [
      ret(cat([tx('你好，'), pm('谁'), pm('语气')])),
    ],
  ),
  fnDef(
    'f4',
    '总和',
    [par('起点', def: 0), par('其余', rest: true)],
    [
      let('s', pm('起点')),
      let('one', nm(0)),
      blk('forEach', {'list': pm('其余'), 'item': 'one'}, [setv('s', op2('+', vr('s'), vr('one')))]),
      ret(vr('s')),
    ],
  ),
  fnDef(
    'f5',
    '阶乘',
    [par('n')],
    [
      iff(op2('<=', pm('n'), nm(1)), [ret(nm(1))], noElse: true),
      ret(op2('*', pm('n'), call('f5', {'n': op2('-', pm('n'), nm(1))}))),
    ],
  ),
  fnDef(
    'f6',
    '记一笔',
    [par('话')],
    [
      blk('log', {
        'value': cat([tx('记：'), pm('话')]),
      }),
    ],
  ),
  fnDef(
    'f7',
    '做两次',
    [par('f'), par('x')],
    [
      ret(
        callV(pm('f'), [
          callV(pm('f'), [pm('x')]),
        ]),
      ),
    ],
  ),
  fnDef(
    'f8',
    '新计数器',
    [par('步长', def: 1)],
    [
      let('n', nm(0)),
      ret(lam([], [setv('n', op2('+', vr('n'), pm('步长'))), ret(vr('n'))])),
    ],
  ),
  // 没有“返回”的函数被当成值用：结果是空。
  fnDef('f9', '什么都不交回', [], [
    blk('do', {'value': nm(1)}),
  ]),
];

List<J> funcBlocksRoutes() => [
  // 定义并调用：语句、值、是否三种样子；递归。
  route('call', 'GET', '/call', [
    callS('f6', {'话': q('n')}),
    json(
      dc({
        'double': call('f1', {'x': qn('n')}),
        'even': call('f2', {'n': qn('n')}),
        'fact': call('f5', {'n': qn('n')}),
        'nothing': call('f9'),
        'if': ex('cond', {
          'cond': call('f2', {'n': qn('n')}),
          'then': tx('双'),
          'orElse': tx('单'),
        }),
      }),
    ),
  ]),
  // 默认参数：一个都不给、只给前一个、只给后一个、都给。
  route('defaults', 'GET', '/defaults', [
    json(
      ls([
        call('f3'),
        call('f3', {'谁': tx('霜霜')}),
        call('f3', {'语气': tx('？')}),
        call('f3', {'谁': tx('咕嘎'), '语气': tx('~')}),
      ]),
    ),
  ]),
  // “剩下的全收”：给一串、给空的、不给、给一个不是列表的值。
  route('rest', 'GET', '/rest', [
    json(
      ls([
        call('f4', {
          '起点': nm(1),
          '其余': ls([nm(2), nm(3), nm(4)]),
        }),
        call('f4', {'起点': nm(10), '其余': ls([])}),
        call('f4', {'起点': nm(5)}),
        call('f4', {
          '其余': ls([nm(7), nm(8)]),
        }),
        call('f4', {'起点': nm(1), '其余': nm(7)}),
      ]),
    ),
  ]),
  // 匿名函数与闭包：改外层变量；函数返回的函数各自记着自己的那份。
  route('closure', 'GET', '/closure', [
    let('count', nm(0)),
    let('add', lam(['x'], [setv('count', op2('+', vr('count'), pm('x'))), ret(vr('count'))])),
    blk('callValueStmt', {
      'fn': vr('add'),
      'args': [nm(5)],
    }),
    let('after', callV(vr('add'), [nm(3)])),
    let('c1', call('f8')),
    let('c2', call('f8', {'步长': nm(10)})),
    json(
      dc({
        'count': vr('count'),
        'after': vr('after'),
        'c1': ls([callV(vr('c1'), []), callV(vr('c1'), []), callV(vr('c1'), [])]),
        'c2': ls([callV(vr('c2'), []), callV(vr('c1'), []), callV(vr('c2'), [])]),
      }),
    ),
  ]),
  // 函数当值传递：“这块积木本身”、短写法、存进变量再调用。
  route('pass', 'GET', '/pass', [
    let('g', ref('f1')),
    let(
      'fs',
      ls([
        ref('f1'),
        arrow(['x'], op2('+', pm('x'), nm(100))),
      ]),
    ),
    json(
      ls([
        call('f7', {'f': ref('f1'), 'x': nm(3)}),
        call('f7', {
          'f': arrow(['x'], op2('+', pm('x'), nm(1))),
          'x': nm(3),
        }),
        callV(vr('g'), [nm(4)]),
        callV(ex('listGet', {'xs': vr('fs'), 'i': nm(1)}), [nm(1)]),
        callV(arrow(['a', 'b'], cat([pm('a'), tx('-'), pm('b')])), [tx('左'), tx('右')]),
      ]),
    ),
  ]),
  // 8 个拿函数当参数的列表操作。
  route('lists', 'GET', '/lists', [
    konst('xs', ls([nm(3), nm(1), nm(4), nm(1), nm(5), nm(9), nm(2), nm(6)])),
    let('seen', ls([])),
    blk('listEach', {
      'xs': vr('xs'),
      'fn': lam(
        ['x'],
        [
          iff(call('f2', {'n': pm('x')}), [push('seen', pm('x'))], noElse: true),
        ],
      ),
    }),
    json(
      dc({
        'each': vr('seen'),
        'map': hof('listMap', vr('xs'), ref('f1')),
        'filter': hof('listFilter', vr('xs'), ref('f2')),
        'find': hof('listFind', vr('xs'), arrow(['x'], op2('>', pm('x'), nm(4)))),
        'findNone': hof('listFind', vr('xs'), arrow(['x'], op2('>', pm('x'), nm(99)))),
        'some': ls([
          hof('listSome', vr('xs'), arrow(['x'], op2('>', pm('x'), nm(8)))),
          hof('listSome', vr('xs'), arrow(['x'], op2('>', pm('x'), nm(9)))),
          hof('listSome', ls([]), ref('f2')),
        ]),
        'every': ls([
          hof('listEvery', vr('xs'), arrow(['x'], op2('>', pm('x'), nm(0)))),
          hof('listEvery', vr('xs'), ref('f2')),
          hof('listEvery', ls([]), ref('f2')),
        ]),
        'reduce': hof('listReduce', vr('xs'), arrow(['acc', 'x'], op2('+', pm('acc'), pm('x'))), nm(100)),
        'reduceText': hof(
          'listReduce',
          vr('xs'),
          lam(
            ['acc', 'x'],
            [
              ret(cat([pm('acc'), pm('x')])),
            ],
          ),
          tx(''),
        ),
        'sort': hof('listSortBy', vr('xs'), arrow(['x'], ex('neg', {'x': pm('x')}))),
        'sortStable': hof('listSortBy', ls([tx('bb'), tx('a'), tx('cc'), tx('d'), tx('eee')]), arrow(['s'], ex('len', {'x': pm('s')}))),
        'chain': hof('listReduce', hof('listMap', hof('listFilter', vr('xs'), ref('f2')), ref('f1')), arrow(['a', 'b'], op2('+', pm('a'), pm('b'))), nm(0)),
        'xs': vr('xs'),
      }),
    ),
  ]),
  // 函数和旧积木混在同一个接口：文档变量、数据集合、请求内容、“如果”。
  route('mix', 'POST', '/mix', [
    setv(
      'total',
      hof(
        'listReduce',
        ex('bodyField', {'name': 'nums'}),
        arrow(['a', 'b'], op2('+', pm('a'), pm('b'))),
        call('f4', {
          '起点': nm(100),
          '其余': ls([nm(1)]),
        }),
      ),
    ),
    blk('dbInsert', {
      'collection': 'notes',
      'value': dc({
        't': call('f3', {
          '谁': ex('bodyField', {'name': 'who'}),
        }),
      }),
      'into': 'saved',
    }),
    blk(
      'if',
      {
        'cond': call('f2', {'n': vr('total')}),
      },
      [
        callS('f6', {
          '话': cat([tx('双 '), vr('total')]),
        }),
      ],
      [
        callS('f6', {
          '话': cat([tx('单 '), vr('total')]),
        }),
      ],
    ),
    json(
      dc({
        'total': vr('total'),
        'count': ex('dbCount', {'collection': 'notes'}),
        'titles': hof('listMap', ex('dbAll', {'collection': 'notes'}), arrow(['row'], ex('field', {'of': pm('row'), 'key': 't'}))),
      }),
      201,
    ),
  ]),
  // 包成积木前后：两个接口的积木一样，测试里把 wrapAfter 的那一截真的“包成积木”，响应要一样。
  for (final id in ['wrapBefore', 'wrapAfter'])
    route(id, 'GET', id == 'wrapBefore' ? '/wrap/before' : '/wrap/after', [
      let('a', qn('a')),
      let('out', ls([])),
      iff(op2('>', vr('a'), nm(0)), [
        push('out', tx('开始')),
        // —— 从这里往下包 ——
        push('out', op2('*', vr('a'), nm(2))),
        blk(
          'forCount',
          {'name': 'i', 'from': nm(1), 'to': vr('a'), 'step': nm(1)},
          [
            push('out', cat([vr('i'), tx('/'), vr('a')])),
          ],
        ),
        blk('log', {
          'value': cat([tx('包 '), vr('a')]),
        }),
      ], noElse: true),
      json(vr('out')),
    ]),
];

J funcBlocksDocumentJson() => {...langBlocksDocumentJson(funcBlocksRoutes()), 'version': 3, 'name': '函数和我的积木', 'functions': funcBlocksFunctions()};

/// 样本文档：读进来以后，把 /wrap/after 里“从第 2 块往下”真的包成积木，再存一遍读回来（走真的存盘路径）。
BeDocument funcBlocksDocument() {
  final doc = parseLangBlocksDocument(funcBlocksDocumentJson());
  final tree = doc.route('wrapAfter')!;
  final from = [lcStep(2), lcStep(1)];
  final outer = beWrapOuterNames(doc, tree, from);
  final made = beWrapTail(doc, tree, from, const CustomBlockLook('填一截'), outer);
  if (made == null) throw StateError('样本里那一截没包成：${beWrapBlocker(doc, tree, from)}');
  final back = BeDocument.parse(jsonEncode(jsonDecode(doc.encode())));
  if (back.note != null) throw StateError(back.note!);
  return back.doc;
}

const List<LangBlocksCase> funcBlocksCases = [
  LangBlocksCase('/call?n=5', '{"double":10,"even":false,"fact":120,"if":"单","nothing":null}'),
  LangBlocksCase('/call?n=4', '{"double":8,"even":true,"fact":24,"if":"双","nothing":null}'),
  LangBlocksCase('/defaults', '["你好，世界！","你好，霜霜！","你好，世界？","你好，咕嘎~"]'),
  LangBlocksCase('/rest', '[10,10,5,15,8]'),
  LangBlocksCase('/closure', '{"after":8,"c1":[1,2,3],"c2":[10,4,20],"count":8}'),
  LangBlocksCase('/closure', '{"after":8,"c1":[1,2,3],"c2":[10,4,20],"count":8}'),
  LangBlocksCase('/pass', '[12,5,8,101,"左-右"]'),
  LangBlocksCase(
    '/lists',
    '{"chain":24,"each":[4,2,6],"every":[true,false,true],"filter":[4,2,6],"find":5,"findNone":null,"map":[6,2,8,2,10,18,4,12],"reduce":131,"reduceText":"31415926","some":[true,false,false],"sort":[9,6,5,4,3,2,1,1],"sortStable":["a","d","bb","cc","eee"],"xs":[3,1,4,1,5,9,2,6]}',
  ),
  LangBlocksCase('/mix', '{"count":1,"titles":["你好，咕嘎！"],"total":107}', method: 'POST', status: 201, body: '{"who":"咕嘎","nums":[1,2,3]}'),
  LangBlocksCase('/mix', '{"count":2,"titles":["你好，咕嘎！","你好，！"],"total":102}', method: 'POST', status: 201, body: '{"nums":[1]}'),
  LangBlocksCase('/wrap/before?a=3', '["开始",6,"1/3","2/3","3/3"]'),
  LangBlocksCase('/wrap/after?a=3', '["开始",6,"1/3","2/3","3/3"]'),
  LangBlocksCase('/wrap/before?a=0', '[]'),
  LangBlocksCase('/wrap/after?a=0', '[]'),
];
const List<String> funcBlocksLogLines = ['记：5', '记：4', '记：单 107', '记：双 102', '包 3', '包 3'];
