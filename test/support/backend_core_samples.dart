// 核心 2（积木第 5 版·A3）的样例文档：用**积木文档的数据模型**搭的（backend.lc.json 里存的那种结构，不是手写语法树），
// 覆盖 错误 / 记录 / 枚举与变体 / “看是哪种情况” / 类与接口 / 模块。每个样例带一份写死的预期输出；
// 标了 fixture 的，预期输出直接读 test/fixtures/core2/ 里同名样例的 .expect——证明“积木搭出来的”和“样例写出来的”跑出来一个样。
// test/backend_core_samples_test.dart（不真跑）和 test/backend_core_run_test.dart（五种语言真跑）用它。
import 'package:lopicode/lang/types.dart';
import 'package:lopicode/lang/types_json.dart';

import 'backend_func_blocks.dart';
import 'backend_lang_blocks.dart';

class CoreSample {
  const CoreSample(this.name, this.covers, this.doc, {this.expect, this.fixture});
  final String name;

  /// 覆盖了哪几类（1 错误 2 记录 3 枚举与变体 4 看是哪种情况 5 类与接口 6 模块）。
  final List<int> covers;
  final J doc;
  final String? expect;

  /// test/fixtures/core2/ 里哪个样例的预期输出。
  final String? fixture;

  @override
  String toString() => name;
}

final J tInt = lTypeToJson(LType.integer);
final J tText = lTypeToJson(LType.text);
final J tBool = lTypeToJson(LType.boolean);
J tRef(String name, {bool nullable = false}) => lTypeToJson(LType.ref(name, nullable: nullable));
J tList(LType of) => lTypeToJson(LType.listOf(of));

J field(String name, J type, {J? init, bool private = false, bool static_ = false}) => {'name': name, 'type': type, 'init': ?init, if (private) 'private': true, if (static_) 'static': true};
J tpar(String name, J type, {Object? def}) => {'name': name, 'type': type, 'default': ?def};
J method(String id, String name, List<J> params, List<J> body, {J? returns, bool static_ = false}) => {
  'id': id,
  'name': name,
  'params': params,
  'returns': ?returns,
  if (static_) 'static': true,
  'body': body,
};
J typeDef(
  String id,
  String kind,
  String name, {
  List<J> fields = const [],
  List<J> cases = const [],
  String? parent,
  List<String> interfaces = const [],
  bool open = false,
  J? ctor,
  List<J> methods = const [],
}) => {
  'id': id,
  'kind': kind,
  'name': name,
  if (fields.isNotEmpty) 'fields': fields,
  if (cases.isNotEmpty) 'cases': cases,
  'parent': ?parent,
  if (interfaces.isNotEmpty) 'interfaces': interfaces,
  if (open) 'open': true,
  'ctor': ?ctor,
  if (methods.isNotEmpty) 'methods': methods,
};
J kase(String name, [List<J> fields = const []]) => {'name': name, if (fields.isNotEmpty) 'fields': fields};
J tfn(String id, String name, List<J> params, List<J> body, {J? returns}) => {...fnDef(id, name, params, body), 'returns': ?returns};

J log(J value) => blk('log', {'value': value});
J say(List<J> items) => log(cat(items));
J pair(String key, J value) => ex('pair', {'key': key, 'value': value});
J errNew(String kind, J message, [List<J> fields = const []]) => ex('errNew', {'kind': kind, 'message': message, 'fields': fields});
J getF(J of, String name) => ex('getField', {'of': of, 'name': name});
J thro(J value) => blk('throw', {'value': value});
J tryB(List<J> body, List<J> arms, {List<J>? last}) => blk('try', const {}, body, last ?? const [], arms, last == null);
J catchArm(String kind, String name, List<J> body) => arm({'kind': kind, 'name': name}, body);
J match(J value, List<J> arms, {List<J>? orElse}) => blk('match', {'value': value}, const [], orElse ?? const [], arms, orElse == null);
J caseArm(String name, String binds, List<J> body) => arm({'case': name, 'binds': binds}, body);
J newObj(String type, [List<J> args = const []]) => ex('classNew', {'type': type, 'args': args});
J send(J of, String name, [List<J> args = const []]) => ex('callMethod', {'of': of, 'name': name, 'args': args});
J sendS(J of, String name, [List<J> args = const []]) => blk('callMethodStmt', {'of': of, 'name': name, 'args': args});
J setF(J of, String name, J value) => blk('setField', {'of': of, 'name': name, 'value': value});
J me() => ex('this');
J whileB(J cond, List<J> body) => blk('while', {'cond': cond}, body);

