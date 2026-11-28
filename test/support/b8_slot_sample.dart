// 第四轮 B8：插槽内容拿到组件里的数据——一页样例。
import 'package:lopicode/lowcode/model.dart';

import 'comp_samples.dart';
import 'comp_steps.dart';

/// 组件“清单”：属性 `title`（文字）、`rows`（列表）；自己的状态 `picked`（文字，开始是“还没选”）。
/// 里面一个按 `rows` 重复的容器，容器里是默认插槽——它给外面三样：`thing`＝这一项、`no`＝第几项、`head`＝组件的标题。
/// 另一个命名插槽 `foot` 给外面 `chosen`＝组件自己的状态。
/// 页面：一个实例（标题“清单甲”，rows 绑到页面状态 `fruits`——列表属性只能绑、不能写死），默认插槽里填一行字“〔页面状态 shop〕·〔head〕第〔no〕个：〔thing〕”，
/// `foot` 里填一行字“选的是〔chosen〕”；再一个不填内容的实例（用默认内容）；按钮 `rename` 把 `shop` 改成“水果摊”。
LcDocument b8SlotDoc() => LcDocument.fromJson(
  <String, Object?>{
    'version': 3,
    'title': 'B8Slot',
    'logic': {
      'variables': [
        {'name': 'shop', 'type': 'text', 'initial': '小店'},
        {
          'name': 'fruits',
          'type': 'list',
          'initial': ['苹果', '香蕉'],
        },
      ],
      'handlers': [
        {
          'id': 'h1',
          'event': 'click',
          'target': 'rename',
          'body': [
            {
              'op': 'setVar',
              'args': {'name': 'shop', 'value': cText('水果摊')},
            },
          ],
        },
      ],
    },
    'components': [
      {
        'id': 'lst',
        'name': '清单',
        'props': [
          {'name': 'title', 'type': 'text', 'default': '清单'},
          {'name': 'rows', 'type': 'list', 'default': <Object?>[]},
        ],
        'state': [
          {'name': 'picked', 'type': 'text', 'initial': '还没选'},
        ],
        'root': cn(
          'col',
          'column',
          {'gap': 4},
          [
            cn(
              'line',
              'container',
              {},
              [
                cn(
                  'cell',
                  'slot',
                  {},
                  [
                    cn('dflt', 'text', {'text': '（没填）'}),
                  ],
                  {
                    'gives': {'thing': cFrom('it'), 'no': cExpr(cBin('+', cVar('i'), cNum(1))), 'head': cFrom('title')},
                  },
                ),
              ],
              {
                'repeat': {'list': cFrom('rows'), 'item': 'it', 'index': 'i'},
              },
            ),
            cn(
              'foot',
              'slot',
              {'name': 'foot'},
              [],
              {
                'gives': {'chosen': cFrom('picked')},
              },
            ),
          ],
        ),
      },
    ],
    'root': cn(
      'root',
      'page',
      {'padding': 16, 'gap': 8},
      [
        cn(
          'a',
          'component',
          {
            'ref': 'lst',
            'values': {'title': '清单甲'},
          },
          [
            cn(
              'fill',
              'text',
              {'text': ''},
              [],
              {
                'data': {
                  'text': cExpr(cJoin([cVar('shop'), cText('·'), cVar('head'), cText('第'), cVar('no'), cText('个：'), cVar('thing')])),
                },
              },
            ),
            cn(
              'tail',
              'text',
              {'text': ''},
              [],
              {
                'slot': 'foot',
                'data': {
                  'text': cExpr(cJoin([cText('选的是'), cVar('chosen')])),
                },
              },
            ),
          ],
          {
            'data': {'rows': cFrom('fruits')},
          },
        ),
        cn('b', 'component', {
          'ref': 'lst',
          'values': {'title': '另一张'},
        }),
        cn('rename', 'button', {'text': '改名'}),
      ],
    ),
  }.cast<String, dynamic>(),
);

CompSteps b8SlotSteps() => [
  {'op': 'count', 'sel': '.n-fill', 'is': 2},
  {'op': 'text', 'sel': '.n-fill', 'at': 0, 'is': '小店·清单甲第1个：苹果'},
  {'op': 'text', 'sel': '.n-fill', 'at': 1, 'is': '小店·清单甲第2个：香蕉'},
  {'op': 'text', 'sel': '.n-tail', 'is': '选的是还没选'},
  {'op': 'click', 'sel': '.n-rename'},
  {'op': 'text', 'sel': '.n-fill', 'at': 0, 'is': '水果摊·清单甲第1个：苹果'},
  {'op': 'text', 'sel': '.n-fill', 'at': 1, 'is': '水果摊·清单甲第2个：香蕉'},
];
