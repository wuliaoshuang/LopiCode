import 'dart:convert';

import 'package:lopicode/lowcode/model.dart';

/// 第 4 期的多页面样例：三页（首页 / 商品 / 我的），每页底下一条底部导航互相跳；
/// 一个带插槽的自定义组件“卡片”在两页里都用到（组件是项目级的）；
/// “去页面”三种来路都有：按钮上的快捷操作、行里一段文字上的快捷操作、写在“如果”里面的积木。
/// 四种导出的真编译都用它。第二页的名字是中文（转不出英文类名），专门看起名会不会撞。
Map<String, Object?> _n(String id, String type, [Map<String, Object?> props = const {}, List<Object?> children = const [], Map<String, Object?> more = const {}]) => {
  'id': id,
  'type': type,
  if (props.isNotEmpty) 'props': props,
  if (children.isNotEmpty) 'children': children,
  ...more,
};

Map<String, Object?> _nav(int current) => _n('nav', 'bottomNav', {
  'items': [
    {'icon': 'home', 'label': '首页', 'page': 'p1'},
    {'icon': 'search', 'label': '商品', 'page': 'p2'},
    {'icon': 'person', 'label': '我的', 'page': 'p3'},
  ],
  'current': current,
  'width': 'fill',
});

Map<String, Object?> _go(String id, String target, String page) => {
  'id': id,
  'event': 'click',
  'target': target,
  'body': [
    {
      'op': 'goPage',
      'args': {'page': page},
    },
  ],
};

Map<String, Object?> pagesSampleJson() => {
  'version': 3,
  'id': 'p1',
  'title': 'Home',
  'root': _n(
    'root',
    'page',
    {'padding': 16, 'gap': 12, 'bg': '#FFFFFF'},
    [
      _n('bar', 'appBar', {'title': '首页', 'width': 'fill'}),
      _n('hello', 'text', {'text': '欢迎', 'fontSize': 22, 'bold': true}),
      _n(
        'card',
        'component',
        {
          'ref': 'c1',
          'values': {'title': '今日推荐'},
        },
        [
          _n('cardText', 'text', {'text': '草莓蛋糕'}),
        ],
      ),
      _n('toList', 'button', {'text': '去看商品', 'bg': '#058654', 'color': '#FFFFFF', 'radius': 8, 'padding': 12, 'width': 'fill'}),
      _n(
        'line',
        'row',
        {'gap': 8, 'width': 'fill'},
        [
          _n('more', 'text', {'text': '我的资料'}),
          _n('count', 'input', {'placeholder': '数量', 'width': 120}),
        ],
      ),
      _n('check', 'button', {'text': '数量够了就去我的', 'radius': 8, 'padding': 12}),
      _nav(0),
    ],
  ),
  'logic': {
    'variables': [
      {'name': 'n', 'type': 'number', 'initial': 0},
    ],
    'handlers': [
      _go('h1', 'toList', 'p2'),
      _go('h2', 'more', 'p3'),
      {
        'id': 'h3',
        'event': 'click',
        'target': 'check',
        'body': [
          {
            'op': 'if',
            'args': {
              'cond': {
                'e': 'bin',
                'op': '>',
                'l': {'e': 'prop', 'node': 'count', 'prop': 'value'},
                'r': {'e': 'num', 'v': 2},
              },
            },
            'body': [
              {
                'op': 'goPage',
                'args': {'page': 'p3'},
              },
            ],
            'else': [
              {
                'op': 'alert',
                'args': {
                  'message': {'e': 'text', 'v': '再多填一点'},
                },
              },
            ],
          },
        ],
      },
    ],
  },
  'components': [
    {
      'id': 'c1',
      'name': 'Card',
      'props': [
        {'name': 'title', 'type': 'text', 'default': '标题'},
      ],
      'root': _n(
        'k1',
        'card',
        {'padding': 12, 'gap': 8, 'radius': 12, 'bg': '#F4F7F9', 'width': 'fill'},
        [
          _n(
            'k2',
            'text',
            {'text': '标题', 'bold': true},
            const [],
            {
              'bind': {'text': 'title'},
            },
          ),
          _n('k3', 'slot', const {}, [
            _n('k4', 'text', {'text': '（空的）', 'color': '#5C6479'}),
          ]),
        ],
      ),
    },
  ],
  'pages': [
    {
      'id': 'p2',
      'title': '商品列表',
      'root': _n(
        'root',
        'page',
        {'padding': 16, 'gap': 12, 'bg': '#FFFFFF'},
        [
          _n('bar', 'appBar', {'title': '商品', 'width': 'fill', 'back': true}),
          _n('card', 'component', {
            'ref': 'c1',
            'values': {'title': '蛋糕'},
          }),
          _n('item', 'listItem', {'title': '回首页', 'chevron': true, 'width': 'fill'}),
          _nav(1),
        ],
      ),
      'logic': {
        'variables': <Object?>[],
        'handlers': [_go('h1', 'item', 'p1')],
      },
    },
    {
      'id': 'p3',
      'title': 'Me',
      'root': _n(
        'root',
        'page',
        {'padding': 16, 'gap': 12, 'bg': '#FFFFFF'},
        [
          _n('name', 'text', {'text': '霜霜', 'fontSize': 22, 'bold': true}),
          _n('back', 'button', {'text': '回首页', 'radius': 8, 'padding': 12}),
          _nav(2),
        ],
      ),
      'logic': {
        'variables': <Object?>[],
        'handlers': [_go('h1', 'back', 'p1')],
      },
    },
  ],
};

LcDocument pagesSample() => LcDocument.parse(jsonEncode(pagesSampleJson()));
