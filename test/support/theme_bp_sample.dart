import 'dart:convert';

import 'package:lopicode/lowcode/model.dart';

/// 第 4 期 B2 的样例：两页（首页 / 关于），带一套主题变量；首页的标题、按钮、卡片区用了变量，
/// 卡片区在平板上改成横排、在桌面上再加宽；一个自定义组件“标签”里也用了变量；按钮“按下时”的颜色也是变量。
/// 四种导出的真编译和界面测试都用它。
Map<String, Object?> themeBpSampleJson() => {
  'version': 3,
  'id': 'p1',
  'title': 'Home',
  'root': {
    'id': 'root',
    'type': 'page',
    'props': {'padding': 16, 'gap': 12, 'bg': '#FFFFFF'},
    'style': {'background-color': 'var(--color-bg)', 'padding-top': 'var(--space-md)', 'padding-right': 'var(--space-md)', 'padding-bottom': 'var(--space-md)', 'padding-left': 'var(--space-md)'},
    'children': [
      {
        'id': 'title',
        'type': 'text',
        'props': {'text': '欢迎来到小站', 'fontSize': 20, 'bold': true},
        'style': {'font-size': 'var(--font-lg)', 'color': 'var(--color-text)'},
        'responsive': {
          'tablet': {
            'style': {'font-size': 'var(--font-xl)'},
          },
        },
      },
      {
        'id': 'cards',
        'type': 'container',
        'props': {'direction': 'column', 'gap': 8, 'width': 'fill'},
        'responsive': {
          'tablet': {
            'style': {'flex-direction': 'row'},
          },
          'desktop': {
            'style': {'column-gap': '24px', 'row-gap': '24px'},
          },
        },
        'children': [
          {
            'id': 'cardA',
            'type': 'card',
            'props': {'padding': 12},
            'style': {
              'border-top-left-radius': 'var(--radius-md)',
              'border-top-right-radius': 'var(--radius-md)',
              'border-bottom-right-radius': 'var(--radius-md)',
              'border-bottom-left-radius': 'var(--radius-md)',
            },
            'children': [
              {
                'id': 'cardAText',
                'type': 'text',
                'props': {'text': '草莓蛋糕'},
              },
              {
                'id': 'tagA',
                'type': 'component',
                'props': {
                  'ref': 'c1',
                  'values': {'word': '新品'},
                },
              },
            ],
          },
          {
            'id': 'cardB',
            'type': 'card',
            'props': {'padding': 12},
            'children': [
              {
                'id': 'cardBText',
                'type': 'text',
                'props': {'text': '抹茶卷'},
              },
            ],
          },
        ],
      },
      {
        'id': 'buy',
        'type': 'button',
        'props': {'text': '去看看', 'bg': '#058654', 'color': '#FFFFFF'},
        'style': {'background-color': 'var(--color-primary)'},
        'states': {
          'pressed': {'background-color': 'var(--color-text)'},
        },
      },
    ],
  },
  'components': [
    {
      'id': 'c1',
      'name': '标签',
      'props': [
        {'name': 'word', 'type': 'text', 'default': '标签'},
      ],
      'root': {
        'id': 'tagText',
        'type': 'text',
        'props': {'text': '标签', 'fontSize': 12},
        'bind': {'text': 'word'},
        'style': {'color': 'var(--color-primary)', 'font-size': 'var(--font-sm)'},
      },
    },
  ],
  'pages': [
    {
      'id': 'p2',
      'title': '关于',
      'root': {
        'id': 'root',
        'type': 'page',
        'props': {'padding': 16, 'gap': 12},
        'children': [
          {
            'id': 'about',
            'type': 'text',
            'props': {'text': '关于我们'},
            'style': {'color': 'var(--color-text-muted)'},
          },
        ],
      },
    },
  ],
  'theme': {
    'vars': {
      'color-primary': '#058654',
      'color-text': '#222435',
      'color-text-muted': '#5c6479',
      'color-bg': '#ffffff',
      'font-sm': '12px',
      'font-lg': '20px',
      'font-xl': '30px',
      'space-md': '16px',
      'radius-md': '10px',
    },
    'labels': {'color-primary': '品牌绿'},
  },
};

LcDocument themeBpSample() => LcDocument.parse(jsonEncode(themeBpSampleJson()));