J coreDoc(
  String name, {
  List<J> types = const [],
  List<J> functions = const [],
  List<J> globals = const [],
  List<J> modules = const [],
  String? entry,
  List<String> public = const [],
  required List<J> main,
}) => {
  'version': 4,
  'kind': 'backend',
  'name': name,
  'port': 8130,
  'language': 'node',
  'rules': 2,
  if (functions.isNotEmpty) 'functions': functions,
  'core': {
    if (types.isNotEmpty) 'types': types,
    if (globals.isNotEmpty) 'globals': globals,
    if (modules.isNotEmpty) 'modules': modules,
    'entry': ?entry,
    if (public.isNotEmpty) 'public': public,
    'main': {'body': main},
  },
};

J _iffThrow(int n, J what) => iff(op2('==', pm('n'), nm(n)), [thro(what)], noElse: true);

final List<CoreSample> coreSamples = [
  // 1 错误：自己定义的错误种类（带字段、一层层继承）、按种类分别接、兜底的一节、抛一句话、小库自己报的错也分种类。
  CoreSample(
    's1-错误按种类接',
    [1],
    coreDoc(
      '错误',
      types: [
        typeDef('t1', 'error', 'HTTP错误', parent: '错误', open: true, fields: [field('状态码', tInt)]),
        typeDef('t2', 'error', '没权限', parent: 'HTTP错误'),
      ],
      functions: [
        tfn(
          'f1',
          '办事',
          [tpar('n', tInt)],
          [
            _iffThrow(1, errNew('HTTP错误', tx('服务器坏了'), [pair('状态码', nm(500))])),
            _iffThrow(2, errNew('没权限', tx('不让进'), [pair('状态码', nm(403))])),
            _iffThrow(3, errNew('找不到', tx('没有这个东西'))),
            _iffThrow(4, tx('一句话')),
            iff(op2('==', pm('n'), nm(5)), [ret(op2('%', pm('n'), nm(0)))], noElse: true),
            iff(op2('==', pm('n'), nm(6)), [
              ret(
                ex('index', {
                  'of': ls([nm(1), nm(2)]),
                  'key': nm(9),
                }),
              ),
            ], noElse: true),
            _iffThrow(7, errNew('超时', tx('等太久了'))),
            ret(pm('n')),
          ],
          returns: tInt,
        ),
      ],
      main: [
        let('i', nm(0)),
        whileB(op2('<', vr('i'), nm(9)), [
          tryB(
            [
              say([
                tx('办成 '),
                call('f1', {'n': vr('i')}),
              ]),
            ],
            [
              catchArm('没权限', 'e', [
                say([tx('没权限：'), getF(vr('e'), '消息'), tx(' '), getF(vr('e'), '状态码'), tx(' '), getF(vr('e'), '种类')]),
              ]),
              catchArm('HTTP错误', 'e', [
                say([tx('HTTP：'), getF(vr('e'), '消息'), tx(' '), getF(vr('e'), '状态码'), tx(' '), getF(vr('e'), '种类')]),
              ]),
              catchArm('找不到', 'e', [
                say([tx('找不到：'), getF(vr('e'), '消息'), tx(' '), getF(vr('e'), '种类')]),
              ]),
              catchArm('数值不对', '', [log(tx('数不对'))]),
              catchArm('@any', 'e', [
                say([tx('别的：'), getF(vr('e'), '消息'), tx(' '), getF(vr('e'), '种类')]),
              ]),
            ],
          ),
          setv('i', op2('+', vr('i'), nm(1))),
        ]),
      ],
    ),
    fixture: 'e02-by-kind',
  ),
  // 1 错误：“最后总要”、接住再抛、里外两层。
  CoreSample(
    's2-最后总要和再抛',
    [1],
    coreDoc(
      '错误二',
      main: [
        tryB(
          [
            tryB([thro(tx('里面坏了'))], const [], last: [log(tx('里层收尾'))]),
          ],
          [
            catchArm('@any', 'e', [
              say([tx('外层接到：'), getF(vr('e'), '消息')]),
            ]),
          ],
          last: [log(tx('外层收尾'))],
        ),
        tryB(
          [
            tryB(
              [thro(errNew('超时', tx('太慢')))],
              [
                catchArm('超时', 'e', [log(tx('先记一笔')), thro(vr('e'))]),
              ],
            ),
          ],
          [
            catchArm('错误', 'e2', [
              say([tx('又接到：'), getF(vr('e2'), '种类'), tx(' '), getF(vr('e2'), '消息')]),
            ]),
          ],
        ),
      ],
    ),
    expect: '里层收尾\n外层接到：里面坏了\n外层收尾\n先记一笔\n又接到：超时 太慢\n',
  ),
  // 2 记录：定义、新建、读字段、复制并改（原来那份不变）。
  CoreSample(
    's3-记录',
    [2],
    coreDoc(
      '记录',
      types: [
        typeDef('t1', 'record', '点', fields: [field('x', tInt), field('y', tInt)]),
        typeDef('t2', 'record', '线', fields: [field('头', tRef('点')), field('尾', tRef('点')), field('名', tText)]),
      ],
      main: [
        let(
          'p',
          ex('recNew', {
            'type': '点',
            'fields': [pair('x', nm(1)), pair('y', nm(2))],
          }),
        ),
        let(
          'q',
          ex('recCopy', {
            'of': vr('p'),
            'fields': [pair('x', nm(5))],
          }),
        ),
        say([getF(vr('p'), 'x'), tx(','), getF(vr('p'), 'y'), tx(' '), getF(vr('q'), 'x'), tx(','), getF(vr('q'), 'y')]),
        let(
          'l',
          ex('recNew', {
            'type': '线',
            'fields': [pair('头', vr('p')), pair('尾', vr('q')), pair('名', tx('甲'))],
          }),
        ),
        let(
          'm',
          ex('recCopy', {
            'of': vr('l'),
            'fields': [
              pair('名', tx('乙')),
              pair(
                '尾',
                ex('recCopy', {
                  'of': vr('q'),
                  'fields': [pair('y', nm(9))],
                }),
              ),
            ],
          }),
        ),
        say([getF(vr('l'), '名'), tx(' '), getF(getF(vr('l'), '尾'), 'y'), tx(' '), getF(vr('m'), '名'), tx(' '), getF(getF(vr('m'), '尾'), 'y'), tx(' '), getF(getF(vr('m'), '头'), 'x')]),
      ],
    ),
    expect: '1,2 5,2\n甲 2 乙 9 1\n',
  ),
  // 3、4 枚举与变体 + “看是哪种情况”：每种情况一段、带出的东西绑成变量、“其他情况”。
  CoreSample(
    's4-枚举变体分情况',
    [3, 4],
    coreDoc(
      '枚举与变体',
      types: [
        typeDef('t1', 'enum', '颜色', cases: [kase('红'), kase('绿'), kase('蓝')]),
        typeDef(
          't2',
          'variant',
          '形状',
          cases: [
            kase('圆', [field('半径', tInt)]),
            kase('方', [field('宽', tInt), field('高', tInt)]),
            kase('点'),
          ],
        ),
      ],
      functions: [
        tfn(
          'f1',
          '面积',
          [tpar('s', tRef('形状'))],
          [
            match(pm('s'), [
              caseArm('圆', 'r', [ret(op2('*', op2('*', vr('r'), vr('r')), nm(3)))]),
              caseArm('方', 'w, h', [ret(op2('*', vr('w'), vr('h')))]),
              caseArm('点', '', [ret(nm(0))]),
            ]),
          ],
          returns: tInt,
        ),
        tfn(
          'f2',
          '冷暖',
          [tpar('c', tRef('颜色'))],
          [
            match(
              pm('c'),
              [
                caseArm('红', '', [ret(tx('暖'))]),
              ],
              orElse: [ret(tx('冷'))],
            ),
          ],
          returns: tText,
        ),
      ],
      main: [
        say([
          call('f1', {
            's': ex('varNew', {
              'type': '形状',
              'case': '圆',
              'args': [nm(2)],
            }),
          }),
          tx(' '),
          call('f1', {
            's': ex('varNew', {
              'type': '形状',
              'case': '方',
              'args': [nm(3), nm(4)],
            }),
          }),
          tx(' '),
          call('f1', {
            's': ex('varNew', {'type': '形状', 'case': '点', 'args': <J>[]}),
          }),
        ]),
        say([
          call('f2', {
            'c': ex('enumVal', {'type': '颜色', 'case': '红'}),
          }),
          call('f2', {
            'c': ex('enumVal', {'type': '颜色', 'case': '蓝'}),
          }),
        ]),
        let('c', ex('enumVal', {'type': '颜色', 'case': '绿'})),
        match(vr('c'), [
          caseArm('红', '', [log(tx('是红'))]),
          caseArm('绿', '', [log(tx('是绿'))]),
          caseArm('蓝', '', [log(tx('是蓝'))]),
        ]),
      ],
    ),
    expect: '12 12 0\n暖冷\n是绿\n',
  ),
  // 4 “看是哪种情况”看可空的值、“任意”的值。
  CoreSample(
    's5-可空和任意分情况',
    [4],
    coreDoc(
      '可空和任意',
      functions: [
        tfn(
          'f1',
          '读数',
          [tpar('s', tText)],
          [
            match(ex('parseInt', {'s': pm('s')}), [
              caseArm('@null', '', [ret(tx('不是数'))]),
              caseArm('@some', 'n', [
                ret(cat([tx('是 '), op2('+', vr('n'), nm(1))])),
              ]),
            ]),
          ],
          returns: tText,
        ),
      ],
      main: [
        log(call('f1', {'s': tx('41')})),
        log(call('f1', {'s': tx('abc')})),
        let('one', ex('null')),
        blk(
          'forEach',
          {
            'list': ls([
              nm(7),
              tx('字'),
              yes(),
              ls([nm(1)]),
            ]),
            'item': 'one',
          },
          [
            match(
              vr('one'),
              [
                caseArm('@is:number', 'n', [
                  say([tx('数字 '), op2('*', vr('n'), nm(2))]),
                ]),
                caseArm('@is:text', 't', [
                  say([tx('文字 '), vr('t'), vr('t')]),
                ]),
                caseArm('@is:bool', 'b', [
                  say([tx('是否 '), vr('b')]),
                ]),
              ],
              orElse: [log(tx('别的'))],
            ),
          ],
        ),
      ],
    ),
    expect: '是 42\n不是数\n数字 14\n文字 字字\n是否 true\n别的\n',
  ),
  // 5 类：字段带初值、“创建时”、方法、继承、重写、调父类的创建时和方法、“内部”字段、类本身的成员、是不是某类。
  CoreSample(
    's6-类和继承',
    [5],
    coreDoc(
      '类',
      types: [
        typeDef(
          't1',
          'class',
          '动物',
          open: true,
          fields: [
            field('名', tText),
            field('腿', tInt, init: nm(4)),
            field('秘密', tText, init: tx('嘘'), private: true),
            field('总数', tInt, init: nm(0), static_: true),
          ],
          ctor: method(
            'm1',
            '创建时',
            [tpar('name', tText)],
            [
              setF(me(), '名', pm('name')),
              setF(ex('classRef', {'type': '动物'}), '总数', op2('+', getF(ex('classRef', {'type': '动物'}), '总数'), nm(1))),
            ],
          ),
          methods: [
            method('m2', '叫', [], [ret(tx('……'))], returns: tText),
            method(
              'm3',
              '介绍',
              [tpar('prefix', tText, def: '我是')],
              [
                ret(cat([pm('prefix'), getF(me(), '名'), tx('，'), getF(me(), '腿'), tx(' 条腿，'), getF(me(), '秘密')])),
              ],
              returns: tText,
            ),
            method(
              'm4',
              '有几只',
              [],
              [
                ret(getF(ex('classRef', {'type': '动物'}), '总数')),
              ],
              returns: tInt,
              static_: true,
            ),
          ],
        ),
        typeDef(
          't2',
          'class',
          '狗',
          parent: '动物',
          ctor: method(
            'm5',
            '创建时',
            [tpar('name', tText)],
            [
              blk('superInit', {
                'args': [
                  cat([tx('狗·'), pm('name')]),
                ],
              }),
            ],
          ),
          methods: [
            method('m6', '叫', [], [ret(tx('汪'))], returns: tText),
            method(
              'm7',
              '介绍',
              [tpar('prefix', tText, def: '我是')],
              [
                ret(
                  cat([
                    ex('superCall', {
                      'name': '介绍',
                      'args': [pm('prefix')],
                    }),
                    tx('，会'),
                    send(me(), '叫'),
                  ]),
                ),
              ],
              returns: tText,
            ),
          ],
        ),
      ],
      functions: [
        tfn(
          'f1',
          '看看',
          [tpar('a', tRef('动物'))],
          [
            say([
              send(pm('a'), '介绍'),
              tx('｜'),
              send(pm('a'), '叫'),
              tx('｜'),
              ex('isA', {'x': pm('a'), 'type': '狗'}),
            ]),
          ],
        ),
      ],
      main: [
        let('a', newObj('动物', [tx('某只')])),
        let('d', newObj('狗', [tx('旺财')])),
        callS('f1', {'a': vr('a')}),
        callS('f1', {'a': vr('d')}),
        log(send(vr('d'), '介绍', [tx('这是')])),
        setF(vr('a'), '腿', nm(3)),
        log(getF(vr('a'), '腿')),
        log(send(ex('classRef', {'type': '动物'}), '有几只')),
      ],
    ),
    expect: '我是某只，4 条腿，嘘｜……｜false\n我是狗·旺财，4 条腿，嘘，会汪｜汪｜true\n这是狗·旺财，4 条腿，嘘，会汪\n3\n2\n',
  ),
  // 5 接口：一个类实现两个接口、子类自动也算、接口当参数的类型、自己定义的错误从方法里抛出来。
  CoreSample(
    's7-接口',
    [5, 1],
    coreDoc(
      '接口',
      types: [
        typeDef('t1', 'interface', '有名字', methods: [method('m1', '名字', [], [], returns: tText)]),
        typeDef(
          't2',
          'interface',
          '能算价',
          methods: [
            method('m2', '价', [tpar('count', tInt)], [], returns: tInt),
          ],
        ),
        typeDef('t3', 'error', '卖完了', parent: '错误', fields: [field('货', tText)]),
        typeDef(
          't4',
          'class',
          '商品',
          open: true,
          interfaces: ['有名字', '能算价'],
          fields: [field('叫', tText), field('单价', tInt)],
          ctor: method('m3', '创建时', [tpar('name', tText), tpar('price', tInt)], [setF(me(), '叫', pm('name')), setF(me(), '单价', pm('price'))]),
          methods: [
            method('m4', '名字', [], [ret(getF(me(), '叫'))], returns: tText),
            method(
              'm5',
              '价',
              [tpar('count', tInt)],
              [
                iff(op2('>', pm('count'), nm(9)), [
                  thro(errNew('卖完了', tx('不够'), [pair('货', getF(me(), '叫'))])),
                ], noElse: true),
                ret(op2('*', getF(me(), '单价'), pm('count'))),
              ],
              returns: tInt,
            ),
          ],
        ),
        typeDef(
          't5',
          'class',
          '进口商品',
          parent: '商品',
          methods: [
            method(
              'm6',
              '价',
              [tpar('count', tInt)],
              [
                ret(
                  op2(
                    '+',
                    ex('superCall', {
                      'name': '价',
                      'args': [pm('count')],
                    }),
                    nm(5),
                  ),
                ),
              ],
              returns: tInt,
            ),
          ],
        ),
        typeDef(
          't6',
          'class',
          '服务',
          interfaces: ['能算价'],
          methods: [
            method('m7', '价', [tpar('count', tInt)], [ret(op2('+', nm(30), op2('*', pm('count'), nm(20))))], returns: tInt),
          ],
        ),
      ],
      functions: [
        tfn(
          'f1',
          '叫什么',
          [tpar('x', tRef('有名字'))],
          [
            ret(cat([tx('〈'), send(pm('x'), '名字'), tx('〉')])),
          ],
          returns: tText,
        ),
        tfn(
          'f2',
          '两份',
          [tpar('x', tRef('能算价'))],
          [
            ret(send(pm('x'), '价', [nm(2)])),
          ],
          returns: tInt,
        ),
      ],
      main: [
        let('rice', newObj('商品', [tx('米'), nm(30)])),
        let('wine', newObj('进口商品', [tx('酒'), nm(100)])),
        let('fix', newObj('服务')),
        say([
          call('f1', {'x': vr('rice')}),
          call('f1', {'x': vr('wine')}),
        ]),
        say([
          call('f2', {'x': vr('rice')}),
          tx(' '),
          call('f2', {'x': vr('wine')}),
          tx(' '),
          call('f2', {'x': vr('fix')}),
        ]),
        say([
          ex('isA', {'x': vr('wine'), 'type': '有名字'}),
          tx(' '),
          ex('isA', {'x': vr('fix'), 'type': '商品'}),
        ]),
        tryB(
          [
            log(send(vr('wine'), '价', [nm(10)])),
          ],
          [
            catchArm('卖完了', 'e', [
              say([getF(vr('e'), '货'), tx(' '), getF(vr('e'), '消息'), tx(' '), getF(vr('e'), '种类')]),
            ]),
          ],
        ),
      ],
    ),
    expect: '〈米〉〈酒〉\n60 205 70\ntrue false\n酒 不够 卖完了\n',
  ),
  // 6 模块：三个模块、“用到了谁”、公开的函数 / 记录 / 变量 / 错误种类、模块顶上的变量带初值、入口模块。
  CoreSample(
    's8-模块',
    [6, 1, 2],
    coreDoc(
      '模块',
      modules: [
        {
          'name': '错误们',
          'owns': ['t1'],
        },
        {
          'name': '仓库',
          'uses': ['错误们'],
          'owns': ['g:stock', 'g:times', 't2', 'f1'],
        },
        {
          'name': '店',
          'uses': ['仓库', '错误们'],
          'owns': ['f2'],
        },
      ],
      entry: '店',
      public: ['t1', 'g:times', 't2', 'f1'],
      types: [
        typeDef('t1', 'error', '没货', parent: '错误', fields: [field('货名', tText)]),
        typeDef('t2', 'record', '出库单', fields: [field('货名', tText), field('数量', tInt)]),
      ],
      globals: [
        {
          'name': 'stock',
          'init': dc({'苹果': nm(3), '梨': nm(0)}),
          'type': lTypeToJson(const LType.dictOf(LType.integer)),
        },
        {'name': 'times', 'init': nm(0), 'type': tInt},
      ],
      functions: [
        tfn(
          'f1',
          '出库',
          [tpar('name', tText), tpar('n', tInt)],
          [
            let(
              'have',
              ex('orElse', {
                'x': ex('index', {'of': vr('stock'), 'key': pm('name')}),
                'd': nm(0),
              }),
            ),
            iff(op2('<', vr('have'), pm('n')), [
              thro(errNew('没货', cat([pm('name'), tx(' 没货了')]), [pair('货名', pm('name'))])),
            ], noElse: true),
            blk('setItem', {'of': vr('stock'), 'key': pm('name'), 'value': op2('-', vr('have'), pm('n'))}),
            setv('times', op2('+', vr('times'), nm(1))),
            ret(
              ex('recNew', {
                'type': '出库单',
                'fields': [pair('货名', pm('name')), pair('数量', pm('n'))],
              }),
            ),
          ],
          returns: tRef('出库单'),
        ),
        tfn(
          'f2',
          '买',
          [tpar('name', tText), tpar('n', tInt)],
          [
            tryB(
              [
                let('bill', call('f1', {'name': pm('name'), 'n': pm('n')})),
                say([tx('买到 '), getF(vr('bill'), '货名'), tx('×'), getF(vr('bill'), '数量')]),
              ],
              [
                catchArm('没货', 'e', [
                  say([tx('没货：'), getF(vr('e'), '货名'), tx('｜'), getF(vr('e'), '消息')]),
                ]),
              ],
            ),
          ],
        ),
      ],
      main: [
        callS('f2', {'name': tx('苹果'), 'n': nm(2)}),
        callS('f2', {'name': tx('苹果'), 'n': nm(2)}),
        callS('f2', {'name': tx('梨'), 'n': nm(1)}),
        setv('times', op2('+', vr('times'), nm(10))),
        say([tx('出库次数 '), vr('times')]),
      ],
    ),
    expect: '买到 苹果×2\n没货：苹果｜苹果 没货了\n没货：梨｜梨 没货了\n出库次数 11\n',
  ),
];
