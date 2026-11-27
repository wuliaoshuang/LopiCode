// “用户自己写库”的验收样例（积木第 5 版·库 2）：库和用库的文档都是**积木文档的数据模型**搭的（画布上存的那种结构）。
// 每个库都走整条产品路径：库文档 → 写出器 → 库文件 → 读入器 → 放进用它的文档 → 五种语言生成。
// backend_user_lib_test.dart（不真跑）、backend_user_lib_run_test.dart（五种语言真跑）共用。
import 'package:lopicode/backend/backend_lib_build.dart';
import 'package:lopicode/backend/backend_lib_doc.dart';
import 'package:lopicode/backend/backend_model.dart';
import 'package:lopicode/lang/lib_model.dart';
import 'package:lopicode/lang/types.dart';
import 'package:lopicode/lang/types_json.dart';

import 'backend_core_samples.dart';
import 'backend_func_blocks.dart';
import 'backend_lang_blocks.dart';

/// 库文档：在核心文档上多一节 `library`；库里没有“程序开始时”。
J libDoc(String name, String id, {List<String> collections = const [], List<J> types = const [], List<J> functions = const [], List<J> globals = const [], List<String> public = const [], required List<J> blocks, List<J> settings = const [], List<J> uses = const [], String author = '霜霜'}) => {
  'version': 5,
  'kind': 'backend',
  'name': name,
  'port': 8130,
  'language': 'node',
  'rules': 2,
  if (functions.isNotEmpty) 'functions': functions,
  'core': {
    if (types.isNotEmpty) 'types': types,
    if (globals.isNotEmpty) 'globals': globals,
    if (public.isNotEmpty) 'public': public,
  },
  if (collections.isNotEmpty) 'collections': [for (final c in collections) {'name': c}],
  'library': {'id': id, 'version': '1.0.0', 'author': author, if (settings.isNotEmpty) 'settings': settings, 'blocks': blocks},
  if (uses.isNotEmpty) 'uses': uses,
};

/// 公开成的一块积木。
J def(String id, String how, {String? fn, String? type, String? method, J? look, Map<String, J> params = const {}, bool into = false, List<String> mouths = const [], Map<String, String> provides = const {}, String? shape}) => {
  'id': id,
  'how': how,
  'fn': ?fn,
  'type': ?type,
  'method': ?method,
  'look': ?look,
  if (params.isNotEmpty) 'params': params,
  if (into) 'into': true,
  if (mouths.isNotEmpty) 'mouths': mouths,
  if (provides.isNotEmpty) 'provides': provides,
  'shape': ?shape,
};
J fromContext(String name) => {'from': 'context', 'key': name};
J fromSetting(String id) => {'from': 'setting', 'key': id};
J fromPreset(Object? v) => {'from': 'preset', 'value': v};
J fromLiteral() => {'from': 'literal'};
J look(String name, String template, {String shape = 'auto'}) => {'name': name, 'shape': shape, 'template': template};

/// 用库积木：语句 / 值。
J lb(String lib, String block, [J args = const {}, List<J> body = const [], List<J> orElse = const []]) => blk(beLibOp(lib, block), args, body, orElse);
J lx(String lib, String block, [J args = const {}]) => ex(beLibOp(lib, block), args);
J use(String lib, [J settings = const {}]) => {'id': lib, if (settings.isNotEmpty) 'settings': settings};
J hat(String id, String lib, String block, J args, List<J> body) => {'id': id, 'op': beLibOp(lib, block), 'args': args, 'body': body};

/// 定义画布上的两块：做口里的积木、把值交给用的人选的变量。
J mouth(String name) => blk(kBeLibMouthOp, {'name': name});
J put(J value) => blk(kBeLibPutOp, {'value': value});

/// 库文档 → 库文件 → 读回来（整条产品路径的前半段）。出不来就抛，带原因。
({LibLibrary lib, Map<String, String> files}) buildUserLib(J doc, [List<LibLibrary> loaded = const []]) {
  final parsed = parseLangBlocksDocument(doc)..loaded = [...loaded];
  final built = beLibFiles(parsed);
  if (built.files == null) throw StateError('库「${doc['name']}」出不来：${built.problems.join('；')}');
  final lib = libRead(built.files!, builtin: false);
  if (!lib.ok) throw StateError('库「${doc['name']}」读不回来：${lib.problems.join('；')}');
  return (lib: lib, files: built.files!);
}

