/// 内置组件库里“用封装做出来”的 P1 组件（第四轮 B5）：图标按钮、链接、网格、滚动区、步进器、表单项。
/// 这里只有定义的数据（和页面文件里 `components` 一个写法）；怎么列出来、怎么装进文档在 comp_lib_builtin.dart。
///
/// 它们全是拿现成的控件、样式、绑定、往外发的事件、变体拼出来的，没有任何专门给它们写的画法和导出：
/// 四种导出走的就是自定义组件那条路。组件里现在还不能放逻辑，所以：
/// - **步进器**是“受控”的：点加减只往外发“改了”（带着算好的新值），数字自己不变；页面上把“值”绑到一个数字状态、
///   再给“改了”接“把一个状态设成事件带来的值”，就成了。
/// - **链接**去哪：页面上给“点了”接“去页面”或“打开网址”。
library;

Map<String, Object?> _n(String id, String type, [Map<String, Object?> props = const {}, List<Object?> children = const [], Map<String, Object?> more = const {}]) => {
  'id': id,
  'type': type,
  if (props.isNotEmpty) 'props': props,
  ...more,
  if (children.isNotEmpty) 'children': children,
};

Map<String, Object?> _var(String name) => {'e': 'var', 'name': name};
Map<String, Object?> _from(String name) => {'from': 'var', 'name': name};
Map<String, Object?> _expr(Object e) => {'from': 'expr', 'expr': e};
Map<String, Object?> _bin(String op, Object l, Object r) => {'e': 'bin', 'op': op, 'l': l, 'r': r};

const Map<String, Object?> _tap = {
  'click': {'event': 'tap'},
};
const List<Object?> _tapEvent = [
  {'name': 'tap', 'label': '点了'},
];

Map<String, Object?> _stepButton(String id, String text, String op, String edgeOp, String edge) => _n(
  id,
  'button',
  {'text': text, 'padding': 6, 'radius': 6, 'fontSize': 16, 'bg': '#EEF3F5', 'color': '#222435'},
  const [],
  {
    'style': {'min-width': '32px'},
    'data': {'disabled': _expr(_bin(edgeOp, _var('value'), _var(edge)))},
    'emit': {
      'click': {
        'event': 'change',
        'args': {'value': _expr(_bin(op, _var('value'), _var('step')))},
      },
    },
  },
);

