import 'package:lopicode/lowcode/model.dart';

/// 第四轮 B2（组件库）的三种形状的样例组件。每个函数给出“组件定义（JSON）”，页面怎么用另给。
/// 真编译、真跑、Flutter 真装进界面、存库导出导入都用它们。
Map<String, Object?> cn(String id, String type, [Map<String, Object?> props = const {}, List<Object?> children = const [], Map<String, Object?> more = const {}]) => {
  'id': id,
  'type': type,
  if (props.isNotEmpty) 'props': props,
  ...more,
  if (children.isNotEmpty) 'children': children,
};

Map<String, Object?> cVar(String name, [List<String> path = const []]) => {'e': 'var', 'name': name, if (path.isNotEmpty) 'path': path};
Map<String, Object?> cText(String v) => {'e': 'text', 'v': v};
Map<String, Object?> cNum(num v) => {'e': 'num', 'v': v};
Map<String, Object?> cJoin(List<Object> items) => {'e': 'join', 'items': items};
Map<String, Object?> cBin(String op, Object l, Object r) => {'e': 'bin', 'op': op, 'l': l, 'r': r};
Map<String, Object?> cExpr(Object e) => {'from': 'expr', 'expr': e};
Map<String, Object?> cFrom(String name, [List<String> path = const []]) => {'from': 'var', 'name': name, if (path.isNotEmpty) 'path': path};

/// 形状一：商品卡片——默认插槽＋命名插槽、事件“点了加入购物车”（带出名字）、两组变体、定义里的绑定、自己的状态（收藏）。
Map<String, Object?> productCardDef([String id = 'c1']) => {
  'id': id,
  'name': '商品卡片',
  'props': [
    {'name': 'title', 'type': 'text', 'default': '商品'},
    {'name': 'price', 'type': 'number', 'default': 0},
  ],
  'root': cn(
    'card',
    'card',
    {'padding': 12, 'gap': 8},
    [
      cn('pic', 'slot', {}, [
        cn('picText', 'text', {'text': '（放图片）'}),
      ]),
      cn(
        'name',
        'text',
        {'text': '商品', 'fontSize': 16},
        [],
        {
          'data': {'text': cFrom('title')},
        },
      ),
      cn(
        'money',
        'text',
        {'text': '¥0'},
        [],
        {
          'data': {
            'text': cExpr(cJoin([cText('¥'), cVar('price')])),
          },
        },
      ),
      cn(
        'fav',
        'checkbox',
        {'text': '收藏', 'checked': false},
        [],
        {
          'model': {'state': 'liked'},
        },
      ),
      cn('favTip', 'text', {'text': '已收藏'}, [], {'showIf': cFrom('liked')}),
      cn(
        'extraBox',
        'row',
        {'gap': 4},
        [
          cn('extra', 'slot', {'name': 'extra'}),
        ],
      ),
      cn(
        'buy',
        'button',
        {'text': '加入购物车'},
        [],
        {
          'emit': {
            'click': {
              'event': 'addCart',
              'args': {'title': cFrom('title')},
            },
          },
        },
      ),
    ],
  ),
  'events': [
    {
      'name': 'addCart',
      'label': '点了加入购物车',
      'params': [
        {'name': 'title', 'type': 'text'},
      ],
    },
  ],
  'variants': [
    {
      'name': 'hot',
      'label': '热卖',
      'group': 'kind',
      'groupLabel': '样子',
      'style': {'background-color': '#FFF3E0'},
      'nodes': {
        'money': {
          'style': {'color': '#D84315'},
        },
      },
    },
    {
      'name': 'large',
      'label': '大',
      'group': 'size',
      'groupLabel': '大小',
      'nodes': {
        'name': {
          'style': {'font-size': '22px'},
        },
      },
    },
  ],
  'state': [
    {'name': 'liked', 'type': 'bool', 'initial': false},
  ],
};