/// 用库的文档（读盘路径读进来，再把库放进去）。
BeDocument userDocument(J doc, List<LibLibrary> libs) => parseLangBlocksDocument(doc)..loaded = [...libs];

// ———————————————————— (b) 带类与接口的库：校验器 ————————————————————
const String kLibCheck = 'shuang/check';
J checkLibDoc() => libDoc(
  '校验器',
  kLibCheck,
  types: [
    typeDef('t1', 'interface', '规则', methods: [method('m1', '检查', [tpar('值', tText)], [], returns: tText)]),
    typeDef('t2', 'class', '不为空', interfaces: ['规则'], methods: [
      method('m2', '检查', [tpar('值', tText)], [
        iff(op2('==', pm('值'), tx('')), [ret(tx('不能空着'))], noElse: true),
        ret(tx('')),
      ], returns: tText),
    ]),
    typeDef('t3', 'class', '最短', interfaces: ['规则'], fields: [field('几个', tInt)], ctor: method('m3', '创建时', [tpar('n', tInt)], [setF(me(), '几个', pm('n'))]), methods: [
      method('m4', '检查', [tpar('值', tText)], [
        iff(op2('<', ex('len', {'x': pm('值')}), getF(me(), '几个')), [
          ret(cat([tx('至少要 '), getF(me(), '几个'), tx(' 个字')])),
        ], noElse: true),
        ret(tx('')),
      ], returns: tText),
    ]),
    typeDef('t4', 'class', '校验器', fields: [field('规则们', tList(LType.ref('规则')), init: ls([])), field('查过', tInt, init: nm(0))], methods: [
      method('m5', '加', [tpar('r', tRef('规则'))], [blk('listPush', {'xs': getF(me(), '规则们'), 'v': pm('r')})]),
      method('m6', '查', [tpar('值', tText)], [
        setF(me(), '查过', op2('+', getF(me(), '查过'), nm(1))),
        blk('let', {'name': 'out', 'value': ls([]), 'type': tList(LType.text)}),
        blk('listEach', {'xs': getF(me(), '规则们'), 'fn': lam(['r'], [
          konst('m', send(pm('r'), '检查', [pm('值')])),
          iff(op2('!=', vr('m'), tx('')), [push('out', vr('m'))], noElse: true),
        ])}),
        ret(vr('out')),
      ], returns: tList(LType.text)),
      method('m7', '查过几次', [], [ret(getF(me(), '查过'))], returns: tInt),
      method('m8', '新的', [], [ret(newObj('校验器'))], returns: tRef('校验器'), static_: true),
    ]),
  ],
  functions: [
    tfn('f1', '不为空的规则', [], [ret(newObj('不为空'))], returns: tRef('规则')),
    tfn('f2', '最短的规则', [tpar('n', tInt)], [ret(newObj('最短', [pm('n')]))], returns: tRef('规则')),
    tfn('f3', '拼问题', [tpar('问题', tList(LType.text))], [
      iff(op2('==', ex('len', {'x': pm('问题')}), nm(0)), [ret(tx('没问题'))], noElse: true),
      ret(ex('listJoin', {'xs': pm('问题'), 'sep': tx('；')})),
    ], returns: tText),
  ],
  blocks: [
    def('newChecker', 'static', type: 't4', method: 'm8', look: look('新的校验器', '新的校验器')),
    def('add', 'method', type: 't4', method: 'm5', look: look('加规则', '给 {对象} 加上 {r}')),
    def('check', 'method', type: 't4', method: 'm6', look: look('查一查', '用 {对象} 查 {值}')),
    def('checkInto', 'method', type: 't4', method: 'm6', look: look('查一查放进', '用 {对象} 查 {值}'), into: true),
    def('count', 'method', type: 't4', method: 'm7', look: look('查过几次', '{对象} 查过几次')),
    def('notEmpty', 'call', fn: 'f1', look: look('不为空', '不能空着')),
    def('minLen', 'call', fn: 'f2', look: look('最短', '至少 {n} 个字')),
    def('min3', 'call', fn: 'f2', look: look('至少三个字', '至少三个字'), params: {'n': fromPreset(3)}),
    def('joinAll', 'call', fn: 'f3', look: look('拼问题', '把 {问题} 说成一句')),
  ],
);

