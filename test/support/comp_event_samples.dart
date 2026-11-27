// 第四轮 B4：事件带数据的两个样例组件，和用它们的页面。
import 'package:lopicode/lowcode/model.dart';

import 'comp_samples.dart';
import 'comp_steps.dart';

/// 标签条（带数据）：点哪个标签就发“选了一个”，带上那一项的文字和它是第几个（数据来自“重复”带出的项）。
Map<String, Object?> pickBarDef([String id = 'c5']) => {
  'id': id,
  'name': '可选标签条',
  'props': [
    {'name': 'tags', 'type': 'list', 'default': <Object?>[]},
    {'name': 'picked', 'type': 'text', 'default': ''},
  ],
  'root': cn(
    'bar',
    'row',
    {'gap': 6},
    [
      cn(
        'chip',
        'button',
        {'text': '标签'},
        [],
        {
          'repeat': {'list': cFrom('tags'), 'item': 'it', 'index': 'i'},
          'data': {'text': cFrom('it')},
          'classIf': [
            {
              'name': 'on',
              'when': cExpr(cBin('==', cVar('it'), cVar('picked'))),
              'style': {'font-weight': '700'},
            },
          ],
          'emit': {
            'click': {
              'event': 'pick',
              'args': {'tag': cFrom('it'), 'at': cFrom('i')},
            },
          },
        },
      ),
    ],
  ),
  'events': [
    {
      'name': 'pick',
      'label': '选了一个',
      'params': [
        {'name': 'tag', 'type': 'text'},
        {'name': 'at', 'type': 'number'},
      ],
    },
  ],
};

/// 加量按钮（带数据）：点一下发“要加”，带上属性 step（数据来自组件属性，不在“重复”里）。
Map<String, Object?> addButtonDef([String id = 'c6']) => {
  'id': id,
  'name': '加量按钮',
  'props': [
    {'name': 'step', 'type': 'number', 'default': 1},
  ],
  'root': cn('wrap', 'row', {}, [
    cn(
      'go',
      'button',
      {'text': '加'},
      [],
      {
        'emit': {
          'click': {
            'event': 'add',
            'args': {'n': cFrom('step')},
          },
        },
      },
    ),
  ]),
  'events': [
    {
      'name': 'add',
      'label': '要加',
      'params': [
        {'name': 'n', 'type': 'number'},
      ],
    },
  ],
};

const Map<String, Object?> _event = {'e': 'event'};

/// 页面：标签条选了哪个 → 状态 cur 设成事件带来的值；两个加量按钮（step 5 和 7）→ 状态 got 设成事件带来的值。
/// [withPick] 为否时不放标签条（给摊开的那两种导出用：“重复”里带出的项在摊开的处理里拿不到）。
Map<String, Object?> compEventPageJson({bool withPick = true}) => {
  'version': 3,
  'title': 'Pick',
  'logic': {
    'variables': [
      {
        'name': 'tagList',
        'type': 'list',
        'initial': ['水果', '蔬菜', '零食'],
      },
      {'name': 'cur', 'type': 'text', 'initial': '蔬菜'},
      {'name': 'got', 'type': 'number', 'initial': 0},
    ],
  },
  'components': [if (withPick) pickBarDef(), addButtonDef()],
  'root': cn('root', 'page', {}, [
    if (withPick)
      cn(
        'tags',
        'component',
        {'ref': 'c5'},
        [],
        {
          'data': {'tags': cFrom('tagList'), 'picked': cFrom('cur')},
          'on': {
            'pick': [
              {
                'op': 'setVar',
                'args': {'name': 'cur', 'value': _event},
              },
            ],
          },
        },
      ),
    cn(
      'curText',
      'text',
      {'text': ''},
      [],
      {
        'data': {
          'text': cExpr(cJoin([cText('现在选的：'), cVar('cur')])),
        },
      },
    ),
    for (final (id, step) in [('a5', 5), ('a7', 7)])
      cn(
        id,
        'component',
        {
          'ref': 'c6',
          'values': {'step': step},
        },
        [],
        {
          'on': {
            'add': [
              {
                'op': 'setVar',
                'args': {'name': 'got', 'value': _event},
              },
            ],
          },
        },
      ),
    cn(
      'gotText',
      'text',
      {'text': ''},
      [],
      {
        'data': {
          'text': cExpr(cJoin([cText('拿到 '), cVar('got')])),
        },
      },
    ),
  ]),
};

LcDocument compEventDoc({bool withPick = true}) => LcDocument.fromJson(compEventPageJson(withPick: withPick).cast<String, dynamic>());

const Map<String, String> kCompEventDefs = {'tags': 'c5', 'a5': 'c6', 'a7': 'c6'};

/// 加量按钮那几步（三种网页导出都走）。
CompSteps addButtonSteps() => [
  {'op': 'text', 'sel': '.n-gotText', 'is': '拿到 0'},
  {'op': 'click', 'sel': '.n-a5__go'},
  {'op': 'text', 'sel': '.n-gotText', 'is': '拿到 5'},
  {'op': 'click', 'sel': '.n-a7__go'},
  {'op': 'text', 'sel': '.n-gotText', 'is': '拿到 7'},
  {'op': 'click', 'sel': '.n-a5__go'},
  {'op': 'text', 'sel': '.n-gotText', 'is': '拿到 5'},
];

/// 标签条那几步（只有组件文件的两种导出走）。
CompSteps pickBarSteps() => [
  {'op': 'count', 'sel': '.n-tags__chip', 'is': 3},
  {'op': 'text', 'sel': '.n-curText', 'is': '现在选的：蔬菜'},
  {'op': 'hasClass', 'sel': '.n-tags__chip', 'is': true, 'name': 'on', 'at': 1},
  {'op': 'click', 'sel': '.n-tags__chip', 'at': 2},
  {'op': 'text', 'sel': '.n-curText', 'is': '现在选的：零食'},
  {'op': 'hasClass', 'sel': '.n-tags__chip', 'is': true, 'name': 'on', 'at': 2},
  {'op': 'hasClass', 'sel': '.n-tags__chip', 'is': false, 'name': 'on', 'at': 1},
  {'op': 'click', 'sel': '.n-tags__chip', 'at': 0},
  {'op': 'text', 'sel': '.n-curText', 'is': '现在选的：水果'},
];
