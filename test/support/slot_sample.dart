import 'dart:convert';

import 'package:lopicode/lowcode/model.dart';

/// 第 3 期第 3 段的样例页：一个带插槽的自定义组件“商品卡片”（默认插槽“内容”＋具名插槽“底部按钮”，各有默认内容），
/// 页面上放两个实例——第一个两个插槽都填了，第二个什么都没填（显示默认内容）。四种导出的真编译都用它。
Map<String, Object?> slotCardJson() => {
  'version': 3,
  'title': 'Shop',
  'root': {
    'id': 'root',
    'type': 'page',
    'props': {'padding': 16, 'gap': 12, 'bg': '#F4F7F9'},
    'children': [
      {
        'id': 'head',
        'type': 'text',
        'props': {'text': '今日推荐', 'fontSize': 22, 'bold': true},
      },
      {
        'id': 'a',
        'type': 'component',
        'props': {
          'ref': 'c1',
          'values': {'title': '草莓蛋糕'},
        },
        'children': [
          // 没写 slot：算在默认插槽里
          {
            'id': 'p1',
            'type': 'text',
            'props': {'text': '新鲜草莓，当天现做', 'width': 'fill'},
          },
          {
            'id': 'p2',
            'type': 'text',
            'props': {'text': '¥ 68', 'color': '#C2410C', 'bold': true},
            'slot': 'default',
          },
          {
            'id': 'b1',
            'type': 'button',
            'props': {'text': '立即购买', 'bg': '#058654', 'color': '#FFFFFF', 'radius': 8, 'padding': 10},
            'slot': 'footer',
          },
          {
            'id': 'b2',
            'type': 'button',
            'props': {'text': '收藏', 'radius': 8, 'padding': 10},
            'slot': 'footer',
          },
        ],
      },
      {
        'id': 'b',
        'type': 'component',
        'props': {'ref': 'c1'},
      },
    ],
  },
  'components': [
    {
      'id': 'c1',
      'name': 'ProductCard 商品卡片',
      'props': [
        {'name': 'title', 'type': 'text', 'default': '商品名'},
      ],
      'root': {
        'id': 'k1',
        'type': 'card',
        'props': {'padding': 12, 'gap': 8, 'bg': '#FFFFFF', 'radius': 12, 'width': 'fill'},
        'children': [
          {
            'id': 'k2',
            'type': 'text',
            'props': {'text': '商品名', 'fontSize': 18, 'bold': true},
            'bind': {'text': 'title'},
          },
          {
            'id': 'k3',
            'type': 'column',
            'props': {'gap': 6, 'width': 'fill'},
            'children': [
              {
                'id': 'k4',
                'type': 'slot',
                'name': '内容',
                'children': [
                  {
                    'id': 'k5',
                    'type': 'text',
                    'props': {'text': '暂无介绍', 'color': '#5C6479'},
                  },
                ],
              },
            ],
          },
          {
            'id': 'k6',
            'type': 'row',
            'props': {'gap': 8, 'width': 'fill', 'justify': 'end'},
            'children': [
              {
                'id': 'k7',
                'type': 'slot',
                'name': '底部按钮',
                'props': {'name': 'footer'},
                'children': [
                  {
                    'id': 'k8',
                    'type': 'button',
                    'props': {'text': '加入购物车', 'radius': 8, 'padding': 10},
                  },
                ],
              },
            ],
          },
        ],
      },
      'slots': [
        {'name': 'default', 'label': '内容'},
        {'name': 'footer', 'label': '底部按钮'},
      ],
    },
  ],
};

LcDocument slotCardPage() => LcDocument.parse(jsonEncode(slotCardJson()));
