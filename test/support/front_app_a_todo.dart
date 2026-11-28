// 小应用甲组·第 1 种形状“待办”：登录（请求＋本地保存记住登录）→ 列表（请求＋状态仓库）→ 详情（去页面带参数）→ 新建、改完成状态
// （提交请求，回列表看到变化）。三组样例走的路不一样：正常走通；登录失败再重试＋空标题被服务拒＋关掉再开还在登录＋退出；
// 超时、服务报错后重试恢复＋列表为空。
import 'package:lopicode/lang/types.dart';

import 'backend_core_samples.dart';
import 'backend_func_blocks.dart';
import 'backend_lang_blocks.dart';
import 'front_app_a_kit.dart';
import 'front_libs_samples.dart';
import 'page_front_samples.dart';
import 'typeops_sample.dart';

const String kTodoToken = 'todo_token';

/// 假服务这一头的待办世界。[listFaults]＝取列表的头几次出什么岔子（'hang' 拖着不回、'500' 报错），用完就正常。
class TodoWorld {
  TodoWorld(List<(String, bool)> start, {List<String> listFaults = const []}) : _faults = [...listFaults] {
    for (final (title, done) in start) {
      items.add({'id': _next++, 'title': title, 'done': done});
    }
  }
  final List<Map<String, Object?>> items = [];
  final List<String> _faults;
  int _next = 1;

  FakeRes handle(FakeReq q) {
    if (q.method == 'POST' && q.path == '/login') {
      return q.json['user'] == '霜霜' && q.json['pass'] == '123' ? const FakeRes(200, {'token': 'tk-1'}) : const FakeRes(401, '密码不对');
    }
    if (q.token != 'tk-1') return const FakeRes(401, '没登录');
    if (q.path == '/todos' && q.method == 'GET') {
      if (_faults.isNotEmpty) {
        return _faults.removeAt(0) == 'hang' ? const FakeRes.hang() : const FakeRes(500, '坏了');
      }
      return FakeRes(200, items);
    }
    if (q.path == '/todos' && q.method == 'POST') {
      final title = '${q.json['title'] ?? ''}'.trim();
      if (title.isEmpty) return const FakeRes(400, '标题不能空');
      final item = {'id': _next++, 'title': title, 'done': false};
      items.add(item);
      return FakeRes(201, item);
    }
    final m = RegExp(r'^/todos/(\d+)$').firstMatch(q.path);
    if (m != null) {
      final found = items.where((t) => '${t['id']}' == m.group(1)).toList();
      if (found.isEmpty) return const FakeRes(404, '没有这一条');
      if (q.method == 'GET') return FakeRes(200, found.single);
      if (q.method == 'PUT') {
        found.single['done'] = q.json['done'] == true;
        return FakeRes(200, found.single);
      }
    }
    return const FakeRes(404, '没有');
  }
}

J _req(String method, J url, {J? data, num timeout = 2000}) => authReq(kTodoToken, method, url, data: data, timeout: timeout);
J _errTo(String node) => catchArm('错误', 'e', [
  show(node, cat([tx('出错：'), getF(vr('e'), '消息')])),
]);

