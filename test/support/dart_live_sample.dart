import 'dart:convert';

import 'package:lopicode/lowcode/model.dart';

/// 第四轮 B1：Flutter“会动的”导出的样例（一页）——bind_sample / theme_bp_sample 没盖到的那些：
/// 网格（跨列、平板上换列数）、开关 / 单选 / 下拉 / 多行输入框 / 数字输入框的双向绑定、样式绑定（颜色、字号）、
/// 输入框聚焦时的边框颜色、按钮禁用时的底色、禁用绑状态、图片地址绑状态、顶栏标题绑状态、弹窗标题绑状态、平板上不显示的一块。
Map<String, Object?> _n(String id, String type, [Map<String, Object?> props = const {}, List<Object?> children = const [], Map<String, Object?> more = const {}]) => {
  'id': id,
  'type': type,
  if (props.isNotEmpty) 'props': props,
  if (children.isNotEmpty) 'children': children,
  ...more,
};

Map<String, Object?> _var(String name) => {'e': 'var', 'name': name};
Map<String, Object?> _text(String v) => {'e': 'text', 'v': v};
Map<String, Object?> _join(List<Object> items) => {'e': 'join', 'items': items};
Map<String, Object?> _expr(Object e) => {'from': 'expr', 'expr': e};
Map<String, Object?> _from(String name) => {'from': 'var', 'name': name};
Map<String, Object?> _data(String prop, Object src) => {
  'data': {prop: src},
};

Map<String, Object?> dartLiveSampleJson() => {
  'version': 3,
  'id': 'live',
  'title': 'Live',
  'theme': {
    'vars': {'color-accent': '#058654', 'space-sm': '8px', 'font-family-x': 'serif'},
  },
  'logic': {
    'variables': [
      {'name': 'on', 'type': 'bool', 'initial': false},
      {'name': 'pick', 'type': 'text', 'initial': 'a'},
      {'name': 'city', 'type': 'text', 'initial': ''},
      {'name': 'note', 'type': 'text', 'initial': ''},
      {'name': 'n', 'type': 'number', 'initial': 2},
      {'name': 'tint', 'type': 'text', 'initial': '#FF0000'},
      {'name': 'photo', 'type': 'text', 'initial': ''},
      {
        'name': 'twice',
        'type': 'number',
        'initial': 0,
        'kind': 'derived',
        'expr': {
          'e': 'bin',
          'op': '*',
          'l': _var('n'),
          'r': {'e': 'num', 'v': 2},
        },
      },
    ],
    'handlers': const <Object?>[],
  },
  'root': _n(
    'root',
    'page',
    {'padding': 16, 'gap': 12, 'bg': '#FFFFFF'},
    [
      _n('bar', 'appBar', {'title': '标题'}, const [], _data('title', _expr(_join([_text('数到 '), _var('n')])))),
      _n(
        'grid',
        'container',
        {'width': 'fill'},
        [
          _n(
            'cellA',
            'card',
            {'padding': 8},
            [
              _n('cellAText', 'text', {'text': '甲（跨两列）'}),
            ],
            {
              'style': {'grid-column': 'span 2'},
            },
          ),
          _n(
            'cellB',
            'card',
            {'padding': 8},
            [
              _n('cellBText', 'text', {'text': '乙'}),
            ],
          ),
          _n(
            'cellC',
            'card',
            {'padding': 8},
            [
              _n('cellCText', 'text', {'text': '丙'}),
            ],
          ),
        ],
        {
          'style': {'display': 'grid', 'grid-template-columns': 'repeat(2, 1fr)', 'column-gap': 'var(--space-sm)', 'row-gap': '8px'},
          'responsive': {
            'tablet': {
              'style': {'grid-template-columns': 'repeat(4, 1fr)'},
            },
          },
        },
      ),
      _n(
        'sw',
        'switch',
        {'checked': false},
        const [],
        {
          'model': {'state': 'on'},
        },
      ),
      _n('swText', 'text', {'text': '开着'}, const [], {'showIf': _from('on')}),
      _n(
        'rd',
        'radio',
        {
          'options': [
            {'value': 'a', 'label': '甲项'},
            {'value': 'b', 'label': '乙项'},
          ],
        },
        const [],
        {
          'model': {'state': 'pick'},
        },
      ),
      _n(
        'rdBtn',
        'radio',
        {
          'variant': 'button',
          'options': [
            {'value': 'a', 'label': '按钮甲'},
            {'value': 'b', 'label': '按钮乙'},
          ],
        },
        const [],
        {
          'model': {'state': 'pick'},
        },
      ),
      _n('rdText', 'text', {'text': '选了'}, const [], _data('text', _expr(_join([_text('选了：'), _var('pick')])))),
      _n(
        'sel',
        'select',
        {
          'placeholder': '选城市',
          'width': 'fill',
          'options': [
            {'value': 'bj', 'label': '北京'},
            {'value': 'sh', 'label': '上海'},
          ],
        },
        const [],
        {
          'model': {'state': 'city'},
        },
      ),
      _n('selText', 'text', {'text': '城市'}, const [], _data('text', _expr(_join([_text('城市：'), _var('city')])))),
      _n(
        'ta',
        'textarea',
        {'placeholder': '备注', 'rows': 2, 'width': 'fill'},
        const [],
        {
          'model': {'state': 'note'},
        },
      ),
      _n(
        'taText',
        'text',
        {'text': '备注'},
        const [],
        {
          ..._data('text', _expr(_join([_text('备注：'), _var('note')]))),
          'renderIf': _expr({'e': 'bin', 'op': '!=', 'l': _var('note'), 'r': _text('')}),
        },
      ),
      _n(
        'num',
        'input',
        {'placeholder': '数字', 'inputType': 'number', 'width': 'fill'},
        const [],
        {
          'model': {'state': 'n'},
          'states': {
            'focused': {'border-top-color': '#FF0000', 'border-right-color': '#FF0000', 'border-bottom-color': '#FF0000', 'border-left-color': '#FF0000'},
          },
        },
      ),
      _n(
        'numText',
        'text',
        {'text': '双倍', 'fontSize': 14, 'color': '#222435'},
        const [],
        {
          ..._data('text', _expr(_join([_text('双倍：'), _var('twice')]))),
          'styles': {
            'color': _from('tint'),
            'font-size': _expr(
              _join([
                {
                  'e': 'bin',
                  'op': '*',
                  'l': _var('n'),
                  'r': {'e': 'num', 'v': 10},
                },
                _text('px'),
              ]),
            ),
            'letter-spacing': _from('tint'),
          },
        },
      ),
      _n(
        'go',
        'button',
        {'text': '提交', 'bg': '#058654', 'color': '#FFFFFF'},
        const [],
        {
          ..._data('disabled', _expr({'e': 'not', 'x': _var('on')})),
          'style': {'background-color': 'var(--color-accent)'},
          'states': {
            'disabled': {'background-color': '#CCCCCC'},
            'pressed': {'color': '#FFFF00'},
          },
        },
      ),
      _n('pic', 'image', {'height': 40, 'alt': '照片'}, const [], _data('src', _from('photo'))),
      _n(
        'phoneOnly',
        'text',
        {'text': '只在手机上'},
        const [],
        {
          'responsive': {
            'tablet': {
              'style': {'display': 'none'},
            },
          },
        },
      ),
      _n('dlg', 'dialog', {'title': '弹窗', 'text': '正文'}, const [], _data('title', _expr(_join([_text('现在是 '), _var('n')])))),
    ],
  ),
};

LcDocument dartLiveSample() => LcDocument.parse(jsonEncode(dartLiveSampleJson()));
