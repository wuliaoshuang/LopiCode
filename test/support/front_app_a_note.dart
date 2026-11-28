// 小应用甲组·第 3 种形状“笔记”：登录 → 列表 → 详情 → 编辑提交。突出类型：
// 记录“笔记”、类“草稿”（带“创建时”和两个方法）、两种自己的错误（带字段）、模块（类型们／取数／这一页，带模块顶上的变量）、
// 函数（写了参数和结果的类型）、试着做／出错时（按错误种类分开接）、“要等的事”（两件同时开始、最多等多久）。
import 'package:lopicode/lang/types.dart';
import 'package:lopicode/lang/types_json.dart';

import 'backend_core_samples.dart';
import 'backend_func_blocks.dart';
import 'backend_lang_blocks.dart';
import 'backend_wait_sample.dart' show await_, spawnOf;
import 'front_app_a_kit.dart';
import 'front_libs_samples.dart';
import 'page_front_samples.dart';
import 'typeops_sample.dart';

const String kNoteToken = 'note_token';

/// 假服务这一头的笔记本。[listFaults]、[saveFaults]＝头几次出什么岔子（'hang' 拖着不回、'500' 报错），用完就正常。
class NoteWorld {
  NoteWorld(List<(String, String)> start, {List<String> listFaults = const [], List<String> saveFaults = const [], this.gone = const {}}) : _listFaults = [...listFaults], _saveFaults = [...saveFaults] {
    for (final (title, body) in start) {
      notes.add({'id': notes.length + 1, 'title': title, 'body': body});
    }
  }
  final List<Map<String, Object?>> notes = [];
  final List<String> _listFaults;
  final List<String> _saveFaults;

  /// 列表里有、点进去却没了的（别处删掉了）。
  final Set<int> gone;

  FakeRes handle(FakeReq q) {
    if (q.method == 'POST' && q.path == '/login') {
      return q.json['user'] == '霜霜' && q.json['pass'] == '123' ? const FakeRes(200, {'token': 'tk-3'}) : const FakeRes(401, '密码不对');
    }
    if (q.token != 'tk-3') return const FakeRes(401, '没登录');
    if (q.path == '/me') return const FakeRes(200, {'name': '霜霜'});
    if (q.path == '/notes' && q.method == 'GET') {
      if (_listFaults.isNotEmpty) {
        return _listFaults.removeAt(0) == 'hang' ? const FakeRes.hang() : const FakeRes(500, '坏了');
      }
      return FakeRes(200, notes);
    }
    final m = RegExp(r'^/notes/(\d+)$').firstMatch(q.path);
    if (m == null) return const FakeRes(404, '没有');
    final id = int.parse(m.group(1)!);
    final found = notes.where((n) => n['id'] == id && !gone.contains(id)).toList();
    if (found.isEmpty) return const FakeRes(404, '没有这篇');
    if (q.method == 'GET') return FakeRes(200, found.single);
    if (q.method == 'PUT') {
      if (_saveFaults.isNotEmpty) {
        return _saveFaults.removeAt(0) == 'hang' ? const FakeRes.hang() : const FakeRes(500, '坏了');
      }
      final title = q.json['title'];
      if (title is! String || title.isEmpty) return const FakeRes(400, '标题不能空');
      if (notes.any((n) => n['title'] == title && n['id'] != id)) return const FakeRes(409, '重名了');
      found.single
        ..['title'] = title
        ..['body'] = q.json['body'];
      return FakeRes(200, found.single);
    }
    return const FakeRes(404, '没有');
  }
}

J _req(String method, J url, {J? data, num timeout = 2000}) => authReq(kNoteToken, method, url, data: data, timeout: timeout);
J _errTo(String node) => catchArm('错误', 'e', [
  show(node, cat([tx('出错：'), getF(vr('e'), '消息')])),
]);
// 状态码这个字段写的是整数，请求库给的状态码是“数”（可能带小数）：得取整了才放得进去——不取整会被检查拦下。
J _status(String res) => ex('toInt', {'x': lx('http', 'status', {'res': vr(res)})});

// —— 两页共用的类型 ——
J noteRecord() => typeDef('t1', 'record', '笔记', fields: [field('编号', tInt), field('标题', tText), field('正文', tText)]);
J noteFetchError() => typeDef('t2', 'error', '取不到', parent: '错误', fields: [field('状态码', tInt)]);