J checkUserDoc() => {
  ...coreDoc('用校验器', main: [
    konst('c', lx(kLibCheck, 'newChecker')),
    lb(kLibCheck, 'add', {'对象': vr('c'), 'r': lx(kLibCheck, 'notEmpty')}),
    lb(kLibCheck, 'add', {'对象': vr('c'), 'r': lx(kLibCheck, 'minLen', {'n': nm(5)})}),
    log(lx(kLibCheck, 'joinAll', {'问题': lx(kLibCheck, 'check', {'对象': vr('c'), '值': tx('')})})),
    log(lx(kLibCheck, 'joinAll', {'问题': lx(kLibCheck, 'check', {'对象': vr('c'), '值': tx('霜霜')})})),
    blk('let', {'name': 'got', 'value': ls([]), 'type': tList(LType.text)}),
    lb(kLibCheck, 'checkInto', {'对象': vr('c'), '值': tx('小塔塔和霜霜'), '结果': 'got'}),
    log(lx(kLibCheck, 'joinAll', {'问题': vr('got')})),
    konst('d', lx(kLibCheck, 'newChecker')),
    lb(kLibCheck, 'add', {'对象': vr('d'), 'r': lx(kLibCheck, 'min3')}),
    log(lx(kLibCheck, 'joinAll', {'问题': lx(kLibCheck, 'check', {'对象': vr('d'), '值': tx('"引号"\n换行')})})),
    log(lx(kLibCheck, 'joinAll', {'问题': lx(kLibCheck, 'check', {'对象': vr('d'), '值': tx('好')})})),
    say([tx('查过 '), lx(kLibCheck, 'count', {'对象': vr('c')}), tx(' 次和 '), lx(kLibCheck, 'count', {'对象': vr('d')}), tx(' 次')]),
  ]),
  'version': 5,
  'uses': [use(kLibCheck)],
};
const String kCheckWant = '不能空着；至少要 5 个字\n至少要 5 个字\n没问题\n没问题\n至少要 3 个字\n查过 3 次和 2 次\n';

// ———————————————————— (c) 带帽子、隐含的东西、带口展开型的库：流程 ————————————————————
const String kLibFlow = 'shuang/flow';
J flowLibDoc() => libDoc(
  '流程',
  kLibFlow,
  settings: [
    {'id': 'prefix', 'name': '每句话前面加什么', 'type': '文字', 'default': '▶'},
    {'id': 'tries', 'name': '默认试几次', 'type': '整数', 'default': 2, 'min': 1, 'max': 9},
  ],
  globals: [
    {'name': 'noted', 'init': nm(0), 'type': tInt},
  ],
  functions: [
    tfn('f1', '记一笔', [tpar('前缀', tText), tpar('话', tText)], [
      setv('noted', op2('+', vr('noted'), nm(1))),
      say([pm('前缀'), pm('话')]),
    ]),
    tfn('f2', '当开工', [tpar('名字', tText)], [
      konst('round', cat([tx('「'), pm('名字'), tx('」')])),
      say([tx('开工 '), vr('round')]),
      mouth('里面'),
      say([tx('收工 '), vr('round')]),
    ]),
    tfn('f3', '这一轮的名字', [tpar('轮', tText)], [ret(pm('轮'))], returns: tText),
    tfn('f4', '多试几次', [tpar('次数', tInt)], [
      let('tries', nm(0)),
      let('ok', no()),
      whileB(op2('<', vr('tries'), pm('次数')), [
        setv('tries', op2('+', vr('tries'), nm(1))),
        tryB([
          mouth('做'),
          setv('ok', yes()),
          blk('break'),
        ], [
          catchArm('错误', 'e', [say([tx('第 '), vr('tries'), tx(' 次没成：'), getF(vr('e'), '消息')])]),
        ]),
      ]),
      iff(vr('ok'), [mouth('成了以后')], orElse: [thro(cat([tx('试了 '), pm('次数'), tx(' 次都没成')]))]),
    ]),
    tfn('f5', '加到', [tpar('n', tInt)], [
      let('sum', nm(0)),
      blk('forCount', {'name': 'i', 'from': nm(1), 'to': pm('n'), 'step': nm(1)}, [setv('sum', op2('+', vr('sum'), vr('i')))]),
      put(vr('sum')),
    ]),
    tfn('f6', '记了几笔了', [], [ret(vr('noted'))], returns: tInt),
  ],
  blocks: [
    def('note', 'call', fn: 'f1', look: look('记一笔', '记一笔 {话}'), params: {'前缀': fromSetting('prefix')}),
    def('onStart', 'expand', fn: 'f2', look: look('当开工', '当开工，这一轮叫 {名字}'), shape: 'hat', mouths: ['里面'], provides: {'这一轮': 'round'}, params: {'名字': fromLiteral()}),
    def('roundName', 'call', fn: 'f3', look: look('这一轮的名字', '这一轮的名字'), params: {'轮': fromContext('这一轮')}),
    def('retry', 'expand', fn: 'f4', look: look('多试几次', '最多试 {次数} 次'), mouths: ['做', '成了以后']),
    def('retryDefault', 'expand', fn: 'f4', look: look('试几次', '试几次（照设置）'), mouths: ['做', '成了以后'], params: {'次数': fromSetting('tries')}),
    def('sumTo', 'expand', fn: 'f5', look: look('加到', '从 1 加到 {n}'), into: true),
    def('noted', 'call', fn: 'f6', look: look('记了几笔', '记了几笔')),
  ],
);

