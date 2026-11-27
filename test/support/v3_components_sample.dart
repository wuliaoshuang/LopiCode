import 'dart:convert';

import 'package:lopicode/lowcode/model.dart';

/// 第 3 期第 2 段的样例页：登录页、设置页、带底部导航的首页（第 3 期验收写明要能搭出来的三个），
/// 和一个把 11 个新组件、每个插槽、每种样子、网格、状态样式都用上的页。四种导出的真编译都用它们。
Map<String, Object?> _n(String id, String type, [Map<String, Object?> props = const {}, List<Object?> children = const [], Map<String, Object?> more = const {}]) => {
  'id': id,
  'type': type,
  if (props.isNotEmpty) 'props': props,
  if (children.isNotEmpty) 'children': children,
  ...more,
};

LcDocument _doc(String title, Map<String, Object?> pageProps, List<Object?> children, {Map<String, Object?>? logic}) =>
    LcDocument.parse(jsonEncode({'version': 3, 'title': title, 'root': _n('root', 'page', pageProps, children), 'logic': ?logic}));

/// 登录页：导航栏、账号密码、记住我、协议、登录按钮。
LcDocument v3LoginPage() => _doc(
  'Login',
  {'padding': 16, 'gap': 16, 'bg': '#FFFFFF'},
  [
    _n('bar', 'appBar', {'title': '登录', 'back': true, 'variant': 'center', 'bg': '#FFFFFF', 'color': '#222435', 'width': 'fill'}),
    _n('logo', 'icon', {'icon': 'person', 'size': 56, 'color': '#058654'}),
    _n('hello', 'text', {'text': '欢迎回来', 'fontSize': 24, 'bold': true}),
    _n('user', 'input', {'label': '手机号', 'placeholder': '请输入手机号', 'inputType': 'tel', 'required': true, 'width': 'fill', 'radius': 8}),
    _n('pwd', 'input', {'label': '密码', 'placeholder': '请输入密码', 'inputType': 'password', 'required': true, 'width': 'fill', 'radius': 8}),
    _n(
      'keep',
      'row',
      {'gap': 8, 'width': 'fill', 'justify': 'between'},
      [
        _n('remember', 'checkbox', {'text': '记住我', 'checked': true}),
        _n('forgot', 'text', {'text': '忘记密码？', 'color': '#058654', 'fontSize': 14}),
      ],
    ),
    _n(
      'go',
      'button',
      {'text': '登录', 'bg': '#058654', 'color': '#FFFFFF', 'radius': 8, 'padding': 12, 'width': 'fill'},
      const [],
      {
        'states': {
          'pressed': {'background-color': '#046b43'},
          'focused': {'outline': '2px solid #7fd1ae'},
        },
      },
    ),
    _n('agree', 'checkbox', {'text': '我已阅读并同意《用户协议》', 'fontSize': 13, 'color': '#5C6479'}),
  ],
);

/// 设置页：分组的列表行，右边是开关 / 文字 / 箭头；下面一个下拉、一段留言。
LcDocument v3SettingsPage() => _doc(
  'Settings',
  {'padding': 16, 'gap': 12, 'bg': '#F4F7F9'},
  [
    _n(
      'bar',
      'appBar',
      {'title': '设置', 'back': true, 'bg': '#FFFFFF', 'color': '#222435', 'width': 'fill', 'sticky': true},
      [
        _n('more', 'icon', {'icon': 'more_horiz', 'size': 24}, const [], {'slot': 'right'}),
      ],
    ),
    _n(
      'g1',
      'card',
      {'bg': '#FFFFFF', 'radius': 12, 'width': 'fill'},
      [
        _n(
          'me',
          'listItem',
          {'title': '霜霜', 'subtitle': '点这里改资料', 'variant': 'two', 'chevron': true, 'width': 'fill'},
          [
            _n('face', 'icon', {'icon': 'person', 'size': 40, 'color': '#058654'}, const [], {'slot': 'left'}),
          ],
        ),
      ],
    ),
    _n(
      'g2',
      'card',
      {'bg': '#FFFFFF', 'radius': 12, 'width': 'fill'},
      [
        _n(
          'notify',
          'listItem',
          {'title': '消息通知', 'chevron': false, 'width': 'fill'},
          [
            _n('bell', 'icon', {'icon': 'mail', 'size': 24}, const [], {'slot': 'left'}),
            _n('notifySw', 'switch', {'checked': true}, const [], {'slot': 'right'}),
          ],
        ),
        _n('d1', 'divider'),
        _n(
          'dark',
          'listItem',
          {'title': '深色模式', 'chevron': false, 'width': 'fill'},
          [
            _n('darkSw', 'switch', {'checked': false}, const [], {'slot': 'right'}),
          ],
        ),
        _n('d2', 'divider'),
        _n('lang', 'listItem', {'title': '语言', 'trailing': '简体中文', 'chevron': true, 'width': 'fill'}),
      ],
    ),
    _n(
      'g3',
      'card',
      {'bg': '#FFFFFF', 'radius': 12, 'padding': 16, 'gap': 12, 'width': 'fill'},
      [
        _n('sizeLabel', 'text', {'text': '字号', 'fontSize': 14, 'color': '#5C6479'}),
        _n('size', 'radio', {
          'variant': 'button',
          'value': 'm',
          'options': [
            {'value': 's', 'label': '小'},
            {'value': 'm', 'label': '中'},
            {'value': 'l', 'label': '大'},
          ],
        }),
        _n('city', 'select', {
          'placeholder': '选择地区',
          'width': 'fill',
          'radius': 8,
          'options': [
            {'value': 'bj', 'label': '北京'},
            {'value': 'sh', 'label': '上海'},
          ],
        }),
        _n('note', 'textarea', {'label': '意见反馈', 'placeholder': '想说点什么', 'rows': 3, 'maxLength': 200, 'width': 'fill', 'radius': 8}),
      ],
    ),
    _n('out', 'button', {'text': '退出登录', 'bg': '#FFFFFF', 'color': '#C62828', 'radius': 12, 'padding': 12, 'width': 'fill'}),
    _n('sure', 'dialog', {'title': '退出登录', 'text': '确定要退出吗？', 'variant': 'confirm', 'okText': '退出', 'cancelText': '再想想'}),
  ],
  logic: {
    'variables': const <Object?>[],
    'handlers': [
      {
        'id': 'h1',
        'event': 'click',
        'target': 'out',
        'body': [
          {
            'op': 'setProp',
            'args': {
              'node': 'sure',
              'prop': 'visible',
              'value': {'e': 'bool', 'v': true},
            },
            'body': const <Object?>[],
            'else': const <Object?>[],
          },
        ],
      },
    ],
  },
);