/// 形状二：登录表单——表单双向（两个输入框双向到属性，属性由页面绑到状态上）、事件“点了登录”、一组变体。
Map<String, Object?> loginFormDef([String id = 'c2']) => {
  'id': id,
  'name': '登录表单',
  'props': [
    {'name': 'user', 'type': 'text', 'default': ''},
    {'name': 'pass', 'type': 'text', 'default': ''},
    {'name': 'caption', 'type': 'text', 'default': '登录'},
  ],
  'root': cn(
    'form',
    'column',
    {'gap': 8, 'padding': 12},
    [
      cn(
        'head',
        'text',
        {'text': '登录'},
        [],
        {
          'data': {'text': cFrom('caption')},
        },
      ),
      cn(
        'userIn',
        'input',
        {'placeholder': '用户名'},
        [],
        {
          'model': {'state': 'user'},
        },
      ),
      cn(
        'passIn',
        'input',
        {'placeholder': '密码', 'inputType': 'password'},
        [],
        {
          'model': {'state': 'pass'},
        },
      ),
      cn(
        'show',
        'checkbox',
        {'text': '显示提示', 'checked': false},
        [],
        {
          'model': {'state': 'showTip'},
        },
      ),
      cn(
        'tip',
        'text',
        {'text': ''},
        [],
        {
          'renderIf': cFrom('showTip'),
          'data': {
            'text': cExpr(cJoin([cText('要登录的是：'), cVar('user')])),
          },
        },
      ),
      cn(
        'go',
        'button',
        {'text': '登录'},
        [],
        {
          'data': {'disabled': cExpr(cBin('==', cVar('user'), cText('')))},
          'emit': {
            'click': {'event': 'submit'},
          },
        },
      ),
      cn('foot', 'slot', {'name': 'foot'}),
    ],
  ),
  'events': [
    {'name': 'submit', 'label': '点了登录'},
  ],
  'variants': [
    {
      'name': 'tight',
      'label': '紧凑',
      'style': {'padding': '4px'},
    },
  ],
  'state': [
    {'name': 'showTip', 'type': 'bool', 'initial': false},
  ],
};

/// 形状三：标签筛选条——重复（列表由页面绑进来）、每一项按“是不是选中的”换类名（类名开关配了样子）、事件“点了清空”。
Map<String, Object?> tagBarDef([String id = 'c3']) => {
  'id': id,
  'name': '标签筛选条',
  'props': [
    {'name': 'tags', 'type': 'list', 'default': <Object?>[]},
    {'name': 'picked', 'type': 'text', 'default': ''},
  ],
  'root': cn(
    'bar',
    'row',
    {'gap': 6, 'padding': 8},
    [
      cn(
        'chip',
        'text',
        {'text': '标签'},
        [],
        {
          'repeat': {'list': cFrom('tags'), 'item': 'it', 'index': 'i', 'empty': '还没有标签'},
          'data': {'text': cFrom('it')},
          'classIf': [
            {
              'name': 'on',
              'when': cExpr(cBin('==', cVar('it'), cVar('picked'))),
              'style': {'color': '#1565C0', 'font-weight': '700'},
            },
          ],
        },
      ),
      cn(
        'count',
        'text',
        {'text': ''},
        [],
        {
          'data': {
            'text': cExpr(
              cJoin([
                cText('共 '),
                {'e': 'len', 'x': cVar('tags')},
                cText(' 个'),
              ]),
            ),
          },
        },
      ),
      cn(
        'clear',
        'button',
        {'text': '清空'},
        [],
        {
          'emit': {
            'click': {'event': 'clear'},
          },
        },
      ),
    ],
  ),
  'events': [
    {'name': 'clear', 'label': '点了清空'},
  ],
};