J flowUserDoc({String prefix = '→ '}) => {
  ...coreDoc('用流程', main: [
    say([tx('一共记了 '), lx(kLibFlow, 'noted'), tx(' 笔')]),
  ]),
  'version': 5,
  'uses': [
    use(kLibFlow, {'prefix': prefix}),
  ],
  'hats': [
    hat('h1', kLibFlow, 'onStart', {'名字': '甲'}, [
      lb(kLibFlow, 'note', {'话': lx(kLibFlow, 'roundName')}),
      let('n', nm(0)),
      lb(kLibFlow, 'retry', {'次数': nm(3)}, [
        setv('n', op2('+', vr('n'), nm(1))),
        iff(op2('<', vr('n'), nm(3)), [thro(cat([tx('才 '), vr('n')]))], noElse: true),
        lb(kLibFlow, 'note', {'话': tx('做成了')}),
      ], [
        lb(kLibFlow, 'note', {'话': cat([tx('一共试了 '), vr('n'), tx(' 次')])}),
      ]),
      let('t', nm(0)),
      lb(kLibFlow, 'sumTo', {'n': nm(4), '结果': 't'}),
      lb(kLibFlow, 'note', {'话': cat([tx('1 加到 4 是 '), vr('t')])}),
      tryB([
        lb(kLibFlow, 'retryDefault', const {}, [thro(tx('就是不行'))]),
      ], [
        catchArm('错误', 'e', [lb(kLibFlow, 'note', {'话': getF(vr('e'), '消息')})]),
      ]),
    ]),
    hat('h2', kLibFlow, 'onStart', {'名字': '乙'}, [
      lb(kLibFlow, 'note', {'话': cat([lx(kLibFlow, 'roundName'), tx('没什么事')])}),
    ]),
  ],
};
const String kFlowWant = '''
开工 「甲」
→ 「甲」
第 1 次没成：才 1
第 2 次没成：才 2
→ 做成了
→ 一共试了 3 次
→ 1 加到 4 是 10
第 1 次没成：就是不行
第 2 次没成：就是不行
→ 试了 2 次都没成
收工 「甲」
开工 「乙」
→ 「乙」没什么事
收工 「乙」
一共记了 6 笔
''';

