// 第四轮 B7：容器的“禁用”“说明文字”，图标按钮（内置组件库）的“禁用”“说明文字”。
// 一页：四个能点的容器（没禁用 / 写死禁用 / 禁用绑在状态上）、两个图标按钮（写死禁用 / 禁用绑在状态上）、一个“锁上”按钮。
// 点到的都给 hits 加 1；禁用着的点了不加。
import 'package:lopicode/lowcode/comp_lib_builtin.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/slots.dart';

import 'comp_samples.dart';
import 'comp_steps.dart';

Map<String, Object?> _hit(String id, String target) => {
  'id': id,
  'event': 'click',
  'target': target,
  'body': [
    {
      'op': 'changeVar',
      'args': {'name': 'hits', 'by': cNum(1)},
    },
  ],
};

const Map<String, Object?> _tapHit = {
  'tap': [
    {
      'op': 'changeVar',
      'args': {
        'name': 'hits',
        'by': {'e': 'num', 'v': 1},
      },
    },
  ],
};

LcDocument boxOffDoc() {
  final doc = LcDocument.fromJson(
    <String, Object?>{
      'version': 3,
      'title': 'BoxOff',
      'logic': {
        'variables': [
          {'name': 'hits', 'type': 'number', 'initial': 0},
          {'name': 'off', 'type': 'bool', 'initial': false},
          {'name': 'tip', 'type': 'text', 'initial': '会锁上的块'},
        ],
        'handlers': [
          _hit('h1', 'a'),
          _hit('h2', 'b'),
          _hit('h3', 'c'),
          {
            'id': 'h4',
            'event': 'click',
            'target': 'lock',
            'body': [
              {
                'op': 'setVar',
                'args': {
                  'name': 'off',
                  'value': {'e': 'bool', 'v': true},
                },
              },
            ],
          },
        ],
      },
      'root': cn('root', 'page', {}, [
        cn(
          'hitText',
          'text',
          {'text': ''},
          [],
          {
            'data': {
              'text': cExpr(cJoin([cText('点了 '), cVar('hits'), cText(' 次')])),
            },
          },
        ),
        cn(
          'a',
          'container',
          {'alt': '加一'},
          [
            cn('aText', 'text', {'text': '能点的块'}),
          ],
        ),
        cn(
          'b',
          'container',
          {'disabled': true, 'alt': '关着的块'},
          [
            cn('bText', 'text', {'text': '禁用的块'}),
          ],
        ),
        cn(
          'c',
          'container',
          {},
          [
            cn('cText', 'text', {'text': '会锁上的块'}),
          ],
          {
            'data': {'disabled': cFrom('off'), 'alt': cFrom('tip')},
          },
        ),
        cn('lock', 'button', {'text': '锁上'}),
        cn(
          'ib',
          'component',
          {
            'ref': lcBuiltinDefId('iconButton'),
            'values': {'disabled': true, 'label': '收藏'},
          },
          [],
          {'on': _tapHit},
        ),
        cn(
          'ib2',
          'component',
          {
            'ref': lcBuiltinDefId('iconButton'),
            'values': {'label': '点赞'},
          },
          [],
          {
            'data': {'disabled': cFrom('off')},
            'on': _tapHit,
          },
        ),
        cn('ib3', 'component', {'ref': lcBuiltinDefId('iconButton')}, [], {'on': _tapHit}),
      ]),
    }.cast<String, dynamic>(),
  );
  lcEnsureBuiltin(doc, lcBuiltinDefId('iconButton'));
  lcLinkInstances(doc);
  return LcDocument.parse(doc.encode());
}

/// 在浏览器里要走的步骤（tool/verify/run_dom.mjs 照着做）。
CompSteps boxOffSteps() => [
  {'op': 'text', 'sel': '.n-hitText', 'is': '点了 0 次'},
  {'op': 'click', 'sel': '.n-a'},
  {'op': 'text', 'sel': '.n-hitText', 'is': '点了 1 次'},
  // 写死禁用的容器：点它、点它里面的字，都不算数
  {'op': 'click', 'sel': '.n-b'},
  {'op': 'click', 'sel': '.n-bText'},
  {'op': 'text', 'sel': '.n-hitText', 'is': '点了 1 次'},
  // 禁用绑在状态上的：这会儿没禁用，点得动
  {'op': 'click', 'sel': '.n-c'},
  {'op': 'text', 'sel': '.n-hitText', 'is': '点了 2 次'},
  // 图标按钮：写死禁用的点了不发事件；另两个发
  {'op': 'click', 'sel': '.n-ib'},
  {'op': 'text', 'sel': '.n-hitText', 'is': '点了 2 次'},
  {'op': 'click', 'sel': '.n-ib2'},
  {'op': 'click', 'sel': '.n-ib3'},
  {'op': 'text', 'sel': '.n-hitText', 'is': '点了 4 次'},
  // 锁上：绑着状态的两个都点不动了，别的照旧
  {'op': 'click', 'sel': '.n-lock'},
  {'op': 'click', 'sel': '.n-c'},
  {'op': 'click', 'sel': '.n-cText'},
  {'op': 'click', 'sel': '.n-ib2'},
  {'op': 'text', 'sel': '.n-hitText', 'is': '点了 4 次'},
  {'op': 'click', 'sel': '.n-a'},
  {'op': 'click', 'sel': '.n-ib3'},
  {'op': 'text', 'sel': '.n-hitText', 'is': '点了 6 次'},
];

Map<String, String> get kBoxOffDefs => {
  for (final id in ['ib', 'ib2', 'ib3']) id: lcBuiltinDefId('iconButton'),
};