/// 项目乙：一页，用上面三个组件（[defs] 给哪几个就带哪几个定义）。页面状态：cart（数字）、last（文字）、
/// u / p（文字，登录表单双向到它们）、logged（数字）、tagList（列表）、cur（文字）。
Map<String, Object?> compUserPageJson(List<Map<String, Object?>> defs) => {
  'version': 3,
  'title': 'Shop',
  'logic': {
    'variables': [
      {'name': 'cart', 'type': 'number', 'initial': 0},
      {'name': 'apple', 'type': 'text', 'initial': '苹果'},
      {'name': 'u', 'type': 'text', 'initial': ''},
      {'name': 'p', 'type': 'text', 'initial': ''},
      {'name': 'logged', 'type': 'number', 'initial': 0},
      {
        'name': 'tagList',
        'type': 'list',
        'initial': ['水果', '蔬菜', '零食'],
      },
      {'name': 'cur', 'type': 'text', 'initial': '蔬菜'},
    ],
    'handlers': [
      {
        'id': 'h1',
        'event': 'click',
        'target': 'rename',
        'body': [
          {
            'op': 'setVar',
            'args': {'name': 'apple', 'value': cText('红苹果')},
          },
        ],
      },
    ],
  },
  'components': defs,
  'root': cn('root', 'page', {}, [
    cn(
      'cartText',
      'text',
      {'text': ''},
      [],
      {
        'data': {
          'text': cExpr(cJoin([cText('购物车 '), cVar('cart'), cText(' 件')])),
        },
      },
    ),
    cn('rename', 'button', {'text': '改名'}),
    if (defs.any((d) => d['id'] == 'c1')) ...[
      cn(
        'p1',
        'component',
        {
          'ref': 'c1',
          'values': {'price': 3},
        },
        [
          cn('p1img', 'text', {'text': '苹果的图'}),
          cn('p1tag', 'text', {'text': '新'}, [], {'slot': 'extra'}),
        ],
        {
          'data': {'title': cFrom('apple')},
          'variant': {'kind': 'hot', 'size': 'large'},
          'on': {
            'addCart': [
              {
                'op': 'changeVar',
                'args': {'name': 'cart', 'by': cNum(1)},
              },
            ],
          },
        },
      ),
      cn(
        'p2',
        'component',
        {
          'ref': 'c1',
          'values': {'title': '香蕉', 'price': 2},
        },
        [],
        {
          'on': {
            'addCart': [
              {
                'op': 'changeVar',
                'args': {'name': 'cart', 'by': cNum(10)},
              },
            ],
          },
        },
      ),
    ],
    if (defs.any((d) => d['id'] == 'c2')) ...[
      cn(
        'login',
        'component',
        {
          'ref': 'c2',
          'values': {'caption': '请登录'},
        },
        [
          cn('loginFoot', 'text', {'text': '忘记密码？'}, [], {'slot': 'foot'}),
        ],
        {
          'data': {'user': cFrom('u'), 'pass': cFrom('p')},
          'variant': {'variant': 'tight'},
          'on': {
            'submit': [
              {
                'op': 'changeVar',
                'args': {'name': 'logged', 'by': cNum(1)},
              },
            ],
          },
        },
      ),
      cn(
        'echo',
        'text',
        {'text': ''},
        [],
        {
          'data': {
            'text': cExpr(cJoin([cText('用户='), cVar('u'), cText(' 密码='), cVar('p'), cText(' 登录了 '), cVar('logged'), cText(' 次')])),
          },
        },
      ),
    ],
    if (defs.any((d) => d['id'] == 'c3')) ...[
      cn(
        'tags',
        'component',
        {'ref': 'c3'},
        [],
        {
          'data': {'tags': cFrom('tagList'), 'picked': cFrom('cur')},
          'on': {
            'clear': [
              {
                'op': 'setVar',
                'args': {'name': 'cur', 'value': cText('')},
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
    ],
  ]),
};

LcDocument compUserDoc(List<Map<String, Object?>> defs) => LcDocument.fromJson(compUserPageJson(defs).cast<String, dynamic>());