// ———————————————————— (a) 带接口的小服务用的库：待办（叠在内置“接口服务”库上） ————————————————————
// 待办放在“接口服务”的数据集合 todos 里（PHP 每次请求都从头跑一遍程序，放在模块级变量里的东西留不到下一次请求）。
const String kLibTodo = 'shuang/todo';
final J _tAny = lTypeToJson(LType.any);
J _get(J id) => ex('dbGet', {'collection': 'todos', 'id': id});
J todoLibDoc() => libDoc(
  '待办',
  kLibTodo,
  collections: ['todos'],
  functions: [
    tfn('f1', '加待办', [tpar('标题', tText)], [
      blk('let', {'name': 'saved', 'value': ex('null'), 'type': _tAny}),
      blk('dbInsert', {'collection': 'todos', 'value': dc({'title': pm('标题'), 'done': no()}), 'into': 'saved'}),
      ret(vr('saved')),
    ], returns: _tAny),
    tfn('f2', '全部待办', [], [ret(ex('dbAll', {'collection': 'todos'}))], returns: lTypeToJson(const LType.listOf(LType.any))),
    tfn('f4', '标成做完', [tpar('号', tText)], [
      konst('it', _get(pm('号'))),
      iff(op2('==', vr('it'), ex('null')), [ret(no())], noElse: true),
      blk('dbUpdate', {'collection': 'todos', 'id': pm('号'), 'value': dc({'title': ex('field', {'of': vr('it'), 'key': 'title'}), 'done': yes()})}),
      ret(yes()),
    ], returns: tBool),
    tfn('f5', '删待办', [tpar('号', tText)], [
      iff(op2('==', _get(pm('号')), ex('null')), [ret(no())], noElse: true),
      blk('dbDelete', {'collection': 'todos', 'id': pm('号')}),
      ret(yes()),
    ], returns: tBool),
    tfn('f6', '请求里的标题', [tpar('r', tRef('请求'))], [
      ret(ex('orElse', {'x': q('title'), 'd': tx('')})),
    ], returns: tText),
    tfn('f7', '回清单', [], [json(call('f2'))]),
    tfn('f8', '要有标题', [tpar('r', tRef('请求'))], [
      iff(op2('==', call('f6', {'r': pm('r')}), tx('')), [text(tx('要写标题'), 400)], noElse: true),
    ]),
    tfn('f9', '回一条', [tpar('号', tText)], [
      konst('it', _get(pm('号'))),
      iff(op2('==', vr('it'), ex('null')), [text(tx('没有这一条'), 404)], noElse: true),
      json(vr('it')),
    ]),
  ],
  blocks: [
    def('add', 'call', fn: 'f1', look: look('加一条待办', '加一条待办 {标题}')),
    def('title', 'call', fn: 'f6', look: look('请求里的标题', '这次请求里的标题'), params: {'r': fromContext('请求')}),
    def('done', 'call', fn: 'f4', look: look('标成做完', '把 {号} 标成做完')),
    def('remove', 'call', fn: 'f5', look: look('删待办', '删掉 {号}')),
    def('respondAll', 'expand', fn: 'f7', look: look('回清单', '返回全部待办'), shape: 'cap'),
    def('needTitle', 'expand', fn: 'f8', look: look('要有标题', '没写标题就回 400'), params: {'r': fromContext('请求')}),
    def('respondOne', 'expand', fn: 'f9', look: look('回一条', '返回 {号} 这一条'), shape: 'cap'),
  ],
);

J _id() => ex('orElse', {'x': ex('pathParam', {'name': 'id'}), 'd': tx('')});
J todoUserDoc() => {
  ...coreDoc('用待办', main: [blk('sleep', {'ms': nm(1)})]),
  'version': 5,
  'uses': [use(kLibTodo)],
  'routes': [
    route('r1', 'POST', '/todos', [
      lb(kLibTodo, 'needTitle'),
      json(lx(kLibTodo, 'add', {'标题': lx(kLibTodo, 'title')}), 201),
    ]),
    route('r2', 'GET', '/todos', [lb(kLibTodo, 'respondAll')]),
    route('r3', 'GET', '/todos/:id', [
      lb(kLibTodo, 'respondOne', {'号': _id()}),
    ]),
    route('r4', 'POST', '/todos/:id/done', [
      iff(lx(kLibTodo, 'done', {'号': _id()}), [text(tx('好'))], orElse: [text(tx('没有这一条'), 404)]),
    ]),
    route('r5', 'DELETE', '/todos/:id', [
      iff(lx(kLibTodo, 'remove', {'号': _id()}), [text(tx('删了'))], orElse: [text(tx('没有这一条'), 404)]),
    ]),
  ],
};