/// 把服务回来的一条（字典）变成“笔记”记录：每个字段都当成写好的类型用，对不上当场出错。
J noteOfFn(String id) => tfn(
  id,
  '变成笔记',
  [tpar('d', lTypeToJson(const LType.dictOf(LType.any)))],
  [
    ret(
      ex('recNew', {
        'type': '笔记',
        'fields': [pair('编号', castTo(at(pm('d'), 'id'), LType.integer)), pair('标题', castTo(at(pm('d'), 'title'), LType.text)), pair('正文', castTo(at(pm('d'), 'body'), LType.text))],
      }),
    ),
  ],
  returns: tRef('笔记'),
);

AppPage _login(String base) => AppPage(
  'login',
  [txt('lg_rdy'), inp('lg_user'), inp('lg_pass'), btn('lg_go', '登录'), txt('lg_msg')],
  const [],
  frontDoc(
    uses: [useLib('http'), useLib('storage')],
    hats: [
      mounted([
        iff(lx('storage', 'has', {'key': tx(kNoteToken)}), [show('lg_msg', tx('已登录')), goTo('list')], orElse: [show('lg_msg', tx('请登录'))]),
        show('lg_rdy', tx('好了')),
      ]),
      onClick('h1', 'lg_go', [
        tryB(
          [
            let(
              'res',
              lx('http', 'request', {
                'method': 'POST',
                'url': tx('$base/login'),
                'data': dc({'user': valOf('lg_user'), 'pass': valOf('lg_pass')}),
                'timeout': nm(2000),
              }),
            ),
            iff(
              resOk('res'),
              [
                lb('storage', 'set', {'key': tx(kNoteToken), 'value': at(asDict(resJson('res')), 'token')}),
                show('lg_msg', tx('登录成功')),
                goTo('list'),
              ],
              orElse: [
                show('lg_msg', cat([tx('登录失败（'), resStatus('res'), tx('）')])),
              ],
            ),
          ],
          [_errTo('lg_msg')],
        ),
      ]),
    ],
  ),
);

/// 列表页的逻辑。三个模块：类型们（记录、错误）、取数（三个函数）、这一页（帽子和“加载”；叫“页面”会和自带的“页面”库撞名）。
J noteListFront(String base) => noteFront(
  uses: [useLib('http'), useLib('storage')],
  types: [noteRecord(), noteFetchError()],
  modules: [
    {
      'name': '类型们',
      'owns': ['t1', 't2'],
    },
    {
      'name': '取数',
      'uses': ['类型们', '请求', '本地保存'],
      'owns': ['f1', 'f2', 'f3'],
    },
    {
      'name': '这一页',
      'uses': ['取数', '类型们', '页面', '请求', '本地保存'],
      'owns': ['f4'],
    },
  ],
  entry: '这一页',
  public: ['t1', 't2', 'f1', 'f2', 'f3'],
  functions: [
    noteOfFn('f1'),
    tfn(
      'f2',
      '取列表',
      const [],
      [
        let('res', _req('GET', tx('$base/notes'), timeout: 250)),
        iff(notB(resOk('res')), [
          thro(errNew('取不到', tx('列表取不到'), [pair('状态码', _status('res'))])),
        ], noElse: true),
        ret(asDicts(resJson('res'))),
      ],
      returns: lTypeToJson(const LType.listOf(LType.dictOf(LType.any))),
    ),
    tfn('f3', '我是谁', const [], [
      let('res', _req('GET', tx('$base/me'))),
      iff(notB(resOk('res')), [ret(tx('？'))], noElse: true),
      ret(castTo(at(asDict(resJson('res')), 'name'), LType.text)),
    ], returns: tText),
    // 两件事同时开始，再一件件等：列表和“我是谁”。
    tfn('f4', '加载', const [], [
      tryB(
        [
          konst('a', spawnOf(call('f2'))),
          konst('b', spawnOf(call('f3'))),
          konst('who', await_(vr('b'))),
          konst('rows', await_(vr('a'))),
          let('words', nm(0)),
          forIn(vr('rows'), 'd', [
            konst('n', call('f1', {'d': vr('d')})),
            setv('words', op2('+', vr('words'), lenOf(getF(vr('n'), '正文')))),
          ]),
          stSet('items', vr('rows')),
          show('ls_sum', cat([vr('who'), tx('：'), toText(lenOf(vr('rows'))), tx(' 篇，共 '), toText(vr('words')), tx(' 字')])),
          show('ls_err', tx('')),
        ],
        [
          catchArm('取不到', 'e', [
            show('ls_err', cat([getF(vr('e'), '消息'), tx('（'), toText(getF(vr('e'), '状态码')), tx('）')])),
          ]),
          _errTo('ls_err'),
        ],
      ),
    ]),
  ],
  hats: [
    mounted([
      iff(
        notB(lx('storage', 'has', {'key': tx(kNoteToken)})),
        [goTo('login')],
        orElse: [callS('f4'), show('ls_rdy', tx('好了'))],
      ),
    ]),
    onClick('h1', 'ls_retry', [callS('f4')]),
    onClick('h2', 'ls_open', [
      goWith('edit', {'id': toText(ex(pg('eventItemField'), {'key': tx('id')}))}),
    ]),
    onClick('h3', 'ls_out', [
      lb('storage', 'remove', {'key': tx(kNoteToken)}),
      goTo('login'),
    ]),
  ],
);

