import 'dart:convert';

import 'package:lopicode/lowcode/model.dart';

/// 第 5 期的样例：两页，带页面级和项目级状态、派生值，8 种绑定各有一处。四种导出的真编译、真跑、画布、冒烟都用它。
///
/// 项目级：user（文字）、cart（列表，每项一条记录）、visits（数字，第二页的按钮给它加一）、cartCount（派生＝cart 有几项）。
/// 首页（home）：count（数字）、keyword（文字）、agree（是 / 否）、names（列表）、tip（派生＝“已点 N 次”）。
/// 第二页（cart）：自己有一个也叫 user 的状态——页面的盖住项目级的。
Map<String, Object?> _n(String id, String type, [Map<String, Object?> props = const {}, List<Object?> children = const [], Map<String, Object?> more = const {}]) => {
  'id': id,
  'type': type,
  if (props.isNotEmpty) 'props': props,
  if (children.isNotEmpty) 'children': children,
  ...more,
};

Map<String, Object?> _var(String name, [List<String> path = const []]) => {'e': 'var', 'name': name, if (path.isNotEmpty) 'path': path};
Map<String, Object?> _text(String v) => {'e': 'text', 'v': v};
Map<String, Object?> _num(num v) => {'e': 'num', 'v': v};
Map<String, Object?> _bin(String op, Object l, Object r) => {'e': 'bin', 'op': op, 'l': l, 'r': r};
Map<String, Object?> _join(List<Object> items) => {'e': 'join', 'items': items};
Map<String, Object?> _expr(Object e) => {'from': 'expr', 'expr': e};
Map<String, Object?> _from(String name, [List<String> path = const []]) => {'from': 'var', 'name': name, if (path.isNotEmpty) 'path': path};