/// 待办服务的请求和预期：方式、路径、状态码、内容。
const List<(String, String, int, String)> kTodoCases = [
  ('POST', '/todos', 400, '要写标题'),
  ('POST', '/todos?title=%E4%B9%B0%E8%8F%9C', 201, '{"done":false,"id":1,"title":"买菜"}'),
  ('POST', '/todos?title=write%20%22lib%22', 201, '{"done":false,"id":2,"title":"write \\"lib\\""}'),
  ('GET', '/todos', 200, '[{"done":false,"id":1,"title":"买菜"},{"done":false,"id":2,"title":"write \\"lib\\""}]'),
  ('POST', '/todos/1/done', 200, '好'),
  ('POST', '/todos/9/done', 404, '没有这一条'),
  ('GET', '/todos/1', 200, '{"done":true,"id":1,"title":"买菜"}'),
  ('GET', '/todos/9', 404, '没有这一条'),
  ('DELETE', '/todos/2', 200, '删了'),
  ('DELETE', '/todos/2', 404, '没有这一条'),
  ('GET', '/todos', 200, '[{"done":true,"id":1,"title":"买菜"}]'),
];

// ———————————————————— (d) 用到“要等的事”的库：批量任务 ————————————————————
const String kLibBatch = 'shuang/batch';
J batchLibDoc() => libDoc(
  '批量任务',
  kLibBatch,
  functions: [
    tfn('f1', '慢慢平方', [tpar('n', tInt), tpar('ms', tInt)], [
      blk('sleep', {'ms': pm('ms')}),
      ret(op2('*', pm('n'), pm('n'))),
    ], returns: tInt),
    tfn('f2', '一起平方', [tpar('数们', tList(LType.integer)), tpar('ms', tInt)], [
      ret(ex('awaitAll', {'list': hof('listMap', pm('数们'), arrow(['n'], ex('spawnOf', {'x': call('f1', {'n': pm('n'), 'ms': pm('ms')})})))})),
    ], returns: tList(LType.integer)),
    tfn('f3', '限时平方', [tpar('n', tInt), tpar('ms', tInt), tpar('最多', tInt)], [
      tryB([
        konst('v', ex('awaitMax', {'x': ex('spawnOf', {'x': call('f1', {'n': pm('n'), 'ms': pm('ms')})}), 'ms': pm('最多')})),
        ret(cat([tx('算出 '), vr('v')])),
      ], [
        catchArm('超时', 'e', [ret(tx('超时了'))]),
      ]),
      ret(tx('')),
    ], returns: tText),
    tfn('f4', '限时做', [tpar('毫秒', tInt)], [
      blk('spawn', {'name': 'job'}, [mouth('做')]),
      tryB([
        blk('do', {'value': ex('awaitMax', {'x': vr('job'), 'ms': pm('毫秒')})}),
      ], [
        catchArm('超时', 'e', [
          blk('cancel', {'x': vr('job')}),
          mouth('超时了'),
        ]),
      ]),
    ]),
  ],
  blocks: [
    def('together', 'call', fn: 'f2', look: look('一起平方', '一起算 {数们} 的平方，每个花 {ms} 毫秒')),
    def('timed', 'call', fn: 'f3', look: look('限时平方', '算 {n} 的平方（要 {ms} 毫秒），最多等 {最多} 毫秒')),
    def('within', 'expand', fn: 'f4', look: look('限时做', '最多花 {毫秒} 毫秒做'), mouths: ['做', '超时了']),
  ],
);

J batchUserDoc() => {
  ...coreDoc('用批量任务', main: [blk('sleep', {'ms': nm(1)})]),
  'version': 5,
  'uses': [use(kLibBatch)],
  'routes': [
    route('r1', 'GET', '/go', [
      konst('all', lx(kLibBatch, 'together', {'数们': ls([nm(3), nm(1), nm(2)]), 'ms': nm(40)})),
      konst('fast', lx(kLibBatch, 'timed', {'n': nm(4), 'ms': nm(20), '最多': nm(800)})),
      konst('slow', lx(kLibBatch, 'timed', {'n': nm(4), 'ms': nm(900), '最多': nm(60)})),
      let('a', tx('没动')),
      lb(kLibBatch, 'within', {'毫秒': nm(800)}, [blk('sleep', {'ms': nm(10)}), setv('a', tx('做完'))], [setv('a', tx('超时'))]),
      let('b', tx('没动')),
      lb(kLibBatch, 'within', {'毫秒': nm(50)}, [blk('sleep', {'ms': nm(900)}), setv('b', tx('做完'))], [setv('b', tx('超时'))]),
      text(cat([vr('all'), tx('｜'), vr('fast'), tx('｜'), vr('slow'), tx('｜'), vr('a'), tx('｜'), vr('b')])),
    ]),
  ],
};
const String kBatchWant = '[9,1,4]｜算出 16｜超时了｜做完｜超时';