AppPage _list(String base) => AppPage(
  'list',
  [
    txt('ls_rdy'),
    txt('ls_err'),
    btn('ls_retry', '重试'),
    repeatRow('ls_row', 'items', [boundText('ls_title', 'it', ['title']), btn('ls_open', '看')]),
    txt('ls_sum'),
    btn('ls_out', '退出'),
  ],
  [listVar('items')],
  noteListFront(base),
);

/// 类“草稿”：正在改的那一份。创建时给标题和正文；“毛病”说哪里不合格（没毛病是空的）；“字数”数正文。
J draftClass() => typeDef(
  't3',
  'class',
  '草稿',
  fields: [field('标题', tText), field('正文', tText)],
  ctor: method('m1', '创建时', [tpar('title', tText), tpar('body', tText)], [setF(me(), '标题', pm('title')), setF(me(), '正文', pm('body'))]),
  methods: [
    method('m2', '字数', const [], [ret(lenOf(getF(me(), '正文')))], returns: tInt),
    method(
      'm3',
      '毛病',
      const [],
      [
        iff(op2('==', getF(me(), '标题'), tx('')), [ret(tx('标题不能空'))], noElse: true),
        iff(op2('>', send(me(), '字数'), nm(20)), [
          ret(cat([tx('正文太长（'), toText(send(me(), '字数')), tx(' 个字，最多 20）')])),
        ], noElse: true),
        ret(tx('')),
      ],
      returns: tText,
    ),
  ],
);
J noteSaveError() => typeDef('t4', 'error', '没存上', parent: '错误', fields: [field('状态码', tInt)]);

J noteGetFn(String base) => tfn(
  'f2',
  '取一篇',
  [tpar('id', tText)],
  [
    let('res', _req('GET', cat([tx('$base/notes/'), pm('id')]))),
    iff(notB(resOk('res')), [
      thro(errNew('取不到', tx('这篇取不到'), [pair('状态码', _status('res'))])),
    ], noElse: true),
    ret(call('f1', {'d': asDict(resJson('res'))})),
  ],
  returns: tRef('笔记'),
);

J noteSaveFn(String base, {J? code, J? returnsType}) => tfn(
  'f3',
  '存上',
  [tpar('id', tText), tpar('d', tRef('草稿'))],
  [
    let('res', _req('PUT', cat([tx('$base/notes/'), pm('id')]), data: dc({'title': getF(pm('d'), '标题'), 'body': getF(pm('d'), '正文')}))),
    iff(notB(resOk('res')), [
      thro(errNew('没存上', tx('没存上'), [pair('状态码', code ?? _status('res'))])),
    ], noElse: true),
    setv('saves', op2('+', vr('saves'), nm(1))),
    ret(call('f1', {'d': asDict(resJson('res'))})),
  ],
  returns: returnsType ?? tRef('笔记'),
);

