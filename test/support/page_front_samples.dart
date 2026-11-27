// 新的页面逻辑（一份前端这一边的积木文档，存在页面逻辑的 front 里）的样例和它们在浏览器里要走的步骤（积木第 5 版·前端 1·下半）。
// 文档是用积木文档的数据模型搭的（和后端积木页存盘的是同一种结构），不是手写语法树。
import 'dart:convert';

import 'package:lopicode/backend/front_doc.dart';
import 'package:lopicode/lang/types.dart';
import 'package:lopicode/lang/types_json.dart';
import 'package:lopicode/lowcode/model.dart';

import 'backend_core_samples.dart';
import 'backend_func_blocks.dart';
import 'backend_lang_blocks.dart';

final J tNum = lTypeToJson(LType.number);
final J tAny = lTypeToJson(LType.any);

String pg(String id) => 'lib:lopi/page#$id';
J hat(String id, String block, List<J> body, {J args = const {}}) => {'id': id, 'op': pg(block), 'args': args, 'body': body};
J onClick(String id, String node, List<J> body) => hat(id, 'onClick', body, args: {'node': node});
J onInput(String id, String node, List<J> body) => hat(id, 'onInput', body, args: {'node': node});
J stGet(String name) => ex(pg('stateGet'), {'name': name});
J stSet(String name, J value) => blk(pg('stateSet'), {'name': name, 'value': value});
J prGet(String node, String prop) => ex(pg('propGet'), {'node': node, 'prop': prop});
J prSet(String node, String prop, J value) => blk(pg('propSet'), {'node': node, 'prop': prop, 'value': value});
J show(String node, J value) => prSet(node, 'text', value);
J toNum(J x) => ex('convert', {'x': x, 'fn': 'toNumber'});
J asNum(J x) => ex(pg('oldNum'), {'value': x});
J toText(J x) => ex('convert', {'x': x, 'fn': 'toText'});

J btn(String id, String text) => {
  'id': id,
  'type': 'button',
  'props': {'text': text},
};
J txt(String id, [String text = '-']) => {
  'id': id,
  'type': 'text',
  'props': {'text': text},
};
J inp(String id) => {
  'id': id,
  'type': 'input',
  'props': {'placeholder': '填'},
};

/// 前端这一边的积木文档（存盘的样子）。
J frontDoc({List<J> functions = const [], List<J> types = const [], List<J> hats = const [], List<J> uses = const []}) => {
  'version': 5,
  'kind': 'backend',
  'side': 'frontend',
  'rules': 2,
  'name': '页面逻辑',
  if (functions.isNotEmpty) 'functions': functions,
  if (types.isNotEmpty) 'core': {'types': types},
  if (uses.isNotEmpty) 'uses': uses,
  'hats': hats,
};

/// 一页的页面文档：控件、状态、新的页面逻辑。空壳处理照产品里存盘时的办法同步好。
LcDocument frontPage(List<J> children, List<J> variables, J front, {String title = 'Front'}) {
  final doc = LcDocument.parse(
    jsonEncode({
      'version': 3,
      'title': title,
      'root': {
        'id': 'root',
        'type': 'page',
        'props': {'padding': 16, 'gap': 8},
        'children': children,
      },
      'logic': {'variables': variables, 'front': front},
    }),
  );
  lcFrontStore(doc.logic, lcFrontOf(doc.logic)!);
  return doc;
}