/// 带底部导航的首页：导航栏、标签页（两个页签里各有内容）、网格、底部导航。
LcDocument v3HomePage() => _doc(
  'Home',
  {'padding': 16, 'gap': 12, 'bg': '#FFFFFF'},
  [
    _n(
      'bar',
      'appBar',
      {'title': '首页', 'bg': '#058654', 'color': '#FFFFFF', 'width': 'fill'},
      [
        _n('find', 'icon', {'icon': 'search', 'size': 24, 'color': '#FFFFFF'}, const [], {'slot': 'right'}),
      ],
    ),
    _n(
      'grid',
      'container',
      {'width': 'fill'},
      [
        for (final (i, name) in ['订单', '收藏', '下载', '邮件'].indexed)
          _n(
            'cell$i',
            'column',
            {'align': 'center', 'gap': 4, 'padding': 8},
            [
              _n('cellIcon$i', 'icon', {
                'icon': const ['edit', 'favorite', 'download', 'mail'][i],
                'size': 28,
                'color': '#058654',
              }),
              _n('cellText$i', 'text', {'text': name, 'fontSize': 13}),
            ],
          ),
      ],
      {
        'style': {'display': 'grid', 'grid-template-columns': 'repeat(4, 1fr)', 'column-gap': '8px', 'row-gap': '8px'},
      },
    ),
    _n(
      'tabs',
      'tabs',
      {
        'tabs': [
          {'id': 'hot', 'label': '热门'},
          {'id': 'new', 'label': '最新'},
        ],
        'current': 'hot',
        'width': 'fill',
        'color': '#058654',
      },
      [
        _n('hot1', 'listItem', {'title': '第一条热门', 'subtitle': '刚刚', 'variant': 'two', 'chevron': true, 'width': 'fill'}, const [], {'slot': 'hot'}),
        _n('hot2', 'listItem', {'title': '第二条热门', 'subtitle': '一小时前', 'variant': 'two', 'chevron': true, 'width': 'fill'}, const [], {'slot': 'hot'}),
        _n('new1', 'text', {'text': '最新的内容在这里'}, const [], {'slot': 'new'}),
      ],
    ),
    _n('nav', 'bottomNav', {
      'items': [
        {'icon': 'home', 'label': '首页'},
        {'icon': 'search', 'label': '发现'},
        {'icon': 'person', 'label': '我的'},
      ],
      'current': 0,
      'bg': '#FFFFFF',
      'color': '#058654',
      'width': 'fill',
    }),
  ],
);