AppPage _login(String base) => AppPage(
  'login',
  [txt('lg_rdy'), inp('lg_user'), inp('lg_pass'), btn('lg_go', '登录'), txt('lg_msg')],
  const [],
  frontDoc(
    uses: [useLib('http'), useLib('storage')],
    hats: [
      mounted([
        iff(lx('storage', 'has', {'key': tx(kTodoToken)}), [show('lg_msg', tx('已登录')), goTo('list')], orElse: [show('lg_msg', tx('请登录'))]),
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
                lb('storage', 'set', {'key': tx(kTodoToken), 'value': at(asDict(resJson('res')), 'token')}),
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

AppPage _list(String base) => AppPage(
  'list',
  [
    txt('ls_rdy'),
    txt('ls_err'),
    btn('ls_retry', '重试'),
    inp('ls_new'),
    btn('ls_add', '加'),
    repeatRow('ls_row', 'items', [
      boundText('ls_title', 'it', ['title']),
      boundText('ls_mark', 'it', ['mark']),
      btn('ls_open', '看'),
    ]),
    txt('ls_sum'),
    btn('ls_out', '退出'),
  ],
  [listVar('items')],
  frontDoc(
    uses: [useLib('http'), useLib('storage'), useLib('store')],
    functions: [
      // 我的积木“加载待办”：取回来放进仓库；取不到、出错都写在页面上。
      tfn('f1', '加载待办', const [], [
        tryB(
          [
            let('res', _req('GET', tx('$base/todos'), timeout: 250)),
            iff(
              resOk('res'),
              [
                lb('store', 'set', {'store': tx('待办'), 'key': tx('items'), 'value': resJson('res')}),
                show('ls_err', tx('')),
              ],
              orElse: [
                show('ls_err', cat([tx('取不到：'), resStatus('res')])),
              ],
            ),
          ],
          [_errTo('ls_err')],
        ),
      ]),
    ],
    hats: [
      mounted([
        iff(
          lx('storage', 'has', {'key': tx(kTodoToken)}),
          [
            lb('store', 'create', {
              'store': tx('待办'),
              'initial': dc({'items': ls(const [])}),
            }),
            callS('f1'),
          ],
          orElse: [show('ls_err', tx('没登录')), goTo('login')],
        ),
        show('ls_rdy', tx('好了')),
      ]),
      // 仓库一变，列表状态和下面那行小结跟着变。
      libHat(
        'h1',
        'store',
        'watch',
        {'store': '待办'},
        [
          let('out', ascribe(ls(const []), const LType.listOf(LType.dictOf(LType.any)))),
          let('done', nm(0)),
          forIn(asDicts(lx('store', 'get', {'store': tx('待办'), 'key': tx('items')})), 't', [
            let('mark', tx('没做')),
            iff(castTo(at(vr('t'), 'done'), LType.boolean), [setv('mark', tx('完成')), setv('done', op2('+', vr('done'), nm(1)))], noElse: true),
            push('out', dc({'id': at(vr('t'), 'id'), 'title': at(vr('t'), 'title'), 'mark': vr('mark')})),
          ]),
          stSet('items', vr('out')),
          show('ls_sum', cat([toText(lenOf(vr('out'))), tx(' 件，'), toText(vr('done')), tx(' 件完成')])),
        ],
      ),
      onClick('h2', 'ls_add', [
        tryB(
          [
            let('res', _req('POST', tx('$base/todos'), data: dc({'title': valOf('ls_new')}))),
            iff(
              resOk('res'),
              [callS('f1')],
              orElse: [
                show('ls_err', cat([tx('加不了：'), resStatus('res')])),
              ],
            ),
          ],
          [_errTo('ls_err')],
        ),
      ]),
      onClick('h3', 'ls_retry', [callS('f1')]),
      onClick('h4', 'ls_open', [
        goWith('detail', {
          'id': ex(pg('eventItemField'), {'key': tx('id')}),
        }),
      ]),
      onClick('h5', 'ls_out', [
        lb('storage', 'remove', {'key': tx(kTodoToken)}),
        goTo('login'),
      ]),
    ],
  ),
);

AppPage _detail(String base) {
  J url() => cat([tx('$base/todos/'), toText(stGet('tid'))]);
  return AppPage(
    'detail',
    [txt('dt_rdy'), txt('dt_title'), txt('dt_state'), btn('dt_toggle', '改完成状态'), btn('dt_back', '回列表'), txt('dt_err')],
    [textVar('tid'), numVar('done')],
    frontDoc(
      uses: [useLib('http'), useLib('storage')],
      hats: [
        mounted([
          stSet('tid', toText(param('id'))),
          tryB(
            [
              let('res', _req('GET', url())),
              iff(
                resOk('res'),
                [
                  let('t', asDict(resJson('res'))),
                  show('dt_title', toText(at(vr('t'), 'title'))),
                  iff(castTo(at(vr('t'), 'done'), LType.boolean), [stSet('done', nm(1)), show('dt_state', tx('完成'))], orElse: [stSet('done', nm(0)), show('dt_state', tx('没做'))]),
                ],
                orElse: [
                  show('dt_err', cat([tx('取不到：'), resStatus('res')])),
                ],
              ),
            ],
            [_errTo('dt_err')],
          ),
          show('dt_rdy', tx('好了')),
        ]),
        onClick('h1', 'dt_toggle', [
          tryB(
            [
              let('res', _req('PUT', url(), data: dc({'done': op2('==', asNum(stGet('done')), nm(0))}))),
              iff(
                resOk('res'),
                [show('dt_err', tx('改好了')), goTo('list')],
                orElse: [
                  show('dt_err', cat([tx('改不了：'), resStatus('res')])),
                ],
              ),
            ],
            [_errTo('dt_err')],
          ),
        ]),
        onClick('h2', 'dt_back', [goTo('list')]),
      ],
    ),
  );
}

/// 整个待办小应用（三页）。[base]＝假服务的地址。
List<AppPage> todoPages(String base) => [_login(base), _list(base), _detail(base)];

Steps _loginOk(String kind, {String pass = '123'}) => [
  typeIn('lg_user', '霜霜'),
  typeIn('lg_pass', pass),
  click('lg_go'),
  ...arriveAt(kind, 'list', wait: untilText('lg_msg', '登录成功'), ready: untilText('ls_rdy', '好了')),
];
Steps _toggleBack(String kind) => [click('dt_toggle'), ...arriveAt(kind, 'list', wait: untilText('dt_err', '改好了'), ready: untilText('ls_rdy', '好了'))];

/// 三组样例。每组自己一个假服务的世界（[world] 交给测试去起服务）。
class TodoCase {
  TodoCase(this.name, this.world, this.steps, this.after);
  final String name;
  final TodoWorld world;
  final Steps Function(String kind) steps;
  final void Function(FakeApi api, TodoWorld world) after;
}

List<TodoCase> todoCases() => [
  TodoCase(
    '正常走通：登录、看列表、新建、进详情改完成、回列表看到变化',
    TodoWorld([('写周报', false), ('取快递', false)]),
    (kind) => [
      netOn(),
      untilText('lg_rdy', '好了'),
      textIs('lg_msg', '请登录'),
      ..._loginOk(kind),
      countIs('ls_title', 2),
      textIs('ls_sum', '2 件，0 件完成'),
      textAt('ls_title', 0, '写周报'),
      typeIn('ls_new', '买菜'),
      click('ls_add'),
      untilText('ls_sum', '3 件，0 件完成'),
      textAt('ls_title', 2, '买菜'),
      clickAt('ls_open', 1),
      ...arriveAt(kind, 'detail', ready: untilText('dt_rdy', '好了')),
      textIs('dt_title', '取快递'),
      textIs('dt_state', '没做'),
      ..._toggleBack(kind),
      untilText('ls_sum', '3 件，1 件完成'),
      textAt('ls_mark', 0, '没做'),
      textAt('ls_mark', 1, '完成'),
    ],
    (api, world) {
      if (world.items.length != 3 || world.items[1]['done'] != true) throw StateError('服务那头：${world.items}');
      if (api.hit('PUT /todos/2') != 1 || api.hit('POST /todos') != 1) throw StateError('请求次数：${api.hits}');
    },
  ),
  TodoCase(
    '登录失败再重试；空标题被服务拒；关掉再开还在登录；把完成的改回没做；退出',
    TodoWorld([('浇花', true), ('洗车', false)]),
    (kind) => [
      netOn(),
      untilText('lg_rdy', '好了'),
      typeIn('lg_user', '霜霜'),
      typeIn('lg_pass', '000'),
      click('lg_go'),
      untilText('lg_msg', '登录失败（401）'),
      storedIs(kTodoToken, null),
      ..._loginOk(kind),
      storedIs(kTodoToken, '"tk-1"'),
      textIs('ls_sum', '2 件，1 件完成'),
      click('ls_add'),
      untilText('ls_err', '加不了：400'),
      countIs('ls_title', 2),
      typeIn('ls_new', '喂猫'),
      click('ls_add'),
      untilText('ls_sum', '3 件，1 件完成'),
      textIs('ls_err', ''),
      // 关掉再开：纯网页先重开首页（它看见登录过，说“已登录”就去列表）；Vue / React 重开就是从首页进，自己到列表。
      ...reopen(),
      if (kind == 'html') ...arrive(kind, 'login', home: true),
      ...arriveAt(kind, 'list', wait: untilText('lg_msg', '已登录'), ready: untilText('ls_rdy', '好了')),
      untilText('ls_sum', '3 件，1 件完成'),
      clickAt('ls_open', 0),
      ...arriveAt(kind, 'detail', ready: untilText('dt_rdy', '好了')),
      textIs('dt_state', '完成'),
      ..._toggleBack(kind),
      untilText('ls_sum', '3 件，0 件完成'),
      click('ls_out'),
      ...arriveAt(kind, 'login', home: true, ready: untilText('lg_msg', '请登录')),
      storedIs(kTodoToken, null),
    ],
    (api, world) {
      if (api.hit('POST /login') != 2) throw StateError('登录了 ${api.hit('POST /login')} 次');
      if (world.items.length != 3 || world.items[0]['done'] != false) throw StateError('服务那头：${world.items}');
    },
  ),
  TodoCase(
    '取列表先超时、再服务报错，重试后恢复；列表是空的；加头一件、改完成',
    TodoWorld(const [], listFaults: ['hang', '500']),
    (kind) => [
      netOn(),
      untilText('lg_rdy', '好了'),
      ..._loginOk(kind),
      textIs('ls_err', '出错：超时'),
      countIs('ls_title', 0),
      click('ls_retry'),
      untilText('ls_err', '取不到：500'),
      countIs('ls_title', 0),
      click('ls_retry'),
      untilText('ls_err', ''),
      countIs('ls_title', 0),
      textIs('ls_sum', '0 件，0 件完成'),
      typeIn('ls_new', '头一件'),
      click('ls_add'),
      untilText('ls_sum', '1 件，0 件完成'),
      clickAt('ls_open', 0),
      ...arriveAt(kind, 'detail', ready: untilText('dt_rdy', '好了')),
      textIs('dt_title', '头一件'),
      ..._toggleBack(kind),
      untilText('ls_sum', '1 件，1 件完成'),
      textAt('ls_mark', 0, '完成'),
    ],
    (api, world) {
      // 超时的那一次：等的人走了，假服务手上还拖着一个没回的。
      if (api.hanging != 1) throw StateError('拖着没回的有 ${api.hanging} 个');
      if (world.items.single['done'] != true) throw StateError('服务那头：${world.items}');
    },
  ),
];