/// 样例一：函数（带默认值、递归）＋闭包＋类＋错误“试着做”。
LcDocument frontSampleCore() => frontPage(
  [btn('b1', '函数'), txt('t1'), btn('b2', '类'), txt('t2'), inp('in1'), btn('b3', '除'), txt('t3'), btn('b4', '闭包'), txt('t4')],
  [
    {'name': 'n', 'type': 'number', 'initial': 3},
  ],
  frontDoc(
    functions: [
      tfn(
        'f1',
        '阶乘',
        [tpar('n', tNum)],
        [
          iff(op2('<=', pm('n'), nm(1)), [ret(nm(1))], noElse: true),
          ret(op2('*', pm('n'), call('f1', {'n': op2('-', pm('n'), nm(1))}))),
        ],
        returns: tNum,
      ),
      tfn(
        'f2',
        '安全除',
        [tpar('a', tNum), tpar('b', tNum)],
        [
          tryB(
            [
              iff(op2('==', pm('b'), nm(0)), [thro(errNew('错误', tx('不能除以零')))], noElse: true),
              ret(cat([tx('商是 '), toText(op2('/', pm('a'), pm('b')))])),
            ],
            [
              catchArm('错误', 'e', [
                ret(cat([tx('出错：'), getF(vr('e'), '消息')])),
              ]),
            ],
          ),
        ],
        returns: tText,
      ),
    ],
    types: [
      typeDef(
        'c1',
        'class',
        '计数器',
        fields: [field('数', tNum, init: nm(0))],
        ctor: method('c1k', '创建时', [tpar('start', tNum)], [setF(me(), '数', pm('start'))]),
        methods: [
          method('c1m', '加', [tpar('k', tNum)], [setF(me(), '数', op2('+', getF(me(), '数'), pm('k')))]),
        ],
      ),
    ],
    hats: [
      onClick('h1', 'b1', [
        stSet('n', call('f1', {'n': asNum(stGet('n'))})),
        show('t1', cat([tx('n='), toText(stGet('n'))])),
      ]),
      onClick('h2', 'b2', [
        let('c', newObj('计数器', [nm(5)])),
        sendS(vr('c'), '加', [nm(2)]),
        sendS(vr('c'), '加', [nm(3)]),
        show('t2', cat([tx('数到 '), toText(getF(vr('c'), '数'))])),
      ]),
      onClick('h3', 'b3', [
        show('t3', call('f2', {'a': nm(10), 'b': toNum(prGet('in1', 'value'))})),
      ]),
      onClick('h4', 'b4', [
        let('add', arrow(['x'], op2('+', pm('x'), asNum(stGet('n'))))),
        show('t4', toText(callV(vr('add'), [nm(100)]))),
      ]),
    ],
  ),
);

List<Map<String, Object?>> frontStepsCore() => [
  {'op': 'click', 'sel': '.n-b1'},
  {'op': 'text', 'sel': '.n-t1', 'is': 'n=6'},
  {'op': 'click', 'sel': '.n-b1'},
  {'op': 'text', 'sel': '.n-t1', 'is': 'n=720'},
  {'op': 'click', 'sel': '.n-b2'},
  {'op': 'text', 'sel': '.n-t2', 'is': '数到 10'},
  {'op': 'type', 'sel': '.n-in1', 'text': '4'},
  {'op': 'click', 'sel': '.n-b3'},
  {'op': 'text', 'sel': '.n-t3', 'is': '商是 2.5'},
  {'op': 'type', 'sel': '.n-in1', 'text': '0'},
  {'op': 'click', 'sel': '.n-b3'},
  {'op': 'text', 'sel': '.n-t3', 'is': '出错：不能除以零'},
  {'op': 'click', 'sel': '.n-b4'},
  {'op': 'text', 'sel': '.n-t4', 'is': '820'},
];

J node(String id, String type, [J props = const {}, List<J> children = const [], J more = const {}]) => {
  'id': id,
  'type': type,
  if (props.isNotEmpty) 'props': props,
  if (children.isNotEmpty) 'children': children,
  ...more,
};
J fromVar(String name, [List<String> path = const []]) => {'from': 'var', 'name': name, if (path.isNotEmpty) 'path': path};
J fromExpr(J e) => {'from': 'expr', 'expr': e};

