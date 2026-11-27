// 第四轮 B7：步进器开箱即用（不接线）、“重复”里的事件带上这一项、Flutter 新认的三样动作——一页样例和浏览器里要走的步骤。
import 'package:lopicode/lowcode/comp_lib_builtin.dart';
import 'package:lopicode/lowcode/model.dart';
import 'package:lopicode/lowcode/slots.dart';

import 'comp_event_samples.dart';
import 'comp_samples.dart';
import 'comp_steps.dart';

const Map<String, Object?> _event = {'e': 'event'};

/// - `st1`：步进器，值写死 3、最大 5，什么线都没接；
/// - `st2`：步进器，值绑状态 n，没接“改了”；旁边一行字“数量 n”；
/// - `st3`：步进器，自己接了“改了”（把 got 设成带来的值）——不替它补线，它自己的数字不动；
/// - `tags`：可选标签条（按钮在“重复”里），接了“选了一个”→ cur 设成带来的那一项；
/// - `a5`：加量按钮（一次 5），接了：重复 3 次｛k 加上带来的数｝；等 30 毫秒｛msg 设成“等完了”｝；打印 k。
LcDocument b7LiveDoc() {
  final doc = LcDocument.fromJson(
    <String, Object?>{
      'version': 3,
      'title': 'B7Live',
      'logic': {
        'variables': [
          {'name': 'n', 'type': 'number', 'initial': 2},
          {'name': 'got', 'type': 'number', 'initial': 0},
          {'name': 'k', 'type': 'number', 'initial': 0},
          {'name': 'msg', 'type': 'text', 'initial': '还没等'},
          {
            'name': 'tagList',
            'type': 'list',
            'initial': ['水果', '蔬菜', '零食'],
          },
          {'name': 'cur', 'type': 'text', 'initial': '蔬菜'},
        ],
      },
      'components': [pickBarDef(), addButtonDef()],
      'root': cn('root', 'page', {}, [
        cn('st1', 'component', {
          'ref': lcBuiltinDefId('stepper'),
          'values': {'value': 3, 'max': 5},
        }),
        cn(
          'st2',
          'component',
          {'ref': lcBuiltinDefId('stepper')},
          [],
          {
            'data': {'value': cFrom('n')},
          },
        ),
        _line('nText', '数量 ', 'n'),
        cn(
          'st3',
          'component',
          {
            'ref': lcBuiltinDefId('stepper'),
            'values': {'value': 7},
          },
          [],
          {
            'on': {
              'change': [
                {
                  'op': 'setVar',
                  'args': {'name': 'got', 'value': _event},
                },
              ],
            },
          },
        ),
        _line('gotText', '带来的是 ', 'got'),
        cn(
          'tags',
          'component',
          {'ref': 'c5'},
          [],
          {
            'data': {'tags': cFrom('tagList'), 'picked': cFrom('cur')},
            'on': {
              'pick': [
                {
                  'op': 'setVar',
                  'args': {'name': 'cur', 'value': _event},
                },
              ],
            },
          },
        ),
        _line('curText', '现在选的：', 'cur'),
        cn(
          'a5',
          'component',
          {
            'ref': 'c6',
            'values': {'step': 5},
          },
          [],
          {
            'on': {
              'add': [
                {
                  'op': 'repeat',
                  'args': {'times': cNum(3)},
                  'body': [
                    {
                      'op': 'changeVar',
                      'args': {'name': 'k', 'by': _event},
                    },
                  ],
                },
                {
                  'op': 'wait',
                  'args': {'ms': cNum(30)},
                  'body': [
                    {
                      'op': 'setVar',
                      'args': {'name': 'msg', 'value': cText('等完了')},
                    },
                  ],
                },
                {
                  'op': 'log',
                  'args': {'value': cVar('k')},
                },
              ],
            },
          },
        ),
        _line('kText', 'k=', 'k'),
        _line('msgText', '', 'msg'),
      ]),
    }.cast<String, dynamic>(),
  );
  lcEnsureBuiltin(doc, lcBuiltinDefId('stepper'));
  lcLinkInstances(doc);
  return LcDocument.parse(doc.encode());
}

Map<String, Object?> _line(String id, String head, String state) => cn(
  id,
  'text',
  {'text': ''},
  [],
  {
    'data': {
      'text': cExpr(cJoin([cText(head), cVar(state)])),
    },
  },
);

/// 实例 → 定义（组件文件的两种导出换选择器用）。
Map<String, String> b7LiveDefs() => {'st1': lcBuiltinDefId('stepper'), 'st2': lcBuiltinDefId('stepper'), 'st3': lcBuiltinDefId('stepper'), 'tags': 'c5', 'a5': 'c6'};

/// [pick]：走不走标签条那几步。
CompSteps b7LiveSteps() => [
  // 没接线的步进器：自己记着，点加减数字就变；到最大“加”禁用
  {'op': 'text', 'sel': '.n-st1__num', 'is': '3'},
  {'op': 'click', 'sel': '.n-st1__plus'},
  {'op': 'text', 'sel': '.n-st1__num', 'is': '4'},
  {'op': 'click', 'sel': '.n-st1__plus'},
  {'op': 'text', 'sel': '.n-st1__num', 'is': '5'},
  {'op': 'disabled', 'sel': '.n-st1__plus', 'is': true},
  {'op': 'click', 'sel': '.n-st1__minus'},
  {'op': 'text', 'sel': '.n-st1__num', 'is': '4'},
  // 值绑了状态、没接“改了”：写回那个状态
  {'op': 'text', 'sel': '.n-nText', 'is': '数量 2'},
  {'op': 'click', 'sel': '.n-st2__plus'},
  {'op': 'text', 'sel': '.n-nText', 'is': '数量 3'},
  {'op': 'text', 'sel': '.n-st2__num', 'is': '3'},
  {'op': 'text', 'sel': '.n-st1__num', 'is': '4'},
  // 自己接了“改了”的：照她接的做，不替它记
  {'op': 'click', 'sel': '.n-st3__plus'},
  {'op': 'text', 'sel': '.n-gotText', 'is': '带来的是 8'},
  {'op': 'text', 'sel': '.n-st3__num', 'is': '7'},
  // “重复”里的按钮：点哪个带出哪一项
  ...pickBarSteps(),
  // 重复 3 次、等一会儿
  {'op': 'text', 'sel': '.n-msgText', 'is': '还没等'},
  {'op': 'click', 'sel': '.n-a5__go'},
  {'op': 'text', 'sel': '.n-kText', 'is': 'k=15'},
  {'op': 'wait', 'ms': 200},
  {'op': 'text', 'sel': '.n-msgText', 'is': '等完了'},
];
