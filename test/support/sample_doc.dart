import 'dart:convert';

import 'package:lopicode/lowcode/model.dart';

/// 覆盖所有组件类型和各种嵌套情况的示例页面。
LcDocument sample() => LcDocument.parse(jsonEncode({
  'version': 1,
  'title': '登录页 Demo',
  'root': {
    'id': 'root',
    'type': 'page',
    'props': {'padding': 16, 'gap': 12, 'bg': '#f6fbfd'},
    'children': [
      {'id': 't1', 'type': 'text', 'props': {'text': "欢迎 <b>'回来'</b> \$5", 'fontSize': 24, 'bold': true, 'textAlign': 'center', 'width': 'fill'}},
      {
        'id': 'card',
        'type': 'card',
        'props': {'padding': 16, 'gap': 8, 'bg': '#FFFFFF', 'radius': 12, 'width': 'fill'},
        'children': [
          {'id': 'in', 'type': 'input', 'props': {'placeholder': '手机号', 'width': 'fill'}},
          {
            'id': 'row',
            'type': 'row',
            'props': {'gap': 8, 'justify': 'between', 'width': 'fill'},
            'children': [
              {'id': 'b1', 'type': 'button', 'props': {'text': '登录', 'bg': '#058654', 'color': '#FFFFFF', 'width': 'fill'}},
              {'id': 'b2', 'type': 'button', 'props': {'text': '注册', 'width': 96}},
              {'id': 'in2', 'type': 'input', 'props': {'placeholder': '行内输入'}},
              {'id': 'tx', 'type': 'text', 'props': {'text': '行内文本'}},
              {'id': 'dv', 'type': 'divider'},
              {'id': 'sp', 'type': 'spacer', 'props': {'size': 8}},
            ],
          },
        ],
      },
      {'id': 'img', 'type': 'image', 'props': {'height': 120, 'radius': 8, 'width': 'fill'}},
      {'id': 'img2', 'type': 'image', 'props': {'src': 'https://example.com/a.png', 'height': 80, 'width': 80}},
      {'id': 'ls', 'type': 'list', 'props': {'items': ['一', '二 & 三'], 'padding': 8, 'bg': '#FFFFFF'}},
      {'id': 'col', 'type': 'column', 'props': {'gap': 4, 'align': 'stretch'}, 'children': [
        {'id': 'c1', 'type': 'container', 'props': {'height': 40, 'bg': '#D3DEE4', 'margin': 4}},
      ]},
      {'id': 'dv2', 'type': 'divider', 'props': {'margin': 8}},
      {'id': 'sp2', 'type': 'spacer', 'props': {'size': 24}},
    ],
  },
}));