/// 11 个新组件、每个插槽、每种样子都用上；文字里带会捣乱的字符。
LcDocument v3AllPage() => _doc(
  'All',
  {'padding': 12, 'gap': 10},
  [
    _n(
      'bar',
      'appBar',
      {'title': '全部 <组件> & "引号"', 'back': true, 'variant': 'center', 'bg': '#FFFFFF', 'width': 'fill'},
      [
        _n('barL', 'icon', {'icon': 'menu'}, const [], {'slot': 'left'}),
        _n('barR', 'button', {'text': '存', 'padding': 6}, const [], {'slot': 'right'}),
      ],
    ),
    _n('bar2', 'appBar', {'title': '不在最上面的导航栏', 'width': 'fill'}),
    _n('ic', 'icon', {'icon': 'star', 'size': 32, 'color': '#E0A100'}),
    _n('icBad', 'icon', {'icon': 'star'}),
    _n('ta', 'textarea', {'value': '第一行\n第二行 </textarea> {{ x }}', 'placeholder': '写点什么', 'rows': 2, 'autoGrow': true, 'width': 'fill'}),
    _n('taOff', 'textarea', {'label': '备注 <b>', 'required': true, 'disabled': true, 'maxLength': 50, 'width': 'fill'}),
    _n(
      'row',
      'row',
      {'gap': 12},
      [
        _n('sw', 'switch', {'checked': true}),
        _n('swOff', 'switch', {'checked': false, 'disabled': true}),
        _n('cb', 'checkbox', {'text': '同意 {条款}', 'checked': true}),
        _n('cbOff', 'checkbox', {'text': '不能点', 'disabled': true}),
      ],
    ),
    _n('rd', 'radio', {
      'value': 'b',
      'direction': 'row',
      'options': [
        {'value': 'a', 'label': '甲'},
        {'value': 'b', 'label': '乙 "x"'},
        {'value': 'c'},
      ],
    }),
    _n('rdBtn', 'radio', {
      'variant': 'button',
      'value': 'x',
      'disabled': true,
      'options': [
        {'value': 'x', 'label': '左'},
        {'value': 'y', 'label': '右'},
      ],
    }),
    _n('sel', 'select', {
      'value': 'b',
      'width': 'fill',
      'options': [
        {'value': 'a', 'label': '苹果'},
        {'value': 'b', 'label': '香蕉 <b>'},
      ],
    }),
    _n('selEmpty', 'select', {
      'placeholder': '请选择',
      'disabled': true,
      'options': [
        {'value': 'a'},
      ],
    }),
    _n(
      'li',
      'listItem',
      {'title': '两行的列表行', 'subtitle': '副标题', 'trailing': '说明', 'variant': 'two', 'chevron': true, 'width': 'fill', 'bg': '#F4F7F9'},
      [
        _n('liL', 'icon', {'icon': 'home'}, const [], {'slot': 'left'}),
        _n('liR', 'switch', {'checked': true}, const [], {'slot': 'right'}),
        _n('liLost', 'text', {'text': '没写插槽'}),
      ],
    ),
    _n('li1', 'listItem', {'title': '一行的列表行', 'chevron': false, 'width': 'fill'}),
    _n(
      'tb',
      'tabs',
      {
        'variant': 'pill',
        'tabs': [
          {'id': 'a', 'label': '甲'},
          {'id': 'b', 'label': '乙'},
          {'id': 'c'},
        ],
        'current': 'b',
        'width': 'fill',
      },
      [
        _n('tbA', 'text', {'text': '甲页签的内容'}, const [], {'slot': 'a'}),
        _n('tbB', 'input', {'placeholder': '乙页签里的输入框', 'width': 'fill'}, const [], {'slot': 'b'}),
        _n('tbB2', 'button', {'text': '乙页签里的按钮'}, const [], {'slot': 'b'}),
      ],
    ),
    _n('open', 'button', {'text': '打开弹窗'}),
    // 第四轮 B5 加的滑块（B6 补进样例页；放在按钮后面，前面各项的位置不变）。
    _n('sld', 'slider', {'value': 30, 'min': 0, 'max': 200, 'step': 5, 'width': 'fill'}),
    _n(
      'dlg',
      'dialog',
      {'title': '自己的内容', 'variant': 'alert', 'dismissible': false, 'open': false},
      [
        _n('dlgIn', 'input', {'placeholder': '弹窗里的输入框', 'width': 'fill'}, const [], {'slot': 'content'}),
        _n('dlgNote', 'text', {'text': '没写插槽的算内容'}),
        _n('dlgOk', 'button', {'text': '知道了'}, const [], {'slot': 'footer'}),
      ],
    ),
    _n('dlg2', 'dialog', {'title': '一开始就开着', 'text': '点确定关掉', 'variant': 'confirm', 'open': true}),
    _n('nav', 'bottomNav', {
      'variant': 'iconOnly',
      'items': [
        {'icon': 'home', 'label': '首页'},
        {'icon': 'star'},
      ],
      'current': 1,
      'width': 'fill',
    }),
  ],
  logic: {
    'variables': const <Object?>[],
    'handlers': [
      {
        'id': 'h1',
        'event': 'click',
        'target': 'open',
        'body': [
          {
            'op': 'setProp',
            'args': {
              'node': 'dlg',
              'prop': 'visible',
              'value': {'e': 'bool', 'v': true},
            },
            'body': const <Object?>[],
            'else': const <Object?>[],
          },
        ],
      },
    ],
  },
);

/// 四个样例页（名字 → 文档）。
Map<String, LcDocument Function()> v3ComponentSamples() => {'登录页': v3LoginPage, '设置页': v3SettingsPage, '带底部导航的首页': v3HomePage, '11 个新组件都用上的页': v3AllPage};