/// 点“保存”做的事。[draft]＝新建草稿那一块、[saveCall]＝叫“存上”那一块（故意写错的样例换掉它们）。
List<J> noteSaveBody({J? draft, J? saveCall, J? shown, String catchKind = '没存上'}) => [
  konst('d', draft ?? newObj('草稿', [valOf('ed_title'), valOf('ed_body')])),
  konst('bad', send(vr('d'), '毛病')),
  iff(
    op2('!=', vr('bad'), tx('')),
    [show('ed_msg', vr('bad'))],
    orElse: [
      tryB(
        [
          konst('t', spawnOf(saveCall ?? call('f3', {'id': param('id'), 'd': vr('d')}))),
          show('ed_msg', tx('正在存…')),
          // 最多等 400 毫秒：服务拖着不回就走“超时”。
          konst('n', ex('awaitMax', {'x': vr('t'), 'ms': nm(400)})),
          show('ed_now', shown ?? cat([getF(vr('n'), '标题'), tx('｜'), getF(vr('n'), '正文')])),
          show('ed_msg', cat([tx('存好了，这一回存了 '), toText(vr('saves')), tx(' 次')])),
          goTo('list'),
        ],
        [
          catchArm('超时', 'e', [show('ed_msg', tx('存得太慢，再点一次'))]),
          catchArm(catchKind, 'e', [
            show('ed_msg', cat([getF(vr('e'), '消息'), tx('（'), toText(getF(vr('e'), '状态码')), tx('）')])),
          ]),
          _errTo('ed_msg'),
        ],
      ),
    ],
  ),
];

/// 详情＋编辑页的逻辑。[saveBody]、[saveFn]、[extra] 给故意写错的样例换零件用。
J noteEditFront(String base, {List<J>? saveBody, J? saveFn, List<J> mountedExtra = const []}) => noteFront(
  uses: [useLib('http'), useLib('storage')],
  types: [noteRecord(), noteFetchError(), draftClass(), noteSaveError()],
  globals: [
    {'name': 'saves', 'init': nm(0), 'type': tInt},
  ],
  modules: [
    {
      'name': '类型们',
      'owns': ['t1', 't2', 't3', 't4'],
    },
    {
      'name': '取数',
      'uses': ['类型们', '请求', '本地保存'],
      'owns': ['g:saves', 'f1', 'f2', 'f3'],
    },
    {
      'name': '这一页',
      'uses': ['取数', '类型们', '页面', '请求', '本地保存'],
      'owns': <String>[],
    },
  ],
  entry: '这一页',
  public: ['t1', 't2', 't3', 't4', 'g:saves', 'f1', 'f2', 'f3'],
  functions: [noteOfFn('f1'), noteGetFn(base), saveFn ?? noteSaveFn(base)],
  hats: [
    mounted([
      tryB(
        [
          konst('n', call('f2', {'id': param('id')})),
          show('ed_now', cat([getF(vr('n'), '标题'), tx('｜'), getF(vr('n'), '正文')])),
          prSet('ed_title', 'value', getF(vr('n'), '标题')),
          prSet('ed_body', 'value', getF(vr('n'), '正文')),
          ...mountedExtra,
          show('ed_msg', tx('')),
        ],
        [
          catchArm('取不到', 'e', [
            show('ed_msg', cat([getF(vr('e'), '消息'), tx('（'), toText(getF(vr('e'), '状态码')), tx('）')])),
          ]),
          _errTo('ed_msg'),
        ],
      ),
      show('ed_rdy', tx('好了')),
    ]),
    onClick('h1', 'ed_save', saveBody ?? noteSaveBody()),
    onClick('h2', 'ed_back', [goTo('list')]),
  ],
);

AppPage noteEditPage(J front) => AppPage('edit', [txt('ed_rdy'), txt('ed_now'), inp('ed_title'), inp('ed_body'), btn('ed_save', '保存'), btn('ed_back', '返回'), txt('ed_msg')], const [], front);

/// 整个笔记小应用（三页）。
List<AppPage> notePages(String base) => [_login(base), _list(base), noteEditPage(noteEditFront(base))];

/// 前端这一边的积木文档，带模块、模块顶上的变量、入口模块、公开的名字。
J noteFront({
  List<J> functions = const [],
  List<J> types = const [],
  List<J> globals = const [],
  List<J> modules = const [],
  String? entry,
  List<String> public = const [],
  List<J> hats = const [],
  List<J> uses = const [],
}) => {
  ...frontDoc(functions: functions, hats: hats, uses: uses),
  'core': {
    if (types.isNotEmpty) 'types': types,
    if (globals.isNotEmpty) 'globals': globals,
    if (modules.isNotEmpty) 'modules': modules,
    'entry': ?entry,
    if (public.isNotEmpty) 'public': public,
  },
};