/// 样例二：列表和记录状态（加、删、改一项、改字段）＋“重复”里的事件拿这一项、第几项＋去页面带参数（两页）。
LcDocument frontSampleList() {
  final home = frontDoc(
    hats: [
      onClick('h1', 'add', [
        blk(pg('stateListAdd'), {
          'name': 'items',
          'value': dc({'name': prGet('in1', 'value')}),
        }),
      ]),
      onClick('h2', 'del', [
        blk(pg('stateListRemove'), {'name': 'items', 'index': ex(pg('eventIndex'))}),
      ]),
      onClick('h3', 'pick', [
        stSet('picked', ex(pg('eventItemField'), {'key': tx('name')})),
        blk(pg('stateFieldSet'), {'name': 'info', 'key': tx('at'), 'value': ex(pg('eventIndex'))}),
      ]),
      onClick('h4', 'up', [
        blk(pg('stateListSet'), {
          'name': 'items',
          'index': nm(0),
          'value': dc({'name': tx('头一个')}),
        }),
      ]),
      onClick('h5', 'go', [
        blk(pg('goPageWith'), {
          'page': 'detail',
          'params': dc({
            'who': stGet('picked'),
            'n': ex('len', {
              'x': ex(pg('stateList'), {'name': 'items'}),
            }),
          }),
        }),
      ]),
    ],
  );
  final detail = frontDoc(
    hats: [
      hat('h1', 'onMounted', [
        show(
          'got',
          cat([
            tx('带来：'),
            ex(pg('oldText'), {
              'value': ex(pg('pageParam'), {'name': tx('who')}),
            }),
            tx(' / '),
            ex(pg('oldText'), {
              'value': ex(pg('pageParam'), {'name': tx('n')}),
            }),
          ]),
        ),
      ]),
      onClick('h2', 'back', [
        blk(pg('goPage'), {'page': 'home'}),
      ]),
    ],
  );
  final doc = LcDocument.parse(
    jsonEncode({
      'version': 3,
      'id': 'home',
      'title': 'Home',
      'root': node(
        'root',
        'page',
        {'padding': 16, 'gap': 8},
        [
          inp('in1'),
          btn('add', '加'),
          btn('up', '改头一个'),
          node(
            'row',
            'row',
            {'gap': 8},
            [
              node(
                'itName',
                'text',
                {'text': '名'},
                const [],
                {
                  'data': {
                    'text': fromVar('it', ['name']),
                  },
                },
              ),
              btn('pick', '选'),
              btn('del', '删'),
            ],
            {
              'repeat': {'list': fromVar('items'), 'item': 'it', 'index': 'i', 'empty': '空的'},
            },
          ),
          node(
            'count',
            'text',
            {'text': '几'},
            const [],
            {
              'data': {
                'text': fromExpr({
                  'e': 'join',
                  'items': [
                    {
                      'e': 'len',
                      'x': {'e': 'var', 'name': 'items'},
                    },
                    {'e': 'text', 'v': ' 项，选了 '},
                    {'e': 'var', 'name': 'picked'},
                    {'e': 'text', 'v': '@'},
                    {
                      'e': 'var',
                      'name': 'info',
                      'path': ['at'],
                    },
                  ],
                }),
              },
            },
          ),
          btn('go', '去详情'),
        ],
      ),
      'logic': {
        'variables': [
          {
            'name': 'items',
            'type': 'list',
            'initial': [
              {'name': '甲'},
              {'name': '乙'},
              {'name': '丙'},
            ],
          },
          {'name': 'picked', 'type': 'text', 'initial': '无'},
          {
            'name': 'info',
            'type': 'record',
            'initial': {'at': -1},
          },
        ],
        'front': home,
      },
      'pages': [
        {
          'id': 'detail',
          'title': 'Detail',
          'root': node('root', 'page', {'padding': 16, 'gap': 8}, [txt('got'), btn('back', '回去')]),
          'logic': {'variables': <J>[], 'front': detail},
        },
      ],
    }),
  );
  for (final p in doc.pages) {
    lcFrontStore(p.logic, lcFrontOf(p.logic)!);
  }
  return doc;
}

List<Map<String, Object?>> frontStepsList(String kind) => [
  {'op': 'text', 'sel': '.n-count', 'is': '3 项，选了 无@-1'},
  {'op': 'count', 'sel': '.n-itName', 'is': 3},
  // 重复里的事件：第 2 份上的“选”拿到这一项（乙）和第几项（1）
  {'op': 'click', 'sel': '.n-pick', 'at': 1},
  {'op': 'text', 'sel': '.n-count', 'is': '3 项，选了 乙@1'},
  // 删掉第 1 份（甲）
  {'op': 'click', 'sel': '.n-del', 'at': 0},
  {'op': 'count', 'sel': '.n-itName', 'is': 2},
  {'op': 'text', 'sel': '.n-itName', 'is': '乙'},
  // 加一项、改头一个
  {'op': 'type', 'sel': '.n-in1', 'text': '丁'},
  {'op': 'click', 'sel': '.n-add'},
  {'op': 'count', 'sel': '.n-itName', 'is': 3},
  {'op': 'click', 'sel': '.n-up'},
  {'op': 'text', 'sel': '.n-itName', 'is': '头一个'},
  {'op': 'click', 'sel': '.n-pick', 'at': 2},
  {'op': 'text', 'sel': '.n-count', 'is': '3 项，选了 丁@2'},
  // 去详情页，带上参数
  {'op': 'click', 'sel': '.n-go'},
  if (kind == 'html') {'op': 'page', 'html': 'page-detail.html'} else {'op': 'hash', 'is': '#/detail'},
  {'op': 'text', 'sel': '.n-got', 'is': '带来：丁 / 3'},
];