Map<String, Object?> bindSampleJson() => {
  'version': 3,
  'id': 'home',
  'title': 'Home',
  'state': [
    {'name': 'user', 'type': 'text', 'initial': '小塔塔'},
    {
      'name': 'cart',
      'type': 'list',
      'initial': [
        {'id': 'a', 'name': '苹果', 'price': 3},
        {'id': 'b', 'name': '香蕉', 'price': 2},
      ],
    },
    {'name': 'visits', 'type': 'number', 'initial': 0},
    {
      'name': 'cartCount',
      'type': 'number',
      'initial': 0,
      'kind': 'derived',
      'expr': {'e': 'len', 'x': _var('cart')},
    },
  ],
  'root': _n(
    'root',
    'page',
    {'padding': 16, 'gap': 12, 'bg': '#FFFFFF'},
    [
      _n('hello', 'text', {'text': '你好', 'fontSize': 22, 'bold': true}, const [], {
        'data': {
          'text': _expr(_join([_text('你好，'), _var('user')])),
        },
      }),
      _n('tipText', 'text', {'text': '提示'}, const [], {
        'data': {'text': _from('tip')},
      }),
      _n('add', 'button', {'text': '加一', 'radius': 8, 'padding': 12}),
      _n('kw', 'input', {'placeholder': '搜点什么', 'width': 'fill'}, const [], {
        'model': {'state': 'keyword'},
      }),
      _n('echo', 'text', {'text': '你输入的'}, const [], {
        'data': {
          'text': _expr(_join([_text('在搜：'), _var('keyword')])),
        },
        'showIf': _expr(_bin('!=', _var('keyword'), _text(''))),
      }),
      _n('agreeBox', 'checkbox', {'text': '我同意'}, const [], {
        'model': {'state': 'agree'},
      }),
      _n('submit', 'button', {'text': '提交', 'radius': 8, 'padding': 12}, const [], {
        'data': {
          'disabled': _expr({'e': 'not', 'x': _var('agree')}),
        },
        'classIf': [
          {'name': 'ready', 'when': _from('agree')},
        ],
        'styles': {
          'width': _expr(_join([_bin('+', _bin('*', _var('count'), _num(10)), _num(120)), _text('px')])),
        },
      }),
      _n('enough', 'text', {'text': '点够三次了'}, const [], {'renderIf': _expr(_bin('>=', _var('count'), _num(3)))}),
      _n(
        'rowItem',
        'row',
        {'gap': 8, 'width': 'fill'},
        [
          _n('itemName', 'text', {'text': '商品'}, const [], {
            'data': {
              'text': _expr(_join([_bin('+', _var('i'), _num(1)), _text('. '), _var('it', ['name']), _text(' ¥'), _var('it', ['price'])])),
            },
          }),
        ],
        {
          'repeat': {'list': _from('cart'), 'item': 'it', 'index': 'i', 'key': _from('it', ['id']), 'empty': '购物车是空的', 'preview': 3},
        },
      ),
      _n('nameList', 'list', {
        'items': ['一', '二'],
      }, const [], {
        'data': {'items': _from('names')},
      }),
      _n('total', 'text', {'text': '共几件'}, const [], {
        'data': {
          'text': _expr(_join([_text('共 '), _var('cartCount'), _text(' 件')])),
        },
      }),
      _n('homeVisits', 'text', {'text': '来过几次'}, const [], {
        'data': {
          'text': _expr(_join([_text('来过 '), _var('visits'), _text(' 次')])),
        },
      }),
      _n('toCart', 'button', {'text': '去购物车', 'radius': 8, 'padding': 12}),
    ],
  ),
  'logic': {
    'variables': [
      {'name': 'count', 'type': 'number', 'initial': 0},
      {'name': 'keyword', 'type': 'text', 'initial': ''},
      {'name': 'agree', 'type': 'bool', 'initial': false},
      {
        'name': 'names',
        'type': 'list',
        'initial': ['甲', '乙'],
      },
      {
        'name': 'tip',
        'type': 'text',
        'initial': '',
        'kind': 'derived',
        'expr': _join([_text('已点 '), _var('count'), _text(' 次')]),
      },
    ],
    'handlers': [
      {
        'id': 'h1',
        'event': 'click',
        'target': 'add',
        'body': [
          {
            'op': 'changeVar',
            'args': {'name': 'count', 'by': _num(1)},
          },
        ],
      },
      {
        'id': 'h2',
        'event': 'click',
        'target': 'toCart',
        'body': [
          {
            'op': 'goPage',
            'args': {'page': 'cart'},
          },
        ],
      },
    ],
  },
  'pages': [
    {
      'id': 'cart',
      'title': '购物车',
      'root': _n(
        'root',
        'page',
        {'padding': 16, 'gap': 12, 'bg': '#FFFFFF'},
        [
          _n('who', 'text', {'text': '谁'}, const [], {
            'data': {'text': _from('user')},
          }),
          _n('sum', 'text', {'text': '共几件'}, const [], {
            'data': {
              'text': _expr(_join([_text('共 '), _var('cartCount'), _text(' 件')])),
            },
          }),
          _n('cartVisits', 'text', {'text': '来过几次'}, const [], {
            'data': {
              'text': _expr(_join([_text('来过 '), _var('visits'), _text(' 次')])),
            },
          }),
          _n('bump', 'button', {'text': '记一次', 'radius': 8, 'padding': 12}),
          _n('back', 'button', {'text': '回首页', 'radius': 8, 'padding': 12}),
        ],
      ),
      'logic': {
        'variables': [
          {'name': 'user', 'type': 'text', 'initial': '本页的名字'},
        ],
        'handlers': [
          {
            'id': 'h2',
            'event': 'click',
            'target': 'bump',
            'body': [
              {
                'op': 'changeVar',
                'args': {'name': 'visits', 'by': _num(1)},
              },
            ],
          },
          {
            'id': 'h1',
            'event': 'click',
            'target': 'back',
            'body': [
              {
                'op': 'goPage',
                'args': {'page': 'home'},
              },
            ],
          },
        ],
      },
    },
  ],
};

LcDocument bindSample() => LcDocument.parse(jsonEncode(bindSampleJson()));