/// 六个定义，按组件盒里的先后。
List<Map<String, Object?>> lcBuiltinP1Defs() => [
  {
    'id': 'iconButton',
    'name': '图标按钮',
    'root': _n(
      'btn',
      'container',
      {'padding': 8, 'radius': 20, 'bg': '#EEF3F5', 'width': 40, 'height': 40, 'align': 'center', 'justify': 'center'},
      [
        _n('ic', 'slot', const {}, [
          _n('icon', 'icon', {'icon': 'add', 'size': 24, 'color': '#222435'}),
        ]),
      ],
      {'emit': _tap},
    ),
    'events': _tapEvent,
    'variants': [
      {
        'name': 'outline',
        'label': '描边',
        'group': 'look',
        'groupLabel': '样子',
        'style': {'background-color': 'transparent', 'border': '1px solid #C5D0D6'},
      },
      {
        'name': 'plain',
        'label': '无底',
        'group': 'look',
        'groupLabel': '样子',
        'style': {'background-color': 'transparent'},
      },
    ],
  },
  {
    'id': 'link',
    'name': '链接',
    'props': [
      {'name': 'text', 'type': 'text', 'default': '链接'},
    ],
    'root': _n(
      'a',
      'text',
      {'text': '链接', 'fontSize': 16, 'color': '#1565C0'},
      const [],
      {
        'style': {'text-decoration-line': 'underline', 'cursor': 'pointer'},
        'data': {'text': _from('text')},
        'emit': _tap,
      },
    ),
    'events': _tapEvent,
  },
  {
    'id': 'grid',
    'name': '网格',
    'root': _n(
      'grid',
      'container',
      {'padding': 0, 'width': 'fill'},
      [
        _n('cells', 'slot', const {}, [
          _n('hint', 'text', {'text': '把东西放进来', 'fontSize': 14, 'color': '#7A8791'}),
        ]),
      ],
      {
        'style': {'display': 'grid', 'grid-template-columns': 'repeat(2, 1fr)', 'column-gap': '8px', 'row-gap': '8px'},
      },
    ),
    'variants': [
      for (final n in const [3, 4])
        {
          'name': 'c$n',
          'label': '$n 列',
          'group': 'cols',
          'groupLabel': '列数',
          'style': {'grid-template-columns': 'repeat($n, 1fr)'},
        },
    ],
  },
  {
    'id': 'scroll',
    'name': '滚动区',
    'root': _n(
      'box',
      'container',
      {'padding': 0, 'gap': 8, 'width': 'fill', 'height': 200},
      [
        _n('body', 'slot', const {}, [
          _n('hint', 'text', {'text': '把东西放进来，放多了能滚', 'fontSize': 14, 'color': '#7A8791'}),
        ]),
      ],
      {
        'style': {'overflow-y': 'auto'},
      },
    ),
    'variants': [
      {
        'name': 'row',
        'label': '横着滚',
        'group': 'dir',
        'groupLabel': '方向',
        'style': {'flex-direction': 'row', 'overflow-x': 'auto', 'overflow-y': 'hidden', 'height': 'auto'},
      },
    ],
  },
  {
    'id': 'stepper',
    'name': '步进器',
    'props': [
      {'name': 'value', 'type': 'number', 'default': 1},
      {'name': 'min', 'type': 'number', 'default': 0},
      {'name': 'max', 'type': 'number', 'default': 99},
      {'name': 'step', 'type': 'number', 'default': 1},
    ],
    'root': _n(
      'box',
      'row',
      {'gap': 8, 'align': 'center'},
      [
        _stepButton('minus', '−', '-', '<=', 'min'),
        _n(
          'num',
          'text',
          {'text': '1', 'fontSize': 16, 'color': '#222435', 'textAlign': 'center'},
          const [],
          {
            'style': {'min-width': '24px'},
            'data': {'text': _from('value')},
          },
        ),
        _stepButton('plus', '+', '+', '>=', 'max'),
      ],
    ),
    'events': [
      {
        'name': 'change',
        'label': '改了',
        'params': [
          {'name': 'value', 'type': 'number'},
        ],
      },
    ],
  },
  {
    'id': 'formItem',
    'name': '表单项',
    'props': [
      {'name': 'label', 'type': 'text', 'default': '标签'},
      {'name': 'required', 'type': 'bool', 'default': false},
      {'name': 'help', 'type': 'text', 'default': ''},
      {'name': 'error', 'type': 'text', 'default': ''},
    ],
    'root': _n(
      'item',
      'column',
      {'gap': 4, 'width': 'fill'},
      [
        _n(
          'main',
          'column',
          {'gap': 4, 'width': 'fill'},
          [
            _n(
              'head',
              'row',
              {'gap': 2},
              [
                _n(
                  'label',
                  'text',
                  {'text': '标签', 'fontSize': 14, 'color': '#4A5560'},
                  const [],
                  {
                    'data': {'text': _from('label')},
                  },
                ),
                _n('star', 'text', {'text': '*', 'fontSize': 14, 'color': '#D32F2F'}, const [], {'renderIf': _from('required')}),
              ],
            ),
            _n('body', 'slot', const {}, [
              _n('field', 'input', {'placeholder': '请输入', 'radius': 8, 'width': 'fill'}),
            ]),
          ],
        ),
        _n(
          'help',
          'text',
          {'text': '', 'fontSize': 12, 'color': '#7A8791'},
          const [],
          {
            'data': {'text': _from('help')},
            'renderIf': _expr(_bin('!=', _var('help'), {'e': 'text', 'v': ''})),
          },
        ),
        _n(
          'error',
          'text',
          {'text': '', 'fontSize': 12, 'color': '#D32F2F'},
          const [],
          {
            'data': {'text': _from('error')},
            'renderIf': _expr(_bin('!=', _var('error'), {'e': 'text', 'v': ''})),
          },
        ),
      ],
    ),
    'variants': [
      {
        'name': 'left',
        'label': '标签在左',
        'group': 'layout',
        'groupLabel': '标签位置',
        'nodes': {
          'main': {
            'style': {'flex-direction': 'row', 'align-items': 'center', 'gap': '8px'},
          },
        },
      },
    ],
  },
];
