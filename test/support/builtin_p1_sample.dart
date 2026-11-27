// 第四轮 B5：内置组件库里六个 P1 组件（图标按钮、链接、网格、滚动区、步进器、表单项）各放一个的两页样例，
// 和在浏览器里要走的步骤（tool/verify/run_dom.mjs 照着做）。
import 'package:lopicode/lowcode/comp_lib_builtin.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/slots.dart';

import 'comp_samples.dart';
import 'comp_steps.dart';

const Map<String, Object?> _event = {'e': 'event'};

Map<String, Object?> _inst(String id, String builtin, {Map<String, Object?> values = const {}, List<Object?> children = const [], Map<String, Object?> more = const {}}) =>
    cn(id, 'component', {'ref': lcBuiltinDefId(builtin), if (values.isNotEmpty) 'values': values}, children, more);

/// 首页：步进器（值绑状态 n，1 到 5，一次走 2）、链接（点了去“更多”页）、图标按钮（点了 hits 加 1）、
/// 三列网格（三个格子）、滚动区、表单项（必填、带错误提示、里面一个输入框）。第二页“更多”只有一行字。
LcDocument builtinP1Doc() {
  final doc = LcDocument.fromJson(
    <String, Object?>{
      'version': 3,
      'id': 'home',
      'title': 'Home',
      'logic': {
        'variables': [
          {'name': 'n', 'type': 'number', 'initial': 3},
          {'name': 'hits', 'type': 'number', 'initial': 0},
        ],
      },
      'root': cn('root', 'page', {}, [
        cn(
          'nText',
          'text',
          {'text': ''},
          [],
          {
            'data': {
              'text': cExpr(cJoin([cText('数量 '), cVar('n')])),
            },
          },
        ),
        _inst(
          'st',
          'stepper',
          values: {'min': 1, 'max': 5, 'step': 2},
          more: {
            'data': {'value': cFrom('n')},
            'on': {
              'change': [
                {
                  'op': 'setVar',
                  'args': {'name': 'n', 'value': _event},
                },
              ],
            },
          },
        ),
        _inst(
          'lk',
          'link',
          values: {'text': '去更多'},
          more: {
            'on': {
              'tap': [
                {
                  'op': 'goPage',
                  'args': {'page': 'more'},
                },
              ],
            },
          },
        ),
        _inst(
          'ib',
          'iconButton',
          children: [
            cn('ibIcon', 'icon', {'icon': 'star'}),
          ],
          more: {
            'variant': {'look': 'outline'},
            'on': {
              'tap': [
                {
                  'op': 'changeVar',
                  'args': {'name': 'hits', 'by': cNum(1)},
                },
              ],
            },
          },
        ),
        cn(
          'hitText',
          'text',
          {'text': ''},
          [],
          {
            'data': {
              'text': cExpr(cJoin([cText('点了 '), cVar('hits'), cText(' 次')])),
            },
          },
        ),
        _inst(
          'gr',
          'grid',
          children: [
            for (final i in [1, 2, 3]) cn('g$i', 'text', {'text': '格 $i'}),
          ],
          more: {
            'variant': {'cols': 'c3'},
          },
        ),
        _inst(
          'sc',
          'scroll',
          children: [
            cn('s1', 'text', {'text': '滚动区里的字'}),
          ],
        ),
        _inst(
          'fi',
          'formItem',
          values: {'label': '姓名', 'required': true, 'error': '必填'},
          children: [
            cn('fiIn', 'input', {'placeholder': '你的名字'}),
          ],
        ),
      ]),
      'pages': [
        {
          'id': 'more',
          'title': 'More',
          'root': cn('root', 'page', {}, [
            cn('moreText', 'text', {'text': '这是更多页'}),
          ]),
        },
      ],
    }.cast<String, dynamic>(),
  );
  for (final b in ['stepper', 'link', 'iconButton', 'grid', 'scroll', 'formItem']) {
    lcEnsureBuiltin(doc, lcBuiltinDefId(b));
  }
  lcLinkInstances(doc);
  // 存一遍再读：和手机上“放上画布 → 导出”走的是同一条路。
  return LcDocument.parse(doc.encode());
}

/// 步骤（找元素用摊开时的写法 `.n-<实例>__<控件>`；组件文件的两种导出用 [compFileSteps] 换写法）。
/// [jump]：点链接以后看地址栏（Vue / React；纯网页换页是整页跳转，jsdom 里不走）。
CompSteps builtinP1Steps({required bool jump}) => [
  // 步进器：受控——点加减发“改了”，页面把状态设成带来的值，数字跟着变；到边上按钮禁用
  {'op': 'text', 'sel': '.n-nText', 'is': '数量 3'},
  {'op': 'text', 'sel': '.n-st__num', 'is': '3'},
  {'op': 'disabled', 'sel': '.n-st__plus', 'is': false},
  {'op': 'click', 'sel': '.n-st__plus'},
  {'op': 'text', 'sel': '.n-nText', 'is': '数量 5'},
  {'op': 'text', 'sel': '.n-st__num', 'is': '5'},
  {'op': 'disabled', 'sel': '.n-st__plus', 'is': true},
  {'op': 'click', 'sel': '.n-st__minus'},
  {'op': 'click', 'sel': '.n-st__minus'},
  {'op': 'text', 'sel': '.n-st__num', 'is': '1'},
  {'op': 'text', 'sel': '.n-nText', 'is': '数量 1'},
  {'op': 'disabled', 'sel': '.n-st__minus', 'is': true},
  // 图标按钮：插槽里换上的图标在；点了页面上的数加 1
  {'op': 'count', 'sel': '.n-ibIcon', 'is': 1},
  {'op': 'text', 'sel': '.n-hitText', 'is': '点了 0 次'},
  {'op': 'click', 'sel': '.n-ib'},
  {'op': 'click', 'sel': '.n-ib'},
  {'op': 'text', 'sel': '.n-hitText', 'is': '点了 2 次'},
  // 网格、滚动区：放进去的东西都在
  {'op': 'count', 'sel': '.n-gr > *', 'is': 3},
  {'op': 'text', 'sel': '.n-g2', 'is': '格 2'},
  {'op': 'text', 'sel': '.n-s1', 'is': '滚动区里的字'},
  // 表单项：标签、必填的星号、错误提示在；没写的说明不出现；插槽里的输入框在
  {'op': 'text', 'sel': '.n-fi__label', 'is': '姓名'},
  {'op': 'count', 'sel': '.n-fi__star', 'is': 1},
  {'op': 'text', 'sel': '.n-fi__error', 'is': '必填'},
  {'op': 'count', 'sel': '.n-fi__help', 'is': 0},
  {'op': 'count', 'sel': '.n-fiIn', 'is': 1},
  // 链接
  {'op': 'text', 'sel': '.n-lk', 'is': '去更多'},
  if (jump) ...[
    {'op': 'click', 'sel': '.n-lk'},
    {'op': 'hash', 'is': '#/more'},
    {'op': 'text', 'sel': '.n-moreText', 'is': '这是更多页'},
  ],
];

/// 各实例用的定义（给 [compFileSteps]）。
Map<String, String> get kBuiltinP1Defs => {
  for (final e in {'st': 'stepper', 'lk': 'link', 'ib': 'iconButton', 'gr': 'grid', 'sc': 'scroll', 'fi': 'formItem'}.entries) e.key: lcBuiltinDefId(e.value),
};
